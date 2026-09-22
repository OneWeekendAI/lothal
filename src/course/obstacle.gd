class_name Obstacle
extends RefCounted
## Something standing in the field: a box, a pole, or a wall, placed on the terrain rather than
## floating over it.
##
## ---------------------------------------------------------------------------
## THE BASE COMES FROM `height_at`, NOT FROM A SECOND FORMULA
## ---------------------------------------------------------------------------
##
## `terrain_mesh.gd`'s whole point is one height formula feeding both the mesh and the collider —
## `vertices()` calls `Terrain.height_at`, and nothing else computes a ground height. An obstacle
## that invented its own "where is the ground here" would be exactly the drift that file exists to
## rule out: a pole planted at y = 0 on a 10 m hill reads as buried to anyone standing at the top of
## it. So `place()` — the one constructor obstacles are actually built through — asks the terrain
## the same question the mesh asks, and an obstacle built without a terrain (a bare `Obstacle.new()`,
## or `place()` given `null`) reads flat at zero, the same "no terrain means flat" rule every other
## file in this room uses.
##
## ---------------------------------------------------------------------------
## WHAT IS AUTHORED, AND WHAT IS DERIVED
## ---------------------------------------------------------------------------
##
## `kind`, `x`/`z` and `dims` are what a builder typed; `position.y` is never one of them. Two
## fields would let a builder's x/z drift out of step with a `y` nobody re-derived the moment the
## terrain under it changed shape — so only x/z and dims round-trip through `to_data()`, and `y` is
## recomputed from the terrain every time an obstacle is placed, the same way `height_at` itself is
## asked fresh per call rather than cached.

const BOX := &"box"
const POLE := &"pole"
const WALL := &"wall"
const KINDS := [BOX, POLE, WALL]

## What this is. One of BOX / POLE / WALL; nothing else is recognised (see `from_data`).
var kind: StringName = BOX
## x/z placed by the builder; y is the terrain height at that point, set once at `place()` time.
var position := Vector3.ZERO
## box: w/h/d/yaw_deg (w along local x before rotation, d along local z, h vertical, from the
##   base up).
## pole: radius/height, vertical cylinder from the base up.
## wall: length/height/thickness/yaw_deg — a box in all but name, length along local x, thickness
##   along local z.
var dims: Dictionary = {}

## How finely a leg or a ring's tube is sampled against an obstacle's solid, in metres. Small
## enough to catch the thinnest authored dimension this room ships a default for
## (`TerrainMesh.WALL_THICKNESS_M` = 0.2 m) several times over, so a wall does not hide between two
## samples; not a proximity bubble — it never grows the obstacle's own geometry, only how often
## that geometry is asked whether a point is inside it.
const SAMPLE_STEP_M := 0.05


## The constructor obstacles are actually built through. `x`/`z` are where the builder placed it;
## `p_terrain` answers "how high is the ground there" the one way this room ever asks that question.
## `null` reads flat at zero, matching every other caller of `height_at` in this room.
static func place(p_kind: StringName, x: float, z: float, p_dims: Dictionary,
		p_terrain: Terrain = null) -> Obstacle:
	var out := Obstacle.new()
	out.kind = p_kind
	var y := p_terrain.height_at(x, z) if p_terrain != null else 0.0
	out.position = Vector3(x, y, z)
	out.dims = p_dims.duplicate(true)
	return out


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## The obstacle's own axis-aligned bounding box in world space — the rotated footprint's extremes,
## not a pre-rotation shortcut, so a yawed box or wall still reports the box it actually occupies.
func aabb() -> AABB:
	match kind:
		POLE:
			var radius := _num("radius")
			var height := _num("height")
			return AABB(Vector3(position.x - radius, position.y, position.z - radius),
				Vector3(radius * 2.0, height, radius * 2.0))
		WALL:
			return _box_like_aabb(_num("length") * 0.5, _num("thickness") * 0.5, _num("height"))
		_:
			return _box_like_aabb(_num("w") * 0.5, _num("d") * 0.5, _num("h"))


func _box_like_aabb(half_x: float, half_z: float, height: float) -> AABB:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for corner in [Vector2(-half_x, -half_z), Vector2(half_x, -half_z),
			Vector2(-half_x, half_z), Vector2(half_x, half_z)]:
		var world := _to_world_xz(corner)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_z = minf(min_z, world.y)
		max_z = maxf(max_z, world.y)
	return AABB(Vector3(min_x, position.y, min_z), Vector3(max_x - min_x, height, max_z - min_z))


