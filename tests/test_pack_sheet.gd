class_name TestPackSheet
extends RefCounted
## PackSheet: the buy-and-build text for a designed pack, in the style of the Airframe build sheet.
## Every number on it is read from the design (PackDesign.derive and the cell), never typed here.
##
## The checks that could have passed while proving nothing:
## - Cell and count are asserted against a design built HERE with known S, P and cell, with values
##   that cannot coincide (6S3P of a named Li-ion cell: 18 cells, 7 pins), so a sheet that printed
##   the default pack fails.
## - "expected figures equal derive()" compares to a fresh derive() of the same design, key by key.

const FORBIDDEN := ["tabletop", "hardware track", "our board", "lothal board", "dev board",
	"prototype board", "planned hardware", "upcoming hardware", "flight controller of ours"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _design(lib: CellLibrary, cell_id: String, s: int, p: int) -> PackDesign:
	var d := PackDesign.default_design(lib)
	d.cell = lib.get_cell(cell_id)
	d.series = s
	d.parallel = p
	d.name = "Sheet test pack"
	return d


static func one_text_for(lib: CellLibrary) -> String:
	return String(PackSheet.compose(_design(lib, "cell_lipo_1500", 4, 1))["balance_lead"]["text"])


static func run() -> Array:
	var results: Array = []
	var lib := CellLibrary.load_default()
	var d := _design(lib, "cell_molicel_p42a", 6, 3)
	var sheet := PackSheet.compose(d)
	var text := PackSheet.to_text(d)

	results.append(_t("sheet names cell model and S.P count",
		String(sheet["cells"]["model"]) == "Molicel INR-21700-P42A" and int(sheet["cells"]["count"]) == 18
		and String(sheet["arrangement"]) == "6S3P"
		and text.contains("Molicel INR-21700-P42A") and text.contains("18") and text.contains("6S3P"),
		str(sheet["cells"])))

	var bt4 := String(one_text_for(lib))
	results.append(_t("balance text counts S-1 junctions between cells and S+1 wires (4S: 3 junctions, 5 wires)",
		bt4.contains("5-pin") and bt4.contains("3 junctions") and not bt4.contains("4 series junctions")
		and String(sheet["balance_lead"]["text"]).contains("5 junctions") and text.contains("5 junctions"),
		bt4 + " | " + String(sheet["balance_lead"]["text"])))

	var order: Array = sheet["wiring_order"]
	results.append(_t("wiring order reads series then parallel",
		order.size() >= 2 and String(order[0]).begins_with("6S3P: 6 cells in series")
		and String(order[0]).contains("3 in parallel") and text.contains(String(order[0])),
		str(order)))
	var one := PackSheet.compose(_design(lib, "cell_lipo_1500", 4, 1))
	results.append(_t("a single-string pack says plain series",
		String((one["wiring_order"] as Array)[0]) == "4S1P: 4 cells in series", str(one["wiring_order"])))

	results.append(_t("balance lead has S+1 pins",
		int(sheet["balance_lead"]["pins"]) == 7 and String(sheet["balance_lead"]["connector"]) == "JST-XH"
		and int(one["balance_lead"]["pins"]) == 5 and text.contains("7-pin"), str(sheet["balance_lead"])))

	results.append(_t("includes the ideal / datasheet label and a safety note",
		String(sheet["label"]) == "ideal / datasheet" and text.contains("ideal / datasheet")
		and (sheet["safety"] as Array).size() >= 3 and text.to_lower().contains("fire")
		and text.to_lower().contains("polarity"), String(sheet["label"])))

	var f := d.derive()
	var same := true
	var diff := ""
	for k in f:
		if str((sheet["expected"] as Dictionary).get(k, null)) != str(f[k]):
			same = false
			diff = String(k)
	results.append(_t("expected figures equal derive()", same and (sheet["expected"] as Dictionary).size() == f.size(), diff))

	results.append(_t("lead and connector come from the design",
		String(sheet["connector"]["family"]) == d.connector_family
		and int(sheet["lead"]["awg"]) == d.lead_awg and float(sheet["lead"]["length_mm"]) == d.lead_length_mm
		and text.contains("%d AWG" % d.lead_awg) and text.contains(d.connector_family)))

	var d2 := _design(lib, "cell_lipo_1500", 4, 1)
	d2.connector_family = "XT90"
	d2.lead_awg = 12
	var s2 := PackSheet.compose(d2)
	results.append(_t("changing the wiring changes the sheet",
		String(s2["connector"]["family"]) == "XT90" and int(s2["lead"]["awg"]) == 12))

	var typ := PackSheet.compose(_design(lib, "cell_lipo_1500", 4, 1))
	var typ_text := PackSheet.to_text(_design(lib, "cell_lipo_1500", 4, 1))
	results.append(_t("a class-typical pack's sheet says typical",
		String(typ["label"]) == "typical" and typ_text.contains("Figures are typical") and not typ_text.contains("ideal / datasheet")
		and not typ_text.contains("est.)  burst") and not typ_text.contains("burst (est.)"), String(typ["label"])))
	results.append(_t("a pack whose cell burst is only an estimate says (est.) beside the burst figure",
		text.contains(" A burst (est.)") and not PackSheet.to_text(_design(lib, "cell_samsung_40t", 4, 1)).contains("(est.)"),
		text))

	var legacy := PackDesign.from_record(DesignedPacks.migrate_v1_record(
		PartsCatalog.load_default().get_part("battery_4s_1300")), lib)
	var lsheet := PackSheet.compose(legacy)
	var ltext := PackSheet.to_text(legacy)
	results.append(_t("legacy pack sheet says typed figures",
		String(lsheet["label"]) == PackDesign.LEGACY_BASIS and ltext.contains("typed figures")
		and not ltext.contains("ideal / datasheet"), String(lsheet["label"])))

	# The designer's actions: Copy returns (and clipboards) the same text; Save writes it to a file.
	var designer := PackDesigner.new(PartsCatalog.load_default(), lib, DesignedPacks.new(), PackCharge.new(), null)
	designer.open_new()
	var copied := designer.copy_specs()
	var path := "user://test_pack_sheet_out.txt"
	var wrote := designer.save_specs(path)
	var on_disk := FileAccess.get_file_as_string(path) if wrote else ""
	results.append(_t("the designer's Copy specs and Save as text give the sheet",
		copied == PackSheet.to_text(designer.design) and wrote and on_disk == copied
		and designer.copy_button.visible and designer.save_text_button.visible
		and copied.contains("PACK BUILD SHEET"), "wrote=%s" % wrote))
	designer.free()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var clean := true
	var hit := ""
	for w in FORBIDDEN:
		for body in [text.to_lower(), ltext.to_lower()]:
			if body.contains(String(w)):
				clean = false
				hit = String(w)
	results.append(_t("no planned-hardware words", clean, hit))
	return results
