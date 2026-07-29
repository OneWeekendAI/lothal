class_name DroneCore
extends RefCounted
## The physics core (architecture.md): assembles day 2's verified subsystems into one
## steppable simulation. Zero engine/scene dependencies — a scene node drives this by
## calling step() every substep and reading rigid_body afterward, nothing more.

const GRAVITY_MPS2 := 9.81
const LINEAR_DRAG_COEFF := 0.02   # small placeholder; real Cd*A comes with day 5/6 polish

var mass_properties: MassProperties
var rigid_body := RigidBodyState.new()
var motor_model: MotorModel
var arm_m: float
var k_t: float
var k_q: float
var battery: BatteryModel

var motor_rpm := {"M1": 0.0, "M2": 0.0, "M3": 0.0, "M4": 0.0}
var last_voltage_v: float
var last_current_total_a: float = 0.0

func _init(p_mass_properties: MassProperties, p_motor_model: MotorModel, p_arm_m: float, p_k_t: float, p_k_q: float, p_battery: BatteryModel) -> void:
	mass_properties = p_mass_properties
	motor_model = p_motor_model
	arm_m = p_arm_m
	k_t = p_k_t
	k_q = p_k_q
	battery = p_battery
	last_voltage_v = battery.nominal_v

## motor_throttle_cmds = {"M1": 0..1, "M2": 0..1, "M3": 0..1, "M4": 0..1}
func step(motor_throttle_cmds: Dictionary, dt: float) -> void:
	var total_force := Vector3(0, -GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var total_torque := Vector3.ZERO
	var total_current_a := 0.0

	for name in MotorLayout.MOTOR_NAMES:
		var rpm: float = motor_model.step(motor_rpm[name], motor_throttle_cmds[name], last_voltage_v, dt)
		motor_rpm[name] = rpm

		var thrust_n := PropellerModel.thrust_n(k_t, rpm)
		var reaction_n_m := PropellerModel.reaction_torque_n_m(k_q, rpm)
		# Current draw fit: quadratic in RPM like thrust, scaled to hit max_amps at max RPM.
		var rpm_fraction := rpm / motor_model.max_rpm(last_voltage_v)
		total_current_a += ReferenceBuild.MOTOR_MAX_AMPS * rpm_fraction * rpm_fraction

		var pos := MotorLayout.motor_position(name, arm_m)
		var lift := Vector3(0, thrust_n, 0)
		total_force += lift

		var tau := pos.cross(lift)   # physical torque about X/Z from thrust position; Y is always 0 here
		var spin: float = MotorLayout.SPIN[name]
		var reaction_about_y := -spin * reaction_n_m   # Newton's third law: opposes the rotor's own spin
		total_torque += Vector3(tau.x, reaction_about_y, tau.z)

	var speed := rigid_body.velocity_mps.length()
	if speed > 0.0:
		total_force += -rigid_body.velocity_mps.normalized() * LINEAR_DRAG_COEFF * speed * speed

	rigid_body.integrate(total_force, total_torque, mass_properties.total_mass_kg, mass_properties.inertia, mass_properties.inertia_inverse, dt)

	battery.drain(total_current_a, dt)
	last_current_total_a = total_current_a
	last_voltage_v = battery.voltage_live(total_current_a)
