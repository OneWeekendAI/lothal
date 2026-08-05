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
## the 43 g of loose electronics that LTHL-11 will eventually unbundle: a VTX, a camera, a
## receiver, an antenna, straps, screws and wiring, standing as one budgeted lump that nobody
## has ever weighed. See BuildValidation's header for why the quantity is DRY mass and why
## hover throttle is absent.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_every_build_is_within_its_bound(catalog))
	results.append_array(_test_the_error_is_reported_with_its_sign(catalog))
	results.append_array(_test_the_data_is_genuinely_held_out())
	results.append_array(_test_the_pack_cancels(catalog))
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
		"every held-out build is predicted within its stated bound",
		busted.is_empty(),
		" | ".join(lines) if busted.is_empty() else "BUSTED: " + " | ".join(busted)
	))

	return results


## The spread and the bias are different facts and only one of them is fixable. A dataset
## scattered either side of zero says the mass model is right on average and noisy about
## individual aircraft; a dataset all of one sign says a constant in Build is wrong by a fixed
## amount, and names ELECTRONICS_MASS_G as the first place to look. Averaging the magnitudes
## would destroy exactly the distinction worth having, so the signed mean is printed as its own
## line whether or not anything failed.
static func _test_the_error_is_reported_with_its_sign(catalog: PartsCatalog) -> Array:
	var points := BuildValidation.evaluate_all(catalog)
	var mean := BuildValidation.signed_mean_error(points)

	var same_sign := true
	var first_sign := 0.0
	for point in points:
		if point.is_empty():
			continue
		var direction := signf(float(point["error_fraction"]))
		if first_sign == 0.0:
			first_sign = direction
		elif direction != first_sign:
			same_sign = false

	# "no points" must not render as a diagnosis. A zero mean over an empty dataset is not the
	# model being unbiased, and the sentence has to say so or it reads as a clean bill of health.
	var reading := "no builds to average"
	if first_sign != 0.0:
		reading = "scatter either side of zero" if not same_sign else \
			("a consistent OVER-prediction — look at ELECTRONICS_MASS_G" if first_sign > 0.0
				else "a consistent UNDER-prediction — look at ELECTRONICS_MASS_G")

	return [TestResult.new(
		"the signed mean error is inside the bound, and its sign is reported",
		absf(mean) <= BuildValidation.DRY_MASS_BOUND,
		"signed mean %+.1f%%, %s" % [mean * 100.0, reading]
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


# ---------------------------------------------------------------------------
# The check has teeth
# ---------------------------------------------------------------------------

## Proof that the bound rejects something. Every assertion above is a pass, and a suite made
## entirely of passes cannot tell a working check from one wired to `true`. So: take the real
## dataset, break the MODEL rather than the data — add 60 g to every frame in a private copy
## of the catalog, which is roughly what a wrong electronics budget would look like — and
## confirm the machinery says no.
##
## The model side rather than the reported side deliberately. Halving a reported mass proves
## the subtraction works; moving a mass the model reads proves the bound would actually catch
## Build being wrong, which is the only thing this file exists to catch.
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

	var all_honest_pass := true
	var all_tampered_fail := true
	for i in honest_points.size():
		if honest_points[i].is_empty() or tampered_points[i].is_empty():
			continue
		all_honest_pass = all_honest_pass and bool(honest_points[i]["within_bound"])
		all_tampered_fail = all_tampered_fail and not bool(tampered_points[i]["within_bound"])

	return [TestResult.new(
		"the bound rejects a mass model that is 60 g heavy",
		all_honest_pass and all_tampered_fail,
		"real catalog %+.1f%% mean, same builds with 60 g of extra frame %+.1f%% mean" % [
			BuildValidation.signed_mean_error(honest_points) * 100.0,
			BuildValidation.signed_mean_error(tampered_points) * 100.0]
	)]
