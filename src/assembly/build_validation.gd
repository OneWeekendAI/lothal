class_name BuildValidation
extends RefCounted
## Predicted versus reported mass for a WHOLE AIRCRAFT that someone really built and really
## weighed — ThrustValidation's sibling, one level up.
##
## ThrustValidation answers "does the thrust model predict a prop it was never fitted on".
## Everything ABOVE thrust in this project is still self-referential: the reference build's
## 496 g, 11.7:1 and 29% hover are asserted in six test files, and every one of those
## assertions checks the model against itself. If ELECTRONICS_MASS_G were wrong by 15 g the
## whole suite would stay green and every build in the catalog would be quietly wrong by the
## same amount. This class is the first thing in the project that could notice.
##
## WHAT IS ACTUALLY UNDER TEST, stated precisely, because a validation number that does not
## say what it validates is worth as little as no number at all:
##
##   Build.mass_parts() — the sum of frame, four motor-and-prop pairs, the two boards, and
##   the loose electronics budget. Not a physical prediction; an addition. The interesting
##   term by far is Build.ELECTRONICS_MASS_G's undisplaced remainder (LTHL-11): 35 g standing
##   in for a VTX, a camera, a receiver, an antenna, straps, screws and wiring, whose real
##   total varies a lot between aircraft and is the one number here nobody has ever measured.
##
## THE QUANTITY IS DRY MASS — ALL-UP WEIGHT LESS THE PACK — and that is a deliberate
## narrowing of what this slice was asked for, so it is stated at the top rather than buried.
## Two reasons, and the second is the one that decided it:
##
##   1. Including the pack would FLATTER the model. A 5" build carries 240 g of battery in a
##      700 g all-up weight, and that 240 g is the one mass in the aircraft that is printed on
##      the wrapper and that no model has to predict. Carrying it in the denominator would
##      halve every error this file reports without the model having got anything more right.
##   2. The packs these aircraft are weighed with cannot be entered honestly. A manufacturer
##      publishes a takeoff weight "with a 1480 mAh battery" and sells no such pack; the
##      pack's internal resistance and C-rating — both physics-bearing `specs` in
##      batteries.json — are published by nobody. Adding a battery to make a build fit would
##      be exactly the fabrication data/validation/builds.json's schema forbids.
##
## So each build is evaluated on a STAND-IN pack (PACK_ID below) and the pack's mass is
## subtracted from both sides, where it cancels exactly. tests/test_build_validation.gd
## asserts that cancellation against a different pack rather than trusting this paragraph.
##
## HOVER THROTTLE IS NOT VALIDATED HERE, and that is the same constraint biting in a place
## where it cannot be worked around: hover throttle depends on the pack's mass, its resting
## voltage and its internal resistance, so a stand-in pack does not cancel out of it — it
## replaces the answer. The slice this file came from asked for hover throttle as the second
## quantity and named this exact outcome as a legitimate finding rather than a failure. See
## builds.json's `_schema` for what would have to be published for it to become possible.
##
## FLIGHT TIME IS NOT VALIDATED EITHER, for a different and more permanent reason:
## Build.FREESTYLE_FLIGHT_PROFILE is an assumed mission mix, the forward-flight propeller model
## under it is characteristic and quotes no error bar, and REFERENCE_DRAG_AREA_M2 is one fixed
## number with no moment arm (LTHL-16). A flight-time miss could come from the mass model or from
## any of those, and a number that cannot say which part is wrong is not evidence about any of
## them.

## Error bound, as a fraction of the reported dry mass. FIXED IN ADVANCE of running it against
## a single real aircraft, and committed before the data was, so the git history shows the
## bound was chosen blind. That ordering is the methodological content of this file, exactly
## as it was for ThrustValidation.
##
## Five percent, and the reasoning is that this is NOT a physical prediction. Thrust
## prediction gets ten and twenty percent because it interpolates rules of thumb across
## propeller geometry; this is a sum of masses that are each printed on a product page. There
## is no modelling in it to be generous about. What the five percent is actually buying is:
##
##   - the 35 g loose-electronics budget, which is the only invented number in the sum, and
##     which is about 8% of a 5" aircraft's dry mass. A bound tighter than the size of the
##     one term under test could not be met by a correct model either.
##   - the FC and ESC standing at their budgeted 8 g and 12 g rather than at the boards these
##     aircraft actually fly, because a named flight controller cannot be entered in the
##     catalog without inventing gyro noise and bias figures no manufacturer publishes. Worth
##     a handful of grams, in a known direction: the shipped boards are mini-stack class.
##   - published frame masses that sometimes exclude the TPU the assembled aircraft carries.
##
## If a build busts this, the answer is to report it and look at the model — most likely at
## ELECTRONICS_MASS_G. A bound moved to fit the data it measures is not a bound
## (thrust_validation.gd:44 says this first, and it applies here verbatim).
const DRY_MASS_BOUND := 0.05

## The stand-in pack every validation build is assembled with. Its mass is subtracted from the
## prediction, so it cannot reach the reported number — see the header, and the test that
## proves it rather than asserting it. A 6S pack rather than a 4S one only so that the
## assembled Build is a physically sensible aircraft while its mass is being read off.
const PACK_ID := "battery_6s_1300"

const DATASET_PATH := "res://data/validation/builds.json"


## The held-out builds, straight off disk, in file order. An empty array is a real answer and
## the caller must treat it as one: "not validated" and "passes" are opposite things, and the
## suite fails on zero rather than reporting a vacuous success.
static func load_dataset() -> Array:
	if not FileAccess.file_exists(DATASET_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATASET_PATH))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("builds"):
		return []
	return (parsed as Dictionary)["builds"]


