extends RefCounted
## One arm of an airframe, as a beam (airframe.md §4.2-§4.5) — the slice that replaces a guessed
## number with a computed one.
##
## ---------------------------------------------------------------------------
## WHY THIS FILE EXISTS AT ALL
## ---------------------------------------------------------------------------
##
## `VibrationModel.REFERENCE_RESONANCE_HZ := 180.0` is a guess, and its own comment says so. Every
## frame's resonance in Lothal today is a ratio to that one number. Because it is a guess,
## `RateTune.kd_ceiling_for` was deliberately left uncoupled from vibration: the mechanism is
## written, measured and reportable, but it is not allowed to move a gain, because moving a gain on
## an unmeasured anchor is inventing physics.
##
## Two attempts to pin the anchor down failed. LTHL-18 went looking for the mode in public blackbox
## logs and hit a wall that is not about effort — in normal flying the 1x line sweeps 155-235 Hz
## inside a single analysis frame, so no peak survives to be measured. LTHL-49 built an impact test
## instead, and it was never run against a real airframe.
##
## This file takes the third route, which is the one the airframe document is about: stop trying to
## MEASURE the resonance of a frame we only know six numbers about, and start COMPUTING it from a
## frame whose geometry we actually have. A carbon arm is a flat plate of constant thickness with a
## width that varies along its length. That is a tapered rectangular-section cantilever, and a
## tapered rectangular-section cantilever is a solved problem — no FEA, no meshing, no fitting.
##
## ---------------------------------------------------------------------------
## WHAT IS AND IS NOT CLAIMED
## ---------------------------------------------------------------------------
##
## §8's honesty tiers apply per output, and this class labels them at each returning function:
##
##   ENGINEERING-GRADE  tip deflection, k_tip, first-mode resonance, bending / net-section /
##                      bearing stress. Standard closed forms, correct physics, honestly +/-20%.
##   CHARACTERISTIC     torsion (see torsion_deg), and the root-fixity factor multiplying k_tip.
##                      Ranking only. No error bar, ever, until something is measured.
##
## The honest limit, stated up front and not in a footnote: this is the FIRST BENDING MODE OF ONE
## ARM, treated as rooted at the centre plate. A real frame also has plate modes, torsional modes,
## and a root that is a bolted joint rather than a fixture. Nothing here claims to find those.
##
## ---------------------------------------------------------------------------
## SCOPE OF THIS SLICE (A5)
## ---------------------------------------------------------------------------
##
## ArmBeam is standalone and is not wired into anything. `REFERENCE_RESONANCE_HZ` is still there and
## `VibrationModel` still hangs off it. That is deliberate: tests/test_arm_beam.gd ends with a
## CALIBRATION FINDING comparing this model's answer for the reference 5" build against the guessed
## 180 Hz, and the rewiring is a later step that wants that finding in hand first. A constant moved
## to agree with a guess would be worse than either of them alone.


# ---------------------------------------------------------------------------
# The one free constant
# ---------------------------------------------------------------------------

## ROOT FIXITY — THE ONE DECLARED FREE CONSTANT IN THIS FILE, AND IT IS A GUESS (§5.4).
##
## Everything above assumes the textbook cantilever: the arm's root does not move and does not
## rotate. A unibody plate — arms cut from the same sheet as the centre section — is close enough to
## that to call it 1.0 by definition, and 1.0 is not a fitted number, it is the statement that the
## textbook case IS the unibody case.
##
## A bolted arm is not. Two bolts through a carbon plate with finite preload let the root rotate a
## little under load, and a root that rotates is a softer spring than one that does not. 0.85 is a
## GUESS. What can be said for it: LTHL-49 priced root fixity at +/-10% on the resonance, and since
## f goes as sqrt(k), a 15% softening is about 8% on the frequency — the same order, from the other
## end. What cannot be said for it: nothing has been measured. No test rig, no log, no datasheet.
##
## It is deliberately ONE constant and not thirteen. Modelling the joint properly — bolt count,
## spacing, preload, plate-on-plate contact stiffness — would be a dozen numbers of which we could
## source zero, and §5.4 says in as many words to resist exactly that. One honest guess beats
## thirteen tuned ones, and this one is applied in exactly one place: k_tip_n_per_m().
const ROOT_FIXITY_BOLTED := 0.85
const ROOT_FIXITY_UNIBODY := 1.0

