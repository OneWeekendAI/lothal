class_name TestCustomControlComponents
extends RefCounted
## CustomGps and CustomBuzzers — the two stores C7 added for C2's ADDED components.
##
## What these two stores must do that CustomCameras does not is REFUSE a record that leaves out the
## one field its category exists for, and the checks below are about that and about what the model
## then does with a record that got through:
##
##   a GPS with no mast is refused — Build.component_rise_m would seat it flat, silently;
##   a GPS mast of 0 is ACCEPTED — a flat module saying so is the honest record, not a missing one;
##   a negative or string mast is refused;
##   a buzzer with no `self_powered` is refused, and so is a string or a number in its place;
##   an accepted custom part comes back through PartsCatalog.load_with_custom, fits, and its field
##   reaches the consumer that reads it (the seat height; ControlPlausibility's warning);
##   and a custom GPS and buzzer merely HELD in the file change the reference build not at all.
##
## ONE TEST PER CASE, never a loop over cases (feedback_loop_tests_hide_coverage). Every row names in
## its header comment what would make it fail, and every one was run red against that mutation.
##
## Scratch file only: nothing here reads or writes the developer's user://custom_parts.json.

const PATH := "user://test_custom_control_components.json"
const EPS := 1e-9


static func run() -> Array:
	var results: Array = []
	_wipe()
	results.append(_test_a_gps_with_a_mast_is_accepted())
	results.append(_test_a_flat_gps_with_mast_zero_is_accepted())
	results.append(_test_a_gps_with_no_mast_is_refused())
	results.append(_test_a_gps_with_a_negative_mast_is_refused())
	results.append(_test_a_gps_with_a_string_mast_is_refused())
	results.append(_test_a_buzzer_that_says_how_it_is_powered_is_accepted())
	results.append(_test_a_buzzer_that_does_not_say_is_refused())
	results.append(_test_a_buzzer_with_a_string_self_powered_is_refused())
	results.append(_test_a_buzzer_with_a_number_self_powered_is_refused())
	results.append(_test_a_custom_gps_loads_into_the_catalog_and_its_mast_seats_it())
	results.append(_test_a_custom_fc_powered_buzzer_draws_the_warning())
	results.append(_test_a_custom_self_powered_buzzer_does_not())
	results.append(_test_held_but_unfitted_parts_leave_the_reference_build_bit_identical())
	_wipe()
	return results


static func _wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func _gps(name: String, mast: float) -> Dictionary:
	return CustomGps.make_record(name, 11.0, 22.0, 22.0, 7.0, mast, "GPS + Galileo", true, "UBX",
		"measured on my scale, mast cut to length")


static func _buzzer(name: String, self_powered: Variant) -> Dictionary:
	return CustomBuzzers.make_record(name, 3.0, 20.0, 15.0, 9.0, self_powered, null,
		"off the product page")


static func _mentions(problems: Array, word: String) -> bool:
	for problem in problems:
		if str(problem).contains(word):
			return true
	return false


# ---------------------------------------------------------------------------
# The GPS store's refusals
# ---------------------------------------------------------------------------

## FAILS IF: the mast refusal is too eager (refuses a present positive mast), or the base refusals
## stopped being inherited so badly that a good record is refused.
static func _test_a_gps_with_a_mast_is_accepted() -> TestResult:
	var problems := CustomGps.new().add(_gps("Shed masted", 60.0))
	return TestResult.new("a custom GPS with a 60 mm mast is accepted", problems.is_empty(),
		str(problems))


## FAILS IF: the mast check reads 0 as absent (`<= 0` instead of `< 0`, or a truthiness test) — which
## would refuse every flat module, the commonest thing fitted.
static func _test_a_flat_gps_with_mast_zero_is_accepted() -> TestResult:
	var record := _gps("Shed flat", 0.0)
	var problems := CustomGps.new().add(record)
	return TestResult.new("a flat custom GPS saying mast_height_mm 0 is accepted, and 0 is stored",
		problems.is_empty() and (record["specs"] as Dictionary).get("mast_height_mm", -1.0) == 0.0,
		"problems=%s, specs=%s" % [problems, record["specs"]])


