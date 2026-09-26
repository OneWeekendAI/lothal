class_name TestSpinUpOverlay
extends RefCounted
## The spin-up overlay — P10e's fourth, see plans/2026-09-02-analysis-overlays-design.md §4.
##
## ## What has to be true for this overlay to be worth drawing
##
## The design doc is unusually blunt about this one: it is "the weakest of the five against §0's
## bar", because tau is ALREADY a number on the propulsion panel and a chart of a scalar is not
## news. What it adds is the shape — how long the motor takes to arrive, drawn against time — and
## a shape is only worth drawing if it is the shape the aircraft actually flies. So:
##
## 1. **It draws the curve the sim flies.** `MotorModel::step` advances RPM by
##    `alpha = 1 - exp(-dt/tau)` per step, and iterating that from zero at a constant command IS
##    `omega_final · (1 - exp(-t/tau))`. The overlay states the closed form; the check integrates
##    the Rust one and compares. Any other first-order-looking expression fails by a mile.
##
## 2. **The tau is the build's, not the fallback.** `MotorSpinUp.FALLBACK_TAU_S` is 0.03 and it is
##    not a measurement — it is the pre-P7 constant, kept so a caller that cannot compute produces
##    the old numbers instead of a silent zero. §4.3: a fallback curve must not look like a
##    computed one.
##
## 3. **The final RPM is the operating point the linearisation used.** tau is computed AT an
##    omega; drawing the approach to a different omega would be a curve about an aircraft whose
##    tau is not this tau. `Build.operating_rpm()` exists for exactly this reason, and P10e's
##    first overlay already reads it.
##
## 4. **One curve, because the model carries one tau.** §4.1 asks for four curves so an asymmetric
##    build shows as four shapes. A `Build` has ONE motor and ONE propeller, so its `spin_up()` is
##    one dictionary and four curves would be four copies of one number drawn on top of each
##    other — a picture claiming a capability the model does not have. The check below pins that,
##    and fails the day per-motor spin-up lands, which is the day the fourth curve becomes real.

## How close the closed form must sit to the integrated Rust one. Both are the same exponential;
## the gap is the accumulated rounding of 2000 multiply-adds, which lands near 1e-13 relative.
## 1e-9 is a ceiling well under any wrong-formula candidate (the nearest miss, `exp(-t·tau)`,
## is wrong by order 1) and well over the noise.
const LAW_TOLERANCE := 1.0e-9

## The step the integration check uses, in seconds, and the count of steps. dt is small against
## the reference build's tau (order 4 ms) so the comparison is over a curve that has actually
## arrived, not over its first corner.
const STEP_DT_S := 0.0001
const STEP_COUNT := 2000


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_curve_is_the_lag_the_sim_flies())
	results.append(_test_the_tau_is_the_builds_own_rather_than_the_fallback())
	results.append(_test_a_fallback_tau_is_flagged_rather_than_drawn_as_a_result())
	results.append(_test_the_final_rpm_is_the_linearisation_point())
	results.append(_test_no_drone_is_a_refusal_rather_than_a_flat_curve())
	results.append(_test_the_model_carries_one_tau_so_the_overlay_draws_one_curve())
	results.append(_test_the_curve_maps_onto_the_canvas())
	return results


# ---------------------------------------------------------------------------
# 1. The overlay draws the lag the sim flies
# ---------------------------------------------------------------------------

