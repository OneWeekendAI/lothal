extends RefCounted
## The self-levelling OUTER loop (physics.md §7). It produces rate setpoints, not motor
## commands — a proportional controller on attitude error whose output is handed to
## RateModeController, the one inner loop, exactly as the pilot's sticks are in acro.
##
## This class used to be a second, parallel control law: it ran its own P+D on angle,
## called MotorMixer itself, and passed the yaw stick through to the mixer as a RAW TORQUE
## with no loop on it at all. Constant torque means yaw rate accelerates while the stick is
## held, and on release nothing commands it back to zero — only aerodynamic drag. That is
## the whole of the reported "tap A then D and it never settles". The fix is not a
## constant; it is that yaw is rate-controlled in every mode, which is how real flight
## controllers work and what makes releasing the stick mean "stop rotating".
##
## The D term this class used to carry is gone. Damping is the inner loop's job now, and
## running a second derivative term on top of it would be two controllers fighting over
## the same physics.

const MAX_ANGLE_RAD := 0.5235988   # 30 degrees at full stick

## Attitude error (rad) -> rate setpoint (rad/s), so its units are 1/s and it sets how
## briskly the aircraft returns to level. At full stick (30 deg = 0.524 rad) it asks for
## 5.2 rad/s, ~300 deg/s, which is a firm but not violent snap to a bank angle.
##
## ---------------------------------------------------------------------------
## AND IT DOES NOT SCALE WITH THE AIRCRAFT, WHICH IS A RESULT RATHER THAN AN OVERSIGHT
## ---------------------------------------------------------------------------
##
## RateTune scales the INNER loop's three gains per axis with the plant, because a rate loop closes
## directly on angular acceleration and one gain set across a 30x spread of it is a tune that is
## correct for one aircraft. The obvious next question is whether this gain needs the same
## treatment. It does not, and the reason is exactly what the scaling law holds constant.
##
## This is a cascade. The outer loop does not see the airframe; it sees the INNER LOOP, whose job
## is to deliver whatever rate it is asked for. What it can be told about that inner loop is its
## closed-loop time constant — and RateTune's whole law is that tau is held at the reference
## aircraft's value on every build in the catalog. So the plant this gain closes on is already
## invariant. Scaling it would be correcting for a variation that the slice below it has removed.
##
## Which is a real dependency and worth stating plainly: if anyone ever changes RateTune to hold
## something other than tau constant, this constant stops being safe, and this comment is where
## they should find out. tests/test_catalog_tuning.gd flies angle mode on the two extremes of the
## catalog for that reason — the recovery-to-level check has the outer loop in the path, so a law
## that stopped equalising the inner one would show up here as an aircraft that returns to level
## slowly, or oscillates about it, at one end of the catalog and not the other.
##
## The clamp below is what makes this robust rather than merely true. Even on an aircraft whose
## inner loop cannot keep up, the outer one cannot demand more than MAX_LEVEL_RATE_RAD_S, so the
## worst case is a slow recovery rather than a saturated inner loop.
const LEVEL_P := 10.0

## The clamp matters more than the gain. An outer loop that can demand unbounded rate makes
## the inner loop saturate at large attitude errors — and a saturated inner loop is one that
## has stopped tracking, so the aircraft feels unpredictable exactly when it is furthest
## from level and the pilot most needs it to behave. 400 deg/s is half the inner loop's
## 800 deg/s ceiling, which leaves the rate loop headroom to actually track the demand.
const MAX_LEVEL_RATE_RAD_S := 6.981317   # 400 deg/s

## rc = {roll: -1..1, pitch: -1..1, yaw: -1..1, throttle: 0..1}
## Returns Vector3(roll, pitch, yaw) rate setpoints, normalized against
## RateModeController.MAX_RATE_RAD_S — the same units the acro front end produces, because
## they feed the same loop.
static func rate_setpoint(orientation: Quaternion, rc: Dictionary) -> Vector3:
	var euler := orientation.get_euler(EULER_ORDER_YXZ)
	var pitch_current := euler.x    # rotation about +X; +Pitch = nose up (coordinate contract)
	var roll_current := -euler.z    # rotation about -Z; +Roll = right side down (contract)

	var pitch_error: float = (rc.pitch * MAX_ANGLE_RAD) - pitch_current
	var roll_error: float = (rc.roll * MAX_ANGLE_RAD) - roll_current

	var pitch_rate_sp := clampf(LEVEL_P * pitch_error, -MAX_LEVEL_RATE_RAD_S, MAX_LEVEL_RATE_RAD_S)
	var roll_rate_sp := clampf(LEVEL_P * roll_error, -MAX_LEVEL_RATE_RAD_S, MAX_LEVEL_RATE_RAD_S)

	# Yaw: the stick IS a rate setpoint, handed straight through. Angle mode deliberately
	# does NOT lock absolute heading — no real flight controller does in this mode, and a
	# heading lock would fight the pilot every time they pointed the aircraft somewhere.
	# What it does now, and did not before, is close a RATE loop on yaw: stick centred means
	# "rate zero", not "no torque".
	return Vector3(
		roll_rate_sp / RateModeController.MAX_RATE_RAD_S,
		pitch_rate_sp / RateModeController.MAX_RATE_RAD_S,
		rc.yaw)
