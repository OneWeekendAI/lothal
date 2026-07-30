class_name LabScreen
extends Control
## Lothal Labs — the garage, and the screen the app opens on (labs-and-sim.md §2).
##
## This slice holds frame selection: the rail on the left, the generated airframe in the
## middle, the details and derived stats on the right. Nothing here flies. There is no
## integrator, no flight controller and no audio synthesiser in this file, and that absence
## is the entire point of the Lab/Sim split — choosing a frame is arithmetic and should not
## cost a laptop's fans.
##
## The 3D content lives in a SubViewport with its OWN World3D. That is not decoration: Sim
## is a separate scene with its own cameras and lights, and giving Lab a private world is
## what stops the two from rendering into each other. It also means a hidden Lab genuinely
## stops drawing (UPDATE_WHEN_VISIBLE) rather than quietly rendering behind the field.
##
## One handler drives everything (_on_frame_selected): geometry, details, stats. There is no
## apply button and there is no second path — a stat cannot disagree with the airframe on
## screen because both are rebuilt from the same dictionary in the same call.

## The other three parts are held fixed at the reference build while a frame is chosen.
## Comparing two frames means changing one thing, so the motor, prop and pack stay put; the
## rest of the catalog gets its own bench in a later slice.
const VIEWPORT_SIZE := Vector2i(1280, 720)

## The camera sits at a FIXED distance, deliberately — and this is the one piece of framing
## that must not be clever. Zooming to fit each frame would normalise away the thing worth
## seeing: a 65 mm whoop must look tiny beside a 10" long-range, and it only does if the
## camera holds still. So the distance is computed ONCE, from the largest arm in the catalog,
## and then never moves. Derived rather than authored, so adding a 13" frame reframes the room
## instead of hanging it off the edge of the viewport (which is exactly what a hand-picked
## 0.62 m did to the 10" entry).
const CAMERA_FOV := 38.0
## Fraction of the viewport width the largest airframe should span. Leaves the biggest frame
## visibly inside the room rather than touching both edges.
const LARGEST_FRAME_SCREEN_FRACTION := 0.78

## The camera orbits the airframe on two angles: AZIMUTH around the vertical, and ELEVATION
## above and below the horizon. Together those reach every point on the sphere, which is what
## matters as soon as Lab holds more than a frame — a battery tray, a payload mount and the
## bottom plate are all under the build, and a yaw-only turntable can never look at any of
## them. There is deliberately no third rotation: roll would not reveal a single surface the
## other two cannot already reach, it would only change which way is up on screen, and losing
## which way is up is expensive on a screen whose whole job is judging an airframe.
##
## The camera moves and the airframe stays level, rather than tumbling the model. Same
## pictures, but the build keeps its own sense of up and the lighting stays consistent.
const ELEVATION_LIMIT_DEG := 85.0
const START_AZIMUTH_DEG := 0.0
const START_ELEVATION_DEG := 22.0

## The idle orbit: a continuous turn about the vertical, plus a slow rise and fall through the
## horizon so the view drifts between looking down on the top plate and up at the underside.
## The vertical drift is what makes the object read as solid; a pure yaw spin can look like a
## flat picture on a rotating card.
const AUTO_ORBIT_DEG_S := 11.0
const AUTO_ELEVATION_CENTRE_DEG := 14.0
const AUTO_ELEVATION_SWING_DEG := 32.0
const AUTO_ELEVATION_PERIOD_S := 26.0

## Drag speed when the builder takes the orbit over by hand — horizontal for azimuth,
## vertical for elevation.
const DRAG_DEG_PER_PIXEL := 0.4

var catalog: PartsCatalog
var picker: FramePicker
var details: FrameDetails
var frame_model: FrameModel

var _viewport: SubViewport
## The camera boom. Rotating this orbits the camera; the airframe itself never moves.
var _orbit: Node3D
var _camera: Camera3D
var _dragging := false

## The idle orbit runs until somebody takes hold of the view, and then it stops for good. It
## does NOT resume: an orbit that starts creeping again after you let go carries the angle you
## just chose away from you, which is precisely wrong when the reason you chose it was to look
## at one particular thing — a mount, a tray, the underside of a plate.
var auto_orbit := true

