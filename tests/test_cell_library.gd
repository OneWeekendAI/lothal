class_name TestCellLibrary
extends RefCounted
## The named cell library behind the pack designer: every cell must be a real, citable thing.

const BASES := ["datasheet", "class-typical"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func run() -> Array:
	var results: Array = []
	var lib := CellLibrary.load_default()
	var cells := lib.cells()
	results.append(_t("the library holds cells", cells.size() >= 10, "%d cells" % cells.size()))

	var bad_chem: Array = []
	var bad_src: Array = []
	var bad_num: Array = []
	var seen := {}
	var dup: Array = []
	for c in cells:
		var id := String(c.get("cell_id", ""))
		if seen.has(id) or id == "":
			dup.append(id)
		seen[id] = true
		if not BatteryModel.is_known_chemistry(String(c.get("chemistry", ""))):
			bad_chem.append(id)
		if String(c.get("source", "")).strip_edges() == "" or not BASES.has(String(c.get("basis", ""))):
			bad_src.append(id)
		var s: Dictionary = c.get("specs", {})
		for k in ["mah", "r_mohm", "mass_g", "max_cont_a", "max_burst_a", "nominal_v"]:
			if float(s.get(k, 0.0)) <= 0.0:
				bad_num.append("%s.%s" % [id, k])
		var dims: Array = ["diameter_mm", "length_mm"] if c.get("form") == "cylindrical" \
			else ["length_mm", "width_mm", "thickness_mm"]
		for k in dims:
			if float(s.get(k, 0.0)) <= 0.0:
				bad_num.append("%s.%s" % [id, k])
		if float(s.get("max_burst_a", 0.0)) < float(s.get("max_cont_a", 0.0)):
			bad_num.append("%s burst<cont" % id)
		if not ["cylindrical", "pouch"].has(String(c.get("form", ""))):
			bad_num.append("%s form" % id)
	results.append(_t("every cell names a known chemistry", bad_chem.is_empty(), str(bad_chem)))
	results.append(_t("every cell cites a source and a basis", bad_src.is_empty(), str(bad_src)))
	results.append(_t("cell ids are unique and non-empty", dup.is_empty(), str(dup)))
	results.append(_t("positive mah/r/mass/dims", bad_num.is_empty(), str(bad_num)))

	for chem in BatteryModel.known_chemistries():
		results.append(_t("chemistry %s has at least one cell" % chem,
			lib.by_chemistry(chem).size() >= 1, ""))

	var found := false
	for c in lib.by_chemistry("LiPo"):
		if absf(float(c.specs.mah) - 1500.0) < 1.0 and c.form == "pouch":
			found = true
	results.append(_t("a 1500 mAh-class LiPo pouch exists for the default pack", found, ""))

	var some: Dictionary = lib.get_cell("cell_molicel_p42a")
	results.append(_t("get_cell returns a record by id, empty for unknown",
		not some.is_empty() and lib.get_cell("nope").is_empty(), ""))

	var named := ["Molicel INR-21700-P42A", "Molicel INR-21700-P45B", "Samsung INR21700-40T", "VTC6", "A123",
		"Samsung INR21700-50S", "Molicel INR-18650-P28A", "VTC5A"]
	var missing: Array = []
	for n in named:
		var hit := false
		for c in cells:
			if String(c.name).contains(n):
				hit = true
		if not hit:
			missing.append(n)
	results.append(_t("the named cells are present", missing.is_empty(), str(missing)))


	# Datasheet corrections (cell_check 2026-11): figures pinned to the published sheets.
	var chk := {
		"cell_a123_anr26650m1b": {"max_cont_a": 50.0},
		"cell_molicel_p42a": {"r_mohm": 10.0, "diameter_mm": 21.4, "length_mm": 70.0},
		"cell_molicel_p45b": {"diameter_mm": 21.4, "length_mm": 70.0},
		"cell_samsung_40t": {"r_mohm": 12.0},
	}
	var wrong: Array = []
	for cid in chk:
		var rec: Dictionary = lib.get_cell(cid)
		for k in chk[cid]:
			if absf(float(rec.get("specs", {}).get(k, -1.0)) - float(chk[cid][k])) > 1e-9:
				wrong.append("%s.%s" % [cid, k])
	results.append(_t("datasheet-corrected figures match the published sheets", wrong.is_empty(), str(wrong)))
	var unflagged: Array = []
	for cid in ["cell_molicel_p42a", "cell_molicel_p45b"]:
		if String(lib.get_cell(cid).get("burst_basis", "")) != "estimate":
			unflagged.append(cid)
	results.append(_t("Molicel burst figures are flagged as unverified estimates", unflagged.is_empty(), str(unflagged)))

	# Cells added with cited sources (2026-11), and the figures sourced for the gaps.
	var added := {
		"cell_samsung_50s": {"mah": 5000.0, "max_cont_a": 20.0, "max_burst_a": 45.0, "r_mohm": 14.0},
		"cell_molicel_p28a": {"mah": 2800.0, "max_cont_a": 35.0, "r_mohm": 20.0},
		"cell_murata_vtc5a": {"mah": 2600.0, "max_cont_a": 35.0, "mass_g": 44.9},
		"cell_molicel_p45b": {"r_mohm": 7.0},
		"cell_murata_vtc6": {"r_mohm": 13.0},
		"cell_samsung_40t": {"max_burst_a": 45.0, "diameter_mm": 21.22, "length_mm": 70.3},
	}
	var off: Array = []
	for cid in added:
		var rec2: Dictionary = lib.get_cell(cid)
		for k in added[cid]:
			if absf(float(rec2.get("specs", {}).get(k, -1.0)) - float(added[cid][k])) > 1e-9:
				off.append("%s.%s" % [cid, k])
	results.append(_t("added and newly sourced cell figures match their cited sheets", off.is_empty(), str(off)))
	var unsourced: Array = []
	for cid in ["cell_samsung_50s", "cell_molicel_p28a", "cell_murata_vtc5a", "cell_molicel_p45b", "cell_murata_vtc6", "cell_samsung_40t"]:
		var src := String(lib.get_cell(cid).get("source", ""))
		if not (src.contains("mOhm") or src.contains("impedance")) or not (src.contains("data sheet") or src.contains("specification")):
			unsourced.append(cid)
	results.append(_t("each of them cites what it was read from", unsourced.is_empty(), str(unsourced)))
	var est: Array = []
	if String(lib.get_cell("cell_molicel_p28a").get("burst_basis", "")) != "estimate":
		est.append("p28a burst")
	if String(lib.get_cell("cell_murata_vtc5a").get("burst_basis", "")) != "estimate":
		est.append("vtc5a burst")
	if String(lib.get_cell("cell_murata_vtc5a").get("r_basis", "")) != "estimate":
		est.append("vtc5a r")
	for cid in ["cell_samsung_50s", "cell_samsung_40t", "cell_murata_vtc6", "cell_molicel_p45b"]:
		if lib.get_cell(cid).has("r_basis"):
			est.append("%s r flagged" % cid)
	for cid in ["cell_samsung_50s", "cell_samsung_40t"]:
		if lib.get_cell(cid).has("burst_basis"):
			est.append("%s burst flagged" % cid)
	results.append(_t("figures a sheet does not publish are marked estimate, published ones are not", est.is_empty(), str(est)))

	var cc := CellLibrary.custom_cell("Mine", "Li-ion", 3000.0, 20.0, 30.0, 15.0, 48.0,
		Vector3(18.4, 65.0, 0.0), "cylindrical")
	results.append(_t("custom_cell builds a record flagged custom",
		cc.basis == "custom" and cc.chemistry == "Li-ion" and float(cc.specs.mah) == 3000.0
		and absf(float(cc.specs.diameter_mm) - 18.4) < 1e-5, str(cc)))
	var r_li := CellLibrary.custom_cell_r_ohm("Li-ion", 3000.0, 10.0)
	var r_lipo := CellLibrary.custom_cell_r_ohm("LiPo", 1500.0, 75.0)
	# K = r_mohm * Ah * C  ->  r_ohm = K / (Ah * C) / 1000
	results.append(_t("custom_cell_r_ohm uses the pinned K per chemistry",
		absf(r_li - 1229.0 / (3.0 * 10.0) / 1000.0) < 1e-12
		and absf(r_lipo - 336.0 / (1.5 * 75.0) / 1000.0) < 1e-12, "%s %s" % [r_li, r_lipo]))
	return results
