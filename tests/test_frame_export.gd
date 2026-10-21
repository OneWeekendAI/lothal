class_name TestFrameExport
extends RefCounted
## The files a frame leaves Lothal as: a printable sheet, a cut file and a solid.
##
## ## Why an export needs tests at all
##
## Because its failures are silent and expensive. An SVG whose `width` and `viewBox` disagree still
## opens, still looks right on screen, and prints at 94% — so the plate comes back from the cutter
## 6 mm short and nothing anywhere said so. A DXF missing its closed-polyline flag loads in every
## viewer and leaves one edge uncut. An STL with both cap faces wound the same way renders fine and
## is rejected as non-manifold by the slicer three days later. None of these show up by looking.
##
## So every test below asserts the property that MAKES the file correct rather than the presence of
## the text: the scale is 1:1, the contours are closed, the parts do not overlap, the normals point
## outward.
##
## ## MUTATION NOTES
##
##   - `_test_the_sheet_is_one_to_one` fails if the `mm` suffix is dropped from width/height, which
##     is the single most consequential character in the file — without it the sheet scales to the
##     page and every printed dimension is wrong by an amount that depends on the printer.
##   - `_test_a_cut_sheet_does_not_overlap_its_own_parts` fails if the nesting is skipped, which is
##     what an assembly drawing sent to a cutter looks like: four arms crossing one centre plate,
##     cut as one tangled contour.
##   - `_test_every_contour_is_closed` fails if the DXF `70/1` flag goes.
##   - `_test_the_solid_is_closed` fails if the bottom cap is wound like the top: the facet count is
##     unchanged and every normal still has unit length, so only the sum of the outward normals
##     catches it.
##   - `_test_the_solid_has_its_holes` fails on the STL writer as it was before printable parts: it
##     extruded the OUTLINE only, so a printed plate came off the bed with no screw holes at all.
##     Caught by volume, which a solid with its holes filled in overshoots by exactly the holes.
##   - `_test_one_layer_prints_as_one_solid` fails if a layer is not merged (each plate its own
##     part, as the old writer emitted them): four arm solids that each reach the centre, opposite
##     arms sharing their root corners — edges with four faces, which `StlWriter.check_manifold`
##     reports as inconsistent winding. Also fails if the holes of one member are not cut through the
##     merged part (the stack holes lie under the arm roots).
##   - `_test_a_sliver_does_not_open_the_solid` fails if a zero-area cap triangle is DROPPED rather
##     than folded into its neighbour (`_split_slivers`): eight edges open on the unibody of the
##     3" printed frame this test rebuilds, which is where it was found.

const EPS := 1.0e-6


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_sheet_is_one_to_one())
	results.append(_test_the_sheet_carries_every_contour())
	results.append(_test_a_cut_sheet_does_not_overlap_its_own_parts())
	results.append(_test_every_contour_is_closed())
	results.append(_test_the_solid_is_closed())
	results.append(_test_the_solid_has_its_holes())
	results.append(_test_one_layer_prints_as_one_solid())
	results.append(_test_a_sliver_does_not_open_the_solid())
	results.append(_test_every_part_writes_as_its_own_closed_solid())
	results.append(_test_a_frame_name_cannot_break_the_file())
	results.append(_test_writing_lands_on_disk())
	return results


static func _frame() -> AirframeDocument:
	return FrameLayouts.build("quad_x", {"arm_length_mm": 110.0})


## 1 user unit = 1 mm, which is what makes the print measurable against the part.
##
## Checked as a RATIO of the declared width to the viewBox width rather than by matching a string:
## the numbers are computed from the drawing's bounds, so hard-coding them here would just be a
## second copy of the arithmetic, and a test that copies the code it tests proves nothing.
static func _test_the_sheet_is_one_to_one() -> TestResult:
	var svg := FrameExport.to_svg(_frame())
	var width_mm := _number_after(svg, 'width="')
	var view_box := _view_box(svg)
	var height_mm := _number_after(svg, 'height="')
	var declares_mm := svg.contains('width="%.3fmm"' % width_mm)
	return TestResult.new(
		"the printed sheet is 1:1 — its millimetre size and its user units are the same number",
		declares_mm and absf(width_mm - view_box.z) < 0.01
			and absf(height_mm - view_box.w) < 0.01 and width_mm > 100.0,
		"%.1f × %.1f mm over a %.1f × %.1f viewBox" % [
			width_mm, height_mm, view_box.z, view_box.w])


## Every outline and every hole reaches the file. A hole that does not is a bolt hole somebody
## drills by eye afterwards, at which point the motor pattern is whatever their eye was.
static func _test_the_sheet_carries_every_contour() -> TestResult:
	var document := _frame()
	var contours := 0
	for plate in document.plates:
		contours += 1 + AirframeDocument.plate_holes(plate).size()
	var svg := FrameExport.to_svg(document)
	var paths := svg.count('<path d="M')
	return TestResult.new(
		"every plate outline and every hole is drawn on the sheet",
		paths == contours and contours > 4,
		"%d paths for %d contours" % [paths, contours])


