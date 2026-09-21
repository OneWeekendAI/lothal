class_name TestConfigPorts
extends RefCounted
## Config room slice C5 — THE SUPPLY SIDE OF THE PORT BUDGET.
## Design: plans/2026-09-20-config-room-design.md §2.2 and §4.2.
##
## C4 corrected the demand side and deliberately left the supply side unknown: the row counted the
## fitted parts that want a serial port and said the board's own count was not published. C5 gives
## it a number, and the whole difficulty is that THE NUMBER IS A GUESS. §0.1 relaxed the bar on
## accuracy and kept the bar that matters: a guess may never be presented as measured. So every
## check below is about the number and its PROVENANCE arriving together —
##
##   CLASS-TYPICAL — the catalog's range, said as a range and labelled as typical of a class.
##   TYPED         — the builder read the real figure off their board's page; Lothal takes it and
##                   says whose number it is, which is a DIFFERENT provenance, not a better guess.
##   UNPUBLISHED   — an entry with no range at all still gets C4's honest silence, unchanged.
##
## And the verdict has to survive the uncertainty, which is §4.2's argument for a range being
## admissible at all: four peripherals do not fit a 1–2 port board on either end of the range, and
## saying so is worth more than the precision it lacks.

## The six entries the range was written onto, and the two the checks below read by name.
const WHOOP_FC := "fc_f411_25x25_whoop"
const H743_FC := "fc_h743_30x30"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_every_board_publishes_a_labelled_range(catalog))
	results.append_array(_the_class_typical_range_is_read_from_the_board(catalog))
	results.append_array(_a_typed_override_replaces_it_and_says_so(catalog))
	results.append_array(_a_board_with_no_range_keeps_the_old_silence(catalog))
	results.append_array(_the_verdict_survives_the_range(catalog))
	results.append_array(_the_row_never_states_the_number_without_its_provenance(catalog))
	results.append_array(_the_panel_shows_the_budget_and_edits_the_override(catalog))
	return results


