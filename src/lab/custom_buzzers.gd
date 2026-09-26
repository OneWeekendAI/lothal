class_name CustomBuzzers
extends CustomComponents
## The lost-model buzzers a builder entered themselves (C7). Read CustomComponents for the
## box-and-mass half every one of these shares, and CustomParts for the id space and the document.
##
## ---------------------------------------------------------------------------
## `self_powered` IS REQUIRED, AS A BOOLEAN, AND THERE IS NO SAFE DEFAULT TO GIVE IT
## ---------------------------------------------------------------------------
##
## It is the field the whole component is for (buzzers.json `_schema`): a buzzer on the flight
## controller's 5 V rail goes silent the moment the pack disconnects, which is the moment it exists
## for. ControlPlausibility reads it — `bool(specs.get("self_powered", false))` — and turns false
## into the amber "dies with the pack" warning.
##
## Either default is a lie about somebody's aircraft. Defaulting to false, which is what that reader
## does with a missing key, warns a builder whose finder has its own cell that it will go quiet when
## it will not — a warning that is wrong the first time teaches them to ignore it the time it is
## right. Defaulting to true silences the one warning this category carries on the buzzers it is
## actually true of. So the builder answers, and the store refuses a record that did not.
##
## A BOOLEAN AND NOT A TRUTHY VALUE. `"false"` and `0` are the shapes a hand-edited file arrives
## in, and neither means what the builder meant once a reader coerces it — so both are refused rather
## than interpreted. tests/test_control_parts.gd holds the shipped file to TYPE_BOOL for the same
## reason; a builder's file is held to the same.
##
## NO DEFAULT, NO CARVED SHARE: a buzzer is ADDED mass (design §3), like the GPS.
##
## `loudness_db` is carried in `catalog`, null when the builder has no figure, and read by no check —
## the same position buzzers.json takes.

const BUZZERS_KEY := "buzzers"


func array_key() -> String:
	return BUZZERS_KEY


func category() -> String:
	return "buzzer"


func buzzers() -> Array:
	return records()


static func load_from(path: String = SAVE_PATH) -> CustomBuzzers:
	var document := CustomBuzzers.new()
	document.read_from(path)
	return document


## `self_powered` null means "the builder did not say", and becomes an ABSENT key — so a dialog whose
## power question was left unanswered reaches the refusal rather than writing either default.
## `loudness_db` null means no published figure and is stored as null, as buzzers.json does.
static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, self_powered: Variant, loudness_db: Variant, source: String) -> Dictionary:
	var record := component_record(id_for(name), name, "buzzer", mass_g, length_mm, width_mm,
		height_mm, {"loudness_db": loudness_db}, source)
	if self_powered != null:
		(record["specs"] as Dictionary)["self_powered"] = self_powered
	return record


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "buzzer")


func _category_problems(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems := super(record, catalog)
	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		return problems
	var specs := raw_specs as Dictionary

	if not specs.has("self_powered"):
		problems.append("specs.self_powered is required — true if the buzzer has its own cell and keeps sounding when the pack ejects, false if it runs off the flight controller's 5 V rail. There is no default: either guess is wrong about somebody's aircraft")
	elif not (specs["self_powered"] is bool):
		problems.append("specs.self_powered must be true or false, not %s" % type_string(typeof(specs["self_powered"])))
	return problems
