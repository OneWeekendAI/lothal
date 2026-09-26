class_name PrintedDiagram
extends Control
## The drawing on a Printed part's item page (lab dock design §2, §3) — VideoDiagram's sibling.
## Read-only. It draws the part's OWN exported triangles (`PrintedParts.solid_for`, the solid the
## Export button writes), so what is drawn is what prints:
##
##   - PLAN (as it lies on the bed, X across, Y up the page) and SIDE (X across, Z up), to one
##     scale, each dimensioned with the solid's extent (`PrintedExport.bbox_mm`, the record's own).
##   - THE KEY FIT, when the part closes on a bought one (`PrintedFigures.fit`): a section through
##     the joint — the bought part inside the hole the generator cut for it — enlarged, with the
##     clearance dimensioned each side. Schematic in shape (a slab in a slot), true in its numbers.
##
## A part the build refuses is not drawn: its reason is the page's warning.

## The triangles, mm, as `solid_for` returns them; empty when refused.
var triangles: Array = []
## `PrintedExport.bbox_mm` of those triangles: [x, y, z].
var bbox: Array = []
## `PrintedFigures.fit`, or empty.
var fit: Dictionary = {}
var part_id := ""
var quantity := 1
var refused_reason := ""

## mm → px for both views, and each view's origin (the bbox's low corner, drawn bottom-left).
var _scale := 1.0
var _plan_origin := Vector2.ZERO
var _side_origin := Vector2.ZERO
var _low := Vector3.ZERO


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func show_part(build: Build, p_part_id: String) -> void:
	part_id = p_part_id
	triangles = []
	bbox = []
	fit = {}
	refused_reason = ""
	quantity = 1
	if build != null and part_id != "":
		var solid := PrintedParts.solid_for(build, part_id)
		quantity = int(solid["quantity"])
		if bool(solid["ok"]):
			triangles = solid["triangles"]
			bbox = PrintedExport.bbox_mm(triangles)
			fit = PrintedFigures.fit(build, part_id)
		else:
			refused_reason = str(solid["reason"])
	queue_redraw()


## The words the drawing puts on its dimensions, in order: plan width, plan depth, side height, and
## — with a fit — the bought part, the hole, and the clearance each side. For tests; `_draw` writes
## exactly these.
func dimension_labels() -> Array:
	var out: Array = []
	if bbox.size() != 3:
		return out
	out.append("%.1f mm" % float(bbox[0]))
	out.append("%.1f mm" % float(bbox[1]))
	out.append("%.1f mm" % float(bbox[2]))
	if not fit.is_empty():
		out.append("%s %.1f mm" % [str(fit["what"]), float(fit["part_mm"])])
		out.append("hole %.1f mm" % float(fit["hole_mm"]))
		out.append("%.2f mm each side" % ((float(fit["hole_mm"]) - float(fit["part_mm"])) * 0.5))
	return out


## Where a point of the solid lands in the plan view, px. For tests.
func plan_px(point_mm: Vector3) -> Vector2:
	return _plan_origin + Vector2(point_mm.x - _low.x, -(point_mm.y - _low.y)) * _scale


func side_px(point_mm: Vector3) -> Vector2:
	return _side_origin + Vector2(point_mm.x - _low.x, -(point_mm.z - _low.z)) * _scale


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if triangles.is_empty():
		_text(Vector2(16.0, 24.0), "Nothing to draw — this build cannot generate the part"
			if refused_reason != "" else "Nothing to print", LothalTheme.TEXT_FAINT)
		return
	var labels := dimension_labels()
	_fit_views()
	_text(Vector2(16.0, 20.0), "Plan on the bed · side · mm to scale%s" % (
		"" if quantity <= 1 else " · one of %d" % quantity), LothalTheme.TEXT_MUTED)
	_draw_view(true)
	_draw_view(false)
	var width := float(bbox[0]) * _scale
	var depth := float(bbox[1]) * _scale
	var height := float(bbox[2]) * _scale
	# Plan: width under it, depth to its left. Side: height to its left.
	_dimension(_plan_origin + Vector2(0.0, 14.0), _plan_origin + Vector2(width, 14.0), labels[0], true)
	_dimension(_plan_origin + Vector2(-14.0, 0.0), _plan_origin + Vector2(-14.0, -depth), labels[1], false)
	_dimension(_side_origin + Vector2(-14.0, 0.0), _side_origin + Vector2(-14.0, -height), labels[2], false)
	_text(_plan_origin + Vector2(0.0, -depth - 8.0), "Plan", LothalTheme.TEXT_MUTED)
	_text(_side_origin + Vector2(0.0, -height - 8.0), "Side", LothalTheme.TEXT_MUTED)
	if not fit.is_empty():
		_draw_fit(labels)


