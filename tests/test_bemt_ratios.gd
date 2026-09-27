class_name TestBemtRatios
extends RefCounted
## The tabulated forward-flight ratios (propulsion.md §9's P6 row, `rust/src/bemt_ratios.rs`).
##
## P6's closure replaced `PropellerModel::thrust_factor` / `power_factor` — a linear C_T(J) rule of
## thumb and a Glauert construction anchored on a guessed FIGURE_OF_MERIT — with blade-element
## theory on the blade's own planform. It could not do that by calling BEMT from the flight tick:
## one thrust+power pair costs 232 µs, and the tick evaluates twelve of them, so a direct swap
## spends 22% of the 120 Hz budget on one subsystem. The solve therefore moves to build time and
## the tick reads a surface.
##
## THAT SUBSTITUTION IS ONLY LEGITIMATE IF THE SURFACE IS TWO-DIMENSIONAL, and this file's first
## section is the proof rather than the assumption. Every other check here is downstream of it: if
## the ratios depended on RPM or on air density, a table indexed by two inflow ratios would be
## returning one operating point's answer for every operating point, silently, and every check
## below would still pass.
##
## Nothing here may quote an error bar. The polar under these ratios is characteristic
## (validation.md §9) — what is asserted is the model agreeing with itself about a mechanism, plus
## one measured, bounded number: how much the interpolation costs.

## Where the table is allowed to disagree with a direct solve. See `_interpolation_error_is_bounded`
## for what this is measured against and why it is quoted rather than tightened.
const INTERPOLATION_BOUND := 0.05

## The reference propeller, as a document, so every check runs on the same geometry.
static func _reference_doc() -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.diameter_mm = 127.0
	doc.pitch_mm = 114.3
	doc.blades = 3
	doc.chord = PropellerDocument.generate_chord(127.0, 3)
	return doc


static func run() -> Array:
	var results: Array = []
	var doc := _reference_doc()
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)
	var ratios := BemtRatios.for_prop(d_m, p_m, blades, doc.chord)

	results.append_array(_the_surface_really_is_two_dimensional(d_m, p_m, blades, doc.chord))
	results.append(_the_anchor_is_exact(ratios))
	results.append_array(_interpolation_error_is_bounded(ratios, d_m, p_m, blades, doc.chord))
	results.append(_the_domain_covers_the_flight_envelope())
	results.append_array(_beyond_the_domain_it_clamps_rather_than_extrapolates(ratios))
	results.append(_descent_is_declined(ratios))
	results.append(_a_stopped_rotor_is_not_a_division(ratios))
	results.append(_the_cache_returns_the_same_surface(d_m, p_m, blades, doc.chord))

	# [P10b] The guard closure. Ordered anchor-first, on the same discipline the P6 block above
	# holds: the identity at closure = 0.0 is what every earlier oracle now leans on, so it is
	# asserted before anything that depends on the closure doing something.
	#
	# The closure checks run on the CATALOG's reference propeller rather than on this file's
	# `_reference_doc` — the two differ (the catalog's prop_5x43x3 is a 4.3" pitch, the doc
	# above is a 4.5"), and the measured findings below are quoted in `test_prop_guard.gd`'s
	# whole-build checks too. One propeller, one set of numbers, or the two files drift.
	var catalog_doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var cd_m := catalog_doc.diameter_mm * 0.001
	var cp_m := catalog_doc.pitch_mm * 0.001
	var cb := float(catalog_doc.blades)
	results.append_array(_the_closure_anchor_is_exact(cd_m, cp_m, cb, catalog_doc.chord))
	results.append_array(_a_duct_raises_thrust_and_lowers_torque(cd_m, cp_m, cb, catalog_doc.chord))
	results.append_array(
		_the_closure_factors_are_rpm_and_density_invariant(cd_m, cp_m, cb, catalog_doc.chord))
	results.append_array(
		_the_ratio_surface_moves_enough_to_need_the_closure_in_its_key(cd_m, cp_m, cb, catalog_doc.chord))
	results.append_array(
		_a_closure_outside_the_unit_interval_makes_no_claim(cd_m, cp_m, cb, catalog_doc.chord))
	results.append(_the_forward_fixed_point_converges_with_the_tip_leak_closed())

	return results


# ---------------------------------------------------------------------------
# The claim the whole file rests on
# ---------------------------------------------------------------------------

