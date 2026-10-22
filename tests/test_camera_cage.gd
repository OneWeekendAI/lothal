class_name TestCameraCage
extends RefCounted
## Camera side plates — airframe gaps build plan, slice G5. Upright plates in the document
## (`AirframeDocument.is_upright`), their mass/CG/tensor (`AirframeProperties`), "+ Camera cage"
## (`FrameEdits.add_camera_cage`, `CameraCage`), the upright drawing (`FrameModel`, `AirframeModel`),
## the flat export (`FrameExport`) and the camera-width warning (`CameraCage.warnings`).
##
## Where each check could pass while proving nothing, and what stops it:
##   - the mass delta is asserted EXACT against area × t × ρ computed here from `PolygonProps.area` of
##     each contour, not from `region_properties` (the function the code under test integrates with).
##   - the standing-plate tensor is checked against the closed-form BOX, and the product of inertia
##     against a right triangle's −a²b²/72, both written here. A plate weighed as if flat has
##     I_yy = m(L²+H²)/12 instead of m(L²+t²)/12 — five orders off on this box.
##   - "tall, not flat" compares the drawn AABB's height with the plate's own h extent AND its width
##     with the stock thickness, so a mesh left flat (height = t) fails both ways.
##   - the export check requires side-plate vertices to EXIST to the right of the frame (a count, so
##     an STL with no side plates cannot pass by having nothing to check) and every one at 0 ≤ z ≤ t.
##   - the warning is asserted both ways, and with a 20 mm camera against a 19 mm cage: a spacing
##     measured centre-to-centre (21 mm) would let that one through.
##   Mutation-checked in src/ for the G5 report: see the MUTATIONS block at the end of this file.

const REL := 1.0e-9
const FIXTURE_FRAME_ID := "frame_5in_freestyle"


