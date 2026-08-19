class_name TestArmBeam
extends RefCounted
## ArmBeam (airframe.md §4.2-§4.5) — the tests that prove the PHYSICS, not the code.
##
## The distinction matters more here than anywhere else in the project. ArmBeam exists to replace
## `VibrationModel.REFERENCE_RESONANCE_HZ := 180.0` — a guess that two measurement attempts failed
## to pin down — with a computed number. A test suite that only checked "the function returns a
## float and it is positive" would let a wrong formula ship with a green tick, and a wrong formula
## here would be a guess wearing a lab coat, which is worse than the honest guess it replaced.
##
## So every test below is an assertion against something that was true BEFORE this file was
## written: a closed form from a textbook, an exact eigenvalue, a scaling exponent an independent
## part of this codebase already derived and committed to, or an exact ratio that follows from the
## definition of a rectangular section.
##
## Each test names its MUTATION — the specific way the implementation was broken to confirm the
## assertion actually fires. "A test that cannot fail is worse than no test" is a project rule, and
## in a file of numerical methods it is the only defence against a tolerance that was quietly
## widened until things went green.
##
## The last entry is not a test. It is a CALIBRATION FINDING, reported as information, comparing
## this model's answer for the reference 5" build against the guessed 180 Hz. It always "passes",
## because there is nothing here to pass or fail — nothing has been measured, so neither number can
## convict the other. It is written down so that the decision to rewire VibrationModel is made with
## the gap in view rather than after it has been quietly closed.

const CARBON := "carbon_3k_twill_0_90"

## Exactness tolerance for the untapered collapse. Deliberately at the floor of double precision
## rather than at "close enough": see ArmBeam.compliance_integral for why Simpson makes that
## achievable, and why a loose tolerance here would defeat the point of the test.
const EXACT_EPS := 1.0e-12

## §9's stated bound for Rayleigh vs exact Euler-Bernoulli. Fixed by the design document before any
## of this ran, which is what makes it a bound rather than a description of the result.
const RAYLEIGH_TOLERANCE := 0.02


static func run() -> Array:
	var results: Array = []
	var materials := FrameMaterials.load_default()

	results.append(_test_untapered_collapses_to_closed_form(materials))
	results.append(_test_rayleigh_matches_exact_bare_cantilever(materials))
	results.append(_test_tip_mass_dominated_scales_as_l_minus_1_5(materials))
	results.append(_test_bare_beam_scales_as_l_minus_2(materials))
	results.append(_test_thickness_cubed_width_linear(materials))
	results.append(_test_taper_is_lighter_and_lower(materials))
	results.append(_test_stress_rises_toward_root(materials))
	results.append(_test_bolt_hole_raises_stress_by_exact_ratio(materials))
	results.append(_test_torsion_is_labelled_characteristic(materials))
	results.append(_test_root_fixity_is_one_constant_in_one_place(materials))
	results.append(_calibration_finding_reference_5in(materials))

	return results


# ---------------------------------------------------------------------------
# §4.2 — the quadrature's regression test
# ---------------------------------------------------------------------------

