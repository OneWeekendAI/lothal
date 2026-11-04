class_name TestMotorBench
extends RefCounted
## Motor Designer M6: the bench behind the designer (MotorBench) and its place on the screen.
##
## Each logic check below was shown to fail under a mutation (see MOTOR_HANDOVER.md for the list):
## - thrust strictly rising: flatten the rpm above 70 % throttle in Build.uncapped_point.
## - hotter magnet clears the heat warning: delete the temperature test, or hard-code the limit.
## - higher-R pack lowers punch-out rpm: drop `pack_record` in make_build.
## - thermal: bench back on the one-lump MotorModel.temp_step_c / cooling_w_per_k (punch reads 250 C), or air conductance without the rpm term.
## - too-big prop warning: raise or drop PROP_LOADED_MIN.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _top(a: PackedFloat64Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, v)
	return m


static func _has(lines: Array, word: String) -> bool:
	for l in lines:
		if String(l).contains(word):
			return true
	return false


static func _design(cfg: MotorConfigs, size: String, kv: float, magnet := "N52") -> MotorDesign:
	var d := MotorDesign.default_design(cfg)
	d.set_size(cfg, size)
	d.set_kv(cfg, kv)
	d.set_magnet(cfg, magnet)
	return d


static func run() -> Array:
	var out: Array = []
	var cfg := MotorConfigs.load_default()
	out.append_array(_logic(cfg))
	out.append_array(_screen(cfg))
	return out


