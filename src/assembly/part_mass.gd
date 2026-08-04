class_name PartMass
extends RefCounted
## A single mass-contributing part instance: its mass, its position relative to the
## frame's geometric origin, and its own local (body-axis-aligned) inertia tensor.
## SI units throughout (kg, m).

var mass_kg: float
var position_m: Vector3
var local_inertia_diag: Vector3
## What this entry IS, in the builder's own words. Carried for the frame bench, which reports each
## part's share of roll inertia and cannot say "the pack dominates" while holding an unnamed list.
##
## Deliberately inert: nothing in MassProperties reads it, so a mislabelled part is a wrong caption
## and never a wrong number. Optional, so an entry authored before this existed still assembles.
var label: String

func _init(p_mass_kg: float, p_position_m: Vector3, p_local_inertia_diag: Vector3,
		p_label: String = "") -> void:
	mass_kg = p_mass_kg
	position_m = p_position_m
	local_inertia_diag = p_local_inertia_diag
	label = p_label