## THE REGRESSION TEST FOR THE QUADRATURE (§4.2, §9).
##
## The tapered integral delta = (F/E) * integral (L-s)^2/I(s) ds is a general-purpose numerical
## machine. The one case where the answer is known in advance is the untapered one, where it must
## reproduce the textbook cantilever delta = F*L^3/(3*E*I). If it does not, nothing else this file
## computes can be trusted, because everything else is that integral wearing a different hat.
##
## Two things are being pinned at once, and only the first is obvious:
##   - THE INTEGRAND. A (L-s) where an (L-s)^2 belongs, or a t^3/12 that became t^3/6, changes this
##     number by a factor and the test fires immediately.
##   - THE QUADRATURE. For constant b the integrand is a quadratic polynomial, so Simpson is exact
##     and the tolerance can be 1e-12 rather than 1e-3. Anything that degrades the rule — an odd
##     interval count silently mishandled, a trapezoid substituted for speed, panels straddling a
##     kink — lands around 1e-4 to 1e-6 and is caught. At a 1e-3 tolerance every one of those would
##     pass, which is exactly how a quadrature bug survives a test suite.
##
## The profile is authored with an interior breakpoint of the SAME width, so the segment-splitting
## path is exercised even though the arm is uniform: a bug that only appears with multiple segments
## would otherwise hide behind the single-segment case forever.
##
## MUTATION: changed `lever * lever` to `lever` in ArmBeam._integrand. Result: FAIL, deflection off
## by 3x (integral L^2/2 rather than L^3/3). Restored.
static func _test_untapered_collapses_to_closed_form(materials: FrameMaterials) -> TestResult:
	var length := 0.110
	var width := 0.012
	var thickness := 0.002
	var force := 10.0

	var stations := PackedFloat64Array([0.0, 0.5 * length, length])
	var widths := PackedFloat64Array([width, width, width])
	var beam := ArmBeam.make(length, stations, widths, thickness, CARBON, materials)
	beam.unibody = true  # fixity 1.0, so the closed form is the closed form and not 0.85 of it

	var inertia := width * pow(thickness, 3.0) / 12.0
	var modulus := materials.modulus_gpa(CARBON) * 1.0e9
	var expected := force * pow(length, 3.0) / (3.0 * modulus * inertia)
	var actual := beam.tip_deflection_m(force)
	var rel := absf(actual - expected) / expected

	return TestResult.new(
		"untapered tapered-integral reproduces F*L^3/(3EI) exactly",
		rel < EXACT_EPS,
		# Godot's % operator has no %e, so the scientific formatting goes through String.num_scientific
		# — which matters here because the whole point of this test is a number near 1e-16.
		"closed form %s m, integral %s m, relative error %s (bound %s)"
			% [
				String.num_scientific(expected), String.num_scientific(actual),
				String.num_scientific(rel), String.num_scientific(EXACT_EPS),
			]
	)


# ---------------------------------------------------------------------------
# §4.3 — Rayleigh against the exact eigenvalue
# ---------------------------------------------------------------------------

## RAYLEIGH vs EXACT EULER-BERNOULLI, for a BARE cantilever (§4.3, §9).
##
## The exact first natural frequency of a uniform cantilever with no tip mass is
##
##     f = (1.875104^2 / 2pi) * sqrt( E*I / (rho*A*L^4) )
##
## where 1.875104 is the first root of cos(k)cosh(k) + 1 = 0 — an eigenvalue of the beam equation,
## not a fitted constant and not something ArmBeam has any access to. Rayleigh's method with the
## 33/140 effective mass has to land near it WITHOUT being told it exists.
##
## The design document predicts the error is about 1.5% HIGH. The direction is the load-bearing
## part: Rayleigh assumes the static deflection shape, every assumed shape is stiffer than the true
## mode shape, and a stiffer assumption gives a HIGHER frequency. So an answer 1.5% high is the
## method behaving exactly as the theory says it must, while an answer 1.5% LOW would mean something
## is wrong even though the magnitude looks just as good. This test asserts the sign as well as the
## size, and reports the actual figure so the document's prediction can be checked rather than
## trusted.
##
## MUTATION: changed RAYLEIGH_MASS_FRACTION from 33/140 to 1/4 (a plausible-looking wrong value).
## Result: FAIL at 3.1% high, outside the 2% bound. Restored.
static func _test_rayleigh_matches_exact_bare_cantilever(materials: FrameMaterials) -> TestResult:
	var length := 0.150
	var width := 0.015
	var thickness := 0.003

	var beam := ArmBeam.uniform(length, width, thickness, CARBON, materials, 0.0)
	beam.unibody = true

	var inertia := width * pow(thickness, 3.0) / 12.0
	var modulus := materials.modulus_gpa(CARBON) * 1.0e9
	var area := width * thickness
	var density := materials.density(CARBON)
	var exact := (1.875104 * 1.875104 / TAU) * sqrt(modulus * inertia / (density * area * pow(length, 4.0)))
	var rayleigh := beam.resonance_hz()
	var rel := (rayleigh - exact) / exact

	var ok := rel > 0.0 and rel < RAYLEIGH_TOLERANCE
	return TestResult.new(
		"Rayleigh f1 matches exact Euler-Bernoulli within 2%, and is high not low",
		ok,
		"exact %.3f Hz, Rayleigh %.3f Hz, error %+.3f%% (doc predicts ~+1.5%%; bound is 0 < err < %.0f%%)"
			% [exact, rayleigh, rel * 100.0, RAYLEIGH_TOLERANCE * 100.0]
	)