## In-plane shear modulus for a carbon plate, as a fraction of its quoted Young's modulus.
## CHARACTERISTIC and nothing better (§4.4). For an ISOTROPIC solid G = E/(2(1+nu)) puts this near
## 0.38; for a 0/90 laminate loaded in shear it is nowhere near that, because in-plane shear is
## carried by the MATRIX rather than by the fibres, and published G12 for a standard-modulus 0/90
## laminate sits around 4-5 GPa against a 70 GPa tensile modulus. 0.065 lands in that band.
##
## This is used ONLY by torsion_deg(), which returns a CHARACTERISTIC result and says so in its
## own docstring and in its returned dictionary. It may rank two arms. It may not be quoted.
const CHARACTERISTIC_SHEAR_FRACTION := 0.065

## Rayleigh's effective mass of a cantilever deflecting in its static tip-loaded shape (§4.3). Not
## a tuned number and not adjustable — 33/140 falls out of integrating the static deflection shape
## against the mass distribution, and the bare-beam test in tests/test_arm_beam.gd is what proves
## it is the right one (it puts f1 ~1.5% above the exact Euler-Bernoulli answer, as §4.3 predicts).
const RAYLEIGH_MASS_FRACTION := 33.0 / 140.0

## Sub-intervals per taper segment for the compliance integral. §4.2 asks for "~100 stations"; this
## is per SEGMENT and even (Simpson needs pairs), so a single-segment arm integrates over 121
## stations and a taper with kinks gets at least that many.
const STATIONS_PER_SEGMENT := 120


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## Metres, root to tip along the arm's declared centreline (§10, open question 1: the centreline is
## authored on the plate, not inferred from its outline).
var length_m := 0.0

## The taper, as a piecewise-linear width profile: two parallel arrays, stations in increasing s
## with the first at 0 and the last at length_m, and the width at each. A single sample means a
## constant-width arm. Kept as the AUTHORED breakpoints rather than resampled, so that the
## quadrature can put panel boundaries exactly on the kinks — see compliance_integral().
##
## WHY TWO FLOAT64 ARRAYS AND NOT AN Array[Vector2], WHICH IS THE OBVIOUS SHAPE: Godot's Vector2 is
## 32-BIT. A 12 mm width stored in one comes back as 0.012000000104308128, a relative error of about
## 9e-9. That is invisible in a drawing and fatal to the exactness this file's tests depend on — the
## untapered-collapse regression is asserted at 1e-12 precisely so it can catch a bad quadrature,
## and a float32 round-trip on the geometry would swamp it at 1e-8 and make that test unable to tell
## a quantisation artefact from a broken integrator. Geometry that physics integrates is kept in
## doubles all the way through.
var profile_s_m := PackedFloat64Array()
var profile_b_m := PackedFloat64Array()

## Metres. Constant, because a plate is one sheet at one thickness — that is not a simplification
## imposed on the model, it is what the object is (§0).
var thickness_m := 0.0

## Kilograms at the tip: motor + prop + mount hardware. §4.3's point is that this is no longer
## unpublished; the build already knows all three.
var tip_mass_kg := 0.0

var material_id := ""
var materials: FrameMaterials = null

## Degrees between the arm's axis and the sheet's 0 degree weave direction. Feeds
## FrameMaterials.modulus_at_angle_gpa, which is CHARACTERISTIC for an anisotropic material and
## exact-by-construction (one modulus at every angle) for a quasi-isotropic one. Defaults to 0 —
## an arm cut along the weave, which is what a sane CNC nest does.
var cut_angle_deg := 0.0

## true when the arm is cut from the same sheet as the centre plate. Selects between the two root
## fixity values above and nothing else.
var unibody := false

## Anything structurally refusing to be analysed. Populated by validate(); a beam with errors will
## still answer, but with zeros rather than infinities, so a caller that ignores this gets an
## obviously wrong number rather than a plausible one.
var errors: Array[String] = []


static func make(
	p_length_m: float,
	p_stations_m: PackedFloat64Array,
	p_widths_m: PackedFloat64Array,
	p_thickness_m: float,
	p_material_id: String,
	p_materials: FrameMaterials,
	p_tip_mass_kg: float = 0.0
) -> ArmBeam:
	var beam := ArmBeam.new()
	beam.length_m = p_length_m
	beam.profile_s_m = p_stations_m.duplicate()
	beam.profile_b_m = p_widths_m.duplicate()
	beam.thickness_m = p_thickness_m
	beam.material_id = p_material_id
	beam.materials = p_materials
	beam.tip_mass_kg = p_tip_mass_kg
	beam.validate()
	return beam