## `SpinUpOverlay.rpm_at` against `MotorModel.step` integrated from a standstill.
##
## The comparison is on the FRACTION arrived, not on the RPM, because the two have different
## finals by construction: the sim steps toward `throttle · max_rpm` and the overlay draws the
## approach to `operating_rpm()`. What is being checked is the LAW; which point it converges on
## is check 4's business, and conflating them would let a wrong final hide a wrong curve.
##
## MUTATION that turns this red: write the exponent as `-t_s * p_tau_s` instead of `-t_s /
## p_tau_s` — the transposition that still gives 0 at t = 0, still rises monotonically, still
## saturates at the final, and is wrong everywhere in between. Verified: worst fraction gap goes
## from 4e-14 to 0.63.
static func _test_the_curve_is_the_lag_the_sim_flies() -> TestResult:
	var build := ReferenceBuild.build()
	var tau: float = float(build.spin_up()["tau_s"])
	var motor := MotorModel.create_with_tau(float(ReferenceBuild.MOTOR_KV), 1.0, tau)
	var voltage := ReferenceBuild.BATTERY_NOMINAL_V
	var target := motor.max_rpm(voltage)

	var rpm := 0.0
	var worst := 0.0
	var worst_t := 0.0
	for i in STEP_COUNT:
		rpm = motor.step(rpm, 1.0, voltage, STEP_DT_S)
		var t: float = float(i + 1) * STEP_DT_S
		var flown := rpm / target
		var drawn := SpinUpOverlay.rpm_at(t, tau, target) / target
		var gap: float = absf(flown - drawn)
		if gap > worst:
			worst = gap
			worst_t = t
	return TestResult.new(
		"the drawn curve is the first-order lag MotorModel.step integrates",
		worst <= LAW_TOLERANCE,
		"worst fraction gap %s at t = %.4f s over %d steps" % [str(worst), worst_t, STEP_COUNT])


# ---------------------------------------------------------------------------
# 2. The tau is the build's own
# ---------------------------------------------------------------------------

## `adopt` carries `Build.spin_up()["tau_s"]` through unchanged, and on the reference build that
## is not the fallback.
##
## Equality is `==` on doubles: the overlay applies no arithmetic to tau at all, so anything but
## bit-identity means a second opinion about the time constant has appeared somewhere.
##
## The second clause is what makes the first one worth asserting. A build whose tau happened to
## BE 0.03 would satisfy the equality while telling a reader nothing, so the reference build's
## recovered tau is asserted to differ from `FALLBACK_TAU_S` — which is also the check that goes
## red if the recovery silently starts failing catalog-wide.
##
## MUTATION that turns this red: fill `tau_s` from `MotorSpinUp.FALLBACK_TAU_S` in `adopt`.
static func _test_the_tau_is_the_builds_own_rather_than_the_fallback() -> TestResult:
	var build := ReferenceBuild.build()
	var expected: float = float(build.spin_up()["tau_s"])
	var overlay := SpinUpOverlay.new()
	overlay.adopt(build)
	var exact: bool = overlay.tau_s == expected
	var not_fallback: bool = expected != MotorSpinUp.FALLBACK_TAU_S
	overlay.free()
	return TestResult.new(
		"the overlay's tau IS the build's spin-up tau, and it is a computed one",
		exact and not_fallback,
		"overlay %s vs build %s, fallback %s" % [
			str(expected), str(expected), str(MotorSpinUp.FALLBACK_TAU_S)])


# ---------------------------------------------------------------------------
# 3. A fallback is drawn as a fallback
# ---------------------------------------------------------------------------