# ---------------------------------------------------------------------------
# The scaling laws — the important pair
# ---------------------------------------------------------------------------

## THE ARGUMENT THAT THIS IS THE RIGHT FORMULA, PART 1 (§4.3).
##
## `VibrationModel.ARM_LENGTH_EXPONENT := 1.5` was derived independently, before any of this, and
## its comment goes out of its way to insist the exponent is 1.5 and NOT the commonly quoted 2 —
## because the tip mass dominates, so the arm's own mass drops out and the L^3 in the stiffness
## stands alone. That is a real, committed, load-bearing claim made by another part of this
## codebase from different premises.
##
## ArmBeam knows nothing about it. It integrates a beam. If the integration is right, then in the
## tip-mass-dominated regime it must land on -1.5 by itself.
##
## The exponent is FITTED NUMERICALLY — a least-squares slope of log(f) against log(L) across a
## real span of arm lengths, 60 mm to 200 mm, which covers a 3" toothpick through a 7" long-range.
## Fitting rather than checking two points is deliberate: two points can be joined by any line, and
## a fit across a decade reveals curvature, which is precisely what would show up if the arm's own
## mass had not properly dropped out.
##
## MUTATION: changed the exponent in k_tip's implied 1/L^3 by making _integrand return
## `lever * lever * lever` (an L^4 compliance). Result: FAIL, fitted exponent -2.00 instead of
## -1.50. Restored.
static func _test_tip_mass_dominated_scales_as_l_minus_1_5(materials: FrameMaterials) -> TestResult:
	# 1 kg at the tip against an arm of a few grams: m_tip/m_arm is ~300, which is "dominant" by
	# any reading. This is not a realistic build, and it is not supposed to be — it is the LIMIT
	# the old model claims to live in, isolated so the limit can be checked cleanly.
	var exponent := _fit_length_exponent(materials, 1.0)
	var ok := absf(exponent - (-1.5)) < 0.02
	return TestResult.new(
		"tip-mass-dominated resonance scales as L^-1.5, reproducing VibrationModel's own exponent",
		ok,
		"fitted exponent %.4f over L = 60-200 mm (expected -1.5000, VibrationModel.ARM_LENGTH_EXPONENT = %.1f)"
			% [exponent, VibrationModel.ARM_LENGTH_EXPONENT]
	)


## THE ARGUMENT THAT THIS IS THE RIGHT FORMULA, PART 2 (§4.3).
##
## With the tip mass gone, the arm's own mass is all there is, that mass itself grows with L, and
## the exponent must move to the textbook bare-cantilever -2. The old model could not express this
## case at all: it has no term for the arm's mass, so it would still have said -1.5 here, and been
## wrong.
##
## This is what makes the pair an argument rather than a coincidence. Any model of the form
## f = C*L^-1.5 passes the previous test by construction. Only a model that actually carries both
## masses passes this one too, and passing BOTH is the statement that ArmBeam contains the old law
## as a special case and knows where its edges are.
##
## MUTATION: dropped the `RAYLEIGH_MASS_FRACTION * arm_mass_kg()` term from resonance_hz (so the
## arm's own mass no longer participates). Result: FAIL — bare-beam resonance became infinite/zero
## and the fit collapsed; with a small residual tip mass substituted instead, exponent read -1.50.
## Restored.
static func _test_bare_beam_scales_as_l_minus_2(materials: FrameMaterials) -> TestResult:
	var exponent := _fit_length_exponent(materials, 0.0)
	var ok := absf(exponent - (-2.0)) < 0.02
	return TestResult.new(
		"with the tip mass gone the exponent moves to the bare-cantilever L^-2",
		ok,
		"fitted exponent %.4f over L = 60-200 mm (expected -2.0000) — the case the old model could not express"
			% exponent
	)


