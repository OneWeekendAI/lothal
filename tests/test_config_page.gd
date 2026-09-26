class_name TestConfigPage
extends RefCounted
## The Config item pages (lab dock design §3, §4): Motor direction, Ports, Failsafe, Rates and
## Sheet, headless.
##
## What this suite guards: each row's line 2 is the setting in force and its line 3 a ✓ with the
## check that passed, or the row's own warning — and the row, its page's two numbers and its drawing
## read ONE computation (`ConfigFigures`). No UART number, no expo curve and no per-axis rate
## appears anywhere: Lothal knows none of them.
##
## One test per case.


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()

	# --- the shared figures
	out.append(_spin_check_of_the_reference_cancels(build))
	out.append(_spin_check_of_props_in_cancels())
	out.append(_spin_check_of_all_cw_does_not())
	out.append(_spin_check_names_a_broken_diagonal())
	out.append(_plausibility_warns_from_the_same_check())
	out.append(_sheet_settings_of_the_reference_are_all_defaults(build))
	out.append(_sheet_flag_count_is_the_sheets_own_list(build))

	# --- the rows
	out.append(_motor_direction_row(build))
	out.append(_motor_direction_row_props_in())
	out.append(_motor_direction_row_unflyable())
	out.append(_ports_row(build))
	out.append(_ports_row_typed_fits())
	out.append(_ports_row_over_the_board())
	out.append(_ports_row_over_carries_the_budget_sentence())
	out.append(_ports_row_straddling_the_range())
	out.append(_failsafe_row(build))
	out.append(_failsafe_row_chosen())
	out.append(_failsafe_row_gps_rescue_without_gps())
	out.append(_failsafe_text_withholds_the_tick_without_gps())
	out.append(_rates_row(build))
	out.append(_rates_row_set_slower_with_expo())
	out.append(_sheet_row(build))
	out.append(_sheet_row_all_set())

	# --- the page numbers
	out.append(_motor_direction_page_numbers(build))
	out.append(_motor_direction_page_numbers_all_cw())
	out.append(_ports_page_numbers(build))
	out.append(_ports_page_numbers_typed())
	out.append(_failsafe_page_numbers(build))
	out.append(_failsafe_page_numbers_bidir_on())
	out.append(_rates_page_numbers(build))
	out.append(_sheet_page_numbers(build))

	# --- the drawings and the dock's panels
	out.append(_page_definitions_name_their_drawings())
	out.append(_plan_corner_is_the_mixers_corner())
	out.append(_motors_drawing_reads_the_spin_check(build))
	out.append(_motors_drawing_marks_a_broken_diagonal())
	out.append(_uart_slots_of_the_reference(build))
	out.append(_uart_slots_over_a_typed_count())
	out.append(_uart_slots_unpublished())
	out.append(_failsafe_drawing_gps_rescue_without_gps())
	out.append(_rates_drawing_reads_both_rates())
	out.append(_sheet_drawing_reads_the_sheet_settings(build))
	out.append(_motors_panel_warnings_stay_hidden_after_render())
	out.append(_failsafe_panel_prose_hides_the_teaching_half(build))
	out.append(_ports_panel_says_what_its_box_means_on_the_dock())
	return out


static func _with(config: Dictionary) -> Build:
	var build := ReferenceBuild.build()
	for key in config:
		build.config[key] = config[key]
	return build


static func _row(build: Build, id: StringName) -> Dictionary:
	for row in SectionRows.rows("Config", build, build.warnings()):
		if row["id"] == id:
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "'%s' / '%s' (%s)" % [row.get("choice"), row.get("line3"), row.get("status")]


static func _all_cw() -> Dictionary:
	return {"motor_spin": {"M1": 1, "M2": 1, "M3": 1, "M4": 1}}


static func _all_set() -> Dictionary:
	return {"motor_spin": "props_out", PortBudget.CONFIG_KEY: 5,
		FailsafeSettings.STAGE2_KEY: FailsafeSettings.DROP, RateSettings.MAX_RATE_KEY: 800.0}


# ---------------------------------------------------------------------------
# The shared figures
# ---------------------------------------------------------------------------

static func _spin_check_of_the_reference_cancels(build: Build) -> TestResult:
	var check := ConfigFigures.spin_check(build)
	return TestResult.new("config figures: the reference map cancels and its diagonals agree",
		float(check["net"]) == 0.0 and (check["broken"] as Array).is_empty()
			and ConfigFigures.spin_flies(build), str(check))


