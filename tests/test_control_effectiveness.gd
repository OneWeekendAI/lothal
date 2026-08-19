class_name TestControlEffectiveness
extends RefCounted
## ControlEffectiveness replaces two pieces of hand-written arithmetic — MotorLayout's fixed motor
## positions and MotorMixer's table of +/-1 sign patterns — with a matrix computed from geometry.
## A replacement for working code is only worth having if it is provably the SAME code for the case
## the old one covered, so the first test here is a regression against the existing flying mixer
## and everything else is about the layouts the old one could not describe.
##
## THE ONE THAT MATTERS is _test_matches_existing_mixer. Note how it is wired, because the obvious
## version of it cannot fail: feeding B*u through B+ and getting u back is the identity B+ B = I
## and holds for ANY invertible B, sign errors and all. So the wrench is NOT computed from the new
## matrix. It is computed by summing MotorLayout.torque_from_motor() — the repo's existing, trusted
## cross product — over the four motors, and only then handed to the new pseudo-inverse. Flip a
## sign in build_matrix() and the two paths disagree immediately, which is exactly what was
## confirmed by mutation before this file was committed.

const EPS := 1.0e-9
## Loose enough for a 4x4 Jacobi round trip through a Gram matrix (which squares the condition
## number), tight enough that no sign or factor error survives it.
const EPS_ROUNDTRIP := 1.0e-7


static func run() -> Array:
	var results: Array = []
	results.append(_test_matrix_matches_motor_layout_torque())
	results.append(_test_matches_existing_mixer())
	results.append(_test_three_motors_not_controllable())
	results.append(_test_collinear_not_controllable())
	results.append(_test_near_collinear_is_treated_as_collinear())
	results.append(_test_stretched_x_trades_roll_for_pitch())
	results.append(_test_deadcat_is_rank_4())
	results.append(_test_six_and_eight_motors())
	results.append(_test_pseudo_inverse_on_row_space())
	return results


## The symmetric X the whole sim flies today, expressed as motors for the new class. Positions come
## from MotorLayout so this fixture cannot drift from the aircraft it is claiming to describe.
static func _reference_motors(arm_m: float) -> Array:
	var drag := ReferenceBuild.propeller_k_q() / ReferenceBuild.propeller_k_t()
	var motors := []
	for name in MotorLayout.MOTOR_NAMES:
		var p := MotorLayout.motor_position(name, arm_m)
		motors.append(ControlEffectiveness.motor(p.x, p.z, MotorLayout.SPIN[name], drag))
	return motors


## The wrench four thrusts produce, computed WITHOUT the new matrix: MotorLayout.torque_from_motor
## is the project's only thrust cross product and is the oracle here.
static func _reference_wrench(thrusts: Array, arm_m: float) -> Array:
	var drag := ReferenceBuild.propeller_k_q() / ReferenceBuild.propeller_k_t()
	var f := 0.0
	var roll := 0.0
	var pitch := 0.0
	var yaw := 0.0
	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var t: float = thrusts[i]
		# Reaction torque is k_q*w^2 and thrust is k_t*w^2, so Q = (k_q/k_t)*T exactly — the same
		# ratio the matrix's yaw row carries, arrived at from the propeller model rather than
		# copied from the thing under test.
		var q := drag * t
		var tau := MotorLayout.torque_from_motor(name, t, q, arm_m)
		f += t
		roll += tau.roll
		pitch += tau.pitch
		yaw += tau.yaw
	return [f, roll, pitch, yaw]