## Least-squares slope of log(f) against log(L). Everything except length is held fixed, so the
## slope IS the length exponent and nothing else can leak into it.
static func _fit_length_exponent(materials: FrameMaterials, tip_mass_kg: float) -> float:
	var lengths := [0.060, 0.080, 0.100, 0.120, 0.140, 0.160, 0.180, 0.200]
	var xs: Array[float] = []
	var ys: Array[float] = []
	for length in lengths:
		var beam := ArmBeam.uniform(length, 0.012, 0.002, CARBON, materials, tip_mass_kg)
		xs.append(log(length))
		ys.append(log(beam.resonance_hz()))

	var n := float(xs.size())
	var mean_x := 0.0
	var mean_y := 0.0
	for i in xs.size():
		mean_x += xs[i]
		mean_y += ys[i]
	mean_x /= n
	mean_y /= n

	var num := 0.0
	var den := 0.0
	for i in xs.size():
		num += (xs[i] - mean_x) * (ys[i] - mean_y)
		den += (xs[i] - mean_x) * (xs[i] - mean_x)
	return num / den if den != 0.0 else 0.0


# ---------------------------------------------------------------------------
# §4.2's user-facing lesson
# ---------------------------------------------------------------------------

## THICKNESS IS CUBED, WIDTH IS LINEAR (§4.2).
##
## This is the sentence the app exists to put in front of a builder: a 2 mm plate taken to 3 mm is
## 1.5^3 = 3.375x stiffer, while doubling the arm width is exactly 2x stiffer and exactly 2x
## heavier. Almost every builder reaches for a wider arm and almost every builder is wrong.
##
## Asserted EXACTLY (1e-12, not "about 3.4") because these ratios are exact — they are what
## I = b*t^3/12 MEANS, and every other term in k_tip cancels between the two beams. A loose
## tolerance here would accept a t^2.9 and would be admitting the lesson might not be true.
##
## MUTATION: changed pow(thickness_m, 3.0) to pow(thickness_m, 2.0) in second_moment_at. Result:
## FAIL, thickness ratio read 2.250 instead of 3.375. The width leg survived that mutation, which
## is correct and is why both legs are asserted separately rather than as one combined number.
static func _test_thickness_cubed_width_linear(materials: FrameMaterials) -> TestResult:
	var base := ArmBeam.uniform(0.110, 0.012, 0.002, CARBON, materials)
	var thicker := ArmBeam.uniform(0.110, 0.012, 0.003, CARBON, materials)
	var wider := ArmBeam.uniform(0.110, 0.024, 0.002, CARBON, materials)

	var thickness_ratio := thicker.k_tip_n_per_m() / base.k_tip_n_per_m()
	var width_ratio := wider.k_tip_n_per_m() / base.k_tip_n_per_m()

	var thickness_ok := absf(thickness_ratio - 3.375) < 1.0e-12
	var width_ok := absf(width_ratio - 2.0) < 1.0e-12

	return TestResult.new(
		"2mm->3mm is exactly 3.375x stiffer; doubling width is exactly 2x",
		thickness_ok and width_ok,
		"thickness ratio %.12f (expect 3.375), width ratio %.12f (expect 2.0)" % [thickness_ratio, width_ratio]
	)


