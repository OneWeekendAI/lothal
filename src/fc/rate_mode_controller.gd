class_name RateModeController
extends RefCounted
## THE inner loop. PID on angular rate, all three axes, every mode, no exceptions — and the
## only thing in the codebase that produces motor commands (physics.md §7).
##
## This is what a real flight controller is. It does not know or care whether the setpoints
## in front of it came from a pilot's sticks in acro or from a self-levelling outer loop in
## angle mode; it is handed a rate setpoint per axis and a gyro reading, and it closes the
## loop between them. Self-levelling is a front end, not a second control law.
##
## That distinction is the whole point of the restructure. Lothal previously had TWO laws
## producing motor commands from different inputs, and angle mode's yaw was a raw torque
## passthrough with no loop on it at all — so releasing the stick meant "stop pushing"
## rather than "stop rotating", and two taps cancelled only if their durations matched
## exactly, which human taps never do. Having two laws also meant a fix to one silently did
## not apply to the other, which is a standing bug source rather than a single bug.
##
## Gains act on a NORMALIZED rate error (a fraction of MAX_RATE_RAD_S), which is why they
## are small dimensionless numbers rather than raw rad/s gains.
##
## Roll and pitch were tuned against tests/test_rate_step_response.gd and
## tests/test_rate_mode_release.gd in physics.md §7's stated order: P raised until
## oscillation (~1.5, 24% overshoot), backed off, D added to kill bounce-back, a small I
## last for steady-state drift. Yaw is NOT a copy of them — see below.

const MAX_RATE_RAD_S := 13.962634   # 800 deg/s at full stick

var pid_roll := PIDController.new(2.3, 0.15, 0.042)
var pid_pitch := PIDController.new(2.3, 0.15, 0.042)
var pid_yaw := PIDController.new(2.3, 0.15, 0.042)

## The acro front end: all three sticks ARE rate setpoints, and the outer loop is simply
## absent. Named as a function rather than left inline so both front ends read the same way
## at the call site — see FlightController, where the mode switch chooses between this and
## AngleModeController.rate_setpoint and changes nothing else.
static func rate_setpoint(rc: Dictionary) -> Vector3:
	return Vector3(rc.roll, rc.pitch, rc.yaw)

## setpoint_normalized — Vector3(roll, pitch, yaw), each -1..1 as a fraction of
##   MAX_RATE_RAD_S, whatever produced it.
## gyro_rate_rad_s — the SENSOR's body-frame reading (DroneCore.gyro), never ground truth.
func update(setpoint_normalized: Vector3, gyro_rate_rad_s: Vector3, throttle: float, dt: float) -> Dictionary:
	# One expression of the body-XYZ -> roll/pitch/yaw mapping, borrowed from the sensor that
	# owns it. Writing it out by hand here is how the two old control laws came to disagree.
	var measured := Gyro.contract_rates(gyro_rate_rad_s) / MAX_RATE_RAD_S

	# PIDController clamps its own output and stops integrating while it is clamped, so
	# there is no clampf here — a second clamp outside the controller would hide the
	# saturation from the anti-windup that needs to see it.
	var roll_cmd := pid_roll.update(setpoint_normalized.x, measured.x, dt)
	var pitch_cmd := pid_pitch.update(setpoint_normalized.y, measured.y, dt)
	var yaw_cmd := pid_yaw.update(setpoint_normalized.z, measured.z, dt)

	return MotorMixer.mix(throttle, roll_cmd, pitch_cmd, yaw_cmd)

func reset() -> void:
	pid_roll.reset()
	pid_pitch.reset()
	pid_yaw.reset()
