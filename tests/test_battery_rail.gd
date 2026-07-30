class_name TestBatteryRail
extends RefCounted
## The pack, made choosable (labs-and-sim.md §2.1). Until this slice Lothal had four selectable
## categories on paper and three in the interface: the battery was pinned to the reference pack
## and every number that depends on it was therefore a number about one pack.
##
## The assertions here are chosen so that a decorative rail fails. A picker that lists twelve
## packs and emits a signal nobody acts on would look completely finished, so the checks below
## are almost all about CONSEQUENCE — that choosing a different pack moves the mass, the
## thrust-to-weight and the flight time, that it moves them on every panel at once, and that the
## pack crosses the door into the bench and into the field with the rest of the build.
##
## The catalog checks are the other half. batteries.json is the file this slice doubled, and the
## two-tier rule it moved onto is easy to state and easy to erode — the next contributor adding a
## pack has nothing stopping them putting a price in `catalog` except a test that objects.
##
## Every Control built here is freed, or the runner emits leaked-RID ERROR lines that read like
## failures.

## Admitted browsing fields. A `catalog` block may hold these and nothing else: each is a
## factual, checkable property of the real product AND is needed to navigate a shelf of packs.
const ADMITTED_CATALOG_FIELDS := ["cell_class", "c_rating", "connector"]

## Physics-bearing fields every pack must carry. `chemistry` is here rather than in the catalog
## block because it selects the discharge curve (physics.md §5).
const REQUIRED_SPEC_FIELDS := ["cells", "nominal_v", "mah", "internal_r_ohm", "chemistry"]

## Banned by name from both blocks, per every catalog file's own `_schema`. Checked as substrings
## of the key so "vendor_url" and "price_inr" are caught as readily as "price".
const BANNED_FIELD_SUBSTRINGS := ["colour", "color", "price", "cost", "vendor", "retailer",
	"url", "link", "buy", "stock"]

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_the_catalog(catalog))
	results.append_array(_test_the_catalog_spans_what_the_frames_need(catalog))
	results.append_array(_test_the_rail_moves_the_build(catalog))
	results.append_array(_test_the_pack_crosses_the_doors(catalog))

	return results


# ---------------------------------------------------------------------------
# The catalog
# ---------------------------------------------------------------------------

