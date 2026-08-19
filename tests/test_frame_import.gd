class_name TestFrameImport
extends RefCounted
## Reading an outline back in — `FrameImport`, the inverse of `FrameExport`.
##
## ## What these tests are really guarding
##
## An import that is subtly wrong is the most dangerous single failure in this room, because it is
## the only one with no symptom on screen. Every other mistake shows: a bad edit draws a bad shape,
## a bad mass reads oddly against a vendor figure. A file read at the wrong SCALE draws a perfectly
## normal frame, weighs a perfectly plausible amount, and is discovered at the cutter. A file read
## MIRRORED is worse still — it is invisible on a symmetric plate, which most plates are.
##
## So the assertions below are almost all about millimetres and handedness rather than about vertex
## counts, and the anchor is the round trip: what `FrameExport` writes, `FrameImport` must read back
## as the same polygon. Neither file is checked against a number typed here.
##
## ## MUTATION NOTES
##
##   - `_test_a_pixel_svg_is_read_at_96_dpi` fails if the unit path ever assumes one user unit is
##     one millimetre. That assumption reads a 96 px square as 96 mm instead of 25.4 mm — a 3.8×
##     error, and the exact shape of the failure that gets a plate cut wrong.
##   - `_test_an_svg_round_trips_the_way_round_it_was_drawn` fails if a Y flip is reintroduced.
##     `PlanTransform` fixes `+v` as DOWN, the same sense as SVG's Y, so a flip mirrors every
##     import — and mirrors it invisibly on every symmetric part.
##   - `_test_an_inner_loop_becomes_a_hole_that_subtracts` fails if nesting is dropped or wound the
##     same way as its outline. A hole with positive area ADDS mass, so a plate with six bolt holes
##     in it comes out heavier than the solid plate.
##   - `_test_a_spline_dxf_is_refused_whole` fails if the refusal is softened to "read what you
##     can". A plate missing one edge closes into a polygon that looks and weighs almost right.
##   - `_test_a_refused_file_leaves_the_document_alone` fails if `into_document` is ever called
##     before the error is checked — a half-import the builder then keeps editing.

const EPS_MM := 0.05
## Areas are compared as a fraction rather than in mm²: a 40 mm plate and a 3 mm bolt hole differ by
## three orders of magnitude, and one absolute tolerance cannot be right for both.
const AREA_TOLERANCE := 0.005


