class_name MotorLayout
extends RefCounted
## Motor positions and spin directions for a symmetric X-quad, per the coordinate
## contract in physics.md §1 (Betaflight numbering, viewed from above, nose = -Z):
##   M1 = rear-right    M2 = front-right
##   M3 = rear-left     M4 = front-left
## Invariant: diagonal pairs (M1/M4, M2/M3) spin the SAME direction; adjacent pairs oppose.

const MOTOR_NAMES := ["M1", "M2", "M3", "M4"]

const SPIN := {
	"M1": 1.0, "M4": 1.0,
	"M2": -1.0, "M3": -1.0,
}

## THE ONE ACCESSOR. Config-room design §5.1: `SPIN` is read from two places — `MotorMixer.mix()`
## and `torque_from_motor()` below — and they must never be allowed to disagree about which way a
## motor turns. Both go through here, so an authored map reaches the mixer and the torque model as
## one fact rather than two.
##
## `config` is the persisted `config` decision block (C1), and its `motor_spin` key is either:
##   - absent, or "props_out"  — today's constants, BIT FOR BIT. A build saved before this room
##     existed flies exactly the aircraft it was saved as, which is what §5.2 is protecting: every
##     oracle in the project is defined at this configuration.
##   - "props_in"              — every motor reversed. Both fly; what changes is which way each
##     prop is mounted and which way the aircraft washes out (§4.3).
##   - a Dictionary            — a per-motor map, taken VERBATIM, including one that cannot fly.
##     §5.3: a wrong configuration must fly badly, not be blocked. Correcting it here would make
##     `ConfigPlausibility`'s warning a lie, because the aircraft would not be the one accused.
##
## A motor the map does not mention keeps its default, and a value that is not a number is not a
## spin direction and is ignored — the sign of a float is the only thing this can return.
static func spin_map(config: Dictionary = {}) -> Dictionary:
	var authored: Variant = config.get("motor_spin", null)
	var out := {}
	for name in MOTOR_NAMES:
		var value: float = SPIN[name]
		if authored is String and String(authored) == "props_in":
			value = -value
		elif authored is Dictionary:
			var per_motor: Dictionary = authored
			if per_motor.has(name):
				var raw: Variant = per_motor[name]
				if raw is float or raw is int:
					value = -1.0 if float(raw) < 0.0 else 1.0
		out[name] = value
	return out


## What a spin sign is CALLED, viewed from above — the one spelling in the project.
##
## A positive sign is a positive rotation about +Y, and a rotation about +Y reads CLOCKWISE to
## somebody looking DOWN at the aircraft, which is how a builder looks at it with the props off.
## Written here rather than inline at each site because C3 gave the sign a second reader: the
## warning quotes the map in words and the marker on the aircraft labels each motor, and two
## copies of this sentence could disagree about which way "CW" points while both kept passing.
static func direction_name(spin: float) -> String:
	return "CW" if spin > 0.0 else "CCW"


const IS_FRONT := {
	"M1": false, "M2": true, "M3": false, "M4": true,
}
const IS_RIGHT := {
	"M1": true, "M2": true, "M3": false, "M4": false,
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

## The body-frame torque one motor's thrust exerts on the aircraft, as a raw r x F vector.
##
## THIS IS THE PROJECT'S ONLY CROSS PRODUCT FOR THRUST TORQUE, and it is a single function
## because of what its third argument is.
##
## `com_m` is the point the aircraft rotates about. An aircraft rotates about its centre of mass,
## not about the frame's geometric origin, so the torque arm is measured from the CoM — the origin
## is just where the modeller happened to put (0,0,0). For every build Lothal could describe until
## the mount offsets reached the mass model those two points coincided, and while they coincide the
## distinction cannot be seen: r x F returns the same number either way.
##
## Which is exactly why it needed one home. Once a pack can be slid forward, an origin-referenced
## torque is wrong by (com x F) — and wrong SILENTLY, because the number stays plausible and the
## aircraft still flies. It would surface as a tune that stopped equalising across the catalog, and
## the search would start in RateTune, which would be innocent. Two copies of this arithmetic
## (torque_from_motor had one, DroneCore.step() had the other) were survivable while the answer
## could not differ and are not survivable now.
##
## It also settles a reference-point mismatch that was already latent: MassProperties shifts every
## part's inertia about the COMPOSITE CENTRE OF MASS (parallel axis relative to `com`), so an
## origin-referenced torque handed to integrate() alongside that tensor would be two different
## reference points in one equation of motion.
##
## Defaults to the origin, which is the honest default for a caller that has no mass model to ask —
## and is what every current caller passed implicitly before this argument existed.
static func thrust_torque(name: String, thrust_n: float, arm_m: float, com_m: Vector3 = Vector3.ZERO) -> Vector3:
	var arm := motor_position(name, arm_m) - com_m
	return arm.cross(Vector3(0, thrust_n, 0))   # y-component is always 0 for a vertical F


## Torque a single motor contributes about the body's roll/pitch/yaw axes, given a
## thrust delta (N, applied along body +Y at the motor's position) and its reaction
## torque (N*m, about the motor's own spin axis, +Y).
##
## Roll and yaw are defined about the NEGATIVE Z and Y axes respectively (physics.md §1:
## "+Roll ... rotation about the forward axis, -Z", "+Yaw ... rotation about -Y"), while
## pitch is defined about +X directly. So roll_signed and yaw_signed below are the
## negated Z/Y components of the raw torque vector; pitch_signed is the raw X component.
## `com_m` is the point the arms are measured from — see thrust_torque(), which does the actual
## cross product. This function is a RE-LABELLING of that vector into the coordinate contract's
## axes and nothing more; it must never grow a second r x F of its own.
## `config` is the build's `config` decision block; it reaches the spin direction through
## spin_map() and nowhere else — see that function for why there is only one door.
static func torque_from_motor(name: String, thrust_delta_n: float, reaction_torque_n_m: float, arm_m: float, com_m: Vector3 = Vector3.ZERO, config: Dictionary = {}) -> Dictionary:
	var tau := thrust_torque(name, thrust_delta_n, arm_m, com_m)

	var spin: float = spin_map(config)[name]
	var yaw_reaction := spin * reaction_torque_n_m   # sign convention verified in test_torque_signs.gd

	return {
		"pitch": tau.x,
		"roll": -tau.z,
		"yaw": yaw_reaction,
	}
