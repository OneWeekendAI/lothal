class_name TestStickRelease
extends RefCounted
## The thing the pilot actually asked for: "tapping A then D does not return the drone to
## neutral."
##
## The naive test — equal and opposite taps cancel — is worthless here. It passes on a
## merely SYMMETRIC open loop, which is exactly what the code had, and it misses the point
## entirely. Human taps are never equal. So each case below taps one way for one duration,
## the other way for a DIFFERENT duration, then releases every stick and integrates
## forward with no corrective input at all.
##
## What that encodes is the real requirement: with a closed rate loop, two taps do not need
## to cancel each other, because releasing the stick is ITSELF the command "rate = 0".
##
## Run on all three axes and in both modes, because whatever was true of yaw was never
## checked on roll or pitch either.

const DT := 0.001
const TAP_A_S := 0.20
const TAP_B_S := 0.35   # deliberately NOT equal to TAP_A_S
const RECOVERY_S := 1.0

## ~2.9 deg/s, the same residual band tests/test_rate_mode_release.gd already holds roll to.
const RESIDUAL_RATE_RAD_S := 0.05
## Attitude must have stopped moving, not merely be moving slowly: 0.05 rad/s sustained over
## the final 200 ms window is 0.57 deg, so 1 degree is the residual rate's own budget plus a
## little, rather than a number chosen to fit an outcome.
const RESIDUAL_ATTITUDE_DEG := 1.0
const SETTLE_WINDOW_S := 0.2

const AXES := ["roll", "pitch", "yaw"]

static func _zero_rc(throttle: float) -> Dictionary:
	return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}

## Body rates in contract axes: +Roll about -Z, +Pitch about +X, +Yaw about -Y.
static func _contract_rates(core: DroneCore) -> Vector3:
	var w := core.rigid_body.angular_velocity_rad_s
	return Vector3(-w.z, w.x, -w.y)

static func _rate_on(core: DroneCore, axis: String) -> float:
	var r := _contract_rates(core)
	match axis:
		"roll": return r.x
		"pitch": return r.y
	return r.z

static func _advance(core: DroneCore, fc: FlightController, rc: Dictionary, duration_s: float) -> void:
	for i in int(duration_s / DT):
		core.step(fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT), DT)

## Two unequal opposing taps on one axis, then hands off. Returns the residual rate on that
## axis and how far the whole attitude still moved over the last SETTLE_WINDOW_S.
static func _unequal_taps(axis: String, use_rate_mode: bool) -> Dictionary:
	var core := ReferenceBuild.build_drone_core()
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)
	var fc := FlightController.new()
	fc.mode = FlightController.Mode.ACRO if use_rate_mode else FlightController.Mode.ANGLE

	var tap_a := _zero_rc(hover)
	tap_a[axis] = 1.0
	var tap_b := _zero_rc(hover)
	tap_b[axis] = -1.0

	_advance(core, fc, tap_a, TAP_A_S)
	_advance(core, fc, tap_b, TAP_B_S)

	# Hands off from here. Nothing below touches a stick.
	var released := _zero_rc(hover)
	_advance(core, fc, released, RECOVERY_S - SETTLE_WINDOW_S)
	var attitude_before := core.rigid_body.orientation
	_advance(core, fc, released, SETTLE_WINDOW_S)

	return {
		"rate": _rate_on(core, axis),
		# Quaternion.angle_to already returns the rotation angle, not the half-angle.
		"attitude_deg": rad_to_deg(absf(attitude_before.angle_to(core.rigid_body.orientation))),
	}

static func run() -> Array:
	var results: Array = []

	for use_rate_mode in [false, true]:
		var mode_name := "acro" if use_rate_mode else "angle"
		for axis in AXES:
			var outcome := _unequal_taps(axis, use_rate_mode)
			results.append(TestResult.new(
				"%s mode, %s: unequal opposing taps, then hands off -> rate returns to zero within %.1f s"
					% [mode_name, axis, RECOVERY_S],
				absf(outcome.rate) < RESIDUAL_RATE_RAD_S,
				"residual %s rate = %.4f rad/s (%.2f deg/s)" % [axis, outcome.rate, rad_to_deg(outcome.rate)]
			))
			results.append(TestResult.new(
				"%s mode, %s: and the attitude has stopped changing" % [mode_name, axis],
				outcome.attitude_deg < RESIDUAL_ATTITUDE_DEG,
				"attitude moved %.3f deg over the final %.0f ms" % [outcome.attitude_deg, SETTLE_WINDOW_S * 1000.0]
			))

	return results
