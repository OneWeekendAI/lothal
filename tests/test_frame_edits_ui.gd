class_name TestFrameEditsUi
extends RefCounted
## Frame edits on the 5" in the Design Space, the 3D and UI half (PLAN Section 4): a click on a plate
## lands in that plate's own plan millimetres, an edited plate is redrawn with real through holes and
## fresh pick proxies, and the tool row shows refusals, the change and what is not modelled.
##
## ## The checks that could have passed while proving nothing
##
## - Hits are made by real rays against the pick registry (the registry the click uses), either
##   straight down through a plan point or from the camera through its projection, never by asking
##   the code under test where it would have hit.
## - "Through hole" is three checks, not one: the ray down the new hole's centre meets NOTHING of the
##   plate, a ray 1 mm outside the hole's edge still meets the plate, and the ray down the centre
##   meets the new hole's own proxy (so Fill can pick it).
## - The redrawn plate's material is checked by area: the top face's triangles must add up to the
##   outline minus every cut, so a triangulator that dropped a piece or filled a hole fails.
## - A refused edit is checked for the reason shown, its colour, and that the plate's mesh is the
##   same object as before.

const CLASS_ID := "five_inch"
const HOLE_MM := 3.0
## The known free arm point (tests/test_frame_edits_design.gd): 91 mm out along arm FL's axis.
const ALONG_MM := 91.0
const ROUND_TRIP_TOL_MM := 0.01


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_round_trip(catalog))
	results.append_array(_test_solid_pieces(catalog))
	results.append_array(_test_drill_through(catalog))
	results.append_array(_test_refusal(catalog))
	results.append_array(_test_tool_row(catalog))
	results.append_array(_test_sliders_and_pocket(catalog))
	return results


static func _ds(catalog: PartsCatalog, class_id: String = CLASS_ID) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(class_id), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	return ds


static func _top_mm(plate: Dictionary) -> float:
	return AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate)


## Every pick hit along a vertical ray down through plan point `p` (from above the whole frame).
static func _down(ds: DesignSpace, p: Vector2) -> Array:
	var xf := ds.doc_xf()
	var origin := FrameView.space_point(p, 200.0, xf)
	return ds.picks.hits(origin, xf.basis * Vector3.DOWN)


static func _hit_on(hits: Array, node_name: String) -> Dictionary:
	for h in hits:
		if String((h["entry"]["node"] as Node).name) == node_name:
			return h
	return {}


## A point in the plate's material: the centroid of the largest triangle of its first solid piece.
static func _material_point(plate: Dictionary) -> Vector2:
	var best := Vector2.ZERO
	var best_a := -1.0
	for piece in FrameView.solid_pieces(AirframeDocument.plate_outline(plate), AirframeDocument.plate_holes(plate)):
		var poly: PackedVector2Array = piece
		var idx := Geometry2D.triangulate_polygon(poly)
		for t in int(idx.size() / 3.0):
			var a := poly[idx[t * 3]]
			var b := poly[idx[t * 3 + 1]]
			var c := poly[idx[t * 3 + 2]]
			var area := absf((b - a).cross(c - a)) * 0.5
			if area > best_a:
				best_a = area
				best = (a + b + c) / 3.0
	return best


## The first frame address along a hit list (the props and parts above an arm are not frame).
static func _first_frame(hits: Array) -> String:
	for h in hits:
		if String(h["address"]).begins_with("frame/"):
			return String(h["address"])
	return ""


static func _ndc_of(ds: DesignSpace, p: Vector2, z_mm: float) -> Vector2:
	return ds.rig.project(FrameView.space_point(p, z_mm, ds.doc_xf()))


# ---------------------------------------------------------------------------

