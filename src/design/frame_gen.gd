class_name FrameGen
extends RefCounted
## The realistic frame (PLAN Section 6): ONE generator for every flat carbon plate, catalog or edited,
## and the hardware the document lists. Static and pure: DesignSpace owns the nodes.
##
## ## A plate
##
## The material between z0 and z1 = z0 + thickness: outline minus every hole. Every boundary loop (the
## outline and each hole) is a ring of TRUE points (the document's polygon) plus, per point, a miter
## direction into the material. Each face (top, bottom) is the loops pushed into the material by that
## face's chamfer width; the cut edge is three strips per loop: top chamfer (inset at z1 -> true at
## z1 - c), the wall (true, full depth between the chamfers), bottom chamfer. A countersunk hole has a
## 90-degree cone in place of its chamfer on the head side (bottom plate: underside, else top).
##
## ## Closed by construction
##
## Each face is triangulated with Delaunay over the loop points only, keeping triangles whose centroid
## is in the material. That is exact once every loop edge is a Delaunay edge, so any loop edge that is
## missing is split at its midpoint (on every ring of that loop at once, so the strips stay matched)
## and the face is triangulated again. No T-junction can survive: the faces and strips share the same
## points. `closed_report` proves it on the result, never assumes it.
##
## ## Surfaces
##
## Surface 0 (SURF_FACE) is the two faces: UVs are plan mm * FrameView.UV_PER_MM (the GLB's twill
## repeat), turned 90 degrees for body plates. Surface 1 (SURF_EDGE) is every cut edge (chamfers,
## walls, countersinks): U runs along the perimeter, V up the edge.

const SURF_FACE := 0
const SURF_EDGE := 1
## Chamfer width = thickness * this, clamped to [CHAMFER_MIN_MM, CHAMFER_MAX_MM].
const CHAMFER_PER_T := 0.06
const CHAMFER_MIN_MM := 0.12
const CHAMFER_MAX_MM := 0.3
## Countersink: a 90-degree cone out to HEAD_PER_THREAD * the hole's diameter, never deeper than this
## fraction of the plate.
const COUNTERSINK_HEAD_PER_HOLE := 1.9
const COUNTERSINK_MAX_DEPTH := 0.6
const MAX_SPLIT_ROUNDS := 24
## The frame's triangle budget (plates + hardware), checked by tests/test_frame_gen.gd. The catalog
## 5" frame uses about 16.5k; the head room is for drilled holes and pockets.
const TRIANGLE_BUDGET := 25000
## Hardware mesh resolution.
const SCREW_SEGMENTS := 24
const HEX_SOCKET_PER_THREAD := 2.5 / 3.0


static func chamfer_mm(t_mm: float) -> float:
	return clampf(t_mm * CHAMFER_PER_T, CHAMFER_MIN_MM, CHAMFER_MAX_MM)


