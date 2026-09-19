class_name FramePlanEditor
extends Control
## The plan view you draw a frame in — airframe.md §7.1, slice A7.
##
## ## What this file is and is not
##
## It is the top view of the open `AirframeDocument`, drawn to scale, with the plates, their holes,
## the arm centrelines and the motors on it; and it is the hands that move those points. It is NOT
## where any of the editing arithmetic lives. Every change goes through `FrameEdits`, which is pure
## and fully tested headless (`test_frame_edits.gd`), and every mm-to-pixel conversion goes through
## `PlanTransform`, which is also pure and also tested. What is left here — and it is deliberately
## all that is left — is: which thing is under the cursor, what a drag means, and what the result
## looks like.
##
## That split is what makes the risky half provable. "Dragging a vertex doubles the plate's mass" is
## an assertion about arithmetic; "the vertex highlights when you hover it" is not, and only the
## second needs a human to look at it.
##
## ## Why it draws the same polygons the physics reads
##
## §0's rule, applied literally: this canvas paints `AirframeDocument.plate_outline()` and nothing
## else. There is no simplified display polygon, no cached silhouette, no "close enough for the
## picture" shape. If a plate looks wrong here, the mass is wrong too, and that is the intended
## coupling — the drawing is the model, so a drawing that lies is a bug you can see.
##
## ## Nose up
##
## `PlanTransform` puts +v (aft) DOWN, so the frame is drawn nose-up like every product photo. The
## conventions are stated there rather than here, because getting them from one place is what stops
## the picture and the inertia tensor disagreeing about which way is forward.

## Emitted after any edit, so the four inspector tabs repaint against the changed frame. The
## document is passed rather than being read back off this node: the panels should never have to
## know where the editor keeps its state.
signal document_changed(document: AirframeDocument)
## Emitted when the selection changes, so a properties strip can follow it.
signal selection_changed(plate_index: int)
## Emitted when the CAMERA moves — zoom or pan — and nothing about the document has changed. Its
## own signal rather than a second use of `document_changed`, because the four inspector tabs listen
## to that one and re-integrating the mass of every plate because somebody scrolled a wheel is work
## for an answer that cannot have moved.
signal view_changed

## How close, in PIXELS, the cursor has to be to grab a vertex. In pixels rather than millimetres
## because it describes a hand rather than a frame: at 8 px it is the same physical distance whether
## you are looking at a whole 10" frame or one bolt hole.
const GRAB_RADIUS_PX := 9.0
const VERTEX_RADIUS_PX := 4.0

const ZOOM_STEP := 1.15

## What is being dragged, if anything.
enum Drag { NONE, VERTEX, PLATE, PAN }

var document: AirframeDocument
var history := FrameHistory.new()
var transform := PlanTransform.new()

## Which plate is selected, and which of its vertices is hovered. −1 for none, in both cases.
var selected_plate := -1
var hovered_plate := -1
var hovered_vertex := -1

## The grid, in mm, that a drag lands on. Zero disables snapping — see `FrameEdits.snap`.
var snap_mm := FrameEdits.DEFAULT_SNAP_MM

## When true, dragging one arm's vertex applies to every arm, so a quad stays a quad. §7.1's
## "symmetry on by default, breakable" (§10 q2): it is on, and one click turns it off.
var symmetric_arms := true

var _drag := Drag.NONE
var _drag_vertex := -1
var _last_mouse_px := Vector2.ZERO
var _fitted := false
## Whether the builder has moved the view themselves. Until they have, a resize re-frames the
## drawing; after it, a resize leaves the camera exactly where they put it. Without the flag the
## canvas either abandons a frame on the first window resize or overrides a deliberate zoom on
## every one, and both are wrong for the same reason: the view belongs to whoever last aimed it.
var _view_moved := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	# THE CANVAS MUST CLIP. A Control does not clip its own drawing, and every line here is placed
	# by a pan-and-zoom transform with no bound on it — so a zoomed-in frame painted its arms
	# straight over the toolbar, the inspector and the window edge, on top of chrome it is
	# supposed to sit under. One property, and it is the difference between a viewport and a
	# stencil-free plotter.
	clip_contents = true
	resized.connect(_on_resized)


## Opens a frame. Clears the history, because the previous frame's undo stack is not this one's —
## an undo that reached across an open would silently replace the frame you just opened with the one
## you just left.
func open(p_document: AirframeDocument) -> void:
	document = p_document
	history.clear()
	selected_plate = -1
	hovered_plate = -1
	hovered_vertex = -1
	_fitted = false
	queue_redraw()
	document_changed.emit(document)


