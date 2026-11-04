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
	var n52 := MotorBench.run("punch", _design(cfg, "2306", 2100.0, "N52"), cfg)
	var n52h := MotorBench.run("punch", _design(cfg, "2306", 2100.0, "N52H"), cfg)
	var peak := float(n52.peak_temp_c)
	out.append(_t("a hotter magnet limit removes the heat warning (same run, same temperature)",
		peak > cfg.magnet_max_c("N52") and peak < cfg.magnet_max_c("N52H")
		and _has(n52.warnings, "winding reaches") and not _has(n52h.warnings, "winding reaches")
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

	# Heat is plausible: a 2207 flat out for 15 s lands in the real range, and a hover soak stays cool.
	# (The old one-lump model, copper + iron against a still-air film, read 250 C for the punch.)
	var hot := MotorBench.run("punch", _design(cfg, "2207", 1960.0), cfg)
	out.append(_t("thermal: 2207 punch-out ends below 130 C (and above 60 C), the hover soak below 70 C",
		float(hot.end_temp_c) < 130.0 and float(hot.end_temp_c) > 60.0 and float(soak.end_temp_c) < 70.0,
		"punch %.0f C soak %.0f C" % [hot.end_temp_c, soak.end_temp_c]))
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
	var slow := MotorBench.Lumps.new(fig)
	var fast := MotorBench.Lumps.new(fig)
	for i in 60:
		slow.step(40.0, 2000.0, 0.5)
		fast.step(40.0, 20000.0, 0.5)
	out.append(_t("thermal: the same loss runs cooler at high rpm than at low rpm",
		fast.winding_c < slow.winding_c - 5.0, "%.0f vs %.0f" % [fast.winding_c, slow.winding_c]))

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
	out.append(_t("warnings show as one plain amber line each under the chart",
		d.bench_warning_label.text.split("\n").size() == d.bench_warnings().size() and d.bench_warnings().size() >= 2
		and d.bench_warning_label.get_theme_color("font_color") == LothalTheme.WARNING,
		d.bench_warning_label.text))
	var note := d.find_child("BenchNote", true, false) as Label
	out.append(_t("the bench is labelled ideal / model and says current reads high until the prop chapter",
		note != null and note.text.contains("ideal / model") and note.text.to_lower().contains("current reads high")
		and note.text.to_lower().contains("prop chapter"), "" if note == null else note.text))
	d.free()
	return out
