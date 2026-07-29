class_name MotorModel
extends RefCounted
## RPM response of a single motor. Pure and engine-independent (physics.md §3).
## max_RPM = KV * live pack voltage — the same motor spins much faster on 6S than 4S,
## which is most of why voltage choice feels dramatic to fly.

const SPIN_UP_TAU_S := 0.03   # first-order lag time constant; instant RPM makes it twitchy

var kv: float

func _init(p_kv: float) -> void:
	kv = p_kv

func max_rpm(voltage_v: float) -> float:
	return kv * voltage_v

## Advances current RPM one dt toward the throttle-commanded target, via first-order lag.
func step(current_rpm: float, throttle_cmd: float, voltage_v: float, dt: float) -> float:
	var target_rpm: float = clampf(throttle_cmd, 0.0, 1.0) * max_rpm(voltage_v)
	var alpha := 1.0 - exp(-dt / SPIN_UP_TAU_S)
	return current_rpm + (target_rpm - current_rpm) * alpha
