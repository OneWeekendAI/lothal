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

## Emitted when a plate is clicked, with its index in the document, or −1 for a click on nothing.
##
## THE 3D VIEW HAS HANDS NOW. It used to be look-only, which made the one property a plan view
## cannot show — how high a plate sits in the stack — the one property you could not edit where you
## could see it. A builder checking whether the top plate clears the stack had to switch back to a
## flat drawing to move it.
signal plate_picked(plate_index: int)
## Emitted while a selected plate is dragged: how far it moved in plan, mm, and how far it moved
## vertically, mm. Both in the DOCUMENT's units, because the view's job is to say what the gesture
## meant and `FrameEdits` is what performs it — the same split the plan canvas keeps.
signal plate_dragged(plate_index: int, delta_mm: Vector2, delta_z_mm: float)

## Which plate is selected, mirrored from the workbench so the two views agree. −1 for none.
var selected_plate := -1

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
## How far a plate rises per pixel of a Shift-drag, mm. Slow enough that a 25 mm stack is a
## deliberate movement rather than a flick.
const HEIGHT_DRAG_MM_PER_PX := 0.5

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
## The plate being dragged in 3D, or −1. Its own state rather than a mode, because the gesture is
## decided by what was under the cursor when the button went down.
var _dragging_plate := -1
var _drag_from_mm := Vector2.ZERO
var _drag_plane_z_mm := 0.0

## What to draw once there is a world to draw it in. See the class comment: a document can arrive
## before `_ready`, and dropping it would leave the view blank until the next edit.
var _pending_document: AirframeDocument
var _pending_frame: Dictionary = {}
var _built := false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Re-frames the model when the view's own rectangle changes.
##
## The room's canvas takes whatever the shelf and the controls leave it, so this view is routinely
## given its real size AFTER a document has been handed to it — and a fit computed against a
## placeholder rectangle leaves the frame cropped at the edges of a viewport it was framed for at a
## different size. Only while visible: fitting a hidden view is arithmetic nobody sees.
func _on_resized_refit() -> void:
	if visible and _built and _pending_document != null:
		fit_to_document()


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
			if not button.pressed:
				_orbiting = false
				_dragging_plate = -1
				return
			# A CLICK ON A PLATE SELECTS IT; A CLICK ON NOTHING ORBITS. That split is what lets one
			# button do both without a modal tool: the empty space around a frame is most of the
			# viewport, so the gesture a builder already knows still works everywhere it used to.
			var hit := pick(button.position)
			plate_picked.emit(hit)
			if hit >= 0:
				_dragging_plate = hit
				_drag_plane_z_mm = AirframeDocument.plate_z_mm(_pending_document.plates[hit])
				_drag_from_mm = _plan_point_at(button.position, _drag_plane_z_mm)
			else:
				_orbiting = true
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_plate >= 0:
			_drag_plate(motion)
		elif _orbiting:
			_yaw -= deg_to_rad(motion.relative.x * ORBIT_SENSITIVITY)
			# CLAMPED, not wrapped. Letting the pitch roll past vertical flips the horizon and leaves
			# a builder looking at a mirrored frame with no way to tell that is what happened.
			_pitch = clampf(_pitch + deg_to_rad(motion.relative.y * ORBIT_SENSITIVITY),
				deg_to_rad(MIN_PITCH_DEG), deg_to_rad(MAX_PITCH_DEG))
			_apply_camera()


## Moves the plate under the cursor: in plan normally, in HEIGHT with Shift held.
##
## Shift for height rather than a second mouse button, because height is the reason to drag here at
## all and it has to be reachable on a trackpad. The plan drag is done by re-projecting the cursor
## onto the plate's own plane rather than by scaling pixels: at a shallow camera angle a pixel is
## worth centimetres near the horizon and millimetres near the camera, and a scaled drag makes the
## plate slide out from under the cursor.
func _drag_plate(motion: InputEventMouseMotion) -> void:
	if _pending_document == null or _dragging_plate >= _pending_document.plates.size():
		return
	if motion.shift_pressed:
		# 0.5 mm per pixel, upward for an upward drag. A height has no plane to project onto — the
		# gesture is along the screen — so this is the one place a pixel rate is the honest answer.
		var lift := -motion.relative.y * HEIGHT_DRAG_MM_PER_PX
		_drag_plane_z_mm += lift
		plate_dragged.emit(_dragging_plate, Vector2.ZERO, lift)
		return
	var now := _plan_point_at(motion.position, _drag_plane_z_mm)
	var delta := now - _drag_from_mm
	_drag_from_mm = now
	if delta != Vector2.ZERO:
		plate_dragged.emit(_dragging_plate, delta, 0.0)


