class_name Frame3DView
extends SubViewportContainer
## The frame you drew, in three dimensions — the other half of the Airframe room.
##
## ## Why the room needed this at all
##
## `FramePlanEditor` is a top view, and a top view cannot show the one thing an airframe is: a
## STACK. Plate roles, standoff height, which plate an arm is sandwiched between and how far the
## top plate sits above the bottom are all authored in the plan view as numbers and are invisible
## there. They are the whole shape here. A builder who has just dragged a corner should be able to
## turn the result over without leaving the room they drew it in, and before this they could not —
## the 3D model one dropdown click away is the FITTED frame, not the one on the canvas.
##
## ## It draws the same document, through the same builder
##
## This does not have a mesh generator of its own. It hands the open `AirframeDocument` to
## `FrameModel.rebuild_document`, which is the same call Lab makes for the fitted frame and the
## same `PlateMesh.extrude` the physics reads its polygons from. §0's rule again: one geometry, so
## a plate that looks wrong here is wrong in the mass model too.
##
## ## Its own world, built in `_ready` and never in `_init`
##
## A `SubViewport` HAS NO `World3D` UNTIL IT IS INSIDE THE TREE. A screen built in a constructor
## captures null, renders nothing, and reports no error — which is exactly how Lab's old inset
## silently failed to draw for weeks. So everything below happens on `_ready`, and a document handed
## over before then is remembered and rendered when the world exists.

## Where the camera starts. Slightly above the horizon and off the nose, which is the angle a frame
## is photographed from and the one that shows the stack and the arm sweep in the same picture.
const START_YAW_DEG := 28.0
const START_PITCH_DEG := 20.0

const MIN_PITCH_DEG := -85.0
const MAX_PITCH_DEG := 85.0

## How much of the view the frame spans at rest. Under one, so a frame never touches the edges and
## an arm dragged outward has somewhere to go before the view has to be re-fitted.
const FRAME_SCREEN_FRACTION := 0.72
const CAMERA_FOV := 42.0

const ZOOM_STEP := 1.12
const MIN_DISTANCE_M := 0.06
const MAX_DISTANCE_M := 4.0

const ORBIT_SENSITIVITY := 0.35

var _viewport: SubViewport
var _orbit: Node3D
var _camera: Camera3D
var _frame_model: FrameModel

var _yaw := deg_to_rad(START_YAW_DEG)
var _pitch := deg_to_rad(START_PITCH_DEG)
var _distance_m := 0.5
## Set by `fit_to_document`, and what a zoom is measured against — so "fit" is a distance this
## object can return to exactly rather than a gesture that approximates it.
var _fitted_distance_m := 0.5

var _orbiting := false

## What to draw once there is a world to draw it in. See the class comment: a document can arrive
## before `_ready`, and dropping it would leave the view blank until the next edit.
var _pending_document: AirframeDocument
var _pending_frame: Dictionary = {}
var _built := false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_build_world()
	_built = true
	if _pending_document != null:
		show_document(_pending_document, _pending_frame)


## Draws a document. `frame` is the catalog entry the document came from and is used for exactly
## what `FrameModel.rebuild_document` uses it for — the surface material and the mount table.
## Neither is geometry, and an empty dictionary is a legal argument for a frame nobody started from.
func show_document(document: AirframeDocument, frame: Dictionary = {}) -> void:
	_pending_document = document
	_pending_frame = frame
	if not _built or document == null:
		return
	_frame_model.rebuild_document(document, frame, -1.0)
	fit_to_document()


## Puts the camera where the whole frame is in shot, and remembers that distance as the one `Fit`
## returns to.
func fit_to_document() -> void:
	_fitted_distance_m = _distance_for(_span_m())
	_distance_m = _fitted_distance_m
	_apply_camera()


## Resets the angle as well as the distance — the button in the toolbar, and what a builder means
## by "put it back" after tumbling the view somewhere unreadable.
func reset_view() -> void:
	_yaw = deg_to_rad(START_YAW_DEG)
	_pitch = deg_to_rad(START_PITCH_DEG)
	fit_to_document()


func zoom_by(factor: float) -> void:
	_distance_m = clampf(_distance_m / factor, MIN_DISTANCE_M, MAX_DISTANCE_M)
	_apply_camera()


