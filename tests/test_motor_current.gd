class_name TestMotorCurrent
extends RefCounted
## One motor law (owner decision 2026-11-03): every motor's current comes from the DC model (Kv, Rm,
## Io, the prop's torque). The legacy rated-amps law and the `current_model == "dc"` gate are gone.
##
## The first group shows no motor takes the legacy path (every shelf preset, and a custom motor that
## carries no Rm/Io); the second shows Rm and Io matter to flight figures; the third shows the flying
## powertrain and the stats panel read one model; the fourth that the ceilings and the lumped coaxial
## thruster are on the same model.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _build(rm_scale: float = 1.0, io_scale: float = 1.0,
		motor_id: String = ReferenceBuild.MOTOR_ID) -> Build:
	var catalog := PartsCatalog.load_default()
	var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)
	var m: Dictionary = b.motor.duplicate(true)
	m["specs"]["rm_ohm"] = float(m["specs"]["rm_ohm"]) * rm_scale
	m["specs"]["io_a"] = float(m["specs"]["io_a"]) * io_scale
	b.motor = m
	b._recompute()
	return b


static func _preset_ids() -> Array:
	var ids: Array = []
	for raw in JsonStore.read_document("res://data/parts/motors.json").get("parts", []):
		ids.append(String(raw["part_id"]))
	return ids


static func _on_own_prop(motor_id: String) -> Build:
	var catalog := PartsCatalog.load_default()
	var p := catalog.get_part(motor_id)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id,
		String(p["thrust_test"]["prop_id"]), ReferenceBuild.BATTERY_ID)


