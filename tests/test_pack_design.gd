class_name TestPackDesign
extends RefCounted
## PackDesign: cell x layout x wiring -> a catalog-shaped battery record. The designer and the
## drone read one pack model; this is the seam where the designer produces the shape Build eats.

const SCRATCH := "user://test_pack_design_scratch.json"


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _close(a: float, b: float, rel: float = 1e-9) -> bool:
	return absf(a - b) <= rel * maxf(absf(b), 1e-12)


static func run() -> Array:
	var results: Array = []
	var lib := CellLibrary.load_default()
	var d := PackDesign.default_design(lib)
	var f := d.derive()

	results.append(_t("default design derives a valid pack",
		d.series == 4 and d.parallel == 1 and d.connector_family == "XT60" and d.lead_awg == 14
		and d.lead_length_mm == 100.0 and float(f.mah) == 1500.0 and float(f.mass_g) > 0.0
		and float(f.internal_r_ohm) > 0.0 and String(f.basis) == "ideal / datasheet", str(f)))

	results.append(_t("4S1P pouch: nominal = 4 x chemistry nominal, mah = cell mah",
		_close(float(f.nominal_v), 4.0 * BatteryModel.nominal_cell_v("LiPo"))
		and _close(float(f.full_v), 4.0 * BatteryModel.max_cell_v("LiPo"))
		and _close(float(f.empty_v), 4.0 * BatteryModel.min_cell_v("LiPo"))
		and float(f.mah) == 1500.0, str(f)))

	var fe := PackDesign.default_design(lib)
	fe.cell = lib.get_cell("cell_a123_anr26650m1b")
	fe.series = 3
	var fef := fe.derive()
	results.append(_t("a LiFePO4 pack uses the cell's own nominal (A123: 3 x 3.3 V, not the 3.2 V chemistry default)",
		_close(float(fef.nominal_v), 3.0 * 3.3) and _close(float(fef.wh), 3.0 * 3.3 * 2.5)
		and _close(float(fe.to_record().specs.nominal_v), 9.9), str(fef.nominal_v)))
	var lp := PackDesign.default_design(lib)
	lp.cell = lib.get_cell("cell_lipo_1500")
	results.append(_t("a cell whose nominal equals its chemistry's changes nothing",
		_close(float(lp.derive().nominal_v), 4.0 * BatteryModel.nominal_cell_v("LiPo"))))

	var d2 := PackDesign.default_design(lib)
	d2.parallel = 2
	var f2 := d2.derive()
	var cell_r := float(d.cell.specs.r_mohm) / 1000.0
	results.append(_t("2P doubles mAh and halves the cell R share",
		float(f2.mah) == 3000.0
		and _close(float(f2.r_parts.cells), float(f.r_parts.cells) / 2.0)
		and _close(float(f.r_parts.cells), cell_r * 4.0)
		and _close(float(f2.cont_a), 2.0 * float(f.cont_a)), str(f2.r_parts)))

	var lead_r := 2.0 * WireGauge.resistance_ohm(14, 0.1)
	results.append(_t("pack R is cells plus the pigtail, nothing else",
		_close(float(f.internal_r_ohm), cell_r * 4.0 + lead_r)
		and _close(float(f.r_parts.lead), lead_r), "%s vs %s" % [f.internal_r_ohm, cell_r * 4.0 + lead_r]))

	var sum := 0.0
	for k in f.mass_parts:
		sum += float(f.mass_parts[k])
	results.append(_t("mass = sum of mass_parts",
		_close(float(f.mass_g), sum) and f.mass_parts.has("cells") and f.mass_parts.has("interconnect_wrap")
		and f.mass_parts.has("lead") and f.mass_parts.has("connector_half"), str(f.mass_parts)))
	var xt60_pair := 6.0
	results.append(_t("only the pack half of the connector is counted",
		_close(float(f.mass_parts.connector_half), xt60_pair * (1.0 - Harness.AIRCRAFT_SIDE_SHARE))
		and _close(float(f.mass_parts.lead), 2.0 * WireGauge.mass_g(14, 0.1)), str(f.mass_parts)))

	results.append_array(_harness_boundary(d))

	var rec := d.to_record()
	var scratch_doc := DesignedPacks.new()
	var problems := scratch_doc.add(rec)
	results.append(_t("record passes the DesignedPacks refusals", problems.is_empty(), str(problems)))
	results.append(_t("record is catalog-shaped",
		rec.specs.cells == 4 and rec.catalog.connector == "XT60" and rec.catalog.cell_class == "4S"
		and rec.mounting.attachment == "strap" and rec.category == "battery"
		and _close(float(rec.mass_g), float(f.mass_g))
		and _close(float(rec.specs.internal_r_ohm), float(f.internal_r_ohm))
		and _close(float(rec.specs.c_rating), float(f.cont_a) / 1.5)
		and rec.specs.chemistry == "LiPo" and rec.has("design"), str(rec.specs)))

	var back := PackDesign.from_record(rec, lib)
	var rt := back.to_record()
	results.append(_t("from_record(to_record()) round-trips",
		back.series == 4 and back.parallel == 1 and back.cell.cell_id == d.cell.cell_id
		and back.connector_family == "XT60" and back.lead_awg == 14 and back.name == d.name
		and not back.is_legacy() and JSON.stringify(rt) == JSON.stringify(rec), ""))

	var custom := CellLibrary.custom_cell("Bench cell", "Li-ion", 3000.0, 20.0, 30.0, 15.0, 48.0,
		Vector3(18.4, 65.0, 0.0), "cylindrical")
	var dc := PackDesign.default_design(lib)
	dc.cell = custom
	dc.series = 3
	dc.parallel = 2
	var crec := dc.to_record()
	var cback := PackDesign.from_record(crec, lib)
	results.append(_t("a custom-cell pack round-trips with its cell",
		cback.cell.basis == "custom" and absf(float(cback.cell.specs.mah) - 3000.0) < 1e-9
		and cback.series == 3 and cback.parallel == 2
		and JSON.stringify(cback.to_record()) == JSON.stringify(crec)
		and DesignedPacks.new().add(crec).is_empty(), ""))

	var legacy := PackDesign.new()
	legacy.name = "Typed"
	legacy.cell = custom
	legacy.legacy_specs = {"cells": 4, "nominal_v": 14.8, "mah": 1300.0, "internal_r_ohm": 0.011,
		"chemistry": "LiPo", "c_rating": 95.0, "length_mm": 77.0, "width_mm": 38.5, "height_mm": 27.0}
	legacy.legacy_mass_g = 155.0
	legacy.series = 4
	legacy.parallel = 1
	var lf := legacy.derive()
	var lrec := legacy.to_record()
	results.append(_t("a legacy design reports its typed figures untouched",
		legacy.is_legacy() and float(lf.mass_g) == 155.0 and float(lf.internal_r_ohm) == 0.011
		and float(lrec.mass_g) == 155.0 and JSON.stringify(lrec.specs) == JSON.stringify(legacy.legacy_specs),
		str(lf)))

	var bad := PackDesign.default_design(lib)
	bad.series = 0
	results.append(_t("series is clamped into the shelf's range", bad.derive().nominal_v > 0.0 and
		PackDesign.S_RANGE == Vector2i(1, 6) and PackDesign.P_RANGE == Vector2i(1, 4), ""))
	return results


