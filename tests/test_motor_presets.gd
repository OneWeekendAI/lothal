class_name TestMotorPresets
extends RefCounted
## Motor Designer M3: every shelf preset carries Rm and Io (est., from the M2 formulas), and the
## flight figures of every preset and seed build are exactly what they were before.
##
## The fixture (tests/fixtures/motor_preset_figures.json) was snapshotted from the tree BEFORE the
## presets gained Rm/Io. Anything that moves a preset's AUW, thrust:weight, hover throttle, flight
## time or top speed fails here; re-baselining the fixture is a decision, not a test fix.

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
		results.append(_t("%s keeps its pre-M3 flight figures" % key, bad.is_empty(), "; ".join(bad)))
	return results
