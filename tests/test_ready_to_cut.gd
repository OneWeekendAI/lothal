class_name TestReadyToCut
extends RefCounted
## The ready-to-cut check — airframe gaps build plan, slice G3. `ReadyToCut` (inside corners and gaps
## against the cutting bit, reached through `FrameWarnings.of`), `FrameEdits.round_inside_corner`, the
## countersink flag, and the per-plate notes in the DXF and SVG.
##
## Where each check could pass while proving nothing, and what stops it:
##   - every "warns" has a "does not warn" partner on the same shape after the fix, and every quiet
##     shape has a loud one, so a check stuck at yes or at no fails one side (feedback: plans whose
##     tests cannot fail, case 8).
##   - the leftover depth of a sharp 90° corner is asserted against r(√2 - 1) written here, not read
##     back from the code under test.
##   - the notch case (two 90° turns joined by an edge) is the shape a naive "run of inside turns is
##     one arc" reading passes; it must report TWO sharp corners.
##   - the fix's mass change is asserted against the fillet's own area, r²(1 - π/4)·ρ·t, so a fix
##     that drew nothing, or drew the arc the wrong way (removing material), fails.
##   - the bit setting is proven by a fillet that passes at 1/16" and fails at 1/8": a check that
##     ignored the document's bit would answer the same both times.
##   - warnings are read through `FrameWarnings.of`, so the wiring is under test, not just the class.
##   - one result per case, never a loop that fails once (feedback: loop tests hide coverage).

const L_INSIDE_VERTEX := 3


static func run() -> Array:
	var sections := {}
	sections["inside corners"] = _inside_corners()
	sections["rounding fix"] = _rounding_fix()
	sections["holes and gaps"] = _holes_and_gaps()
	sections["bit setting"] = _bit_setting()
	sections["countersinks"] = _countersinks()
	sections["notes"] = _notes()
	sections["presets"] = _presets_are_ready_to_cut()
	sections["rows and workbench"] = _rows_and_workbench()
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("ready to cut: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## An L-shaped bottom plate, counter-clockwise. Five outer corners and ONE inside corner, at (10, 10),
## which is vertex 3.
static func _l_plate() -> AirframeDocument:
	var document := FrameEdits.new_frame("L")
	document.plates.append(AirframeDocument.make_plate(PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 10), Vector2(10, 10), Vector2(10, 40),
		Vector2(0, 40)]), [], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM))
	return document


static func _rect_plate(width: float = 40.0, height: float = 40.0) -> AirframeDocument:
	var document := FrameEdits.new_frame("rect")
	FrameEdits.add_rectangle(document, Vector2.ZERO, width, height, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	return document


## The L's inside corner drawn as a fillet of `radius`, tessellated the way the app draws arcs.
static func _l_with_fillet(radius: float) -> AirframeDocument:
	var arc := PolygonProps.tessellate_arc(Vector2(10 + radius, 10 + radius), radius, -PI * 0.5,
		-PI * 0.5)
	var points := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 10)])
	points.append_array(arc)
	points.append_array(PackedVector2Array([Vector2(10, 40), Vector2(0, 40)]))
	var document := FrameEdits.new_frame("L fillet")
	document.plates.append(AirframeDocument.make_plate(points, [], 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM))
	return document


static func _warning(document: AirframeDocument, id: StringName) -> BuildWarning:
	var props := AirframeProperties.compute(document, FrameMaterials.load_default())
	for warning in FrameWarnings.of(document, props):
		if warning.id == id:
			return warning
	return null


static func _corner_count(document: AirframeDocument) -> int:
	var warning := _warning(document, ReadyToCut.TIGHT_CORNER)
	return 0 if warning == null else (warning.values["corners"] as Array).size()


static func _mass_g(document: AirframeDocument) -> float:
	return AirframeProperties.compute(document, FrameMaterials.load_default()).total_mass_g()


# ---------------------------------------------------------------------------
# Inside corners
# ---------------------------------------------------------------------------