static func _logic(cfg: MotorConfigs) -> Array:
	var out: Array = []

	# Throttle sweep: more throttle, more thrust, on a few motors.
	var bad := ""
	for spec in [["2207", 1960.0], ["2306", 1900.0], ["2507", 1500.0], ["1404", 3800.0]]:
		var d := _design(cfg, spec[0], spec[1])
		var r := MotorBench.run("sweep", d, cfg)
		var th: PackedFloat64Array = r.get("thrust_g", PackedFloat64Array())
		if th.size() != MotorBench.SWEEP_STEPS + 1 or th[0] != 0.0:
			bad += " %s shape" % spec[0]
			continue
		for i in range(1, th.size()):
			if not th[i] > th[i - 1]:
				bad += " %s@%d(%.0f<=%.0f)" % [spec[0], i, th[i], th[i - 1]]
				break
	out.append(_t("sweep: thrust rises strictly with throttle from 0 g, for four motors", bad == "", bad))

	var sweep := MotorBench.run("sweep", _design(cfg, "2207", 1960.0), cfg)
	var amps: PackedFloat64Array = sweep.current_a
	out.append(_t("sweep: current also rises with throttle and the result line quotes max thrust, A and g/W",
		amps[amps.size() - 1] > amps[1] and amps[0] == 0.0 and String(sweep.result).begins_with("Per motor")
		and String(sweep.result).contains(" g/W at hover") and float(sweep.max_thrust_g) > 1000.0, String(sweep.result)))
	# PER MOTOR, with the total small beside it. The reference frame is a quad: the result line quotes
	# a quarter of the aircraft's thrust and current, and the total line the whole of it.
	var n_motors := int(sweep.motors)
	var one_g := float(sweep.max_thrust_g) / float(n_motors)
	out.append(_t("sweep: the result line is per motor (a quarter of the quad's total) and a small line gives x4 = the total",
		n_motors == 4 and is_equal_approx(float(sweep.motor_thrust_g), one_g)
		and is_equal_approx(float(sweep.motor_current_a), float(sweep.max_current_a) / 4.0)
		and String(sweep.result).contains(MotorBench._thousands(one_g) + " g")
		and not String(sweep.result).contains(MotorBench._thousands(float(sweep.max_thrust_g)) + " g")
		and String(sweep.total_text).begins_with("x4 = ")
		and String(sweep.total_text).contains(MotorBench._thousands(float(sweep.max_thrust_g)) + " g"),
		"%s | %s" % [sweep.result, sweep.total_text]))

	# Heat limits, each read against the part it protects. The magnets sit in the BELL: their limit
	# (N52 80 C, N52H 120 C) is read against the bell's temperature. The winding enamel (class H,
	# 180 C) is read against the WINDING. A 2207 1960 KV punch-out takes the winding to ~121 C, over
	# the N52 limit, while the bell is still ~31 C: the magnets are fine, so no magnet warning.
	var n52 := MotorBench.run("punch", _design(cfg, "2207", 1960.0, "N52"), cfg)
	out.append(_t("magnet limit is read on the bell: a winding at ~121 C (over 80 C) with the bell near 31 C does not warn the magnets",
		float(n52.peak_temp_c) > cfg.magnet_max_c("N52") and float(n52.peak_bell_c) < cfg.magnet_max_c("N52") - 30.0
		and not _has(n52.warnings, "Magnets") and float(n52.burn_s) < 0.0,
		"winding %.0f bell %.0f %s" % [n52.peak_temp_c, n52.peak_bell_c, n52.warnings]))
	var wb := MotorBench.make_build(_design(cfg, "2207", 1960.0), cfg)
	var f52 := _design(cfg, "2207", 1960.0, "N52").derive(cfg)
	var f52h := _design(cfg, "2207", 1960.0, "N52H").derive(cfg)
	var warm: Dictionary = n52.duplicate()
	warm["peak_bell_c"] = 100.0
	warm["peak_temp_c"] = 110.0
	out.append(_t("a bell between the N52 limit (80 C) and the N52H limit (120 C) warns the N52 magnets, not the N52H ones, and names the bell",
		_has(MotorBench.warnings(warm, wb, f52), "Magnets overheat: bell 100") and not _has(MotorBench.warnings(warm, wb, f52h), "Magnets")
		and MotorBench.warnings(warm, wb, f52).size() == 1, str(MotorBench.warnings(warm, wb, f52))))
	var cool_bell: Dictionary = warm.duplicate()
	cool_bell["peak_bell_c"] = 60.0
	cool_bell["peak_temp_c"] = 170.0
	out.append(_t("a winding at 170 C with a cool bell warns no magnets (the enamel limit is the burn-out's, 180 C)",
		not _has(MotorBench.warnings(cool_bell, wb, f52), "Magnets"), str(MotorBench.warnings(cool_bell, wb, f52))))
	var n52h := MotorBench.run("punch", _design(cfg, "2306", 1700.0, "N52H"), cfg)
	var peak := float(n52h.peak_temp_c)
	out.append(_t("the soak line compares the BELL with the magnet limit",
		MotorBench.run("soak", _design(cfg, "2207", 1960.0), cfg).result.contains("bell")
		and peak > 0.0, ""))

	# A weaker pack lowers the punch-out rpm and the loaded voltage.
	var d2 := _design(cfg, "2207", 1960.0)
	var cat := PartsCatalog.load_default()
	var pack := cat.get_part(ReferenceBuild.BATTERY_ID).duplicate(true)
	var stiff := MotorBench.run("punch", d2, cfg)
	pack["specs"]["internal_r_ohm"] = float(pack["specs"]["internal_r_ohm"]) * 3.0
	var soft := MotorBench.run("punch", d2, cfg, {}, pack)
	out.append(_t("a higher-resistance pack lowers punch-out rpm and pack voltage",
		float(soft.end_rpm) < float(stiff.end_rpm) - 100.0 and float(soft.low_v) < float(stiff.low_v)
		and float(soft.start_rpm) < float(stiff.start_rpm),
		"rpm %.0f vs %.0f, V %.1f vs %.1f" % [soft.end_rpm, stiff.end_rpm, soft.low_v, stiff.low_v]))

	# Hover soak: temperature climbs and levels; punch-out gets hotter faster than a hover.
	var soak := MotorBench.run("soak", _design(cfg, "2207", 1960.0), cfg)
	var temps: PackedFloat64Array = soak.temp_c
	out.append(_t("soak: winding starts at ambient, rises, ends below the limit with a headroom line; no warnings at hover",
		temps[0] == MotorBench.AMBIENT_C and temps[temps.size() - 1] > temps[0] + 5.0
		and String(soak.result).contains("below the 80") and soak.warnings.is_empty(), String(soak.result)))

	# Heat from physics (thermal refit 2026-11-04, constants sourced in rust/src/motor.rs): a 2207 1960 KV
	# on the reference 4S ends the 15 s punch at ~130 C and the 5 min hover soak at ~64 C. That is HOTTER
	# than the 60-100 / 35-55 C the owner expected; the constants were not tuned to fit it. The band
	# pins the model, so a changed constant must change this deliberately.
	var hot := MotorBench.run("punch", _design(cfg, "2207", 1960.0), cfg)
	# Since the stator-to-air path (air pulled through the bell, prop-wash driven; 2026-11-04) the
	# same 2207 reads ~121 C after the punch and ~49 C after the soak (previously 130 and 64): the
	# path is a cited correlation, not tuned to land anywhere.
	out.append(_t("thermal: 2207 1960 KV from physics: punch-out ~121 C (115-127), hover soak ~49 C (45-54), no burn-out",
		float(hot.end_temp_c) > 115.0 and float(hot.end_temp_c) < 127.0 and float(soak.end_temp_c) > 45.0
		and float(soak.end_temp_c) < 54.0 and float(hot.burn_s) < 0.0 and hot.x[hot.x.size() - 1] == MotorBench.PUNCH_S,
		"punch %.0f C soak %.0f C" % [hot.end_temp_c, soak.end_temp_c]))
	# Burn-out: a 2207 on a 7 inch prop on 6S pulls ~90 A a motor; the winding passes the 180 C enamel
	# limit (IEC 60085 class H) and the run stops there.
	var big := {"propeller": "prop_7x4x3", "battery": "battery_6s_1300"}
	var burnt := MotorBench.run("punch", _design(cfg, "2207", 1960.0), cfg, big)
	var bx: PackedFloat64Array = burnt.x
	var bt: PackedFloat64Array = burnt.temp_c
	var bv: PackedFloat64Array = burnt.v_live
	var burn_s := float(burnt.burn_s)
	var past := false
	for v in bt:
		past = past or v > MotorBench.ENAMEL_LIMIT_C + 1e-9
	out.append(_t("burn-out: 2207 on a 7 inch prop on 6S stops at the enamel limit, never plots past it, and says when",
		MotorBench.ENAMEL_LIMIT_C >= 180.0 and MotorBench.ENAMEL_LIMIT_C <= 200.0
		and burn_s > 0.0 and burn_s < MotorBench.PUNCH_S and bx[bx.size() - 1] == burn_s and bx.size() == bt.size()
		and bx.size() == bv.size() and is_equal_approx(bt[bt.size() - 1], MotorBench.ENAMEL_LIMIT_C) and not past
		and String(burnt.result).begins_with("Burns out after ") and String(burnt.result).contains("%.1f s" % burn_s),
		"%.2f s, last t %.2f, %s" % [burn_s, bx[bx.size() - 1], burnt.result]))
	out.append(_t("burn-out: below the limit the run is not cut short (hover on the same build, 2207 reference punch)",
		float(MotorBench.run("soak", _design(cfg, "2207", 1960.0), cfg, big).burn_s) < 0.0 and not String(hot.result).begins_with("Burns"),
		String(hot.result)))
	# A hover soak burns out too when the loss is high enough: a 1404 hanging a 5 inch prop's weight.
	var soak_burn := MotorBench.run("soak", _design(cfg, "1404", 3800.0), cfg, {"propeller": "prop_8x45x3", "battery": "battery_6s_1300"})
	var sx: PackedFloat64Array = soak_burn.x
	out.append(_t("burn-out: the hover soak stops at the limit too",
		float(soak_burn.burn_s) > 0.0 and sx[sx.size() - 1] == float(soak_burn.burn_s) and sx[sx.size() - 1] < MotorBench.SOAK_S
		and _top(soak_burn.temp_c) <= MotorBench.ENAMEL_LIMIT_C + 1e-9
		and String(soak_burn.result).begins_with("Burns out after "), String(soak_burn.result)))
	# Warnings: short, most severe first.
	var wl: Array = burnt.warnings
	var short := true
	for w in wl:
		short = short and String(w).split(" ", false).size() <= 8
	out.append(_t("warnings: each is 8 words or fewer; a real burn-out run names the winding first, then the current (the bell stays cool, so no magnet line)",
		wl.size() >= 2 and short and String(wl[0]).begins_with("Winding burns out") and String(wl[1]).begins_with("Over current rating: ")
		and not _has(wl, "Magnets"), str(wl)))
	# Severity order with every line present: burn-out, magnets (bell), current, prop.
	var all_lines: Dictionary = burnt.duplicate()
	all_lines["peak_bell_c"] = 100.0
	var wb2 := MotorBench.make_build(_design(cfg, "2207", 1960.0), cfg, big)
	var ordered := MotorBench.warnings(all_lines, wb2, _design(cfg, "2207", 1960.0).derive(cfg))
	var all_short := true
	for w in ordered:
		all_short = all_short and String(w).split(" ", false).size() <= 8
	out.append(_t("warnings: burn-out comes first, then magnets, then current, then prop, each 8 words or fewer",
		ordered.size() == 4 and all_short and String(ordered[0]).begins_with("Winding burns out")
		and String(ordered[1]).begins_with("Magnets overheat") and String(ordered[2]).begins_with("Over current")
		and String(ordered[3]).begins_with("Prop too big"), str(ordered)))
	# The bell is part of the heat path: more conduction into it, a cooler winding (same loss).
	var fig := _design(cfg, "2207", 1960.0).derive(cfg)
	var lumps := MotorBench.Lumps.new(fig)
	var tight := MotorBench.Lumps.new(fig)
	tight.g_cond = lumps.g_cond * 4.0
	for i in 30:
		lumps.step(150.0, 20000.0, 0.5)
		tight.step(150.0, 20000.0, 0.5)
	out.append(_t("thermal: the bell is a second lump (winding hotter than bell; tighter coupling cools the winding)",
		lumps.winding_c > lumps.bell_c + 5.0 and tight.winding_c < lumps.winding_c - 3.0 and lumps.bell_c > MotorBench.AMBIENT_C + 5.0,
		"%.0f/%.0f vs %.0f" % [lumps.winding_c, lumps.bell_c, tight.winding_c]))
	# Faster rpm cools better (forced convection), same loss and lumps.
	# (The bell-to-stator conduction is a narrow 0.1 W/K, so the air side shows in the bell within
	# seconds and in the winding only over minutes: run 10 minutes.)
	var slow := MotorBench.Lumps.new(fig)
	var fast := MotorBench.Lumps.new(fig)
	for i in 1200:
		slow.step(10.0, 2000.0, 0.5)
		fast.step(10.0, 20000.0, 0.5)
	out.append(_t("thermal: the same loss runs cooler at high rpm than at low rpm (bell at once, winding over minutes)",
		fast.bell_c < slow.bell_c - 5.0 and fast.winding_c < slow.winding_c - 5.0,
		"%.0f vs %.0f, bell %.0f vs %.0f" % [fast.winding_c, slow.winding_c, fast.bell_c, slow.bell_c]))

	# The stator-to-air path: the same loss runs cooler with prop wash over the stator than without.
	var dry := MotorBench.Lumps.new(fig)
	var washed := MotorBench.Lumps.new(fig)
	for i in 1200:
		dry.step(10.0, 20000.0, 0.5, 0.0)
		washed.step(10.0, 20000.0, 0.5, 8.0)
	out.append(_t("thermal: air through the bell cools the stator (same loss, 8 m/s of wash vs none)",
		washed.winding_c < dry.winding_c - 3.0, "%.1f vs %.1f" % [washed.winding_c, dry.winding_c]))
	# The wash is the momentum-theory induced velocity of the BEMT-fitted thrust, v = sqrt(T / 2 rho A).
	var rb := MotorBench.make_build(_design(cfg, "2207", 1960.0), cfg)
	var voc := rb.resolve_open_circuit_v(Build.AT_NOMINAL)
	var pt := rb.uncapped_point(1.0, voc)
	var area := PI * pow(float(rb.propeller["specs"]["diameter_inches"]) * 0.0254 * 0.5, 2.0)
	var by_hand := sqrt(float(pt.thrust_n) / 4.0 / (2.0 * rb.air.kgm3() * area))
	out.append(_t("thermal: the prop wash is v_i = sqrt(T / 2 rho A) of one rotor, and is faster at full throttle than at hover",
		absf(MotorBench.wash_mps(rb, 1.0, voc) - by_hand) < 1e-6 and by_hand > 5.0 and by_hand < 30.0
		and MotorBench.wash_mps(rb, rb.hover_throttle(), voc) < by_hand, "%.2f" % by_hand))
	# And the runs really use it: the punch and the soak are cooler than with the path switched off.
	var f2207 := _design(cfg, "2207", 1960.0).derive(cfg)
	var no_wash := MotorBench._punch(rb, f2207, 0.0)
	var hp := rb.uncapped_point(rb.hover_throttle(), voc)
	var soak_dry := MotorBench._heat(f2207, float(hp.rpm), float(hp.winding_current_a), MotorBench.SOAK_S, 0.0)
	out.append(_t("thermal: punch and soak both run cooler than the same runs with no air through the bell",
		float(no_wash.end_temp_c) > float(hot.end_temp_c) + 3.0
		and float(soak_dry.y[soak_dry.y.size() - 1]) > float(soak.end_temp_c) + 3.0,
		"punch %.1f vs %.1f, soak %.1f vs %.1f" % [no_wash.end_temp_c, hot.end_temp_c, soak_dry.y[soak_dry.y.size() - 1], soak.end_temp_c]))

	# "Limited by" agrees with the run. THE RULE (MotorBench.limited_from): burn-out ends the run so
	# it is the limit; else, of the pack / motor current / prop load, any over its limit is hit from
	# the first instant and the furthest over wins; else the magnets' heat limit if it was passed;
	# else the least margin. Synthetic punch-outs pin each branch, then real runs.
	var lb := MotorBench.make_build(_design(cfg, "2207", 1960.0), cfg)
	var real := MotorBench._punch(lb, f2207)
	var calm: Dictionary = real.duplicate()
	calm["peak_temp_c"] = 40.0
	calm["burn_s"] = -1.0
	calm["peak_winding_a"] = 1.0
	calm["peak_pack_a"] = lb.pack_max_amps() * 3.0
	var burnt_fake: Dictionary = calm.duplicate()
	burnt_fake["burn_s"] = 6.0
	burnt_fake["peak_temp_c"] = MotorBench.ENAMEL_LIMIT_C
	var hot_fake: Dictionary = calm.duplicate()
	hot_fake["peak_temp_c"] = float(f2207.magnet_max_c) + 1.0
	hot_fake["peak_bell_c"] = float(f2207.magnet_max_c) + 1.0
	hot_fake["peak_pack_a"] = lb.pack_max_amps() * 0.5
	var both_fake: Dictionary = calm.duplicate()
	both_fake["peak_temp_c"] = float(f2207.magnet_max_c) + 1.0
	both_fake["peak_bell_c"] = float(f2207.magnet_max_c) + 1.0
	var late_fake: Dictionary = both_fake.duplicate()
	late_fake["peak_temp_c"] = 150.0
	late_fake["peak_bell_c"] = 100.0
	late_fake["peak_pack_a"] = lb.pack_max_amps() * 1.2
	var lim_late := MotorBench.limited_from(lb, f2207, late_fake)
	var lim_pack := MotorBench.limited_from(lb, f2207, calm)
	var lim_burn := MotorBench.limited_from(lb, f2207, burnt_fake)
	var lim_hot := MotorBench.limited_from(lb, f2207, hot_fake)
	var lim_both := MotorBench.limited_from(lb, f2207, both_fake)
	out.append(_t("limited by: a pack 3x over its rating is the limit while the motor is fine",
		lim_pack.key == "pack" and float(lim_pack.ratios.pack) > float(lim_pack.ratios.motor), str(lim_pack)))
	out.append(_t("limited by: a winding that burns out is the limit even with the pack 3x over",
		float(lim_burn.ratios.pack) > float(lim_burn.ratios.motor) and lim_burn.key == "motor"
		and String(lim_burn.text).contains("burns out"), str(lim_burn)))
	out.append(_t("limited by: passing the magnet limit is the limit when nothing else is over",
		lim_hot.key == "motor" and float(lim_hot.ratios.pack) < 1.0 and String(lim_hot.text).contains("°C of"), str(lim_hot)))
	out.append(_t("limited by: a pack over its rating from the first instant comes before magnets passed later",
		lim_both.key == "pack", str(lim_both)))
	# The two heat limits name the part: magnets on the bell, enamel on the winding.
	var winding_hot: Dictionary = calm.duplicate()
	winding_hot["peak_pack_a"] = lb.pack_max_amps() * 0.5
	winding_hot["peak_temp_c"] = 170.0
	winding_hot["peak_bell_c"] = 40.0
	var lim_wind := MotorBench.limited_from(lb, f2207, winding_hot)
	var bell_hot: Dictionary = winding_hot.duplicate()
	bell_hot["peak_temp_c"] = 90.0
	bell_hot["peak_bell_c"] = 79.0
	var lim_bell := MotorBench.limited_from(lb, f2207, bell_hot)
	out.append(_t("limited by: a winding at 170 C (bell cool) is winding heat against 180 C, not magnet heat",
		lim_wind.key == "motor" and String(lim_wind.text).contains("winding heat, 170 °C of 180 °C"), str(lim_wind)))
	out.append(_t("limited by: a bell at 79 C (winding 90 C) is magnet heat on the bell against 80 C",
		lim_bell.key == "motor" and String(lim_bell.text).contains("magnet heat, bell 79 °C of 80 °C"), str(lim_bell)))
	out.append(_t("limited by: a pack just over its rating (first instant) beats a much larger heat ratio reached later, short of burn-out",
		lim_late.key == "pack" and float(lim_late.ratios.motor) > float(lim_late.ratios.pack), str(lim_late.ratios)))
	var bad_lim := ""
	for spec in [["2207", 1960.0, {}], ["2207", 1960.0, {"propeller": "prop_7x4x3", "battery": "battery_6s_1300"}],
			["2306", 1700.0, {}], ["1404", 3800.0, {}], ["2306", 2700.0, {}]]:
		var dd := _design(cfg, spec[0], spec[1])
		var run_p := MotorBench.run("punch", dd, cfg, spec[2])
		var lm := MotorBench.limited_by(dd, cfg, spec[2])
		if float(run_p.burn_s) >= 0.0 and lm.key != "motor":
			bad_lim += " %s/%s:%s" % [spec[0], str(spec[2]), lm.key]
		if float(run_p.burn_s) >= 0.0 and not String(lm.text).contains("burns out"):
			bad_lim += " %s text" % spec[0]
	out.append(_t("limited by: every real punch-out that burned out names motor heat and says it burns out", bad_lim == "", bad_lim))
	var burn_real := MotorBench.limited_by(_design(cfg, "2207", 1960.0), cfg, {"propeller": "prop_7x4x3", "battery": "battery_6s_1300"})
	out.append(_t("limited by: the reference 2207 on a 7 inch prop and 6S burns out and (pack ratio above the motor's) still says motor",
		burn_real.key == "motor" and float(burn_real.ratios.pack) > float(burn_real.ratios.motor) and String(burn_real.text).contains("burns out"), str(burn_real)))

	# Current and prop-size warnings.
	var small := MotorBench.run("sweep", _design(cfg, "0802", 19000.0 if _design(cfg, "0802", 0.0).kv_choices(cfg).has(19000.0) else _design(cfg, "0802", 0.0).kv_choices(cfg)[0]), cfg)
	out.append(_t("a tiny motor on a 5 inch prop is told the prop is too big and that its current is over rating",
		_has(small.warnings, "too big") and _has(small.warnings, "rating"), str(small.warnings)))
	out.append(_t("a well-matched big motor has no prop warning",
		not _has(MotorBench.run("sweep", _design(cfg, "3115", 900.0 if _design(cfg, "3115", 0.0).kv_choices(cfg).has(900.0) else _design(cfg, "3115", 0.0).kv_choices(cfg)[0]), cfg).warnings, "too big"), ""))
	return out