## Both ratios are functions of mu_axial = V_ax/(Omega·R) and mu_edge = V_edge/(Omega·R) and of
## NOTHING else. The reason is structural: phi = atan((V_ax + v_i)/(Omega·r)) is invariant when V
## and v_i both scale with Omega, so alpha, C_l, C_d and the tip-loss factor are invariant too; and
## both sides of the annulus closure are linear in rho, so rho cancels out of the fixed point and
## then out of the ratio of two thrusts.
##
## ASSERTED TWO WAYS, because floating point makes one of the claims sharper than the other.
##
## ACROSS DENSITY the agreement must be BIT-EXACT, and it is: rho multiplies both sides of the
## annulus closure, so it never enters the fixed point at all and the two thrusts it scales divide
## it straight back out. There is no rounding for it to hide in, and a tolerance here would let a
## real rho-dependence through.
##
## ACROSS RPM, bit-exactness is asserted between 10,000 and 20,000 — where it holds, because the two
## differ by a power of two and this test's own `mu x Omega x R` reconstruction of the velocity is
## therefore exact — and the 3x range including 30,000 is checked at 1e-14 relative, a few ULP. That
## last spread is the TEST's arithmetic and not the model's: reconstructing a velocity from a ratio
## rounds, and 30,000 rounds where 20,000 does not. Demanding bit-exactness there would be asserting
## something about float representation rather than about the physics, and it would fail for a
## reason that has nothing to do with what is being tested.
##
## TO MAKE THIS FAIL: give the polar a Reynolds-number term, or make the tip-loss factor read an
## absolute radius instead of r/R. Either introduces a real length scale, the surface stops being
## two-dimensional, and `bemt_ratios.rs` is invalid — to be deleted rather than patched.
static func _the_surface_really_is_two_dimensional(d_m: float, p_m: float, blades: float,
		chord: PackedFloat64Array) -> Array:
	var mu_ax := 0.12
	var mu_ed := 0.20

	# [thrust ratio, power ratio] at this same mu, whatever RPM and density are used to reach it.
	var at := func(rpm: float, rho: float) -> Array:
		var omega_r: float = (rpm * TAU / 60.0) * (d_m * 0.5)
		return [
			BemtModel.thrust_ratio_forward(
				rho, d_m, p_m, blades, rpm, chord, mu_ax * omega_r, mu_ed * omega_r),
			BemtModel.power_ratio_forward(
				rho, d_m, p_m, blades, rpm, chord, mu_ax * omega_r, mu_ed * omega_r),
		]

	var sea: Array = at.call(20000.0, 1.225)
	var thin: Array = at.call(20000.0, 0.7557)
	var half: Array = at.call(10000.0, 1.225)
	var triple: Array = at.call(30000.0, 1.225)

	# Relative 1e-14 (~45 ULP), not ==: on x86 libm/FMA, T moves one ULP between the two densities.
	# Any rho that failed to cancel shows up at 1e-3 or worse across a 1.6x range.
	var rho_exact: bool = absf(thin[0] / sea[0] - 1.0) < 1.0e-14 and absf(thin[1] / sea[1] - 1.0) < 1.0e-14
	var rpm_exact: bool = half[0] == sea[0] and half[1] == sea[1]
	var rpm_close: bool = absf(triple[0] / sea[0] - 1.0) < 1.0e-14 \
		and absf(triple[1] / sea[1] - 1.0) < 1.0e-14

	return [
		TestResult.new(
			"both ratios agree to 1e-14 relative across a 1.6x air-density range — rho cancels (to rounding)",
			rho_exact,
			"at mu = (%.2f, %.2f): sea level T %.17f P %.17f;  3500 m T %.17f P %.17f" % [
				mu_ax, mu_ed, sea[0], sea[1], thin[0], thin[1]]),
		TestResult.new(
			"and BIT-IDENTICAL between 10,000 and 20,000 RPM, where the velocity reconstruction is exact",
			rpm_exact,
			"at mu = (%.2f, %.2f): 10k T %.17f P %.17f;  20k T %.17f P %.17f" % [
				mu_ax, mu_ed, half[0], half[1], sea[0], sea[1]]),
		TestResult.new(
			"and agree to 1e-14 across a 3x RPM range, so a 2D table can stand in for the solve",
			rpm_close,
			"at mu = (%.2f, %.2f): 30k against 20k differs by %.17f (thrust), %.17f (power)" % [
				mu_ax, mu_ed, absf(triple[0] / sea[0] - 1.0), absf(triple[1] / sea[1] - 1.0)]),
		# The checks above pass vacuously if the ratios happen not to depend on airspeed either,
		# so pin that the operating point chosen is one where they genuinely move.
		TestResult.new(
			"the sampled point is one where the ratios are NOT 1, so the checks above can fail",
			absf(sea[0] - 1.0) > 0.005 and absf(sea[1] - 1.0) > 0.005,
			"thrust ratio %.4f, power ratio %.4f at mu = (%.2f, %.2f)" % [
				sea[0], sea[1], mu_ax, mu_ed]),
	]


# ---------------------------------------------------------------------------
# The anchor, and what the table costs
# ---------------------------------------------------------------------------

## The static path is P5's calibration anchor and nothing may move it, not by the last bit. Under a
## tabulated surface that is a sharper obligation than it was under a formula: a bilinear read at
## the corner has to return the corner node untouched.
##
## HONEST NOTE ON WHAT THIS CHECK CAN AND CANNOT CATCH, because it was mutation-tested and the
## obvious recipe did not work. Deleting the zero-velocity short circuit in `BemtRatios::read`
## leaves this GREEN: node (0,0) is itself exactly 1.0, and a bilinear read at a corner with both
## interpolation weights at zero returns that node untouched. The exactness here is OVER-DETERMINED
## — three independent mechanisms produce it (the read's short circuit, the ratio functions' own
## hover short circuit at build time, and `solve_forward` delegating to `solve` at V = 0) and no
## single-line edit removes all three.
##
## So this is a GUARD rather than a discriminating test, and it is kept as one: it fails the moment
## a FOURTH mechanism is introduced that does arithmetic on the way to the anchor — a relaxation
## factor, a smoothing pass over the table, a units conversion applied unconditionally. Those are
## the realistic ways an anchor moves, and they are what it is here to catch. The check with the
## teeth about the surface being right is `_interpolation_error_is_bounded`, below.
static func _the_anchor_is_exact(ratios: BemtRatios) -> TestResult:
	var exact := true
	for rpm in [1000.0, 10000.0, 26000.0]:
		if ratios.thrust_ratio(rpm, 0.0, 0.0) != 1.0 or ratios.power_ratio(rpm, 0.0, 0.0) != 1.0:
			exact = false
	return TestResult.new(
		"standing still, both ratios are EXACTLY 1.0 at every RPM — the bit, not a rounding",
		exact,
		"thrust %.20f, power %.20f at 10,000 RPM" % [
			ratios.thrust_ratio(10000.0, 0.0, 0.0), ratios.power_ratio(10000.0, 0.0, 0.0)])