static func _inside_corners() -> Array:
	var out: Array = []
	var bit_r := AirframeDocument.DEFAULT_CUTTING_BIT_MM * 0.5

	var sharp := _warning(_l_plate(), ReadyToCut.TIGHT_CORNER)
	var depth := -1.0 if sharp == null else float(sharp.values["depth_mm"])
	var expected := bit_r * (sqrt(2.0) - 1.0)
	out.append(TestResult.new(
		"G3: a sharp inside corner warns, LIMITING, with the bit's leftover r(√2-1)",
		sharp != null and sharp.severity == BuildWarning.Severity.LIMITING
			and _corner_count(_l_plate()) == 1 and absf(depth - expected) < 1e-4,
		"corners %d, depth %.5f mm vs %.5f" % [_corner_count(_l_plate()), depth, expected]))

	out.append(TestResult.new(
		"G3: outer sharp corners never warn (a rectangle is four of them, the L has five)",
		_warning(_rect_plate(), ReadyToCut.TIGHT_CORNER) == null and _corner_count(_l_plate()) == 1,
		"rectangle %s, L counts %d" % [str(_warning(_rect_plate(), ReadyToCut.TIGHT_CORNER) != null),
			_corner_count(_l_plate())]))

	# A drawn fillet at the bit's radius is followed; one at 0.3 mm is not.
	out.append(TestResult.new("G3: a drawn fillet at the bit radius does not warn",
		_corner_count(_l_with_fillet(bit_r)) == 0,
		"corners %d" % _corner_count(_l_with_fillet(bit_r))))
	var small := _warning(_l_with_fillet(0.3), ReadyToCut.TIGHT_CORNER)
	var small_r := -1.0
	if small != null:
		small_r = float((small.values["corners"] as Array)[0]["radius_mm"])
	out.append(TestResult.new("G3: a drawn fillet smaller than the bit warns, and is measured as one",
		small != null and absf(small_r - 0.3) < 1e-3,
		"measured radius %.4f mm" % small_r))

	# The notch: two 90° inside turns joined by a 10 mm edge. Read as one run it is a "3.2 mm arc"
	# and passes; it is two sharp corners.
	var notch := FrameEdits.new_frame("notch")
	notch.plates.append(AirframeDocument.make_plate(PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(25, 30), Vector2(25, 20),
		Vector2(15, 20), Vector2(15, 30), Vector2(0, 30)]), [], 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM))
	out.append(TestResult.new("G3: a square notch is two sharp corners, not one wide arc",
		_corner_count(notch) == 2, "corners %d" % _corner_count(notch)))
	return out


# ---------------------------------------------------------------------------
# The fix
# ---------------------------------------------------------------------------

static func _rounding_fix() -> Array:
	var out: Array = []
	var document := _l_plate()
	var before_g := _mass_g(document)
	var rounded := FrameEdits.round_inside_corner(document, 0, ReadyToCut.OUTLINE, L_INSIDE_VERTEX)
	var after_g := _mass_g(document)
	out.append(TestResult.new("G3: the rounded corner no longer warns",
		rounded and _warning(document, ReadyToCut.TIGHT_CORNER) == null,
		"rounded %s, corners after %d" % [str(rounded), _corner_count(document)]))

	# The fillet ADDS r²(1 - π/4) of plate: the material the bit leaves in the corner anyway. The
	# tessellated arc's chords sit inside the true arc, so the polygon adds a little more — 2-3%.
	var r := AirframeDocument.DEFAULT_CUTTING_BIT_MM * 0.5
	var density := FrameMaterials.load_default().density("carbon_3k_twill_0_90")
	var expected_g := r * r * (1.0 - PI / 4.0) * 2.0 * 1.0e-9 * density * 1000.0
	var delta_g := after_g - before_g
	out.append(TestResult.new("G3: mass follows the rounded geometry: + r²(1-π/4)·t·ρ",
		delta_g > 0.0 and absf(delta_g - expected_g) / expected_g < 0.05,
		"Δ %.6f g vs fillet %.6f g" % [delta_g, expected_g]))

	var outer := _rect_plate()
	out.append(TestResult.new("G3: rounding refuses an OUTER corner (nothing to fix there)",
		not FrameEdits.round_inside_corner(outer, 0, ReadyToCut.OUTLINE, 0),
		"outline unchanged at %d points" % AirframeDocument.plate_outline(outer.plates[0]).size()))

	var square_hole := _rect_plate()
	square_hole.plates[0]["holes"] = [AirframeDocument.flatten(PolygonProps.reversed(
		FrameLayouts.square(5.0)))]
	var fixed := FrameEdits.round_tight_corners(square_hole, 0)
	out.append(TestResult.new("G3: round_tight_corners fixes all four corners of a square hole",
		fixed == 4 and _warning(square_hole, ReadyToCut.TIGHT_CORNER) == null,
		"fixed %d, corners left %d" % [fixed, _corner_count(square_hole)]))
	return out


# ---------------------------------------------------------------------------
# Holes and gaps
# ---------------------------------------------------------------------------

