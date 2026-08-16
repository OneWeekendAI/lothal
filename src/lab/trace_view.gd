class_name TraceView
extends Control
## N channels of a complete flight log, over the log's own clock (LTHL-55).
##
## ===========================================================================
## WHY THIS IS NOT BandTrace
## ===========================================================================
##
## BandTrace is 430 lines of working plot code and it is the wrong widget here, in five ways that
## are each structural rather than a missing feature:
##
##     BandTrace                      | a log viewer
##     -------------------------------|------------------------------------------
##     streaming, appended live       | complete, already on disk
##     exactly two series, filled     | N, chosen by the builder
##     capped at 1200, drops samples  | 180 000, all of them meaningful
##     x axis grows with the data     | the file's full span, known up front
##     MOUSE_FILTER_IGNORE            | wants a cursor
##
## Three benches depend on BandTrace — battery, ESC and frame. Widening it to carry this list
## would put a viewer's requirements into a widget three working screens rely on, to save writing
## a second one. So this is a SIBLING and BandTrace is left exactly as it is.
##
## What is taken from it rather than reinvented: immediate-mode _draw() with no .tscn and no
## Line2D, the margins, _nice_step's axis ticks, Duration's x-axis formatting, and above all the
## queryable state surface — bucket_count(), channel_extent() and friends — which is what lets a
## test assert on a plot without rendering one.
##
## Axis ticks now exist in two files. That is duplication of PRESENTATION, not of a law, and is
## the acceptable kind: two charts disagreeing about where to put a gridline is a cosmetic bug,
## while two charts disagreeing about a voltage is a lie.
##
## ===========================================================================
## MIN/MAX PER PIXEL COLUMN, AND THIS IS THE ONE DECISION THAT IS NOT COSMETIC
## ===========================================================================
##
## A 900 px plot of 180 000 samples is 200 samples per pixel. They cannot all be drawn and
## something has to choose which survive.
##
## THE CONTENT OF A VIBRATION TRACE IS ITS SPIKES. That is the whole reason a builder opens one.
##
## - Dropping 199 of every 200 makes the peaks depend on which samples happened to land on a kept
##   index, so the same log drawn at two window widths shows different amplitudes and neither of
##   them is the log. BandTrace._decimate() drops, which is right for a slow bench curve and
##   wrong here.
## - Averaging is worse in a more specific way: it is a lowpass filter nobody asked for, at a
##   cutoff set by the window width, applied to a trace whose entire purpose is to show what a
##   lowpass filter costs.
##
## So each pixel column draws a VERTICAL EXTENT from the minimum to the maximum of the samples
## that fall in it. The drawn extent is the true range of the signal there, a spike one sample
## wide is visible, and widening the window never changes what the trace claims.

const BACKGROUND := LothalTheme.PANEL_BG
const GRID_COLOUR := LothalTheme.BORDER
const AXIS_TEXT := LothalTheme.TEXT_MUTED

const MARGIN_LEFT := 54.0
const MARGIN_RIGHT := 12.0
const MARGIN_TOP := 14.0
const MARGIN_BOTTOM := 26.0

## Per-channel colours, in the order channels are added. Six, because a builder watching more than
## six lines at once is not reading a chart any more — and the seventh wraps rather than being
## refused, since refusing to draw a channel is worse than drawing two in one colour.
const SERIES_COLOURS := [
	LothalTheme.ACCENT,
	LothalTheme.SUCCESS,
	LothalTheme.WARNING,
	LothalTheme.DANGER,
	Color(0.55, 0.75, 0.95),
	Color(0.85, 0.65, 0.95),
]

const EMPTY_HINT := "Pick a channel."

## The clock every channel is drawn against, and it is the log's own t_s rather than a sample
## index. A trace indexed by row would be wrong the moment decimation is on, and silently: the
## rows would still be evenly spaced, just not one millisecond apart.
var times := PackedFloat64Array()

## name -> PackedFloat64Array, in insertion order. Held whole rather than pre-decimated, because
## the bucket count is the widget's pixel width and that changes on every resize.
var _channels: Dictionary = {}

## The decimation, rebuilt when the width changes or a channel is added. name -> {lo, hi}, each of
## bucket_count() entries. Cached because a resize should not re-walk 180 000 samples per channel
## per frame, and invalidated on width change because that is exactly when it must.
var _buckets: Dictionary = {}
var _bucket_width := -1.0


func _init() -> void:
	# Unlike BandTrace, this one takes input: a viewer wants a cursor. Nothing reads it yet, and
	# the filter is set here rather than left to LTHL-20 so the widget's intent is stated once.
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_invalidate)


