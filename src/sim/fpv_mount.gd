class_name FpvMount
extends RefCounted
## R2.3: the FPV camera on a soft mount. The camera is a 2nd-order system on the frame: a rotational
## spring-damper with natural frequency `natural_hz` and damping ratio `zeta`, excited by the frame's
## own motion (base excitation). What the FPV feed shows is the frame's pose plus `offset()`.
##
## Two inputs, both sim state, nothing invented:
##   1. The frame's VIBRATION (VibrationModel.tone_angles): each motor's 1x and blade-pass lines, each
##      passed through the mount's transmissibility at its own frequency. Steady state, per tone, exact:
##      FlightLaw.mount_transmissibility, the one transmissibility in the codebase.
##          T(r) = sqrt((1 + (2 zeta r)^2) / ((1 - r^2)^2 + (2 zeta r)^2)),  r = f / natural_hz
##      The frame's vibration is the airframe model's (the same arm bending the gyro reads; the camera
##      sits on the same plates, so the same rotation is taken at the camera: an ESTIMATE of position).
##   2. The rigid body's angular rate changes (manoeuvres, and R1.1 contact impulses), integrated in the
##      time domain as the camera's lag RELATIVE to the frame: x'' + 2 zeta wn x' + wn^2 x = -theta_b''.
##      A step in body rate (an impact) rings the camera at the mount frequency and dies away. This input
##      is band-limited (the rigid body holds no 500 Hz content), so time-domain integration is honest
##      here, where it would not be for the vibration lines.
## Zero vibration and a steady body rate give exactly zero offset.
##
## MOUNT ESTIMATES (labelled, not measured on any specific camera): a hard mount passes the frame through
## unchanged (INF). Printed TPU camera mounts: ~30-60 Hz, taken as 45 Hz, zeta 0.10 (TPU loss factor
## ~0.2, zeta ~ eta / 2). Rubber damper balls: ~25 Hz, zeta 0.15.

const MOUNTS := {
	"hard": {"hz": INF, "zeta": 0.0},
	"tpu": {"hz": 45.0, "zeta": 0.10},
	"rubber_damper": {"hz": 25.0, "zeta": 0.15},
}
## ESTIMATE: a printed TPU camera mount is the common soft mount.
const DEFAULT_MOUNT := "tpu"

var mount_type := DEFAULT_MOUNT
var natural_hz := 45.0
var zeta := 0.10
## The camera's angle relative to the frame from the time-domain channel (rad, body axes) and its rate.
var rel_angle := Vector3.ZERO
var rel_rate := Vector3.ZERO
var _prev_body_rate := Vector3.ZERO
var _has_prev := false


func _init(p_type: String = DEFAULT_MOUNT) -> void:
	set_mount(p_type)


func set_mount(p_type: String) -> void:
	mount_type = p_type if MOUNTS.has(p_type) else DEFAULT_MOUNT
	var m: Dictionary = MOUNTS[mount_type]
	natural_hz = float(m["hz"])
	zeta = float(m["zeta"])
	reset()


func reset() -> void:
	rel_angle = Vector3.ZERO
	rel_rate = Vector3.ZERO
	_prev_body_rate = Vector3.ZERO
	_has_prev = false


## |camera / frame| at `hz` for a mount at (`f_n`, `p_zeta`): the analytic 2nd-order base-excitation form.
static func transmissibility(hz: float, f_n: float, p_zeta: float) -> float:
	return FlightLaw.mount_transmissibility(hz, f_n, p_zeta)


func transmissibility_at(hz: float) -> float:
	return transmissibility(hz, natural_hz, zeta)


## One physics substep, given the body's angular rate (body axes, rad/s) after it. Semi-implicit Euler;
## at 1 kHz and wn = 2 pi 45 Hz, wn dt = 0.29, well inside its stability bound (2).
func step_body(body_rate_rad_s: Vector3, dt: float) -> void:
	if not _has_prev:
		_prev_body_rate = body_rate_rad_s
		_has_prev = true
	if dt <= 0.0:
		return
	var base_accel := (body_rate_rad_s - _prev_body_rate) / dt
	_prev_body_rate = body_rate_rad_s
	if is_inf(natural_hz):
		rel_angle = Vector3.ZERO
		rel_rate = Vector3.ZERO
		return
	var wn := TAU * natural_hz
	rel_rate += (-base_accel - 2.0 * zeta * wn * rel_rate - wn * wn * rel_angle) * dt
	rel_angle += rel_rate * dt


## The vibration channel: the camera's angle from the frame's vibration lines (rad, body axes).
func vibration_offset(model: VibrationModel) -> Vector3:
	if model == null:
		return Vector3.ZERO
	var out := Vector3.ZERO
	for tone in model.tone_angles():
		var t := 1.0 if is_inf(natural_hz) else transmissibility_at(float(tone["hz"]))
		out += (tone["angle"] as Vector3) * t
	return out


## The camera's angle relative to the frame's rigid pose: the vibration lines through the mount, plus
## the mount's lag behind the rigid body. Both are zero for a still, vibration-free frame.
func offset(model: VibrationModel) -> Vector3:
	return vibration_offset(model) + rel_angle
