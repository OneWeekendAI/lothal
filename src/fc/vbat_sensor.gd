class_name VbatSensor
extends RefCounted
## The flight controller's battery-voltage measurement (R1.3), and the one place the compensation
## factor is computed.
##
## The FC never sees the pack's true terminal voltage. It sees what a real board's ADC sees: the
## pack voltage plus ADC noise, quantised to the ADC step, then smoothed by a low-pass (Betaflight
## filters its battery reading hard, because the raw one is dominated by the motors' own current
## ripple). `filtered_v` is the only voltage the control path may read; the true value goes in
## through update() and nothing else.
##
## COMPENSATION is Betaflight's vbat_sag_compensation: 0-100 %, default 0 = off. At p percent the
## motor output is scaled by 1 + p/100 * (reference / filtered - 1), never below 1 (a pack above the
## reference gets no extra cut) and, in MotorMixer, never past full output. `reference_v` is the
## full-charge resting voltage, the figure a pilot sets as the pack's full voltage.
##
## LABELLED GUESSES: 0.02 V RMS ADC noise, a 0.01 V ADC step and a 0.5 Hz filter. Betaflight's own
## defaults are in this region; no catalog data pins them.

const CONFIG_KEY := "vbat_sag_compensation"
const MAX_PERCENT := 100.0
const DEFAULT_NOISE_V := 0.02
const ADC_STEP_V := 0.01
const DEFAULT_CUTOFF_HZ := 0.5
const DEFAULT_SEED := 0x7BA7

var noise_v: float
var cutoff_hz: float
## What the FC reads. 0.0 until the first sample, which seeds the filter (a real board also
## starts from its first conversion, not from zero).
var filtered_v := 0.0
## Full-charge resting voltage of the fitted pack; 0.0 means "not configured" and disables
## compensation.
var reference_v := 0.0

var _rng := RandomNumberGenerator.new()
var _seed: int

func _init(p_reference_v: float = 0.0, p_noise_v: float = DEFAULT_NOISE_V,
		p_cutoff_hz: float = DEFAULT_CUTOFF_HZ, p_seed: int = DEFAULT_SEED) -> void:
	reference_v = p_reference_v
	noise_v = p_noise_v
	cutoff_hz = p_cutoff_hz
	_seed = p_seed
	_rng.seed = _seed

## Advances the sensor against the pack's TRUE voltage. Called by the aircraft, never by the FC.
func update(true_voltage_v: float, dt: float) -> float:
	var raw := true_voltage_v
	if noise_v > 0.0:
		raw += _rng.randfn(0.0, noise_v)
	raw = snappedf(raw, ADC_STEP_V)
	if filtered_v <= 0.0:
		filtered_v = raw
	else:
		filtered_v += (raw - filtered_v) * FlightLaw.lowpass_alpha(dt, cutoff_hz)
	return filtered_v

func reset() -> void:
	filtered_v = 0.0
	_rng.seed = _seed

## The 0-100 setting in the build's config block; absent or out of band reads as off.
static func percent(config: Dictionary) -> float:
	var stored := float(config.get(CONFIG_KEY, 0.0))
	return stored if stored > 0.0 and stored <= MAX_PERCENT else 0.0

## Refuses anything outside 0-100 and erases at zero, like RateSettings' setters.
static func set_percent(config: Dictionary, value: float) -> void:
	if value <= 0.0:
		config.erase(CONFIG_KEY)
		return
	if value > MAX_PERCENT:
		return
	config[CONFIG_KEY] = value

## The output multiplier for `percent_setting` given what the FC measures. 1.0 whenever the
## compensation is off, the sensor is unconfigured or has no reading yet.
static func scale(percent_setting: float, sensor: VbatSensor) -> float:
	if percent_setting <= 0.0 or sensor == null or sensor.reference_v <= 0.0 or sensor.filtered_v <= 0.0:
		return 1.0
	var full := sensor.reference_v / sensor.filtered_v
	return maxf(1.0, 1.0 + percent_setting / MAX_PERCENT * (full - 1.0))