## An assembly drawing has its arms crossing its centre plate, which is correct for a picture and
## catastrophic for a cutter: the overlapping contours are cut as drawn. The nested sheet has to
## pull the parts apart, and "apart" means no two bounding boxes intersect.
static func _test_a_cut_sheet_does_not_overlap_its_own_parts() -> TestResult:
	var document := _frame()
	var svg := FrameExport.to_svg(document, FrameExport.LAYOUT_NEST)
	var boxes := _path_boxes(svg, document)
	var overlaps := 0
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if (boxes[i] as Rect2).intersects(boxes[j] as Rect2):
				overlaps += 1
	# The assembly layout is asserted to overlap, because a test that only checks the nested sheet
	# would pass just as happily on a frame whose plates never touched in the first place.
	var assembly_boxes := _path_boxes(
		FrameExport.to_svg(document, FrameExport.LAYOUT_ASSEMBLY), document)
	var assembly_overlaps := 0
	for i in assembly_boxes.size():
		for j in range(i + 1, assembly_boxes.size()):
			if (assembly_boxes[i] as Rect2).intersects(assembly_boxes[j] as Rect2):
				assembly_overlaps += 1
	return TestResult.new(
		"a cut sheet separates the plates that an assembly drawing shows overlapping",
		overlaps == 0 and assembly_overlaps > 0,
		"%d overlaps nested, %d in the assembly drawing" % [overlaps, assembly_overlaps])


## Every DXF contour closed, and one polyline per contour. An unclosed polyline leaves the part
## attached to the sheet by its last edge.
static func _test_every_contour_is_closed() -> TestResult:
	var document := _frame()
	var contours := 0
	var vertices := 0
	for plate in document.plates:
		contours += 1
		vertices += AirframeDocument.plate_outline(plate).size()
		for hole in AirframeDocument.plate_holes(plate):
			contours += 1
			vertices += hole.size()
	var dxf := FrameExport.to_dxf(document)
	return TestResult.new(
		"every contour in the cut file is a closed polyline with all of its vertices",
		dxf.count("\nPOLYLINE\n") == contours and dxf.count("\n70\n1") == contours
			and dxf.count("\nVERTEX\n") == vertices and dxf.ends_with("EOF\n"),
		"%d polylines, %d closed, %d vertices (wanted %d/%d/%d)" % [
			dxf.count("\nPOLYLINE\n"), dxf.count("\n70\n1"), dxf.count("\nVERTEX\n"),
			contours, contours, vertices])


## A closed solid: every facet has a unit normal, and the outward normals of a closed body sum to
## nothing. The second half is the one that catches a cap wound the wrong way — a fault that
## changes no count and no length, only a direction.
static func _test_the_solid_is_closed() -> TestResult:
	var stl := FrameExport.to_stl(_frame())
	var total := Vector3.ZERO
	var facets := 0
	var bad_length := 0
	for line in stl.split("\n"):
		if not line.begins_with("facet normal"):
			continue
		var parts := line.split(" ", false)
		var normal := Vector3(float(parts[2]), float(parts[3]), float(parts[4]))
		facets += 1
		if absf(normal.length() - 1.0) > 1.0e-3:
			bad_length += 1
		total += normal
	return TestResult.new(
		"the exported solid is closed — unit normals that cancel over the whole body",
		facets > 40 and bad_length == 0 and total.length() < 0.01 * float(facets),
		"%d facets, %d off-length, normals sum to %.4f" % [facets, bad_length, total.length()])


## A plate with holes prints with its holes. The solid's volume is the plate's AREA NET OF ITS HOLES
## times its thickness — the one number a filled-in hole cannot fake — and it is still a closed,
## outward-wound body by `StlWriter`'s directed-edge check.
static func _test_the_solid_has_its_holes() -> TestResult:
	var document := AirframeDocument.new()
	var plate := FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 30.0, 3.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	FrameEdits.add_hole(document, plate, Vector2(-10.0, 0.0), 3.2)
	FrameEdits.add_hole(document, plate, Vector2(10.0, 5.0), 6.0)
	var holes_area := 0.0
	for hole in AirframeDocument.plate_holes(document.plates[plate]):
		holes_area += absf(PolygonProps.area(hole))
	var expected := (40.0 * 30.0 - holes_area) * 3.0
	var report := StlWriter.check_manifold(_triangles_of(FrameExport.to_stl(document)))
	var volume := float(report["volume_mm3"])
	return TestResult.new(
		"an exported plate is a closed solid with its holes cut through (volume net of the holes)",
		bool(report["ok"]) and absf(volume - expected) < 0.01,
		"%.3f mm³ against %.3f net (%.3f with the holes filled); %s" % [volume, expected,
			40.0 * 30.0 * 3.0, ", ".join(PackedStringArray(report["reasons"]))])


