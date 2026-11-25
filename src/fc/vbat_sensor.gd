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
## COMPENSATION is Betaflight's vbat_sag_compensation: 0-100 %, default 0 = off. Betaflight
## (mixer.c) attenuates the motor output RANGE by
##     a(v) = p/100 * clamp(v_cell - vbat_min_cell, 0, full - min) / full
## with full = vbat_full_cell_voltage and v_cell the filtered pack voltage per cell, so a full pack
## flies at (1 - a_full) of the range and a pack at or below the min cell voltage at 100 %. The sim
## keeps "100 % output = a full pack" (nothing tuned on a full pack moves), so `scale` is Betaflight's
## output relative to a full pack: (1 - a(v)) / (1 - a(full)). B2/P6: that is clamped exactly as
## Betaflight's is: 1 at or above the full cell voltage, full / min (1.24 at 100 %) at or below the
## min cell voltage. The reference is cells x full-cell voltage, not the pack's resting voltage.
## B2/P5: MotorMixer applies it to the whole mix BEFORE desaturation, as Betaflight scales the
## output range, so the attitude differential survives at high throttle.
##
## LABELLED GUESSES: 0.02 V RMS ADC noise, a 0.01 V ADC step and a 0.5 Hz filter. Betaflight's own
## defaults are in this region; no catalog data pins them.

const CONFIG_KEY := "vbat_sag_compensation"
const MAX_PERCENT := 100.0
const DEFAULT_NOISE_V := 0.02
const ADC_STEP_V := 0.01
const DEFAULT_CUTOFF_HZ := 0.5
const DEFAULT_SEED := 0x7BA7
## Betaflight defaults (battery.c): vbat_full_cell_voltage 4.10 V, vbat_min_cell_voltage 3.30 V.
const BF_FULL_CELL_V := 4.10
const BF_MIN_CELL_V := 3.30

var noise_v: float
var cutoff_hz: float
## FlightLaw.lowpass_alpha(dt, cutoff_hz), kept while neither changes.
var _alpha_dt := -1.0
var _alpha_cutoff_hz := -1.0
var _alpha := 0.0
## What the FC reads. 0.0 until the first sample, which seeds the filter (a real board also
## starts from its first conversion, not from zero).
var filtered_v := 0.0
## Cell count of the fitted pack; 0 means "not configured" and disables compensation.
var cells := 0
var full_cell_v := BF_FULL_CELL_V
var min_cell_v := BF_MIN_CELL_V
## The compensation reference, cells x full-cell voltage (Betaflight's vbatFull for the pack).
var reference_v: float:
	get:
		return float(cells) * full_cell_v

var _rng := RandomNumberGenerator.new()
var _seed: int

func _init(p_cells: int = 0, p_noise_v: float = DEFAULT_NOISE_V,
		p_cutoff_hz: float = DEFAULT_CUTOFF_HZ, p_seed: int = DEFAULT_SEED) -> void:
	cells = p_cells
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
		if dt != _alpha_dt or cutoff_hz != _alpha_cutoff_hz:
			_alpha_dt = dt
			_alpha_cutoff_hz = cutoff_hz
			_alpha = FlightLaw.lowpass_alpha(dt, cutoff_hz)
		filtered_v += (raw - filtered_v) * _alpha
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
	if percent_setting <= 0.0 or sensor == null or sensor.cells <= 0 or sensor.filtered_v <= 0.0:
		return 1.0
	var full := sensor.full_cell_v
	var span := maxf(full - sensor.min_cell_v, 0.0)
	var p := minf(percent_setting, MAX_PERCENT) / MAX_PERCENT
	var v_cell := sensor.filtered_v / float(sensor.cells)
	var att := p * clampf(v_cell - sensor.min_cell_v, 0.0, span) / full
	var att_full := p * span / full
	return (1.0 - att) / (1.0 - att_full)
