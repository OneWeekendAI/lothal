class_name TestPowerParts
extends RefCounted
## connectors.json and capacitors.json — PW1's two parts files.
##
## THE JOIN IS THE ONE THAT MATTERS HERE, and it is the first test below. Two files that each look
## fine and do not join is the defect this slice was most likely to ship: PW3's connector
## compatibility check is a string comparison between a pack's `catalog.connector` and a lead's
## `catalog.family`, and if the two spellings never match, that check passes on every build forever
## and nothing on screen looks wrong. So it is asserted in BOTH directions — every family a pack
## uses has a row, and every row's family either appears on a pack or declares that it does not.
##
## The field checks are here rather than in test_parts_system.gd's required-field table on purpose:
## these two categories name their own required fields, in the file that also asserts what those
## fields mean, so a field added to the schema prose and forgotten in a row fails in one place.

## The fields every connector row must carry, split by tier. `specs` is physics-bearing;
## `catalog` is browsing metadata. A field in the wrong block is as wrong as a field missing.
const CONNECTOR_SPECS := ["continuous_a", "burst_a", "contact_resistance_ohm", "pigtail_mass_g"]
const CONNECTOR_CATALOG := ["family", "shipped_on_packs", "typical_use"]
const CAPACITOR_SPECS := ["capacitance_uf", "voltage_v", "esr_ohm", "diameter_mm", "height_mm"]
const CAPACITOR_CATALOG := ["cell_range", "dielectric"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_every_connector_family_joins_to_a_pack(catalog))
	results.append(_test_every_row_carries_every_declared_field(catalog))
	results.append(_test_both_categories_load_and_return_by_id(catalog))
	results.append(_test_specs_hold_numbers_only(catalog))
	results.append(_test_every_row_says_where_its_numbers_came_from(catalog))
	results.append(_test_ratings_and_sizes_are_ordered_and_sane(catalog))

	return results