## The plate as raw arrays in GLB-root space (metres). `opts`: {subtract_holes: bool (default true,
## false only for the proof that the hole check can fail)}. Returns {surfaces: [ {verts, normals, uvs},
## {verts, normals, uvs} ], ok: bool} where every 3 verts are one triangle, front face clockwise as Godot
## draws it (FrameView._face's rule).
static func plate_arrays(plate: Dictionary, turn: bool, opts: Dictionary = {}) -> Dictionary:
	var outline := AirframeDocument.plate_outline(plate)
	var holes: Array = AirframeDocument.plate_holes(plate) if opts.get("subtract_holes", true) else []
	var t := AirframeDocument.plate_thickness_mm(plate)
	var z0 := AirframeDocument.plate_z_mm(plate)
	var z1 := z0 + t
	var c := chamfer_mm(t)
	var sink_bottom := String(plate.get("role", "")) == AirframeDocument.ROLE_BOTTOM
	var loops: Array = []
	loops.append(_loop(outline, false, c, c))
	for k in holes.size():
		var h := holes[k] as PackedVector2Array
		if h.size() < 3:
			continue
		var wt := c
		var wb := c
		if AirframeDocument.hole_is_countersunk(plate, k):
			var d := 2.0 * sqrt(absf(PolygonProps.area(h)) / PI)
			var w := minf(0.5 * d * (COUNTERSINK_HEAD_PER_HOLE - 1.0), t * COUNTERSINK_MAX_DEPTH)
			if sink_bottom:
				wb = w
			else:
				wt = w
		loops.append(_loop(h, true, wt, wb))
	_limit_widths(loops)
	var tri_top := PackedInt32Array()
	var tri_bot := PackedInt32Array()
	var ok := false
	for _round in MAX_SPLIT_ROUNDS:
		var a := _face_tris(loops, true)
		var b := _face_tris(loops, false)
		tri_top = a["tris"]
		tri_bot = b["tris"]
		var missing: Dictionary = a["missing"]
		for key in b["missing"]:
			missing[key] = true
		if missing.is_empty():
			ok = true
			break
		_split(loops, missing)
	var faces := {"verts": [], "normals": [], "uvs": []}
	var edges := {"verts": [], "normals": [], "uvs": []}
	_emit_face(faces, loops, tri_top, true, z1, turn)
	_emit_face(faces, loops, tri_bot, false, z0, turn)
	for lp in loops:
		_emit_strips(edges, lp, z0, z1)
	return {"surfaces": [_packed(faces), _packed(edges)], "ok": ok}


## The emit buffers (plain Arrays: a PackedArray inside a Dictionary is copied on append) as packed.
static func _packed(out: Dictionary) -> Dictionary:
	return {"verts": PackedVector3Array(out["verts"]), "normals": PackedVector3Array(out["normals"]),
		"uvs": PackedVector2Array(out["uvs"])}


## The plate as a two-surface mesh in the space `local_xf` maps the GLB root into (the inverse of the
## mesh node's transform in the scene). `face_mat` on SURF_FACE, `edge_mat` on SURF_EDGE.
static func plate_mesh(plate: Dictionary, local_xf: Transform3D, face_mat: Material, edge_mat: Material,
		turn: bool, opts: Dictionary = {}) -> ArrayMesh:
	var arr := plate_arrays(plate, turn, opts)
	var mesh := ArrayMesh.new()
	var mats := [face_mat, edge_mat]
	for s in 2:
		var surf: Dictionary = arr["surfaces"][s]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vs: PackedVector3Array = surf["verts"]
		var ns: PackedVector3Array = surf["normals"]
		var us: PackedVector2Array = surf["uvs"]
		for i in vs.size():
			st.set_normal((local_xf.basis * ns[i]).normalized())
			st.set_uv(us[i])
			st.add_vertex(local_xf * vs[i])
		st.index()
		st.generate_tangents()
		st.commit(mesh)
		if mats[s] != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[s])
	return mesh


# --- loops -------------------------------------------------------------------------------------

## A boundary loop: true points (plan mm, CCW) and per point the miter direction into the material,
## scaled so that p + dir * w is the w-inset line. `wt`/`wb` = the top and bottom chamfer widths.
static func _loop(poly: PackedVector2Array, is_hole: bool, wt: float, wb: float) -> Dictionary:
	var pts := PackedVector2Array()
	for p in (poly if PolygonProps.area(poly) >= 0.0 else _reversed(poly)):
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 1.0e-6:
			pts.append(p)
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) <= 1.0e-6:
		pts.remove_at(pts.size() - 1)
	var n := pts.size()
	var dirs := PackedVector2Array()
	for i in n:
		var e0 := (pts[i] - pts[(i - 1 + n) % n]).normalized()
		var e1 := (pts[(i + 1) % n] - pts[i]).normalized()
		# CCW: the interior is left of each edge; a hole's material is outside it.
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		if is_hole:
			n0 = -n0
			n1 = -n1
		var m := (n0 + n1)
		m = n1 if m.length() < 1.0e-6 else m.normalized()
		dirs.append(m / maxf(m.dot(n1), 0.35))
	return {"pts": pts, "dirs": dirs, "hole": is_hole, "wt": wt, "wb": wb}


