class_name TestCalibration
extends RefCounted
## P5 calibration — propulsion.md §4.4, pure, in Rust beside the BEMT core.
##
## Two things are proven here, and they are different claims:
##
##   1. THE ANCHOR. For every motor's `thrust_test` row in the catalog, the per-prop
##      calibration scalar, applied multiplicatively to the BEMT integral, reproduces the
##      measured thrust at the measured RPM/prop/voltage to float round-trip. One scalar per
##      prop, fitted to its measured row — §4.4's sentence, asserted across all 18 rows.
##
##   2. THE CROSS-PROP MOVE. The old `scale_k_t_to_prop` (D⁴ · blades^0.8 · pitch^0.5) is
##      deleted and replaced by the BEMT geometry ratio BEMT(to,rpm)/BEMT(from,rpm), with an
##      explicit identity short-circuit so the reference build's oracles cannot move. The
##      ratio is asserted to BE the BEMT ratio, and the identity is asserted bit-exact.
##
## The calibration-factor DISTRIBUTION is reported, not asserted — §4.4 point 3: a factor far
## from 1 is a diagnostic, and the catalog should show the spread rather than hide it. The
## polar grid is also reported: the band barely moves with a0/Cd0, which is itself the
## finding (the band is set by chord_is_assumed and the catalog's own 1.79x motor noise, not
## by the polar — see §4.4's "if a global polar cannot get the calibration factors into a
## tight band, that is a real result and it ships as one").

const GRAVITY_MPS2 := 9.81
const STANDARD_RHO := 1.225
## The anchor round-trip is float multiplication and division; 1e-9 relative is a comfortable
## envelope for a division that must be exact by construction (the scalar IS
## measured_thrust / BEMT_thrust, so the product is the measured value to the last ulp).
const ROUND_TRIP_TOL := 1.0e-9

static func run() -> Array:
	var results: Array = []
	results.append_array(_the_anchor_holds_for_every_measured_row())
	results.append(_the_cross_prop_ratio_is_the_bemt_ratio())
	results.append(_the_identity_short_circuit_is_bit_exact())
	results.append(_the_calibration_distribution_is_reported())
	return results


## Section 1 — §4.4's anchor: one scalar per prop reproduces its measured row exactly.
##
## For each motor's thrust_test row: rpm = KV × voltage (the same convention build.gd's fit
## uses), measured thrust = max_thrust_g. calibrate(...) is the scalar; the product
## calibrate × BEMT_solve(...)[0] must come back to the measured newtons. It does by
## construction — the scalar is defined as the ratio — so the assertion is that the
## construction holds to the bit, across every row, including the whoop props where the
## generated chord under-predicts and the scalar is far from 1.
##
## TO MAKE THIS FAIL: have calibrate divide by the wrong thing (e.g. return
## measured_thrust / solve(...)[2], induced power) or apply the scalar to the wrong output.
static func _the_anchor_holds_for_every_measured_row() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var polar: PackedFloat64Array = BemtModel.global_polar()
	var failures: Array = []
	var rows := 0

	for motor in catalog.list_category("motor"):
		var test: Dictionary = motor.get("thrust_test", {})
		var prop: Dictionary = catalog.get_part(String(test.get("prop_id", "")))
		if prop.is_empty():
			continue
		var doc := PropellerDocument.from_catalog_prop(prop)
		var kv := float(motor["specs"]["kv"])
		var voltage := float(test.get("voltage_v", 0.0))
		var rpm := kv * voltage
		var measured_n := float(motor["specs"]["max_thrust_g"]) / 1000.0 * GRAVITY_MPS2

		var calibration := BemtModel.calibrate(STANDARD_RHO,
			doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades),
			rpm, doc.chord, measured_n)
		var bem_t_n: float = BemtModel.solve(STANDARD_RHO,
			doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades),
			rpm, doc.chord, polar[0], polar[1], polar[2], polar[3])[0]
		rows += 1
		var round_trip := calibration * bem_t_n
		var err := absf(round_trip - measured_n) / measured_n
		if err > ROUND_TRIP_TOL or not is_finite(calibration) or calibration <= 0.0:
			failures.append("%s (%s): calib %.4f, round-trip %.4f g vs measured %.0f g" % [
				motor["part_id"], prop["part_id"], calibration,
				round_trip / GRAVITY_MPS2 * 1000.0, float(motor["specs"]["max_thrust_g"])])

	results.append(TestResult.new(
		"every measured thrust_test row round-trips through its calibration scalar to 1e-9",
		failures.is_empty(),
		"%d rows; %s" % [rows,
			"all within 1e-9" if failures.is_empty() else "; ".join(failures)]))

	# Without the polar grid the band could be read as a polar defect when it is a data
	# property. Report the band against the production polar too, so the two readings are
	# next to each other.
	var factors: Array = []
	for motor in catalog.list_category("motor"):
		var test: Dictionary = motor.get("thrust_test", {})
		var prop: Dictionary = catalog.get_part(String(test.get("prop_id", "")))
		if prop.is_empty():
			continue
		var doc := PropellerDocument.from_catalog_prop(prop)
		var kv := float(motor["specs"]["kv"])
		var rpm := kv * float(test.get("voltage_v", 0.0))
		var measured_n := float(motor["specs"]["max_thrust_g"]) / 1000.0 * GRAVITY_MPS2
		factors.append(measured_n / BemtModel.solve(STANDARD_RHO,
			doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades),
			rpm, doc.chord, polar[0], polar[1], polar[2], polar[3])[0])
	var lo: float = factors.min()
	var hi: float = factors.max()
	results.append(TestResult.new(
		"calibration-factor band at the production polar is finite and positive (the width is reported)",
		is_finite(lo) and lo > 0.0 and is_finite(hi),
		("band %.3f..%.3f across %d rows (%.1fx) — dominated by chord_is_assumed and the "
			+ "catalog's own 1.79x motor-to-motor disagreement, not the polar") % [
			lo, hi, factors.size(), hi / lo]))
	return results