static func run() -> Array:
	var sections := {}
	var catalog := PartsCatalog.load_default()
	sections["mass and cg"] = _mass_and_cg(catalog)
	sections["standing box"] = _standing_box_matches_closed_form()
	sections["standing product"] = [_standing_triangle_product_of_inertia()]
	sections["geometry"] = _cage_geometry(catalog)
	sections["ready to cut"] = _cage_is_ready_to_cut(catalog)
	sections["3d"] = _drawn_standing(catalog)
	sections["export"] = _exported_flat(catalog)
	sections["warning"] = _camera_width_warning(catalog)
	sections["workbench"] = _workbench_button(catalog)
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("camera cage: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


# ---------------------------------------------------------------------------
# Mass, CG, inertia
# ---------------------------------------------------------------------------

static func _mass_and_cg(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var materials := FrameMaterials.load_default()
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
	var before := AirframeProperties.compute(document, materials)
	var added := FrameEdits.add_camera_cage(document, 19.0)
	var after := AirframeProperties.compute(document, materials)

	# Expected: each new plate's net area (outline minus holes, by the shoelace area) × t × ρ.
	var expected_g := 0.0
	for index in added:
		var plate: Dictionary = document.plates[index]
		var area := absf(PolygonProps.area(AirframeDocument.plate_outline(plate)))
		for hole in AirframeDocument.plate_holes(plate):
			area -= absf(PolygonProps.area(hole))
		expected_g += area * AirframeDocument.plate_thickness_mm(plate) * 1.0e-9 \
			* materials.density(document.plate_material_id(plate)) * 1000.0
	var delta_g := after.total_mass_g() - before.total_mass_g()
	out.append(TestResult.new(
		"+ Camera cage adds exactly its two plates' area × t × ρ to the frame's mass",
		added.size() == 2 and expected_g > 0.5 and absf(delta_g - expected_g) <= expected_g * 1.0e-9,
		"%d plates, Δm %.9f g, expected %.9f g" % [added.size(), delta_g, expected_g]))

	var moved := after.cg_m - before.cg_m
	out.append(TestResult.new("the cage moves the CG forward (−Z) and up (+Y)",
		moved.z < -1.0e-5 and moved.y > 1.0e-5,
		"CG moved by (%.3f, %.3f, %.3f) mm" % [moved.x * 1000.0, moved.y * 1000.0, moved.z * 1000.0]))
	out.append(TestResult.new("a mirrored cage leaves the CG on the centreline",
		absf(after.cg_m.x - before.cg_m.x) < 1.0e-9,
		"ΔX %s m" % _sci(after.cg_m.x - before.cg_m.x)))
	return out


## A standing rectangle L (along s) × H (along h) × t, at x = 12, base 5 mm: the box closed form.
static func _standing_box_matches_closed_form() -> Array:
	var out: Array = []
	var l := 30.0
	var h := 16.0
	var t := 3.0
	var document := AirframeDocument.new()
	var outline := PackedVector2Array([Vector2(-10.0, 0.0), Vector2(20.0, 0.0), Vector2(20.0, h),
		Vector2(-10.0, h)])
	document.plates.append(AirframeDocument.make_side_plate(outline, [], t, 12.0, 5.0))
	var materials := FrameMaterials.load_default()
	var props := AirframeProperties.compute(document, materials)
	var rho := materials.density(document.material_id)
	var m := rho * l * h * t * 1.0e-9
	var lm := l / 1000.0
	var hm := h / 1000.0
	var tm := t / 1000.0
	var want := {
		"mass": m,
		"i_xx": m * (lm * lm + hm * hm) / 12.0,
		"i_yy": m * (lm * lm + tm * tm) / 12.0,
		"i_zz": m * (hm * hm + tm * tm) / 12.0,
	}
	var got := {"mass": props.total_mass_kg, "i_xx": props.i_xx, "i_yy": props.i_yy,
		"i_zz": props.i_zz}
	for key in ["mass", "i_xx", "i_yy", "i_zz"]:
		var rel := absf(float(got[key]) - float(want[key])) / float(want[key])
		out.append(TestResult.new("standing box: %s matches the closed form" % key, rel < REL,
			"got %s, want %s (rel %s)" % [_sci(got[key]), _sci(want[key]), _sci(rel)]))
	var products := absf(props.i_xy) + absf(props.i_xz) + absf(props.i_yz)
	out.append(TestResult.new("standing box: no products of inertia about its centroid",
		products < float(want["i_zz"]) * REL, "|Ixy|+|Ixz|+|Iyz| = %s" % _sci(products)))
	var cg_mm := props.cg_m * 1000.0
	out.append(TestResult.new("standing box: CG at (x, base + H/2, mid-s)",
		cg_mm.distance_to(Vector3(12.0, 5.0 + h * 0.5, 5.0)) < 1.0e-4,
		"CG (%.5f, %.5f, %.5f) mm" % [cg_mm.x, cg_mm.y, cg_mm.z]))
	return out


## A right triangle, legs a along s and b along h: ∫(s−s̄)(h−h̄) dA = −a²b²/72, so the tensor's
## I_YZ = −ρt·(−a²b²/72) and the other two products stay zero.
static func _standing_triangle_product_of_inertia() -> TestResult:
	var a := 24.0
	var b := 18.0
	var t := 2.0
	var document := AirframeDocument.new()
	document.plates.append(AirframeDocument.make_side_plate(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(a, 0.0), Vector2(0.0, b)]), [], t, -7.0, 0.0))
	var materials := FrameMaterials.load_default()
	var props := AirframeProperties.compute(document, materials)
	var rho_t := materials.density(document.material_id) * t / 1000.0
	var want := rho_t * a * a * b * b / 72.0 * 1.0e-12
	var rel := absf(props.i_yz - want) / want
	return TestResult.new("standing triangle: I_yz = ρt·a²b²/72, I_xy = I_xz = 0",
		rel < 1.0e-6 and absf(props.i_xy) < want * 1.0e-9 and absf(props.i_xz) < want * 1.0e-9,
		"I_yz %s want %s (rel %s), I_xy %s, I_xz %s" % [_sci(props.i_yz), _sci(want), _sci(rel),
			_sci(props.i_xy), _sci(props.i_xz)])


# ---------------------------------------------------------------------------
# The cage's own geometry
# ---------------------------------------------------------------------------

