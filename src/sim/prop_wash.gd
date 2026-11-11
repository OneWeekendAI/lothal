class_name PropWash
extends Node3D
## Dust and grass kicked up where the rotor downwash meets the ground. Visual only: it reads the
## published thrust and the aircraft's height above the terrain, and feeds nothing back.
##
## The one number it draws from is the momentum-theory induced velocity, v_i = sqrt(T / (2 rho A))
## (Leishman, Principles of Helicopter Aerodynamics, eq. 2.xx). The jet below a rotor loses speed
## with distance; we take v(h) = v_i * min(1, REACH_DIAMETERS * D / h), an ESTIMATE shaped like a
## free turbulent jet's inverse decay, and dust lifts when that speed passes LIFT_MPS (loose dry soil
## lifts at a few m/s of near-ground wind, also an estimate). Both estimates are named constants so a
## measurement can replace them.

const REACH_DIAMETERS := 1.5
## Dust only exists when the rotor is this close to the ground, in rotor diameters (ground effect is
## gone by about two diameters). Full strength inside FULL_WITHIN_DIAMETERS, fading to none at the limit.
const GROUND_LIMIT_DIAMETERS := 2.0
const FULL_WITHIN_DIAMETERS := 1.0
const LIFT_MPS := 2.0
const FULL_MPS := 8.0
const MAX_PARTICLES := 36
## The emitter sits this far above the terrain mesh, which the physics height only approximates: a puff
## spawned at the surface is sliced by it and reads as a flat-bottomed dome.
const LIFT_OFF_M := 0.16

var _particles: GPUParticles3D
var _material: ParticleProcessMaterial


## 0 (no dust) .. 1 (full), for a hover at `height_m` above the ground with `thrust_n` total across
## discs of `disc_area_m2` total, in air of density `rho`. Pure, so a test can ask it directly.
static func intensity(height_m: float, thrust_n: float, disc_area_m2: float, rho: float,
		rotor_diameter_m: float) -> float:
	if thrust_n <= 0.0 or disc_area_m2 <= 0.0 or rho <= 0.0:
		return 0.0
	var v_i := sqrt(thrust_n / (2.0 * rho * disc_area_m2))
	var h := maxf(height_m, 0.05)
	var v_ground := v_i * minf(1.0, REACH_DIAMETERS * rotor_diameter_m / h)
	var lift := clampf((v_ground - LIFT_MPS) / (FULL_MPS - LIFT_MPS), 0.0, 1.0)
	# The hard ground gate: a hover a metre up (many diameters) lifts nothing, whatever the thrust.
	var d := maxf(rotor_diameter_m, 0.001)
	var gate := clampf((GROUND_LIMIT_DIAMETERS * d - h) / ((GROUND_LIMIT_DIAMETERS - FULL_WITHIN_DIAMETERS) * d), 0.0, 1.0)
	return lift * gate


func _init() -> void:
	name = "PropWash"
	_material = ParticleProcessMaterial.new()
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_material.emission_ring_axis = Vector3.UP
	_material.emission_ring_height = 0.01
	_material.emission_ring_radius = 0.1
	_material.emission_ring_inner_radius = 0.05
	_material.direction = Vector3(0, 0.05, 0)
	_material.spread = 12.0
	_material.radial_velocity_min = 0.25
	_material.radial_velocity_max = 0.7
	_material.gravity = Vector3(0, 0.0, 0)
	_material.damping_min = 0.8
	_material.damping_max = 1.6
	_material.scale_min = 0.07
	_material.scale_max = 0.17
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	_material.scale_curve = grow_tex
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.2, Color(1, 1, 1, 0.1))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	_material.color_ramp = ramp_tex

	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64
	var g := Gradient.new()
	# A round puff that reaches ZERO alpha well inside the quad's edge, so no quad outline is ever drawn.
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.add_point(0.45, Color(1, 1, 1, 0.3))
	g.add_point(0.85, Color(1, 1, 1, 0.0))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	puff.gradient = g
	var quad_mat := StandardMaterial3D.new()
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.vertex_color_use_as_albedo = true
	quad_mat.albedo_texture = puff
	quad_mat.albedo_color = Color(0.5, 0.47, 0.4, 0.28)
	# Soft particles: fade as a quad nears the terrain it would otherwise slice through, which is what
	# drew the hard horizontal cut-offs. No depth write, so overlapping puffs blend rather than clip.
	quad_mat.proximity_fade_enabled = true
	quad_mat.proximity_fade_distance = 0.35
	quad_mat.disable_receive_shadows = true
	quad_mat.particles_anim_h_frames = 1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = quad_mat

	_particles = GPUParticles3D.new()
	_particles.amount = MAX_PARTICLES
	_particles.lifetime = 0.5
	_particles.local_coords = false
	_particles.emitting = false
	_particles.process_material = _material
	_particles.draw_pass_1 = quad
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 4, 12))
	add_child(_particles)


## Moves the emitter to the ground point under the aircraft and sets how much it gives off.
func update(ground_point: Vector3, strength: float, ring_radius_m: float) -> void:
	global_position = ground_point + Vector3(0, LIFT_OFF_M, 0)
	_material.emission_ring_radius = maxf(0.5 * ring_radius_m, 0.04)
	_material.emission_ring_inner_radius = 0.25 * _material.emission_ring_radius
	var on := strength > 0.04
	_particles.amount_ratio = clampf(strength, 0.1, 1.0)
	if _particles.emitting != on:
		_particles.emitting = on


func is_active() -> bool:
	return _particles.emitting
