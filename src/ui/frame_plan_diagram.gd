class_name FramePlanDiagram
extends Control
## The drawing on an Airframe item page (lab dock design §2; the mockup's frame-page canvas): the
## frame in plan, top view, nose up, with the page's own item picked out. Read-only — the frame
## designer is where a frame is drawn; this is where one is looked at.
##
## Three modes, one per row whose page carries `"diagram"` (SectionRows.DEFINITIONS):
##
##   - `arms`: the arm plates filled, everything else faint, one arm dimensioned.
##   - `hardware`: every standoff and screw where the document puts it, and the hole the joint
##     check flags ringed with its edge distance (FrameHardware.worst_edge_hole — the check's own
##     measurement, so the ring and the warning cannot disagree).
##   - `layout`: the pack and the fitted parts as the rectangles their clearance is measured from,
##     the prop discs they are measured against, and the closest gap marked in mm. That gap is
##     `closest_gap`, which is `AirframeModel.footprint_prop_clearance_m`'s arithmetic on the same
##     shapes: the picture and the row's number are one measurement (labs-and-sim.md §2.2).
##
## Plates are painted from `AirframeDocument.plate_outline`, the polygons the mass is integrated
## over — no display-only shape (FramePlanEditor's rule).

const MODE_ARMS := "arms"
const MODE_HARDWARE := "hardware"
const MODE_LAYOUT := "layout"

const MARGIN_PX := 36.0

var document: AirframeDocument
var mode := ""
## Layout mode: `{centre: Vector2, radius}` mm (AirframeModel.prop_discs_mm).
var discs: Array = []
## Layout mode: `{label, rect: Rect2}` mm (AirframeModel.plan_parts_mm).
var parts: Array = []
## Hardware mode: `{centre_mm, distance_mm}` of the hole the edge check flags, or `{}`.
var flagged_hole: Dictionary = {}

var _xf := PlanTransform.new()


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


## Points the drawing at a document in one mode. `extras` carries `discs` and `parts` for layout.
func show_plan(p_document: AirframeDocument, p_mode: String, extras: Dictionary = {}) -> void:
	document = p_document
	mode = p_mode
	discs = extras.get("discs", [])
	parts = extras.get("parts", [])
	flagged_hole = {}
	if mode == MODE_HARDWARE and document != null:
		var worst := FrameHardware.worst_edge_hole(document)
		var screws := FrameHardware.items_of_kind(document, "screw")
		if not worst.is_empty() and not screws.is_empty():
			var thread := float((screws[0] as Dictionary).get("thread_d_mm", 0.0))
			if float(worst["distance_mm"]) < HardwareMass.EDGE_DISTANCE_RATIO * thread:
				flagged_hole = worst
	queue_redraw()


## The smallest gap between any part rectangle and any disc, `{label, mm, from, to}` in mm: `from`
## on the part, `to` on the disc's rim. Negative mm is inside the disc. `{}` with nothing to measure.
##
## The per-axis arithmetic of `AirframeModel.footprint_prop_clearance_m`, restated on mm shapes —
## the distance from the hub to the nearest point of the rectangle, less the radius.
static func closest_gap(part_list: Array, disc_list: Array) -> Dictionary:
	var best := {}
	for part in part_list:
		var rect: Rect2 = part["rect"]
		for disc in disc_list:
			var centre: Vector2 = disc["centre"]
			var near := centre.clamp(rect.position, rect.end)
			var gap := centre.distance_to(near) - float(disc["radius"])
			if best.is_empty() or gap < float(best["mm"]):
				var direction := (near - centre).normalized() if near != centre else Vector2.UP
				best = {"label": part["label"], "mm": gap, "from": near,
					"to": centre + direction * float(disc["radius"])}
	return best


func _bounds_mm() -> Rect2:
	var box := Rect2()
	var first := true
	if document != null:
		for plate in document.plates:
			for point in AirframeDocument.plate_outline(plate):
				box = Rect2(point, Vector2.ZERO) if first else box.expand(point)
				first = false
	for disc in discs:
		var r := float(disc["radius"])
		var c: Vector2 = disc["centre"]
		for corner in [c - Vector2(r, r), c + Vector2(r, r)]:
			box = Rect2(corner, Vector2.ZERO) if first else box.expand(corner)
			first = false
	for part in parts:
		var rect: Rect2 = part["rect"]
		box = rect if first else box.merge(rect)
		first = false
	if first:
		return Rect2(Vector2(-100, -100), Vector2(200, 200))
	return box


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var box := _bounds_mm()
	_xf.fit(box.position, box.end, size, MARGIN_PX)
	_draw_grid()
	if document != null:
		for plate in document.plates:
			_draw_plate(plate)
	match mode:
		MODE_ARMS:
			_draw_arm_dimension()
		MODE_HARDWARE:
			_draw_hardware()
		MODE_LAYOUT:
			_draw_layout()
	_draw_scale()


func _draw_grid() -> void:
	var step := _xf.grid_step_mm(14.0)
	var colour := Color(LothalTheme.BORDER, 0.5)
	var top_left := _xf.to_mm(Vector2.ZERO)
	var bottom_right := _xf.to_mm(size)
	var x: float = floor(top_left.x / step) * step
	while x <= bottom_right.x:
		var px := _xf.to_pixels(Vector2(x, 0.0)).x
		draw_line(Vector2(px, 0.0), Vector2(px, size.y), colour, 1.0)
		x += step
	var y: float = floor(top_left.y / step) * step
	while y <= bottom_right.y:
		var py := _xf.to_pixels(Vector2(0.0, y)).y
		draw_line(Vector2(0.0, py), Vector2(size.x, py), colour, 1.0)
		y += step


