class_name BandTrace
extends Control
## Two series against a shared x axis, with the region between them filled. The chart that both of
## Lab's chart-shaped benches draw on (labs-and-sim.md §2.1) — the battery bench, where the two
## lines are resting voltage and voltage under load and the band between them is SAG, and the ESC
## bench, where they are the board's continuous rating and what one channel actually draws and the
## band between them is HEADROOM.
##
## This was VoltageTrace, the battery bench's alone. It is generalised rather than copied for the
## same reason InstrumentPanel was when the battery bench wanted the thrust stand's readout: the
## shape is an opinion worth holding in one place, and the third copy is the one that drifts.
##
## TWO LINES, AND THE GAP BETWEEN THEM IS THE POINT. On the battery bench the upper line is the
## pack's resting voltage, which falls slowly as the pack empties and never comes back, and the
## lower is what it actually reads under load — resting minus I*R, recovering the instant the
## throttle does. Drawing only the second would show a falling line and lose the entire
## distinction: you could not tell a pack that is nearly empty from a good pack being worked hard,
## which is the single confusion that bench exists to clear up. On the ESC bench the upper line is
## FLAT, because a rating does not move, and the whole question is whether the lower one reaches it.
##
## So the region between them is filled. A quantity that would otherwise be a number ticking down
## becomes a band you can watch widen — or, on the ESC bench, close and then invert, which is
## filled in a different colour because a board past its rating is a different fact from a board
## close to it, not a smaller amount of the same one.
##
## Nothing here computes anything about a battery or a board. It is handed samples and it draws
## them — the same rule PropellerMesh follows about RPM, and for the same reason: a chart that
## derived its own resting voltage would be a second opinion about the pack, agreeing with the
## model today and drifting from it next month.

## What the x axis MEANS, which is the one thing the two benches genuinely disagree about. The
## battery bench plots against elapsed time, because how long a pack holds up is half of what it is
## for. The ESC bench plots against THROTTLE, because "at what throttle does this board become the
## binding constraint" is a question you cannot read off a time axis, even though the sweep that
## produced the samples took time to run.
enum XAxis { TIME, FRACTION }

## How often a sample is taken, in x units. Fine enough that a punch shows as a step rather than a
## ramp on a time axis, and that the crossing point is legible on a throttle one.
const BASE_INTERVAL := 0.05
## Above this the trace decimates — drops every other sample and doubles its interval — so a
## twenty-minute Li-ion run costs no more memory than a two-minute LiPo one and still shows the
## whole shape. A window that scrolled instead would hide the knee, which is the thing worth
## watching for.
const MAX_SAMPLES := 1200

## The x axis never shows less than this, so the first seconds of a run do not draw as a wildly
## rescaling line. Ignored when x_max is set.
const MIN_SPAN_S := 30.0

## Breathing room left beyond a sample that pushed a bound out, so the extreme point of a collapse
## — or of an overload — sits on the chart rather than exactly on its edge.
const AXIS_OVERSHOOT := 0.3

const BACKGROUND := Color(0.11, 0.12, 0.15)
const GRID_COLOUR := Color(0.22, 0.24, 0.28)
const AXIS_TEXT := Color(0.62, 0.66, 0.72)
const MARKER_COLOUR := Color(0.85, 0.80, 0.45, 0.55)

## The battery bench's palette, and the default, because it was the first caller and these are the
## colours the two lines were chosen against.
const RESTING_COLOUR := Color(0.55, 0.70, 0.95)
const LIVE_COLOUR := Color(1.0, 0.45, 0.36)
const SAG_FILL := Color(1.0, 0.45, 0.36, 0.16)
## What a band drawn the WRONG WAY UP is filled with — the lower series above the upper one. On the
## battery bench that cannot happen. On the ESC bench it is the entire finding.
const OVER_FILL := Color(1.0, 0.30, 0.26, 0.32)

const MARGIN_LEFT := 54.0
const MARGIN_RIGHT := 12.0
const MARGIN_TOP := 14.0
const MARGIN_BOTTOM := 26.0

