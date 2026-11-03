class_name TestMotorDesigner
extends RefCounted
## Motor Designer M5: the designer screen and the MotorDesign choices behind it. Headless: the
## controls are built, no frames run.
##
## The checks that could have passed while proving nothing:
## - "KV choices follow the size" reads the KV chips off the SCREEN (kv_on_screen walks kv_row),
##   not the model's kv_choices(), so a model that is right behind a stale row of chips fails.
## - The figure checks compare against MotorConfigs' laws computed here from the size's own
##   dimensions, and against the text the figures column shows, not only against derive().

const SIZE := Vector2(1280, 720)


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _walk(n: Node, out: Array, cls: String) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_walk(c, out, cls)


static func _near(a: float, b: float, rel := 1e-6) -> bool:
	return absf(a - b) <= rel * maxf(absf(b), 1e-12)


static func run() -> Array:
	var results: Array = []
	var cfg := MotorConfigs.load_default()
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_default(cfg, catalog))
	results.append_array(_test_size_limits_kv(cfg, catalog))
	results.append_array(_test_selection_to_figures(cfg, catalog))
	results.append_array(_test_labels(cfg, catalog))
	results.append_array(_test_shelf_tile(catalog))
	return results


static func _designer(cfg: MotorConfigs, catalog: PartsCatalog) -> MotorDesigner:
	var d := MotorDesigner.new(cfg, catalog)
	d.size = SIZE
	return d


