class_name TestGyro
extends RefCounted
## The gyro is a SENSOR, not a getter. Real firmware never sees the rigid body's true
## angular velocity; it sees a sampled, band-limited, slightly wrong estimate, and the gap
## between the two is where a large part of real drone behaviour lives — the phase lag that
## sets how hard the D term can be pushed, the noise floor that decides whether D is usable
## at all, the bias that makes a hands-off quad wander.
##
## Every check here would pass on a gyro that simply returned ground truth, EXCEPT the ones
## that name the specific things a passthrough cannot do. Those are the ones that matter,
## and they were written against a passthrough stub and watched to fail before the real
## model existed.

const DT := 0.001

## Steps a gyro with a constant true rate for a while and returns its final reading.
static func _settle(gyro: Gyro, true_rate: Vector3, duration_s: float) -> Vector3:
	var out := Vector3.ZERO
	for i in int(duration_s / DT):
		out = gyro.update(true_rate, DT)
	return out

static func run() -> Array:
	var results: Array = []

	# --- The filter exists, and it costs lag ---
	# A step in true rate must NOT appear instantly at the output. This is the check a
	# passthrough gyro cannot survive, and it is the reason the class exists.
	var stepper := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	var first := stepper.update(Vector3(0.0, 0.0, -10.0), DT)
	results.append(TestResult.new(
		"a step in true rate does not appear instantly: the low-pass costs phase lag",
		absf(first.z) < 9.0,
		"true -10.000 rad/s, gyro read %.4f rad/s on the first sample (%.0f%% of the step)"
			% [first.z, absf(first.z) / 10.0 * 100.0]
	))

	# ...and the lag is the RIGHT size. A PT1 reaches 1 - 1/e = 63.2% of a step in exactly one
	# time constant, RC = 1/(2*pi*fc). Asserting that rather than "some lag" is what separates
	# a real filter from an arbitrary smoothing factor tuned until it looked smooth.
	#
	# Sampled at 20 kHz rather than the stock 1 kHz, deliberately. The continuous 63.2% figure
	# is only what a DISCRETE PT1 approaches as the sample period shrinks against RC, and at
	# 1 kHz against a 1.06 ms RC the period is not small — see the next check, which pins that
	# down instead of hiding it.
	var tau_s := 1.0 / (TAU * Gyro.DEFAULT_CUTOFF_HZ)
	var fine_hz := 20000.0
	var fine := Gyro.new(fine_hz, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	var fine_out := Vector3.ZERO
	for i in int(tau_s * fine_hz):
		fine_out = fine.update(Vector3(0.0, 0.0, -10.0), 1.0 / fine_hz)
	var reached := absf(fine_out.z) / 10.0
	results.append(TestResult.new(
		"the low-pass is a real PT1: one time constant reaches 63.2% of a step",
		absf(reached - 0.632) < 0.02,
		"RC = %.4f ms at %.0f Hz cutoff; sampled at %.0f kHz, reached %.1f%% (expected 63.2%%)"
			% [tau_s * 1000.0, Gyro.DEFAULT_CUTOFF_HZ, fine_hz / 1000.0, reached * 100.0]
	))

	# And the honest consequence of the stock configuration, stated rather than glossed: at
	# 1 kHz the sample period is very nearly RC itself, so the discrete filter is COARSE —
	# a single sample already carries 48.5% of a step, where the continuous form would carry
	# 61%. That is a real property of the FC being modelled, not an error to be tuned away,
	# and it is why raising DEFAULT_SAMPLE_RATE_HZ changes the feel even with the cutoff held.
	var alpha := (1.0 / Gyro.DEFAULT_SAMPLE_RATE_HZ) / (tau_s + 1.0 / Gyro.DEFAULT_SAMPLE_RATE_HZ)
	var coarse := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	var one_sample := absf(coarse.update(Vector3(0.0, 0.0, -10.0), DT).z) / 10.0
	results.append(TestResult.new(
		"at the stock 1 kHz the discretisation is coarse, and the model says so exactly",
		absf(one_sample - alpha) < 0.0001,
		"one 1 ms sample carries %.1f%% of a step; alpha = dt/(RC+dt) = %.4f" % [one_sample * 100.0, alpha]
	))

	# The filter must not cost STEADY-STATE accuracy — a low-pass that changed the DC gain
	# would be a scale error on every rate the FC ever sees.
	var settled := _settle(Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO),
		Vector3(0.0, 0.0, -10.0), 0.5)
	results.append(TestResult.new(
		"the filter has unity DC gain: a held rate is eventually read exactly",
		absf(settled.z + 10.0) < 0.001,
		"after 500 ms of a true -10.000 rad/s, gyro reads %.5f rad/s" % settled.z
	))

	# --- Sampling is discrete ---
	# Between samples the reading is HELD. A gyro sampling at 200 Hz driven at 1 kHz must
	# return the identical value for four calls out of five.
	var slow := Gyro.new(200.0, 10000.0, 0.0, Vector3.ZERO)
	var readings: Array = []
	for i in 10:
		readings.append(slow.update(Vector3(0.0, 0.0, -float(i)), DT))
	var distinct := 0
	for i in range(1, readings.size()):
		if readings[i] != readings[i - 1]:
			distinct += 1
	results.append(TestResult.new(
		"sampling is discrete: a 200 Hz gyro driven at 1 kHz holds its reading between samples",
		distinct == 2,
		"%d changes across 10 calls at 1 kHz (200 Hz => a new sample every 5th call)" % distinct
	))

	# --- Bias ---
	var biased := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, 10000.0, 0.0, Vector3(0.0, 0.02, 0.0))
	var bias_read := _settle(biased, Vector3.ZERO, 0.5)
	results.append(TestResult.new(
		"a constant bias is reported as rotation the aircraft is not doing",
		absf(bias_read.y - 0.02) < 0.001,
		"stationary aircraft, gyro reads %.5f rad/s about Y against a 0.02000 bias" % bias_read.y
	))

	# --- Noise ---
	var noisy := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, 10000.0, 0.05, Vector3.ZERO)
	var spread := 0.0
	var sum := 0.0
	var n := 2000
	for i in n:
		var v := noisy.update(Vector3.ZERO, DT).x
		spread = maxf(spread, absf(v))
		sum += v
	results.append(TestResult.new(
		"noise is present when asked for, and is zero-mean",
		spread > 0.05 and absf(sum / float(n)) < 0.01,
		"peak |noise| = %.4f rad/s, mean = %.5f rad/s over %d samples at sigma 0.05" % [spread, sum / float(n), n]
	))

	# Determinism. Noise from an unseeded global RNG would make every test in this repo that
	# touches the flight loop irreproducible, which is a worse defect than having no noise.
	var a := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ, 0.05, Vector3.ZERO)
	var b := Gyro.new(Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ, 0.05, Vector3.ZERO)
	var identical := true
	for i in 500:
		if a.update(Vector3(0.1, 0.0, 0.0), DT) != b.update(Vector3(0.1, 0.0, 0.0), DT):
			identical = false
			break
	results.append(TestResult.new(
		"noise is seeded, so two identically-configured gyros produce identical traces",
		identical,
		"500 samples compared, traces %s" % ("identical" if identical else "DIVERGED")
	))

	# --- The defaults are quiet ---
	# The point of this slice is a correct architecture, not a mushy one. A default bias big
	# enough to make the aircraft wander would have replaced one bug with another.
	var stock := Gyro.new()
	var stock_read := _settle(stock, Vector3.ZERO, 1.0)
	results.append(TestResult.new(
		"stock defaults are low enough that the aircraft still flies clean (< 1 deg/s of error)",
		stock_read.length() < deg_to_rad(1.0),
		"stationary aircraft reads %.4f deg/s with default noise %.4f and bias %s"
			% [rad_to_deg(stock_read.length()), Gyro.DEFAULT_NOISE_RAD_S, Gyro.DEFAULT_BIAS_RAD_S]
	))

	results.append_array(_vibration_path_results())

	# --- Axis convention ---
	var contract := Gyro.contract_rates(Vector3(1.0, 2.0, 3.0))
	results.append(TestResult.new(
		"contract_rates maps body XYZ onto physics.md §1's roll/pitch/yaw",
		contract == Vector3(-3.0, 1.0, -2.0),
		"body (1, 2, 3) -> roll/pitch/yaw %s (+Roll about -Z, +Pitch about +X, +Yaw about -Y)" % contract
	))

	# --- It is the aircraft's sensor, not the scene's ---
	var core := ReferenceBuild.build_drone_core()
	core.rigid_body.angular_velocity_rad_s = Vector3(0.0, 0.0, -5.0)
	var before: Vector3 = core.observables.gyro_rad_s
	core.step(MotorMixer.mix(ReferenceBuild.hover_throttle(), 0.0, 0.0, 0.0), DT)
	results.append(TestResult.new(
		"DroneCore owns the gyro and publishes its reading every step",
		before == Vector3.ZERO and core.observables.gyro_rad_s != Vector3.ZERO
			and core.observables.gyro_rad_s == core.gyro.rate_rad_s,
		"published gyro went %s -> %s while true rate is %s" % [before,
			core.observables.gyro_rad_s, core.rigid_body.angular_velocity_rad_s]
	))

	# The reading must not BE ground truth. If it were, the seam exists on paper only.
	results.append(TestResult.new(
		"the published gyro reading is a sensor estimate, not a copy of the true rate",
		core.observables.gyro_rad_s != core.rigid_body.angular_velocity_rad_s,
		"gyro %s vs true %s" % [core.observables.gyro_rad_s, core.rigid_body.angular_velocity_rad_s]
	))

	return results


