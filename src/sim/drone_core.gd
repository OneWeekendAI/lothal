class_name DroneCore
extends RefCounted
## The physics core (architecture.md): a Powertrain plus a rigid body. Zero engine/scene
## dependencies — a scene node drives this by calling step() every substep and reading
## rigid_body afterward, nothing more.
##
## Everything electrical lives in Powertrain, which runs perfectly well without this class.
## That is what lets Lothal Labs bench a motor with no flight simulation: the field is the
## garage plus an integrator, and there is only one copy of the electrical model.

const GRAVITY_MPS2 := 9.81

var powertrain: Powertrain
var mass_properties: MassProperties
var rigid_body := RigidBodyState.new()
var arm_m: float
## 0.5 * rho * Cd * A, supplied per build — a 7" airframe presents far more area than a 3".
var drag_coefficient: float

## The published observables layer — the SAME instance the powertrain fills, so a consumer
## cannot tell which half published what. Refilled at the end of every step(); no consumer
## should read physics internals directly.
var observables: Observables
## Aliases the powertrain's dictionary. Dictionaries are reference types in GDScript, so
## writing through either name reaches the same storage.
var motor_rpm: Dictionary

func _init(p_mass_properties: MassProperties, p_motor_model: MotorModel, p_arm_m: float, p_k_t: float, p_k_q: float, p_battery: BatteryModel, p_motor_max_amps: float, p_rated_rpm: float, p_drag_coefficient: float, p_pole_pairs: float = 7.0, p_blades: float = 3.0, p_prop_radius_m: float = 0.0635) -> void:
	powertrain = Powertrain.new(p_motor_model, p_k_t, p_k_q, p_battery, p_motor_max_amps,
		p_rated_rpm, p_pole_pairs, p_blades, p_prop_radius_m)
	observables = powertrain.observables
	motor_rpm = powertrain.motor_rpm
	mass_properties = p_mass_properties
	arm_m = p_arm_m
	drag_coefficient = p_drag_coefficient
	_publish(Vector3.ZERO)

## Current drawn by ONE motor at a given RPM. Delegates: there is one such function in the
## codebase and it is the powertrain's.
func current_at_rpm(rpm: float) -> float:
	return powertrain.current_at_rpm(rpm)

## Places all four motors at the steady-state RPM for a given throttle, and the pack at
## the voltage that draws. Motors otherwise start dead: spinning up through the ~30 ms lag
## costs about 0.4 m/s of downward velocity, and with no altitude hold in week 1 that
## velocity never comes back — the drone spawns and sinks forever at a constant rate.
func prime_motors(throttle: float) -> void:
	powertrain.prime(throttle)
	# Priming is a state change like any other, and consumers read observables between a
	# respawn and the next step(). Leaving the flight half stale here means the HUD spends
	# one frame reporting the g-force of the flight that just ended in a crash.
	_publish(Vector3.ZERO)

## motor_throttle_cmds = {"M1": 0..1, "M2": 0..1, "M3": 0..1, "M4": 0..1}
func step(motor_throttle_cmds: Dictionary, dt: float) -> void:
	# The powertrain advances first: the forces below are built from the RPM this produces,
	# which is the same ordering the single fused loop had.
	powertrain.step(motor_throttle_cmds, dt)

	var total_force := Vector3(0, -GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var total_torque := Vector3.ZERO
	var total_thrust_body_n := 0.0

	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var rpm: float = powertrain.motor_rpm[name]
		var thrust_n: float = powertrain.observables.thrust_n[i]
		var reaction_n_m := PropellerModel.reaction_torque_n_m(powertrain.k_q, rpm)

		var pos := MotorLayout.motor_position(name, arm_m)
		var lift := Vector3(0, thrust_n, 0)   # BODY frame: props always push along the body's own up
		total_thrust_body_n += thrust_n

		var tau := pos.cross(lift)   # body-frame torque about X/Z from thrust position; Y is always 0 here
		var spin: float = MotorLayout.SPIN[name]
		var reaction_about_y := -spin * reaction_n_m   # Newton's third law: opposes the rotor's own spin
		total_torque += Vector3(tau.x, reaction_about_y, tau.z)

	# Thrust is generated along BODY +Y and must be rotated into the world frame before it
	# is summed with gravity and drag (physics.md §4, "along body +Y"). Skipping this
	# rotation leaves the drone unable to translate at all: it banks and stays put, because
	# a tilted quad's thrust would still point straight up. Torque stays in the body frame,
	# which is where the inertia tensor and the gyroscopic term live.
	total_force += rigid_body.orientation * Vector3(0, total_thrust_body_n, 0)

	var speed := rigid_body.velocity_mps.length()
	if speed > 0.0:
		total_force += -rigid_body.velocity_mps.normalized() * drag_coefficient * speed * speed

	# Specific force — total force minus gravity — is captured BEFORE integration, while
	# the force that produced this tick's acceleration is still in hand. Recovering it
	# afterwards from a velocity difference would be a numerical derivative of an
	# integrated quantity, which is both noisier and one tick late.
	var specific_force := total_force + Vector3(0, GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)

	rigid_body.integrate(total_force, total_torque, mass_properties.total_mass_kg, mass_properties.inertia, mass_properties.inertia_inverse, dt)

	_publish(specific_force)

## Fills the FLIGHT half of the observables layer; the powertrain half is already filled by
## Powertrain.publish(). Republishing the powertrain half here is what this split exists to
## prevent, so this function must never recompute rpm, thrust, blade-pass or voltage.
##
## It does still CALL powertrain.publish(), which is a different thing: tests/test_observables.gd
## writes RPM straight into core.motor_rpm and then calls _publish, expecting blade-pass to be
## recomputed from it — precisely the check that blade-pass has one expression in the codebase.
## The republish is idempotent; it recomputes from stored state and integrates nothing.
func _publish(specific_force_n: Vector3) -> void:
	powertrain.publish()

	observables.weight_n = mass_properties.total_mass_kg * GRAVITY_MPS2

	observables.position_m = rigid_body.position_m
	observables.velocity_mps = rigid_body.velocity_mps
	observables.orientation = rigid_body.orientation
	observables.angular_velocity_rad_s = rigid_body.angular_velocity_rad_s
	observables.airspeed_mps = rigid_body.velocity_mps.length()

	var specific_accel := specific_force_n / mass_properties.total_mass_kg
	observables.accel_body_mps2 = rigid_body.orientation.inverse() * specific_accel
	observables.g_force = specific_accel.length() / GRAVITY_MPS2
