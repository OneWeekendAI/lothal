class_name Accelerometer
extends RefCounted
## The aircraft's accelerometer — the MEMS sibling of Gyro, on the same IMU (R1.2).
##
## It reads SPECIFIC FORCE: every force on the airframe except gravity, per unit mass, in the BODY
## frame. At a still hover that is (0, +g, 0) — the sensor feels the rotors holding it up, not the
## gravity they are holding it against — and in free fall it reads zero. This is the whole reason an
## attitude estimator built on it can be fooled: it measures where "up" appears to be, which is the
## direction of thrust plus drag, and only equals the direction of true up when the aircraft is not
## accelerating.
##
## It goes through the gyro's own sensor path: sampled after integration at its own rate and held
## between samples, PT1-filtered, offset by a bias, with white noise from a fixed-seed RNG (so a
## replay is the same flight), and shaken by the SAME airframe vibration the gyro is shaken by.
##
## WHAT IS NOT MODELLED: scale-factor error, axis misalignment, temperature drift, saturation.
## The vibration coupling is a labelled guess (see SHAKE_MPS2_PER_RAD_S).

## A 1 kHz sample, with the gyro. 100 Hz PT1: looser than a tuned build's estimator input, so the
## estimator sees more of the shake than it might; rejecting it is what the Kp gain is for.
const DEFAULT_SAMPLE_RATE_HZ := 1000.0
const DEFAULT_CUTOFF_HZ := 100.0
## ~5 mg RMS per sample: an MPU-6000's 400 ug/sqrt(Hz) over a few hundred Hz, rounded.
const DEFAULT_NOISE_MPS2 := 0.05
## ~5 mg: the residue a bench calibration leaves. It is a ~0.3 degree attitude bias on its own.
const DEFAULT_BIAS_MPS2 := Vector3(0.05, 0.05, 0.05)
const DEFAULT_SEED := 0xACC31

## LABELLED GUESS. The gyro's vibration source gives a body-rate shake (rad/s); the same airframe
## shake reaches the accelerometer as a linear acceleration. No catalog or measured data relates
## the two, so this is one scalar: 1 rad/s of gyro shake <-> this many m/s^2 on the accelerometer,
## along the same body axes. Set it to 0 to take vibration off the accelerometer. 10 was tried and
## rectified (the aliased tone is not zero-mean) into a 0.7 degree hover tilt, which is more than the
## guess can justify.
const SHAKE_MPS2_PER_RAD_S := 2.0

var sample_rate_hz: float
var cutoff_hz: float
## FlightLaw.lowpass_alpha(period, cutoff_hz), kept while neither changes.
var _alpha_period := -1.0
var _alpha_cutoff_hz := -1.0
var _alpha := 0.0
var noise_mps2: float
var bias_mps2: Vector3
## What a level calibration has taken back out of `bias_mps2` (R1.7); zero until `calibrate()` runs.
var trim_mps2 := Vector3.ZERO

## The level calibration every flight controller offers and every pilot does once (B1, review P8): on a level surface,
## motors off, the firmware averages `CALIBRATION_SAMPLES` readings and subtracts their mean from (0, g, 0). The residue
## is the average's own noise, sigma / sqrt(N), drawn from a calibration RNG apart from the flight's noise stream.
## Betaflight's accelerometer calibration averages 400 samples.
const CALIBRATION_SAMPLES := 400

func calibrate() -> void:
	trim_mps2 = Gyro.still_average(bias_mps2, noise_mps2, _seed ^ 0xCA1B, CALIBRATION_SAMPLES)
## The most recent reading (m/s^2, body frame). Held between samples.
var reading_mps2 := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _seed: int
var _time_since_sample := 0.0

func _init(p_sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ, p_cutoff_hz: float = DEFAULT_CUTOFF_HZ,
		p_noise_mps2: float = DEFAULT_NOISE_MPS2, p_bias_mps2: Vector3 = DEFAULT_BIAS_MPS2,
		p_seed: int = DEFAULT_SEED) -> void:
	sample_rate_hz = p_sample_rate_hz
	cutoff_hz = p_cutoff_hz
	noise_mps2 = p_noise_mps2
	bias_mps2 = p_bias_mps2
	_seed = p_seed
	_rng.seed = _seed

## Advances the sensor by dt against the true specific force (body frame, m/s^2) and the shake the
## gyro was last shaken with (rad/s, body frame). Returns the current reading.
func update(true_specific_force_body_mps2: Vector3, gyro_shake_rad_s: Vector3, dt: float) -> Vector3:
	var period := 1.0 / sample_rate_hz
	_time_since_sample += dt
	while _time_since_sample >= period:
		_time_since_sample -= period
		var raw := true_specific_force_body_mps2 + bias_mps2 - trim_mps2 + gyro_shake_rad_s * SHAKE_MPS2_PER_RAD_S
		if noise_mps2 > 0.0:
			raw += Vector3(_rng.randfn(0.0, noise_mps2), _rng.randfn(0.0, noise_mps2),
				_rng.randfn(0.0, noise_mps2))
		if period != _alpha_period or cutoff_hz != _alpha_cutoff_hz:
			_alpha_period = period
			_alpha_cutoff_hz = cutoff_hz
			_alpha = FlightLaw.lowpass_alpha(period, cutoff_hz)
		reading_mps2 += (raw - reading_mps2) * _alpha
	return reading_mps2

func reset() -> void:
	reading_mps2 = Vector3.ZERO
	_time_since_sample = 0.0
	_rng.seed = _seed
