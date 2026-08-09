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
## moves that k_t to the fitted prop through PropellerModel.scale_k_t_to_prop:
##
##     k_t' = k_t * (D'/D)^4 * (blades'/blades)^0.8 * (pitch'/pitch)^0.5
##
## Only the D^4 term is exact — it is dimensional. The blade-count and pitch exponents are rules of
## thumb, admitted as such in propeller_model.gd's own doc comments, "to be replaced when per-prop
## thrust tables are authored". So the further the fitted prop sits from the test prop in any of
## those three ratios, the more the reported thrust is being computed by extrapolating two guesses.
##
## The D^4 term makes diameter errors brutal in particular: a 20% diameter change is a 2x change
## in k_t, before either rule of thumb speaks. A custom motor tested on a 5" prop and flown on a
## 7" is having its thrust extrapolated by more than the catalog's own worst noise.
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

## Mirrors propeller.rs (BLADE_COUNT_EXPONENT/PITCH_EXPONENT). Rust cannot export constants
## to GDScript, so the exponents keep a module const here; the value must agree with the
## Rust source of truth. Two things enforce that, and neither is optional: the Tier 2 golden
## cross-check (tests/rust_crosscheck_tier2.gd) hardcodes 0.8/0.5 rather than referencing
## these consts, so it pins the Rust; and test_rust_constants.gd asserts the copy below
## equals what the Rust reports, so the two cannot drift apart silently.
const BLADE_COUNT_EXPONENT := 0.8
const PITCH_EXPONENT := 0.5


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

	var from_geom := _geometry(test_prop)
	var to_geom := _geometry(build.propeller)
	if from_geom.is_empty() or to_geom.is_empty():
		return out

	# The factors, their product, the magnitude and the dominant-term ranking all live in Rust
	# (rust/src/plausibility.rs) — the same D^4/blades^0.8/pitch^0.5 arithmetic one copy of.
	var factors: PackedFloat64Array = Plausibility.extrapolation_factors(
		from_geom.diameter_m, from_geom.pitch_m, from_geom.blades,
		to_geom.diameter_m, to_geom.pitch_m, to_geom.blades)
	var diameter_factor := factors[0]
	var blade_factor := factors[1]
	var pitch_factor := factors[2]
	var combined := factors[3]
	var magnitude := factors[4]

	# Symmetric around 1.0: an aircraft flown on a prop that HALVES its k_t is extrapolating just
	# as far as one that DOUBLES it, and the reader deserves the same sentence either way.
	if magnitude <= EXTRAPOLATION_BOUND:
		return out

	# Which of the three ratios is doing the work — reported as the dominant term rather than as a
	# split, because a builder acting on the warning wants to know what to change and a split is
	# usually one term with two rounding companions. The ranking is Rust's; this maps it to words.
	var dominant := _dominant_term(int(factors[5]))

	out.append(BuildWarning.characteristic(NAME,
		"%s on a motor thrust-tested with %s puts the reported thrust %.1fx off the manufacturer's own bench — that difference is %s, computed by %s. Only the diameter term is exact (T ∝ D⁴, dimensional); the blade and pitch exponents are documented rules of thumb, so an extrapolation this far is worth more scepticism than the number itself carries." % [
			build.propeller.get("name", build.propeller.get("part_id", "?")),
			test_prop.get("name", test_prop.get("part_id", "?")),
			magnitude, dominant["what"], dominant["how"]],
		{"correction": combined, "magnitude": magnitude,
			"diameter_factor": diameter_factor, "blade_factor": blade_factor,
			"pitch_factor": pitch_factor, "test_prop_id": test_prop_id,
			"dominant_term": dominant["term"]}))
	return out


static func _geometry(prop: Dictionary) -> Dictionary:
	var specs: Dictionary = prop.get("specs", {})
	var diameter_in := float(specs.get("diameter_inches", 0.0))
	var pitch_in := float(specs.get("pitch_inches", 0.0))
	var blades := float(specs.get("blades", 0.0))
	if diameter_in <= 0.0 or pitch_in <= 0.0 or blades <= 0.0:
		return {}
	# Ratios cancel the unit, so anything consistent works — keeping inches here avoids one round
	# trip through 0.0254 that would otherwise buy nothing but a chance for a copy-paste bug.
	return {"diameter_m": diameter_in, "pitch_m": pitch_in, "blades": blades}


## The sentence for the dominant term, by the index Rust ranked (0=diameter, 1=blades, 2=pitch).
## Log-distance because the three factors combine multiplicatively — a 1.5x diameter factor
## beside a 0.8x pitch factor are pulling equally hard in opposite directions, and log|f| ranks
## them honestly. The ranking itself moved to Rust; this maps the winner back to words.
static func _dominant_term(dominant_idx: int) -> Dictionary:
	var terms := [
		{"term": "diameter", "what": "almost all diameter",
			"how": "the exact D⁴ term"},
		{"term": "blades", "what": "mostly blade count",
			"how": "the blades^%.1f rule of thumb" % BLADE_COUNT_EXPONENT},
		{"term": "pitch", "what": "mostly pitch",
			"how": "the pitch^%.1f rule of thumb" % PITCH_EXPONENT},
	]
	return terms[clampi(dominant_idx, 0, 2)]
