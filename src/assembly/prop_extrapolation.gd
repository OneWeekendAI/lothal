class_name PropExtrapolation
extends RefCounted
## How far a build's fitted prop sits from the prop its motor was thrust-tested on, and whether
## that distance is one Lothal is willing to stand behind.
##
## ===========================================================================
## THE PROBLEM
## ===========================================================================
##
## build.gd fits k_t from motor.max_thrust_g on the prop the manufacturer measured it on, and then
## moves that k_t to the fitted prop through the BEMT geometry ratio (§0, P5):
##
##     k_t' = k_t * BEMT(to, rpm) / BEMT(from, rpm)
##
## Blade count and twist enter the integral where they act — the exponents are deleted. What
## remains uncertain is the CHORD: every preset's planform is generated (chord_is_assumed), so the
## further the fitted prop sits from the test prop, the more the reported thrust depends on a
## planform nobody published.
##
## Diameter errors stay brutal in particular: the integral runs over the disc, so thrust still
## scales close to D^4 and a 20% diameter change is near enough a 2x change in k_t. A custom
## motor tested on a 5" prop and flown on a 7" is having its thrust extrapolated by more than
## the catalog's own worst noise — and on a planform that was generated for both ends of the
## move, not published for either.
##
## ===========================================================================
## THE BOUND, AND WHY IT IS WHERE IT IS
## ===========================================================================
##
## Anywhere the combined correction moves k_t by more than a factor of TWO, this file says so:
##
const EXTRAPOLATION_BOUND := 2.0
##
## The 1.8x FLOOR. MotorPlausibility's finding — that five shipped motors sharing prop_5x43x3 as
## their test prop fit k_t values whose ratio spans 1.79x — is the honest lower limit on any bound
## here. The catalog itself already disagrees with itself by 1.8x on ONE prop with ZERO
## extrapolation, so a bound tighter than that would fire on scaled k_t values that are inside the
## catalog's own noise. 1.8x is therefore the smallest defensible bound.
##
## The MARGIN. Setting the bound at the noise floor means every build sitting one shipped catalog's
## standard deviation above nominal on the scaling side would warn — which is a false positive
## rate no builder would trust. Widening to 2.0 leaves the bound at the same shape (a factor above
## unity) while giving a little space for the scaling itself to move without a warning. It is not a
## generous margin, and that is on purpose: a 2x correction is IS a lot, and calling it out with a
## small buffer is better than hiding it with a large one.
##
## THIS BOUND WILL FIRE ON CATALOG BUILDS TOO, and that is not a bug. If a shipped combination is
## already extrapolating hard, the reader deserves to know it today. Silencing catalog builds would
## turn the warning into a label on custom parts rather than a statement about physics — a category
## error the whole file is written to avoid.
##
## The 1.8x figure itself is derived from MotorPlausibility.k_t_band_for_prop's own inputs; it is
## not hardcoded here.
##
## ===========================================================================
## SEVERITY
## ===========================================================================
##
## CHARACTERISTIC, and this is the case the severity scale exists for. Nothing binds; the aircraft
## flies exactly as its numbers say. What the warning describes is HOW MUCH those numbers are
## being derived from a rule of thumb rather than from the manufacturer's own bench — a property
## of the build, plainly stated, with the reader left to decide what to do with it. LIMITING would
## claim something caps this build when nothing does, and IMPOSSIBLE would claim the aircraft
## cannot exist.

const NAME := &"prop_extrapolation"


## Everything this file has to say about one build, in one list. Empty when the fitted prop is
## the motor's own test prop (correction 1.0) or when it is near enough.
static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	var test_prop_id := str(build.motor.get("thrust_test", {}).get("prop_id", ""))
	if test_prop_id == "":
		return out
	var test_prop: Dictionary = build.catalog.get_part(test_prop_id)
	if test_prop.is_empty():
		return out

	# The cross-prop distance is the BEMT geometry ratio (§0, P5): blade count and twist enter
	# the integral where they act, at the RPM the motor's k_t was fitted at. The arithmetic is
	# Rust's (Plausibility.extrapolation_factors → BemtModel.scale_k_t_to_prop); here we supply
	# both planforms and the fit RPM.
	var from_doc := PropellerDocument.from_catalog_prop(test_prop)
	var to_doc := PropellerDocument.from_catalog_prop(build.propeller)
	var fit_rpm := float(build.motor["specs"]["kv"]) \
		* float(build.motor["thrust_test"]["voltage_v"])
	var factors: PackedFloat64Array = Plausibility.extrapolation_factors(
		from_doc.diameter_mm * 0.001, from_doc.pitch_mm * 0.001, float(from_doc.blades), from_doc.chord,
		to_doc.diameter_mm * 0.001, to_doc.pitch_mm * 0.001, float(to_doc.blades), to_doc.chord,
		fit_rpm)
	var ratio := factors[0]
	var magnitude := factors[1]

	# Symmetric around 1.0: an aircraft flown on a prop that HALVES its k_t is extrapolating just
	# as far as one that DOUBLES it, and the reader deserves the same sentence either way.
	if magnitude <= EXTRAPOLATION_BOUND:
		return out

	out.append(BuildWarning.characteristic(NAME,
		"%s on a motor thrust-tested with %s puts the reported thrust %.1fx off the manufacturer's own bench — that difference is computed by the blade-element integral on the two props' own geometry (chord assumed), not by a fitted rule of thumb. The chord on a preset is assumed, so an extrapolation this far is worth more scepticism than the number itself carries." % [
			build.propeller.get("name", build.propeller.get("part_id", "?")),
			test_prop.get("name", test_prop.get("part_id", "?")),
			magnitude],
		{"correction": ratio, "magnitude": magnitude,
			"test_prop_id": test_prop_id}))
	return out