## The common case, spelled so a caller does not have to build a one-element array to say
## "this arm is the same width all the way along".
static func uniform(
	p_length_m: float,
	p_width_m: float,
	p_thickness_m: float,
	p_material_id: String,
	p_materials: FrameMaterials,
	p_tip_mass_kg: float = 0.0
) -> ArmBeam:
	return ArmBeam.make(
		p_length_m,
		PackedFloat64Array([0.0, p_length_m]),
		PackedFloat64Array([p_width_m, p_width_m]),
		p_thickness_m, p_material_id, p_materials, p_tip_mass_kg
	)


func validate() -> void:
	errors.clear()
	if length_m <= 0.0:
		errors.append("length_m must be positive")
	if thickness_m <= 0.0:
		errors.append("thickness_m must be positive")
	if profile_b_m.is_empty():
		errors.append("width profile is empty")
	if profile_s_m.size() != profile_b_m.size():
		errors.append("width profile stations and widths differ in length")
	for i in range(profile_b_m.size()):
		# A zero-width station is a division by zero in the compliance integral, and physically it
		# is an arm that has been cut through. Refused rather than clamped: a clamp would answer a
		# question about a different arm.
		if profile_b_m[i] <= 0.0:
			errors.append("width profile has a non-positive width at s = %.4f m" % profile_s_m[i])
	if materials == null or materials.get_material(material_id).is_empty():
		errors.append("unknown material: %s" % material_id)


func is_valid() -> bool:
	return errors.is_empty()


# ---------------------------------------------------------------------------
# Section properties
# ---------------------------------------------------------------------------

## Width b(s) at station s, by linear interpolation between authored breakpoints. Clamped outside
## the profile rather than extrapolated: extrapolating a taper past its last authored point is how
## you get a negative width at the tip and a nonsense stiffness that still looks like a number.
func width_at(s: float) -> float:
	var n := profile_b_m.size()
	if n == 0:
		return 0.0
	if n == 1 or s <= profile_s_m[0]:
		return profile_b_m[0]
	if s >= profile_s_m[n - 1]:
		return profile_b_m[n - 1]
	for i in range(n - 1):
		if s <= profile_s_m[i + 1]:
			var span := profile_s_m[i + 1] - profile_s_m[i]
			if span <= 0.0:
				return profile_b_m[i + 1]
			return profile_b_m[i] + (profile_b_m[i + 1] - profile_b_m[i]) * (s - profile_s_m[i]) / span
	return profile_b_m[n - 1]


## Second moment of area, m^4. I(s) = b(s)*t^3/12 for a rectangle bending about its own centroid.
##
## THIS ONE LINE IS THE USER-FACING LESSON OF §4.2: thickness is CUBED and width is LINEAR. Going
## from a 2 mm to a 3 mm plate is 1.5^3 = 3.375x stiffer for 1.5x the mass; doubling the arm width
## is exactly 2x stiffer for exactly 2x the mass. Almost every builder reaches for a wider arm and
## almost every builder is wrong. tests/test_arm_beam.gd asserts both ratios EXACTLY, because they
## are exact — they are the definition, not an approximation of it.
func second_moment_at(s: float) -> float:
	return width_at(s) * pow(thickness_m, 3.0) / 12.0


## Pa. E(theta) for the material this arm is cut from, at the angle it is cut at.
func youngs_modulus_pa() -> float:
	if materials == null:
		return 0.0
	return materials.modulus_at_angle_gpa(material_id, cut_angle_deg) * 1.0e9


func root_fixity() -> float:
	return ROOT_FIXITY_UNIBODY if unibody else ROOT_FIXITY_BOLTED


# ---------------------------------------------------------------------------
# §4.2 Bending
# ---------------------------------------------------------------------------

