class_name PackCharts
extends Control
## The bench's charts: a short stack of plain line charts that draw themselves in over `reveal`
## (0 to 1, tweened over about three seconds by the pop-up) and then stay on screen, static.
## Calm on purpose: one hairline frame, one line each, the range on the left and the end value on
## the right. Nothing animates once reveal is 1.

const MAX_POINTS := 240
const PAD_L := 40.0
const PAD_R := 56.0
const PAD_T := 16.0
const PAD_B := 4.0
const GAP := 6.0

## Each chart: {title, x: PackedFloat64Array (seconds), y: PackedFloat64Array, y_min, y_max,
## unit, color, x_max (optional, seconds)}.
var charts: Array = []
var reveal := 1.0:
	set(v):
		reveal = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	name = "PackCharts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 150)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_charts(p_charts: Array) -> void:
	charts = p_charts
	queue_redraw()


## The fraction of each chart's points that are drawn now, for tests (1 once the reveal is done).
func visible_fraction() -> float:
	return reveal


func _draw() -> void:
	var n := charts.size()
	if n == 0 or size.x < 10.0 or size.y < 10.0:
		return
	var h := (size.y - GAP * float(n - 1)) / float(n)
	for k in n:
		_draw_chart(charts[k], Rect2(0.0, (h + GAP) * float(k), size.x, h))


func _draw_chart(c: Dictionary, area: Rect2) -> void:
	var font := LothalTheme.draw_font()
	var small := LothalTheme.FONT_SIZE_SMALL - 1
	draw_rect(area, LothalTheme.PANEL_SUNKEN)
	draw_rect(area, LothalTheme.BORDER, false, 1.0)
	var plot := Rect2(area.position + Vector2(PAD_L, PAD_T), area.size - Vector2(PAD_L + PAD_R, PAD_T + PAD_B))
	draw_string(font, area.position + Vector2(8.0, 12.0), String(c.get("title", "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, small, LothalTheme.TEXT_MUTED)
	var xs: PackedFloat64Array = c.get("x", PackedFloat64Array())
	var ys: PackedFloat64Array = c.get("y", PackedFloat64Array())
	if xs.size() < 2 or plot.size.x < 4.0 or plot.size.y < 4.0:
		return
	var y_min := float(c.get("y_min", 0.0))
	var y_max := float(c.get("y_max", 1.0))
	var span_y := maxf(y_max - y_min, 1e-9)
	var x_max := maxf(float(c.get("x_max", xs[xs.size() - 1])), 1e-9)
	var unit := String(c.get("unit", ""))
	# The range, on the left; the faint baseline.
	draw_string(font, Vector2(area.position.x + 4.0, plot.position.y + 8.0), _num(y_max),
		HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 8.0, small, LothalTheme.TEXT_FAINT)
	draw_string(font, Vector2(area.position.x + 4.0, plot.end.y), _num(y_min),
		HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 8.0, small, LothalTheme.TEXT_FAINT)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, LothalTheme.BORDER_STRONG, 1.0)
	# The time axis end, so "how long" is readable without a legend.
	draw_string(font, Vector2(plot.end.x - 60.0, area.position.y + 12.0), _time(x_max),
		HORIZONTAL_ALIGNMENT_RIGHT, 64.0, small, LothalTheme.TEXT_FAINT)

	var stride := maxi(1, int(ceil(float(xs.size()) / float(MAX_POINTS))))
	var upto := int(floor(reveal * float(xs.size() - 1)))
	var pts := PackedVector2Array()
	var i := 0
	while i <= upto:
		pts.append(_to_plot(plot, xs[i], ys[i], x_max, y_min, span_y))
		i += stride
	if (upto % stride) != 0 or pts.size() == 0:
		pts.append(_to_plot(plot, xs[upto], ys[upto], x_max, y_min, span_y))
	if pts.size() >= 2:
		draw_polyline(pts, c.get("color", LothalTheme.ACCENT), 1.6, true)
	var tip := pts[pts.size() - 1]
	draw_circle(tip, 2.5, c.get("color", LothalTheme.ACCENT))
	draw_string(font, Vector2(plot.end.x + 6.0, clampf(tip.y + 4.0, plot.position.y + 8.0, plot.end.y)),
		"%s%s" % [_num(ys[upto]), unit], HORIZONTAL_ALIGNMENT_LEFT, PAD_R - 6.0, small, LothalTheme.TEXT_MAIN)


static func _to_plot(plot: Rect2, x: float, y: float, x_max: float, y_min: float, span_y: float) -> Vector2:
	return Vector2(plot.position.x + plot.size.x * clampf(x / x_max, 0.0, 1.0),
		plot.end.y - plot.size.y * clampf((y - y_min) / span_y, 0.0, 1.0))


static func _num(v: float) -> String:
	if absf(v) < 0.005:
		return "0"
	if absf(v) >= 100.0:
		return "%.0f" % v
	if absf(v) >= 10.0:
		return "%.1f" % v
	return "%.2f" % v


static func _time(s: float) -> String:
	if s >= 5400.0:
		return "%.1f h" % (s / 3600.0)
	if s >= 120.0:
		return "%.0f min" % (s / 60.0)
	return "%.0f s" % s