## A chamfer may not eat the web between two cuts: each loop's widths are capped at WEB_SHARE of its
## clearance to the nearest other loop (the drawn 5" arm has a 0.17 mm web between a pocket and a hole).
const WEB_SHARE := 0.4


static func _limit_widths(loops: Array) -> void:
	for a in loops.size():
		var gap := INF
		for b in loops.size():
			if a != b:
				gap = minf(gap, _clearance(loops[a]["pts"], loops[b]["pts"]))
		var cap := WEB_SHARE * gap
		loops[a]["wt"] = minf(loops[a]["wt"], cap)
		loops[a]["wb"] = minf(loops[a]["wb"], cap)


static func _clearance(pa: PackedVector2Array, pb: PackedVector2Array) -> float:
	var best := INF
	for pair in [[pa, pb], [pb, pa]]:
		var ps: PackedVector2Array = pair[0]
		var qs: PackedVector2Array = pair[1]
		for p in ps:
			for j in qs.size():
				var q := Geometry2D.get_closest_point_to_segment(p, qs[j], qs[(j + 1) % qs.size()])
				best = minf(best, p.distance_to(q))
	return best


static func _reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.reverse()
	return out


static func _inset(lp: Dictionary, top: bool) -> PackedVector2Array:
	var w: float = lp["wt"] if top else lp["wb"]
	var out := PackedVector2Array()
	var pts: PackedVector2Array = lp["pts"]
	var dirs: PackedVector2Array = lp["dirs"]
	for i in pts.size():
		out.append(pts[i] + dirs[i] * w)
	return out


## Splits every listed edge ("loop:index") at its midpoint, on the true ring and its directions.
static func _split(loops: Array, missing: Dictionary) -> void:
	for li in loops.size():
		var lp: Dictionary = loops[li]
		var pts: PackedVector2Array = lp["pts"]
		var dirs: PackedVector2Array = lp["dirs"]
		var np := PackedVector2Array()
		var nd := PackedVector2Array()
		for i in pts.size():
			np.append(pts[i])
			nd.append(dirs[i])
			if missing.has("%d:%d" % [li, i]):
				var j := (i + 1) % pts.size()
				np.append((pts[i] + pts[j]) * 0.5)
				nd.append((dirs[i] + dirs[j]) * 0.5)
		lp["pts"] = np
		lp["dirs"] = nd


## Delaunay over one face's inset rings; keeps material triangles and lists missing loop edges.
static func _face_tris(loops: Array, top: bool) -> Dictionary:
	var all := PackedVector2Array()
	var rings: Array = []
	var starts: Array = []
	for lp in loops:
		var ring := _inset(lp, top)
		starts.append(all.size())
		rings.append(ring)
		all.append_array(ring)
	var centre := Vector2.ZERO
	for p in all:
		centre += p
	centre /= maxf(1.0, all.size())
	var local := PackedVector2Array()
	for p in all:
		local.append(p - centre)
	var idx := Geometry2D.triangulate_delaunay(local)
	var boxes: Array = []
	for r in rings:
		var box := Rect2((r as PackedVector2Array)[0], Vector2.ZERO)
		for p in r:
			box = box.expand(p)
		boxes.append(box)
	var tris := PackedInt32Array()
	var have := {}
	for k in int(idx.size() / 3.0):
		var a := idx[k * 3]
		var b := idx[k * 3 + 1]
		var c := idx[k * 3 + 2]
		var area := (all[b] - all[a]).cross(all[c] - all[a])
		if absf(area) < 1.0e-9:
			continue
		# Conformity is judged on the RAW triangulation: once every loop edge is a Delaunay edge no
		# triangle crosses a boundary, and the centroid test below is exact.
		for e in [[a, b], [b, c], [c, a]]:
			have[_ekey(e[0], e[1])] = true
		var g := (all[a] + all[b] + all[c]) / 3.0
		if not Geometry2D.is_point_in_polygon(g, rings[0]):
			continue
		var inside_hole := false
		for r in range(1, rings.size()):
			if (boxes[r] as Rect2).has_point(g) and Geometry2D.is_point_in_polygon(g, rings[r]):
				inside_hole = true
				break
		if inside_hole:
			continue
		tris.append_array([a, b, c])
	var missing := {}
	for li in rings.size():
		var n := (rings[li] as PackedVector2Array).size()
		for i in n:
			if not have.has(_ekey(starts[li] + i, starts[li] + (i + 1) % n)):
				missing["%d:%d" % [li, i]] = true
	return {"tris": tris, "missing": missing}