static func _cage_geometry(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for size in ["nano", "micro", "full"]:
		var width := CameraCage.size_width_mm(size, catalog)
		var document := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
		FrameEdits.add_camera_cage(document, width)
		var spacing := CameraCage.spacing_mm(document)
		out.append(TestResult.new("%s cage: inner faces exactly the camera width apart" % size,
			width > 0.0 and absf(spacing - width) < 1.0e-9,
			"width %.3f mm, spacing %.6f mm" % [width, spacing]))
	# Catalog widths, as published in cameras.json (nano 14, micro 19, full-size 26).
	out.append(TestResult.new("cage sizes read cameras.json widths",
		CameraCage.size_width_mm("nano", catalog) == 14.0
			and CameraCage.size_width_mm("micro", catalog) == 19.0
			and CameraCage.size_width_mm("full", catalog) == 26.0,
		"%.2f / %.2f / %.2f" % [CameraCage.size_width_mm("nano", catalog),
			CameraCage.size_width_mm("micro", catalog), CameraCage.size_width_mm("full", catalog)]))

	# The slot carries the second screw from 0° to 50° of uptilt, and not to 60°.
	var profile := CameraCage.plate_profile(19.0)
	var pivot: Vector2 = profile["pivot"]
	var slot: PackedVector2Array = (profile["holes"] as Array)[1]
	var radius := 19.0 * CameraCage.SLOT_RADIUS_PER_WIDTH
	var inside := 0
	for tilt in [0.0, 25.0, 50.0]:
		var screw := pivot + Vector2(cos(-deg_to_rad(tilt)), sin(-deg_to_rad(tilt))) * radius
		if Geometry2D.is_point_in_polygon(screw, slot):
			inside += 1
	var beyond := pivot + Vector2(cos(-deg_to_rad(60.0)), sin(-deg_to_rad(60.0))) * radius
	out.append(TestResult.new("the tilt slot holds the screw at 0°, 25° and 50°, not at 60°",
		inside == 3 and not Geometry2D.is_point_in_polygon(beyond, slot),
		"%d of 3 inside, 60° inside: %s" % [inside, Geometry2D.is_point_in_polygon(beyond, slot)]))
	out.append(TestResult.new("the slot subtracts (wound clockwise)", PolygonProps.area(slot) < 0.0,
		"area %.3f" % PolygonProps.area(slot)))
	return out


## Rounded to the bit: nothing to warn about with the default 1/16" bit, for every size. And the
## same plates DO warn with a 1/8" bit, which is wider than the 2.2 mm slot — proof the check sees
## the slot rather than passing because it never looked.
static func _cage_is_ready_to_cut(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for size in ["nano", "micro", "full"]:
		var document := FrameEdits.new_frame("cage")
		FrameEdits.add_camera_cage(document, CameraCage.size_width_mm(size, catalog))
		var warnings := ReadyToCut.warnings(document)
		var ids: Array = []
		for warning in warnings:
			ids.append(str(warning.id))
		out.append(TestResult.new("%s cage passes ready-to-cut with the 1/16\" bit" % size,
			document.plates.size() == 2 and warnings.is_empty(), "warnings %s" % [ids]))
	var wide := FrameEdits.new_frame("cage")
	FrameEdits.add_camera_cage(wide, 19.0)
	FrameEdits.set_cutting_bit(wide, 3.175)
	var narrow := 0
	for warning in ReadyToCut.warnings(wide):
		if warning.id == ReadyToCut.NARROW_GAP:
			narrow += 1
	out.append(TestResult.new("the same cage warns about its 2.2 mm slot under a 1/8\" bit",
		narrow == 2, "%d narrow-gap warnings (want one per plate)" % narrow))
	return out


# ---------------------------------------------------------------------------
# Drawn standing
# ---------------------------------------------------------------------------

static func _drawn_standing(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var frame := catalog.get_part(FIXTURE_FRAME_ID)
	var document := AirframeDocument.from_catalog_frame(frame)
	FrameEdits.add_camera_cage(document, 19.0)
	var plate_height := 19.0 * CameraCage.PLATE_HEIGHT_PER_WIDTH

	var model := FrameModel.new()
	model.rebuild_document(document, frame, -1.0)
	out.append(_standing_check("frame 3D view", model, plate_height))
	model.free()

	var airframe := AirframeModel.new()
	var build := Build.from_ids(catalog, FIXTURE_FRAME_ID, "motor_2207_1960kv", "prop_5x43x3",
		"battery_4s_1500")
	airframe.rebuild(build, null, document)
	out.append(_standing_check("assembled aircraft", airframe.frame_model, plate_height))
	# Standing ON the bottom plate: the plate's lowest point is the bottom plate's upper face.
	var bottom := airframe.frame_model.get_node_or_null("PlateBottom") as MeshInstance3D
	var low := INF
	for record in airframe.frame_model.side_plates:
		var node: MeshInstance3D = record["node"]
		low = minf(low, (node.transform * node.mesh.get_aabb()).position.y)
	var face := INF
	if bottom != null:
		face = (bottom.transform * bottom.mesh.get_aabb()).end.y
	out.append(TestResult.new("assembled aircraft: the cage stands on the bottom plate's upper face",
		bottom != null and absf(low - face) < 1.0e-5,
		"cage bottom %.4f mm, plate face %.4f mm" % [low * 1000.0, face * 1000.0]))
	# And the camera view sees its corners where they are drawn.
	var points := airframe.camera_obstruction_points_m()
	var side_keys := 0
	for key in points:
		if str(key).begins_with("SidePlate_"):
			side_keys += 1
	out.append(TestResult.new("assembled aircraft: the camera-view check is given both side plates",
		side_keys == 2, "%d side plates among %s" % [side_keys, points.keys()]))
	airframe.free()

	# Lab's own path: a cage cut into Lab's fitted document reaches the aircraft it assembles.
	var lab := LabScreen.new(catalog)
	var lab_ok := lab.frame_document != null
	if lab_ok:
		FrameEdits.add_camera_cage(lab.frame_document, 19.0)
		lab._on_selection_changed()
	out.append(TestResult.new("Lab: a cage cut into the fitted frame stands on the assembled aircraft",
		lab_ok and lab.airframe.frame_model.side_plates.size() == 2,
		"document %s, %d side plates drawn" % [lab_ok,
			lab.airframe.frame_model.side_plates.size() if lab_ok else -1]))
	lab.free()
	return out


static func _standing_check(where: String, model: FrameModel, plate_height_mm: float) -> TestResult:
	var boxes: Array = []
	var ok := model.side_plates.size() == 2
	for record in model.side_plates:
		var node: MeshInstance3D = record["node"]
		var box: AABB = node.transform * node.mesh.get_aabb()
		boxes.append("%.2f×%.2f×%.2f" % [box.size.x * 1000.0, box.size.y * 1000.0, box.size.z * 1000.0])
		ok = ok and absf(box.size.y * 1000.0 - plate_height_mm) < 1.0e-3 \
			and absf(box.size.x * 1000.0 - CameraCage.DEFAULT_THICKNESS_MM) < 1.0e-3
	return TestResult.new("%s: each side plate is drawn TALL (height = its h extent, width = t)" % where,
		ok, "%d side plates, AABB x×y×z mm %s (want ×%.1f× tall, %.1f wide)" % [
			model.side_plates.size(), boxes, plate_height_mm, CameraCage.DEFAULT_THICKNESS_MM])


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

static func _exported_flat(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
	FrameEdits.add_camera_cage(document, 19.0)
	var t := CameraCage.DEFAULT_THICKNESS_MM

	var flat_max_x := -INF
	for plate in document.plates:
		if not AirframeDocument.is_upright(plate):
			for point in AirframeDocument.plate_outline(plate):
				flat_max_x = maxf(flat_max_x, point.x)

	var bare := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
	var bare_vertices := FrameExport.to_stl(bare).count("vertex ")
	var stl := FrameExport.to_stl(document)
	# Every vertex the cage added must be one of the ones laid beside the frame: a standing (or
	# duplicated) copy left in the assembly adds vertices that are not.
	var added_vertices := stl.count("vertex ") - bare_vertices
	var beside := 0
	var worst_z := 0.0
	for line in stl.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("vertex "):
			continue
		var parts := text.split(" ", false)
		var x := float(parts[1])
		if x > flat_max_x + 1.0e-3:
			beside += 1
			var z := float(parts[3])
			worst_z = maxf(worst_z, maxf(-z, z - t))
	out.append(TestResult.new("STL: the side plates lie flat (0 ≤ z ≤ t) beside the frame, not in it",
		beside > 0 and worst_z < 1.0e-4 and added_vertices == beside,
		"%d vertices beside the frame of %d the cage added, worst z outside [0, t] by %.5f mm" % [
			beside, added_vertices, worst_z]))

	var svg := FrameExport.to_svg(document)
	var notes := svg.count("upright side plate, cut flat")
	var contours := 0
	for plate in document.plates:
		contours += 1 + (plate.get("holes", []) as Array).size()
	out.append(TestResult.new("SVG: both side plates are on the sheet, flat, with their notes",
		notes == 2 and svg.count("<path ") == contours,
		"%d notes, %d paths for %d contours" % [notes, svg.count("<path "), contours]))

	var dxf := FrameExport.to_dxf(document)
	var outlines := dxf.count("POLYLINE\n8\nSIDE\n")
	var holes := dxf.count("POLYLINE\n8\nSIDE_HOLES\n")
	out.append(TestResult.new("DXF: two SIDE outlines, four SIDE_HOLES, and the notes",
		outlines == 2 and holes == 4 and dxf.count("upright side plate, cut flat") == 2,
		"%d outlines, %d holes, %d notes" % [outlines, holes,
			dxf.count("upright side plate, cut flat")]))
	return out


# ---------------------------------------------------------------------------
# The camera-width warning
# ---------------------------------------------------------------------------

static func _camera_width_warning(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
	FrameEdits.add_camera_cage(document, 19.0)
	for case in [["cam_fullsize_analog", true], ["cam_dji_o4_pro", true],
			["cam_micro_analog", false], ["cam_digital_hd", false]]:
		var camera := catalog.get_part(str(case[0]))
		var warnings := CameraCage.warnings(camera, document)
		var fires := warnings.size() == 1 and warnings[0].id == CameraCage.CAMERA_WIDER_THAN_CAGE \
			and warnings[0].severity == BuildWarning.Severity.LIMITING
		out.append(TestResult.new("19 mm cage, %s (%.2f mm wide): %s" % [case[0],
				float(camera.get("specs", {}).get("width_mm", 0.0)),
				"LIMITING warning" if case[1] else "no warning"],
			fires == bool(case[1]) and (bool(case[1]) or warnings.is_empty()),
			"%d warnings %s" % [warnings.size(),
				warnings[0].message if not warnings.is_empty() else ""]))
	var bare := AirframeDocument.from_catalog_frame(catalog.get_part(FIXTURE_FRAME_ID))
	out.append(TestResult.new("no cage, no warning, whatever the camera",
		CameraCage.warnings(catalog.get_part("cam_fullsize_analog"), bare).is_empty(), ""))
	var row := WarningRows.TABLE.get(CameraCage.CAMERA_WIDER_THAN_CAGE, []) as Array
	out.append(TestResult.new("the warning has a row (Camera)",
		not row.is_empty() and row[0] == WarningRows.CAMERA, "row %s" % [row]))
	return out


# ---------------------------------------------------------------------------
# The workbench
# ---------------------------------------------------------------------------

static func _workbench_button(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(catalog.get_part(FIXTURE_FRAME_ID))
	var plates0 := workbench.editor.document.plates.size()
	var depth0 := workbench.editor.history.depth()
	workbench.cage_picker.select(0)
	var button := _find_button(workbench, "+ Camera cage")
	if button != null:
		button.pressed.emit()
	var doc := workbench.editor.document
	out.append(TestResult.new("\"+ Camera cage\" adds two upright nano plates as ONE undo step",
		button != null and doc.plates.size() == plates0 + 2
			and AirframeDocument.is_upright(doc.plates[doc.plates.size() - 1])
			and absf(CameraCage.spacing_mm(doc) - 14.0) < 1.0e-9
			and workbench.editor.history.depth() == depth0 + 1,
		"button %s, plates %d -> %d, spacing %.3f, depth %d -> %d" % [button != null, plates0,
			doc.plates.size(), CameraCage.spacing_mm(doc), depth0, workbench.editor.history.depth()]))
	workbench.editor.undo()
	out.append(TestResult.new("one Undo takes both side plates away",
		workbench.editor.document.plates.size() == plates0,
		"%d plates after undo" % workbench.editor.document.plates.size()))
	workbench.free()
	return out


static func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


static func _sci(value: float) -> String:
	return String.num_scientific(value)


# MUTATIONS (G5, 2026-10-03) — each applied alone in src/, this suite run, then reverted. All 18 red:
#   M1  upright plates skipped in AirframeProperties.compute        → 8 fail (mass, CG, box, triangle)
#   M2  upright tensor left on the flat axes (not rotated)          → 4 fail (box I_xx/I_yy/I_zz, triangle)
#   M3  upright plate placed through world_m as if flat             → 3 fail (CG forward/up, centreline, box CG)
#   M4  product of inertia sign flipped in the local tensor         → 1 fail (triangle I_yz)
#   M5  FrameModel side mesh basis = IDENTITY (left flat)           → 3 fail (both "drawn TALL", stands on plate)
#   M6  _stand_side_plates not called after the seating             → 1 fail (stands on the bottom plate)
#   M7  STL also emits upright plates where they stand              → 1 fail (vertices beside == vertices added)
#   M8  export note text removed                                    → 2 fail (SVG, DXF)
#   M9  spacing measured centre-to-centre                           → 5 fail (spacing ×3, 20 mm camera, button)
#   M10 warning comparison flipped                                  → 4 fail (all four camera cases)
#   M11 plates placed at ±width/2 (thickness ignored)               → 6 fail
#   M12 TILT_MAX_DEG 30                                             → 1 fail (slot at 50°)
#   M13 slot cut 1.4 mm wide                                        → 3 fail (ready to cut, all sizes)
#   M14 workbench add records no undo step                          → 2 fail
#   M15 camera obstruction points omit side plates                  → 1 fail
#   M16 sizes ignore cameras.json                                   → 1 fail
#   M17 AirframeModel ignores the document                          → 4 fail
#   M18 LabScreen does not pass its frame_document                  → 1 fail
