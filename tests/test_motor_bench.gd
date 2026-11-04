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
		amps[amps.size() - 1] > amps[1] and amps[0] == 0.0 and String(sweep.result).begins_with("Max ")
		and String(sweep.result).contains(" g/W at hover") and float(sweep.max_thrust_g) > 1000.0, String(sweep.result)))

	# Heat warning follows the magnet's limit (same motor, same run, only the grade differs).
	# 2306 at 1700 KV (114 C peak, between N52's 80 C and N52H's 120 C, and under the 180 C burn-out).
	# It was 2700 KV before the thermal refit (2026-11-04), which now burns out the winding instead.
	var n52 := MotorBench.run("punch", _design(cfg, "2306", 1700.0, "N52"), cfg)
	var n52h := MotorBench.run("punch", _design(cfg, "2306", 1700.0, "N52H"), cfg)
	var peak := float(n52.peak_temp_c)
	out.append(_t("a hotter magnet limit removes the heat warning (same run, same temperature)",
		peak > cfg.magnet_max_c("N52") and peak < cfg.magnet_max_c("N52H")
		and _has(n52.warnings, "Magnets overheat") and not _has(n52h.warnings, "Magnets overheat")
		and float(n52.burn_s) < 0.0
		and is_equal_approx(peak, float(n52h.peak_temp_c)),
		"peak %.1f N52 %s N52H %s" % [peak, n52.warnings, n52h.warnings]))

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
	out.append(_t("thermal: 2207 1960 KV from physics: punch-out ~130 C (120-140), hover soak ~64 C (58-70), no burn-out",
		float(hot.end_temp_c) > 120.0 and float(hot.end_temp_c) < 140.0 and float(soak.end_temp_c) > 58.0
		and float(soak.end_temp_c) < 70.0 and float(hot.burn_s) < 0.0 and hot.x[hot.x.size() - 1] == MotorBench.PUNCH_S,
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
	out.append(_t("warnings: each is 8 words or fewer, and the burn-out comes first, then heat, then current",
		wl.size() >= 3 and short and String(wl[0]).begins_with("Winding burns out") and String(wl[1]).begins_with("Magnets overheat")
		and String(wl[2]).begins_with("Over current rating: "), str(wl)))
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
	out.append(_t("three-way selector: sweep draws three charts, soak one, punch-out two; one result line each",
		counts == {"sweep": 3, "soak": 1, "punch": 2} and ok_lines, str(counts)))

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
	var bx2: PackedFloat64Array = d.charts.charts[0].x
	out.append(_t("the burn-out chart ends at the burn-out time and the other punch chart too",
		float(d.bench_result().burn_s) > 0.0 and bx2[bx2.size() - 1] == float(d.bench_result().burn_s)
		and (d.charts.charts[1].x as PackedFloat64Array).size() == bx2.size(), str(bx2[bx2.size() - 1])))
	var note := d.find_child("BenchNote", true, false) as Label
	out.append(_t("the bench is labelled ideal / model and says current reads high until the prop chapter",
		note != null and note.text.contains("ideal / model") and note.text.to_lower().contains("current reads high")
		and note.text.to_lower().contains("prop chapter"), "" if note == null else note.text))
	d.free()
	return out
