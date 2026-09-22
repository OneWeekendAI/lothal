class_name TerrainMesh
extends RefCounted
## The mesh and collider drawn FROM `Terrain` — one description, read once. F3 built `height_at`;
## F4 made it the ground authority for crashes and below-ground warnings; this file is the last
## place either of those could quietly diverge from what a pilot SEES.
##
## ---------------------------------------------------------------------------
## ONE FORMULA, TWO CONSUMERS
## ---------------------------------------------------------------------------
##
## `vertices()` calls `Terrain.height_at(x, z)` for every sample — it does not carry a second copy
## of the slope/bowl/bank arithmetic. A mesh built from its own expression would let a hill exist
## on screen that the physics does not have, and nothing would look wrong until someone flew into
## the gap between the two.
##
## `build_mesh()` and `build_collider()` both read the SAME triangle list (`_all_triangles`), so
## what the pilot sees and what the aircraft can hit are, by construction, one list of points read
## twice rather than two lists that happen to agree today.
##
## ---------------------------------------------------------------------------
## THE FLOOR AND THE WALLS ARE DIFFERENT THINGS
## ---------------------------------------------------------------------------
##
## `Terrain.height_at` returns 0.0 everywhere for an enclosure — its walls, roof and pillars are
## NOT a height field, they are geometry that belongs here. `vertices()` returns only the floor
## grid (the thing check 1 holds to `height_at`); walls, pillars and the roof are appended
## afterward, in `build_mesh`/`build_collider`, and are deliberately excluded from what
## `vertices()` returns.
##
## ---------------------------------------------------------------------------
## WORLD SPACE, NOT LOCAL
## ---------------------------------------------------------------------------
##
## A site's origin is not (0,0) — `center_x_m`/`center_z_m` shift it. Every vertex this file
## produces is already in world coordinates (so it can be compared against `height_at`, which also
## takes world coordinates), and the node this mesh is attached to keeps an identity transform.

## Sampling step in metres. A chosen number — fine enough that a slope or a bowl reads as curved
## rather than faceted, coarse enough that a 120 m field is a few thousand triangles rather than a
## few hundred thousand.
const GRID_STEP_M := 2.0

## Enclosure wall thickness, in metres. A labelled guess: nothing measures a wall, and the design
## only says a wall exists and how tall it is (`wall_height_m`). Thin enough to read as a wall
## rather than a room.
const WALL_THICKNESS_M := 0.2

## Enclosure pillar cross-section, in metres. Same status as the wall thickness above.
const PILLAR_SIZE_M := 0.3


## Every floor vertex, in world space, `y` read straight from `height_at`. Row-major: `length_m`'s
## axis (z) is the outer loop, `width_m`'s axis (x) the inner one. An enclosure's floor is flat
## at zero, same as everywhere else `height_at` says so — its walls are not here.
static func vertices(p_terrain: Terrain) -> PackedVector3Array:
	var terrain := _terrain_or_default(p_terrain)
	var dims := _grid_dims(terrain)
	var n_x: int = dims.x
	var n_z: int = dims.y
	var half := terrain.half_extent()
	var out := PackedVector3Array()
	out.resize((n_x + 1) * (n_z + 1))
	var i := 0
	for row in range(n_z + 1):
		var z := _lerp_index(row, n_z, terrain.center_z_m - half.y, terrain.center_z_m + half.y)
		for col in range(n_x + 1):
			var x := _lerp_index(col, n_x, terrain.center_x_m - half.x, terrain.center_x_m + half.x)
			out[i] = Vector3(x, terrain.height_at(x, z), z)
			i += 1
	return out


## The drawn ground: the floor grid, plus an enclosure's walls, pillars and roof when the shape
## calls for them, plus whatever `p_obstacles` (F6) stands on it. Defaulted to empty so every
## caller from before F6 — and F5's own suite, which pins its calls by exact text — keeps reading
## `TerrainMesh.build_mesh(terrain)` unchanged.
static func build_mesh(p_terrain: Terrain, p_obstacles: Array[Obstacle] = []) -> ArrayMesh:
	var triangles := _all_triangles(p_terrain, p_obstacles)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in triangles:
		tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()


