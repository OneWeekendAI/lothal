class_name TestEscDynamics
extends RefCounted
## R1.4: the motor is an electrical + mechanical model (back-EMF, winding resistance, the current
## that makes torque, prop load torque) behind an ESC with a current limit and a braking setting,
## not a first-order lag. Each test states the effect and carries its counterfactual: the same
## measurement with the effect removed must come out on the other side, or the test cannot fail.
##
## Estimates (no data in the repo): the ESC current limit (2 x rated amps) and active braking ON.
## Both are fields the tests overwrite, so they are exercised rather than trusted.

const REF_MOTOR := "motor_2207_1960kv"
const DT := 0.001


static func run() -> Array:
	var results: Array = []
	results.append(_test_spin_up_slower_at_low_voltage())
	results.append(_test_braking_faster_than_coast_down())
	results.append(_test_current_limit_clips())
	results.append(_test_pack_current_reaches_sag())
	results.append(_test_steady_state_matches_dc_solve())
	results.append(_test_whoop_cinelifter_ratio_vs_p7())
	results.append(_test_dynamics_off_is_the_p7_lag())
	return results


## A motor model for a catalog motor on its test prop, dynamics on (limit_a < 0 = the build's 1.5x).
static func _model(motor_id: String, limit_a: float = -1.0, braking: bool = true) -> Dictionary:
	var catalog := PartsCatalog.load_default()
	var motor: Dictionary = catalog.get_part(motor_id)
	var test_prop: Dictionary = catalog.get_part(str(motor["thrust_test"]["prop_id"]))
	var fit := Build.fit_rated_point(motor, test_prop)
	var dc := Build.dc_motor_params(motor)
	var up := TestMotorSpinUp._spin_up_for_motor(motor, catalog, FrameMaterials.load_default())
	var mm := MotorModel.create(float(motor["specs"]["kv"]), 1.0)
	mm.set_dc(dc[1], dc[2], dc[3], float(fit["k_q"]))
	var limit := Build.ESC_LIMIT_PER_RATED_AMPS * float(motor["specs"]["max_amps"]) if limit_a < 0.0 else limit_a
	mm.set_dynamics(float(up["j_total_kg_m2"]), limit, braking)
	return {"mm": mm, "tau": float(up["tau_s"])}


## Seconds for rpm to first reach `rpm_goal` from `rpm0` under a constant throttle, or INF.
static func _time_to(mm: MotorModel, rpm0: float, throttle: float, volts: float, rpm_goal: float,
		falling: bool = false, t_max: float = 1.0) -> float:
	var rpm := rpm0
	var t := 0.0
	while t < t_max:
		rpm = mm.step_dynamic(rpm, throttle, volts, DT)[0]
		t += DT
		if (falling and rpm <= rpm_goal) or (not falling and rpm >= rpm_goal):
			return t
	return INF


static func _test_spin_up_slower_at_low_voltage() -> TestResult:
	# No current limit: with one the ramp is current-limited, and current limit is independent of the
	# pack voltage until the back-EMF catches up. This test isolates the voltage-limited regime.
	var mm: MotorModel = _model(REF_MOTOR, 0.0)["mm"]
	# Goal: 90% of the rpm the LOW pack reaches at full throttle. Same rpm, same throttle, both packs.
	var low_v := 10.0
	var high_v := 16.8
	var goal := 0.9 * mm.target_rpm(1.0, low_v)
	var t_low := _time_to(mm, 0.0, 1.0, low_v, goal)
	var t_high := _time_to(mm, 0.0, 1.0, high_v, goal)
	var passed := t_low < INF and t_high < INF and t_low > 1.15 * t_high
	return TestResult.new(
		"spin-up to a fixed rpm is slower on a low pack voltage (>15%)",
		passed, "10 V %.1f ms, 16.8 V %.1f ms" % [t_low * 1000.0, t_high * 1000.0])