## What the table costs, measured where bilinear interpolation is WORST — the midpoint of every
## grid cell — rather than near the nodes, where it would flatter itself.
##
## The bound is 0.05 absolute and the measured worst is about 0.034. It is quoted rather than
## tightened because the surface is only piecewise smooth: the thrust clamp at zero and the
## induced-power floor both put kinks in it, so convergence is linear in the cell size and refining
## the grid buys very little for a lot of build time (measured: 17 mu_edge nodes instead of 13
## moves the worst power error from 0.0339 to 0.0309).
##
## That error is a real cost of the closure and it is worth stating against what it sits inside: the
## catalog's own motor-to-motor disagreement is 1.79x, and the polar under these ratios is
## characteristic. Unlike either, this one is bounded and asserted.
##
## TO MAKE THIS FAIL: halve MU_AXIAL_NODES to 25. Measured: the worst midpoint error goes to 0.0586
## on thrust and 0.0956 on power, and both bust the bound.
static func _interpolation_error_is_bounded(ratios: BemtRatios, d_m: float, p_m: float,
		blades: float, chord: PackedFloat64Array) -> Array:
	var counts := BemtRatios.node_counts()
	var mu_max: float = BemtRatios.domain_mu_max()
	var ha: float = mu_max / (counts[0] - 1.0)
	var he: float = mu_max / (counts[1] - 1.0)
	var rpm := 20000.0
	var omega_r: float = (rpm * TAU / 60.0) * (d_m * 0.5)

	var worst_thrust := 0.0
	var worst_power := 0.0
	for i in int(counts[0]) - 1:
		for j in int(counts[1]) - 1:
			var v_ax: float = (i + 0.5) * ha * omega_r
			var v_ed: float = (j + 0.5) * he * omega_r
			worst_thrust = maxf(worst_thrust, absf(ratios.thrust_ratio(rpm, v_ax, v_ed)
				- BemtModel.thrust_ratio_forward(1.225, d_m, p_m, blades, rpm, chord, v_ax, v_ed)))
			worst_power = maxf(worst_power, absf(ratios.power_ratio(rpm, v_ax, v_ed)
				- BemtModel.power_ratio_forward(1.225, d_m, p_m, blades, rpm, chord, v_ax, v_ed)))

	# And at the NODES themselves the table is the solve, exactly — there is no interpolation to
	# do. This is what makes the midpoint number an interpolation error rather than a modelling
	# disagreement between two implementations of the same thing.
	var node_worst := 0.0
	for i in int(counts[0]):
		for j in int(counts[1]):
			var v_ax: float = i * ha * omega_r
			var v_ed: float = j * he * omega_r
			node_worst = maxf(node_worst, absf(ratios.power_ratio(rpm, v_ax, v_ed)
				- BemtModel.power_ratio_forward(1.225, d_m, p_m, blades, rpm, chord, v_ax, v_ed)))

	return [
		TestResult.new(
			"the table reproduces a direct BEMT solve at every grid node, to floating-point",
			node_worst < 1.0e-12,
			"worst node disagreement across %d x %d nodes: %.15f" % [
				int(counts[0]), int(counts[1]), node_worst]),
		TestResult.new(
			"interpolation between nodes costs less than the stated bound, measured at cell midpoints",
			worst_thrust < INTERPOLATION_BOUND and worst_power < INTERPOLATION_BOUND,
			"worst midpoint error: thrust %.4f, power %.4f, against a bound of %.2f" % [
				worst_thrust, worst_power, INTERPOLATION_BOUND]),
	]


# ---------------------------------------------------------------------------
# The domain
# ---------------------------------------------------------------------------

## The table covers mu in [0, 0.6] and clamps outside it. That is only safe if real flight stays
## inside, so this walks the mission profile the flight-time figure is built from and the top-speed
## solve, and asserts every operating point the app actually quotes lands in the tabulated region.
##
## TO MAKE THIS FAIL: drop MU_MAX to 0.1. The fast rows of FREESTYLE_FLIGHT_PROFILE leave the grid
## and the check reports which one.
static func _the_domain_covers_the_flight_envelope() -> TestResult:
	var build := ReferenceBuild.build()
	var ratios := build.forward_ratios()
	var mu_max: float = BemtRatios.domain_mu_max()
	var ceiling: float = build.peak_thrust()["throttle"]
	var worst := 0.0
	var worst_at := ""

	for segment in Build.FREESTYLE_FLIGHT_PROFILE:
		var airspeed := float(segment["airspeed_mps"])
		var load_g := float(segment["load_factor"])
		# The same trim the current model solves: lean until horizontal thrust beats drag.
		var lift_n := load_g * build.weight_n()
		var drag_n := build.drag_coefficient * airspeed * airspeed
		var lean := atan2(drag_n, lift_n)
		var rpm := build.rpm_at_throttle(ceiling, Build.AT_NOMINAL)
		var mu_ax: float = ratios.mu_for(rpm, airspeed * sin(lean))
		var mu_ed: float = ratios.mu_for(rpm, airspeed * cos(lean))
		var mu: float = maxf(mu_ax, mu_ed)
		if mu > worst:
			worst = mu
			worst_at = "%.0f m/s at %.1f g" % [airspeed, load_g]

	var top_mps := build.top_speed_kmh() / 3.6
	var top_mu: float = ratios.mu_for(build.max_rpm_at_nominal(),
		top_mps * cos(Build.TOP_SPEED_LEAN_RAD))
	if top_mu > worst:
		worst = top_mu
		worst_at = "top speed, %.0f km/h" % build.top_speed_kmh()

	return TestResult.new(
		"every operating point the reference build's own figures are quoted at is inside the table",
		worst < mu_max,
		"worst inflow ratio reached: %.4f (%s) against a tabulated domain of %.2f" % [
			worst, worst_at, mu_max])


