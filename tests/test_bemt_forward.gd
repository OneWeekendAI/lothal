class_name TestBemtForward
extends RefCounted
## BEMT forward flight (P6) — propulsion.md §4.1 with V_ax ≠ 0, and the descent refusal.
##
## Four proof obligations from §9's P6 row, each with a "to make this fail" note in the same
## voice test_forward_flight.gd uses. The physics lives in BemtModel::solve_forward /
## thrust_ratio_forward / power_ratio_forward; every number here is an outcome of the compiled
## core rather than a re-derivation in GDScript.
##
##   1. HOVER IDENTITY. At V_ax = V_edge = 0 the forward-flight solve is the static solve, and
##      the two ratios are exactly 1.0 by SHORT CIRCUIT — the same discipline test_calibration
##      uses so the reference build's oracles (496.0 g / 11.69:1 / 29.6%) cannot move by the
##      millimetre of a rounding difference between two integrals that are analytically equal.
##   2. THRUST FALLS WITH AIRSPEED. At fixed RPM the axial-inflow term unloads the disc, so
##      thrust_ratio_forward is monotone-decreasing in V_ax and clamps at [0, 1] rather than
##      admitting a claim of reversed thrust past the geometric advance.
##   3. THE U-SHAPED POWER CURVE SURVIVES. Sweeping the edgewise velocity across a real range,
##      power_ratio_forward has a MINIMUM at neither end — the classical rotorcraft result, and
##      P6's headline: it falls out of the two quadratures with no FIGURE_OF_MERIT input.
##   4. DESCENT REFUSES. For every V_ax < 0, both ratios return exactly 1.0 (the static answer,
##      the model declining to answer) rather than a converged number from a fixed point with
##      no contractivity in that region. This is the propeller.rs guard's argument, translated:
##      a quad in a descent must not charge its own pack.
##
## Nothing here may quote an error bar. The model is characteristic (validation.md §9's rule):
## no manufacturer publishes C_T(J) for an FPV propeller, so every figure asserted below is
## the model agreeing with itself about a mechanism, never a measurement.

const REFERENCE_PROP_ID := "prop_5x43x2"
const REFERENCE_RPM := 20000.0
const REFERENCE_RHO := 1.225


static func run() -> Array:
	var results: Array = []
	var doc := _catalog_prop("prop_5x43x2")
	if doc == null:
		results.append(TestResult.new(
			"reference prop present in catalog",
			false,
			"prop_5x43x2 missing — cannot run BEMT forward tests"))
		return results

	results.append_array(_hover_identity_is_bit_exact(doc))
	results.append(_thrust_falls_monotonically_with_airspeed(doc))
	results.append(_the_thrust_ratio_is_clamped_past_the_advance(doc))
	results.append(_the_power_curve_has_a_minimum(doc))
	results.append_array(_descent_is_declined_rather_than_guessed(doc))
	results.append(_air_density_scales_both_static_and_forward(doc))
	results.append(_the_forward_fixed_point_converges_across_the_catalog())
	return results


# ---------------------------------------------------------------------------
# 1. The anchor
# ---------------------------------------------------------------------------

## TO MAKE THIS FAIL: delete the `if (v_axial == 0.0 && v_edge == 0.0)` short circuits at the
## top of thrust_ratio_forward / power_ratio_forward. The forward-flight solve reduces to the
## hover form ANALYTICALLY — momentum with |V_total| = v_i is the hover integrand exactly — but
## the two integrals are evaluated by different code paths and would agree to ~1e-12 rather
## than to the bit. Any downstream oracle calibrated against the static path would then move
## by that much whenever the anchor ratio is passed through it, and P5's identity discipline
## (test_calibration.gd::_the_identity_short_circuit_is_bit_exact) does not tolerate a millimetre.
static func _hover_identity_is_bit_exact(doc: PropellerDocument) -> Array:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	var thrust_ratio := BemtModel.thrust_ratio_forward(
		REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 0.0, 0.0)
	var power_ratio := BemtModel.power_ratio_forward(
		REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 0.0, 0.0)

	# And the forward solve at V=0 must ALSO agree with the static solve. This is what the
	# short circuit is protecting: absent the guard these two integrals agree only to numeric
	# precision, and the assertion here is that the fallthrough (with V_ax > 0 tiny) still
	# converges to the same answer up to residual. The bit-exact claim is on the RATIO only.
	var static_r: PackedFloat64Array = BemtModel.solve(
		REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
		5.5, 0.03, 0.02, 1.0)
	var forward_r: PackedFloat64Array = BemtModel.solve_forward(
		REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
		5.5, 0.03, 0.02, 1.0, 0.0, 0.0)
	var thrust_close := absf(static_r[0] - forward_r[0]) < 1e-9
	var power_close := absf((static_r[2] + static_r[3]) - (forward_r[2] + forward_r[3])) < 1e-9

	return [
		TestResult.new(
			"thrust_ratio_forward is EXACTLY 1.0 at V_ax = V_edge = 0",
			thrust_ratio == 1.0,
			"ratio = %.20f" % thrust_ratio),
		TestResult.new(
			"power_ratio_forward is EXACTLY 1.0 at V_ax = V_edge = 0",
			power_ratio == 1.0,
			"ratio = %.20f" % power_ratio),
		TestResult.new(
			"solve_forward at V = 0 agrees with solve (thrust)",
			thrust_close,
			"static %.6f N vs forward-at-rest %.6f N" % [static_r[0], forward_r[0]]),
		TestResult.new(
			"solve_forward at V = 0 agrees with solve (shaft power)",
			power_close,
			"static %.6f W vs forward-at-rest %.6f W" % [
				static_r[2] + static_r[3], forward_r[2] + forward_r[3]]),
	]


