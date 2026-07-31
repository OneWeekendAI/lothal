class_name TestRateModeRelease
extends RefCounted
## Day 4's actual gate (week1.md): "a clean 360deg roll that stops where the stick is
## released — no wobble, no bounce-back, no drift." Commands a roll rate long enough to
## complete one full rotation, releases the stick to zero, and checks the rate returns
## to (near) zero quickly and stays there, rather than overshooting past zero and
## ringing (bounce-back) or settling on a nonzero residual (drift).

const DT := 0.001
const ROLL_RATE_DEG_S := 360.0   # one full rotation per second at this rate
const POST_RELEASE_DURATION_S := 0.5
const BOUNCE_BACK_LIMIT_RAD_S := 0.15   # ~8.6 deg/s residual swing tolerance
const DRIFT_LIMIT_RAD_S := 0.05         # ~2.9 deg/s steady-state residual tolerance

static func run() -> Array:
	var results: Array = []

	var core := ReferenceBuild.build_drone_core()
	var controller := RateModeController.new()
	var rate_rad_s := deg_to_rad(ROLL_RATE_DEG_S)
	var throttle := ReferenceBuild.hover_throttle()
	var held := Vector3(rate_rad_s / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)

	# Hold the roll rate for exactly one second -> one full 360deg rotation.
	for i in int(1.0 / DT):
		var motor_cmds := controller.update(held, core.gyro.rate_rad_s, throttle, DT)
		core.step(motor_cmds, DT)

	# Release: roll stick back to centre.
	var released := Vector3.ZERO
	var min_rate_after_release := 0.0
	var final_rate := 0.0
	for i in int(POST_RELEASE_DURATION_S / DT):
		var motor_cmds := controller.update(released, core.gyro.rate_rad_s, throttle, DT)
		core.step(motor_cmds, DT)
		var roll_rate := -core.rigid_body.angular_velocity_rad_s.z
		min_rate_after_release = min(min_rate_after_release, roll_rate)
		final_rate = roll_rate

	results.append(TestResult.new(
		"released roll stick: no bounce-back past zero",
		min_rate_after_release > -BOUNCE_BACK_LIMIT_RAD_S,
		"min rate after release = %.4f rad/s" % min_rate_after_release
	))
	results.append(TestResult.new(
		"released roll stick: no residual drift",
		absf(final_rate) < DRIFT_LIMIT_RAD_S,
		"final rate = %.4f rad/s" % final_rate
	))

	return results