static func _test_matrix_matches_motor_layout_torque() -> TestResult:
	var arm := ReferenceBuild.arm_m()
	var b := ControlEffectiveness.build_matrix(_reference_motors(arm))

	# Four deliberately lopsided thrust sets, so no symmetry can hide a swapped row: one motor
	# alone (the test_torque_signs.gd hand check), then three arbitrary asymmetric ones.
	var cases := [
		[1.0, 0.0, 0.0, 0.0],
		[0.0, 2.5, 0.0, 0.0],
		[3.0, 1.0, 0.5, 2.0],
		[0.2, 0.9, 1.7, 0.4],
	]
	var worst := 0.0
	var detail := ""
	for thrusts in cases:
		var got := ControlEffectiveness.apply(b, thrusts)
		var want := _reference_wrench(thrusts, arm)
		for r in 4:
			var d: float = absf(float(got[r]) - float(want[r]))
			if d > worst:
				worst = d
				detail = "%s row %s: B gives %.9f, MotorLayout gives %.9f" % [
					thrusts, ControlEffectiveness.ROW_NAMES[r], got[r], want[r]]

	# M1 is rear-right, so a lone M1 must give negative roll AND negative pitch (test_torque_signs).
	var m1 := ControlEffectiveness.apply(b, [1.0, 0.0, 0.0, 0.0])
	var signs_ok: bool = float(m1[ControlEffectiveness.ROW_ROLL]) < 0.0 \
		and float(m1[ControlEffectiveness.ROW_PITCH]) < 0.0 \
		and signf(float(m1[ControlEffectiveness.ROW_YAW])) == signf(float(MotorLayout.SPIN["M1"]))

	var ok: bool = worst <= EPS_ROUNDTRIP and signs_ok
	if ok:
		detail = "B reproduces MotorLayout.torque_from_motor for 4 thrust sets (max err %.12f); lone M1 gives -roll,-pitch" % worst
	elif signs_ok == false and worst <= EPS_ROUNDTRIP:
		detail = "M1-alone signs wrong: roll=%.6f pitch=%.6f yaw=%.6f" % [
			m1[ControlEffectiveness.ROW_ROLL], m1[ControlEffectiveness.ROW_PITCH], m1[ControlEffectiveness.ROW_YAW]]
	return TestResult.new("B matrix agrees with MotorLayout's cross product, sign for sign", ok, detail)


static func _test_matches_existing_mixer() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var arm: float = float(frame["specs"]["arm_mm"]) / 1000.0
	var motors := _reference_motors(arm)
	var pinv := ControlEffectiveness.mixer(motors)

	# Stick inputs chosen to exercise each axis alone and all three together. Throttle sits at 0.5
	# so MotorMixer's airmode step 3 never shifts the collective and the comparison is against the
	# mixer's ordinary behaviour rather than its saturation behaviour.
	var sticks := [
		[0.5, 1.0, 0.0, 0.0],
		[0.5, 0.0, 1.0, 0.0],
		[0.5, 0.0, 0.0, 1.0],
		[0.5, -0.7, 0.3, 0.0],
		[0.5, 0.4, -0.6, 0.8],
		[0.3, 1.0, 1.0, 1.0],
	]
	var worst := 0.0
	var detail := ""
	for s in sticks:
		var out: Dictionary = MotorMixer.mix(s[0], s[1], s[2], s[3])
		# MotorMixer speaks throttle 0..1; the matrix speaks newtons. The map between them is a
		# single positive scale, which the round trip is invariant to, so the commands are used as
		# thrusts directly and the comparison stays a comparison of PATTERN and SIGN.
		var thrusts := []
		for name in MotorLayout.MOTOR_NAMES:
			thrusts.append(float(out[name]))
		var wrench := _reference_wrench(thrusts, arm)          # oracle: NOT from B
		var recovered := ControlEffectiveness.apply_mixer(pinv, wrench)
		for i in 4:
			var d: float = absf(float(recovered[i]) - float(thrusts[i]))
			if d > worst:
				worst = d
				detail = "sticks %s motor %s: mixer wants %.9f, B+ gives %.9f" % [
					s, MotorLayout.MOTOR_NAMES[i], thrusts[i], recovered[i]]

	var ok: bool = worst <= EPS_ROUNDTRIP
	if ok:
		detail = "B+ reproduces MotorMixer's per-motor commands for %d stick inputs (max err %.12f)" % [sticks.size(), worst]
	return TestResult.new("pseudo-inverse mixer reproduces the existing MotorMixer exactly", ok, detail)


