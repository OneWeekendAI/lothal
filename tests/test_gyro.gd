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
