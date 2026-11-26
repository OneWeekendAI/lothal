class_name TestDesignBuildSheet
extends RefCounted
## "Export build sheet…" of the Design Space: the sheet is a reading of the session's Build, and every figure on
## it is parsed back off the written file and compared with the Build method that owns it.

const CLASS_ID := "five_inch"
const PATH := "user://test_design_build_sheet.md"


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var s := DesignSession.default_for_class(CLASS_ID)
	var b := s.build(catalog)
	out.append(TestResult.new("the menu entry is live", ProjectMenu.is_live("export_build_sheet"), ""))
	out.append(TestResult.new("the default file name is '<project> build sheet.md'",
		DesignBuildSheet.default_name('Weekend 5"/v2') == "Weekend 5__v2 build sheet.md"
		and DesignBuildSheet.default_name("") == "Untitled build sheet.md", DesignBuildSheet.default_name("")))
	var wrote := DesignBuildSheet.write(s, catalog, "My quad", PATH, "2026-11-27")
	out.append(TestResult.new("writing produces a file", wrote and FileAccess.file_exists(PATH), ""))
	var text := FileAccess.get_file_as_string(PATH)
	DirAccess.remove_absolute(PATH)
	out.append(TestResult.new("a bad path degrades to false", not DesignBuildSheet.write(s, catalog, "x",
		"/nonexistent_dir_zz/a.md", "d"), ""))

	out.append(TestResult.new("the header names project, class, date and version",
		text.begins_with("# Build sheet — My quad") and text.contains("- Date: 2026-11-27")
		and text.contains("- Lothal version: %s" % LothalVersion.CURRENT)
		and text.contains("- Class: %s" % String(DroneClass.by_id(CLASS_ID).get("name", ""))), ""))

	var r := DesignSession.readouts_of(b)
	r["can_hover"] = b.can_hover()
	var lines := text.split("\n")
	var auw_line := "- Weight: %s" % ("%.1f g" % b.all_up_weight_g())
	out.append(TestResult.new("the Weight line is the readout's text",
		lines.has(auw_line) and auw_line.ends_with(DesignSpace.format_readout("auw_g", r)), auw_line))
	var expected := {"Thrust : weight": "%.2f : 1" % b.thrust_to_weight(),
		"Hover": "%.1f %%" % (b.hover_throttle() * 100.0),
		"Flight (est.)": "%.1f min" % b.flight_time_min(),
		"Top speed (est.)": "%.0f km/h" % b.top_speed_kmh()}
	for caption in expected:
		out.append(TestResult.new("%s equals its Build method" % caption,
			lines.has("- %s: %s" % [caption, expected[caption]]), expected[caption]))
	var lim := b.limiting_component()
	out.append(TestResult.new("the current cap is the limiting component's",
		text.contains("- Current cap: %s, %.0f A, %.0f %% throttle" % [lim["label"], float(lim["amps"]),
		float(lim["throttle"]) * 100.0]), ""))

	# Parts: parse the table back. The rows are grouped from Build.mass_parts(); there is no derived row, so the
	# SUM of the printed rows is checked against the Weight readout independently of the Total cell.
	var sum := 0.0
	var data_rows := 0
	var total_cell := ""
	for line in lines:
		if line.begins_with("| ") and line.ends_with(" |"):
			var cells := line.split("|")
			var mass_cell := cells[4].strip_edges()
			if cells[1].strip_edges() == "**Total**":
				total_cell = mass_cell
			elif mass_cell.ends_with(" g"):
				sum += float(mass_cell.trim_suffix(" g"))
				data_rows += 1
	out.append(TestResult.new("no row is derived by subtraction", not text.contains("derived"), ""))
	out.append(TestResult.new("the parts table's total is the Weight readout",
		total_cell == "**%s**" % DesignSpace.format_readout("auw_g", r), total_cell))
	out.append(TestResult.new("the printed rows sum to the Weight readout (print rounding only)",
		absf(sum - b.all_up_weight_g()) <= 0.05 * float(data_rows) + 0.05, "%.2f vs %.2f" % [sum, b.all_up_weight_g()]))
	var exact := 0.0
	for row in DesignBuildSheet.part_rows(s, catalog, b):
		exact += float(row["mass_g"])
	out.append(TestResult.new("the rows' exact masses sum to all_up_weight_g (display rounding of the readout)",
		absf(exact - b.all_up_weight_g()) < 0.05, "%.4f vs %.4f" % [exact, b.all_up_weight_g()]))
	var kinds := {}
	for row in DesignBuildSheet.part_rows(s, catalog, b):
		kinds[row["category"]] = true
	out.append(TestResult.new("the rows include the split harness rows and no 'other' bucket on the default build",
		kinds.has("wiring") and kinds.has("connector") and kinds.has("sundries") and not kinds.has("wiring / harness") and kinds.has("motor + propeller") and not kinds.has("other"), str(kinds.keys())))
	out.append(TestResult.new("each fitted part's mass is its catalog mass times its count",
		text.contains("| motor + propeller | %s + %s | 4 | %.1f g |" % [b.motor["name"], b.propeller["name"], (float(b.motor["mass_g"]) + float(b.propeller["mass_g"])) * 4.0]), ""))

	# Source is one of three short words; harness rows carry their chosen part's name.
	var sources_ok := true
	var connector_named := false
	for row in DesignBuildSheet.part_rows(s, catalog, b):
		if not (row["source"] in ["catalog", "custom", "est."]):
			sources_ok = false
		if row["category"] == "connector" and String(row["name"]) == String(b.harness.connector_row(b).get("name", "?")) \
				and String(row["name"]) != "none":
			connector_named = true
	out.append(TestResult.new("Source values are only catalog/custom/est.", sources_ok, ""))
	out.append(TestResult.new("the connector row names the harness's connector", connector_named
		and text.contains("| connector | %s | 1 |" % String(b.harness.connector_row(b).get("name", "?"))), ""))
	out.append(TestResult.new("the default strap is shown as unchosen inside the sundries row",
		text.contains("| sundries | Default strap + ") and text.contains("| est. |"), ""))
	# Mutation: dropping the connector row must break the independent sum.
	var no_conn := 0.0
	for row in DesignBuildSheet.part_rows(s, catalog, b):
		if row["category"] != "connector":
			no_conn += float(row["mass_g"])
	out.append(TestResult.new("mutation: a sheet without the connector row no longer sums to the Weight",
		absf(no_conn - b.all_up_weight_g()) > 0.05, "%.3f vs %.3f" % [no_conn, b.all_up_weight_g()]))

	# Warnings: every Build warning sentence, in order, and nothing else under the heading.
	var heavy := DesignSession.default_for_class(CLASS_ID)
	heavy.set_part("propeller", _oversize_prop(catalog, heavy))
	var hb := heavy.build(catalog)
	var htext := DesignBuildSheet.compose(heavy, catalog, "Heavy", "d")
	var want: Array = []
	for w in hb.warnings():
		want.append("- [%s] %s" % [BuildWarning.severity_name(w.severity), w.message])
	var got: Array = []
	var in_warnings := false
	for line in htext.split("\n"):
		if line.begins_with("## "):
			in_warnings = line == "## Warnings"
		elif in_warnings and line.begins_with("- ["):
			got.append(line)
	out.append(TestResult.new("the warnings listed are Build.warnings() exactly",
		not want.is_empty() and got == want, "%d vs %d" % [got.size(), want.size()]))

	# A custom part says "custom".
	var cs := DesignSession.default_for_class(CLASS_ID)
	var mine: Dictionary = (catalog.get_part(String(cs.selection["motor"])) as Dictionary).duplicate(true)
	mine["part_id"] = "custom_sheet_motor"
	mine["name"] = "My motor"
	catalog.by_id["custom_sheet_motor"] = mine
	cs.selection["motor"] = "custom_sheet_motor"
	var ctext := DesignBuildSheet.compose(cs, catalog, "Custom", "d")
	out.append(TestResult.new("a custom part's source reads 'custom'",
		ctext.contains("| motor + propeller | My motor + ") and ctext.contains("| custom |"), ""))
	out.append(TestResult.new("a catalog part's source is not 'custom'",
		not text.contains("| custom |"), ""))
	catalog.by_id.erase("custom_sheet_motor")

	# Frame edits and harness.
	out.append(TestResult.new("an unedited frame says so", text.contains("- Edits: none"), ""))
	var h := b.harness
	out.append(TestResult.new("the harness lines are the Harness's own",
		text.contains("- Harness mass: %.1f g" % h.total_mass_g(b))
		and text.contains("- Straps: %s x %d" % [String(h.strap_row(b).get("name", "none")), h.strap_count(b)]), ""))

	# An edited frame: the sheet's frame row is the FLOWN mass and the edit line carries the mass delta.
	var es := DesignSession.default_for_class(CLASS_ID)
	var doc := es.frame_document()
	var fl := es.plate_of_mesh("frame_arm_FL")
	var at := AirframeDocument.point_of(doc.motors[0]["position_mm"]).normalized() * 91.0
	var verdict := es.drill(fl, at, 3.0)
	var eb := es.build(catalog)
	var edit := es.frame_edit(catalog)
	var etext := DesignBuildSheet.compose(es, catalog, "Edited", "d")
	out.append(TestResult.new("an edited frame reports its mass delta and flown mass",
		verdict["ok"] and not edit.is_empty()
		and etext.contains("mass %+.1f g against the published frame" % float(edit["drawn_delta_g"]))
		and etext.contains("| frame | %s | 1 | %.1f g |" % [eb.frame["name"], eb.frame_mass_g() - float(edit["drawn_delta_g"])])
		and etext.contains("| frame edits |") and absf(_sum_of(es, catalog) - eb.all_up_weight_g()) < 0.05,
		"%s %s" % [verdict, edit]))
	return out


static func _sum_of(s: DesignSession, catalog: PartsCatalog) -> float:
	var total := 0.0
	for row in DesignBuildSheet.part_rows(s, catalog, s.build(catalog)):
		total += float(row["mass_g"])
	return total


## Any catalog propeller the five-inch frame cannot clear, so the build has an impossible warning.
static func _oversize_prop(catalog: PartsCatalog, s: DesignSession) -> String:
	var limit := float(s.build(catalog).frame["specs"]["max_prop_inches"])
	for part in catalog.list_category("propeller"):
		if float(part["specs"]["diameter_inches"]) > limit:
			return String(part["part_id"])
	return String(s.selection["propeller"])