## Frames the whole document in the view. Called once on the first draw after an open, and by the
## "fit" control; not on every redraw, or the view would fight the builder for the camera every time
## they dragged a vertex outward.
func fit_to_document() -> void:
	var bounds := _bounds_mm()
	transform.fit(bounds[0], bounds[1], size)
	_fitted = true
	_view_moved = false
	queue_redraw()
	view_changed.emit()


## Zooms about the middle of the view. The toolbar's ± buttons and the keyboard drive this; the
## wheel does NOT, because a wheel has a cursor to zoom about and a button does not, and zooming a
## button press about the last place the mouse happened to be is how a canvas jumps sideways when
## you press "+".
func zoom_by(factor: float) -> void:
	transform.zoom_at(size * 0.5, factor)
	_view_moved = true
	queue_redraw()
	view_changed.emit()


## How far in the view is, as a multiple of what `fit` would choose. Shown in the toolbar so the
## scale bar has a number beside it and "I am lost" has an obvious way back.
func zoom_ratio() -> float:
	var bounds := _bounds_mm()
	var fitted := PlanTransform.new()
	fitted.fit(bounds[0], bounds[1], size)
	if fitted.scale_px_per_mm <= 0.0:
		return 1.0
	return transform.scale_px_per_mm / fitted.scale_px_per_mm


## Whether a change of size should re-frame the drawing.
##
## Its own predicate rather than two clauses inside the signal handler, because it is the whole of
## the policy and the signal is untestable here: `resized` does not fire on a Control outside the
## tree, so a suite that drove it through `size =` would assert nothing in either direction. This
## can be asked directly, and it is the part that can be wrong.
func should_refit_on_resize() -> bool:
	return _fitted and not _view_moved


func _on_resized() -> void:
	if should_refit_on_resize():
		fit_to_document()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_handle_key(event as InputEventKey)


func _handle_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		transform.zoom_at(event.position, ZOOM_STEP)
		_view_moved = true
		queue_redraw()
		view_changed.emit()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		transform.zoom_at(event.position, 1.0 / ZOOM_STEP)
		_view_moved = true
		queue_redraw()
		view_changed.emit()
		return

	# Middle button pans, always, whatever is under it. A canvas where panning depends on hitting
	# empty space is a canvas you cannot pan once you have drawn something.
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_drag = Drag.PAN if event.pressed else Drag.NONE
		_last_mouse_px = event.position
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		_drag = Drag.NONE
		_drag_vertex = -1
		return

	_last_mouse_px = event.position
	var hit := _vertex_at(event.position)
	if hit[0] >= 0:
		# THE SNAPSHOT IS TAKEN ON PRESS, ONCE — not per motion event. A drag is one edit as far as
		# a builder is concerned, and recording every intermediate position would make undo step
		# back through the path the mouse took rather than to where the vertex started.
		history.record(document)
		selected_plate = hit[0]
		_drag_vertex = hit[1]
		_drag = Drag.VERTEX
		selection_changed.emit(selected_plate)
		queue_redraw()
		return

	var plate := _plate_at(event.position)
	if plate >= 0:
		history.record(document)
		selected_plate = plate
		_drag = Drag.PLATE
		selection_changed.emit(selected_plate)
	else:
		selected_plate = -1
		_drag = Drag.PAN
		selection_changed.emit(selected_plate)
	queue_redraw()


func _handle_motion(event: InputEventMouseMotion) -> void:
	var delta := event.position - _last_mouse_px
	_last_mouse_px = event.position

	match _drag:
		Drag.PAN:
			transform.pan(delta)
			_view_moved = true
		Drag.VERTEX:
			_drag_vertex_to(event.position, event.ctrl_pressed)
		Drag.PLATE:
			# Plate drags are snapped by their DELTA rather than by their position, so a plate whose
			# corners are off-grid keeps its shape instead of being quantised corner by corner.
			FrameEdits.move_plate(document, selected_plate,
				FrameEdits.snap(delta * transform.mm_per_pixel(), _active_snap(event.ctrl_pressed)))
			document_changed.emit(document)
		Drag.NONE:
			var hit := _vertex_at(event.position)
			var plate := _plate_at(event.position)
			if hit[0] != hovered_plate or hit[1] != hovered_vertex or plate != hovered_plate:
				hovered_plate = hit[0] if hit[0] >= 0 else plate
				hovered_vertex = hit[1]
	queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				undo()
		KEY_F:
			fit_to_document()
		KEY_S:
			symmetric_arms = not symmetric_arms
			queue_redraw()


## Steps back one edit. Public because the toolbar drives it too, and both paths must be the same
## one — an undo button that did its own thing would diverge from Ctrl-Z the first time either
## changed.
func undo() -> void:
	if not history.can_undo():
		return
	document = history.undo(document)
	selected_plate = mini(selected_plate, document.plates.size() - 1)
	queue_redraw()
	document_changed.emit(document)


