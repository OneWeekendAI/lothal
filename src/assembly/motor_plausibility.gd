class_name MotorPlausibility
extends RefCounted
## What a build says about a motor whose numbers came from a builder rather than from the catalog.
##
## FramePlausibility next door is the model for all of this, and the same two rules hold: nothing
## here blocks anything (labs-and-sim.md §2 warns and never blocks — the refusals are all in
## CustomMotors, where the alternative is silence), and every bound was FIXED BEFORE it was run
## against any custom data, in thrust_validation.gd's spirit. A bound moved to fit the data it is
## measuring is not a bound.
##
## What is different here, and what makes this file worth more than its length, is that a frame's
## surprising numbers are surprising in an obvious way — a 900 mm arm looks like a 900 mm arm on
## screen — whereas a motor's are not. A thrust figure with a digit wrong produces an aircraft
## that looks entirely normal and flies on thrust nobody ever measured. There is nothing to see.
## So the check has to be arithmetic, and it has to be arithmetic against something real.
##
## ===========================================================================
## THE FINDING THIS FILE IS BUILT ON
## ===========================================================================
##
## k_t = thrust_N / omega^2 is a PURE PROPELLER COEFFICIENT. There is no motor term in it. Two
## motors tested on the same propeller should therefore fit the same k_t, and across the shipped
## catalog they do not — five motors share prop_5x43x3 as their test prop and their fitted k_t
## spans 1.79x:
##
##     motor_2207_1750kv            1850 g @ 1750KV/22.2V   k_t = 1.096e-06
##     motor_2207_1960kv            1450 g @ 1960KV/14.8V   k_t = 1.542e-06
##     motor_2207_2400kv            1700 g @ 2400KV/14.8V   k_t = 1.205e-06
##     motor_f60proii_2207_1750kv   1785 g @ 1840KV/23.4V   k_t = 8.606e-07
##     motor_speedx_gr2306_2450kv   1519 g @ 2430KV/15.5V   k_t = 9.628e-07
##
## Scaled onto one prop through PropellerModel.scale_k_t_to_prop, all fifteen catalog motors span
## 3.32x. Those numbers are not noise in the model — the model is one division. They are fifteen
## manufacturers' thrust tables disagreeing with each other, measured on different stands, at
## different temperatures, with different ideas of what "max" means. That disagreement IS the
## honest error bar on max_thrust_g as a published spec, and it is the only error bar available
## without a thrust stand in the room.
##
## So this file uses it as one: a custom motor's implied k_t is compared against the band the
## CATALOG shows for the same test prop, and it warns when it falls outside. That catches the
## real failure mode — a digit typo, or grams confused with newtons — with physics rather than
## with a numeric range somebody invented.
##
## ===========================================================================
## THE BOUNDS, AND WHY EACH IS WHERE IT IS
## ===========================================================================
##
## All three are the same shape: take the span the shipped catalog actually occupies, and widen
## it by one factor. Fixed before any custom motor was run against them, and derived rather than
## chosen, because the same argument sets all three.
##
## THE ARGUMENT. Each of these checks exists to catch one thing above all others: a decimal point
## in the wrong place, which is a factor of ten. So the bound must be tight enough that a 10x
## error is caught WHEREVER in the catalog's own span the true motor happens to sit. If the
## catalog spans S and the bound is a factor B outside each edge, a motor sitting at the bottom
## edge with a 10x error lands at 10/S times the top edge — so the check catches every 10x slip
## exactly when B < 10/S. For the k_t band, S = 3.32 and 10/S = 3.01.
##
## Setting B at the edge of what it must catch leaves no margin at all, and a bound that only
## just works is one catalog addition away from not working. So B is half of it, rounded down:
##
const BAND_WIDENING_FACTOR := 2.0
##
## which catches a 10x slip with 50% to spare, and still requires a motor to disagree with the
## whole catalog by more than the catalog disagrees with itself before it says a word. The same
## factor serves all three checks because the same 10x argument sets all three, and their spans
## (3.32x, 1.71x, 2.80x) are close enough that one number is honest for all of them rather than
## three numbers tuned individually — three would be three chances to have tuned one to the data.
##
## WHAT EACH BAND IS MEASURED OVER — all derived from the shipped catalog at call time, never
## hardcoded, so adding a motor to data/parts/ moves the bands rather than dating this comment:
##
##   K_T — every shipped motor's fitted k_t, scaled onto the custom motor's OWN test prop through
##   scale_k_t_to_prop. Scaled rather than compared per-prop, because most props in the catalog
##   are the test prop of exactly one motor, and a band of one point is not a band. This is also
##   what lets a custom motor tested on a prop no catalog motor uses be compared at all.
##
##   KV vs STATOR — KV and stator size are inversely related in every real product line, and the
##   catalog says how strongly: a least-squares fit of log(KV) against log(stator diameter) over
##   all fifteen motors gives an exponent of -1.97 with residuals spanning 1.71x. An exponent of
##   almost exactly -2 is not a coincidence, it is what falls out of KV being set by turns and
##   flux area, and it is a much tighter law than a catalog of fifteen hand-authored parts had any
##   obligation to produce. The fit is recomputed here rather than written down, so the LAW is the
##   claim and the -1.97 is just today's value of it. The ticket's own example lands where it
##   should: a 2807 at 4000KV is 3.16x the fitted prediction, well outside; a real 2810 at 1100KV
##   is 0.87x, well inside; and the catalog's own worst point is 1.31x.
##
##   THRUST PER STATOR VOLUME — max_thrust_g over pi*r^2*h of stator, which spans 2.80x across the
##   catalog (0.279 g/mm^3 for the 0802 whoop motor to 0.780 for the 1404 4600KV). A second,
##   independent way for a wrong thrust figure to show itself: the k_t band asks whether the
##   thrust agrees with the PROP, this asks whether it agrees with the amount of motor there is.
##
## ===========================================================================
## WHY THESE ARE CHARACTERISTIC AND NOT LIMITING
## ===========================================================================
##
## BuildWarning's rule is that LIMITING means something binds and the builder should be told
## which part — the current-limit warnings are the standard, and they compute a throttle cap from
## the parts and name the component that caps it. Nothing here binds. A motor outside the k_t band
## does not fly worse; it flies exactly as its numbers say, and the numbers may well be right —
## the catalog's own 1.79x disagreement on one prop is proof that published figures scatter this
## much without anybody having made a mistake.
##
## What these warnings actually say is "this figure disagrees with every other figure of its kind,
## and you should look at it again before you trust what it implies". That is a description of
## what the build IS, which is CHARACTERISTIC by BuildWarning's own definition, and it sits beside
## the custom-provenance warning it belongs with. Colouring a possible typo the same as a pack
## that physically will not fit would be the cinelifter mistake again — the one BuildWarning
## exists to have stopped.

