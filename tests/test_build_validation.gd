class_name TestBuildValidation
extends RefCounted
## Held-out validation one level above thrust: does the MASS model predict an aircraft it was
## never calibrated against?
##
## tests/test_validation.gd is the answer to the objection that would sink the thrust stand.
## This file is the answer to the objection that would sink everything above it. The reference
## build's 496 g, 11.7:1 and 29% hover are asserted in test_hover, test_esc, test_build_panel,
## test_build_warnings, test_flight_controller and test_battery_model — and every one of those
## checks the model against a fixture the model's own constants were chosen to reproduce. Move
## Build.ELECTRONICS_MASS_G by 15 g and all six stay green while every aircraft in the catalog
## becomes wrong by 15 g. Nothing in the project noticed that until this file.
##
## THE BOUND IS FIXED IN BuildValidation AND WAS COMMITTED BEFORE THE DATA WAS. That ordering
## is the methodological content here, exactly as it was for ThrustValidation: a bound set
## after seeing the errors is not a bound, it is a description, and it passes for ever no
## matter what the model does. If a build busts it, the honest response is to report the
## failure and look at the model — not to widen the bound.
##
## What is under test is Build.mass_parts(), and the interesting term in it by a distance is
## the 35 g of loose electronics that LTHL-11 will eventually unbundle: a VTX, a camera, a
## receiver, an antenna, straps, screws and wiring, standing as one budgeted lump that nobody
## has ever weighed. See BuildValidation's header for why the quantity is DRY mass and why
## hover throttle is absent.

## Builds that miss the bound for a reason that has been investigated and written down.
##
## This is NOT a way to make a failing check green, and the shape of it is what stops it being
## one. A build listed here must STILL miss, by the recorded amount, within `tolerance`. If the
## model improves and the aircraft comes inside the bound, this suite FAILS and says so —
## because a finding that quietly disappears is as much a change to the validation as a new
## bust is, and the record has to be updated deliberately rather than decay into a list of
## excuses nobody rereads.
##
## The alternative was widening DRY_MASS_BOUND, which BuildValidation forbids in as many words:
## a bound moved to fit the data it measures is not a bound. Nothing here moves it. The bound
## still applies, unchanged, to every build not named below, and the named one is pinned to the
## error it actually has rather than forgiven.
##
## Entering something here requires the `why` to be a claim about the WORLD — a spec sheet, a
## missing part, a published number that disagrees with itself — never "the model is a bit off".
## If the reason is that the model is wrong, the fix is the model.
const KNOWN_MISSES := {
	"iflight_nazgul_evoque_f5_v3_o4_6s": {
		"error_fraction": -0.070,
		"tolerance": 0.015,
		"why": "iFlight publishes the V3 as 56 g heavier than the V2 while publishing its frame "
			+ "kit as only 7 g heavier. Same motors, same propellers, same O4 air unit, same "
			+ "20x20 stack class — the ~49 g gap is in neither spec sheet, and it is a fact "
			+ "about two product pages rather than a fact about Build.mass_parts(). "
			+ "REWRITTEN 2026-08-16, and what changed is worth reading before trusting the "
			+ "number above. The recorded error was -10.4% while every entry in the dataset was "
			+ "modelled with an 8 g analog camera and a 6 g 400 mW VTX standing in for the "
			+ "digital O4 air unit all three aircraft actually carry — a wrong input worth 17 g "
			+ "on every point. Naming the real parts moved this build to -7.0%, so about a "
			+ "third of the recorded miss was the model being fed the wrong aircraft and two "
			+ "thirds is the published gap. The finding survives with its magnitude cut and its "
			+ "argument sharpened: the V2, built from the same constants and the same air unit, "
			+ "now comes in at +3.4%, so a constant large enough to close the V3's 34 g would "
			+ "push the V2 to about +11% — further out than the V3 is now, and in the opposite "
			+ "direction. It stands until somebody weighs a V3 themselves.",
	},
}


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_every_build_is_within_its_bound(catalog))
	results.append_array(_test_the_error_is_reported_with_its_sign(catalog))
	results.append_array(_test_the_data_is_genuinely_held_out())
	results.append_array(_test_the_pack_cancels(catalog))
	results.append_array(_test_the_entry_chooses_its_components(catalog))
	results.append_array(_test_the_check_can_actually_fail())

	return results


# ---------------------------------------------------------------------------
# The claim
# ---------------------------------------------------------------------------

