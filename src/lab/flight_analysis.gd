class_name FlightAnalysis
extends RefCounted
## What can honestly be computed FROM a flight log, and what cannot (LTHL-20).
##
## ===========================================================================
## READING A LOG MUST NEVER RECONSTRUCT A BUILD
## ===========================================================================
##
## This is the fourth file to read logs and it is the one where the rule is hardest to keep,
## because every figure below is the kind of thing the Lab computes from a Build. It would take
## one line to fetch the parts named by the fingerprint and ask them for the answer.
##
## It takes header fields and column arrays. It never touches PartsCatalog or Build.from_ids, and
## tests/test_flight_recorder.gd enforces that by grepping this file's source.
##
## The exception that is not one: RateTune.noise_fraction_for. That is a static taking three
## floats — a step noise, a sample rate and a gain — and no Build at all. It exists because the
## alternative was writing D's arithmetic out a second time here. See the note on it.
##
## ===========================================================================
## WHAT THIS COMPUTES, AND WHAT IT REFUSES TO
## ===========================================================================
##
## It computes: the gyro-vs-omega gap, what the tune's D gain costs on the noise this flight
## actually had, an averaged spectrum, and where the rpm harmonics and the MODELLED resonance sit
## on it.
##
## IT NEVER NAMES A MEASURED RESONANCE. Finding a mode in a spectrum is a statistic with a
## pre-registration behind it — trend division, an order curve, a peak rule, an ambiguity test,
## a coverage requirement — and all of that lives in tools/resonance_analysis.py, validated to
## 0.6% on synthetic modes, with a written-down protocol and a corpus behind it. A second version
## of that statistic, written to fill a UI panel, would be the same law spelled twice with only
## one of the spellings defended. logs.md names that as the failure to avoid.
##
## So Studio draws the spectrum, marks where the model SAYS the mode is, marks where the rpm
## harmonics ARE, and lets the builder look. The difference matters and the pane states it.
##
## ===========================================================================
## THE ADMISSIBILITY CHECK, AND WHY A SPECTRUM PANE NEEDS ONE
## ===========================================================================
##
## LTHL-18's null result across 141 flights WAS a refusal: normal flying moves the 1x line
## 155-235 Hz inside a single 1.024 s frame, so no line survives to be a line. A pane that drew a
## confident-looking curve for such a log and marked a peak on it would have told a builder
## something Lothal does not know.
##
## Two conditions, both transcribed from the pre-registration rather than invented here:
##
##   SMEAR    — the tracked harmonic must stay inside a few bins across one analysis frame. This
##              is the LTHL-18 wall directly.
##   COVERAGE — the harmonics must actually sweep ACROSS the modelled resonance. A hover log's
##              lines are parked, and a bump next to a parked line cannot be told apart from the
##              line. resonance_analysis.coverage, pre-registration 4.
##
## A log failing either still gets a spectrum drawn. What it does not get is any suggestion that
## a feature in it is a mode.

## Body-axis suffixes on the recorder's columns, in the tune's order — Vector3(roll, pitch, yaw).
const AXES := ["x", "y", "z"]
const AXIS_LABELS := ["roll", "pitch", "yaw"]

const TIME_COLUMN := "t_s"
const SENSOR_PREFIX := "gyro_"
const TRUTH_PREFIX := "omega_"
const RATE_SUFFIX := "_rad_s"
const MOTOR_RPM_COLUMNS := ["m1_rpm", "m2_rpm", "m3_rpm", "m4_rpm"]

## The channel the spectrum is taken of. Roll, and the SENSOR rather than ground truth: the whole
## question a spectrum answers here is what the flight controller was fed, and omega is by
## construction free of the vibration being looked for.
const SPECTRUM_CHANNEL := "gyro_x_rad_s"

## resonance_analysis pre-registration 3 tracks orders 1, 2 and blade-pass. Blade-pass comes from
## the header's blade count, so it is added at runtime.
const BASE_ORDERS := [1, 2]

## How far the highest tracked harmonic may move inside ONE analysis frame, in bins, before the
## line it would draw is not a line. Four bins at a 0.977 Hz resolution is about 4 Hz — an order
## of magnitude tighter than the 80 Hz smear that made the LTHL-18 corpus inadmissible, and loose
## enough that a hand-flown steady climb still passes.
const MAX_SMEAR_BINS := 4.0

## What fraction of frames have to clear that bound. Not all of them: one throttle punch in an
## otherwise steady log should not disqualify the log, it should be a minority of frames whose
## contribution to the average is a minority of the average.
const MIN_SHARP_FRACTION := 0.6

## resonance_analysis.AGREEMENT_FRACTION, reused as MIN_COVERAGE_SPAN is there: the swept range
## has to reach this far either side of the modelled resonance to have tested it.
const MIN_COVERAGE_SPAN := 0.25

