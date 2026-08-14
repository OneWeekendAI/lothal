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
## The aircraft's rate sensor. It lives here, on the aircraft, rather than in the scene:
## the flight controller must have exactly ONE route to a rate, and if a consumer can reach
## around this to rigid_body.angular_velocity_rad_s then the seam exists on paper only.
##
## HANDED IN rather than constructed here, because its four figures are properties of the
## FLIGHT CONTROLLER that is fitted (data/parts/flight_controllers.json) and a core that
## built its own would be a second opinion about what board this aircraft has. A core built
## without one gets the stock sensor, so every call site written before flight controllers
## were selectable still means what it meant.
var gyro: Gyro
var arm_m: float
## 0.5 * rho * Cd * A, supplied per build — a 7" airframe presents far more area than a 3".
var drag_coefficient: float

## The published observables layer — the SAME instance the powertrain fills, so a consumer
## cannot tell which half published what. Refilled at the end of every step(); no consumer
## should read physics internals directly.
var observables: Observables

func _init(p_mass_properties: MassProperties, p_motor_model: MotorModel, p_arm_m: float, p_k_t: float, p_k_q: float, p_battery: BatteryModel, p_motor_max_amps: float, p_rated_rpm: float, p_drag_coefficient: float, p_pole_pairs: float = 7.0, p_blades: float = 3.0, p_prop_radius_m: float = 0.0635, p_gyro: Gyro = null, p_prop_pitch_m: float = 0.10922,
		p_air_density_kgm3: float = AirDensity.standard_kgm3()) -> void:
	powertrain = Powertrain.create(p_motor_model, p_k_t, p_k_q, p_battery, p_motor_max_amps,
		p_rated_rpm, p_pole_pairs, p_blades, p_prop_radius_m, p_prop_pitch_m, p_air_density_kgm3)
	observables = powertrain.observables
	mass_properties = p_mass_properties
	arm_m = p_arm_m
	drag_coefficient = p_drag_coefficient
	gyro = p_gyro if p_gyro != null else Gyro.new()
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
	# which is the same ordering the single fused loop had. Across the FFI the powertrain's
	# step takes the commands as a typed array (MotorLayout.MOTOR_NAMES order), so the
	# string-keyed Dictionary is unpacked here, once, rather than carried across the boundary.
	var cmds := PackedFloat64Array()
	for name in MotorLayout.MOTOR_NAMES:
		cmds.append(motor_throttle_cmds.get(name, 0.0))
	# The powertrain is told how the aircraft is MOVING, not just what the sticks asked for. Without
	# this line the propeller behaves identically parked and at 120 km/h: no unloading at speed, and
	# no translational lift, so forward flight costs the same current as hovering. Both halves
	# matter and they pull opposite ways — see PropellerModel's forward-flight block.
	#
	# In the BODY frame, because that is where the rotor axis is: thrust is along body +Y, so the
	# component of velocity that unloads the prop is simply .y, and nothing has to decide what a
	# lean angle's sign convention is. Taken BEFORE integration, so it is the velocity this tick's
	# forces are being built at, which is the same convention every other term here uses.
	powertrain.step_in_flight(cmds, dt, rigid_body.orientation.inverse() * rigid_body.velocity_mps)

	var total_force := Vector3(0, -GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var total_torque := Vector3.ZERO
	var total_thrust_body_n := 0.0

	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var thrust_n: float = powertrain.observables.thrust_n[i]
		# Read, not recomputed: the powertrain stepped and published a line above, so this is the
		# reaction torque of THIS tick's rpm, and it is the same number any consumer reading the
		# observables layer sees. A second k_q x omega^2 here would agree with it exactly until
		# the day one of the two was edited.
		var reaction_n_m: float = powertrain.observables.reaction_torque_n_m[i]

		total_thrust_body_n += thrust_n

		# Arms are measured from the CENTRE OF MASS, not from the frame's origin — the aircraft
		# rotates about the former, and the inertia tensor this torque is about to be integrated
		# against is already computed about it too (MassProperties). MotorLayout owns the cross
		# product; this loop must not grow a second one, which is the duplication that made the
		# reference point possible to get wrong in only one of two places.
		var tau := MotorLayout.thrust_torque(name, thrust_n, arm_m, mass_properties.com_m)
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

	# The sensor's shake follows the MOTORS, so the four current rpms are handed over before the
	# sample. Four rather than one average: they are not equal while the aircraft is manoeuvring,
	# and that inequality is what turns the signal into a beating, wandering thing instead of a
	# single sine. Pushed rather than pulled because Gyro must not know what a Powertrain is —
	# it is a sensor, and this core is the one thing that holds both halves.
	if gyro.vibration is VibrationModel:
		gyro.vibration.set_rpm(powertrain.motor_rpm)

	# Sampled AFTER integration, so the reading the controller picks up at the top of the
	# next substep is one tick old. That is not an approximation to apologise for — it is
	# what a real loop does, and the delay is part of what the gains are tuned against.
	gyro.update(rigid_body.angular_velocity_rad_s, dt)

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
	observables.gyro_rad_s = gyro.rate_rad_s
	observables.airspeed_mps = rigid_body.velocity_mps.length()

	var specific_accel := specific_force_n / mass_properties.total_mass_kg
	observables.accel_body_mps2 = rigid_body.orientation.inverse() * specific_accel
	observables.g_force = specific_accel.length() / GRAVITY_MPS2
