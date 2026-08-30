class_name PropellerPlanformEditor
extends Control
## The blade's planform, drawn to scale and editable — propulsion.md §7.1, slice P10d.
##
## ## What this canvas shows
##
## A blade seen from above: radius across, chord up and down, symmetric about the blade's own
## centreline, with one control point per station of the document's `c(r)` table. Drag a point and
## the blade gets wider or narrower there — and because P10d made `PropellerMesh` read
## `PropellerDocument.chord_at()`, the 3D blade in Lab changes with it. That coupling is the whole
## reason the room exists: before it, an edited planform moved the physics and not the picture.
##
## ## What is NOT in this file
##
## The editing arithmetic. Every gesture ends in a `PlanformEdits` call, which is pure and tested
## headless — the same split `FramePlanEditor` made against `FrameEdits`, for the same reason:
## "dragging a station halves the chord there" is provable without a window, and "the point lights
## up when you hover it" is not.
##
## Nor is there any pan or zoom. A planform has a known extent in both axes — radius runs 0 to 1 and
## chord runs 0 to its own maximum — so the view that fits it is the only view worth having, and a
## canvas that can be scrolled away from its subject is a canvas a builder has to re-find. This is
## the deliberate difference from the frame designer, whose subject has no natural size.
##
## ## Chord up AND down
##
## The blade is drawn symmetric about its centreline because that is what `section_corners_mm`
## says: the section is centred on the radial axis, half the chord each side. Drawing it as a
## single-sided profile would be a prettier picture of a blade the model does not have, and the
## first question a builder asks the room — "where is the widest point" — would be answered against
## the wrong shape.

## Emitted after any edit, with the changed document. Passed rather than read back off this node,
## on `FramePlanEditor`'s own rule: nothing downstream should have to know where the editor keeps
## its state.
signal document_changed(document: PropellerDocument)
## Emitted when the caret moves — the r/R the section view draws at. Its own signal because moving
## the caret changes no geometry, and the room's numbers strip must not re-integrate a blade
## because somebody moved the mouse.
signal caret_moved(r_frac: float)

## How close, in PIXELS, the cursor must be to grab a station. Pixels rather than millimetres for
## `FramePlanEditor.GRAB_RADIUS_PX`'s reason: it describes a hand, so it is the same physical
## distance on a 3" blade and a 16" one.
const GRAB_RADIUS_PX := 9.0
const STATION_RADIUS_PX := 3.5

## The margin around the drawing, in pixels. Room for the outermost control point's own disc plus
## the axis labels, and nothing more — the canvas is small and every pixel of it is the blade.
const MARGIN_PX := 22.0

var document: PropellerDocument

## Which station is hovered and which is being dragged. −1 for none, in both.
var hovered_station := -1
var dragging_station := -1

## Where the section view is looking, as a fraction of radius. Starts at the widest part of a
## typical blade rather than at the root, because the root of a propeller is a fillet and the
## section there tells a builder nothing.
var caret_r_frac := 0.7

## True while a drag is in progress and the document has already been changed once. The room
## records undo state on `edit_began`, and a drag that emitted that on every mouse motion would
## fill the history with one entry per pixel.
var _edit_open := false


func _init(p_document: PropellerDocument = null) -> void:
	document = p_document
	custom_minimum_size = Vector2(260, 150)
	# A Control does NOT clip its own `_draw` (the airframe room's own finding), and a chord that
	# grows past the fitted scale during a drag would paint over the toolbar above it.
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_document(p_document: PropellerDocument) -> void:
	document = p_document
	hovered_station = -1
	dragging_station = -1
	queue_redraw()


# ---------------------------------------------------------------------------
# The mm <-> pixel mapping
# ---------------------------------------------------------------------------
#
# Public and pure, so the tests can assert where a station LANDS without rendering anything —
# `PlanTransform`'s posture, in the one-axis-each case where a whole class would be ceremony.

## The chord the vertical scale is fitted to: the widest station, or a nominal 1 mm for a planform
## that is somehow all zero, so the mapping never divides by nothing.
func chord_scale_mm() -> float:
	var widest := 0.0
	if document != null:
		for point in PlanformEdits.points(document.chord):
			widest = maxf(widest, float(point[1]))
	return widest if widest > 0.0 else 1.0


## (r/R, chord_mm) to a pixel on this canvas. The chord is HALVED because the blade is drawn
## symmetric about its centreline: a station of chord c reaches c/2 either side.
func to_pixels(r_frac: float, chord_mm: float) -> Vector2:
	var inner := _inner_rect()
	var x := inner.position.x + inner.size.x * clampf(r_frac, 0.0, 1.0)
	var y := inner.position.y + inner.size.y * 0.5 \
		- inner.size.y * 0.5 * (chord_mm * 0.5) / chord_scale_mm()
	return Vector2(x, y)


## A pixel back to a chord in mm, measured from the centreline. The inverse of the halving above,
## so a drag to a pixel and a read of that pixel agree.
func chord_from_pixels(pixel: Vector2) -> float:
	var inner := _inner_rect()
	if inner.size.y <= 0.0:
		return 0.0
	var half := (inner.position.y + inner.size.y * 0.5 - pixel.y) / (inner.size.y * 0.5)
	return maxf(half * chord_scale_mm() * 2.0, 0.0)