## Whether a sphere of `radius` at `centre` touches this obstacle's solid — the geometric test
## every new warning is built from. `radius == 0.0` asks whether `centre` itself is inside.
func intersects_sphere(centre: Vector3, radius: float) -> bool:
	return _distance_to(centre) <= radius


## Whether the segment `a` -> `b` passes through this obstacle's solid, sampled finely enough that
## a thin wall cannot hide between two samples (see `SAMPLE_STEP_M`). The WHOLE segment is tested,
## not just its endpoints — a leg that clips a wall in the middle and lands clear at both ends must
## still be caught.
func intersects_segment(a: Vector3, b: Vector3) -> bool:
	var length := a.distance_to(b)
	if length < 1.0e-9:
		return intersects_sphere(a, 0.0)
	var steps := maxi(1, ceili(length / SAMPLE_STEP_M))
	for i in steps + 1:
		var t := float(i) / float(steps)
		if intersects_sphere(a.lerp(b, t), 0.0):
			return true
	return false


## The triangle soup for this obstacle, world space, wound the same way `terrain_mesh.gd`'s floor
## and walls are (front faces clockwise, seen from the front) so it drops straight into the same
## `_all_triangles()` list the floor and the enclosure geometry already share.
func triangles() -> PackedVector3Array:
	match kind:
		POLE:
			return _cylinder_triangles(_num("radius"), _num("height"))
		WALL:
			return _box_triangles(_num("length") * 0.5, _num("thickness") * 0.5, _num("height"))
		_:
			return _box_triangles(_num("w") * 0.5, _num("d") * 0.5, _num("h"))


# ---------------------------------------------------------------------------
# Distance to the solid — the one function every intersects_* call reduces to
# ---------------------------------------------------------------------------

func _distance_to(p: Vector3) -> float:
	match kind:
		POLE:
			return _pole_distance(p)
		WALL:
			return _box_like_distance(p, _num("length") * 0.5, _num("thickness") * 0.5, _num("height"))
		_:
			return _box_like_distance(p, _num("w") * 0.5, _num("d") * 0.5, _num("h"))


## Distance from `p` to the nearest point of a box standing from the base up to `height`, oriented
## by `yaw_deg`. Zero when `p` is already inside — the clamp does nothing to an interior point, so
## the distance to its own clamped position is zero, which is exactly what "the sphere at `p` with
## radius 0 intersects" needs.
func _box_like_distance(p: Vector3, half_x: float, half_z: float, height: float) -> float:
	var local := _to_local_xz(Vector2(p.x, p.z))
	var clamped_x := clampf(local.x, -half_x, half_x)
	var clamped_z := clampf(local.y, -half_z, half_z)
	var clamped_y := clampf(p.y - position.y, 0.0, height)
	var dx := local.x - clamped_x
	var dz := local.y - clamped_z
	var dy := (p.y - position.y) - clamped_y
	return sqrt(dx * dx + dz * dz + dy * dy)


func _pole_distance(p: Vector3) -> float:
	var radius := _num("radius")
	var height := _num("height")
	var horizontal := Vector2(p.x - position.x, p.z - position.z).length()
	var d_horizontal := maxf(0.0, horizontal - radius)
	var clamped_y := clampf(p.y - position.y, 0.0, height)
	var d_vertical := (p.y - position.y) - clamped_y
	return sqrt(d_horizontal * d_horizontal + d_vertical * d_vertical)


# ---------------------------------------------------------------------------
# Rotation
# ---------------------------------------------------------------------------

func _to_local_xz(world: Vector2) -> Vector2:
	var yaw := deg_to_rad(_num("yaw_deg"))
	var dx := world.x - position.x
	var dz := world.y - position.z
	var c := cos(-yaw)
	var s := sin(-yaw)
	return Vector2(dx * c - dz * s, dx * s + dz * c)


func _to_world_xz(local: Vector2) -> Vector2:
	var yaw := deg_to_rad(_num("yaw_deg"))
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(position.x + local.x * c - local.y * s, position.z + local.x * s + local.y * c)


# ---------------------------------------------------------------------------
# Triangles
# ---------------------------------------------------------------------------