static func _screen(cfg: MotorConfigs) -> Array:
	var out: Array = []
	var d := MotorDesigner.new(cfg, PartsCatalog.load_default())
	d.size = Vector2(1280, 720)
	var counts := {}
	var ok_lines := true
	for kind in MotorBench.KINDS:
		d.set_bench(kind)
		counts[kind] = d.charts.charts.size()
		ok_lines = ok_lines and d.bench_result_label.text == String(d.bench_result().result) \
			and d.bench_result().kind == kind
	out.append(_t("three-way selector: sweep draws one chart (thrust), soak one, punch-out two; one result line each",
		counts == {"sweep": 1, "soak": 1, "punch": 2} and ok_lines, str(counts)))
	# The sweep's chart toggle: thrust by default; Current / Efficiency swap that one chart.
	d.set_bench("sweep")
	var shows_thrust: bool = d.charts.charts[0].title == "Thrust per motor"
	var tog_cur := d.find_child("View_current", true, false) as Button
	var tog_eff := d.find_child("View_efficiency", true, false) as Button
	tog_cur.pressed.emit()
	var cur_one: bool = d.charts.charts.size() == 1 and d.charts.charts[0].title == "Current per motor" and tog_cur.button_pressed and not tog_eff.button_pressed
	tog_eff.pressed.emit()
	var eff_one: bool = d.charts.charts.size() == 1 and d.charts.charts[0].title == "g per watt" and tog_eff.button_pressed and not tog_cur.button_pressed
	tog_eff.pressed.emit()
	var back: bool = d.charts.charts.size() == 1 and d.charts.charts[0].title == "Thrust per motor" and not tog_eff.button_pressed
	out.append(_t("sweep chart toggle: thrust by default; Current and Efficiency each swap the one chart; pressing it again returns to thrust",
		shows_thrust and cur_one and eff_one and back, "%s %s %s %s" % [shows_thrust, cur_one, eff_one, back]))
	d.set_bench("punch")
	var calm_colour: Color = d.charts.charts[0].color
	out.append(_t("punch chart: the winding at ~121 C over the 80 C magnet limit but a cool bell draws in the normal colour",
		float(d.bench_result().peak_temp_c) > 80.0 and calm_colour == MotorDesigner.line_colour(false), str(calm_colour)))
	d.set_bench("sweep")
	var ch_t: PackedFloat64Array = d.charts.charts[0].y
	out.append(_t("sweep chart is per motor too: its last point is the result line's per-motor thrust, not the total",
		is_equal_approx(ch_t[ch_t.size() - 1], float(d.bench_result().motor_thrust_g))
		and ch_t[ch_t.size() - 1] < float(d.bench_result().max_thrust_g) * 0.3, str(ch_t[ch_t.size() - 1])))
	out.append(_t("the result line is per motor with the x4 total in its own small label",
		d.bench_result_label.text.begins_with("Per motor") and d.bench_total_label.text.begins_with("x4 = ")
		and d.bench_total_label.get_theme_font_size("font_size") < d.bench_result_label.get_theme_font_size("font_size"),
		d.bench_result_label.text + " | " + d.bench_total_label.text))

	d.set_bench("sweep")
	var before := String(d.bench_result_label.text)
	d.set_kv(2400.0)
	out.append(_t("a designer change reruns the bench at once (result line changes with KV)",
		String(d.bench_result_label.text) != before and d.bench_result_label.text == String(d.bench_result().result),
		before + " -> " + d.bench_result_label.text))
	d.set_stator("0802")
	d.set_bench("punch")
	var all_w := d.bench_warnings().size()
	out.append(_t("warnings: at most the two most severe show as amber lines; the rest sit behind Details",
		all_w >= 3 and d.bench_warning_label.text.split("\n").size() == 2
		and d.bench_warning_label.text == "\n".join(d.bench_warnings().slice(0, 2))
		and d.warn_details_button.visible and d.warn_details_button.text.begins_with("Details")
		and d.bench_warning_label.get_theme_color("font_color") == LothalTheme.WARNING,
		d.bench_warning_label.text + " | " + d.warn_details_button.text))
	d.toggle_warning_details()
	var opened := d.bench_warning_label.text.split("\n").size() == all_w and d.warn_details_button.text.begins_with("Hide")
	d.toggle_warning_details()
	out.append(_t("warnings: Details opens every line, pressing it again folds back to two",
		opened and d.bench_warning_label.text.split("\n").size() == 2, ""))
	out.append(_t("punch chart: a burn-out draws in the warning colour",
		float(d.bench_result().burn_s) > 0.0 and d.charts.charts[0].color == MotorDesigner.line_colour(true), ""))
	var bx2: PackedFloat64Array = d.charts.charts[0].x
	out.append(_t("the burn-out chart ends at the burn-out time and the other punch chart too",
		float(d.bench_result().burn_s) > 0.0 and bx2[bx2.size() - 1] == float(d.bench_result().burn_s)
		and (d.charts.charts[1].x as PackedFloat64Array).size() == bx2.size(), str(bx2[bx2.size() - 1])))
	var note := d.find_child("BenchNote", true, false) as Label
	out.append(_t("the bench is labelled ideal / model and the stale 'current reads high' note is gone",
		note != null and note.text.contains("ideal / model") and not note.text.to_lower().contains("current reads high")
		and not note.text.to_lower().contains("prop chapter"), "" if note == null else note.text))
	d.free()
	return out