## The collider for the same ground: the SAME triangle list `build_mesh` drew, obstacles included,
## so what the aircraft can hit and what the pilot sees are one list of points, not two.
static func build_collider(p_terrain: Terrain, p_obstacles: Array[Obstacle] = []) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_all_triangles(p_terrain, p_obstacles))
	return shape


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## `null` reads as flat at zero everywhere else in this plan (main.gd's `_course_terrain`); this
## file follows the same rule rather than crashing on the one path that never assigns a terrain.
static func _terrain_or_default(p_terrain: Terrain) -> Terrain:
	if p_terrain != null:
		return p_terrain
	return Terrain.flat(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)


## Grid cell counts along x and y (length, confusingly stored as `.y` in a Vector2i since there is
## no Vector2i.z). At least one cell either way, so a degenerate 0 m site still has one quad.
static func _grid_dims(p_terrain: Terrain) -> Vector2i:
	var half := p_terrain.half_extent()
	var n_x := maxi(1, roundi((half.x * 2.0) / GRID_STEP_M))
	var n_z := maxi(1, roundi((half.y * 2.0) / GRID_STEP_M))
	return Vector2i(n_x, n_z)


## The point `index` of `count` cells between `lo` and `hi` — `index == 0` lands exactly on `lo`
## and `index == count` lands exactly on `hi`, regardless of whether `GRID_STEP_M` divides the
## span evenly. That is what pins the mesh's bounding box to the site's own extent rather than to
## a rounded multiple of the sampling step.
static func _lerp_index(index: int, count: int, lo: float, hi: float) -> float:
	if count <= 0:
		return lo
	return lerpf(lo, hi, float(index) / float(count))


## The floor grid, wound so every triangle's normal has `y > 0` (Godot's front faces are
## clockwise, seen from the front — this repo has already paid for getting this backwards once).
static func _floor_triangles(p_terrain: Terrain) -> PackedVector3Array:
	var terrain := _terrain_or_default(p_terrain)
	var dims := _grid_dims(terrain)
	var n_x: int = dims.x
	var n_z: int = dims.y
	var grid := vertices(terrain)
	var out := PackedVector3Array()
	var cols := n_x + 1

	for row in range(n_z):
		for col in range(n_x):
			var a := grid[row * cols + col]              # (x0, z0)
			var b := grid[row * cols + col + 1]           # (x1, z0)
			var c := grid[(row + 1) * cols + col]         # (x0, z1)
			var d := grid[(row + 1) * cols + col + 1]     # (x1, z1)
			# a, c, b and c, d, b — see the header on the module for the cross-product check that
			# pins this order to a +y normal.
			out.append(a); out.append(c); out.append(b)
			out.append(c); out.append(d); out.append(b)
	return out


## Walls, pillars and roof for an enclosure; empty for every other shape.
static func _wall_and_pillar_triangles(p_terrain: Terrain) -> PackedVector3Array:
	var terrain := _terrain_or_default(p_terrain)
	var out := PackedVector3Array()
	if terrain.shape != Terrain.ENCLOSURE:
		return out

	var half := terrain.half_extent()
	var cx := terrain.center_x_m
	var cz := terrain.center_z_m
	var wall_height: float = _terrain_num(terrain, "wall_height_m")
	var roofed: Variant = terrain.dims.get("roofed", Terrain.DIM_DEFAULTS[Terrain.ENCLOSURE]["roofed"])
	var pillar_spacing: float = _terrain_num(terrain, "pillar_spacing_m")

	# Four boundary walls, each a thin vertical box from the floor (y=0) to `wall_height`.
	var north_z := cz - half.y
	var south_z := cz + half.y
	var west_x := cx - half.x
	var east_x := cx + half.x
	out.append_array(_wall_box(
		Vector3(cx - half.x, 0.0, north_z), Vector3(cx + half.x, wall_height, north_z + WALL_THICKNESS_M)))
	out.append_array(_wall_box(
		Vector3(cx - half.x, 0.0, south_z - WALL_THICKNESS_M), Vector3(cx + half.x, wall_height, south_z)))
	out.append_array(_wall_box(
		Vector3(west_x, 0.0, cz - half.y), Vector3(west_x + WALL_THICKNESS_M, wall_height, cz + half.y)))
	out.append_array(_wall_box(
		Vector3(east_x - WALL_THICKNESS_M, 0.0, cz - half.y), Vector3(east_x, wall_height, cz + half.y)))

	# Pillars along the perimeter, spaced `pillar_spacing_m` apart, starting from each corner.
	if pillar_spacing > 0.0:
		out.append_array(_perimeter_pillars(cx, cz, half, wall_height, pillar_spacing))

	# The roof, one flat quad at `wall_height`, wound the same way the floor is (+y normal, so it
	# is a ceiling seen from below and a roof seen from above).
	if roofed:
		var p0 := Vector3(cx - half.x, wall_height, cz - half.y)
		var p1 := Vector3(cx + half.x, wall_height, cz - half.y)
		var p2 := Vector3(cx - half.x, wall_height, cz + half.y)
		var p3 := Vector3(cx + half.x, wall_height, cz + half.y)
		out.append(p0); out.append(p2); out.append(p1)
		out.append(p2); out.append(p3); out.append(p1)

	return out


