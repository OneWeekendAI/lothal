class_name InertiaPrimitives
extends RefCounted
## Local (body-axis-aligned) inertia tensors for simple primitive shapes.
## All inputs/outputs are SI (kg, m). Returned as a diagonal Vector3 (Ixx, Iyy, Izz)
## since no primitive used in the reference build is rotated relative to the body frame.

static func box(mass_kg: float, size_m: Vector3) -> Vector3:
	var sx := size_m.x
	var sy := size_m.y
	var sz := size_m.z
	return Vector3(
		(mass_kg / 12.0) * (sy * sy + sz * sz),
		(mass_kg / 12.0) * (sx * sx + sz * sz),
		(mass_kg / 12.0) * (sx * sx + sy * sy)
	)


## Solid cylinder with its spin axis along body +Y (motor/prop mount orientation).
static func cylinder_y_axis(mass_kg: float, radius_m: float, height_m: float) -> Vector3:
	var i_axial := 0.5 * mass_kg * radius_m * radius_m
	var i_radial := (mass_kg / 12.0) * (3.0 * radius_m * radius_m + height_m * height_m)
	return Vector3(i_radial, i_axial, i_radial)