## Arms and a bottom plate on one layer — the unibody — print as ONE closed solid, with the stack holes
## that lie under the arm roots cut through it.
static func _test_one_layer_prints_as_one_solid() -> TestResult:
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 70.0, "arm_thickness_mm": 4.0,
		"plate_thickness_mm": 4.0, "stack_pitch_mm": 30.5})
	var parts := FrameExport.printable_parts(document)
	var triangles: Array = []
	for part in parts:
		triangles.append_array(FrameExport.part_triangles(part, float(part["z_mm"])))
	var report := StlWriter.check_manifold(triangles)
	var unibody: Dictionary = {}
	for part in parts:
		if (part["plates"] as Array).size() == 5:
			unibody = part
	var stack_holes := 0
	if not unibody.is_empty():
		for hole in unibody["holes"]:
			var centre := PolygonProps.centroid(hole)
			if absf(absf(centre.x) - 15.25) < 0.01 and absf(absf(centre.y) - 15.25) < 0.01:
				stack_holes += 1
	return TestResult.new(
		"arms and bottom plate on one layer export as one closed solid, stack holes cut through",
		bool(report["ok"]) and not unibody.is_empty() and stack_holes == 4,
		"%d parts, unibody found: %s, %d of 4 stack holes; %s" % [parts.size(),
			not unibody.is_empty(), stack_holes, ", ".join(PackedStringArray(report["reasons"]))])


## The triangulator can hand back a triangle whose corners are collinear — the leftmost points of
## two holes stacked one above the other, joined through a bridge. That frame is rebuilt here (the
## 3" printed quad X it was found on), the sliver's presence is asserted first so the test cannot
## pass by not meeting one, and the solid must still be closed.
static func _test_a_sliver_does_not_open_the_solid() -> TestResult:
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 75.0, "arm_root_width_mm": 24.0,
		"arm_tip_width_mm": 20.0, "arm_thickness_mm": 6.0, "plate_thickness_mm": 6.0,
		"plate_side_mm": 46.0, "motor_pitch_mm": 12.0, "stack_pitch_mm": 34.0})
	var bottom := -1
	for index in document.plates.size():
		if str(document.plates[index].get("role", "")) == AirframeDocument.ROLE_BOTTOM:
			bottom = index
	var square := AirframeDocument.plate_outline(document.plates[bottom])
	FrameEdits.move_vertex(document, bottom, 0, square[0] + Vector2(0.0, -8.0))
	FrameEdits.move_vertex(document, bottom, 1, square[1] + Vector2(0.0, -8.0))
	FrameEdits.move_vertex(document, bottom, 2, square[2] + Vector2(0.0, 13.5))
	FrameEdits.move_vertex(document, bottom, 3, square[3] + Vector2(0.0, 13.5))
	FrameEdits.add_stack_mount(document, bottom, Vector2.ZERO, "20x20")
	var unibody: Dictionary = FrameExport.printable_parts(document)[0]
	var polygon := FrameExport.keyhole(unibody["outlines"][0], unibody["holes"])
	var indices := Geometry2D.triangulate_polygon(polygon)
	var slivers := 0
	var index := 0
	while index + 2 < indices.size():
		var a := polygon[indices[index]]
		if absf((polygon[indices[index + 1]] - a).cross(polygon[indices[index + 2]] - a)) < 2.0e-9:
			slivers += 1
		index += 3
	var report := StlWriter.check_manifold(FrameExport.part_triangles(unibody))
	return TestResult.new(
		"a zero-area triangle from the triangulator is folded away, not dropped — the solid stays closed",
		slivers > 0 and bool(report["ok"]),
		"%d sliver(s) met; %s" % [slivers, ", ".join(PackedStringArray(report["reasons"]))])


## One file per part, each on the bed (z from 0 to its thickness) and each passing the manifold
## check `StlWriter.write` refuses on — a camera cage's two upright plates included.
static func _test_every_part_writes_as_its_own_closed_solid() -> TestResult:
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 70.0, "arm_thickness_mm": 4.0,
		"plate_thickness_mm": 4.0, "stack_pitch_mm": 30.5})
	FrameEdits.add_camera_cage(document, 19.0, 3.0)
	var directory := "user://test_exports/parts"
	var results := FrameExport.write_parts(document, directory, "frame")
	var good := 0
	var on_bed := 0
	for entry in results:
		if not bool(entry["ok"]):
			continue
		good += 1
		var lowest := INF
		for triangle in _triangles_of(FileAccess.get_file_as_string(str(entry["path"]))):
			for point in triangle:
				lowest = minf(lowest, (point as Vector3).z)
		if absf(lowest) < 1.0e-4:
			on_bed += 1
		DirAccess.remove_absolute(str(entry["path"]))
	# bottom+4 arms, top, and the cage's two sides.
	return TestResult.new(
		"every printable part writes to its own closed STL, lying on the bed",
		results.size() == 4 and good == 4 and on_bed == 4,
		"%d parts, %d written, %d on the bed: %s" % [results.size(), good, on_bed,
			JSON.stringify(results)])