static func run() -> Array:
	# Collected per section and asserted non-empty below. A runtime error inside one helper aborts
	# only that helper, and the suite would otherwise return the others and PASS — the failure mode
	# that once hid four deleted assertions behind "ALL TESTS PASSED".
	var sections := {
		"svg": _svg_tests(),
		"dxf": _dxf_tests(),
		"placement": _placement_tests(),
		"refusal": _refusal_tests(),
	}
	var results: Array = []
	for key in sections:
		var section: Array = sections[key]
		results.append(TestResult.new("import section \"%s\" ran" % key, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


static func _svg_tests() -> Array:
	return [
		_test_lothal_svg_round_trips_to_the_same_area(),
		_test_an_svg_round_trips_the_way_round_it_was_drawn(),
		_test_a_pixel_svg_is_read_at_96_dpi(),
		_test_a_millimetre_svg_ignores_its_view_box_units(),
		_test_a_group_transform_moves_what_it_contains(),
		_test_a_curve_is_flattened_inside_its_tolerance(),
		_test_an_inner_loop_becomes_a_hole_that_subtracts(),
		_test_a_hole_over_an_edge_comes_back_as_its_own_outline(),
	]


static func _dxf_tests() -> Array:
	return [
		_test_lothal_dxf_round_trips_to_the_same_area(),
		_test_loose_lines_are_chained_into_one_loop(),
		_test_a_bulge_makes_an_arc_not_a_chord(),
		_test_a_spline_dxf_is_refused_whole(),
	]


static func _placement_tests() -> Array:
	return [
		_test_an_import_lands_centred_on_the_origin(),
		_test_an_imported_plate_is_never_an_arm(),
		_test_an_import_adds_the_mass_it_drew(),
	]


static func _refusal_tests() -> Array:
	return [
		_test_a_refused_file_leaves_the_document_alone(),
		_test_an_empty_svg_is_an_error_not_an_empty_frame(),
		_test_an_unknown_extension_is_refused_by_name(),
	]


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _square_svg(size_attribute: String, view_box: String, side: float) -> String:
	return ('<svg xmlns="http://www.w3.org/2000/svg" %s viewBox="%s">' +
		'<path d="M 0 0 L %f 0 L %f %f L 0 %f Z"/></svg>') % [
			size_attribute, view_box, side, side, side, side]


static func _total_area_mm2(loops: Array) -> float:
	var total := 0.0
	for loop in loops:
		total += absf(PolygonProps.area(loop))
	return total


static func _document_area_mm2(document: AirframeDocument) -> float:
	var total := 0.0
	for plate in document.plates:
		var properties := PolygonProps.region_properties(
			AirframeDocument.plate_outline(plate), AirframeDocument.plate_holes(plate))
		total += absf(float(properties["area"]))
	return total


static func _relative(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1.0e-9)


## The round-trip fixture: two plates and an arm, with every hole INSIDE the plate it is drilled in.
##
## Not `FrameLayouts.build("quad_x")`, and the reason is a real property of the formats rather than
## a convenience. Neither SVG nor DXF records which outline owns which hole — the reader recovers
## that by containment, which is what every fill engine does — so a hole that crosses its plate's
## edge cannot come back as a hole. quad_x has exactly that: a 16 mm bolt pattern on a 12 mm arm
## tip, which overhangs on both sides and at the end. That frame is a legitimate drawing and
## `FrameWarnings` has an opinion about it; it is simply not a frame any vector format can express
## unambiguously, and `_test_a_hole_over_an_edge_comes_back_as_its_own_outline` states that
## limitation instead of hiding it inside a fixture chosen to dodge it.
static func _round_trip_fixture() -> AirframeDocument:
	var document := FrameEdits.new_frame("round trip")
	var bottom := FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	for corner in FrameLayouts.bolt_pattern(Vector2.ZERO, 30.5, 0.0):
		FrameEdits.add_hole(document, bottom, corner, 3.2)
	var top := FrameEdits.add_rectangle(document, Vector2.ZERO, 36.0, 36.0, 2.0, 25.0,
		AirframeDocument.ROLE_TOP)
	FrameEdits.add_hole(document, top, Vector2.ZERO, 10.0)
	FrameEdits.add_arm(document, 45.0, 110.0, 20.0, 20.0, 5.0)
	# A 12 mm pattern inside a 20 mm tip: inboard of the edge on every side, so it survives a format
	# that knows only about containment.
	FrameEdits.add_motor_mount(document, document.plates.size() - 1,
		Vector2(cos(deg_to_rad(45.0)), sin(deg_to_rad(45.0))) * 100.0, 12.0, 45.0)
	return document


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------

## The anchor of the whole file: Lothal's own sheet, read back.
##
## The comparison is against the DOCUMENT the sheet was written from, not against a number typed
## here, so this fails if either side of the pair drifts — which is what makes it worth more than a
## hand-written fixture. Areas rather than vertices, because the nest layout moves plates and the
## reader has no reason to preserve the order they were written in.
static func _test_lothal_svg_round_trips_to_the_same_area() -> TestResult:
	var document := _round_trip_fixture()
	var svg := FrameExport.to_svg(document, FrameExport.LAYOUT_NEST, false)
	var result := FrameImport.from_svg(svg)
	if str(result["error"]) != "":
		return TestResult.new("an exported SVG reads back", false, str(result["error"]))

	var read := FrameImport.plates_from_loops(result["loops"])
	var imported := AirframeDocument.new()
	imported.plates = read
	var error := _relative(_document_area_mm2(imported), _document_area_mm2(document))
	return TestResult.new("an exported SVG reads back as the same area",
		read.size() == document.plates.size() and error < AREA_TOLERANCE,
		"%d plates in, %d out, area off by %.3f%%" % [
			document.plates.size(), read.size(), error * 100.0])


## Handedness, checked on a shape that has one.
##
## An L, not a square: a mirrored square is a square, and the flip this guards against is invisible
## on every symmetric part. The assertion is that the point drawn 10 mm along +y in the file is
## 10 mm along +v in the document — the two axes agree, per `PlanTransform`'s header.
static func _test_an_svg_round_trips_the_way_round_it_was_drawn() -> TestResult:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="40mm" height="40mm" ' + \
		'viewBox="0 0 40 40"><path d="M 0 0 L 30 0 L 30 10 L 10 10 L 10 30 L 0 30 Z"/></svg>'
	var result := FrameImport.from_svg(svg)
	if str(result["error"]) != "" or (result["loops"] as Array).is_empty():
		return TestResult.new("an L imports the way round it was drawn", false, "nothing read")

	var loop: PackedVector2Array = (result["loops"] as Array)[0]
	var has_long_x := false
	var has_long_y := false
	for point in loop:
		has_long_x = has_long_x or (absf(point.x - 30.0) < EPS_MM and absf(point.y) < EPS_MM)
		has_long_y = has_long_y or (absf(point.x) < EPS_MM and absf(point.y - 30.0) < EPS_MM)
	# A vertical flip would put the long leg at v = -30, so both of these hold only unmirrored.
	return TestResult.new("an L imports the way round it was drawn",
		has_long_x and has_long_y,
		"+u leg %s, +v leg %s" % [has_long_x, has_long_y])


## A file that states no real-world size is 96 dpi, and NOT 1 unit = 1 mm.
##
## 96 px is exactly one inch: 25.4 mm on a side, 645.16 mm². The wrong assumption gives 9216 mm²,
## which is a factor of fourteen in area and unmissable here and invisible on a canvas that fits.
static func _test_a_pixel_svg_is_read_at_96_dpi() -> TestResult:
	var result := FrameImport.from_svg(_square_svg("width=\"96px\" height=\"96px\"", "0 0 96 96", 96.0))
	if str(result["error"]) != "":
		return TestResult.new("a pixel SVG is read at 96 dpi", false, str(result["error"]))
	var area := _total_area_mm2(result["loops"])
	var expected := 25.4 * 25.4
	return TestResult.new("a pixel SVG is read at 96 dpi",
		_relative(area, expected) < AREA_TOLERANCE and str(result["note"]) != "",
		"%.1f mm² (want %.1f), note %s" % [area, expected,
			"present" if str(result["note"]) != "" else "MISSING"])


## `width` in mm against a viewBox in user units: the scale is the ratio, and the user units are
## not millimetres. A 200-unit square on a 100 mm wide artboard is 50 mm across, and nothing about
## the file says "50" anywhere.
static func _test_a_millimetre_svg_ignores_its_view_box_units() -> TestResult:
	var result := FrameImport.from_svg(
		_square_svg("width=\"100mm\" height=\"100mm\"", "0 0 200 200", 100.0))
	if str(result["error"]) != "":
		return TestResult.new("a mm SVG scales by its viewBox", false, str(result["error"]))
	var area := _total_area_mm2(result["loops"])
	return TestResult.new("a mm SVG scales by its viewBox",
		_relative(area, 50.0 * 50.0) < AREA_TOLERANCE and str(result["note"]) == "",
		"%.1f mm² (want 2500), note %s" % [area,
			"none" if str(result["note"]) == "" else str(result["note"])])


## The reason this is an XML parse and not a text search: geometry inside a transformed group is at
## the group's place, and a reader that finds `d="..."` strings alone puts it 40 mm away.
static func _test_a_group_transform_moves_what_it_contains() -> TestResult:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="200mm" height="200mm" ' + \
		'viewBox="0 0 200 200"><g transform="translate(40 25)">' + \
		'<rect x="0" y="0" width="10" height="10"/></g></svg>'
	var result := FrameImport.from_svg(svg)
	if str(result["error"]) != "" or (result["loops"] as Array).is_empty():
		return TestResult.new("a group transform is applied", false, "nothing read")
	var centre := PolygonProps.centroid((result["loops"] as Array)[0])
	return TestResult.new("a group transform is applied",
		centre.distance_to(Vector2(45.0, 30.0)) < EPS_MM,
		"centre at (%.2f, %.2f), want (45.00, 30.00)" % [centre.x, centre.y])


## A circle drawn as four arcs must come back a circle to within the stated chord tolerance, and
## the tolerance must actually bind: a curve flattened to its endpoints alone would come back as a
## square of area 2r², which is 36% light.
static func _test_a_curve_is_flattened_inside_its_tolerance() -> TestResult:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm" ' + \
		'viewBox="0 0 100 100"><path d="M 50 30 A 20 20 0 1 1 49.99 30 Z"/></svg>'
	var result := FrameImport.from_svg(svg)
	if str(result["error"]) != "" or (result["loops"] as Array).is_empty():
		return TestResult.new("an arc is flattened inside tolerance", false, "nothing read")
	var area := _total_area_mm2(result["loops"])
	var exact := PI * 20.0 * 20.0
	# The flattened polygon is inscribed, so it is a little light — bounded by the sagitta, not by
	# a number guessed here.
	var bound := TAU * 20.0 * FrameImport.CHORD_TOLERANCE_MM
	return TestResult.new("an arc is flattened inside tolerance",
		area <= exact and exact - area < bound,
		"%.2f mm² against %.2f exact, %.2f mm² allowed" % [area, exact, bound])


## Nesting, and the winding that makes it subtract.
static func _test_an_inner_loop_becomes_a_hole_that_subtracts() -> TestResult:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm" ' + \
		'viewBox="0 0 100 100"><rect x="10" y="10" width="40" height="40"/>' + \
		'<circle cx="30" cy="30" r="5"/></svg>'
	var result := FrameImport.from_svg(svg)
	var plates := FrameImport.plates_from_loops(result["loops"])
	if plates.size() != 1:
		return TestResult.new("an inner loop becomes a hole", false,
			"%d plates, want 1" % plates.size())
	var plate: Dictionary = plates[0]
	var holes := AirframeDocument.plate_holes(plate)
	var hole_area := 0.0 if holes.is_empty() else PolygonProps.area(holes[0])
	var properties := PolygonProps.region_properties(
		AirframeDocument.plate_outline(plate), holes)
	var expected := 40.0 * 40.0 - PI * 25.0
	return TestResult.new("an inner loop becomes a hole that subtracts",
		holes.size() == 1 and hole_area < 0.0
			and _relative(float(properties["area"]), expected) < AREA_TOLERANCE,
		"%d hole, signed area %.1f, region %.1f mm² (want %.1f)" % [
			holes.size(), hole_area, float(properties["area"]), expected])


## The stated limit of importing from a vector format, asserted rather than assumed.
##
## A hole that crosses its plate's edge — quad_x's 16 mm motor pattern on a 12 mm arm tip is the
## frame in the app that does this — is not inside anything, so containment cannot recover it and it
## returns as a separate outline. That is the honest reading of the file: an SVG says "here are some
## closed curves" and nothing more.
##
## The test exists so this is a KNOWN property with a name rather than a puzzling extra plate
## somebody hits at the cutter. If nesting is ever given a smarter rule, this is the test that
## records what changed.
static func _test_a_hole_over_an_edge_comes_back_as_its_own_outline() -> TestResult:
	var document := FrameEdits.new_frame("overhang")
	var plate := FrameEdits.add_rectangle(document, Vector2.ZERO, 20.0, 20.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	# Centred on the edge: half in, half out.
	FrameEdits.add_hole(document, plate, Vector2(10.0, 0.0), 6.0)
	var result := FrameImport.from_svg(
		FrameExport.to_svg(document, FrameExport.LAYOUT_ASSEMBLY, false))
	var read := FrameImport.plates_from_loops(result["loops"])
	var holes_found := 0
	for entry in read:
		holes_found += AirframeDocument.plate_holes(entry).size()
	return TestResult.new("a hole over an edge comes back as its own outline",
		read.size() == 2 and holes_found == 0,
		"%d outlines, %d holes — the format records no ownership" % [read.size(), holes_found])


# ---------------------------------------------------------------------------
# DXF
# ---------------------------------------------------------------------------

static func _test_lothal_dxf_round_trips_to_the_same_area() -> TestResult:
	var document := _round_trip_fixture()
	var dxf := FrameExport.to_dxf(document, FrameExport.LAYOUT_NEST)
	var result := FrameImport.from_dxf(dxf)
	if str(result["error"]) != "":
		return TestResult.new("an exported DXF reads back", false, str(result["error"]))
	var imported := AirframeDocument.new()
	imported.plates = FrameImport.plates_from_loops(result["loops"])
	var error := _relative(_document_area_mm2(imported), _document_area_mm2(document))
	return TestResult.new("an exported DXF reads back as the same area",
		error < AREA_TOLERANCE,
		"%d plates out of %d in, area off by %.3f%%" % [
			imported.plates.size(), document.plates.size(), error * 100.0])


## The form most CAD sketches export in: four unrelated LINE entities that only make a part once
## they are chained by their endpoints.
static func _test_loose_lines_are_chained_into_one_loop() -> TestResult:
	var corners := [Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]
	var body := PackedStringArray(["0\nSECTION\n2\nENTITIES"])
	# Deliberately out of order and with two segments reversed: the chainer must join on either end.
	for pair in [[0, 1], [2, 3], [1, 2], [0, 3]]:
		var a: Vector2 = corners[int(pair[0])]
		var b: Vector2 = corners[int(pair[1])]
		body.append("0\nLINE\n8\n0\n10\n%.4f\n20\n%.4f\n11\n%.4f\n21\n%.4f" % [a.x, a.y, b.x, b.y])
	body.append("0\nENDSEC\n0\nEOF")
	var result := FrameImport.from_dxf("\n".join(body))
	if str(result["error"]) != "":
		return TestResult.new("loose lines chain into a loop", false, str(result["error"]))
	var area := _total_area_mm2(result["loops"])
	return TestResult.new("loose lines chain into one loop",
		(result["loops"] as Array).size() == 1 and _relative(area, 400.0) < AREA_TOLERANCE,
		"%d loop(s), %.1f mm² (want 400)" % [(result["loops"] as Array).size(), area])


## Bulge is how a DXF says "this edge is an arc". Two vertices with bulge 1 are two half circles —
## a circle — and reading the bulge as zero gives a zero-area line instead.
static func _test_a_bulge_makes_an_arc_not_a_chord() -> TestResult:
	var dxf := "0\nSECTION\n2\nENTITIES\n0\nLWPOLYLINE\n8\n0\n90\n2\n70\n1\n" + \
		"10\n-10.0\n20\n0.0\n42\n1.0\n10\n10.0\n20\n0.0\n42\n1.0\n0\nENDSEC\n0\nEOF"
	var result := FrameImport.from_dxf(dxf)
	if str(result["error"]) != "":
		return TestResult.new("a bulge becomes an arc", false, str(result["error"]))
	var area := _total_area_mm2(result["loops"])
	var exact := PI * 100.0
	return TestResult.new("a bulge becomes an arc, not a chord",
		area > exact * 0.98 and area <= exact,
		"%.1f mm² against %.1f for the circle (a dropped bulge gives 0)" % [area, exact])


## Refused whole, with the reason named. See the header: a plate short one edge is the failure that
## survives every check up to the cutter.
static func _test_a_spline_dxf_is_refused_whole() -> TestResult:
	var dxf := "0\nSECTION\n2\nENTITIES\n" + \
		"0\nLWPOLYLINE\n8\n0\n90\n3\n70\n1\n10\n0\n20\n0\n10\n20\n20\n0\n10\n20\n20\n20\n" + \
		"0\nSPLINE\n8\n0\n10\n0\n20\n0\n10\n5\n20\n5\n0\nENDSEC\n0\nEOF"
	var result := FrameImport.from_dxf(dxf)
	var message := str(result["error"])
	return TestResult.new("a DXF with a spline is refused whole",
		message.to_lower().contains("spline") and (result["loops"] as Array).is_empty(),
		"error: %s" % ("none — the polyline was imported anyway" if message == "" else message))


# ---------------------------------------------------------------------------
# Landing in a document
# ---------------------------------------------------------------------------

## An artboard 300 mm from the origin still lands where the builder is looking.
static func _test_an_import_lands_centred_on_the_origin() -> TestResult:
	var result := FrameImport.from_svg(
		'<svg xmlns="http://www.w3.org/2000/svg" width="400mm" height="400mm" ' +
		'viewBox="0 0 400 400"><rect x="300" y="300" width="40" height="20"/></svg>')
	var document := FrameEdits.new_frame("import")
	var added := FrameImport.into_document(document, result["loops"])
	var centre := PolygonProps.centroid(
		AirframeDocument.plate_outline(document.plates[0]))
	return TestResult.new("an import lands centred on the origin",
		int(added["count"]) == 1 and centre.length() < EPS_MM
			and (added["span_mm"] as Vector2).distance_to(Vector2(40.0, 20.0)) < EPS_MM,
		"centre (%.2f, %.2f), span %.1f × %.1f" % [centre.x, centre.y,
			(added["span_mm"] as Vector2).x, (added["span_mm"] as Vector2).y])


## No SVG says which end of a shape is bolted to an aircraft, so an imported plate is not an arm and
## `AirframePanel` must not be able to measure a beam off it.
static func _test_an_imported_plate_is_never_an_arm() -> TestResult:
	var result := FrameImport.from_svg(
		'<svg xmlns="http://www.w3.org/2000/svg" width="200mm" height="200mm" ' +
		'viewBox="0 0 200 200"><rect x="0" y="0" width="110" height="16"/></svg>')
	var document := FrameEdits.new_frame("import")
	FrameImport.into_document(document, result["loops"])
	var plate: Dictionary = document.plates[0]
	return TestResult.new("an imported plate is never an arm",
		str(plate.get("role", "")) != AirframeDocument.ROLE_ARM
			and not plate.has("root_point") and not plate.has("tip_point"),
		"role %s" % str(plate.get("role", "?")))


## The point of importing at all: the geometry is weighed, by the same integral as everything else.
static func _test_an_import_adds_the_mass_it_drew() -> TestResult:
	var document := FrameEdits.new_frame("import")
	var materials := FrameMaterials.load_default()
	var before := AirframeProperties.compute(document, materials)
	var result := FrameImport.from_svg(
		'<svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm" ' +
		'viewBox="0 0 100 100"><rect x="0" y="0" width="50" height="40"/></svg>')
	FrameImport.into_document(document, result["loops"],
		FrameEdits.DEFAULT_PLATE_THICKNESS_MM)
	var after := AirframeProperties.compute(document, materials)
	var density := materials.density(document.material_id)
	var expected_g := 50.0 * 40.0 * FrameEdits.DEFAULT_PLATE_THICKNESS_MM * 1.0e-9 * density * 1000.0
	var gained := (after.total_mass_kg - before.total_mass_kg) * 1000.0
	return TestResult.new("an imported outline is weighed like any other plate",
		_relative(gained, expected_g) < AREA_TOLERANCE,
		"%.2f g gained, rho*t*A says %.2f g" % [gained, expected_g])


# ---------------------------------------------------------------------------
# Refusal
# ---------------------------------------------------------------------------

## Atomic: a file that cannot be read leaves the frame exactly as it was.
static func _test_a_refused_file_leaves_the_document_alone() -> TestResult:
	var document := FrameLayouts.build("quad_x")
	var before := document.plates.size()
	var area_before := _document_area_mm2(document)
	var result := FrameImport.from_svg("this is not xml at all <<<")
	if str(result["error"]) != "":
		FrameImport.into_document(document, result["loops"])
	return TestResult.new("a refused file leaves the document alone",
		str(result["error"]) != "" and document.plates.size() == before
			and is_equal_approx(_document_area_mm2(document), area_before),
		"%d plates before, %d after" % [before, document.plates.size()])


## An SVG of text and nothing else is an ERROR, not a successful import of zero parts. The two look
## identical to a caller that only checks whether plates were added, and only one of them should
## put a sentence on the status line.
static func _test_an_empty_svg_is_an_error_not_an_empty_frame() -> TestResult:
	var result := FrameImport.from_svg(
		'<svg xmlns="http://www.w3.org/2000/svg" width="50mm" height="50mm" ' +
		'viewBox="0 0 50 50"><text x="1" y="1">cut here</text></svg>')
	return TestResult.new("an SVG with no outline is an error",
		str(result["error"]) != "" and (result["loops"] as Array).is_empty(),
		"error: %s" % ("none" if str(result["error"]) == "" else str(result["error"])))


static func _test_an_unknown_extension_is_refused_by_name() -> TestResult:
	var path := "user://test_frame_import.stl"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return TestResult.new("an unknown extension is refused", false, "could not write fixture")
	file.store_string("solid x\nendsolid\n")
	file.close()
	var result := FrameImport.read_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var message := str(result["error"])
	return TestResult.new("an unknown extension is refused by name",
		message.contains("SVG") and message.contains("DXF"),
		"error: %s" % ("none" if message == "" else message))
