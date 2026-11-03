class_name TestMotorConfigs
extends RefCounted
## Motor Designer M2: the standard configuration grid and the formulas derived from it.

const SIZES := ["0802", "1103", "1204", "1404", "1505", "1804", "2004", "2207", "2306", "2306.5",
	"2407", "2507", "2806.5", "2810", "3115"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func run() -> Array:
	var results: Array = []
	var cfg := MotorConfigs.load_default()
	var names := cfg.size_names()
	results.append(_t("the grid holds exactly the 15 standard sizes, in order",
		Array(names) == SIZES, str(names)))

	var bad: Array = []
	for s in cfg.sizes():
		var n := String(s.size)
		var kvs: Array = s.kv_options
		if kvs.size() < 3:
			bad.append(n + " kv count")
		for i in range(1, kvs.size()):
			if float(kvs[i]) <= float(kvs[i - 1]):
				bad.append(n + " kv order")
		if not ["9N12P", "12N14P"].has(String(s.config)):
			bad.append(n + " config")
		if String(s.config) != "%dN%dP" % [int(s.slots), int(s.poles)]:
			bad.append(n + " slots/poles vs config")
		if absf(float(s.stator_diameter_mm) - float(n.substr(0, 2))) > 1e-9 \
				or absf(float(s.stator_height_mm) - float(n.substr(2))) > 1e-9:
			bad.append(n + " dims vs name")
		if String(s.kv_basis) != "est.":
			bad.append(n + " kv_basis")
	results.append(_t("every size has ascending KV options, a valid pole config and dims matching its name",
		bad.is_empty(), str(bad)))

	var unlabelled: Array = []
	for k in ["rm_c", "io_k", "mass_base_g", "mass_per_cm3_g", "loss_w_per_g23", "copper_mass_fraction", "stator_mass_fraction"]:
		var c: Dictionary = cfg._coef.get(k, {})
		if String(c.get("basis", "")) != "est." or String(c.get("note", "")).strip_edges() == "" or float(c.get("value", 0.0)) <= 0.0:
			unlabelled.append(k)
	results.append(_t("every coefficient is labelled est., carries a note and is positive",
		unlabelled.is_empty(), str(unlabelled)))

	var nonpos: Array = []
	var count := 0
	for n in SIZES:
		for kv in cfg.kv_options(n):
			count += 1
			var d := cfg.derive(n, float(kv))
			for k in ["rm_ohm", "io_a", "mass_g", "max_current_a", "max_power_w", "kt", "copper_g", "stator_g"]:
				if float(d.get(k, 0.0)) <= 0.0:
					nonpos.append("%s %s %s" % [n, kv, k])
			if String(d.get("basis", "")) != "est.":
				nonpos.append("%s %s basis" % [n, kv])
	results.append(_t("every grid combination derives positive figures marked est. (%d combos)" % count,
		nonpos.is_empty() and count > 50, str(nonpos)))

	var a := cfg.derive("2207", 1750.0)
	var b := cfg.derive("2207", 2400.0)
	results.append(_t("higher KV on one stator: Rm falls as 1/Kv^2",
		absf(a.rm_ohm / b.rm_ohm - pow(2400.0 / 1750.0, 2.0)) < 1e-9, "%.4f vs %.4f" % [a.rm_ohm, b.rm_ohm]))
	results.append(_t("higher KV on one stator: more max current, same mass",
		b.max_current_a > a.max_current_a and absf(a.mass_g - b.mass_g) < 1e-9, ""))
	var big := cfg.derive("2810", 1100.0)
	var small := cfg.derive("1404", 4600.0)
	results.append(_t("a bigger stator is heavier and has lower Rm at equal KV x ratio",
		big.mass_g > small.mass_g and cfg.derive("2806.5", 1300.0).rm_ohm < cfg.derive("1404", 1300.0).rm_ohm, ""))
	results.append(_t("2306.5 is taller than 2306, so heavier and lower Rm at one KV",
		cfg.derive("2306.5", 1900.0).mass_g > cfg.derive("2306", 1900.0).mass_g
		and cfg.derive("2306.5", 1900.0).rm_ohm < cfg.derive("2306", 1900.0).rm_ohm, ""))
	results.append(_t("2207 1750KV lands in the class-typical band (Rm 0.04-0.09 ohm, 28-45 g, 25-50 A)",
		a.rm_ohm > 0.04 and a.rm_ohm < 0.09 and a.mass_g > 28.0 and a.mass_g < 45.0
		and a.max_current_a > 25.0 and a.max_current_a < 50.0,
		"Rm %.3f mass %.1f I %.1f" % [a.rm_ohm, a.mass_g, a.max_current_a]))
	results.append(_t("Io scales with KV on one stator (stated at one voltage) and with stator volume",
		absf(b.io_a / a.io_a - 2400.0 / 1750.0) < 1e-9
		and cfg.derive("2306.5", 1900.0).io_a > cfg.derive("2306", 1900.0).io_a, "%.3f vs %.3f" % [a.io_a, b.io_a]))
	results.append(_t("Kt in the derivation is MotorModel.kt", absf(a.kt - 60.0 / (TAU * 1750.0)) < 1e-12, ""))
	results.append(_t("an off-grid size or a zero KV derives nothing",
		cfg.derive("9999", 1000.0).is_empty() and cfg.derive("2207", 0.0).is_empty(), ""))
	# The derived figures drive the bench model without a second model.
	var p := MotorModel.operating_point(24.0, 1750.0, a.rm_ohm, a.io_a, a.io_voltage_v, 1.8e-8)
	results.append(_t("derived Rm/Io feed MotorModel.operating_point to a sane point",
		p.rpm > 10000.0 and p.rpm < 1750.0 * 24.0 and p.efficiency > 0.4, str(p.rpm)))
	return results
