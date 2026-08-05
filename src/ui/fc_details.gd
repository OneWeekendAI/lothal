class_name FcDetails
extends PartDetails
## What the selected flight controller is, and — more usefully — what its sensor costs you.
##
## The rows split in two. The top half is the board: its processor, its IMU, its mass, its bolt
## pattern. The bottom half is the CONSEQUENCE, and it is the half worth having.
##
## "Noise floor 0.0028 rad/s" is not a number anyone can act on. What that noise floor becomes
## at the motors, through the D gain actually installed, is a decision.

const SPEC_ROWS := [
	{"key": "processor", "label": "Processor"},
	{"key": "imu", "label": "Gyro"},
	{"key": "mass_g", "label": "Board mass"},
	{"key": "mount", "label": "Mount"},
	{"key": "loop_rate_hz", "label": "Loop rate"},
	{"key": "sample_rate", "label": "Gyro sample rate"},
	{"key": "filter_lag", "label": "Filter delay"},
	{"key": "noise_floor", "label": "Noise floor"},
	{"key": "bias", "label": "Calibration drift"},
	{"key": "d_cost", "label": "Noise at the motors"},
]

var _build: Build = null

func _init() -> void:
	super(SPEC_ROWS)

## Kept so the consequence rows can reach the installed controller. PartDetails hands the part
## down; this panel needs the aircraft the part is fitted to, which is a different thing.
## Stashed BEFORE the super call, because that is what fills the rows _read() answers.
func render(part: Dictionary, build: Build) -> void:
	_build = build
	super(part, build)

func _read(fc: Dictionary, key: String) -> String:
	var gyro := Gyro.from_part(fc)

	match key:
		"mass_g":
			return "%.0f g" % float(fc.get("mass_g", 0.0))
		"mount":
			return _or_dash(str(fc.get("mounting", {}).get("pattern", "")))
		"loop_rate_hz":
			# Carried and labelled, exactly as the ESC's burst rating is. Leaving it off the
			# screen would be its own kind of dishonesty — a builder comparing an F4 to an H7
			# compares it — but showing it unqualified would claim the sim models it.
			var loop: float = float(fc.get("catalog", {}).get("loop_rate_hz", 0.0))
			if loop <= 0.0:
				return "—"
			return "%.0f kHz  (not modelled)" % (loop / 1000.0)
		"sample_rate":
			return "%.1f kHz" % (gyro.sample_rate_hz / 1000.0)
		"filter_lag":
			# A PT1's lag is exactly one time constant, RC = 1/(2*pi*fc) — which is why the
			# filter is a PT1 and not a biquad (physics.md §7). Milliseconds, because that is
			# the unit the loop period is in, and the comparison is the whole point.
			var rc_ms := 1000.0 / (TAU * gyro.cutoff_hz)
			return "%.2f ms  (%.0f Hz cutoff)" % [rc_ms, gyro.cutoff_hz]
		"noise_floor":
			return "%.2f °/s RMS" % rad_to_deg(gyro.noise_rad_s)
		"bias":
			return "%.2f °/s per axis" % rad_to_deg(gyro.bias_rad_s.x)
		"d_cost":
			return _d_term_noise()
	return super(fc, key)


## What the noise floor becomes at the motors, as a fraction of full command, with the aircraft
## perfectly still.
##
## THE ROW THAT TURNS A SPEC SHEET INTO A DECISION, and it is exactly derivable rather than
## estimated: PIDController has no D-term lowpass — `derivative = -(measured - last)/dt` acts on
## the raw measurement — so successive samples are independent, their difference carries sqrt(2)
## times the per-sample sigma, and the derivative divides by the sample period.
##
##   sigma_norm = noise / MAX_RATE_RAD_S        the loop's own normalised units
##   d_rms      = kd * sigma_norm * sqrt(2) / T
##
## Two honesty notes, the second of which is on screen rather than only here:
##
##   IT SCALES AS 1/T. A FASTER loop amplifies gyro noise MORE, which is the real reason fast
##   boards need better sensors — and it falls out of the arithmetic here rather than being
##   asserted somewhere else. That is this slice's contribution to labs-and-sim.md §7, whose
##   open question is what one fixed gain set can mean across the catalog.
##
##   IT IS AN UPPER BOUND. Real Betaflight applies a D-term lowpass that Lothal does not model,
##   so this is what the noise would cost with nothing filtering the D term at all — not a
##   prediction of a real board's motor heat.
##
## kd and MAX_RATE_RAD_S are read from the installed controller rather than restated here, so
## this panel and the loop that is actually flying cannot come to different conclusions.
func _d_term_noise() -> String:
	if _build == null:
		return "—"
	var gyro := _build.gyro()
	var sigma_norm := gyro.noise_rad_s / RateModeController.MAX_RATE_RAD_S
	var period := 1.0 / gyro.sample_rate_hz
	var d_rms := RateModeController.ROLL_PITCH_KD * sigma_norm * sqrt(2.0) / period
	return "%.1f%% of full command  (upper bound)" % (d_rms * 100.0)
