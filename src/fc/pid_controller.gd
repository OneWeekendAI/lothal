class_name PIDController
extends RefCounted
## A single generic PID axis, reusable for roll/pitch/yaw rate loops (physics.md §7).
## Derivative acts on the MEASUREMENT, not the error — a step in the setpoint (exactly
## what the step-response harness commands) would otherwise cause an instantaneous
## "derivative kick" that has nothing to do with the plant's actual response.

var kp: float
var ki: float
var kd: float
var integral_limit: float

var _integral: float = 0.0
var _last_measured: float = 0.0
var _has_last: bool = false

func _init(p_kp: float, p_ki: float, p_kd: float, p_integral_limit: float = 1.0) -> void:
	kp = p_kp
	ki = p_ki
	kd = p_kd
	integral_limit = p_integral_limit

func update(target: float, measured: float, dt: float) -> float:
	var error := target - measured
	_integral = clampf(_integral + error * dt, -integral_limit, integral_limit)

	var derivative := 0.0
	if _has_last and dt > 0.0:
		derivative = -(measured - _last_measured) / dt
	_last_measured = measured
	_has_last = true

	return kp * error + ki * _integral + kd * derivative

func reset() -> void:
	_integral = 0.0
	_has_last = false
