class_name CustomMotors
extends CustomParts
## The motors a builder entered themselves. Read CustomParts first for the id space, the shared
## document and the refusals that are not about motors.
##
## A builder holding a motor Lothal does not stock enters what is printed on the product page and
## Lothal flies it. Motors are commodity parts, and a buyer reads six things off a listing — those
## six things are exactly the physics contract, which is why this record has no field a product
## page does not already carry:
##
##   "2207"         specs.stator_diameter_mm, specs.stator_height_mm — rotor inertia, the drawn bell
##   "1960KV"       specs.kv                  — rpm per volt, and therefore the whole propulsion chain
##   "1450 g max"   specs.max_thrust_g        — what k_t is fitted from
##   "32 A max"     specs.max_amps            — throttle limits, pack current warnings
##   "32 g"         mass_g                    — the mass model
##   "M5 / 16x16"   mount_pattern             — the frame-fit warning
##   "14 pole"      specs.poles               — the electrical-frequency observable
##
## `mount_pattern` is TOP LEVEL rather than inside `specs`, matching motors.json exactly. That is
## not tidiness: it is what lets build.gd's motor-fit warning fire for a custom motor with no
## changes at all, and tests/test_custom_motors.gd asserts that it did not have to be taught.
##
## ---------------------------------------------------------------------------
## THE ONE HARD REQUIREMENT: `thrust_test` IS MANDATORY
## ---------------------------------------------------------------------------
##
## A motor's headline thrust figure is not a description of the motor. It is one row of a bench
## test, and it means nothing without the prop it was measured on and the pack it was measured at
## — which is why motors.json names both, and why build.gd:222 fits k_t from that exact pairing.
##
## So a motor with no thrust test is REFUSED, and this is the one place in this slice where a
## refusal rather than a warning is the honest move. The alternative is not "a slightly wrong
## aircraft": PropellerModel.fit_k_t would run against an empty dictionary, and the builder would
## get a drone that silently does not fly, with no sentence anywhere saying why. physics.md §4
## says do not guess C_T, and inventing one here would be the first place in this codebase where
## Lothal fabricates a bench number.
##
## This is not a burden. Every manufacturer thrust table is headed with the prop and the voltage;
## the builder is copying a column header.
##
## ---------------------------------------------------------------------------
## AND ONE THING A CUSTOM MOTOR MAY NEVER CARRY
## ---------------------------------------------------------------------------
##
## `validation`. Read thrust_validation.gd's header for the full argument; the short form is that
## the block means an independently-measured HELD-OUT point, and it exists to stop the thrust
## stand marking its own homework. A user-entered figure is neither independent nor held out — it
## comes off the same page the fit came from — so quoting it back would produce a bench that
## congratulates itself on data it was handed.
##
## The bench therefore shows "not validated" for every custom motor. That is not a gap in this
## feature. It is the honest reading of what is known about a number one person typed in.

const MOTORS_KEY := "motors"


func array_key() -> String:
	return MOTORS_KEY


func category() -> String:
	return "motor"


func motors() -> Array:
	return records()


func get_motor(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomMotors:
	var doc := CustomMotors.new()
	doc.read_from(path)
	return doc


## A catalog-shaped record from what is printed on a product page, and nothing that is not.
## `mount_pattern` is TOP LEVEL rather than inside `specs`, matching motors.json, which is what
## lets build.gd's motor-fit warning fire for a custom motor with no changes at all.
static func make_record(name: String, mass_g: float, stator_diameter_mm: float,
		stator_height_mm: float, kv: float, max_thrust_g: float, max_amps: float, poles: int,
		mount_pattern: String, test_prop_id: String, test_voltage_v: float,
		source: String) -> Dictionary:
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "motor",
		"mass_g": mass_g,
		"mount_pattern": mount_pattern,
		"specs": {
			"kv": kv,
			"stator_diameter_mm": stator_diameter_mm,
			"stator_height_mm": stator_height_mm,
			"max_thrust_g": max_thrust_g,
			"max_amps": max_amps,
			"poles": poles,
		},
		"thrust_test": {
			"prop_id": test_prop_id,
			"voltage_v": test_voltage_v,
		},
		"catalog": {
			"stator_class": stator_class_for(stator_diameter_mm),
			"kv_class": kv_class_for(kv),
			"intended_use": "custom",
		},
		"source": source,
	}


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "motor")


## The picker's Stator bucket, derived rather than asked for — the same reasoning as
## CustomFrames.size_class_for, and unlike that one this derivation is exact. motors.json spells
## it "08xx", "22xx", "28xx": the stator diameter in millimetres, two digits, zero-padded. There
## is no hand-authored inconsistency to reproduce here and no judgement to make.
static func stator_class_for(stator_diameter_mm: float) -> String:
	return "%02dxx" % int(round(stator_diameter_mm))