static func _spin_check_of_props_in_cancels() -> TestResult:
	var build := _with({"motor_spin": "props_in"})
	var check := ConfigFigures.spin_check(build)
	return TestResult.new("config figures: props-in flips every motor and still cancels",
		ConfigFigures.spin_flies(build) and float(check["spin"]["M1"]) == -1.0, str(check))


static func _spin_check_of_all_cw_does_not() -> TestResult:
	var check := ConfigFigures.spin_check(_with(_all_cw()))
	return TestResult.new("config figures: four CW motors net +4 with both diagonals agreeing",
		float(check["net"]) == 4.0 and (check["broken"] as Array).is_empty(), str(check))


static func _spin_check_names_a_broken_diagonal() -> TestResult:
	var check := ConfigFigures.spin_check(_with({"motor_spin": {"M1": 1, "M2": 1, "M3": -1,
		"M4": -1}}))
	return TestResult.new("config figures: M1/M2 CW with M3/M4 CCW nets 0 and breaks both diagonals",
		float(check["net"]) == 0.0 and check["broken"] == ["M1/M4", "M2/M3"], str(check))


static func _plausibility_warns_from_the_same_check() -> TestResult:
	var ids: Array = []
	for w in ConfigPlausibility.warnings_for(_with(_all_cw())):
		ids.append(w.id)
	return TestResult.new("config figures: the unflyable warning fires on the map the check fails",
		ids.has(&"motor_spin_unflyable"), str(ids))


static func _sheet_settings_of_the_reference_are_all_defaults(build: Build) -> TestResult:
	var whose: Array = []
	for setting in ConfigFigures.sheet_settings(build):
		whose.append(setting["whose"])
	return TestResult.new("config figures: the reference's four sheet settings are defaults or a class guess",
		whose == [ConfigFigures.DEFAULT, ConfigFigures.GUESS, ConfigFigures.DEFAULT,
			ConfigFigures.DEFAULT], str(whose))


static func _sheet_flag_count_is_the_sheets_own_list(build: Build) -> TestResult:
	var body := ConfigSheet.body(build, "t")
	var section := body.substr(body.find("## What is wrong with this build"))
	section = section.substr(0, section.find("## If it will not arm"))
	var listed := section.count("\n- [")
	return TestResult.new("config figures: the sheet's flag count is the lines its warnings section lists",
		ConfigFigures.sheet_flag_count(build) == listed and listed > 0,
		"%d vs %d listed" % [ConfigFigures.sheet_flag_count(build), listed])


# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

static func _motor_direction_row(build: Build) -> TestResult:
	var row := _row(build, &"motor_direction")
	return TestResult.new("config rows: Motor direction reads props out and its cancelling ✓",
		row.get("choice") == "props out" and row.get("line3") == "✓ yaw torques cancel"
			and row.get("status") == SectionRows.OK, _show(row))


static func _motor_direction_row_props_in() -> TestResult:
	var row := _row(_with({"motor_spin": "props_in"}), &"motor_direction")
	return TestResult.new("config rows: Motor direction reads props in",
		row.get("choice") == "props in" and row.get("line3") == "✓ yaw torques cancel", _show(row))


static func _motor_direction_row_unflyable() -> TestResult:
	var row := _row(_with(_all_cw()), &"motor_direction")
	return TestResult.new("config rows: an unflyable map is red with its warning on line 3",
		row.get("choice") == "custom" and row.get("line3") == "⚠ motor directions cannot fly"
			and row.get("status") == SectionRows.BAD, _show(row))


static func _ports_row(build: Build) -> TestResult:
	var row := _row(build, &"ports")
	return TestResult.new("config rows: Ports names what wants a UART and the count against the board's ~range",
		row.get("choice") == "RX · VTX" and row.get("line3") == "✓ 2 of ~4–5 UARTs used"
			and row.get("status") == SectionRows.OK, _show(row))


static func _ports_row_typed_fits() -> TestResult:
	var row := _row(_with({PortBudget.CONFIG_KEY: 2}), &"ports")
	return TestResult.new("config rows: a typed count loses its ~",
		row.get("line3") == "✓ 2 of 2 UARTs used", _show(row))


static func _ports_row_over_the_board() -> TestResult:
	var row := _row(_with({PortBudget.CONFIG_KEY: 1}), &"ports")
	return TestResult.new("config rows: more parts than the board's ports is amber, the count on line 3",
		row.get("line3") == "⚠ 2 want a UART, board has 1" and row.get("status") == SectionRows.WARN,
		_show(row))