static func _ekey(a: int, b: int) -> int:
	return mini(a, b) * 1000003 + maxi(a, b)


# --- emit --------------------------------------------------------------------------------------

static func _w(p: Vector2, z_mm: float) -> Vector3:
	return AirframeDocument.world_m(p, z_mm)


static func _uv(p: Vector2, turn: bool) -> Vector2:
	return (Vector2(-p.y, p.x) if turn else p) * FrameView.UV_PER_MM


static func _emit_face(out: Dictionary, loops: Array, tris: PackedInt32Array, top: bool, z: float,
		turn: bool) -> void:
	var all := PackedVector2Array()
	for lp in loops:
		all.append_array(_inset(lp, top))
	var nrm := Vector3.UP if top else Vector3.DOWN
	for k in int(tris.size() / 3.0):
		var a := all[tris[k * 3]]
		var b := all[tris[k * 3 + 1]]
		var c := all[tris[k * 3 + 2]]
		_tri(out, [_w(a, z), _w(b, z), _w(c, z)], [_uv(a, turn), _uv(b, turn), _uv(c, turn)], nrm)


## The three strips of one loop: top chamfer, wall, bottom chamfer.
static func _emit_strips(out: Dictionary, lp: Dictionary, z0: float, z1: float) -> void:
	var pts: PackedVector2Array = lp["pts"]
	var top := _inset(lp, true)
	var bot := _inset(lp, false)
	var wt: float = lp["wt"]
	var wb: float = lp["wb"]
	var rows := [[top, z1], [pts, z1 - wt], [pts, z0 + wb], [bot, z0]]
	var n := pts.size()
	var s := 0.0
	for i in n:
		var j := (i + 1) % n
		var e := pts[j] - pts[i]
		var el := e.length()
		var into := Vector2(-e.y, e.x).normalized()
		if lp["hole"]:
			into = -into
		var out_plan := -into
		var v := 0.0
		for r in 3:
			var ra: PackedVector2Array = rows[r][0]
			var rb: PackedVector2Array = rows[r + 1][0]
			var za: float = rows[r][1]
			var zb: float = rows[r + 1][1]
			var hint := Vector3(out_plan.x, 0.0, out_plan.y)
			if r == 0:
				hint += Vector3(0, 1, 0)
			elif r == 2:
				hint += Vector3(0, -1, 0)
			var p00 := _w(ra[i], za)
			var p01 := _w(ra[j], za)
			var p10 := _w(rb[i], zb)
			var p11 := _w(rb[j], zb)
			var dv := Vector2(absf(za - zb), ra[i].distance_to(rb[i])).length()
			var u0 := Vector2(s, v) * FrameView.UV_PER_MM
			var u1 := Vector2(s + el, v) * FrameView.UV_PER_MM
			var u2 := Vector2(s, v + dv) * FrameView.UV_PER_MM
			var u3 := Vector2(s + el, v + dv) * FrameView.UV_PER_MM
			var nq := (p01 - p00).cross(p10 - p00)
			if nq.length() < 1.0e-14:
				nq = hint
			nq = nq.normalized()
			if nq.dot(hint) < 0.0:
				nq = -nq
			_tri(out, [p00, p01, p11], [u0, u1, u3], nq)
			_tri(out, [p00, p11, p10], [u0, u3, u2], nq)
			v += dv
		s += el