## A box from the base up to `height`, rotated by `yaw_deg`, wound the same way
## `TerrainMesh._wall_box` winds an axis-aligned one: (a, c, b) then (c, d, b) per face, which is
## what pins every face's normal outward under Godot's clockwise-front-face rule.
func _box_triangles(half_x: float, half_z: float, height: float) -> PackedVector3Array:
	var c0 := _to_world_xz(Vector2(-half_x, -half_z))
	var c1 := _to_world_xz(Vector2(half_x, -half_z))
	var c2 := _to_world_xz(Vector2(-half_x, half_z))
	var c3 := _to_world_xz(Vector2(half_x, half_z))
	var y0 := position.y
	var y1 := position.y + height
	var corners := [
		Vector3(c0.x, y0, c0.y), Vector3(c1.x, y0, c1.y),
		Vector3(c0.x, y1, c0.y), Vector3(c1.x, y1, c1.y),
		Vector3(c2.x, y0, c2.y), Vector3(c3.x, y0, c3.y),
		Vector3(c2.x, y1, c2.y), Vector3(c3.x, y1, c3.y),
	]
	var faces := [
		[0, 1, 2, 3],  # -local-z face
		[5, 4, 7, 6],  # +local-z face
		[4, 0, 6, 2],  # -local-x face
		[1, 5, 3, 7],  # +local-x face
		[4, 5, 0, 1],  # base
		[2, 3, 6, 7],  # top
	]
	var out := PackedVector3Array()
	for face in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		out.append(a); out.append(c); out.append(b)
		out.append(c); out.append(d); out.append(b)
	return out


## A cylinder from the base up to `height`, `SIDES` flat faces — enough to read as round without
## being an obstacle-count multiplier on a course with several poles in it.
const SIDES := 12

func _cylinder_triangles(radius: float, height: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if radius <= 0.0 or height <= 0.0:
		return out
	var y0 := position.y
	var y1 := position.y + height
	var top_centre := Vector3(position.x, y1, position.z)
	var base_centre := Vector3(position.x, y0, position.z)
	for i in SIDES:
		var a0 := TAU * float(i) / float(SIDES)
		var a1 := TAU * float(i + 1) / float(SIDES)
		var p0 := Vector3(position.x + cos(a0) * radius, y0, position.z + sin(a0) * radius)
		var p1 := Vector3(position.x + cos(a1) * radius, y0, position.z + sin(a1) * radius)
		var p2 := Vector3(position.x + cos(a0) * radius, y1, position.z + sin(a0) * radius)
		var p3 := Vector3(position.x + cos(a1) * radius, y1, position.z + sin(a1) * radius)
		# Side quad, same (a, c, b)/(c, d, b) winding as every box face in this file.
		out.append(p0); out.append(p2); out.append(p1)
		out.append(p2); out.append(p3); out.append(p1)
		# Top cap fan, wound so its normal points up; base cap wound so its normal points down
		# (into the ground it is embedded in — never seen, but consistent rather than absent).
		out.append(top_centre); out.append(p3); out.append(p2)
		out.append(base_centre); out.append(p0); out.append(p1)
	return out


func _num(key: String) -> float:
	var value: Variant = dims.get(key)
	return float(value) if value is float or value is int else 0.0


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## An obstacle from a record, or `null` if its kind is not one this version recognises.
##
## DROPPED, NOT DEFAULTED. A box built in place of an unreadable kind would put standing structure
## in the field nobody authored — the builder types "spire" (a kind a later version might add), an
## older build cannot draw a spire, and defaulting it to a box hides a dimension-mismatched box
## where the builder placed something else, silently. Dropping it is the honest answer: nothing
## stands there as far as this version can tell.
static func from_data(data: Variant, p_terrain: Terrain = null) -> Obstacle:
	if not (data is Dictionary):
		return null
	var record: Dictionary = data
	var named := StringName(String(record.get("kind", "")))
	if not (named in KINDS):
		return null
	var x := _read_number(record, "x", 0.0)
	var z := _read_number(record, "z", 0.0)
	var raw_dims: Variant = record.get("dims", {})
	var dims_dict: Dictionary = (raw_dims as Dictionary).duplicate(true) if raw_dims is Dictionary else {}
	return place(named, x, z, dims_dict, p_terrain)


static func _read_number(record: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = record.get(key)
	return float(value) if value is float or value is int else fallback


## The record as plain JSON values. `y` is never written — see the header — so an obstacle
## round-trips on exactly what a builder authored: its kind, where it stands, and its dims.
func to_data() -> Dictionary:
	return {
		"kind": String(kind),
		"x": position.x,
		"z": position.z,
		"dims": dims.duplicate(true),
	}
