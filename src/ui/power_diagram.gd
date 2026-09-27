class_name PowerDiagram
extends Control
## The drawing on the Battery and ESC item pages (lab dock design §2, §3) — PropulsionDiagram's
## sibling. Read-only; every figure comes from `PowerFigures`, the same calls the row and the
## page's two numbers read, so the picture cannot disagree with them. (The Harness page draws
## `HarnessSchematic`, the designer's own view.)
##
##   - `pack` (Battery): pack voltage against total current — the load lines of a fresh pack and of
##     the nominal datum (`rest - I*R`), the pack's rated continuous current as a wall with the
##     region past it shaded, and where this build sits on them: hover, the flight-profile average
##     (with the flight time it gives), and full throttle on each line.
##   - `esc` (ESC): one channel, in amps — the board's continuous rating, what the motors can ask
##     at their own limit, what this pack drives at full throttle, the burst rating as a tick
##     marked "not modelled", and the headroom between the motors' ask and the rating.

const MODE_PACK := "pack"
const MODE_ESC := "esc"

const MARGIN_PX := 44.0

var mode := ""

# Pack
var fresh_v := 0.0
var nominal_v := 0.0
var limit_a := 0.0
var max_a := 0.0
var fresh_line: Array = []
var nominal_line: Array = []
## `{label, amps, volts, fresh}` per marked operating point.
var points: Array = []
var r_ohm := 0.0

# ESC
## `{label, amps}` per bar, top to bottom.
var bars: Array = []
var burst_a := 0.0
var rating_a := 0.0
var motor_max_a := 0.0
var headroom_a := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func show_build(build: Build, p_mode: String) -> void:
	mode = p_mode
	fresh_line = []
	nominal_line = []
	points = []
	bars = []
	if build == null:
		queue_redraw()
		return
	match mode:
		MODE_PACK:
			fresh_v = PowerFigures.fresh_rest_v(build)
			nominal_v = PowerFigures.nominal_v(build)
			r_ohm = PowerFigures.internal_r_ohm(build)
			limit_a = PowerFigures.pack_limit_a(build)
			var worst := PowerFigures.worst_draw_a(build)
			max_a = maxf(limit_a, worst) * 1.15
			fresh_line = PowerFigures.load_line(build, fresh_v, max_a)
			nominal_line = PowerFigures.load_line(build, nominal_v, max_a)
			var hover := PowerFigures.hover_draw_a(build)
			var flight := PowerFigures.flight_draw_a(build)
			var nominal_ft := PowerFigures.nominal_full_throttle_a(build)
			if hover > 0.0:
				points.append({"label": "hover %d A" % roundi(hover), "amps": hover,
					"volts": nominal_v - hover * r_ohm, "fresh": false})
			if flight > 0.0:
				var seconds := roundi(build.flight_time_min() * 60.0)
				points.append({"label": "flying %d A · ~%d:%02d" % [roundi(flight),
						floori(seconds / 60.0), seconds % 60],
					"amps": flight, "volts": nominal_v - flight * r_ohm, "fresh": false})
			points.append({"label": "full throttle %d A" % roundi(nominal_ft), "amps": nominal_ft,
				"volts": nominal_v - nominal_ft * r_ohm, "fresh": false})
			points.append({"label": "full throttle, fresh %s A" % PowerFigures.amps_text(worst), "amps": worst,
				"volts": fresh_v - worst * r_ohm, "fresh": true})
		MODE_ESC:
			var channel := PowerFigures.esc_channel(build)
			rating_a = float(channel["rating"])
			burst_a = float(channel["burst"])
			motor_max_a = float(channel["motor_max"])
			headroom_a = float(channel["headroom"])
			bars = [{"label": "Rated, continuous", "amps": rating_a},
				{"label": "Motors' max", "amps": motor_max_a},
				{"label": "Full throttle, this pack", "amps": float(channel["drawn"])}]
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match mode:
		MODE_PACK:
			_draw_pack()
		MODE_ESC:
			_draw_esc()


# ---------------------------------------------------------------------------
# Pack voltage against current
# ---------------------------------------------------------------------------

func _pack_plot() -> Rect2:
	return Rect2(Vector2(MARGIN_PX + 10.0, 30.0),
		size - Vector2(MARGIN_PX + 10.0 + 24.0, 30.0 + MARGIN_PX))