var _xs := PackedFloat32Array()
var _upper := PackedFloat32Array()
var _lower := PackedFloat32Array()
## The mode in force at each sample, so a switch mid-run can be marked where it happened.
var _modes := PackedInt32Array()

var _interval := BASE_INTERVAL
var _next_sample_at := 0.0

## The sampling interval a fresh trace starts at, in x units. Handed in rather than fixed, because
## a throttle axis is one unit wide where a discharge axis is several hundred seconds, and one
## constant cannot be right for both. Decimation doubles the live interval from here as usual.
var base_interval := BASE_INTERVAL

## The value at the top and bottom of the plot. Handed in rather than derived from the samples: an
## axis that rescaled to fit its data would flatten every trace into the same shape and destroy the
## comparison between two packs or two boards, which is most of what this chart is for.
##
## The one exception is that the bounds OPEN — never close — to keep a sample that would otherwise
## fall off the chart on it. That exception is not a convenience. A clipped line does not look
## clipped: it looks like a quantity that stopped changing and levelled off, which is a specific
## and completely wrong thing to say about a pack that is actually collapsing, or about a channel
## that is actually past its rating. It first showed up on the Li-ion, whose live line ran two
## volts below an axis sized for a LiPo and drew a confident flat floor.
var y_min := 10.0
var y_max := 15.0

## A horizontal line drawn across the plot with a caption — the pack's cutoff voltage on the
## battery bench, and nothing on the ESC bench, where the rating IS one of the two series. Zero
## means none.
var reference_value := 0.0
var reference_label := "cutoff"

## The unit suffix on the y axis labels, and the step between gridlines. The step is handed in
## rather than guessed, because "1 V" and "10 A" are both right for a range of the same width and
## neither is derivable from it.
var y_unit := "V"
var y_step := 0.0

var x_axis: int = XAxis.TIME
## A FIXED right-hand end, or zero to grow with the data. The throttle axis is fixed at 1.0: a
## sweep that rescaled as it climbed would slide the crossing point sideways under your eyes.
var x_max := 0.0

var upper_colour := RESTING_COLOUR
var lower_colour := LIVE_COLOUR
var fill_colour := SAG_FILL
var over_fill_colour := OVER_FILL

## Drawn in the corner of an empty chart, so a bench nobody has started yet says what to do rather
## than showing a blank rectangle.
var empty_hint := "Apply a load to start the trace."


func _init() -> void:
	custom_minimum_size = Vector2(420, 260)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fixes the y axis. Called on a pack or board change, never per frame.
func configure(p_y_min: float, p_y_max: float, p_reference: float = 0.0) -> void:
	y_min = p_y_min
	y_max = p_y_max
	reference_value = p_reference
	queue_redraw()


func clear() -> void:
	_xs = PackedFloat32Array()
	_upper = PackedFloat32Array()
	_lower = PackedFloat32Array()
	_modes = PackedInt32Array()
	_interval = base_interval
	_next_sample_at = 0.0
	queue_redraw()


## Offers a reading at `x`. Kept or dropped according to the sampling interval, so a caller can
## hand one in every frame without thinking about it.
func sample(x: float, upper: float, lower: float, mode: int = 0) -> void:
	if _xs.size() > 0 and x < _next_sample_at:
		return
	_xs.append(x)
	_upper.append(upper)
	_lower.append(lower)
	_modes.append(mode)
	_next_sample_at = x + _interval

	# Open the bounds rather than clip a line — see the comment on y_min. BOTH bounds and BOTH
	# series now: the battery bench only ever pushes the floor down with its live line, but the ESC
	# bench's draw line climbs UP through its rating, and an overload drawn flat along the top of
	# the chart is the same lie told in the more expensive direction.
	for value in [upper, lower]:
		if value < y_min:
			y_min = value - AXIS_OVERSHOOT
		if value > y_max:
			y_max = value + AXIS_OVERSHOOT

	if _xs.size() > MAX_SAMPLES:
		_decimate()
	queue_redraw()