## §4.3's one obligation: "a `FALLBACK_TAU_S` curve must not look like a computed one".
##
## Four clauses, because the tier vocabulary has a shape the obvious implementation gets wrong.
## `MotorSpinUp` returns `"recovered"`, `"fallback_r"`, and `"fallback_all:" + reason` — the last
## one CARRIES A REASON, so an equality test against `"fallback_all"` passes the two easy cases
## and misses the only one where tau is entirely a constant. So the fourth clause classifies a
## string the code actually produced rather than one this test wrote: `MotorSpinUp.compute` on a
## motor with no KV, which is the branch that builds that string.
##
## It goes through `compute` rather than through a whole `Build` deliberately. A `Build` fitted
## with a zero-KV motor does not reach `spin_up()` at all — `operating_rpm()` -> `can_hover()` ->
## `rpm_at_throttle` panics inside the Rust on a NaN clamp, which is a real defect and a separate
## one. Routing this check through the function that owns the tier keeps it about the tier.
##
## MUTATION that turns this red: `return p_tier == "fallback_r" or p_tier == "fallback_all"`.
static func _test_a_fallback_tau_is_flagged_rather_than_drawn_as_a_result() -> TestResult:
	var recovered_is_not: bool = not SpinUpOverlay.is_fallback("recovered")
	var partial_is: bool = SpinUpOverlay.is_fallback("fallback_r")

	# The string the code makes, not the string this test guessed at.
	var produced: String = String(MotorSpinUp.compute({"specs": {}}, null, null, 0.0, 0.0, 0.0)
		.get("tier", ""))
	var total_is: bool = SpinUpOverlay.is_fallback(produced)

	# `tier_note` is a pure function of the tier, so it is asked directly — the overlay would have
	# to be fed a build it cannot survive to get there any other way.
	var overlay := SpinUpOverlay.new()
	overlay.tier = produced
	var noted: bool = overlay.tier_note() != "" and overlay.tier_note().contains("0.03")
	overlay.tier = "recovered"
	var quiet_when_computed: bool = overlay.tier_note() == ""
	overlay.free()

	return TestResult.new(
		"a fallback tau is flagged, including the one that carries its reason",
		recovered_is_not and partial_is and total_is and noted and quiet_when_computed,
		"recovered %s, fallback_r %s, produced \"%s\" flagged %s, noted %s, quiet when computed %s" % [
			str(not recovered_is_not), str(partial_is), produced, str(total_is), str(noted),
			str(quiet_when_computed)])


# ---------------------------------------------------------------------------
# 4. The curve converges on the point tau was linearised at
# ---------------------------------------------------------------------------

## The final RPM is `Build.operating_rpm()` — the same point `spin_up()` hands `MotorSpinUp` as
## `omega_hover_rad_s`, and the same one P10e's thrust overlay draws at.
##
## `rated_rpm()` is the plausible wrong answer and it is not a small difference: on the reference
## build it is 29,008 rpm against a hover of 8,578. A curve drawn to rated would show a motor
## arriving somewhere it never goes in the flight the tau describes.
##
## MUTATION that turns this red: `final_rpm = build.rated_rpm()`.
static func _test_the_final_rpm_is_the_linearisation_point() -> TestResult:
	var build := ReferenceBuild.build()
	var overlay := SpinUpOverlay.new()
	overlay.adopt(build)
	var matches: bool = overlay.final_rpm == build.operating_rpm()
	var differs_from_rated: bool = build.operating_rpm() != build.rated_rpm()
	var drawn := overlay.final_rpm
	overlay.free()
	return TestResult.new(
		"the curve converges on operating_rpm, the point the tau was linearised at",
		matches and differs_from_rated,
		"drawn %.0f rpm, operating %.0f, rated %.0f" % [
			drawn, build.operating_rpm(), build.rated_rpm()])


# ---------------------------------------------------------------------------
# 5. No drone is a refusal
# ---------------------------------------------------------------------------

## The empty state. `GlassShell._refill_thrust_overlay` hands every overlay a null build when no
## project is open, and a spin-up curve for no motor would be a picture of the fallback constant
## with nothing on screen to say so — the §4.3 failure reached by a different door.
##
## MUTATION that turns this red: `refusal = ""` on the null branch, leaving `tau_s` at 0.0. The
## curve clause catches it too, which is why both are asserted: a refusal with a curve under it
## and a curve with no refusal over it are different bugs.
static func _test_no_drone_is_a_refusal_rather_than_a_flat_curve() -> TestResult:
	var overlay := SpinUpOverlay.new()
	overlay.adopt(null)
	var refused: bool = overlay.refusal != ""
	var no_curve: bool = overlay.curve_points().is_empty()
	var words := overlay.refusal
	overlay.free()
	return TestResult.new(
		"no drone open is a refusal, not a curve at the fallback constant",
		refused and no_curve,
		"refusal \"%s\", curve empty %s" % [words, str(no_curve)])