var _azimuth_rad := deg_to_rad(START_AZIMUTH_DEG)
var _elevation_rad := deg_to_rad(START_ELEVATION_DEG)
var _auto_elevation_time := 0.0

func _init(p_catalog: PartsCatalog) -> void:
	catalog = p_catalog

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	picker = FramePicker.new(catalog)
	row.add_child(picker)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.add_child(_viewport)

	_build_world()

	details = FrameDetails.new()
	row.add_child(details)

	# Connected before anything is announced, then asked for the current selection once — so
	# the first paint goes through exactly the same path as every later change.
	picker.frame_selected.connect(_on_frame_selected)
	picker.emit_current()


## Lab's private 3D world: a turntable pivot holding the generated airframe, a camera at a
## fixed distance, and enough light to read carbon against nylon.
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Light enough to read a near-black airframe against, dark enough to still look like a
	# workshop rather than a spec sheet. The first pass at 0.09 lost the frame entirely.
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	# The airframe sits still and level at the origin; only the camera moves.
	frame_model = FrameModel.new()
	_viewport.add_child(frame_model)

	_orbit = Node3D.new()
	_viewport.add_child(_orbit)

	# A dimmer fill fixed in the world, grazing almost horizontally. Carbon fibre is nearly
	# black and a single light turns half the airframe into a silhouette, which hides the arms.
	# Kept near-horizontal rather than steeply overhead so it still does something once the
	# orbit drops below the airframe.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-6.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	_viewport.add_child(fill_light)

	# A weak bounce from below, standing in for the bench the build is sitting over. Without it
	# the underside — the view a battery tray or a payload mount is actually judged from — is
	# the one angle in the whole orbit that is lit only by ambient.
	var bounce_light := DirectionalLight3D.new()
	bounce_light.rotation_degrees = Vector3(62.0, 20.0, 0.0)
	bounce_light.light_energy = 0.32
	_viewport.add_child(bounce_light)

	_camera = Camera3D.new()
	# Horizontal FOV, held constant while the column's aspect changes — see _camera_distance_m.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 20.0
	# Parked out along the boom's +Z with no rotation of its own. A camera looks down its own
	# -Z, so from there it already points straight back at the origin — and it keeps pointing
	# there for every possible boom rotation, with no look_at and no aiming maths that could
	# drift. Rotating the boom is then the entire orbit, and the distance is structurally
	# impossible to change by accident, which is what protects the no-zoom guarantee.
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, _camera_distance_m()))
	_orbit.add_child(_camera)

	# The key light rides the boom, so whichever side of the build you orbit to is the side
	# that is lit. Underneath a frame is the one view that is otherwise always in shadow, and
	# it is exactly the view a battery tray or a payload mount needs.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, -22.0, 0.0)
	key_light.light_energy = 1.5
	key_light.shadow_enabled = true
	_orbit.add_child(key_light)

	_apply_orbit()


## Distance at which the CATALOG'S LARGEST airframe spans LARGEST_FRAME_SCREEN_FRACTION of
## the view — so the framing is chosen by the biggest frame that exists and then held for
## every frame, big or small. Falls back to the reference build's arm if the catalog somehow
## has no frames, rather than dividing by zero and putting the camera at the origin.
func _camera_distance_m() -> float:
	var largest_arm_m := 0.0
	for frame in catalog.list_category("frame"):
		largest_arm_m = maxf(largest_arm_m, float(frame["specs"]["arm_mm"]) / 1000.0)
	if largest_arm_m <= 0.0:
		largest_arm_m = Build.REFERENCE_ARM_M

	# Arm length is centre-to-motor, so the airframe spans twice that tip to tip.
	var span_m := largest_arm_m * 2.0
	var required_width_m := span_m / LARGEST_FRAME_SCREEN_FRACTION

	# CAMERA_FOV is the HORIZONTAL angle, because the camera is set to KEEP_WIDTH (see
	# _build_world). That is load-bearing rather than incidental: Lab's viewport is the middle
	# column of a three-column layout, so it is portrait, and its aspect changes with the
	# window. Under Godot's default KEEP_HEIGHT the horizontal field of view would depend on
	# that column's width — which put the 10" frame's arms straight off both edges.
	return (required_width_m * 0.5) / tan(deg_to_rad(CAMERA_FOV) * 0.5)


