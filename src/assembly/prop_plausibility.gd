class_name PropPlausibility
extends RefCounted
## What a build says about a propeller whose numbers came from a builder rather than from the
## catalog. MotorPlausibility next door is the shape and the reasoning, and both hold here: the
## bounds were FIXED BEFORE any custom data ran against them (thrust_validation.gd's spirit), and
## nothing blocks — labs-and-sim.md §2 warns and never blocks, and the refusals that ARE required
## live in CustomPropellers where the alternative is undefined physics.
##
## Two checks live here, and both exist for the same reason MotorPlausibility does: the numbers on
## a prop listing (a diameter, a pitch, a blade count, a mass) all look reasonable individually,
## and the failure mode is one figure that disagrees with the others in a way that produces an
## aircraft that looks fine and flies on physics that is not.
##
## ===========================================================================
## THE BOUNDS, AND WHY EACH IS WHERE IT IS
## ===========================================================================
##
##   BLADES OUTSIDE 2-4. The catalog spans 2-, 3- and 4-blade props (propellers.json). Real props
##   exist outside the range — five-blade cinelifter, single-blade of, ducted whoop stators — but
##   they are class outliers on any airframe Lothal knows how to build. The mass model reads
##   blades as a factor in rotor inertia; the render draws exactly that many blades; the k_t
##   scaling law's blades^0.8 exponent was fitted against nothing tighter than tables of tri-
##   blades and bi-blades, so extrapolating to eight blades is an exercise the model has not
##   earned. WARN, never block: an aircraft with a 5-blade prop flies fine on paper, and if the
##   builder knows what they are doing that is their business.
##
##   MASS vs DIAMETER. Prop mass scales as diameter cubed, near enough — it is a small piece of
##   plastic whose volume grows as the diameter grows. A fit over the shipped catalog's 17 entries
##   gives an exponent close to 3 with residuals inside a factor of ~2. Same argument as
##   MotorPlausibility's KV-for-stator law: a builder who types 45 g for a 5" prop has typed the
##   mass of the whole aircraft into a field that is supposed to hold 4.5 g, and everything
##   downstream — TWR, rotor inertia, resonance — quietly fits itself around it. The bound is
##   the widening of the catalog's own residual, same shape and same reason as
##   MotorPlausibility.BAND_WIDENING_FACTOR.
##
## Both these bounds fire only for CUSTOM props. The shipped catalog's numbers have been through
## review, and every entry is inside its own band by construction. Same policy as MotorPlausibility.

const BAND_WIDENING_FACTOR := 2.0

## Mirrors propeller.rs BLADE_COUNT_EXPONENT. Rust cannot export constants to GDScript;
## keep in step with the Rust source of truth (enforced by the golden cross-check).
const BLADE_COUNT_EXPONENT := 0.8

## The blade counts the catalog spans. Outside these is a fact about the aircraft, said out loud.
const MIN_TYPICAL_BLADES := 2
const MAX_TYPICAL_BLADES := 4


## Everything this file has to say about one build, in one list. Nothing at all for a catalog
## prop: every check here is a check on numbers one person typed.
static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not PartsCatalog.is_custom(str(build.propeller.get("part_id", ""))):
		return out

	out.append(_provenance(build.propeller))
	out.append_array(_blade_count(build.propeller))
	out.append_array(_mass_for_diameter(build.catalog, build.propeller))
	return out


## That the numbers behind the prop have been through nothing, and — the part specific to props —
## that the k_t the aircraft flies on is fitted from the MOTOR's max_thrust_g and then scaled to
## this prop through blade-count and pitch rules of thumb. Extrapolating those far is what
## PropExtrapolation names; this warning names the fact that the prop side of the calculation is
## a builder's own three numbers to begin with.
static func _provenance(prop: Dictionary) -> BuildWarning:
	var source := str(prop.get("source", "")).strip_edges()
	var specs: Dictionary = prop.get("specs", {})
	return BuildWarning.characteristic(&"custom_propeller",
		"The %s is a propeller you entered yourself (%s). Its %.1f\" diameter, %.1f\" pitch and %d-blade geometry set the rotor inertia and scale the motor's fitted k_t — every thrust, hover and TWR figure on this build reads from those three numbers together with the prop's %.1f g mass." % [
			prop.get("name", prop.get("part_id", "?")), source,
			float(specs.get("diameter_inches", 0.0)), float(specs.get("pitch_inches", 0.0)),
			int(specs.get("blades", 0)), float(prop.get("mass_g", 0.0))],
		{"part_id": str(prop.get("part_id", "")), "source": source})