static func _test_braking_faster_than_coast_down() -> TestResult:
	var braked: MotorModel = _model(REF_MOTOR, -1.0, true)["mm"]
	var coast: MotorModel = _model(REF_MOTOR, -1.0, false)["mm"]
	var v := 16.0
	var start := braked.target_rpm(0.8, v)
	var goal := 0.3 * start
	var t_brake := _time_to(braked, start, 0.0, v, goal, true)
	var t_coast := _time_to(coast, start, 0.0, v, goal, true)
	var t_up := _time_to(braked, 0.0, 0.8, v, 0.7 * start)
	var passed := t_brake < INF and t_coast < INF and t_brake < 0.7 * t_coast and t_brake > 0.0
	return TestResult.new(
		"throttle chop: active braking reaches 30% rpm in under 70% of the coast-down time",
		passed, "brake %.1f ms, coast %.1f ms (spin-up to 70%%: %.1f ms)" % [
			t_brake * 1000.0, t_coast * 1000.0, t_up * 1000.0])


static func _test_current_limit_clips() -> TestResult:
	var v := 16.0
	var limit := 45.0  # above the ~30 A steady draw at full throttle, so it binds the transient only
	var lim: MotorModel = _model(REF_MOTOR, limit)["mm"]
	var free: MotorModel = _model(REF_MOTOR, 0.0)["mm"]  # 0 = no limit
	var goal := 0.8 * lim.target_rpm(1.0, v)
	var rpm := 0.0
	var peak := 0.0
	var rpm_free := 0.0
	var peak_free := 0.0
	for _i in 15:
		var a := lim.step_dynamic(rpm, 1.0, v, DT)
		rpm = a[0]
		peak = maxf(peak, a[1])
		var b := free.step_dynamic(rpm_free, 1.0, v, DT)
		rpm_free = b[0]
		peak_free = maxf(peak_free, b[1])
	var t_lim := _time_to(lim, 0.0, 1.0, v, goal)
	var t_free := _time_to(free, 0.0, 1.0, v, goal)
	var passed := peak <= limit + 1e-9 and peak > 0.9 * limit and peak_free > 3.0 * limit \
		and t_lim > 1.3 * t_free and rpm < rpm_free
	return TestResult.new(
		"the ESC current limit clips the phase current and so slows the spin-up",
		passed, "peak %.1f A (limit %.0f A, unlimited %.0f A); to 80%%: %.1f ms vs %.1f ms" % [
			peak, limit, peak_free, t_lim * 1000.0, t_free * 1000.0])


## The pack current of the spin-up reaches the battery: with a stiff pack the voltage barely moves,
## with a resistive pack the same punch sags it and the motors spin up slower.
static func _test_pack_current_reaches_sag() -> TestResult:
	var out: Array = []
	for r_pack in [0.002, 0.06]:
		var build := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
			ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)
		build.esc_dynamics = true
		var g := build.prop_geometry()
		var pack := build.battery_model()
		pack.internal_r_ohm = r_pack
		var pt := Powertrain.create(build.motor_model(), build.k_t, build.k_q, pack,
			build.effective_max_amps, build.rated_rpm(), build.pole_pairs(), g.blades,
			g.diameter_m * 0.5, g.pitch_m, build.air.kgm3(), build.blade_chord(), build.blade_twist())
		var cmds := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
		var peak_a := 0.0
		var min_v := 1e9
		for _i in 30:
			pt.step(cmds, DT)
			peak_a = maxf(peak_a, pt.last_current_total_a)
			min_v = minf(min_v, pt.last_voltage_v)
		out.append({"peak_a": peak_a, "min_v": min_v, "rpm": pt.motor_rpm[0],
			"v_rest": pack.resting_voltage_v(), "r": r_pack})
	var stiff: Dictionary = out[0]
	var soft: Dictionary = out[1]
	var dip_soft: float = soft["v_rest"] - soft["min_v"]
	var dip_stiff: float = stiff["v_rest"] - stiff["min_v"]
	# The dip is I*R at the current the motors drew (the current REACHED the sag path), the punch
	# draws a real transient current, and the resistive pack spins up slower.
	var passed: bool = stiff["peak_a"] > 10.0 and dip_soft > 1.0 \
		and absf(dip_soft - 0.06 * soft["peak_a"]) < 0.5 * dip_soft \
		and soft["rpm"] < 0.995 * stiff["rpm"] and dip_stiff < 0.5 * dip_soft
	return TestResult.new(
		"the spin-up current draw reaches battery sag, and sag slows the spin-up",
		passed, "stiff pack: peak %.0f A, dip %.2f V, rpm %.0f; 60 mohm pack: peak %.0f A, dip %.2f V, rpm %.0f" % [
			stiff["peak_a"], dip_stiff, stiff["rpm"], soft["peak_a"], dip_soft, soft["rpm"]])


