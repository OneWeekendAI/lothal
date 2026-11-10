class_name TestSr9Mapper
extends RefCounted
## SR9 / L4.1 mapping-drone catalog parts (mapper_*), promoted from tests/sim_reality/references.json (mavic_3m) plus a Li-ion survey pack.
## One TestResult per case: each id loads and is non-empty, each carries a source naming ESTIMATED or published, and a Build from them
## weighs 1000-1500 g all-up (the plan's ~1.2 kg mapper; the Mavic-like body alone solves to 951 g, the survey pack adds the rest).
## FAIL-PROOFS (observed 2026-11-10): MT1 parts not yet in the data files: every load case FAILS (RED run). MT2 one source blanked in
## batteries.json (mapper_battery_4s_10000_liion): its source case FAILS and nothing else. MT3 frame mass_g set to 0: the mass case FAILS.

## L4.2/L4.3 (observed 2026-11-10): RED run (parts absent, wiring present) = 3 fails (rededge, rtk, and the apply case before
## apply_class_payload recomputed). MT5 `payload_mass_g` line removed from Build.apply_class_payload: only the apply case FAILS (dm 0.00 g,
## total current unchanged). MT6 `payload_w` line removed: only the apply case FAILS (dI 0.000). MT7 payload_from_entry ignores the entry's
## values: only the lookup case FAILS.

## L4.4/L4.5 (observed 2026-11-10): RED run (no class, no table row, example on the caller's class) = 6 fails of 6 new cases. MUTATIONS (each fails
## only its own case): MT8 Mission.TABLE "mapper" row removed -> defaults_for falls to the derived 20 m default, the table case FAILS.
## MT9 cropmerge_example class_id forced back to five_inch -> the class_id case FAILS. Both observed RED (1 fail each, only the named case: height 20/speed 5 derived; class_id five_inch) and GREEN after restoring (22/22).

## L5.2 (observed 2026-11-10): row cases (5) first RED with no "row" in cropmerge_example (all 5 fail), then GREEN. MT10 row low set to the high
## percentile (low==high): only the range case FAILS. MT11 published tag blanked: the tag case and the published-beside case FAIL (2), the rest pass.

const NEW_IDS := ["mapper_cam_multispectral_rededge", "mapper_gps_rtk"]
const IDS := ["mapper_frame_380", "mapper_motor_2008", "mapper_prop_94x53", "mapper_battery_4s_5000", "mapper_battery_4s_10000_liion"]


static func run() -> Array:
	var out: Array = []
	for id in IDS:
		out.append(_loads(id))
	for id in IDS:
		out.append(_sourced(id))
	out.append(_mass())
	for id in NEW_IDS:
		out.append(_new_part(id))
	out.append(_payload_zero())
	out.append(_payload_lookup())
	out.append(_payload_applies())
	out.append_array(_class_cases())
	out.append_array(_row_cases())
	return out


## L5.2: the CropMerge row (Sensitivity.cropmerge_example(...)["row"]) on a small fast field, n = 3.
static func _row() -> Dictionary:
	var field := PackedVector2Array([Vector2(0, 0), Vector2(175, 0), Vector2(175, 100), Vector2(0, 100)])
	return Sensitivity.cropmerge_example("mapper", field, 100.0, 3, 1).get("row", {})


static func _row_cases() -> Array:
	var out: Array = []
	var row := _row()
	var ab: Dictionary = row.get("acres_per_battery", {})
	out.append(TestResult.new("sr9 mapper row: acres per battery is a range (low < high, both positive), not a single point",
		float(ab.get("low", 0.0)) > 0.0 and float(ab.get("low", 0.0)) < float(ab.get("high", 0.0)), "%s-%s" % [str(ab.get("low")), str(ab.get("high"))]))
	var tags_ok := true
	var bad := ""
	for k in ["acres_per_battery", "published", "area", "batteries_used", "flight_time"]:
		var tg := String((row.get(k, {}) as Dictionary).get("tag", ""))
		if not tg in ["measured", "published", "estimated"]:
			tags_ok = false
			bad += k + " "
	out.append(TestResult.new("sr9 mapper row: every figure carries a source tag (measured/published/estimated)", tags_ok, "untagged: " + bad))
	var pub: Dictionary = row.get("published", {})
	out.append(TestResult.new("sr9 mapper row: the published 100-125 acres/battery sits beside the range, tagged published and kept apart from the simulated range",
		pub.get("low") == 100.0 and pub.get("high") == 125.0 and pub.get("tag") == "published" and String(pub.get("note", "")).contains("optimistic")
		and ab.get("tag") == "estimated", str(pub)))
	var basis := String((row.get("area", {}) as Dictionary).get("basis", ""))
	out.append(TestResult.new("sr9 mapper row: the area basis says photo-mapped track and names not-swath, and the area is positive",
		basis.contains("photo-mapped track") and basis.contains("not field area") and basis.contains("swath") and float((row.get("area", {}) as Dictionary).get("mapped_acres", 0.0)) > 0.0, basis.left(90)))
	var trail: Dictionary = row.get("trail", {})
	var trail_ok := true
	for k in ["build_fingerprint", "seed", "master_seed", "model_version", "mission"]:
		trail_ok = trail_ok and trail.has(k) and str(trail[k]) != ""
	out.append(TestResult.new("sr9 mapper row: the input trail carries build fingerprint, seed, master seed, model version and mission", trail_ok, str(trail)))
	return out