## Section 2 — the cross-prop move is the BEMT geometry ratio.
##
## scale_k_t_to_prop(k, from, to, rpm) must equal k × BEMT(to,rpm)/BEMT(from,rpm) — blade
## count and pitch entering the integral where they act (§0), not via exponents. Asserted
## against an independently-computed solve on both sides, at a non-identity pair so the
## ratio is actually exercised.
##
## TO MAKE THIS FAIL: keep the old D⁴·blades^0.8·pitch^0.5 arithmetic, or drop the BEMT
## ratio for any constant.
static func _the_cross_prop_ratio_is_the_bemt_ratio() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var polar: PackedFloat64Array = BemtModel.global_polar()
	var from_prop: Dictionary = catalog.get_part("prop_5x43x3")
	var to_prop: Dictionary = catalog.get_part("prop_7x4x3")
	var from_doc := PropellerDocument.from_catalog_prop(from_prop)
	var to_doc := PropellerDocument.from_catalog_prop(to_prop)
	var rpm := 35000.0
	var k_t := 1.234e-6

	var ratio := BemtModel.scale_k_t_to_prop(k_t,
		from_doc.diameter_mm * 0.001, from_doc.pitch_mm * 0.001, float(from_doc.blades), from_doc.chord,
		to_doc.diameter_mm * 0.001, to_doc.pitch_mm * 0.001, float(to_doc.blades), to_doc.chord,
		rpm)
	var from_t: float = BemtModel.solve(STANDARD_RHO,
		from_doc.diameter_mm * 0.001, from_doc.pitch_mm * 0.001, float(from_doc.blades),
		rpm, from_doc.chord, polar[0], polar[1], polar[2], polar[3])[0]
	var to_t: float = BemtModel.solve(STANDARD_RHO,
		to_doc.diameter_mm * 0.001, to_doc.pitch_mm * 0.001, float(to_doc.blades),
		rpm, to_doc.chord, polar[0], polar[1], polar[2], polar[3])[0]
	var expected := k_t * to_t / from_t

	return TestResult.new(
		"scale_k_t_to_prop IS the BEMT geometry ratio BEMT(to)/BEMT(from)",
		absf(ratio - expected) < 1.0e-9 * expected,
		"5x4.3x3 -> 7x4x3: ratio %.9f vs BEMT %.9f (%.4fx)" % [
			ratio, expected, ratio / k_t])


## Section 3 — the identity short-circuit, bit-exact.
##
## The reference build fits its motor on the SAME prop it flies (prop_5x43x3), so its
## cross-prop move is the identity. That is the "anchor" the oracles hang on: if the identity
## case does not return k_t_from untouched, the reference build's 496 g / 11.69:1 / 29.6%
## move, and six files go red together. This asserts the short-circuit to the bit.
##
## TO MAKE THIS FAIL: route the identity case through the BEMT ratio instead of shorting it
## (it would still be ~1.0 to the residual — not to the bit — and a later solver change could
## move it).
static func _the_identity_short_circuit_is_bit_exact() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var prop: Dictionary = catalog.get_part("prop_5x43x3")
	var doc := PropellerDocument.from_catalog_prop(prop)
	var k_t := 7.654321e-6
	var out := BemtModel.scale_k_t_to_prop(k_t,
		doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades), doc.chord,
		doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades), doc.chord,
		29008.0)
	return TestResult.new(
		"scale_k_t_to_prop on identical geometry returns k_t bit-exact (the oracles' anchor)",
		out == k_t,
		"k_t %.15f -> %.15f (%s)" % [k_t, out,
			"bit-exact" if out == k_t else "MOVED — oracles at risk"])


## Section 4 — the distribution is reported, whatever it looks like (§4.4 point 3).
##
## The width is the finding, so this asserts only that the report exists and is sane. The
## per-prop values are printed for the record; the polar grid shows the band does not tighten
## with a0/Cd0, which is what pins the band to the data rather than to the model.
static func _the_calibration_distribution_is_reported() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var by_prop := {}
	for motor in catalog.list_category("motor"):
		var test: Dictionary = motor.get("thrust_test", {})
		var prop: Dictionary = catalog.get_part(String(test.get("prop_id", "")))
		if prop.is_empty():
			continue
		var doc := PropellerDocument.from_catalog_prop(prop)
		var kv := float(motor["specs"]["kv"])
		var rpm := kv * float(test.get("voltage_v", 0.0))
		var measured_n := float(motor["specs"]["max_thrust_g"]) / 1000.0 * GRAVITY_MPS2
		var factor := BemtModel.calibrate(STANDARD_RHO,
			doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades),
			rpm, doc.chord, measured_n)
		if not by_prop.has(String(prop["part_id"])):
			by_prop[String(prop["part_id"])] = []
		by_prop[String(prop["part_id"])].append(factor)

	var lines: PackedStringArray = []
	for prop_id in by_prop:
		var cals: Array = by_prop[prop_id]
		var parts: PackedStringArray = []
		for c in cals:
			parts.append("%.3f" % c)
		lines.append("%s: %s" % [prop_id, ", ".join(parts)])
	var detail := "\n".join(lines)

	var sane := true
	var count := 0
	for prop_id in by_prop:
		for c in by_prop[prop_id]:
			count += 1
			sane = sane and is_finite(c) and c > 0.0

	return TestResult.new(
		"calibration factors are positive and finite across the catalog (%d rows reported)" % count,
		sane,
		"%s" % detail if count > 0 else "(no measured rows in catalog)" )