static func _test_default(cfg: MotorConfigs, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(cfg, catalog)
	var f := d.figures()
	var vol := MotorConfigs.stator_volume_cm3(22.0, 7.0)
	out.append(_t("opens on a 2207 at 1960 KV, 12N14P, with its figures already derived",
		d.design.size == "2207" and d.design.kv == 1960.0 and d.design.config() == "12N14P"
		and _near(float(f.get("rm_ohm", 0.0)), cfg.rm_for(vol, 1960.0))
		and _near(float(f.get("io_a", 0.0)), cfg.io_for(vol, 1960.0, 10.0))
		and _near(float(f.get("kt", 0.0)), 60.0 / (TAU * 1960.0)),
		"%s %s %s %s" % [d.design.size, d.design.kv, d.design.config(), f]))
	out.append(_t("the 3D view holds a motor with a bell and a prop on it",
		d.motor_view.motor.find_child("Bell", false, false) != null and d.motor_view.prop.visible
		and d.motor_view.prop.blade_count > 0 and d.prop_id != "", d.prop_id))
	d.free()
	return out


static func _test_size_limits_kv(cfg: MotorConfigs, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(cfg, catalog)
	var bad: Array = []
	var names := cfg.size_names()
	for n in names:
		d.set_stator(n)
		var want: Array = cfg.kv_options(n).map(func(k): return float(k))
		if d.kv_on_screen() != want or not want.has(d.design.kv):
			bad.append("%s: screen %s kv %s" % [n, d.kv_on_screen(), d.design.kv])
	out.append(_t("for every size the KV chips on screen are exactly that size's options, and KV is one of them",
		bad.is_empty() and names.size() == 15, str(bad)))

	d.set_stator("2207")
	var ok_2207 := d.set_kv(2400.0)
	d.set_stator("1404")
	var moved_kv := d.design.kv
	var accepted := d.set_kv(1960.0)
	out.append(_t("a 2207 at 2400 KV moved to 1404 lands on 1404's nearest option, and 1960 KV is refused there",
		ok_2207 and moved_kv == 2750.0 and not accepted and d.design.kv == 2750.0,
		"moved %s accepted %s now %s opts %s" % [moved_kv, accepted, d.design.kv, cfg.kv_options("1404")]))

	d.set_stator("0802")
	var down := d.step_size(-1)
	d.set_stator("3115")
	var up := d.step_size(1)
	d.set_stator("2207")
	d.step_size(1)
	out.append(_t("the size stepper walks the grid in order and stops at both ends",
		not down and not up and d.design.size == "2306" and d.size_label.text == "2306",
		"%s" % d.design.size))

	d.set_stator("1404")
	var shafts_ok := d.design.shaft_mm == float(cfg.shaft_options("1404")[0]) \
		and d.design.mount == String(cfg.mount_options("1404")[0])
	d.set_stator("3115")
	var mount_ok := d.design.mount == String(cfg.mount_options("3115")[0]) and d.mount_option.item_count == 2
	out.append(_t("a size change resets shaft and mount to that size's own options",
		shafts_ok and mount_ok, "%s %s" % [d.design.shaft_mm, d.design.mount]))
	d.free()
	return out


static func _test_selection_to_figures(cfg: MotorConfigs, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(cfg, catalog)
	var n0 := d.derive_count
	var rm0 := float(d.figures().rm_ohm)
	var text0 := d.figure_text("rm_ohm")
	d.set_kv(2400.0)
	var rm1 := float(d.figures().rm_ohm)
	out.append(_t("choosing a higher KV re-derives at once: Rm falls as 1/KV^2 and the column shows it",
		d.derive_count == n0 + 1 and _near(rm1, rm0 * pow(1960.0 / 2400.0, 2.0))
		and d.figure_text("rm_ohm") != text0 and d.figure_text("kv") == "2400 KV",
		"%s -> %s, %s -> %s" % [rm0, rm1, text0, d.figure_text("rm_ohm")]))

	var io14 := float(d.figures().io_a)
	d.set_poles(12)
	var io12 := float(d.figures().io_a)
	out.append(_t("12 poles instead of 14 on a 2207 cuts Io by 12/14 and the summary reads 9N12P",
		_near(io12, io14 * 12.0 / 14.0) and d.summary_label.text.contains("9N12P"),
		"%s -> %s %s" % [io14, io12, d.summary_label.text]))

	d.set_magnet("N52H")
	out.append(_t("the N52H magnet raises the heat limit to 120 C on screen",
		float(d.figures().magnet_max_c) == 120.0 and d.figure_text("magnet_max_c").begins_with("120"),
		d.figure_text("magnet_max_c")))

	var m4 := float(d.figures().mass_g)
	d.set_shaft(5.0)
	var m5 := float(d.figures().mass_g)
	# Steel, pi/4 * (5^2 - 4^2) mm2 over 7 * 2.6 + 8 mm.
	var want := 7.85 * PI / 4.0 * (25.0 - 16.0) * (7.0 * 2.6 + 8.0) / 1000.0
	out.append(_t("a 5 mm shaft instead of 4 mm adds its steel to the mass",
		_near(m5 - m4, want, 1e-4), "%s -> %s want +%s" % [m4, m5, want]))

	var refused := not d.set_shaft(3.0) and not d.set_mount("25 x 25 mm, M3") and not d.set_poles(16)
	out.append(_t("a shaft, mount or pole count not offered for the size is refused",
		refused and d.design.shaft_mm == 5.0, str(d.design.shaft_mm)))

	d.set_stator("1404")
	var f := d.figures()
	var vol := MotorConfigs.stator_volume_cm3(14.0, 4.0)
	var row := cfg.derive("1404", d.design.kv)
	out.append(_t("on 1404 every figure is the grid law for 1404 (rm, io, kt, max current, max power)",
		_near(float(f.rm_ohm), cfg.rm_for(vol, d.design.kv))
		and _near(float(f.io_a), float(row.io_a)) and _near(float(f.kt), 60.0 / (TAU * d.design.kv))
		and _near(float(f.max_current_a), float(row.max_current_a))
		and _near(float(f.max_power_w), float(row.max_power_w)), str(f)))
	d.free()
	return out


static func _test_labels(cfg: MotorConfigs, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(cfg, catalog)
	var bad: Array = []
	for key in MotorDesigner.FIGURE_ROWS:
		var tag := (d._figure_values[key + "_tag"] as Label).text
		var want := String(MotorDesign.figure_tags()[key])
		if tag != want or d.figure_text(key) in ["", "—"]:
			bad.append("%s=%s/%s" % [key, d.figure_text(key), tag])
		if key in ["rm_ohm", "io_a", "mass_g", "max_current_a", "max_power_w"] and tag != "est.":
			bad.append(key + " not est.")
	var header := (d.find_child("FiguresHeader", true, false) as Label).text
	out.append(_t("every figure shows a value and its tag; Rm, Io, mass and the limits are marked est.; header says ideal / model",
		bad.is_empty() and header.contains("ideal / model"), str(bad)))

	var typed: Array = []
	_walk(d.find_child("Right", true, false), typed, "LineEdit")
	_walk(d.find_child("Right", true, false), typed, "SpinBox")
	out.append(_t("nothing in the figures column can be typed into", typed.is_empty(), str(typed)))

	var bar := d.find_child("TopBar", true, false)
	var names: Array = []
	for c in bar.get_children():
		names.append(String(c.name))
	out.append(_t("top bar: Back, name, Copy specs, Save; and a bench placeholder region",
		names.has("Back") and names.has("NameField") and names.has("CopySpecs") and names.has("Save")
		and d.find_child("BenchPlaceholder", true, false) != null, str(names)))

	d.set_motor_name("Hill climber")
	var specs := d.copy_specs()
	out.append(_t("Copy specs names the motor, its choices and every figure with its tag",
		specs.begins_with("Hill climber") and specs.contains("2207 stator") and specs.contains("Resistance:")
		and specs.contains("(est.)") and specs.contains("ideal / model"), specs))
	d.free()
	return out


static func _test_shelf_tile(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = SIZE
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("motor")
	var tile := ds.shelf.find_child("AddMotor", true, false) as BaseButton
	var label := tile.find_child("Label", true, false) as Label if tile != null else null
	out.append(_t("the motor shelf ends with a Design your own tile",
		tile != null and label != null and label.text == "Design your own"))
	if tile != null:
		tile.pressed.emit()
	out.append(_t("pressing it opens the motor designer over the Design Space",
		ds.motor_designer != null and ds.motor_designer.get_parent() == ds))
	if ds.motor_designer != null:
		ds.motor_designer.close()
	out.append(_t("Back closes it and the Design Space forgets it", ds.motor_designer == null))
	ds.free()
	return out