static func _test_three_motors_not_controllable() -> TestResult:
	# A Y3 at 120 degrees: geometrically sane, and still impossible, because a 4 x 3 matrix cannot
	# have rank 4. A real tricopter buys the fourth axis with a tail servo.
	var motors := []
	for k in 3:
		var ang := deg_to_rad(90.0 + 120.0 * k)
		motors.append(ControlEffectiveness.motor(0.12 * cos(ang), 0.12 * sin(ang), 1.0 if k == 0 else -1.0, 0.012))
	var b := ControlEffectiveness.build_matrix(motors)
	var r := ControlEffectiveness.rank(b)
	var verdict := ControlEffectiveness.controllable(b)
	var ok: bool = r == 3 and not verdict["ok"] and str(verdict["reason"]).contains("3 motors")
	return TestResult.new(
		"3 motors: rank 3, refused, and the reason names the motor count",
		ok,
		"rank=%d ok=%s reason='%s' kappa=%s" % [r, verdict["ok"], verdict["reason"], ControlEffectiveness.condition_number(b)]
	)


static func _test_collinear_not_controllable() -> TestResult:
	# Four motors on one lateral line. Every z is zero, so the pitch row is all zeros: pitching
	# would mean changing collective. Roll and yaw survive, so rank is 3, not 2 — and the failure
	# has to name PITCH, since "not controllable" alone tells a builder nothing to move.
	var motors := [
		ControlEffectiveness.motor(-0.18, 0.0, 1.0, 0.012),
		ControlEffectiveness.motor(-0.06, 0.0, -1.0, 0.012),
		ControlEffectiveness.motor(0.06, 0.0, -1.0, 0.012),
		ControlEffectiveness.motor(0.18, 0.0, 1.0, 0.012),
	]
	var b := ControlEffectiveness.build_matrix(motors)
	var r := ControlEffectiveness.rank(b)
	var verdict := ControlEffectiveness.controllable(b)
	var auth := ControlEffectiveness.axis_authority(b)

	# The mixer must still return NUMBERS for this layout, and the right ones. This is the
	# assertion that the pseudo-inverse DROPS its null-space eigenvalue rather than inverting it:
	# the demand for pitch is unmeetable, so the minimum-norm answer is to do nothing about it —
	# every motor exactly zero — and a 1/0 in the inversion turns that into INF or NaN commands
	# fed straight to four ESCs. Which is why "not controllable" is checked separately above and
	# never inferred from the mixer refusing to produce output; it does not refuse.
	var pinv := ControlEffectiveness.mixer(motors)
	var pitch_cmd := ControlEffectiveness.apply_mixer(pinv, [0.0, 0.0, 1.0, 0.0])
	var roll_cmd := ControlEffectiveness.apply_mixer(pinv, [0.0, 1.0, 0.0, 0.0])
	var finite_and_null := true
	for i in 4:
		if not is_finite(float(pitch_cmd[i])) or absf(float(pitch_cmd[i])) > EPS:
			finite_and_null = false
		if not is_finite(float(roll_cmd[i])):
			finite_and_null = false
	# ...and roll, which IS available, must still come out: dropping the null space must not have
	# taken the live axes with it.
	var roll_back := ControlEffectiveness.apply(b, roll_cmd)
	if absf(float(roll_back[ControlEffectiveness.ROW_ROLL]) - 1.0) > EPS_ROUNDTRIP:
		finite_and_null = false

	var ok: bool = r == 3 and not verdict["ok"] and str(verdict["reason"]).contains("pitch") \
		and float(auth["pitch"]) == 0.0 and float(auth["roll"]) > 0.0 \
		and ControlEffectiveness.condition_number(b) == INF and finite_and_null
	return TestResult.new(
		"4 collinear motors: rank 3, refused, and the mixer stays finite with a null pitch column",
		ok,
		"rank=%d reason='%s' pitch_auth=%.6f roll_auth=%.6f pitch_cmd=%s roll_cmd=%s" % [
			r, verdict["reason"], auth["pitch"], auth["roll"], pitch_cmd, roll_cmd]
	)


