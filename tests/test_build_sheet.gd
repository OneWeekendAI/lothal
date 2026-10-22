class_name TestBuildSheet
extends RefCounted
## The build sheet and the cutting-cost estimate — airframe gaps build plan, slice G6. `BuildSheet`
## (parts, hardware, sections, assembly order, the HTML page) and `CutCost` (nest area × thickness rate,
## plus cut length), and their two places in the workbench: the Export menu and the numbers strip.
##
## Where each check could pass while proving nothing, and what stops it:
##   - hardware counts are recomputed HERE from `document.hardware` by its own loop, on a fixture with
##     two screw LENGTHS of one thread and a hex standoff beside the round ones — so grouping by thread
##     alone, or reading only round standoffs, gives a wrong count instead of the same one.
##   - the hole's cut length is asserted against a 4 × 6 mm rectangle's 20 mm, written here, not
##     against the code's own perimeter function.
##   - "cost rises with area" uses two plates with the SAME perimeter (10 × 50 and 30 × 30, 120 mm
##     each), so the cut term cannot carry it — only the sheet term can.
##   - "cost rises with thickness" compares the same outline at 2, 2.5 and 3 mm, so a rate lookup that
##     ignores thickness (or returns one row) is equal, not rising.
##   - every "section appears when present" has its "absent when absent" partner on the same fixture
##     (feedback: plans whose tests cannot fail, case 8 — a check stuck at yes or at no fails a side).
##   - one result per case, never a loop that fails once (feedback: loop tests hide coverage).

const FRAME_ID := "frame_5in_freestyle"


static func run() -> Array:
	var sections := {}
	var catalog := PartsCatalog.load_default()
	sections["hardware counts"] = _hardware_counts(catalog)
	sections["plates"] = _plates(catalog)
	sections["cut length"] = _cut_length()
	sections["cost"] = _cost()
	sections["sections"] = _sections_when_present()
	sections["assembly"] = _assembly(catalog)
	sections["mass"] = _mass(catalog)
	sections["workbench"] = _workbench(catalog)
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("build sheet: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The 5" preset plus hardware it does not carry: two M3 × 10 steel screws (same thread,
## another length), an M2 × 6 screw, and a hex standoff.
static func _mixed_hardware(catalog: PartsCatalog) -> AirframeDocument:
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FRAME_ID))
	for spec in [[3.0, 10.0], [3.0, 10.0], [2.0, 6.0]]:
		document.hardware.append({"kind": "screw", "material_id": "steel_fastener",
			"thread_d_mm": spec[0], "shank_len_mm": spec[1], "head_d_mm": spec[0] * 1.9,
			"head_h_mm": spec[0] * 0.6, "position_mm": [0.0, 0.0], "z_mm": 0.0})
	document.hardware.append({"kind": "standoff_hex", "material_id": "aluminium_6061",
		"across_flats_mm": 5.0, "bore_d_mm": 3.0, "length_mm": 20.0, "position_mm": [0.0, 0.0],
		"z_mm": 10.0})
	return document


