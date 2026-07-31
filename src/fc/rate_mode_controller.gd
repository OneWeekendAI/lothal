class_name RateModeController
extends RefCounted
## Acro mode (physics.md §7's Implementation A continued) — PID directly on angular
## rate rather than angle, which is where the "feel" of flying lives. Same single-method
## contract as AngleModeController so main.gd can swap between them behind one interface
## (architecture.md's FlightController). Gains act on a NORMALIZED rate error (measured
## as a fraction of max_rate), which is why they're small dimensionless numbers rather
## than raw rad/s gains.
##
## Tuned against tests/test_rate_step_response.gd and tests/test_rate_mode_release.gd,
## in week1.md's stated order: P raised until oscillation (~1.5, 24% overshoot), backed
## off, then D added to kill bounce-back, then a small I last for steady-state drift.
## Result: 3.1% overshoot, 77ms settle, no bounce-back past zero on release.

const MAX_RATE_RAD_S := 13.962634   # 800 deg/s at full stick

var pid_roll := PIDController.new(2.3, 0.15, 0.042)
var pid_pitch := PIDController.new(2.3, 0.15, 0.042)
var pid_yaw := PIDController.new(2.3, 0.15, 0.042)

## rc = {roll: -1..1, pitch: -1..1, yaw: -1..1, throttle: 0..1} — sticks command a RATE,
## not an angle, so releasing the stick commands zero rate, not "return to level."
func update(gyro_rate_rad_s: Vector3, rc: Dictionary, dt: float) -> Dictionary:
	var roll_rate_measured := -gyro_rate_rad_s.z    # matches the -euler.z roll sign convention
	var pitch_rate_measured := gyro_rate_rad_s.x
	var yaw_rate_measured := -gyro_rate_rad_s.y     # matches the "+Yaw = rotation about -Y" convention

	var roll_cmd := clampf(pid_roll.update(rc.roll, roll_rate_measured / MAX_RATE_RAD_S, dt), -1.0, 1.0)
	var pitch_cmd := clampf(pid_pitch.update(rc.pitch, pitch_rate_measured / MAX_RATE_RAD_S, dt), -1.0, 1.0)
	var yaw_cmd := clampf(pid_yaw.update(rc.yaw, yaw_rate_measured / MAX_RATE_RAD_S, dt), -1.0, 1.0)

	return MotorMixer.mix(rc.throttle, roll_cmd, pitch_cmd, yaw_cmd)

func reset() -> void:
	pid_roll.reset()
	pid_pitch.reset()
	pid_yaw.reset()
