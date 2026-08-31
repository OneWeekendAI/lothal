class_name CustomPropellers
extends CustomParts
## The propellers a builder entered themselves. Read CustomParts first for the id space, the shared
## document and the refusals that are not about propellers.
##
## A propeller is three numbers and a mass. That IS the physics contract:
##
##   "5x4.3x3"      specs.diameter_inches — thrust as D^4, dominates everything
##                  specs.pitch_inches    — k_t scaling, blade twist in the render
##                  specs.blades          — k_t scaling, blade count in the render
##   "4.5 g"        mass_g                — rotor inertia (build.gd _prop_geometry), airframe mass
##
## `catalog.material` is browsing metadata and stays there. Nothing reads blade stiffness; the day
## the model grows a flex term is the day material moves into `specs`, and not before.
##
## ---------------------------------------------------------------------------
## LOAD ORDER: PROPS BEFORE MOTORS
## ---------------------------------------------------------------------------
##
## A custom motor's `thrust_test.prop_id` may name a custom prop. So this document must be loaded
## and merged into the catalog BEFORE CustomMotors reads user://, or a motor citing a custom prop
## would be refused at load with "not a propeller Lothal knows about" — the exact silent-fail
## CustomMotors was designed to prevent, back-doored. PartsCatalog.load_with_custom does the
## merge in that order, and CustomMotors.read_from resolves against a catalog that already holds
## these entries. tests/test_custom_propellers.gd asserts the order from both sides.
##
## ---------------------------------------------------------------------------
## DELETE-REFUSAL: A PROP A MOTOR DEPENDS ON MUST NOT VANISH SILENTLY
## ---------------------------------------------------------------------------
##
## Removing a custom prop that a custom motor names in its `thrust_test` leaves the motor's k_t
## fitted against an empty dictionary — the failure motors.json's _schema warns about, back-doored
## by a delete rather than by a missing field. So `remove()` here refuses when the prop is depended
## on, and the refusal names the dependent motor so the builder can act. Nothing else in the app
## goes near `_records` directly, so this one seam is the whole of the guard.

const PROPELLERS_KEY := "propellers"


func array_key() -> String:
	return PROPELLERS_KEY


func category() -> String:
	return "propeller"


func propellers() -> Array:
	return records()


func get_propeller(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomPropellers:
	var doc := CustomPropellers.new()
	doc.read_from(path)
	return doc


## A catalog-shaped record from the six things a builder reads off a listing. Static, and the ONE
## place a prop record's shape is written down — a UI that has drifted cannot produce a record no
## reader understands.
static func make_record(name: String, mass_g: float, diameter_inches: float, pitch_inches: float,
		blades: int, material: String, source: String) -> Dictionary:
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "propeller",
		"mass_g": mass_g,
		"specs": {
			"diameter_inches": diameter_inches,
			"pitch_inches": pitch_inches,
			"blades": blades,
		},
		"catalog": {
			"blade_count": blade_count_for(blades),
			"diameter_class": diameter_class_for(diameter_inches),
			"intended_use": "custom",
			"material": material,
		},
		"source": source,
	}


## An authored blade published as a propeller a build can fit
## (plans/2026-09-01-authored-blade-design.md §3). The Propulsion room's second door: `Save` keeps a
## draft in `BladeLibrary`, and this turns one into a product.
##
## Delegates to `make_record` rather than assembling a record beside it, so the "ONE place a prop
## record's shape is written down" rule above survives a second author. What this adds is the inline
## blade block — the whole document under `PropellerDocument.AUTHORED_BLADE_KEY` — which is what
## `from_catalog_prop` resolves and therefore what makes the fitted aircraft fly the drawn shape.
##
## MASS IS DERIVED, and that is this function's load-bearing decision. `BladeGeometry.blade_mass_g`
## integrates the planform against the material's density and the document's own thickness ratio
## (and already multiplies by the blade count — the name says blade, the integral says propeller).
## A publish path that let a mass be typed would let a builder narrow a blade by 40% and keep the
## mass of the blade they copied, and then the aerodynamics would follow the new geometry while the
## rotor inertia, the spin-up tau and the aircraft's own mass followed the old one. Half the model
## moving is worse than none of it moving, because nothing on screen says which half.
##
## The document's `published_mass_g` is set to the same number before the block is written. For a
## catalog blade those two are a manufacturer's figure and an integral, and P1's falsification is
## the gap between them; for an authored blade there is no manufacturer, so they are one number by
## construction. `MotorSpinUp`'s two inertia paths — published and computed — therefore agree here,
## and `tests/test_authored_blade.gd` asserts that rather than leaving it as a comment.
static func record_from_document(document: PropellerDocument, materials: FrameMaterials,
		source: String) -> Dictionary:
	if document == null:
		return {}
	var published := document.to_dictionary()
	var mass_g := BladeGeometry.blade_mass_g(document, materials)
	published["published_mass_g"] = mass_g

	var record := make_record(document.name, mass_g,
		document.diameter_mm / PropellerDocument.INCH_TO_MM,
		document.pitch_mm / PropellerDocument.INCH_TO_MM,
		document.blades, document.material_id, source)
	record[PropellerDocument.AUTHORED_BLADE_KEY] = published
	return record


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "propeller")