static func _ports_row_over_carries_the_budget_sentence() -> TestResult:
	var build := _with({PortBudget.CONFIG_KEY: 1})
	var owned: Array = _row(build, &"ports").get("warnings", [])
	var why := (owned[0] as BuildWarning).long() if owned.size() == 1 else ""
	return TestResult.new("config rows: the over-budget Why? pastes PortBudget's own sentence and verdict",
		why.contains(str(PortBudget.for_build(build)["sentence"])) and why.contains("2 does not fit."),
		why)


static func _ports_row_straddling_the_range() -> TestResult:
	# No catalogue board publishes a range the reference's two parts fall inside, so this one
	# publishes 1–3 (a copy of the row, so the shared catalogue is untouched).
	var build := ReferenceBuild.build()
	build.fc = build.fc.duplicate(true)
	(build.fc["catalog"] as Dictionary)[PortBudget.CATALOG_KEY] = [1, 3]
	var row := _row(build, &"ports")
	return TestResult.new("config rows: a demand inside the board's range reads 'check board', no ✓",
		row.get("line3") == "2 of ~1–3 UARTs · check board" and row.get("status") == SectionRows.OK,
		_show(row))


static func _failsafe_row(build: Build) -> TestResult:
	var row := _row(build, &"failsafe")
	return TestResult.new("config rows: Failsafe reads stage 2 drop as Betaflight's default, and ✓",
		row.get("choice") == "stage 2 drop · BF default"
			and row.get("line3") == "✓ this build can carry it out", _show(row))


static func _failsafe_row_chosen() -> TestResult:
	var row := _row(_with({FailsafeSettings.STAGE2_KEY: FailsafeSettings.LAND}), &"failsafe")
	return TestResult.new("config rows: a chosen stage 2 reads as yours",
		row.get("choice") == "stage 2 land · yours", _show(row))


static func _failsafe_row_gps_rescue_without_gps() -> TestResult:
	var row := _row(_with({FailsafeSettings.STAGE2_KEY: FailsafeSettings.GPS_RESCUE}), &"failsafe")
	return TestResult.new("config rows: GPS rescue with no GPS is amber with its short",
		row.get("line3") == "⚠ GPS rescue with no GPS" and row.get("status") == SectionRows.WARN,
		_show(row))


static func _failsafe_text_withholds_the_tick_without_gps() -> TestResult:
	var text := ConfigFigures.failsafe_text(_with({FailsafeSettings.STAGE2_KEY:
		FailsafeSettings.GPS_RESCUE}))
	return TestResult.new("config figures: GPS rescue with no GPS gets no ✓ of its own", text == "", text)


static func _rates_row(build: Build) -> TestResult:
	var row := _row(build, &"rates")
	return TestResult.new("config rows: Rates reads the full-stick rate and that the sim flies the same",
		row.get("choice") == "800°/s each axis" and row.get("line3") == "✓ same as the sim flies",
		_show(row))


static func _rates_row_set_slower_with_expo() -> TestResult:
	var row := _row(_with({RateSettings.MAX_RATE_KEY: 600.0, RateSettings.EXPO_KEY: 0.2}), &"rates")
	return TestResult.new("config rows: a set rate and expo read on line 2, the sim's rate on line 3",
		row.get("choice") == "600°/s each axis · expo 0.20" and row.get("line3") == "sim flies 800°/s",
		_show(row))


static func _sheet_row(build: Build) -> TestResult:
	var row := _row(build, &"sheet")
	return TestResult.new("config rows: Sheet counts the settings that are yours and flags the rest amber",
		row.get("choice") == "0 of 4 settings yours" and row.get("line3") == "⚠ 4 settings not set by you"
			and row.get("status") == SectionRows.WARN, _show(row))


static func _sheet_row_all_set() -> TestResult:
	var row := _row(_with(_all_set()), &"sheet")
	return TestResult.new("config rows: with every setting yours the Sheet is ready",
		row.get("choice") == "4 of 4 settings yours" and row.get("line3") == "✓ ready to export"
			and row.get("status") == SectionRows.OK, _show(row))


# ---------------------------------------------------------------------------
# The page numbers
# ---------------------------------------------------------------------------

static func _motor_direction_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"motor_direction", build)
	var want := [["Net yaw torque, equal throttles", "0 · cancels"], ["Diagonal pairs agreeing", "2 of 2"]]
	return TestResult.new("page numbers: Motor direction shows the net torque and the diagonals",
		got == want, "%s" % [got])