## The picker's KV bucket. The boundaries are the catalog's own, and they are NOT continuous: the
## shipped motors leave 2600-3000KV and 5000-8000KV with no bucket at all, because no motor in
## the catalog lives there. A custom motor that does gets "custom" rather than being filed under
## the nearest band it is not in — that would be a false statement on a filter, and "custom" is a
## bucket of one which is the honest limit of deriving from a catalog with holes in it. Same
## shape of admission as the frames slice's note about "65mm".
static func kv_class_for(kv: float) -> String:
	if kv < 1500.0:
		return "under 1500KV"
	if kv < 2000.0:
		return "1500-2000KV"
	if kv < 2600.0:
		return "2000-2600KV"
	if kv >= 3000.0 and kv < 5000.0:
		return "3000-5000KV"
	if kv >= 8000.0:
		return "8000KV+"
	return "custom"


# ---------------------------------------------------------------------------
# The motor-specific refusals
# ---------------------------------------------------------------------------

## Everything without which there is no propulsion to compute. Deliberately short, and every
## entry on it is a case where the sim would produce a number rather than a complaint — a
## refusal is only defensible where the alternative is silence.
##
## Nothing here is about whether the motor is a SENSIBLE one. A 2807 claiming 6 kg of thrust is
## accepted, flown, and warned about by MotorPlausibility, because labs-and-sim.md §2 warns and
## never blocks and because "surprising" is a judgement while "undefined" is not.
func _category_problems(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: kv, stator_diameter_mm, stator_height_mm, max_thrust_g and max_amps, as printed on the listing")
		return problems
	var specs := raw_specs as Dictionary

	# Each of these is squared, divided by, or drawn from. None has a defensible default: a
	# fallback KV would be a motor the builder does not own, flying on numbers nobody published.
	for field in ["kv", "stator_diameter_mm", "stator_height_mm", "max_amps"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — it is on the product page and nothing here can stand in for it" % field)

	# Called out separately from the loop because the sentence is different: this is the one the
	# whole slice turns on, and "must be positive" would undersell it.
	if not specs.has("max_thrust_g") or float(specs["max_thrust_g"]) <= 0.0:
		problems.append("specs.max_thrust_g is required — k_t is fitted from it, and Lothal will not invent a thrust figure for a motor that does not publish one")

	problems.append_array(_thrust_test_problems(record, catalog))

	if record.has("validation"):
		problems.append("a motor you entered cannot carry a \"validation\" block: that means a HELD-OUT measurement somebody else made, and a figure off the same page as the thrust test is neither held out nor independent. The bench will say \"not validated\", which is the true answer")

	# Required rather than warned about, unlike everything else that is merely surprising. A
	# record with no mount_pattern does not go quiet — build.gd's fit warning fires on every
	# build and reports "?" against the frame's pattern, which is a permanent false claim that
	# the motor does not fit. A refusal that names the missing field is the kinder failure.
	if str(record.get("mount_pattern", "")).strip_edges() == "":
		problems.append("mount_pattern is required (the bolt circle, e.g. \"16x16\") — without it Lothal would tell you on every build that this motor does not fit your frame, which it has no way to know")

	return problems


## The column header of the manufacturer's table: which prop, and at what voltage.
##
## The prop is resolved against the SHIPPED catalog, because that is what add() and read_from()
## can pass without re-entering PartsCatalog.load_with_custom, which loads this document. When
## the custom-propellers slice lands it will have to hand a merged catalog in here instead — the
## seam is the `catalog` argument, and this comment is the note that it is load-bearing.
func _thrust_test_problems(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_test: Variant = record.get("thrust_test", null)
	if not (raw_test is Dictionary) or (raw_test as Dictionary).is_empty():
		problems.append("thrust_test is required: the prop and the voltage the thrust figure was measured on. Every manufacturer table is headed with both — a motor without them has no thrust Lothal can compute, and it would fly as though it had none")
		return problems
	var test := raw_test as Dictionary

	var prop_id := str(test.get("prop_id", ""))
	if prop_id == "":
		problems.append("thrust_test.prop_id is required: which propeller the thrust figure was measured on. It is the heading of the column you read the figure out of")
	elif catalog.get_part(prop_id).is_empty():
		problems.append("thrust_test.prop_id \"%s\" is not a propeller Lothal knows about — check the id against the propeller list" % prop_id)
	elif str(catalog.get_part(prop_id).get("category", "")) != "propeller":
		problems.append("thrust_test.prop_id \"%s\" is not a propeller" % prop_id)

	if float(test.get("voltage_v", 0.0)) <= 0.0:
		problems.append("thrust_test.voltage_v must be positive: the pack voltage the table was measured at. A 6S table means 22.2 V")

	return problems