static func _rect(width: float, height: float, thickness: float = 2.0) -> AirframeDocument:
	var document := FrameEdits.new_frame("rect")
	FrameEdits.add_rectangle(document, Vector2.ZERO, width, height, thickness, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	return document


# ---------------------------------------------------------------------------
# Hardware: every item FrameHardware derives, with the right count
# ---------------------------------------------------------------------------

static func _hardware_counts(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var document := _mixed_hardware(catalog)
	var sheet := BuildSheet.compose(document)
	var html := BuildSheet.to_html(document)

	# Expected, by the test's own loop over the document.
	var expected_screws := {}
	for item in document.hardware:
		if str(item["kind"]) != "screw":
			continue
		var key := "M%s × %s mm screw" % [_trim(float(item["thread_d_mm"])), _trim(float(item["shank_len_mm"]))]
		expected_screws[key] = int(expected_screws.get(key, 0)) + 1
	var expected_standoffs := {}
	for item in document.hardware:
		var kind := str(item["kind"])
		if kind != "standoff_round" and kind != "standoff_hex":
			continue
		var key := "%s|%s" % [kind, _trim(float(item["length_mm"]))]
		expected_standoffs[key] = int(expected_standoffs.get(key, 0)) + 1

	for key in expected_screws:
		var found := -1
		for row in sheet["screws"]:
			if BuildSheet.screw_label(row) == key:
				found = int(row["count"])
		out.append(TestResult.new("G6: the sheet lists %s with count %d" % [key, expected_screws[key]],
			found == int(expected_screws[key]), "sheet says %d" % found))
		var cell := "<td>%s</td><td>Steel (fastener)</td><td class=\"n\">%d</td>" % [key,
			int(expected_screws[key])]
		out.append(TestResult.new("G6: the HTML has the %s row with its count" % key,
			html.contains(cell), "looked for %s" % cell))
	for key in expected_standoffs:
		var parts: PackedStringArray = key.split("|")
		var found := -1
		for row in sheet["standoffs"]:
			if str(row["kind"]) == parts[0] and _trim(float(row["length_mm"])) == parts[1]:
				found = int(row["count"])
		out.append(TestResult.new("G6: the sheet lists the %s standoffs %s mm long, count %d" % [
			parts[0], parts[1], expected_standoffs[key]], found == int(expected_standoffs[key]),
			"sheet says %d" % found))
	var screw_total := 0
	for row in sheet["screws"]:
		screw_total += int(row["count"])
	var standoff_total := 0
	for row in sheet["standoffs"]:
		standoff_total += int(row["count"])
	out.append(TestResult.new("G6: screws on the sheet add up to FrameHardware's screws",
		screw_total == FrameHardware.items_of_kind(document, "screw").size(),
		"%d vs %d" % [screw_total, FrameHardware.items_of_kind(document, "screw").size()]))
	out.append(TestResult.new("G6: standoffs on the sheet add up to FrameHardware's standoffs",
		standoff_total == FrameHardware.standoffs(document).size(),
		"%d vs %d" % [standoff_total, FrameHardware.standoffs(document).size()]))
	return out


# ---------------------------------------------------------------------------
# Plates: every plate, with role, thickness, material and quantity
# ---------------------------------------------------------------------------

static func _plates(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FRAME_ID))
	var sheet := BuildSheet.compose(document)
	var listed := 0
	var arm_row: Dictionary = {}
	for row in sheet["plates"]:
		listed += (row["labels"] as PackedStringArray).size()
		if str(row["role"]) == AirframeDocument.ROLE_ARM:
			arm_row = row
	out.append(TestResult.new("G6: every plate is on the sheet once", listed == document.plates.size(),
		"%d listed of %d" % [listed, document.plates.size()]))
	out.append(TestResult.new("G6: the four arms are one row, qty 4, 5 mm, with the material's name",
		not arm_row.is_empty() and int(arm_row["quantity"]) == 4
			and absf(float(arm_row["thickness_mm"]) - 5.0) < 1e-9
			and str(arm_row["material"]) == "Carbon plate, 3K twill 0/90",
		str(arm_row)))
	return out


# ---------------------------------------------------------------------------
# Cut length: a hole adds its perimeter
# ---------------------------------------------------------------------------

static func _cut_length() -> Array:
	var out: Array = []
	var document := _rect(40.0, 40.0)
	var before := CutCost.cut_length_m(document)
	var cost_before := CutCost.estimate(document)
	# A 4 × 6 mm rectangular hole: 20 mm of cut, whatever the code's perimeter function says.
	document.plates[0]["holes"] = [AirframeDocument.flatten(PolygonProps.reversed(PackedVector2Array([
		Vector2(-2, -3), Vector2(2, -3), Vector2(2, 3), Vector2(-2, 3)])))]
	var after := CutCost.cut_length_m(document)
	var cost_after := CutCost.estimate(document)
	out.append(TestResult.new("G6: a 40 × 40 plate is 160 mm of cut", absf(before - 0.160) < 1e-9,
		"%.6f m" % before))
	out.append(TestResult.new("G6: adding a 4 × 6 mm hole adds its 20 mm perimeter to the cut length",
		absf((after - before) - 0.020) < 1e-9, "delta %.6f m" % (after - before)))
	var rates := CutCost.load_rates()
	var per_m: Dictionary = rates["cut_price_per_m"]
	out.append(TestResult.new("G6: and the estimate's high end rises by exactly that cut at the high rate",
		absf((float(cost_after["high"]) - float(cost_before["high"])) - 0.020 * float(per_m["high"])) < 1e-9,
		"delta %.6f" % (float(cost_after["high"]) - float(cost_before["high"]))))
	return out


# ---------------------------------------------------------------------------
# Cost: rises with thickness and with area; always a labelled range
# ---------------------------------------------------------------------------

static func _cost() -> Array:
	var out: Array = []
	var thin := CutCost.estimate(_rect(40.0, 40.0, 2.0))
	var mid := CutCost.estimate(_rect(40.0, 40.0, 2.5))
	var thick := CutCost.estimate(_rect(40.0, 40.0, 3.0))
	out.append(TestResult.new("G6: the same plate costs more at 2.5 mm than at 2 mm, both ends",
		float(mid["low"]) > float(thin["low"]) and float(mid["high"]) > float(thin["high"]),
		"%.3f–%.3f vs %.3f–%.3f" % [thin["low"], thin["high"], mid["low"], mid["high"]]))
	out.append(TestResult.new("G6: and more at 3 mm than at 2.5 mm, both ends",
		float(thick["low"]) > float(mid["low"]) and float(thick["high"]) > float(mid["high"]),
		"%.3f–%.3f vs %.3f–%.3f" % [mid["low"], mid["high"], thick["low"], thick["high"]]))
	var rates := CutCost.load_rates()
	out.append(TestResult.new("G6: beyond the table, thicker still costs more (8 mm > 6 mm)",
		float(CutCost.sheet_rate_per_cm2(rates, 8.0)["low"])
			> float(CutCost.sheet_rate_per_cm2(rates, 6.0)["low"]), ""))

	var long_plate := _rect(10.0, 50.0)
	var square_plate := _rect(30.0, 30.0)
	var long_cost := CutCost.estimate(long_plate)
	var square_cost := CutCost.estimate(square_plate)
	out.append(TestResult.new("G6: precondition — 10 × 50 and 30 × 30 have the same 120 mm of cut",
		absf(CutCost.cut_length_m(long_plate) - CutCost.cut_length_m(square_plate)) < 1e-9
			and absf(CutCost.cut_length_m(long_plate) - 0.120) < 1e-9, ""))
	out.append(TestResult.new("G6: with the same cut, the larger plate (900 vs 500 mm²) costs more",
		float(square_cost["low"]) > float(long_cost["low"])
			and float(square_cost["high"]) > float(long_cost["high"]),
		"%.3f–%.3f vs %.3f–%.3f" % [long_cost["low"], long_cost["high"], square_cost["low"],
			square_cost["high"]]))

	var catalog := PartsCatalog.load_default()
	var preset := CutCost.estimate(AirframeDocument.from_catalog_frame(catalog.get_part(FRAME_ID)))
	var text := CutCost.labelled_text(preset)
	out.append(TestResult.new("G6: the estimate is a range, never one number (low < high, both shown)",
		float(preset["low"]) < float(preset["high"])
			and text.begins_with("$%d–$%d" % [floori(float(preset["low"])), ceili(float(preset["high"]))]),
		text))
	out.append(TestResult.new("G6: the range names its tier as placeholder rates",
		str(preset["tier"]) == "placeholder" and text.contains("placeholder rates"), text))
	out.append(TestResult.new("G6: the 2.5 mm plates and the 5 mm arms are priced as separate stock",
		(preset["stocks"] as Array).size() == 2, "%d stocks" % (preset["stocks"] as Array).size()))
	return out


# ---------------------------------------------------------------------------
# Sections: strap and cage only when present
# ---------------------------------------------------------------------------

static func _sections_when_present() -> Array:
	var out: Array = []
	var document := _rect(60.0, 60.0)
	var bare := BuildSheet.to_html(document)
	out.append(TestResult.new("G6: a plain plate has no strap section", not bare.contains('id="straps"')
		and (BuildSheet.compose(document)["strap"] as Dictionary).is_empty(), ""))
	out.append(TestResult.new("G6: a plain plate has no camera cage section", not bare.contains('id="cage"')
		and (BuildSheet.compose(document)["cage"] as Dictionary).is_empty(), ""))

	document.plates[0]["holes"] = [AirframeDocument.flatten(StrapSlots.make_slot(Vector2(0, 10), 22.0, 3.5)),
		AirframeDocument.flatten(StrapSlots.make_slot(Vector2(0, -10), 22.0, 3.5))]
	var slotted := BuildSheet.to_html(document)
	out.append(TestResult.new("G6: cutting two strap slots brings the strap section, with both slots",
		slotted.contains('id="straps"') and slotted.contains("2 strap slots 22.0 × 3.5 mm"), ""))
	out.append(TestResult.new("G6: …and still no camera cage section", not slotted.contains('id="cage"'), ""))
	var steps := BuildSheet.assembly_order(document)
	out.append(TestResult.new("G6: …and a strap step in the assembly order",
		steps.size() > 0 and steps[steps.size() - 1].begins_with("Thread the battery strap"), str(steps)))

	# A FULL-size (22 mm) cage: its tilt slot measures 8.7 × 2.9 mm, which IS a slot by StrapSlots'
	# shape rule — so a sheet that scanned upright plates for strap slots would list it.
	FrameEdits.add_camera_cage(document, 22.0)
	var caged := BuildSheet.to_html(document)
	out.append(TestResult.new("G6: adding a camera cage brings the cage section with its 22 mm spacing",
		caged.contains('id="cage"') and caged.contains("22.0 mm clear between the plates"), ""))
	var caged_steps := BuildSheet.assembly_order(document)
	var has_cage_step := false
	for step in caged_steps:
		has_cage_step = has_cage_step or step.begins_with("Fit the camera between the side plates")
	out.append(TestResult.new("G6: …and a camera step in the assembly order", has_cage_step,
		str(caged_steps)))
	var slot_count := 0
	for row in (BuildSheet.compose(document)["strap"] as Dictionary).get("slots", []):
		slot_count += int(row["count"])
	out.append(TestResult.new("G6: the cage's own tilt slots are not counted as strap slots",
		slot_count == 2 and caged.contains("2 strap slots 22.0 × 3.5 mm"), "%d slots" % slot_count))
	return out


# ---------------------------------------------------------------------------
# Assembly order: bottom → arms → standoffs → stack → top → cage → strap, from what is there
# ---------------------------------------------------------------------------

static func _assembly(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FRAME_ID))
	FrameEdits.add_camera_cage(document, 19.0)
	var steps := BuildSheet.assembly_order(document)
	var prefixes := ["Lay the bottom plate", "Seat the 4 arms", "Screw in the 4 standoffs",
		"Mount the flight stack", "Close with the top plate", "Fit the camera between",
		"Thread the battery strap"]
	var at: Array = []
	for prefix in prefixes:
		var found := -1
		for index in steps.size():
			if steps[index].begins_with(prefix):
				found = index
		at.append(found)
	var in_order := not at.has(-1)
	for index in at.size() - 1:
		in_order = in_order and int(at[index]) < int(at[index + 1])
	out.append(TestResult.new("G6: the 5\" with a cage assembles bottom → arms → standoffs → stack → top → cage → strap",
		in_order and steps.size() == prefixes.size(), str(steps)))
	var bare := BuildSheet.assembly_order(_rect(40.0, 40.0))
	out.append(TestResult.new("G6: a lone bottom plate has one step, and no arms, stack or strap",
		bare.size() == 1 and bare[0].begins_with("Lay the bottom plate"), str(bare)))
	return out