static func _motor_direction_page_numbers_all_cw() -> TestResult:
	var got := SectionRows.page_numbers(&"motor_direction", _with(_all_cw()))
	return TestResult.new("page numbers: four CW motors net +4 motors' worth",
		got == [["Net yaw torque, equal throttles", "+4 motors' worth"],
			["Diagonal pairs agreeing", "2 of 2"]], "%s" % [got])


static func _ports_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"ports", build)
	return TestResult.new("page numbers: Ports shows the demand and the board's figure with its provenance",
		got == [["Parts wanting a UART", "2"], ["Board's UARTs", "~4–5 · class guess"]], "%s" % [got])


static func _ports_page_numbers_typed() -> TestResult:
	var got := SectionRows.page_numbers(&"ports", _with({PortBudget.CONFIG_KEY: 6}))
	return TestResult.new("page numbers: a typed UART count is yours",
		got[1] == ["Board's UARTs", "6 · yours"], "%s" % [got])


static func _failsafe_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"failsafe", build)
	return TestResult.new("page numbers: Failsafe shows stage 2 and bidirectional DShot against the ESC's protocol",
		got == [["Stage 2", "drop · BF default"], ["Bidirectional DShot", "off · ESC DShot600"]],
		"%s" % [got])


static func _failsafe_page_numbers_bidir_on() -> TestResult:
	var got := SectionRows.page_numbers(&"failsafe", _with({FailsafeSettings.BIDIR_KEY: true}))
	return TestResult.new("page numbers: bidirectional DShot on reads on",
		got[1] == ["Bidirectional DShot", "on · ESC DShot600"], "%s" % [got])


static func _rates_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"rates", build)
	return TestResult.new("page numbers: Rates shows this aircraft's full-stick rate and the sim's",
		got == [["Full stick, this aircraft", "800°/s"], ["Full stick, the sim", "800°/s"]],
		"%s" % [got])


static func _sheet_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"sheet", build)
	return TestResult.new("page numbers: Sheet shows the settings yours and the flags it lists",
		got == [["Settings yours", "0 of 4"], ["Flags on the sheet", "%d" % build.warnings().size()]]
			and build.warnings().size() > 0, "%s" % [got])



# ---------------------------------------------------------------------------
# The drawings, and the panels on the dock
# ---------------------------------------------------------------------------

static func _diagram(build: Build, mode: String) -> ConfigDiagram:
	var d := ConfigDiagram.new()
	d.show_build(build, mode)
	return d


static func _page_definitions_name_their_drawings() -> TestResult:
	var got := {}
	for definition in SectionRows.DEFINITIONS["Config"]:
		got[definition["id"]] = definition["page"].get("diagram", "")
	var want := {&"motor_direction": ConfigDiagram.MODE_MOTORS, &"ports": ConfigDiagram.MODE_PORTS,
		&"failsafe": ConfigDiagram.MODE_FAILSAFE, &"rates": ConfigDiagram.MODE_RATES,
		&"sheet": ConfigDiagram.MODE_SHEET}
	return TestResult.new("config rows: each page names its ConfigDiagram mode", got == want, str(got))


static func _plan_corner_is_the_mixers_corner() -> TestResult:
	# M2 is front-right: right is +x on screen, front is up (-y).
	var got := [ConfigDiagram.plan_corner("M2"), ConfigDiagram.plan_corner("M3")]
	return TestResult.new("config drawing: M2 is drawn front-right and M3 rear-left",
		got == [Vector2(1, -1), Vector2(-1, 1)], str(got))


static func _motors_drawing_reads_the_spin_check(build: Build) -> TestResult:
	var d := _diagram(build, ConfigDiagram.MODE_MOTORS)
	var ok := d.spin_check == ConfigFigures.spin_check(build) and float(d.spin_check["spin"]["M1"]) == 1.0
	var shown := str(d.spin_check)
	d.free()
	return TestResult.new("config drawing: the motors are drawn with the mixer's map", ok, shown)


static func _motors_drawing_marks_a_broken_diagonal() -> TestResult:
	var d := _diagram(_with({"motor_spin": {"M1": 1, "M2": 1, "M3": -1, "M4": -1}}),
		ConfigDiagram.MODE_MOTORS)
	var ok: bool = d.spin_check["broken"] == ["M1/M4", "M2/M3"]
	var shown := str(d.spin_check)
	d.free()
	return TestResult.new("config drawing: a split map's diagonals are both marked broken", ok, shown)