## An axis-aligned box's 12 triangles, from `lo` to `hi`, each face wound outward.
static func _wall_box(lo: Vector3, hi: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var corners := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z),
	]
	# Index pairs per face: (a, c, b) and (c, d, b), matching the floor's winding rule, applied to
	# each of the box's six faces in turn.
	var faces := [
		[0, 1, 2, 3],  # -z face
		[5, 4, 7, 6],  # +z face
		[4, 0, 6, 2],  # -x face
		[1, 5, 3, 7],  # +x face
		[4, 5, 0, 1],  # -y face
		[2, 3, 6, 7],  # +y face
	]
	for face in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		out.append(a); out.append(c); out.append(b)
		out.append(c); out.append(d); out.append(b)
	return out


## Square pillars, `PILLAR_SIZE_M` on a side, along all four walls, spaced `spacing_m` apart
## starting from each wall's low-coordinate corner.
static func _perimeter_pillars(cx: float, cz: float, half: Vector2, wall_height: float,
		spacing_m: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var half_size := PILLAR_SIZE_M * 0.5

	# North and south walls: pillars step along x.
	var steps_x := maxi(1, floori((half.x * 2.0) / spacing_m))
	for i in range(steps_x + 1):
		var x := lerpf(cx - half.x, cx + half.x, float(i) / float(steps_x))
		out.append_array(_wall_box(
			Vector3(x - half_size, 0.0, cz - half.y - half_size),
			Vector3(x + half_size, wall_height, cz - half.y + half_size)))
		out.append_array(_wall_box(
			Vector3(x - half_size, 0.0, cz + half.y - half_size),
			Vector3(x + half_size, wall_height, cz + half.y + half_size)))

	# East and west walls: pillars step along z.
	var steps_z := maxi(1, floori((half.y * 2.0) / spacing_m))
	for i in range(steps_z + 1):
		var z := lerpf(cz - half.y, cz + half.y, float(i) / float(steps_z))
		out.append_array(_wall_box(
			Vector3(cx - half.x - half_size, 0.0, z - half_size),
			Vector3(cx - half.x + half_size, wall_height, z + half_size)))
		out.append_array(_wall_box(
			Vector3(cx + half.x - half_size, 0.0, z - half_size),
			Vector3(cx + half.x + half_size, wall_height, z + half_size)))

	return out


static func _terrain_num(p_terrain: Terrain, key: String) -> float:
	var value: Variant = p_terrain.dims.get(key)
	if value is float or value is int:
		return float(value)
	var fallback: Variant = Terrain.DIM_DEFAULTS.get(p_terrain.shape, {}).get(key, 0.0)
	return float(fallback) if fallback is float or fallback is int else 0.0


## The complete drawn/collidable triangle list: floor, then walls/pillars/roof for an enclosure,
## then every obstacle standing on it (F6) — one list, so what is drawn and what is collidable
## never have to be kept in sync by hand.
static func _all_triangles(p_terrain: Terrain, p_obstacles: Array[Obstacle] = []) -> PackedVector3Array:
	var out := _floor_triangles(p_terrain)
	out.append_array(_wall_and_pillar_triangles(p_terrain))
	for obstacle in p_obstacles:
		out.append_array(obstacle.triangles())
	return out