static func _class_build() -> Build:
	var catalog := PartsCatalog.load_default()
	var parts := DroneClass.parts_for("mapper")
	var b := Build.from_ids(catalog, String(parts["frame"]), String(parts["motor"]), String(parts["propeller"]), String(parts["battery"]),
		String(parts["esc"]), String(parts["flight_controller"]))
	b.apply_class_payload(DroneClass.payload_for("mapper"))
	return b


static func _class_cases() -> Array:
	var out: Array = []
	out.append(TestResult.new("sr9 mapper: class 'mapper' is available", DroneClass.is_available("mapper") and DroneClass.ids().has("mapper"), str(DroneClass.ids())))
	var catalog := PartsCatalog.load_default()
	var parts := DroneClass.parts_for("mapper")
	var ok := not parts.is_empty()
	var bad := ""
	for cat in ["frame", "motor", "propeller", "battery", "esc", "flight_controller", "camera", "gps"]:
		if String(parts.get(cat, "")) == "" or catalog.get_part(String(parts.get(cat, ""))).is_empty():
			ok = false
			bad += cat + " "
	out.append(TestResult.new("sr9 mapper: parts_for('mapper') names frame/motor/prop/battery/esc/fc/camera/gps and every id resolves in the catalog", ok, "unresolved: " + bad))
	var g := 0.0
	var ft := NAN
	if DroneClass.is_available("mapper"):
		var b := _class_build()
		g = b.all_up_weight_g()
		ft = b.flight_time_min()
	out.append(TestResult.new("sr9 mapper: a Build from the class (payload applied) weighs 1000-1500 g and has a finite positive hover flight time",
		g >= 1000.0 and g <= 1500.0 and is_finite(ft) and ft > 0.0, "%.1f g, %s min" % [g, str(ft)]))
	var p := DroneClass.payload_for("mapper")
	out.append(TestResult.new("sr9 mapper: the class payload is 20 W / 40 g tagged estimated", p["w"] == 20.0 and p["mass_g"] == 40.0 and p["tag"] == "estimated", str(p)))
	var d := Mission.defaults_for("mapper", Mission.SURVEY)
	var row: Dictionary = Mission.TABLE.get("mapper", {})
	var fl: Dictionary = d.get("fields", {})
	var dh := float((fl.get("height_m", {}) as Dictionary).get("value", -1.0))
	# The survey mission's own speed is min(cruise, camera interval cap) = 7.15 m/s, so the table's 8 m/s is read from the cruise loop.
	var ds := float(((Mission.defaults_for("mapper", Mission.CRUISE_LOOP).get("fields", {}) as Dictionary).get("speed_mps", {}) as Dictionary).get("value", -1.0))
	out.append(TestResult.new("sr9 mapper: Mission.defaults_for('mapper','survey') reads survey height 60 m and the table cruise speed (8 m/s)",
		not row.is_empty() and dh == 60.0 and ds == float(row.get("speed_mps", -2.0)) and ds == 8.0, "height %s speed %s" % [str(dh), str(ds)]))
	var field := PackedVector2Array([Vector2(0, 0), Vector2(175, 0), Vector2(175, 100), Vector2(0, 100)])
	var c := Sensitivity.cropmerge_example("mapper", field, 100.0, 4, 1)
	out.append(TestResult.new("sr9 mapper: cropmerge_example(mapper) reports class_id mapper and a label that does not call it a stand-in class",
		c.get("class_id", "") == "mapper" and not String(c.get("label", "")).contains("STAND-IN"), String(c.get("label", "")).left(100)))
	return out


