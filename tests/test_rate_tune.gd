class_name TestRateTune
extends RefCounted
## The scaling law itself, checked as arithmetic rather than as flight.
##
## tests/test_catalog_tuning.gd flies the result; this one checks that the numbers handed to the
## loop are the numbers the law says they should be, which is a different question and a much
## faster one. The two together are the slice: a law that is right on paper and wrong in the air is
## a law, and a tune that flies well for a reason nobody wrote down is a coincidence.

## The reference build's hand tune, restated here as literals ON PURPOSE.
##
## Every other file in this project reads these from RateModeController rather than repeating them,
## and that is the right rule everywhere except here. This suite's whole job is to catch the day
## somebody changes the reference aircraft's gains while believing they are changing a scaling
## rule, and a test that read the constant it is guarding would pass through that change silently.
const ANCHOR_KP := Vector3(2.3, 2.3, 6.0)
const ANCHOR_KI := Vector3(0.15, 0.15, 0.39)
const ANCHOR_KD := Vector3(0.042, 0.042, 0.0)

const WHOOP := "frame_65mm_whoop"
const LONG_RANGE := "frame_10in_long_range"


## A build that differs from the reference in exactly one part, so that anything the tune does
## differently is attributable. The frame variants are the spread labs-and-sim.md §7 measured.
static func _with_frame(frame_id: String) -> Build:
	return _swap({"frame": frame_id})


static func _swap(parts: Dictionary) -> Build:
	return Build.from_ids(PartsCatalog.load_default(),
		String(parts.get("frame", ReferenceBuild.FRAME_ID)),
		String(parts.get("motor", ReferenceBuild.MOTOR_ID)),
		String(parts.get("propeller", ReferenceBuild.PROPELLER_ID)),
		String(parts.get("battery", ReferenceBuild.BATTERY_ID)),
		String(parts.get("esc", ReferenceBuild.ESC_ID)),
		String(parts.get("fc", ReferenceBuild.FC_ID)))


