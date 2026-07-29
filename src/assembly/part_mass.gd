class_name PartMass
extends RefCounted
## A single mass-contributing part instance: its mass, its position relative to the
## frame's geometric origin, and its own local (body-axis-aligned) inertia tensor.
## SI units throughout (kg, m).

var mass_kg: float
var position_m: Vector3
var local_inertia_diag: Vector3

func _init(p_mass_kg: float, p_position_m: Vector3, p_local_inertia_diag: Vector3) -> void:
	mass_kg = p_mass_kg
	position_m = p_position_m
	local_inertia_diag = p_local_inertia_diag