## Halves the sample count by keeping every other one, and doubles the interval to match. The
## first and last samples are always kept: the last is the live end of the trace, and losing it
## makes the line stop short of the reading the instruments are showing.
func _decimate() -> void:
	# Named `kept_*` rather than `xs`, `upper` and so on: a local called `xs` shadows this class's
	# own xs() accessor, which reads fine until someone edits it and reaches for the accessor by
	# name three lines down.
	var kept_xs := PackedFloat32Array()
	var kept_upper := PackedFloat32Array()
	var kept_lower := PackedFloat32Array()
	var kept_modes := PackedInt32Array()
	for i in _xs.size():
		if i % 2 == 0 or i == _xs.size() - 1:
			kept_xs.append(_xs[i])
			kept_upper.append(_upper[i])
			kept_lower.append(_lower[i])
			kept_modes.append(_modes[i])
	_xs = kept_xs
	_upper = kept_upper
	_lower = kept_lower
	_modes = kept_modes
	_interval *= 2.0


# ---------------------------------------------------------------------------
# What the trace holds, as data. The tests assert on this rather than on pixels.
# ---------------------------------------------------------------------------

func sample_count() -> int:
	return _xs.size()

## The x of the last sample — elapsed seconds on a time axis, the highest throttle reached on a
## throttle one.
func span() -> float:
	return _xs[_xs.size() - 1] if _xs.size() > 0 else 0.0

func xs() -> PackedFloat32Array:
	return _xs

func upper_series() -> PackedFloat32Array:
	return _upper

func lower_series() -> PackedFloat32Array:
	return _lower

## The widest the band ever got with the upper series ABOVE — the deepest sag the pack took, or the
## most headroom the board ever had. Never negative; the other side is worst_overshoot().
func widest_gap() -> float:
	var worst := 0.0
	for i in _xs.size():
		worst = maxf(worst, _upper[i] - _lower[i])
	return worst


## The furthest the LOWER series ever got ABOVE the upper one. Zero on a chart where that cannot
## happen, and on the ESC bench the amount by which the board was overrun.
func worst_overshoot() -> float:
	var worst := 0.0
	for i in _xs.size():
		worst = maxf(worst, _lower[i] - _upper[i])
	return worst


## The x at which the lower series first crosses the upper one, or -1.0 if it never does. On the
## ESC bench this is the throttle at which the board becomes the binding constraint, which is one
## of the two things labs-and-sim.md §2.1 asks that bench to report.
func first_crossing_x() -> float:
	for i in _xs.size():
		if _lower[i] > _upper[i]:
			return _xs[i]
	return -1.0


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		maxf(size.x - MARGIN_LEFT - MARGIN_RIGHT, 1.0),
		maxf(size.y - MARGIN_TOP - MARGIN_BOTTOM, 1.0))


func _x_span() -> float:
	if x_max > 0.0:
		return x_max
	return maxf(span(), MIN_SPAN_S)


func _point(x: float, value: float) -> Vector2:
	var plot := _plot_rect()
	var px := plot.position.x + plot.size.x * clampf(x / _x_span(), 0.0, 1.0)
	var fraction := (value - y_min) / maxf(y_max - y_min, 0.001)
	var py := plot.position.y + plot.size.y * (1.0 - clampf(fraction, 0.0, 1.0))
	return Vector2(px, py)


