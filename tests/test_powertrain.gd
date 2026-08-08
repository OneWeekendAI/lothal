class_name TestPowertrain
extends RefCounted
## The bench suite. Every test here constructs a Powertrain DIRECTLY — no DroneCore, no
## MassProperties, no RigidBodyState — because that is the whole claim being made: the
## garage can spin a motor without the field existing.
##
## The checks with teeth are the first two. Build solves steady-state RPM and thrust
## ANALYTICALLY, by iterating a fixed point; Powertrain reaches them DYNAMICALLY, by
## integrating a first-order lag against a sagging pack. Those are two independent routes
## to the same number, so agreement is evidence rather than tautology. A bench that quietly
## ignored pack sag would still converge — to a number several hundred RPM too high.

const BENCH_DT := 0.001          # 1 kHz, the same substep the flight loop uses
const SETTLE_STEPS := 2000       # 2 s, ~66 motor time constants
const TEST_THROTTLE := 0.5

static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()

	# --- Steady-state RPM, dynamic vs analytic ---
	var pt := _bench(build)
	for _i in SETTLE_STEPS:
		pt.step(_even(TEST_THROTTLE), BENCH_DT)

	# Predicted at the voltage the bench's pack is ACTUALLY resting at, not at the nominal datum
	# Build quotes its stats panel figures at. Those are different questions since nominal became
	# an operating point rather than full charge (physics.md §5): this pack is nearly full, so it
	# rests above nominal, and comparing a run at 16.8 V against arithmetic at 14.8 V would be
	# asserting that the datum change did not happen.
	var bench_rest_v := pt.battery.resting_voltage_v()
	var expected_rpm := build.rpm_at_throttle(TEST_THROTTLE, bench_rest_v)
	var actual_rpm: float = pt.motor_rpm[0]
	results.append(TestResult.new(
		"a bench with no rigid body settles at the analytically predicted RPM",
		absf(actual_rpm - expected_rpm) / expected_rpm < 0.01,
		"bench %.0f RPM vs analytic %.0f RPM" % [actual_rpm, expected_rpm]
	))

	# --- Steady-state thrust, dynamic vs analytic ---
	var expected_thrust := build.thrust_at_throttle_n(TEST_THROTTLE, bench_rest_v)
	var actual_thrust: float = pt.observables.total_thrust_n
	results.append(TestResult.new(
		"published bench thrust matches the analytic thrust at the same throttle",
		absf(actual_thrust - expected_thrust) / expected_thrust < 0.02,
		"bench %.2f N vs analytic %.2f N" % [actual_thrust, expected_thrust]
	))

	# --- The pack sags under load, on the bench, exactly as it does in flight ---
	results.append(TestResult.new(
		"the pack sags under bench load rather than sitting at its resting voltage",
		pt.last_voltage_v < bench_rest_v - 0.05 and pt.last_voltage_v > 0.0,
		"%.2f V live under %.1f A, resting %.2f V (nominal %.2f V)" % [
			pt.last_voltage_v, pt.last_current_total_a, bench_rest_v,
			build.battery_model().nominal_v]
	))

	# --- Capacity is consumed by bench running, so a bench session costs charge ---
	results.append(TestResult.new(
		"running the bench drains the pack",
		pt.observables.capacity_used_fraction > 0.0,
		"used %.4f%% of capacity over %.1f s" % [
			pt.observables.capacity_used_fraction * 100.0, SETTLE_STEPS * BENCH_DT]
	))

	# --- Everything the audio synthesiser reads is published by the bench alone ---
	# DroneAudio/RotorSynth consume only Observables. If the bench fills these, the garage
	# is audible with zero changes to the audio code — architecture.md's stated test that
	# adding a consumer touches no physics.
	var audio_fields_filled: bool = (
		pt.observables.rpm[0] > 0.0
		and pt.observables.blade_pass_hz[0] > 0.0
		and pt.observables.electrical_hz[0] > 0.0
		and pt.observables.tip_speed_mps[0] > 0.0
		and pt.observables.thrust_n[0] > 0.0
	)
	results.append(TestResult.new(
		"the bench publishes every observable the audio synthesiser reads",
		audio_fields_filled,
		"rpm %.0f, blade-pass %.0f Hz, electrical %.0f Hz, tip %.0f m/s, thrust %.2f N" % [
			pt.observables.rpm[0], pt.observables.blade_pass_hz[0], pt.observables.electrical_hz[0],
			pt.observables.tip_speed_mps[0], pt.observables.thrust_n[0]]
	))

	# --- The bench does not fly ---
	# A bench that quietly integrated a rigid body would publish a position. This is the
	# test that fails if someone later "helpfully" gives Powertrain a RigidBodyState.
	var stationary: bool = (
		pt.observables.position_m == Vector3.ZERO
		and pt.observables.velocity_mps == Vector3.ZERO
		and pt.observables.airspeed_mps == 0.0
	)
	results.append(TestResult.new(
		"a bench never moves: position, velocity and airspeed stay at zero",
		stationary,
		"position %s, airspeed %.3f m/s" % [pt.observables.position_m, pt.observables.airspeed_mps]
	))

	# --- Priming places the bench at steady state immediately ---
	# The bench needs this for the same reason flight does: a UI that shows a throttle
	# already at 50% must not spend 30 ms of spin-up publishing numbers nobody commanded.
	var primed := _bench(build)
	primed.prime(TEST_THROTTLE)
	results.append(TestResult.new(
		"priming reaches steady state without stepping",
		absf(primed.motor_rpm[0] - expected_rpm) / expected_rpm < 0.01,
		"primed %.0f RPM vs analytic %.0f RPM" % [primed.motor_rpm[0], expected_rpm]
	))

	# --- Sag is what separates a real bench from an arithmetic one ---
	# This is the test the deliberately-wrong stub was written to fail. A powertrain that
	# held the pack at nominal converges perfectly happily; it just converges high, because
	# nothing ever takes voltage away from the RPM ceiling. Naming the size of that gap
	# means the check cannot be satisfied by a model that merely runs.
	var no_sag_rpm := TEST_THROTTLE * build.motor_model().max_rpm(bench_rest_v)
	results.append(TestResult.new(
		"the bench lands below the no-sag RPM ceiling, by the amount the pack's resistance costs",
		actual_rpm < no_sag_rpm - 100.0,
		"bench %.0f RPM vs %.0f RPM if the pack never sagged (%.0f RPM of sag)" % [
			actual_rpm, no_sag_rpm, no_sag_rpm - actual_rpm]
	))

	return results

## A Powertrain assembled straight from the reference build's parts. Deliberately NOT via
## DroneCore — constructing this without mass properties or a rigid body is the point.
static func _bench(build: Build) -> Powertrain:
	var geometry := build.prop_geometry()
	return Powertrain.create(
		build.motor_model(), build.k_t, build.k_q, build.battery_model(),
		build.effective_max_amps, build.rated_rpm(),
		build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5
	)

static func _even(throttle: float) -> PackedFloat64Array:
	# MotorLayout.MOTOR_NAMES order — the powertrain's step takes a typed array, not a dict.
	return PackedFloat64Array([throttle, throttle, throttle, throttle])
