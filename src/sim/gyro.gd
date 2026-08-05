class_name Gyro
extends RefCounted
## The aircraft's rate sensor — a MEMS gyro model sitting between the rigid body and the
## flight controller (physics.md §7).
##
## Real firmware never sees ground truth. It sees a signal that has been sampled at a
## finite rate, low-passed to keep frame resonance out of the D term, and shifted by a bias
## the calibration did not quite remove. The gap between that signal and the truth is not a
## detail: it is where a large part of real drone behaviour lives. Phase lag from the
## filter is what limits how hard D can be pushed; the noise floor is what decides whether
## D is usable at all; bias is why a hands-off quad wanders.
##
## So the FC consumes this, and nothing reaches around it to
## rigid_body.angular_velocity_rad_s. That single rule is the whole point of the class.
##
## WHAT IS NOT MODELLED, deliberately: scale-factor error, axis misalignment, temperature
## drift, and rate saturation (a real ICM-42688 clips around 2000 deg/s). Attitude, too,
## is still taken straight from the integrator rather than estimated — a real FC fuses an
## accelerometer to correct gyro drift, and Lothal has no accelerometer fusion yet. All of
## that is a later slice; the seam built here is what makes it a later slice rather than a
## rewrite.

## --- The filter ---
## PT1 (single-pole IIR), not a biquad. Chosen because it is what Betaflight's default
## gyro_lowpass_type is, because its lag is exactly one time constant and therefore
## assertable rather than approximate (see tests/test_gyro.gd), and because a second-order
## section buys steeper rolloff at the cost of MORE phase lag in the passband — which is
## the quantity that actually limits the loop. When frame resonance gets modelled, a
## notch belongs here alongside the PT1, not instead of it.
##
## Cutoff is the single most consequential FC tuning parameter after the PID gains. Lower
## it and D gets quiet but the loop gets sluggish and eventually unstable; raise it and the
## aircraft feels sharp until the props go out of balance. 150 Hz sits in Betaflight's
## usual 100-250 Hz band, and costs 1.06 ms of lag against a rate loop running at 1 ms.
const DEFAULT_CUTOFF_HZ := 150.0

## The rate loop runs at 1 kHz (physics.md §6, 8 substeps of a 120 Hz frame), so the stock
## sensor samples with it. It is a separate number from the loop rate on purpose: real
## hardware runs the gyro faster than the PID loop, and lowering this is how you find out
## what a slow sensor does to a fast loop.
const DEFAULT_SAMPLE_RATE_HZ := 1000.0

## --- Error terms, both defaulting LOW ---
## The point of this slice is a correct architecture, not a mushy one. A bias large enough
## to make the aircraft drift on its own would have replaced one bug with another, so both
## defaults are set where a well-behaved calibrated sensor actually sits, and the aircraft
## still flies clean. RAISING them is how you explore why real drones need filtering at
## all — wind the noise up and watch the D term turn into a motor heater.
##
## ~0.16 deg/s RMS: an MPU-6000's published 0.005 deg/s/sqrt(Hz) rate noise density carried
## across a 1 kHz bandwidth (InvenSense PS-MPU-6000A-00 rev 3.4).
##
## This previously named the ICM-42688, whose density is 0.0028 — the NUMBER was right and
## the PART was wrong. The fix was not to move a constant every flight test is calibrated
## against: it was to make the reference board in data/parts/flight_controllers.json the
## MPU-6000 board this figure actually describes. The ICM-42688 boards in that file are
## genuinely quieter, which is an upgrade a builder can feel rather than a relabelling.
const DEFAULT_NOISE_RAD_S := 0.0028
## ~0.1 deg/s on each axis: the residue a bench calibration leaves behind, not the raw
## uncalibrated offset, which is tens of times larger.
const DEFAULT_BIAS_RAD_S := Vector3(0.0017, 0.0017, 0.0017)

## Fixed by default. Noise drawn from an unseeded global RNG would make every test in this
## repo that touches the flight loop irreproducible — a worse defect than having no noise
## at all.
const DEFAULT_SEED := 0x10FA1

var sample_rate_hz: float
var cutoff_hz: float
## Standard deviation of the per-sample white noise, rad/s, applied independently per axis.
var noise_rad_s: float
var bias_rad_s: Vector3

## The most recent reading. Held between samples, which is what a consumer polling faster
## than the sensor actually gets.
var rate_rad_s := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _seed: int
var _time_since_sample: float = 0.0

