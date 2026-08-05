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

## Roll and pitch's D gain, named rather than left as a literal in two constructors.
##
## A READ SEAM, not a tuning change: the value is exactly what it was. It is named because the
## FC details panel quotes what a board's noise floor costs at the installed D gain, and a panel
## that restated 0.042 would be a second opinion about the tune the day anyone changed it.
const ROLL_PITCH_KD := 0.042

## THE HAND TUNE, per axis, as Vector3(roll, pitch, yaw) — the gains below, named so that RateTune
## has a reference to scale FROM without restating them.
##
## Another read seam, and the same reasoning as ROLL_PITCH_KD's: these values are exactly what they
## were, and the derivation in rate_tune.gd is normalised so that the aircraft they were found on
## reproduces them exactly. What changed is that a build which is NOT that aircraft no longer gets
## them unaltered.
const REFERENCE_KP := Vector3(2.3, 2.3, 6.0)
const REFERENCE_KI := Vector3(0.15, 0.15, 0.39)
const REFERENCE_KD := Vector3(ROLL_PITCH_KD, ROLL_PITCH_KD, 0.0)

var pid_roll := PIDController.new(2.3, 0.15, ROLL_PITCH_KD)
var pid_pitch := PIDController.new(2.3, 0.15, ROLL_PITCH_KD)

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
var pid_yaw := PIDController.new(6.0, 0.39, 0.0)

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


## The acro front end: all three sticks ARE rate setpoints, and the outer loop is simply
## absent. Named as a function rather than left inline so both front ends read the same way
## at the call site — see FlightController, where the mode switch chooses between this and
## AngleModeController.rate_setpoint and changes nothing else.
static func rate_setpoint(rc: Dictionary) -> Vector3:
	return Vector3(rc.roll, rc.pitch, rc.yaw)

## setpoint_normalized — Vector3(roll, pitch, yaw), each -1..1 as a fraction of
##   MAX_RATE_RAD_S, whatever produced it.
## gyro_rate_rad_s — the SENSOR's body-frame reading (DroneCore.gyro), never ground truth.
func update(setpoint_normalized: Vector3, gyro_rate_rad_s: Vector3, throttle: float, dt: float) -> Dictionary:
	# One expression of the body-XYZ -> roll/pitch/yaw mapping, borrowed from the sensor that
	# owns it. Writing it out by hand here is how the two old control laws came to disagree.
	var measured := Gyro.contract_rates(gyro_rate_rad_s) / MAX_RATE_RAD_S

	# PIDController clamps its own output and stops integrating while it is clamped, so
	# there is no clampf here — a second clamp outside the controller would hide the
	# saturation from the anti-windup that needs to see it.
	var roll_cmd := pid_roll.update(setpoint_normalized.x, measured.x, dt)
	var pitch_cmd := pid_pitch.update(setpoint_normalized.y, measured.y, dt)
	var yaw_cmd := pid_yaw.update(setpoint_normalized.z, measured.z, dt)

	return MotorMixer.mix(throttle, roll_cmd, pitch_cmd, yaw_cmd)

func reset() -> void:
	pid_roll.reset()
	pid_pitch.reset()
	pid_yaw.reset()