const GRAVITY_MPS2 := 9.81
const INCH_M := 0.0254

## The per-cell voltages a real lithium pack is bench-tested at. A table headed "6S" means 22.2 V
## nominal; one headed "6S 25.2V" means fully charged; and the two named-product tables in this
## catalog were run at 3.9 and 3.875 V per cell, which are neither. So the check is not "near a
## multiple of 3.7" — that would flag two of the catalog's own entries — but "divides into some
## cell count at a voltage a lithium cell is actually at during a bench run".
##
## The floor is 3.2 V rather than a cell's 3.0 V cutoff because nobody publishes a thrust table on
## a flat pack. That floor is what catches the error worth catching: a builder who reads "6S" and
## types 6 gets 3.0 V per cell at 2S, and the physics would absorb it silently — a 6 V table would
## fit a k_t nearly fourteen times too large.
const CELL_VOLTAGE_MIN := 3.2
const CELL_VOLTAGE_MAX := 4.35
const MAX_CELLS := 12


## Everything this file has to say about one build, in one list, so Build.warnings() appends it
## unconditionally and has no opinion about which of these apply. Nothing at all for a catalog
## motor: every check here is a check on a number one person typed, and the shipped catalog's
## numbers have been through review.
static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not PartsCatalog.is_custom(str(build.motor.get("part_id", ""))):
		return out

	out.append(_provenance(build.motor))
	out.append_array(_test_voltage(build.motor))
	out.append_array(_thrust_coefficient(build.catalog, build.motor))
	out.append_array(_kv_for_stator(build.catalog, build.motor))
	out.append_array(_thrust_density(build.catalog, build.motor))
	return out


