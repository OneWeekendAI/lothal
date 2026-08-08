class_name TestYawAuthority
extends RefCounted
## Does the PLANT yaw equally hard both ways?
##
## This suite exists to settle a question that must be answered BEFORE any control-loop
## change: when the pilot reports that "A feels stronger than D", is that a genuine
## asymmetry in the aircraft — mixer, propellers, integrator — or is it entirely the
## absence of a closed loop on yaw?
##
## So it deliberately bypasses every flight controller and drives MotorMixer directly.
## A controller in the path would hide a plant asymmetry (it would correct for it) or
## invent one (its own integrator state differs between the two runs). What is measured
## here is the open-loop response of the airframe to a mixer command, and nothing else.
##
## The second half derives the yaw authority the aircraft actually has, in N*m and in
## rad/s^2, so that yaw PID gains can be set against a number rather than copied from
## roll/pitch. Yaw torque comes from propeller DRAG (k_q), not from thrust differential
## across an arm, and yaw inertia is the largest of the three — that pair is why yaw
## sharing roll's gains is not a neutral choice.

const DT := 0.001
const IMPULSE_S := 0.25
## Both runs start from the same primed-at-hover state, so the only difference between
## them is the sign of the mixer's yaw command.
const SYMMETRY_TOLERANCE_PCT := 1.0

## Yaw rate (contract sign: +Yaw = nose right = rotation about -Y).
static func _yaw_rate(core: DroneCore) -> float:
	return -core.rigid_body.angular_velocity_rad_s.y

## Holds a raw mixer yaw command for IMPULSE_S from a freshly primed hover, and returns
## the yaw rate reached. Roll/pitch commands stay at zero throughout.
static func _impulse(yaw_cmd: float) -> float:
	var core := ReferenceBuild.build_drone_core()
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)

	var cmds := MotorMixer.mix(hover, 0.0, 0.0, yaw_cmd)
	for i in int(IMPULSE_S / DT):
		core.step(cmds, DT)
	return _yaw_rate(core)

static func run() -> Array:
	var results: Array = []

	var positive := _impulse(1.0)
	var negative := _impulse(-1.0)
	var asymmetry_pct: float = 0.0
	if absf(positive) > 0.0:
		asymmetry_pct = (absf(positive) - absf(negative)) / absf(positive) * 100.0

	results.append(TestResult.new(
		"a mixer yaw command produces yaw at all, in the commanded direction",
		positive > 0.0 and negative < 0.0,
		"+1 -> %.4f rad/s, -1 -> %.4f rad/s after %.0f ms" % [positive, negative, IMPULSE_S * 1000.0]
	))

	## The tolerance is not fitted to what the code produced. The two runs are the SAME
	## four throttle values with the motor assignments swapped, so total current, total
	## thrust and every RPM in the set are identical between them; the only thing that
	## differs is which diagonal pair carries them. A symmetric plant therefore owes an
	## exactly equal and opposite answer, and the 1% band is headroom for float ordering
	## in the integrator, not for physics.
	results.append(TestResult.new(
		"+yaw and -yaw of equal duration are equal and opposite within %.1f%%" % SYMMETRY_TOLERANCE_PCT,
		absf(asymmetry_pct) < SYMMETRY_TOLERANCE_PCT,
		"|+1| = %.6f, |-1| = %.6f rad/s, asymmetry = %+.4f%%" % [absf(positive), absf(negative), asymmetry_pct]
	))

	# --- Yaw authority, derived rather than guessed ---
	var build := ReferenceBuild.build()
	var core := ReferenceBuild.build_drone_core()
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)
	var hover_rpm: float = core.powertrain.motor_rpm[0]

	# Full yaw deflection moves one diagonal pair up by MIX_GAIN and the other down by it.
	# RPM is proportional to throttle (max_rpm = KV * V), so the RPM either side of hover
	# scales the same way.
	var rpm_hi := hover_rpm * (hover + MotorMixer.MIX_GAIN) / hover
	var rpm_lo := hover_rpm * maxf(hover - MotorMixer.MIX_GAIN, 0.0) / hover
	var yaw_torque_n_m := 2.0 * (PropellerModel.reaction_torque_n_m(build.k_q, rpm_hi)
		- PropellerModel.reaction_torque_n_m(build.k_q, rpm_lo))

	# Roll, for comparison: the same MIX_GAIN deflection across the left/right pair, but
	# acting through the arm as a thrust differential.
	var arm_lever: float = build.arm_m * cos(deg_to_rad(45.0))
	var roll_torque_n_m := 2.0 * arm_lever * (PropellerModel.thrust_n(build.k_t, rpm_hi)
		- PropellerModel.thrust_n(build.k_t, rpm_lo))

	var inertia := build.mass_properties.inertia
	var i_yaw: float = inertia.y.y
	var i_roll: float = inertia.z.z
	var yaw_accel := yaw_torque_n_m / i_yaw
	var roll_accel := roll_torque_n_m / i_roll

	results.append(TestResult.new(
		"yaw authority is far weaker than roll: drag torque, and a larger inertia",
		yaw_accel < roll_accel * 0.5,
		"full deflection: yaw %.4f N*m / I %.6f = %.1f rad/s^2; roll %.4f N*m / I %.6f = %.1f rad/s^2 (ratio %.3f)"
			% [yaw_torque_n_m, i_yaw, yaw_accel, roll_torque_n_m, i_roll, roll_accel, yaw_accel / roll_accel]
	))

	return results