func camera_distance_m() -> float:
	return _distance_m


func viewport() -> SubViewport:
	return _viewport


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = button.pressed
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_yaw -= deg_to_rad(motion.relative.x * ORBIT_SENSITIVITY)
		# CLAMPED, not wrapped. Letting the pitch roll past vertical flips the horizon and leaves a
		# builder looking at a mirrored frame with no way to tell that is what happened.
		_pitch = clampf(_pitch + deg_to_rad(motion.relative.y * ORBIT_SENSITIVITY),
			deg_to_rad(MIN_PITCH_DEG), deg_to_rad(MAX_PITCH_DEG))
		_apply_camera()


# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------

func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = LothalTheme.SURFACE_BASE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# BRIGHTER THAN LAB'S WORLD, deliberately. Lab lights a whole aircraft — motors, a pack, props,
	# a printed mount — and the carbon reads against those. Here there is nothing in shot but the
	# carbon, which is nearly black, so the same lighting produced a dark grey frame on a dark grey
	# ground and the plate edges that are the entire point of this view were invisible.
	env.ambient_light_color = Color(0.58, 0.63, 0.72)
	env.ambient_light_energy = 1.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	_frame_model = FrameModel.new()
	_viewport.add_child(_frame_model)

	# A near-horizontal fill, for the reason Lab's world states: carbon is nearly black and one
	# light turns half of an airframe into a silhouette, which is the half with the arms in it.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-6.0, 145.0, 0.0)
	fill_light.light_energy = 0.7
	_viewport.add_child(fill_light)

	# A weak bounce from below, standing in for the bench the frame is lying on. Without it the
	# underside is lit by ambient alone — and the underside is half of every orbit through a plate
	# stack, which is the shape this view exists to show.
	var bounce_light := DirectionalLight3D.new()
	bounce_light.rotation_degrees = Vector3(62.0, 20.0, 0.0)
	bounce_light.light_energy = 0.45
	_viewport.add_child(bounce_light)

	_orbit = Node3D.new()
	_viewport.add_child(_orbit)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 30.0
	_orbit.add_child(_camera)

	# The key light rides the boom, so whichever side you orbit to is the side that is lit —
	# including underneath, which is where a plate stack is actually judged from.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, -22.0, 0.0)
	key_light.light_energy = 2.1
	_orbit.add_child(key_light)

	_apply_camera()


## The camera is parked out along the boom's +Z with no rotation of its own, and the boom is turned.
## A camera looks down its own −Z, so from there it already points at the origin for EVERY boom
## rotation, with no `look_at` and no aiming arithmetic that could drift as the angle wraps.
func _apply_camera() -> void:
	if _orbit == null:
		return
	_orbit.rotation = Vector3(-_pitch, _yaw, 0.0)
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, _distance_m))


## How wide the frame is on screen, in metres, as an extent about the origin.
##
## THE BOUNDING BOX, NOT THE RADIUS. An X frame's arms reach furthest along the diagonals, so its
## radial reach is about 40% larger than anything you can actually see across it — measured that
## way, a 5" frame was framed as though it were a disc 310 mm across and drew at about half the
## width it should have, marooned in the middle of a large empty viewport.
##
## About the ORIGIN rather than about the drawing's own centre, because the origin is what the
## camera looks at and what every motor position is measured from — a frame authored off-centre
## should look off-centre, which is the one way a builder ever notices they drew it that way.
func _span_m() -> float:
	var extent := Vector2.ZERO
	if _pending_document != null:
		for plate in _pending_document.plates:
			for point in AirframeDocument.plate_outline(plate):
				extent = extent.max(point.abs())
	var half_mm := maxf(extent.x, extent.y)
	if half_mm <= 0.0:
		# An empty document. A 200 mm box, matching the plan editor's empty framing, so switching
		# views on a blank frame does not change how big "nothing" looks.
		half_mm = 100.0
	return half_mm * 2.0 / 1000.0


func _distance_for(span_m: float) -> float:
	var half_fov := deg_to_rad(CAMERA_FOV) * 0.5
	var wanted := (span_m * 0.5) / maxf(tan(half_fov) * FRAME_SCREEN_FRACTION, 0.0001)
	return clampf(wanted, MIN_DISTANCE_M, MAX_DISTANCE_M)
