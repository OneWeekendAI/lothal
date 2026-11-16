class_name TestAttitudeEstimator
extends RefCounted
## R1.2: the accelerometer, the Mahony estimator, and angle mode flying on the ESTIMATE.
##
## Two kinds of check. The estimator is exercised on SYNTHETIC kinematics where the truth is a closed
## form (hover, a coordinated turn), so a bound here is a statement about the filter, not about how
## well a particular tune flies. The full-aircraft checks then run the real DroneCore + FlightController.

const G := 9.80665
const DT := 0.001

## Angle between two attitudes' "up" axes, in degrees. Yaw is unobservable to the estimator, so it
## is deliberately not compared.
static func tilt_error_deg(a: Quaternion, b: Quaternion) -> float:
	var ua := a.inverse() * Vector3.UP
	var ub := b.inverse() * Vector3.UP
	return rad_to_deg(acos(clampf(ua.dot(ub), -1.0, 1.0)))

## A steady coordinated turn at bank `bank_rad`, true airspeed 10 m/s. Returns the tilt error (deg)
## sampled at each of `at_s` after starting with an estimate that is exactly right.
static func turn_errors(bank_rad: float, kp: float, at_s: Array) -> Array:
	var turn_rate := G * tan(bank_rad) / 10.0
	var est := AttitudeEstimator.new()
	est.kp = kp
	var truth := Quaternion(Vector3(0, 0, 1), bank_rad)
	est.attitude = truth
	est.seeded = true
	var out: Array = []
	var yaw := 0.0
	var steps := int(float(at_s.back()) / DT)
	var next := 0
	for i in steps:
		yaw += turn_rate * DT
		truth = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3(0, 0, 1), bank_rad)
		# Thrust is along body +Y and carries the weight AND the centripetal force: g / cos(bank).
		var accel := Vector3(0, G / cos(bank_rad), 0)
		var gyro := truth.inverse() * Vector3(0, turn_rate, 0)
		est.update(gyro, accel, DT)
		if next < at_s.size() and float(i + 1) * DT >= float(at_s[next]) - 1e-9:
			out.append(tilt_error_deg(est.attitude, truth))
			next += 1
	return out

static func _code_only(src: String) -> String:
	var lines: Array = []
	for line in src.split("\n"):
		var hash_at := line.find("#")
		lines.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(lines)

static func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if not is_equal_approx(float(a[k]), float(b[k])):
			return false
	return true

