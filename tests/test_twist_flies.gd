class_name TestTwistFlies
extends RefCounted
## PD2: authored twist reaches the solve (spec finding 1). The preset half of the promise is
## TestPropPin; this file is the half where a table exists. Static figures can sit on the lift cap
## (finding 2), so the effect is read through forward figures unless a check says otherwise.
##
## TO MAKE THESE FAIL: (a) return the helix from `bemt.rs::beta_at`; (c) drop `blade_twist()` from
## `Build.forward_ratios`, or drop the twist from the key in `bemt_ratios.rs::key_of`.


static func run() -> Array:
	var results: Array = []
	results.append(_measured_twist_raises_the_zero_thrust_j())
	results.append(_a_table_sampling_the_helix_flies_the_helix())
	results.append(_twist_reaches_builds_ratios())
	results.append(_low_twist_moves_static_thrust_through_build())
	results.append(_the_drone_core_flies_the_same_table())
	results.append(_geometric_mode_ignores_a_stale_table())
	return results


static func _measured_twist_raises_the_zero_thrust_j() -> TestResult:
	var p: Dictionary = PropGap.props()["apcff_4.2x4"]
	var helix := PropGap.model_figures(p)
	var twisted := PropGap.model_figures(p, PropGap.twist_of(p))
	return TestResult.new("twist: measured 4.2x4 twist lifts J0 by at least 0.05 (spec's port said so)",
		float(twisted.j0) - float(helix.j0) >= 0.05, "%.3f -> %.3f" % [helix.j0, twisted.j0])


## Sampled finely, the helix as a table must fly within interpolation error of no table. Separates a
## working table from one read at the wrong stride, radius or unit, which would all move J0 too.
static func _a_table_sampling_the_helix_flies_the_helix() -> TestResult:
	var p: Dictionary = PropGap.props()["apcff_4.2x4"]
	var doc := PropellerDocument.new()
	doc.diameter_mm = float(p["diameter_in"]) * 25.4
	doc.pitch_mm = float(p["pitch_in"]) * 25.4
	var table := PackedFloat64Array()
	for i in range(0, 201):
		var f: float = 0.15 + 0.85 * i / 200.0
		table.append(f)
		table.append(doc.beta_rad(f))
	var a := PropGap.model_point(p, 0.5)
	var b := PropGap.model_point(p, 0.5, table)
	return TestResult.new("twist: a fine table of the helix flies the helix (within 0.1 %)",
		absf(a.x - b.x) <= 0.001 * a.x and absf(a.y - b.y) <= 0.001 * a.y, "%s vs %s" % [a, b])


static func _build_with_twist(id: String, table: PackedFloat64Array) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	var doc := PropellerDocument.from_catalog_prop(record)
	doc.chord_is_assumed = false
	doc.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED
	doc.twist = table
	record["part_id"] = id
	record[PropellerDocument.AUTHORED_BLADE_KEY] = doc.to_dictionary()
	catalog.by_id[id] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID, id,
		ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)


static func _flat(deg: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, deg_to_rad(deg), 1.0, deg_to_rad(deg)])


## Both builds are asked in one process, so a cache key that forgets the twist hands the second the
## first's table, and they come back equal.
static func _twist_reaches_builds_ratios() -> TestResult:
	var a := _build_with_twist("twist_fixture_a", _flat(12.0)).forward_ratios()
	var b := _build_with_twist("twist_fixture_b", _flat(24.0)).forward_ratios()
	var ta := a.thrust_ratio(20000.0, 20.0, 0.0)
	var tb := b.thrust_ratio(20000.0, 20.0, 0.0)
	return TestResult.new("twist: two blades differing only in twist get different forward ratios",
		absf(ta - tb) > 0.02, "%.4f vs %.4f" % [ta, tb])


## Well below the lift cap thrust does respond, so the static path is testable after all.
static func _low_twist_moves_static_thrust_through_build() -> TestResult:
	var a := _build_with_twist("twist_fixture_low", _flat(3.0))
	var b := _build_with_twist("twist_fixture_mid", _flat(6.0))
	return TestResult.new("twist: under the cap, k_t and k_q follow the table through Build",
		b.k_t > a.k_t * 1.2 and b.k_q != a.k_q, "k_t %s vs %s" % [a.k_t, b.k_t])


static func _the_drone_core_flies_the_same_table() -> TestResult:
	var b := _build_with_twist("twist_fixture_core", _flat(12.0))
	var flown: float = b.build_drone_core().powertrain.forward_thrust_ratio(20000.0, 20.0, 0.0)
	var panel: float = b.forward_ratios().thrust_ratio(20000.0, 20.0, 0.0)
	var helix: float = ReferenceBuild.build().forward_ratios().thrust_ratio(20000.0, 20.0, 0.0)
	return TestResult.new("twist: the flight tick reads the panel's surface, not the helix",
		flown == panel and absf(flown - helix) > 0.02, "%.4f, %.4f, helix %.4f" % [flown, panel, helix])


static func _geometric_mode_ignores_a_stale_table() -> TestResult:
	var doc := PropellerDocument.new()
	doc.twist = _flat(10.0)
	doc.twist_mode = PropellerDocument.TWIST_MODE_GEOMETRIC
	return TestResult.new("twist: geometric mode flies the helix whatever table it holds",
		doc.flown_twist().is_empty(), str(doc.flown_twist()))