static func run() -> Array:
	var results: Array = []
	var dc := _build()

	# No motor takes the legacy path. Every preset, and a motor that carries no Rm/Io at all.
	var ids := _preset_ids()
	results.append(_t("the shelf still has its 16 presets", ids.size() == 16, str(ids.size())))
	for id in ids:
		var b := _on_own_prop(id)
		var a := b._dc_args()
		var rpm := 0.6 * b.rated_rpm()
		var legacy_i := Fitting.current_at_rpm(rpm, b.effective_max_amps, b.rated_rpm())
		var ok := b.uses_dc_motor() and not a.is_empty() \
			and b.current_at_rpm(rpm) == Fitting.dc_pack_current_at_rpm(rpm,
				b.resolve_open_circuit_v(Build.AT_NOMINAL), a[0], a[1], a[2], a[3], a[4]) \
			and b.winding_current_at_rpm(rpm) == Fitting.dc_current_at_rpm(rpm, a[0], a[2], a[3], a[4]) \
			and absf(b.current_at_rpm(rpm) - legacy_i) > 0.01
		results.append(_t("%s: current comes from the DC model, not the legacy law" % id, ok,
			"%f vs legacy %f" % [b.current_at_rpm(rpm), legacy_i]))
		var legacy_rpm := Fitting.rpm_at_throttle(0.5, b.max_throttle_fraction(), float(b.motor["specs"]["kv"]),
			b.resolve_open_circuit_v(Build.AT_NOMINAL), float(b.battery["specs"]["internal_r_ohm"]),
			b.effective_max_amps, b.rated_rpm())
		results.append(_t("%s: rpm at a throttle comes from the DC solve, not the legacy fixed point" % id,
			absf(b.rpm_at_throttle(0.5) - legacy_rpm) > 1.0 and b.rpm_at_throttle(0.5) > 0.0,
			"%.0f vs legacy %.0f" % [b.rpm_at_throttle(0.5), legacy_rpm]))
	var bare := _build()
	var m: Dictionary = bare.motor.duplicate(true)
	for k in ["rm_ohm", "io_a", "io_voltage_v", "rm_io_basis"]:
		m["specs"].erase(k)
	bare.motor = m
	bare._recompute()
	var d := MotorConfigs.load_default().derive_stator(float(m["specs"]["stator_diameter_mm"]),
		float(m["specs"]["stator_height_mm"]), float(m["specs"]["kv"]), float(m["thrust_test"]["voltage_v"]))
	var ba := bare._dc_args()
	results.append(_t("a motor with no Rm/Io on its record flies on the DC model with the est. values for its stator",
		bare.uses_dc_motor() and absf(float(ba[1]) - float(d["rm_ohm"])) < 1e-9
		and absf(float(ba[2]) - float(d["io_a"])) < 1e-9
		and absf(bare.flight_time_min() - dc.flight_time_min()) < 0.05 * dc.flight_time_min(),
		"%s vs %s; %.3f vs %.3f min" % [ba, d, bare.flight_time_min(), dc.flight_time_min()]))

	# Rm and Io matter. On the SAME prop: k_t is fitted at the loaded rated point, so a motor record
	# with more Rm (same datasheet thrust) would otherwise imply a better prop; pinning k_t and k_q
	# to the base build isolates the motor.
	var hi_rm := _build(3.0, 1.0)
	var hi_io := _build(1.0, 3.0)
	for pinned: Build in [hi_rm, hi_io]:
		pinned.k_t = dc.k_t
		pinned.k_q = dc.k_q
		pinned._throttle_limits.clear()
		pinned._bench_limits.clear()
	var rpm_base := dc.rpm_at_throttle(0.6)
	var rpm_hi_rm := hi_rm.rpm_at_throttle(0.6)
	results.append(_t("more Rm: the same throttle spins slower",
		rpm_hi_rm < rpm_base - 50.0, "%.0f vs %.0f" % [rpm_hi_rm, rpm_base]))
	results.append(_t("more Rm: the hover throttle rises",
		hi_rm.hover_throttle() > dc.hover_throttle() + 0.001,
		"%.4f vs %.4f" % [hi_rm.hover_throttle(), dc.hover_throttle()]))
	results.append(_t("more Io: the average flight current rises and the flight time falls",
		hi_io.average_flight_current_a() > dc.average_flight_current_a() + 0.05
		and hi_io.flight_time_min() < dc.flight_time_min() - 0.01,
		"%.3f A %.3f min vs %.3f A %.3f min" % [hi_io.average_flight_current_a(), hi_io.flight_time_min(),
			dc.average_flight_current_a(), dc.flight_time_min()]))
	results.append(_t("the fresh-pack draw at full throttle follows the DC model",
		absf(hi_rm.fresh_draw_at_a(1.0) - dc.fresh_draw_at_a(1.0)) > 1.0,
		"%.1f vs %.1f" % [hi_rm.fresh_draw_at_a(1.0), dc.fresh_draw_at_a(1.0)]))

	# One model between the panel and the flying powertrain.
	for pair in [["dc", dc], ["dc high Rm", hi_rm]]:
		var b: Build = pair[1]
		var g := b.prop_geometry()
		var pt := Powertrain.create(b.motor_model(), b.k_t, b.k_q, b.battery_model(),
			b.effective_max_amps, b.rated_rpm(), b.pole_pairs(), g.blades, g.diameter_m * 0.5,
			g.pitch_m, b.air.kgm3(), b.blade_chord())
		results.append(_t("%s: the powertrain's per-motor current equals the build's" % pair[0],
			absf(pt.current_at_rpm(18000.0) - b.current_at_rpm(18000.0)) < 1e-9,
			"%f vs %f" % [pt.current_at_rpm(18000.0), b.current_at_rpm(18000.0)]))
		# The flying tick and the stats panel solve the same operating point: priming at 0.5
		# must land where Fitting's DC solve does, on the powertrain's own pack.
		pt.prime(0.5)
		var args := b._dc_args()
		var expect := Fitting.dc_rpm_at_throttle(0.5, 1.0, args[0], args[1], args[2], args[3], args[4],
			pt.battery.resting_voltage_v(), pt.battery.internal_r_ohm, 4.0)
		results.append(_t("%s: priming the powertrain at 0.5 reaches the DC solve's rpm" % pair[0],
			absf(pt.motor_rpm[0] - expect) < 0.01 * expect, "%.0f vs %.0f" % [pt.motor_rpm[0], expect]))
		var amps := Fitting.dc_pack_draw_a(0.5, args[0], args[1], args[2], args[3], args[4],
			pt.battery.resting_voltage_v(), pt.battery.internal_r_ohm, 4.0)
		results.append(_t("%s: the pack current the powertrain draws is the DC solve's" % pair[0],
			absf(pt.last_current_total_a - amps) < 0.02 * amps, "%.2f vs %.2f" % [pt.last_current_total_a, amps]))

	# The ceilings are on the DC model too, and no longer read the legacy k_q-ratio rating.
	var five := _on_own_prop("motor_2207_1960kv")
	var fa := five._dc_args()
	var test_v := float(five.motor["thrust_test"]["voltage_v"])
	var full := Fitting.dc_pack_draw_a(1.0, fa[0], fa[1], fa[2], fa[3], fa[4], test_v, 0.0, 1.0)
	var rated := five.motor_rated_draw_a()
	results.append(_t("on its own rated prop at its test voltage the motors' bench ceiling is 100% (a rating is flat out on that prop)",
		five.motor_bench_limit() == 1.0 and absf(full - rated) < 1e-9,
		"%.2f A draw vs %.2f A rating, limit %.4f" % [full, rated, five.motor_bench_limit()]))
	results.append(_t("one motor's demand at the bench limit is its rated draw",
		absf(five.motor_demand_per_channel_a() - rated) < 0.01 * rated, "%.2f vs %.2f" % [five.motor_demand_per_channel_a(), rated]))
	var heavy := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID, "motor_2207_1960kv",
		"prop_7x35x2", ReferenceBuild.BATTERY_ID)
	results.append(_t("a prop that loads the motor harder than its rated prop is held below 100% on the bench",
		heavy.k_q > five.k_q and heavy.motor_bench_limit() < 1.0, "k_q %s vs %s, limit %.3f" % [heavy.k_q, five.k_q, heavy.motor_bench_limit()]))
	var limit_before := five.motor_throttle_limit()
	five.effective_max_amps *= 3.0
	five._throttle_limits.clear()
	results.append(_t("the flight motor limit does not read the legacy effective_max_amps",
		five.motor_throttle_limit() == limit_before, "%f vs %f" % [five.motor_throttle_limit(), limit_before]))
	results.append(_t("the flight motor limit is where the sagged DC draw reaches the rating",
		absf(five.fresh_draw_at_a(limit_before) - 4.0 * rated) < 0.01 * 4.0 * rated or limit_before >= 1.0,
		"%.2f A vs %.2f A" % [five.fresh_draw_at_a(limit_before), 4.0 * rated]))

	# The PACK carries the ESC duty times the winding current, not the winding current (2026-11-03:
	# summing winding currents tripled the 5" hover draw). Hand check on the 5" seed (MOTOR_REBASELINE.md):
	# hover 1.24 N per motor -> ~6590 rpm on the loaded-point k_t (2.6e-6), winding 5.11 A torque +
	# 0.38 A Io = 5.49 A, motor volts 6590/1960 + 5.49*0.0575 = 3.68 of ~14.7 -> duty 0.25, ~5.5 A total.
	var seed5 := DesignSession.default_for_class("five_inch").build(PartsCatalog.load_default())
	var ht := seed5.hover_throttle()
	var hrpm := seed5.rpm_at_throttle(ht)
	var winding_total := 4.0 * seed5.winding_current_at_rpm(hrpm)
	var pack_total := seed5.hover_current_a(ht)
	results.append(_t("5\" seed hover: the pack draws duty x winding current, about 5.5 A, not the winding's 22 A",
		absf(pack_total - ht * winding_total) < 0.01 * pack_total and pack_total > 5.0 and pack_total < 6.0
		and winding_total > 2.5 * pack_total,
		"pack %.2f A, winding %.2f A, duty %.3f" % [pack_total, winding_total, ht]))
	var sv := seed5.resolve_open_circuit_v(Build.AT_NOMINAL)
	var a5 := seed5._dc_args()
	var v_motor := hrpm / float(a5[0]) + seed5.winding_current_at_rpm(hrpm) * float(a5[1])
	results.append(_t("one motor's pack current at an rpm is its winding current times (rpm/Kv + I*Rm) / supply",
		absf(seed5.current_at_rpm(hrpm) - seed5.winding_current_at_rpm(hrpm) * v_motor / sv) < 1e-9,
		"%.4f vs %.4f" % [seed5.current_at_rpm(hrpm), seed5.winding_current_at_rpm(hrpm) * v_motor / sv]))
	var xc := DesignSession.default_for_class("x_class").build(PartsCatalog.load_default())
	results.append(_t("the X-Class seed hovers on its seed pack",
		xc.can_hover() and xc.flight_time_min() > 3.0, "flight %.2f min" % xc.flight_time_min()))

	# The lumped coaxial thruster draws every motor's current.
	var catalog := PartsCatalog.load_default()
	var x8 := DesignSession.default_for_class("cinelifter").build(catalog)
	var single := x8.motor_model()
	var lumped := x8.lumped_motor_model()
	results.append(_t("a coaxial pair's lumped motor model is on the DC model and draws two motors' current",
		lumped.uses_dc() and x8.motors_per_arm() == 2
		and absf(lumped.dc_current_at_rpm(15000.0) - 2.0 * single.dc_current_at_rpm(15000.0)) < 1e-9
		and absf(lumped.target_rpm(0.5, 22.0) - single.target_rpm(0.5, 22.0)) < 1e-9,
		"%f vs 2x %f" % [lumped.dc_current_at_rpm(15000.0), single.dc_current_at_rpm(15000.0)]))
	var quad := _build()
	results.append(_t("a quad's lumped motor model is exactly its motor model",
		quad.lumped_motor_model().dc_current_at_rpm(15000.0) == quad.motor_model().dc_current_at_rpm(15000.0), ""))
	return results