## One scale for both views, sized to the left of the fit detail (or the whole width without one).
func _fit_views() -> void:
	_low = Vector3(INF, INF, INF)
	for t in triangles:
		for p in t:
			_low = _low.min(p as Vector3)
	var detail := 0.0 if fit.is_empty() else minf(300.0, size.x * 0.38)
	var area := Rect2(Vector2(64.0, 56.0), Vector2(size.x - detail - 96.0, size.y - 120.0))
	var span := Vector2(float(bbox[0]), float(bbox[1]) + float(bbox[2]))
	_scale = minf(area.size.x / maxf(span.x, 1.0), (area.size.y - 60.0) / maxf(span.y, 1.0))
	_scale = clampf(_scale, 0.1, 12.0)
	var left := area.position.x + (area.size.x - float(bbox[0]) * _scale) * 0.5
	_plan_origin = Vector2(left, area.position.y + 20.0 + float(bbox[1]) * _scale)
	_side_origin = Vector2(left, _plan_origin.y + 60.0 + float(bbox[2]) * _scale)


func _draw_view(plan: bool) -> void:
	var fill := Color(LothalTheme.ACCENT, 0.22)
	for t in triangles:
		var points := PackedVector2Array()
		for p in t:
			points.append(plan_px(p) if plan else side_px(p))
		# Edge-on triangles project to a line; a zero-area polygon is skipped, not an error.
		if absf((points[1] - points[0]).cross(points[2] - points[0])) < 0.01:
			continue
		draw_colored_polygon(points, fill)


## The joint in section: the bought part (solid) in the printed hole (outlined), enlarged so the
## clearance shows, with the three numbers.
func _draw_fit(labels: Array) -> void:
	var panel := Rect2(Vector2(size.x - minf(300.0, size.x * 0.38) - 16.0, 56.0),
		Vector2(minf(300.0, size.x * 0.38), minf(260.0, size.y - 90.0)))
	draw_rect(panel, Color(LothalTheme.TEXT_FAINT, 0.08))
	_text(panel.position + Vector2(10.0, 20.0), "The fit, in section", LothalTheme.TEXT_MUTED)
	var hole := float(fit["hole_mm"])
	var part := float(fit["part_mm"])
	var px := (panel.size.x - 80.0) / maxf(hole, 0.1)
	var centre := panel.position + Vector2(panel.size.x * 0.5, panel.size.y * 0.55)
	var tall := panel.size.y * 0.42
	var hole_rect := Rect2(centre - Vector2(hole * px * 0.5, tall * 0.5), Vector2(hole * px, tall))
	var part_rect := Rect2(centre - Vector2(part * px * 0.5, tall * 0.5 - 6.0),
		Vector2(part * px, tall - 12.0))
	# The print around the hole: walls either side.
	draw_rect(Rect2(hole_rect.position - Vector2(24.0, 0.0), Vector2(24.0, tall)),
		Color(LothalTheme.ACCENT, 0.35))
	draw_rect(Rect2(Vector2(hole_rect.end.x, hole_rect.position.y), Vector2(24.0, tall)),
		Color(LothalTheme.ACCENT, 0.35))
	draw_rect(hole_rect, LothalTheme.ACCENT, false, 1.5)
	draw_rect(part_rect, Color(LothalTheme.TEXT_MUTED, 0.55))
	_text(Vector2(part_rect.position.x + 4.0, centre.y + 4.0), labels[3], LothalTheme.TEXT_MAIN)
	_dimension(Vector2(hole_rect.position.x, hole_rect.end.y + 16.0),
		Vector2(hole_rect.end.x, hole_rect.end.y + 16.0), labels[4], true)
	var gap_colour := LothalTheme.WARNING
	draw_line(Vector2(hole_rect.position.x, hole_rect.position.y - 10.0),
		Vector2(part_rect.position.x, hole_rect.position.y - 10.0), gap_colour, 2.0)
	draw_line(Vector2(part_rect.end.x, hole_rect.position.y - 10.0),
		Vector2(hole_rect.end.x, hole_rect.position.y - 10.0), gap_colour, 2.0)
	_text(Vector2(hole_rect.position.x, hole_rect.position.y - 18.0), labels[5], gap_colour)


## A dimension line with end ticks and its label: below a horizontal one, left of a vertical one.
func _dimension(a: Vector2, b: Vector2, label: String, horizontal: bool) -> void:
	var colour := LothalTheme.TEXT_MUTED
	draw_line(a, b, colour, 1.0)
	var tick := Vector2(0.0, 4.0) if horizontal else Vector2(4.0, 0.0)
	draw_line(a - tick, a + tick, colour, 1.0)
	draw_line(b - tick, b + tick, colour, 1.0)
	var mid := (a + b) * 0.5
	if horizontal:
		_text(mid + Vector2(-20.0, 16.0), label, LothalTheme.TEXT_MAIN)
	else:
		_text(mid + Vector2(-8.0, 4.0), label, LothalTheme.TEXT_MAIN, true)


func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	var y := clampf(at.y, 14.0, size.y - 4.0)
	var height := font.get_height(LothalTheme.FONT_SIZE_SMALL)
	draw_rect(Rect2(Vector2(x - 2.0, y - font.get_ascent(LothalTheme.FONT_SIZE_SMALL) - 1.0),
		Vector2(width + 4.0, height + 2.0)), Color(LothalTheme.SURFACE_BASE, 0.85))
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)