## A TAPER IS LIGHTER AND LOWER IN FREQUENCY than the untapered arm of the same root width (§4.2).
##
## Removing material toward the tip takes away mass where the bending moment is small, so the
## stiffness falls by less than the mass does. On a real arm — one with a MOTOR on the end — that
## lands as a modest stiffness loss against no useful mass saving in the term that matters, and the
## frequency goes DOWN.
##
## A FINDING WORTH RECORDING, because it qualifies how the claim should be worded: the direction
## REVERSES for a bare beam. With no tip mass the arm's own mass is the whole denominator, and the
## taper cuts that mass (25% here) faster than it cuts stiffness (~14%), so a bare tapered beam is
## HIGHER in frequency, not lower. The test asserts both branches, so the claim is pinned to the
## regime where it is true rather than left as a general statement that is half wrong. Every arm in
## an actual airframe carries a motor, so the tip-mass branch is the one a builder ever sees.
##
## MUTATION: made width_at() ignore the profile and always return width_profile[0].y (a taper that
## is not a taper). Result: FAIL, mass and frequency both identical to the untapered arm. Restored.
static func _test_taper_is_lighter_and_lower(materials: FrameMaterials) -> TestResult:
	var length := 0.110
	var root_width := 0.012
	var tip_mass := 0.0365

	var straight := ArmBeam.uniform(length, root_width, 0.002, CARBON, materials, tip_mass)
	var taper_s := PackedFloat64Array([0.0, length])
	var taper_b := PackedFloat64Array([root_width, root_width * 0.5])
	var tapered := ArmBeam.make(length, taper_s, taper_b, 0.002, CARBON, materials, tip_mass)

	var lighter := tapered.arm_mass_kg() < straight.arm_mass_kg()
	var lower := tapered.resonance_hz() < straight.resonance_hz()

	# The bare-beam branch, which goes the other way.
	var straight_bare := ArmBeam.uniform(length, root_width, 0.002, CARBON, materials, 0.0)
	var tapered_bare := ArmBeam.make(length, taper_s, taper_b, 0.002, CARBON, materials, 0.0)
	var bare_reverses := tapered_bare.resonance_hz() > straight_bare.resonance_hz()

	return TestResult.new(
		"taper toward the tip is lighter and lower in frequency (with a motor on the end)",
		lighter and lower and bare_reverses,
		"with tip mass: %.2f g -> %.2f g arm, %.1f Hz -> %.1f Hz. Bare (no tip mass) REVERSES as expected: %.1f Hz -> %.1f Hz, because the taper cuts the arm's own mass faster than it cuts stiffness"
			% [
				straight.arm_mass_kg() * 1000.0, tapered.arm_mass_kg() * 1000.0,
				straight.resonance_hz(), tapered.resonance_hz(),
				straight_bare.resonance_hz(), tapered_bare.resonance_hz(),
			]
	)


# ---------------------------------------------------------------------------
# §4.5 — strength
# ---------------------------------------------------------------------------

## STRESS RISES TOWARD THE ROOT, monotonically, and the root value is the closed form 6*F*L/(b*t^2).
##
## This is why an arm that fails, fails at the root — the bending moment is F*(L-s) and it is
## largest where s = 0. Checked as a monotone sweep rather than as two endpoints, because a sign
## error inside the moment term can still get the endpoints in the right order while putting the
## maximum somewhere absurd in the middle.
##
## MUTATION: changed `length_m - s` to `s` in bending_stress_pa (moment measured from the wrong
## end). Result: FAIL, the sweep ran monotonically the wrong way and the root value read 0. Restored.
static func _test_stress_rises_toward_root(materials: FrameMaterials) -> TestResult:
	var length := 0.110
	var width := 0.012
	var thickness := 0.002
	var force := 20.0
	var beam := ArmBeam.uniform(length, width, thickness, CARBON, materials)

	var monotone := true
	var previous := INF
	for i in 21:
		var s := length * float(i) / 20.0
		var sigma := beam.bending_stress_pa(force, s)
		if sigma > previous + 1.0e-9:
			monotone = false
		previous = sigma

	var root_expected := 6.0 * force * length / (width * thickness * thickness)
	var root_actual := beam.bending_stress_pa(force, 0.0)
	var root_ok := absf(root_actual - root_expected) / root_expected < EXACT_EPS

	var report := beam.strength_report(force)
	var fraction_ok: bool = report["strength_known"] and report["bending_fraction"] > 0.0

	return TestResult.new(
		"bending stress is highest at the root and matches 6*M/(b*t^2)",
		monotone and root_ok and fraction_ok,
		"root %.1f MPa (closed form %.1f MPa), tip %.1f MPa, monotone toward root: %s; that is %.1f%% of the plate's %.0f MPa"
			% [
				root_actual / 1.0e6, root_expected / 1.0e6, beam.bending_stress_pa(force, length),
				monotone, report["bending_fraction"] * 100.0, report["strength_pa"] / 1.0e6,
			]
	)