# ---------------------------------------------------------------------------
# The vibration path (LTHL-15)
#
# These check the MECHANISM — that a vibration source reaches the reading at the sensor's own
# sample instants, through the PT1 and not around it — and nothing about what vibration IS.
# What it is belongs to VibrationModel and is checked in tests/test_vibration.gd, which is a
# separate suite for the same reason these are separate commits: a wrong signal delivered
# correctly and a right signal delivered wrongly look the same from the output and have
# nothing to do with each other.
#
# So the source used here is a fixed-frequency tone that knows nothing about rpm. As a MODEL
# of vibration that is deliberately, uselessly wrong. As a test instrument it is exactly right,
# because every assertion below wants a signal whose frequency and amplitude are known in
# advance rather than derived from an aircraft.
# ---------------------------------------------------------------------------

## A pure tone on body X. Frequency-fixed, so it may compute phase straight from t; a source
## whose frequency follows rpm may not, and VibrationModel integrates phase instead.
class Tone extends VibrationSource:
	var hz: float
	var amplitude_rad_s: float
	func _init(p_hz: float, p_amplitude_rad_s: float) -> void:
		hz = p_hz
		amplitude_rad_s = p_amplitude_rad_s
	func angular_rate_at(t_s: float) -> Vector3:
		return Vector3(amplitude_rad_s * sin(TAU * hz * t_s), 0.0, 0.0)


