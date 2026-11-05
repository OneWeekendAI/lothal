class_name PropTunnelChart
extends Control
## One line against J. Solid while the model is inside its reach, dashed where a point is flagged,
## and it draws only what it is given, so a refusal is an empty frame. Dots are measured rows.
## Monochrome: a flagged stretch is dashes, not a colour.

const PAD := Vector4(44.0, 18.0, 12.0, 20.0)
const DOT_R := 3.0
const DASH := 6.0
const GAP := 5.0

## [{x, y, flagged}], in order.
var points: Array = []
var dots := PackedVector2Array()
var unit := ""
var caret_x := -1.0
## The second prop's line, the same shape as `points`; [] for none. Legend names go with it.
var compare_points: Array = []
var legend_names := PackedStringArray()


func set_data(p_points: Array, p_dots: PackedVector2Array, p_unit: String, p_caret_x: float) -> void:
	points = p_points
	dots = p_dots
	unit = p_unit
	caret_x = p_caret_x
	queue_redraw()


## The segments as drawn: a segment is dashed if either end is flagged. `[count solid, count dashed]`.
func segment_counts() -> Vector2i:
	var out := Vector2i.ZERO
	for i in range(1, points.size()):
		if _flagged(i):
			out.y += 1
		else:
			out.x += 1
	return out


## What the frame must hold: x from 0, y from 0 or lower, the line and every dot.
func data_range() -> Rect2:
	var x_max := 0.05
	var y_min := 0.0
	var y_max := 0.0
	for p: Dictionary in points:
		x_max = maxf(x_max, float(p.x))
		y_min = minf(y_min, float(p.y))
		y_max = maxf(y_max, float(p.y))
	for p: Dictionary in compare_points:
		x_max = maxf(x_max, float(p.x))
		y_min = minf(y_min, float(p.y))
		y_max = maxf(y_max, float(p.y))
	for d in dots:
		x_max = maxf(x_max, d.x)
		y_min = minf(y_min, d.y)
		y_max = maxf(y_max, d.y)
	if y_max <= y_min:
		y_max = y_min + 1.0
	return Rect2(0.0, y_min, x_max, y_max - y_min)


func set_compare(p_points: Array, names: PackedStringArray) -> void:
	compare_points = p_points
	legend_names = names
	queue_redraw()


func _flagged(i: int) -> bool:
	return bool(points[i].flagged) or bool(points[i - 1].flagged)


func _draw() -> void:
	var plot := Rect2(PAD.x, PAD.y, size.x - PAD.x - PAD.z, size.y - PAD.y - PAD.w)
	draw_rect(plot, DesignSpace.INK_FAINT, false, 1.0)
	var font := get_theme_default_font()
	var fs := LothalTheme.FONT_SIZE_SMALL
	if points.is_empty():
		return
	var r := data_range()
	var x_max := r.size.x
	var y_min := r.position.y
	var y_max := r.end.y
	var to_px := func(x: float, y: float) -> Vector2:
		return Vector2(plot.position.x + x / x_max * plot.size.x,
			plot.end.y - (y - y_min) / (y_max - y_min) * plot.size.y)

	draw_string(font, Vector2(2, plot.position.y + fs), _num(y_max), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 4, fs, DesignSpace.INK_MUTED)
	draw_string(font, Vector2(2, plot.end.y), _num(y_min), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 4, fs, DesignSpace.INK_MUTED)
	draw_string(font, Vector2(plot.position.x, plot.position.y - 5), unit, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x, fs, DesignSpace.INK_MUTED)
	draw_string(font, Vector2(plot.position.x, plot.position.y - 5), "line: model" + (", dots: measured" if not dots.is_empty() else ""),
		HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x, fs, DesignSpace.INK_MUTED)
	draw_string(font, Vector2(plot.position.x, plot.end.y + fs + 2), "J 0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignSpace.INK_MUTED)
	draw_string(font, Vector2(plot.position.x, plot.end.y + fs + 2), "%.2f" % x_max, HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x, fs, DesignSpace.INK_MUTED)

	if caret_x >= 0.0:
		var cx: float = (to_px.call(caret_x, y_min) as Vector2).x
		draw_line(Vector2(cx, plot.position.y), Vector2(cx, plot.end.y), DesignSpace.INK_FAINT, 1.0)
	_draw_series(compare_points, MotorDesigner.COMPARE_INK, MotorDesigner.COMPARE_INK, to_px)
	_draw_series(points, DesignSpace.INK, DesignSpace.INK_MUTED, to_px)
	if legend_names.size() == 2:
		# On the title row: any spot inside the plot sits on some metric's curve.
		var y := plot.position.y - 5
		var w := (plot.size.x - 140.0) * 0.5
		draw_string(font, Vector2(plot.position.x + 62, y), legend_names[0], HORIZONTAL_ALIGNMENT_LEFT, w, fs, DesignSpace.INK)
		draw_string(font, Vector2(plot.position.x + 66 + w, y), legend_names[1], HORIZONTAL_ALIGNMENT_LEFT, w, fs, MotorDesigner.COMPARE_INK)
	for d in dots:
		draw_arc(to_px.call(d.x, d.y), DOT_R, 0.0, TAU, 12, DesignSpace.INK, 1.0, true)


## One prop's line. The dash phase carries across points: dashing each short segment on its own reads
## as solid.
func _draw_series(series: Array, ink: Color, flagged_ink: Color, to_px: Callable) -> void:
	var walked := 0.0
	for i in range(1, series.size()):
		var a: Vector2 = to_px.call(float(series[i - 1].x), float(series[i - 1].y))
		var b: Vector2 = to_px.call(float(series[i].x), float(series[i].y))
		if not (bool(series[i - 1].flagged) or bool(series[i].flagged)):
			draw_line(a, b, ink, 1.5, true)
			continue
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			var phase := fmod(walked + at, DASH + GAP)
			var run := DASH - phase if phase < DASH else DASH + GAP - phase
			run = minf(run, length - at)
			if phase < DASH:
				draw_line(a.lerp(b, at / length), a.lerp(b, (at + run) / length), flagged_ink, 1.5, true)
			at += maxf(run, 0.01)
		walked += length


static func _num(v: float) -> String:
	return "%.0f" % v if absf(v) >= 10.0 else "%.2f" % v