static func _test_near_collinear_is_treated_as_collinear() -> TestResult:
	# The same four-in-a-row layout with a 10 femtometre fore-aft stagger. Exactly-zero is the easy
	# case — any division by zero produces INF on its own and the code looks like it works. This is
	# the case the RELATIVE tolerance exists for: the pitch lever is real, positive, and utterly
	# useless, and a rank test or a condition number that compares against an absolute epsilon
	# happily reports a controllable aircraft with kappa in the trillions.
	var eps_z := 1.0e-14
	var motors := [
		ControlEffectiveness.motor(-0.18, eps_z, 1.0, 0.012),
		ControlEffectiveness.motor(-0.06, -eps_z, -1.0, 0.012),
		ControlEffectiveness.motor(0.06, eps_z, -1.0, 0.012),
		ControlEffectiveness.motor(0.18, -eps_z, 1.0, 0.012),
	]
	var b := ControlEffectiveness.build_matrix(motors)
	var r := ControlEffectiveness.rank(b)
	var kappa := ControlEffectiveness.condition_number(b)
	var verdict := ControlEffectiveness.controllable(b)
	var ok: bool = r == 3 and kappa == INF and not verdict["ok"]
	return TestResult.new(
		"near-collinear (1e-14 m of pitch lever) is refused, not flown at kappa 1e14",
		ok,
		"rank=%d kappa=%s reason='%s'" % [r, kappa, verdict["reason"]]
	)


static func _test_stretched_x_trades_roll_for_pitch() -> TestResult:
	# Arms longer fore-aft (|z| = 0.15) than side-to-side (|x| = 0.07): a "stretched X", the layout
	# a long-range build uses. The DIRECTION is the assertion. Pitch is rotation about the lateral
	# axis and is levered by the FORE-AFT offset z, so a fore-aft stretch must buy PITCH authority
	# and give up ROLL. Getting this backwards is precisely the x/z swap airframe.md §4.1 contains,
	# and an inequality test with no direction would pass with the swap in place.
	var lat := 0.07
	var lon := 0.15
	var motors := [
		ControlEffectiveness.motor(lat, lon, 1.0, 0.012),
		ControlEffectiveness.motor(lat, -lon, -1.0, 0.012),
		ControlEffectiveness.motor(-lat, lon, -1.0, 0.012),
		ControlEffectiveness.motor(-lat, -lon, 1.0, 0.012),
	]
	var b := ControlEffectiveness.build_matrix(motors)
	var auth := ControlEffectiveness.axis_authority(b)
	var roll: float = auth["roll"]
	var pitch: float = auth["pitch"]
	# Row norms are exactly 2*|x| and 2*|z| for four motors at +/- each: check the real numbers,
	# not just the ordering, so a row that is right-signed but wrong-scaled is still caught.
	var ok: bool = pitch > roll \
		and absf(roll - 2.0 * lat) <= EPS and absf(pitch - 2.0 * lon) <= EPS \
		and ControlEffectiveness.controllable(b)["ok"]
	return TestResult.new(
		"stretched X: fore-aft stretch buys pitch authority and costs roll",
		ok,
		"roll=%.6f (expect %.6f) pitch=%.6f (expect %.6f) yaw=%.6f" % [roll, 2.0 * lat, pitch, 2.0 * lon, auth["yaw"]]
	)


static func _test_deadcat_is_rank_4() -> TestResult:
	# Deadcat: the front arms swept forward and outward to clear the camera view. Asymmetric
	# fore-aft, which is the first layout the old fixed table simply could not express.
	var motors := [
		ControlEffectiveness.motor(0.13, -0.10, -1.0, 0.012),   # front-right, swept forward
		ControlEffectiveness.motor(-0.13, -0.10, 1.0, 0.012),   # front-left
		ControlEffectiveness.motor(0.09, 0.12, 1.0, 0.012),     # rear-right
		ControlEffectiveness.motor(-0.09, 0.12, -1.0, 0.012),   # rear-left
	]
	var b := ControlEffectiveness.build_matrix(motors)
	var verdict := ControlEffectiveness.controllable(b)
	var pinv := ControlEffectiveness.mixer(motors)
	# The mixer must actually invert: demand each axis in turn and get the wrench back.
	var worst := 0.0
	for axis in 4:
		var want := [0.0, 0.0, 0.0, 0.0]
		want[axis] = 1.0
		var got := ControlEffectiveness.apply(b, ControlEffectiveness.apply_mixer(pinv, want))
		for r in 4:
			worst = maxf(worst, absf(float(got[r]) - float(want[r])))
	var ok: bool = verdict["ok"] and ControlEffectiveness.rank(b) == 4 and worst <= EPS_ROUNDTRIP
	return TestResult.new(
		"deadcat layout is rank 4 and its mixer inverts on all four axes",
		ok,
		"rank=%d kappa=%.1f max round-trip err %.12f" % [verdict["rank"], ControlEffectiveness.condition_number(b), worst]
	)


