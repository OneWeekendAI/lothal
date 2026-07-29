class_name MotorMixer
extends RefCounted
## Standard X-quad mixer: turns normalized throttle + roll/pitch/yaw correction commands
## into a per-motor throttle command. This is the inverse of motor_layout.gd's
## torque_from_motor — it must move motors in the direction that PRODUCES the requested
## sign of roll/pitch/yaw under the coordinate contract, not the direction that looks
## obvious from the motor's own position. See test_torque_signs.gd for the hand-check
## this is built from: extra right-motor thrust yields -Roll, so +roll_cmd DECREASES
## right motors; extra rear-motor thrust yields -Pitch, so +pitch_cmd DECREASES rear motors.

const MIX_GAIN := 0.2   # fraction of throttle range given to attitude authority

static func mix(throttle: float, roll_cmd: float, pitch_cmd: float, yaw_cmd: float) -> Dictionary:
	var out := {}
	for name in MotorLayout.MOTOR_NAMES:
		var t := throttle
		t += pitch_cmd * MIX_GAIN * (1.0 if MotorLayout.IS_FRONT[name] else -1.0)
		t += roll_cmd * MIX_GAIN * (-1.0 if MotorLayout.IS_RIGHT[name] else 1.0)
		t += yaw_cmd * MIX_GAIN * MotorLayout.SPIN[name]
		out[name] = clampf(t, 0.0, 1.0)
	return out
