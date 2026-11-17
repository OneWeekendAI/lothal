class_name BetaflightPid
extends RefCounted
## One rate-loop axis with Betaflight 4.4/4.5 semantics (pid.c), in this sim's normalised units.
##
## UNITS. Betaflight's PID works on deg/s and outputs "pidSum" where 1000 = a motor-mix value of 1.0
## (mixer.c divides by PID_MIXER_SCALING). Here the error is a fraction of MAX_RATE_RAD_S (800 deg/s)
## and the output is a fraction of full command, which MotorMixer turns into +/-MIX_GAIN (0.2) of
## motor range per motor. So a sim command c is a Betaflight mix value of 0.2 c, i.e. pidSum = 200 c,
## and Betaflight's own scale constants map as (800 deg/s per normalised unit, /200 per pidSum):
##
##     kp = PTERM_SCALE  0.032029 * P * 4.0      = 0.128116 * P
##     ki = ITERM_SCALE  0.244381 * I * 4.0      = 0.977524 * I
##     kd = DTERM_SCALE  0.000529 * D * 4.0      = 0.002116 * D
##     kff = FEEDFORWARD_SCALE 0.013754 * F/100 * 4.0 = 0.00055016 * F
##
## The ratios are what carry across airframes: Betaflight's defaults (P45 I80 D40 F120) give an
## integral time kp/ki = 0.0737 s, a derivative time kd/kp = 0.0147 s and a feed-forward time
## kff/kp = 0.0115 s. RateTune holds those times and scales the absolute gains per build.
##
## What each term does, all as pid.c:
## - P on error, D on MEASUREMENT (no derivative kick), FF on the setpoint's rate of change.
## - I accumulates the error times a relax factor (iterm_relax SETPOINT type; this sim runs RPY, cutoff RELAX_CUTOFF_HZ):
##   factor = max(0, 1 - |setpoint - PT1(setpoint)| / 40 deg/s). During a fast stick move the
##   loop is BEHIND the stick by design, and integrating that lag is what makes a flip bounce back
##   on release; relax freezes I exactly while the stick moves and releases it once the stick stops.
## - I growth is attenuated as the motor-mix range approaches saturation (iterm_windup 85: the
##   factor runs from 1 at range 0.85 to 0 at range 1.0), and the stored I is clamped to iterm_limit
##   (400 of pidsum_limit 500, i.e. 0.8 of the output limit).
## - anti_gravity multiplies I's accumulation rate by (1 + accelerator) on fast throttle moves.

## The scale constants above, per Betaflight unit.
const KP_PER_BF := 0.032029 * 4.0
const KI_PER_BF := 0.244381 * 4.0
const KD_PER_BF := 0.000529 * 4.0
const KFF_PER_BF := 0.013754 / 100.0 * 4.0

## Betaflight's ITERM_RELAX_SETPOINT_THRESHOLD, 40 deg/s, normalised.
const RELAX_THRESHOLD := 40.0 / 800.0
## iterm_relax_cutoff for the 5" reference: 5 Hz (B1 final, 2026-11-17). BF 4.2+ ships 15 (the race value);
## freestyle tunes lower it against bounce-back. At 15 the reference could not reach <= 5% overshoot on a
## 50 deg/s step without losing the I the acro taps need; at 10 it sat at 4.8-5.5%, ON the 5% band, so
## every catalog frame's settle time jumped by its peak. At 5 Hz P50 I20 is 3.2% with a flat tail. RateTune.relax_cutoff_for picks
## the per-class value (whoop 25, 5" and 7" 10, 8-10" and cinelifters 5; estimates from BF guidance).
const RELAX_CUTOFF_HZ := 5.0
## iterm_windup 85 -> itermWindupPointInv = 1 / (1 - 0.85).
const WINDUP_POINT := 0.85
## iterm_limit 400 of pidsum_limit 500.
const ITERM_LIMIT_FRACTION := 0.8

var kp: float
var ki: float
var kd: float
var kff: float
var output_limit: float = 1.0
## Whether relax applies on this axis (RP mode: roll/pitch only; RPY: all three).
var relax_axis: bool = true
## iterm_relax_cutoff (Hz); a per-build tuner knob in Betaflight.
var relax_cutoff_hz := RELAX_CUTOFF_HZ