## The single path from a selection to everything that shows it. Geometry, spec rows and the
## five derived stats are rebuilt from one dictionary in one call, so there is no ordering in
## which the panel could be showing one frame while the viewport shows another.
func _on_frame_selected(frame: Dictionary) -> void:
	frame_model.rebuild(frame)
	details.render(frame, _build_with(frame))


## This frame fitted to the reference motor, prop and pack. Frames are only comparable if
## everything downstream of them is held still.
func _build_with(frame: Dictionary) -> Build:
	return Build.from_ids(
		catalog,
		frame["part_id"],
		ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID,
		ReferenceBuild.BATTERY_ID
	)


# ---------------------------------------------------------------------------
# The inspection orbit
# ---------------------------------------------------------------------------

## Points the camera at the airframe from the given angles. Elevation is clamped short of
## either pole: straight overhead is where an orbit rig's up-vector becomes undefined, and
## going past it flips the airframe over, which is disorienting and tells you nothing new.
func set_orbit(azimuth_rad: float, elevation_rad: float) -> void:
	var limit := deg_to_rad(ELEVATION_LIMIT_DEG)
	_azimuth_rad = azimuth_rad
	_elevation_rad = clampf(elevation_rad, -limit, limit)
	_apply_orbit()


## Nudges the orbit, as a drag does. This is the builder taking the view over, so the idle
## motion stops and stays stopped.
func orbit_by(azimuth_delta_rad: float, elevation_delta_rad: float) -> void:
	auto_orbit = false
	set_orbit(_azimuth_rad + azimuth_delta_rad, _elevation_rad + elevation_delta_rad)


func elevation_deg() -> float:
	return rad_to_deg(_elevation_rad)


func azimuth_deg() -> float:
	return rad_to_deg(_azimuth_rad)


## The camera's transform in Lab's world, composed by hand rather than read from
## global_transform — Lab is constructed before it is parented, and in the headless tests it
## is never parented at all.
func camera_world_transform() -> Transform3D:
	return _orbit.transform * _camera.transform


## Azimuth about the vertical, then elevation in the frame that azimuth already turned. Node3D
## defaults to YXZ euler order, which composes them in exactly that order, so the two angles
## behave as an orbit rather than as two independent world-axis spins.
##
## The X rotation is negated because a camera parked at +Z swings DOWN under a positive
## rotation about +X, and a positive elevation should raise it.
func _apply_orbit() -> void:
	if _orbit != null:
		_orbit.rotation = Vector3(-_elevation_rad, _azimuth_rad, 0.0)


func _process(delta: float) -> void:
	if _orbit == null or _dragging or not auto_orbit:
		return

	_auto_elevation_time += delta
	var phase := TAU * _auto_elevation_time / AUTO_ELEVATION_PERIOD_S
	set_orbit(
		_azimuth_rad + deg_to_rad(AUTO_ORBIT_DEG_S) * delta,
		deg_to_rad(AUTO_ELEVATION_CENTRE_DEG + AUTO_ELEVATION_SWING_DEG * sin(phase))
	)


## Drag anywhere over the viewport to orbit by hand: horizontal swings around the build,
## vertical rises over the top plate and drops under the belly. Releasing hands the azimuth
## back to the slow automatic turn, but leaves the elevation where it was put.
##
## There is deliberately no scroll-to-zoom. The camera distance is what makes two frames
## comparable at a glance (see _camera_distance_m), and a zoom control would let that go
## without anything looking wrong.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		orbit_by(
			deg_to_rad(motion.relative.x * DRAG_DEG_PER_PIXEL),
			deg_to_rad(-motion.relative.y * DRAG_DEG_PER_PIXEL)
		)
