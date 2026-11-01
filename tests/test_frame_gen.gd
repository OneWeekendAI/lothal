class_name TestFrameGen
extends RefCounted
## PLAN Section 6, the realistic frame: every plate the 5" Design Space draws comes from FrameGen, and
## is checked ON THE NODE it is drawn on (not a mesh built for the test): closed and manifold, the
## bounding box of the document's outline and thickness within 0.01 mm, every document hole a through
## hole by a ray, the material beside each hole solid, the hardware instanced one per document item,
## the whole frame under its triangle budget. A drilled (edited) arm must pass the same checks. And the
## hole check is proved able to fail: with hole subtraction skipped it must find no through hole.

const CLASS_ID := "five_inch"
const AABB_TOL_MM := 0.01
const VOLUME_TOL := 0.03
const HOLE_MM := 3.0
const ALONG_MM := 91.0


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	for i in doc.plates.size():
		results.append_array(_plate_checks(ds, doc.plates[i], ""))
	results.append_array(_test_hardware(ds, doc))
	results.append_array(_test_budget(ds, doc))
	results.append_array(_test_surfaces(ds, doc))
	results.append_array(_test_hole_proof(doc))
	results.append_array(_test_countersink(doc))
	results.append_array(_test_edited(catalog))
	ds.free()
	return results


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	return ds


static func _node(ds: DesignSpace, plate: Dictionary) -> MeshInstance3D:
	return ds._doc_root.find_child(FrameTools.plate_mesh(plate), true, false) as MeshInstance3D


## The node's drawn triangles in GLB-root space (metres), one soup per surface.
static func _soups(ds: DesignSpace, node: MeshInstance3D) -> Array:
	var xf := PickRegistry._xform_to(node, ds._doc_root)
	var out: Array = []
	for soup in FrameGen.mesh_soups(node.mesh):
		out.append(xf * (soup as PackedVector3Array))
	return out


static func _plate_checks(ds: DesignSpace, plate: Dictionary, tag: String) -> Array:
	var out: Array = []
	var nm := FrameTools.plate_mesh(plate) + tag
	var node := _node(ds, plate)
	if node == null or node.mesh == null:
		out.append(TestResult.new("%s is drawn" % nm, false, "no node"))
		return out
	var soups := _soups(ds, node)
	var rep := FrameGen.closed_report(soups)
	out.append(TestResult.new("%s: the drawn plate mesh is closed and manifold" % nm, rep["closed"],
		"%s" % rep))
	# Bounding box against the document, in plan mm.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s in soups:
		for p in s:
			lo = lo.min(p)
			hi = hi.max(p)
	var outline := AirframeDocument.plate_outline(plate)
	var r := Rect2(outline[0], Vector2.ZERO)
	for q in outline:
		r = r.expand(q)
	var z0 := AirframeDocument.plate_z_mm(plate)
	var t := AirframeDocument.plate_thickness_mm(plate)
	var want_lo := Vector3(r.position.x, z0, r.position.y)
	var want_hi := Vector3(r.end.x, z0 + t, r.end.y)
	var got_lo := Vector3(lo.x, lo.y, lo.z) * 1000.0
	var got_hi := Vector3(hi.x, hi.y, hi.z) * 1000.0
	var err := maxf(_maxabs(got_lo - want_lo), _maxabs(got_hi - want_hi))
	out.append(TestResult.new("%s: bounding box equals the outline and thickness within 0.01 mm" % nm,
		err <= AABB_TOL_MM, "worst %.4f mm (got %s..%s, want %s..%s)" % [err, got_lo, got_hi, want_lo, want_hi]))
	# Volume: the faces point outward and enclose the material (outline minus holes) times thickness,
	# less the chamfers.
	var area := absf(PolygonProps.area(outline))
	for h in AirframeDocument.plate_holes(plate):
		area -= absf(PolygonProps.area(h as PackedVector2Array))
	var want_v := area * t
	var got_v := _volume_mm3(soups)
	out.append(TestResult.new("%s: faces point outward and hold the plate's volume within 3%%" % nm,
		got_v > 0.0 and absf(got_v - want_v) <= VOLUME_TOL * want_v, "%.1f vs %.1f mm3" % [got_v, want_v]))
	var blocked: Array = []
	var hollow: Array = []
	var holes := AirframeDocument.plate_holes(plate)
	for k in holes.size():
		var hole := holes[k] as PackedVector2Array
		var c := FrameGen.hole_point(hole)
		if not FrameGen.ray_through(soups, plate, c)["through"]:
			blocked.append(k)
		var beside := _beside(hole, outline, holes, k)
		if beside.x < INF and FrameGen.ray_through(soups, plate, beside)["through"]:
			hollow.append(k)
	out.append(TestResult.new("%s: every document hole (%d) is a through hole (ray test)" % [nm, holes.size()],
		holes.size() > 0 and blocked.is_empty(), "blocked %s" % [blocked]))
	out.append(TestResult.new("%s: the material just outside every hole is solid (ray test)" % nm,
		hollow.is_empty(), "hollow beside %s" % [hollow]))
	return out