## THE ROW THE STORE EXISTS FOR. FAILS IF: the `has("mast_height_mm")` refusal is deleted — the
## record is then accepted and component_rise_m seats it at 0.
static func _test_a_gps_with_no_mast_is_refused() -> TestResult:
	var record := _gps("Shed unsaid", NAN)
	var problems := CustomGps.new().add(record)
	return TestResult.new("a custom GPS with no mast_height_mm is refused, naming the field",
		not (record["specs"] as Dictionary).has("mast_height_mm") and problems.size() == 1
			and _mentions(problems, "mast_height_mm"),
		"problems=%s" % [problems])


## FAILS IF: the negative-mast refusal is deleted.
static func _test_a_gps_with_a_negative_mast_is_refused() -> TestResult:
	var problems := CustomGps.new().add(_gps("Shed upside down", -5.0))
	return TestResult.new("a custom GPS with a negative mast is refused",
		problems.size() == 1 and _mentions(problems, "negative"), str(problems))


## FAILS IF: the type check is deleted — `float("45")` would then read as a real 45 mm and a
## hand-edited file's string would be quietly coerced.
static func _test_a_gps_with_a_string_mast_is_refused() -> TestResult:
	var record := _gps("Shed stringy", 45.0)
	(record["specs"] as Dictionary)["mast_height_mm"] = "45"
	var problems := CustomGps.new().add(record)
	return TestResult.new("a custom GPS whose mast is the string \"45\" is refused",
		problems.size() == 1 and _mentions(problems, "number"), str(problems))


# ---------------------------------------------------------------------------
# The buzzer store's refusals
# ---------------------------------------------------------------------------

## FAILS IF: the power refusal is too eager — `false` read as absent would refuse every FC-powered
## buzzer, which is most of them. Both answers asserted, since a check that only tried `true` could
## not see that.
static func _test_a_buzzer_that_says_how_it_is_powered_is_accepted() -> TestResult:
	var document := CustomBuzzers.new()
	var own_cell := document.add(_buzzer("Shed cell", true))
	var fc_rail := document.add(_buzzer("Shed rail", false))
	return TestResult.new("a custom buzzer saying self_powered true, and one saying false, are both accepted",
		own_cell.is_empty() and fc_rail.is_empty(),
		"true: %s; false: %s" % [own_cell, fc_rail])


## THE ROW THE STORE EXISTS FOR. FAILS IF: the `has("self_powered")` refusal is deleted — the record
## is accepted and ControlPlausibility reads the absent key as false.
static func _test_a_buzzer_that_does_not_say_is_refused() -> TestResult:
	var record := _buzzer("Shed unsaid", null)
	var problems := CustomBuzzers.new().add(record)
	return TestResult.new("a custom buzzer with no self_powered is refused, naming the field",
		not (record["specs"] as Dictionary).has("self_powered") and problems.size() == 1
			and _mentions(problems, "self_powered"),
		str(problems))


## FAILS IF: the `is bool` check is deleted.
static func _test_a_buzzer_with_a_string_self_powered_is_refused() -> TestResult:
	var problems := CustomBuzzers.new().add(_buzzer("Shed stringy", "false"))
	return TestResult.new("a custom buzzer whose self_powered is the string \"false\" is refused",
		problems.size() == 1 and _mentions(problems, "true or false"), str(problems))


## FAILS IF: the `is bool` check is loosened to "a bool or a number" — 1.0 is what a JSON file holds
## when somebody writes 1.
static func _test_a_buzzer_with_a_number_self_powered_is_refused() -> TestResult:
	var problems := CustomBuzzers.new().add(_buzzer("Shed numeric", 1.0))
	return TestResult.new("a custom buzzer whose self_powered is the number 1 is refused",
		problems.size() == 1 and _mentions(problems, "true or false"), str(problems))


# ---------------------------------------------------------------------------
# Through the catalog and into the consumers
# ---------------------------------------------------------------------------

static func _save_one(document: CustomParts, record: Dictionary) -> Array[String]:
	document.read_from(PATH)
	var problems := document.add(record)
	if problems.is_empty():
		document.save(PATH)
	return problems


static func _reference_with(catalog: PartsCatalog, overrides: Dictionary) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, overrides)