## The amplitude of the component at `hz` in a sampled signal — one DFT bin, by correlation.
## Exact when the window holds a whole number of cycles, which every caller below arranges.
## A peak-of-the-samples measurement would not do: at 1 kHz a 100 Hz tone is only sampled ten
## times per cycle, so the largest sample can miss the true peak by 5%, and 5% is larger than
## the differences these checks are trying to resolve.
static func _amplitude_at(samples: PackedFloat64Array, hz: float, sample_rate_hz: float) -> float:
	var re := 0.0
	var im := 0.0
	for n in samples.size():
		var theta := TAU * hz * float(n) / sample_rate_hz
		re += samples[n] * cos(theta)
		im += samples[n] * sin(theta)
	return 2.0 / float(samples.size()) * sqrt(re * re + im * im)


## Drives a gyro at its own sample rate for `count` samples and returns the X readings.
static func _trace_x(gyro: Gyro, count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var dt := 1.0 / gyro.sample_rate_hz
	for i in count:
		out.append(gyro.update(Vector3.ZERO, dt).x)
	return out


## The discrete PT1's magnitude response at one frequency. For y[n] = (1-a)y[n-1] + a x[n],
## H(z) = a / (1 - (1-a) z^-1), so |H| = a / |1 - (1-a) e^-jw|. Written out here rather than
## asserted as "roughly attenuated", because a filter that attenuates by an arbitrary amount is
## indistinguishable from a bug that attenuates by an arbitrary amount.
static func _pt1_gain(hz: float, cutoff_hz: float, sample_rate_hz: float) -> float:
	var period := 1.0 / sample_rate_hz
	var rc := 1.0 / (TAU * cutoff_hz)
	var a := period / (rc + period)
	var w := TAU * hz / sample_rate_hz
	var real := 1.0 - (1.0 - a) * cos(w)
	var imag := (1.0 - a) * sin(w)
	return a / sqrt(real * real + imag * imag)


static func _vibration_path_results() -> Array:
	var results: Array = []
	var fs := Gyro.DEFAULT_SAMPLE_RATE_HZ

	# --- A source with no vibration in it changes nothing ---
	# The default. 670 tests were written against a gyro with no vibration path at all, and they
	# are entitled to keep meaning what they meant.
	var quiet := Gyro.new(fs, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	var silent := Gyro.new(fs, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	silent.vibration = VibrationSource.new()
	var matched := true
	for i in 200:
		if quiet.update(Vector3(0.3, 0.0, 0.0), 1.0 / fs) != silent.update(Vector3(0.3, 0.0, 0.0), 1.0 / fs):
			matched = false
			break
	results.append(TestResult.new(
		"a gyro with the base vibration source reads exactly what a gyro with none reads",
		matched,
		"200 samples compared, traces %s" % ("identical" if matched else "DIVERGED")))

	# --- Vibration arrives THROUGH the PT1, at the filter's own published attenuation ---
	# This is the check that says the injection point is right. Added after the filter it would
	# arrive at full amplitude; added to the rigid body it would not arrive at all.
	var through := Gyro.new(fs, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	through.vibration = Tone.new(200.0, 1.0)
	_trace_x(through, 1000)   # let the filter settle before measuring
	var seen := _amplitude_at(_trace_x(through, 1000), 200.0, fs)
	var predicted := _pt1_gain(200.0, Gyro.DEFAULT_CUTOFF_HZ, fs)
	results.append(TestResult.new(
		"vibration is added ahead of the PT1, so a 200 Hz tone arrives at the filter's own gain",
		absf(seen - predicted) < 0.01,
		"1.000 rad/s at 200 Hz read as %.4f; the %0.f Hz PT1's magnitude response there is %.4f"
			% [seen, Gyro.DEFAULT_CUTOFF_HZ, predicted]))

	# --- Raising the cutoff lets more of it through ---
	# The FC bench's whole argument in one assertion. A model that added vibration anywhere but
	# ahead of the filter would show the same amplitude at both cutoffs.
	var sharp := Gyro.new(fs, 500.0, 0.0, Vector3.ZERO)
	sharp.vibration = Tone.new(200.0, 1.0)
	_trace_x(sharp, 1000)
	var sharp_seen := _amplitude_at(_trace_x(sharp, 1000), 200.0, fs)
	results.append(TestResult.new(
		"raising the gyro cutoff lets more vibration through — the cutoff sweep has a landmark",
		sharp_seen > seen * 1.4,
		"200 Hz tone reads %.4f at a %.0f Hz cutoff and %.4f at 500 Hz (%.2fx)"
			% [seen, Gyro.DEFAULT_CUTOFF_HZ, sharp_seen, sharp_seen / seen]))

	# --- Aliasing, by construction ---
	# Blade pass on the reference build at full throttle is ~1450 Hz, and the sensor samples at
	# 1000. A 1 kHz sampler cannot tell 1450 Hz from 450 Hz: 1450n/1000 and 450n/1000 differ by
	# exactly n whole cycles, so the two sample sequences are not similar, they are IDENTICAL.
	# Asserting equality rather than "some low-frequency content appears" is what makes this a
	# statement about the sampler instead of an observation about the output.
	var above := Gyro.new(fs, 10000.0, 0.0, Vector3.ZERO)
	above.vibration = Tone.new(1450.0, 1.0)
	var below := Gyro.new(fs, 10000.0, 0.0, Vector3.ZERO)
	below.vibration = Tone.new(450.0, 1.0)
	var folded := _trace_x(above, 400)
	var direct := _trace_x(below, 400)
	var worst := 0.0
	for i in folded.size():
		worst = maxf(worst, absf(folded[i] - direct[i]))
	results.append(TestResult.new(
		"blade pass above Nyquist folds down: 1450 Hz through a 1 kHz sensor IS 450 Hz",
		worst < 1e-9,
		"400 samples, largest difference between the 1450 Hz and 450 Hz traces %.12f rad/s" % worst))

	# ...and it is not that everything simply gets through. The fold-down is a specific frequency,
	# not a smear, so the SAME tone must be absent from the bin it was actually generated at.
	var alias_amp := _amplitude_at(_trace_x(above, 1000), 450.0, fs)
	var origin_amp := _amplitude_at(_trace_x(above, 1000), 1450.0 - 1000.0 + 200.0, fs)
	results.append(TestResult.new(
		"the fold-down lands on one frequency rather than smearing across the band",
		alias_amp > 0.9 and origin_amp < 0.05,
		"1450 Hz tone reads %.4f rad/s in the 450 Hz bin and %.4f in the 650 Hz bin"
			% [alias_amp, origin_amp]))

	# --- Determinism across a respawn ---
	# gyro.gd re-seeds its RNG in reset() so that "the same flight twice" is the same flight.
	# A vibration source that carried its phase across a respawn would break that guarantee from
	# a place nobody would think to look.
	var respawned := Gyro.new(fs, Gyro.DEFAULT_CUTOFF_HZ, 0.0, Vector3.ZERO)
	respawned.vibration = Tone.new(213.0, 1.0)
	var first_run := _trace_x(respawned, 300)
	respawned.reset()
	var second_run := _trace_x(respawned, 300)
	var replay := true
	for i in first_run.size():
		if absf(first_run[i] - second_run[i]) > 1e-12:
			replay = false
			break
	results.append(TestResult.new(
		"reset returns the vibration phase to zero, so a respawn replays the same shake",
		replay,
		"300 samples either side of a reset, traces %s" % ("identical" if replay else "DIVERGED")))

	return results
