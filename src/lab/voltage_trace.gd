class_name VoltageTrace
extends Control
## Voltage against time, for a pack under a sustained load. The deliverable of the battery bench
## (labs-and-sim.md §2.1) — that bench is a chart, where the thrust stand was a stand.
##
## TWO LINES, AND THE GAP BETWEEN THEM IS THE POINT. The upper line is the pack's resting
## voltage, which falls slowly as the pack empties and never comes back. The lower line is what
## it actually reads under load, which is the resting voltage minus I*R and recovers the instant
## the throttle does. Drawing only the second would show a falling line and lose the entire
## distinction: you could not tell a pack that is nearly empty from a good pack being worked hard,
## which is the single confusion this bench exists to clear up.
##
## So the region between them is filled. Sag stops being a number that ticks down and becomes a
## band you can see widen when the load goes on.
##
## Nothing here computes anything about a battery. It is handed samples and it draws them — the
## same rule the propeller mesh follows about RPM, and for the same reason: a chart that derived
## its own resting voltage would be a second opinion about the pack, agreeing with the model today
## and drifting from it later.

## How often a sample is taken. Fine enough that a punch shows as a step rather than a ramp.
const BASE_INTERVAL_S := 0.05
## Above this the trace decimates — drops every other sample and doubles its interval — so a
## twenty-minute Li-ion run costs no more memory than a two-minute LiPo one and still shows the
## whole shape. A window that scrolled instead would hide the knee, which is the thing worth
## watching for.
const MAX_SAMPLES := 1200

## The x axis never shows less than this, so the first seconds of a run do not draw as a wildly
## rescaling line.
const MIN_SPAN_S := 30.0

## Breathing room left under a sample that pushed the floor down, so the deepest point of a
## collapse sits on the chart rather than exactly on its bottom edge.
const AXIS_OVERSHOOT_V := 0.3

const BACKGROUND := Color(0.11, 0.12, 0.15)
const GRID_COLOUR := Color(0.22, 0.24, 0.28)
const AXIS_TEXT := Color(0.62, 0.66, 0.72)
const RESTING_COLOUR := Color(0.55, 0.70, 0.95)
const LIVE_COLOUR := Color(1.0, 0.45, 0.36)
const SAG_FILL := Color(1.0, 0.45, 0.36, 0.16)
const MARKER_COLOUR := Color(0.85, 0.80, 0.45, 0.55)

const MARGIN_LEFT := 54.0
const MARGIN_RIGHT := 12.0
const MARGIN_TOP := 14.0
const MARGIN_BOTTOM := 26.0

var _times := PackedFloat32Array()
var _resting := PackedFloat32Array()
var _live := PackedFloat32Array()
## The load mode in force at each sample, so a switch mid-run can be marked where it happened.
var _modes := PackedInt32Array()

var _interval_s := BASE_INTERVAL_S
var _next_sample_at := 0.0

## Volts at the top and bottom of the plot. Handed in rather than derived from the samples: an
## axis that rescaled to fit its data would flatten every trace into the same shape and destroy
## the comparison between two packs, which is most of what this chart is for.
##
## The one exception is `v_min`, which drops — never rises — to keep a sample that would otherwise
## fall off the bottom on the chart. That exception is not a convenience. A clipped line does not
## look clipped: it looks like a voltage that stopped falling and levelled off, which is a
## specific and completely wrong thing to tell someone about a pack that is actually collapsing.
## It first showed up on the Li-ion, whose live line ran two volts below an axis sized for a LiPo
## and drew a confident flat floor.
var v_min := 10.0
var v_max := 15.0

## Cutoff line, drawn across the plot. The voltage below which a pack is done.
var v_cutoff := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(420, 260)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fixes the voltage axis for a pack. Called on a pack change, never per frame.
func configure(p_v_min: float, p_v_max: float, p_v_cutoff: float) -> void:
	v_min = p_v_min
	v_max = p_v_max
	v_cutoff = p_v_cutoff
	queue_redraw()


func clear() -> void:
	_times = PackedFloat32Array()
	_resting = PackedFloat32Array()
	_live = PackedFloat32Array()
	_modes = PackedInt32Array()
	_interval_s = BASE_INTERVAL_S
	_next_sample_at = 0.0
	queue_redraw()


## Offers a reading at elapsed time `t`. Kept or dropped according to the sampling interval, so a
## caller can hand one in every frame without thinking about it.
func sample(t: float, resting_v: float, live_v: float, mode: int) -> void:
	if _times.size() > 0 and t < _next_sample_at:
		return
	_times.append(t)
	_resting.append(resting_v)
	_live.append(live_v)
	_modes.append(mode)
	_next_sample_at = t + _interval_s

	# Open the floor rather than clip the line — see the comment on v_min.
	if live_v < v_min:
		v_min = live_v - AXIS_OVERSHOOT_V

	if _times.size() > MAX_SAMPLES:
		_decimate()
	queue_redraw()


