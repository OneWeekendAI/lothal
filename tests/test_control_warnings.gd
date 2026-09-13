class_name TestControlWarnings
extends RefCounted
## `ControlPlausibility`, `LinkDetails` and the GPS mast field — control-room design §5 and §6,
## slice C6.
##
## THE CHECK THAT MATTERS MOST IN THIS FILE ASSERTS THE ABSENCE OF A CLAIM, which is an odd shape
## for a test and is the honest one here. No board in `flight_controllers.json` publishes a UART
## count and none ever has, so the serial-port row states how many fitted parts WANT a port and
## says the board's own number is unpublished. The failure mode it guards is not a wrong number —
## it is a CONFIDENT one, a headroom figure derived from a count nobody published, wearing a
## measurement's confidence. Design §0 relaxed the bar on values and not on that.

## The catalog rows these checks fit. Named here so a catalog edit that removed one fails loudly at
## the top rather than silently weakening every row below.
const MASTED_GPS := "gps_masted_long_range"
const FLAT_GPS := "gps_micro_flat"
const FC_POWERED_BUZZER := "buzz_active_5v"
const SELF_POWERED_BUZZER := "buzz_selfpowered_cell"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_the_fixtures_are_really_in_the_catalog(catalog))
	results.append_array(_test_the_panel_says_not_fitted_and_reads_its_total_from_the_model(catalog))
	results.append_array(_test_the_receiver_row_moved_panels(catalog))
	results.append_array(_test_the_mast_moves_the_centre_of_mass_and_is_stored_as_typed(catalog))
	results.append_array(_test_no_receiver_warns(catalog))
	results.append_array(_test_a_buzzer_on_the_fc_rail_warns(catalog))
	results.append_array(_test_the_port_row_states_a_count_and_never_a_headroom(catalog))
	results.append(_test_every_control_warning_carries_its_values(catalog))

	return results


## The vacuity guard. Every fixture below names a catalog row by id, and an id that stopped
## existing would make `_build_with` fit nothing — turning "the warning does not fire" into a pass
## for the wrong reason on almost every row in this file.
static func _test_the_fixtures_are_really_in_the_catalog(catalog: PartsCatalog) -> TestResult:
	var missing: Array[String] = []
	for id in [MASTED_GPS, FLAT_GPS, FC_POWERED_BUZZER, SELF_POWERED_BUZZER]:
		if catalog.get_part(id).is_empty():
			missing.append(id)

	# And the two buzzers really must differ in the field the whole §6.2 warning turns on.
	var fc_powered := catalog.get_part(FC_POWERED_BUZZER)
	var self_powered := catalog.get_part(SELF_POWERED_BUZZER)
	var differ := (not fc_powered.is_empty() and not self_powered.is_empty()
		and not bool((fc_powered["specs"] as Dictionary).get("self_powered", true))
		and bool((self_powered["specs"] as Dictionary).get("self_powered", false)))

	return TestResult.new(
		"the fixtures this file names are in the catalog, and the two buzzers really do differ",
		missing.is_empty() and differ,
		"missing %s, differ=%s" % ["none" if missing.is_empty() else ", ".join(missing), differ])


