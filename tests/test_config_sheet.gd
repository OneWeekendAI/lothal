class_name TestConfigSheet
extends RefCounted
## Config room slice C9 — THE CONFIG SHEET, the artifact that leaves the room. Design:
## plans/2026-09-20-config-room-design.md §3, and `2026-08-17-build-sheet-design.md`, whose
## decisions this reuses rather than re-argues.
##
## The build sheet's design settled five things and every one of them applies here unchanged:
##
##   §2.1 — ONE ARTIFACT CARRYING BOTH HALVES. The settings to type and the verdict on them ship
##     together. A list of numbers with no warnings beside it is a game output wearing a
##     spreadsheet's clothes.
##
##   §2.4 — CONFIDENCE IS PER-CLAIM, IN THE SOURCE'S OWN WORDS. No aggregate score; that
##     antipattern has been rejected three times in this project now. Every figure on this sheet
##     arrives with the provenance ITS OWN MODULE attached, and the sheet PASTES that sentence
##     WHOLE. C5, C6 and C8 each wrote that rule into their module headers for the same reason:
##     a caller that picks the number out and writes its own sentence is exactly how a guess
##     loses its label. Off-screen and in someone's hands, that loss is unrecoverable — they are
##     at a bench with a soldering iron and no way to ask.
##
##   §2.5 — THE ARTIFACT IS A DATED MARKDOWN FILE, and its BODY IS DETERMINISTIC. A sheet whose
##     body varies run to run cannot be the pre-registration §2.5 says it is, because there is no
##     single set of predictions to be held to. Only the date may vary.
##
##   §4 — EMITTING AUTHORS NOTHING. The build sheet asserts `PackCharge` is untouched across an
##     emission; the config sheet's equivalent is that the drone's `config` block is byte-identical
##     afterwards. Writing a sheet is reading, and a sheet that tidied a setting on its way past
##     would change an aircraft by being printed.
##
##   §7 — A BAD PATH DEGRADES. `write` returns false; it does not crash the room.
##
## WHAT THIS SLICE REFUSES, and both are the design's refusals rather than new ones: it invents no
## sentence of its own for a figure another module owns, and it blocks nothing. Every warning is
## printed at the severity it already has.


## A board with no published `uart_range`, so the sheet meets `PortBudget.UNPUBLISHED`.
const NO_RANGE_FC_ID := "fc_f405_30x30"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_every_modules_sentence_is_pasted_whole(catalog))
	results.append_array(_provenance_travels_with_the_figure(catalog))
	results.append_array(_an_unpublished_port_count_is_never_a_number(catalog))
	results.append_array(_the_tune_ships_with_its_boundary(catalog))
	results.append_array(_the_motor_map_comes_from_the_one_accessor(catalog))
	results.append_array(_the_body_is_deterministic(catalog))
	results.append_array(_emitting_authors_nothing(catalog))
	results.append_array(_every_warning_reaches_the_sheet(catalog))
	results.append_array(_the_sheet_says_lothal_never_ran_these_settings(catalog))
	results.append_array(_writing_lands_and_a_bad_path_degrades(catalog))
	results.append_array(_the_panel_previews_and_writes_nothing(catalog))
	return results


# ---------------------------------------------------------------------------
# §2.4 — the sentences, pasted whole
# ---------------------------------------------------------------------------

