class_name TestSr9Mapper
extends RefCounted
## SR9 / L4.1 mapping-drone catalog parts (mapper_*), promoted from tests/sim_reality/references.json (mavic_3m) plus a Li-ion survey pack.
## One TestResult per case: each id loads and is non-empty, each carries a source naming ESTIMATED or published, and a Build from them
## weighs 1000-1500 g all-up (the plan's ~1.2 kg mapper; the Mavic-like body alone solves to 951 g, the survey pack adds the rest).
## FAIL-PROOFS (observed 2026-11-10): MT1 parts not yet in the data files: every load case FAILS (RED run). MT2 one source blanked in
## batteries.json (mapper_battery_6s_20000_liion): its source case FAILS and nothing else. MT3 frame mass_g set to 0: the mass case FAILS.

## L4.2/L4.3 (observed 2026-11-10): RED run (parts absent, wiring present) = 3 fails (rededge, rtk, and the apply case before
## apply_class_payload recomputed). MT5 `payload_mass_g` line removed from Build.apply_class_payload: only the apply case FAILS (dm 0.00 g,
## total current unchanged). MT6 `payload_w` line removed: only the apply case FAILS (dI 0.000). MT7 payload_from_entry ignores the entry's
## values: only the lookup case FAILS.

const NEW_IDS := ["mapper_cam_multispectral_rededge", "mapper_gps_rtk"]
const IDS := ["mapper_frame_380", "mapper_motor_2008", "mapper_prop_94x53", "mapper_battery_4s_5000", "mapper_battery_6s_20000_liion"]


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
		var p := DroneClass.payload_for(id)
		ok = ok and p["w"] == 0.0 and p["mass_g"] == 0.0 and p["tag"] == "estimated" and p.has("note")
	return TestResult.new("sr9 mapper: payload_for is all zeros (tag estimated) for every existing class", ok, str(DroneClass.payload_for("five_inch")))


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
