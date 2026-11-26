class_name TestFrameDocs
extends RefCounted
## Every class whose frame is a flat open plate frame has a frame document, so FrameGen draws it and it is
## edited like the 5". The documents are exported by tools/blender/build_drone.py from the very config the
## shipped GLB was built from, and this suite holds them to that GLB:
##   - the class has a document, whose id is the class's own seed frame part;
##   - per plate: the generated mesh's bounding box equals the GLB plate mesh's, every document hole with a
##     GLB pick proxy sits where the proxy does, the motor bore sits at the motor, each standoff at the GLB's;
##   - the wheelbase (diagonal motor distance) equals `wb` in build_drone.py's CFGS (read from that file);
##   - the unedited document leaves Build's mass, centre of mass and inertia exactly as the catalog build;
##   - an edit (a drilled hole) lightens the build, and the edited frame survives a design-file round trip.
## Classes with no document on purpose (moulded whoop, ducted cinewhoop, tube cinelifter/x_class, mapper) are
## asserted to have none, so a document cannot appear for them without this suite being revisited.

const CLASSES := ["toothpick", "sub250_35", "four_inch", "five_inch", "six_inch", "seven_lr"]
const SKIPPED := ["tiny_whoop", "cinewhoop_3", "cinelifter", "mapper", "x_class"]
const MATCH_TOL_MM := 1.0
## Standoffs per frame (build_drone.py STAND_PTS): 8 on every class.
const STACKS := 8
const SCRIPT := "res://tools/blender/build_drone.py"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var wbs := _wheelbases()
	for c in SKIPPED:
		var s := DesignSession.default_for_class(c)
		results.append(TestResult.new("%s has no frame document (not a plain plate frame)" % c,
			s != null and s.frame_document() == null and not DesignSession.FRAME_DOCUMENTS.has(c), c))
	for c in CLASSES:
		results.append_array(_class_checks(c, catalog, wbs))
	return results


## CFGS' `wb=` per class, read from the Blender script itself.
static func _wheelbases() -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(SCRIPT)
	var rx := RegEx.new()
	rx.compile("\"([a-z0-9_]+)\": dict\\(wb=([0-9.]+)")
	for m in rx.search_all(text):
		out[m.get_string(1)] = float(m.get_string(2)) * 1000.0
	return out


static func _bbox(mesh: Mesh, node: Node3D, root: Node3D) -> AABB:
	var xf := PickRegistry._xform_to(node, root)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for soup in FrameGen.mesh_soups(mesh):
		for p in (xf * (soup as PackedVector3Array)):
			lo = lo.min(p)
			hi = hi.max(p)
	return AABB(lo * 1000.0, (hi - lo) * 1000.0)


static func _worst(a: AABB, b: AABB) -> float:
	var w := 0.0
	for v in [a.position - b.position, a.end - b.end]:
		w = maxf(w, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))))
	return w


static func _hole_centre(hole: PackedVector2Array) -> Vector2:
	var r := Rect2(hole[0], Vector2.ZERO)
	for q in hole:
		r = r.expand(q)
	return r.get_center()