static func _holes_and_gaps() -> Array:
	var out: Array = []
	var square_hole := _rect_plate()
	square_hole.plates[0]["holes"] = [AirframeDocument.flatten(PolygonProps.reversed(
		FrameLayouts.square(5.0)))]
	out.append(TestResult.new("G3: a square hole's four corners are inside corners and warn",
		_corner_count(square_hole) == 4, "corners %d" % _corner_count(square_hole)))

	var round_hole := _rect_plate()
	FrameEdits.add_hole(round_hole, 0, Vector2.ZERO, 3.2)
	out.append(TestResult.new("G3: a round M3 hole is neither a tight corner nor a narrow gap",
		_warning(round_hole, ReadyToCut.TIGHT_CORNER) == null
			and _warning(round_hole, ReadyToCut.NARROW_GAP) == null,
		"corners %d" % _corner_count(round_hole)))

	var narrow := _slot_plate(1.0)
	var gap := _warning(narrow, ReadyToCut.NARROW_GAP)
	var width := -1.0 if gap == null else float(gap.values["width_mm"])
	out.append(TestResult.new("G3: a slot 1.0 mm wide (under the 1.59 mm bit) warns, measured at 1.0",
		gap != null and gap.severity == BuildWarning.Severity.LIMITING and absf(width - 1.0) < 1e-4,
		"width %.4f mm" % width))
	out.append(TestResult.new("G3: a strap slot 3.5 mm wide is not a narrow gap",
		_warning(_slot_plate(3.5), ReadyToCut.NARROW_GAP) == null, "quiet"))

	# A slot with 0.3 mm corners turns the same way all the way round (its straight sides' end
	# vertices turn too), so it is ONE run of inside turns. It must still read as four 0.3 mm corners.
	var small_round := _rect_plate()
	small_round.plates[0]["holes"] = [AirframeDocument.flatten(
		StrapSlots.make_slot(Vector2.ZERO, 22.0, 3.5, 0.0, 0.3))]
	var rounded_warning := _warning(small_round, ReadyToCut.TIGHT_CORNER)
	var radii: Array = []
	if rounded_warning != null:
		for corner in rounded_warning.values["corners"]:
			radii.append(snappedf(float(corner["radius_mm"]), 0.001))
	out.append(TestResult.new("G3: a slot rounded at 0.3 mm reads as four 0.3 mm corners, not one run",
		radii == [0.3, 0.3, 0.3, 0.3], "radii %s" % str(radii)))

	# A slit into the OUTLINE (the cut region is outside the plate there): 1.2 mm wide.
	var slit := FrameEdits.new_frame("slit")
	slit.plates.append(AirframeDocument.make_plate(PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(20.6, 30), Vector2(20.6, 15),
		Vector2(19.4, 15), Vector2(19.4, 30), Vector2(0, 30)]), [], 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM))
	var slit_gap := _warning(slit, ReadyToCut.NARROW_GAP)
	out.append(TestResult.new("G3: a 1.2 mm slit cut into the outline warns too",
		slit_gap != null and absf(float(slit_gap.values["width_mm"]) - 1.2) < 1e-3,
		"width %s" % ("none" if slit_gap == null else "%.4f" % float(slit_gap.values["width_mm"]))))
	return out


static func _slot_plate(width: float) -> AirframeDocument:
	var document := _rect_plate()
	document.plates[0]["holes"] = [AirframeDocument.flatten(
		StrapSlots.make_slot(Vector2.ZERO, 12.0, width))]
	return document


# ---------------------------------------------------------------------------
# The bit is a setting
# ---------------------------------------------------------------------------

static func _bit_setting() -> Array:
	var out: Array = []
	var fine := _l_with_fillet(0.8)
	var coarse := _l_with_fillet(0.8)
	FrameEdits.set_cutting_bit(coarse, 3.175)
	out.append(TestResult.new("G3: a 0.8 mm fillet passes a 1/16\" bit and warns under a 1/8\" bit",
		_corner_count(fine) == 0 and _corner_count(coarse) == 1,
		"1/16: %d, 1/8: %d" % [_corner_count(fine), _corner_count(coarse)]))

	var saved := coarse.to_dictionary()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var loaded := AirframeDocument.from_dictionary(parsed if parsed is Dictionary else {})
	var fresh := AirframeDocument.from_dictionary({"name": "old file"})
	out.append(TestResult.new("G3: the bit survives save/load; an old file reads the 1/16\" default",
		absf(loaded.cutting_bit_mm - 3.175) < 1e-9
			and absf(fresh.cutting_bit_mm - 1.5875) < 1e-9,
		"loaded %.4f, old file %.4f" % [loaded.cutting_bit_mm, fresh.cutting_bit_mm]))
	return out