## THE VACUITY GUARD AND THE HONESTY GUARD IN ONE. Six entries, each with a plausible ascending
## range, and each `source` saying in plain words that the figure is typical of a class rather than
## read off a product. A range added without that sentence is exactly the failure §2.2 names.
static func _every_board_publishes_a_labelled_range(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var boards := catalog.list_category("flight_controller")

	results.append(TestResult.new(
		"all six flight controllers are still there to carry a range",
		boards.size() == 6, "found %d" % boards.size()))

	for board in boards:
		var entry: Dictionary = board
		var cat: Dictionary = entry.get("catalog", {})
		var range_value: Variant = cat.get(PortBudget.CATALOG_KEY, null)
		var ok := range_value is Array and (range_value as Array).size() == 2 \
			and int((range_value as Array)[0]) >= 1 \
			and int((range_value as Array)[1]) >= int((range_value as Array)[0])
		results.append(TestResult.new(
			"%s publishes a two-ended uart_range with a sane low and high" % entry.get("part_id", "?"),
			ok, "uart_range = %s" % [range_value]))

		var source := str(entry.get("source", "")).to_lower()
		results.append(TestResult.new(
			"%s says in its source that the port figure is class-typical, not a product's" % entry.get("part_id", "?"),
			source.contains("class-typical") and source.contains("port"),
			"source: %s" % [entry.get("source", "")]))

	return results


## The range reaches a build from the board it is fitted with, and it arrives labelled.
static func _the_class_typical_range_is_read_from_the_board(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var whoop := _build(catalog, WHOOP_FC, {})
	var budget := PortBudget.for_build(whoop)
	var catalog_range: Array = (catalog.get_part(WHOOP_FC)["catalog"] as Dictionary)[PortBudget.CATALOG_KEY]

	results.append(TestResult.new(
		"a whoop build reads its port range off the board it is fitted with",
		int(budget["low"]) == int(catalog_range[0]) and int(budget["high"]) == int(catalog_range[1]),
		"budget %s from catalog %s" % [budget, catalog_range]))

	results.append(TestResult.new(
		"and the range is marked as a class-typical figure rather than a measured one",
		String(budget["provenance"]) == PortBudget.CLASS_TYPICAL,
		"provenance %s" % [budget["provenance"]]))

	# THE SENTENCE IS THE POINT. A builder reads it, not `values`.
	var sentence := String(budget["sentence"]).to_lower()
	results.append(TestResult.new(
		"and its sentence says the figure is typical of the class and that they can set their own",
		sentence.contains("typical") and sentence.contains("set yours"),
		"sentence: %s" % [budget["sentence"]]))

	# A DIFFERENT BOARD MUST READ DIFFERENTLY, or the range is decoration: an H743 has more ports
	# than an F411 whoop, and a budget that returned one number for both would pass every check
	# above while telling every builder the same thing.
	# BOTH ENDS, ON A BOARD WHOSE ENDS ARE NOT ADJACENT. A whoop's 1–2 is satisfied by any rule that
	# invents the high end from the low one; the H743's 6–8 is not, and a mutation that did exactly
	# that survived until this row was written.
	var big := PortBudget.for_build(_build(catalog, H743_FC, {}))
	var big_catalog: Array = (catalog.get_part(H743_FC)["catalog"] as Dictionary)[PortBudget.CATALOG_KEY]
	results.append(TestResult.new(
		"and a wider board's range is read at BOTH ends, not derived from its low one",
		int(big["low"]) == int(big_catalog[0]) and int(big["high"]) == int(big_catalog[1])
			and int(big["high"]) > int(budget["high"]),
		"h743 %s against catalog %s" % [big, big_catalog]))

	return results


## The override: a number the builder typed, held per drone, and flagged as THEIRS.
static func _a_typed_override_replaces_it_and_says_so(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var config := {}
	PortBudget.set_count(config, 3)
	var typed := PortBudget.for_build(_build(catalog, WHOOP_FC, config))

	results.append(TestResult.new(
		"a typed override becomes the whole range, low and high alike",
		int(typed["low"]) == 3 and int(typed["high"]) == 3,
		"budget %s" % [typed]))

	results.append(TestResult.new(
		"and it carries a DIFFERENT provenance from the class-typical guess it replaced",
		String(typed["provenance"]) == PortBudget.TYPED
			and PortBudget.TYPED != PortBudget.CLASS_TYPICAL,
		"provenance %s" % [typed["provenance"]]))

	var sentence := String(typed["sentence"]).to_lower()
	results.append(TestResult.new(
		"and its sentence says the figure is the builder's own, not the catalog's",
		sentence.contains("you") and not sentence.contains("typical"),
		"sentence: %s" % [typed["sentence"]]))

	# WARN, NEVER BLOCK — and never let a nonsense entry become a confident claim. Zero and
	# negative mean "no override", falling back to the class-typical range rather than asserting a
	# board with no ports.
	var cleared := {}
	PortBudget.set_count(cleared, 0)
	var fallback := PortBudget.for_build(_build(catalog, WHOOP_FC, cleared))
	results.append(TestResult.new(
		"and a zero override is no override: the class-typical range comes back",
		String(fallback["provenance"]) == PortBudget.CLASS_TYPICAL
			and not cleared.has(PortBudget.CONFIG_KEY),
		"provenance %s, config %s" % [fallback["provenance"], cleared]))

	return results


## The case C4 shipped, still intact: no range published, no number invented.
static func _a_board_with_no_range_keeps_the_old_silence(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var build := _build(catalog, WHOOP_FC, {})
	# A board that publishes no range at all — the pre-C5 catalog, and any custom board authored
	# without one.
	build.fc = build.fc.duplicate(true)
	(build.fc["catalog"] as Dictionary).erase(PortBudget.CATALOG_KEY)
	var budget := PortBudget.for_build(build)

	results.append(TestResult.new(
		"a board publishing no range states no port count at all",
		String(budget["provenance"]) == PortBudget.UNPUBLISHED
			and int(budget["low"]) == 0 and int(budget["high"]) == 0,
		"budget %s" % [budget]))

	var warning := _port_warning(build)
	results.append(TestResult.new(
		"and its warning row still says the count is not published in this catalog",
		warning != null and warning.message.contains(ControlPlausibility.PORTS_UNPUBLISHED),
		"message: %s" % ["<missing>" if warning == null else warning.message]))

	return results


## §4.2's argument for a range being admissible: the verdict survives it. Four peripherals do not
## fit a 1–2 port board at either end, and that is worth saying however rough the range is.
static func _the_verdict_survives_the_range(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# A whoop with a receiver, a GPS and an analog VTX, on a non-DShot ESC: four demands.
	var crowded := _crowded_build(catalog, {})
	var warning := _port_warning(crowded)
	results.append(TestResult.new(
		"the crowded fixture really does want four ports, or the verdict below proves nothing",
		warning != null and int(warning.values.get("serial_peripherals", -1)) == 4,
		"counted %s" % ["<missing>" if warning == null else warning.values.get("serial_peripherals", -1)]))

	results.append(TestResult.new(
		"four parts do not fit a 1-2 port whoop, and the row says so on either end of the range",
		warning != null and warning.message.to_lower().contains("does not fit"),
		"message: %s" % ["<missing>" if warning == null else warning.message]))

	# The same four on a board with room: the verdict flips, which is what makes the one above a
	# finding rather than a sentence that is always printed.
	var roomy := _port_warning(_crowded_build(catalog, {}, H743_FC))
	results.append(TestResult.new(
		"and the same four parts DO fit a 6-8 port board, so the verdict is computed not printed",
		roomy != null and not roomy.message.to_lower().contains("does not fit")
			and roomy.message.to_lower().contains("fit"),
		"message: %s" % ["<missing>" if roomy == null else roomy.message]))

	# The genuinely undecided case — demand between the two ends — must say it is undecided rather
	# than pick the end that flatters the build.
	var config := {}
	var undecided := _port_warning(_crowded_build(catalog, config, "fc_f405_20x20"))
	results.append(TestResult.new(
		"and a demand of four against a 3-4 range says the answer depends on which figure is right",
		undecided != null and undecided.message.to_lower().contains("depends"),
		"message: %s" % ["<missing>" if undecided == null else undecided.message]))

	return results


## THE WORDING RULE, which §2.2 turns on: the row states the count and where it came from IN THE
## SAME BREATH, never the count alone. Asserted on the message a builder reads and on `values`,
## because the panel reads one and the sheet reads the other.
static func _the_row_never_states_the_number_without_its_provenance(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var warning := _port_warning(_crowded_build(catalog, {}))
	var message := "" if warning == null else warning.message

	results.append(TestResult.new(
		"the row prints the board's port figure",
		message.contains("1") and message.contains("2"), "message: %s" % [message]))

	results.append(TestResult.new(
		"and never without saying it is a class-typical figure rather than this board's",
		message.to_lower().contains("typical"), "message: %s" % [message]))

	results.append(TestResult.new(
		"and `values` carries the provenance beside the figure, for everything that reads values",
		warning != null and warning.values.has("uart_low") and warning.values.has("uart_high")
			and String(warning.values.get("uart_provenance", "")) == PortBudget.CLASS_TYPICAL,
		"values: %s" % [str(warning.values) if warning != null else "<missing>"]))

	var config := {}
	PortBudget.set_count(config, 6)
	var typed := _port_warning(_crowded_build(catalog, config))
	results.append(TestResult.new(
		"and with a typed override the row says whose number it is instead",
		typed != null and String(typed.values.get("uart_provenance", "")) == PortBudget.TYPED
			and not typed.message.to_lower().contains("typical"),
		"message: %s" % ["<missing>" if typed == null else typed.message]))

	return results


## The editable field §4.2 calls "the answer to genericness" — it has to exist somewhere a builder
## can reach, and it must write through the same way the C3 panel does: announce, never write.
static func _the_panel_shows_the_budget_and_edits_the_override(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var panel := ConfigPortsPanel.new()
	var build := _crowded_build(catalog, {})
	var emitted: Array = []
	panel.uart_count_edited.connect(func(count: int) -> void: emitted.append(count))
	panel.render(build)

	results.append(TestResult.new(
		"the Ports panel shows the demand count it was rendered with",
		panel.demand_text().contains("4"), "demand row: %s" % [panel.demand_text()]))

	results.append(TestResult.new(
		"and it shows the supply figure WITH its provenance, the same sentence the warning uses",
		panel.supply_text().to_lower().contains("typical")
			and panel.supply_text().contains("1"),
		"supply row: %s" % [panel.supply_text()]))

	# The signal a mouse would send. A `Range` assigned headlessly announces nothing, so this drives
	# the box's own signal and checks what the panel does with it — which is the wiring that breaks.
	panel.port_field().value_changed.emit(5.0)
	results.append(TestResult.new(
		"and typing a port count announces it rather than writing it into the build itself",
		emitted == [5] and not build.config.has(PortBudget.CONFIG_KEY),
		"emitted %s, config %s" % [emitted, build.config]))

	# Rendering a build that already carries an override must show that override, or a builder
	# reopens their drone and sees the guess they replaced.
	var config := {}
	PortBudget.set_count(config, 7)
	panel.render(_crowded_build(catalog, config))
	results.append(TestResult.new(
		"and reopening a drone with an override shows the typed figure, not the guess",
		panel.field_value() == 7 and panel.supply_text().contains("7"),
		"field %d, supply row: %s" % [panel.field_value(), panel.supply_text()]))

	panel.free()
	return results


static func _build(catalog: PartsCatalog, fc_id: String, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, fc_id,
		{"receiver": "rx_elrs_2400"})
	build.set_config(config)
	return build


## Four demands on one build: receiver, GPS, analog VTX, and an ESC whose protocol has no return
## path on the signal wire. Every one of those is C4's, unchanged.
static func _crowded_build(catalog: PartsCatalog, config: Dictionary,
		fc_id: String = WHOOP_FC) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, fc_id,
		{"receiver": "rx_elrs_2400", "gps": "gps_micro_flat", "vtx": "vtx_analog_400mw"})
	build.set_config(config)
	# The ESC's protocol is what decides the fourth demand, and it is set here rather than by
	# picking a catalog row so the fixture cannot quietly lose the demand to a catalog edit.
	build.esc = build.esc.duplicate(true)
	(build.esc["catalog"] as Dictionary)["protocol"] = "Multishot"
	return build


static func _port_warning(build: Build) -> BuildWarning:
	for warning in ControlPlausibility.warnings_for(build):
		if warning.id == &"serial_peripherals":
			return warning
	return null
