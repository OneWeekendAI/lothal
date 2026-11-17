class_name RateModeController
extends RefCounted
## THE inner loop. PID on angular rate, all three axes, every mode, no exceptions — and the
## only thing in the codebase that produces motor commands (physics.md §7).
##
## This is what a real flight controller is. It does not know or care whether the setpoints
## in front of it came from a pilot's sticks in acro or from a self-levelling outer loop in
## angle mode; it is handed a rate setpoint per axis and a gyro reading, and it closes the
## loop between them. Self-levelling is a front end, not a second control law.
##
## That distinction is the whole point of the restructure. Lothal previously had TWO laws
## producing motor commands from different inputs, and angle mode's yaw was a raw torque
## passthrough with no loop on it at all — so releasing the stick meant "stop pushing"
## rather than "stop rotating", and two taps cancelled only if their durations matched
## exactly, which human taps never do. Having two laws also meant a fix to one silently did
## not apply to the other, which is a standing bug source rather than a single bug.
##
## Gains act on a NORMALIZED rate error (a fraction of MAX_RATE_RAD_S), which is why they
## are small dimensionless numbers rather than raw rad/s gains.
##
## Roll and pitch were tuned against tests/test_rate_step_response.gd and
## tests/test_rate_mode_release.gd in physics.md §7's stated order: P raised until
## oscillation (~1.5, 24% overshoot), backed off, D added to kill bounce-back, a small I
## last for steady-state drift. Yaw is NOT a copy of them — see below.

const MAX_RATE_RAD_S := 13.962634   # 800 deg/s at full stick

## THE TUNE, in Betaflight's own numbers (P, I, D, F per axis), mapped to this loop's units by
## BetaflightPid's scale constants (betaflight_pid.gd). B1 RETUNE (2026-11-17).
##
## Why it changed: the old tune (P 2.3 / I 0.15, i.e. Betaflight P18 / I0.15) had an integral time
## of 15.3 s against Betaflight's 0.074 s, so nothing could remove the steady torque the rotor
## H-force puts on the hub-height lever (acro taps left 0.51 rad/s, whoops never levelled).
##
## How it was retuned, as a tuner on Betaflight 4.4 would: I and F at Betaflight's DEFAULTS (I80,
## F120); iterm_relax RP/setpoint on; then P and D found against the flip release and the step.
## - I80 with the old P bounced the flip release back 0.44 rad/s. A tenth of a second after the stop,
##   descending at 8 m/s through its own wake, the airframe takes a roll pulse; I integrates it and
##   then overshoots when it passes (ki = 0: no bounce at all). More P and D shrink the pulse.
## - D is bounded by the board: the noisiest catalog FC caps kd at 0.179, and the 8" cinelifter's
##   derived scale is 2.39, so the reference D must stay under 0.075 (D35) or the big frames get a
##   clipped D and stop responding like the reference (test_catalog_tuning).
## - P53 / D35 then left the bounce at -0.127 rad/s with relax at its 15 Hz default (bound 0.15).
##   iterm_relax_cutoff stays at Betaflight's 15 Hz for this 5" reference (owner decision 2026-11-17:
##   per-class BF guidance, RateTune.relax_cutoff_for). (An earlier 2 Hz gave -0.079 but is not a value
##   a 5" tuner would set.) At 15 Hz relax only holds I ~25 ms after a 360 deg/s stop, so the pulse at
##   ~150 ms is met by I; P53 I80 bounced -0.170. A tuner lowers I first (BF's own advice for a
##   bounce-back after flips): sweep (.test_runs/tp.gd) P/I/D multipliers at D35 (the board cap):
##   I80 -0.170, I40 -0.150, I32 -0.140, I28 -0.134, I24 -0.126; P56 I32 -0.128 (step 2.2%, 57 ms).
##   P58+ or D40+ also cut it but D clips on the X8 and P alone made it worse. Then the 65 mm whoop sagged out of its 5% band at 0.6 s on a 50 deg/s step (rolling 30 deg it slides, and rotor H torque grows faster than I32 follows): I32 settles at 600 ms, I37 600, I38 81 ms. Chosen: P56 I38 D35 F120 (flip -0.134).
##   Integral time 56*0.128/(38*0.978) = 0.19 s, still 65x faster than the pre-B1 15 s.
## Yaw: P70 (P53 was tried for the catalog yaw settle and broke the 500 deg/s yaw step, 521 ms vs 413; see HANDOVER) (yaw is slew-limited on big steps but not on small ones, where P buys the settling), D0
## and F120 as Betaflight's defaults, and I by Betaflight's integral time held against yaw's OWN loop
## (YAW_LOOP_SLOWDOWN below).
const BF_ROLL_PITCH := Vector4(56.0, 38.0, 35.0, 120.0)
const BF_YAW_P := 70.0
const BF_YAW_F := 120.0

