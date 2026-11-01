class_name FrameView
extends RefCounted
## The 3D side of a frame edit (PLAN Section 4.3): where a click on a plate lands in that plate's own
## plan millimetres, and the solid an EDITED plate is drawn as. Static, no Node: DesignSpace owns the
## nodes and calls these.
##
## ## One mapping, both ways
##
## The frame document's coordinates are the GLB scene's own space (tools/blender/build_drone.py,
## `frame_doc_write`), mapped by `AirframeDocument.world_m` (u -> X, v -> Z, z -> Y). `space_point`
## is world_m followed by where the GLB scene sits on the stage; `plan_point` is its exact inverse.
## Nothing else converts between the two, so a click and the hole it drills cannot disagree.
##
## ## A plate with holes, without a polygon-with-holes triangulator
##
## Godot's `triangulate_polygon` takes one simple polygon. A plate is an outline with holes inside
## it, so `solid_pieces` first cuts the outline in two along a line through the middle of each hole
## that lies wholly inside a piece (`intersect_polygons` with a half-plane box): the hole then
## straddles the cut and `clip_polygons` turns it into a notch in each half's boundary. Every piece
## that comes out is a simple polygon, and the union of the pieces is exactly the material. The rim
## is drawn from the TRUE boundary (the outline and every hole), never from the cut lines, so the
## seams are invisible: both halves' faces are coplanar.
##
## Only edited plates are drawn this way; an unedited one keeps the GLB's own mesh and its bevels.

## The carbon weave's texture repeat, read off the GLB's arm UVs: 62.5 tiles per metre (16 mm).
const UV_PER_MM := 0.0625
## A cut is only split if a piece wholly encloses it; this many rounds is far more than any plate
## needs (each round removes at least one enclosed hole) and stops a degenerate shape looping.
const MAX_SPLIT_ROUNDS := 64


## A stage point -> the plan point (mm) of the document plane it lies on. `doc_xf` is the GLB
## scene's transform on the stage.
static func plan_point(at: Vector3, doc_xf: Transform3D) -> Vector2:
	var p := doc_xf.affine_inverse() * at
	return Vector2(p.x, p.z) * 1000.0


## The height (document z, mm) of a stage point.
static func plan_z_mm(at: Vector3, doc_xf: Transform3D) -> float:
	return (doc_xf.affine_inverse() * at).y * 1000.0


## A plan point (mm) at document height `z_mm` -> the stage. The inverse of `plan_point`.
static func space_point(plan_mm: Vector2, z_mm: float, doc_xf: Transform3D) -> Vector3:
	return doc_xf * AirframeDocument.world_m(plan_mm, z_mm)


## Where a stage ray meets the plane at document height `z_mm`, in plan mm. `{}` when the ray runs
## parallel to it or points away. Returns {point: Vector2}.
static func ray_on_plane(origin: Vector3, dir: Vector3, z_mm: float, doc_xf: Transform3D) -> Dictionary:
	var inv := doc_xf.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	var y := z_mm / 1000.0
	if absf(d.y) < 1.0e-9:
		return {}
	var t := (y - o.y) / d.y
	if t <= 0.0:
		return {}
	var p := o + d * t
	return {"point": Vector2(p.x, p.z) * 1000.0}


static func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	return poly if PolygonProps.area(poly) >= 0.0 else _reversed(poly)


static func _reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.reverse()
	return out


static func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## The material of a plate as simple polygons (CCW, plan mm): `outline` minus every hole. See the
## header for the split-then-clip rule.
static func solid_pieces(outline: PackedVector2Array, holes: Array) -> Array:
	var pieces: Array = [_ccw(outline)]
	for raw in holes:
		var hole := _ccw(raw as PackedVector2Array)
		if hole.size() < 3:
			continue
		var next: Array = []
		var queue: Array = pieces.duplicate()
		var rounds := 0
		while not queue.is_empty():
			var piece: PackedVector2Array = queue.pop_back()
			var clipped := Geometry2D.clip_polygons(piece, hole)
			# An enclosed hole comes back as an outer boundary plus a hole of the opposite winding; the
			# largest polygon is always an outer one, so its winding says which are outers.
			var outer_cw := false
			var biggest := -1.0
			for c in clipped:
				var a := absf(PolygonProps.area(c))
				if a > biggest:
					biggest = a
					outer_cw = Geometry2D.is_polygon_clockwise(c)
			var encloses := false
			for c in clipped:
				if Geometry2D.is_polygon_clockwise(c) != outer_cw:
					encloses = true
			if encloses and rounds < MAX_SPLIT_ROUNDS:
				rounds += 1
				queue.append_array(_split(piece, _bbox(hole).get_center().x))
				continue
			for c in clipped:
				if Geometry2D.is_polygon_clockwise(c) == outer_cw:
					next.append(_ccw(c))
		pieces = next
	return pieces


## `piece` cut by the vertical line u = `x`: the parts left and right of it.
static func _split(piece: PackedVector2Array, x: float) -> Array:
	var r := _bbox(piece).grow(1.0)
	var left := PackedVector2Array([r.position, Vector2(x, r.position.y), Vector2(x, r.end.y),
		Vector2(r.position.x, r.end.y)])
	var right := PackedVector2Array([Vector2(x, r.position.y), Vector2(r.end.x, r.position.y), r.end,
		Vector2(x, r.end.y)])
	var out: Array = []
	for half in [left, right]:
		for p in Geometry2D.intersect_polygons(piece, half):
			if absf(PolygonProps.area(p)) > 1.0e-9:
				out.append(p)
	return out