# ---------------------------------------------------------------------------
# Mass: computed, and moves with the hardware
# ---------------------------------------------------------------------------

static func _mass(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var materials := FrameMaterials.load_default()
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FRAME_ID))
	var before: Dictionary = BuildSheet.compose(document)["mass"]
	var hex := {"kind": "standoff_hex", "material_id": "aluminium_6061", "across_flats_mm": 5.0,
		"bore_d_mm": 3.0, "length_mm": 20.0, "position_mm": [0.0, 0.0], "z_mm": 10.0}
	document.hardware.append(hex)
	var after: Dictionary = BuildSheet.compose(document)["mass"]
	# (√3/2·5² − π/4·3²) mm² × 20 mm × 2700 kg/m³, by hand: 21.6506 − 7.0686 = 14.5821 mm² → 0.7874 g.
	var expected_g := (sqrt(3.0) / 2.0 * 25.0 - PI / 4.0 * 9.0) * 20.0 * 1.0e-9 \
		* materials.density("aluminium_6061") * 1000.0
	out.append(TestResult.new("G6: a 20 mm hex standoff adds its own mass to hardware and to the total",
		absf((float(after["hardware_g"]) - float(before["hardware_g"])) - expected_g) < 1e-6
			and absf((float(after["total_g"]) - float(before["total_g"])) - expected_g) < 1e-6,
		"hardware +%.4f, total +%.4f, expected %.4f" % [float(after["hardware_g"]) - float(before["hardware_g"]),
			float(after["total_g"]) - float(before["total_g"]), expected_g]))
	out.append(TestResult.new("G6: the sheet's total is AirframeProperties' total",
		absf(float(after["total_g"]) - AirframeProperties.compute(document, materials).total_mass_g()) < 1e-9,
		""))
	return out


# ---------------------------------------------------------------------------
# Workbench: the Export item writes the page; the numbers strip shows the range
# ---------------------------------------------------------------------------

static func _workbench(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(catalog.get_part(FRAME_ID))
	var id := -1
	for index in FrameWorkbench.EXPORTS.size():
		if str(FrameWorkbench.EXPORTS[index]["extension"]) == "html":
			id = index
	var path := "%s/%s-build-sheet.html" % [FrameWorkbench.EXPORT_DIRECTORY,
		FrameWorkbench._safe_file_name(workbench.editor.document.name)]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if id >= 0:
		workbench._on_export_chosen(id)
	var text := FileAccess.get_file_as_string(path)
	out.append(TestResult.new("G6: Export → Build sheet writes the page, cost section and all",
		id >= 0 and text.contains("<h2 id=\"cost\">") and text.contains("M3 × 8 mm screw"),
		"menu id %d, %d chars at %s" % [id, text.length(), path]))
	var estimate := CutCost.estimate(workbench.editor.document)
	var line := workbench.numbers.cost_text()
	out.append(TestResult.new("G6: the numbers strip shows the same labelled range",
		line.contains(CutCost.range_text(estimate)) and line.contains("placeholder rates"), line))
	workbench.free()
	return out


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
