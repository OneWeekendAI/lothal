class_name RigidBodyState
extends RefCounted
## Owns the drone's rigid-body state and integrates it directly (physics.md §6) —
## NOT handed to Godot's rigid-body solver. Semi-implicit Euler, gyroscopic term
## included, quaternion renormalized every tick. Pure, engine-independent.

var position_m: Vector3 = Vector3.ZERO
var velocity_mps: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
var angular_velocity_rad_s: Vector3 = Vector3.ZERO

func integrate(force_n: Vector3, torque_n_m: Vector3, mass_kg: float, inertia: Basis, inertia_inverse: Basis, dt: float) -> void:
	var i_omega := inertia * angular_velocity_rad_s
	var gyroscopic := angular_velocity_rad_s.cross(i_omega)
	var angular_accel := inertia_inverse * (torque_n_m - gyroscopic)
	angular_velocity_rad_s += angular_accel * dt

	# angular_velocity_rad_s is expressed in the BODY frame — that is the frame the torque
	# and the inertia tensor are in — so the quaternion rate is q_dot = 0.5 * q (x) omega.
	# The world-frame form (omega (x) q) looks almost identical and agrees while the drone
	# is near level, which is why it survives a hover test; once rolled it rotates the body
	# about the wrong axis entirely.
	var omega_quat := Quaternion(angular_velocity_rad_s.x, angular_velocity_rad_s.y, angular_velocity_rad_s.z, 0.0)
	var orientation_delta := orientation * omega_quat
	orientation = Quaternion(
		orientation.x + orientation_delta.x * 0.5 * dt,
		orientation.y + orientation_delta.y * 0.5 * dt,
		orientation.z + orientation_delta.z * 0.5 * dt,
		orientation.w + orientation_delta.w * 0.5 * dt
	).normalized()

	var accel := force_n / mass_kg
	velocity_mps += accel * dt      # velocity updated first...
	position_m += velocity_mps * dt  # ...then position uses the NEW velocity (semi-implicit)


## Speed at which the body point `r_body_m` (from the centre of mass, body frame) is moving INTO a surface
## whose outward unit normal is `normal_world`. Positive = approaching, <= 0 = leaving or sliding.
func approach_speed(r_body_m: Vector3, normal_world: Vector3) -> float:
	return -_point_velocity(r_body_m).dot(normal_world)


func _point_velocity(r_body_m: Vector3) -> Vector3:
	return velocity_mps + orientation * angular_velocity_rad_s.cross(r_body_m)


## R1.1: one contact impulse at the body point `r_body_m`, against a surface with outward unit
## `normal_world`. A normal impulse with `restitution`, then a Coulomb friction impulse (capped at
## mu x the normal impulse, and at the impulse that would just stop the slide). Linear AND angular
## velocity change, so a prop-tip hit spins the aircraft. Returns the normal impulse (N s), 0 when the
## point is not approaching. Position is NOT touched: pushing out of penetration is the caller's.
func apply_contact_impulse(r_body_m: Vector3, normal_world: Vector3, restitution: float, friction: float,
		mass_kg: float, inertia_inverse: Basis) -> float:
	var vn := approach_speed(r_body_m, normal_world)
	if vn <= 0.0:
		return 0.0
	var n_b := orientation.inverse() * normal_world
	var rxn := r_body_m.cross(n_b)
	var k_n := 1.0 / mass_kg + (inertia_inverse * rxn).cross(r_body_m).dot(n_b)
	var j := (1.0 + restitution) * vn / k_n
	velocity_mps += normal_world * (j / mass_kg)
	angular_velocity_rad_s += inertia_inverse * r_body_m.cross(n_b * j)

	var v_p := _point_velocity(r_body_m)
	var slide := v_p - normal_world * v_p.dot(normal_world)
	var slide_speed := slide.length()
	if slide_speed > 1.0e-9 and friction > 0.0:
		var t_w := slide / slide_speed
		var t_b := orientation.inverse() * t_w
		var k_t := 1.0 / mass_kg + (inertia_inverse * r_body_m.cross(t_b)).cross(r_body_m).dot(t_b)
		var jt := minf(friction * j, slide_speed / k_t)
		velocity_mps -= t_w * (jt / mass_kg)
		angular_velocity_rad_s -= inertia_inverse * r_body_m.cross(t_b * jt)
	return j