func _pack_volts_range() -> Vector2:
	var low := nominal_v - max_a * r_ohm
	return Vector2(floorf(low - 0.5), ceilf(fresh_v + 0.3))


func _pack_px(amps: float, volts: float) -> Vector2:
	var plot := _pack_plot()
	var range_v := _pack_volts_range()
	return Vector2(plot.position.x + amps / max_a * plot.size.x,
		plot.end.y - (volts - range_v.x) / (range_v.y - range_v.x) * plot.size.y)


func _draw_pack() -> void:
	if fresh_line.is_empty() or max_a <= 0.0:
		return
	var plot := _pack_plot()
	var range_v := _pack_volts_range()
	var grid := Color(LothalTheme.BORDER, 0.6)
	var step_a := PropulsionDiagram._round_step(max_a / 5.0)
	var a := 0.0
	while a <= max_a:
		var x := _pack_px(a, range_v.x).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid, 1.0)
		_text(Vector2(x - 10.0, plot.end.y + 16.0), "%d A" % roundi(a), LothalTheme.TEXT_MUTED)
		a += step_a
	var step_v := PropulsionDiagram._round_step((range_v.y - range_v.x) / 5.0)
	var v := range_v.x
	while v <= range_v.y + 0.001:
		var y := _pack_px(0.0, v).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
		_text(Vector2(4.0, y + 4.0), "%s V" % _trim(v), LothalTheme.TEXT_MUTED)
		v += step_v
	_text(Vector2(plot.position.x, plot.end.y + 34.0),
		"Pack voltage vs total current · sag = I × %d mΩ" % roundi(r_ohm * 1000.0),
		LothalTheme.TEXT_MUTED)

	# The rating: a wall, and past it shaded — the pack is asked for more than it is rated to give.
	var lx := _pack_px(limit_a, range_v.x).x
	draw_rect(Rect2(Vector2(lx, plot.position.y), Vector2(plot.end.x - lx, plot.size.y)),
		Color(LothalTheme.DANGER, 0.08))
	draw_line(Vector2(lx, plot.position.y), Vector2(lx, plot.end.y), LothalTheme.WARNING, 1.5)
	# At the foot of the wall, left of it: the key holds the top left, the lines the middle.
	_text(Vector2(lx - 6.0, plot.end.y - 8.0), "rated %s A continuous" % rating_text(),
		LothalTheme.WARNING, true)

	_polyline(fresh_line, LothalTheme.TEXT_MAIN)
	_polyline(nominal_line, LothalTheme.ACCENT)
	# The two lines named in a key at the top left, clear of the points on them.
	var key := plot.position + Vector2(10.0, 14.0)
	draw_line(key + Vector2(0.0, -4.0), key + Vector2(18.0, -4.0), LothalTheme.TEXT_MAIN, 2.0)
	_text(key + Vector2(24.0, 0.0), "fresh pack, %s V at rest" % _trim(fresh_v),
		LothalTheme.TEXT_MAIN)
	draw_line(key + Vector2(0.0, 14.0), key + Vector2(18.0, 14.0), LothalTheme.ACCENT, 2.0)
	_text(key + Vector2(24.0, 18.0), "nominal, %s V — what the stats quote" % _trim(nominal_v),
		LothalTheme.ACCENT)

	# The operating points. Hover and the flight average sit close together at the left: their
	# labels stack above the nominal line on short leaders, where no line runs. Full-throttle
	# labels sit below-left of their dots (the falling line is above there), short of the wall.
	var stacked := 0
	for point in points:
		var at := _pack_px(float(point["amps"]), float(point["volts"]))
		var colour := LothalTheme.TEXT_MAIN if bool(point["fresh"]) else LothalTheme.ACCENT
		draw_circle(at, 4.0, colour)
		var label := str(point["label"])
		if label.begins_with("full throttle"):
			_text(Vector2(minf(at.x - 10.0, lx - 6.0), at.y + 18.0), label, colour, true)
			continue
		var anchor := at + Vector2(12.0, -34.0 + 16.0 * float(stacked))
		draw_line(at, anchor + Vector2(-3.0, -4.0), Color(colour, 0.6), 1.0)
		_text(anchor, label, colour)
		stacked += 1


## The pack's rating as the sheet prints it ("%.0f", so 112.5 A reads 112 A on both).
func rating_text() -> String:
	return "%.0f" % limit_a