# ---------------------------------------------------------------------------
# 6. One tau, one curve
# ---------------------------------------------------------------------------

## The correction to §4.1, asserted rather than described.
##
## The design asks for four curves "so an asymmetric build shows as four curves instead of one".
## A `Build` holds one `motor` dictionary and one `propeller`, and `spin_up()` returns ONE
## dictionary with no motor name anywhere in it — so the four curves would be one curve drawn four
## times, which is a picture asserting the model can express something it cannot. §9 of
## CONTINUE-HERE: never invent a spec to unlock a feature.
##
## This check is the tripwire on that reasoning. It goes red the day `spin_up()` gains per-motor
## keys, which is the day the fourth curve stops being a fiction and this overlay should grow it.
##
## MUTATION that turns this red: add `"M1": {...}` to the dictionary `Build.spin_up()` returns.
static func _test_the_model_carries_one_tau_so_the_overlay_draws_one_curve() -> TestResult:
	var spin: Dictionary = ReferenceBuild.build().spin_up()
	var per_motor: Array[String] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		if spin.has(motor_name):
			per_motor.append(motor_name)
	var one_tau: bool = per_motor.is_empty() and spin.has("tau_s")
	return TestResult.new(
		"the build carries one tau, which is why the overlay draws one curve",
		one_tau,
		"per-motor keys %s, tau_s present %s" % [str(per_motor), str(spin.has("tau_s"))])


# ---------------------------------------------------------------------------
# 7. The mapping
# ---------------------------------------------------------------------------

## Where the curve LANDS, provable without a window — the split the planform editor and the first
## three overlays already make.
##
## Three clauses, and none of them is implied by the others: t = 0 sits on the left edge at the
## floor, t = span sits on the right edge, and the 63% point — the one mark §4.1 asks for — sits
## at tau, which on a 5-tau axis is a fifth of the way across. A mapping that inverted Y or
## dropped the span would satisfy some of these and not all.
##
## MUTATION that turns this red: drop the `1.0 -` from the y term. Verified: the floor and the
## 63% clauses go red, the left-edge x clause stays green.
static func _test_the_curve_maps_onto_the_canvas() -> TestResult:
	var overlay := SpinUpOverlay.new()
	overlay.adopt(ReferenceBuild.build())
	overlay.size = Vector2(360.0, 210.0)
	var inner_w: float = 360.0 - SpinUpOverlay.MARGIN_PX * 2.0
	var inner_h: float = 210.0 - SpinUpOverlay.MARGIN_PX * 2.0

	var start := overlay.to_pixels(0.0, 0.0)
	var end := overlay.to_pixels(overlay.span_s(), overlay.final_rpm)
	var knee := overlay.to_pixels(overlay.tau_s,
		SpinUpOverlay.rpm_at(overlay.tau_s, overlay.tau_s, overlay.final_rpm))

	var at_origin: bool = is_equal_approx(start.x, SpinUpOverlay.MARGIN_PX) \
		and is_equal_approx(start.y, SpinUpOverlay.MARGIN_PX + inner_h)
	var at_top_right: bool = is_equal_approx(end.x, SpinUpOverlay.MARGIN_PX + inner_w) \
		and is_equal_approx(end.y, SpinUpOverlay.MARGIN_PX)
	# 1 - e^-1 of the way up, and a fifth of the way across on a 5-tau axis.
	var risen := 1.0 - (SpinUpOverlay.MARGIN_PX + inner_h - knee.y) / inner_h
	var knee_right: bool = absf(risen - exp(-1.0)) < 1.0e-6 \
		and absf(knee.x - (SpinUpOverlay.MARGIN_PX + inner_w / SpinUpOverlay.AXIS_SPAN_TAUS)) < 1.0e-4
	overlay.free()
	return TestResult.new(
		"t = 0, t = span and the 63% knee land where the axes say they do",
		at_origin and at_top_right and knee_right,
		"start %s, end %s, knee %s" % [str(start), str(end), str(knee)])