## FAILS IF: CustomGps is not merged in load_with_custom (the part is not in the catalog, so nothing
## is fitted), or its array key / category word is wrong, or the stored mast does not reach the model
## — asserted as the rise the build reads, at the 60 mm typed, not merely "a GPS was fitted".
static func _test_a_custom_gps_loads_into_the_catalog_and_its_mast_seats_it() -> TestResult:
	_wipe()
	var record := _gps("Shed masted", 60.0)
	var problems := _save_one(CustomGps.new(), record)
	var catalog := PartsCatalog.load_with_custom(PATH)
	var part_id := str(record["part_id"])
	var build := _reference_with(catalog, {"gps": part_id})
	var fitted: Dictionary = build.components.get("gps", {})
	var rise := build.rise_m_for(fitted) if not fitted.is_empty() else -1.0
	_wipe()
	return TestResult.new("a saved custom GPS loads into the catalog, fits, and is seated on its 60 mm mast",
		problems.is_empty() and not catalog.get_part(part_id).is_empty()
			and str(fitted.get("part_id", "")) == part_id and absf(rise - 0.060) < EPS,
		"problems=%s, in catalog=%s, fitted=%s, rise=%.4f m, load errors=%s" % [problems,
			not catalog.get_part(part_id).is_empty(), fitted.get("part_id", "<none>"), rise,
			catalog.load_errors])


static func _warning_ids(build: Build) -> Array:
	var out: Array = []
	for warning in ControlPlausibility.warnings_for(build):
		out.append(String(warning.id))
	return out


## FAILS IF: CustomBuzzers is not merged, or the stored `false` does not survive the file (a record
## written without the key would ALSO fire this — which is exactly why the next row exists too).
static func _test_a_custom_fc_powered_buzzer_draws_the_warning() -> TestResult:
	_wipe()
	var record := _buzzer("Shed rail", false)
	var problems := _save_one(CustomBuzzers.new(), record)
	var catalog := PartsCatalog.load_with_custom(PATH)
	var build := _reference_with(catalog, {"buzzer": str(record["part_id"])})
	var ids := _warning_ids(build)
	_wipe()
	return TestResult.new("a saved custom FC-powered buzzer is fitted and draws the dies-with-the-pack warning",
		problems.is_empty() and build.components.has("buzzer") and ids.has("buzzer_not_self_powered"),
		"problems=%s, fitted=%s, warnings=%s" % [problems, build.components.has("buzzer"), ids])


## The other half. FAILS IF: `true` is lost between the dialog's store and the reader — the warning
## would then fire on a finder that has its own cell. Together with the row above it is the only
## pair that proves the field is READ rather than defaulted either way.
static func _test_a_custom_self_powered_buzzer_does_not() -> TestResult:
	_wipe()
	var record := _buzzer("Shed cell", true)
	var problems := _save_one(CustomBuzzers.new(), record)
	var catalog := PartsCatalog.load_with_custom(PATH)
	var build := _reference_with(catalog, {"buzzer": str(record["part_id"])})
	var ids := _warning_ids(build)
	_wipe()
	return TestResult.new("a saved custom self-powered buzzer is fitted and stays quiet",
		problems.is_empty() and build.components.has("buzzer")
			and not ids.has("buzzer_not_self_powered"),
		"problems=%s, fitted=%s, warnings=%s" % [problems, build.components.has("buzzer"), ids])


## Design §3: added mass, no default. A custom GPS and buzzer sitting in the builder's file must not
## reach an aircraft that did not fit them — the reference build through load_with_custom must equal
## ReferenceBuild.build() exactly, not approximately.
##
## FAILS IF: either store is given a default (DEFAULT_COMPONENT_IDS pointed at a custom id, or a
## "first record in the category" fallback), or a carved share — the mass or the CoM moves.
static func _test_held_but_unfitted_parts_leave_the_reference_build_bit_identical() -> TestResult:
	_wipe()
	var held := _save_one(CustomGps.new(), _gps("Shed masted", 70.0))
	held.append_array(_save_one(CustomBuzzers.new(), _buzzer("Shed cell", true)))
	var catalog := PartsCatalog.load_with_custom(PATH)
	var with_custom := _reference_with(catalog, {})
	var reference_build := ReferenceBuild.build()
	_wipe()
	var same_mass := with_custom.all_up_weight_g() == reference_build.all_up_weight_g()
	var same_com := with_custom.mass_properties.com_m == reference_build.mass_properties.com_m
	return TestResult.new("a custom GPS and buzzer held but not fitted leave the reference build bit-identical",
		held.is_empty() and catalog.list_category("gps").size() > 0 and same_mass and same_com
			and not with_custom.components.has("gps") and not with_custom.components.has("buzzer"),
		"held problems=%s, %.6f g vs %.6f g, CoM %s vs %s" % [held,
			with_custom.all_up_weight_g(), reference_build.all_up_weight_g(),
			with_custom.mass_properties.com_m, reference_build.mass_properties.com_m])
