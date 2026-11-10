class_name TestSr9Mapper
extends RefCounted
## SR9 / L4.1 mapping-drone catalog parts (mapper_*), promoted from tests/sim_reality/references.json (mavic_3m) plus a Li-ion survey pack.
## One TestResult per case: each id loads and is non-empty, each carries a source naming ESTIMATED or published, and a Build from them
## weighs 1000-1500 g all-up (the plan's ~1.2 kg mapper; the Mavic-like body alone solves to 951 g, the survey pack adds the rest).
## FAIL-PROOFS (observed 2026-11-10): MT1 parts not yet in the data files: every load case FAILS (RED run). MT2 one source blanked in
## batteries.json (mapper_battery_6s_20000_liion): its source case FAILS and nothing else. MT3 frame mass_g set to 0: the mass case FAILS.

const IDS := ["mapper_frame_380", "mapper_motor_2008", "mapper_prop_94x53", "mapper_battery_4s_5000", "mapper_battery_6s_20000_liion"]


static func run() -> Array:
	var out: Array = []
	for id in IDS:
		out.append(_loads(id))
	for id in IDS:
		out.append(_sourced(id))
	out.append(_mass())
	return out


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
