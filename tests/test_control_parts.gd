class_name TestControlParts
extends RefCounted
## gps.json and buzzers.json — C1's two parts files.
## plans/2026-09-12-control-room-plan.md, slice C1. Design: §2.3, §2.4, §0, §9.
##
## THE TWO FIELDS THIS FILE EXISTS TO DEFEND are `specs.mast_height_mm` on a GPS and
## `specs.self_powered` on a buzzer, and neither is defended by its value being right — both are
## defended by the CATALOG BEING ABLE TO EXPRESS BOTH CASES. Design §2.3 wants a module whose mass
## sits above the top plate on a stalk and a module that sits on it; §6.2's warning wants a buzzer
## that dies with the pack and one that does not. A file where every row agreed would leave both of
## those checks green forever against a catalog that cannot make them fire, which is the exact shape
## of "a test that cannot fail". So the last two checks below assert the SPREAD, not the numbers.
##
## The field checks live here rather than in test_parts_system.gd's required-field table for the
## reason test_power_parts.gd gives for connectors and capacitors: these two categories name their
## own required fields in the file that also asserts what those fields mean, so a field added to the
## schema prose and forgotten in a row fails in one place.
##
## TYPES ARE ASSERTED PER FIELD, not "specs hold numbers only" as test_power_parts.gd does. Buzzers
## break that rule honestly — `self_powered` is a BOOLEAN in the physics tier, because the thing it
## models is a binary and rounding it to 0.0/1.0 would invite arithmetic on it. A blanket
## numbers-only check would either fail on a correct file or have to carve out an exception, and an
## exception is a description rather than a constraint. A declared type per field is stricter than
## both: it catches `"self_powered": "true"` and `"mast_height_mm": "45"`, which a numbers-only
## check would catch only half of.
##
## ONE ROW OF C1's CHECK TABLE IS DELIBERATELY NOT REIMPLEMENTED HERE, and this is the record of
## that decision rather than an omission. "A row claiming the custom prefix is refused and reported
## in load_errors" is ALREADY covered: test_custom_frames.gd drives _load_category directly against
## tests/fixtures/frames_with_custom_id.json and asserts all three of refusal, surgical refusal, and
## the id being named in load_errors. That branch reads `part_id` and nothing else — it never looks
## at the category — so a gps-flavoured fixture would feed the same line the same input class and
## the plan's mutation (remove the prefix branch) reddens the existing check either way. A second
## copy would add a passing line and no coverage. The branch that had NO coverage anywhere in
## tests/ is the CATEGORY-MATCH one beside it, and that is _test_loader_refuses_a_mislabelled_row
## below, with a fixture written to disagree with itself because no shipped file does.

## The fields every GPS row must carry, split by tier. `specs` is physics-bearing; `catalog` is
## browsing metadata. A field in the wrong block is as wrong as a field missing — it reads as
## present to a human and is absent to every caller.
const GPS_SPECS := {
	"length_mm": TYPE_FLOAT,
	"width_mm": TYPE_FLOAT,
	"height_mm": TYPE_FLOAT,
	"mast_height_mm": TYPE_FLOAT,
}
const GPS_CATALOG := ["constellations", "compass", "protocol"]
const BUZZER_SPECS := {
	"length_mm": TYPE_FLOAT,
	"width_mm": TYPE_FLOAT,
	"height_mm": TYPE_FLOAT,
	# The one boolean in either file's physics tier. See the header.
	"self_powered": TYPE_BOOL,
}
const BUZZER_CATALOG := ["loudness_db"]