func _init(p_sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ, p_cutoff_hz: float = DEFAULT_CUTOFF_HZ,
		p_noise_rad_s: float = DEFAULT_NOISE_RAD_S, p_bias_rad_s: Vector3 = DEFAULT_BIAS_RAD_S,
		p_seed: int = DEFAULT_SEED) -> void:
	sample_rate_hz = p_sample_rate_hz
	cutoff_hz = p_cutoff_hz
	noise_rad_s = p_noise_rad_s
	bias_rad_s = p_bias_rad_s
	_seed = p_seed
	_rng.seed = _seed

## A gyro configured from a catalog flight controller — THE ONE PLACE catalog keys become
## gyro fields.
##
## The four specs are properties of the IMU on the board you buy, and the constants above are
## what a board that does not name one gets. That is the whole point of the FC catalog:
## sensor quality stops being a project-wide constant and becomes a decision with a
## consequence you can feel.
##
## Every field falls back INDIVIDUALLY, so a contributor's partial entry degrades to the
## stock sensor rather than to zero. Zero is not a quiet sensor here: a zero cutoff is a
## divide-by-zero, and a zero sample rate is an infinite loop in update().
##
## Bias is published as one scalar and applied to all three axes. Real per-axis residues
## differ, but a catalog that asked a contributor for three numbers would be asking them to
## invent two — the scalar is the honest shape for a class-typical figure.
static func from_part(fc: Dictionary) -> Gyro:
	var specs: Dictionary = fc.get("specs", {})
	var bias := DEFAULT_BIAS_RAD_S
	if specs.has("gyro_bias_rad_s"):
		bias = Vector3.ONE * float(specs["gyro_bias_rad_s"])
	return Gyro.new(
		float(specs.get("gyro_sample_rate_hz", DEFAULT_SAMPLE_RATE_HZ)),
		float(specs.get("gyro_cutoff_hz", DEFAULT_CUTOFF_HZ)),
		float(specs.get("gyro_noise_rad_s", DEFAULT_NOISE_RAD_S)),
		bias)

## Advances the sensor by dt against the body's true angular rate and returns the current
## reading. Called once per substep by DroneCore, AFTER integration.
##
## Between sample instants the reading is held rather than recomputed — that hold is the
## sensor's own zero-order hold, and it is a real source of lag when the sample rate is
## dropped below the loop rate.
func update(true_rate_rad_s: Vector3, dt: float) -> Vector3:
	var period := 1.0 / sample_rate_hz
	_time_since_sample += dt
	# A while loop rather than an if: a caller stepping slower than the sample rate owes
	# the sensor several samples, and silently dropping them would quietly turn a 1 kHz
	# gyro into whatever rate the caller happened to run at.
	#
	# Each catch-up sample sees the same true rate, because that is the only value in hand.
	# A real sensor would have seen the motion in between; this is the one place the model
	# is knowingly optimistic, and it only bites when dt exceeds the sample period.
	while _time_since_sample >= period:
		_time_since_sample -= period
		_sample(true_rate_rad_s, period)
	return rate_rad_s

func reset() -> void:
	rate_rad_s = Vector3.ZERO
	_time_since_sample = 0.0
	# Re-seeded, so a respawn replays the same noise rather than continuing the old stream.
	# Without this, "the same flight twice" would not be the same flight.
	_rng.seed = _seed

## One sensor sample: truth, plus bias, plus noise, through the PT1.
func _sample(true_rate_rad_s: Vector3, period: float) -> void:
	var raw := true_rate_rad_s + bias_rad_s
	if noise_rad_s > 0.0:
		raw += Vector3(
			_rng.randfn(0.0, noise_rad_s),
			_rng.randfn(0.0, noise_rad_s),
			_rng.randfn(0.0, noise_rad_s))

	# Filter state starts at zero and is filtered into from the first sample, rather than
	# being seeded WITH the first sample. Seeding would make the very first reading after a
	# reset exact and unlagged, which is the one thing a filtered sensor cannot be — and it
	# costs nothing here, because a reset happens at rest, where zero IS the truth.
	#
	# alpha = dt / (RC + dt), RC = 1 / (2*pi*fc). This form has unity DC gain by
	# construction — a filter that changed the steady-state reading would be a scale error
	# on every rate the FC ever sees.
	var rc := 1.0 / (TAU * cutoff_hz)
	var alpha := period / (rc + period)
	rate_rad_s += (raw - rate_rad_s) * alpha

## Body-axis rates re-expressed in the coordinate contract's roll/pitch/yaw
## (physics.md §1): +Roll about -Z, +Pitch about +X, +Yaw about -Y.
##
## Lives here so there is exactly one expression of the mapping in the codebase. It was
## previously written out by hand in each controller, which is how two control laws end up
## disagreeing about a sign.
static func contract_rates(body_rate_rad_s: Vector3) -> Vector3:
	return Vector3(-body_rate_rad_s.z, body_rate_rad_s.x, -body_rate_rad_s.y)