# ---------------------------------------------------------------------------
# Countersinks and notes
# ---------------------------------------------------------------------------

## A bottom plate with two M3 holes, the second countersunk.
static func _countersunk_doc(mark: bool) -> AirframeDocument:
	var document := _rect_plate()
	FrameEdits.add_hole(document, 0, Vector2(-10, 0), 3.2)
	FrameEdits.add_hole(document, 0, Vector2(10, 0), 3.2)
	if mark:
		FrameEdits.set_hole_countersunk(document, 0, 1, true)
	return document


static func _countersinks() -> Array:
	var out: Array = []
	var marked := FrameExport.to_dxf(_countersunk_doc(true))
	var plain := FrameExport.to_dxf(_countersunk_doc(false))
	out.append(TestResult.new(
		"G3: a countersunk hole goes on the BOTTOM_COUNTERSINK layer, the other stays on BOTTOM_HOLES",
		marked.count("POLYLINE\n8\nBOTTOM_COUNTERSINK\n") == 1
			and marked.count("POLYLINE\n8\nBOTTOM_HOLES\n") == 1
			and not plain.contains("COUNTERSINK\n"),
		"marked: %d countersink, %d holes; unmarked has layer: %s" % [
			marked.count("POLYLINE\n8\nBOTTOM_COUNTERSINK\n"),
			marked.count("POLYLINE\n8\nBOTTOM_HOLES\n"), str(plain.contains("COUNTERSINK\n"))]))

	var svg := FrameExport.to_svg(_countersunk_doc(true))
	var plain_svg := FrameExport.to_svg(_countersunk_doc(false))
	out.append(TestResult.new(
		"G3: the SVG rings a countersunk hole (not as a cut path) and the legend names it",
		svg.count("<circle ") == 1 and svg.contains("countersink this hole")
			and svg.count('<path d="M') == plain_svg.count('<path d="M')
			and not plain_svg.contains("<circle "),
		"circles %d, legend %s" % [svg.count("<circle "), str(svg.contains("countersink this hole"))]))

	var round_trip := AirframeDocument.from_dictionary(
		JSON.parse_string(JSON.stringify(_countersunk_doc(true).to_dictionary())))
	out.append(TestResult.new("G3: the countersink flag survives save/load (JSON ints come back floats)",
		AirframeDocument.hole_is_countersunk(round_trip.plates[0], 1)
			and not AirframeDocument.hole_is_countersunk(round_trip.plates[0], 0),
		"hole 1 %s" % str(AirframeDocument.hole_is_countersunk(round_trip.plates[0], 1))))

	var imported := FrameImport.from_dxf(marked)
	out.append(TestResult.new("G3: the noted DXF still imports — TEXT is not read as geometry",
		str(imported.get("error", "x")).is_empty() and (imported["loops"] as Array).size() == 3,
		"loops %d, error '%s'" % [(imported.get("loops", []) as Array).size(),
			str(imported.get("error", ""))]))
	return out


static func _notes() -> Array:
	var out: Array = []
	var document := FrameEdits.new_frame("notes")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var arm := FrameEdits.add_arm(document, 45.0, 90.0, 14.0, 14.0, 5.0)
	FrameEdits.replicate_radially(document, arm, 4)
	var dxf := FrameExport.to_dxf(document)
	var texts := _dxf_texts(dxf)
	var bottom := _first_containing(texts, "Plate 1 (bottom)")
	var an_arm := _first_containing(texts, "(arm)")
	out.append(TestResult.new(
		"G3: the DXF carries a NOTES text per plate: role, thickness, material, quantity, bit",
		texts.size() >= 5 and bottom.contains("2.0 mm Carbon plate, 3K twill 0/90")
			and bottom.contains("qty 1 of 1") and bottom.contains("1.59 mm bit")
			and an_arm.contains("5.0 mm") and an_arm.contains("qty 1 of 4 identical"),
		"%d notes; bottom '%s'; arm '%s'" % [texts.size(), bottom, an_arm]))
	out.append(TestResult.new("G3: the DXF header states the bit as a typical shop value",
		_first_containing(texts, "1.5875 mm (1/16 in, a typical shop value)") != "",
		_first_containing(texts, "end mill")))

	var svg := FrameExport.to_svg(document, FrameExport.LAYOUT_NEST)
	out.append(TestResult.new("G3: the SVG has a notes block naming every plate",
		svg.contains('<g id="notes"') and svg.count("qty 1 of 4 identical") == 4
			and svg.contains("Plate 1 (bottom) - 2.0 mm Carbon plate"),
		"arms in notes %d" % svg.count("qty 1 of 4 identical")))
	return out