static func _test_six_and_eight_motors() -> TestResult:
	# Hex and octo, built by the same code path with no special-casing. Both are OVER-actuated:
	# B is 4 x 6 and 4 x 8, B+ is the minimum-norm right inverse, and B B+ = I still holds even
	# though B+ B cannot. Which way round that identity goes is the thing to get wrong here.
	var detail := ""
	var ok := true
	for n in [6, 8]:
		var motors := []
		var radius := 0.15
		for k in n:
			var ang := TAU * float(k) / float(n)
			motors.append(ControlEffectiveness.motor(radius * sin(ang), -radius * cos(ang), 1.0 if k % 2 == 0 else -1.0, 0.012))
		var b := ControlEffectiveness.build_matrix(motors)
		var verdict := ControlEffectiveness.controllable(b)
		var pinv := ControlEffectiveness.mixer(motors)
		var worst := 0.0
		for axis in 4:
			var want := [0.0, 0.0, 0.0, 0.0]
			want[axis] = 1.0
			var got := ControlEffectiveness.apply(b, ControlEffectiveness.apply_mixer(pinv, want))
			for r in 4:
				worst = maxf(worst, absf(float(got[r]) - float(want[r])))
		var this_ok: bool = verdict["ok"] and pinv.size() == n and worst <= EPS_ROUNDTRIP
		ok = ok and this_ok
		detail += "n=%d rank=%d kappa=%.1f err=%.12f; " % [n, verdict["rank"], ControlEffectiveness.condition_number(b), worst]
	return TestResult.new("6 and 8 motor layouts build and invert with no special-casing", ok, detail)


static func _test_pseudo_inverse_on_row_space() -> TestResult:
	# The defining property, tested where it is actually true. B B+ v = v holds for v in the COLUMN
	# space of B (the achievable wrenches) and nowhere else — for an uncontrollable layout there
	# are wrenches it demonstrably does not hold for, and asserting it everywhere would be
	# asserting something false. So achievable wrenches are constructed as v = B u.
	var arm := ReferenceBuild.arm_m()
	var cases := [
		{"name": "symmetric X", "motors": _reference_motors(arm)},
		{"name": "collinear (rank 3)", "motors": [
			ControlEffectiveness.motor(-0.18, 0.0, 1.0, 0.012),
			ControlEffectiveness.motor(-0.06, 0.0, -1.0, 0.012),
			ControlEffectiveness.motor(0.06, 0.0, -1.0, 0.012),
			ControlEffectiveness.motor(0.18, 0.0, 1.0, 0.012),
		]},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260818
	var worst := 0.0
	var detail := ""
	for case in cases:
		var motors: Array = case["motors"]
		var b := ControlEffectiveness.build_matrix(motors)
		var pinv := ControlEffectiveness.mixer(motors)
		for trial in 20:
			var u := []
			for i in motors.size():
				u.append(rng.randf_range(-2.0, 2.0))
			var v := ControlEffectiveness.apply(b, u)
			var back := ControlEffectiveness.apply(b, ControlEffectiveness.apply_mixer(pinv, v))
			for r in 4:
				var d: float = absf(float(back[r]) - float(v[r]))
				if d > worst:
					worst = d
					detail = "%s row %s: %.9f vs %.9f" % [case["name"], ControlEffectiveness.ROW_NAMES[r], back[r], v[r]]
	var ok: bool = worst <= EPS_ROUNDTRIP
	if ok:
		detail = "B B+ v = v for 40 achievable wrenches across a full-rank and a rank-3 layout (max err %.12f)" % worst
	return TestResult.new("pseudo-inverse is exact on the achievable wrench space", ok, detail)