static func run() -> Array:
	var results: Array = []

	# --- THE ANCHOR -----------------------------------------------------------------------
	#
	# Not "close to". The scaling is normalised so that the aircraft the gains were hand-found on
	# reproduces the hand tune exactly, and every other build moves relative to it. Exactness is
	# achievable because the reference's own plant figure is the divisor: A_ref / A_ref is 1.0 in
	# floating point, not 0.9999999.
	var ref_tune := RateTune.derive(ReferenceBuild.build())
	results.append(TestResult.new(
		"the reference build derives EXACTLY today's hand tune",
		ref_tune.kp == ANCHOR_KP and ref_tune.ki == ANCHOR_KI and ref_tune.kd == ANCHOR_KD,
		"kp %s ki %s kd %s" % [ref_tune.kp, ref_tune.ki, ref_tune.kd]))
	results.append(TestResult.new(
		"the reference build's scale factor is exactly 1 on all three axes",
		ref_tune.scale == Vector3.ONE,
		"scale = %s" % ref_tune.scale))

	# --- THE PLANT HAS ONE SOURCE ---------------------------------------------------------
	#
	# The frame bench already measures settled per-axis angular acceleration, at the nominal-voltage
	# datum, for exactly this purpose. A second derivation here would agree for a long time and then
	# stop, which is the divergence this project keeps having to undo — so the tune reads the bench.
	var lr := _with_frame(LONG_RANGE)
	var from_bench := Vector3.ZERO
	for axis in 3:
		var bench := FrameBench.for_build(lr)
		bench.begin(axis, lr.hover_throttle())
		from_bench[axis] = bench.peak_alpha_rad_s2
	results.append(TestResult.new(
		"the plant gain IS the frame bench's settled acceleration, not a second opinion",
		RateTune.plant_alpha_for(lr) == from_bench,
		"tune %s vs bench %s" % [RateTune.plant_alpha_for(lr), from_bench]))

	# --- THE LAW --------------------------------------------------------------------------
	#
	# kp * alpha is the loop gain the controller closes on, and the law holds it constant. So the
	# product is the same number on every build in the catalog, which is a stronger statement than
	# "the gains moved in the right direction" and the one worth asserting.
	var whoop := RateTune.derive(_with_frame(WHOOP))
	var long_range := RateTune.derive(lr)
	var worst := 0.0
	for tune in [whoop, long_range]:
		for axis in 3:
			var product: float = tune.kp[axis] * tune.plant_alpha[axis]
			var anchor: float = ANCHOR_KP[axis] * ref_tune.plant_alpha[axis]
			worst = maxf(worst, absf(product - anchor) / anchor)
	results.append(TestResult.new(
		"kp * plant acceleration is invariant across the catalog's extremes",
		worst < 1e-6,
		"worst relative deviation %.3e over a %.1fx plant spread" % [
			worst, whoop.plant_alpha.z / long_range.plant_alpha.z]))

	# The whoop rolls harder than the reference, so it needs LESS gain, not more. Stated as a
	# direction as well as a product, because an inverted law would satisfy the invariant above if
	# the plant figure were inverted with it.
	results.append(TestResult.new(
		"a stiffer plant gets lower gains and a lazier one gets higher",
		whoop.kp.x < ANCHOR_KP.x and long_range.kp.x > ANCHOR_KP.x,
		"whoop kp %.3f, reference %.3f, 10\" %.3f" % [whoop.kp.x, ANCHOR_KP.x, long_range.kp.x]))

	# --- YAW KEEPS ITS OWN CHARACTER ------------------------------------------------------
	#
	# rate_mode_controller.gd's yaw docstring is explicit that the integral TIME CONSTANT is what
	# sets the character and the absolute values follow the authority. That sentence is the scaling
	# law, already written, for one axis — so scaling must preserve it rather than overwrite it.
	var ratio_error := 0.0
	for tune in [whoop, long_range]:
		for axis in 3:
			if tune.ki[axis] <= 0.0:
				continue
			var ti: float = tune.kp[axis] / tune.ki[axis]
			var anchor_ti: float = ANCHOR_KP[axis] / ANCHOR_KI[axis]
			ratio_error = maxf(ratio_error, absf(ti - anchor_ti) / anchor_ti)
	results.append(TestResult.new(
		"the integral time constant kp/ki is preserved on every axis of every build",
		ratio_error < 1e-6,
		"worst deviation %.3e from roll's %.1f s and yaw's %.1f s" % [
			ratio_error, ANCHOR_KP.x / ANCHOR_KI.x, ANCHOR_KP.z / ANCHOR_KI.z]))

	# Yaw's kd is zero because yaw's plant is rotor-drag dominated and already damped, not because
	# it happened to be small. Zero times any scale factor is zero, and that is the point: the law
	# cannot quietly reintroduce a term a previous slice removed on physical grounds.
	results.append(TestResult.new(
		"yaw's kd stays zero on every build — scaling cannot reintroduce it",
		whoop.kd.z == 0.0 and long_range.kd.z == 0.0 and ref_tune.kd.z == 0.0,
		"whoop %.4f, reference %.4f, 10\" %.4f" % [whoop.kd.z, ref_tune.kd.z, long_range.kd.z]))

	# --- D IS BOUNDED BY THE BOARD --------------------------------------------------------
	#
	# The FC slice made a board's noise cost visible on the details panel. This is the same
	# arithmetic reaching the tune: a scaled-up D on a noisy board multiplies gyro noise into the
	# motors, so the derived D has a ceiling, and the ceiling belongs to the board.
	var quiet := RateTune.kd_ceiling_for(_swap({"fc": "fc_f405_30x30"}))
	var noisy := RateTune.kd_ceiling_for(_swap({"fc": "fc_f411_25x25_whoop"}))
	results.append(TestResult.new(
		"a noisier board yields a lower D ceiling",
		noisy < quiet,
		"F411/8 kHz allows kd %.4f; the reference MPU-6000/1 kHz allows %.4f" % [noisy, quiet]))

	# The ceiling must never touch the aircraft the tune was found on, or the anchor above is being
	# held up by luck.
	results.append(TestResult.new(
		"the reference build and board sit clear of the ceiling",
		RateTune.derive(ReferenceBuild.build()).kd.x < RateTune.kd_ceiling_for(ReferenceBuild.build()),
		"installed kd %.4f against a ceiling of %.4f" % [
			ANCHOR_KD.x, RateTune.kd_ceiling_for(ReferenceBuild.build())]))

	# And it must actually BITE somewhere, or it is a bound nobody could ever reach — a check that
	# cannot fail. The 10" long-range wants twice the reference's D; the budget board cannot pay
	# for it.
	var budget_lr := RateTune.derive(_swap({"frame": LONG_RANGE, "fc": "fc_f405_30x30_budget"}))
	results.append(TestResult.new(
		"a big airframe on a budget board is D-limited, and says which part limits it",
		budget_lr.d_limited and budget_lr.kd.x < long_range.kd.x,
		"capped to %.4f from the derived %.4f" % [budget_lr.kd.x, long_range.derived_kd.x]))

	var limiting := 0
	var names := ""
	for warning in budget_lr.warnings():
		if warning.severity == BuildWarning.Severity.LIMITING:
			limiting += 1
			names = warning.message
	results.append(TestResult.new(
		"the D ceiling is reported at `limiting` severity and names the board",
		limiting == 1 and names.contains(_swap({"fc": "fc_f405_30x30_budget"}).fc["name"]),
		names if limiting > 0 else "no limiting warning emitted"))

	results.append(TestResult.new(
		"the reference build raises no tuning warning at all",
		ref_tune.warnings().is_empty(),
		"%d warnings" % ref_tune.warnings().size()))

	# --- OVERRIDES ------------------------------------------------------------------------
	#
	# The derived baseline stays visible after a builder has changed something, because "what did I
	# change and by how much" is the question a tuning screen exists to answer.
	var edited := RateTune.derive(lr)
	edited.set_gains(0, Vector3(9.0, 0.5, 0.1))
	results.append(TestResult.new(
		"an override changes the gains in force and leaves the derived baseline intact",
		edited.kp.x == 9.0 and edited.derived_kp.x == long_range.derived_kp.x
			and edited.is_overridden(0) and not edited.is_overridden(2),
		"in force %.2f, derived %.3f" % [edited.kp.x, edited.derived_kp.x]))

	edited.clear_override(0)
	results.append(TestResult.new(
		"clearing an override returns the axis to the derived tune",
		edited.kp == long_range.kp and edited.kd == long_range.kd,
		"kp back to %s" % edited.kp))

	# An absurd gain is ACCEPTED — warn, never block (parts.md) — and described.
	edited.set_gains(0, Vector3(400.0, 0.0, 0.0))
	var described := false
	for warning in edited.warnings():
		if warning.id == &"tune_override":
			described = true
	results.append(TestResult.new(
		"an absurd manual gain is accepted and described, never refused",
		edited.kp.x == 400.0 and described,
		"kp held at %.1f" % edited.kp.x))

	return results