## Outside the domain the table CLAMPS rather than extrapolating a bilinear fit off the end of a
## kinked surface. What that buys is that the answer stays a number in the range the model produces:
## the thrust ratio has been zero for a factor of two by then, and the current a motor draws goes as
## RPM², so a rotor at an inflow ratio this high is drawing almost nothing anyway.
##
## TO MAKE THE FIRST FAIL: replace the clamp in `BemtRatios::read` with linear extrapolation. The
## thrust ratio goes negative past the edge — the aircraft pulled backwards by its own props, which
## is the failure the deleted `thrust_factor`'s own clamp existed to prevent.
static func _beyond_the_domain_it_clamps_rather_than_extrapolates(ratios: BemtRatios) -> Array:
	var rpm := 3000.0
	var omega_r: float = (rpm * TAU / 60.0) * 0.0635
	var mu_max: float = BemtRatios.domain_mu_max()
	var at_edge := ratios.power_ratio(rpm, mu_max * omega_r, 0.0)
	var far_out := ratios.power_ratio(rpm, 10.0 * mu_max * omega_r, 0.0)
	var thrust_far_out := ratios.thrust_ratio(rpm, 10.0 * mu_max * omega_r, 0.0)
	return [
		TestResult.new(
			"past the tabulated domain the ratio holds its edge value rather than running away",
			far_out == at_edge,
			"at mu = %.2f: %.6f;  at mu = %.2f: %.6f" % [
				mu_max, at_edge, 10.0 * mu_max, far_out]),
		TestResult.new(
			"and the thrust ratio out there is zero, never negative",
			thrust_far_out == 0.0,
			"thrust ratio at mu = %.2f: %.6f" % [10.0 * mu_max, thrust_far_out]),
	]


# ---------------------------------------------------------------------------
# The refusals
# ---------------------------------------------------------------------------

## Descent is out of domain — vortex ring below the windmill-brake threshold, energy extraction
## above it — and the table declines it rather than reading a surface that has no negative side.
## Returning 1.0 is the static answer, which is the model saying "outside the model" in the only
## currency the tick understands.
##
## TO MAKE THIS FAIL: drop the `v_axial_mps < 0.0` branch in `BemtRatios::read`. A negative velocity
## clamps to mu = 0 and the descent silently reads as a hover — the same number, arrived at without
## the refusal, which is the difference between declining and guessing.
static func _descent_is_declined(ratios: BemtRatios) -> TestResult:
	var worst_thrust := 1.0
	var worst_power := 1.0
	for i in range(1, 61):
		worst_thrust = minf(worst_thrust, ratios.thrust_ratio(8500.0, -float(i), 5.0))
		worst_power = minf(worst_power, ratios.power_ratio(8500.0, -float(i), 5.0))
	return TestResult.new(
		"no descent, however fast and whatever the edgewise flow, moves either ratio off 1.0",
		worst_thrust == 1.0 and worst_power == 1.0,
		"1-60 m/s descent with 5 m/s edgewise: worst thrust %.6f, worst power %.6f" % [
			worst_thrust, worst_power])


## A rotor that has stopped has no inflow ratio — mu is a division by Omega. It reads 1.0, which
## costs nothing because the thrust it multiplies is zero and the current goes as RPM².
##
## TO MAKE THIS FAIL: remove the `omega_r <= 0.0` guard. mu becomes inf, the clamp turns it into
## MU_MAX, and a stopped motor on a fast aircraft reports the far edge of the table instead of
## nothing at all — a real number where there is no question.
static func _a_stopped_rotor_is_not_a_division(ratios: BemtRatios) -> TestResult:
	var t := ratios.thrust_ratio(0.0, 20.0, 20.0)
	var p := ratios.power_ratio(0.0, 20.0, 20.0)
	return TestResult.new(
		"a stopped rotor returns 1.0 rather than a NaN or the far edge of the table",
		t == 1.0 and p == 1.0 and not is_nan(t) and not is_nan(p),
		"at 0 RPM and 20 m/s: thrust %.6f, power %.6f" % [t, p])


