class_name TestValidation
extends RefCounted
## Held-out validation: does the thrust model predict a point it was NOT fitted on?
##
## This suite is the answer to the objection that would otherwise sink the whole thrust stand.
## k_t is fitted from each motor's `thrust_test` row, so a bench checked against that same row
## reports a fraction of a percent and proves nothing — it is a test that cannot fail. Every
## assertion below is therefore against an independently-measured point on a DIFFERENT prop,
## read off a real published test table and cited row by row in motors.json.
##
## THE BOUNDS ARE FIXED IN ThrustValidation AND WERE CHOSEN BEFORE THESE NUMBERS WERE RUN.
## That ordering is the entire methodological content of this file. A bound set after seeing
## the errors is not a bound, it is a description, and it would pass for ever no matter what
## the model did. If a point busts its tier, the honest response is to report the failure and
## fix the model — not to widen the tier.
##
## What is under test is PropellerModel.scale_k_t_to_prop: its D^4 term is the exact
## dimensional law, and its blade-count (0.8) and pitch (0.5) exponents are documented rules
## of thumb. The two tiers exist because a same-diameter point exercises only the rules of
## thumb, while a cross-diameter point runs the D^4 extrapolation as well and compounds all
## three. See ThrustValidation's header for why each bound is the number it is.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_every_point_is_within_its_bound(catalog))
	results.append_array(_test_the_data_is_genuinely_held_out(catalog))
	results.append_array(_test_unvalidated_motors_say_so(catalog))
	results.append_array(_test_the_check_can_actually_fail(catalog))

	return results


# ---------------------------------------------------------------------------
# The claim
# ---------------------------------------------------------------------------

