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

	var omega_quat := Quaternion(angular_velocity_rad_s.x, angular_velocity_rad_s.y, angular_velocity_rad_s.z, 0.0)
	var orientation_delta := omega_quat * orientation
	orientation = Quaternion(
		orientation.x + orientation_delta.x * 0.5 * dt,
		orientation.y + orientation_delta.y * 0.5 * dt,
		orientation.z + orientation_delta.z * 0.5 * dt,
		orientation.w + orientation_delta.w * 0.5 * dt
	).normalized()

	var accel := force_n / mass_kg
	velocity_mps += accel * dt      # velocity updated first...
	position_m += velocity_mps * dt  # ...then position uses the NEW velocity (semi-implicit)