## Halves the sample count by keeping every other one, and doubles the interval to match. The
## first and last samples are always kept: the last is the live end of the trace, and losing it
## makes the line stop short of the reading the instruments are showing.
func _decimate() -> void:
	var times := PackedFloat32Array()
	var resting := PackedFloat32Array()
	var live := PackedFloat32Array()
	var modes := PackedInt32Array()
	for i in _times.size():
		if i % 2 == 0 or i == _times.size() - 1:
			times.append(_times[i])
			resting.append(_resting[i])
			live.append(_live[i])
			modes.append(_modes[i])
	_times = times
	_resting = resting
	_live = live
	_modes = modes
	_interval_s *= 2.0


# ---------------------------------------------------------------------------
# What the trace holds, as data. The tests assert on this rather than on pixels.
# ---------------------------------------------------------------------------

func sample_count() -> int:
	return _times.size()

func span_s() -> float:
	return _times[_times.size() - 1] if _times.size() > 0 else 0.0

func times() -> PackedFloat32Array:
	return _times

func resting_series() -> PackedFloat32Array:
	return _resting

func live_series() -> PackedFloat32Array:
	return _live

## The widest gap between the two lines anywhere in the trace — the deepest sag the pack took.
func deepest_sag_v() -> float:
	var worst := 0.0
	for i in _times.size():
		worst = maxf(worst, _resting[i] - _live[i])
	return worst


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		maxf(size.x - MARGIN_LEFT - MARGIN_RIGHT, 1.0),
		maxf(size.y - MARGIN_TOP - MARGIN_BOTTOM, 1.0))


func _x_span() -> float:
	return maxf(span_s(), MIN_SPAN_S)


func _point(t: float, volts: float) -> Vector2:
	var plot := _plot_rect()
	var x := plot.position.x + plot.size.x * clampf(t / _x_span(), 0.0, 1.0)
	var fraction := (volts - v_min) / maxf(v_max - v_min, 0.001)
	var y := plot.position.y + plot.size.y * (1.0 - clampf(fraction, 0.0, 1.0))
	return Vector2(x, y)


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)

	var font := ThemeDB.fallback_font
	var font_size := 11

	# Voltage gridlines, at whole volts where that is a sensible density and at coarser steps
	# for a 6S pack, so the axis does not turn into a solid block of labels.
	var volt_step := 1.0 if (v_max - v_min) <= 8.0 else 2.0
	var v := ceilf(v_min / volt_step) * volt_step
	while v <= v_max:
		var y := _point(0.0, v).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(6.0, y + 4.0), "%.0f V" % v,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		v += volt_step

	# Time gridlines. The step is chosen from the span so a 30 s run and a 20 minute one both
	# get about five labels rather than five or four hundred.
	var span := _x_span()
	var time_step := _nice_step(span / 5.0)
	var t := time_step
	while t <= span:
		var x := _point(t, v_min).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(x - 14.0, plot.end.y + 18.0), _format_time(t),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		t += time_step

	if v_cutoff > v_min:
		var cutoff_y := _point(0.0, v_cutoff).y
		draw_dashed_line(Vector2(plot.position.x, cutoff_y), Vector2(plot.end.x, cutoff_y),
			MARKER_COLOUR, 1.0, 5.0)
		draw_string(font, Vector2(plot.position.x + 6.0, cutoff_y - 4.0), "cutoff",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MARKER_COLOUR)

	if _times.size() < 2:
		draw_string(font, plot.position + Vector2(10.0, 22.0),
			"Apply a load to start the trace.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AXIS_TEXT)
		return

	# The sag band first, so both lines draw over it. One quad per sample pair rather than a
	# single polygon, because the two series are not parallel and a single polygon built from
	# one then the other reversed self-intersects wherever the load changes abruptly.
	for i in range(1, _times.size()):
		var quad := PackedVector2Array([
			_point(_times[i - 1], _resting[i - 1]),
			_point(_times[i], _resting[i]),
			_point(_times[i], _live[i]),
			_point(_times[i - 1], _live[i - 1]),
		])
		draw_colored_polygon(quad, SAG_FILL)

	# A tick wherever the load changed, so a mid-run switch is legible as an event rather than
	# as an unexplained step in the line.
	for i in range(1, _modes.size()):
		if _modes[i] != _modes[i - 1]:
			var x := _point(_times[i], v_min).x
			draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
				MARKER_COLOUR, 1.0, 4.0)

	_draw_series(_resting, RESTING_COLOUR, 2.0)
	_draw_series(_live, LIVE_COLOUR, 2.0)


func _draw_series(series: PackedFloat32Array, colour: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in _times.size():
		points.append(_point(_times[i], series[i]))
	draw_polyline(points, colour, width, true)


## Rounds a raw axis step up to something a person would choose: 1, 2, 5, 10, 20, 50 and so on.
static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var magnitude := pow(10.0, floorf(log(raw) / log(10.0)))
	var normalised := raw / magnitude
	if normalised <= 1.0:
		return magnitude
	if normalised <= 2.0:
		return 2.0 * magnitude
	if normalised <= 5.0:
		return 5.0 * magnitude
	return 10.0 * magnitude


static func _format_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0fs" % seconds
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