static func _new_part(id: String) -> TestResult:
	var part := PartsCatalog.load_default().get_part(id)
	var src := String(part.get("source", ""))
	var specs: Dictionary = part.get("specs", {})
	var dims_ok := not specs.is_empty()
	for k in ["length_mm", "width_mm", "height_mm"]:
		dims_ok = dims_ok and float(specs.get(k, 0.0)) > 0.0
	var ok := not part.is_empty() and src != "" and (src.contains("ESTIMATED") or src.contains("unverified") or src.contains("published")) \
		and float(part.get("mass_g", 0.0)) > 0.0 and dims_ok
	return TestResult.new("sr9 mapper: %s loads, is sourced (ESTIMATED/unverified/published), mass>0 and dims>0" % id, ok, src.left(80))


static func _payload_zero() -> TestResult:
	var ok := true
	for id in DroneClass.ids():
		if DroneClass.by_id(id).has("payload"):
			continue  # the mapper (L4.4) is the one class that carries a payload; its figures are asserted in _class_cases
		var p := DroneClass.payload_for(id)
		ok = ok and p["w"] == 0.0 and p["mass_g"] == 0.0 and p["tag"] == "estimated" and p.has("note")
	return TestResult.new("sr9 mapper: payload_for is all zeros (tag estimated) for every class without a payload key", ok, str(DroneClass.payload_for("five_inch")))


static func _payload_lookup() -> TestResult:
	var p := DroneClass.payload_from_entry({"id": "x", "payload": {"w": 20.0, "mass_g": 80.0, "note": "n"}})
	var q := DroneClass.payload_from_entry({"id": "y"})
	return TestResult.new("sr9 mapper: a CLASSES entry's payload key is returned with tag estimated; absent key is zero",
		p["w"] == 20.0 and p["mass_g"] == 80.0 and p["tag"] == "estimated" and p["note"] == "n" and q["w"] == 0.0 and q["mass_g"] == 0.0, str(p))


static func _payload_applies() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var a := Build.from_ids(catalog, IDS[0], IDS[1], IDS[2], IDS[4], "esc_4in1_20a_20x20", "fc_f405_20x20")
	var b := Build.from_ids(catalog, IDS[0], IDS[1], IDS[2], IDS[4], "esc_4in1_20a_20x20", "fc_f405_20x20")
	b.apply_class_payload({"w": 20.0, "mass_g": 80.0, "tag": "estimated", "note": ""})
	var v := 22.2
	var di := b.non_motor_load_w() / v - a.non_motor_load_w() / v
	var dg := b.all_up_weight_g() - a.all_up_weight_g()
	var ia := a.hover_current_a(a.hover_throttle(v), v) + a.non_motor_load_w() / v
	var ib := b.hover_current_a(b.hover_throttle(v), v) + b.non_motor_load_w() / v
	return TestResult.new("sr9 mapper: applying {w:20,mass_g:80} adds 20/V to the hover current (within 5%) and 80 g to the AUW",
		absf(di - 20.0 / v) < 0.05 * 20.0 / v and ib - ia >= 20.0 / v * 0.95 and absf(dg - 80.0) < 0.5,
		"dI %.3f (want %.3f), total dI %.3f, dm %.2f g" % [di, 20.0 / v, ib - ia, dg])


static func _loads(id: String) -> TestResult:
	var part := PartsCatalog.load_default().get_part(id)
	return TestResult.new("sr9 mapper: %s loads from the default catalog and is non-empty" % id, not part.is_empty(), str(part.keys()))


static func _sourced(id: String) -> TestResult:
	var src := String(PartsCatalog.load_default().get_part(id).get("source", ""))
	return TestResult.new("sr9 mapper: %s has a source naming ESTIMATED or published" % id,
		src.contains("ESTIMATED") or src.contains("published"), src.left(80))


static func _mass() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var b := Build.from_ids(catalog, IDS[0], IDS[1], IDS[2], IDS[4], "esc_4in1_20a_20x20", "fc_f405_20x20")
	var g := b.all_up_weight_g()
	return TestResult.new("sr9 mapper: Build from the mapper ids weighs 1000-1500 g all-up", g >= 1000.0 and g <= 1500.0, "%.1f g" % g)