## Held at a throttle long enough, the dynamics settle on the same operating point `target_rpm`
## (the DC solve the k_t fit and every steady test use) reports: nothing steady moved.
static func _test_steady_state_matches_dc_solve() -> TestResult:
	var mm: MotorModel = _model(REF_MOTOR)["mm"]
	var worst := 0.0
	for throttle in [0.3, 0.6, 1.0]:
		var rpm := 0.0
		for _i in 600:
			rpm = mm.step_dynamic(rpm, throttle, 15.0, DT)[0]
		var want := mm.target_rpm(throttle, 15.0)
		worst = maxf(worst, absf(rpm - want) / want)
	return TestResult.new(
		"held throttle settles on the DC operating point target_rpm (within 0.5%)",
		worst < 0.005, "worst error %.4f%%" % (worst * 100.0))


## P7 had a whoop/cinelifter tau ratio of about 1.3x (0802 slower: damping K_e^2/R outgrows J). The
## new model's 63% rise time on the same small step must keep the ordering and land within 2x of
## P7's ratio. Not required to equal tau: tau is linearised, this one is shaped by voltage and the
## current limit.
static func _test_whoop_cinelifter_ratio_vs_p7() -> TestResult:
	var small := _rise_63("motor_0802_19000kv")
	var large := _rise_63("motor_2808_1300kv")
	var p7_small: float = _model("motor_0802_19000kv")["tau"]
	var p7_large: float = _model("motor_2808_1300kv")["tau"]
	var ratio_new := small / large
	var ratio_p7 := p7_small / p7_large
	var passed := small > 0.0 and large > 0.0 and ratio_new > 1.0 and ratio_new / ratio_p7 > 0.5 \
		and ratio_new / ratio_p7 < 2.0
	return TestResult.new(
		"whoop vs cinelifter: 0802 slower than 2808, ratio within 2x of P7's",
		passed, "63%% rise 0802 %.1f ms, 2808 %.1f ms, ratio %.2fx (P7 tau %.1f / %.1f ms = %.2fx)" % [
			small * 1000.0, large * 1000.0, ratio_new, p7_small * 1000.0, p7_large * 1000.0, ratio_p7])


## Time to 63.2% of the step from throttle 0.35 to 0.5 (the small step P7's tau is linearised for).
static func _rise_63(motor_id: String) -> float:
	var mm: MotorModel = _model(motor_id)["mm"]
	var v := 3.7 * 4.0
	var lo := mm.target_rpm(0.35, v)
	var hi := mm.target_rpm(0.5, v)
	return _time_to(mm, lo, 0.5, v, lo + 0.632 * (hi - lo), false, 2.0)


## A motor with no dynamics set is untouched: step() is still P7's lag, and dynamics_on is false.
static func _test_dynamics_off_is_the_p7_lag() -> TestResult:
	var mm := MotorModel.create_with_tau(2000.0, 1.0, 0.05)
	var rpm := mm.step(0.0, 1.0, 10.0, 0.05)
	var passed := not mm.dynamics_on() and absf(rpm / 20000.0 - (1.0 - exp(-1.0))) < 1e-12
	return TestResult.new("dynamics off: MotorModel.step is still the P7 first-order lag",
		passed, "fraction %.12f" % (rpm / 20000.0))
