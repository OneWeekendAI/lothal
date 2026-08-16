class_name TestSpectrum
extends RefCounted
## The report pane: the FFT, the figures computed from a log, and what they refuse to claim
## (LTHL-20).
##
## ===========================================================================
## THE CROSSCHECK, AND WHY IT IS A FILE ON DISK
## ===========================================================================
##
## rust/src/spectrum.rs is a SECOND IMPLEMENTATION of a law tools/resonance_analysis.py already
## has. logs.md names that as the failure the recorder derives nothing in order to avoid, and
## tests/rust_crosscheck_tier2.gd is the precedent for the only thing that makes it acceptable:
## something has to force the two to agree.
##
## That something cannot be a live Python call. This suite runs headless in CI with no numpy and
## no promised interpreter, and a crosscheck that skips itself when Python is missing is a
## crosscheck that will skip itself forever.
##
## So Python runs by hand, via tools/spectrum_oracle.py, and leaves its answer in
## tests/fixtures/spectrum_oracle.json next to the exact samples it was fed. This suite compares
## against the file, bin for bin.
##
## WINDOWING AND DETRENDING ARE FIXED BY THE CROSSCHECK RATHER THAN DISCOVERED BY IT. Both are
## choices — impact_analysis.py's finding that a Hann window destroys a ringdown is the standing
## reminder — and two implementations that chose independently would compare two different
## questions and agree about neither. The oracle signal carries a DC offset of 3.0 for exactly
## this reason: an implementation that skipped the per-frame mean removal would agree with Python
## across the whole band except the first few bins, which is where a slow log's structure lives.
##
## ===========================================================================
## THE ADMISSIBILITY FIXTURE, AND WHY IT IS SYNTHETIC
## ===========================================================================
##
## Every other Studio fixture is written through the real recorder, deliberately, so the suite
## cannot agree with itself about a header format the recorder has since changed. The
## admissibility fixtures cannot be.
##
## An ADMISSIBLE log is one whose tracked harmonic stays inside a few bins across one 1.024 s
## frame AND sweeps across the modelled mode. Those two pull against each other, and the amount
## of flight that satisfies both is set by physics rather than by convenience:
##
##     the harmonic must cross +-25% of a 180 Hz mode        -> about 108 Hz of sweep
##     it may move at most ~3.9 Hz within one 1.024 s frame  -> at most ~3.8 Hz/s
##                                                           -> AT LEAST 28 SECONDS
##
## which is why tools/record_sweep.gd flies 120. Twenty-eight seconds of the real sim at 1 kHz is
## 28 000 rows through the full flight loop, per test run.
##
## So these two fixtures carry a REAL RECORDER HEADER — read back from a real log and patched in
## the four fields the check reads — with synthetic rows underneath it. The header format still
## comes from the recorder. What is hand-made is the flight, which is the part being varied.
##
## THE POINT OF HAVING BOTH: a check that only ever produces "inadmissible" is a check that
## cannot fail, and admissibility is the single easiest thing in this file to get permanently
## stuck at "no" — every plausible-looking bug in the smear or coverage arithmetic refuses
## everything. So one fixture is built to pass and one to fail, and the pair is the test.

const TEST_DIR := "user://test_spectrum_logs"
const ORACLE_JSON := "res://tests/fixtures/spectrum_oracle.json"
## .txt rather than .csv: Godot imports any .csv under res:// as a Translation resource.
const ORACLE_SIGNAL := "res://tests/fixtures/spectrum_signal.txt"

## Relative agreement required between the Rust spectrum and Python's, per bin.
##
## 1e-9 rather than 1e-12: the two run different FFT algorithms (rustfft's mixed radix against
## numpy's pocketfft) over 1024 points, so the last few ulps genuinely differ and demanding they
## do not would be asserting that two libraries share an implementation. Nine digits is four
## orders of magnitude tighter than any difference a windowing or detrending disagreement could
## hide in — the DC-offset case below moves bin 0 by a factor of thousands.
const CROSSCHECK_TOLERANCE := 1e-9

## The synthetic sweep. See the class header for where these numbers come from.
const SYNTH_RATE_HZ := 500.0
const SYNTH_SECONDS := 32.0
const SYNTH_MODE_HZ := 180.0
## Blade-pass, and the top tracked order for the reference build's three-blade props.
const SYNTH_ORDER := 3


static func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for entry in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [TEST_DIR, entry]))
	DirAccess.remove_absolute(absolute)


static func _fresh_dir() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))


