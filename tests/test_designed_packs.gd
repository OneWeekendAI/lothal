class_name TestDesignedPacks
extends RefCounted
## DesignedPacks: custom_parts.json schema 2, designed packs and the lossless migration of the
## v1 hand-typed battery records.

const FIXTURE := "res://tests/fixtures/custom_parts_v1_batteries.json"
const SCRATCH := "user://test_designed_packs_scratch.json"
const CHARGE := "user://test_designed_packs_charge.json"

const CHAIN_IDS := ["custom_shed_4s_1300", "custom_long_range_6s", "custom_whoop_1s"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _fixture_text() -> String:
	return FileAccess.get_file_as_string(FIXTURE)


static func _stage() -> String:
	_wipe(SCRATCH)
	var h := FileAccess.open(SCRATCH, FileAccess.WRITE)
	h.store_string(_fixture_text())
	h.close()
	return SCRATCH


static func run() -> Array:
	var results: Array = []
	results.append_array(_migration())
	results.append_array(_flies_identically())
	results.append_array(_files())
	results.append_array(_charge_rules())
	results.append_array(_unknown_and_chemistry())
	_wipe(SCRATCH)
	_wipe(CHARGE)
	return results


static func _migration() -> Array:
	var out: Array = []
	var raw: Dictionary = JSON.parse_string(_fixture_text())
	var path := _stage()
	var doc := DesignedPacks.load_from(path)
	var same := doc.records().size() == (raw.batteries as Array).size()
	var detail := ""
	for want in raw.batteries:
		var got := doc.get_record(String(want.part_id))
		if got.is_empty() or JSON.stringify(got.specs) != JSON.stringify(want.specs) \
				or float(got.mass_g) != float(want.mass_g) or got.name != want.name \
				or JSON.stringify(got.catalog) != JSON.stringify(want.catalog):
			same = false
			detail += " " + String(want.part_id)
	out.append(_t("v1 battery records load with identical specs and mass", same, detail))

	var legacy_ok := true
	for rec in doc.records():
		var design: Dictionary = rec.get("design", {})
		legacy_ok = legacy_ok and bool(design.get("legacy", false)) \
			and String(design.get("basis", "")) == "legacy (typed figures)" \
			and int(design.series) == int(rec.specs.cells) and int(design.parallel) == 1 \
			and (design.get("custom_cell", {}) as Dictionary).has("specs")
	out.append(_t("migrated records are marked legacy with a custom cell", legacy_ok, ""))

	var lib := CellLibrary.load_default()
	var designs := doc.designs(lib)
	var all_legacy := designs.size() == 3
	for d in designs:
		all_legacy = all_legacy and d.is_legacy() and JSON.stringify(d.to_record().specs) \
			== JSON.stringify(doc.get_record(d.part_id).specs)
	out.append(_t("designs() gives legacy designs that reproduce the typed specs", all_legacy, ""))

	var rebuilt := designs[0]
	var before := float(rebuilt.derive().mass_g)
	rebuilt.rebuild_from_cells()
	out.append(_t("rebuild_from_cells turns a legacy pack into a derived one",
		not rebuilt.is_legacy() and float(rebuilt.derive().mass_g) != before, ""))
	return out


## Figures of the three v1 fixture packs, FROZEN from the retired v1 custom-pack path (captured the
## day before it was deleted): [AUW g, T/W, hover throttle, flight min, top km/h, R ohm, pack mass g].
## Re-pinned at the DC-law motor re-baseline, and again at the prop chapter (k_t and k_q from BEMT, 2026-11-04): hover, flight time, top speed and the non-reference packs' T/W
## moved with the motor law; AUW, R and mass are as captured.
## Flight-time column (index 3) re-pinned a third time at SR1-SR2 (2026-11-09): forward flight now costs rear-rotor interference
## (up to +9.5 % power in the 5-15 m/s window), directional drag and profile-power growth (1+4.65 mu^2), less the translational lift
## the old thrust-ratio cap threw away. shed_4s_1300 8.361 -> 6.864 min (-17.9 %, the same cut as battery_4s_1300 in
## test_preset_pack_pin: 8.363 -> 6.865, and the 0.02 % gap between the two packs is unchanged); long_range_6s 16.073 -> 15.367 (-4.4 %,
## a high-resistance Li-ion pack, which moves least, as the preset battery_6s_4000_liion does: 15.13 -> 15.02, -0.7 %; mechanism not isolated). Every other column
## (AUW, T:W, hover throttle, top speed, R, mass) is unchanged to 1e-9, so hover physics did not move.
const V1_GOLDEN := {
	"custom_shed_4s_1300": [477.480708465516, 8.64188216420273, 0.31956843668757,
		6.86398367309389, 104.940833999123, 0.0113, 155.0],
	"custom_long_range_6s": [944.980708465516, 8.61511446938397, 0.34437748810877,
		15.3669031649656, 147.631172121907, 0.2345, 612.5],
	"custom_whoop_1s": [327.030708465516, 0.91282443245776, 1.0,
		0.0, 46.9173887685779, 0.0721, 9.5],
}
const V1_GOLDEN_SPECS := {
	"custom_shed_4s_1300": {"c_rating": 95.0, "cells": 4.0, "chemistry": "LiPo", "height_mm": 27.0,
		"internal_r_ohm": 0.0113, "length_mm": 77.0, "mah": 1300.0, "nominal_v": 14.8, "width_mm": 38.5},
	"custom_long_range_6s": {"c_rating": 8.0, "cells": 6.0, "chemistry": "Li-ion", "height_mm": 44.0,
		"internal_r_ohm": 0.2345, "length_mm": 80.0, "mah": 4200.0, "nominal_v": 21.6, "width_mm": 66.0},
	"custom_whoop_1s": {"c_rating": 50.0, "cells": 1.0, "chemistry": "LiPo", "height_mm": 7.0,
		"internal_r_ohm": 0.0721, "length_mm": 60.0, "mah": 450.0, "nominal_v": 3.7, "width_mm": 16.0},
}


static func _flies_identically() -> Array:
	var out: Array = []
	var v2 := PartsCatalog.load_with_custom(_stage())
	var bad := ""
	for id in CHAIN_IDS:
		var b := Build.from_ids(v2, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, id)
		var fb: Array = [b.all_up_weight_g(), b.thrust_to_weight(), b.hover_throttle(),
			b.flight_time_min(), b.top_speed_kmh(), float(b.battery.specs.internal_r_ohm),
			float(b.battery.mass_g)]
		var gold: Array = V1_GOLDEN[id]
		for k in gold.size():
			if absf(float(fb[k]) - float(gold[k])) > 1e-9 * maxf(absf(float(gold[k])), 1.0):
				bad += " %s[%d] %s vs %s" % [id, k, fb[k], gold[k]]
		var want: Dictionary = V1_GOLDEN_SPECS[id]
		for key in want:
			if absf(float(b.battery.specs.get(key, -1)) - float(want[key])) > 1e-9 and String(key) != "chemistry":
				bad += " %s.%s" % [id, key]
		if String(b.battery.specs.get("chemistry", "")) != String(want["chemistry"]):
			bad += " %s.chemistry" % id
	out.append(_t("migrated pack flies as the v1 path did (frozen golden table)", bad == "", bad))
	out.append(_t("the merged catalog carries the migrated packs",
		v2.get_part("custom_shed_4s_1300").has("design"), ""))
	return out


static func _files() -> Array:
	var out: Array = []
	var path := _stage()
	var before := FileAccess.get_file_as_string(path)
	var doc := DesignedPacks.load_from(path)
	doc.designs(CellLibrary.load_default())
	out.append(_t("loading a v1 file does not rewrite it",
		FileAccess.get_file_as_string(path) == before, ""))
	out.append(_t("CustomParts is at schema 4", CustomParts.SCHEMA_VERSION == 4, ""))
	var charge := PackCharge.new()
	var d := doc.designs(CellLibrary.load_default())[0]
	d.name = "Shed 4S 1300 renamed"
	var id := doc.save_design(d, charge, d.part_id)
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ids: Array = []
	for r in written.batteries:
		ids.append(r.part_id)
	out.append(_t("save writes schema 4, keeps ids and other blocks",
		int(written.schema) == 4 and id == "custom_shed_4s_1300" and ids == CHAIN_IDS
		and written.has("x_future_block") and written.has("frames"), str(ids)))
	return out


## JSON text keeps ~14 significant digits, so a reloaded float may differ in the last bit.
static func _specs_close(a: Dictionary, b: Dictionary) -> bool:
	var ka := a.keys()
	var kb := b.keys()
	ka.sort()
	kb.sort()
	if ka != kb:
		return false
	for k in a:
		if a[k] is String:
			if a[k] != b[k]:
				return false
		elif absf(float(a[k]) - float(b[k])) > 1e-9 * maxf(absf(float(b[k])), 1.0):
			return false
	return true


static func _fresh_design(lib: CellLibrary, name: String) -> PackDesign:
	var d := PackDesign.default_design(lib)
	d.name = name
	return d


static func _charge_rules() -> Array:
	var out: Array = []
	_wipe(SCRATCH)
	_wipe(CHARGE)
	var lib := CellLibrary.load_default()
	var doc := DesignedPacks.load_from(SCRATCH)
	var charge := PackCharge.load_from(CHARGE)
	var d := _fresh_design(lib, "Rule Pack")
	var id := doc.save_design(d, charge)
	out.append(_t("a new pack saves under a custom_ id", id == "custom_rule_pack"
		and doc.get_record(id).name == "Rule Pack", id))
	charge.set_used_mah(id, 400.0)

	# rename keeps charge and id
	d.name = "Rule Pack Renamed"
	var id_r := doc.save_design(d, charge, id)
	out.append(_t("a rename keeps the id and the charge",
		id_r == id and is_equal_approx(charge.used_mah(id), 400.0)
		and doc.get_record(id).name == "Rule Pack Renamed", ""))

	# resave unchanged keeps charge
	doc.save_design(d, charge, id)
	out.append(_t("saving with no electrical change keeps the charge",
		is_equal_approx(charge.used_mah(id), 400.0), ""))

	# edit S resets
	d.series = 5
	doc.save_design(d, charge, id)
	out.append(_t("editing S resets charge to full under the same id",
		charge.used_mah(id) == 0.0 and doc.get_record(id).specs.cells == 5, ""))

	charge.set_used_mah(id, 300.0)
	d.parallel = 2
	doc.save_design(d, charge, id)
	out.append(_t("editing P resets charge", charge.used_mah(id) == 0.0, ""))

	charge.set_used_mah(id, 300.0)
	d.cell = lib.get_cell("cell_lipo_1300")
	doc.save_design(d, charge, id)
	out.append(_t("changing the cell resets charge", charge.used_mah(id) == 0.0, ""))

	charge.set_used_mah(id, 300.0)
	d.lead_awg = 12
	doc.save_design(d, charge, id)
	out.append(_t("changing only the wiring keeps charge",
		is_equal_approx(charge.used_mah(id), 300.0), ""))

	# save as
	var new_id := doc.save_as(d, charge)
	out.append(_t("save_as creates a new id at full charge and leaves the original alone",
		new_id != id and new_id != "" and charge.used_mah(new_id) == 0.0
		and is_equal_approx(charge.used_mah(id), 300.0)
		and not doc.get_record(new_id).is_empty() and not doc.get_record(id).is_empty(), new_id))
	out.append(_t("a second save_as on the same name gets yet another id",
		doc.save_as(d, charge) not in [id, new_id], ""))

	# survives a reload, and the refusals still bite
	var again := DesignedPacks.load_from(SCRATCH)
	out.append(_t("saved designs reload as the same derived pack",
		again.designs(lib).size() == 3 and not again.get_record(id).is_empty()
		and _specs_close(again.get_record(id).specs, doc.get_record(id).specs), ""))
	var broken := _fresh_design(lib, "Broken")
	broken.lead_length_mm = 100.0
	broken.cell = {}
	out.append(_t("a design with no cell is refused and nothing is stored",
		doc.save_design(broken, charge) == "" and doc.get_record("custom_broken").is_empty(), ""))
	return out


static func _unknown_and_chemistry() -> Array:
	var out: Array = []
	var path := _stage()
	var lib := CellLibrary.load_default()
	var doc := DesignedPacks.load_from(path)
	var charge := PackCharge.new()
	var d := doc.designs(lib)[0]
	d.name = "Shed edited"
	doc.save_design(d, charge, d.part_id)
	var again := DesignedPacks.load_from(path)
	var rec := again.get_record("custom_shed_4s_1300")
	out.append(_t("unknown fields survive a round trip at schema 2",
		rec.get("x_note_from_the_future", {}) == {"tag": "keep"} and rec.name == "Shed edited"
		and JSON.stringify(rec.specs) == JSON.stringify(doc.get_record("custom_shed_4s_1300").specs), str(rec.keys())))

	var raw: Dictionary = JSON.parse_string(_fixture_text())
	raw.batteries[0].specs.chemistry = "Unobtainium"
	_wipe(SCRATCH)
	var h := FileAccess.open(SCRATCH, FileAccess.WRITE)
	h.store_string(JSON.stringify(raw))
	h.close()
	var bad := DesignedPacks.load_from(SCRATCH)
	var loud := false
	for r in bad.rejections():
		if r.contains("Unobtainium"):
			loud = true
	out.append(_t("a migrated record with an unknown chemistry is rejected loudly",
		loud and bad.get_record("custom_shed_4s_1300").is_empty() and bad.records().size() == 2,
		str(bad.rejections())))

	var every_known := true
	for r in DesignedPacks.load_from(_stage()).records():
		every_known = every_known and BatteryModel.is_known_chemistry(String(r.specs.chemistry))
	out.append(_t("every migrated chemistry is known", every_known, ""))
	return out
