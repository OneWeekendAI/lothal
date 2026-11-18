class_name CollisionWorld
extends RefCounted
## R1.1: the solid things the aircraft can hit — the terrain, the obstacles and the gate rings — behind
## ONE query: `contact(point, radius)`. The same Terrain/Obstacle/gate data the scene draws, no second copy.

var terrain: Terrain = null
var obstacles: Array[Obstacle] = []
var gates: Array[Dictionary] = []
## B4/Q1 broad phase: each obstacle's AABB, cached once. A point outside an obstacle's box grown by the contact radius
## is farther than that radius from the obstacle (the box contains it), so skipping it changes no contact.
var _boxes: Array[AABB] = []
## The gates unpacked once from their dictionaries (ring = aperture radius + GATE_TUBE_RADIUS_M).
var _gate_pos := PackedVector3Array()
var _gate_n := PackedVector3Array()
var _gate_ring := PackedFloat64Array()
## Per-point narrow queries answered so far (tests/test_sim_perf.gd counts that the broad phase skips them in clear air).
var point_queries := 0
## Slack on both broad-phase rejections so float rounding can never skip a real contact.
const BROAD_MARGIN_M := 1.0e-3

func _init(p_terrain: Terrain = null, p_obstacles: Array[Obstacle] = [], p_gates: Array[Dictionary] = []) -> void:
	terrain = p_terrain
	obstacles = p_obstacles
	gates = p_gates


func _cache_gates() -> void:
	_gate_pos.clear()
	_gate_n.clear()
	_gate_ring.clear()
	for gate in gates:
		_gate_pos.append(gate["position"])
		_gate_n.append(gate["normal"])
		_gate_ring.append(float(gate["radius"]) + CollisionConstants.GATE_TUBE_RADIUS_M)


## B4/Q1 whole-aircraft broad phase: true when NO sphere lying inside the sphere (`centre`, `bound_r`) can touch anything,
## so the per-point queries can be skipped with no change in result. Conservative: ground is only cleared on flat-at-zero
## terrain (elsewhere this answers false and every point is queried as before).
func clear_of(centre: Vector3, bound_r: float) -> bool:
	if terrain != null and not terrain.is_flat_at_zero():
		return false
	if centre.y - bound_r <= BROAD_MARGIN_M:
		return false
	if _boxes.size() != obstacles.size():
		_boxes.clear()
		for o in obstacles:
			_boxes.append(o.aabb())
	for box in _boxes:
		if box.grow(bound_r + BROAD_MARGIN_M).has_point(centre):
			return false
	if _gate_pos.size() != gates.size():
		_cache_gates()
	var reach := bound_r + CollisionConstants.GATE_TUBE_RADIUS_M + BROAD_MARGIN_M
	for gi in _gate_pos.size():
		if (centre - _gate_pos[gi]).length() - _gate_ring[gi] < reach:
			return false
	return true


## The deepest overlap of a sphere with the world, or {} when clear. {normal (out of the surface,
## unit), depth (m, > 0), surface ("ground" | "obstacle" | "gate")}.
func contact(centre: Vector3, radius: float) -> Dictionary:
	point_queries += 1
	var best := {}
	var best_depth := 0.0

	var ground_y := terrain.height_at(centre.x, centre.z) if terrain != null else 0.0
	var ground_depth := ground_y + radius - centre.y
	if ground_depth > best_depth:
		best_depth = ground_depth
		best = {"normal": _ground_normal(centre), "depth": ground_depth, "surface": "ground"}

	if _boxes.size() != obstacles.size():
		_boxes.clear()
		for o in obstacles:
			_boxes.append(o.aabb())
	for oi in obstacles.size():
		var obstacle := obstacles[oi]
		if not _boxes[oi].grow(radius + BROAD_MARGIN_M).has_point(centre):
			continue
		var d := obstacle._distance_to(centre)
		if d < radius:
			var depth := radius - d
			if d <= 1.0e-9:
				depth = radius + _inside_depth(obstacle, centre)
			if depth > best_depth:
				best_depth = depth
				best = {"normal": _obstacle_normal(obstacle, centre, d), "depth": depth, "surface": "obstacle"}

	if _gate_pos.size() != gates.size():
		_cache_gates()
	for gi in _gate_pos.size():
		var gp: Vector3 = _gate_pos[gi]
		# The ring is a torus: a tube of GATE_TUBE_RADIUS_M around the circle just outside the aperture.
		var ring_r: float = _gate_ring[gi]
		var rel := centre - gp
		# Broad phase (exact): every point of the tube's centre circle is ring_r from gp, so dist >= |rel| - ring_r.
		if rel.length() - ring_r >= radius + CollisionConstants.GATE_TUBE_RADIUS_M + BROAD_MARGIN_M:
			continue
		var gn: Vector3 = _gate_n[gi]
		var axial := rel.dot(gn)
		var radial := rel - gn * axial
		var rad := radial.length()
		var radial_dir := radial / rad if rad > 1.0e-9 else Vector3.RIGHT
		var to_tube := radial_dir * (rad - ring_r) + gn * axial
		var dist := to_tube.length()
		var reach := radius + CollisionConstants.GATE_TUBE_RADIUS_M
		if dist < reach:
			var depth := reach - dist
			if depth > best_depth:
				best_depth = depth
				best = {"normal": to_tube / dist if dist > 1.0e-9 else Vector3.UP, "depth": depth, "surface": "gate"}
	return best


func _ground_normal(at: Vector3) -> Vector3:
	if terrain == null:
		return Vector3.UP
	var h := 0.1
	var dx := terrain.height_at(at.x + h, at.z) - terrain.height_at(at.x - h, at.z)
	var dz := terrain.height_at(at.x, at.z + h) - terrain.height_at(at.x, at.z - h)
	return Vector3(-dx, 2.0 * h, -dz).normalized()


## Outward normal: the gradient of the distance field when outside; the shortest way out of the
## bounding box when the centre is already inside.
func _obstacle_normal(obstacle: Obstacle, p: Vector3, d: float) -> Vector3:
	if d > 1.0e-6:
		var e := 1.0e-3
		var g := Vector3(
			obstacle._distance_to(p + Vector3(e, 0, 0)) - obstacle._distance_to(p - Vector3(e, 0, 0)),
			obstacle._distance_to(p + Vector3(0, e, 0)) - obstacle._distance_to(p - Vector3(0, e, 0)),
			obstacle._distance_to(p + Vector3(0, 0, e)) - obstacle._distance_to(p - Vector3(0, 0, e)))
		if g.length() > 1.0e-9:
			return g.normalized()
	var box := obstacle.aabb()
	var best := Vector3.UP
	var best_gap := box.end.y - p.y
	var sides := [
		[p.x - box.position.x, Vector3.LEFT], [box.end.x - p.x, Vector3.RIGHT],
		[p.z - box.position.z, Vector3.FORWARD], [box.end.z - p.z, Vector3.BACK]]
	for s in sides:
		if float(s[0]) < best_gap:
			best_gap = float(s[0])
			best = s[1]
	return best


func _inside_depth(obstacle: Obstacle, p: Vector3) -> float:
	var box := obstacle.aabb()
	return maxf(0.0, minf(box.end.y - p.y, minf(minf(p.x - box.position.x, box.end.x - p.x), minf(p.z - box.position.z, box.end.z - p.z))))