## Roll and pitch's D gain, named: the FC details panel quotes what a board's noise floor costs at the
## installed D gain, and a panel that restated a literal would be a second opinion about the tune.
const ROLL_PITCH_KD := BetaflightPid.KD_PER_BF * 35.0

const REFERENCE_KP := Vector3(BetaflightPid.KP_PER_BF * BF_ROLL_PITCH.x, BetaflightPid.KP_PER_BF * BF_ROLL_PITCH.x,
	BetaflightPid.KP_PER_BF * BF_YAW_P)
## Yaw's closed loop is slower than roll's by alpha_roll*kp_roll / (alpha_yaw*kp_yaw) (the authority
## figures documented at pid_yaw below: 448.8 and 57.2 rad/s^2). Betaflight's integral time is set
## against a roll/pitch loop; copied onto yaw's slower loop it made a 50 deg/s yaw step overshoot 49%
## with a 475 ms tail. Yaw's I keeps roll's Ti/tau instead.
const YAW_LOOP_SLOWDOWN := (448.8 * BF_ROLL_PITCH.x) / (57.2 * BF_YAW_P)
const REFERENCE_KI := Vector3(BetaflightPid.KI_PER_BF * BF_ROLL_PITCH.y, BetaflightPid.KI_PER_BF * BF_ROLL_PITCH.y,
	BetaflightPid.KP_PER_BF * BF_YAW_P / (BF_ROLL_PITCH.x / BF_ROLL_PITCH.y * BetaflightPid.KP_PER_BF / BetaflightPid.KI_PER_BF * YAW_LOOP_SLOWDOWN))
const REFERENCE_KFF := Vector3(BetaflightPid.KFF_PER_BF * 120.0, BetaflightPid.KFF_PER_BF * 120.0,
	BetaflightPid.KFF_PER_BF * BF_YAW_F)
const REFERENCE_KD := Vector3(ROLL_PITCH_KD, ROLL_PITCH_KD, 0.0)

var pid_roll := BetaflightPid.new(REFERENCE_KP.x, REFERENCE_KI.x, REFERENCE_KD.x, REFERENCE_KFF.x, true)
var pid_pitch := BetaflightPid.new(REFERENCE_KP.y, REFERENCE_KI.y, REFERENCE_KD.y, REFERENCE_KFF.y, true)

