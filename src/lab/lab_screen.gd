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
const CAMERA_ELEVATION_DEG := 26.0
const CAMERA_FOV := 38.0
## Fraction of the viewport width the largest airframe should span. Leaves the biggest frame
## visibly inside the room rather than touching both edges.
const LARGEST_FRAME_SCREEN_FRACTION := 0.78

## A slow turntable, so the airframe reads as a three-dimensional object rather than a
## picture of one. Rotation cannot hide a size difference the way a moving camera could.
const AUTO_ORBIT_DEG_S := 11.0
## Drag speed when the pilot takes over the turntable by hand.
const DRAG_DEG_PER_PIXEL := 0.4

var catalog: PartsCatalog
var picker: FramePicker
var details: FrameDetails
var frame_model: FrameModel

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _dragging := false

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

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key_light.light_energy = 1.5
	key_light.shadow_enabled = true
	_viewport.add_child(key_light)

	# A second, dimmer light from the opposite side. Carbon fibre is nearly black and a
	# single key light turns half the airframe into a silhouette, which hides the arms —
	# the one thing this screen exists to show.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	_viewport.add_child(fill_light)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	frame_model = FrameModel.new()
	_pivot.add_child(frame_model)

	_camera = Camera3D.new()
	# Horizontal FOV, held constant while the column's aspect changes — see _camera_distance_m.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 20.0
	var distance := _camera_distance_m()
	var elevation := deg_to_rad(CAMERA_ELEVATION_DEG)
	var eye := Vector3(
		0.0,
		sin(elevation) * distance,
		cos(elevation) * distance
	)
	# Basis.looking_at rather than Node3D.look_at: look_at requires the node to be inside a
	# tree, and Lab is constructed before it is parented (and never parented at all in the
	# headless tests). Basis.looking_at points -Z down the given direction, which is the
	# camera's own forward, so aiming it at the origin needs no correction term.
	_camera.transform = Transform3D(Basis.looking_at(-eye.normalized(), Vector3.UP), eye)
	_viewport.add_child(_camera)


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


func _process(delta: float) -> void:
	if _pivot != null and not _dragging:
		_pivot.rotate_y(deg_to_rad(AUTO_ORBIT_DEG_S) * delta)


## Drag anywhere over the viewport to take the turntable over by hand; releasing hands it
## back to the slow automatic orbit.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging and _pivot != null:
		_pivot.rotate_y(deg_to_rad(motion.relative.x * DRAG_DEG_PER_PIXEL))
