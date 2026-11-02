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

	var named := ["Molicel INR-21700-P42A", "Molicel INR-21700-P45B", "Samsung INR21700-40T", "VTC6", "A123"]
	var missing: Array = []
	for n in named:
		var hit := false
		for c in cells:
			if String(c.name).contains(n):
				hit = true
		if not hit:
			missing.append(n)
	results.append(_t("the named cells are present", missing.is_empty(), str(missing)))

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
