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

	var rho_exact: bool = thin[0] == sea[0] and thin[1] == sea[1]
	var rpm_exact: bool = half[0] == sea[0] and half[1] == sea[1]
	var rpm_close: bool = absf(triple[0] / sea[0] - 1.0) < 1.0e-14 \
		and absf(triple[1] / sea[1] - 1.0) < 1.0e-14

	return [
		TestResult.new(
			"both ratios are BIT-IDENTICAL across a 1.6x air-density range — rho cancels exactly",
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