static func _maxabs(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))


## A point 0.05 mm outside the hole's widest-spaced edge, inside the outline and no other hole.
static func _beside(hole: PackedVector2Array, outline: PackedVector2Array, holes: Array, k: int) -> Vector2:
	var c := FrameGen.hole_point(hole)
	for i in hole.size():
		var p := hole[i]
		var q := p + (p - c).normalized() * 0.05
		if not Geometry2D.is_point_in_polygon(q, outline):
			continue
		var clear := true
		for j in holes.size():
			if j != k and Geometry2D.is_point_in_polygon(q, holes[j]):
				clear = false
		if clear:
			return q
	return Vector2(INF, INF)


static func _volume_mm3(soups: Array) -> float:
	var v := 0.0
	for s in soups:
		var ps := s as PackedVector3Array
		for i in int(ps.size() / 3.0):
			v += ps[i * 3].dot(ps[i * 3 + 1].cross(ps[i * 3 + 2]))
	# Godot front faces are clockwise seen from outside, so an outward-facing closed mesh sums negative.
	return -v / 6.0 * 1.0e9


static func _test_hardware(ds: DesignSpace, doc: AirframeDocument) -> Array:
	var out: Array = []
	var holder := ds.hardware_root
	var n := holder.get_child_count() if holder != null else -1
	out.append(TestResult.new("the document lists the drawn hardware: 8 standoffs and 16 screws",
		FrameHardware.items_of_kind(doc, "standoff_hex").size() == 8 and FrameHardware.items_of_kind(doc, "screw").size() == 16,
		"%d items" % doc.hardware.size()))
	var misplaced: Array = []
	if holder != null:
		for i in mini(n, doc.hardware.size()):
			var mi := holder.get_child(i) as MeshInstance3D
			var item: Dictionary = doc.hardware[i]
			var at := FrameView.plan_point(mi.transform.origin, Transform3D.IDENTITY)
			if String(mi.name) != FrameGen.hardware_node_name(item) or mi.mesh == null \
					or at.distance_to(AirframeDocument.point_of(item["position_mm"])) > 0.01:
				misplaced.append(String(mi.name))
	out.append(TestResult.new("hardware instance count equals the document's hardware list, each at its item",
		n == doc.hardware.size() and n > 0 and misplaced.is_empty(), "%d instances, %d items, wrong %s" % [n, doc.hardware.size(), misplaced]))
	var shown := 0
	for pattern in ["frame_standoff_*", "frame_screw_*"]:
		for glb in ds._doc_root.find_children(pattern, "MeshInstance3D", true, false):
			if (glb as Node).get_parent() != holder and (glb as MeshInstance3D).visible:
				shown += 1
	out.append(TestResult.new("the GLB's own standoff and screw meshes are hidden", shown == 0, "%d visible" % shown))
	var entry := {}
	for e in ds.picks.entries:
		if String(e["address"]) == "frame/screw/top/3":
			entry = e
	out.append(TestResult.new("picking still reaches a screw, now the instanced one",
		not entry.is_empty() and (entry["node"] as Node).get_parent() == holder, "%s" % [entry.get("node")]))
	var bad: Array = []
	if holder != null:
		var seen := {}
		for c in holder.get_children():
			var m := (c as MeshInstance3D).mesh
			if seen.has(m):
				continue
			seen[m] = true
			if not FrameGen.closed_report(FrameGen.mesh_soups(m))["closed"]:
				bad.append(String(c.name))
	out.append(TestResult.new("every hardware mesh is closed and manifold, and shared between instances",
		bad.is_empty() and holder != null and _shared(holder), "open %s" % [bad]))
	return out


## One mesh per (kind, size): the 8 standoffs share one, the 16 screws another.
static func _shared(holder: Node3D) -> bool:
	var by_kind := {}
	for c in holder.get_children():
		var kind := String(c.name).get_slice("_", 1)
		if not by_kind.has(kind):
			by_kind[kind] = {}
		by_kind[kind][(c as MeshInstance3D).mesh] = true
	return by_kind.size() == 2 and by_kind.values().all(func(d): return (d as Dictionary).size() == 1)


