class_name TestFrameEditsDesign
extends RefCounted
## Frame edits on the 5" in the Design Space, the pure half (PLAN Section 4): the frame document the
## GLB was built with, the drill/pocket/fill/thickness/width verdicts, and the session that flies them.
##
## ## The checks that could have passed while proving nothing
##
## - The document is checked against the GLB itself (mesh AABBs, proxy AABBs), not against the
##   script that wrote both: a document drawn from a different outline, a mirrored axis or an
##   unscaled plate fails on the plate or proxy it got wrong. The TPU tail mount is not in the
##   document (not a carbon plate) and its proxies are skipped by name.
## - The drilled-hole mass is compared with rho*t*pi*r^2 computed HERE from the material table and
##   the plate's thickness, and read off the session's `Build` (flown frame and AUW), so a session
##   that never handed the edit over, or an epsilon that swallowed it, reads unchanged and fails.
## - Every refusal checks three things: the reason names the rule, the pure call left its document
##   unchanged, and the session (document and history) is unchanged too.
## - Undo is compared with a fresh session's readouts with `==`, not approximately.

const CLASS_ID := "five_inch"
const GLB := "res://assets/models/classes/five_inch.glb"
const TOL_MM := 0.02
## The arms' vertical corners carry Blender's 0.28 mm bevel (`carve(..., bevel=0.00028)`), which pulls
## the root corners in; a plate mesh's AABB is held to that, a proxy (no bevel) to TOL_MM.
const BEVEL_TOL_MM := 0.3
const HOLE_MM := 3.0
## The known arm point: 91 mm out along arm FL's axis, between its outer pocket and the motor pad.
const ALONG_MM := 91.0


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_document_vs_glb())
	results.append_array(_test_drill(catalog))
	results.append_array(_test_refusals(catalog))
	results.append_array(_test_undo(catalog))
	results.append_array(_test_thickness_and_width(catalog))
	results.append_array(_test_other_classes(catalog))
	return results


static func _session() -> DesignSession:
	return DesignSession.default_for_class(CLASS_ID)


static func _rho_g_mm3(doc: AirframeDocument) -> float:
	return float(AirframePanel.materials().get_material(doc.material_id)["specs"]["density_kg_m3"]) * 1.0e-6


static func _arm_axis(doc: AirframeDocument, plate: int) -> Vector2:
	return AirframeDocument.point_of(doc.plates[plate]["tip_point"]).normalized()


static func _text(doc: AirframeDocument) -> String:
	return JSON.stringify(doc.to_dictionary()) if doc != null else "null"


# ---------------------------------------------------------------------------
# The document is the GLB's frame
# ---------------------------------------------------------------------------

## A node's AABB in the GLB scene's space, metres.
static func _aabb_in_scene(node: Node, scene: Node) -> AABB:
	var xf := Transform3D.IDENTITY
	var at := node
	while at != null and at != scene:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf * (node as MeshInstance3D).mesh.get_aabb()


