class_name TestRateStepResponse
extends RefCounted
## Day 4's mitigation for its biggest risk (week1.md): "feels wobbly" is not a number you
## can iterate on — this is. Commands a hard 500 deg/s roll step, logs the gyro trace,
## and computes overshoot and settling time. Targets from week1.md: <10% overshoot,
## <80ms settle. This is what the manual gains in rate_mode_controller.gd get tuned
## against — if this test fails, adjust the gains there, not this harness.

const DT := 0.001
const DURATION_S := 1.0
const STEP_DEG_S := 500.0
const SETTLE_BAND_FRACTION := 0.05   # standard 5% settling-time band

static func run() -> Array:
	var results: Array = []

	var core := ReferenceBuild.build_drone_core()
	var controller := RateModeController.new()
	var target_rad_s := deg_to_rad(STEP_DEG_S)
	var throttle := ReferenceBuild.hover_throttle()
	var setpoint := Vector3(target_rad_s / RateModeController.MAX_RATE_RAD_S, 0.0, 0.0)

	var trace: Array = []
	var steps := int(DURATION_S / DT)
	for i in steps:
		var motor_cmds := controller.update(setpoint, core.gyro.rate_rad_s, throttle, DT)
		core.step(motor_cmds, DT)
		trace.append(-core.rigid_body.angular_velocity_rad_s.z)   # roll rate, contract sign

	var peak: float = target_rad_s
	for v in trace:
		peak = max(peak, v)
	var overshoot_pct := (peak - target_rad_s) / target_rad_s * 100.0

	var settle_step := -1
	var band := target_rad_s * SETTLE_BAND_FRACTION
	for i in range(trace.size() - 1, -1, -1):
		if absf(trace[i] - target_rad_s) > band:
			settle_step = i + 1
			break
	var settle_time_ms: float = 0.0 if settle_step == -1 else settle_step * DT * 1000.0

	results.append(TestResult.new(
		"500deg/s roll step: overshoot < 10%%",
		overshoot_pct < 10.0,
		"overshoot = %.2f%%" % overshoot_pct
	))
	results.append(TestResult.new(
		"500deg/s roll step: settles within 80ms",
		settle_time_ms < 80.0,
		"settle time = %.1f ms" % settle_time_ms
	))

	return results