static func _class_checks(c: String, catalog: PartsCatalog, wbs: Dictionary) -> Array:
	var out: Array = []
	var session := DesignSession.default_for_class(c)
	var doc := session.frame_document() if session != null else null
	out.append(TestResult.new("%s: the class opens with a frame document" % c, doc != null and doc.plates.size() == 6, c))
	if doc == null:
		return out
	out.append(TestResult.new("%s: the document is the class's seed frame part (%s)" % [c, doc.id],
		doc.id == String(session.selection.get("frame", "")) and catalog.get_part(doc.id) != null, doc.id))
	out.append(TestResult.new("%s: four motors, 4 arms + 2 plates, a standoff and two screws per stack" % c,
		doc.motors.size() == 4 and doc.hardware.size() == 3 * STACKS and doc.plates.size() == 6, "%d hardware" % doc.hardware.size()))
	# wheelbase: the diagonal motor distance equals the Blender config's
	var by_name := {}
	for m in doc.motors:
		by_name[String(m["name"])] = AirframeDocument.point_of(m["position_mm"])
	var diag := (by_name["M1"] as Vector2).distance_to(by_name["M4"])
	var diag2 := (by_name["M2"] as Vector2).distance_to(by_name["M3"])
	var want_wb: float = float(wbs.get(c, -1.0))
	out.append(TestResult.new("%s: wheelbase %.2f / %.2f mm equals CFGS wb %.2f mm within %.1f mm" % [c, diag, diag2, want_wb, MATCH_TOL_MM],
		want_wb > 0.0 and absf(diag - want_wb) <= MATCH_TOL_MM and absf(diag2 - want_wb) <= MATCH_TOL_MM, c))
	# the drawn frame against the GLB's own plate meshes
	var ds := DesignSpace.new(session, catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	var root := ds._doc_root
	var worst_box := 0.0
	var worst_hole := 0.0
	var worst_motor := 0.0
	var proxies_seen := 0
	var proxies_named := 0
	var drawn_ok := true
	var no_glb := []
	for plate in doc.plates:
		var mesh_name := FrameTools.plate_mesh(plate)
		var node := root.find_child(mesh_name, true, false) as MeshInstance3D
		if node == null or not ds._glb_meshes.has(mesh_name) or not ds._gen_meshes.has(mesh_name):
			no_glb.append(mesh_name)
			continue
		if node.mesh != ds._gen_meshes[mesh_name]:
			drawn_ok = false
		worst_box = maxf(worst_box, _worst(_bbox(ds._glb_meshes[mesh_name], node, root), _bbox(node.mesh, node, root)))
		var holes := AirframeDocument.plate_holes(plate)
		var names: Array = plate.get("hole_names", [])
		var owner := String(plate.get("owner", ""))
		var proxy_by_name := {}
		for px in ds._glb_proxies.get(owner, []):
			proxy_by_name[String(px.name)] = px
		for k in holes.size():
			var hn := String(names[k]) if k < names.size() else ""
			var hc := _hole_centre(holes[k] as PackedVector2Array)
			if hn.begins_with("pick_"):
				proxies_named += 1
			if proxy_by_name.has(hn):
				var px := proxy_by_name[hn] as MeshInstance3D
				var bb := _bbox(px.mesh, px, root)
				worst_hole = maxf(worst_hole, Vector2(bb.get_center().x, bb.get_center().z).distance_to(hc))
				proxies_seen += 1
			elif hn.begins_with("motor_bore_") and plate.has("tip_point"):
				worst_motor = maxf(worst_motor, hc.distance_to(AirframeDocument.point_of(plate["tip_point"])))
	out.append(TestResult.new("%s: every plate has a GLB mesh and is drawn by FrameGen" % c, no_glb.is_empty() and drawn_ok, str(no_glb)))
	out.append(TestResult.new("%s: generated plate boxes equal the GLB plates' within %.1f mm (worst %.3f)" % [c, MATCH_TOL_MM, worst_box],
		no_glb.is_empty() and worst_box <= MATCH_TOL_MM, "%.4f" % worst_box))
	out.append(TestResult.new("%s: %d document cut-outs sit on the GLB's pick proxies within %.1f mm (worst %.3f)" % [c, proxies_seen, MATCH_TOL_MM, worst_hole],
		proxies_named > 0 and proxies_seen == proxies_named and worst_hole <= MATCH_TOL_MM, "%d proxies, %.4f" % [proxies_seen, worst_hole]))
	out.append(TestResult.new("%s: each motor bore sits at its motor within %.1f mm (worst %.3f)" % [c, MATCH_TOL_MM, worst_motor],
		worst_motor <= MATCH_TOL_MM, "%.4f" % worst_motor))
	# standoffs: the hidden GLB nodes against the document hardware
	var worst_stand := 0.0
	var stands := 0
	for glb in root.find_children("frame_standoff_*", "MeshInstance3D", true, false):
		if glb.get_parent() == ds.hardware_root:
			continue
		var bb := _bbox((glb as MeshInstance3D).mesh, glb as Node3D, root)
		for item in doc.hardware:
			if "frame_" + String(item["name"]) == String(glb.name):
				var p := AirframeDocument.point_of(item["position_mm"])
				worst_stand = maxf(worst_stand, Vector2(bb.get_center().x, bb.get_center().z).distance_to(p))
				stands += 1
	out.append(TestResult.new("%s: %d document standoffs sit on the GLB's within %.1f mm (worst %.3f)" % [c, stands, MATCH_TOL_MM, worst_stand],
		stands == STACKS and worst_stand <= MATCH_TOL_MM, "%d, %.4f" % [stands, worst_stand]))
	# the drawn plates are real: closed, through holes (the same checks the 5" has)
	var drawn_fail := []
	for plate in doc.plates:
		for r in TestFrameGen._plate_checks(ds, plate, " [%s]" % c):
			if not (r as TestResult).passed:
				drawn_fail.append((r as TestResult).name)
	out.append(TestResult.new("%s: every generated plate is closed, solid and drilled through" % c, drawn_fail.is_empty(), str(drawn_fail)))
	ds.free()
	out.append_array(_figures_and_edit(c, catalog))
	return out


static func _figures(b: Build) -> String:
	var mp := b.mass_properties
	return "%s|%s|%s|%s" % [b.all_up_weight_g(), var_to_str(mp.com_m), var_to_str(mp.inertia), mp.total_mass_kg]


static func _figures_and_edit(c: String, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var session := DesignSession.default_for_class(c)
	var plain := DroneClass.starting_project(c, "plain").to_build(catalog)
	var built := session.build(catalog)
	out.append(TestResult.new("%s: the unedited document leaves mass, centre and inertia bit-identical to the catalog build" % c,
		plain != null and built != null and _figures(plain) == _figures(built), _figures(built)))
	var doc := session.frame_document()
	var fl := session.plate_of_mesh("frame_arm_FL")
	var root_p := AirframeDocument.point_of(doc.plates[fl]["root_point"])
	var tip_p := AirframeDocument.point_of(doc.plates[fl]["tip_point"])
	var drilled := false
	var why := ""
	for i in 30:
		var frac := 0.25 + 0.02 * i
		var r := session.drill(fl, root_p.lerp(tip_p, frac), 1.6)
		why = String(r.get("reason", ""))
		if r["ok"]:
			drilled = true
			break
	out.append(TestResult.new("%s: a hole can be drilled in the front-left arm" % c, drilled, why))
	var edited := session.build(catalog)
	out.append(TestResult.new("%s: the drilled frame flies lighter (%.4f -> %.4f g)" % [c, built.all_up_weight_g(), edited.all_up_weight_g()],
		drilled and edited != null and edited.all_up_weight_g() < built.all_up_weight_g() - 0.0005, ""))
	var want := JSON.stringify(session.frame_document().to_dictionary())
	var reopened := DesignFile.from_dict(JSON.parse_string(JSON.stringify(DesignFile.to_dict(session, "t"))), catalog)
	var s2: DesignSession = reopened["session"]
	out.append(TestResult.new("%s: the edit persists through a design-file round trip, same weight" % c,
		s2 != null and s2.frame_document() != null and JSON.stringify(s2.frame_document().to_dictionary()) == want
		and s2.build(catalog).all_up_weight_g() == edited.all_up_weight_g(), String(reopened.get("reason", ""))))
	out.append(TestResult.new("%s: undo takes the hole back out" % c,
		session.undo() and session.build(catalog).all_up_weight_g() == built.all_up_weight_g(), ""))
	return out