# ---------------------------------------------------------------------------
# Presets, warning rows, the workbench
# ---------------------------------------------------------------------------

## Every catalog preset and every generated layout is ready to cut as generated: their strap slots are
## drawn with the bit's fillet. One result per frame.
static func _presets_are_ready_to_cut() -> Array:
	var out: Array = []
	var presets := AirframeDocument.presets_from_catalog(PartsCatalog.load_default())
	var named: Dictionary = {}
	for key in presets:
		named["preset %s" % key] = presets[key]
	for id in FrameLayouts.ids():
		named["layout %s" % id] = FrameLayouts.build(id)
	for key in named:
		var messages: Array = []
		for warning in ReadyToCut.warnings(named[key]):
			messages.append(warning.message)
		out.append(TestResult.new("G3: %s is ready to cut as generated" % key, messages.is_empty(),
			"warnings: %s" % str(messages)))
	return out


static func _rows_and_workbench() -> Array:
	var out: Array = []
	var sharp := _warning(_l_plate(), ReadyToCut.TIGHT_CORNER)
	var gap := _warning(_slot_plate(1.0), ReadyToCut.NARROW_GAP)
	out.append(TestResult.new("G3: both warnings have a row on the Frame item",
		sharp != null and gap != null and WarningRows.has(sharp.id) and WarningRows.has(gap.id)
			and WarningRows.item_of(sharp.id, sharp.values) == WarningRows.FRAME
			and WarningRows.short_of(sharp.id, sharp.values) == "1 corner sharper than the bit",
		"short '%s'" % ("" if sharp == null else WarningRows.short_of(sharp.id, sharp.values))))

	var catalog := PartsCatalog.load_default()
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(catalog.list_category("frame")[0])
	workbench._on_add_plate()
	var index := workbench.editor.document.plates.size() - 1
	workbench.editor.document.plates[index]["holes"] = [AirframeDocument.flatten(
		PolygonProps.reversed(FrameLayouts.square(5.0)))]
	var depth := workbench.editor.history.depth()
	var rounded := workbench.round_tight_corners()
	out.append(TestResult.new("G3: the workbench's \"Round inside corners\" is one undo step and clears them",
		rounded == 4 and workbench.editor.history.depth() == depth + 1
			and _warning(workbench.editor.document, ReadyToCut.TIGHT_CORNER) == null,
		"rounded %d, depth %d -> %d" % [rounded, depth, workbench.editor.history.depth()]))
	var again := workbench.round_tight_corners()
	out.append(TestResult.new("G3: with nothing left to round it adds no undo step",
		again == 0 and workbench.editor.history.depth() == depth + 1,
		"rounded %d, depth %d" % [again, workbench.editor.history.depth()]))

	workbench._on_export_chosen(FrameWorkbench.BIT_MENU_ID + 1)
	out.append(TestResult.new("G3: the Export menu's 1/8\" item sets the document's bit",
		absf(workbench.editor.document.cutting_bit_mm - 3.175) < 1e-9,
		"bit %.4f" % workbench.editor.document.cutting_bit_mm))

	FrameEdits.add_hole(workbench.editor.document, index, Vector2(8.0, 8.0), 3.2)
	workbench._on_selection_changed(index)
	var marked := workbench.toggle_countersinks()
	var plate: Dictionary = workbench.editor.document.plates[index]
	out.append(TestResult.new("G3: countersinking a plate marks its round screw hole and not the square cut-out",
		marked == 1 and AirframeDocument.hole_is_countersunk(plate, 1)
			and not AirframeDocument.hole_is_countersunk(plate, 0),
		"marked %d" % marked))
	workbench.free()
	return out


## Every TEXT entity's string on the NOTES layer.
static func _dxf_texts(dxf: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := dxf.split("\n")
	var index := 0
	while index < lines.size():
		if lines[index] == "TEXT" and index + 2 < lines.size() and lines[index + 2] == "NOTES":
			var k := index + 1
			while k + 1 < lines.size() and lines[k] != "0":
				if lines[k] == "1":
					out.append(lines[k + 1])
				k += 2
		index += 1
	return out


static func _first_containing(texts: PackedStringArray, needle: String) -> String:
	for text in texts:
		if text.contains(needle):
			return text
	return ""
