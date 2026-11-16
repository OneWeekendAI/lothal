class_name CollisionWorld
extends RefCounted
## R1.1: the solid things the aircraft can hit — the terrain, the obstacles and the gate rings — behind
## ONE query: `contact(point, radius)`. The same Terrain/Obstacle/gate data the scene draws, no second copy.

var terrain: Terrain = null
var obstacles: Array[Obstacle] = []
var gates: Array[Dictionary] = []

func _init(p_terrain: Terrain = null, p_obstacles: Array[Obstacle] = [], p_gates: Array[Dictionary] = []) -> void:
	terrain = p_terrain
	obstacles = p_obstacles
	gates = p_gates


## The deepest overlap of a sphere with the world, or {} when clear. {normal (out of the surface,
## unit), depth (m, > 0), surface ("ground" | "obstacle" | "gate")}.
func contact(centre: Vector3, radius: float) -> Dictionary:
	var best := {}
	var best_depth := 0.0

	var ground_y := terrain.height_at(centre.x, centre.z) if terrain != null else 0.0
	var ground_depth := ground_y + radius - centre.y
	if ground_depth > best_depth:
		best_depth = ground_depth
		best = {"normal": _ground_normal(centre), "depth": ground_depth, "surface": "ground"}

	for obstacle in obstacles:
		var d := obstacle._distance_to(centre)
		if d < radius:
			var depth := radius - d
			if d <= 1.0e-9:
				depth = radius + _inside_depth(obstacle, centre)
			if depth > best_depth:
				best_depth = depth
				best = {"normal": _obstacle_normal(obstacle, centre, d), "depth": depth, "surface": "obstacle"}

	for gate in gates:
		var gp: Vector3 = gate["position"]
		var gn: Vector3 = gate["normal"]
		# The ring is a torus: a tube of GATE_TUBE_RADIUS_M around the circle just outside the aperture.
		var ring_r: float = float(gate["radius"]) + CollisionConstants.GATE_TUBE_RADIUS_M
		var rel := centre - gp
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