static func _blade_count(prop: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var blades := int(prop.get("specs", {}).get("blades", 0))
	if blades >= MIN_TYPICAL_BLADES and blades <= MAX_TYPICAL_BLADES:
		return out

	out.append(BuildWarning.characteristic(&"implausible_blade_count",
		"%d-blade props are outside the %d-%d range the catalog carries. The physics still runs — blades scale k_t through a documented rule of thumb (blades^%.1f) — but the exponent was fitted against tri- and bi-blade tables, and %d blades is extrapolation this file has no way to check." % [
			blades, MIN_TYPICAL_BLADES, MAX_TYPICAL_BLADES,
			BLADE_COUNT_EXPONENT, blades],
		{"blades": blades, "min_typical": MIN_TYPICAL_BLADES, "max_typical": MAX_TYPICAL_BLADES}))
	return out


## Mass as a power of diameter, log-log over the shipped catalog. Same shape as
## MotorPlausibility.kv_law — the fit is recomputed here rather than written down, so the LAW
## (mass scales with diameter) is the claim and the exponent is only today's value of it.
##
## Returns `residual_high` alongside so the warning quotes the catalog's own worst-fit residual
## rather than acting as if the fit were exact.
static func mass_law(catalog: PartsCatalog) -> Dictionary:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for prop in catalog.list_category("propeller"):
		if PartsCatalog.is_custom(str((prop as Dictionary).get("part_id", ""))):
			continue
		var diameter := float((prop as Dictionary).get("specs", {}).get("diameter_inches", 0.0))
		var mass := float((prop as Dictionary).get("mass_g", 0.0))
		if diameter <= 0.0 or mass <= 0.0:
			continue
		xs.append(log(diameter))
		ys.append(log(mass))

	# The regression itself lives in Rust (rust/src/plausibility.rs) — the same log-log fit
	# behind kv_law and thrust_density_band, one copy in the codebase.
	var fit: PackedFloat64Array = Plausibility.log_log_fit(PackedFloat64Array(xs), PackedFloat64Array(ys))
	return {"exponent": fit[0], "coefficient": fit[1], "residual_high": fit[2],
		"count": int(fit[3])}


static func _mass_for_diameter(catalog: PartsCatalog, prop: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var specs: Dictionary = prop.get("specs", {})
	var diameter := float(specs.get("diameter_inches", 0.0))
	var mass := float(prop.get("mass_g", 0.0))
	if diameter <= 0.0 or mass <= 0.0:
		return out

	var law := mass_law(catalog)
	if int(law["count"]) < 3:
		return out
	var predicted := float(law["coefficient"]) * pow(diameter, float(law["exponent"]))
	if predicted <= 0.0:
		return out

	var ratio := mass / predicted
	if ratio <= BAND_WIDENING_FACTOR and ratio >= 1.0 / BAND_WIDENING_FACTOR:
		return out

	out.append(BuildWarning.characteristic(&"implausible_prop_mass",
		"%.1f g on a %.1f\" prop is %.1fx %s than the %.1f g the catalog's own props imply for that diameter. Across the %d shipped propellers mass scales as diameter^%.2f — close to the cube you would expect for a piece of plastic that grows in three dimensions — and the worst-fitting real prop is only %.2fx off that line. A diameter and a mass this far apart is usually a units mistake or a value copied from the wrong row." % [
			mass, diameter, maxf(ratio, 1.0 / ratio),
			"heavier" if ratio > 1.0 else "lighter", predicted,
			int(law["count"]), float(law["exponent"]), float(law["residual_high"])],
		{"mass_g": mass, "diameter_inches": diameter, "predicted_mass_g": predicted,
			"exponent": float(law["exponent"]), "ratio": ratio}))
	return out