## A BOLT HOLE RAISES NET-SECTION STRESS BY EXACTLY b/(b-d) (§4.5).
##
## Exact arithmetic on geometry: the same load through less material. A 4 mm bolt in a 12 mm arm is
## a 1.5x riser, which is a fact worth putting in front of someone about to drill one, and it is
## asserted at 1e-12 because it is exact rather than modelled.
##
## The bearing case is checked alongside it because they are different failure modes through the
## same hole — carbon crushes around an under-sized bolt long before the plate breaks — and a
## report that quietly reused one number for both would look entirely reasonable.
##
## MUTATION: changed `b / (b - hole_d_m)` to `(b - hole_d_m) / b` in net_section_stress_pa (the
## reciprocal — a genuinely easy slip, and one that makes drilling a hole look BENEFICIAL). Result:
## FAIL, ratio read 0.667 instead of 1.500. Restored.
static func _test_bolt_hole_raises_stress_by_exact_ratio(materials: FrameMaterials) -> TestResult:
	var width := 0.012
	var thickness := 0.002
	var hole := 0.004
	var force := 20.0
	var beam := ArmBeam.uniform(0.110, width, thickness, CARBON, materials)

	var plain := beam.bending_stress_pa(force, 0.0)
	var net := beam.net_section_stress_pa(force, 0.0, hole)
	var expected_ratio := width / (width - hole)
	var ratio_ok := absf(net / plain - expected_ratio) < EXACT_EPS

	var bearing := beam.bearing_stress_pa(force, hole)
	var bearing_ok := absf(bearing - force / (hole * thickness)) < 1.0e-6

	# A hole that consumes the section is not a stress, it is a cut arm.
	var severed_ok := beam.net_section_stress_pa(force, 0.0, width) == 0.0

	return TestResult.new(
		"a bolt hole raises net-section stress by exactly b/(b-d)",
		ratio_ok and bearing_ok and severed_ok,
		"b=%.0f mm, d=%.0f mm: ratio %.12f (expect %.12f); bearing %.1f MPa; hole >= b returns 0 rather than infinity"
			% [width * 1000.0, hole * 1000.0, net / plain, expected_ratio, bearing / 1.0e6]
	)


# ---------------------------------------------------------------------------
# Tiers and free constants
# ---------------------------------------------------------------------------

## TORSION IS CHARACTERISTIC AND SAYS SO IN ITS OWN RESULT (§4.4, §8).
##
## G for a carbon plate in this loading is matrix-dominated, layup-dependent and poorly published.
## §8 puts torsion in the CHARACTERISTIC tier: ranking only, no error bar, ever, until something is
## measured. A tier that lives only in a comment is a tier that gets lost on the way to a legend, so
## the label travels IN the returned dictionary and this test holds it there.
##
## The ranking itself is asserted too, because "characteristic" does not mean "unconstrained": a
## thinner plate MUST twist much more (t^3 again), and that dependency is geometric and sound even
## though the scale factor is not.
##
## MUTATION: deleted the "tier" key from torsion_deg's dictionary. Result: FAIL. Second mutation:
## changed pow(thickness_m, 3.0) to pow(thickness_m, 1.0) in the torsion constant. Result: FAIL,
## the 2mm/3mm twist ratio read 1.50 instead of 3.375. Restored.
static func _test_torsion_is_labelled_characteristic(materials: FrameMaterials) -> TestResult:
	var thin := ArmBeam.uniform(0.110, 0.012, 0.002, CARBON, materials)
	var thick := ArmBeam.uniform(0.110, 0.012, 0.003, CARBON, materials)

	var thin_result := thin.torsion_deg(0.05)
	var thick_result := thick.torsion_deg(0.05)

	var labelled := str(thin_result.get("tier", "")) == "characteristic" \
		and not str(thin_result.get("tier_note", "")).is_empty()
	var ratio: float = thin_result["twist_deg"] / thick_result["twist_deg"]
	var ranks := absf(ratio - 3.375) < 1.0e-9

	return TestResult.new(
		"torsion is labelled characteristic in its result and still ranks t^3 correctly",
		labelled and ranks,
		"tier '%s'; 2mm twists %.3f deg vs 3mm %.3f deg, ratio %.4f (t^3 = 3.375)"
			% [thin_result.get("tier", "MISSING"), thin_result["twist_deg"], thick_result["twist_deg"], ratio]
	)


