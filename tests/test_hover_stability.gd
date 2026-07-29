class_name TestHoverStability
extends RefCounted
## Day 3 gate (week1.md): "hovers stable at ~29% throttle, holds level hands-off, no
## drift or explosion over 60 seconds." No 3D window exists in this headless environment,
## so this drives the same DroneCore + AngleModeController the scene will use, starting
## from a 5-degree tilt with sticks centered, and checks it self-levels and stays bounded
## rather than diverging — the numeric equivalent of watching it hover on screen.

const DT := 0.001          # 1 kHz, matching physics.md §6
const DURATION_S := 60.0
const INITIAL_TILT_RAD := 0.0872665   # 5 degrees

static func run() -> Array:
	var results: Array = []

	var core := ReferenceBuild.build_drone_core()
	core.rigid_body.orientation = Quaternion(Vector3(0, 0, 1), INITIAL_TILT_RAD)   # start rolled 5 deg
	var hover_throttle := ReferenceBuild.hover_throttle()
	core.prime_motors(hover_throttle)   # steady state, not a spin-up transient
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover_throttle}

	var steps := int(DURATION_S / DT)
	var max_angular_speed := 0.0
	var max_linear_speed := 0.0
	var diverged := false

	for i in steps:
		var motor_cmds := AngleModeController.update(core.rigid_body.orientation, core.rigid_body.angular_velocity_rad_s, rc)
		core.step(motor_cmds, DT)

		max_angular_speed = max(max_angular_speed, core.rigid_body.angular_velocity_rad_s.length())
		max_linear_speed = max(max_linear_speed, core.rigid_body.velocity_mps.length())

		if not is_finite(core.rigid_body.position_m.length()) or not is_finite(core.rigid_body.orientation.length()):
			diverged = true
			break

	results.append(TestResult.new(
		"60s hands-off hover: no divergence (NaN/Inf)",
		not diverged,
		"diverged=%s" % diverged
	))
	results.append(TestResult.new(
		"60s hands-off hover: angular velocity stays bounded (< 20 rad/s)",
		max_angular_speed < 20.0,
		"max |omega| = %.4f rad/s" % max_angular_speed
	))
	results.append(TestResult.new(
		"60s hands-off hover: linear velocity stays bounded (< 50 m/s)",
		max_linear_speed < 50.0,
		"max |v| = %.4f m/s" % max_linear_speed
	))

	var final_euler := core.rigid_body.orientation.get_euler(EULER_ORDER_YXZ)
	var final_tilt_deg := rad_to_deg(max(absf(final_euler.x), absf(final_euler.z)))
	results.append(TestResult.new(
		"60s hands-off hover: self-levels from a 5deg tilt to < 1deg",
		final_tilt_deg < 1.0,
		"final tilt = %.4f deg" % final_tilt_deg
	))

	return results
