class_name FlightController
extends RefCounted
## The single control path, and the interface architecture.md named on day one:
##
##   FlightController.update(accel, gyro, rc, dt) -> motor_output[4]
##
## One inner rate loop always runs. The mode switch changes only WHAT PRODUCES THE
## SETPOINTS it tracks — the pilot's sticks directly in acro, or the self-levelling outer
## loop in angle mode — and changes nothing else. Two front ends, one control path.
##
## That is the whole shape of a real flight controller, and it is what makes releasing the
## stick mean "stop rotating" on every axis in every mode. Lothal previously had two
## independent laws each producing motor commands, which meant a fix to one silently did
## not reach the other and the two could disagree about a sign convention.
##
## Implementation B — BetaflightSITL over UDP — slots in behind this same call.

enum Mode { ANGLE, ACRO }

var mode: Mode = Mode.ANGLE
## The inner loop, kept across mode changes: the aircraft does not stop being rate
## controlled because the pilot flicked a switch, and rebuilding it mid-flight would dump
## the integrator state that is holding the aircraft trimmed.
var rate_loop := RateModeController.new()

## What the controller believes about its attitude, built only from the modelled IMU (R1.2). It
## runs in every mode, as a real board's does, so switching to angle finds a converged estimate.
var estimator := AttitudeEstimator.new()

## gyro_rate_rad_s must come from DroneCore.gyro and accel_body_mps2 from DroneCore.accel. Nothing
## here may reach for rigid_body.angular_velocity_rad_s or rigid_body.orientation — see
## src/sim/gyro.gd. Angle mode levels against the ESTIMATED attitude, so it inherits what the
## estimator gets wrong (a tilted horizon in a long turn, under hard acceleration).
func update(accel_body_mps2: Vector3, gyro_rate_rad_s: Vector3, rc: Dictionary, dt: float, vbat: VbatSensor = null) -> Dictionary:
	estimator.update(gyro_rate_rad_s, accel_body_mps2, dt)
	if turtle:
		return turtle_mix(rc)
	var setpoint := rate_setpoint(estimator.attitude, rc)
	return rate_loop.update(setpoint, gyro_rate_rad_s, rc.throttle, dt, vbat)

## The mode switch, in its entirety. `orientation` is the ESTIMATE.
func rate_setpoint(orientation: Quaternion, rc: Dictionary) -> Vector3:
	if mode == Mode.ANGLE:
		return AngleModeController.rate_setpoint(orientation, rc)
	return RateModeController.rate_setpoint(rc)

func toggle_mode() -> void:
	mode = Mode.ACRO if mode == Mode.ANGLE else Mode.ANGLE
	# Integral and derivative history from the previous mode's setpoints has nothing to say
	# about the new one's.
	rate_loop.reset()   # the estimator is NOT reset: attitude does not change with the mode

## TURTLE MODE (Betaflight "flip over after crash", 4.x mixer.c). A quad resting on its back stays there: its
## thrust points into the ground, and no stick input can lift it (measured: full roll at 36% throttle leaves it
## inverted, tests/test_turtle_mode.gd). Real pilots flip it with the props spun BACKWARDS: the ESCs reverse the
## motors on the side the stick names and nothing else, so that side lifts and the aircraft pivots over the
## other side's arms. While on, the stabiliser and throttle are bypassed entirely, as in Betaflight.
var turtle := false

## Betaflight's default crashflip_expo (35): flip power = f*d + (1-f)*d^3 with f = 1 - expo/100.
const CRASHFLIP_EXPO := 35.0

func toggle_turtle() -> void:
	turtle = not turtle
	# The rate loop's history belongs to flight, not to a flip on the ground: re-enter flight clean.
	rate_loop.reset()

## Motor commands in turtle mode, MotorLayout.MOTOR_NAMES order keys, each in [0, 1]. Only the dominant stick
## axis acts (Betaflight picks yaw when it dominates, else roll/pitch together); a motor runs when its mixer
## sign for that input agrees with the stick, and sits at zero otherwise.
static func turtle_mix(rc: Dictionary, config: Dictionary = {}) -> Dictionary:
	var roll: float = clampf(float(rc.get("roll", 0.0)), -1.0, 1.0)
	var pitch: float = clampf(float(rc.get("pitch", 0.0)), -1.0, 1.0)
	var yaw: float = clampf(float(rc.get("yaw", 0.0)), -1.0, 1.0)
	var rp := Vector2(roll, pitch).length()
	var use_yaw := absf(yaw) > rp
	var d := clampf(absf(yaw) if use_yaw else rp, 0.0, 1.0)
	var f := 1.0 - CRASHFLIP_EXPO / 100.0
	var power := f * d + (1.0 - f) * d * d * d
	var spin := MotorLayout.spin_map(config)
	var out := {}
	for name in MotorLayout.MOTOR_NAMES:
		# The normal mixer's signs: roll right speeds the LEFT motors, pitch forward the REAR ones, yaw by spin.
		var m_roll := -1.0 if MotorLayout.IS_RIGHT[name] else 1.0
		var m_pitch := -1.0 if MotorLayout.IS_FRONT[name] else 1.0
		var drive := 0.0
		if use_yaw:
			drive = signf(yaw) * -float(spin[name])
		else:
			drive = (roll * m_roll + pitch * m_pitch) / maxf(rp, 1.0e-9)
		out[name] = power * clampf(drive, 0.0, 1.0) if d > 0.0 else 0.0
	return out

func is_rate_mode() -> bool:
	return mode == Mode.ACRO

func reset() -> void:
	turtle = false
	rate_loop.reset()
	estimator.reset()