# ---------------------------------------------------------------------------
# 2. Effect (a) — thrust falls with airspeed
# ---------------------------------------------------------------------------

## TO MAKE THIS FAIL: seed v_i somewhere other than 0 in solve_forward's inner loop (e.g. seed
## at v_h and forget the momentum-magnitude uses |V_total|, not just v_i). The fixed point
## then walks away from the correct axial-inflow answer and thrust either rises or oscillates
## with V_ax — a rotor that gets stronger the faster it flies, which is a mechanism that would
## power a perpetual-motion aircraft rather than a quadcopter.
static func _thrust_falls_monotonically_with_airspeed(doc: PropellerDocument) -> TestResult:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	var previous := 1.0
	var strictly_decreasing := true
	var last_ratio := 1.0
	for i in range(1, 31):
		var v := float(i) * 0.5
		var ratio := BemtModel.thrust_ratio_forward(
			REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, v, 0.0)
		if ratio > previous + 1e-9:
			strictly_decreasing = false
		previous = ratio
		last_ratio = ratio
	return TestResult.new(
		"thrust_ratio_forward falls monotonically with V_ax at fixed RPM",
		strictly_decreasing,
		"at %.0f RPM: 1.000 at 0 m/s -> %.3f at 15 m/s (monotone: %s)" % [
			REFERENCE_RPM, last_ratio, "yes" if strictly_decreasing else "no"])


## TO MAKE THIS FAIL: remove the `.max(0.0).min(1.0)` clamp in thrust_ratio_forward. Past the
## geometric advance the BEMT integral correctly reports a negative thrust — the linear polar
## has crossed zero angle of attack and the section is producing lift on the wrong side — and
## an unclamped ratio would let the caller multiply a positive static thrust by a negative
## ratio and pull the aircraft backwards at speed. This is the same clamp propeller.rs uses on
## the same physics.
static func _the_thrust_ratio_is_clamped_past_the_advance(doc: PropellerDocument) -> TestResult:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	# 3x the geometric advance velocity: pitch × rev/s = 5.08e-3 × 20000/60 × 3 ≈ 5 m/s? No —
	# for a 5x4.3 at 20000 RPM the geometric advance is 0.1092 m/rev × 333 rev/s ≈ 36 m/s, so
	# 100 m/s is deep past the linear polar's zero.
	var deep := BemtModel.thrust_ratio_forward(
		REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 100.0, 0.0)
	return TestResult.new(
		"thrust_ratio_forward clamps at 0 well past the geometric advance",
		deep >= 0.0 and deep <= 1.0,
		"at 100 m/s (deep past J0): ratio = %.6f (clamped in [0, 1])" % deep)


# ---------------------------------------------------------------------------
# 3. The U-shape
# ---------------------------------------------------------------------------