## The fixture that drives the category-match branch. Not in CATEGORY_FILES and never loaded by the
## app — every shipped file agrees with itself, which is why this branch was uncovered.
const MISLABELLED_FIXTURE := "res://tests/fixtures/gps_with_wrong_category.json"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_both_categories_load_and_return_by_id(catalog))
	results.append(_test_every_gps_row_carries_every_declared_field(catalog))
	results.append(_test_every_buzzer_row_carries_every_declared_field(catalog))
	results.append(_test_spec_fields_hold_their_declared_types(catalog))
	results.append(_test_every_gps_row_says_where_its_numbers_came_from(catalog))
	results.append(_test_every_buzzer_row_says_where_its_numbers_came_from(catalog))
	results.append(_test_gps_entries_are_ordered_by_mass(catalog))
	results.append(_test_buzzer_entries_are_ordered_by_mass(catalog))
	results.append(_test_loader_refuses_a_mislabelled_row())
	results.append(_test_both_schemas_state_the_rules_they_are_for())
	results.append(_test_the_gps_catalog_expresses_both_a_mast_and_no_mast(catalog))
	results.append(_test_the_buzzer_catalog_expresses_both_power_sources(catalog))

	return results


## ROW ONE. Registration, asserted from the catalog's own side rather than by re-reading the files:
## a CATEGORY_FILES line that is absent, misspelled or pointed at the wrong path produces an EMPTY
## category, and an empty category makes every other check in this file pass on nothing.
static func _test_both_categories_load_and_return_by_id(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []

	if not catalog.load_errors.is_empty():
		problems.append("load errors: %s" % "; ".join(catalog.load_errors))
	# is_valid() refuses an empty category anywhere in CATEGORY_FILES, so it fails the moment either
	# new line is dropped OR either file stops parsing.
	if not catalog.is_valid():
		problems.append("catalog reports itself invalid")

	var counts := {}
	for category in ["gps", "buzzer"]:
		var rows := catalog.list_category(category)
		counts[category] = rows.size()
		if rows.is_empty():
			problems.append("%s loaded no parts — the CATEGORY_FILES line is missing or wrong" % category)
			continue
		# by_id is the lookup every caller actually uses; a row in by_category and absent from by_id
		# is selectable and then unresolvable.
		for row in rows:
			if catalog.get_part(str(row["part_id"])).is_empty():
				problems.append("%s: in the %s list and not in by_id" % [row["part_id"], category])

	# The plan asks for 4-5 GPS entries and 3-4 buzzers. Held as a floor rather than an exact count:
	# a file that shrank to one row would satisfy every other check in here.
	if int(counts.get("gps", 0)) < 4:
		problems.append("only %d gps rows; the plan asks for 4-5" % int(counts.get("gps", 0)))
	if int(counts.get("buzzer", 0)) < 3:
		problems.append("only %d buzzer rows; the plan asks for 3-4" % int(counts.get("buzzer", 0)))

	return TestResult.new(
		"gps.json and buzzers.json load through PartsCatalog and every row resolves by id",
		problems.is_empty(),
		"%d gps, %d buzzer rows, %s" % [int(counts.get("gps", 0)), int(counts.get("buzzer", 0)),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW TWO, GPS half. Every row, every field the schema declares, in the tier it declares it in.
static func _test_every_gps_row_carries_every_declared_field(catalog: PartsCatalog) -> TestResult:
	return _fields_for(catalog, "gps", GPS_SPECS, GPS_CATALOG)


## ROW TWO, buzzer half. Split from the GPS half rather than looped over both categories:
## feedback_loop_tests_hide_coverage — one file's rows going bad must not be able to hide behind
## the other file's, and a single result for both would fail once either way.
static func _test_every_buzzer_row_carries_every_declared_field(catalog: PartsCatalog) -> TestResult:
	return _fields_for(catalog, "buzzer", BUZZER_SPECS, BUZZER_CATALOG)


static func _fields_for(catalog: PartsCatalog, category: String, specs_required: Dictionary,
		catalog_required: Array) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	# Substrings, not exact keys, so "vendor_url", "price_usd" and "colour" are all caught. Both
	# files' _schema bans these by name and this is what holds them to it.
	var banned := ["colour", "color", "price", "cost", "vendor", "url", "link", "buy", "shop", "sku"]

	for part in catalog.list_category(category):
		checked += 1
		var specs: Dictionary = part.get("specs", {})
		var browsing: Dictionary = part.get("catalog", {})
		for field in specs_required:
			if not specs.has(field):
				problems.append("%s: specs missing %s" % [part["part_id"], field])
			# A physics field parked in the browsing block reads as present to a human and is
			# absent to every caller — the same silence a missing field would make, with none of
			# the noise.
			if browsing.has(field):
				problems.append("%s: %s is in catalog, where nothing reads it" % [part["part_id"], field])
		for field in catalog_required:
			# has(), not a truthiness test: loudness_db is legitimately null, and `get(field, "")`
			# would report a correctly-null row as missing.
			if not browsing.has(field):
				problems.append("%s: catalog missing %s" % [part["part_id"], field])
			if specs.has(field):
				problems.append("%s: %s is in specs, where it would read as physics" % [part["part_id"], field])
		if not part.has("mass_g") or float(part["mass_g"]) <= 0.0:
			problems.append("%s: no positive mass_g" % part["part_id"])
		if String(part.get("category", "")) != category:
			problems.append("%s: declares category %s" % [part["part_id"], part.get("category", "")])
		for block_name in ["specs", "catalog"]:
			for key in part.get(block_name, {}):
				for word in banned:
					if String(key).to_lower().contains(word):
						problems.append("%s: %s.%s is a banned field" % [part["part_id"], block_name, key])

	if checked == 0:
		problems.append("the %s category loaded no parts — this check would pass vacuously" % category)

	return TestResult.new(
		"every %s row carries every field its schema declares, in the right tier, and nothing banned" % category,
		problems.is_empty(),
		"%d rows checked, %s" % [checked,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## The type half of row two, and the reason it is a table rather than "specs hold numbers only" is
## in the header: `self_powered` is a boolean on purpose, and an exception carved out of a blanket
## rule describes the file instead of constraining it.
##
## GDScript types a JSON `0.0` as FLOAT and a JSON `0` as INT, and both are acceptable for a
## dimension — a contributor typing `6` rather than `6.0` is not a defect. A STRING is, and so is a
## bool where a number belongs, which is what this catches.
static func _test_spec_fields_hold_their_declared_types(catalog: PartsCatalog) -> TestResult:
	var declared := {"gps": GPS_SPECS, "buzzer": BUZZER_SPECS}
	var problems: Array[String] = []
	var checked := 0

	for category in declared:
		for part in catalog.list_category(category):
			var specs: Dictionary = part.get("specs", {})
			for field in specs:
				checked += 1
				var value = specs[field]
				if not declared[category].has(field):
					# An undeclared field in the PHYSICS tier is the one place extra fields are not
					# harmless: nothing reads it, and its presence claims something is modelled.
					problems.append("%s: specs.%s is not a declared field of %s" % [
						part["part_id"], field, category])
					continue
				var want: int = declared[category][field]
				if want == TYPE_BOOL and not (value is bool):
					problems.append("%s: specs.%s is %s, not a bool" % [
						part["part_id"], field, type_string(typeof(value))])
				elif want == TYPE_FLOAT and not (value is float or value is int):
					problems.append("%s: specs.%s is %s, not a number" % [
						part["part_id"], field, type_string(typeof(value))])
				elif want == TYPE_FLOAT and value is bool:
					problems.append("%s: specs.%s is a bool where a number belongs" % [
						part["part_id"], field])
				elif want == TYPE_FLOAT and float(value) < 0.0:
					problems.append("%s: specs.%s is negative (%.2f)" % [
						part["part_id"], field, float(value)])
	# loudness_db is the one browsing field with a shape worth holding: a published figure or null,
	# never a string and never zero. _schema's rule is null over an invention.
	for part in catalog.list_category("buzzer"):
		# has(), and NOT a sentinel default compared with ==: GDScript 4 raises on `float ==
		# String`, so `get("loudness_db", "missing") == "missing"` crashes the check on exactly the
		# rows that carry a published figure. Found the hard way in this slice.
		var browsing: Dictionary = part.get("catalog", {})
		if not browsing.has("loudness_db"):
			continue
		var loudness = browsing["loudness_db"]
		if loudness == null:
			continue
		if not (loudness is float or loudness is int) or float(loudness) <= 0.0:
			problems.append("%s: catalog.loudness_db is %s — a published figure or null, nothing else" % [
				part["part_id"], str(loudness)])

	if checked == 0:
		problems.append("no spec fields checked at all — this check would pass vacuously")

	return TestResult.new(
		"every gps and buzzer spec field holds its declared type — mast_height a number, self_powered a bool",
		problems.is_empty(),
		"%d spec fields checked, %s" % [checked,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW THREE, GPS half. Design §0 relaxed the bar on VALUES and not on honesty: a rough number is
## allowed, an unlabelled one is not. Every mass and every mast height in this file is a guess, so
## every row has to say the word.
static func _test_every_gps_row_says_where_its_numbers_came_from(catalog: PartsCatalog) -> TestResult:
	return _sources_for(catalog, "gps")


## ROW THREE, buzzer half. Split for the same reason row two is.
static func _test_every_buzzer_row_says_where_its_numbers_came_from(catalog: PartsCatalog) -> TestResult:
	return _sources_for(catalog, "buzzer")


static func _sources_for(catalog: PartsCatalog, category: String) -> TestResult:
	var problems: Array[String] = []
	var labelled := 0
	var rows := catalog.list_category(category)
	for part in rows:
		var source := String(part.get("source", ""))
		if source.length() < 40:
			problems.append("%s: no meaningful source string (%d chars)" % [
				part["part_id"], source.length()])
			continue
		if source.contains("ROUGH") or source.contains("class-typical"):
			labelled += 1
		else:
			problems.append("%s: source claims neither a published figure nor a rough one" % part["part_id"])
	# Every row in both files is at least partly class-typical — §9 says so of the masses and the
	# mast heights alike — and if that ever stops being true the count says so rather than the check
	# quietly weakening.
	if rows.is_empty():
		problems.append("the %s category loaded no parts — this check would pass vacuously" % category)
	elif labelled != rows.size():
		problems.append("%d of %d rows labelled rough or class-typical" % [labelled, rows.size()])
	return TestResult.new(
		"every %s row labels its numbers as rough or class-typical rather than presenting a guess as measured" % category,
		problems.is_empty(),
		"%d of %d rows labelled, %s" % [labelled, rows.size(),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW FOUR, GPS half. Catalog file order IS the dropdown order — PartsCatalog.by_category's own
## comment says so, and load_with_custom appends rather than sorts precisely so that the authored
## order survives. Nothing sorts these at display time, so the file is the only place the order
## can be right.
static func _test_gps_entries_are_ordered_by_mass(catalog: PartsCatalog) -> TestResult:
	return _mass_order_for(catalog, "gps")


## ROW FOUR, buzzer half.
static func _test_buzzer_entries_are_ordered_by_mass(catalog: PartsCatalog) -> TestResult:
	return _mass_order_for(catalog, "buzzer")


static func _mass_order_for(catalog: PartsCatalog, category: String) -> TestResult:
	var problems: Array[String] = []
	var rows := catalog.list_category(category)
	var pairs := 0
	for i in range(1, rows.size()):
		pairs += 1
		var previous := float(rows[i - 1]["mass_g"])
		var current := float(rows[i]["mass_g"])
		if current < previous:
			problems.append("%s (%.1f g) follows %s (%.1f g)" % [
				rows[i]["part_id"], current, rows[i - 1]["part_id"], previous])
	# One row has no adjacent pair and two identical rows would compare equal forever; the pair
	# count is part of the assertion so a file that shrank cannot pass by having nothing to compare.
	if pairs < 2:
		problems.append("only %d adjacent pairs in %s — this check would pass vacuously" % [pairs, category])
	return TestResult.new(
		"%s entries are authored in ascending mass, which is the order the rail shows them in" % category,
		problems.is_empty(),
		"%d adjacent pairs checked, %s" % [pairs,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW SIX of C1's table, and the branch that had NO coverage anywhere in tests/ before this slice.
##
## `_load_category` refuses an entry whose own `category` field disagrees with the category it is
## being loaded as. Every shipped file agrees with itself, so the only way to reach that branch is a
## file written to disagree — hence the fixture, following frames_with_custom_id.json's pattern
## including the `_schema` line saying it is a fixture and not a catalog file.
##
## Checks all three of the same things test_custom_frames.gd checks of the prefix branch: the
## mislabelled row is refused (absent from by_id), the refusal is SURGICAL rather than a file-level
## abort (the ordinary entry beside it still loads), and the refusal is REPORTED (load_errors names
## the offending id) rather than merely silent. A silent refusal is the dangerous one: a contributor
## copying a row between two files and forgetting to change its `category` would lose the part with
## nothing on screen to say so.
static func _test_loader_refuses_a_mislabelled_row() -> TestResult:
	var catalog := PartsCatalog.new()
	catalog._load_category("gps", MISLABELLED_FIXTURE)
	var mislabelled_rejected := not catalog.by_id.has("gps_fixture_mislabelled")
	var ordinary_loaded := catalog.by_id.has("gps_fixture_ordinary")
	var error_named := false
	for error in catalog.load_errors:
		if error.contains("gps_fixture_mislabelled"):
			error_named = true
	# The fixture must actually contain the disagreement, or all three clauses above hold trivially
	# against a file with nothing wrong in it.
	var fixture_disagrees := false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MISLABELLED_FIXTURE))
	if parsed is Dictionary:
		for entry in (parsed as Dictionary).get("parts", []):
			if str(entry.get("part_id", "")) == "gps_fixture_mislabelled" \
					and str(entry.get("category", "")) != "gps":
				fixture_disagrees = true
	return TestResult.new(
		"_load_category refuses an entry declaring the wrong category, names it, and keeps its neighbour",
		mislabelled_rejected and ordinary_loaded and error_named and fixture_disagrees,
		"mislabelled rejected: %s, ordinary loaded: %s, error named it: %s, fixture really disagrees: %s (load_errors: %s)" % [
			mislabelled_rejected, ordinary_loaded, error_named, fixture_disagrees, catalog.load_errors]
	)


## The `_schema` prose is the only documentation the next contributor gets, so it is held to what it
## claims — the same treatment test_battery_rail.gd and test_frame_materials.gd give theirs. Two
## clauses beyond the two-tier rule and the ban, and they are the point of these files: the schema
## has to say WHY `mast_height_mm` and `self_powered` exist, because a reader who does not know that
## will treat both as decoration and author them carelessly.
static func _test_both_schemas_state_the_rules_they_are_for() -> TestResult:
	var problems: Array[String] = []
	var lengths := {}

	for category in ["gps", "buzzer"]:
		var schema := PartsCatalog.schema_for(category)
		lengths[category] = schema.length()
		if schema.length() < 200:
			problems.append("%s carries no meaningful _schema block (%d chars)" % [category, schema.length()])
			continue
		# Case-insensitive: the house voice starts the ban sentence with "Colour, price and vendor
		# links are banned by name", so an exact-case search for "colour" fails on a correct file.
		for word in ["specs", "catalog", "colour", "price", "vendor"]:
			if not schema.to_lower().contains(word):
				problems.append("%s _schema never says \"%s\"" % [category, word])

	var gps_schema := PartsCatalog.schema_for("gps")
	# Design §2.3: the mast is why the category exists, and the words that carry it are the mass
	# being above the plate and the centre of mass moving vertically.
	for phrase in ["mast_height_mm", "ABOVE THE TOP PLATE", "VERTICALLY", "EDITABLE DEFAULT"]:
		if not gps_schema.contains(phrase):
			problems.append("gps _schema never says \"%s\" — §2.3's reason for the field" % phrase)
	if not gps_schema.contains("navigation"):
		problems.append("gps _schema never says navigation is unmodelled")

	var buzzer_schema := PartsCatalog.schema_for("buzzer")
	# Design §2.4: the field is for the moment the pack ejects, and loudness_db is carried and not
	# modelled — the same sentence capacitors.json writes about esr_ohm.
	for phrase in ["self_powered", "SILENT THE MOMENT THE PACK DISCONNECTS", "loudness_db"]:
		if not buzzer_schema.contains(phrase):
			problems.append("buzzer _schema never says \"%s\" — §2.4's reason for the field" % phrase)
	if not buzzer_schema.contains("READ BY NO CHECK"):
		problems.append("buzzer _schema never says loudness_db is carried and not modelled")

	return TestResult.new(
		"both _schema blocks state the two-tier rule, the ban, and why mast_height_mm and self_powered exist",
		problems.is_empty(),
		"gps %d chars, buzzer %d chars, %s" % [int(lengths.get("gps", 0)), int(lengths.get("buzzer", 0)),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW SEVEN, and it is not padding. Design §2.3's whole argument is that a masted GPS moves the
## vertical centre of mass more than anything else fitted — and C2's check for that compares a
## masted module against a flat one of equal mass. A file where every `mast_height_mm` were 0 would
## leave that check with nothing to compare and no way to fail, while staying green.
##
## Asserted as a SPREAD rather than as values: which rows are flat and how tall the stalks are is a
## §0 default and will be retuned. That there is one of each is structural and will not.
static func _test_the_gps_catalog_expresses_both_a_mast_and_no_mast(catalog: PartsCatalog) -> TestResult:
	var flat: Array[String] = []
	var masted: Array[String] = []
	var problems: Array[String] = []
	for part in catalog.list_category("gps"):
		var mast := float(part.get("specs", {}).get("mast_height_mm", -1.0))
		if mast < 0.0:
			problems.append("%s: no mast_height_mm at all" % part["part_id"])
		elif mast == 0.0:
			flat.append(str(part["part_id"]))
		else:
			masted.append(str(part["part_id"]))
	if flat.is_empty():
		problems.append("no flat GPS: every row has a mast, so §2.3's comparison has no baseline")
	if masted.is_empty():
		problems.append("no masted GPS: nothing in the file puts mass above the top plate")
	return TestResult.new(
		"the gps catalog offers both a flat module (mast_height_mm 0) and a masted one (> 0)",
		problems.is_empty(),
		"%d flat %s, %d masted %s, %s" % [flat.size(), str(flat), masted.size(), str(masted),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW EIGHT, same argument from the other side. Design §6.2's warning fires on a fitted buzzer with
## `self_powered` false and must stay quiet on one with true. A file where every row were true would
## make the warning untestable in the firing direction; every row false, untestable in the quiet
## direction. Both are needed and both are asserted here rather than in C6, so the data defect is
## caught in the slice that authored the data.
static func _test_the_buzzer_catalog_expresses_both_power_sources(catalog: PartsCatalog) -> TestResult:
	var own_cell: Array[String] = []
	var fc_powered: Array[String] = []
	var problems: Array[String] = []
	for part in catalog.list_category("buzzer"):
		var specs: Dictionary = part.get("specs", {})
		if not specs.has("self_powered"):
			problems.append("%s: no self_powered at all" % part["part_id"])
		elif bool(specs["self_powered"]):
			own_cell.append(str(part["part_id"]))
		else:
			fc_powered.append(str(part["part_id"]))
	if own_cell.is_empty():
		problems.append("no self-powered buzzer: §6.2's warning has nothing it must stay quiet on")
	if fc_powered.is_empty():
		problems.append("no FC-powered buzzer: §6.2's warning has nothing it must fire on")
	return TestResult.new(
		"the buzzer catalog offers both a self-powered module and one that dies with the pack",
		problems.is_empty(),
		"%d with their own cell %s, %d on the FC's rail %s, %s" % [own_cell.size(), str(own_cell),
			fc_powered.size(), str(fc_powered),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)
