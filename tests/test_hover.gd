class_name TestHover
extends RefCounted
## Tests 5-6 from week1.md Day 2: thrust-to-weight and hover throttle. Test 6 is the
## smoke test / oracle (physics.md §8) — 29% under the legacy motor law, 33.0% on the DC law
## (2026-11-03) — a very specific, very checkable number.

static func run() -> Array:
	var results: Array = []

	var mp := MassProperties.compute(ReferenceBuild.mass_parts())
	var weight_n := mp.total_mass_kg * 9.81

	# BY HAND ON THE DC MOTOR LAW (2026-11-03). Flat out, the motor does NOT turn Kv x V: the winding
	# current through Rm costs volts, so V = rpm/Kv + I(rpm) x Rm with I = Io(rpm) + k_q w^2 / Kt.
	# k_t is fitted at that loaded rpm on the test prop (Build.fit_rated_point), so thrust at Kv x V
	# (the pre-DC hand check, 19.4 : 1 with today's k_t) is a motor nobody flies. Solved here by
	# bisection from the four DC constants alone, independently of Fitting / MotorModel's solver.
	var build := ReferenceBuild.build()
	var k_t := ReferenceBuild.propeller_k_t()
	var k_q := ReferenceBuild.propeller_k_q()
	var dc := Build.dc_motor_params(build.motor)
	var kv: float = dc[0]
	var rm: float = dc[1]
	var io: float = dc[2]
	var io_v: float = dc[3]
	var kt_motor := 60.0 / (TAU * kv)
	var v := ReferenceBuild.BATTERY_NOMINAL_V
	var winding_a := func(rpm: float) -> float:
		var omega := rpm * TAU / 60.0
		return io * rpm / (kv * io_v) + k_q * omega * omega / kt_motor
	var lo := 0.0
	var hi := kv * v
	for _i in 80:
		var mid := (lo + hi) * 0.5
		if mid / kv + float(winding_a.call(mid)) * rm < v:
			lo = mid
		else:
			hi = mid
	var max_rpm := lo
	var max_total_thrust_n := PropellerModel.thrust_n(k_t, max_rpm) * 4.0

	var twr := max_total_thrust_n / weight_n
	results.append(TestResult.new(
		"thrust-to-weight ~= 8.13 : 1 (the oracle), at the loaded flat-out rpm",
		absf(twr - 8.131) / 8.131 < 0.03 and max_rpm < 0.95 * kv * v,
		"got %.2f : 1 at %.0f rpm (%.2f of Kv x V)" % [twr, max_rpm, max_rpm / (kv * v)]
	))

	# Hover: the rpm that makes a quarter of the weight, and the ESC duty that holds it there:
	# duty x V = rpm/Kv + I x Rm. No pack sag here, which is why the oracle (with sag) sits a hair
	# above it. Under the pre-DC law this was hover_rpm / (Kv x V), 29%.
	var hover_thrust_per_motor_n := weight_n / 4.0
	var hover_omega := sqrt(hover_thrust_per_motor_n / k_t)
	var hover_rpm := hover_omega * 60.0 / TAU
	var hover_throttle := (hover_rpm / kv + float(winding_a.call(hover_rpm)) * rm) / v

	results.append(TestResult.new(
		"hover throttle ~= 33% (the oracle since the prop chapter)",
		absf(hover_throttle - 0.3303) < 0.02 and absf(hover_throttle - build.hover_throttle()) < 0.01,
		"got %.1f%% by hand, oracle %.1f%%" % [hover_throttle * 100.0, build.hover_throttle() * 100.0]
	))

	return results