static func run() -> Array:
	var results: Array = []
	results.append_array(_test_crosscheck_against_python())
	results.append_array(_test_frame_layout_is_pinned())
	results.append_array(_test_spectrum_refuses_rather_than_crashes())
	results.append_array(_test_stats())
	results.append_array(_test_frame_extents())
	results.append_array(_test_analysis_of_a_real_flight())
	results.append_array(_test_admissibility())
	results.append_array(_test_report_pane())
	results.append_array(_test_rust_source())
	_clean()
	return results


## ---------------------------------------------------------------------------
## The crosscheck
## ---------------------------------------------------------------------------

static func _test_crosscheck_against_python() -> Array:
	var results: Array = []

	var oracle: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORACLE_JSON))
	if parsed is Dictionary:
		oracle = parsed
	# A MISSING OR UNPARSEABLE ORACLE IS A FAILURE, not a skip. The whole point of the file is to
	# be the thing that cannot quietly stop being checked; "no oracle, no complaint" is how a
	# crosscheck disappears.
	if oracle.is_empty():
		results.append(TestResult.new("the Python spectrum oracle is present and parses", false,
			"%s missing or malformed — regenerate with tools/spectrum_oracle.py" % ORACLE_JSON))
		return results

	var samples := PackedFloat64Array()
	for line in FileAccess.get_file_as_string(ORACLE_SIGNAL).split("\n"):
		if not line.strip_edges().is_empty():
			samples.append(line.to_float())

	var fs := float(oracle.get("sample_rate_hz", 0.0))
	var expected: Array = oracle.get("mags", [])
	results.append(TestResult.new("the oracle signal and its spectrum are the same length as generated",
		samples.size() == 6000 and expected.size() == 513,
		"%d samples, %d bins" % [samples.size(), expected.size()]))

	var got: Dictionary = LogReader.spectrum(samples, fs)
	results.append(TestResult.new("the Rust spectrum runs on the oracle signal",
		bool(got.get("ok", false)), str(got.get("reason", "ok"))))
	if not bool(got.get("ok", false)):
		return results

	# The frame layout has to match before the bins can be compared: two spectra of different
	# frame lengths disagreeing tells you nothing about windowing.
	results.append(TestResult.new(
		"Rust and Python frame the signal identically — same length, same hop, same count",
		int(got.get("frame_len", 0)) == int(oracle.get("frame_len", -1))
			and int(got.get("hop", 0)) == int(oracle.get("hop", -1))
			and int(got.get("frames", 0)) == int(oracle.get("frames", -1)),
		"rust %d/%d/%d vs python %d/%d/%d" % [
			int(got.get("frame_len", 0)), int(got.get("hop", 0)), int(got.get("frames", 0)),
			int(oracle.get("frame_len", -1)), int(oracle.get("hop", -1)),
			int(oracle.get("frames", -1))]))

	var mags: PackedFloat64Array = got.get("mags", PackedFloat64Array())
	var worst := 0.0
	var worst_bin := -1
	var compared := mini(mags.size(), expected.size())
	for bin in compared:
		var want := float(expected[bin])
		var scale := maxf(absf(want), 1e-12)
		var relative := absf(mags[bin] - want) / scale
		if relative > worst:
			worst = relative
			worst_bin = bin
	results.append(TestResult.new(
		"the Rust spectrum agrees with resonance_analysis.spectrogram bin for bin",
		mags.size() == expected.size() and worst <= CROSSCHECK_TOLERANCE,
		"worst relative difference %s at bin %d of %d" % [worst, worst_bin, compared]))

	# THE DETREND, ASSERTED SEPARATELY FROM THE ORACLE. The comparison above would also catch a
	# missing per-frame mean removal, but only as "bin 0 is wrong by 4e5" with no hint of why.
	# The oracle signal carries a DC offset of exactly 3.0; if the mean is removed, bin 0 is
	# noise, and if it is not, bin 0 is the largest number in the array by three orders of
	# magnitude. Deleting the mean subtraction in spectrum.rs fails this line by itself.
	var loudest := 0.0
	for value in mags:
		loudest = maxf(loudest, value)
	results.append(TestResult.new(
		"the per-frame mean is removed — a DC offset of 3.0 does not appear in bin 0",
		mags.size() > 0 and mags[0] < loudest * 0.05,
		"bin 0 is %.4f against a peak of %.4f" % [mags[0] if mags.size() > 0 else NAN, loudest]))

	# The fixture's fixed 183.4 Hz tone. A frame-length or window error moves it; a sample-rate
	# error scales it. Neither is visible in "the two implementations agree" if both are wrong in
	# the same way, and both being wrong in the same way is what a shared constant makes possible.
	var mode_hz := float(oracle.get("mode_hz", 0.0))
	var bin_hz := float(got.get("bin_hz", 0.0))
	var mode_bin := int(round(mode_hz / bin_hz)) if bin_hz > 0.0 else -1
	var local_peak := 0.0
	for offset in range(-2, 3):
		var bin: int = mode_bin + offset
		if bin >= 0 and bin < mags.size():
			local_peak = maxf(local_peak, mags[bin])
	var neighbourhood := 0.0
	for offset in [-40, -30, 30, 40]:
		var bin: int = mode_bin + int(offset)
		if bin >= 0 and bin < mags.size():
			neighbourhood = maxf(neighbourhood, mags[bin])
	results.append(TestResult.new(
		"the fixture's %.1f Hz tone lands where it was put" % mode_hz,
		mode_bin > 0 and local_peak > neighbourhood * 4.0,
		"bin %d reads %.4f against %.4f nearby" % [mode_bin, local_peak, neighbourhood]))

	return results