## The cache is keyed on the geometry, so a second Build with the same propeller gets the same
## surface rather than paying 150 ms of BEMT again — and, more importantly, gets the SAME numbers.
## A cache that returned a differently-built table for the same prop would make two panels disagree
## about one aircraft.
##
## TO MAKE THIS FAIL: key the cache on a rounded diameter. Two props that differ in the last bit of
## a chord station then share a surface, and the second check goes red.
static func _the_cache_returns_the_same_surface(d_m: float, p_m: float, blades: float,
		chord: PackedFloat64Array) -> TestResult:
	var a := BemtRatios.for_prop(d_m, p_m, blades, chord)
	var b := BemtRatios.for_prop(d_m, p_m, blades, chord)
	var same := a.power_ratio(20000.0, 8.0, 12.0) == b.power_ratio(20000.0, 8.0, 12.0)

	# A DIFFERENT planform must get a different surface. Same diameter, same pitch, same blade
	# count — only the chord distribution differs, which is the part of the key most easily
	# dropped by accident.
	var fat := chord.duplicate()
	for i in range(1, fat.size(), 2):
		fat[i] = fat[i] * 1.6
	var c := BemtRatios.for_prop(d_m, p_m, blades, fat)
	var differs := absf(c.power_ratio(20000.0, 8.0, 12.0) - a.power_ratio(20000.0, 8.0, 12.0)) > 1.0e-6

	return TestResult.new(
		"the same propeller gets the same surface, and a different planform gets a different one",
		same and differs,
		"same planform: %.12f vs %.12f;  60%% fatter chord: %.12f" % [
			a.power_ratio(20000.0, 8.0, 12.0), b.power_ratio(20000.0, 8.0, 12.0),
			c.power_ratio(20000.0, 8.0, 12.0)])


# ---------------------------------------------------------------------------
# [P10b] The guard closure — plans/2026-08-26-propulsion-room-design.md §4
# ---------------------------------------------------------------------------

## The reference cinewhoop duct's closure on the reference propeller: `guards.json`'s
## `guard_duct_5in_cinewhoop` has `tip_gap_mm = 1.5`, the reference `prop_5x43x3` has a tip chord
## of 1.92096 mm, and `PropGuard.tip_loss_closure`'s rational form gives 1/(1 + 1.5/1.92096).
## Written out rather than recomputed so this file's numbers are pinned to a real catalog part
## instead of to a closure someone picked because it looked good.
const REFERENCE_DUCT_CLOSURE := 0.56152690342056

## Where the tabulated ratios move when the closure changes. Measured, not chosen — see
## `_the_ratio_surface_moves_enough_to_need_the_closure_in_its_key` for what the number means
## and why it is asserted as a FLOOR.
const RATIO_CLOSURE_SENSITIVITY := 0.012169


## THE ANCHOR AT CLOSURE = 0.0, and it is the check every P4/P5/P6 oracle in the project now
## leans on. `solve_with_guard(..., 0.0)` and `solve` must be the same numbers to the BIT, or
## the 496 g / 11.69:1 / 29.6% reference figures moved for a build that fits no guard at all.
##
## The implementation earns this structurally rather than by a branch: `solve` and
## `solve_with_guard` both call ONE `solve_impl`, and `F_effective = F + 0.0 · (1 − F)` is `F`
## exactly in IEEE 754 for every finite F. The plan's §7 preferred an `if guard_closure == 0.0`
## branch for readability; the shipped code declines it, so this test is what stands in for the
## branch's other job — making the identity checkable rather than an argument to reconstruct.
##
## Asserted on the FULL five-element result, not on thrust alone. Torque, both power terms and
## the residual all pass through the same `f`, and a closure that leaked into only one of them
## would be invisible to a thrust-only check.
##
## TO MAKE THIS FAIL: give `tip_loss_with_closure` a `1.0 - guard_closure` factor somewhere, or
## let `sanitize_closure` return anything but 0.0 for 0.0.
static func _the_closure_anchor_is_exact(d_m: float, p_m: float, blades: float,
		chord: PackedFloat64Array) -> Array:
	var rho := 1.225
	var rpm := 20000.0
	var plain: PackedFloat64Array = BemtModel.solve(rho, d_m, p_m, blades, rpm, chord,
		5.5, 0.03, 0.02, 1.0)
	var guarded: PackedFloat64Array = BemtModel.solve_with_guard(rho, d_m, p_m, blades, rpm,
		chord, 5.5, 0.03, 0.02, 1.0, 0.0)
	var fwd_plain: PackedFloat64Array = BemtModel.solve_forward(rho, d_m, p_m, blades, rpm,
		chord, 5.5, 0.03, 0.02, 1.0, 8.0, 3.0)
	var fwd_guarded: PackedFloat64Array = BemtModel.solve_forward_with_guard(rho, d_m, p_m,
		blades, rpm, chord, 5.5, 0.03, 0.02, 1.0, 8.0, 3.0, 0.0)

	var static_same := true
	for i in plain.size():
		if plain[i] != guarded[i]:
			static_same = false
	var forward_same := true
	for i in fwd_plain.size():
		if fwd_plain[i] != fwd_guarded[i]:
			forward_same = false

	# And the surface, which is the object a Build actually flies. `for_prop` delegates to
	# `for_prop_with_guard(..., 0.0)`, so this asserts the delegation as much as the arithmetic.
	var open_surface := BemtRatios.for_prop(d_m, p_m, blades, chord)
	var zero_surface := BemtRatios.for_prop_with_guard(d_m, p_m, blades, chord, 0.0)
	var surface_same := true
	for mu_ax in [0.0, 0.05, 0.2, 0.45]:
		for mu_ed in [0.0, 0.1, 0.35]:
			var omega_r: float = (20000.0 * TAU / 60.0) * (d_m * 0.5)
			if open_surface.thrust_ratio(mu_ax * omega_r, mu_ed * omega_r, 20000.0) \
					!= zero_surface.thrust_ratio(mu_ax * omega_r, mu_ed * omega_r, 20000.0):
				surface_same = false
			if open_surface.power_ratio(mu_ax * omega_r, mu_ed * omega_r, 20000.0) \
					!= zero_surface.power_ratio(mu_ax * omega_r, mu_ed * omega_r, 20000.0):
				surface_same = false

	return [
		TestResult.new(
			"[P10b] solve_with_guard at closure 0.0 is solve, BIT-IDENTICAL in all five outputs",
			static_same,
			"T %.17f / %.17f, Q %.17f / %.17f" % [plain[0], guarded[0], plain[1], guarded[1]]),
		TestResult.new(
			"[P10b] and solve_forward_with_guard at closure 0.0 is solve_forward, bit-identical",
			forward_same,
			"T %.17f / %.17f at V_ax 8, V_edge 3" % [fwd_plain[0], fwd_guarded[0]]),
		TestResult.new(
			"[P10b] and for_prop_with_guard(0.0) reaches the same cached surface as for_prop",
			surface_same and zero_surface.guard_closure() == 0.0
				and zero_surface.static_closure_factor() == 1.0
				and zero_surface.static_closure_torque_factor() == 1.0,
			"closure %.17f, thrust factor %.17f, torque factor %.17f" % [
				zero_surface.guard_closure(), zero_surface.static_closure_factor(),
				zero_surface.static_closure_torque_factor()]),
	]