static func _triangles_of(stl: String) -> Array:
	var triangles: Array = []
	var current := PackedVector3Array()
	for line in stl.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("vertex"):
			continue
		var parts := text.split(" ", false)
		current.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
		if current.size() == 3:
			triangles.append(current)
			current = PackedVector3Array()
	return triangles


## A frame called `5" X <v2> & co` is a frame somebody will name, and an unescaped quote in the
## title element is a file no viewer opens.
static func _test_a_frame_name_cannot_break_the_file() -> TestResult:
	var document := _frame()
	document.name = '5" X <v2> & co'
	var svg := FrameExport.to_svg(document)
	var title := svg.substr(svg.find("<title>") + 7)
	title = title.substr(0, title.find("</title>"))
	return TestResult.new(
		"a frame name with quotes and angle brackets is escaped rather than emitted raw",
		not title.contains("<v2>") and title.contains("&lt;v2&gt;") and title.contains("&amp;"),
		title)


## The extension chooses the format, and an unknown one is refused rather than written as
## something else. A `.step` that silently contained an STL would be a file somebody sends to a
## machinist.
static func _test_writing_lands_on_disk() -> TestResult:
	var document := _frame()
	var directory := "user://test_exports"
	DirAccess.make_dir_recursive_absolute(directory)
	var wrote_svg := FrameExport.write(document, "%s/frame.svg" % directory)
	var wrote_dxf := FrameExport.write(document, "%s/frame.dxf" % directory)
	var refused := FrameExport.write(document, "%s/frame.step" % directory)
	var svg_text := FileAccess.get_file_as_string("%s/frame.svg" % directory)
	var dxf_text := FileAccess.get_file_as_string("%s/frame.dxf" % directory)
	for name in ["frame.svg", "frame.dxf"]:
		DirAccess.remove_absolute("%s/%s" % [directory, name])
	return TestResult.new(
		"the extension picks the format, and an unknown one is refused rather than mis-written",
		wrote_svg and wrote_dxf and not refused
			and svg_text.begins_with("<?xml") and dxf_text.contains("POLYLINE")
			and not FileAccess.file_exists("%s/frame.step" % directory),
		"svg %d bytes, dxf %d bytes, .step refused: %s" % [
			svg_text.length(), dxf_text.length(), not refused])


# ---------------------------------------------------------------------------
# Reading the files back
# ---------------------------------------------------------------------------

static func _number_after(text: String, key: String) -> float:
	var start := text.find(key)
	if start < 0:
		return 0.0
	return float(text.substr(start + key.length()))


static func _view_box(svg: String) -> Vector4:
	var start := svg.find('viewBox="')
	if start < 0:
		return Vector4.ZERO
	var rest := svg.substr(start + 9)
	var parts := rest.substr(0, rest.find('"')).split(" ")
	if parts.size() < 4:
		return Vector4.ZERO
	return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


## The bounding box of each PLATE OUTLINE in an SVG, in file order. Holes are skipped by counting
## contours the same way the writer emits them: one outline followed by that plate's holes.
static func _path_boxes(svg: String, document: AirframeDocument) -> Array:
	var boxes: Array = []
	var paths: Array = []
	var cursor := 0
	while true:
		var start := svg.find('<path d="', cursor)
		if start < 0:
			break
		var rest := svg.substr(start + 9)
		paths.append(rest.substr(0, rest.find('"')))
		cursor = start + 9
	var index := 0
	for plate in document.plates:
		if index >= paths.size():
			break
		boxes.append(_box_of(str(paths[index])))
		index += 1 + AirframeDocument.plate_holes(plate).size()
	return boxes


static func _box_of(path: String) -> Rect2:
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	var tokens := path.split(" ", false)
	var index := 0
	while index + 2 < tokens.size():
		if tokens[index] == "M" or tokens[index] == "L":
			var point := Vector2(float(tokens[index + 1]), float(tokens[index + 2]))
			lowest = lowest.min(point)
			highest = highest.max(point)
			index += 3
		else:
			index += 1
	if not is_finite(lowest.x):
		return Rect2()
	return Rect2(lowest, highest - lowest)