## Fewer frames than this and the average is one or two windows, which is a spectrum of a moment.
const MIN_FRAMES := 4

## resonance_analysis.FRAME_SECONDS, and rust/src/spectrum.rs's FRAME_SECONDS, restated so the UI
## can say what window the numbers came from. THIS IS A THIRD COPY OF A CONSTANT and it is only
## safe because it is pinned: test_spectrum.gd asserts LogReader.frame_layout returns exactly
## round(FRAME_SECONDS * fs), so a change on either side fails rather than drifts.
const FRAME_SECONDS := 1.024

var ok := false
## Why not, when not ok. Never empty when ok is false.
var reason := ""

var rows := 0
## Derived from the t_s column rather than taken from the header, because the header's rate is
## the SIM's and the log's rows are that rate divided by `decimation`. A spectrum computed at the
## wrong sample rate is a spectrum with every frequency scaled by a constant, which looks entirely
## normal and is entirely wrong.
var sample_rate_hz := 0.0

## axis -> {"sensor_sd", "truth_sd", "ratio", "step_sd"}, all rad/s except the ratio.
var gap: Dictionary = {}

## axis -> fraction of full command that this flight's D gain spent on sensor noise, or absent
## when the log cannot support the figure. See _measure_d_cost.
var d_cost: Dictionary = {}
## Why d_cost is empty, when it is.
var d_cost_reason := ""

var mags := PackedFloat64Array()
var bin_hz := 0.0
var frames := 0
var skipped_frames := 0
var spectrum_reason := ""

## Where the vibration model SAYS the mode is. A guess (VibrationModel.REFERENCE_RESONANCE_HZ
## scaled), carried here so the pane can mark it and say what it is.
var modelled_resonance_hz := 0.0

## [{"order": int, "hz": float}] at the log's mean rotation rate.
var harmonics: Array = []

var admissible := false
## The sentence the pane prints under the spectrum. Always set, including when admissible.
var admissibility := ""


## Reads what it needs and computes everything. One entry point, because every figure here shares
## the same 180 000-row pass and doing them lazily would mean doing that pass repeatedly.
static func of(p_path: String, p_header: Dictionary) -> FlightAnalysis:
	var out := FlightAnalysis.new()

	var request := PackedStringArray([TIME_COLUMN, SPECTRUM_CHANNEL])
	for axis in AXES:
		request.append(SENSOR_PREFIX + axis + RATE_SUFFIX)
		request.append(TRUTH_PREFIX + axis + RATE_SUFFIX)
	for column_name in MOTOR_RPM_COLUMNS:
		request.append(column_name)

	var read: Dictionary = LogReader.read_columns(p_path, request)
	if not bool(read.get("ok", false)):
		out.reason = str(read.get("reason", "the log could not be read"))
		return out

	var columns: Dictionary = read.get("columns", {})
	out.rows = int(read.get("rows", 0))
	if out.rows < 2:
		out.reason = "%d rows is not a flight" % out.rows
		return out

	var times: PackedFloat64Array = columns.get(TIME_COLUMN, PackedFloat64Array())
	var span := times[times.size() - 1] - times[0] if times.size() >= 2 else 0.0
	if span <= 0.0:
		out.reason = "the clock in this log does not advance"
		return out
	out.sample_rate_hz = float(times.size() - 1) / span
	out.ok = true

	out._measure_gap(columns)
	out._measure_d_cost(p_header)
	out._take_spectrum(columns, p_header)
	out._judge_admissibility(columns, p_header)
	return out


## ---------------------------------------------------------------------------
## The gap — the number no real drone can produce about itself
## ---------------------------------------------------------------------------
##
## A physical quad has one angular rate: whatever the gyro says. There is no second instrument in
## it reporting what the airframe actually did, which is why FPV tuning is done by ear and by
## crash. Here omega IS the aircraft and gyro is what the sensor made of it, and the difference
## between them is the thing the D term amplifies into the motors.
##
## Per axis rather than one headline number, because the axes genuinely differ: the frame's
## bending modes are not symmetric and a build can be clean in roll and filthy in pitch.
func _measure_gap(p_columns: Dictionary) -> void:
	for index in AXES.size():
		var axis: String = AXES[index]
		var sensor_name := SENSOR_PREFIX + axis + RATE_SUFFIX
		var truth_name := TRUTH_PREFIX + axis + RATE_SUFFIX
		if not (p_columns.has(sensor_name) and p_columns.has(truth_name)):
			continue
		var sensor: PackedFloat64Array = p_columns[sensor_name]
		var truth: PackedFloat64Array = p_columns[truth_name]

		var sensor_stats: Dictionary = LogReader.stats(sensor, PackedFloat64Array())
		var truth_stats: Dictionary = LogReader.stats(truth, PackedFloat64Array())
		# The step deviation of the DIFFERENCE, which is the sensor-only excursion. Not the step
		# deviation of the gyro: a fast roll makes that large without any noise in it at all.
		var noise_stats: Dictionary = LogReader.stats(sensor, truth)

		var truth_sd := float(truth_stats.get("sd", 0.0))
		gap[axis] = {
			"label": AXIS_LABELS[index],
			"sensor_sd": float(sensor_stats.get("sd", 0.0)),
			"truth_sd": truth_sd,
			# INF rather than a large number when the aircraft was still. A perfectly still axis
			# with any noise on it has an unbounded ratio, and 999.9 would be a figure somebody
			# could later mistake for a measurement. Same judgement as kd_ceiling_for's INF.
			"ratio": (float(sensor_stats.get("sd", 0.0)) / truth_sd) if truth_sd > 0.0 else INF,
			"step_sd": float(noise_stats.get("step_sd", 0.0)),
		}