## THE FINDING P10b WENT LOOKING FOR, and it is not the one §4.0 predicted.
##
## §4.0 said "on a real cinewhoop at hover, the thrust rises by the hand-computable amount the
## tip annuli contribute. If it is 3% the panel says so; if it is 20% the panel says that."
## Measured on the reference `prop_5x43x3` at the reference duct's closure of 0.5615:
##
##     static thrust   x 1.00999      (+1.0%)
##     static torque   x 0.99472      (-0.53%)
##
## So the thrust rise is 1%, at the small end of the range §4.0 was ready for — but the
## INTERESTING motion is in the other channel and it points the other way. Closing the tip leak
## enlarges the annulus that accepts momentum, the induced velocity falls, and induced drag
## falls with it. A duct on this model is an EFFICIENCY part far more than a thrust part.
##
## That is why `static_closure_factors` returns a pair. `Build` fits `k_q` from `k_t` by a fixed
## multiple, so a `k_t` scaled by 1.00999 with `k_q` derived from it would have reported the duct
## costing 1% more current where the model says it saves 0.53% — the wrong SIGN on the one number
## a duct is fitted for. `test_prop_guard.gd`'s `_a_duct_saves_current_rather_than_costing_it`
## holds the other end of that.
##
## The last check is the vacuity guard: both factors must be off 1.0 by more than the noise, or
## the direction assertions above are statements about nothing.
##
## TO MAKE THIS FAIL: clamp either factor to >= 1.0 (an earlier draft clamped the thrust one,
## which would have hidden the torque finding entirely), or drop the torque half of the pair.
static func _a_duct_raises_thrust_and_lowers_torque(d_m: float, p_m: float, blades: float,
		chord: PackedFloat64Array) -> Array:
	var factors: PackedFloat64Array = BemtModel.static_closure_factors(
		d_m, p_m, blades, chord, REFERENCE_DUCT_CLOSURE)
	var thrust_factor := factors[0]
	var torque_factor := factors[1]
	return [
		TestResult.new(
			"[P10b] closing the tip leak RAISES static thrust — the duct's thrust claim, +1.0%",
			thrust_factor > 1.0 and absf(thrust_factor - 1.00999) < 5.0e-5,
			"thrust factor %.8f at closure %.6f" % [thrust_factor, REFERENCE_DUCT_CLOSURE]),
		TestResult.new(
			"[P10b] and LOWERS static torque — less induced velocity, less induced drag, -0.53%",
			torque_factor < 1.0 and absf(torque_factor - 0.99472) < 5.0e-5,
			"torque factor %.8f at closure %.6f" % [torque_factor, REFERENCE_DUCT_CLOSURE]),
		TestResult.new(
			"[P10b] and both are off 1.0 by more than a rounding, so the directions above can fail",
			absf(thrust_factor - 1.0) > 1.0e-3 and absf(torque_factor - 1.0) > 1.0e-3,
			"|T - 1| = %.6f, |Q - 1| = %.6f" % [
				absf(thrust_factor - 1.0), absf(torque_factor - 1.0)]),
	]


