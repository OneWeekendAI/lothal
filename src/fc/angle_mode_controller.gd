class_name AngleModeController
extends RefCounted
## Angle mode (self-levelling) flight controller — physics.md §7's Implementation A.
## Single method contract, matching architecture.md's FlightController interface:
##   update(orientation, rc) -> motor_output[4]
## Stick position commands an ABSOLUTE roll/pitch angle rather than a rate, which is
## why it visibly hovers hands-off: zero stick means "hold level", not "hold rate zero".
## Rate-mode PID (acro) is day 4's job, behind this same interface.

const MAX_ANGLE_RAD := 0.5235988   # 30 degrees
const ANGLE_P := 1.5               # tuned by feel; day 4 owns the real tuning harness
## A pure-P angle loop is an undamped oscillator — it will ring and, past small-angle
## range, tumble rather than settle. This light rate term is the minimum damping needed
## for angle mode to actually self-level; it is NOT day 4's cascaded rate-mode PID.
const ANGLE_D := 0.15

## rc = {roll: -1..1, pitch: -1..1, yaw: -1..1, throttle: 0..1}
static func update(orientation: Quaternion, angular_velocity_rad_s: Vector3, rc: Dictionary) -> Dictionary:
	var euler := orientation.get_euler(EULER_ORDER_YXZ)
	var pitch_current := euler.x    # rotation about +X; +Pitch = nose up (coordinate contract)
	var roll_current := -euler.z    # rotation about -Z; +Roll = right side down (coordinate contract)
	var pitch_rate_current := angular_velocity_rad_s.x
	var roll_rate_current := -angular_velocity_rad_s.z

	var pitch_error: float = (rc.pitch * MAX_ANGLE_RAD) - pitch_current
	var roll_error: float = (rc.roll * MAX_ANGLE_RAD) - roll_current

	var pitch_cmd := clampf(ANGLE_P * pitch_error - ANGLE_D * pitch_rate_current, -1.0, 1.0)
	var roll_cmd := clampf(ANGLE_P * roll_error - ANGLE_D * roll_rate_current, -1.0, 1.0)
	var yaw_cmd: float = rc.yaw   # rate passthrough — angle mode does not lock absolute yaw

	return MotorMixer.mix(rc.throttle, roll_cmd, pitch_cmd, yaw_cmd)
