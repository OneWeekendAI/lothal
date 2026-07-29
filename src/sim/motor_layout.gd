class_name MotorLayout
extends RefCounted
## Motor positions and spin directions for a symmetric X-quad, per the coordinate
## contract in physics.md §1 (Betaflight numbering, viewed from above, nose = -Z):
##   M1 = rear-right    M2 = front-right
##   M3 = rear-left     M4 = front-left
## Invariant: diagonal pairs (M1/M4, M2/M3) spin the SAME direction; adjacent pairs oppose.

const SPIN := {
	"M1": 1.0, "M4": 1.0,
	"M2": -1.0, "M3": -1.0,
}

static func motor_position(name: String, arm_m: float) -> Vector3:
	var a := arm_m * cos(deg_to_rad(45.0))
	match name:
		"M1": return Vector3(a, 0, a)     # rear-right
		"M2": return Vector3(a, 0, -a)    # front-right
		"M3": return Vector3(-a, 0, a)    # rear-left
		"M4": return Vector3(-a, 0, -a)   # front-left
	push_error("unknown motor name: %s" % name)
	return Vector3.ZERO

## Torque a single motor contributes about the body's roll/pitch/yaw axes, given a
## thrust delta (N, applied along body +Y at the motor's position) and its reaction
## torque (N*m, about the motor's own spin axis, +Y).
##
## Roll and yaw are defined about the NEGATIVE Z and Y axes respectively (physics.md §1:
## "+Roll ... rotation about the forward axis, -Z", "+Yaw ... rotation about -Y"), while
## pitch is defined about +X directly. So roll_signed and yaw_signed below are the
## negated Z/Y components of the raw torque vector; pitch_signed is the raw X component.
static func torque_from_motor(name: String, thrust_delta_n: float, reaction_torque_n_m: float, arm_m: float) -> Dictionary:
	var pos := motor_position(name, arm_m)
	var lift := Vector3(0, thrust_delta_n, 0)
	var tau := pos.cross(lift)   # r x F; y-component is always 0 for vertical F

	var spin: float = SPIN[name]
	var yaw_reaction := spin * reaction_torque_n_m   # sign convention verified in test_torque_signs.gd

	return {
		"pitch": tau.x,
		"roll": -tau.z,
		"yaw": yaw_reaction,
	}