## Yaw is NOT roll's gains, and sharing them was never a neutral choice.
##
## Yaw torque comes from propeller DRAG (k_q) rather than from thrust differential across an
## arm, and yaw inertia is the LARGEST of the three axes on a flat quad. Measured on the
## reference build in tests/test_yaw_authority.gd, at full deflection:
##
##   yaw:  0.1316 N*m / I_yy 0.002302 =  57.2 rad/s^2
##   roll: 0.5119 N*m / I_zz 0.001141 = 448.8 rad/s^2      yaw is 0.127 of roll
##
## Turn that into a loop gain. A command of 1.0 buys 57.2 rad/s^2 on yaw, and a normalized
## rate error of 1.0 is MAX_RATE_RAD_S = 13.96 rad/s, so the closed loop is
## rate_dot = (57.2 / 13.96) * kp * error = 4.10 * kp * error, a first-order response with
## time constant 1 / (4.10 * kp). The same arithmetic on roll gives 32.15 * kp, so roll at
## kp = 2.3 runs a 13.5 ms time constant — and yaw at those same gains runs 106 ms, nearly
## eight times slower. That is the whole of "A feels stronger than D and neither settles":
## not asymmetry, but a yaw loop far too slow to close before the pilot has moved on.
##
## kp = 6.0 puts yaw at a 41 ms time constant — three times roll's rather than eight, which
## is honest to yaw genuinely having less authority without pretending it does not.
##
## It is deliberately not higher. A 500 deg/s yaw step is SLEW-LIMITED, not gain-limited:
## reaching 8.7 rad/s at 57.2 rad/s^2 takes 145 ms with the command pinned at full, and no
## tuning beats that. Sweeping kp from 6.5 to 9.0 moved the measured settling time by 2 ms
## (261 -> 259) and bought nothing but more gain multiplying gyro noise on the axis with the
## least authority to spare. Above about 6 the loop is waiting on the airframe, so 6 is where
## it stops.
## ki holds the same integral time constant as roll (kp/ki = 15.3 s), which is the standard
## way to move a PID onto a weaker plant: the ratio is what sets the character, the absolute
## values follow the authority.
## kd is ZERO, matching Betaflight's own yaw default. Yaw's plant is dominated by rotor drag
## and is already damped; there is no fast resonance for D to catch, so all it would do is
## amplify gyro noise on the axis with the least authority to spare.
## iterm_relax = RPY (a Betaflight option): with relax on roll/pitch only, a small yaw step on the
## reference (unsaturated) wound I through the rise and overshot 7.6%, while big frames, slew-limited
## at their output clamp, had I frozen by anti-windup and overshot ~3%: the catalog stopped responding
## alike. Relax on yaw freezes I through every build's rise the same way.
var pid_yaw := BetaflightPid.new(REFERENCE_KP.z, REFERENCE_KI.z, REFERENCE_KD.z, REFERENCE_KFF.z, true)

## anti_gravity (Betaflight 4.4: anti_gravity_gain 80, cutoff 5 Hz): |d throttle/dt| through a
## PT2 at 5 Hz, times (1 - throttle)^2, times gain/100 -> the I accelerator. The point is that a
## throttle punch changes every motor's torque at once and the I term must catch up fast.
const ANTI_GRAVITY_GAIN := 0.8
const ANTI_GRAVITY_CUTOFF_HZ := 5.0
var anti_gravity_enabled := true
var _ag_last_throttle := -1.0
var _ag_lpf1 := 0.0
var _ag_lpf2 := 0.0
## Last tick's motor-mix range for the iterm_windup attenuation (0..1, 1 = saturated).
var _mix_range := 0.0

## The tune in force, or null for the hand tune above.
##
## The default is the hand tune rather than "derive one", deliberately, and it is what keeps
## RateModeController.new() meaning what it has always meant: a bare controller is the REFERENCE
## aircraft's controller, which is the fixture every control test in this repo is written against.
## Deriving a tune requires a Build, and the objects that have one — DroneCore's owner, Lab — hand
## it in through adopt_tune(). Nothing reaches for a catalog from in here.
var tune: RateTune = null


## Retunes the three axes in place. In place rather than by construction, because the integrator
## state is holding the aircraft trimmed and rebuilding the controllers would dump it — the same
## reason FlightController keeps its rate loop across a mode change.
##
## Sim never calls this. Lab derives the tune, Lab persists the builder's overrides, and the
## aircraft arrives in the field already tuned (labs-and-sim.md §1: Sim authors nothing).
func adopt_tune(p_tune: RateTune) -> void:
	tune = p_tune
	if p_tune == null:
		return
	pid_roll.kp = p_tune.kp.x
	pid_roll.ki = p_tune.ki.x
	pid_roll.kd = p_tune.kd.x
	pid_pitch.kp = p_tune.kp.y
	pid_pitch.ki = p_tune.ki.y
	pid_pitch.kd = p_tune.kd.y
	pid_yaw.kp = p_tune.kp.z
	pid_yaw.ki = p_tune.ki.z
	pid_yaw.kd = p_tune.kd.z
	pid_roll.kff = p_tune.kff.x
	pid_pitch.kff = p_tune.kff.y
	pid_yaw.kff = p_tune.kff.z
	for pid in [pid_roll, pid_pitch, pid_yaw]:
		pid.relax_cutoff_hz = p_tune.relax_cutoff_hz


## The acro front end: all three sticks ARE rate setpoints, and the outer loop is simply
## absent. Named as a function rather than left inline so both front ends read the same way
## at the call site — see FlightController, where the mode switch chooses between this and
## AngleModeController.rate_setpoint and changes nothing else.
static func rate_setpoint(rc: Dictionary) -> Vector3:
	return Vector3(rc.roll, rc.pitch, rc.yaw)