## The gridline spacing on the y axis: whatever was handed in, or whole units where that is a
## sensible density and a coarser step for a range wide enough that whole units would turn the
## axis into a solid block of labels.
func _resolved_y_step() -> float:
	if y_step > 0.0:
		return y_step
	return 1.0 if (y_max - y_min) <= 8.0 else 2.0


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)

	var font := ThemeDB.fallback_font
	var font_size := 11

	var step := _resolved_y_step()
	var value := ceilf(y_min / step) * step
	while value <= y_max:
		var y := _point(0.0, value).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(6.0, y + 4.0), "%.0f %s" % [value, y_unit],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		value += step

	# x gridlines. The step is chosen from the span so a 30 s run and a 20 minute one both get
	# about five labels rather than five or four hundred.
	var span_x := _x_span()
	var x_step := _nice_step(span_x / 5.0)
	var x := x_step
	while x <= span_x + x_step * 0.001:
		var px := _point(x, y_min).x
		draw_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(px - 14.0, plot.end.y + 18.0), _format_x(x),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		x += x_step

	if reference_value > y_min:
		var ref_y := _point(0.0, reference_value).y
		draw_dashed_line(Vector2(plot.position.x, ref_y), Vector2(plot.end.x, ref_y),
			MARKER_COLOUR, 1.0, 5.0)
		draw_string(font, Vector2(plot.position.x + 6.0, ref_y - 4.0), reference_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MARKER_COLOUR)

	if _xs.size() < 2:
		draw_string(font, plot.position + Vector2(10.0, 22.0),
			empty_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AXIS_TEXT)
		return

	# The band first, so both lines draw over it. One quad per sample pair rather than a single
	# polygon, because the two series are not parallel and a single polygon built from one then the
	# other reversed self-intersects wherever the load changes abruptly.
	#
	# Coloured per PAIR rather than once for the whole band, which is what lets the ESC bench draw
	# the stretch where the draw is past the rating differently from the stretch where it is not.
	# The crossing point is the thing that bench exists to find, and a band in one colour throughout
	# would hide it behind two lines that merely happen to swap over.
	for i in range(1, _xs.size()):
		_draw_band_segment(i)

	# A tick wherever the mode changed, so a mid-run switch is legible as an event rather than as
	# an unexplained step in the line.
	for i in range(1, _modes.size()):
		if _modes[i] != _modes[i - 1]:
			var px := _point(_xs[i], y_min).x
			draw_dashed_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y),
				MARKER_COLOUR, 1.0, 4.0)

	_draw_series(_upper, upper_colour, 2.0)
	_draw_series(_lower, lower_colour, 2.0)


## One quad of the band, between sample i-1 and i — SPLIT AT THE CROSSING when the two series swap
## over inside it.
##
## Without the split this is a bowtie: the quad's two long edges intersect, Godot's triangulator
## refuses it ("Invalid polygon data, triangulation failed") and the segment simply does not draw.
## The hole would land exactly at the crossing point, which on the ESC bench is the one place on
## the whole chart worth looking at — a gap in the fill precisely where the board runs out. Split
## into two triangles it also gets the colours right on both sides of the crossing, which a single
## quad could never do whatever colour it was given.
func _draw_band_segment(i: int) -> void:
	var upper_a := _point(_xs[i - 1], _upper[i - 1])
	var upper_b := _point(_xs[i], _upper[i])
	var lower_a := _point(_xs[i - 1], _lower[i - 1])
	var lower_b := _point(_xs[i], _lower[i])

	var gap_a := _upper[i - 1] - _lower[i - 1]
	var gap_b := _upper[i] - _lower[i]

	if (gap_a < 0.0) == (gap_b < 0.0):
		draw_colored_polygon(
			PackedVector2Array([upper_a, upper_b, lower_b, lower_a]),
			over_fill_colour if gap_b < 0.0 else fill_colour)
		return

	# Where the gap passes through zero, in this segment's own parameter. The two series meet there,
	# so it is one point on both lines and the apex of both triangles.
	var t := gap_a / (gap_a - gap_b)
	var crossing := upper_a.lerp(upper_b, t)
	draw_colored_polygon(PackedVector2Array([upper_a, crossing, lower_a]),
		over_fill_colour if gap_a < 0.0 else fill_colour)
	draw_colored_polygon(PackedVector2Array([crossing, upper_b, lower_b]),
		over_fill_colour if gap_b < 0.0 else fill_colour)


func _draw_series(series: PackedFloat32Array, colour: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in _xs.size():
		points.append(_point(_xs[i], series[i]))
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


func _format_x(x: float) -> String:
	if x_axis == XAxis.FRACTION:
		return "%.0f %%" % (x * 100.0)
	return Duration.short(x)
