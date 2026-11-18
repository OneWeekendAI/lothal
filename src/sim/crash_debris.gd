class_name CrashDebris
extends Node3D
## R2.5b: what an R1.1 hit sheds. On a damage event whose kinetic energy (1/2 m v_impact^2, the
## aircraft's mass and the contact speed R1.1 measured) is at least ENERGY_THRESHOLD_J, fragments leave
## the aircraft at the impact point with the aircraft's velocity at impact plus a scatter, and tumble,
## bounce and settle on the terrain under gravity. Each is a small rigid body: mass, velocity, spin, and
## a ground contact with restitution and friction (CollisionConstants'). They despawn after LIFETIME_S.
##
## ESTIMATES (labelled; no crash-debris data exists for these builds):
##   ENERGY_THRESHOLD_J 1.5 J: a 5" build at ~2.2 m/s, just above R1.1's 2 m/s bounce speed where a
##     prop first loses thrust; below it a prop chips but sheds nothing visible.
##   J_PER_FRAGMENT 1.5 J: one fragment per threshold's worth of energy, so the count is linear in
##     energy; MAX_FRAGMENTS caps the draw cost.
##   SCATTER_MPS 1.5: the fragments' spread about the impact velocity (a broken blade is flung at a
##     fraction of tip speed, but most of that is spent in the hit itself).

const ENERGY_THRESHOLD_J := 1.5
const J_PER_FRAGMENT := 1.5
const MAX_FRAGMENTS := 12
const LIFETIME_S := 6.0
const SCATTER_MPS := 1.5
const GRAVITY := 9.81
const FRAGMENT_SIZE_M := Vector3(0.025, 0.003, 0.008)

## Active fragments: {node, v, w, age, rest}.
var fragments: Array[Dictionary] = []
## Sampled ground height at (x, z); null = flat at y 0.
var ground: Callable = Callable()
var _rng := RandomNumberGenerator.new()
var _mesh: BoxMesh
var _mat: StandardMaterial3D


func _init() -> void:
	_rng.seed = 7
	_mesh = BoxMesh.new()
	_mesh.size = FRAGMENT_SIZE_M
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.12, 0.12, 0.13)
	_mat.roughness = 0.6
	_mesh.material = _mat


## How many fragments an impact of `energy_j` sheds: none below the threshold, then linear in energy.
static func fragment_count(energy_j: float) -> int:
	if energy_j < ENERGY_THRESHOLD_J:
		return 0
	return clampi(int(floor(energy_j / J_PER_FRAGMENT)), 1, MAX_FRAGMENTS)


static func impact_energy_j(mass_kg: float, impact_speed_mps: float) -> float:
	return 0.5 * mass_kg * impact_speed_mps * impact_speed_mps


## Sheds the fragments for one damage event. Returns how many were spawned.
func shed(at: Vector3, velocity_mps: Vector3, energy_j: float) -> int:
	var n := fragment_count(energy_j)
	for i in n:
		var node := MeshInstance3D.new()
		node.mesh = _mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var scatter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1), _rng.randf_range(-1, 1)).normalized()
		node.position = at
		node.basis = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		add_child(node)
		fragments.append({"node": node, "v": velocity_mps + scatter * SCATTER_MPS * _rng.randf_range(0.4, 1.0),
			"w": Vector3(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40), _rng.randf_range(-40, 40)),
			"age": 0.0, "rest": false})
	return n


func _ground_at(p: Vector3) -> float:
	return float(ground.call(p.x, p.z)) if ground.is_valid() else 0.0


## One step: gravity, tumble, a terrain contact with restitution and friction, and despawn by age.
func step(dt: float) -> void:
	var i := fragments.size() - 1
	while i >= 0:
		var f: Dictionary = fragments[i]
		var node := f["node"] as MeshInstance3D
		f["age"] = float(f["age"]) + dt
		if float(f["age"]) >= LIFETIME_S:
			node.queue_free()
			remove_child(node)
			fragments.remove_at(i)
			i -= 1
			continue
		if not bool(f["rest"]):
			var v: Vector3 = f["v"]
			var w: Vector3 = f["w"]
			v.y -= GRAVITY * dt
			var p := node.position + v * dt
			var gy := _ground_at(p) + FRAGMENT_SIZE_M.y * 0.5
			if p.y <= gy:
				p.y = gy
				if v.y < 0.0:
					v.y = -v.y * CollisionConstants.RESTITUTION
				v.x *= (1.0 - CollisionConstants.FRICTION)
				v.z *= (1.0 - CollisionConstants.FRICTION)
				w *= 0.5
				if v.length() < 0.15:
					f["rest"] = true
					v = Vector3.ZERO
					w = Vector3.ZERO
			node.position = p
			if w.length_squared() > 0.0:
				node.basis = Basis(w.normalized(), w.length() * dt) * node.basis
			f["v"] = v
			f["w"] = w
		i -= 1


func clear() -> void:
	for f in fragments:
		(f["node"] as Node).queue_free()
	fragments.clear()


func _process(delta: float) -> void:
	step(delta)