static func _uart_slots_of_the_reference(build: Build) -> TestResult:
	var got := ConfigFigures.uart_slots(build)
	var want := {"known": true, "slots": [{"part": "RX", "maybe": false}, {"part": "VTX", "maybe": false},
		{"part": "", "maybe": false}, {"part": "", "maybe": false}, {"part": "", "maybe": true}],
		"over": [], "parts": ["RX", "VTX"]}
	return TestResult.new("config figures: ~4–5 UARTs draw five slots, the fifth a maybe, RX and VTX in order",
		got == want, str(got))


static func _uart_slots_over_a_typed_count() -> TestResult:
	var got := ConfigFigures.uart_slots(_with({PortBudget.CONFIG_KEY: 1}))
	return TestResult.new("config figures: one typed UART holds RX; VTX is left over",
		got["slots"] == [{"part": "RX", "maybe": false}] and got["over"] == ["VTX"], str(got))


static func _uart_slots_unpublished() -> TestResult:
	var build := ReferenceBuild.build()
	build.fc = build.fc.duplicate(true)
	(build.fc["catalog"] as Dictionary).erase(PortBudget.CATALOG_KEY)
	var got := ConfigFigures.uart_slots(build)
	return TestResult.new("config figures: an unpublished count draws no slots and invents none",
		got["known"] == false and (got["slots"] as Array).is_empty() and got["parts"] == ["RX", "VTX"],
		str(got))


static func _failsafe_drawing_gps_rescue_without_gps() -> TestResult:
	var d := _diagram(_with({FailsafeSettings.STAGE2_KEY: FailsafeSettings.GPS_RESCUE}),
		ConfigDiagram.MODE_FAILSAFE)
	var ok := not d.failsafe_ok and d.failsafe_needs == "a GPS" \
		and d.stage2_label == FailsafeSettings.label_for(FailsafeSettings.GPS_RESCUE)
	var shown := "%s / %s / %s" % [d.stage2_label, d.failsafe_ok, d.failsafe_needs]
	d.free()
	return TestResult.new("config drawing: GPS rescue with no GPS draws its need unmet", ok, shown)


static func _rates_drawing_reads_both_rates() -> TestResult:
	var d := _diagram(_with({RateSettings.MAX_RATE_KEY: 600.0}), ConfigDiagram.MODE_RATES)
	var ok := is_equal_approx(d.rate_set, 600.0) and is_equal_approx(d.rate_sim, ConfigFigures.sim_rate_deg_s())
	var shown := "%s / %s" % [d.rate_set, d.rate_sim]
	d.free()
	return TestResult.new("config drawing: the rate line ends at the set rate, the sim's beside it", ok, shown)


static func _sheet_drawing_reads_the_sheet_settings(build: Build) -> TestResult:
	var d := _diagram(build, ConfigDiagram.MODE_SHEET)
	var ok := d.settings == ConfigFigures.sheet_settings(build) and d.flags == build.warnings().size()
	var shown := "%s / %d" % [d.settings, d.flags]
	d.free()
	return TestResult.new("config drawing: the sheet preview is the sheet's four settings and its flags", ok, shown)


static func _motors_panel_warnings_stay_hidden_after_render() -> TestResult:
	var panel := ConfigMotorsPanel.new()
	panel.set_warnings_visible(false)
	panel.render(_with(_all_cw()))
	var text := panel.warning_text()
	panel.free()
	return TestResult.new("config panels: a hidden warning list stays hidden when an unflyable map renders",
		text == "", text)


static func _failsafe_panel_prose_hides_the_teaching_half(build: Build) -> TestResult:
	var panel := ConfigFailsafePanel.new()
	panel.set_prose_visible(false)
	panel.render(build)
	var ok := not panel._arming.visible and not panel._provenance.visible and panel.stage2_chooser().visible
	panel.free()
	return TestResult.new("config panels: off the dock's prose, the arming notes go and the chooser stays", ok, "")


static func _ports_panel_says_what_its_box_means_on_the_dock() -> TestResult:
	var panel := ConfigPortsPanel.new()
	var off_dock := panel.short_hint_visible()
	panel.set_prose_visible(false)
	var ok := not off_dock and panel.short_hint_visible()
	panel.free()
	return TestResult.new("config panels: with the paragraph off, the Ports box keeps a one-line meaning", ok, "")
