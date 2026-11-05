class_name PropTwistEditor
extends Control
## The blade angle against radius, editable, for the prop designer. A helix blade shows its helix at
## fixed stations; the first drag turns that into an authored table. The vertical axis is fixed, so
## a point stays under the cursor while it is dragged.

signal document_changed(document: PropellerDocument)
signal caret_moved(r_frac: float)
## Fires once per gesture, before the first change, so a drag is one undo step.
signal edit_began()

const MAX_DEG := 85.0
const MARGIN_PX := 14.0
const GRAB_RADIUS_PX := 9.0
const STATION_RADIUS_PX := 3.5

var document: PropellerDocument
var ink := DesignSpace.INK
var caret_r_frac := 0.7
var dragging_station := -1
var _edit_open := false


func _init(p_document: PropellerDocument = null) -> void:
	document = p_document
	custom_minimum_size = Vector2(260, 104)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_document(p_document: PropellerDocument) -> void:
	document = p_document
	dragging_station = -1
	_edit_open = false
	queue_redraw()


## What the canvas draws: the authored table, or the helix sampled.
func table() -> PackedFloat64Array:
	var flown := document.flown_twist()
	return flown if not flown.is_empty() else PlanformEdits.helix_table(document)


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


func to_pixels(r_frac: float, beta_deg: float) -> Vector2:
	var inner := _inner_rect()
	return Vector2(inner.position.x + inner.size.x * clampf(r_frac, 0.0, 1.0),
		inner.end.y - inner.size.y * beta_deg / MAX_DEG)


func deg_from_pixels(pixel: Vector2) -> float:
	var inner := _inner_rect()
	return clampf((inner.end.y - pixel.y) / inner.size.y * MAX_DEG, 0.0, MAX_DEG)


func r_frac_from_pixels(pixel: Vector2) -> float:
	var inner := _inner_rect()
	return clampf((pixel.x - inner.position.x) / inner.size.x, 0.0, 1.0)


func station_at(pixel: Vector2) -> int:
	if document == null:
		return -1
	var pts := PlanformEdits.points(table())
	var best := -1
	var best_distance := GRAB_RADIUS_PX
	for i in pts.size():
		var distance := to_pixels(float(pts[i][0]), rad_to_deg(float(pts[i][1]))).distance_to(pixel)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		_edit_open = false
		dragging_station = station_at(button.position) if button.pressed else -1
		if button.pressed and dragging_station < 0:
			set_caret(r_frac_from_pixels(button.position))
	elif event is InputEventMouseMotion and dragging_station >= 0:
		drag_station_to(dragging_station, (event as InputEventMouseMotion).position)


func drag_station_to(index: int, pixel: Vector2) -> void:
	if document == null:
		return
	var base := table()
	var edited := PlanformEdits.set_chord(base, index, deg_to_rad(deg_from_pixels(pixel)))
	if edited == base:
		return
	if not _edit_open:
		edit_began.emit()
	document.twist = edited
	document.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED
	_edit_open = true
	queue_redraw()
	document_changed.emit(document)


func set_caret(r_frac: float) -> void:
	var clamped := clampf(r_frac, 0.0, 1.0)
	if is_equal_approx(clamped, caret_r_frac):
		return
	caret_r_frac = clamped
	queue_redraw()
	caret_moved.emit(caret_r_frac)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	var inner := _inner_rect()
	draw_line(Vector2(inner.position.x, inner.end.y), inner.end, LothalTheme.BORDER, 1.0)
	if document == null:
		return
	var line := PackedVector2Array()
	for point in PlanformEdits.points(table()):
		line.append(to_pixels(float(point[0]), rad_to_deg(float(point[1]))))
	if line.size() >= 2:
		draw_polyline(line, ink, 1.5)
	var caret_x := to_pixels(caret_r_frac, 0.0).x
	draw_line(Vector2(caret_x, inner.position.y), Vector2(caret_x, inner.end.y), DesignSpace.INK_MUTED, 1.0)
	for at in line:
		draw_circle(at, STATION_RADIUS_PX, ink)
	draw_string(LothalTheme.draw_font(), Vector2(4, 11), "%d°" % int(MAX_DEG), HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_FAINT)
