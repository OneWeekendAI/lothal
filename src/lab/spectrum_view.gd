class_name SpectrumView
extends Control
## The averaged magnitude spectrum of one channel, with the marks that make it readable (LTHL-20).
##
## ===========================================================================
## A THIRD CHART, AND WHY IT IS NOT TraceView WITH A DIFFERENT X AXIS
## ===========================================================================
##
## TraceView is a min/max decimator over a time axis. Nothing in it applies here and one thing in
## it would be actively wrong:
##
##   * There is no decimation to do. A spectrum is 513 bins wide and a plot is 300 px, so this is
##     the ONE chart in the project where the data is smaller than the pixels.
##   * The y axis is LOGARITHMIC, and it has to be. A spectrum's interesting features are 40 dB
##     below its largest one; on a linear axis a vibration peak is a flat line along the bottom.
##     TraceView is linear and must stay linear — a linear axis is the correct one for a rate.
##   * The x axis carries MARKS, which is most of the value here. A curve with a bump at 183 Hz
##     says nothing; the same curve with "1x at 96", "3x at 288" and "model says 183" on it says
##     whether the bump is the motors or the frame.
##
## So this is a third sibling, like TraceView was to BandTrace, and for the same reason: widening
## an existing chart until it covers a case it shares no arithmetic with produces one widget that
## three screens are afraid to touch.
##
## ===========================================================================
## WHAT THE MARKS MEAN, AND THE ONE THAT IS NOT A MEASUREMENT
## ===========================================================================
##
## Harmonic marks come from the log: the motors' mean rpm times an order. They are data.
##
## The MODEL mark does not. It is VibrationModel's resonance for this airframe, which is anchored
## on one guessed constant nobody has ever sourced (validation.md §9, and RateTune.kd_ceiling_for
## refuses to let it move a gain for exactly this reason). It is drawn DASHED and labelled
## "model", against the solid harmonic lines, because a builder who reads it as "Lothal measured
## my frame at 183.4 Hz" has been told something Lothal does not know.
##
## The dashing is doing real work there and is not decoration.

const BACKGROUND := LothalTheme.PANEL_BG
const GRID_COLOUR := LothalTheme.BORDER
const AXIS_TEXT := LothalTheme.TEXT_MUTED
const CURVE_COLOUR := LothalTheme.ACCENT
const HARMONIC_COLOUR := LothalTheme.SUCCESS
const MODEL_COLOUR := LothalTheme.WARNING

const MARGIN_LEFT := 34.0
const MARGIN_RIGHT := 8.0
const MARGIN_TOP := 12.0
const MARGIN_BOTTOM := 22.0

## Below this the curve is noise floor and drawing three more decades of it just shrinks
## everything above. Magnitudes are gyro rad/s summed over a 1024-point window, so this is small.
const FLOOR := 1e-6

## The band drawn. resonance_analysis.SEARCH_BAND_HZ is (60, 600) and this is deliberately wider:
## the search band is where a MODE is looked for, while a builder looking at a spectrum wants to
## see the 1x line too, and at hover that is around 90 Hz with its rigid-body content below it.
const MIN_HZ := 0.0
const MAX_HZ := 600.0

const EMPTY_HINT := "No spectrum."

var mags := PackedFloat64Array()
var bin_hz := 0.0
## [{"hz": float, "label": String, "dashed": bool}]
var marks: Array = []
## Shown instead of a curve when there is none.
var note := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0, 160)


func show_spectrum(p_mags: PackedFloat64Array, p_bin_hz: float, p_marks: Array) -> void:
	mags = p_mags
	bin_hz = p_bin_hz
	marks = p_marks.duplicate()
	note = ""
	queue_redraw()


func clear(p_note: String = "") -> void:
	mags = PackedFloat64Array()
	bin_hz = 0.0
	marks = []
	note = p_note
	queue_redraw()


## ---------------------------------------------------------------------------
## The queryable surface — what the tests assert on instead of pixels
## ---------------------------------------------------------------------------

func bin_count() -> int:
	return mags.size()


## The highest frequency the chart draws, which is the smaller of Nyquist and MAX_HZ.
func span_hz() -> float:
	if mags.size() < 2 or bin_hz <= 0.0:
		return 0.0
	return minf(bin_hz * float(mags.size() - 1), MAX_HZ)