func _polyline(line: Array, colour: Color) -> void:
	var drawn := PackedVector2Array()
	for point in line:
		drawn.append(_pack_px((point as Vector2).x, (point as Vector2).y))
	draw_polyline(drawn, colour, 2.0, true)


# ---------------------------------------------------------------------------
# One ESC channel
# ---------------------------------------------------------------------------

func _draw_esc() -> void:
	if bars.is_empty():
		return
	var top := 0.0
	for bar in bars:
		top = maxf(top, float(bar["amps"]))
	top = maxf(top, burst_a) * 1.12
	if top <= 0.0:
		return
	var left := 170.0
	var plot := Rect2(Vector2(left, 40.0), Vector2(size.x - left - 30.0, size.y - 40.0 - 70.0))
	var to_x := func(amps: float) -> float: return plot.position.x + amps / top * plot.size.x
	var grid := Color(LothalTheme.BORDER, 0.6)
	var step := PropulsionDiagram._round_step(top / 5.0)
	var a := 0.0
	while a <= top:
		var x: float = to_x.call(a)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid, 1.0)
		_text(Vector2(x - 8.0, plot.end.y + 16.0), "%d A" % roundi(a), LothalTheme.TEXT_MUTED)
		a += step
	_text(Vector2(12.0, plot.end.y + 40.0), "One ESC channel (one motor) · amps",
		LothalTheme.TEXT_MUTED)

	# Rows capped in height, so the three bars read as one comparison rather than three islands.
	var row_h := minf(plot.size.y / float(bars.size()), 90.0)
	var bar_h := minf(row_h * 0.45, 34.0)
	var colours := [LothalTheme.TEXT_MAIN, LothalTheme.ACCENT, Color(LothalTheme.ACCENT, 0.55)]
	var centres: Array = []
	for i in bars.size():
		var bar: Dictionary = bars[i]
		var cy := plot.position.y + row_h * (float(i) + 0.5)
		centres.append(cy)
		var x_end: float = to_x.call(float(bar["amps"]))
		draw_rect(Rect2(Vector2(plot.position.x, cy - bar_h * 0.5),
			Vector2(x_end - plot.position.x, bar_h)), colours[i])
		_text(Vector2(12.0, cy + 4.0), str(bar["label"]), LothalTheme.TEXT_MAIN)
		_text(Vector2(x_end + 6.0, cy + 4.0), "%d A" % roundi(float(bar["amps"])), colours[i])

	# Burst: carried, not a limit anywhere — a dashed tick through the rating's bar.
	if burst_a > 0.0:
		var bx: float = to_x.call(burst_a)
		draw_dashed_line(Vector2(bx, plot.position.y), Vector2(bx, plot.end.y),
			LothalTheme.TEXT_MUTED, 1.0, 5.0)
		_text(Vector2(bx - 4.0, plot.position.y - 8.0), "burst %d A (not modelled)" % roundi(burst_a),
			LothalTheme.TEXT_MUTED, true)

	# Headroom: from the motors' ask to the rating, between their two bars.
	var from: float = to_x.call(motor_max_a)
	var to: float = to_x.call(rating_a)
	var y := (float(centres[0]) + float(centres[1])) * 0.5
	var colour := LothalTheme.SUCCESS if headroom_a >= 0.0 else LothalTheme.DANGER
	draw_line(Vector2(from, y), Vector2(to, y), colour, 2.0)
	draw_line(Vector2(from, y - 5.0), Vector2(from, y + 5.0), colour, 2.0)
	draw_line(Vector2(to, y - 5.0), Vector2(to, y + 5.0), colour, 2.0)
	var word := "headroom" if headroom_a >= 0.0 else "short"
	# Above the bracket, from its left end: to its right runs the burst tick.
	_text(Vector2(minf(from, to), y - 9.0), "%d A %s" % [roundi(absf(headroom_a)), word], colour)


## A label kept inside the canvas; `right` sets it to end at `at.x` instead of starting there.
func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	# A backing plate, so a gridline or the rating's wall never runs through the words.
	var height := font.get_height(LothalTheme.FONT_SIZE_SMALL)
	draw_rect(Rect2(Vector2(x - 2.0, at.y - font.get_ascent(LothalTheme.FONT_SIZE_SMALL) - 1.0),
		Vector2(width + 4.0, height + 2.0)), Color(LothalTheme.SURFACE_BASE, 0.85))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