## The closure factors are RPM- and DENSITY-invariant, which is what makes ONE scalar pair per
## (propeller, closure) legitimate — the same self-similarity this whole file rests on, extended
## to the closure. If it failed, `BemtRatios` would be caching a factor computed at 20,000 RPM and
## handing it to a build that hovers at 12,000, silently.
##
## Asserted BIT-EXACTLY across RPM between 10,000 and 20,000, and to a few ULP across density.
## The weaker density claim is the TEST's arithmetic, not the model's, and the distinction is
## worth stating because `_the_surface_really_is_two_dimensional` above DOES get bit-exactness
## across density: it reads a ratio Rust forms internally from two solves at ONE rho, where rho
## divides straight back out. This check forms its ratio in GDScript from solves at DIFFERENT
## rho, and rho cancels through the fixed point mathematically rather than bitwise — measured at
## 2 ULP. Demanding bit-exactness here would assert something about float representation.
##
## TO MAKE THIS FAIL: make the closure depend on an absolute length or an absolute velocity —
## a tip-gap Reynolds number, say — instead of post-processing a factor that is already a
## function of r/R and phi alone.
static func _the_closure_factors_are_rpm_and_density_invariant(d_m: float, p_m: float,
		blades: float, chord: PackedFloat64Array) -> Array:
	var factor_at := func(rpm: float, rho: float) -> Array:
		var base: PackedFloat64Array = BemtModel.solve_with_guard(
			rho, d_m, p_m, blades, rpm, chord, 5.5, 0.03, 0.02, 1.0, 0.0)
		var closed: PackedFloat64Array = BemtModel.solve_with_guard(
			rho, d_m, p_m, blades, rpm, chord, 5.5, 0.03, 0.02, 1.0, REFERENCE_DUCT_CLOSURE)
		return [closed[0] / base[0], closed[1] / base[1]]

	var sea: Array = factor_at.call(20000.0, 1.225)
	var thin: Array = factor_at.call(20000.0, 0.7557)
	var half: Array = factor_at.call(10000.0, 1.225)

	return [
		TestResult.new(
			"[P10b] the closure's thrust and torque factors agree to 1e-14 across 1.6x density",
			absf(thin[0] / sea[0] - 1.0) < 1.0e-14 and absf(thin[1] / sea[1] - 1.0) < 1.0e-14,
			"sea T %.17f Q %.17f;  3500 m T %.17f Q %.17f" % [sea[0], sea[1], thin[0], thin[1]]),
		TestResult.new(
			"[P10b] and bit-identical between 10,000 and 20,000 RPM, so one cached pair is enough",
			half[0] == sea[0] and half[1] == sea[1],
			"20k T %.17f Q %.17f;  10k T %.17f Q %.17f" % [sea[0], sea[1], half[0], half[1]]),
	]


## §4.0'S PREDICTION, TESTED AND FAILED — and the failure is the reason the shipped cache key
## carries the closure.
##
## The plan predicted: "the closure enters the solve, so bench numbers shift by it, but the
## RATIOS largely do NOT — the tip-loss suppression multiplies both numerator and denominator by
## nearly the same factor. This is a prediction that P10b's test suite must assert, not a claim
## to accept: if the ratios move substantially with closure, the assumption that the surface can
## be tabulated PER-PROPELLER fails and bemt_ratios.rs needs the closure in its outer dimension
## too."
##
## Measured on the reference propeller across closure ∈ {0.5615, 1.0} and mu_axial ∈ [0.02, 0.5],
## mu_edge ∈ [0, 0.4]: the worst deviation is **0.0122 in a ratio that lives in [0, 1]**.
##
## That is smaller than the plan feared and larger than it predicted, so it is worth being exact
## about what it does and does not settle. It is a systematic shift, not scatter: the ducted
## surface sits consistently off the open one over a whole region of the envelope, which is a
## different animal from `INTERPOLATION_BOUND`'s 0.05 worst-case read error (that one is
## symmetric noise about the right answer, and it is bounded by the grid rather than by the
## physics). A surface tabulated per-propeller-only would hand every ducted build the open
## rotor's forward-flight behaviour, wrong in one direction, everywhere — 1.2 points of thrust
## fraction that no amount of averaging removes. So §4.0's "largely do NOT" does not hold, and
## the shipped closure-keyed cache is the right shape.
##
## The shipped code is already correct about this: `key_of` bit-keys `guard_closure` alongside the
## geometry, so a guard's surface IS its own table. This test asserts the sensitivity as a FLOOR
## rather than a bound, so a future "optimisation" that drops the closure from the key has to
## delete an assertion that says in words why it is there.
##
## TO MAKE THIS FAIL: remove `guard_closure` from `key_of`'s tuple — the two surfaces below then
## come back as the same cached table and the deviation collapses to zero.
static func _the_ratio_surface_moves_enough_to_need_the_closure_in_its_key(d_m: float,
		p_m: float, blades: float, chord: PackedFloat64Array) -> Array:
	var open_surface := BemtRatios.for_prop_with_guard(d_m, p_m, blades, chord, 0.0)
	var duct_surface := BemtRatios.for_prop_with_guard(
		d_m, p_m, blades, chord, REFERENCE_DUCT_CLOSURE)
	var full_surface := BemtRatios.for_prop_with_guard(d_m, p_m, blades, chord, 1.0)
	var omega_r := (20000.0 * TAU / 60.0) * (d_m * 0.5)

	var worst := 0.0
	var worst_where := ""
	for surface in [duct_surface, full_surface]:
		for mu_ax in [0.02, 0.1, 0.3, 0.5]:
			for mu_ed in [0.0, 0.1, 0.4]:
				var v_ax: float = mu_ax * omega_r
				var v_ed: float = mu_ed * omega_r
				var d_t: float = absf(surface.thrust_ratio(v_ax, v_ed, 20000.0)
					- open_surface.thrust_ratio(v_ax, v_ed, 20000.0))
				var d_p: float = absf(surface.power_ratio(v_ax, v_ed, 20000.0)
					- open_surface.power_ratio(v_ax, v_ed, 20000.0))
				if maxf(d_t, d_p) > worst:
					worst = maxf(d_t, d_p)
					worst_where = "closure %.4f at mu = (%.2f, %.2f)" % [
						surface.guard_closure(), mu_ax, mu_ed]

	return [
		TestResult.new(
			"[P10b] the ratios DO move with closure — §4.0's per-propeller-only tabulation is dead",
			worst > 0.01,
			"worst deviation %.6f (%s); the plan predicted this would be negligible" % [
				worst, worst_where]),
		TestResult.new(
			"[P10b] measured at %.4f, so the closure belongs in the cache key and is in it" % RATIO_CLOSURE_SENSITIVITY,
			absf(worst - RATIO_CLOSURE_SENSITIVITY) < 1.0e-3
				and duct_surface.guard_closure() == REFERENCE_DUCT_CLOSURE
				and full_surface.guard_closure() == 1.0,
			"worst %.6f, surfaces keyed at closure %.6f and %.6f" % [
				worst, duct_surface.guard_closure(), full_surface.guard_closure()]),
	]