## Replaces everything. One call, so there is no arrangement in which the clock belongs to one
## flight and a channel to another.
func show_log(p_times: PackedFloat64Array, p_channels: Dictionary) -> void:
	times = p_times
	_channels = p_channels.duplicate()
	_invalidate()
	queue_redraw()


func clear() -> void:
	times = PackedFloat64Array()
	_channels = {}
	_invalidate()
	queue_redraw()


func channel_names() -> PackedStringArray:
	var out := PackedStringArray()
	for channel in _channels:
		out.append(channel)
	return out


## ---------------------------------------------------------------------------
## The queryable surface the tests assert on
## ---------------------------------------------------------------------------

func bucket_count() -> int:
	return maxi(1, int(_plot_rect().size.x))


## The drawn vertical extent of one channel in one bucket, as [lo, hi]. THIS IS WHAT THE TEST FOR
## min/max DECIMATION ASSERTS ON: it is the number actually rendered, so a widget that quietly
## changed how it chose samples could not keep this honest while drawing something else.
func bucket_extent(channel: String, bucket: int) -> Vector2:
	_rebuild_buckets()
	if not _buckets.has(channel):
		return Vector2.ZERO
	var pair: Dictionary = _buckets[channel]
	var lo: PackedFloat64Array = pair["lo"]
	var hi: PackedFloat64Array = pair["hi"]
	if bucket < 0 or bucket >= lo.size():
		return Vector2.ZERO
	return Vector2(lo[bucket], hi[bucket])


## The full drawn range of a channel across every bucket — the y extent a reader would measure off
## the screen. A decimation that lost a spike shows up here as a smaller number.
##
## RETURNS A Vector2, WHOSE COMPONENTS ARE 32-BIT. That is a deliberate narrowing and it is safe
## for exactly one reason: this figure exists to scale pixels, and a pixel is not addressable to
## seven significant figures. The LOG's values stay float64 all the way from the recorder through
## LogReader into `_channels`, and nothing here writes back — so the precision is lost on the way
## to the screen and nowhere else. A caller wanting the true extent of the data should read
## `_channels` and not this. Tests asserting on this must use an f32-sized tolerance.
func channel_extent(channel: String) -> Vector2:
	_rebuild_buckets()
	if not _buckets.has(channel):
		return Vector2.ZERO
	var pair: Dictionary = _buckets[channel]
	var lo: PackedFloat64Array = pair["lo"]
	var hi: PackedFloat64Array = pair["hi"]
	if lo.is_empty():
		return Vector2.ZERO
	var low: float = lo[0]
	var high: float = hi[0]
	for i in lo.size():
		# NaN is what LogReader writes for a cell that would not parse, and it must not become the
		# extent: min/max against NaN in GDScript propagates it, and one bad cell would blank the
		# whole axis.
		if is_nan(lo[i]) or is_nan(hi[i]):
			continue
		low = minf(low, lo[i])
		high = maxf(high, hi[i])
	return Vector2(low, high)


func span_s() -> float:
	if times.size() < 2:
		return 0.0
	return times[times.size() - 1] - times[0]


## ---------------------------------------------------------------------------
## Decimation
## ---------------------------------------------------------------------------

func _invalidate() -> void:
	_bucket_width = -1.0
	queue_redraw()


## One pass per channel, bucketing by TIME rather than by sample index.
##
## By time, deliberately. Indexing by row assumes the rows are evenly spaced, which is true of a
## log written at decimation 1 and false of every other one — and the failure would be a trace
## whose x axis was subtly wrong while looking entirely normal.
func _rebuild_buckets() -> void:
	var buckets := bucket_count()
	if _bucket_width == float(buckets) and not _buckets.is_empty():
		return
	_bucket_width = float(buckets)
	_buckets = {}

	if times.size() < 2:
		return
	var t0: float = times[0]
	var span := span_s()
	if span <= 0.0:
		return

	for channel in _channels:
		var values: PackedFloat64Array = _channels[channel]
		var lo := PackedFloat64Array()
		var hi := PackedFloat64Array()
		lo.resize(buckets)
		hi.resize(buckets)
		var seen := PackedByteArray()
		seen.resize(buckets)

		var count: int = mini(values.size(), times.size())
		for i in count:
			var bucket := int((times[i] - t0) / span * float(buckets - 1))
			bucket = clampi(bucket, 0, buckets - 1)
			var value: float = values[i]
			if is_nan(value):
				continue
			if seen[bucket] == 0:
				seen[bucket] = 1
				lo[bucket] = value
				hi[bucket] = value
			else:
				lo[bucket] = minf(lo[bucket], value)
				hi[bucket] = maxf(hi[bucket], value)

		# A bucket no sample landed in — possible when the plot is wider than the log is long —
		# carries the previous bucket's value rather than a zero, so a short log draws as a line
		# with gaps in the sampling rather than a comb down to the axis.
		var last := 0.0
		var have_last := false
		for b in buckets:
			if seen[b] == 1:
				last = hi[b]
				have_last = true
			elif have_last:
				lo[b] = last
				hi[b] = last
			else:
				lo[b] = NAN
				hi[b] = NAN

		_buckets[channel] = {"lo": lo, "hi": hi}