static func run() -> Array:
	var results: Array = []
	var hover := ReferenceBuild.hover_throttle()
	var rate_loop := RateModeController.new()

	# ---- the accelerometer model ----
	var core := ReferenceBuild.build_drone_core()
	core.prime_motors(hover)
	var sum := Vector3.ZERO
	var n := 0
	for i in 1500:
		core.step(rate_loop.update(Vector3.ZERO, core.gyro.rate_rad_s, hover, DT), DT)
		if i >= 500:
			sum += core.accel.reading_mps2
			n += 1
	var mean := sum / float(n)
	# The reading is specific force: at a hover it is +g up the body axis, NOT zero (gravity is not
	# sensed) and NOT -g. Tolerance 0.4 m/s^2: bias (0.05) plus a hover that is not quite steady.
	results.append(TestResult.new(
		"accelerometer at hover reads specific force +g along the body up axis",
		absf(mean.y - G) < 0.4 and absf(mean.x) < 0.4 and absf(mean.z) < 0.4,
		"mean = %s (g = %.3f)" % [str(mean), G]))

	var fall := ReferenceBuild.build_drone_core()
	var fall_loop := RateModeController.new()
	for i in 300:
		fall.step(fall_loop.update(Vector3.ZERO, fall.gyro.rate_rad_s, 0.0, DT), DT)
	results.append(TestResult.new(
		"accelerometer in free fall reads ~0 (it senses support, not gravity)",
		fall.accel.reading_mps2.length() < 0.5 and fall.rigid_body.velocity_mps.y < -1.0,
		"reading = %s, vy = %.2f" % [str(fall.accel.reading_mps2), fall.rigid_body.velocity_mps.y]))

	# On the ground, motors idle, the ground pushes back and the sensor feels it: 1 g, not ~0.
	var ground := ReferenceBuild.build_drone_core()
	ground.ground_contact_enabled = true
	ground.ground_y_m = 0.0
	ground.rigid_body.position_m.y = ground.rest_height_m
	for i in 300:
		ground.step(fall_loop.update(Vector3.ZERO, ground.gyro.rate_rad_s, 0.0, DT), DT)
	results.append(TestResult.new(
		"accelerometer resting on the ground reads +g along the body up axis (the ground pushes back)",
		absf(ground.accel.reading_mps2.y - G) < 0.4,
		"reading = %s" % str(ground.accel.reading_mps2)))

	var quiet := Accelerometer.new(1000.0, 100.0, 0.0, Vector3.ZERO)
	var shaken := Accelerometer.new(1000.0, 100.0, 0.0, Vector3.ZERO)
	var spread_q := 0.0
	var spread_s := 0.0
	for i in 400:
		var s := Vector3(1.0 * sin(float(i) * 0.9), 0, 0)
		quiet.update(Vector3(0, G, 0), Vector3.ZERO, DT)
		shaken.update(Vector3(0, G, 0), s, DT)
		if i >= 100:
			spread_q = maxf(spread_q, absf(quiet.reading_mps2.x))
			spread_s = maxf(spread_s, absf(shaken.reading_mps2.x))
	results.append(TestResult.new(
		"gyro vibration reaches the accelerometer through the same path",
		spread_q < 1e-6 and spread_s > 0.3,
		"quiet %.6f, shaken %.3f m/s^2" % [spread_q, spread_s]))

	# Through the real core: the airframe shake that the gyro carries must reach the accelerometer
	# too. Same build, same seeds; the only difference is the vibration source.
	var spread: Array = []
	for shake in [true, false]:
		var c := ReferenceBuild.build_drone_core()
		c.accel.noise_mps2 = 0.0
		if not shake:
			c.gyro.vibration = null
		c.prime_motors(hover)
		var lo := 1e9
		var hi := -1e9
		for i in 1200:
			c.step(rate_loop.update(Vector3.ZERO, c.gyro.rate_rad_s, hover, DT), DT)
			if i >= 600:
				lo = minf(lo, c.accel.reading_mps2.x)
				hi = maxf(hi, c.accel.reading_mps2.x)
		spread.append(hi - lo)
	results.append(TestResult.new(
		"the airframe shake reaches the accelerometer through DroneCore",
		spread[0] > 0.02 and spread[1] < 0.001,
		"x spread shaken %.3f vs still %.3f m/s^2" % [spread[0], spread[1]]))

	var a1 := Accelerometer.new()
	var a2 := Accelerometer.new()
	for i in 50:
		a1.update(Vector3(0, G, 0), Vector3.ZERO, DT)
	a1.reset()
	for i in 50:
		a1.update(Vector3(0, G, 0), Vector3.ZERO, DT)
		a2.update(Vector3(0, G, 0), Vector3.ZERO, DT)
	results.append(TestResult.new(
		"accelerometer reset replays the same noise stream",
		a1.reading_mps2.is_equal_approx(a2.reading_mps2) and a1.reading_mps2.length() > 1.0,
		"%s vs %s" % [str(a1.reading_mps2), str(a2.reading_mps2)]))

	# ---- estimator: convergence ----
	# Start 20 degrees wrong, perfect still inputs. Kp = 0.25 /s is a 4 s time constant, so 20 s is
	# five of them: 20 * e^-5 = 0.13 degrees. Bound 0.5.
	var est := AttitudeEstimator.new()
	est.attitude = Quaternion(Vector3(0, 0, 1), deg_to_rad(20.0))
	est.seeded = true
	for i in 20000:
		est.update(Vector3.ZERO, Vector3(0, G, 0), DT)
	var pull_in := tilt_error_deg(est.attitude, Quaternion.IDENTITY)
	results.append(TestResult.new(
		"estimator pulls a 20 degree error to < 0.5 degrees in 20 s at hover (Kp default 0.25)",
		pull_in < 0.5 and AttitudeEstimator.DEFAULT_KP == 0.25,
		"error after 20 s = %.3f deg" % pull_in))

	# Full aircraft: noise, bias, vibration, real hover. Measured 2.1 degrees worst over this window,
	# and it is REAL, not slop: the stock gyro bias (0.1 deg/s) alone gives 1.3 and the accel bias
	# 1.4, because the controller levels the estimate and the aircraft then wanders with it (with
	# every error source off it is 0.1). Bound 3 degrees.
	var fly := ReferenceBuild.build_drone_core()
	fly.prime_motors(hover)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover}
	var worst := 0.0
	for i in 20000:
		fly.step(fc.update(fly.accel.reading_mps2, fly.gyro.rate_rad_s, rc, DT), DT)
		if i > 3000:
			worst = maxf(worst, tilt_error_deg(fc.estimator.attitude, fly.rigid_body.orientation))
	results.append(TestResult.new(
		"estimate tracks the true attitude to < 3 degrees through a 20 s real hover",
		fc.estimator.seeded and worst < 3.0,
		"worst error after 3 s = %.3f deg" % worst))

	# ---- estimator: the accel-fooled effect ----
	# 20 degrees of bank is 1.064 g, inside the trust window, so the accelerometer insists the
	# aircraft is level. With perfect gyro the ONLY thing moving the estimate off truth is that lie,
	# so the error must grow toward the full bank and stay bounded by it.
	var bank := deg_to_rad(20.0)
	var errs := turn_errors(bank, AttitudeEstimator.DEFAULT_KP, [1.0, 8.0, 30.0])
	results.append(TestResult.new(
		"coordinated 20 degree turn: the horizon tilts and keeps tilting (>= 8 degrees by 30 s) ...",
		errs[0] < errs[1] and errs[2] > 8.0,
		"error at 1/8/30 s = %.2f / %.2f / %.2f deg" % [errs[0], errs[1], errs[2]]))
	results.append(TestResult.new(
		"... and stays bounded by the bank angle (<= 21 degrees)",
		maxf(errs[1], maxf(errs[0], errs[2])) <= 21.0,
		"error at 8/30 s = %.2f / %.2f deg" % [errs[1], errs[2]]))
	var steep := turn_errors(deg_to_rad(40.0), AttitudeEstimator.DEFAULT_KP, [30.0])
	results.append(TestResult.new(
		"coordinated 40 degree turn (1.3 g): accelerometer is rejected, error stays < 1 degree",
		steep[0] < 1.0,
		"error after 30 s = %.3f deg" % steep[0]))
	var stiff := turn_errors(bank, 1.0, [8.0])
	var soft := turn_errors(bank, 0.0625, [8.0])
	results.append(TestResult.new(
		"the gain is the knob: higher Kp is fooled faster, lower Kp is fooled slower",
		stiff[0] > errs[1] and soft[0] < errs[1],
		"8 s error at Kp 1.0 / 0.25 / 0.0625 = %.2f / %.2f / %.2f deg" % [stiff[0], errs[1], soft[0]]))

	# ---- angle mode on the estimate ----
	var tilted := ReferenceBuild.build_drone_core()
	tilted.rigid_body.orientation = Quaternion(Vector3(0, 0, 1), deg_to_rad(15.0))
	tilted.prime_motors(hover)
	var fc2 := FlightController.new()
	# An estimator that has been tracking the aircraft (a gyro-integrated disturbance), not a cold
	# start: a board powered up already banked has only specific force to go on, and that points up
	# the body axis whatever the bank is, so it would believe itself level until drag settles.
	fc2.estimator.attitude = tilted.rigid_body.orientation
	fc2.estimator.seeded = true
	for i in 20000:
		tilted.step(fc2.update(tilted.accel.reading_mps2, tilted.gyro.rate_rad_s, rc, DT), DT)
	var e := tilted.rigid_body.orientation.get_euler(EULER_ORDER_YXZ)
	var final_tilt := rad_to_deg(maxf(absf(e.x), absf(e.z)))
	results.append(TestResult.new(
		"angle mode on the estimate levels the real aircraft from 15 degrees to < 3 degrees in 20 s (the hover wander floor is ~2)",
		final_tilt < 3.0,
		"final true tilt = %.3f deg" % final_tilt))

	# ---- angle mode no longer reads the true attitude ----
	var fc_code := _code_only(FileAccess.get_file_as_string("res://src/fc/flight_controller.gd"))
	var angle_code := _code_only(FileAccess.get_file_as_string("res://src/fc/angle_mode_controller.gd"))
	results.append(TestResult.new(
		"source: the flight controller never touches rigid_body or takes an orientation argument",
		not fc_code.contains("rigid_body") and not fc_code.contains("func update(orientation")
			and fc_code.contains("estimator.attitude") and not angle_code.contains("rigid_body"),
		"update() levels against estimator.attitude"))
	for path in ["res://src/scenes/main.gd", "res://src/autopilot/nav_pilot.gd"]:
		var code := _code_only(FileAccess.get_file_as_string(path))
		results.append(TestResult.new(
			"source: %s hands the controller the accelerometer, not the true orientation" % path.get_file(),
			code.contains("fc.update(core.accel.reading_mps2") and not code.contains("fc.update(core.rigid_body"),
			"call site passes core.accel.reading_mps2"))

	# Behaviour: the controller is told, by the sensors alone, that it is rolled; truth is never in
	# the picture. Angle mode must command a correction, and acro must not.
	var rolled_accel := Quaternion(Vector3(0, 0, 1), deg_to_rad(20.0)).inverse() * Vector3(0, G, 0)
	var level_accel := Vector3(0, G, 0)
	var angle_rolled := FlightController.new().update(rolled_accel, Vector3.ZERO, rc, DT)
	var angle_level := FlightController.new().update(level_accel, Vector3.ZERO, rc, DT)
	var acro_a := FlightController.new()
	acro_a.mode = FlightController.Mode.ACRO
	var acro_b := FlightController.new()
	acro_b.mode = FlightController.Mode.ACRO
	var acro_rolled := acro_a.update(rolled_accel, Vector3.ZERO, rc, DT)
	var acro_level := acro_b.update(level_accel, Vector3.ZERO, rc, DT)
	results.append(TestResult.new(
		"angle mode commands a correction purely from the accelerometer's idea of tilt",
		not _same(angle_rolled, angle_level),
		"rolled %s vs level %s" % [str(angle_rolled), str(angle_level)]))
	results.append(TestResult.new(
		"acro (rate) mode is unchanged: the accelerometer does not touch its output",
		_same(acro_rolled, acro_level),
		"rolled %s vs level %s" % [str(acro_rolled), str(acro_level)]))

	return results