## The picker's blade-count bucket. Spelled the way propellers.json spells it: "2-blade",
## "3-blade", "4-blade". A custom prop whose blade count sits in the catalog's own set lands in the
## catalog's own filter bucket rather than in a bucket of one — same reasoning as
## CustomFrames.size_class_for.
static func blade_count_for(blades: int) -> String:
	return "%d-blade" % blades


## The picker's diameter bucket. Spelled with the inch mark ("5\"") to match the catalog's own
## `diameter_class` values. Rounded to whole inches when it lands on one, decimal otherwise — the
## catalog carries both forms ("5\"" and "3.5\"") and this reproduces that. Same shape as
## CustomFrames.size_class_for.
static func diameter_class_for(diameter_inches: float) -> String:
	if diameter_inches <= 0.0:
		return "unspecified"
	var rounded := snappedf(diameter_inches, 0.5)
	var text := str(rounded)
	if text.ends_with(".0"):
		text = text.trim_suffix(".0")
	return "%s\"" % text


# ---------------------------------------------------------------------------
# The prop-specific refusals
# ---------------------------------------------------------------------------

## Each of these is either squared, cubed, raised to the fourth or drawn from. None has a
## defensible default — a prop with no diameter has no thrust, and a fallback would be inventing
## an aircraft nobody owns.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: diameter_inches, pitch_inches and blades, as printed on the listing")
		return problems
	var specs := raw_specs as Dictionary

	for field in ["diameter_inches", "pitch_inches"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — it is printed on the prop and nothing here can stand in for it" % field)

	if not specs.has("blades") or int(specs["blades"]) < 1:
		problems.append("specs.blades must be present and at least 1 — a zero-blade prop makes no thrust")

	return problems


# ---------------------------------------------------------------------------
# Delete-refusal: name the dependent motor rather than let it fall silent
# ---------------------------------------------------------------------------

## Motors that name this prop in their `thrust_test`. Kept ONLY over the custom-motor document —
## a custom prop cannot be named by a shipped motor (a shipped motor's thrust_test is checked at
## authoring time against shipped props) and the collision defence already prevents a custom prop
## from shadowing a shipped id — so this is the complete list.
func dependent_motors(motor_doc: CustomMotors, part_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for motor in motor_doc.motors():
		var test: Variant = (motor as Dictionary).get("thrust_test", null)
		if test is Dictionary and str((test as Dictionary).get("prop_id", "")) == part_id:
			out.append(motor as Dictionary)
	return out


## The message a caller can show, or "" if the prop is free to go. Deliberately a helper rather
## than baked into `remove()`: a Lab surface removing a prop should tell the user WHY before it
## fails, not after. `remove()` still refuses on its own (see below), so a caller that forgot to
## check does not silently take the motor down with it.
func removal_block_message(motor_doc: CustomMotors, part_id: String) -> String:
	var dependents := dependent_motors(motor_doc, part_id)
	if dependents.is_empty():
		return ""
	var names: Array[String] = []
	for motor in dependents:
		names.append(str(motor.get("name", motor.get("part_id", "?"))))
	return "\"%s\" is the thrust-test prop for %s; delete or edit %s first — without it those motors have no thrust Lothal can compute." % [
		part_id, ", ".join(names), "them" if names.size() > 1 else "it"]


## The one entry point that removes a prop. Refuses when a custom motor depends on it, so a
## caller that skipped removal_block_message does not silently produce a motor with no fittable
## k_t. Returns true on success; caller can consult removal_block_message for the sentence.
##
## Reads the neighbouring motor document from the same file this one lives in, since that is what
## PartsCatalog.load_with_custom does and it is the only file a delete could break.
func remove_or_refuse(part_id: String, motor_doc: CustomMotors = null) -> bool:
	var doc := motor_doc if motor_doc != null else CustomMotors.load_from()
	if not dependent_motors(doc, part_id).is_empty():
		return false
	return remove(part_id)
