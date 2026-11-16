class_name AttitudeEstimator
extends RefCounted
## The flight controller's own idea of its attitude (R1.2) — a Mahony complementary filter fusing
## the modelled gyro and accelerometer, in the manner of Betaflight's IMU code.
##
## The gyro is integrated for the fast, smooth part; the accelerometer's idea of "up" pulls the
## estimate back for the slow, drift-free part, at a rate set by KP. The accelerometer measures
## specific force, not gravity, so the correction is only right while the aircraft is not
## accelerating. Two things follow, and both are deliberate:
##
##   * The correction is applied only while |specific force| is within TRUST_BAND of 1 g (what
##     Betaflight does with its 0.9-1.1 g window). Outside it the filter coasts on the gyro.
##   * Inside it the filter is still fooled. A sustained coordinated turn is the textbook case:
##     the specific force points straight along the body "up" axis the whole way round (1/cos(bank)
##     g, inside the window up to ~24 degrees of bank), so the accelerometer says "level" and the
##     horizon the controller believes in tilts toward the bank, with time constant 1/KP.
##
## Yaw is unobservable from gravity, so it is gyro-only and free to drift. Angle mode does not use
## it. The estimate starts from the first trustworthy accelerometer reading, as a board does at
## power-on, rather than from the truth.

## Betaflight's imu_dcm_kp default (2500 / 10000), in 1/s: a time constant of 4 s. Raise it and
## the estimate sticks to the accelerometer (faster convergence, more fooled by acceleration and
## shake); lower it and it trusts the gyro (slower to correct drift, fooled less).
const DEFAULT_KP := 0.25
## Accept the accelerometer when |a| is within this fraction of 1 g.
const TRUST_BAND := 0.1
const GRAVITY_MPS2 := 9.80665

var kp: float = DEFAULT_KP
var seeded := false
## Body -> world, as the FC believes it.
var attitude := Quaternion.IDENTITY

func reset() -> void:
	seeded = false
	attitude = Quaternion.IDENTITY

func trusts(accel_body_mps2: Vector3) -> bool:
	var g := accel_body_mps2.length() / GRAVITY_MPS2
	return absf(g - 1.0) <= TRUST_BAND

## One step. gyro is the body-frame reading (rad/s); accel the body-frame specific force (m/s^2).
func update(gyro_body_rad_s: Vector3, accel_body_mps2: Vector3, dt: float) -> void:
	var valid := trusts(accel_body_mps2)
	if not seeded:
		if valid:
			# Shortest rotation taking the measured "up" (body) onto world up; yaw starts at zero.
			attitude = Quaternion(accel_body_mps2.normalized(), Vector3.UP)
			seeded = true
		return
	var omega := gyro_body_rad_s
	if valid and kp > 0.0:
		var up_est_body := attitude.inverse() * Vector3.UP
		omega += kp * accel_body_mps2.normalized().cross(up_est_body)
	var angle := omega.length() * dt
	if angle > 0.0:
		attitude = (attitude * Quaternion(omega / omega.length(), angle)).normalized()