## Moves the dragged vertex, and its counterparts on the other arms when symmetry is on.
##
## The counterpart is found by ROTATION, not by index: arm 2's matching vertex is arm 1's vertex
## turned by 90 degrees about the origin, which is the same relationship `FrameEdits.replicate_
## radially` created them with. Matching by index alone would work for arms made by replication and
## silently mangle any arm a builder had since edited.
func _drag_vertex_to(position_px: Vector2, no_snap: bool) -> void:
	var target := FrameEdits.snap(
		transform.to_mm(position_px), _active_snap(no_snap))
	FrameEdits.move_vertex(document, selected_plate, _drag_vertex, target)

	if symmetric_arms and _is_arm(selected_plate):
		var arms := _arm_indices()
		var count := arms.size()
		var source_slot := arms.find(selected_plate)
		if count > 1 and source_slot >= 0:
			for slot in count:
				if slot == source_slot:
					continue
				var angle := TAU * float(slot - source_slot) / float(count)
				FrameEdits.move_vertex(document, arms[slot], _drag_vertex, target.rotated(angle))
	document_changed.emit(document)


## The snap step in force for this event. Holding Ctrl suspends snapping, which is the standard
## gesture and the one escape hatch a builder needs when a real part lands between grid steps.
func _active_snap(no_snap: bool) -> float:
	return 0.0 if no_snap else snap_mm


# ---------------------------------------------------------------------------
# Hit testing
# ---------------------------------------------------------------------------

## `[plate_index, vertex_index]` of the vertex under a screen position, or `[-1, -1]`.
##
## Searched in REVERSE document order so the plate drawn on top is the one you grab. Drawing order
## and hit order have to be opposites or the thing you can see is not the thing you can click.
func _vertex_at(position_px: Vector2) -> Array:
	if document == null:
		return [-1, -1]
	for index in range(document.plates.size() - 1, -1, -1):
		var points := AirframeDocument.plate_outline(document.plates[index])
		for vertex in points.size():
			if transform.to_pixels(points[vertex]).distance_to(position_px) <= GRAB_RADIUS_PX:
				return [index, vertex]
	return [-1, -1]


## The topmost plate whose outline contains a screen position, or −1.
func _plate_at(position_px: Vector2) -> int:
	if document == null:
		return -1
	var point_mm := transform.to_mm(position_px)
	for index in range(document.plates.size() - 1, -1, -1):
		var points := AirframeDocument.plate_outline(document.plates[index])
		if points.size() >= 3 and Geometry2D.is_point_in_polygon(point_mm, points):
			return index
	return -1


func _is_arm(plate_index: int) -> bool:
	if document == null or plate_index < 0 or plate_index >= document.plates.size():
		return false
	return str((document.plates[plate_index] as Dictionary).get("role", "")) \
		== AirframeDocument.ROLE_ARM


func _arm_indices() -> Array:
	var out: Array = []
	if document == null:
		return out
	for index in document.plates.size():
		if _is_arm(index):
			out.append(index)
	return out


## The document's extent in mm, with a sane box for an empty frame so `fit` has something to frame.
func _bounds_mm() -> Array:
	var min_mm := Vector2(INF, INF)
	var max_mm := Vector2(-INF, -INF)
	if document != null:
		for plate in document.plates:
			for point in AirframeDocument.plate_outline(plate):
				min_mm = min_mm.min(point)
				max_mm = max_mm.max(point)
	if not is_finite(min_mm.x) or not is_finite(max_mm.x):
		# An empty frame is framed on a 200 mm square centred on the origin: about a 5" frame, so
		# the first plate somebody draws is a sensible size on screen rather than a speck or a wall.
		return [Vector2(-100.0, -100.0), Vector2(100.0, 100.0)]
	return [min_mm, max_mm]


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _fitted and size.x > 0.0 and size.y > 0.0:
		fit_to_document()

	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	_draw_grid()
	_draw_axes()

	if document == null:
		return

	for index in document.plates.size():
		_draw_plate(index)
	_draw_motors()
	_draw_scale_bar()


func _draw_grid() -> void:
	var step := transform.grid_step_mm()
	var colour := Color(LothalTheme.BORDER, 0.35)
	var top_left := transform.to_mm(Vector2.ZERO)
	var bottom_right := transform.to_mm(size)

	var x: float = floor(top_left.x / step) * step
	while x <= bottom_right.x:
		var px := transform.to_pixels(Vector2(x, 0.0)).x
		draw_line(Vector2(px, 0.0), Vector2(px, size.y), colour, 1.0)
		x += step
	var y: float = floor(top_left.y / step) * step
	while y <= bottom_right.y:
		var py := transform.to_pixels(Vector2(0.0, y)).y
		draw_line(Vector2(0.0, py), Vector2(size.x, py), colour, 1.0)
		y += step