## The three copies of 1.024 — Python's, Rust's and FlightAnalysis's — pinned to each other.
##
## Fails the moment any one of them moves, which is the only thing that makes a restated constant
## safe. Without this the GDScript label could say "1.024 s frames" over a spectrum computed with
## something else, and the label is the only place a builder can see the number at all.
static func _test_frame_layout_is_pinned() -> Array:
	var results: Array = []
	for fs in [1000.0, 500.0, 8000.0]:
		var layout: Dictionary = LogReader.frame_layout(100000, fs)
		var want_len := int(round(FlightAnalysis.FRAME_SECONDS * fs))
		results.append(TestResult.new(
			"at %.0f Hz the Rust frame is round(FlightAnalysis.FRAME_SECONDS * fs)" % fs,
			int(layout.get("frame_len", 0)) == want_len,
			"%d vs %d" % [int(layout.get("frame_len", 0)), want_len]))
		results.append(TestResult.new(
			"at %.0f Hz the hop is 25%% of the frame — 75%% overlap, as pre-registered" % fs,
			int(layout.get("hop", 0)) == int(round(float(want_len) * 0.25)),
			"hop %d of frame %d" % [int(layout.get("hop", 0)), want_len]))
	return results


## panic = "abort" means a bad input is a process death, not an exception. Each of these is a
## shape a real file produces: a flight shorter than one frame, an empty channel, a nonsense rate.
static func _test_spectrum_refuses_rather_than_crashes() -> Array:
	var results: Array = []

	var short := PackedFloat64Array()
	for i in 100:
		short.append(sin(float(i)))
	var cases := {
		"a trace shorter than one analysis frame": LogReader.spectrum(short, 1000.0),
		"an empty channel": LogReader.spectrum(PackedFloat64Array(), 1000.0),
		"a zero sample rate": LogReader.spectrum(short, 0.0),
		"a negative sample rate": LogReader.spectrum(short, -1000.0),
	}
	for label in cases:
		var result: Dictionary = cases[label]
		results.append(TestResult.new(
			"%s comes back as a reason, not a crash" % label,
			not bool(result.get("ok", true)) and not str(result.get("reason", "")).is_empty(),
			str(result.get("reason", "(no reason given)"))))

	# A NaN is what LogReader writes into a cell that will not parse, so this is the shape of a
	# hand-edited log rather than a hypothetical. The frame carrying it goes; the rest stay.
	var withnan := PackedFloat64Array()
	for i in 4000:
		withnan.append(sin(TAU * 200.0 * float(i) / 1000.0))
	withnan[5] = NAN
	var nan_result: Dictionary = LogReader.spectrum(withnan, 1000.0)
	var nan_mags: PackedFloat64Array = nan_result.get("mags", PackedFloat64Array())
	var all_finite := true
	for value in nan_mags:
		all_finite = all_finite and is_finite(value)
	results.append(TestResult.new(
		"one unreadable sample drops its own frame and leaves the rest of the spectrum finite",
		bool(nan_result.get("ok", false)) and int(nan_result.get("skipped", 0)) > 0
			and int(nan_result.get("frames", 0)) > 0 and all_finite,
		"%d frames averaged, %d skipped, all finite: %s" % [
			int(nan_result.get("frames", 0)), int(nan_result.get("skipped", 0)), all_finite]))

	return results


## ---------------------------------------------------------------------------
## The array primitives
## ---------------------------------------------------------------------------

