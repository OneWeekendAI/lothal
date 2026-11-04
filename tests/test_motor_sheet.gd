class_name TestMotorSheet
extends RefCounted
## Motor Designer M8: the buy-and-build sheet (MotorSheet).
##
## Mutations each check was shown to fail under:
## - per-motor figures: quote the aircraft's total instead of `motor_thrust_g` / `motor_current_a`.
## - ideal / model label: drop the label line.
## - screw note: drop the thread or the "windings" sentence.
## - spec lines: print the grid's KV instead of the design's (set_kv) or drop the magnet grade.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _design(cfg: MotorConfigs, size: String, kv: float, magnet := "N52") -> MotorDesign:
	var d := MotorDesign.default_design(cfg)
	d.set_size(cfg, size)
	d.set_kv(cfg, kv)
	d.set_magnet(cfg, magnet)
	return d


static func run() -> Array:
	var out: Array = []
	var cfg := MotorConfigs.load_default()
	var d := _design(cfg, "2207", 1960.0)
	var sheet := MotorSheet.compose(d, cfg)
	var text := MotorSheet.to_text(d, cfg)
	var sweep := MotorBench.run("sweep", d, cfg)
	var e: Dictionary = sheet["expected"]

	out.append(_t("sheet: names the motor's spec (stator, KV, poles, magnet, shaft, mount)",
		text.contains("Stator: 2207 (22 x 7 mm)") and text.contains("KV: 1960") and text.contains("Poles: 14 (12N14P)")
		and text.contains("Magnets: N52 (heat limit 80 °C)") and text.contains("Shaft: 4 mm")
		and text.contains("Mount: 16 x 16 mm, M3"), text))
	out.append(_t("sheet: the spec follows the design (another KV and magnet grade change the lines)",
		MotorSheet.to_text(_design(cfg, "2306", 1700.0, "N52H"), cfg).contains("KV: 1700")
		and MotorSheet.to_text(_design(cfg, "2306", 1700.0, "N52H"), cfg).contains("Magnets: N52H (heat limit 120 °C)")
		and MotorSheet.to_text(_design(cfg, "2306", 1700.0, "N52H"), cfg).contains("Stator: 2306"), ""))
	out.append(_t("sheet: expected figures are PER MOTOR (a quarter of the quad's total), with the total on its own line",
		is_equal_approx(float(e.max_thrust_g), float(sweep.max_thrust_g) / 4.0)
		and is_equal_approx(float(e.current_a), float(sweep.max_current_a) / 4.0)
		and text.contains("Full throttle: %s g thrust, %.0f A" % [MotorBench._thousands(float(e.max_thrust_g)), float(e.current_a)])
		and text.contains("All 4 motors together: %s g" % MotorBench._thousands(float(sweep.max_thrust_g))),
		"%.0f g per motor, %.0f total" % [e.max_thrust_g, sweep.max_thrust_g]))
	out.append(_t("sheet: says which prop and pack the figures are for",
		text.contains("On: ") and text.contains(String(sheet.setup.prop)) and text.contains(String(sheet.setup.pack))
		and String(sheet.setup.prop) != "" and String(sheet.setup.pack) != "", str(sheet.setup)))
	var other := MotorSheet.to_text(d, cfg, {"propeller": "prop_6x4x2", "battery": "battery_6s_1300"})
	out.append(_t("sheet: another prop and pack change the figures and the 'On:' line",
		other != text and other.contains(String(PartsCatalog.load_default().get_part("prop_6x4x2").name))
		and other.contains(String(PartsCatalog.load_default().get_part("battery_6s_1300").name))
		and float(MotorSheet.compose(d, cfg, {"propeller": "prop_6x4x2", "battery": "battery_6s_1300"}).expected.max_thrust_g) != float(e.max_thrust_g),
		other.get_slice("\n", 12)))
	out.append(_t("sheet: carries the ideal / model label twice (top and the figures heading), never 'datasheet'",
		text.contains("Figures are ideal / model, not measured.") and text.contains("PER MOTOR (ideal / model)")
		and not text.to_lower().contains("datasheet"), ""))
	out.append(_t("sheet: one-line mounting-screw safety note, with the thread, under SAFETY",
		text.contains("SAFETY\n  - M3 screws: measure before fitting.") and text.contains("reaches the windings")
		and MotorSheet.screw_note("M3").count("\n") == 0, MotorSheet.screw_note("M3")))
	out.append(_t("sheet: the thread comes from the mount option (M3, M2, M1.4) and a bare option falls back to a general note",
		MotorSheet.thread_of("16 x 16 mm, M3") == "M3" and MotorSheet.thread_of("9 x 9 mm, M2") == "M2"
		and MotorSheet.thread_of("6.6 mm, M1.4") == "M1.4" and MotorSheet.thread_of("16 x 16 mm") == ""
		and MotorSheet.screw_note("").begins_with("Mounting screws:"), ""))
	var burn := MotorSheet.to_text(d, cfg, {"propeller": "prop_7x4x3", "battery": "battery_6s_1300"})
	out.append(_t("sheet: a burn-out build says so and lists the warnings",
		burn.contains("burns out after") and burn.contains("WARNINGS") and burn.contains("Winding burns out"), burn))
	return out