## The frequency of the largest bin inside the drawn band.
##
## NOT a resonance and never called one — it is where this curve happens to be tallest, which on
## almost every real log is the 1x line. FlightAnalysis names no peaks and neither does this; the
## method exists so a test can assert the chart is drawing the signal it was handed.
func loudest_hz() -> float:
	if mags.is_empty() or bin_hz <= 0.0:
		return 0.0
	var best := -INF
	var best_bin := 0
	for bin in mags.size():
		var hz := float(bin) * bin_hz
		if hz > MAX_HZ:
			break
		if mags[bin] > best:
			best = mags[bin]
			best_bin = bin
	return float(best_bin) * bin_hz


func mark_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for mark in marks:
		out.append(str(mark.get("label", "")))
	return out


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
	var font_size := 10

	if mags.size() < 2 or bin_hz <= 0.0:
		draw_string(font, plot.position + Vector2(8.0, 20.0),
			note if not note.is_empty() else EMPTY_HINT,
			HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 8.0, 11, AXIS_TEXT)
		return

	var span := span_hz()
	var top := FLOOR
	for bin in mags.size():
		if float(bin) * bin_hz > MAX_HZ:
			break
		top = maxf(top, mags[bin])
	# Three decades below the loudest bin. Fixed rather than fitted to the quietest bin, because
	# the quietest bin is numerical dust and fitting to it would rescale the whole chart whenever
	# a different flight happened to have a slightly emptier corner.
	var floor_value := top * 1e-3

	# Decade gridlines, which is the only y annotation that means anything on a log axis.
	var decade := pow(10.0, floorf(log(floor_value) / log(10.0)))
	while decade <= top:
		var y := _y_pixel(decade, floor_value, top, plot)
		if y >= plot.position.y and y <= plot.end.y:
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOUR, 1.0)
			draw_string(font, Vector2(3.0, y + 4.0), "1e%d" % roundi(log(decade) / log(10.0)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		decade *= 10.0

	var x_step := TraceView._nice_step(span / 4.0)
	var hz := x_step
	while hz <= span:
		var px := _x_pixel(hz, span, plot)
		draw_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), GRID_COLOUR, 1.0)
		draw_string(font, Vector2(px - 10.0, plot.end.y + 15.0), "%.0f" % hz,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_TEXT)
		hz += x_step

	# The curve. One point per bin, joined — there are fewer bins in the band than pixels, so
	# nothing is being decided about which samples survive. See the class header.
	var previous := Vector2.INF
	for bin in mags.size():
		var f := float(bin) * bin_hz
		if f > span:
			break
		var point := Vector2(_x_pixel(f, span, plot),
			_y_pixel(mags[bin], floor_value, top, plot))
		if previous != Vector2.INF:
			draw_line(previous, point, CURVE_COLOUR, 1.0)
		previous = point

	for mark in marks:
		_draw_mark(mark, span, plot, font, font_size)


func _draw_mark(p_mark: Dictionary, p_span: float, p_plot: Rect2, p_font: Font,
		p_font_size: int) -> void:
	var hz := float(p_mark.get("hz", 0.0))
	if hz <= 0.0 or hz > p_span:
		return
	var dashed := bool(p_mark.get("dashed", false))
	var colour: Color = MODEL_COLOUR if dashed else HARMONIC_COLOUR
	var px := _x_pixel(hz, p_span, p_plot)

	if dashed:
		# Hand-drawn dashes rather than draw_dashed_line, which exists but takes a dash length in
		# pixels and produces a different pattern at every widget height. See the class header for
		# why this one line has to look different from the others.
		var y := p_plot.position.y
		while y < p_plot.end.y:
			draw_line(Vector2(px, y), Vector2(px, minf(y + 4.0, p_plot.end.y)), colour, 1.0)
			y += 8.0
	else:
		draw_line(Vector2(px, p_plot.position.y), Vector2(px, p_plot.end.y), colour, 1.0)

	draw_string(p_font, Vector2(px + 3.0, p_plot.position.y + 10.0),
		str(p_mark.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, p_font_size, colour)


func _x_pixel(p_hz: float, p_span: float, p_plot: Rect2) -> float:
	var fraction := (p_hz - MIN_HZ) / maxf(p_span - MIN_HZ, 1e-9)
	return p_plot.position.x + p_plot.size.x * clampf(fraction, 0.0, 1.0)


func _y_pixel(p_value: float, p_floor: float, p_top: float, p_plot: Rect2) -> float:
	var value := maxf(p_value, p_floor)
	var lo := log(maxf(p_floor, FLOOR))
	var hi := log(maxf(p_top, p_floor * 10.0))
	var fraction := (log(value) - lo) / maxf(hi - lo, 1e-9)
	return p_plot.position.y + p_plot.size.y * (1.0 - clampf(fraction, 0.0, 1.0))