## ROW THREE, and the reason this slice has a test file of its own.
##
## Both directions, because each catches a different mistake. Forwards: a pack terminating in a
## family nothing here offers is a pack that can never be checked for compatibility. Backwards: a
## row claiming shipped_on_packs while no pack spells it that way is a misspelling — XT-60 for
## XT60, "BT2.0 " with a space — which is invisible in a diff and fatal to a string comparison.
##
## The vacuity guard matters more here than usual: two EMPTY sets join perfectly.
static func _test_every_connector_family_joins_to_a_pack(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []

	var pack_families := {}
	for battery in catalog.list_category("battery"):
		var spelling := String(battery.get("catalog", {}).get("connector", ""))
		if spelling == "":
			problems.append("%s: no catalog.connector at all" % battery["part_id"])
			continue
		pack_families[spelling] = true

	var lead_families := {}
	for connector in catalog.list_category("connector"):
		var family := String(connector.get("catalog", {}).get("family", ""))
		var claims_packs: bool = bool(connector.get("catalog", {}).get("shipped_on_packs", false))
		lead_families[family] = true
		if claims_packs and not pack_families.has(family):
			problems.append("%s: claims shipped_on_packs but no pack spells its connector \"%s\"" % [
				connector["part_id"], family])
		if not claims_packs and pack_families.has(family):
			problems.append("%s: says shipped_on_packs false, but a pack does terminate in \"%s\"" % [
				connector["part_id"], family])

	# The forward half. A pack in a family with no row here cannot be compatibility-checked at all.
	for family in pack_families:
		if not lead_families.has(family):
			problems.append("packs terminate in \"%s\" and connectors.json has no such family" % family)

	# Two empty sets join. Neither may be empty.
	if pack_families.is_empty() or lead_families.is_empty():
		problems.append("one side of the join is empty (%d pack families, %d connector rows) — this check would pass vacuously" % [
			pack_families.size(), lead_families.size()])

	return TestResult.new(
		"every connector family joins: packs' catalog.connector and connectors' catalog.family are one spelling",
		problems.is_empty(),
		"%d pack families %s against %d connector rows, %s" % [pack_families.size(),
			str(pack_families.keys()), lead_families.size(),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW FOUR. Every row, every field the schema declares, in the tier it declares it in.
static func _test_every_row_carries_every_declared_field(catalog: PartsCatalog) -> TestResult:
	var required := {
		"connector": [CONNECTOR_SPECS, CONNECTOR_CATALOG],
		"capacitor": [CAPACITOR_SPECS, CAPACITOR_CATALOG],
	}
	var problems: Array[String] = []
	var checked := 0

	for category in required:
		for part in catalog.list_category(category):
			checked += 1
			var specs: Dictionary = part.get("specs", {})
			var browsing: Dictionary = part.get("catalog", {})
			for field in required[category][0]:
				if not specs.has(field):
					problems.append("%s: specs missing %s" % [part["part_id"], field])
				# A physics field parked in the browsing block reads as present to a human and is
				# absent to every caller — the same silence a missing field would make, with none
				# of the noise.
				if browsing.has(field):
					problems.append("%s: %s is in catalog, where nothing reads it" % [part["part_id"], field])
			for field in required[category][1]:
				if not browsing.has(field):
					problems.append("%s: catalog missing %s" % [part["part_id"], field])
			if not part.has("mass_g") or float(part["mass_g"]) <= 0.0:
				problems.append("%s: no positive mass_g" % part["part_id"])
		if catalog.list_category(category).is_empty():
			problems.append("the %s category loaded no parts — this check would pass vacuously" % category)

	return TestResult.new(
		"every connector and capacitor row carries every field its schema declares, in the right tier",
		problems.is_empty(),
		"%d rows checked, %s" % [checked,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## ROW FIVE. Registration, asserted from the catalog's own side rather than by re-reading the files:
## a CATEGORY_FILES line that is absent, misspelled or pointed at the wrong path produces an empty
## category, and an empty category makes every other check in this file pass on nothing.
static func _test_both_categories_load_and_return_by_id(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []

	if not catalog.load_errors.is_empty():
		problems.append("load errors: %s" % "; ".join(catalog.load_errors))
	# is_valid() refuses an empty category anywhere in CATEGORY_FILES, so it fails the moment either
	# new line is dropped OR either file stops parsing.
	if not catalog.is_valid():
		problems.append("catalog reports itself invalid")

	for category in ["connector", "capacitor"]:
		var rows := catalog.list_category(category)
		if rows.is_empty():
			problems.append("%s loaded no parts — the CATEGORY_FILES line is missing or wrong" % category)
			continue
		# by_id is the lookup everything downstream actually uses, and it is a FLAT dictionary
		# across categories, so a part that lists but does not look up is a part a build cannot fit.
		for row in rows:
			var fetched := catalog.get_part(String(row["part_id"]))
			if fetched.is_empty():
				problems.append("%s lists but does not resolve through by_id" % row["part_id"])
			elif String(fetched.get("category", "")) != category:
				problems.append("%s resolves to category %s" % [row["part_id"], fetched.get("category", "")])
		# And the schema prose has to be there for the next contributor.
		if PartsCatalog.schema_for(category).length() < 200:
			problems.append("%s carries no meaningful _schema block" % category)

	return TestResult.new(
		"connector and capacitor both load through PartsCatalog and return by id",
		problems.is_empty(),
		"connector %d rows, capacitor %d rows, %s" % [
			catalog.list_category("connector").size(), catalog.list_category("capacitor").size(),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## `specs` is numbers physics reads. A string in there is a browsing field that got smuggled in, and
## it will be silently read as 0.0 by the first thing that floats it — the failure mode batteries.json
## already paid for once, when c_rating was the string "75C" and the pack current limit was zero.
static func _test_specs_hold_numbers_only(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	for category in ["connector", "capacitor"]:
		for part in catalog.list_category(category):
			for field in part.get("specs", {}):
				checked += 1
				var value = part["specs"][field]
				if not (value is float or value is int):
					problems.append("%s: specs.%s is %s, not a number" % [
						part["part_id"], field, type_string(typeof(value))])
	if checked == 0:
		problems.append("no spec fields checked at all — this check would pass vacuously")
	return TestResult.new(
		"nothing but numbers lives in specs — no browsing field smuggled into the physics tier",
		problems.is_empty(),
		"%d spec fields checked, %s" % [checked,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## Design §0 relaxed the bar on VALUES and not on honesty: a rough number is allowed, an unlabelled
## one is not. Every row says where its numbers came from and whether it is class-typical rather
## than a specific product — and the rows whose numbers really are guesses have to say the word.
static func _test_every_row_says_where_its_numbers_came_from(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var rough_rows := 0
	for category in ["connector", "capacitor"]:
		for part in catalog.list_category(category):
			var source := String(part.get("source", ""))
			if source.length() < 40:
				problems.append("%s: no meaningful source string" % part["part_id"])
				continue
			if source.contains("ROUGH") or source.contains("class-typical"):
				rough_rows += 1
			else:
				problems.append("%s: source claims neither a published figure nor a rough one" % part["part_id"])
	# Every row in both files is at least partly class-typical, and if that ever stops being true the
	# count says so rather than the check quietly weakening.
	if rough_rows != catalog.list_category("connector").size() + catalog.list_category("capacitor").size():
		problems.append("%d rows labelled rough or class-typical, of %d" % [rough_rows,
			catalog.list_category("connector").size() + catalog.list_category("capacitor").size()])
	return TestResult.new(
		"every connector and capacitor row labels its numbers as published or as class-typical",
		problems.is_empty(),
		"%d rows labelled, %s" % [rough_rows,
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## The typo guard, and the one physical constraint in either file that is not a matter of taste.
##
## A capacitor run above its rated voltage fails — not sags, fails — so a 6S-labelled part below
## 25.2 V is a shipped mistake. And burst must never be BELOW continuous: it is carried and never
## read as a limit, which means nothing else would ever notice it had been transposed.
static func _test_ratings_and_sizes_are_ordered_and_sane(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []

	for connector in catalog.list_category("connector"):
		var specs: Dictionary = connector["specs"]
		if float(specs["burst_a"]) < float(specs["continuous_a"]):
			problems.append("%s: burst %.0f A is below continuous %.0f A" % [
				connector["part_id"], specs["burst_a"], specs["continuous_a"]])
		# Sub-milliohm to a few milliohms. A contact resistance in the ohms would swamp the whole
		# harness, which is precisely the magnitude §3.5 says it does not have.
		var r := float(specs["contact_resistance_ohm"])
		if r <= 0.0 or r > 0.01:
			problems.append("%s: contact resistance %.4f ohm is outside milliohms" % [connector["part_id"], r])

	for cap in catalog.list_category("capacitor"):
		var specs: Dictionary = cap["specs"]
		var cells := String(cap.get("catalog", {}).get("cell_range", ""))
		# 6S rests at 22.2 V and comes off the charger at 25.2. Anything claiming 6S must clear that.
		if cells.contains("6S") and float(specs["voltage_v"]) < 25.2:
			problems.append("%s: claims %s at only %.0f V, under a 6S pack's 25.2 V full charge" % [
				cap["part_id"], cells, specs["voltage_v"]])
		if float(specs["esr_ohm"]) <= 0.0 or float(specs["diameter_mm"]) <= 0.0 or float(specs["height_mm"]) <= 0.0:
			problems.append("%s: a non-positive ESR or dimension" % cap["part_id"])

	# The §3.4 rule needs something in its band and something outside it, or the check it feeds has
	# never been shown to fire.
	var in_band := 0
	for cap in catalog.list_category("capacitor"):
		var uf := float(cap["specs"]["capacitance_uf"])
		if uf >= 470.0 and uf <= 1000.0 and float(cap["specs"]["voltage_v"]) >= 35.0:
			in_band += 1
	if in_band < 2:
		problems.append("only %d caps sit in the 470-1000 uF / 35 V band the §3.4 rule names" % in_band)

	return TestResult.new(
		"connector burst never sits below continuous, and no capacitor is rated under the pack it claims",
		problems.is_empty(),
		"%d connectors, %d capacitors (%d in the 6S band), %s" % [
			catalog.list_category("connector").size(), catalog.list_category("capacitor").size(),
			in_band, "no problems" if problems.is_empty() else "; ".join(problems)]
	)