static func _test_budget(ds: DesignSpace, doc: AirframeDocument) -> Array:
	var tris := 0
	for plate in doc.plates:
		var node := _node(ds, plate)
		if node != null and node.mesh != null:
			tris += int(FrameGen.closed_report(_soups(ds, node))["triangles"])
	if ds.hardware_root != null:
		for c in ds.hardware_root.get_children():
			tris += int(FrameGen.closed_report(FrameGen.mesh_soups((c as MeshInstance3D).mesh))["triangles"])
	return [TestResult.new("the frame (plates + hardware) stays under its %d-triangle budget" % FrameGen.TRIANGLE_BUDGET,
		tris > 0 and tris <= FrameGen.TRIANGLE_BUDGET, "%d triangles" % tris)]


static func _test_surfaces(ds: DesignSpace, doc: AirframeDocument) -> Array:
	var wrong: Array = []
	for plate in doc.plates:
		var node := _node(ds, plate)
		var glb: Mesh = ds._glb_meshes.get(FrameTools.plate_mesh(plate))
		if node == null or node.mesh == null or node.mesh == glb or node.mesh.get_surface_count() != 2 \
				or node.mesh.surface_get_material(FrameGen.SURF_FACE) != ds.face_material \
				or node.mesh.surface_get_material(FrameGen.SURF_EDGE) != ds.edge_material:
			wrong.append(FrameTools.plate_mesh(plate))
	return [TestResult.new("every plate is the generator's mesh: faces in the FrameLook twill, cut edges on their own surface",
		wrong.is_empty() and ds.edge_material != null and ds.face_material != null, "%s" % [wrong])]


static func _test_hole_proof(doc: AirframeDocument) -> Array:
	var plate: Dictionary = doc.plates[0]
	var arr := FrameGen.plate_arrays(plate, false, {"subtract_holes": false})
	var soups := [arr["surfaces"][0]["verts"], arr["surfaces"][1]["verts"]]
	var through := 0
	for h in AirframeDocument.plate_holes(plate):
		if FrameGen.ray_through(soups, plate, FrameGen.hole_point(h))["through"]:
			through += 1
	return [TestResult.new("the hole check can fail: with hole subtraction skipped it finds no through hole",
		through == 0 and FrameGen.closed_report(soups)["closed"], "%d through" % through)]


static func _test_countersink(doc: AirframeDocument) -> Array:
	var out: Array = []
	var plate: Dictionary = (doc.plates[4] as Dictionary).duplicate(true)
	var holes := AirframeDocument.plate_holes(plate)
	var hole := holes[0] as PackedVector2Array
	var c := FrameGen.hole_point(hole)
	var rr := 0.0
	for p in hole:
		rr = maxf(rr, p.distance_to(c))
	var probe := c + Vector2(rr + 0.6, 0.0)
	var top := AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate)
	var plain := _hit_z(plate, probe)
	plate[AirframeDocument.PLATE_COUNTERSUNK_HOLES] = [0]
	var sunk := _hit_z(plate, probe)
	var arr := FrameGen.plate_arrays(plate, true)
	var rep := FrameGen.closed_report([arr["surfaces"][0]["verts"], arr["surfaces"][1]["verts"]])
	out.append(TestResult.new("a countersunk hole is a cone on the head side, and the plate stays closed",
		rep["closed"] and absf(plain - top) < 0.01 and sunk < top - 0.2, "plain %.3f sunk %.3f top %.3f %s" % [plain, sunk, top, rep]))
	return out


static func _hit_z(plate: Dictionary, plan: Vector2) -> float:
	var arr := FrameGen.plate_arrays(plate, true)
	var tm := FrameGen.mm_triangle_mesh([arr["surfaces"][0]["verts"], arr["surfaces"][1]["verts"]])
	var hit: Dictionary = tm.intersect_ray(AirframeDocument.world_m(plan, 100.0) * 1000.0, Vector3.DOWN)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


static func _test_edited(catalog: PartsCatalog) -> Array:
	var ds := _ds(catalog)
	var doc := ds.session.frame_document()
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var plate: Dictionary = doc.plates[fl]
	var before := AirframeDocument.plate_holes(plate).size()
	var aim := AirframeDocument.point_of(plate["tip_point"]).normalized() * ALONG_MM
	ds.select("frame/arm/FL")
	ds.set_frame_tool("drill")
	ds.drill_d_mm = HOLE_MM
	var z := AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate)
	var v := ds.drill_at(ds.rig.project(FrameView.space_point(aim, z, ds.doc_xf())))
	doc = ds.session.frame_document()
	plate = doc.plates[fl]
	var out: Array = [TestResult.new("edited frame: the drill added a hole to arm FL and the arm was regenerated",
		v.get("ok", false) and AirframeDocument.plate_holes(plate).size() == before + 1 and ds.plate_regenerated(fl),
		"%s" % [v])]
	out.append_array(_plate_checks(ds, plate, " (drilled)"))
	ds.free()
	return out