## ---------------------------------------------------------------------------
## What the D gain cost on this flight
## ---------------------------------------------------------------------------
##
## RateTune.noise_fraction_for is the same arithmetic the tune derivation uses, called with a
## MEASURED step noise instead of a modelled one. See its comment for why it was extracted rather
## than written out again here.
##
## REFUSED ON A DECIMATED LOG, and this is the guard worth having. `decimation: 4` means the log
## holds every fourth row, so the difference between consecutive ROWS is the change over four
## sample periods — roughly twice the step, by a random walk — while the D term ran on every
## sample. The figure would come out high by about the square root of the decimation, look
## plausible, and be wrong. A missing number is recoverable; a wrong one is not.
func _measure_d_cost(p_header: Dictionary) -> void:
	var tune: Variant = p_header.get("tune", null)
	if not tune is Dictionary:
		d_cost_reason = "this flight did not record its tune, so what D cost cannot be computed."
		return

	var decimation := int(p_header.get("decimation", 1))
	if decimation != 1:
		d_cost_reason = ("recorded with decimation %d, so consecutive rows are %d sample periods"
			+ " apart. The D term ran on every sample and this log does not contain them.") % [
			decimation, decimation]
		return

	var gyro: Dictionary = p_header.get("gyro", {})
	var gyro_rate := float(gyro.get("sample_rate_hz", 0.0))
	if gyro_rate <= 0.0:
		d_cost_reason = "this log does not state its gyro sample rate."
		return

	var tune_map: Dictionary = tune
	for index in AXES.size():
		var axis: String = AXES[index]
		var label: String = AXIS_LABELS[index]
		if not (gap.has(axis) and tune_map.has(label)):
			continue
		var gains: Dictionary = tune_map[label]
		var kd := float(gains.get("d", 0.0))
		if kd <= 0.0:
			continue
		var step_sd := float(gap[axis]["step_sd"])
		d_cost[axis] = {
			"label": label,
			"kd": kd,
			"step_sd": step_sd,
			"fraction": RateTune.noise_fraction_for(step_sd, gyro_rate, kd),
		}


## ---------------------------------------------------------------------------
## The spectrum
## ---------------------------------------------------------------------------

func _take_spectrum(p_columns: Dictionary, p_header: Dictionary) -> void:
	var vibration: Dictionary = p_header.get("vibration_model", {})
	modelled_resonance_hz = float(vibration.get("resonance_hz", 0.0))

	if not p_columns.has(SPECTRUM_CHANNEL):
		spectrum_reason = "this log has no %s column." % SPECTRUM_CHANNEL
		return
	var samples: PackedFloat64Array = p_columns[SPECTRUM_CHANNEL]
	var result: Dictionary = LogReader.spectrum(samples, sample_rate_hz)
	if not bool(result.get("ok", false)):
		spectrum_reason = str(result.get("reason", "the transform failed"))
		return
	mags = result.get("mags", PackedFloat64Array())
	bin_hz = float(result.get("bin_hz", 0.0))
	frames = int(result.get("frames", 0))
	skipped_frames = int(result.get("skipped", 0))
	if skipped_frames > 0:
		spectrum_reason = ("%d analysis frame%s dropped for containing unreadable samples."
			% [skipped_frames, "" if skipped_frames == 1 else "s"])

	harmonics = _mean_harmonics(p_columns, p_header)