func _screen(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(_xf.to_pixels(point))
	return out


func _draw_plate(plate: Dictionary) -> void:
	var outline := _screen(AirframeDocument.plate_outline(plate))
	if outline.size() < 3:
		return
	var is_arm := str(plate.get("role", "")) == AirframeDocument.ROLE_ARM
	# The page's item is the only thing in colour; the rest of the frame is context.
	var lit := (mode == MODE_ARMS and is_arm)
	var base := LothalTheme.ACCENT if lit else LothalTheme.TEXT_MUTED
	draw_colored_polygon(outline, Color(base, 0.30 if lit else 0.10))
	draw_polyline(_closed(outline), Color(base, 0.95 if lit else 0.45), 1.5 if lit else 1.0)
	for hole in AirframeDocument.plate_holes(plate):
		var ring := _screen(hole)
		if ring.size() >= 3:
			draw_colored_polygon(ring, LothalTheme.SURFACE_BASE)
			draw_polyline(_closed(ring), Color(base, 0.5), 1.0)


## One arm, dimensioned root to tip: the length the Arms sheet's beam is measured along.
func _draw_arm_dimension() -> void:
	for plate in FrameHardware.arm_plates(document):
		if not plate.has("root_point") or not plate.has("tip_point"):
			continue
		var root := AirframeDocument.point_of(plate["root_point"])
		var tip := AirframeDocument.point_of(plate["tip_point"])
		var a := _xf.to_pixels(root)
		var b := _xf.to_pixels(tip)
		draw_dashed_line(a, b, LothalTheme.WARNING, 1.5, 6.0)
		_label((a + b) * 0.5 + Vector2(10, -6), "arm %d mm" % roundi(root.distance_to(tip)),
			LothalTheme.WARNING)
		return


func _draw_hardware() -> void:
	for item in FrameHardware.standoffs(document):
		var at := _xf.to_pixels(AirframeDocument.point_of(item.get("position_mm", [0.0, 0.0])))
		var r := maxf(float(item.get("outer_d_mm", item.get("across_flats_mm", 5.0))) * 0.5
			* _xf.scale_px_per_mm, 3.0)
		draw_circle(at, r, Color(LothalTheme.ACCENT, 0.35))
		draw_arc(at, r, 0.0, TAU, 24, LothalTheme.ACCENT, 1.5)
	for item in FrameHardware.items_of_kind(document, "screw"):
		var at := _xf.to_pixels(AirframeDocument.point_of(item.get("position_mm", [0.0, 0.0])))
		var r := maxf(float(item.get("head_d_mm", 5.0)) * 0.5 * _xf.scale_px_per_mm, 2.0)
		draw_arc(at, r, 0.0, TAU, 16, LothalTheme.TEXT_MAIN, 1.0)
	if not flagged_hole.is_empty():
		var at := _xf.to_pixels(flagged_hole["centre_mm"])
		draw_arc(at, 14.0, 0.0, TAU, 32, LothalTheme.WARNING, 2.0)
		_label(at + Vector2(18, 4), "%.1f mm to edge" % float(flagged_hole["distance_mm"]),
			LothalTheme.WARNING)


func _draw_layout() -> void:
	for disc in discs:
		var c := _xf.to_pixels(disc["centre"])
		var r := float(disc["radius"]) * _xf.scale_px_per_mm
		draw_circle(c, r, Color(LothalTheme.TEXT_MUTED, 0.06))
		draw_arc(c, r, 0.0, TAU, 64, Color(LothalTheme.TEXT_MUTED, 0.6), 1.0)
	var gap := closest_gap(parts, discs)
	for part in parts:
		var rect: Rect2 = part["rect"]
		var a := _xf.to_pixels(rect.position)
		var b := _xf.to_pixels(rect.end)
		var screen := Rect2(a, b - a).abs()
		var closest: bool = not gap.is_empty() and part["label"] == gap["label"]
		var colour := LothalTheme.ACCENT if not closest else _gap_colour(float(gap["mm"]))
		draw_rect(screen, Color(colour, 0.22))
		draw_rect(screen, Color(colour, 0.9), false, 1.5)
		if part["label"] == "pack" or closest:
			_label(screen.position + Vector2(4, 14), str(part["label"]), colour)
	if not gap.is_empty():
		var colour := _gap_colour(float(gap["mm"]))
		var from := _xf.to_pixels(gap["from"])
		var to := _xf.to_pixels(gap["to"])
		draw_line(from, to, colour, 2.0)
		draw_circle(from, 3.0, colour)
		draw_circle(to, 3.0, colour)
		_label((from + to) * 0.5 + Vector2(8, -8), "%d mm" % roundi(float(gap["mm"])), colour)


static func _gap_colour(mm: float) -> Color:
	if mm < 0.0:
		return LothalTheme.DANGER
	if mm < AirframeModel.TIGHT_PROP_CLEARANCE_MM:
		return LothalTheme.WARNING
	return LothalTheme.SUCCESS


func _draw_scale() -> void:
	var step := _xf.grid_step_mm(14.0)
	var text := "Top view · nose up · 1 grid = %s mm" % _trim(step)
	var width := LothalTheme.draw_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	# On a backing, so the caption is not read through the grid lines.
	draw_rect(Rect2(Vector2(6, size.y - 26), Vector2(width + 12, 20)), LothalTheme.SURFACE_BASE)
	_label(Vector2(12, size.y - 12), text, LothalTheme.TEXT_MUTED)


## A label kept inside the canvas: one that would run off the right edge is set to the left of
## its anchor instead, so "1.9 mm to edge" on a right-hand motor pad is read, not clipped.
func _label(at: Vector2, text: String, colour: Color) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := at.x
	if x + width > size.x - 6.0:
		x = maxf(6.0, at.x - width - 36.0)
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