## The `_schema` prose the dataset carries, for the same reason PartsCatalog.schema_for exists:
## nothing in the app reads it, and a test holds it to what it claims.
static func schema() -> String:
	if not FileAccess.file_exists(DATASET_PATH):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATASET_PATH))
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("_schema", ""))


## One held-out build, evaluated. Empty for an entry naming a part the catalog does not have —
## which is a data error the suite reports by name rather than a point to be skipped quietly.
##
## Keys: build_id, name, predicted_dry_mass_g, reported_dry_mass_g, error_fraction (signed;
## positive means the model predicts a HEAVIER aircraft than was weighed), bound, within_bound,
## source.
static func evaluate(catalog: PartsCatalog, entry: Dictionary) -> Dictionary:
	for key in ["frame_id", "motor_id", "propeller_id"]:
		if catalog.get_part(String(entry.get(key, ""))).is_empty():
			return {}
	if catalog.get_part(PACK_ID).is_empty():
		return {}

	# A component id that resolves to nothing is left UNFITTED by Build.from_ids — which is the
	# right answer for the app (a missing part is visible in the details panel) and the wrong one
	# here, because an unfitted component weighs zero and a typo would quietly make an aircraft
	# lighter and its error better. So a named component that does not exist fails the whole entry,
	# the same way a named frame does. An empty string is not a typo: it is "not fitted", said
	# deliberately, and it is allowed through.
	for category in Build.OPTIONAL_COMPONENTS:
		var component_id := String((entry.get("components", {}) as Dictionary).get(category, ""))
		if component_id != "" and catalog.get_part(component_id).is_empty():
			return {}

	var reported: float = float(entry.get("reported_dry_mass_g", 0.0))
	if reported <= 0.0:
		return {}

	# The two boards are chosen by the aircraft's PUBLISHED stack size — a 20x20 mini stack gets
	# the catalog's 20x20 boards — and that choice is made off the spec sheet before any error is
	# computed. Picking the board that flattered the number afterwards would be fitting the model
	# to the data it is being measured against. An entry that names neither gets Build's defaults,
	# which is the full-size 30.5x30.5 pair.
	#
	# THE FOUR OPTIONAL COMPONENTS GO THROUGH THE SAME RULE AND THE SAME SENTENCE, and this call
	# site not passing them was a real defect rather than an omission: every entry in this dataset
	# names a DJI O4 Air Unit Pro in its `source`, and every one of them was silently modelled on
	# Build's defaults — an 8 g analog camera and a 6 g 400 mW transmitter, 14 g standing in for a
	# digital HD air unit. There was no way to say otherwise, so every number this file ever
	# produced was computed on a wrong input. `components` is that way. An entry that omits it, or
	# omits a category within it, still gets Build's defaults and still builds the aircraft it used
	# to; an empty string is NOT FITTED, which is how an entry says its air unit's antennas are
	# already counted somewhere else.
	var build := Build.from_ids(catalog, String(entry["frame_id"]), String(entry["motor_id"]),
		String(entry["propeller_id"]), PACK_ID,
		String(entry.get("esc_id", Build.DEFAULT_ESC_ID)),
		String(entry.get("fc_id", Build.DEFAULT_FC_ID)),
		entry.get("components", {}))
	var predicted := predicted_dry_mass_g(build)
	var error_fraction := (predicted - reported) / reported

	return {
		"build_id": String(entry.get("build_id", "?")),
		"name": String(entry.get("name", entry.get("build_id", "?"))),
		"predicted_dry_mass_g": predicted,
		"reported_dry_mass_g": reported,
		"error_fraction": error_fraction,
		"bound": DRY_MASS_BOUND,
		"within_bound": absf(error_fraction) <= DRY_MASS_BOUND,
		"source": String(entry.get("source", "")),
	}


## The aircraft without its battery, in grams. The one place the subtraction happens, so the
## claim "the pack cancels" is a property of one line rather than of two call sites that could
## drift apart.
static func predicted_dry_mass_g(build: Build) -> float:
	return build.all_up_weight_g() - float(build.battery["mass_g"])


## Every entry in the dataset, evaluated, skipping nothing silently — an entry that cannot be
## evaluated yields an empty dictionary and is reported as such by the caller.
static func evaluate_all(catalog: PartsCatalog, dataset: Array = load_dataset()) -> Array:
	var out: Array = []
	for entry in dataset:
		out.append(evaluate(catalog, entry))
	return out


## The signed mean error across the dataset, as a fraction. Reported separately from the
## spread, and this is the whole point of keeping the sign: a symmetric scatter says the model
## is right on average and noisy, and a consistent bias says a constant in Build is wrong by a
## fixed amount. Only one of those is fixable, and averaging the magnitudes would hide which
## one you have.
static func signed_mean_error(points: Array) -> float:
	var total := 0.0
	var count := 0
	for point in points:
		if point.is_empty():
			continue
		total += float(point["error_fraction"])
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## One line per build, or the honest absence of one. Never invents a number: an empty dataset
## reads as "not validated", which is what an empty dataset means.
static func summary(catalog: PartsCatalog, dataset: Array = load_dataset()) -> String:
	var lines: PackedStringArray = []
	for point in evaluate_all(catalog, dataset):
		if point.is_empty():
			continue
		lines.append("%s: predicted %.0f g dry vs reported %.0f g (%+.1f%%)" % [
			point["name"], point["predicted_dry_mass_g"], point["reported_dry_mass_g"],
			point["error_fraction"] * 100.0])
	if lines.is_empty():
		return "not validated"
	return "\n".join(lines)
