extends RefCounted
## Standard X-quad mixer: turns normalized throttle + roll/pitch/yaw correction commands
## into a per-motor throttle command. This is the inverse of motor_layout.gd's
## torque_from_motor — it must move motors in the direction that PRODUCES the requested
## sign of roll/pitch/yaw under the coordinate contract, not the direction that looks
## obvious from the motor's own position. See test_torque_signs.gd for the hand-check
## this is built from: extra right-motor thrust yields -Roll, so +roll_cmd DECREASES
## right motors; extra rear-motor thrust yields -Pitch, so +pitch_cmd DECREASES rear motors.
##
## Called from exactly one place: RateModeController, the single inner rate loop.
##
## ## Saturation, and why the naive clamp was a direction-dependent bug
##
## This used to build each motor's command and clamp it to [0, 1] independently. When a
## motor clipped, the requested attitude torque was silently NOT delivered — and how much
## was lost depended on which motors clipped, which depends on the SIGN of the command and
## on where the collective throttle happened to sit. Ask for the same roll authority at 5%
## throttle and at 95% and you got two different aircraft, neither of them the one that was
## tuned. That is a plant asymmetry manufactured by the mixer.
##
## What real firmware does about this is what Betaflight calls AIRMODE, and it is a choice
## about what to sacrifice. Attitude authority and collective throttle cannot both be
## honoured once the commands do not fit in [0, 1]. Attitude wins:
##
##   1. Build the per-motor attitude DELTAS first, with no throttle in them.
##   2. If their spread exceeds the full actuator range, scale all three axes by ONE common
##      factor. One factor rather than per-axis clipping, because that preserves the
##      DIRECTION of the requested torque vector even when its magnitude cannot be met — a
##      roll-and-yaw demand clipped per-axis becomes a DIFFERENT demand, which is how an
##      aircraft ends up doing something the pilot did not ask for at full stick.
##   3. Shift the collective throttle until the deltas fit. The attitude correction is
##      delivered in full; the collective is whatever is left.
##
## Step 2 is a guard rather than a hot path, and it is worth being explicit about why. The
## three mix rows are mutually orthogonal sign patterns, so a full-deflection demand on all
## three axes at once does NOT stack to 3 * MIX_GAIN on every motor: exactly one motor sees
## all three agree (+3) and the other three see +1 each with two cancelling, giving a spread
## of 4 * MIX_GAIN = 0.8, comfortably inside the range. Combined with PIDController clamping
## its own output to +/-1, the scale step never fires at MIX_GAIN = 0.2. It fires the moment
## anyone raises MIX_GAIN past 0.25, which is exactly when silently changing the torque
## direction would be hardest to notice.
##
## THE TRADEOFF, stated plainly: at large stick deflections the aircraft no longer holds the
## throttle it was given. Full three-axis deflection confines the collective to [0.2, 0.4].
## Hover at 29% sits inside that window and is untouched — which is why none of the
## project's oracles moved — but a pilot at 95% throttle throwing the aircraft around gets
## 40%, and drops. That is the correct sacrifice for a freestyle quad, since losing attitude
## authority mid-flip is how you meet the ground. It does mean airmode and altitude hold are
## in direct tension, and an altitude controller added later must be built knowing the mixer
## can overrule it. The alternative — honouring throttle and dropping attitude — is what the
## old code did by accident, and it is the behaviour the pilot reported as the aircraft not
## going where it was pointed.

const MIX_GAIN := 0.2   # fraction of throttle range given to attitude authority

## `config` is the build's `config` decision block. Spin direction is read through
## MotorLayout.spin_map() — the SAME accessor torque_from_motor() uses, per design §5.1: the mixer
## that commands a yaw and the model that produces its torque cannot be allowed to hold two
## different opinions about which way a motor turns.
static func mix(throttle: float, roll_cmd: float, pitch_cmd: float, yaw_cmd: float, config: Dictionary = {}) -> Dictionary:
	var spin := MotorLayout.spin_map(config)
	# Step 1: attitude only. Throttle is deliberately not in here yet — mixing it in first
	# is what makes saturation depend on where the throttle sits.
	var delta := {}
	var lo := INF
	var hi := -INF
	for name in MotorLayout.MOTOR_NAMES:
		var d := pitch_cmd * MIX_GAIN * (1.0 if MotorLayout.IS_FRONT[name] else -1.0)
		d += roll_cmd * MIX_GAIN * (-1.0 if MotorLayout.IS_RIGHT[name] else 1.0)
		d += yaw_cmd * MIX_GAIN * float(spin[name])
		delta[name] = d
		lo = minf(lo, d)
		hi = maxf(hi, d)

	# Step 2: one common scale factor across all three axes, so the torque VECTOR keeps its
	# direction. Inactive at MIX_GAIN = 0.2 — see the header — and live from 0.25 up.
	var spread := hi - lo
	if spread > 1.0:
		var scale := 1.0 / spread
		for name in MotorLayout.MOTOR_NAMES:
			delta[name] *= scale
		lo *= scale
		hi *= scale

	# Step 3: the collective goes wherever it must for the attitude deltas to fit. With the
	# spread guaranteed <= 1, the window [-lo, 1-hi] is never empty, so this always has an
	# answer and every motor lands inside [0, 1] by construction.
	var collective := clampf(throttle, -lo, 1.0 - hi)

	var out := {}
	for name in MotorLayout.MOTOR_NAMES:
		# The clamp is now only mopping up float error; step 3 already guarantees the range.
		out[name] = clampf(collective + delta[name], 0.0, 1.0)
	return out