## The compliance integral of §4.2, in 1/m^3:
##
##     C = integral_0^L  (L - s)^2 / I(s)  ds
##
## from which delta = (F/E) * C. Split out because it is the whole numerical content of this file
## and it deserves its own name and its own regression test.
##
## ---------------------------------------------------------------------------
## THE QUADRATURE, AND WHY THIS ONE
## ---------------------------------------------------------------------------
##
## COMPOSITE SIMPSON, applied SEGMENT BY SEGMENT of the authored width profile, with an even number
## of sub-intervals in each. Two properties earned it the job, and one of them is not about
## accuracy:
##
## 1. WHEN THE ARM IS UNTAPERED THE ANSWER IS EXACT, to floating point. b constant makes the
##    integrand (L-s)^2 * 12/(b*t^3), a QUADRATIC polynomial, and Simpson integrates cubics exactly.
##    So the collapse to the textbook delta = F*L^3/(3*E*I) is not "close" — it is the same number.
##    That matters because that collapse is this slice's regression test, and a regression test that
##    passes at 1e-3 cannot tell a good quadrature from a subtly wrong integrand. At 1e-12 it can.
##
## 2. KINKS LAND ON PANEL BOUNDARIES. b(s) is piecewise linear, so the integrand has a derivative
##    discontinuity at every breakpoint. Simpson's error bound assumes a smooth fourth derivative,
##    and a panel straddling a kink quietly loses its order. Integrating each linear segment
##    separately means no panel ever spans one, and the order is kept on every piece.
##
## Inside a tapered segment the integrand is quadratic-over-linear rather than polynomial, so there
## the rule is an approximation like any other — but a fourth-order one over 120 sub-intervals per
## segment, which is deep in the noise against the +/-20% the physics itself is quoted at. Gauss
## quadrature would be more accurate per station and would give up property 1's exactness; adaptive
## refinement would cost determinism, which a test suite values more than the last digit.
func compliance_integral() -> float:
	if not is_valid():
		return 0.0
	var total := 0.0
	var breakpoints := _integration_breakpoints()
	for i in range(breakpoints.size() - 1):
		total += _simpson(breakpoints[i], breakpoints[i + 1], STATIONS_PER_SEGMENT)
	return total


func _integration_breakpoints() -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0])
	for station in profile_s_m:
		if station > out[out.size() - 1] + 1.0e-12 and station < length_m - 1.0e-12:
			out.append(station)
	out.append(length_m)
	return out


func _integrand(s: float) -> float:
	var inertia := second_moment_at(s)
	if inertia <= 0.0:
		return 0.0
	var lever := length_m - s
	return lever * lever / inertia


func _simpson(a: float, b: float, intervals: int) -> float:
	var n := intervals if intervals % 2 == 0 else intervals + 1
	var h := (b - a) / float(n)
	var total := _integrand(a) + _integrand(b)
	for i in range(1, n):
		total += _integrand(a + h * i) * (4.0 if i % 2 == 1 else 2.0)
	return total * h / 3.0


## Metres of tip deflection under a tip load of `force_n`. ENGINEERING-GRADE.
##
## Linear in F by construction — this is small-deflection beam theory, and a carbon arm that is
## deflecting non-linearly has already failed §4.5 and is not a stiffness question any more.
func tip_deflection_m(force_n: float) -> float:
	var modulus := youngs_modulus_pa()
	if modulus <= 0.0:
		return 0.0
	return force_n * compliance_integral() / modulus


## N/m. The arm as a spring at the motor mount: k = F/delta. ENGINEERING-GRADE with a
## CHARACTERISTIC root-fixity factor on it (§10, open question 4 — this is the mixed tier the
## document flags, and the honest reading is "engineering-grade shape, characteristic scale").
##
## THE ROOT FIXITY FACTOR IS APPLIED HERE AND NOWHERE ELSE. One multiplication, one place, so that
## anyone auditing the free constants can grep it and find one hit.
func k_tip_n_per_m() -> float:
	var compliance := compliance_integral()
	var modulus := youngs_modulus_pa()
	if compliance <= 0.0 or modulus <= 0.0:
		return 0.0
	return root_fixity() * modulus / compliance


# ---------------------------------------------------------------------------
# Mass
# ---------------------------------------------------------------------------

## Kilograms of the arm itself. Integrated over the same taper the stiffness is integrated over,
## which is the point of §0's rule: widen the arm on screen and BOTH the mass and the resonance
## move, because they are integrals of the same polygon.
##
## The width profile is piecewise linear, so its area is exact by trapezoid — no quadrature error
## and no reason to reach for one.
func arm_mass_kg() -> float:
	if not is_valid():
		return 0.0
	return plan_area_m2() * thickness_m * materials.density(material_id)


func plan_area_m2() -> float:
	if profile_b_m.size() < 2:
		return width_at(0.0) * length_m
	var area := 0.0
	for i in range(profile_b_m.size() - 1):
		area += 0.5 * (profile_b_m[i] + profile_b_m[i + 1]) * (profile_s_m[i + 1] - profile_s_m[i])
	return area


# ---------------------------------------------------------------------------
# §4.3 Resonance
# ---------------------------------------------------------------------------