static func _test_stats() -> Array:
	var results: Array = []

	# Hand-computed: mean 3, population variance ((4+1+0+1+4)/5) = 2, sd = sqrt(2).
	var series := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var plain: Dictionary = LogReader.stats(series, PackedFloat64Array())
	results.append(TestResult.new("stats reports the population sd, matching np.std and RateTune",
		absf(float(plain.get("sd", 0.0)) - sqrt(2.0)) < 1e-12
			and absf(float(plain.get("mean", 0.0)) - 3.0) < 1e-12,
		"mean %.6f sd %.6f" % [float(plain.get("mean", 0.0)), float(plain.get("sd", 0.0))]))
	results.append(TestResult.new("stats reports the step sd — every step here is exactly 1",
		absf(float(plain.get("step_sd", 0.0)) - 1.0) < 1e-12,
		"%.6f" % float(plain.get("step_sd", 0.0))))

	# The subtract path, which is how the gap gets the sensor-only excursion. Identical arrays
	# have a difference of zero, and a zero-sd result is the honest answer for a perfect sensor.
	var same: Dictionary = LogReader.stats(series, series)
	results.append(TestResult.new("stats of a channel minus itself is flat",
		float(same.get("sd", -1.0)) == 0.0 and float(same.get("step_sd", -1.0)) == 0.0,
		"sd %.6f" % float(same.get("sd", -1.0))))

	var offset := PackedFloat64Array([0.5, 0.5, 0.5, 0.5, 0.5])
	var difference: Dictionary = LogReader.stats(series, offset)
	results.append(TestResult.new("stats of a - b uses the difference, not either side",
		absf(float(difference.get("mean", 0.0)) - 2.5) < 1e-12,
		"mean %.6f" % float(difference.get("mean", 0.0))))

	# A STEP ACROSS A SKIPPED SAMPLE IS NOT A STEP. Here the readable values are 1 and 3 with a
	# NaN between them; counting 3 - 1 = 2 as one step would report a difference accumulated over
	# two sample periods as if it happened in one, which is the exact quantity a D gain divides
	# by the period. Removing the `previous = None` line in stats() fails this.
	var gapped := PackedFloat64Array([1.0, NAN, 3.0, 4.0])
	var gapped_stats: Dictionary = LogReader.stats(gapped, PackedFloat64Array())
	results.append(TestResult.new(
		"a step across an unreadable sample is not counted as a step",
		int(gapped_stats.get("n", 0)) == 3
			and absf(float(gapped_stats.get("step_sd", 0.0)) - 1.0) < 1e-12,
		"n=%d step_sd=%.6f (2.0 would mean the gap was counted)" % [
			int(gapped_stats.get("n", 0)), float(gapped_stats.get("step_sd", 0.0))]))

	# A dead-still channel. sum_sq/n - mean^2 goes very slightly negative here and sqrt of that
	# is NaN, which would be read as a broken sensor rather than a still one.
	var constant := PackedFloat64Array()
	for _i in 500:
		constant.append(1234.5678)
	var constant_stats: Dictionary = LogReader.stats(constant, PackedFloat64Array())
	results.append(TestResult.new("a perfectly constant channel reports zero sd, not NaN",
		is_finite(float(constant_stats.get("sd", NAN)))
			and float(constant_stats.get("sd", 1.0)) < 1e-9,
		"sd = %s" % float(constant_stats.get("sd", NAN))))

	var empty_stats: Dictionary = LogReader.stats(PackedFloat64Array(), PackedFloat64Array())
	results.append(TestResult.new("stats of nothing is zeroes and n = 0, not a crash",
		int(empty_stats.get("n", -1)) == 0, "n=%d" % int(empty_stats.get("n", -1))))

	return results