## The origin, which is the point every motor position, every inertia and the whole mixer is
## measured from. Drawn because a frame drifting off its own origin is invisible otherwise, and it
## is the difference between a balanced quad and one that trims itself sideways forever.
func _draw_axes() -> void:
	var origin := transform.to_pixels(Vector2.ZERO)
	var colour := Color(LothalTheme.TEXT_MUTED, 0.7)
	draw_line(Vector2(0.0, origin.y), Vector2(size.x, origin.y), colour, 1.0)
	draw_line(Vector2(origin.x, 0.0), Vector2(origin.x, size.y), colour, 1.0)


func _draw_plate(index: int) -> void:
	var plate: Dictionary = document.plates[index]
	var points := AirframeDocument.plate_outline(plate)
	if points.size() < 3:
		return

	var screen := PackedVector2Array()
	for point in points:
		screen.append(transform.to_pixels(point))

	var is_arm := str(plate.get("role", "")) == AirframeDocument.ROLE_ARM
	var selected := index == selected_plate
	# Arms and plates are told apart by fill, not by outline colour: an arm is the thing whose
	# stiffness and resonance are computed, and which plates those are is the single most
	# consequential piece of state on this canvas.
	var fill := LothalTheme.ACCENT if is_arm else LothalTheme.TEXT_MAIN
	draw_colored_polygon(screen, Color(fill, 0.16 if not selected else 0.28))
	draw_polyline(_closed(screen), Color(fill, 0.9 if selected else 0.6), 2.0 if selected else 1.0)

	for hole in AirframeDocument.plate_holes(plate):
		var hole_screen := PackedVector2Array()
		for point in hole:
			hole_screen.append(transform.to_pixels(point))
		if hole_screen.size() >= 3:
			# Holes are drawn as the SURFACE colour rather than as an outline, so a hole that
			# overlaps an edge reads as material missing rather than as a circle drawn on top.
			draw_colored_polygon(hole_screen, LothalTheme.SURFACE_BASE)
			draw_polyline(_closed(hole_screen), Color(fill, 0.5), 1.0)

	if is_arm and plate.has("root_point") and plate.has("tip_point"):
		var root := transform.to_pixels(AirframeDocument.point_of(plate["root_point"]))
		var tip := transform.to_pixels(AirframeDocument.point_of(plate["tip_point"]))
		# The authored centreline (§10 q1). Dashed, because it is not an edge of anything — it is
		# the line the width is measured perpendicular to, and drawing it solid would read as a cut.
		draw_dashed_line(root, tip, Color(LothalTheme.WARNING, 0.8), 1.5, 6.0)

	if selected or index == hovered_plate:
		for vertex in screen.size():
			var hot := index == hovered_plate and vertex == hovered_vertex
			draw_circle(screen[vertex], VERTEX_RADIUS_PX + (2.0 if hot else 0.0),
				LothalTheme.BORDER_FOCUS if hot else Color(fill, 0.9))


func _draw_motors() -> void:
	for motor in document.motors:
		var centre := transform.to_pixels(
			AirframeDocument.point_of(motor.get("position_mm", [0.0, 0.0])))
		var clockwise := float(motor.get("spin", 1.0)) > 0.0
		# Spin direction is drawn as a filled vs hollow ring rather than as a letter: it is readable
		# at any zoom, and it is the property that decides whether the layout can yaw at all.
		var colour := LothalTheme.SUCCESS if clockwise else LothalTheme.WARNING
		draw_arc(centre, 9.0, 0.0, TAU, 24, colour, 2.0)
		if clockwise:
			draw_circle(centre, 3.0, colour)


## A bar of known length, so the drawing has a scale even in a screenshot. Cheap, and it is the
## difference between "a frame" and "a 5-inch frame" for anybody looking at the picture later.
func _draw_scale_bar() -> void:
	var step := transform.grid_step_mm() * 5.0
	var length_px := step * transform.scale_px_per_mm
	var y := size.y - 24.0
	var start := Vector2(20.0, y)
	var end := start + Vector2(length_px, 0.0)
	draw_line(start, end, LothalTheme.TEXT_MUTED, 2.0)
	draw_line(start + Vector2(0.0, -4.0), start + Vector2(0.0, 4.0), LothalTheme.TEXT_MUTED, 2.0)
	draw_line(end + Vector2(0.0, -4.0), end + Vector2(0.0, 4.0), LothalTheme.TEXT_MUTED, 2.0)
	var font := LothalTheme.draw_font()
	draw_string(font, start + Vector2(0.0, -8.0), "%.0f mm" % step,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