## §5 — an empty bay reads `not fitted`, and the total is the model's.
##
## `not fitted` rather than `0 g` (a component that weighs nothing) and rather than the em dash
## PartDetails uses for a field nobody filled in. Neither of those is "you did not fit one", and
## that distinction is the entire reason the rail next door exists.
static func _test_the_panel_says_not_fitted_and_reads_its_total_from_the_model(
		catalog: PartsCatalog) -> Array:
	var results: Array = []

	# ALL THREE BAYS EMPTY, which `_build_with` is not — it always fits a receiver, because every
	# other row in this file needs one. A "no bay is fitted" check run against a build with one
	# fitted is a check on two bays wearing the name of three.
	var empty := _build_without_receiver(catalog)
	var panel := LinkDetails.new()
	panel.render_components(empty)
	var text := _panel_text(panel, LinkDetails.SPEC_ROWS)

	# PER BAY, not "somewhere in the panel". Asserting the phrase appears anywhere passes while the
	# bay rows say something else entirely, because the mast and own-power rows use the same words —
	# which is exactly what the em-dash mutation proved before this check was written this way.
	for category in LinkDetails.BAYS:
		var row := panel.row_text(category)
		results.append(TestResult.new(
			"an empty %s bay reads \"not fitted\", not \"0 g\" and not an em dash" % category,
			row == LinkDetails.NOT_FITTED_TEXT,
			"the %s row reads \"%s\" (whole panel: %s)" % [category, row, text]))

	var fitted := _build_with(catalog, MASTED_GPS, SELF_POWERED_BUZZER)
	panel.render_components(fitted)
	var fitted_text := _panel_text(panel, LinkDetails.SPEC_ROWS)

	# The total the panel PRINTS against the total the build computes. Read back off the rendering
	# rather than off the panel's helper, because the thing being asserted is what a builder sees.
	var expected := 0.0
	for category in LinkDetails.BAYS:
		if fitted.components.has(category):
			expected += float(fitted.components[category].get("mass_g", 0.0))

	results.append(TestResult.new(
		"the Link total on screen is the sum of the model's own fitted masses",
		fitted_text.contains("%.1f g" % expected) and expected > 0.0,
		"expected %.1f g in: %s" % [expected, fitted_text]))

	return results


## §5 — the receiver is reported by exactly one panel, and it is Control's.
##
## Both halves, because either alone is satisfiable by the wrong thing: gone from Electronics and
## absent from Link is a component nothing reports, and present in both is the same component
## counted twice on screen.
static func _test_the_receiver_row_moved_panels(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var build := _build_with(catalog, "", "")
	var rx_name := str(build.components["receiver"].get("name", ""))

	var electronics := ElectronicsDetails.new()
	electronics.render_components(build)
	var link := LinkDetails.new()
	link.render_components(build)

	var electronics_text := _panel_text(electronics, ElectronicsDetails.SPEC_ROWS)
	var link_text := _panel_text(link, LinkDetails.SPEC_ROWS)

	results.append(TestResult.new(
		"the receiver is gone from ElectronicsDetails",
		not electronics_text.contains(rx_name) and rx_name != "",
		"Electronics says: %s" % electronics_text))

	results.append(TestResult.new(
		"and it is named in LinkDetails instead",
		link_text.contains(rx_name),
		"Link says: %s" % link_text))

	return results


## §2.3 and §6 — the mast is the reason a GPS is modelled rather than added to the harness
## remainder, and the field beside it is what a builder actually sets.
##
## The centre-of-mass half is asserted against the amount `AirframeProperties.compute` returns, by
## comparing two builds that differ ONLY in the mast — not by re-deriving the moment here, which
## would be a second answer to a question the mass model must have exactly one of.
##
## The unclamped half is the one the plan asks for in those words. 250 mm is beyond any mast in the
## catalog (the tallest is 70 mm) and is a DRAWING bound rather than a plausibility judgement: a
## builder who types a real number must never be argued with by an app that has no measurement.
static func _test_the_mast_moves_the_centre_of_mass_and_is_stored_as_typed(
		catalog: PartsCatalog) -> Array:
	var results: Array = []

	var flat := _build_with(catalog, FLAT_GPS, "")
	var masted := _build_with(catalog, MASTED_GPS, "")

	results.append(TestResult.new(
		"a masted GPS puts the centre of mass higher than a flat one does",
		masted.mass_properties.com_m.y > flat.mass_properties.com_m.y,
		"flat %.9f m, masted %.9f m" % [flat.mass_properties.com_m.y, masted.mass_properties.com_m.y]))

	# The builder's value overrides the catalog's, and the mass model reads it.
	var raised := _build_with(catalog, FLAT_GPS, "", 120.0)
	results.append(TestResult.new(
		"typing a mast height raises the fitted module by that amount, over the catalog's own",
		absf(raised.rise_m_for(raised.components["gps"]) - 0.120) < 1e-9
			and raised.mass_properties.com_m.y > flat.mass_properties.com_m.y,
		"rise %.6f m (catalog says %.6f), CoM %.9f m against the flat build's %.9f" % [
			raised.rise_m_for(raised.components["gps"]),
			Build.component_rise_m(raised.components["gps"]),
			raised.mass_properties.com_m.y, flat.mass_properties.com_m.y]))

	# Stored AS TYPED. A tweak the app quietly shrank to something it found plausible would be the
	# app overruling a measurement it does not have.
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.MAST_HEIGHT, 250.0)
	var stored := tweaks.value_mm(AssemblyTweaks.MAST_HEIGHT, flat)
	results.append(TestResult.new(
		"a mast height far beyond the catalog's tallest is stored exactly as typed",
		absf(stored - 250.0) < 1e-6,
		"typed 250.0 mm, stored %.3f mm (catalog's tallest mast is 70 mm)" % stored))

	return results


