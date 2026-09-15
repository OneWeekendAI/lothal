class_name TestFabrication
extends RefCounted
## Printable vs bought, per catalog entry — printed-room slice PR9 (track.md W1P.2).
##
## Where each check could pass while proving nothing, and what stops it:
##   - No catalog entry publishes `fabrication` today, and none may be invented. So every rule is checked
##     on DUPLICATED entries carrying the flag, beside the real entry without it; a check run only on the
##     shipped catalog would see "absent" everywhere and pass any rule.
##   - "a bought guard is not exported" needs the absent-flag guard beside it that IS exported, or a row
##     stuck at "not exportable" would pass.
##   - "a printed frame is exported" checks the solid is the frame export's own tessellation (same facet
##     count as FrameExport.to_stl), so a stand-in box fails.


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append(_the_flag_reads_three_values_and_nothing_else())
	results.append(_no_shipped_entry_invents_a_flag(catalog))
	results.append_array(_a_guards_flag_decides_its_export(catalog))
	results.append_array(_a_frame_is_listed_only_when_printable(catalog))
	return results


static func _the_flag_reads_three_values_and_nothing_else() -> TestResult:
	var read := [
		PartsCatalog.fabrication_of({"fabrication": "printed"}),
		PartsCatalog.fabrication_of({"fabrication": "bought"}),
		PartsCatalog.fabrication_of({"fabrication": "either"}),
		PartsCatalog.fabrication_of({"fabrication": "moulded"}),
		PartsCatalog.fabrication_of({"fabrication": 3}),
		PartsCatalog.fabrication_of({}),
	]
	return TestResult.new("fabrication reads printed / bought / either, and an unknown or absent value reads as unstated",
		read == ["printed", "bought", "either", "", "", ""], "%s" % [read])


static func _no_shipped_entry_invents_a_flag(catalog: PartsCatalog) -> TestResult:
	var flagged: Array = []
	var seen := 0
	for category in PartsCatalog.CATEGORY_FILES:
		for part in catalog.list_category(category):
			seen += 1
			if (part as Dictionary).has("fabrication"):
				flagged.append(part["part_id"])
	return TestResult.new("no shipped catalog entry carries a fabrication flag nobody published",
		seen > 50 and flagged.is_empty(), "%d entries read, flagged %s" % [seen, flagged])


static func _guard_row(build: Build) -> Dictionary:
	for row in PrintedParts.for_build(build):
		if String(row["id"]) == PrintedParts.PROP_GUARD:
			return row
	return {}


static func _a_guards_flag_decides_its_export(catalog: PartsCatalog) -> Array:
	var real := catalog.get_part("guard_bumper_5in_abs")
	var build := ReferenceBuild.build()
	build.guard = real
	var unstated := _guard_row(build)
	var bought_part := real.duplicate(true)
	bought_part["fabrication"] = "bought"
	build.guard = bought_part
	var bought := _guard_row(build)
	var bought_solid := PrintedParts.solid_for(build, PrintedParts.PROP_GUARD, 0.0635)
	var printed_part := real.duplicate(true)
	printed_part["fabrication"] = "printed"
	build.guard = printed_part
	var printed := _guard_row(build)
	return [
		TestResult.new("a guard whose catalog entry says nothing stays exportable, and its row says the catalog does not say",
			bool(unstated.get("exportable", false)) and String(unstated.get("note", "")).contains("catalog does not say"),
			"\"%s\"" % unstated.get("note", "")),
		TestResult.new("a guard marked bought is listed but not exportable, says it is bought, and the export refuses it by name",
			not bought.is_empty() and not bool(bought.get("exportable", true))
				and String(bought.get("note", "")).contains("bought")
				and not bool(bought_solid.get("ok", true)) and String(bought_solid.get("reason", "")).begins_with("prop_guard:"),
			"\"%s\"; solid %s" % [bought.get("note", ""), bought_solid.get("reason", "")]),
		TestResult.new("a guard marked printed is exportable and its row says it is a printed part",
			bool(printed.get("exportable", false)) and String(printed.get("note", "")).contains("printed part")
				and not String(printed.get("note", "")).contains("catalog does not say"),
			"\"%s\"" % printed.get("note", "")),
	]


static func _a_frame_is_listed_only_when_printable(catalog: PartsCatalog) -> Array:
	var real := catalog.get_part("frame_3in_toothpick")
	var build := ReferenceBuild.build()
	build.frame = real
	var unstated := _ids(PrintedParts.for_build(build))
	var bought := real.duplicate(true)
	bought["fabrication"] = "bought"
	build.frame = bought
	var bought_ids := _ids(PrintedParts.for_build(build))
	var printed := real.duplicate(true)
	printed["fabrication"] = "either"
	build.frame = printed
	var printed_ids := _ids(PrintedParts.for_build(build))
	var solid := PrintedParts.solid_for(build, PrintedParts.FRAME, 0.0)
	var triangles: Array = solid.get("triangles", [])
	var report := StlWriter.check_manifold(triangles)
	var facets := FrameExport.to_stl(AirframeDocument.from_catalog_frame(printed)).count("facet normal")
	return [
		TestResult.new("a frame with no flag, or marked bought, lists no frame to print; marked either, it does",
			not unstated.has(PrintedParts.FRAME) and not bought_ids.has(PrintedParts.FRAME)
				and printed_ids.has(PrintedParts.FRAME),
			"unstated %s, bought %s, either %s" % [unstated, bought_ids, printed_ids]),
		# PR9 pinned a refusal here, because the whole-file check refused every catalog frame. PR13 checks each
		# plate as its own body, so a printable frame now passes — and inside each plate it is still strict.
		# `report` is the OLD whole-file check on the same triangles, and it must still refuse: that is what
		# makes "passes per plate" a statement about the per-body check rather than about a changed frame.
		TestResult.new("the printable frame's solid is the frame export's own tessellation: refused whole-file, passed per plate",
			triangles.size() > 0 and triangles.size() == facets and bool(solid.get("ok", false))
				and not bool(report["ok"])
				and bool(StlWriter.check_bodies(solid.get("bodies", []))["ok"])
				and String(solid.get("generator", "")) == "frame@1",
			"ok %s, %d triangles vs %d facets, reason \"%s\"" % [solid.get("ok"), triangles.size(), facets,
				solid.get("reason", "")]),
	]


static func _ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row["id"]))
	return out