## Mutation seams (the tests switch each mechanism off to prove it is what they measure).
var iterm_relax_enabled := true
var anti_windup_enabled := true
var feedforward_enabled := true
var dterm_filter_enabled := true

var _integral: float = 0.0   # the I TERM, in output units (as pidData[axis].I)
var _last_measured: float = 0.0
var _last_setpoint: float = 0.0
var _setpoint_lpf: float = 0.0
var _ff_lpf: float = 0.0
var _has_last: bool = false

## Feed-forward derivative smoothing (stands in for Betaflight's RC smoothing of the setpoint
## before feed-forward; the sim's stick arrives as a step every tick, not at an RC link rate).
const FF_SMOOTH_HZ := 30.0

## D-term lowpass, Betaflight 4.4 defaults: dterm_lpf1 PT1 dynamic 75-150 Hz (its floor, 75, is what a hover at
## low throttle runs; held there, a labelled simplification) then dterm_lpf2 PT1 150 Hz. Without it the D term
## differentiates raw gyro noise straight onto the motors: the five_inch hover chattered at 1.1 percent command
## sd and drew 7.6 percent over the hover model (B1, sr4 hover model); with sensor noise off the gap was 1.5 percent.
const DTERM_LPF1_HZ := 75.0
const DTERM_LPF2_HZ := 150.0
var _d_lpf1: float = 0.0
var _d_lpf2: float = 0.0

func _init(p_kp: float, p_ki: float, p_kd: float, p_kff: float = 0.0, p_relax_axis: bool = true) -> void:
	kp = p_kp
	ki = p_ki
	kd = p_kd
	kff = p_kff
	relax_axis = p_relax_axis

## mix_range: last tick's motor-mix range (0..1, 1 = saturated). ki_boost: anti-gravity accelerator.
func update(target: float, measured: float, dt: float, mix_range: float = 0.0, ki_boost: float = 0.0) -> float:
	# Filter state starts at rest (zero stick), as Betaflight's does at arming: a controller handed a
	# deflected stick on its first tick sees that as a stick MOVE, for relax and feed-forward alike.
	if not _has_last:
		_last_measured = measured
	var error := target - measured

	# iterm_relax (setpoint HPF).
	var k_lpf := _pt1_k(relax_cutoff_hz, dt)
	_setpoint_lpf += k_lpf * (target - _setpoint_lpf)
	var i_error := error
	if iterm_relax_enabled and relax_axis:
		var hpf := absf(target - _setpoint_lpf)
		i_error *= maxf(0.0, 1.0 - hpf / RELAX_THRESHOLD)

	# Anti-windup at motor saturation (iterm_windup).
	var dyn := 1.0
	if anti_windup_enabled:
		dyn = clampf((1.0 - mix_range) / (1.0 - WINDUP_POINT), 0.0, 1.0)
	var i_limit := ITERM_LIMIT_FRACTION * output_limit
	_integral = clampf(_integral + ki * (1.0 + ki_boost) * dyn * i_error * dt, -i_limit, i_limit)

	var d_term := 0.0
	var ff := 0.0
	if _has_last and dt > 0.0:
		var d_raw := -(measured - _last_measured) / dt
		if dterm_filter_enabled:
			_d_lpf1 += _pt1_k(DTERM_LPF1_HZ, dt) * (d_raw - _d_lpf1)
			_d_lpf2 += _pt1_k(DTERM_LPF2_HZ, dt) * (_d_lpf1 - _d_lpf2)
			d_raw = _d_lpf2
		d_term = kd * d_raw
		var sp_rate := (target - _last_setpoint) / dt
		_ff_lpf += _pt1_k(FF_SMOOTH_HZ, dt) * (sp_rate - _ff_lpf)
		if feedforward_enabled:
			ff = kff * _ff_lpf
	_last_measured = measured
	_last_setpoint = target
	_has_last = true
	return clampf(kp * error + _integral + d_term + ff, -output_limit, output_limit)

## Betaflight's pt1FilterGain.
static func _pt1_k(f_cut: float, dt: float) -> float:
	var rc := 1.0 / (TAU * f_cut)
	return dt / (rc + dt)

func reset() -> void:
	_integral = 0.0
	_ff_lpf = 0.0
	_d_lpf1 = 0.0
	_d_lpf2 = 0.0
	_setpoint_lpf = 0.0
	_last_setpoint = 0.0
	_has_last = false