## One triangle, wound so it faces `normal` with Godot's clockwise front faces.
static func _tri(out: Dictionary, pts: Array, uvs: Array, normal: Vector3) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var order := [0, 1, 2] if (b - a).cross(c - a).dot(normal) <= 0.0 else [0, 2, 1]
	for k in order:
		(out["verts"] as Array).append(pts[k])
		(out["normals"] as Array).append(normal)
		(out["uvs"] as Array).append(uvs[k])


# --- checks (pure; tests and DesignSpace both call these) ---------------------------------------

## Welds a triangle soup by position (0.1 um) and counts directed edges: closed + manifold + oriented
## means every directed edge occurs once and its reverse once. Returns {closed, bad_edges, triangles}.
static func closed_report(soups: Array) -> Dictionary:
	var ids := {}
	var directed := {}
	var tris := 0
	for soup in soups:
		var vs := soup as PackedVector3Array
		for k in int(vs.size() / 3.0):
			var t := []
			for m in 3:
				var q := vs[k * 3 + m] * 1.0e7
				var key := Vector3i(roundi(q.x), roundi(q.y), roundi(q.z))
				if not ids.has(key):
					ids[key] = ids.size()
				t.append(ids[key])
			if t[0] == t[1] or t[1] == t[2] or t[0] == t[2]:
				continue
			tris += 1
			for m in 3:
				var e := Vector2i(t[m], t[(m + 1) % 3])
				directed[e] = int(directed.get(e, 0)) + 1
	var bad := 0
	for e in directed:
		if directed[e] != 1 or int(directed.get(Vector2i(e.y, e.x), 0)) != 1:
			bad += 1
	return {"closed": bad == 0 and tris > 0, "bad_edges": bad, "triangles": tris}


## All triangle positions of a mesh (every surface), in its own space.
static func mesh_soups(mesh: Mesh) -> Array:
	var out: Array = []
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var soup := PackedVector3Array()
		if ix.is_empty():
			soup = vs
		else:
			for i in ix:
				soup.append(vs[i])
		out.append(soup)
	return out


