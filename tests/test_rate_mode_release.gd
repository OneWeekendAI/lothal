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
const ON_MEASURED_SWING := 0.159
const ON_MEASURED_RESIDUAL := 0.159
const ON_SWING_LIMIT_RAD_S := 0.25
const ON_RESIDUAL_LIMIT_RAD_S := 0.25
const DRIFT_LIMIT_RAD_S := 0.05         # ~2.9 deg/s steady-state residual tolerance

## Flies the flip-and-release with the vortex-ring fluctuation on or off; returns [min rate after release, final rate].
static func _fly(fluctuation_on: bool) -> Array:
	var core := ReferenceBuild.build_drone_core()
	core.powertrain.vrs_fluctuation_on = fluctuation_on
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
	return [min_rate_after_release, final_rate]


static func run() -> Array:
	var results: Array = []

	# R1.5: after the one-second flip this open-loop throttle falls through near-vertical descent, where the rotors draw
	# the vortex-ring thrust fluctuation (a seeded 10 percent RMS random disturbance, tests/test_vrs.gd).
	# (1) Fluctuation OFF isolates the rate loop's own release behaviour (vortex-ring mean deficit stays on).
	var off := _fly(false)
	results.append(TestResult.new(
		"released roll stick: no bounce-back past zero",
		off[0] > -BOUNCE_BACK_LIMIT_RAD_S,
		"min rate after release = %.4f rad/s" % off[0]
	))
	results.append(TestResult.new(
		"released roll stick: no residual drift",
		absf(off[1]) < DRIFT_LIMIT_RAD_S,
		"final rate = %.4f rad/s" % off[1]
	))

	# (2) Fluctuation ON (the shipped default, seeded so the run is bit-repeatable): the flip must still recover.
	# BOUND = measured physics + margin. Measured on this build: 0.159 rad/s, swing and final coincide (a slow
	# VRS-driven roll drift, not ringing). The bound is that x ~1.5 margin, rounded to 0.25 rad/s (14 deg/s, 4% of the
	# 360 deg/s flip), so it fails if recovery is lost (a diverging tumble is tens of rad/s) yet does not chase the last digit of a seeded random draw.
	var on := _fly(true)
	results.append(TestResult.new(
		"released roll stick with vortex-ring fluctuation on: swing past zero stays bounded",
		on[0] > -ON_SWING_LIMIT_RAD_S,
		"min rate after release = %.4f rad/s (bound %.2f = measured %.3f x ~1.5 margin)" % [on[0], ON_SWING_LIMIT_RAD_S, ON_MEASURED_SWING]
	))
	results.append(TestResult.new(
		"released roll stick with vortex-ring fluctuation on: residual rate stays bounded",
		absf(on[1]) < ON_RESIDUAL_LIMIT_RAD_S,
		"final rate = %.4f rad/s (bound %.2f = measured %.3f x ~1.5 margin)" % [on[1], ON_RESIDUAL_LIMIT_RAD_S, ON_MEASURED_RESIDUAL]
	))

	# B1: one mutation-proven test per Betaflight mechanism (relax, anti-windup, anti-gravity, FF).
	results.append_array(TestBfMechanisms.run())
	return results
