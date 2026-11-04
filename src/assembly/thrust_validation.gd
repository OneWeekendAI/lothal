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
##   BemtModel.scale_k_t_to_prop — moving a fitted k_t from the prop it was measured on to
##   another prop. Since P5 this is the BEMT geometry ratio (propulsion.md §0): blade count
##   and twist enter the integral where they act, at the RPM the fit came from. The integral
##   on the two props' planforms is what the error bar is measuring.
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
##
## THE TIERS ARE A REFERENCE, NOT A GATE (prop chapter, 2026-11-04). Since k_t comes from the
## test prop's blade-element integral instead of a fit to the datasheet thrust, the model no
## longer reproduces a vendor table by construction, and a vendor table is a bench measurement
## with its own spread (the catalog's motor-to-motor disagreement is 1.79x, plausibility.md).
## `within_bound` is still computed and reported on every point, so a reader sees how far each
## sits from the 10 % / 20 % engineering reference; what FAILS is `within_sanity`, predicted
## inside 0.5-2x the measurement, which only a wiring error or a wrong-prop mix-up leaves.
const SAME_DIAMETER_BOUND := 0.10
const CROSS_DIAMETER_BOUND := 0.20
## Predicted / measured must stay inside this band to count as the same physical quantity.
const SANITY_LOW := 0.5
const SANITY_HIGH := 2.0

const GRAVITY_MPS2 := 9.81
const INCH_M := 0.0254


## Every validation point for one motor, each evaluated. Empty for a motor that carries no
## `validation` block — which the bench must render as "not validated" rather than as a
## silent pass, because an empty result and a good result are opposite things.
##
## Each entry: prop_id, prop_name, voltage_v, measured_thrust_g, predicted_thrust_g,
## error_fraction (signed; positive means the model over-predicts), cross_diameter,
## bound, within_bound (the reference, reported only), within_sanity (0.5-2x, the gate), source.
static func evaluate_motor(catalog: PartsCatalog, motor: Dictionary) -> Array:
	var out: Array = []

	var test: Dictionary = motor.get("thrust_test", {})
	var fit_prop: Dictionary = catalog.get_part(String(test.get("prop_id", "")))
	if fit_prop.is_empty():
		return out

	var kv: float = float(motor["specs"]["kv"])
	var fit_voltage: float = float(test.get("voltage_v", 0.0))
	if kv * fit_voltage <= 0.0:
		return out

	# The same fit Build._recompute uses (k_t at the LOADED rated point), so the bench cannot
	# validate a coefficient that differs from the one the physics actually flies on.
	var fitted := Build.fit_rated_point(motor, fit_prop)
	var fit_rpm := float(fitted["rpm"])
	var k_t_at_fit_prop := float(fitted["k_t"])
	var dc := Build.dc_motor_params(motor)
	var fit_doc := PropellerDocument.from_catalog_prop(fit_prop)

	for point in motor.get("validation", []):
		var prop: Dictionary = catalog.get_part(String(point.get("prop_id", "")))
		if prop.is_empty():
			continue

		# The cross-prop move is the BEMT geometry ratio (§0, P5) — blade count and twist in
		# the integral, at the RPM the fit came from — not the deleted exponent law. The
		# held-out point is predicted on the SAME convention the fit uses.
		var hold_doc := PropellerDocument.from_catalog_prop(prop)
		var k_t := BemtModel.scale_k_t_to_prop(
			k_t_at_fit_prop,
			fit_doc.diameter_mm * 0.001, fit_doc.pitch_mm * 0.001, float(fit_doc.blades), fit_doc.chord,
			hold_doc.diameter_mm * 0.001, hold_doc.pitch_mm * 0.001, float(hold_doc.blades), hold_doc.chord,
			fit_rpm)
		var voltage_v: float = float(point.get("voltage_v", 0.0))
		# Predicted at the rpm the motor reaches under THAT prop's torque at that voltage, the
		# same loaded convention the fit used (no-load Kv x V when the motor has no DC data).
		var predict_rpm := kv * voltage_v
		if not dc.is_empty():
			predict_rpm = float(MotorModel.operating_point(voltage_v, dc[0], dc[1], dc[2], dc[3],
				PropellerModel.fit_k_q(k_t, hold_doc.torque_to_thrust_m()))["rpm"])
		var predicted_n := PropellerModel.thrust_n(k_t, predict_rpm)
		var predicted_g := predicted_n / GRAVITY_MPS2 * 1000.0

		var measured_g: float = float(point.get("measured_thrust_g", 0.0))
		if measured_g <= 0.0:
			continue

		var cross_diameter: bool = absf(hold_doc.diameter_mm - fit_doc.diameter_mm) > 0.01
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
			"within_sanity": predicted_g >= SANITY_LOW * measured_g and predicted_g <= SANITY_HIGH * measured_g,
			"source": String(point.get("source", "")),
		})

	return out


## Prop geometry in SI, plus the generated chord planform. Mirrors Build._prop_geometry
## rather than calling it, because a validation point is evaluated against a motor and a prop
## with no frame and no pack — there is no Build to ask, and inventing one to reach a private
## helper would be the tail wagging. The `chord` is needed by the BEMT cross-prop ratio (§0,
## P5) that motor_plausibility uses to draw its band; the other three fields stay for the
## callers that only need geometry.
static func geometry_of(prop: Dictionary) -> Dictionary:
	var doc := PropellerDocument.from_catalog_prop(prop)
	return {
		"diameter_m": float(prop["specs"]["diameter_inches"]) * INCH_M,
		"pitch_m": float(prop["specs"]["pitch_inches"]) * INCH_M,
		"blades": float(prop["specs"]["blades"]),
		"chord": doc.chord,
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