## That these numbers have not been through anything, and — the part that is specific to motors —
## that the thrust figure is a CLAIM. FramePlausibility says the equivalent about a frame, but a
## frame's mass is something the builder can put on a scale. Nobody has a thrust stand, so this
## one figure is taken on the manufacturer's word, and the catalog's own 1.79x spread is the
## measure of what that word is worth.
static func _provenance(motor: Dictionary) -> BuildWarning:
	var source := str(motor.get("source", "")).strip_edges()
	var test: Dictionary = motor.get("thrust_test", {})
	return BuildWarning.characteristic(&"custom_motor",
		"The %s is a motor you entered yourself (%s). Its %.0f g thrust figure is a manufacturer's claim measured on one prop at one voltage, not something Lothal has checked — every thrust, TWR and hover number on this build is exactly as good as that claim is." % [
			motor.get("name", motor.get("part_id", "?")), source,
			float(motor.get("specs", {}).get("max_thrust_g", 0.0))],
		{"part_id": str(motor.get("part_id", "")), "source": source,
			"test_prop_id": str(test.get("prop_id", "")), "test_voltage_v": float(test.get("voltage_v", 0.0))})


## A voltage that is not a pack voltage. The physics absorbs it happily — rpm is KV times volts
## and 6 is a perfectly good number — which is exactly why it needs saying out loud.
static func _test_voltage(motor: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var voltage := float(motor.get("thrust_test", {}).get("voltage_v", 0.0))
	if voltage <= 0.0 or _plausible_cell_count(voltage) > 0:
		return out

	# The pack the builder most likely meant, for the sentence. Nearest whole number of nominal
	# cells to what they typed, which is the reading if they entered a cell COUNT.
	var likely_cells := maxi(1, int(round(voltage)))
	out.append(BuildWarning.characteristic(&"implausible_test_voltage",
		"%.1f V is not a voltage a lithium pack is bench-tested at — no whole number of cells divides into it between %.1f and %.2f V each. If the table was headed \"%dS\", the voltage is %.1f V; entering %.1f would fit a thrust coefficient %.1fx wrong and nothing downstream would complain." % [
			voltage, CELL_VOLTAGE_MIN, CELL_VOLTAGE_MAX, likely_cells, likely_cells * 3.7,
			voltage, pow(likely_cells * 3.7 / voltage, 2.0)],
		{"voltage_v": voltage, "likely_cells": likely_cells}))
	return out


static func _plausible_cell_count(voltage_v: float) -> int:
	for cells in range(1, MAX_CELLS + 1):
		var per_cell := voltage_v / cells
		if per_cell >= CELL_VOLTAGE_MIN and per_cell <= CELL_VOLTAGE_MAX:
			return cells
	return 0


# ---------------------------------------------------------------------------
# The k_t cross-check
# ---------------------------------------------------------------------------

## The band the shipped catalog occupies, on one prop. Public because the test asserts the
## boundary from both sides and has to be able to ask where the boundary is — a test that
## hardcoded a gram figure would be asserting a snapshot of the band rather than the band, and
## would go stale the first time a motor was added to data/parts/.
##
## `observed_low` and `observed_high` are the catalog's real span; `low` and `high` are that span
## widened by BAND_WIDENING_FACTOR, and are what the warning fires outside of. Both are returned
## because the warning's sentence quotes the observed span — telling a builder their motor is
## outside a widened bound means nothing without saying what the real spread was.
static func k_t_band_for_prop(catalog: PartsCatalog, prop: Dictionary) -> Dictionary:
	var to_geometry := ThrustValidation.geometry_of(prop)
	# Shipped motors only, and the implied k_t values are gathered here (each already computed
	# through the Rust PropellerModel); the min/max/widen arithmetic lives in Rust.
	var implied := PackedFloat64Array()
	for motor in catalog.list_category("motor"):
		# A custom motor in the band would let a builder's own typo widen the very band that is
		# meant to catch it, and two custom motors entered from the same mistaken page would
		# vouch for each other.
		if PartsCatalog.is_custom(str((motor as Dictionary).get("part_id", ""))):
			continue
		var k_t := implied_k_t_on(catalog, motor as Dictionary, to_geometry)
		if k_t > 0.0:
			implied.append(k_t)

	var band: PackedFloat64Array = Plausibility.band_around(implied, BAND_WIDENING_FACTOR)
	return {
		"low": band[0],
		"high": band[1],
		"observed_low": band[2],
		"observed_high": band[3],
		"count": int(band[4]),
	}


## One motor's fitted k_t, moved onto the geometry asked for. The same two lines Build._recompute
## fits with, so the band cannot be drawn around a coefficient that differs from the one the
## physics actually flies on. Zero for a motor whose test prop does not resolve — which cannot
## happen for a shipped motor (tests/test_parts_system.gd guards it) and cannot happen for a
## custom one (CustomMotors refuses it), and is handled anyway because both of those are
## statements about today.
static func implied_k_t_on(catalog: PartsCatalog, motor: Dictionary, to_geometry: Dictionary) -> float:
	var test: Dictionary = motor.get("thrust_test", {})
	var fit_prop: Dictionary = catalog.get_part(str(test.get("prop_id", "")))
	if fit_prop.is_empty():
		return 0.0
	var fit_rpm := float(motor.get("specs", {}).get("kv", 0.0)) * float(test.get("voltage_v", 0.0))
	if fit_rpm <= 0.0:
		return 0.0
	var k_t_at_fit := PropellerModel.fit_k_t(float(motor.get("specs", {}).get("max_thrust_g", 0.0)), fit_rpm)
	var fit_geom := ThrustValidation.geometry_of(fit_prop)
	return PropellerModel.scale_k_t_to_prop(
		k_t_at_fit, fit_geom.diameter_m, fit_geom.pitch_m, fit_geom.blades,
		to_geometry.diameter_m, to_geometry.pitch_m, to_geometry.blades)


static func _thrust_coefficient(catalog: PartsCatalog, motor: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var test_prop: Dictionary = catalog.get_part(str(motor.get("thrust_test", {}).get("prop_id", "")))
	if test_prop.is_empty():
		return out

	var geometry := ThrustValidation.geometry_of(test_prop)
	var k_t := implied_k_t_on(catalog, motor, geometry)
	var band := k_t_band_for_prop(catalog, test_prop)
	if k_t <= 0.0 or int(band["count"]) == 0:
		return out
	if k_t >= float(band["low"]) and k_t <= float(band["high"]):
		return out

	var high := k_t > float(band["high"])
	var edge: float = float(band["observed_high"]) if high else float(band["observed_low"])

	# Names all THREE figures the coefficient was fitted from, and blames none of them. k_t comes
	# out of thrust, KV and voltage together, and this check cannot tell which one is wrong — a
	# KV typed 3x high lands here as a coefficient 10x low, and a sentence ending "check the
	# thrust figure" would send that builder to the one field that was right. Pointing at the
	# wrong field is worse than pointing at three, because it gets acted on.
	out.append(BuildWarning.characteristic(&"implausible_thrust_coefficient",
		"%.0f g at %.0fKV on %.1f V implies a thrust coefficient %.1fx %s than any of the %d motors in the catalog measured on %s. k_t is a property of the PROPELLER — there is no motor term in it — so every motor tested on one prop should fit roughly the same value, and the catalog's own figures already disagree by %.1fx. Being outside that by this much usually means a digit rather than a remarkable motor, and it is fitted from all three of those numbers together: check %.0f g, %.0fKV and %.1f V against the heading of the table you read them from." % [
			float(motor["specs"]["max_thrust_g"]), float(motor["specs"]["kv"]),
			float(motor["thrust_test"]["voltage_v"]),
			(k_t / edge) if high else (edge / k_t), "higher" if high else "lower",
			int(band["count"]), test_prop.get("name", test_prop["part_id"]),
			float(band["observed_high"]) / float(band["observed_low"]),
			float(motor["specs"]["max_thrust_g"]), float(motor["specs"]["kv"]),
			float(motor["thrust_test"]["voltage_v"])],
		{"k_t": k_t, "band_low": float(band["low"]), "band_high": float(band["high"]),
			"observed_low": float(band["observed_low"]), "observed_high": float(band["observed_high"]),
			"test_prop_id": str(test_prop["part_id"])}))
	return out


# ---------------------------------------------------------------------------
# KV against stator size
# ---------------------------------------------------------------------------

## KV as a power of stator diameter, least-squares in log-log over the shipped catalog. Returned
## rather than written down so the LAW is what this file claims and the exponent is only today's
## measurement of it — see the header for what today's is, and why -2 is the number to expect.
##
## `residual_high` is how far the catalog's own worst-fitting motor sits from the line, which the
## warning quotes: a builder told their motor is off the line deserves to know the line is not
## exact for the catalog either.
static func kv_law(catalog: PartsCatalog) -> Dictionary:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for motor in catalog.list_category("motor"):
		var specs: Dictionary = (motor as Dictionary).get("specs", {})
		var diameter := float(specs.get("stator_diameter_mm", 0.0))
		var kv := float(specs.get("kv", 0.0))
		if PartsCatalog.is_custom(str((motor as Dictionary).get("part_id", ""))) or diameter <= 0.0 or kv <= 0.0:
			continue
		xs.append(log(diameter))
		ys.append(log(kv))

	# The regression itself lives in Rust (rust/src/plausibility.rs) — the same log-log fit
	# behind mass_law and thrust_density_band, one copy in the codebase.
	var fit: PackedFloat64Array = Plausibility.log_log_fit(PackedFloat64Array(xs), PackedFloat64Array(ys))
	return {"exponent": fit[0], "coefficient": fit[1], "residual_high": fit[2],
		"count": int(fit[3])}


static func _kv_for_stator(catalog: PartsCatalog, motor: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var specs: Dictionary = motor.get("specs", {})
	var diameter := float(specs.get("stator_diameter_mm", 0.0))
	var kv := float(specs.get("kv", 0.0))
	if diameter <= 0.0 or kv <= 0.0:
		return out

	var law := kv_law(catalog)
	if int(law["count"]) < 3:
		return out
	var predicted: float = float(law["coefficient"]) * pow(diameter, float(law["exponent"]))
	if predicted <= 0.0:
		return out

	var ratio := kv / predicted
	if ratio <= BAND_WIDENING_FACTOR and ratio >= 1.0 / BAND_WIDENING_FACTOR:
		return out

	out.append(BuildWarning.characteristic(&"implausible_kv_for_stator",
		"%.0fKV on a %.0f mm stator is %.1fx %s than the %.0fKV the catalog's own motors imply for that size. Across the %d shipped motors KV goes as stator diameter to the power %.2f — close to the inverse square you would expect, since KV is set by turns and flux area — and the worst-fitting real motor in the catalog is only %.2fx off that line. A stator size and a KV this far apart is usually two specs from two different motors." % [
			kv, diameter, maxf(ratio, 1.0 / ratio), "higher" if ratio > 1.0 else "lower",
			predicted, int(law["count"]), float(law["exponent"]), float(law["residual_high"])],
		{"kv": kv, "stator_diameter_mm": diameter, "predicted_kv": predicted,
			"exponent": float(law["exponent"]), "ratio": ratio}))
	return out


# ---------------------------------------------------------------------------
# Thrust against how much motor there is
# ---------------------------------------------------------------------------

## Thrust per cubic millimetre of stator, which is the second and independent way a wrong thrust
## figure shows itself: the k_t band asks whether the thrust agrees with the PROP it was measured
## on, and this asks whether it agrees with the amount of motor there is to make it.
static func thrust_density_band(catalog: PartsCatalog) -> Dictionary:
	# The band arithmetic (the same widened-spread shape as the k_t band) lives in Rust.
	var densities := PackedFloat64Array()
	for motor in catalog.list_category("motor"):
		if PartsCatalog.is_custom(str((motor as Dictionary).get("part_id", ""))):
			continue
		var density := _thrust_per_stator_volume((motor as Dictionary).get("specs", {}))
		if density > 0.0:
			densities.append(density)
	var band: PackedFloat64Array = Plausibility.band_around(densities, BAND_WIDENING_FACTOR)
	return {
		"low": band[0],
		"high": band[1],
		"observed_low": band[2], "observed_high": band[3], "count": int(band[4]),
	}


static func _thrust_per_stator_volume(specs: Dictionary) -> float:
	var radius := float(specs.get("stator_diameter_mm", 0.0)) * 0.5
	var height := float(specs.get("stator_height_mm", 0.0))
	if radius <= 0.0 or height <= 0.0:
		return 0.0
	return float(specs.get("max_thrust_g", 0.0)) / (PI * radius * radius * height)


static func _thrust_density(catalog: PartsCatalog, motor: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var density := _thrust_per_stator_volume(motor.get("specs", {}))
	var band := thrust_density_band(catalog)
	if density <= 0.0 or int(band["count"]) == 0:
		return out
	if density >= float(band["low"]) and density <= float(band["high"]):
		return out

	var high := density > float(band["high"])
	out.append(BuildWarning.characteristic(&"implausible_thrust_density",
		"%.0f g from a %.0fx%.0f stator is %.2f g per mm³ of motor, against %.2f-%.2f for every motor in the catalog. Thrust scales with how much iron and copper there is to make it, so this is a regularity rather than a law — but %s by this margin is worth a second look at the figure rather than a correction to the motor." % [
			float(motor["specs"]["max_thrust_g"]), float(motor["specs"]["stator_diameter_mm"]),
			float(motor["specs"]["stator_height_mm"]), density,
			float(band["observed_low"]), float(band["observed_high"]),
			"above it" if high else "below it"],
		{"grams_per_mm3": density, "observed_low": float(band["observed_low"]),
			"observed_high": float(band["observed_high"])}))
	return out