## A point strictly inside a hole polygon (its centroid when that is inside, else the first triangle's).
static func hole_point(hole: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in hole:
		c += p
	c /= maxf(1.0, hole.size())
	if Geometry2D.is_point_in_polygon(c, hole):
		return c
	var idx := Geometry2D.triangulate_polygon(hole)
	if idx.size() >= 3:
		return (hole[idx[0]] + hole[idx[1]] + hole[idx[2]]) / 3.0
	return c


## Whether a vertical ray through `plan_mm` passes the plate's mesh (GLB-root space soups) without a
## hit: a through hole. Returns {through: bool, hits: int}.
static func ray_through(soups: Array, plate: Dictionary, plan_mm: Vector2) -> Dictionary:
	var tm := mm_triangle_mesh(soups)
	if tm == null:
		return {"through": false, "hits": -1}
	var z0 := AirframeDocument.plate_z_mm(plate)
	var top := _w(plan_mm, z0 + AirframeDocument.plate_thickness_mm(plate) + 10.0) * 1000.0
	var hit: Dictionary = tm.intersect_ray(top, Vector3.DOWN)
	var hits := 0
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		hits = 1 if p.y >= z0 - 0.001 else 0
	return {"through": hits == 0, "hits": hits}


## A BVH of the soups (metres) built in MILLIMETRES: Godot's ray-triangle test rejects triangles under
## its float epsilon, so a millimetre-sized triangle in metres is unhittable (PickRegistry.TO_PICK).
static func mm_triangle_mesh(soups: Array) -> TriangleMesh:
	var faces := PackedVector3Array()
	for s in soups:
		for p in s as PackedVector3Array:
			faces.append(p * 1000.0)
	var tm := TriangleMesh.new()
	return tm if tm.create_from_faces(faces) else null


# --- hardware ----------------------------------------------------------------------------------

## The node name a hardware item is drawn as: the GLB's own name, so PickRegistry addresses agree.
static func hardware_node_name(item: Dictionary) -> String:
	return "frame_" + String(item.get("name", ""))


## One instance per document hardware item under a fresh Node3D named "frame_hardware_gen" (GLB-root
## space). Meshes are shared per (kind, size): instances, not copies. `mats` = {standoff, screw}.
static func hardware_node(document: AirframeDocument, mats: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "frame_hardware_gen"
	var cache := {}
	for raw in document.hardware:
		var item := raw as Dictionary
		var kind := String(item.get("kind", ""))
		var mesh: Mesh = null
		var key := ""
		var length := 0.0
		match kind:
			"standoff_hex", "standoff_round":
				length = float(item.get("length_mm", 0.0))
				var af := float(item.get("across_flats_mm", item.get("outer_d_mm", 5.0)))
				key = "%s|%f|%f" % [kind, af, length]
				if not cache.has(key):
					cache[key] = standoff_mesh(af, length, 6 if kind == "standoff_hex" else SCREW_SEGMENTS,
						mats.get("standoff"))
			"screw":
				var hd := float(item.get("head_d_mm", 5.4))
				var hh := float(item.get("head_h_mm", 1.8))
				var td := float(item.get("thread_d_mm", 3.0))
				key = "screw|%f|%f|%f" % [hd, hh, td]
				if not cache.has(key):
					cache[key] = screw_head_mesh(hd, hh, td, mats.get("screw"))
			_:
				continue
		mesh = cache[key]
		var mi := MeshInstance3D.new()
		mi.name = hardware_node_name(item)
		mi.mesh = mesh
		mi.transform = hardware_xform(item)
		holder.add_child(mi)
	return holder


## Where an item's mesh sits: origin at the standoff's lower end / the screw head's seat, +Y along its
## axis (document z -> Godot Y; axis [0,0,-1] flips the head to face down).
static func hardware_xform(item: Dictionary) -> Transform3D:
	var pos := AirframeDocument.point_of(item.get("position_mm", [0.0, 0.0]))
	var z := float(item.get("z_mm", 0.0))
	var axis: Array = item.get("axis", [0.0, 0.0, 1.0])
	var down := axis.size() == 3 and float(axis[2]) < 0.0
	if String(item.get("kind", "")).begins_with("standoff"):
		z -= 0.5 * float(item.get("length_mm", 0.0))
	var basis := Basis(Vector3.RIGHT, PI) if down else Basis.IDENTITY
	return Transform3D(basis, AirframeDocument.world_m(pos, z))


## A closed prism of `sides` (6 = hex, `size_mm` across flats) from y 0 to `length_mm`.
static func standoff_mesh(size_mm: float, length_mm: float, sides: int, mat: Material) -> ArrayMesh:
	var r := 0.5 * size_mm / 1000.0 / cos(PI / sides) if sides == 6 else 0.5 * size_mm / 1000.0
	var h := length_mm / 1000.0
	var out := {"verts": [], "normals": [], "uvs": []}
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var nm := ((p0 + p1) * 0.5).normalized()
		_tri(out, [p0, p1, p1 + Vector3(0, h, 0)], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], nm)
		_tri(out, [p0, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0)], [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], nm)
		_tri(out, [Vector3(0, h, 0), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)
		_tri(out, [Vector3.ZERO, p0, p1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.DOWN)
	return _commit(out, mat)


## A button head (flat seat, short cylinder, squashed dome) with a hex socket, seat at y 0, +Y up.
## Closed: the socket is a pit with walls and a floor.
static func screw_head_mesh(head_d_mm: float, head_h_mm: float, thread_d_mm: float, mat: Material) -> ArrayMesh:
	var R := 0.5 * head_d_mm / 1000.0
	var H := head_h_mm / 1000.0
	var cyl := H * 0.33
	var af := thread_d_mm * HEX_SOCKET_PER_THREAD / 1000.0
	var rs := 0.5 * af / cos(PI / 6.0)
	var depth := H * 0.55
	var n := SCREW_SEGMENTS
	# Profile rings (radius, height), seat outward then up and over the dome to the socket rim.
	var prof: Array = [[R, 0.0], [R, cyl]]
	for k in range(1, 5):
		var a := k / 5.0 * (PI * 0.5)
		var rr := lerpf(rs * 1.15, R, cos(a))
		prof.append([rr, cyl + (H - cyl) * sin(a)])
	prof.append([rs * 1.15, H])
	var out := {"verts": [], "normals": [], "uvs": []}
	var ring := func(r: float, y: float, i: int) -> Vector3:
		var a := TAU * i / n
		return Vector3(cos(a) * r, y, sin(a) * r)
	for i in n:
		# seat disc
		_tri(out, [Vector3.ZERO, ring.call(R, 0.0, i), ring.call(R, 0.0, i + 1)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.DOWN)
		for k in prof.size() - 1:
			var a0: Vector3 = ring.call(prof[k][0], prof[k][1], i)
			var a1: Vector3 = ring.call(prof[k][0], prof[k][1], i + 1)
			var b0: Vector3 = ring.call(prof[k + 1][0], prof[k + 1][1], i)
			var b1: Vector3 = ring.call(prof[k + 1][0], prof[k + 1][1], i + 1)
			var mid := (a0 + a1 + b0 + b1) * 0.25
			var nm := (Vector3(mid.x, 0, mid.z).normalized() * 0.6 + Vector3.UP * (0.0 if k == 0 else 0.8)).normalized()
			_tri(out, [a0, a1, b1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nm)
			_tri(out, [a0, b1, b0], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nm)
	# Annulus from the round socket rim (n points) to the hex (6 corners), then the pit.
	var hexp := func(c: int, y: float) -> Vector3:
		var a := TAU * (c % 6) / 6.0
		return Vector3(cos(a) * rs, y, sin(a) * rs)
	var per := int(n / 6.0)
	for i in n:
		var c := int(i / float(per))
		_tri(out, [ring.call(rs * 1.15, H, i), ring.call(rs * 1.15, H, i + 1), hexp.call(c, H)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)
		if (i + 1) % per == 0:
			_tri(out, [ring.call(rs * 1.15, H, i + 1), hexp.call(c + 1, H), hexp.call(c, H)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)
	for c in 6:
		var t0: Vector3 = hexp.call(c, H)
		var t1: Vector3 = hexp.call(c + 1, H)
		var d0: Vector3 = hexp.call(c, H - depth)
		var d1: Vector3 = hexp.call(c + 1, H - depth)
		var inward := -((t0 + t1) * 0.5 * Vector3(1, 0, 1)).normalized()
		_tri(out, [t0, t1, d1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], inward)
		_tri(out, [t0, d1, d0], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], inward)
		_tri(out, [Vector3(0, H - depth, 0), d0, d1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)
	return _commit(out, mat)


static func _commit(buffers: Dictionary, mat: Material) -> ArrayMesh:
	var out := _packed(buffers)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vs: PackedVector3Array = out["verts"]
	for i in vs.size():
		st.set_normal((out["normals"] as PackedVector3Array)[i])
		st.set_uv((out["uvs"] as PackedVector2Array)[i])
		st.add_vertex(vs[i])
	st.index()
	var mesh := st.commit()
	if mat != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)
	return mesh
