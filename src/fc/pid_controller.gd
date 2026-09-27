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
## The actuator's range. The controller clamps its own output to +/-this rather than
## leaving the caller to do it, because the anti-windup below has to SEE the saturation —
## a clamp applied outside would hide it.
var output_limit: float

var _integral: float = 0.0
var _last_measured: float = 0.0
var _has_last: bool = false

func _init(p_kp: float, p_ki: float, p_kd: float, p_integral_limit: float = 1.0,
		p_output_limit: float = 1.0) -> void:
	kp = p_kp
	ki = p_ki
	kd = p_kd
	integral_limit = p_integral_limit
	output_limit = p_output_limit

func update(target: float, measured: float, dt: float) -> float:
	# Conditional-integration anti-windup and derivative-on-measurement live in the native core
	# (FlightLaw.pid_step); the reasoning above still describes exactly what it does.
	var r := FlightLaw.pid_step(kp, ki, kd, integral_limit, output_limit,
		_integral, _last_measured, _has_last, target, measured, dt)
	_integral = r[1]
	_last_measured = r[2]
	_has_last = true
	return r[0]

func reset() -> void:
	_integral = 0.0
	_has_last = false
