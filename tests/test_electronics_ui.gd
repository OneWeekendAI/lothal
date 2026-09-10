class_name TestElectronicsUi
extends RefCounted
## The four components LTHL-11 took out of the electronics lump, as far as a builder can reach
## them: the Electronics rail in Lab, the panel that reports what the payload costs, and the four
## dropdowns on Sim's BUILD panel.
##
## The model already knew about cameras, VTXs, antennas and receivers before any of this existed —
## Build.from_ids took a `component_ids` dictionary and nothing ever passed one, so every aircraft
## in both rooms flew DEFAULT_COMPONENT_IDS and the 21 g the carve-out exposed was unreachable.
## That is the specific failure these tests exist to prevent coming back: a selector that renders
## but does not reach the Build is indistinguishable from this slice never having been written.
##
## NOT FITTED IS THE INTERESTING CASE and it is why a plain dropdown over the catalog will not do.
## Build draws a distinction between a category left OUT of `component_ids` (fit the default) and a
## category set to "" (fit nothing), and those two differ by the whole of that component's mass. A
## rail that can only name parts can express one of them, so every list here carries an explicit
## "Not fitted" entry and the tests below check that choosing it reaches the aircraft as "".

## How much lighter an aircraft may be than another before we call it a real difference. Well
## under the lightest single component in any of the four catalogs (a 1.0 g nano receiver), so a
## component silently failing to reach the Build cannot hide under it.
const MASS_EPSILON_G := 0.05

## Each section, by name, so a section that produces NOTHING is reported instead of vanishing.
##
## This guard is here because it already happened, on the way to writing these tests: a runtime
## error partway through a section aborted it, its four assertions were never appended, and the
## suite returned the other fourteen and passed. run_tests.gd catches a suite that produces no
## results at all — the same reasoning, one level up — but a section dying inside a suite that
## still returns something is invisible to it, and "the aircraft actually changes when you use
## the rail" was exactly the section that disappeared.
## Called by name rather than dispatched dynamically: `TestElectronicsUi.call(name, catalog)` over
## a table of section names reads better and hangs the headless runner outright.
static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	var sections := {
		"rail lists and defaults": _test_rail_lists_and_defaults(catalog),
		"not fitted reaches the build": _test_not_fitted_reaches_the_build(catalog),
		"the rail moves the aircraft": _test_the_rail_moves_the_aircraft(catalog),
		"details panel": _test_details_panel(catalog),
		"the payload crosses into sim": _test_the_payload_crosses_into_sim(catalog),
		"build panel dropdowns": _test_build_panel_dropdowns(catalog),
	}

	var silent: Array = []
	for section in sections:
		var produced: Array = sections[section]
		if produced.is_empty():
			silent.append(section)
		results.append_array(produced)

	results.append(TestResult.new(
		"every section of this suite produced assertions",
		silent.is_empty(),
		"produced nothing: %s" % ("none" if silent.is_empty() else ", ".join(silent))
	))

	return results


# ---------------------------------------------------------------------------
# The rail
# ---------------------------------------------------------------------------

