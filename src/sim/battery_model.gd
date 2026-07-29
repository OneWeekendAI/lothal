class_name BatteryModel
extends RefCounted
## Voltage sag and capacity drain (physics.md §5). ~Ten lines, and it's what makes
## battery choice feel real instead of cosmetic: punch throttle -> current spikes ->
## voltage drops -> RPM ceiling drops -> thrust drops.

var nominal_v: float
var internal_r_ohm: float
var capacity_mah: float
var used_mah: float = 0.0

func _init(p_nominal_v: float, p_internal_r_ohm: float, p_capacity_mah: float) -> void:
	nominal_v = p_nominal_v
	internal_r_ohm = p_internal_r_ohm
	capacity_mah = p_capacity_mah

func voltage_live(current_total_a: float) -> float:
	return nominal_v - current_total_a * internal_r_ohm

func drain(current_total_a: float, dt: float) -> void:
	used_mah += current_total_a * (dt / 3600.0) * 1000.0

func remaining_fraction() -> float:
	return clampf(1.0 - used_mah / capacity_mah, 0.0, 1.0)
