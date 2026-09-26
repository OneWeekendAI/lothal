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
## The tune actually installed on this aircraft, so the D cost quoted below is the cost of the D
## gain that is flying rather than of the reference build's. Null falls back to the hand tune, which
## is what a panel rendered before anything has been derived should show.
var _tune: RateTune = null

func _init() -> void:
	super(SPEC_ROWS)

## Kept so the consequence rows can reach the installed controller. PartDetails hands the part
## down; this panel needs the aircraft the part is fitted to, which is a different thing.
## Stashed BEFORE the super call, because that is what fills the rows _read() answers.
func render(part: Dictionary, build: Build, tune: RateTune = null) -> void:
	_build = build
	_tune = tune
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
## THE ROW THAT TURNS A SPEC SHEET INTO A DECISION, and it is derived from the model that is
## actually installed rather than from a convenient approximation of it.
##
## PIDController has no D-term lowpass: `derivative = -(measured - last)/dt` acts directly on
## whatever the gyro handed it. But what the gyro hands it is not the raw noise — it is the raw
## noise THROUGH THE PT1, and that filter is right there in Gyro. Successive readings are
## therefore CORRELATED, and the step between them is far smaller than two independent samples
## would give.
##
## Getting this wrong is not academic. Treating the samples as independent (sqrt(2) * sigma over
## the period) reports 9.4% of full command for the BMI270 board where the filtered model gives
## 1.6% — an overstatement of six times, and it grows with sample rate, so it would have been
## worst exactly on the boards a builder is most likely to be considering. It would also have
## been a number derived from a filter the code does not have while a filter the code DOES have
## sat one call away.
##
## The filtered-step arithmetic now lives on Gyro (sample_step_noise_rad_s) and the command-fraction
## arithmetic on RateTune (d_noise_fraction), because a SECOND consumer arrived: the derived tune
## bounds its own D gain against this exact figure. Two copies would be two opinions about one board
## the day anyone corrected the filter model — and that model has already been corrected once.
##
## IT STILL SCALES ROUGHLY AS 1/T, which is the real reason fast boards need better sensors, and it
## falls out of the arithmetic rather than being asserted somewhere else. That was this row's
## contribution to labs-and-sim.md §7, whose open question was what one fixed gain set could mean
## across the catalog: the achievable D is bounded by the BOARD as well as by the frame. §7 is now
## resolved, and this row is one half of the answer — RateTune is the other.
##
## Still quoted as an upper bound, for one remaining and honest reason: real Betaflight applies a
## D-term lowpass on top of the gyro filter, and Lothal models no such stage. So this is what the
## noise costs with the gyro's own filter and nothing further — not a prediction of a real board's
## motor heat.
##
## The kd is the one ACTUALLY INSTALLED on this aircraft, from the tune the panel was handed, so
## this row and the loop that is flying cannot come to different conclusions. Without a tune it
## quotes the hand tune, which is what the reference build's is anyway.
func _d_term_noise() -> String:
	if _build == null:
		return "—"
	# ControlFigures: the same call the Lab dock's FC page number makes, fallback included.
	var kd := ControlFigures.installed_kd(_tune)
	var d_rms := ControlFigures.d_noise_fraction(_build, _tune)
	var ceiling := RateTune.kd_ceiling_for(_build)
	# Naming the ceiling beside the cost is what turns a number into a decision. A board whose
	# ceiling is below what this airframe's plant asks for is a board that is choosing the tune.
	var headroom := ""
	if is_finite(ceiling):
		headroom = "  (D up to %.3f here)" % ceiling
	return "%.1f%% of full command at D %.3f%s" % [d_rms * 100.0, kd, headroom]