static func _test_rail_lists_and_defaults(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var rail := ElectronicsPicker.new(catalog)

	# Data-driven over Build.OPTIONAL_COMPONENTS rather than naming the four categories, so a
	# fifth component added to the model shows up here as a failure rather than as silence.
	var missing: Array = []
	var miscounted: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		if not rail.has_category(category):
			missing.append(category)
			continue
		# Every part in the category, plus the one "Not fitted" row.
		var expected := catalog.list_category(category).size() + 1
		if rail.options_for(category).size() != expected:
			miscounted.append("%s %d != %d" % [
				category, rail.options_for(category).size(), expected])

	results.append(TestResult.new(
		"the rail carries every optional component category",
		missing.is_empty(),
		"missing: %s" % ("none" if missing.is_empty() else ", ".join(missing))
	))

	results.append(TestResult.new(
		"each list is the catalog plus exactly one \"not fitted\" row",
		miscounted.is_empty(),
		"counts: %s" % ("all correct" if miscounted.is_empty() else ", ".join(miscounted))
	))

	# "Not fitted" is FIRST, and that is not cosmetic: it is the row a builder reaches for to
	# answer "what is this costing me", so it must not be at the bottom of a scrolled list.
	var not_first: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		if rail.options_for(category)[0] != "":
			not_first.append(category)
	results.append(TestResult.new(
		"\"not fitted\" is the first row in every list",
		not_first.is_empty(),
		"not first on: %s" % ("none" if not_first.is_empty() else ", ".join(not_first))
	))

	# The rail opens on what Build would have fitted anyway, so opening Lab and touching nothing
	# is the same aircraft it was before this rail existed. If these disagree, every stat in Lab
	# moves the day the rail is added and nothing says why.
	results.append(TestResult.new(
		"the rail opens on Build's own default components",
		rail.component_ids() == Build.DEFAULT_COMPONENT_IDS,
		"rail %s vs Build %s" % [rail.component_ids(), Build.DEFAULT_COMPONENT_IDS]
	))

	rail.free()
	return results


static func _test_not_fitted_reaches_the_build(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var rail := ElectronicsPicker.new(catalog)

	for category in Build.OPTIONAL_COMPONENTS:
		rail.select_component(category, "")

	results.append(TestResult.new(
		"choosing \"not fitted\" everywhere is exactly Build.no_components()",
		rail.component_ids() == Build.no_components(),
		"rail %s" % [rail.component_ids()]
	))

	# The arithmetic, end to end: a stripped aircraft is lighter than a fitted one by the sum of
	# the four parts' OWN masses — not by their budget shares, which are what the lump was carved
	# by and are deliberately not what a fitted part weighs.
	var fitted := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, Build.DEFAULT_COMPONENT_IDS)
	var stripped := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, rail.component_ids())

	var expected_drop := 0.0
	for category in Build.OPTIONAL_COMPONENTS:
		expected_drop += float(catalog.get_part(
			Build.DEFAULT_COMPONENT_IDS[category]).get("mass_g", 0.0))
	var actual_drop := fitted.all_up_weight_g() - stripped.all_up_weight_g()

	results.append(TestResult.new(
		"stripping the payload drops exactly the four parts' own masses",
		absf(actual_drop - expected_drop) < MASS_EPSILON_G and expected_drop > 0.0,
		"dropped %.2f g, four parts weigh %.2f g" % [actual_drop, expected_drop]
	))

	rail.free()
	return results


# ---------------------------------------------------------------------------
# The rail reaches the aircraft
# ---------------------------------------------------------------------------

