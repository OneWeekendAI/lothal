class_name TestBfMechanisms
## B1 (2026-11-17): one mutation-proven test per Betaflight rate-loop mechanism (src/fc/betaflight_pid.gd,
## rate_mode_controller.gd). Each test flies the SAME manoeuvre with the mechanism on (the shipped
## default) and off (its seam), and passes only if the on-run meets the bound AND the off-run breaks it.
## So switching a mechanism off, or deleting it, turns the test red, and a bound loose enough to pass
## with the mechanism gone fails here instead of silently going green.

const DT := 0.001
const AG_HELD_DEG_S := 30.0
const FF_RAMP_DEG_S := 300.0


static func _controller(relax: bool, windup: bool, ff: bool, ag: bool) -> RateModeController:
	var c := RateModeController.new()
	c.set_mechanisms(relax, windup, ff)
	c.anti_gravity_enabled = ag
	return c


## The 360 deg/s one-second flip, then release (test_rate_mode_release.gd's manoeuvre, VRS
## fluctuation off). Returns the most negative roll rate after release, rad/s.
static func _flip_bounce(relax: bool) -> float:
	var core := ReferenceBuild.build_drone_core()
	core.powertrain.vrs_fluctuation_on = false
	var c := _controller(relax, true, true, true)
	var thr := ReferenceBuild.hover_throttle()
	var held := Vector3(TAU / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)
	var mn := 0.0
	for i in 1500:
		var sp := held if i < 1000 else Vector3.ZERO
		core.step(c.update(sp, core.gyro.rate_rad_s, thr, DT), DT)
		if i >= 1000:
			mn = minf(mn, -core.rigid_body.angular_velocity_rad_s.z)
	return mn


## Full-throttle punch with a full roll stick held for 0.5 s: the motor mix is saturated the whole time.
## Returns the peak roll I term (output units) over the hold.
static func _saturated_i(windup: bool) -> float:
	var core := ReferenceBuild.build_drone_core()
	core.powertrain.vrs_fluctuation_on = false
	# Relax off on both runs, so the stick step does not mask accumulation and windup is the only difference.
	var c := _controller(false, windup, true, true)
	var sp := Vector3(1.0, 0.0, 0.0)
	var peak := 0.0
	for i in 500:
		core.step(c.update(sp, core.gyro.rate_rad_s, 1.0, DT), DT)
		peak = maxf(peak, absf(c.pid_roll._integral))
	return peak


## A held 30 deg/s roll, then a throttle chop from hover to 10% in 40 ms, held 0.3 s. Low throttle cuts the
## plant's authority and the rotor torque balance shifts, so the tracked rate sags. Returns the integrated
## |roll rate error| over the chop, rad.
static func _chop_rate_error(ag: bool) -> float:
	var core := ReferenceBuild.build_drone_core()
	core.powertrain.vrs_fluctuation_on = false
	var c := _controller(true, true, true, ag)
	var hover := ReferenceBuild.hover_throttle()
	var sp0 := Vector3(deg_to_rad(AG_HELD_DEG_S) / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)
	for i in 300:
		core.step(c.update(sp0, core.gyro.rate_rad_s, hover, DT), DT)
	var worst := 0.0
	var tgt := deg_to_rad(AG_HELD_DEG_S)
	var sp := Vector3(tgt / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)
	for i in 340:
		var thr := lerpf(hover, 0.1, clampf(float(i) / 40.0, 0.0, 1.0))
		core.step(c.update(sp, core.gyro.rate_rad_s, thr, DT), DT)
		var w := Gyro.contract_rates(core.rigid_body.angular_velocity_rad_s)
		worst += absf(w.x - tgt) * DT
	return worst


## A stick RAMP, 0 -> 300 deg/s in 100 ms then held (a real stick move; on a pure step FF is a one-tick
## kick that P already saturates past). FF follows the setpoint's derivative, so its job is to cut the
## tracking lag during the ramp. Returns the integrated |roll rate error| over the ramp + 50 ms, rad.
static func _ramp_lag(ff: bool) -> float:
	var core := ReferenceBuild.build_drone_core()
	core.powertrain.vrs_fluctuation_on = false
	var c := _controller(true, true, ff, true)
	var thr := ReferenceBuild.hover_throttle()
	var lag := 0.0
	for i in 150:
		var tgt := deg_to_rad(FF_RAMP_DEG_S) * clampf(float(i) / 100.0, 0.0, 1.0)
		var sp := Vector3(tgt / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)
		core.step(c.update(sp, core.gyro.rate_rad_s, thr, DT), DT)
		lag += absf(tgt - Gyro.contract_rates(core.rigid_body.angular_velocity_rad_s).x) * DT
	return lag


static func run() -> Array:
	var results: Array = []

	# iterm_relax: without it I winds up through the whole 360 deg/s hold and the release bounces past
	# zero. The bound is test_rate_mode_release.gd's BOUNCE_BACK_LIMIT (0.15 rad/s).
	var relax_on := _flip_bounce(true)
	var relax_off := _flip_bounce(false)
	results.append(TestResult.new(
		"mechanism: iterm_relax keeps the flip release inside 0.15 rad/s, and without it the release bounces",
		relax_on > -0.15 and relax_off < -0.15,
		"min rate on %.3f, off %.3f rad/s" % [relax_on, relax_off]))

	# Anti-windup (iterm_windup on the mix range): with the mix saturated the I term must stay under half
	# of what it reaches without the clamp (Betaflight scales I accumulation down by the overshoot of the
	# mix range past iterm_windup).
	var aw_on := _saturated_i(true)
	var aw_off := _saturated_i(false)
	results.append(TestResult.new(
		"mechanism: anti-windup holds the roll I term under half its unclamped value in a saturated punch",
		aw_on < 0.5 * aw_off,
		"|I| on %.4f, off %.4f" % [aw_on, aw_off]))

	# Anti-gravity: a fast throttle chop boosts I so the CoM-offset torque change is held; without it the
	# attitude rate error is larger. Bound: at least 10 percent smaller with it on.
	var ag_on := _chop_rate_error(true)
	var ag_off := _chop_rate_error(false)
	results.append(TestResult.new(
		"mechanism: anti_gravity cuts the throttle-chop rate error by at least 10 percent",
		ag_on < 0.9 * ag_off,
		"integrated rate error on %.5f, off %.5f rad" % [ag_on, ag_off]))

	# Feed-forward: on a stick ramp FF must cut the tracking lag by at least 10 percent.
	var ff_on := _ramp_lag(true)
	var ff_off := _ramp_lag(false)
	results.append(TestResult.new(
		"mechanism: feed-forward cuts the tracking lag on a 300 deg/s stick ramp by at least 10 percent",
		ff_on < 0.9 * ff_off,
		"integrated rate error on %.4f, off %.4f rad" % [ff_on, ff_off]))
	return results