## TO MAKE THIS FAIL: remove the profile-power quadrature from solve_forward (return only the
## induced piece). The curve monotonically falls with airspeed — no turn-back — and the model
## claims flight gets cheaper indefinitely, which busts every flight-time band the app quotes.
##
## The sweep is over edgewise velocity because that is where translational lift lives (V_ax
## unloads the disc while V_edge is the freestream in the disc plane). Real forward-flight in
## an FPV quad tilts the rotor and puts most airspeed on the axis, so a mixed sweep would
## conflate the two effects; here we isolate the U-shape.
##
## The sweep runs to 100 m/s because in THIS formulation the turn-back sits near 40 m/s, far
## above where a quad actually flies. That is a property of the axisymmetric closure, not a
## claim about aircraft: V_edge reaches the rotor only through |V_total| in the momentum
## closure and through U² in the blade element, so its unloading effect is weaker than the
## axial one and the profile term takes longer to overtake it. The assertion is the SHAPE —
## induced power falls, profile power climbs, and the sum turns back — never the position of
## the minimum, which this model is not entitled to quote.
static func _the_power_curve_has_a_minimum(doc: PropellerDocument) -> TestResult:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	var ratios: Array[float] = []
	var speeds: Array[float] = [0.0, 5.0, 10.0, 20.0, 30.0, 40.0, 60.0, 80.0, 100.0]
	for v in speeds:
		# Small axial inflow so induced power falls with speed (the (a) half) while V_edge
		# raises U² (the (b) half). This is the classical helicopter Glauert-BEMT sweep.
		var ratio := BemtModel.power_ratio_forward(
			REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 1.0, v)
		ratios.append(ratio)

	# A U shape: there is some interior index i where ratios[i] is strictly less than both
	# ratios[0] and ratios[-1]. That is the "dips and then climbs" test the forward-flight
	# suite uses — the shape claim, not the position.
	var min_idx := 0
	for i in range(1, ratios.size()):
		if ratios[i] < ratios[min_idx]:
			min_idx = i
	var is_interior := min_idx > 0 and min_idx < ratios.size() - 1
	var strictly_below_both := is_interior \
		and ratios[min_idx] < ratios[0] - 1e-6 \
		and ratios[min_idx] < ratios[-1] - 1e-6

	var trace := ""
	for i in range(ratios.size()):
		trace += "%.0f=%.4f " % [speeds[i], ratios[i]]
	return TestResult.new(
		"power_ratio_forward has a minimum at neither end of the airspeed sweep (U shape)",
		strictly_below_both,
		"V_edge sweep at %.0f RPM: %s | min at index %d" % [REFERENCE_RPM, trace, min_idx])


# ---------------------------------------------------------------------------
# 4. Descent refuses
# ---------------------------------------------------------------------------

## TO MAKE THIS FAIL: remove the `v_axial_mps < 0.0` short circuits in thrust_ratio_forward,
## power_ratio_forward AND solve_forward. The fixed point in the momentum closure has no
## contractivity guarantee for negative axial inflow — it can settle at a v_i that produces
## the wrong sign of induced power — and a descent of a few m/s would report a factor below 1,
## which is a quad EXTRACTING energy from the air. Regenerative braking is out of scope for
## this powertrain (propeller.rs's guard says so, the whole reason it exists is a battery that
## charged itself during a test flight), and this guard is the BEMT-side version of that same
## refusal, translated one file over.
static func _descent_is_declined_rather_than_guessed(doc: PropellerDocument) -> Array:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	var worst_thrust := 1.0
	var worst_power := 1.0
	var refused_sentinel := true
	for i in range(1, 61):
		var descending := -float(i)
		var t_ratio := BemtModel.thrust_ratio_forward(
			REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, descending, 0.0)
		var p_ratio := BemtModel.power_ratio_forward(
			REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord, descending, 0.0)
		worst_thrust = minf(worst_thrust, t_ratio)
		worst_power = minf(worst_power, p_ratio)
		var res: PackedFloat64Array = BemtModel.solve_forward(
			REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
			5.5, 0.03, 0.02, 1.0, descending, 0.0)
		# The sentinel residual is -1.0 on a declined descent — a caller can spot the refusal
		# without a second call.
		if res[4] != -1.0:
			refused_sentinel = false
	return [
		TestResult.new(
			"no descent, however fast, moves thrust_ratio_forward off 1.0",
			worst_thrust == 1.0,
			"1..60 m/s descent, worst ratio %.6f" % worst_thrust),
		TestResult.new(
			"no descent, however fast, moves power_ratio_forward off 1.0",
			worst_power == 1.0,
			"1..60 m/s descent, worst ratio %.6f" % worst_power),
		TestResult.new(
			"solve_forward stamps residual = -1.0 on every declined descent",
			refused_sentinel,
			"1..60 m/s descent, every solve carries the refusal sentinel"),
	]


# ---------------------------------------------------------------------------
# 5. Air density is in both equations where it belongs (§4.1)
# ---------------------------------------------------------------------------