## The claim the whole slice rests on: a selection on the rail changes the aircraft Lab reports,
## draws and hands to Sim. A rail wired to nothing passes every test above and fails this one.
static func _test_the_rail_moves_the_aircraft(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	var before := lab.current_build()
	var before_weight := before.all_up_weight_g()

	results.append(TestResult.new(
		"Lab opens with the default payload fitted",
		before.components.size() == Build.OPTIONAL_COMPONENTS.size(),
		"%d of %d components fitted" % [
			before.components.size(), Build.OPTIONAL_COMPONENTS.size()]
	))

	# Take the camera off. Chosen because it is the heaviest of the four shares and the one with
	# the largest catalog spread, so the change is unmistakable at the epsilon above.
	var camera_mass := float(before.components["camera"].get("mass_g", 0.0))
	lab.electronics_picker.select_component("camera", "")
	var after := lab.current_build()

	results.append(TestResult.new(
		"removing the camera on the rail removes it from Lab's build",
		not after.components.has("camera")
			and absf((before_weight - after.all_up_weight_g()) - camera_mass) < MASS_EPSILON_G,
		"AUW %.2f -> %.2f g, camera weighs %.2f g" % [
			before_weight, after.all_up_weight_g(), camera_mass]
	))

	# And the centre of mass follows it. This is the consequence LTHL-11 named — the components
	# are what put the CoM 0.18 mm aft — so a rail that changed the weight but not the balance
	# would be reporting a mass it is not actually placing anywhere.
	results.append(TestResult.new(
		"and moves the centre of mass, because the camera sat somewhere",
		absf(after.mass_properties.com_m.z - before.mass_properties.com_m.z) > 1e-6,
		"CoM z %.6f -> %.6f m" % [before.mass_properties.com_m.z, after.mass_properties.com_m.z]
	))

	# Put a DIFFERENT camera on, rather than putting the original back: swapping between two real
	# parts is the common case, and it is the one an "is it fitted at all" boolean would pass.
	var cameras := catalog.list_category("camera")
	var heaviest: Dictionary = cameras[0]
	for part in cameras:
		if float(part["mass_g"]) > float(heaviest["mass_g"]):
			heaviest = part
	lab.electronics_picker.select_component("camera", heaviest["part_id"])
	var swapped := lab.current_build()

	results.append(TestResult.new(
		"swapping to a heavier camera is worth exactly the difference",
		swapped.components.get("camera", {}).get("part_id", "") == heaviest["part_id"]
			and absf((swapped.all_up_weight_g() - after.all_up_weight_g())
				- float(heaviest["mass_g"])) < MASS_EPSILON_G,
		"AUW %.2f -> %.2f g fitting a %.1f g camera" % [
			after.all_up_weight_g(), swapped.all_up_weight_g(), float(heaviest["mass_g"])]
	))

	lab.free()
	return results


# ---------------------------------------------------------------------------
# The panel that reports it
# ---------------------------------------------------------------------------

static func _test_details_panel(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var panel := ElectronicsDetails.new()

	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, Build.DEFAULT_COMPONENT_IDS)
	panel.render_components(build)
	var text := panel.rendered_text()

	# Every fitted component names itself and its mass. Asserted by reading back what the panel
	# RENDERED rather than what the build holds — the panel's whole job is putting the number on
	# screen, and checking the build here would test the catalog twice and the panel not at all.
	var unreported: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		var part_name := str(build.components[category].get("name", ""))
		if not text.contains(part_name):
			unreported.append(category)
	results.append(TestResult.new(
		"the panel names every fitted component",
		unreported.is_empty(),
		"unreported: %s" % ("none" if unreported.is_empty() else ", ".join(unreported))
	))

	# The total is the model's own electronics_mass_g(), not a sum the panel does itself. A second
	# adding-up in the UI is a second answer, and the budget is the one number here that must not
	# have two of them.
	results.append(TestResult.new(
		"the reported total is the model's electronics mass",
		panel.detail_text({}, "total") == "%.1f g" % build.electronics_mass_g(),
		"panel says %s, model says %.1f g" % [
			panel.detail_text({}, "total"), build.electronics_mass_g()]
	))

	# The harness is shown as its own row. It used to be a flat 14 g of the 55 and it is now weighed
	# off the build's own gauges and lengths (PW2), which makes the row MORE worth having rather than
	# less: a builder looking at a whoop's mass budget can now see a harness that is actually that
	# whoop's. (parts.md, and LTHL-43.)
	results.append(TestResult.new(
		"the harness is a visible row of its own, at the build's own harness mass",
		panel.detail_text({}, "wiring") == "%.1f g" % build.harness_mass_g()
			and text.to_lower().contains("wiring"),
		"wiring row %s vs %.1f g; panel:\n%s" % [
			panel.detail_text({}, "wiring"), build.harness_mass_g(), text]
	))

	# An empty bay reads as empty, not as 0 g and not as an em dash: "0 g" is a component that
	# weighs nothing and "—" is a value nobody filled in, and neither of those is "you did not
	# fit one".
	var stripped := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, Build.no_components())
	panel.render_components(stripped)

	# Read row by row rather than searching the whole panel for "0.0 g": the total row legitimately
	# renders something like "40.0 g", which contains "0.0 g" as a substring, so a text search here
	# would fail on a panel that is perfectly correct.
	var wrong_empty: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		var row := panel.detail_text({}, category)
		if row != ElectronicsDetails.NOT_FITTED_TEXT:
			wrong_empty.append("%s=%s" % [category, row])
	results.append(TestResult.new(
		"an unfitted component reads as not fitted, not as 0 g and not as a dash",
		wrong_empty.is_empty(),
		"wrong: %s" % ("none" if wrong_empty.is_empty() else ", ".join(wrong_empty))
	))

	# The wiring and the total are still real on a stripped aircraft — the budget did not go away
	# because the bays are empty, and the total must have dropped by exactly what came off.
	results.append(TestResult.new(
		"the total follows the model down when the bays are emptied",
		panel.detail_text({}, "total") == "%.1f g" % stripped.electronics_mass_g()
			and stripped.electronics_mass_g() < build.electronics_mass_g(),
		"stripped total row %s, model %.1f g (fitted %.1f g)" % [
			panel.detail_text({}, "total"), stripped.electronics_mass_g(),
			build.electronics_mass_g()]
	))

	panel.free()
	return results


# ---------------------------------------------------------------------------
# The door into Sim
# ---------------------------------------------------------------------------