## Where the rpm lines sit on average, so the pane can say which bumps are the motors.
##
## The MEAN rotation rate over the whole log, and that is an honest summary only when the rpm was
## steady — which is exactly what the smear half of the admissibility check measures. On a log
## that failed it, these marks are the average of a moving line and the pane says so.
func _mean_harmonics(p_columns: Dictionary, p_header: Dictionary) -> Array:
	var total := 0.0
	var counted := 0
	for column_name in MOTOR_RPM_COLUMNS:
		if not p_columns.has(column_name):
			continue
		var motor_stats: Dictionary = LogReader.stats(p_columns[column_name], PackedFloat64Array())
		if int(motor_stats.get("n", 0)) == 0:
			continue
		total += float(motor_stats.get("mean", 0.0))
		counted += 1
	if counted == 0:
		return []

	var rot_hz := (total / float(counted)) / 60.0
	var out: Array = []
	for order in _orders(p_header):
		var hz := rot_hz * float(order)
		if hz > 0.0 and bin_hz > 0.0 and hz < bin_hz * float(mags.size() - 1):
			out.append({"order": order, "hz": hz})
	return out


func _orders(p_header: Dictionary) -> Array:
	var aircraft: Dictionary = p_header.get("aircraft", {})
	var blades := int(aircraft.get("blades", 0))
	var orders := BASE_ORDERS.duplicate()
	if blades > 0 and not orders.has(blades):
		orders.append(blades)
	orders.sort()
	return orders


## ---------------------------------------------------------------------------
## Whether this log can support a statement about a mode
## ---------------------------------------------------------------------------

func _judge_admissibility(p_columns: Dictionary, p_header: Dictionary) -> void:
	var blocks: Array[String] = []

	if frames < MIN_FRAMES:
		blocks.append("only %d analysis frames of %.3f s" % [frames, FRAME_SECONDS])
	var jumps := int(p_header.get("discontinuities", 0))
	if jumps > 0:
		blocks.append("%d respawn teleport%s in the rows" % [jumps, "" if jumps == 1 else "s"])

	var layout: Dictionary = LogReader.frame_layout(rows, sample_rate_hz)
	var frame_len := int(layout.get("frame_len", 0))
	var hop := int(layout.get("hop", 1))
	var top_order := 1
	for order in _orders(p_header):
		top_order = maxi(top_order, int(order))

	var sharp := 0
	var judged := 0
	var swept_lo := INF
	var swept_hi := -INF
	for column_name in MOTOR_RPM_COLUMNS:
		if not p_columns.has(column_name):
			continue
		var extents: Dictionary = LogReader.frame_extents(p_columns[column_name], frame_len, hop)
		var lo: PackedFloat64Array = extents.get("lo", PackedFloat64Array())
		var hi: PackedFloat64Array = extents.get("hi", PackedFloat64Array())
		for i in lo.size():
			if is_nan(lo[i]) or is_nan(hi[i]):
				continue
			var line_lo := (lo[i] / 60.0) * float(top_order)
			var line_hi := (hi[i] / 60.0) * float(top_order)
			judged += 1
			if line_hi - line_lo <= MAX_SMEAR_BINS * bin_hz:
				sharp += 1
			swept_lo = minf(swept_lo, line_lo)
			swept_hi = maxf(swept_hi, line_hi)

	var sharp_fraction := float(sharp) / float(judged) if judged > 0 else 0.0
	if judged == 0:
		blocks.append("no motor rpm columns to track a harmonic with")
	elif sharp_fraction < MIN_SHARP_FRACTION:
		blocks.append(("the %dx line moves more than %.0f Hz within a single frame in %.0f%% of"
			+ " frames") % [top_order, MAX_SMEAR_BINS * bin_hz, (1.0 - sharp_fraction) * 100.0])

	# Coverage, resonance_analysis pre-registration 4: a sweep that never reached the modelled
	# frequency has not tested it, and a peak at the edge of the swept range is a property of
	# where the sweep stopped.
	if modelled_resonance_hz > 0.0 and judged > 0:
		var need_lo := modelled_resonance_hz * (1.0 - MIN_COVERAGE_SPAN)
		var need_hi := modelled_resonance_hz * (1.0 + MIN_COVERAGE_SPAN)
		if swept_lo > need_lo or swept_hi < need_hi:
			blocks.append(("the harmonics swept %.0f-%.0f Hz and did not cross %.0f-%.0f Hz around"
				+ " the modelled mode") % [swept_lo, swept_hi, need_lo, need_hi])

	admissible = blocks.is_empty() and not mags.is_empty()
	if not mags.is_empty() and admissible:
		admissibility = ("The harmonics are sharp and swept across the modelled mode, so a peak"
			+ " here would be worth measuring — with tools/resonance_analysis.py, which has the"
			+ " protocol. Studio does not name peaks.")
	elif mags.is_empty():
		admissibility = "No spectrum: " + spectrum_reason
	else:
		admissibility = ("This flight cannot support a statement about a resonance: "
			+ ", ".join(blocks) + ". The curve is what the sensor saw; it is not evidence about"
			+ " the airframe.")