## §6.1 — the one warning that catches an aircraft nobody can fly.
static func _test_no_receiver_warns(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var without := _build_without_receiver(catalog)
	var with_rx := _build_with(catalog, "", "")

	results.append(TestResult.new(
		"a build with no receiver is told nothing receives the sticks",
		_has(without, &"no_receiver"),
		"warnings: %s" % [_ids(without)]))

	results.append(TestResult.new(
		"and a build with one is not",
		not _has(with_rx, &"no_receiver"),
		"warnings: %s" % [_ids(with_rx)]))

	# It must name the AIO case, because Lothal cannot tell that case apart and saying so is the
	# difference between a prompt and a false accusation.
	var warning := _find(without, &"no_receiver")
	results.append(TestResult.new(
		"and the warning names the AIO case rather than pretending to a check it cannot make",
		warning != null and warning.message.to_lower().contains("aio"),
		"message: %s" % ["<missing>" if warning == null else warning.message]))

	return results


## §6.2 — a buzzer that goes silent with the pack.
static func _test_a_buzzer_on_the_fc_rail_warns(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var on_rail := _build_with(catalog, "", FC_POWERED_BUZZER)
	var own_cell := _build_with(catalog, "", SELF_POWERED_BUZZER)
	var none := _build_with(catalog, "", "")

	results.append(TestResult.new(
		"a buzzer wired to the flight controller is warned about",
		_has(on_rail, &"buzzer_not_self_powered"),
		"warnings: %s" % [_ids(on_rail)]))

	results.append(TestResult.new(
		"a buzzer with its own cell is not",
		not _has(own_cell, &"buzzer_not_self_powered"),
		"warnings: %s" % [_ids(own_cell)]))

	# Not fitting one at all is NOT a fault — a racer over concrete does not need one, and a
	# warning that fires on every build is a warning nobody reads.
	results.append(TestResult.new(
		"and no buzzer at all is not warned about, because that is a legitimate build",
		not _has(none, &"buzzer_not_self_powered"),
		"warnings: %s" % [_ids(none)]))

	return results


## §6.3 — THE HONESTY CHECK, and the one this slice is most likely to get wrong by being helpful.
##
## The row states a COUNT of fitted parts wanting a serial port. It must never state how many ports
## the board has, or how many are left, because nothing in this catalog knows. Asserted as the
## absence of a claim: no headroom key in `values`, and the message says the count is unpublished.
static func _test_the_port_row_states_a_count_and_never_a_headroom(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var both := _build_with(catalog, MASTED_GPS, SELF_POWERED_BUZZER)
	var warning := _find(both, &"serial_peripherals")

	# A receiver and a GPS are two; the buzzer is on a beeper pad and must not be counted.
	results.append(TestResult.new(
		"the port row counts the receiver and the GPS, and does not count the buzzer",
		warning != null and int(warning.values.get("serial_peripherals", -1)) == 2,
		"counted %s with a buzzer also fitted" % [
			"<missing>" if warning == null else warning.values.get("serial_peripherals", -1)]))

	results.append(TestResult.new(
		"and it says the board's own port count is not published in this catalog",
		warning != null and warning.message.contains(ControlPlausibility.PORTS_UNPUBLISHED),
		"message: %s" % ["<missing>" if warning == null else warning.message]))

	# THE ABSENCE OF THE CLAIM. Any of these keys appearing means somebody has taught the row to
	# assert a number no board publishes.
	var claimed: Array[String] = []
	if warning != null:
		for key in ["uarts", "uart_ports", "ports", "ports_available", "headroom", "ports_free",
				"spare_ports", "uarts_available"]:
			if warning.values.has(key):
				claimed.append(key)

	results.append(TestResult.new(
		"and it states no port count, no headroom and nothing else it cannot know",
		warning != null and claimed.is_empty(),
		"values carries %s; forbidden keys present: %s" % [
			"<missing>" if warning == null else str(warning.values.keys()),
			"none" if claimed.is_empty() else str(claimed)]))

	return results


## The house rule every Power check follows: a warning quotes the numbers it was computed from, so
## a consumer can present them without a second derivation that could drift from the sentence.
static func _test_every_control_warning_carries_its_values(catalog: PartsCatalog) -> TestResult:
	var build := _build_without_receiver(catalog)
	build = Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID,
		{"camera": "", "vtx": "", "antenna": "", "receiver": "",
			"gps": MASTED_GPS, "buzzer": FC_POWERED_BUZZER})

	var empty: Array[String] = []
	var seen := 0
	for warning in ControlPlausibility.warnings_for(build):
		seen += 1
		if warning.values.is_empty():
			empty.append(String(warning.id))

	# All three must be present on this build, or the check is passing on fewer warnings than it
	# thinks it is inspecting.
	return TestResult.new(
		"every control warning carries the values it was computed from",
		seen == 3 and empty.is_empty(),
		"%d warnings, empty values on %s" % [seen, "none" if empty.is_empty() else ", ".join(empty)])


# ---------------------------------------------------------------------------

## Everything the panel would put on screen, as one string. `PartDetails` has no "give me the whole
## rendering" accessor — it answers per row — so the rows are read back through `row_text`, which
## is the same call the panel's own layout makes.
static func _panel_text(panel: PartDetails, rows: Array) -> String:
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s: %s" % [row["label"], panel.row_text(String(row["key"]))])
	return " | ".join(parts)


## The reference build with the two Control bays set, and the mast optionally overridden. Built
## through `Build.from_ids` so the whole production path runs rather than a components dictionary
## being assembled by hand.
static func _build_with(catalog: PartsCatalog, gps_id: String, buzzer_id: String,
		mast_mm: float = -1.0) -> Build:
	var assembly := {}
	if mast_mm >= 0.0:
		assembly = {"mast_height_m": mast_mm / 1000.0}
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID,
		{"camera": "", "vtx": "", "antenna": "", "receiver": "rx_elrs_2400",
			"gps": gps_id, "buzzer": buzzer_id})
	if not assembly.is_empty():
		build.assembly = assembly
		build._recompute()
	return build


static func _build_without_receiver(catalog: PartsCatalog) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID,
		{"camera": "", "vtx": "", "antenna": "", "receiver": "", "gps": "", "buzzer": ""})


static func _find(build: Build, id: StringName) -> BuildWarning:
	for warning in ControlPlausibility.warnings_for(build):
		if warning.id == id:
			return warning
	return null


static func _has(build: Build, id: StringName) -> bool:
	return _find(build, id) != null


static func _ids(build: Build) -> Array:
	var out: Array = []
	for warning in ControlPlausibility.warnings_for(build):
		out.append(String(warning.id))
	return out