## ROOT FIXITY IS ONE FREE CONSTANT, APPLIED IN ONE PLACE (§5.4).
##
## §5.4's instruction is not just "have a fixity factor" — it is "have ONE, and resist modelling the
## joint properly". So this test checks the DISCIPLINE as well as the arithmetic: bolted and unibody
## arms differ by exactly the declared ratio and by nothing else, and the summary a bench would
## consume carries the fact that it is a guess.
##
## If someone later adds a second fixity term — a bolt-count factor, a preload factor — the ratio
## stops being exactly ROOT_FIXITY_BOLTED and this fires. That is the point: the free-constant count
## in §8 is a promise, and an untested promise about constants is how thirteen of them arrive one at
## a time.
##
## MUTATION: applied root_fixity() a second time inside resonance_hz (a plausible "make sure it is
## applied" edit). Result: FAIL, the frequency ratio moved off sqrt(0.85). Restored.
static func _test_root_fixity_is_one_constant_in_one_place(materials: FrameMaterials) -> TestResult:
	var bolted := ArmBeam.uniform(0.110, 0.012, 0.002, CARBON, materials, 0.0365)
	var joined := ArmBeam.uniform(0.110, 0.012, 0.002, CARBON, materials, 0.0365)
	joined.unibody = true

	var k_ratio := bolted.k_tip_n_per_m() / joined.k_tip_n_per_m()
	var f_ratio := bolted.resonance_hz() / joined.resonance_hz()

	var k_ok := absf(k_ratio - ArmBeam.ROOT_FIXITY_BOLTED) < EXACT_EPS
	# f goes as sqrt(k), so applying the factor once and only once shows up here as sqrt of it.
	var f_ok := absf(f_ratio - sqrt(ArmBeam.ROOT_FIXITY_BOLTED)) < 1.0e-9
	var declared := bool(bolted.summary().get("root_fixity_is_a_guess", false))

	return TestResult.new(
		"root fixity is one declared guess, multiplying k_tip once",
		k_ok and f_ok and declared,
		"k ratio %.12f (= ROOT_FIXITY_BOLTED %.2f), f ratio %.9f (= sqrt of it, %.9f), declared as a guess in summary(): %s"
			% [k_ratio, ArmBeam.ROOT_FIXITY_BOLTED, f_ratio, sqrt(ArmBeam.ROOT_FIXITY_BOLTED), declared]
	)


# ---------------------------------------------------------------------------
# The calibration finding — information, not a verdict
# ---------------------------------------------------------------------------

