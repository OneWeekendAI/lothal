class_name FlightController
extends RefCounted
## The single control path, and the interface architecture.md named on day one:
##
##   FlightController.update(orientation, gyro, rc, dt) -> motor_output[4]
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

## gyro_rate_rad_s must come from DroneCore.gyro. Nothing here may reach for
## rigid_body.angular_velocity_rad_s — see src/sim/gyro.gd.
func update(orientation: Quaternion, gyro_rate_rad_s: Vector3, rc: Dictionary, dt: float) -> Dictionary:
	var setpoint := rate_setpoint(orientation, rc)
	return rate_loop.update(setpoint, gyro_rate_rad_s, rc.throttle, dt)

## The mode switch, in its entirety.
func rate_setpoint(orientation: Quaternion, rc: Dictionary) -> Vector3:
	if mode == Mode.ANGLE:
		return AngleModeController.rate_setpoint(orientation, rc)
	return RateModeController.rate_setpoint(rc)

func toggle_mode() -> void:
	mode = Mode.ACRO if mode == Mode.ANGLE else Mode.ANGLE
	# Integral and derivative history from the previous mode's setpoints has nothing to say
	# about the new one's.
	reset()

func is_rate_mode() -> bool:
	return mode == Mode.ACRO

func reset() -> void:
	rate_loop.reset()
