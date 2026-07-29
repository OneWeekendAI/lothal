class_name MotorModel
extends RefCounted
## RPM response of a single motor. Pure and engine-independent (physics.md §3).
## max_RPM = KV * live pack voltage — the same motor spins much faster on 6S than 4S,
## which is most of why voltage choice feels dramatic to fly.

const SPIN_UP_TAU_S := 0.03   # first-order lag time constant; instant RPM makes it twitchy

var kv: float

## Fraction of the KV*voltage RPM ceiling this motor can actually reach with the prop
## fitted, before it hits its own current limit. 1.0 whenever the prop is at or below what
## the motor's amp rating was measured against.
##
## Without this a motor is a free lunch: bolt 7" props onto a 2207 and the D^4 thrust law
## alone reports a ~44:1 thrust-to-weight, because nothing in the model objects to spinning
## a much larger prop at the same RPM. Reality objects through current — torque, and so
## amps, climbs as D^5, and the ESC and motor cap out. parts.md wants that combination
## allowed and wants it to teach "it barely lifts"; this is the term that teaches it.
var max_throttle: float = 1.0

func _init(p_kv: float, p_max_throttle: float = 1.0) -> void:
	kv = p_kv
	max_throttle = clampf(p_max_throttle, 0.0, 1.0)

func max_rpm(voltage_v: float) -> float:
	return kv * voltage_v

## Advances current RPM one dt toward the throttle-commanded target, via first-order lag.
func step(current_rpm: float, throttle_cmd: float, voltage_v: float, dt: float) -> float:
	var target_rpm: float = clampf(throttle_cmd, 0.0, max_throttle) * max_rpm(voltage_v)
	var alpha := 1.0 - exp(-dt / SPIN_UP_TAU_S)
	return current_rpm + (target_rpm - current_rpm) * alpha