## Which plate lies under a screen position, or −1.
##
## Ray against each plate's OWN PLANE, nearest first, rather than a physics query. A physics pick
## would need a collision body per plate, rebuilt on every edit, for a hit test on a handful of flat
## polygons — and `Geometry2D.is_point_in_polygon` against the document's own outline is both
## cheaper and the same polygon the mass integral uses, so a plate you can click is exactly a plate
## that weighs something.
func pick(position_px: Vector2) -> int:
	if _camera == null or _pending_document == null:
		return -1
	var best := -1
	var nearest := INF
	for index in _pending_document.plates.size():
		var plate: Dictionary = _pending_document.plates[index]
		var z_mm := AirframeDocument.plate_z_mm(plate)
		var hit := _plan_point_at(position_px, z_mm, true)
		if not is_finite(hit.x):
			continue
		var outline := AirframeDocument.plate_outline(plate)
		if outline.size() < 3 or not Geometry2D.is_point_in_polygon(hit, outline):
			continue
		var distance := AirframeDocument.world_m(hit, z_mm).distance_to(
			_camera.global_transform.origin)
		if distance < nearest:
			nearest = distance
			best = index
	return best


## Where the cursor's ray crosses the horizontal plane at a stated height, in plan millimetres.
## `Vector2(INF, INF)` when the ray is parallel to the plane or crosses it behind the camera —
## which is a miss, not a position, and returning a plausible number for it would let a plate be
## picked through the floor from underneath.
func _plan_point_at(position_px: Vector2, z_mm: float, strict: bool = false) -> Vector2:
	if _camera == null:
		return Vector2(INF, INF)
	# The container may be scaled relative to its viewport, so the position is mapped rather than
	# passed through: a stretched SubViewportContainer would otherwise pick a few millimetres off,
	# and the error would grow with the window.
	var scaled := position_px
	if size.x > 0.0 and size.y > 0.0:
		var viewport_size := Vector2(_viewport.size)
		scaled = position_px / size * viewport_size
	var origin := _camera.project_ray_origin(scaled)
	var direction := _camera.project_ray_normal(scaled)
	var plane_y := z_mm / 1000.0
	if absf(direction.y) < 1.0e-6:
		return Vector2(INF, INF)
	var travel := (plane_y - origin.y) / direction.y
	if strict and travel <= 0.0:
		return Vector2(INF, INF)
	var point := origin + direction * travel
	# world X → plan u, world Z → plan v, and metres → millimetres: `AirframeDocument.world_m`
	# inverted, which is the only place in this file that mapping appears.
	return Vector2(point.x, point.z) * 1000.0


# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------

func _build_world() -> void:
	resized.connect(_on_resized_refit)
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
## THE RADIUS, NOT THE BOUNDING BOX, and this is the one place the two genuinely differ. A plan view
## never turns, so its own fit can use the bounding box — what you see across a 5" X frame really is
## its 164 mm bbox and not its 220 mm diagonal. THIS view orbits. At the default 28° of yaw an X
## frame's diagonal lies across the screen, so a fit computed from the bounding box framed a 5"
## frame as 164 mm wide and drew it 220 mm wide, with both of the visible arms running off the edges
## of the viewport — the fault the fit exists to prevent, arrived at by measuring the wrong thing.
##
## The cost is honest and small: at a yaw where the arms point at the corners, the frame sits a
## little smaller than it could. A frame slightly too small is a frame you can see.
##
## About the ORIGIN rather than about the drawing's own centre, because the origin is what the
## camera looks at and what every motor position is measured from — a frame authored off-centre
## should look off-centre, which is the one way a builder ever notices they drew it that way.
func _span_m() -> float:
	var half_mm := 0.0
	if _pending_document != null:
		for plate in _pending_document.plates:
			for point in AirframeDocument.plate_outline(plate):
				half_mm = maxf(half_mm, point.length())
	if half_mm <= 0.0:
		# An empty document. A 200 mm box, matching the plan editor's empty framing, so switching
		# views on a blank frame does not change how big "nothing" looks.
		half_mm = 100.0
	return half_mm * 2.0 / 1000.0


func _distance_for(span_m: float) -> float:
	var half_fov := deg_to_rad(CAMERA_FOV) * 0.5
	var wanted := (span_m * 0.5) / maxf(tan(half_fov) * FRAME_SCREEN_FRACTION, 0.0001)
	return clampf(wanted, MIN_DISTANCE_M, MAX_DISTANCE_M)