## A pixel back to a fraction of radius.
func r_frac_from_pixels(pixel: Vector2) -> float:
	var inner := _inner_rect()
	if inner.size.x <= 0.0:
		return 0.0
	return clampf((pixel.x - inner.position.x) / inner.size.x, 0.0, 1.0)


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# Hands
# ---------------------------------------------------------------------------

## The station under a pixel, or −1. Nearest by RADIUS only, then checked against the grab radius
## in both axes: a builder aiming at the tip station of a narrow blade is aiming at a point, and
## picking by horizontal distance alone would hand them a station they can see they did not click.
func station_at(pixel: Vector2) -> int:
	if document == null:
		return -1
	var pts := PlanformEdits.points(document.chord)
	var best := -1
	var best_distance := GRAB_RADIUS_PX
	for i in pts.size():
		var at := to_pixels(float(pts[i][0]), float(pts[i][1]))
		var distance := at.distance_to(pixel)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			dragging_station = station_at(button.position)
			_edit_open = false
			# A click on empty canvas moves the caret rather than doing nothing: the section view
			# is the reason to look at a radius, and making that a separate mode would be a mode.
			if dragging_station < 0:
				set_caret(r_frac_from_pixels(button.position))
		else:
			dragging_station = -1
			_edit_open = false
		queue_redraw()
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if dragging_station >= 0:
			drag_station_to(dragging_station, motion.position)
		else:
			var was := hovered_station
			hovered_station = station_at(motion.position)
			if hovered_station != was:
				queue_redraw()


## Moves a station's chord to whatever `pixel` says, through `PlanformEdits`. Public because it is
## what a test drives: a gesture is a function call, not a synthesised event.
func drag_station_to(index: int, pixel: Vector2) -> void:
	if document == null:
		return
	var chord_mm := chord_from_pixels(pixel)
	var edited := PlanformEdits.set_chord(document.chord, index, chord_mm)
	if edited == document.chord:
		return
	document.chord = edited
	# An EDITED planform is no longer the generator's assumption about a catalog line. This is the
	# flag §3.1 puts on every figure derived from a generated planform, and clearing it here rather
	# than in the room's toggle is what makes the caveat honest: a builder who has drawn the blade
	# is no longer relying on the guess, whether or not they noticed a toggle.
	document.chord_is_assumed = false
	_edit_open = true
	queue_redraw()
	document_changed.emit(document)


## Moves the caret, clamped, and says so once.
func set_caret(r_frac: float) -> void:
	var clamped := clampf(r_frac, 0.0, 1.0)
	if is_equal_approx(clamped, caret_r_frac):
		return
	caret_r_frac = clamped
	queue_redraw()
	caret_moved.emit(caret_r_frac)


# ---------------------------------------------------------------------------
# Paint
# ---------------------------------------------------------------------------

func _draw() -> void:
	var inner := _inner_rect()
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)

	# The centreline, and the hub edge the blade actually starts at. The hub fraction is read from
	# the document rather than drawn at zero, because a blade does not begin at the shaft and a
	# picture that says it does invites a station nobody can reach.
	var centre_y := inner.position.y + inner.size.y * 0.5
	draw_line(Vector2(inner.position.x, centre_y), Vector2(inner.end.x, centre_y),
		LothalTheme.BORDER, 1.0)
	var hub_x := to_pixels(PropellerDocument.HUB_RADIUS_TO_RADIUS, 0.0).x
	draw_line(Vector2(hub_x, inner.position.y), Vector2(hub_x, inner.end.y),
		LothalTheme.BORDER, 1.0)

	if document == null:
		return

	var pts := PlanformEdits.points(document.chord)
	if pts.size() < 2:
		return

	# The blade itself: one closed polygon through the upper edge and back along the lower, which
	# is the planform a cutter would see.
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for point in pts:
		upper.append(to_pixels(float(point[0]), float(point[1])))
		lower.append(to_pixels(float(point[0]), -float(point[1])))
	var outline := PackedVector2Array(upper)
	for i in range(lower.size() - 1, -1, -1):
		outline.append(lower[i])
	draw_colored_polygon(outline, Color(LothalTheme.ACCENT, 0.18))
	draw_polyline(upper, LothalTheme.ACCENT, 1.5)
	draw_polyline(lower, LothalTheme.ACCENT, 1.5)

	# The caret: where the section view is looking.
	var caret_x := to_pixels(caret_r_frac, 0.0).x
	draw_line(Vector2(caret_x, inner.position.y), Vector2(caret_x, inner.end.y),
		LothalTheme.WARNING, 1.0)

	for i in pts.size():
		var at := to_pixels(float(pts[i][0]), float(pts[i][1]))
		var colour := LothalTheme.ACCENT if i != hovered_station else LothalTheme.BORDER_FOCUS
		draw_circle(at, STATION_RADIUS_PX, colour)