static func _test_frame_extents() -> Array:
	var results: Array = []

	# A ramp 0..9, frames of 4 with a hop of 2: [0,1,2,3] [2,3,4,5] [4,5,6,7] [6,7,8,9].
	var ramp := PackedFloat64Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0])
	var extents: Dictionary = LogReader.frame_extents(ramp, 4, 2)
	var lo: PackedFloat64Array = extents.get("lo", PackedFloat64Array())
	var hi: PackedFloat64Array = extents.get("hi", PackedFloat64Array())
	results.append(TestResult.new("frame_extents walks the same overlapping grid the spectrum does",
		lo.size() == 4 and hi.size() == 4 and lo[0] == 0.0 and hi[0] == 3.0
			and lo[3] == 6.0 and hi[3] == 9.0,
		"%d frames, first [%.0f, %.0f], last [%.0f, %.0f]" % [lo.size(),
			lo[0] if lo.size() > 0 else NAN, hi[0] if hi.size() > 0 else NAN,
			lo[3] if lo.size() > 3 else NAN, hi[3] if hi.size() > 3 else NAN]))

	# A frame with a NaN in it yields NaN rather than the min/max of its readable part: a smear
	# measured over half a frame is not the smear over the frame, and reporting it as if it were
	# would make a log look steadier the more of it was unreadable.
	var holed := PackedFloat64Array([0.0, NAN, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
	var holed_extents: Dictionary = LogReader.frame_extents(holed, 4, 2)
	var holed_lo: PackedFloat64Array = holed_extents.get("lo", PackedFloat64Array())
	results.append(TestResult.new(
		"a frame containing an unreadable sample reports NaN, not the range of what was readable",
		holed_lo.size() == 3 and is_nan(holed_lo[0]) and not is_nan(holed_lo[2]),
		"first %s, last %s" % [holed_lo[0] if holed_lo.size() > 0 else NAN,
			holed_lo[2] if holed_lo.size() > 2 else NAN]))

	var too_short: Dictionary = LogReader.frame_extents(ramp, 40, 2)
	var short_lo: PackedFloat64Array = too_short.get("lo", PackedFloat64Array())
	results.append(TestResult.new("a trace shorter than one frame has no frames, and does not crash",
		short_lo.is_empty(), "%d frames" % short_lo.size()))

	return results


## ---------------------------------------------------------------------------
## FlightAnalysis on something the recorder actually wrote
## ---------------------------------------------------------------------------

static func _test_analysis_of_a_real_flight() -> Array:
	var results: Array = []
	_fresh_dir()

	# Long enough for several analysis frames at 1 kHz. Hover, sticks centred — the profile
	# LTHL-18 established cannot support a resonance measurement, which is the point: it is what
	# a builder's first log will be.
	var path := _write_real_log("flight-20260816-120000.csv", 6000, 1)
	var head := FlightRecorder.read_header(path)
	var analysis := FlightAnalysis.of(path, head)

	results.append(TestResult.new("FlightAnalysis reads a recorder-written log",
		analysis.ok, analysis.reason if not analysis.ok else "%d rows" % analysis.rows))
	if not analysis.ok:
		return results

	# Derived from t_s, not taken from the header. A log written with decimation has a row rate
	# that is the sim's divided by it, and every frequency in the spectrum scales with this.
	results.append(TestResult.new("the sample rate is derived from the log's own clock",
		absf(analysis.sample_rate_hz - 1000.0) < 1.0, "%.2f Hz" % analysis.sample_rate_hz))

	results.append(TestResult.new("the gyro-vs-omega gap is reported for all three axes",
		analysis.gap.size() == 3 and analysis.gap.has("x"),
		"axes: %s" % ", ".join(analysis.gap.keys())))

	var roll: Dictionary = analysis.gap.get("x", {})
	# The sensor must report MORE motion than the aircraft had. If it reported less, either the
	# columns are swapped or the gyro is a lowpass with no noise in it, and both would make every
	# figure in this pane a lie in the flattering direction.
	results.append(TestResult.new(
		"the sensor reports more motion than the aircraft had — the gap points the right way",
		float(roll.get("sensor_sd", 0.0)) > float(roll.get("truth_sd", 0.0)),
		"gyro sd %.5f vs omega sd %.5f, ratio %.2f" % [float(roll.get("sensor_sd", 0.0)),
			float(roll.get("truth_sd", 0.0)), float(roll.get("ratio", 0.0))]))

	results.append(TestResult.new("what the D gain cost is reported for the axes that have one",
		not analysis.d_cost.is_empty(),
		analysis.d_cost_reason if analysis.d_cost.is_empty()
			else "roll %.3f%%" % (float(analysis.d_cost["x"]["fraction"]) * 100.0)))

	# The same law, not a second spelling of it. Studio's figure is RateTune.noise_fraction_for
	# fed the measured step noise; if this file recomputed the arithmetic instead, the two would
	# be free to drift and this check would be comparing a function against a copy of itself.
	if analysis.d_cost.has("x"):
		var roll_cost: Dictionary = analysis.d_cost["x"]
		var direct := RateTune.noise_fraction_for(float(roll_cost["step_sd"]),
			float(head.get("gyro", {}).get("sample_rate_hz", 0.0)), float(roll_cost["kd"]))
		results.append(TestResult.new(
			"the D cost is RateTune's arithmetic, not a copy of it living in Studio",
			absf(direct - float(roll_cost["fraction"])) < 1e-12,
			"%.9f vs %.9f" % [direct, float(roll_cost["fraction"])]))

	results.append(TestResult.new("a spectrum comes back with bins and a resolution",
		analysis.mags.size() > 100 and analysis.bin_hz > 0.0,
		"%d bins at %.4f Hz, %d frames" % [analysis.mags.size(), analysis.bin_hz,
			analysis.frames]))

	results.append(TestResult.new("the rpm harmonics are marked from the log's own motor columns",
		not analysis.harmonics.is_empty(),
		"orders: %s" % ", ".join(analysis.harmonics.map(
			func(h: Dictionary) -> String: return "%dx@%.0fHz" % [h["order"], h["hz"]]))))

	# THE DECIMATION GUARD. A log holding every fourth row has consecutive rows four sample
	# periods apart, so its step noise is roughly twice the real one and the D cost would come
	# out high by about that factor — plausible, and wrong. Deleting the guard in
	# _measure_d_cost makes this line green and the number silently overstated.
	var decimated_path := _write_real_log("flight-20260816-130000.csv", 4000, 4)
	var decimated := FlightAnalysis.of(decimated_path, FlightRecorder.read_header(decimated_path))
	results.append(TestResult.new(
		"a decimated log refuses the D cost instead of overstating it",
		decimated.ok and decimated.d_cost.is_empty()
			and decimated.d_cost_reason.contains("decimation"),
		decimated.d_cost_reason if decimated.d_cost.is_empty() else "reported it anyway"))

	# The gap survives decimation — sd of a channel does not care about the row spacing, only the
	# STEP statistic does. Refusing both would be over-correcting into a blank pane.
	results.append(TestResult.new(
		"a decimated log still reports the gap, because a spread is not a step",
		decimated.gap.size() == 3, "%d axes" % decimated.gap.size()))

	return results


## ---------------------------------------------------------------------------
## Admissibility, in both directions
## ---------------------------------------------------------------------------

static func _test_admissibility() -> Array:
	var results: Array = []
	_fresh_dir()

	# A hover log: the rpm sits still, so the harmonics are parked and cannot be told apart from
	# whatever they are sitting on. resonance_analysis.coverage, pre-registration 4.
	var hover := _write_real_log("flight-20260816-140000.csv", 6000, 1)
	var hover_analysis := FlightAnalysis.of(hover, FlightRecorder.read_header(hover))
	results.append(TestResult.new(
		"a hover log is refused: its harmonics never sweep across the modelled mode",
		not hover_analysis.admissible and hover_analysis.admissibility.contains("cannot support"),
		hover_analysis.admissibility))

	# The one that makes the pair a test. See the class header: a check that only ever says "no"
	# is a check that cannot fail, and every plausible bug in this arithmetic says no.
	var swept := _write_synthetic_sweep("flight-20260816-150000.csv", SYNTH_SECONDS)
	var swept_analysis := FlightAnalysis.of(swept, FlightRecorder.read_header(swept))
	results.append(TestResult.new(
		"a slow sweep across the modelled mode IS admissible",
		swept_analysis.ok and swept_analysis.admissible,
		swept_analysis.admissibility if swept_analysis.ok else swept_analysis.reason))

	# Same sweep, same span, eight times faster. Only the smear changes, so a failure here is the
	# smear rule doing its job rather than the coverage rule doing it twice.
	var fast := _write_synthetic_sweep("flight-20260816-160000.csv", SYNTH_SECONDS / 8.0)
	var fast_analysis := FlightAnalysis.of(fast, FlightRecorder.read_header(fast))
	results.append(TestResult.new(
		"the same sweep flown eight times faster is refused for smear",
		fast_analysis.ok and not fast_analysis.admissible
			and fast_analysis.admissibility.contains("within a single frame"),
		fast_analysis.admissibility if fast_analysis.ok else fast_analysis.reason))

	# Even when refused, the curve is still drawn. A pane that went blank would lose the one
	# thing a builder can always do with a spectrum, which is look at it.
	results.append(TestResult.new(
		"a refused log still gets its spectrum — the refusal is about meaning, not drawing",
		not hover_analysis.mags.is_empty(), "%d bins" % hover_analysis.mags.size()))

	# STUDIO NAMES NO PEAKS, and the admissible case is where it would be most tempting to. If a
	# resonance ever appears in this class's surface, tools/resonance_analysis.py's
	# pre-registration has been reimplemented in a UI panel with none of it carried across.
	var surface := FileAccess.get_file_as_string("res://src/lab/flight_analysis.gd")
	var code := TestPidTunes._code_only(surface)
	results.append(TestResult.new(
		"FlightAnalysis exposes no measured resonance — finding a mode has a protocol and it is not here",
		not code.contains("measured_resonance") and not code.contains("func peak"),
		"no peak-finding surface"))

	return results


## ---------------------------------------------------------------------------
## The pane
## ---------------------------------------------------------------------------

static func _test_report_pane() -> Array:
	var results: Array = []
	_fresh_dir()
	var path := _write_real_log("flight-20260816-170000.csv", 6000, 1)
	var id := path.get_file()

	var screen := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	var opened := screen.select(id)
	results.append(TestResult.new("the report pane opens on a real flight", opened,
		"selected %s" % id))
	if not opened:
		screen.free()
		return results

	var labels := _labels_of(screen)
	var text := "\n".join(labels)

	results.append(TestResult.new("the gap is on the pane, in the units it was measured in",
		text.contains("THE VERDICT") and text.contains("rad/s sd"),
		"pane has %d labels" % labels.size()))
	results.append(TestResult.new("what the D gain cost is on the pane",
		text.contains("WHAT D COST"), "found" if text.contains("WHAT D COST") else "absent"))

	# THE CAVEAT TRAVELS WITH THE NUMBER, and that is a placement requirement rather than a
	# content one. The spectrum carries a dashed line labelled "model" anchored on a constant
	# nobody has sourced; the sentence saying so has to be in the same pane as the mark, not in a
	# tooltip or a footnote. Moving it to either fails this line.
	var spectrum_view := screen._spectrum
	results.append(TestResult.new(
		"the tier-three caveat is in the same pane as the spectrum it is about",
		spectrum_view != null and spectrum_view.get_parent() == screen._report
			and text.contains("characteristic model, not predictive"),
		"caveat present: %s" % text.contains("characteristic model, not predictive")))

	results.append(TestResult.new(
		"the admissibility refusal is on the pane for a log that cannot support a measurement",
		text.contains("cannot support a statement about a resonance"),
		"present" if text.contains("cannot support a statement about a resonance") else "absent"))

	# THE GAP IS THE LARGEST TEXT, which the design asked for and which no other check here would
	# notice the loss of. Asserted as a comparison against every other label's font size rather
	# than as "it uses SubHeroReadoutLabel", because the variation name could stay while the theme
	# stopped making it big.
	# Sizes come from LothalTheme rather than from get_theme_font_size(), because this screen is
	# never added to a tree — the suite constructs, drives and frees, so a Control here has no
	# theme to inherit and every label would report the same fallback 16.
	var theme := LothalTheme.get_theme()
	var hero_size := 0
	var other_size := 0
	for label: Label in _label_nodes(screen._report):
		var font_size := theme.get_font_size("font_size", str(label.theme_type_variation))
		# All three axes, not just roll. Matching only "roll" put the pitch and yaw heroes in the
		# "everything else" bucket, and the check compared 26 px against 26 px and failed for the
		# wrong reason — which is a test finding its own bug rather than the code's.
		if _is_gap_headline(str(label.text)):
			hero_size = maxi(hero_size, font_size)
		else:
			other_size = maxi(other_size, font_size)
	results.append(TestResult.new(
		"the gap is the largest text on the pane — it is the reason to simulate a drone at all",
		hero_size > other_size, "%d px against everything else at %d" % [hero_size, other_size]))

	# The marks, which are most of what makes a spectrum readable. Solid lines are data (the
	# motors' mean rpm); the dashed one is the model's guess and is labelled as such.
	var marks := Array(spectrum_view.mark_labels())
	results.append(TestResult.new(
		"the spectrum is marked with the rpm harmonics and, separately, with the model's guess",
		marks.has("model") and marks.size() > 1, "marks: %s" % ", ".join(marks)))
	var dashed := 0
	for mark in spectrum_view.marks:
		if bool(mark.get("dashed", false)):
			dashed += 1
	results.append(TestResult.new(
		"exactly one mark is dashed, and it is the one that is not a measurement",
		dashed == 1, "%d dashed of %d" % [dashed, spectrum_view.marks.size()]))

	screen.free()
	return results


## The hero rows are "<axis>  <ratio>x". Recognised by their text rather than by their theme
## variation, because the variation is exactly what the assertion is about: a check that found the
## hero by asking which label was the hero would be true by construction.
static func _is_gap_headline(p_text: String) -> bool:
	for label in FlightAnalysis.AXIS_LABELS:
		if p_text.begins_with("%s  " % label):
			return true
	return false


static func _labels_of(p_screen: StudioScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for label: Label in _label_nodes(p_screen._report):
		out.append(label.text)
	return out


static func _label_nodes(p_root: Node) -> Array:
	var out: Array = []
	for child in p_root.get_children():
		if child is Label:
			out.append(child)
		out.append_array(_label_nodes(child))
	return out


## ---------------------------------------------------------------------------
## The Rust source, which the GDScript grep in test_flight_recorder.gd cannot read
## ---------------------------------------------------------------------------

static func _test_rust_source() -> Array:
	var results: Array = []
	var sources := ["res://rust/src/log_reader.rs", "res://rust/src/spectrum.rs"]
	var missing: PackedStringArray = []
	var offenders: PackedStringArray = []

	for path in sources:
		# A renamed file reads as "" and contains nothing, so absence has to be its own failure —
		# the same vacuous-pass shape the GDScript reader grep guards against.
		if not FileAccess.file_exists(path):
			missing.append(str(path).get_file())
			continue
		var source := FileAccess.get_file_as_string(path)
		# The test module is exempt: an .expect() in a #[cfg(test)] fn runs under cargo test,
		# never in the shipped dylib, and cannot abort a builder's session.
		var shipped := source.split("#[cfg(test)]")[0]
		for line in shipped.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("//"):
				continue
			if trimmed.contains(".unwrap()") or trimmed.contains(".expect("):
				offenders.append("%s: %s" % [str(path).get_file(), trimmed])
			if trimmed.contains("Build::") or trimmed.contains("PartsCatalog"):
				offenders.append("%s builds an aircraft: %s" % [str(path).get_file(), trimmed])

	results.append(TestResult.new(
		"the shipped Rust log path has no unwrap, no expect, and no route to a Build",
		offenders.is_empty() and missing.is_empty(),
		"%d files checked" % sources.size() if offenders.is_empty() and missing.is_empty()
			else "offenders: %s / missing: %s" % [", ".join(offenders), ", ".join(missing)]))
	return results


## ---------------------------------------------------------------------------
## Fixtures
## ---------------------------------------------------------------------------

## A real flight through the real recorder, so the header is the recorder's own.
static func _write_real_log(p_name: String, p_rows: int, p_decimation: int) -> String:
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	var throttle := ReferenceBuild.hover_throttle()
	core.prime_motors(throttle)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	# WITH A TUNE, unlike test_studio's fixture. The D cost is a figure about the gains that
	# actually flew, so a fixture recorded with `tune: null` would exercise only the "not
	# recorded" branch and every assertion about the number itself would be untested.
	var tune := PidTunes.load_from().tune_for(build)
	var recorder := FlightRecorder.new(build, p_decimation, tune, core.gyro)

	for _i in p_rows * p_decimation:
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, 0.001)
		core.step(cmds, 0.001)
		recorder.capture(core.observables)

	var path := "%s/%s" % [TEST_DIR, p_name]
	recorder.save(path)
	return path


## A slow rpm sweep across the modelled mode, on a real recorder header.
##
## See the class header for why this is synthetic: an admissible flight is at least 28 seconds
## long by physics, and 28 000 rows through the real sim per test run is a suite nobody runs. The
## HEADER still comes from the recorder — written, read back, and patched in the four fields the
## admissibility check reads — so the format cannot drift out from under this fixture.
static func _write_synthetic_sweep(p_name: String, p_seconds: float) -> String:
	# Sixty real rows, purely to obtain a real header to patch.
	var seed_path := _write_real_log("seed-%s" % p_name, 60, 1)
	var head := FlightRecorder.read_header(seed_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(seed_path))

	var rows := int(p_seconds * SYNTH_RATE_HZ)
	head["rows"] = rows
	head["duration_s"] = p_seconds
	head["sample_rate_hz"] = SYNTH_RATE_HZ
	head["decimation"] = 1
	head["discontinuities"] = 0
	var vibration: Dictionary = head.get("vibration_model", {})
	vibration["resonance_hz"] = SYNTH_MODE_HZ
	head["vibration_model"] = vibration

	var columns: Array = head.get("columns", [])
	var index_of: Dictionary = {}
	for i in columns.size():
		index_of[str(columns[i])] = i

	# The blade-pass line sweeps +-30% of the mode, which clears the +-25% coverage requirement
	# with a margin, over p_seconds. At SYNTH_SECONDS that is about 3.4 Hz/s, comfortably inside
	# the 4-bin smear bound; at an eighth of it, comfortably outside. Both by construction.
	var from_hz := SYNTH_MODE_HZ * 0.7
	var to_hz := SYNTH_MODE_HZ * 1.3

	var handle := FileAccess.open("%s/%s" % [TEST_DIR, p_name], FileAccess.WRITE)
	handle.store_line("#" + JSON.stringify(head))
	handle.store_line(",".join(columns))

	var blank: PackedStringArray = []
	for _i in columns.size():
		blank.append("0")

	for row in rows:
		var t := float(row) / SYNTH_RATE_HZ
		var line_hz: float = from_hz + (to_hz - from_hz) * (t / p_seconds)
		var rpm := (line_hz / float(SYNTH_ORDER)) * 60.0
		var cells := blank.duplicate()
		cells[int(index_of["t_s"])] = "%.6f" % t
		for motor in 4:
			cells[int(index_of["m%d_rpm" % (motor + 1)])] = "%.4f" % rpm
		# Something for the transform to find: the sweeping line, and the mode it crosses.
		var value := sin(TAU * line_hz * t) + 0.4 * sin(TAU * SYNTH_MODE_HZ * t)
		cells[int(index_of["gyro_x_rad_s"])] = "%.6f" % value
		handle.store_line(",".join(cells))

	handle.close()
	return "%s/%s" % [TEST_DIR, p_name]