static func _test_the_catalog(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var packs: Array = catalog.list_category("battery")

	results.append(TestResult.new(
		"the battery catalog is deep enough to need a rail rather than a dropdown",
		packs.size() >= 12,
		"%d packs" % packs.size()
	))

	var missing: Array = []
	for pack in packs:
		for field in REQUIRED_SPEC_FIELDS:
			if not pack.get("specs", {}).has(field):
				missing.append("%s lacks specs.%s" % [pack["part_id"], field])
		for field in ADMITTED_CATALOG_FIELDS:
			if not pack.get("catalog", {}).has(field):
				missing.append("%s lacks catalog.%s" % [pack["part_id"], field])
		if str(pack.get("source", "")) == "":
			missing.append("%s cites no source" % pack["part_id"])
	results.append(TestResult.new(
		"every pack carries the full two-tier schema and cites where its numbers came from",
		missing.is_empty(),
		"%d packs complete" % packs.size() if missing.is_empty() else "; ".join(missing)
	))

	# The `catalog` block is browsing metadata and admits nothing else. Stated as a closed set
	# rather than as a ban list, because the failure worth catching is a contributor adding a
	# field nobody thought to forbid.
	var intruders: Array = []
	for pack in packs:
		for key in pack.get("catalog", {}):
			if not ADMITTED_CATALOG_FIELDS.has(key):
				intruders.append("%s.catalog.%s" % [pack["part_id"], key])
	results.append(TestResult.new(
		"the catalog block holds only the fields admitted for browsing, and nothing else",
		intruders.is_empty(),
		"admitted: %s" % ", ".join(ADMITTED_CATALOG_FIELDS) if intruders.is_empty() else "; ".join(intruders)
	))

	var banned: Array = []
	for pack in packs:
		for block in ["specs", "catalog"]:
			for key in pack.get(block, {}):
				for word in BANNED_FIELD_SUBSTRINGS:
					if String(key).to_lower().contains(word):
						banned.append("%s.%s.%s" % [pack["part_id"], block, key])
	results.append(TestResult.new(
		"colour, price and vendor stay banned by name from both blocks",
		banned.is_empty(),
		"checked %d packs against %d banned words" % [packs.size(), BANNED_FIELD_SUBSTRINGS.size()]
			if banned.is_empty() else "; ".join(banned)
	))

	# The file's own _schema has to say the rule out loud, since that string is what the next
	# contributor reads and the only thing standing between them and a price field.
	var schema := PartsCatalog.schema_for("battery")
	results.append(TestResult.new(
		"batteries.json states the two-tier rule and the ban in its own _schema",
		schema.contains("specs") and schema.contains("catalog")
			and schema.to_lower().contains("banned")
			and schema.to_lower().contains("chemistry"),
		"_schema is %d characters and names specs, catalog, the ban and chemistry" % schema.length()
	))

	return results


## The rail has to cover the span the frame rail already covers, or choosing a whoop leaves you
## with nothing to put in it. And the Li-ion entries have to be genuinely different in the one
## way that matters, or the catalog's most instructive comparison is a label rather than a fact.
static func _test_the_catalog_spans_what_the_frames_need(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var packs: Array = catalog.list_category("battery")

	var cell_counts: Array = []
	for pack in packs:
		var cells := int(pack["specs"]["cells"])
		if not cell_counts.has(cells):
			cell_counts.append(cells)
	cell_counts.sort()

	results.append(TestResult.new(
		"the rail runs from whoop packs to 6S, so every frame in the catalog has something to fly on",
		cell_counts.has(1) and cell_counts.has(2) and cell_counts.has(4) and cell_counts.has(6),
		"cell counts stocked: %s" % ", ".join(PackedStringArray(cell_counts.map(func(c): return "%dS" % c)))
	))

	# The Li-ion's whole reason to be in the catalog: far more capacity, far worse internal
	# resistance. If either half of that stops being true the pack becomes a strictly better
	# LiPo and the lesson the battery bench is built to teach quietly evaporates.
	#
	# Compared against the LiPos of the SAME cell count, not against the whole shelf. A 1S whoop
	# pack legitimately runs at 90 mΩ because it is tiny, and measuring the Li-ion against that
	# would compare a chemistry against a size and report the wrong thing passing or failing.
	var liion_count := 0
	var comparisons: Array = []
	var trade_holds := true
	for pack in packs:
		if str(pack["specs"]["chemistry"]) != "Li-ion":
			continue
		liion_count += 1

		var cells := int(pack["specs"]["cells"])
		var worst_peer_r := 0.0
		var biggest_peer_mah := 0.0
		for peer in packs:
			if int(peer["specs"]["cells"]) != cells or str(peer["specs"]["chemistry"]) == "Li-ion":
				continue
			worst_peer_r = maxf(worst_peer_r, float(peer["specs"]["internal_r_ohm"]))
			biggest_peer_mah = maxf(biggest_peer_mah, float(peer["specs"]["mah"]))

		var r := float(pack["specs"]["internal_r_ohm"])
		var mah := float(pack["specs"]["mah"])
		if worst_peer_r <= 0.0 or r < worst_peer_r * 5.0 or mah < biggest_peer_mah * 2.0:
			trade_holds = false
		comparisons.append("%s: %.0f mΩ vs %.0f mΩ and %.0f mAh vs %.0f mAh at %dS" % [
			pack["name"], r * 1000.0, worst_peer_r * 1000.0, mah, biggest_peer_mah, cells])

	results.append(TestResult.new(
		"each Li-ion trades internal resistance for capacity against the LiPos of its own cell count",
		liion_count >= 2 and trade_holds,
		"; ".join(comparisons)
	))

	return results


# ---------------------------------------------------------------------------
# The consequence: a pack change moves the aircraft
# ---------------------------------------------------------------------------

## The check a decorative rail fails. Everything else about a picker can be right — the list, the
## filters, the signal — and the build still be assembled on a pack pinned in code, which is
## exactly the state this slice found the project in.
static func _test_the_rail_moves_the_build(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new())

	results.append(TestResult.new(
		"Lab has a battery rail at all, alongside the frame, motor and propeller rails",
		lab.battery_picker != null and lab.battery_picker.visible_parts().size() >= 12,
		"battery rail lists %d packs" % (
			lab.battery_picker.visible_parts().size() if lab.battery_picker != null else -1)
	))

	lab.battery_picker.select_id("battery_4s_1500")
	var light := lab.current_build()
	var light_weight := light.all_up_weight_g()
	var light_twr := light.thrust_to_weight()
	var light_time := light.flight_time_min()
	var light_shown: String = lab.details._stat_values["weight"].text

	lab.battery_picker.select_id("battery_6s_4000_liion")
	var heavy := lab.current_build()

	results.append(TestResult.new(
		"the build is assembled on the pack the rail is showing, not on a pack pinned in code",
		light.battery["part_id"] == "battery_4s_1500"
			and heavy.battery["part_id"] == "battery_6s_4000_liion",
		"rail said battery_6s_4000_liion, build says %s" % heavy.battery["part_id"]
	))

	results.append(TestResult.new(
		"changing the pack moves all-up weight, thrust-to-weight and flight time together",
		heavy.all_up_weight_g() > light_weight + 100.0
			and not is_equal_approx(heavy.thrust_to_weight(), light_twr)
			and not is_equal_approx(heavy.flight_time_min(), light_time),
		"%.0f g -> %.0f g, %.1f:1 -> %.1f:1, %.1f min -> %.1f min" % [
			light_weight, heavy.all_up_weight_g(), light_twr, heavy.thrust_to_weight(),
			light_time, heavy.flight_time_min()]
	))

	# ...and it moves them on every panel at once. The five derived stats are the aircraft's,
	# not the pack's, so a pack change has to reach the frame panel as surely as the battery one.
	var heavy_shown: String = lab.details._stat_values["weight"].text
	var motor_shown: String = lab.motor_details._stat_values["weight"].text
	results.append(TestResult.new(
		"a pack change reaches the frame and motor panels too, not just the battery one",
		heavy_shown != light_shown and motor_shown == heavy_shown,
		"frame panel %s -> %s, motor panel %s" % [light_shown, heavy_shown, motor_shown]
	))

	# Every value on the battery panel has to trace back to batteries.json rather than being
	# spelled out in code — the same claim test_lab.gd makes of the frame panel.
	var pack: Dictionary = catalog.get_part("battery_6s_4000_liion")
	var expectations := {
		"mass_g": "%.0f" % float(pack["mass_g"]),
		"nominal_v": "%.1f" % float(pack["specs"]["nominal_v"]),
		"mah": "%.0f" % float(pack["specs"]["mah"]),
		"chemistry": str(pack["specs"]["chemistry"]),
		"cell_class": str(pack["catalog"]["cell_class"]),
		"c_rating": str(pack["catalog"]["c_rating"]),
		"connector": str(pack["catalog"]["connector"]),
	}
	var untraced: Array = []
	for key in expectations:
		var shown: String = lab.battery_details._detail_values[key].text
		if not shown.contains(expectations[key]):
			untraced.append("%s: \"%s\" lacks \"%s\"" % [key, shown, expectations[key]])
	results.append(TestResult.new(
		"every value on the battery panel traces back to batteries.json",
		untraced.is_empty(),
		"all %d fields match the JSON" % expectations.size() if untraced.is_empty() else "; ".join(untraced)
	))

	# The chemistry filter is the first in the project to read a `specs` field, so the rail has
	# to actually narrow on it rather than silently matching everything against an empty string.
	lab.battery_picker.set_filter("chemistry", "Li-ion")
	var liion_only: Array = lab.battery_picker.visible_parts()
	var all_liion := not liion_only.is_empty()
	for entry in liion_only:
		if str(entry["specs"]["chemistry"]) != "Li-ion":
			all_liion = false
	results.append(TestResult.new(
		"the chemistry filter reads specs rather than the catalog block, and narrows on it",
		all_liion and liion_only.size() < catalog.list_category("battery").size(),
		"%d of %d packs are Li-ion" % [liion_only.size(), catalog.list_category("battery").size()]
	))

	lab.free()
	return results


# ---------------------------------------------------------------------------
# The pack crosses into the bench and into the field
# ---------------------------------------------------------------------------

## labs-and-sim.md §4: the build crosses from Lab to Sim, whole. A pack that stayed behind while
## the frame, motor and propeller went through the door would be the most convincing kind of bug —
## everything on screen correct, and the aircraft flying on a battery nobody chose.
static func _test_the_pack_crosses_the_doors(_catalog: PartsCatalog) -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.lab.battery_picker.select_id("battery_6s_1300")

	shell.show_bench()
	results.append(TestResult.new(
		"the thrust stand runs on the pack chosen on Lab's rail, not on the reference pack",
		shell.bench.current_build().battery["part_id"] == "battery_6s_1300",
		"benching %s" % shell.bench.current_build().battery["name"]
	))

	shell.show_lab()
	shell.show_sim()
	results.append(TestResult.new(
		"the pack goes through the door into the field with the rest of the build",
		shell.sim.initial_selection.get("battery", "") == "battery_6s_1300",
		"Sim was handed %s" % shell.sim.initial_selection
	))

	shell.show_lab()
	shell.free()
	return results
