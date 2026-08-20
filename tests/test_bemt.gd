class_name TestBemt
extends RefCounted
## BEMT core (P4) — propulsion.md §4.1–§4.2, pure, in Rust beside propeller.rs.
##
## This file carries the three proof obligations from §9's P4 row:
##   1. Static BEMT reproduces the momentum-theory ideal for a uniform-inflow rotor.
##   2. Tip loss F → 1 as N_b → ∞.
##   3. Convergence at the fixed iteration count, proven across the whole catalog —
##      not at one operating point.
##
## The math lives in Rust (`BemtModel`), so every number here is an outcome of the compiled
## core rather than a re-derivation in GDScript. The assertions are written against the closed
## forms §4.1 states, not against a second implementation.

static func run() -> Array:
	var results: Array = []
	results.append(_test_momentum_theory_ideal())
	results.append(_test_tip_loss_tends_to_one())
	results.append(_test_catalog_convergence())
	return results


## Proof 1, in two halves.
##
## 1A — the exact statement. The momentum-theory ideal for a rotor with UNIFORM inflow is
##   T = 2ρA·v²  at  P = T·v,   v = v_i constant across the disc
## — the closed forms §4.1's annulus closure (dT = 4πρr·v_i²·F·dr with F = 1) is supposed to
## reproduce. The core integrates that closure over a uniform v_i; the closed forms must come
## out exactly. A wrong 4π coefficient, a wrong annulus quadrature, or a dropped F each fail it.
##
## 1B — the full solve must respect the ideal as a BOUND. For any converged BEMT solution the
## induced power is never below the ideal (uniform inflow is the minimum), so
## FM = P_ideal/P_shaft ≤ 1 by construction; a sign or coefficient bug pushes the solve to the
## wrong side. Lossless (cd = 0) on the catalog's 5x4.3 at its hover RPM.
static func _test_momentum_theory_ideal() -> TestResult:
	var rho := 1.225
	var diameter_m := 0.127
	var v_i := 4.0
	var ideal: PackedFloat64Array = BemtModel.uniform_inflow_momentum(rho, diameter_m, v_i, 40)
	var area := PI * pow(diameter_m * 0.5, 2.0)
	var expected_t := 2.0 * rho * area * v_i * v_i
	var ideal_ok := absf(ideal[0] - expected_t) < 1e-9 \
		and absf(ideal[1] - expected_t * v_i) < 1e-9

	var catalog := PartsCatalog.load_default()
	var doc := _catalog_prop(catalog, "prop_5x43x2")
	var solve_ok := false
	var fm := -1.0
	var residual := -1.0
	if doc != null:
		var d_m := doc.diameter_mm * 0.001
		var res: PackedFloat64Array = BemtModel.solve(
			1.225, d_m, doc.pitch_mm * 0.001, float(doc.blades),
			11000.0, doc.chord, 5.5, 0.0, 0.0, 1.2)
		var thrust := res[0]
		var v_h := sqrt(thrust / (2.0 * rho * PI * pow(d_m * 0.5, 2.0)))
		fm = thrust * v_h / (res[2] + res[3])
		residual = res[4]
		solve_ok = res[4] < 1e-3 and res[3] < 1e-9 and fm > 0.0 and fm < 1.0 + 1e-6

	return TestResult.new(
		"static BEMT reproduces the momentum-theory ideal for a uniform-inflow rotor",
		ideal_ok and solve_ok,
		"uniform-inflow: T = %.6f vs %.6f N, P = %.6f vs %.6f W | solve: FM = %.4f (≤ 1), residual %.8f" % [
			ideal[0], expected_t, ideal[1], expected_t * v_i, fm, residual])


## Finds a catalog prop's document by part_id; the BEMT tests that need a real preset use this.
static func _catalog_prop(catalog: PartsCatalog, part_id: String) -> PropellerDocument:
	for prop in catalog.list_category("propeller"):
		if str(prop.get("part_id", "")) == part_id:
			return PropellerDocument.from_catalog_prop(prop)
	return null