## Hz. The arm's first bending mode, by Rayleigh's method (§4.3):
##
##     f1 = (1/2pi) * sqrt( k_tip / (m_tip + (33/140)*m_arm) )
##
## THIS IS THE NUMBER THIS WHOLE SLICE EXISTS FOR. It is what `REFERENCE_RESONANCE_HZ := 180.0`
## guesses, computed instead.
##
## Rayleigh works by assuming the mode shape is the STATIC deflected shape and equating peak kinetic
## and strain energy. That assumption is always slightly stiff — a static shape is not the true mode
## shape, and any assumed shape overestimates the frequency — which is why tests/test_arm_beam.gd
## checks the bare-beam case against the exact Euler-Bernoulli eigenvalue and expects to be a bit
## HIGH rather than merely "close". Being high in a KNOWN direction by a KNOWN amount is a much
## stronger statement about a model than being close in an unknown one.
##
## Two facts make this the right formula rather than a new one, and both are asserted rather than
## asserted-about:
##
##   1. TIP MASS DOMINANT (m_tip >> m_arm): k goes as 1/L^3, so f goes as L^-1.5. That is EXACTLY
##      the exponent `VibrationModel.ARM_LENGTH_EXPONENT` already uses, and whose comment goes out
##      of its way to say it is 1.5 and NOT the commonly quoted 2. The new model reproduces the old
##      model in the old model's own regime, from different premises. That is agreement, not
##      coincidence.
##   2. TIP MASS VANISHING: it degenerates to the bare cantilever's L^-2. The old model could not
##      express that case at all — it had no term for the arm's own mass.
##
## Reproducing the old law AND explaining its limit is the entire argument that this is right.
func resonance_hz() -> float:
	var stiffness := k_tip_n_per_m()
	var effective_mass := tip_mass_kg + RAYLEIGH_MASS_FRACTION * arm_mass_kg()
	if stiffness <= 0.0 or effective_mass <= 0.0:
		return 0.0
	return sqrt(stiffness / effective_mass) / TAU


# ---------------------------------------------------------------------------
# §4.4 Torsion
# ---------------------------------------------------------------------------

## Degrees of twist at the tip under motor drag torque T. **CHARACTERISTIC — RANKING ONLY.**
##
##     J ~= (1/3)*b*t^3        theta = T*L/(G*J)
##
## Note t^3 again: the same lesson as bending, in the axis a builder never thinks about.
##
## WHY THIS MAY NOT BE QUOTED, stated here and repeated in the returned dictionary so it cannot be
## lost on the way to a legend: G for a carbon plate in this loading is MATRIX-DOMINATED. The fibres
## barely participate; the resin does the work, and the resin's contribution depends on the layup,
## the cure and the resin system, none of which a builder knows and none of which the material table
## has a source for. CHARACTERISTIC_SHEAR_FRACTION above is a plausible band, not a measurement.
## The RANKING this produces — thinner plate twists much more, longer arm twists more — is sound,
## because those dependencies are geometric and G only scales the whole column.
##
## The thin-strip J is itself an approximation valid for b >> t, which is exactly the regime a plate
## arm is in; `characteristic` in the result is true regardless, so there is no aspect-ratio branch
## that could make this look quotable in some corner.
func torsion_deg(torque_nm: float) -> Dictionary:
	var shear_modulus := youngs_modulus_pa() * CHARACTERISTIC_SHEAR_FRACTION
	var mean_width := plan_area_m2() / length_m if length_m > 0.0 else 0.0
	var torsion_constant := mean_width * pow(thickness_m, 3.0) / 3.0
	var twist_rad := 0.0
	if shear_modulus > 0.0 and torsion_constant > 0.0:
		twist_rad = torque_nm * length_m / (shear_modulus * torsion_constant)
	return {
		"twist_deg": rad_to_deg(twist_rad),
		"torsion_constant_m4": torsion_constant,
		"shear_modulus_pa": shear_modulus,
		"tier": "characteristic",
		"tier_note": "ranking only; G for a carbon plate in torsion is matrix-dominated and unsourced",
	}


# ---------------------------------------------------------------------------
# §4.5 Strength
# ---------------------------------------------------------------------------

