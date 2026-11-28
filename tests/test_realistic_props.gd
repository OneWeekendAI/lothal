class_name TestRealisticProps
extends RefCounted
## Props from the blade generator: handedness and a real bore.
##
## Chirality measure: S = sum over blade vertices of (axial y * tangential z). Each section is a
## chord line tilted by the blade angle beta out of the tangential axis, so its corners have y and z
## of the same sign when beta is in (0, 90) degrees: S is clearly positive for the unmirrored blade.
## Mirroring z -> -z negates every product, so S flips sign and its magnitude is unchanged. It needs
## no knowledge of how the mesh was produced, only of the vertices that came out.
##
## One result per catalog propeller (generated per case, so the failure count means something).


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	for prop in _catalog_props():
		var id := String(prop["part_id"])
		results.append(_test_chirality(catalog, id))
	for prop in _catalog_props():
		results.append(_test_bore(catalog, String(prop["part_id"])))
	results.append(_test_bore_rule())
	results.append(_test_hub_faces_outward(catalog))
	results.append(_test_airframe_reversed_corner(catalog))
	return results


static func _catalog_props() -> Array:
	var f := FileAccess.open("res://data/parts/propellers.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	return data["parts"]


static func _prop(catalog: PartsCatalog, id: String, spin: float) -> PropellerMesh:
	var mesh := PropellerMesh.new()
	mesh.spin = spin
	mesh.rebuild(catalog.get_part(id))
	return mesh


static func _arrays(node: Node) -> Array:
	return ((node as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)


static func chirality(mesh: PropellerMesh) -> float:
	var verts: PackedVector3Array = _arrays(mesh.get_node("Blade_0"))[Mesh.ARRAY_VERTEX]
	var s := 0.0
	for v in verts:
		s += v.y * v.z
	return s


static func _test_chirality(catalog: PartsCatalog, id: String) -> TestResult:
	var cw := _prop(catalog, id, 1.0)
	var ccw := _prop(catalog, id, -1.0)
	var a := chirality(cw)
	var b := chirality(ccw)
	cw.free()
	ccw.free()
	var ok := a * b < 0.0 and absf(a) > 1e-12 and absf(absf(a) - absf(b)) <= 0.01 * absf(a)
	return TestResult.new("%s: CW and CCW blades are mirror images" % id, ok,
		"chirality CW %s, CCW %s" % [a, b])


static func _hub_triangles(mesh: PropellerMesh) -> Array:
	var arrays := _arrays(mesh.get_node("Hub"))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tris: Array = []
	for i in range(0, idx.size(), 3):
		tris.append([verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]])
	return tris


## Moller-Trumbore, both faces.
static func _ray_hits(origin: Vector3, dir: Vector3, tri: Array) -> bool:
	var e1: Vector3 = tri[1] - tri[0]
	var e2: Vector3 = tri[2] - tri[0]
	var p := dir.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-18:
		return false
	var inv := 1.0 / det
	var t := origin - (tri[0] as Vector3)
	var u := t.dot(p) * inv
	if u < 0.0 or u > 1.0:
		return false
	var q := t.cross(e1)
	var v := dir.dot(q) * inv
	if v < 0.0 or u + v > 1.0:
		return false
	return e2.dot(q) * inv > 0.0


static func _test_bore(catalog: PartsCatalog, id: String) -> TestResult:
	var mesh := _prop(catalog, id, 1.0)
	var bore := PropellerMesh.bore_mm_for(catalog.get_part(id))
	var hits := 0
	var inner := INF
	for tri in _hub_triangles(mesh):
		if _ray_hits(Vector3(0, 1, 0), Vector3(0, -1, 0), tri):
			hits += 1
		for v in tri:
			inner = minf(inner, Vector2(v.x, v.z).length())
	mesh.free()
	var inner_mm := inner * 1000.0
	return TestResult.new("%s: bore of %.1f mm is open along the spin axis" % [id, bore],
		hits == 0 and absf(inner_mm - bore * 0.5) <= 0.05,
		"%d hub triangles hit by the axis ray, inner hub radius %.3f mm vs bore radius %.3f mm" % [hits, inner_mm, bore * 0.5])


static func _test_bore_rule() -> TestResult:
	var small := PropellerMesh.bore_mm_for({"specs": {"diameter_inches": 3.0}})
	var big := PropellerMesh.bore_mm_for({"specs": {"diameter_inches": 5.0}})
	var given := PropellerMesh.bore_mm_for({"specs": {"diameter_inches": 5.0, "bore_mm": 6.0}})
	return TestResult.new("bore_mm_for: 1.5 up to 3 in, 5.0 above, spec wins",
		small == 1.5 and big == 5.0 and given == 6.0, "%s %s %s" % [small, big, given])


## Hub winding checked against the blade's, which tests/test_propeller_mesh.gd already proves
## outward: both signed volumes must be positive in the same convention.
static func _test_hub_faces_outward(catalog: PartsCatalog) -> TestResult:
	var mesh := _prop(catalog, "prop_5x43x3", 1.0)
	var vol := 0.0
	for tri in _hub_triangles(mesh):
		vol += (tri[0] as Vector3).dot((tri[1] as Vector3).cross(tri[2])) / 6.0
	var blade_vol := _signed_volume(mesh.get_node("Blade_0"))
	mesh.free()
	return TestResult.new("hub tube is wound the same way round as the blade (faces outward)",
		vol * blade_vol > 0.0, "hub volume %s, blade volume %s" % [vol, blade_vol])


static func _signed_volume(node: Node) -> float:
	var arrays := _arrays(node)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vol := 0.0
	for i in range(0, idx.size(), 3):
		vol += verts[idx[i]].dot(verts[idx[i + 1]].cross(verts[idx[i + 2]])) / 6.0
	return vol


static func _test_airframe_reversed_corner(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID))
	var m1: PropellerMesh = airframe.propeller_meshes["M1"]
	var m2: PropellerMesh = airframe.propeller_meshes["M2"]
	var a := chirality(m1)
	var b := chirality(m2)
	var spins := "%s/%s" % [m1.spin, m2.spin]
	var opposed := m1.spin * m2.spin < 0.0
	airframe.free()
	return TestResult.new("an AirframeModel reversed corner draws the mirrored blade",
		opposed and a * b < 0.0 and absf(absf(a) - absf(b)) <= 0.01 * absf(a),
		"spins %s, chirality %s vs %s" % [spins, a, b])
