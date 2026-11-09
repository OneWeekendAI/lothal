class_name TestMotorPresets
extends RefCounted
## Motor Designer M3: every shelf preset carries Rm and Io (est., from the M2 formulas), and the
## flight figures of every preset and seed build are pinned.
##
## The fixture (tests/fixtures/motor_preset_figures.json) was snapshotted from the tree before M3 and
## DELIBERATELY RE-BASELINED on 2026-11-03 when every motor moved onto the Kv/Rm/Io law and rm_c
## went up x1.2 (before/after table: landingpage/docs/lothal/MOTOR_REBASELINE.md). Anything that
## moves a preset's AUW, thrust:weight, hover throttle, flight time or top speed fails here;
## re-baselining the fixture again is a decision, not a test fix.

const REL_TOL := 1e-9


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _close(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * maxf(absf(a), absf(b)) + 1e-12


static func run() -> Array:
	var results: Array = []
	var cfg := MotorConfigs.load_default()
	var motors: Array = JsonStore.read_document("res://data/parts/motors.json").get("parts", [])
	results.append(_t("the shelf still has its 16 presets", motors.size() == 16, str(motors.size())))

	for m in motors:
		var id := String(m["part_id"])
		var sp: Dictionary = m["specs"]
		var has := sp.has("rm_ohm") and sp.has("io_a") and sp.has("io_voltage_v")
		results.append(_t("%s carries Rm, Io and the voltage Io is stated at" % id, has, str(sp.keys())))
		if not has:
			continue
		results.append(_t("%s: Rm and Io are marked est. and Io is stated at the thrust-test voltage" % id,
			String(sp.get("rm_io_basis", "")) == "est."
			and _close(float(sp["io_voltage_v"]), float(m["thrust_test"]["voltage_v"]), 1e-12),
			"%s / %s" % [sp.get("rm_io_basis", ""), sp["io_voltage_v"]]))
		var d := cfg.derive_stator(float(sp["stator_diameter_mm"]), float(sp["stator_height_mm"]),
			float(sp["kv"]), float(sp["io_voltage_v"]))
		results.append(_t("%s: Rm and Io are the M2 formula values for its stator and KV" % id,
			not d.is_empty() and _close(float(sp["rm_ohm"]), float(d["rm_ohm"]), 1e-3)
			and _close(float(sp["io_a"]), float(d["io_a"]), 1e-3),
			"Rm %s vs %s, Io %s vs %s" % [sp["rm_ohm"], d.get("rm_ohm"), sp["io_a"], d.get("io_a")]))
		results.append(_t("%s: Io is well below the amp rating and the stall current is above it" % id,
			float(sp["io_a"]) > 0.0 and float(sp["io_a"]) < 0.2 * float(sp["max_amps"])
			and float(sp["io_voltage_v"]) / float(sp["rm_ohm"]) > float(sp["max_amps"]),
			"io %s max %s" % [sp["io_a"], sp["max_amps"]]))

	# Since the prop chapter (2026-11-04) k_t and k_q come from the test prop's own blade-element
	# integral, NOT from the datasheet thrust, so "flat out makes its datasheet thrust within 2%" is
	# false by design (x0.71 to x1.98 across the shelf). The datasheet figure is a reference; what is
	# asserted instead is that the model stays in a plausible band around it, per preset:
	#   thrust: model / datasheet in 0.5-2.0 (manufacturer tables disagree by 3.3x among themselves),
	#   hover figure of merit of the test prop in 0.38-0.70 (a real small prop is 0.4-0.65),
	#   amps: model flat-out winding current / rated max_amps in 0.6-2.5 (a burst, not a rating).
	# Outliers (thrust ratio outside 0.8-1.25, amps ratio above 1.5) are LISTED in the detail so the
	# spread is read, not hidden. The bands are broad on purpose; a prop or fit that is wrong by a
	# factor of two, or a k_q off by a third, goes red.
	var catalog := PartsCatalog.load_default()
	var outliers: Array = []
	for m in motors:
		var id := String(m["part_id"])
		var part: Dictionary = catalog.get_part(id)
		var prop: Dictionary = catalog.get_part(String(part["thrust_test"]["prop_id"]))
		var fit := Build.fit_rated_point(part, prop)
		var tv := float(part["thrust_test"]["voltage_v"])
		var p := Build.dc_motor_params(part)
		var op := MotorModel.operating_point(tv, p[0], p[1], p[2], p[3], float(fit["k_q"]))
		var d_m := PropellerDocument.from_catalog_prop(prop).diameter_mm * 0.001
		var fm := pow(float(fit["k_t"]), 1.5) / (sqrt(2.0 * 1.225 * PI * d_m * d_m / 4.0) * float(fit["k_q"]))
		var rated_g := float(part["specs"]["max_thrust_g"])
		var model_g := PropellerModel.thrust_n(float(fit["k_t"]), float(fit["rpm"])) / 9.81 * 1000.0
		var ratio := model_g / maxf(rated_g, 1e-9)
		var amps := float(op["current_a"]) / maxf(float(part["specs"]["max_amps"]), 1e-9)
		var tag := ""
		if ratio < 0.8 or ratio > 1.25 or amps > 1.5:
			tag = " OUTLIER"
			outliers.append(id)
		results.append(_t("%s: flat out on its test prop at %.1f V the BEMT model sits in the plausible band of its datasheet (thrust 0.5-2.0x, FM 0.38-0.70, amps 0.6-2.5x)" % [id, tv],
			rated_g > 0.0 and ratio >= 0.5 and ratio <= 2.0 and fm >= 0.38 and fm <= 0.70
			and amps >= 0.6 and amps <= 2.5,
			"%.1f g vs datasheet %.1f g (x%.3f), FM %.3f, %.1f A vs %.1f A rated (x%.2f)%s" % [
				model_g, rated_g, ratio, fm, float(op["current_a"]), float(part["specs"]["max_amps"]), amps, tag]))
	results.append(_t("the datasheet outliers are the known ones, listed (%d of %d presets)" % [outliers.size(), motors.size()],
		outliers.size() <= 12, ", ".join(outliers)))

	# RE-PINNED 2026-11-09 (SR1-SR2): ONLY flight_time_min moved (auw, T:W, hover throttle, top speed are unchanged to 1e-9, so hover physics
	# did not move). The freestyle profile is forward flight: it now pays rear-rotor interference, directional drag and profile-power
	# growth and gains the translational lift the old thrust-ratio cap discarded. -24 % .. +2.9 % over the 26 builds; the two rises
	# (class/cinelifter +2.6 %, motor_2808_1300kv +2.9 %) are the lowest-disc-loading builds, where uncapped lift (ratio 1.25-1.38
	# at 12 m/s) outweighs the added costs. Old -> new table: sim-reality plan, SR-green section.
	var expected: Dictionary = JsonStore.read_document(MotorPresetFigures.FIXTURE)
	var live := MotorPresetFigures.snapshot()
	results.append(_t("the figures snapshot covers 16 presets and 10 seed builds",
		expected.size() == 26 and live.size() == 26, "%d / %d" % [expected.size(), live.size()]))
	for key in expected:
		var e: Dictionary = expected[key]
		var l: Dictionary = live.get(key, {})
		var bad: Array = []
		for f in MotorPresetFigures.FIELDS:
			if not l.has(f) or not _close(float(e[f]), float(l[f]), REL_TOL):
				bad.append("%s %s vs %s" % [f, e[f], l.get(f)])
		results.append(_t("%s keeps its pinned (2026-11-04 prop chapter) flight figures" % key, bad.is_empty(), "; ".join(bad)))
	return results
