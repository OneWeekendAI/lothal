class_name ThrustValidation
extends RefCounted
## Predicted versus measured thrust at a HELD-OUT point — the thing that makes the thrust
## stand worth trusting (labs-and-sim.md §2.1: "A bench that will not quote its own error
## bar is decoration").
##
## The problem this solves: k_t is FITTED from each motor's `thrust_test` row, so checking
## the bench against that same row is a test that cannot fail. It would report a fraction of
## a percent for ever and mean nothing. So each motor may carry `validation` entries, which
## are independently-measured points on a DIFFERENT prop or at a DIFFERENT voltage, and this
## class reports how far the model misses them by.
##
## WHAT IS ACTUALLY UNDER TEST, stated precisely, because a validation number that does not
## say what it validates is worth as little as no number at all:
##
##   PropellerModel.scale_k_t_to_prop — moving a fitted k_t from the prop it was measured on
##   to another prop. Its D^4 term is the exact dimensional law; its blade-count exponent
##   (0.8) and pitch exponent (0.5) are documented rules of thumb. Those two rules of thumb
##   are what the error bar is measuring.
##
## The prediction deliberately uses the SAME convention the fit uses — rpm = KV x voltage at
## full throttle, with no current cap and no sag — so that the two sides of the comparison
## differ in exactly one thing, the prop. Applying the current cap here would fold a second
## modelling assumption into a number meant to isolate one mechanism, and a disagreement
## would no longer say which half was wrong.
##
## A consequence worth naming: because the same nameplate-KV convention is used on both
## sides, the fact that a real motor never reaches KV x volts under load largely cancels.
## That is not the model getting away with something — it is why held-out points at the same
## voltage as the fit are the honest ones to quote.

## Error bounds, in fraction of the measured value. FIXED IN ADVANCE of running them against
## the catalog, and split in two because the two tiers exercise different amounts of the
## model:
##
##   SAME_DIAMETER — the held-out prop has the fit prop's diameter, so only the pitch and
##   blade-count interpolation is under test. Ten percent is the conventional engineering
##   accuracy quoted for static thrust prediction, and there is no reason to claim less.
##
##   CROSS_DIAMETER — the held-out prop is a different diameter, so the D^4 extrapolation
##   runs as well, and it compounds with both rules of thumb rather than replacing them.
##   Twenty percent is the honest allowance for that compounding.
##
## If a point busts its tier, the answer is to report it, not to widen the tier. A bound
## moved to fit the data it is measuring is not a bound.
const SAME_DIAMETER_BOUND := 0.10
const CROSS_DIAMETER_BOUND := 0.20

const GRAVITY_MPS2 := 9.81
const INCH_M := 0.0254


## Every validation point for one motor, each evaluated. Empty for a motor that carries no
## `validation` block — which the bench must render as "not validated" rather than as a
## silent pass, because an empty result and a good result are opposite things.
##
## Each entry: prop_id, prop_name, voltage_v, measured_thrust_g, predicted_thrust_g,
## error_fraction (signed; positive means the model over-predicts), cross_diameter,
## bound, within_bound, source.
static func evaluate_motor(catalog: PartsCatalog, motor: Dictionary) -> Array:
	var out: Array = []

	var test: Dictionary = motor.get("thrust_test", {})
	var fit_prop: Dictionary = catalog.get_part(String(test.get("prop_id", "")))
	if fit_prop.is_empty():
		return out

	var kv: float = float(motor["specs"]["kv"])
	var fit_voltage: float = float(test.get("voltage_v", 0.0))
	var fit_rpm := kv * fit_voltage
	if fit_rpm <= 0.0:
		return out

	# The same two lines Build._recompute uses to fit, so the bench cannot validate a
	# coefficient that differs from the one the physics actually flies on.
	var k_t_at_fit_prop := PropellerModel.fit_k_t(float(motor["specs"]["max_thrust_g"]), fit_rpm)
	var fit_geometry := geometry_of(fit_prop)

	for point in motor.get("validation", []):
		var prop: Dictionary = catalog.get_part(String(point.get("prop_id", "")))
		if prop.is_empty():
			continue

		var geometry := geometry_of(prop)
		var k_t := PropellerModel.scale_k_t_to_prop(
			k_t_at_fit_prop, fit_geometry.diameter_m, fit_geometry.pitch_m, fit_geometry.blades,
			geometry.diameter_m, geometry.pitch_m, geometry.blades)
		var voltage_v: float = float(point.get("voltage_v", 0.0))
		var predicted_n := PropellerModel.thrust_n(k_t, kv * voltage_v)
		var predicted_g := predicted_n / GRAVITY_MPS2 * 1000.0

		var measured_g: float = float(point.get("measured_thrust_g", 0.0))
		if measured_g <= 0.0:
			continue

		var cross_diameter: bool = absf(geometry.diameter_m - fit_geometry.diameter_m) > 1e-6
		var bound := CROSS_DIAMETER_BOUND if cross_diameter else SAME_DIAMETER_BOUND
		var error_fraction := (predicted_g - measured_g) / measured_g

		out.append({
			"prop_id": prop["part_id"],
			"prop_name": prop.get("name", prop["part_id"]),
			"voltage_v": voltage_v,
			"measured_thrust_g": measured_g,
			"predicted_thrust_g": predicted_g,
			"error_fraction": error_fraction,
			"cross_diameter": cross_diameter,
			"bound": bound,
			"within_bound": absf(error_fraction) <= bound,
			"source": String(point.get("source", "")),
		})

	return out


## Prop geometry in SI. Mirrors Build._prop_geometry rather than calling it, because a
## validation point is evaluated against a motor and a prop with no frame and no pack — there
## is no Build to ask, and inventing one to reach a private helper would be the tail wagging.
static func geometry_of(prop: Dictionary) -> Dictionary:
	return {
		"diameter_m": float(prop["specs"]["diameter_inches"]) * INCH_M,
		"pitch_m": float(prop["specs"]["pitch_inches"]) * INCH_M,
		"blades": float(prop["specs"]["blades"]),
	}


## One line for the bench, or the honest absence of one. Never invents a number: a motor with
## no validation data says so, in the same place a validated motor states its error.
static func summary_for(catalog: PartsCatalog, motor: Dictionary) -> String:
	var points := evaluate_motor(catalog, motor)
	if points.is_empty():
		return "not validated"

	var lines: PackedStringArray = []
	for point in points:
		lines.append("%s @ %.1f V: predicted %.0f g vs measured %.0f g (%+.1f%%)" % [
			point["prop_name"], point["voltage_v"],
			point["predicted_thrust_g"], point["measured_thrust_g"],
			point["error_fraction"] * 100.0])
	return "\n".join(lines)