static func _bbox_m(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return Rect2(r.position / 1000.0, r.size / 1000.0)


static func _test_document_vs_glb() -> Array:
	var out: Array = []
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	var doc := _session().frame_document()
	out.append(TestResult.new("the 5\" session loads a frame document with the fitted frame's id and four motors",
		doc != null and doc.id == ReferenceBuild.FRAME_ID and doc.motors.size() == 4 and doc.plates.size() == 6,
		"doc %s" % ("null" if doc == null else "%s, %d motors, %d plates" % [doc.id, doc.motors.size(), doc.plates.size()])))
	if doc == null:
		scene.free()
		return out
	var tol := TOL_MM / 1000.0
	var bevel_tol := BEVEL_TOL_MM / 1000.0
	for plate in doc.plates:
		var mesh := FrameTools.plate_mesh(plate)
		var node := scene.find_child(mesh, true, false)
		var ok := node is MeshInstance3D
		var detail := "no mesh %s in the GLB" % mesh
		if ok:
			var box := _aabb_in_scene(node, scene)
			var r := _bbox_m(AirframeDocument.plate_outline(plate))
			var z0 := AirframeDocument.plate_z_mm(plate) / 1000.0
			var t := AirframeDocument.plate_thickness_mm(plate) / 1000.0
			var err := maxf(maxf(absf(box.position.x - r.position.x), absf(box.end.x - r.end.x)),
				maxf(absf(box.position.z - r.position.y), absf(box.end.z - r.end.y)))
			err = maxf(err, maxf(absf(box.position.y - z0), absf(box.end.y - (z0 + t))))
			ok = err <= bevel_tol
			detail = "worst edge %.4f mm (GLB %s, doc %s z %.3f..%.3f)" % [err * 1000.0, box, r, z0, z0 + t]
		out.append(TestResult.new("document plate %s coincides with its GLB mesh (within the %.2f mm bevel)" % [mesh, BEVEL_TOL_MM],
			ok, detail))
	var proxies := 0
	for node in scene.find_children("pick_*", "MeshInstance3D", true, false):
		var name := String(node.name)
		if name.contains("tail_mount"):
			continue
		proxies += 1
		var at := doc_hole(doc, name)
		var ok := at.x >= 0
		var detail := "no document hole is named %s" % name
		if ok:
			var box := _aabb_in_scene(node, scene)
			var r := _bbox_m(AirframeDocument.plate_holes(doc.plates[at.x])[at.y])
			var err := maxf(maxf(absf(box.position.x - r.position.x), absf(box.end.x - r.end.x)),
				maxf(absf(box.position.z - r.position.y), absf(box.end.z - r.end.y)))
			ok = err <= tol
			detail = "worst edge %.4f mm" % (err * 1000.0)
		out.append(TestResult.new("proxy %s is document hole %s, edge for edge (within %.2f mm)" % [name, at, TOL_MM],
			ok, detail))
	var named := 0
	for plate in doc.plates:
		for n in FrameTools.hole_names(plate):
			if String(n).begins_with("pick_"):
				named += 1
	out.append(TestResult.new("every proxy-named document hole has a GLB proxy (both counts equal, non-zero)",
		named == proxies and proxies > 0, "document %d, GLB %d" % [named, proxies]))
	var fl := FrameTools.plate_of_mesh(doc, "frame_arm_FL")
	var motor_ok := false
	for m in doc.motors:
		var p := AirframeDocument.point_of((m as Dictionary)["position_mm"])
		if fl >= 0 and str(m["name"]) == "M4" and p.distance_to(AirframeDocument.point_of(doc.plates[fl]["tip_point"])) < 1.0e-6 \
				and p.x < 0.0 and p.y < 0.0:
			motor_ok = true
	out.append(TestResult.new("M4 (front left) sits on arm FL's tip, at -X -Z (nose is -Z)", motor_ok, "fl %d" % fl))
	scene.free()
	return out


static func doc_hole(doc: AirframeDocument, name: String) -> Vector2i:
	return FrameTools.hole_of_proxy(doc, name)


# ---------------------------------------------------------------------------
# Drill: the mass flies
# ---------------------------------------------------------------------------

static func _test_drill(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var doc := s.frame_document()
	var fl := s.plate_of_mesh("frame_arm_FL")
	var point := _arm_axis(doc, fl) * ALONG_MM
	var before := s.build(catalog)
	var holes_before := AirframeDocument.plate_holes(doc.plates[fl]).size()
	var t := AirframeDocument.plate_thickness_mm(doc.plates[fl])
	var expected := _rho_g_mm3(doc) * t * PI * pow(HOLE_MM * 0.5, 2.0)
	var verdict := s.drill(fl, point, HOLE_MM)
	var after := s.build(catalog)
	var frame_drop := float(before.frame["mass_g"]) - float(after.frame["mass_g"])
	var auw_drop := before.all_up_weight_g() - after.all_up_weight_g()
	out.append(TestResult.new("a 3 mm hole on arm FL lowers the flown frame mass by rho*t*pi*r^2 (within 0.002 g)",
		verdict["ok"] and absf(frame_drop - expected) < 0.002,
		"drop %.5f g, expected %.5f g, verdict %s" % [frame_drop, expected, verdict]))
	out.append(TestResult.new("a 3 mm hole on arm FL lowers the AUW by rho*t*pi*r^2 (within 0.002 g)",
		verdict["ok"] and absf(auw_drop - expected) < 0.002,
		"drop %.5f g, expected %.5f g" % [auw_drop, expected]))
	var holes := AirframeDocument.plate_holes(s.frame_document().plates[fl])
	var centred := holes.size() == holes_before + 1 \
		and FrameTools.centre_of(holes[holes.size() - 1]).distance_to(point) < 0.05
	out.append(TestResult.new("the document gains exactly one hole, centred on the drilled point within 0.05 mm",
		centred, "holes %d -> %d" % [holes_before, holes.size()]))
	var radius_ok := false
	if holes.size() == holes_before + 1:
		var last: PackedVector2Array = holes[holes.size() - 1]
		radius_ok = absf(last[0].distance_to(point) - HOLE_MM * 0.5) < 0.01 and PolygonProps.area(last) < 0.0
	out.append(TestResult.new("the drilled hole is 3 mm across and wound to subtract", radius_ok, ""))
	var name := String(FrameTools.hole_names(s.frame_document().plates[fl]).back())
	out.append(TestResult.new("the drilled hole is named as a pick proxy that resolves back to it",
		name.begins_with("pick_hole_arm_FL_") and s.hole_of_proxy(name) == Vector2i(fl, holes_before),
		"name %s -> %s" % [name, s.hole_of_proxy(name)]))
	var filled := s.fill(fl, holes_before)
	out.append(TestResult.new("filling the drilled hole flies the frame as weighed again",
		filled["ok"] and float(s.build(catalog).frame["mass_g"]) == float(before.frame["mass_g"]),
		"fill %s" % filled))
	return out


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

## One refusal case: the pure op on a copy, then the session op. `op` takes (doc) for the pure call;
## `session_op` takes (session).
static func _refusal(title: String, must_say: String, pure: Callable, session_op: Callable) -> TestResult:
	var s := _session()
	var copy := AirframeDocument.from_dictionary(s.frame_document().to_dictionary())
	var before := _text(copy)
	var v: Dictionary = pure.call(copy)
	var pure_ok: bool = not v["ok"] and String(v["reason"]).contains(must_say) and _text(copy) == before
	var doc_before := _text(s.frame_document())
	var sv: Dictionary = session_op.call(s)
	var session_ok: bool = not sv["ok"] and String(sv["reason"]) == String(v["reason"]) \
		and _text(s.frame_document()) == doc_before and not s.can_undo()
	return TestResult.new(title, pure_ok and session_ok,
		"pure %s (unchanged %s), session %s (unchanged %s)" % [v, _text(copy) == before, sv, _text(s.frame_document()) == doc_before])


static func _test_refusals(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var doc := _session().frame_document()
	var fl := FrameTools.plate_of_mesh(doc, "frame_arm_FL")
	var top := FrameTools.plate_of_mesh(doc, "frame_plate_top")
	var axis := _arm_axis(doc, fl)
	var across := axis.orthogonal()
	var bolt := FrameTools.centre_of(AirframeDocument.plate_holes(doc.plates[fl])[1])
	var tip := AirframeDocument.point_of(doc.plates[fl]["tip_point"])
	var near_bolt := bolt + (tip - bolt).normalized() * 2.0
	var cases := [
		["a hole off the arm (at the frame centre) is refused", "off the arm",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.drill(d, fl, Vector2.ZERO, HOLE_MM),
			func(x: DesignSession) -> Dictionary: return x.drill(fl, Vector2.ZERO, HOLE_MM)],
		["a hole overlapping the motor pad's screw hole is refused, naming it", "cut through the motor pad's screw hole",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.drill(d, fl, near_bolt, HOLE_MM),
			func(x: DesignSession) -> Dictionary: return x.drill(fl, near_bolt, HOLE_MM)],
		["a hole 6 mm off the arm's axis breaks the 1.5x edge distance and is refused", "edge",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.drill(d, fl, axis * ALONG_MM + across * 6.0, HOLE_MM),
			func(x: DesignSession) -> Dictionary: return x.drill(fl, axis * ALONG_MM + across * 6.0, HOLE_MM)],
		["a slot across the whole arm would sever it and is refused", "in two",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.pocket(d, fl,
				FrameTools.slot_pocket(axis * ALONG_MM - across * 15.0, axis * ALONG_MM + across * 15.0, 3.0)),
			func(x: DesignSession) -> Dictionary: return x.pocket(fl,
				FrameTools.slot_pocket(axis * ALONG_MM - across * 15.0, axis * ALONG_MM + across * 15.0, 3.0))],
		["a pocket breaking through the arm's edge is refused", "breaks through",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.pocket(d, fl,
				FrameTools.slot_pocket(axis * ALONG_MM, axis * ALONG_MM + across * 15.0, 3.0)),
			func(x: DesignSession) -> Dictionary: return x.pocket(fl,
				FrameTools.slot_pocket(axis * ALONG_MM, axis * ALONG_MM + across * 15.0, 3.0))],
		["a pocket leaving a web under the assumed minimum is refused", "assumed minimum",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.pocket(d, fl,
				FrameTools.rect_pocket(axis * ALONG_MM + across * 6.0, Vector2(3.0, 4.0), axis.angle())),
			func(x: DesignSession) -> Dictionary: return x.pocket(fl,
				FrameTools.rect_pocket(axis * ALONG_MM + across * 6.0, Vector2(3.0, 4.0), axis.angle()))],
		["filling a motor screw hole is refused", "motor is bolted",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.fill(d, fl, 1),
			func(x: DesignSession) -> Dictionary: return x.fill(fl, 1)],
		["a 12 mm top plate is refused by the thickness bounds", "thickness",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.set_thickness(d, top, 12.0),
			func(x: DesignSession) -> Dictionary: return x.set_plate_thickness(top, 12.0)],
		["narrowing arm FL to 90% is refused: its lightening holes would breach the edge distance", "from the arm's edge",
			func(d: AirframeDocument) -> Dictionary: return FrameTools.set_arm_width(d, fl, 0.9),
			func(x: DesignSession) -> Dictionary: return x.set_arm_width(fl, 0.9)],
	]
	for c in cases:
		out.append(_refusal(String(c[0]), String(c[1]), c[2], c[3]))
	return out


# ---------------------------------------------------------------------------
# One history
# ---------------------------------------------------------------------------

static func _test_undo(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ref_readouts := DesignSession.readouts_of(_session().build(catalog))
	var s := _session()
	var fl := s.plate_of_mesh("frame_arm_FL")
	var point := _arm_axis(s.frame_document(), fl) * ALONG_MM
	s.drill(fl, point, HOLE_MM)
	var drilled := DesignSession.readouts_of(s.build(catalog))
	var undone := s.undo()
	out.append(TestResult.new("drill then undo gives the reference readouts bit for bit",
		undone and DesignSession.readouts_of(s.build(catalog)) == ref_readouts and drilled != ref_readouts,
		"undo %s, drilled differs %s" % [undone, drilled != ref_readouts]))
	s.redo()
	out.append(TestResult.new("redo gives the drilled readouts back bit for bit",
		DesignSession.readouts_of(s.build(catalog)) == drilled, ""))
	# Swaps and edits share one history, and each step restores both selection and document.
	var t := _session()
	var home := t.selection.duplicate(true)
	var doc0 := _text(t.frame_document())
	var other := ""
	for p in catalog.list_category("battery"):
		if String(p["part_id"]) != String(home["battery"]) and PartSwap.judge(t, catalog, "battery", String(p["part_id"]), false)["ok"]:
			other = String(p["part_id"])
			break
	t.swap(catalog, "battery", other)
	t.drill(fl, point, HOLE_MM)
	var doc2 := _text(t.frame_document())
	t.undo()
	var step1: bool = t.selection.get("battery") == other and _text(t.frame_document()) == doc0
	t.undo()
	var step2: bool = t.selection == home and _text(t.frame_document()) == doc0 and not t.can_undo()
	t.redo()
	t.redo()
	var step3: bool = t.selection.get("battery") == other and _text(t.frame_document()) == doc2
	out.append(TestResult.new("swap then drill: undo steps back the drill, then the swap; redo replays both",
		other != "" and step1 and step2 and step3, "other %s, steps %s %s %s" % [other, step1, step2, step3]))
	return out


# ---------------------------------------------------------------------------
# Thickness and arm width move the mass by what the geometry says
# ---------------------------------------------------------------------------

static func _test_thickness_and_width(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var doc := s.frame_document()
	var rho := _rho_g_mm3(doc)
	var top := s.plate_of_mesh("frame_plate_top")
	var plate: Dictionary = doc.plates[top]
	var net := float(PolygonProps.region_properties(AirframeDocument.plate_outline(plate),
		AirframeDocument.plate_holes(plate))["area"])
	var t0 := AirframeDocument.plate_thickness_mm(plate)
	var m0 := float(s.build(catalog).frame["mass_g"])
	var v := s.set_plate_thickness(top, t0 + 1.0)
	var m1 := float(s.build(catalog).frame["mass_g"])
	var expected := rho * 1.0 * net
	out.append(TestResult.new("1 mm more top plate adds rho*1mm*net area to the flown frame (within 1e-5 g)",
		v["ok"] and absf((m1 - m0) - expected) < 1.0e-5, "added %.6f g, expected %.6f g" % [m1 - m0, expected]))

	var w := _session()
	var wdoc := w.frame_document()
	var fl := w.plate_of_mesh("frame_arm_FL")
	var arm: Dictionary = wdoc.plates[fl]
	var a0 := PolygonProps.area(AirframeDocument.plate_outline(arm))
	var root0 := float(FrameEdits.arm_geometry(wdoc, fl)["root_width_mm"])
	var t := AirframeDocument.plate_thickness_mm(arm)
	var w0 := float(w.build(catalog).frame["mass_g"])
	var wv := w.set_arm_width(fl, 1.2)
	var w1 := float(w.build(catalog).frame["mass_g"])
	var a1 := PolygonProps.area(AirframeDocument.plate_outline(w.frame_document().plates[fl]))
	var root1 := float(FrameEdits.arm_geometry(w.frame_document(), fl)["root_width_mm"])
	out.append(TestResult.new("arm FL at 120% width: root 1.2x as wide, and the flown frame gains rho*t*(added outline area)",
		wv["ok"] and absf(root1 - 1.2 * root0) < 0.01 and a1 > a0 and absf((w1 - w0) - rho * t * (a1 - a0)) < 1.0e-5,
		"root %.3f -> %.3f, mass +%.5f g vs %.5f g, verdict %s" % [root0, root1, w1 - w0, rho * t * (a1 - a0), wv]))
	# The motor pad (every vertex at or beyond the motor centre along the axis) stays as drawn, so the
	# motor still bolts on: compared vertex for vertex with the outline before the edit.
	var tip := AirframeDocument.point_of(arm["tip_point"])
	var axis := tip.normalized()
	var old_pts := AirframeDocument.plate_outline(arm)
	var new_pts := AirframeDocument.plate_outline(w.frame_document().plates[fl])
	var pad := 0
	var pad_kept := old_pts.size() == new_pts.size()
	for i in mini(old_pts.size(), new_pts.size()):
		if old_pts[i].dot(axis) >= tip.dot(axis) - 1.0e-6:
			pad += 1
			pad_kept = pad_kept and old_pts[i] == new_pts[i]
	out.append(TestResult.new("arm width leaves the motor pad's outline exactly as drawn",
		wv["ok"] and pad > 2 and pad_kept, "pad vertices %d, kept %s" % [pad, pad_kept]))
	return out


# ---------------------------------------------------------------------------
# Every other class: no document, and the frame ops refuse
# ---------------------------------------------------------------------------

static func _test_other_classes(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := DesignSession.default_for_class("four_inch")
	var v := s.drill(0, Vector2.ZERO, HOLE_MM)
	out.append(TestResult.new("the 4\" has no frame document and its drill is refused with a reason",
		s.frame_document() == null and not v["ok"] and String(v["reason"]) != "" and not s.can_undo(), "%s" % v))
	var f := _session()
	var other := ""
	for p in catalog.list_category("frame"):
		if String(p["part_id"]) != ReferenceBuild.FRAME_ID and PartSwap.judge(f, catalog, "frame", String(p["part_id"]), false)["ok"]:
			other = String(p["part_id"])
			break
	f.swap(catalog, "frame", other)
	var fl := f.plate_of_mesh("frame_arm_FL")
	var fv := f.drill(fl, _arm_axis(f.frame_document(), fl) * ALONG_MM, HOLE_MM)
	out.append(TestResult.new("with another 5\" frame swapped in, frame edits are refused (the drawing is the fitted frame's)",
		other != "" and not fv["ok"] and f.frame_edit(catalog).is_empty(), "other %s, %s" % [other, fv]))
	return out
