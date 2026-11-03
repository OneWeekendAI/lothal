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

	# k_t is fitted at the LOADED rated point (Build.fit_rated_point): flat out on its own test prop
	# at its test voltage, no sag, the DC model must make the datasheet thrust. Fitted at the
	# no-load Kv x V instead, every preset made only 0.67-0.79x of it (MOTOR_REBASELINE.md).
	# Computed through the drone's own path (Build.k_t, the DC rpm solve), one result per preset.
	var catalog := PartsCatalog.load_default()
	for m in motors:
		var id := String(m["part_id"])
		var part: Dictionary = catalog.get_part(id)
		var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, id,
			String(part["thrust_test"]["prop_id"]), ReferenceBuild.BATTERY_ID)
		var a := b._dc_args()
		var tv := float(part["thrust_test"]["voltage_v"])
		var rated_g := float(part["specs"]["max_thrust_g"])
		var got_g := 0.0
		if not a.is_empty():
			var rpm := Fitting.dc_rpm_at_throttle(1.0, 1.0, a[0], a[1], a[2], a[3], a[4], tv, 0.0, 1.0)
			got_g = PropellerModel.thrust_n(b.k_t, rpm) / 9.81 * 1000.0
		results.append(_t("%s: flat out on its test prop at %.1f V the DC model makes its datasheet thrust (within 2%%)" % [id, tv],
			rated_g > 0.0 and absf(got_g - rated_g) <= 0.02 * rated_g,
			"%.1f g vs datasheet %.1f g (x%.3f)" % [got_g, rated_g, got_g / maxf(rated_g, 1e-9)]))

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
		results.append(_t("%s keeps its pinned (2026-11-03 re-baselined) flight figures" % key, bad.is_empty(), "; ".join(bad)))
	return results