## The plate as a solid: the material between z_mm and z_mm + thickness, with a rim round the
## outline and down every hole. Vertices are in the space `local_xf` maps the GLB scene into (the
## inverse of the mesh node's transform in the scene), so the mesh drops into the node it replaces.
## `top_uv_turn` turns the weave 90 degrees (the GLB's body plates run their weave along v).
static func plate_mesh(plate: Dictionary, local_xf: Transform3D, material: Material,
		top_uv_turn: bool = false) -> ArrayMesh:
	var outline := AirframeDocument.plate_outline(plate)
	var holes := AirframeDocument.plate_holes(plate)
	return extrude(outline, holes, AirframeDocument.plate_z_mm(plate),
		AirframeDocument.plate_thickness_mm(plate), local_xf, material, top_uv_turn)


## A pick proxy for one cut: its polygon as a closed prism through the plate.
static func cut_proxy_mesh(cut: PackedVector2Array, plate: Dictionary, local_xf: Transform3D) -> ArrayMesh:
	return extrude(cut, [], AirframeDocument.plate_z_mm(plate), AirframeDocument.plate_thickness_mm(plate),
		local_xf, null)


static func extrude(outline: PackedVector2Array, holes: Array, z_mm: float, t_mm: float,
		local_xf: Transform3D, material: Material, top_uv_turn: bool = false) -> ArrayMesh:
	if outline.size() < 3 or t_mm <= 0.0:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := z_mm
	var z1 := z_mm + t_mm
	for piece in solid_pieces(outline, holes):
		var poly: PackedVector2Array = piece
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			# A piece the ear-clipper rejects (a sliver at a cut): its convex parts instead.
			for part in Geometry2D.decompose_polygon_in_convex(poly):
				_cap(st, part, Geometry2D.triangulate_polygon(part), z0, z1, local_xf, top_uv_turn)
			continue
		_cap(st, poly, idx, z0, z1, local_xf, top_uv_turn)
	_rim(st, _ccw(outline), z0, z1, local_xf, false)
	for h in holes:
		var hole := h as PackedVector2Array
		if hole.size() >= 3:
			_rim(st, _ccw(hole), z0, z1, local_xf, true)
	st.generate_tangents()
	var mesh := st.commit()
	if material != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return mesh


static func _uv(p: Vector2, turn: bool) -> Vector2:
	return (Vector2(-p.y, p.x) if turn else p) * UV_PER_MM


static func _cap(st: SurfaceTool, poly: PackedVector2Array, idx: PackedInt32Array, z0: float, z1: float,
		local_xf: Transform3D, turn: bool) -> void:
	for t in int(idx.size() / 3.0):
		var a := poly[idx[t * 3]]
		var b := poly[idx[t * 3 + 1]]
		var c := poly[idx[t * 3 + 2]]
		_face(st, local_xf, [a, b, c].map(func(q): return AirframeDocument.world_m(q, z1)),
			[_uv(a, turn), _uv(b, turn), _uv(c, turn)], Vector3.UP)
		_face(st, local_xf, [a, b, c].map(func(q): return AirframeDocument.world_m(q, z0)),
			[_uv(a, turn), _uv(b, turn), _uv(c, turn)], Vector3.DOWN)


## One wall quad per boundary edge. `poly` is CCW in (u, v); the material is inside an outline and
## outside a hole, so a hole's wall faces into the hole.
static func _rim(st: SurfaceTool, poly: PackedVector2Array, z0: float, z1: float, local_xf: Transform3D,
		is_hole: bool) -> void:
	var s := 0.0
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var edge := p1 - p0
		var el := edge.length()
		if el <= 0.0:
			continue
		# (u, v) -> world (X, Z): a CCW polygon's outward edge normal is (e.y, -e.x) in plan, which
		# is world (e.y, 0, -e.x) for a positive signed area as PolygonProps measures it.
		var out := Vector3(edge.y, 0.0, -edge.x).normalized()
		if is_hole:
			out = -out
		var a := AirframeDocument.world_m(p0, z0)
		var b := AirframeDocument.world_m(p1, z0)
		var c := AirframeDocument.world_m(p1, z1)
		var d := AirframeDocument.world_m(p0, z1)
		var ua := Vector2(s, 0.0) * UV_PER_MM
		var ub := Vector2(s + el, 0.0) * UV_PER_MM
		var uc := Vector2(s + el, z1 - z0) * UV_PER_MM
		var ud := Vector2(s, z1 - z0) * UV_PER_MM
		_face(st, local_xf, [a, b, c], [ua, ub, uc], out)
		_face(st, local_xf, [a, c, d], [ua, uc, ud], out)
		s += el


## One triangle facing `normal` (Godot's front faces are clockwise: the PlateMesh rule, measured).
static func _face(st: SurfaceTool, local_xf: Transform3D, pts: Array, uvs: Array, normal: Vector3) -> void:
	var a: Vector3 = local_xf * (pts[0] as Vector3)
	var b: Vector3 = local_xf * (pts[1] as Vector3)
	var c: Vector3 = local_xf * (pts[2] as Vector3)
	var n := (local_xf.basis * normal).normalized()
	var order := [0, 1, 2] if (b - a).cross(c - a).dot(n) <= 0.0 else [0, 2, 1]
	var vs := [a, b, c]
	for k in order:
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(vs[k])