## Proof 2. The Prandtl tip-loss factor, §4.1:
##   F = (2/π)·acos( exp( −N_b·(R−r) / (2·r·sin φ) ) )
## As N_b → ∞ the exponent → −∞, exp → 0, acos(0) = π/2 and F → 1: the tip leak closes. For
## any finite N_b it is below 1 and non-decreasing in N_b — monotone up to saturation at 1.0
## (for N_b large enough the exp term vanishes below double precision and F is exactly 1.0,
## which the monotonicity check must not read as a decrease) — and at the tip itself (r = R)
## the loss is total, F → 0. All three are asserted here because a sign or scale slip in the
## exponent would break each in a different, silent way.
static func _test_tip_loss_tends_to_one() -> TestResult:
	var values: Array = []
	for blades in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]:
		values.append(BemtModel.tip_loss_factor(blades, 0.5, 0.2))

	# Monotone means non-decreasing; saturation at exactly 1.0 is the limit F approaches, not
	# a decrease. A real backwards step (1e-12 of slack for float rounding) fails.
	var monotone := true
	for i in range(1, values.size()):
		if values[i] < values[i - 1] - 1e-12:
			monotone = false

	var f_huge := BemtModel.tip_loss_factor(1.0e6, 0.5, 0.2)
	var f_finite_lt_one := BemtModel.tip_loss_factor(2.0, 0.5, 0.2) < 1.0
	var f_tip := BemtModel.tip_loss_factor(2.0, 1.0, 0.2)

	return TestResult.new(
		"tip loss F → 1 as N_b → ∞, monotone in N_b, zero at the tip",
		monotone and absf(f_huge - 1.0) < 1e-12 and f_finite_lt_one and absf(f_tip) < 1e-12,
		"F(1)=%.5f F(8)=%.5f F(64)=%.5f F(1e6)=%.15f, F(tip)=%.12f" % [
			values[0], values[3], values[6], f_huge, f_tip])


## Proof 3. The fixed iteration count (BemtModel's BEMT_ITERATIONS, the count the solve
## actually runs) must converge for EVERY prop in the catalog, not at one operating point.
## Each of the 19 presets is solved at three RPMs spanning its hover region (hover RPM scales
## as 1/diameter at fixed disc loading — a 1.6" whoop hovers around three times the RPM of a
## 5" prop) and the residual — the relative mismatch between the blade-element and momentum
## thrusts on the last pass — must be below 1e-3 everywhere.
##
## This is the proof that forced the count up from 12 to 20: the low-solidity large props
## contract at λ ≈ 0.6 per iteration, so 12 leaves a ~0.5% residual while the 5" and smaller
## props have settled to 1e-7. The count is fixed and proven here, never tuned per prop. The
## polar uses the uncalibrated placeholders (a0_eff and C_d0 are P5's fit); convergence is a
## property of the iteration, not of the polar's accuracy. The hover solution is self-similar
## in RPM (v_i scales with Ω, the inflow angles do not), so the residual is RPM-independent —
## which is why the sweep is over props rather than over the three RPM points.
static func _test_catalog_convergence() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var problems: Array = []
	var total_points := 0

	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var diameter_m := doc.diameter_mm * 0.001
		var rpm_hover := 11000.0 * (0.127 / diameter_m)
		for mult in [0.5, 1.0, 1.5]:
			var res: PackedFloat64Array = BemtModel.solve(
				1.225, diameter_m, doc.pitch_mm * 0.001, float(doc.blades),
				rpm_hover * mult, doc.chord, 5.5, 0.03, 0.02, 1.0)
			total_points += 1
			if res[4] >= 1e-3:
				problems.append("%s @ %.0f rpm: residual %.8f" % [
					doc.id, rpm_hover * mult, res[4]])

	return TestResult.new(
		"fixed iteration count converges across the whole catalog",
		problems.is_empty(),
		"%d operating points, all converged" % total_points
			if problems.is_empty() else "%d/%d points failed; %s" % [
				problems.size(), total_points, "; ".join(problems)])