## The build's `config` decision block, for the one value of it the inner loop needs: which way
## each motor turns (design §5). Empty is today's constants, so a bare controller — the reference
## every oracle in this project is defined against — is unchanged.
var config: Dictionary = {}

## setpoint_normalized — Vector3(roll, pitch, yaw), each -1..1 as a fraction of
##   MAX_RATE_RAD_S, whatever produced it.
## gyro_rate_rad_s — the SENSOR's body-frame reading (DroneCore.gyro), never ground truth.
## vbat — the FC's battery-voltage sensor (DroneCore.vbat), or null for no compensation.
func update(setpoint_normalized: Vector3, gyro_rate_rad_s: Vector3, throttle: float, dt: float, vbat: VbatSensor = null) -> Dictionary:
	# One expression of the body-XYZ -> roll/pitch/yaw mapping, borrowed from the sensor that
	# owns it. Writing it out by hand here is how the two old control laws came to disagree.
	var measured := Gyro.contract_rates(gyro_rate_rad_s) / MAX_RATE_RAD_S

	# PIDController clamps its own output and stops integrating while it is clamped, so
	# there is no clampf here — a second clamp outside the controller would hide the
	# saturation from the anti-windup that needs to see it.
	var boost := _anti_gravity(throttle, dt)
	var roll_cmd := pid_roll.update(setpoint_normalized.x, measured.x, dt, _mix_range, boost)
	var pitch_cmd := pid_pitch.update(setpoint_normalized.y, measured.y, dt, _mix_range, boost)
	var yaw_cmd := pid_yaw.update(setpoint_normalized.z, measured.z, dt, _mix_range, boost)
	_mix_range = mix_range(roll_cmd, pitch_cmd, yaw_cmd, config)

	var vbat_scale := VbatSensor.scale(VbatSensor.percent(config), vbat)
	return MotorMixer.mix(throttle, roll_cmd, pitch_cmd, yaw_cmd, config, vbat_scale)

## The motor-mix range Betaflight's iterm_windup reads: the spread of the per-motor deltas
## (MotorMixer's MIX_GAIN times the axis commands), and, because the sim clamps each axis at its
## output_limit (pidsum_limit) before the mixer, an axis pinned at that clamp counts as saturated too.
static func mix_range(r: float, p: float, y: float, p_config: Dictionary = {}) -> float:
	var spin := MotorLayout.spin_map(p_config)
	var front := [false, true, false, true]
	var right := [true, true, false, false]
	var lo := INF
	var hi := -INF
	for i in 4:
		var d: float = MotorMixer.MIX_GAIN * ((p if front[i] else -p) + (-r if right[i] else r)
			+ y * float(spin[MotorLayout.MOTOR_NAMES[i]]))
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var axis_sat := maxf(absf(r), maxf(absf(p), absf(y)))
	return maxf(hi - lo, axis_sat)

func _anti_gravity(throttle: float, dt: float) -> float:
	if _ag_last_throttle < 0.0 or dt <= 0.0:
		_ag_last_throttle = throttle
		return 0.0
	var deriv := absf(throttle - _ag_last_throttle) / dt
	_ag_last_throttle = throttle
	var k := BetaflightPid._pt1_k(ANTI_GRAVITY_CUTOFF_HZ * 1.553774, dt)   # PT2 stage cutoff
	_ag_lpf1 += k * (deriv - _ag_lpf1)
	_ag_lpf2 += k * (_ag_lpf1 - _ag_lpf2)
	if not anti_gravity_enabled:
		return 0.0
	var inv := 1.0 - clampf(throttle, 0.0, 1.0)
	return _ag_lpf2 * inv * inv * ANTI_GRAVITY_GAIN * 10.0

func set_mechanisms(relax: bool, windup: bool, ff: bool) -> void:
	for pid in [pid_roll, pid_pitch, pid_yaw]:
		pid.iterm_relax_enabled = relax
		pid.anti_windup_enabled = windup
		pid.feedforward_enabled = ff

func reset() -> void:
	_mix_range = 0.0
	_ag_last_throttle = -1.0
	_ag_lpf1 = 0.0
	_ag_lpf2 = 0.0
	pid_roll.reset()
	pid_pitch.reset()
	pid_yaw.reset()
