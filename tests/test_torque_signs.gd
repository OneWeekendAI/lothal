class_name TestTorqueSigns
extends RefCounted
## Test 7 from week1.md Day 2: motor 1 (rear-right) alone, thrust increased above hover,
## must produce nonzero roll, pitch, and yaw with hand-checkable signs.
##
## Hand check: M1 sits at the rear-right. Extra lift there should tip the nose down
## (rear rises) and lift the right side (right rises). "Right rises" is the opposite of
## "+Roll = right side down", so roll_signed must be NEGATIVE. "Rear rises" means the
## nose points down, the opposite of "+Pitch = nose up", so pitch_signed must be NEGATIVE.
## Yaw sign depends only on M1's assigned spin direction (motor_layout.gd) and just needs
## to be nonzero and consistent with that assignment.

static func run() -> Array:
	var results: Array = []

	var k_t := ReferenceBuild.propeller_k_t()
	var k_q := ReferenceBuild.propeller_k_q()
	var extra_rpm := 2000.0   # small delta above hover RPM, for a clean linearized check
	var thrust_delta_n := PropellerModel.thrust_n(k_t, extra_rpm)
	var reaction_torque_n_m := PropellerModel.reaction_torque_n_m(k_q, extra_rpm)

	var torque := MotorLayout.torque_from_motor("M1", thrust_delta_n, reaction_torque_n_m, ReferenceBuild.ARM_M)

	results.append(TestResult.new(
		"M1 alone: roll is nonzero and negative (right side rises)",
		torque.roll < 0.0,
		"roll=%.8f" % torque.roll
	))
	results.append(TestResult.new(
		"M1 alone: pitch is nonzero and negative (nose dips)",
		torque.pitch < 0.0,
		"pitch=%.8f" % torque.pitch
	))
	results.append(TestResult.new(
		"M1 alone: yaw is nonzero, sign matches M1's assigned spin direction",
		sign(torque.yaw) == sign(MotorLayout.SPIN["M1"]) and torque.yaw != 0.0,
		"yaw=%.8f (M1 spin=%.0f)" % [torque.yaw, MotorLayout.SPIN["M1"]]
	))

	return results