static func _test_round_trip(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	var xf := ds.doc_xf()
	out.append(TestResult.new("the GLB scene sits on the stage off the origin (so the round trip is not an identity)",
		xf.origin.length() > 1.0e-4, "%s" % xf.origin))
	for i in doc.plates.size():
		var plate: Dictionary = doc.plates[i]
		var mesh := FrameTools.plate_mesh(plate)
		var p := _material_point(plate)
		var z := _top_mm(plate)
		var back := FrameView.plan_point(FrameView.space_point(p, z, xf), xf)
		var back_z := FrameView.plan_z_mm(FrameView.space_point(p, z, xf), xf)
		out.append(TestResult.new("%s: plan mm -> stage -> plan mm round-trips within %.2f mm" % [mesh, ROUND_TRIP_TOL_MM],
			back.distance_to(p) <= ROUND_TRIP_TOL_MM and absf(back_z - z) <= ROUND_TRIP_TOL_MM, "%s -> %s" % [p, back]))
		var h := _hit_on(_down(ds, p), mesh)
		var ok := not h.is_empty()
		var detail := "the ray down met no %s" % mesh
		if ok:
			var q := FrameView.plan_point(h["position"], xf)
			ok = q.distance_to(p) <= ROUND_TRIP_TOL_MM and Geometry2D.is_point_in_polygon(q, AirframeDocument.plate_outline(plate))
			detail = "hit at %s for %s" % [q, p]
		out.append(TestResult.new("%s: a real ray hit on the plate maps back inside its outline, at the point aimed at" % mesh,
			ok, detail))
	# Through the camera, as a click is: the projected arm point resolves to that arm and that point.
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var aim := AirframeDocument.point_of(doc.plates[fl]["tip_point"]).normalized() * ALONG_MM
	var hit := ds.plate_hit(_ndc_of(ds, aim, _top_mm(doc.plates[fl])))
	out.append(TestResult.new("a click at the projected arm point resolves to arm FL at that plan point (within %.2f mm)" % ROUND_TRIP_TOL_MM,
		int(hit.get("plate", -1)) == fl and (hit["point_mm"] as Vector2).distance_to(aim) <= ROUND_TRIP_TOL_MM,
		"%s" % hit))
	ds.free()
	return out


static func _test_solid_pieces(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	for plate in doc.plates:
		var outline := AirframeDocument.plate_outline(plate)
		var holes := AirframeDocument.plate_holes(plate)
		var want := absf(PolygonProps.area(outline))
		for h in holes:
			want -= absf(PolygonProps.area(h))
		var got := 0.0
		for piece in FrameView.solid_pieces(outline, holes):
			got += absf(PolygonProps.area(piece))
		var mesh := FrameTools.plate_mesh(plate)
		var m := FrameView.plate_mesh(plate, Transform3D.IDENTITY, null)
		var top := 0.0
		if m != null:
			var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			for t in int(v.size() / 3.0):
				if n[t * 3].y > 0.99:
					top += (v[t * 3 + 1] - v[t * 3]).cross(v[t * 3 + 2] - v[t * 3]).length() * 0.5e6
		out.append(TestResult.new("%s: the redrawn top face is the outline minus every cut (%d), area within 0.05 mm^2" % [mesh, holes.size()],
			absf(got - want) <= 0.05 and absf(top - want) <= 0.05, "pieces %.3f, top face %.3f, want %.3f" % [got, top, want]))
	ds.free()
	return out


static func _test_drill_through(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var plate: Dictionary = doc.plates[fl]
	var aim := AirframeDocument.point_of(plate["tip_point"]).normalized() * ALONG_MM
	var glb_mesh: Mesh = (ds._doc_root.find_child("frame_arm_FL", true, false) as MeshInstance3D).mesh
	var glb_mat := glb_mesh.surface_get_material(0)
	var before := AirframeDocument.plate_holes(plate).size()
	var proxies_before := ds._doc_root.find_children("pick_*_arm_FL_*", "MeshInstance3D", true, false).size()
	ds.select("frame/arm/FL")
	ds.set_frame_tool("drill")
	ds.drill_d_mm = HOLE_MM
	var v := ds.drill_at(_ndc_of(ds, aim, _top_mm(plate)))
	doc = ds.session.frame_document()
	plate = doc.plates[fl]
	var holes := AirframeDocument.plate_holes(plate)
	var names := FrameTools.hole_names(plate)
	var hole: PackedVector2Array = holes[holes.size() - 1] if holes.size() > before else PackedVector2Array()
	var centre := FrameTools.centre_of(hole) if hole.size() > 0 else Vector2(INF, INF)
	out.append(TestResult.new("a drill click on arm FL adds exactly one hole, centred on the clicked point within 0.05 mm",
		v.get("ok", false) and holes.size() == before + 1 and centre.distance_to(aim) <= 0.05,
		"%s, %d -> %d holes, centre %s" % [v, before, holes.size(), centre]))
	var node := ds._doc_root.find_child("frame_arm_FL", true, false) as MeshInstance3D
	out.append(TestResult.new("the drilled arm is redrawn from the document, in the GLB's own carbon material",
		ds.plate_regenerated(fl) and node.mesh != glb_mesh and node.mesh.surface_get_material(0) == glb_mat, ""))
	var others := 0
	for i in doc.plates.size():
		if i != fl and ds.plate_regenerated(i):
			others += 1
	out.append(TestResult.new("every unedited plate keeps the GLB's mesh", others == 0, "%d redrawn" % others))
	var down := _down(ds, centre)
	out.append(TestResult.new("a ray down the new hole's centre meets nothing of arm FL (a through hole)",
		hole.size() > 0 and _hit_on(down, "frame_arm_FL").is_empty(), "%s" % [down.map(func(h): return h["address"])]))
	var r := HOLE_MM * 0.5
	var outside := centre + AirframeDocument.point_of(plate["tip_point"]).normalized().orthogonal() * (r + 1.0)
	out.append(TestResult.new("a ray 1 mm outside the hole's edge still meets arm FL",
		not _hit_on(_down(ds, outside), "frame_arm_FL").is_empty(), "%s" % outside))
	var new_name := String(names[names.size() - 1]) if names.size() > 0 else ""
	var addr := PickRegistry.address_of(new_name)
	out.append(TestResult.new("the ray down the new hole's centre picks the new hole's own proxy (%s)" % new_name,
		new_name.begins_with("pick_hole_arm_FL_") and _first_frame(down) == addr,
		"%s" % [down.map(func(h): return h["address"])]))
	var line := ds.frame_change_text()
	var dg := float(FittedFrame.drawn(doc)["mass_g"]) - float(FittedFrame.drawn(ds._frame_orig)["mass_g"])
	out.append(TestResult.new("the change is named: \"Frame: 1 hole drilled, %+.2f g\", in the tool row and the inspector" % dg,
		line == "Frame: 1 hole drilled, %+.2f g" % dg and dg < 0.0 and ds.tool_row.change_label.visible
		and ds.tool_row.change_label.text == line and ds.inspector_lines().has(line), "%s / %s" % [line, ds.inspector_lines()]))
	# Fill, on the picked proxy: the hole goes and the arm is the GLB's again, proxies and all.
	ds.select(addr)
	var f := ds.fill_selected()
	plate = ds.session.frame_document().plates[fl]
	var proxies_after := ds._doc_root.find_children("pick_*_arm_FL_*", "MeshInstance3D", true, false).size()
	out.append(TestResult.new("Fill on the picked new hole removes it, and the arm is the GLB's mesh with its proxies again",
		f.get("ok", false) and AirframeDocument.plate_holes(plate).size() == before and not ds.plate_regenerated(fl)
		and proxies_after == proxies_before and ds.selected == "frame/arm/FL",
		"%s, holes %d, proxies %d/%d, selected %s" % [f, AirframeDocument.plate_holes(plate).size(), proxies_after, proxies_before, ds.selected]))
	# Undo and redo, through the tool row's buttons: one history with the session.
	ds.tool_row.undo_button.pressed.emit()
	plate = ds.session.frame_document().plates[fl]
	out.append(TestResult.new("Undo (button) brings the drilled hole back, drawn and pickable",
		AirframeDocument.plate_holes(plate).size() == before + 1 and ds.plate_regenerated(fl)
		and ds.picks.addresses().has(addr), "holes %d, regenerated %s, pickable %s" % [AirframeDocument.plate_holes(plate).size(), ds.plate_regenerated(fl), ds.picks.addresses().has(addr)]))
	ds.tool_row.undo_button.pressed.emit()
	ds.tool_row.redo_button.pressed.emit()
	plate = ds.session.frame_document().plates[fl]
	out.append(TestResult.new("Undo twice then Redo (buttons) gives the drilled arm again",
		AirframeDocument.plate_holes(plate).size() == before + 1 and ds.plate_regenerated(fl), ""))
	ds.free()
	return out


static func _test_refusal(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var plate: Dictionary = doc.plates[fl]
	# Aim at the middle of the arm's first lightening hole, through the camera.
	var k := FrameTools.hole_names(plate).find("pick_hole_arm_FL_1")
	var c := FrameTools.centre_of(AirframeDocument.plate_holes(plate)[k])
	ds.select("frame/arm/FL")
	ds.set_frame_tool("drill")
	ds.drill_d_mm = HOLE_MM
	var node := ds._doc_root.find_child("frame_arm_FL", true, false) as MeshInstance3D
	var mesh_before := node.mesh
	var holes_before := AirframeDocument.plate_holes(plate).size()
	var v := ds.drill_at(_ndc_of(ds, c, _top_mm(plate)))
	var shown := ds.frame_reason_text()
	out.append(TestResult.new("a drill on an existing hole is refused, and its one-line reason is shown",
		not v.get("ok", true) and shown != "" and shown == String(v.get("reason", "")) and not shown.contains("\n"),
		"%s / shown %s" % [v, shown]))
	out.append(TestResult.new("the refusal line is in the warning accent",
		ds.tool_row.reason_label.get_theme_color("font_color") == LothalTheme.WARNING, ""))
	out.append(TestResult.new("a refused drill leaves the mesh and the document unchanged",
		node.mesh == mesh_before and AirframeDocument.plate_holes(ds.session.frame_document().plates[fl]).size() == holes_before
		and not ds.session.can_undo(), ""))
	var off := ds.drill_at(Vector2(-0.98, 0.98))
	out.append(TestResult.new("a drill click on empty floor is refused with a reason",
		not off.get("ok", true) and ds.frame_reason_text() == "Drill on a plate or an arm.", ds.frame_reason_text()))
	ds.set_frame_tool("")
	out.append(TestResult.new("putting the tool down clears the refusal line", ds.frame_reason_text() == "", ""))
	ds.free()
	return out


static func _test_tool_row(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.select("part/battery")
	out.append(TestResult.new("the tool row is hidden while a part is selected", not ds.frame_tools_shown(), ""))
	ds.select("frame/arm/FL")
	out.append(TestResult.new("selecting an arm of the 5\" shows the tool row", ds.frame_tools_shown(), ""))
	out.append(TestResult.new("the tool row shows every \"not modelled\" tag of PLAN §4.3 (CG treated as centred among them)",
		ds.tool_row.tag_texts() == FrameTools.NOT_MODELLED and ds.tool_row.tags_box.visible
		and String(ds.tool_row.tag_texts()[0]).contains("centred"), "%s" % [ds.tool_row.tag_texts()]))
	out.append(TestResult.new("before any edit, Undo and Redo are disabled",
		ds.tool_row.undo_button.disabled and ds.tool_row.redo_button.disabled, ""))
	out.append(TestResult.new("the plan editor button is there, disabled and labelled as not wired",
		ds.tool_row.plan_button.disabled and ds.tool_row.plan_button.text.contains("not yet"), ds.tool_row.plan_button.text))
	ds.tool_row.size_buttons[FrameTools.DRILL_SIZES["M2"]].pressed.emit()
	out.append(TestResult.new("the M2 button sets a 2.2 mm drill", is_equal_approx(ds.drill_d_mm, 2.2), "%f" % ds.drill_d_mm))
	# The signal the SpinBox emits on an edit (out of the tree, setting `value` does not emit it).
	ds.tool_row.free_size.value_changed.emit(4.5)
	out.append(TestResult.new("the free diameter sets the drill", is_equal_approx(ds.drill_d_mm, 4.5), "%f" % ds.drill_d_mm))
	ds.free()
	var four := _ds(catalog, "four_inch") if DroneClass.is_available("four_inch") else null
	if four != null:
		four.select("frame/body" if four.picks.addresses().has("frame/body") else String(four.picks.addresses().filter(func(a): return String(a).begins_with("frame/"))[0]))
		out.append(TestResult.new("the 4\" (no frame document) shows no tool row on a frame selection", not four.frame_tools_shown(), four.selected))
		four.free()
	return out


static func _test_sliders_and_pocket(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var top := ds.session.plate_of_mesh("frame_plate_top")
	ds.select("frame/plate/top")
	ds.tool_row.thickness_committed.emit(3.0)
	var node := ds._doc_root.find_child("frame_plate_top", true, false) as MeshInstance3D
	var aabb := node.mesh.get_aabb()
	out.append(TestResult.new("the thickness slider on the top plate makes it 3 mm, redrawn 3 mm thick",
		is_equal_approx(AirframeDocument.plate_thickness_mm(ds.session.frame_document().plates[top]), 3.0)
		and absf(aabb.size.y - 0.003) < 1.0e-6, "%s" % aabb))
	var r := ds.set_plate_thickness(12.0)
	out.append(TestResult.new("a 12 mm plate is refused with its reason shown, the plate left at 3 mm",
		not r.get("ok", true) and ds.frame_reason_text() != ""
		and is_equal_approx(AirframeDocument.plate_thickness_mm(ds.session.frame_document().plates[top]), 3.0), ds.frame_reason_text()))
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	ds.select("frame/arm/FL")
	var area_before := absf(PolygonProps.area(AirframeDocument.plate_outline(ds.session.frame_document().plates[fl])))
	ds.tool_row.width_committed.emit(1.2)
	var area_after := absf(PolygonProps.area(AirframeDocument.plate_outline(ds.session.frame_document().plates[fl])))
	out.append(TestResult.new("the arm width slider widens arm FL to 120%, redrawn from the document",
		is_equal_approx(FrameTools.arm_width(ds.session.frame_document(), fl), 1.2) and area_after > area_before
		and ds.plate_regenerated(fl) and ds.tool_row.width_box.visible, "%f -> %f" % [area_before, area_after]))
	# A pocket on the bottom plate, found free by the pure verdict, cut through the tool's seam.
	var bottom := ds.session.plate_of_mesh("frame_plate_bottom")
	var bplate: Dictionary = ds.session.frame_document().plates[bottom]
	var spot := Vector2(INF, INF)
	for y in range(-60, 61, 4):
		for x in range(-20, 21, 4):
			var c := Vector2(x, y)
			if FrameTools.pocket_verdict(ds.session.frame_document(), bottom, FrameTools.rect_pocket(c, Vector2(5, 5)))["ok"]:
				spot = c
				break
		if spot.x < INF:
			break
	ds.select("frame/plate/bottom")
	ds.set_frame_tool("pocket")
	ds.pocket_shape = "rect"
	var p := ds.pocket_from_to(bottom, spot - Vector2(2.5, 2.5), spot + Vector2(2.5, 2.5)) if spot.x < INF else {}
	bplate = ds.session.frame_document().plates[bottom]
	var names := FrameTools.hole_names(bplate)
	var last := String(names[names.size() - 1])
	out.append(TestResult.new("a dragged 5x5 mm rectangle cuts a pocket on the bottom plate, and its proxy is pickable",
		p.get("ok", false) and last.begins_with("pick_pocket_plate_bottom_") and ds.picks.addresses().has(PickRegistry.address_of(last))
		and _hit_on(_down(ds, spot), "frame_plate_bottom").is_empty(), "%s at %s, %s" % [p, spot, last]))
	ds.pocket_shape = "slot"
	var s := ds.pocket_from_to(bottom, spot, spot + Vector2(0.2, 0.0))
	out.append(TestResult.new("a slot dragged under 0.5 mm is refused with its reason", not s.get("ok", true)
		and ds.frame_reason_text() == "Drag along the plate to draw the slot.",
		ds.frame_reason_text()))
	ds.free()
	return out