## §0's rule for propulsion: `rho` lives in both the blade element and the momentum closure,
## not as a scalar multiplied on the outside. So halving the air density must halve BOTH the
## static thrust and the forward-flight thrust at the same operating point, and the RATIO
## between them must be invariant to first order — a Bangalore builder flying in 16% less air
## sees a strictly thinner rotor, not one whose forward-flight character changes.
##
## TO MAKE THIS FAIL: pull rho out of the momentum closure and multiply on afterwards
## (`4πr·v²·F·dr * rho`) — the thrust ratio would develop a rho dependence that a rotor's
## forward-flight character does not physically have.
static func _air_density_scales_both_static_and_forward(doc: PropellerDocument) -> TestResult:
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)

	var ratio_sea := BemtModel.thrust_ratio_forward(
		1.225, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 5.0, 3.0)
	var ratio_thin := BemtModel.thrust_ratio_forward(
		1.030, d_m, p_m, blades, REFERENCE_RPM, doc.chord, 5.0, 3.0)

	var thrust_sea := BemtModel.solve(
		1.225, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
		5.5, 0.03, 0.02, 1.0)[0]
	var thrust_thin := BemtModel.solve(
		1.030, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
		5.5, 0.03, 0.02, 1.0)[0]
	# Thrust scales linearly with rho when the polar is unchanged (dT ∝ ρU²). Small deviations
	# come from the induced-velocity coupling, but at REFERENCE_RPM the inflow is much smaller
	# than Ω·r, so the scaling is essentially exact.
	var static_scales := absf(thrust_thin / thrust_sea - 1.030 / 1.225) < 5.0e-3
	# The ratio itself is only weakly rho-dependent (the inflow coupling brings in a mild
	# density dependence). ±3% envelope is the "essentially invariant" claim.
	var ratio_invariant := absf(ratio_sea - ratio_thin) < 3.0e-2

	return TestResult.new(
		"rho scales static and forward thrust the same way; the ratio is essentially invariant",
		static_scales and ratio_invariant,
		"thrust: sea %.3f N, thin %.3f N (ratio %.4f vs %.4f expected); forward ratio: sea %.4f vs thin %.4f" % [
			thrust_sea, thrust_thin, thrust_thin / thrust_sea, 1.030 / 1.225,
			ratio_sea, ratio_thin])


# ---------------------------------------------------------------------------
# 6. The fixed point actually converges (P4's obligation, owed again for V ≠ 0)
# ---------------------------------------------------------------------------

## P4 proved the STATIC fixed point converges at the fixed iteration count across the whole
## catalog, and raised the count from 12 to 20 when it did not. The forward solve is a
## different iteration — Glauert's magnitude closure, under-relaxed — and owes the same proof
## separately. Without it the failure is SILENT: an annulus that overshoots and pins at
## v_i = 0 still returns a thrust and a power, and the ratios built from them still look like
## plausible numbers. That is precisely what happened before this check existed — the U-curve
## test went green on a discontinuous dip at V_edge = 2 m/s produced by a diverged annulus,
## which is a test that could not fail for the reason it claimed.
##
## TO MAKE THIS FAIL: seed the Glauert branch at v_i = 0 instead of at the axial closure's
## quadratic root, or restore the `d_t <= 0 → break` that pinned an overshooting annulus at
## zero inflow. Either one leaves residuals of order 1e29 at low edgewise speed, and every
## number downstream of them is arithmetic on a solve that never converged.
static func _the_forward_fixed_point_converges_across_the_catalog() -> TestResult:
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
		# The claimed domain stops at the geometric advance V = P·rev/s: past it the section
		# angle of attack has gone negative, the rotor is windmilling, and BEMT has nothing to
		# converge TO — which is why thrust_ratio_forward clamps to 0 there rather than
		# reporting a number. Convergence is asserted inside the domain, at 80% of the advance
		# and below, and the clamp test above covers what happens outside it.
		var advance_mps := p_m * REFERENCE_RPM / 60.0
		for v_ax in [0.0, 1.0, 5.0, 15.0, 30.0]:
			if v_ax > 0.8 * advance_mps:
				continue
			for v_edge in [0.0, 0.001, 2.0, 10.0, 40.0]:
				var res: PackedFloat64Array = BemtModel.solve_forward(
					REFERENCE_RHO, d_m, p_m, blades, REFERENCE_RPM, doc.chord,
					5.5, 0.03, 0.02, 1.0, v_ax, v_edge)
				points += 1
				if res[4] > worst:
					worst = res[4]
					worst_where = "%s at V_ax %.0f / V_edge %.3f" % [
						str(prop.get("part_id", "?")), v_ax, v_edge]
	return TestResult.new(
		"the forward fixed point converges at the fixed iteration count across the catalog",
		worst < 1.0e-3,
		"%d operating points, worst residual %.9f (%s)" % [points, worst, worst_where])


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _catalog_prop(part_id: String) -> PropellerDocument:
	var catalog := PartsCatalog.load_default()
	for prop in catalog.list_category("propeller"):
		if str(prop.get("part_id", "")) == part_id:
			return PropellerDocument.from_catalog_prop(prop)
	return null