## ONE RESULT PER SENTENCE rather than a loop, so the failure count says how many of them went
## missing rather than just that one did.
static func _every_modules_sentence_is_pasted_whole(catalog: PartsCatalog) -> Array:
	var results: Array = []
	# A build with something to say in every section: a chosen rate that differs from the sim's, a
	# chosen failsafe, an expo, and fitted peripherals that want ports.
	var config := {"motor_spin": "props_in"}
	RateSettings.set_max_rate_deg_s(config, 400.0)
	RateSettings.set_expo(config, 0.35)
	FailsafeSettings.set_stage2(config, FailsafeSettings.LAND)
	var build := _build(catalog, {"receiver": "rx_elrs_2400", "gps": "gps_micro_flat"}, config)
	var sheet := ConfigSheet.body(build, "Bench quad")

	# ASKED OF THE PORTS SECTION, not of the whole sheet. The same string also arrives in the
	# warnings list, and a check against the whole document would stay green while the ports row
	# above it said something this file made up — which is the one failure C9 exists to prevent.
	results.append(TestResult.new(
		"the ports section pastes the ports sentence whole, with its provenance attached",
		_section(sheet, "Ports and UARTs").contains(_port_message(build)),
		_section(sheet, "Ports and UARTs").substr(0, 60)))

	results.append(TestResult.new(
		"the sheet pastes FailsafeSettings' stage-2 sentence whole",
		sheet.contains(FailsafeSettings.stage2_sentence(config)),
		FailsafeSettings.stage2_sentence(config)))

	results.append(TestResult.new(
		"the sheet pastes RateSettings' max-rate sentence whole",
		sheet.contains(RateSettings.max_rate_sentence(config)),
		RateSettings.max_rate_sentence(config)))

	results.append(TestResult.new(
		"the sheet pastes the sim-versus-real statement whole",
		sheet.contains(RateSettings.sim_versus_real_sentence(config)),
		RateSettings.sim_versus_real_sentence(config)))

	results.append(TestResult.new(
		"the sheet pastes the expo sentence whole, admission included",
		sheet.contains(RateSettings.expo_sentence(config)),
		RateSettings.expo_sentence(config)))

	results.append(TestResult.new(
		"the sheet pastes the modes sentence whole",
		sheet.contains(RateSettings.modes_sentence()),
		RateSettings.modes_sentence()))

	results.append(TestResult.new(
		"the sheet pastes the motor-order refusal whole",
		sheet.contains(ConfigMotorsPanel.REFUSAL),
		ConfigMotorsPanel.REFUSAL.substr(0, 60)))

	results.append(TestResult.new(
		"the sheet pastes the arming preamble whole",
		sheet.contains(ArmingNotes.preamble()),
		ArmingNotes.preamble().substr(0, 60)))

	var arming_lines := ArmingNotes.lines()
	var missing_arming: Array[String] = []
	for line in arming_lines:
		if not sheet.contains(line):
			missing_arming.append(line.substr(0, 40))
	results.append(TestResult.new(
		"every arming line reaches the sheet, each still ending in the disclaimer",
		missing_arming.is_empty() and not arming_lines.is_empty(),
		"%d lines, %d missing" % [arming_lines.size(), missing_arming.size()]))

	# The disclaimer is the one string C7 refused to reword per entry. If the sheet reflowed the
	# lines, this is what would go first.
	var carrying := 0
	for line in arming_lines:
		if sheet.contains(line) and line.ends_with(ArmingNotes.CANNOT_SEE):
			carrying += 1
	results.append(TestResult.new(
		"every arming line on the sheet still ends with \"Lothal cannot see the live flag\"",
		carrying == arming_lines.size(),
		"%d of %d" % [carrying, arming_lines.size()]))

	return results


# ---------------------------------------------------------------------------
# §2.4 — provenance, off-screen
# ---------------------------------------------------------------------------