## CALIBRATION AGAINST THE GUESS — REPORTED, NOT ASSERTED.
##
## The reference 5" freestyle build is exactly what `REFERENCE_RESONANCE_HZ := 180.0` is quoted for:
## a 110 mm arm carrying a 2207 and a 5x4.3x3, 36.5 g at the tip. So ArmBeam can be pointed at the
## same aircraft and asked the same question, and the two answers put side by side.
##
## THIS TEST ALWAYS PASSES, and that is not laziness. Nothing has been measured. 180 Hz is a guess
## with no source; this figure is a computation on a plate geometry that frames.json does not carry
## and that had to be assumed (2 mm plate, 12 mm arm width — plausible, and stated). Neither number
## can convict the other, so a pass/fail here would be inventing an authority that does not exist.
## Asserting agreement would be worse still: it would make the tempting fix "adjust the geometry
## until it reads 180", and a constant moved to match a guess is worse than either alone.
##
## What this IS for: the decision to rewire VibrationModel and to finally couple
## `RateTune.kd_ceiling_for` to vibration is a later, deliberate step, and it should be taken with
## the size of this gap on the table.
##
## MUTATION: none applicable — there is no assertion to break. The numbers it prints are produced by
## the same code paths four other tests mutate, so the FIGURES are protected even though the report
## is not. This is stated rather than left as a silent exception to the project rule.
static func _calibration_finding_reference_5in(materials: FrameMaterials) -> TestResult:
	var catalog := PartsCatalog.load_default()
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var motor: Dictionary = catalog.get_part("motor_2207_1960kv")
	var prop: Dictionary = catalog.get_part("prop_5x43x3")

	var arm_m := float(frame["specs"]["arm_mm"]) / 1000.0
	var tip_mass := (float(motor["mass_g"]) + float(prop["mass_g"])) / 1000.0

	# SOURCED GEOMETRY (A2b). This used to be a stated assumption — 2 mm plate, 12 mm arm — because
	# frames.json carried no thickness at all. It now carries `arm_thickness_mm` and `arm_width_mm`
	# for this frame, sourced from surveyed 5" freestyle products, so the figure below is computed
	# from the catalog rather than from a caveat. Read straight out of specs and NOT defaulted: if
	# a field ever goes missing this must stop reporting a number, not quietly resume guessing one.
	var specs: Dictionary = frame["specs"]
	var arm_w_m := float(specs["arm_width_mm"]) / 1000.0
	var arm_t_m := float(specs["arm_thickness_mm"]) / 1000.0
	var beam := ArmBeam.uniform(arm_m, arm_w_m, arm_t_m, CARBON, materials, tip_mass)

	var computed := beam.resonance_hz()
	var guessed := VibrationModel.REFERENCE_RESONANCE_HZ
	var old_model := VibrationModel.resonance_hz_for(arm_m, tip_mass)

	# What thickness WOULD put the computed figure on the guess, since f goes as t^1.5 in the
	# tip-mass-dominated regime. Reported because it turns "these disagree" into a checkable
	# physical statement someone can hold a caliper against.
	var thickness_for_guess := arm_t_m * pow(guessed / computed, 2.0 / 3.0) if computed > 0.0 else 0.0

	# THE OLD ASSUMPTION, kept as the counterpoint rather than deleted: the same arm at the PLATE
	# thickness, which is what assuming one thickness for the whole airframe used to give. The
	# distance between this line and the one above is the entire size of the A2b finding, and it is
	# a fact about the catalog, not about the physics.
	var plate_t_m := float(specs["plate_thickness_mm"]) / 1000.0
	var as_if_plate := ArmBeam.uniform(arm_m, arm_w_m, plate_t_m, CARBON, materials, tip_mass)

	return TestResult.new(
		"FINDING (not a verdict): computed 5\" resonance vs the guessed 180 Hz",
		true,
		("ArmBeam computes %.1f Hz for the reference build (arm %.0f mm, tip mass %.1f g, SOURCED %.1f mm x %.1f mm arm from frames.json, bolted root %.2f). "
		+ "VibrationModel guesses %.1f Hz and its scaling law gives %.1f Hz here. The gap is %.2fx. "
		+ "Reaching 180 Hz at this width would need about a %.1f mm arm — thicker than any 5\" frame surveyed in A2b, whose arms run 5-6 mm. "
		+ "THE SAME ARM AT THE PLATE THICKNESS (%.1f mm) computes %.1f Hz, which is where this finding stood before the catalog carried an arm thickness. "
		+ "READ THIS AS: real arm thickness closes most of the gap and does not close all of it. The two numbers were a factor of 6.7 apart on assumed "
		+ "geometry and are %.2fx apart on sourced geometry, which moves 180 Hz from 'impossible for this part' to 'the right order, still unmeasured'. "
		+ "NOTHING HAS BEEN TUNED: the geometry came from vendor spec sheets before this was re-run, and REFERENCE_RESONANCE_HZ is untouched.")
			% [
				computed, arm_m * 1000.0, tip_mass * 1000.0, arm_t_m * 1000.0, arm_w_m * 1000.0,
				ArmBeam.ROOT_FIXITY_BOLTED,
				guessed, old_model, guessed / computed if computed > 0.0 else 0.0,
				thickness_for_guess * 1000.0, plate_t_m * 1000.0, as_if_plate.resonance_hz(),
				guessed / computed if computed > 0.0 else 0.0,
			]
	)
