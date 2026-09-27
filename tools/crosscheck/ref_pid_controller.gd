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
	var error := target - measured

	var derivative := 0.0
	if _has_last and dt > 0.0:
		derivative = -(measured - _last_measured) / dt
	_last_measured = measured
	_has_last = true

	# CONDITIONAL INTEGRATION, the anti-windup this controller went without.
	#
	# The old code clamped the integral to +/-1.0 and did nothing when the OUTPUT saturated.
	# Those are different failures. While the actuator is pinned, more integral buys no more
	# control — the motors are already at the limit — but the integrator carries on
	# accumulating anyway, and every bit of it has to be unwound before the output can come
	# off the stop. On yaw, whose authority is an eighth of roll's, that is seconds of the
	# aircraft ignoring the sticks: exactly the "I can't get it back" the pilot described.
	#
	# So the integrator is advanced speculatively and the step is taken back if it would
	# push an already-saturated output further into the stop. Error that would bring the
	# output back INTO range still integrates, which is what keeps this from being a
	# disable-I-when-saturated hack that cannot recover.
	var candidate := clampf(_integral + error * dt, -integral_limit, integral_limit)
	var output := kp * error + ki * candidate + kd * derivative
	if absf(output) > output_limit and signf(error) == signf(output):
		output = kp * error + ki * _integral + kd * derivative
	else:
		_integral = candidate

	return clampf(output, -output_limit, output_limit)

func reset() -> void:
	_integral = 0.0
	_has_last = false
