class_name DroneCore
extends RefCounted
## The physics core (architecture.md): assembles day 2's verified subsystems into one
## steppable simulation. Zero engine/scene dependencies — a scene node drives this by
## calling step() every substep and reading rigid_body afterward, nothing more.

const GRAVITY_MPS2 := 9.81

var mass_properties: MassProperties
var rigid_body := RigidBodyState.new()
var motor_model: MotorModel
var arm_m: float
var k_t: float
var k_q: float
var battery: BatteryModel

var motor_max_amps: float
## The RPM at which a motor draws motor_max_amps with the fitted prop — a FIXED reference
## (KV x the voltage the amp figure was measured at), never the live RPM ceiling.
var rated_rpm: float
## 0.5 * rho * Cd * A, supplied per build — a 7" airframe presents far more area than a 3".
var drag_coefficient: float

var motor_rpm := {"M1": 0.0, "M2": 0.0, "M3": 0.0, "M4": 0.0}
var last_voltage_v: float
var last_current_total_a: float = 0.0

func _init(p_mass_properties: MassProperties, p_motor_model: MotorModel, p_arm_m: float, p_k_t: float, p_k_q: float, p_battery: BatteryModel, p_motor_max_amps: float, p_rated_rpm: float, p_drag_coefficient: float) -> void:
	rated_rpm = p_rated_rpm
	drag_coefficient = p_drag_coefficient
	mass_properties = p_mass_properties
	motor_model = p_motor_model
	arm_m = p_arm_m
	k_t = p_k_t
	k_q = p_k_q
	battery = p_battery
	motor_max_amps = p_motor_max_amps
	last_voltage_v = battery.nominal_v

## Current drawn by ONE motor at a given RPM. Current tracks shaft torque, and torque goes
## as RPM^2 just like thrust, so the reference point is a fixed RPM — the one the motor's
## amp rating was measured at — not the live RPM ceiling.
##
## Measuring it against the live ceiling instead makes current a function of the throttle
## COMMAND rather than of what the motor is really doing, which inverts the feedback: a
## sagging pack should spin the motors slower and therefore draw LESS current, self-limiting.
## Against the live ceiling it keeps drawing full current for RPM it never reached, and a
## high-resistance pack runs away to a total voltage collapse that does not happen in reality.
func current_at_rpm(rpm: float) -> float:
	if rated_rpm <= 0.0:
		return 0.0
	var rpm_fraction := rpm / rated_rpm
	return motor_max_amps * rpm_fraction * rpm_fraction

## Places all four motors at the steady-state RPM for a given throttle, and the pack at
## the voltage that draws. Motors otherwise start dead: spinning up through the ~30 ms lag
## costs about 0.4 m/s of downward velocity, and with no altitude hold in week 1 that
## velocity never comes back — the drone spawns and sinks forever at a constant rate.
func prime_motors(throttle: float) -> void:
	var t := clampf(throttle, 0.0, motor_model.max_throttle)
	# rpm and the sag it causes are mutually dependent; converges quickly because the
	# current term is self-limiting.
	var voltage_v := battery.nominal_v
	var rpm := 0.0
	for _i in 12:
		rpm = t * motor_model.max_rpm(voltage_v)
		voltage_v = battery.voltage_live(4.0 * current_at_rpm(rpm))
	last_current_total_a = 4.0 * current_at_rpm(rpm)
	last_voltage_v = voltage_v
	for name in MotorLayout.MOTOR_NAMES:
		motor_rpm[name] = rpm

## motor_throttle_cmds = {"M1": 0..1, "M2": 0..1, "M3": 0..1, "M4": 0..1}
func step(motor_throttle_cmds: Dictionary, dt: float) -> void:
	var total_force := Vector3(0, -GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var total_torque := Vector3.ZERO
	var total_current_a := 0.0
	var total_thrust_body_n := 0.0

	for name in MotorLayout.MOTOR_NAMES:
		var rpm: float = motor_model.step(motor_rpm[name], motor_throttle_cmds[name], last_voltage_v, dt)
		motor_rpm[name] = rpm

		var thrust_n := PropellerModel.thrust_n(k_t, rpm)
		var reaction_n_m := PropellerModel.reaction_torque_n_m(k_q, rpm)
		total_current_a += current_at_rpm(rpm)

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

	rigid_body.integrate(total_force, total_torque, mass_properties.total_mass_kg, mass_properties.inertia, mass_properties.inertia_inverse, dt)

	battery.drain(total_current_a, dt)
	last_current_total_a = total_current_a
	last_voltage_v = battery.voltage_live(total_current_a)