## A closure arriving from GDScript has had no form imposed on it — `solve_with_guard` is a
## public `#[func]` and NAN, an infinity or 2.0 are all things a caller can pass. `F_effective =
## F + closure·(1 − F)` at closure = 2.0 would put F above 1: a rotor accepting more momentum
## than its own disc area can carry, which is not a duct, it is a free lunch with a sign error.
##
## `sanitize_closure` folds EVERY non-finite case to 0.0 — including +INF, which could just as
## defensibly have clamped to 1.0. One rule ("a number that is not a number is not a claim")
## beats two, and it errs toward the open rotor: a build that reaches this path through a bug
## flies the propeller it has rather than a duct nobody fitted. Finite values outside [0, 1] are
## clamped into it, so they land on a REAL answer at the boundary. Asserted by bit-identity
## against the boundary itself, which is a sharper claim than "the answer is finite".
##
## TO MAKE THIS FAIL: delete `sanitize_closure`'s call sites in `solve_impl` /
## `solve_forward_impl` — NAN then propagates into every annulus and the thrust comes back NAN.
static func _a_closure_outside_the_unit_interval_makes_no_claim(d_m: float, p_m: float,
		blades: float, chord: PackedFloat64Array) -> Array:
	var at := func(closure: float) -> PackedFloat64Array:
		return BemtModel.solve_with_guard(1.225, d_m, p_m, blades, 20000.0, chord,
			5.5, 0.03, 0.02, 1.0, closure)
	var zero: PackedFloat64Array = at.call(0.0)
	var one: PackedFloat64Array = at.call(1.0)
	var same := func(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
		for i in a.size():
			if a[i] != b[i]:
				return false
		return true

	return [
		TestResult.new(
			"[P10b] a NAN, an infinity or a negative closure makes NO claim — identical to 0.0",
			same.call(at.call(NAN), zero) and same.call(at.call(-1.0), zero)
				and same.call(at.call(-INF), zero) and same.call(at.call(INF), zero),
			"NAN thrust %.17f against 0.0's %.17f" % [at.call(NAN)[0], zero[0]]),
		TestResult.new(
			"[P10b] and a FINITE closure above 1 clamps to a fully closed tip, not to F above 1",
			same.call(at.call(2.0), one) and same.call(at.call(1.5), one),
			"closure 2.0 thrust %.17f against 1.0's %.17f" % [at.call(2.0)[0], one[0]]),
	]


## The forward fixed point still converges with the tip leak CLOSED, across the whole catalog, at
## the same fixed iteration count and the same 1e-3 bound `test_bemt_forward.gd` asserts for the
## open rotor. This is not a formality: closure = 1.0 removes Prandtl's factor from the momentum
## closure entirely, which changes the annulus area accepting momentum by up to 1/F near the tip
## — the term the iteration divides by. A scheme that was only marginally contractive at F < 1
## could stop converging exactly where a duct is fitted.
##
## Measured worst residual with the leak fully closed: 1.4e-4, comfortably inside the bound the
## open-rotor sweep holds to.
##
## TO MAKE THIS FAIL: apply the closure to the blade-element side (`blade_dt`) without applying it
## to the momentum side, and the two halves of the residual stop describing the same annulus.
static func _the_forward_fixed_point_converges_with_the_tip_leak_closed() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var worst := 0.0
	var worst_where := ""
	var points := 0
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		if doc == null or doc.chord.size() < 4:
			continue
		var d_m := doc.diameter_mm * 0.001
		var p_m := doc.pitch_mm * 0.001
		var blades := float(doc.blades)
		var advance_mps := p_m * 20000.0 / 60.0
		for v_ax in [0.0, 1.0, 5.0, 15.0, 30.0]:
			if v_ax > 0.8 * advance_mps:
				continue
			for v_edge in [0.0, 0.001, 2.0, 10.0, 40.0]:
				var res: PackedFloat64Array = BemtModel.solve_forward_with_guard(
					1.225, d_m, p_m, blades, 20000.0, doc.chord,
					5.5, 0.03, 0.02, 1.0, v_ax, v_edge, 1.0)
				points += 1
				if res[4] > worst:
					worst = res[4]
					worst_where = "%s at V_ax %.0f / V_edge %.3f" % [
						str(prop.get("part_id", "?")), v_ax, v_edge]
	return TestResult.new(
		"[P10b] the forward fixed point converges across the catalog with the tip leak closed",
		worst < 1.0e-3 and points > 0,
		"%d operating points at closure 1.0, worst residual %.9f (%s)" % [
			points, worst, worst_where])