## Pa. Bending stress at station s under a tip load, for a rectangular section:
##
##     sigma = M*c/I = 6*M/(b*t^2),   M = F*(L - s)
##
## ENGINEERING-GRADE. Rises toward the ROOT on a constant-width arm because the moment arm does —
## which is why an arm that fails, fails at the root, and why §4.5 puts the root first.
##
## A taper toward the tip flattens this: it removes material exactly where the moment is small. That
## is the real reason arms are tapered, and it is a stress argument rather than the mass argument
## builders usually give for it.
func bending_stress_pa(force_n: float, s: float) -> float:
	var b := width_at(s)
	if b <= 0.0 or thickness_m <= 0.0:
		return 0.0
	var moment := force_n * (length_m - s)
	return 6.0 * moment / (b * thickness_m * thickness_m)


## Pa. The same bending stress raised by the net section at a bolt hole of diameter `hole_d_m`:
##
##     sigma_net = sigma * b / (b - d)
##
## EXACT ARITHMETIC on the geometry (the load has to go through less material, in the ratio of the
## widths) and ENGINEERING-GRADE as a failure prediction. A bolt hole through a narrow arm is a real
## and common failure point; a 4 mm hole in a 12 mm arm is a 1.5x stress riser, which is a sentence
## worth putting in front of someone about to drill one.
##
## Returns 0 for a hole that consumes the section: that is not a stress, it is a cut arm, and
## reporting a very large number would imply the beam model still applies.
func net_section_stress_pa(force_n: float, s: float, hole_d_m: float) -> float:
	var b := width_at(s)
	if b <= 0.0 or hole_d_m >= b:
		return 0.0
	return bending_stress_pa(force_n, s) * b / (b - hole_d_m)


## Pa. Bearing stress where a bolt presses on the hole wall: sigma = F/(d*t). Carbon crushes around
## under-sized bolts long before the plate itself breaks, which is why this is its own load case and
## not a footnote to the last one.
func bearing_stress_pa(force_n: float, hole_d_m: float) -> float:
	if hole_d_m <= 0.0 or thickness_m <= 0.0:
		return 0.0
	return force_n / (hole_d_m * thickness_m)


## The §4.5 report: every stress above as a FRACTION of the material's published strength, because
## "this arm root reaches 40% of the plate's flexural strength" is a sentence a builder can act on
## and "218 MPa" is not.
##
## NOT a pass/fail, deliberately. The strength figure carries its own uncertainty, the load case is
## an assumption, and a boolean would hide both behind a colour.
##
## A material whose table declines to quote a strength (TPU) yields fractions of 0.0 and
## `strength_known` false — "not answerable here", never "fine".
func strength_report(force_n: float, hole_d_m: float = 0.0, s: float = 0.0) -> Dictionary:
	var strength_pa := 0.0
	if materials != null:
		strength_pa = materials.strength_mpa(material_id) * 1.0e6
	var bending := bending_stress_pa(force_n, s)
	var net := net_section_stress_pa(force_n, s, hole_d_m) if hole_d_m > 0.0 else bending
	var bearing := bearing_stress_pa(force_n, hole_d_m) if hole_d_m > 0.0 else 0.0
	var known := strength_pa > 0.0
	return {
		"bending_stress_pa": bending,
		"net_section_stress_pa": net,
		"bearing_stress_pa": bearing,
		"strength_pa": strength_pa,
		"strength_known": known,
		"bending_fraction": bending / strength_pa if known else 0.0,
		"net_section_fraction": net / strength_pa if known else 0.0,
		"bearing_fraction": bearing / strength_pa if known else 0.0,
		"tier": "engineering-grade",
	}


# ---------------------------------------------------------------------------
# The whole answer, in one dictionary
# ---------------------------------------------------------------------------

## Everything a bench or an overlay wants, with its tiers attached. Assembled rather than computed
## piecemeal by the caller so that no consumer can pick up the resonance without also picking up the
## label saying what may be claimed for it.
func summary(force_n: float = 10.0) -> Dictionary:
	return {
		"valid": is_valid(),
		"errors": errors.duplicate(),
		"length_m": length_m,
		"thickness_m": thickness_m,
		"root_width_m": width_at(0.0),
		"tip_width_m": width_at(length_m),
		"arm_mass_kg": arm_mass_kg(),
		"tip_mass_kg": tip_mass_kg,
		"youngs_modulus_pa": youngs_modulus_pa(),
		"k_tip_n_per_m": k_tip_n_per_m(),
		"tip_deflection_m": tip_deflection_m(force_n),
		"resonance_hz": resonance_hz(),
		"root_fixity": root_fixity(),
		"root_fixity_is_a_guess": true,
		"tier_deflection": "engineering-grade",
		"tier_resonance": "engineering-grade shape, characteristic root-fixity scale",
		"tier_torsion": "characteristic",
	}