## The designer's R must not carry the connector contact (the harness owns it), and the harness's
## trunk resistance must still include it for a designed pack.
static func _harness_boundary(d: PackDesign) -> Array:
	var out: Array = []
	var doc := DesignedPacks.new()
	var rec := d.to_record()
	var problems := doc.add(rec)
	if not problems.is_empty():
		out.append(_t("harness boundary: record accepted", false, str(problems)))
		return out
	doc.save(SCRATCH)
	var catalog := PartsCatalog.load_with_custom(SCRATCH)
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, String(rec.part_id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	var contact := float((HarnessChecks.connector_row(build).get("specs", {}) as Dictionary)
		.get("contact_resistance_ohm", 0.0)) * HarnessChecks.CONNECTOR_CONTACTS_IN_LOOP
	var trunk := HarnessChecks.trunk_resistance_ohm(build)
	var wire_only := trunk - contact
	var f := d.derive()
	var cells_plus_lead := float(f.r_parts.cells) + float(f.r_parts.lead)
	out.append(_t("pack R excludes connector contact (harness owns it)",
		contact > 0.0 and trunk > wire_only and wire_only > 0.0
		and _close(float(build.battery.specs.internal_r_ohm), cells_plus_lead)
		and _close(float(f.connector_contact_r_ohm_info), contact),
		"contact %s trunk %s pack R %s" % [contact, trunk, build.battery.specs.internal_r_ohm]))
	out.append(_t("the build flies the derived pack's mass and cell count",
		_close(float(build.battery.mass_g), float(f.mass_g)) and int(build.battery.specs.cells) == 4, ""))
	return out