## labs-and-sim.md §4: the field flies exactly the Build the garage assembled. A payload that
## stops at Lab's door is the same bug as a frame that does, and it is quieter — the aircraft
## still flies, it just flies with someone else's camera on it.
static func _test_the_payload_crosses_into_sim(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	lab.electronics_picker.select_component("camera", "")
	lab.electronics_picker.select_component("vtx", "")
	var selection := lab.selection()

	var carried: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		if not selection.has(category):
			carried.append(category)
	results.append(TestResult.new(
		"the selection crossing the door names every component category",
		carried.is_empty(),
		"absent from selection(): %s" % ("none" if carried.is_empty() else ", ".join(carried))
	))

	# "" has to survive the trip. This is the one that a `selection.get(category, DEFAULT)` on the
	# far side breaks silently: the key is present, the value is empty, and a fallback written for
	# a MISSING key happily replaces it with a camera the builder took off.
	results.append(TestResult.new(
		"an unfitted component crosses as \"\" rather than being defaulted back on",
		selection.get("camera", "?") == "" and selection.get("vtx", "?") == "",
		"camera=%s vtx=%s" % [selection.get("camera", "?"), selection.get("vtx", "?")]
	))

	var panel := BuildPanel.new(catalog, selection)
	panel._rebuild()

	results.append(TestResult.new(
		"Sim's panel, opened on that selection, flies the same aircraft Lab assembled",
		absf(panel.build.all_up_weight_g() - lab.current_build().all_up_weight_g())
			< MASS_EPSILON_G,
		"Sim %.2f g vs Lab %.2f g" % [
			panel.build.all_up_weight_g(), lab.current_build().all_up_weight_g()]
	))

	panel.free()
	lab.free()
	return results


static func _test_build_panel_dropdowns(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# A PARTIAL hand-over, which is the normal case for a direct load of main.tscn: nothing names
	# the components, so the panel must fall back to the fitted defaults rather than to nothing.
	var panel := BuildPanel.new(catalog, {
		"frame": ReferenceBuild.FRAME_ID,
		"motor": ReferenceBuild.MOTOR_ID,
		"propeller": ReferenceBuild.PROPELLER_ID,
		"battery": ReferenceBuild.BATTERY_ID,
	})
	panel._rebuild()

	results.append(TestResult.new(
		"a selection naming no components still opens on the reference 507.5 g aircraft",
		absf(panel.build.all_up_weight_g() - 507.48) < 1.0
			and panel.build.components.size() == Build.OPTIONAL_COMPONENTS.size(),
		"%.1f g with %d components" % [
			panel.build.all_up_weight_g(), panel.build.components.size()]
	))

	var missing: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		if not panel._selectors.has(category):
			missing.append(category)
	results.append(TestResult.new(
		"Sim's BUILD panel has a dropdown for every component",
		missing.is_empty(),
		"missing: %s" % ("none" if missing.is_empty() else ", ".join(missing))
	))

	# Drive it the way a click does, through the same handler the signal is connected to.
	var emitted: Array = []
	panel.build_changed.connect(func(b: Build) -> void: emitted.append(b))
	var before_weight := panel.build.all_up_weight_g()
	var receiver_mass := float(panel.build.components["receiver"].get("mass_g", 0.0))
	var selector: OptionButton = panel._selectors["receiver"]
	selector.select(0)                      # the "Not fitted" row
	panel._on_selection_changed(0, "receiver")

	results.append(TestResult.new(
		"taking the receiver off in Sim re-emits a lighter aircraft",
		emitted.size() == 1 and not panel.build.components.has("receiver")
			and absf((before_weight - panel.build.all_up_weight_g()) - receiver_mass)
				< MASS_EPSILON_G,
		"%d emit(s), AUW %.2f -> %.2f g, receiver weighs %.2f g" % [
			emitted.size(), before_weight, panel.build.all_up_weight_g(), receiver_mass]
	))

	# The index shift is the trap this last one guards. Every component dropdown has a row the
	# catalog does not — so `list_category(category)[selector.selected]` is off by one for the
	# whole of these four lists, and off-by-one over a list of similar small parts fits the wrong
	# component without ever looking wrong.
	var cameras := catalog.list_category("camera")
	var last_index := cameras.size()        # the final row: "Not fitted" + every camera
	panel._selectors["camera"].select(last_index)
	panel._on_selection_changed(last_index, "camera")

	results.append(TestResult.new(
		"the last row of a component list is the last part, not one past it",
		panel.build.components.get("camera", {}).get("part_id", "")
			== cameras[cameras.size() - 1]["part_id"],
		"selected %s, expected %s" % [
			panel.build.components.get("camera", {}).get("part_id", "(none)"),
			cameras[cameras.size() - 1]["part_id"]]
	))

	panel.free()
	return results
