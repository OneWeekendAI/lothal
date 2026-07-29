class_name TestHover
extends RefCounted
## Tests 5-6 from week1.md Day 2: thrust-to-weight and hover throttle. Test 6 is the
## smoke test / oracle (physics.md §8) — 29% is a very specific, very checkable number.

static func run() -> Array:
	var results: Array = []

	var mp := MassProperties.compute(ReferenceBuild.mass_parts())
	var weight_n := mp.total_mass_kg * 9.81

	var k_t := ReferenceBuild.propeller_k_t()
	var max_rpm := ReferenceBuild.MOTOR_KV * ReferenceBuild.BATTERY_NOMINAL_V
	var max_thrust_per_motor_n := PropellerModel.thrust_n(k_t, max_rpm)
	var max_total_thrust_n := max_thrust_per_motor_n * 4.0

	var twr := max_total_thrust_n / weight_n
	results.append(TestResult.new(
		"thrust-to-weight ~= 11.7 : 1",
		absf(twr - 11.7) / 11.7 < 0.03,
		"got %.2f : 1" % twr
	))

	var hover_thrust_per_motor_n := weight_n / 4.0
	var hover_omega := sqrt(hover_thrust_per_motor_n / k_t)
	var hover_rpm := hover_omega * 60.0 / TAU
	var hover_throttle := hover_rpm / max_rpm

	results.append(TestResult.new(
		"hover throttle ~= 29% (the oracle)",
		absf(hover_throttle - 0.29) < 0.02,
		"got %.1f%%" % (hover_throttle * 100.0)
	))

	return results
