class_name Powertrain
extends RefCounted
## Motors, propellers and the pack — the electro-mechanical half of the simulation, with
## no rigid body anywhere in it. This is what Lothal Labs runs: a thrust stand.
##
## The split exists because a bench and a flight need exactly the same electrical model
## and share nothing else. Keeping one copy of that model means a motor that behaves a
## certain way on the garage bench behaves identically in the field by construction, not
## by two implementations agreeing today and drifting apart next month.
##
## Owns the powertrain half of the published Observables (architecture.md). DroneCore adds
## the flight half to the SAME Observables instance, so consumers never learn which half
## produced what — the HUD and the audio synthesiser work on a bench unchanged.
##
## Nothing in this file may reference position, velocity, orientation, mass, inertia or
## drag. tests/test_powertrain.gd asserts the consequence (a bench never moves); the
## absence itself is the design.

var motor_model: MotorModel
var battery: BatteryModel
var k_t: float
var k_q: float

var motor_max_amps: float
## The RPM at which a motor draws motor_max_amps with the fitted prop — a FIXED reference
## (KV x the voltage the amp figure was measured at), never the live RPM ceiling.
var rated_rpm: float

## Geometry the dynamics do not need but consumers do (audio needs all three).
var pole_pairs: float = 7.0
var blades: float = 3.0
var prop_radius_m: float = 0.0635

var motor_rpm := {"M1": 0.0, "M2": 0.0, "M3": 0.0, "M4": 0.0}
var last_voltage_v: float
var last_current_total_a: float = 0.0

## The published observables layer. Created here and shared with DroneCore when one wraps
## this — there is exactly one instance per simulation, bench or flight.
var observables := Observables.new()

func _init(p_motor_model: MotorModel, p_k_t: float, p_k_q: float, p_battery: BatteryModel, p_motor_max_amps: float, p_rated_rpm: float, p_pole_pairs: float = 7.0, p_blades: float = 3.0, p_prop_radius_m: float = 0.0635) -> void:
	motor_model = p_motor_model
	k_t = p_k_t
	k_q = p_k_q
	battery = p_battery
	motor_max_amps = p_motor_max_amps
	rated_rpm = p_rated_rpm
	pole_pairs = p_pole_pairs
	blades = p_blades
	prop_radius_m = p_prop_radius_m
	last_voltage_v = battery.nominal_v
	publish()

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

## Places all four motors at the steady-state RPM for a given throttle, and the pack at the
## voltage that draws. Motors otherwise start dead, and a consumer that reads between
## construction and the first step sees a machine at rest that it was told is running.
func prime(throttle: float) -> void:
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
	publish()

## Advances every motor one dt, drains the pack, and republishes.
## motor_throttle_cmds = {"M1": 0..1, "M2": 0..1, "M3": 0..1, "M4": 0..1}
func step(motor_throttle_cmds: Dictionary, dt: float) -> void:
	var total_current_a := 0.0

	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var rpm: float = motor_model.step(motor_rpm[name], motor_throttle_cmds[name], last_voltage_v, dt)
		motor_rpm[name] = rpm
		observables.thrust_n[i] = PropellerModel.thrust_n(k_t, rpm)
		total_current_a += current_at_rpm(rpm)

	# The simulation's own clock. Here rather than in DroneCore because a BENCH runs a powertrain
	# with no rigid body anywhere near it and still has an elapsed time, and two places advancing
	# one clock is two places to forget to.
	observables.elapsed_s += dt

	battery.drain(total_current_a, dt)
	last_current_total_a = total_current_a
	# The live voltage the NEXT step's RPM ceiling is taken against. This one line is the
	# difference between a bench and a spreadsheet: without it every motor converges to the
	# nominal-voltage ceiling and reads a few hundred RPM high, for ever, while looking
	# entirely plausible.
	last_voltage_v = battery.voltage_live(total_current_a)

	publish()

## Fills the powertrain half of the observables layer. The ONLY place blade-pass and
## electrical frequency are computed: architecture.md's stated failure mode is audio and
## the HUD each deriving their own RPM and drifting apart, and the way to make that
## impossible is for there to be exactly one expression of each in the codebase.
##
## Called from step() and prime(), never from a consumer — a consumer that can trigger a
## republish can trigger it at a different rate than physics runs at, which is the same
## drift by another route.
func publish() -> void:
	var total_thrust := 0.0
	for i in MotorLayout.MOTOR_NAMES.size():
		var rpm: float = motor_rpm[MotorLayout.MOTOR_NAMES[i]]
		var rev_per_s := rpm / 60.0
		observables.rpm[i] = rpm
		observables.blade_pass_hz[i] = rev_per_s * blades
		observables.electrical_hz[i] = rev_per_s * pole_pairs
		observables.tip_speed_mps[i] = PropellerModel.rpm_to_rad_s(rpm) * prop_radius_m
		# Recomputed from stored rpm like everything else in this function, so a republish is
		# still idempotent. This is THE call site of the propeller's reaction law: DroneCore
		# reads the published value rather than evaluating k_q x omega^2 a second time.
		observables.reaction_torque_n_m[i] = PropellerModel.reaction_torque_n_m(k_q, rpm)
		observables.current_a[i] = current_at_rpm(rpm)
		total_thrust += observables.thrust_n[i]

	observables.total_thrust_n = total_thrust
	observables.current_total_a = last_current_total_a
	observables.voltage_live_v = last_voltage_v
	observables.capacity_used_fraction = 1.0 - battery.remaining_fraction()

	observables.prop_radius_m = prop_radius_m
	observables.blades = blades
	observables.pole_pairs = pole_pairs