## The same aircraft, twice, differing only in whether the builder typed their board's real port
## count. The sheet must read differently, and it must never present the guess as the measurement.
static func _provenance_travels_with_the_figure(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var guessed := _build(catalog, {"receiver": "rx_elrs_2400"}, {})
	var guessed_sheet := ConfigSheet.body(guessed, "Bench quad")
	var typed_config := {}
	PortBudget.set_count(typed_config, 6)
	var typed := _build(catalog, {"receiver": "rx_elrs_2400"}, typed_config)
	var typed_sheet := ConfigSheet.body(typed, "Bench quad")

	results.append(TestResult.new(
		"a class-typical port figure reaches the sheet labelled class-typical",
		guessed_sheet.contains("class-typical"),
		_port_message(guessed).substr(0, 80)))

	results.append(TestResult.new(
		"a typed port figure reads as the builder's own and drops the class-typical label",
		typed_sheet.contains("your figure for this build")
			and not typed_sheet.contains("class-typical figure"),
		_port_message(typed).substr(0, 80)))

	results.append(TestResult.new(
		"the two sheets differ, so the provenance is not lost by being off-screen",
		guessed_sheet != typed_sheet, "identical" if guessed_sheet == typed_sheet else "differ"))

	# The other provenance seam, C6's: an untouched failsafe must read as BETAFLIGHT's default on
	# the sheet, not as Lothal's advice. This is the one a builder acts on at a bench.
	var untouched := _build(catalog, {}, {})
	results.append(TestResult.new(
		"an untouched failsafe reads on the sheet as Betaflight's default, not Lothal's advice",
		ConfigSheet.body(untouched, "Bench quad").contains(
			"quoted as Betaflight's and not as Lothal's advice"),
		FailsafeSettings.stage2_sentence({})))

	# And C8's: an untouched rate is the SIM's number, labelled as the sim's.
	results.append(TestResult.new(
		"an untouched rate reads on the sheet as the sim's number, labelled as the sim's",
		ConfigSheet.body(untouched, "Bench quad").contains(
			"That is the rate the sim flies, not a reading from your build"),
		RateSettings.max_rate_sentence({})))

	return results


## `PortBudget.UNPUBLISHED` is the case where a zero would read as a count. The sheet must carry
## the module's own words for it and must not print a number of ports.
static func _an_unpublished_port_count_is_never_a_number(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, {"receiver": "rx_elrs_2400"}, {})
	# Strip the published range the way a custom board arrives without one.
	(build.fc["catalog"] as Dictionary).erase(PortBudget.CATALOG_KEY)
	var budget := PortBudget.for_build(build)
	var sheet := ConfigSheet.body(build, "Bench quad")

	results.append(TestResult.new(
		"an unpublished port count reaches the sheet as \"not published\", never as a figure",
		budget["provenance"] == PortBudget.UNPUBLISHED
			and sheet.contains(PortBudget.UNPUBLISHED_TEXT),
		str(budget["provenance"])))

	results.append(TestResult.new(
		"no verdict is printed when there is no figure behind it",
		not sheet.contains(" fits."),
		"verdict present" if sheet.contains(" fits.") else "silent"))

	return results


# ---------------------------------------------------------------------------
# §4.1 — the tune's export row, and the boundary in the sheet's own voice
# ---------------------------------------------------------------------------

## The gains are printed, because they are useful. The claim made about them is the WEAKER one the
## design specifies — the axis ratios are what the derivation is confident about — and a sheet that
## printed the numbers without it would be handing a builder Betaflight gains they are not.
static func _the_tune_ships_with_its_boundary(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, {}, {})
	var tune := RateTune.derive(build)
	var sheet := ConfigSheet.body(build, "Bench quad")
	var roll := tune.gains_for(0)

	results.append(TestResult.new(
		"the derived roll gains are on the sheet",
		sheet.contains("%.4f" % roll.x) and sheet.contains("%.4f" % roll.z),
		"P %.4f D %.4f" % [roll.x, roll.z]))

	results.append(TestResult.new(
		"the tune ships with the boundary that it is not a Betaflight tune",
		sheet.contains(ConfigSheet.TUNE_BOUNDARY)
			and ConfigSheet.TUNE_BOUNDARY.contains("starting point"),
		ConfigSheet.TUNE_BOUNDARY.substr(0, 80)))

	results.append(TestResult.new(
		"the boundary says the ratios between axes are the confident part",
		ConfigSheet.TUNE_BOUNDARY.contains("ratio"),
		ConfigSheet.TUNE_BOUNDARY))

	# §4.1 and §9: filters are refused, and the refusal must not quietly vanish at the one place a
	# builder would look for them — the sheet they are typing from.
	# The refusal itself, not merely the word. Something else on the sheet says "filter" in passing,
	# so a check for the word alone stayed green with the refusal deleted.
	results.append(TestResult.new(
		"the sheet recommends no filter setting and says that is deliberate",
		sheet.contains(ConfigSheet.FILTER_REFUSAL),
		ConfigSheet.FILTER_REFUSAL.substr(0, 60)))

	return results


## §4.3's map, read through the one accessor. Flipping the convention must flip the sheet.
static func _the_motor_map_comes_from_the_one_accessor(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var out_build := _build(catalog, {}, {"motor_spin": "props_out"})
	var in_build := _build(catalog, {}, {"motor_spin": "props_in"})
	var out_sheet := ConfigSheet.body(out_build, "Bench quad")
	var in_sheet := ConfigSheet.body(in_build, "Bench quad")

	var out_spin := MotorLayout.spin_map(out_build.config)
	var in_spin := MotorLayout.spin_map(in_build.config)
	var wrong: Array[String] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		var expect_out := "%s %s" % [motor_name,
			MotorLayout.direction_name(float(out_spin[motor_name]))]
		var expect_in := "%s %s" % [motor_name,
			MotorLayout.direction_name(float(in_spin[motor_name]))]
		if not out_sheet.contains(expect_out):
			wrong.append(expect_out)
		if not in_sheet.contains(expect_in):
			wrong.append(expect_in)
	results.append(TestResult.new(
		"every motor's direction on the sheet is the one the mixer flies",
		wrong.is_empty(), "missing %s" % [wrong]))

	results.append(TestResult.new(
		"choosing props-in changes the sheet, so the map is read and not hardcoded",
		out_sheet != in_sheet,
		"identical" if out_sheet == in_sheet else "differ"))

	return results


# ---------------------------------------------------------------------------
# §2.5 — determinism, and §4 — emitting authors nothing
# ---------------------------------------------------------------------------

static func _the_body_is_deterministic(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var config := {"motor_spin": "props_in"}
	RateSettings.set_max_rate_deg_s(config, 400.0)
	FailsafeSettings.set_bidir_dshot(config, true)
	var build := _build(catalog, {"receiver": "rx_elrs_2400", "gps": "gps_micro_flat"}, config)

	var first := ConfigSheet.body(build, "Bench quad")
	var second := ConfigSheet.body(build, "Bench quad")
	results.append(TestResult.new(
		"the sheet's body is identical run to run, so it can be a pre-registration",
		first == second, "identical" if first == second else "drifted"))

	# Only the date may vary. Two sheets a day apart must differ ONLY on the line carrying it.
	var monday := ConfigSheet.to_markdown(build, "Bench quad", "2026-09-21")
	var tuesday := ConfigSheet.to_markdown(build, "Bench quad", "2026-09-22")
	var differing := _differing_lines(monday, tuesday)
	results.append(TestResult.new(
		"two sheets a day apart differ on the dated line and nowhere else",
		differing.size() == 1 and String(differing[0]).contains("2026-09-21"),
		"%d lines differ: %s" % [differing.size(), differing]))

	# The date gets a LINE TO ITSELF, and the body has none. Both halves matter: a date welded onto
	# a line that also carries a figure makes the two sheets undiffable line by line, which is how
	# a body change hides behind the one difference that is expected.
	results.append(TestResult.new(
		"the date is a line of its own, so a body change cannot hide behind it",
		Array(monday.split("\n")).has("Written: 2026-09-21. Project schema %d.%d." % [
			ProjectSchema.SCHEMA_MAJOR, ProjectSchema.SCHEMA_MINOR]),
		monday.substr(0, 80)))

	results.append(TestResult.new(
		"the body carries no date at all, so it is the same document every run",
		not first.contains("2026-") and not first.contains("Written:"),
		first.substr(0, 80)))

	return results


## The build sheet's `PackCharge` check, one room over. Printing is reading.
static func _emitting_authors_nothing(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var config := {"motor_spin": "props_in"}
	RateSettings.set_max_rate_deg_s(config, 400.0)
	var build := _build(catalog, {"receiver": "rx_elrs_2400"}, config)
	var before := build.config.duplicate(true)

	ConfigSheet.to_markdown(build, "Bench quad", "2026-09-21")

	results.append(TestResult.new(
		"emitting a sheet writes nothing back into the drone's config block",
		build.config == before, "%s against %s" % [build.config, before]))

	return results


# ---------------------------------------------------------------------------
# §2.1 — the verdict travels with the settings
# ---------------------------------------------------------------------------

static func _every_warning_reaches_the_sheet(catalog: PartsCatalog) -> Array:
	var results: Array = []
	# A per-motor map that cannot fly: C2's own check fires, and it must be ON the sheet.
	var build := _build(catalog, {}, {"motor_spin": {"M1": 1.0, "M2": 1.0, "M3": 1.0, "M4": 1.0}})
	var sheet := ConfigSheet.body(build, "Bench quad")

	var warnings := build.warnings()
	var missing: Array[String] = []
	for warning in warnings:
		if not sheet.contains(warning.message):
			missing.append(String(warning.id))
	results.append(TestResult.new(
		"every BuildWarning on the build reaches the sheet, at the severity it already has",
		missing.is_empty() and warnings.size() > 0,
		"%d warnings, missing %s" % [warnings.size(), missing]))

	var severities_named := 0
	for warning in warnings:
		if sheet.contains(BuildWarning.severity_name(warning.severity)):
			severities_named += 1
	results.append(TestResult.new(
		"each warning's severity is named on the sheet rather than compressed to a score",
		severities_named == warnings.size(),
		"%d of %d" % [severities_named, warnings.size()]))

	# §2.4's rejected antipattern, checked explicitly because it is the thing a sheet invites.
	results.append(TestResult.new(
		"the sheet carries no aggregate config score",
		not sheet.to_lower().contains("score"), "score present" if
			sheet.to_lower().contains("score") else "none"))

	return results


## §2.1 of the CONFIG design: SITL is a separate track and the boundary is stated in the sheet.
static func _the_sheet_says_lothal_never_ran_these_settings(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var sheet := ConfigSheet.body(_build(catalog, {}, {}), "Bench quad")

	results.append(TestResult.new(
		"the sheet states in its own voice that Lothal has not run these settings",
		sheet.contains(ConfigSheet.PREAMBLE)
			and ConfigSheet.PREAMBLE.contains("has not run"),
		ConfigSheet.PREAMBLE.substr(0, 80)))

	results.append(TestResult.new(
		"the drone's name is on the sheet, so two sheets on a bench are told apart",
		sheet.contains("Bench quad"), sheet.substr(0, 60)))

	return results


# ---------------------------------------------------------------------------
# §2.5 / §7 — the file
# ---------------------------------------------------------------------------

static func _writing_lands_and_a_bad_path_degrades(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, {}, {})
	var good := "user://test_config_sheet.md"

	var wrote := ConfigSheet.write(build, "Bench quad", good, "2026-09-21")
	var landed := ""
	if FileAccess.file_exists(good):
		landed = FileAccess.get_file_as_string(good)
	results.append(TestResult.new(
		"writing lands the same text the sheet returns",
		wrote and landed == ConfigSheet.to_markdown(build, "Bench quad", "2026-09-21"),
		"wrote=%s, %d bytes" % [wrote, landed.length()]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(good))

	results.append(TestResult.new(
		"a path that cannot be written returns false rather than crashing the room",
		not ConfigSheet.write(build, "Bench quad",
			"user://no_such_directory_for_a_sheet/deeper/x.md", "2026-09-21"),
		"returned true"))

	var path := ConfigSheet.default_path("5\" / v2", "2026-09-21")
	results.append(TestResult.new(
		"the default path is dated and named, and survives a name with punctuation in it",
		path.begins_with(ConfigSheet.DIRECTORY) and path.contains("2026-09-21")
			and path.ends_with(".md") and not path.contains("\""),
		path))

	return results


# ---------------------------------------------------------------------------
# The door out of the room
# ---------------------------------------------------------------------------

## The panel shows the sheet AS IT WILL BE WRITTEN, not a summary of it — a preview that paraphrased
## would put a fourth wording of every figure on screen, which is the one thing this slice exists to
## prevent. And like its four siblings it writes nothing: it announces, and LabScreen writes.
static func _the_panel_previews_and_writes_nothing(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var config := {"motor_spin": "props_in"}
	RateSettings.set_max_rate_deg_s(config, 400.0)
	var build := _build(catalog, {"receiver": "rx_elrs_2400"}, config)
	var before := build.config.duplicate(true)

	var panel := ConfigSheetPanel.new()
	panel.render(build, "Bench quad")

	results.append(TestResult.new(
		"the preview is the sheet itself, not a second wording of it",
		panel.preview_text() == ConfigSheet.body(build, "Bench quad"),
		"%d against %d characters" % [panel.preview_text().length(),
			ConfigSheet.body(build, "Bench quad").length()]))

	results.append(TestResult.new(
		"rendering the preview writes nothing into the drone's config block",
		build.config == before, "%s against %s" % [build.config, before]))

	# The button's connection to the panel's own signal is otherwise untestable outside a window,
	# and it is the thing that breaks — ConfigRatesPanel's `rate_field()` exists for this reason.
	var asked := [false]
	panel.export_requested.connect(func() -> void: asked[0] = true)
	panel.export_button().pressed.emit()
	results.append(TestResult.new(
		"pressing Export asks for a sheet rather than writing one itself",
		asked[0] and build.config == before, "asked=%s" % [asked[0]]))

	panel.show_result("user://sheets/2026-09-21-Bench_quad.md", true)
	var wrote_line := panel.status_text()
	panel.show_result("user://sheets/2026-09-21-Bench_quad.md", false)
	results.append(TestResult.new(
		"a sheet that landed names where it went, and one that did not says so",
		wrote_line.contains("2026-09-21-Bench_quad.md")
			and panel.status_text() != wrote_line
			and panel.status_text().to_upper().contains("COULD NOT"),
		"%s / %s" % [wrote_line, panel.status_text()]))

	panel.free()
	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _build(catalog: PartsCatalog, components: Dictionary, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, components)
	build.set_config(config)
	return build


## The ports row as `ControlPlausibility` writes it — the sentence the sheet must paste.
static func _port_message(build: Build) -> String:
	for warning in ControlPlausibility.warnings_for(build):
		if warning.id == &"serial_peripherals":
			return warning.message
	return ""


## One `## Heading` section of the sheet, so a check can ask the row itself rather than the
## document. See the ports check for why that distinction is load-bearing.
static func _section(sheet: String, heading: String) -> String:
	var marker := "\n## " + heading + "\n"
	var start := sheet.find(marker)
	if start < 0:
		return ""
	start += marker.length()
	var end := sheet.find("\n## ", start)
	return sheet.substr(start, (end - start) if end > start else -1)


static func _differing_lines(a: String, b: String) -> Array:
	var left := a.split("\n")
	var right := b.split("\n")
	var out: Array = []
	for index in maxi(left.size(), right.size()):
		var l := left[index] if index < left.size() else "<absent>"
		var r := right[index] if index < right.size() else "<absent>"
		if l != r:
			out.append(l)
	return out