## ---------------------------------------------------------------------------
## Drawing
## ---------------------------------------------------------------------------

func _plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		maxf(size.x - MARGIN_LEFT - MARGIN_RIGHT, 1.0),
		maxf(size.y - MARGIN_TOP - MARGIN_BOTTOM, 1.0))


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)

	var font := ThemeDB.fallback_font
	var font_size := 11

	if _channels.is_empty() or times.size() < 2:
		draw_string(font, plot.position + Vector2(10.0, 22.0), EMPTY_HINT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AXIS_TEXT)
		return

	_rebuild_buckets()

	# ONE SHARED Y AXIS, scaled to every visible channel together. Per-channel axes would let a
	# builder put rpm next to a rate and read them as comparable, which is the chart lying about
	# the relationship between two lines it drew side by side.
	var y_min := INF
	var y_max := -INF
	for channel in _channels:
		var extent := channel_extent(channel)
		y_min = minf(y_min, extent.x)
		y_max = maxf(y_max, extent.y)
	if not is_finite(y_min) or not is_finite(y_max) or is_equal_approx(y_min, y_max):
		y_min -= 1.0
		y_max += 1.0

	var y_step := _nice_step((y_max - y_min) / 5.0)
	var value := ceilf(y_min / y_step) * y_step
	while value <= y_max:
		var y := _y_pixel(value, y_min, y_max, plot)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(6.0, y + 4.0), _format_y(value),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		value += y_step

	var span := span_s()
	var x_step := _nice_step(span / 5.0)
	var x := x_step
	while x <= span + x_step * 0.001:
		var px := plot.position.x + plot.size.x * (x / span)
		draw_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(px - 14.0, plot.end.y + 18.0), Duration.fine(x),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		x += x_step

	var index := 0
	for channel in _channels:
		_draw_channel(channel, SERIES_COLOURS[index % SERIES_COLOURS.size()], y_min, y_max, plot)
		index += 1


## One vertical segment per pixel column, from the bucket's minimum to its maximum.
##
## Not a polyline through midpoints, which is the tempting simplification and throws away exactly
## what the bucketing preserved: the midpoint of [-0.4, 0.4] is zero, so a symmetric spike would
## draw as a flat line through the middle of itself.
func _draw_channel(channel: String, colour: Color, y_min: float, y_max: float, plot: Rect2) -> void:
	if not _buckets.has(channel):
		return
	var pair: Dictionary = _buckets[channel]
	var lo: PackedFloat64Array = pair["lo"]
	var hi: PackedFloat64Array = pair["hi"]

	for b in lo.size():
		if is_nan(lo[b]) or is_nan(hi[b]):
			continue
		var px := plot.position.x + float(b)
		var top := _y_pixel(hi[b], y_min, y_max, plot)
		var bottom := _y_pixel(lo[b], y_min, y_max, plot)
		# A bucket whose samples were all equal is a zero-height segment, which draws as nothing.
		# One pixel of height keeps a flat channel visible as a line rather than as an absence.
		if absf(bottom - top) < 1.0:
			bottom = top + 1.0
		draw_line(Vector2(px, top), Vector2(px, bottom), colour, 1.0)


func _y_pixel(value: float, y_min: float, y_max: float, plot: Rect2) -> float:
	var fraction := (value - y_min) / maxf(y_max - y_min, 1e-9)
	return plot.position.y + plot.size.y * (1.0 - clampf(fraction, 0.0, 1.0))


## Enough significant figures to tell two gridlines apart, which a fixed "%.0f" does not for an
## axis spanning 0.02 rad/s — every label would read "0".
func _format_y(value: float) -> String:
	var magnitude := maxf(absf(value), 1e-9)
	if magnitude >= 100.0:
		return "%.0f" % value
	if magnitude >= 1.0:
		return "%.1f" % value
	return "%.3f" % value


## Rounds a raw axis step up to something a person would choose. The same ladder BandTrace uses,
## restated rather than shared: see the class header on presentation duplication.
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