static func _test_every_build_is_within_its_bound(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lines: PackedStringArray = []
	var busted: PackedStringArray = []
	var unresolved: PackedStringArray = []
	var count := 0

	var drifted: PackedStringArray = []
	var seen_misses: PackedStringArray = []

	var dataset := BuildValidation.load_dataset()
	for i in dataset.size():
		var point: Dictionary = BuildValidation.evaluate(catalog, dataset[i])
		if point.is_empty():
			unresolved.append(String(dataset[i].get("build_id", "entry %d" % i)))
			continue
		count += 1
		var line := "%s: %.0f g predicted vs %.0f g reported, %+.1f%% (bound %.0f%%)" % [
			point["name"], point["predicted_dry_mass_g"], point["reported_dry_mass_g"],
			point["error_fraction"] * 100.0, point["bound"] * 100.0]
		lines.append(line)

		var build_id := String(point["build_id"])
		if KNOWN_MISSES.has(build_id):
			# A recorded finding. It must still hold, and it is checked in BOTH directions: an
			# error that grew means something moved, and an error that shrank into the bound
			# means the finding is stale. Either way the record is now a lie and must be
			# rewritten by a person who has looked at why.
			seen_misses.append(build_id)
			var record: Dictionary = KNOWN_MISSES[build_id]
			var expected := float(record["error_fraction"])
			var actual := float(point["error_fraction"])
			if absf(actual - expected) > float(record["tolerance"]):
				drifted.append("%s: recorded %+.1f%%, now %+.1f%% — the finding has changed, "
					% [point["name"], expected * 100.0, actual * 100.0]
					+ "re-investigate and update KNOWN_MISSES")
			continue

		if not point["within_bound"]:
			busted.append(line)

	# A suite that silently validated nothing would pass every assertion below it. Say the
	# count out loud and fail on zero: "no data" and "all good" must never look the same.
	# This is test_validation.gd's rule, and it matters more here, because this dataset lives
	# in its own file and an empty one parses perfectly.
	results.append(TestResult.new(
		"the project carries held-out whole-aircraft builds at all",
		count > 0,
		"%d build(s) in %s" % [count, BuildValidation.DATASET_PATH]
	))

	# An entry naming a part the catalog does not have is a data error, not a point to drop
	# quietly — dropping it would shrink the dataset toward zero one typo at a time.
	results.append(TestResult.new(
		"every entry resolves to parts that exist in the catalog",
		unresolved.is_empty(),
		"; ".join(unresolved) if not unresolved.is_empty() else "all entries resolve"
	))

	results.append(TestResult.new(
		"every held-out build is predicted within its stated bound, or is a recorded finding",
		busted.is_empty(),
		" | ".join(lines) if busted.is_empty() else "BUSTED: " + " | ".join(busted)
	))

	# The recorded findings are held to their recorded values. Without this the list above would
	# be a mute button: anything named in it could drift to any error at all, in either
	# direction, and nothing would say so.
	results.append(TestResult.new(
		"every recorded miss still misses by the amount it was recorded at",
		drifted.is_empty(),
		"; ".join(drifted) if not drifted.is_empty()
			else ("%d recorded finding(s), all unchanged" % seen_misses.size() if seen_misses.size() > 0
				else "no recorded findings")
	))

	# A KNOWN_MISSES key naming a build that is no longer in the dataset is an excuse outliving
	# the thing it excused. Left unchecked it would sit there forgiving a build_id that could
	# later be reused by an entirely different aircraft.
	var stale: PackedStringArray = []
	for build_id in KNOWN_MISSES:
		if not seen_misses.has(build_id):
			stale.append(String(build_id))
	results.append(TestResult.new(
		"no recorded miss names a build the dataset no longer contains",
		stale.is_empty(),
		"; ".join(stale) if not stale.is_empty() else "every recorded miss is a live entry"
	))

	return results


## The spread and the bias are different facts and only one of them is fixable. A dataset
## scattered either side of zero says the mass model is right on average and noisy about
## individual aircraft; a dataset all of one sign says a constant in Build is wrong by a fixed
## amount, and names ELECTRONICS_MASS_G as the first place to look. Averaging the magnitudes
## would destroy exactly the distinction worth having, so the signed mean is printed as its own
## line whether or not anything failed.
##
## SHARING A SIGN IS NOT ENOUGH TO CALL IT A BIAS, and getting this wrong sends the reader at
## the wrong constant with the test's own authority behind it. A constant error in the mass sum
## lands on every aircraft ALIKE: it moves each prediction by roughly the same number of grams,
## so the points must agree in MAGNITUDE, not merely in direction. Two points at -0.6% and
## -10.4% share a sign and are not evidence of a bias — a constant big enough to explain the
## second would throw the first out by the same 50 g in the opposite direction. That is one
## outlier next to one aircraft the model gets right, and it is a claim about a spec sheet
## rather than a claim about Build. So a point close enough to zero is recorded as ON THE
## NUMBER and casts no vote, and the remaining points have to cluster before the word "bias"
## is used at all.
const ON_THE_NUMBER := 0.25   ## of the bound — nearer than this to zero is a hit, not a direction
const CLUSTERED := 3.0        ## worst error over best; wider than this is an outlier, not a bias

static func _test_the_error_is_reported_with_its_sign(catalog: PartsCatalog) -> Array:
	var all_points := BuildValidation.evaluate_all(catalog)

	# Bias is a claim about a CONSTANT in Build, so it is measured over the builds that could
	# be evidence about one. A recorded miss is, by the standard KNOWN_MISSES sets, a fact about
	# a spec sheet — and averaging it in produces a number that is not the bias of anything: two
	# points at -0.6% and -10.4% average to -5.5%, which busts the bound while describing no
	# aircraft and implicating no constant. That was this check's own diagnosis in prose ("one
	# build off the number and one is not a trend") while it asserted on the raw mean anyway,
	# and the disagreement between the sentence and the assertion was the defect.
	var points: Array = []
	var excluded: PackedStringArray = []
	for point in all_points:
		if point.is_empty():
			continue
		if KNOWN_MISSES.has(String(point["build_id"])):
			excluded.append("%s %+.1f%%" % [point["build_id"], float(point["error_fraction"]) * 100.0])
			continue
		points.append(point)

	var mean := BuildValidation.signed_mean_error(points)
	# Reported whichever way it goes, so excluding a point can never quietly improve the number
	# a reader sees.
	var mean_all := BuildValidation.signed_mean_error(all_points)

	var negligible := BuildValidation.DRY_MASS_BOUND * ON_THE_NUMBER
	var same_sign := true
	var first_sign := 0.0
	var smallest := INF
	var largest := 0.0
	var voting := 0
	for point in points:
		if point.is_empty():
			continue
		var error := float(point["error_fraction"])
		# A prediction that already lands on the reported mass tells you nothing about which way
		# a constant would have to move, so it must not be counted as agreeing with anything.
		if absf(error) < negligible:
			continue
		voting += 1
		smallest = minf(smallest, absf(error))
		largest = maxf(largest, absf(error))
		var direction := signf(error)
		if first_sign == 0.0:
			first_sign = direction
		elif direction != first_sign:
			same_sign = false

	# "no points" must not render as a diagnosis. A zero mean over an empty dataset is not the
	# model being unbiased, and the sentence has to say so or it reads as a clean bill of health.
	var reading := "no builds to average"
	if points.size() > 0 and voting == 0:
		reading = "every build lands on its reported mass"
	elif voting == 1:
		reading = "one build off the number and one is not a trend — a spec sheet, not a constant"
	elif first_sign != 0.0:
		if not same_sign:
			reading = "scatter either side of zero"
		elif largest > smallest * CLUSTERED:
			# Same sign, wildly different magnitudes: an outlier wearing a bias's clothes.
			reading = "same sign but %.0fx apart (%.1f%% to %.1f%%) — an outlier, not a constant" % [
				largest / smallest, smallest * 100.0, largest * 100.0]
		else:
			reading = "a consistent OVER-prediction — look at ELECTRONICS_MASS_G" if first_sign > 0.0 \
				else "a consistent UNDER-prediction — look at ELECTRONICS_MASS_G"

	var detail := "signed mean %+.1f%%, %s" % [mean * 100.0, reading]
	if not excluded.is_empty():
		detail += " (excluding recorded miss %s; all-in mean %+.1f%%)" % [
			" ".join(excluded), mean_all * 100.0]

	return [TestResult.new(
		"the signed mean error is inside the bound, and its sign is reported",
		absf(mean) <= BuildValidation.DRY_MASS_BOUND,
		detail
	)]


# ---------------------------------------------------------------------------
# ...and the claim is not quietly circular
# ---------------------------------------------------------------------------

## The one way this exercise could be worthless: an entry that is the CALIBRATION point
## wearing a different hat. The reference build's parts were chosen so that 496 g came out, so
## an entry naming them would report a fraction of a percent for ever and prove nothing.
## Checked structurally rather than trusted, because it is exactly what a careless copy-paste
## would introduce.
static func _test_the_data_is_genuinely_held_out() -> Array:
	var results: Array = []
	var circular: PackedStringArray = []
	var unsourced: PackedStringArray = []

	for entry in BuildValidation.load_dataset():
		var id := String(entry.get("build_id", "?"))
		if String(entry.get("frame_id", "")) == ReferenceBuild.FRAME_ID \
				and String(entry.get("motor_id", "")) == ReferenceBuild.MOTOR_ID \
				and String(entry.get("propeller_id", "")) == ReferenceBuild.PROPELLER_ID:
			circular.append("%s: is the reference build, which is the calibration point" % id)
		# No citation, no number. This is the rule that keeps invented data out, and it is the
		# same length test motors.json's validation points are held to.
		if String(entry.get("source", "")).strip_edges().length() < 20:
			unsourced.append("%s: has no usable source string" % id)

	results.append(TestResult.new(
		"no validation build is the reference build in disguise",
		circular.is_empty(),
		"; ".join(circular) if not circular.is_empty() else
			"every entry differs from the calibration build in at least one core part"
	))
	results.append(TestResult.new(
		"every validation build cites where its reported mass was read from",
		unsourced.is_empty(),
		"; ".join(unsourced) if not unsourced.is_empty() else "every entry carries a citation"
	))
	results.append(TestResult.new(
		"the dataset states what belongs in it and what does not",
		BuildValidation.schema().length() > 200
			and BuildValidation.schema().contains("reference build"),
		"%d characters of schema prose" % BuildValidation.schema().length()
	))

	return results


## The pack is a stand-in, and BuildValidation's header claims it cancels out of the reported
## quantity. That is a claim about arithmetic, so it is checked rather than asserted: assemble
## the same aircraft on a 320 g Li-ion instead of the 205 g LiPo and the dry mass must not
## move. If it ever does, every number in this file is measuring the stand-in.
static func _test_the_pack_cancels(catalog: PartsCatalog) -> Array:
	var frame_id := "frame_5in_race"
	var with_lipo := Build.from_ids(catalog, frame_id, "motor_2207_1750kv", "prop_5x45x3",
		BuildValidation.PACK_ID)
	var with_liion := Build.from_ids(catalog, frame_id, "motor_2207_1750kv", "prop_5x45x3",
		"battery_4s_3000_liion")

	var a := BuildValidation.predicted_dry_mass_g(with_lipo)
	var b := BuildValidation.predicted_dry_mass_g(with_liion)

	return [TestResult.new(
		"the stand-in pack cancels out of the validated quantity",
		absf(a - b) < 1e-6 and absf(with_lipo.all_up_weight_g() - with_liion.all_up_weight_g()) > 100.0,
		"dry %.3f g either way, while all-up differs by %.0f g" % [
			a, absf(with_lipo.all_up_weight_g() - with_liion.all_up_weight_g())]
	)]


## An entry's `components` must actually reach the aircraft, and a component it names that does
## not exist must sink the entry rather than weigh nothing.
##
## THIS IS THE TEST THAT WOULD HAVE CAUGHT THE ORIGINAL DEFECT. Every entry in this dataset names
## a DJI O4 Air Unit Pro in its `source`, and for as long as BuildValidation.evaluate() dropped
## the seventh argument to Build.from_ids they were all silently modelled on an 8 g analog camera
## and a 6 g 400 mW transmitter — 17 g of wrong input on every point the dataset had ever
## produced, with every assertion above staying green throughout. Nothing here reads the shipped
## entries: it builds its own two-entry dataset so the check keeps its teeth if the real file
## changes, and it asserts on the DIFFERENCE between two predictions, which is a fact about the
## pass-through rather than about any aircraft's mass.
##
## FAILS IF: the `components` argument is dropped again (both predictions become the default
## build's and the difference goes to zero), or if a misspelt component id is fitted as a
## massless ghost instead of failing the entry.
static func _test_the_entry_chooses_its_components(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var base := {
		"build_id": "fixture", "name": "fixture",
		"frame_id": "frame_5in_race", "motor_id": "motor_2207_1750kv",
		"propeller_id": "prop_5x45x3", "reported_dry_mass_g": 400.0,
		"source": "a fixture, not a real aircraft — asserts on a difference, never on a mass",
	}
	var defaulted := base.duplicate()
	var named := base.duplicate()
	named["components"] = {"camera": "cam_dji_o4_pro"}

	var a := BuildValidation.evaluate(catalog, defaulted)
	var b := BuildValidation.evaluate(catalog, named)

	# Predicted from the catalog rather than read off the run: swapping one component changes the
	# aircraft by the difference of the two parts' own masses, and by nothing else.
	var expected := float(catalog.get_part("cam_dji_o4_pro")["mass_g"]) \
		- float(catalog.get_part(String(Build.DEFAULT_COMPONENT_IDS["camera"]))["mass_g"])
	var moved := float(b["predicted_dry_mass_g"]) - float(a["predicted_dry_mass_g"])

	results.append(TestResult.new(
		"an entry's named component reaches the aircraft, by exactly its mass difference",
		not a.is_empty() and not b.is_empty() and absf(moved - expected) < 1e-6 and expected > 1.0,
		"naming cam_dji_o4_pro moved the prediction %+.3f g against a predicted %+.3f g" % [
			moved, expected]
	))

	var typo := base.duplicate()
	typo["components"] = {"camera": "cam_dji_o4_prro"}
	results.append(TestResult.new(
		"and a component id the catalog does not have fails the entry rather than weighing zero",
		BuildValidation.evaluate(catalog, typo).is_empty(),
		"a misspelt component id yields no point, so it is reported as unresolved"
	))

	var unfitted := base.duplicate()
	unfitted["components"] = {"camera": ""}
	var c := BuildValidation.evaluate(catalog, unfitted)
	var default_camera := float(catalog.get_part(
		String(Build.DEFAULT_COMPONENT_IDS["camera"]))["mass_g"])
	results.append(TestResult.new(
		"while an empty string is 'not fitted' said deliberately, and costs the camera's own mass",
		not c.is_empty()
			and absf((float(a["predicted_dry_mass_g"]) - float(c["predicted_dry_mass_g"]))
				- default_camera) < 1e-6,
		"omitting the camera took off %.3f g against the part's own %.3f g" % [
			float(a["predicted_dry_mass_g"]) - float(c["predicted_dry_mass_g"]), default_camera]
	))

	return results


# ---------------------------------------------------------------------------
# The check has teeth
# ---------------------------------------------------------------------------

## Proof that the bound rejects something. Every other assertion is a pass or a fail ABOUT THE
## MODEL, and neither kind can tell a working check from one wired to `true`. So: take the real
## dataset, break the MODEL rather than the data — add 60 g to every frame in a private copy of
## the catalog, which is roughly the size of a wrong electronics budget — and confirm the
## machinery says no.
##
## The model side rather than the reported side deliberately. Halving a reported mass proves the
## subtraction works; moving a mass the model reads proves the bound would actually catch Build
## being wrong, which is the only thing this file exists to catch.
##
## Scoped to the points that pass HONESTLY, and that scoping is the whole subtlety. A point that
## already busts the bound says nothing about whether the check discriminates — and worse, a
## build that misses LOW by 10% is moved TOWARDS zero by 60 g of extra frame, so demanding that
## every tampered point fail would make this test fail whenever the model is wrong in the
## direction it is currently wrong in. That would couple "does the check work" to "does the model
## pass", which is exactly the confusion this test exists to break.
static func _test_the_check_can_actually_fail() -> Array:
	var honest := PartsCatalog.load_default()
	var dataset := BuildValidation.load_dataset()
	if dataset.is_empty():
		return [TestResult.new("the tamper check has data to work with", false,
			"the validation dataset is empty, so nothing can be perturbed")]

	var honest_points := BuildValidation.evaluate_all(honest, dataset)

	# A SEPARATE catalog instance, freshly parsed, so the mutation cannot leak into any other
	# suite through a shared dictionary.
	var tampered := PartsCatalog.load_default()
	for frame in tampered.list_category("frame"):
		frame["mass_g"] = float(frame["mass_g"]) + 60.0
	var tampered_points := BuildValidation.evaluate_all(tampered, dataset)

	var checked := 0
	var caught := 0
	for i in honest_points.size():
		if honest_points[i].is_empty() or tampered_points[i].is_empty():
			continue
		if not bool(honest_points[i]["within_bound"]):
			continue
		checked += 1
		if not bool(tampered_points[i]["within_bound"]):
			caught += 1

	return [TestResult.new(
		"a build the bound accepts is rejected once the mass model is made 60 g heavy",
		checked > 0 and caught == checked,
		"%d of %d honestly-passing build(s) rejected after tampering (%+.1f%% -> %+.1f%% mean)" % [
			caught, checked,
			BuildValidation.signed_mean_error(honest_points) * 100.0,
			BuildValidation.signed_mean_error(tampered_points) * 100.0]
	)]