static func _test_every_point_is_within_its_bound(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lines: PackedStringArray = []
	var busted: PackedStringArray = []
	var count := 0

	for motor in catalog.list_category("motor"):
		for point in ThrustValidation.evaluate_motor(catalog, motor):
			count += 1
			var line := "%s on %s: %.0f g predicted vs %.0f g measured, %+.1f%% (bound %.0f%%)" % [
				motor["name"], point["prop_name"],
				point["predicted_thrust_g"], point["measured_thrust_g"],
				point["error_fraction"] * 100.0, point["bound"] * 100.0]
			lines.append(line)
			if not point["within_bound"]:
				busted.append(line)

	# A suite that silently validated nothing would pass every assertion below it. Say the
	# count out loud, and fail on zero: "no data" and "all good" must never look the same.
	results.append(TestResult.new(
		"the catalog carries held-out validation points at all",
		count > 0,
		"%d point(s) across the catalog" % count
	))

	results.append(TestResult.new(
		"every held-out point is predicted within its stated bound",
		busted.is_empty(),
		" | ".join(lines) if busted.is_empty() else "BUSTED: " + " | ".join(busted)
	))

	# Stated separately so a run of the suite reports the model's worst case as a number a
	# reader can judge, rather than only as a pass.
	var worst := 0.0
	var worst_line := "—"
	for motor in catalog.list_category("motor"):
		for point in ThrustValidation.evaluate_motor(catalog, motor):
			if absf(point["error_fraction"]) > worst:
				worst = absf(point["error_fraction"])
				worst_line = "%s on %s" % [motor["name"], point["prop_name"]]
	results.append(TestResult.new(
		"the worst held-out error in the catalog is inside the looser of the two bounds",
		worst <= ThrustValidation.CROSS_DIAMETER_BOUND,
		"worst is %.1f%% (%s), against a %.0f%% ceiling" % [
			worst * 100.0, worst_line, ThrustValidation.CROSS_DIAMETER_BOUND * 100.0]
	))

	return results


# ---------------------------------------------------------------------------
# ...and the claim is not quietly circular
# ---------------------------------------------------------------------------

## The one way this whole exercise could still be worthless: a "validation" point that is
## actually the fit point wearing a different hat. Checked structurally rather than trusted,
## because it is the sort of thing that would be introduced by a careless copy-paste and
## would then report a spectacular 0.1% error for ever.
static func _test_the_data_is_genuinely_held_out(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var circular: PackedStringArray = []
	var unsourced: PackedStringArray = []
	var missing_prop: PackedStringArray = []

	for motor in catalog.list_category("motor"):
		var fit_prop_id := String(motor.get("thrust_test", {}).get("prop_id", ""))
		var fit_voltage := float(motor.get("thrust_test", {}).get("voltage_v", 0.0))

		for point in motor.get("validation", []):
			var prop_id := String(point.get("prop_id", ""))
			var voltage: float = float(point.get("voltage_v", 0.0))

			if prop_id == fit_prop_id and is_equal_approx(voltage, fit_voltage):
				circular.append("%s: validates on the very prop and voltage it was fitted on" % motor["part_id"])
			if catalog.get_part(prop_id).is_empty():
				missing_prop.append("%s: validation names %s, which is not in the catalog" % [motor["part_id"], prop_id])
			# No citation, no number. This is the rule that keeps invented data out.
			if String(point.get("source", "")).strip_edges().length() < 20:
				unsourced.append("%s: validation point on %s has no usable source string" % [motor["part_id"], prop_id])

	results.append(TestResult.new(
		"no validation point is the fit point in disguise",
		circular.is_empty(),
		"; ".join(circular) if not circular.is_empty() else "every point differs from its fit in prop or voltage"
	))
	results.append(TestResult.new(
		"every validation point names a propeller that exists in the catalog",
		missing_prop.is_empty(),
		"; ".join(missing_prop) if not missing_prop.is_empty() else "all validation prop_ids resolve"
	))
	results.append(TestResult.new(
		"every validation point cites the table and row it was measured from",
		unsourced.is_empty(),
		"; ".join(unsourced) if not unsourced.is_empty() else "every point carries a source citation"
	))

	return results


# ---------------------------------------------------------------------------
# The honest absence
# ---------------------------------------------------------------------------

## Most of the catalog has no independently-measured second point, and it must say so rather
## than showing a number. This includes the reference build's own motor, deliberately: its
## thrust_test feeds the 11.7:1 and 29%-hover oracles, so re-sourcing it to obtain validation
## data would move the project's fixed points — a bad trade for a green line.
static func _test_unvalidated_motors_say_so(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var reference: Dictionary = catalog.get_part(ReferenceBuild.MOTOR_ID)
	results.append(TestResult.new(
		"a motor with no held-out data reads \"not validated\" rather than showing a number",
		ThrustValidation.summary_for(catalog, reference) == "not validated"
			and ThrustValidation.evaluate_motor(catalog, reference).is_empty(),
		"%s reports \"%s\"" % [reference["name"], ThrustValidation.summary_for(catalog, reference)]
	))

	var validated := 0
	var unvalidated := 0
	for motor in catalog.list_category("motor"):
		if ThrustValidation.evaluate_motor(catalog, motor).is_empty():
			unvalidated += 1
		else:
			validated += 1

	results.append(TestResult.new(
		"the catalog is honest about how little of it is validated",
		unvalidated > 0 and validated > 0,
		"%d of %d motors carry held-out data; the other %d say so" % [
			validated, validated + unvalidated, unvalidated]
	))

	return results


# ---------------------------------------------------------------------------
# The check has teeth
# ---------------------------------------------------------------------------

## Proof that the bound rejects something. Every assertion above is a pass, and a suite made
## entirely of passes cannot distinguish a working check from one wired to `true`. So: take a
## real validated motor, move its held-out measurement somewhere the model does not predict,
## and confirm the machinery says no.
##
## This is the same discipline the Powertrain slice used when it was written wrong on purpose
## first — a test whose failure has never been observed is a test nobody has checked.
static func _test_the_check_can_actually_fail(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var motor: Dictionary = catalog.get_part("motor_f60proii_2207_1750kv").duplicate(true)
	if motor.is_empty():
		return [TestResult.new("the tamper check has a validated motor to work with", false,
			"motor_f60proii_2207_1750kv is not in the catalog")]

	var honest := ThrustValidation.evaluate_motor(catalog, motor)

	# Halve the measured thrust. Nothing about the model changed; the point it is being asked
	# to hit did. A bound that still passed here would not be measuring anything.
	motor["validation"][0]["measured_thrust_g"] = float(motor["validation"][0]["measured_thrust_g"]) * 0.5
	var tampered := ThrustValidation.evaluate_motor(catalog, motor)

	results.append(TestResult.new(
		"the bound rejects a measurement the model does not predict",
		honest[0]["within_bound"] and not tampered[0]["within_bound"],
		"real point %+.1f%% (within bound), same point halved %+.1f%% (rejected)" % [
			honest[0]["error_fraction"] * 100.0, tampered[0]["error_fraction"] * 100.0]
	))

	return results
