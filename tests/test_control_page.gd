class_name TestControlPage
extends RefCounted
## The Control item pages (lab dock design §3, §4): Flight controller, Receiver & link and Tune,
## headless.
##
## What this suite guards: each row's line 3, its page's two numbers and its drawing come from ONE
## computation (`ControlFigures`), shared with the sheets beside them — the port count the FC row
## quotes is the serial-peripherals warning's own count against `PortBudget`'s own range, the D
## noise the FC page quotes is `FcDetails`' row, and the tune's figures are the `RateTune` in force.
##
## One test per case.

## RateTune.derive spools a FrameBench per axis; derived once per run, not once per test.
static var _tune: RateTune = null


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var tune := _derived(build)

	# --- the shared figures
	out.append(_serial_parts_are_the_warnings_count(build))
	out.append(_serial_parts_name_the_receiver_and_the_vtx(build))
	out.append(_ports_text_states_the_class_range_with_its_tilde(build))
	out.append(_ports_text_takes_the_typed_count_without_a_tilde(build))
	out.append(_ports_text_is_empty_when_no_range_is_published(build))
	out.append(_ports_text_never_says_spare(build))
	out.append(_d_noise_is_the_installed_kd_through_rate_tune(build, tune))
	out.append(_d_noise_without_a_tune_is_the_hand_tune(build))
	out.append(_d_noise_matches_the_fc_sheet(build, tune))
	out.append(_link_mass_is_the_link_sheets_total(build))
	out.append(_link_uarts_count_the_receiver_only(build))
	out.append(_pattern_parses_both_sides())
	out.append(_pattern_of_nonsense_is_zero())
	out.append(_d_ceiling_share_is_kd_over_ceiling(tune))
	out.append(_time_constants_are_the_tunes(tune))

	# --- the rows
	out.append(_fc_row_reads_the_ports(build))
	out.append(_fc_row_fits_the_line(build))
	out.append(_receiver_row_leaves_range_empty(build, tune))
	out.append(_tune_row_reads_d_against_the_ceiling(build, tune))
	out.append(_tune_row_fits_the_line(build, tune))
	out.append(_tune_row_without_a_tune_is_empty(build))
	out.append(_tune_row_says_hand_tuned_when_overridden(build))
	out.append(_tune_row_owns_the_tunes_warnings(build))

	# --- the page numbers
	out.append(_fc_page_numbers(build, tune))
	out.append(_receiver_page_numbers(build))
	out.append(_tune_page_numbers(build, tune))

	# --- the drawings
	out.append(_fc_drawing_holds_the_three_patterns(build))
	out.append(_fc_slots_are_the_parts_then_the_range(build))
	out.append(_fc_slots_past_a_typed_count_are_over(build))
	out.append(_fc_slots_with_no_published_count_are_the_parts_alone(build))
	out.append(_link_drawing_lands_the_receiver_on_a_uart(build))
	out.append(_link_drawing_marks_empty_bays(build))
	out.append(_link_drawing_names_the_mast_and_the_buzzers_power())
	out.append(_tune_drawing_gains_are_the_tunes(build, tune))
	out.append(_tune_drawing_marks_a_hand_axis(build))
	out.append(_tune_drawing_ceiling_is_the_tunes(build, tune))
	out.append(_page_definitions_name_their_drawings())
	return out


static func _derived(build: Build) -> RateTune:
	if _tune == null:
		_tune = RateTune.derive(build)
	return _tune


static func _row(rows: Array, id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


static func _warning(build: Build, id: StringName) -> BuildWarning:
	for w in build.warnings():
		if w.id == id:
			return w
	return null


static func _with_fc_catalog(build: Build, catalog: Dictionary) -> Build:
	var copy := ReferenceBuild.build()
	copy.fc = build.fc.duplicate(true)
	copy.fc["catalog"] = catalog
	return copy


# ---------------------------------------------------------------------------
# The shared figures
# ---------------------------------------------------------------------------

static func _serial_parts_are_the_warnings_count(build: Build) -> TestResult:
	var w := _warning(build, &"serial_peripherals")
	var want := int(w.values["serial_peripherals"]) if w != null else -1
	var got := ControlFigures.serial_demand(build)
	return TestResult.new("control figures: the UART demand is the serial-peripherals warning's count",
		got == want and got == 2, "%d vs %d" % [got, want])


static func _serial_parts_name_the_receiver_and_the_vtx(build: Build) -> TestResult:
	var names: Array = []
	for part in ControlFigures.serial_parts(build):
		names.append(str(part["category"]))
	return TestResult.new("control figures: the reference build's serial parts are the receiver and the VTX",
		names == ["receiver", "vtx"], str(names))


static func _ports_text_states_the_class_range_with_its_tilde(build: Build) -> TestResult:
	var got := ControlFigures.ports_used_text(build)
	return TestResult.new("control figures: ports read '2 of ~4–5 UARTs used' — the class range, marked ~",
		got == "2 of ~4–5 UARTs used", "'%s'" % got)


static func _ports_text_takes_the_typed_count_without_a_tilde(build: Build) -> TestResult:
	var copy := ReferenceBuild.build()
	PortBudget.set_count(copy.config, 6)
	var got := ControlFigures.ports_used_text(copy)
	return TestResult.new("control figures: a typed port count replaces the range and loses its ~",
		got == "2 of 6 UARTs used", "'%s'" % got)


static func _ports_text_is_empty_when_no_range_is_published(build: Build) -> TestResult:
	var copy := _with_fc_catalog(build, {"processor": "F405"})
	var got := ControlFigures.ports_used_text(copy)
	return TestResult.new("control figures: no published range, no port text (never an invented count)",
		got == "", "'%s'" % got)


## ControlPlausibility's header refuses a spare-port count: "four does not fit" survives the range,
## "two spare" does not. The row states use against the range and never the difference.
static func _ports_text_never_says_spare(build: Build) -> TestResult:
	var got := ControlFigures.ports_used_text(build) + " " \
		+ str(SectionRows.page_numbers(&"fc", build))
	return TestResult.new("control figures: the port figures never claim a spare count",
		not got.to_lower().contains("spare") and not got.to_lower().contains("free"), got)


static func _d_noise_is_the_installed_kd_through_rate_tune(build: Build, tune: RateTune) -> TestResult:
	var got := ControlFigures.d_noise_fraction(build, tune)
	var want := RateTune.d_noise_fraction(build, tune.kd.x)
	return TestResult.new("control figures: D noise is RateTune's arithmetic at the installed roll D",
		is_equal_approx(got, want) and got > 0.0, "%.5f vs %.5f" % [got, want])


static func _d_noise_without_a_tune_is_the_hand_tune(build: Build) -> TestResult:
	var got := ControlFigures.d_noise_fraction(build, null)
	var want := RateTune.d_noise_fraction(build, RateModeController.ROLL_PITCH_KD)
	return TestResult.new("control figures: with no tune, D noise is quoted at the hand tune (as FcDetails does)",
		is_equal_approx(got, want), "%.5f vs %.5f" % [got, want])


static func _d_noise_matches_the_fc_sheet(build: Build, tune: RateTune) -> TestResult:
	var sheet := FcDetails.new()
	sheet.render(build.fc, build, tune)
	var text := sheet.row_text("d_cost")
	sheet.free()
	var want := "%.1f%%" % (ControlFigures.d_noise_fraction(build, tune) * 100.0)
	return TestResult.new("control figures: the FC sheet's 'Noise at the motors' is the same figure",
		text.begins_with(want), "'%s' want '%s…'" % [text, want])


static func _link_mass_is_the_link_sheets_total(build: Build) -> TestResult:
	var sheet := LinkDetails.new()
	sheet.render_components(build)
	var text := sheet.row_text("total")
	sheet.free()
	var got := ControlFigures.link_mass_g(build)
	return TestResult.new("control figures: the link's mass is the Link sheet's own total",
		text == "%.1f g" % got and got > 0.0, "'%s' vs %.2f" % [text, got])


static func _link_uarts_count_the_receiver_only(build: Build) -> TestResult:
	var got := ControlFigures.link_uarts(build)
	return TestResult.new("control figures: the link takes one UART (the receiver; no GPS fitted)",
		got == 1, "%d" % got)


static func _pattern_parses_both_sides() -> TestResult:
	var got := ControlFigures.pattern_mm("30.5x30.5")
	var other := ControlFigures.pattern_mm("20x20")
	return TestResult.new("control figures: a bolt pattern parses to millimetres",
		got == Vector2(30.5, 30.5) and other == Vector2(20.0, 20.0), "%s %s" % [got, other])


static func _pattern_of_nonsense_is_zero() -> TestResult:
	var got := ControlFigures.pattern_mm("") + ControlFigures.pattern_mm("M3") \
		+ ControlFigures.pattern_mm("axb") + ControlFigures.pattern_mm("0x30.5")
	return TestResult.new("control figures: an unreadable pattern is zero, not a guessed size",
		got == Vector2.ZERO, str(got))


static func _d_ceiling_share_is_kd_over_ceiling(tune: RateTune) -> TestResult:
	var got := ControlFigures.d_ceiling_share(tune)
	var want := tune.kd.x / tune.kd_ceiling
	return TestResult.new("control figures: D's share of the noise ceiling is kd over the ceiling",
		is_equal_approx(got, want) and got > 0.1 and got < 0.5, "%.4f vs %.4f" % [got, want])


static func _time_constants_are_the_tunes(tune: RateTune) -> TestResult:
	var got := ControlFigures.time_constants_ms(tune)
	var want := tune.time_constant_s() * 1000.0
	return TestResult.new("control figures: loop time constants are the tune's own, in ms",
		got.is_equal_approx(want) and got.x > 5.0, "%s vs %s" % [got, want])


# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

static func _fc_row_reads_the_ports(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Control", build, []), &"fc")
	return TestResult.new("control rows: Flight controller reads the UARTs its parts use against the board's",
		row.get("number") == ControlFigures.ports_used_text(build) and row.get("line3") == row.get("number"),
		"'%s'" % row.get("number"))


static func _fc_row_fits_the_line(build: Build) -> TestResult:
	var text := str(_row(SectionRows.rows("Control", build, []), &"fc").get("number"))
	return TestResult.new("control rows: the Flight controller number fits a row's line 3",
		text != "" and text.length() <= WarningRows.SHORT_MAX + 2, "'%s' %d" % [text, text.length()])


## No receiver in the catalogue publishes an output power or a sensitivity, and the control path
## takes sticks from an input device: a range would be invented. Line 3 stays empty.
static func _receiver_row_leaves_range_empty(build: Build, tune: RateTune) -> TestResult:
	var row := _row(SectionRows.rows("Control", build, [], {"tune": tune}), &"receiver")
	return TestResult.new("control rows: Receiver & link states no range (no RF figures to compute one)",
		row.get("number") == "", "'%s'" % row.get("number"))


static func _tune_row_reads_d_against_the_ceiling(build: Build, tune: RateTune) -> TestResult:
	var row := _row(SectionRows.rows("Control", build, [], {"tune": tune}), &"tune")
	var want := "D at ~%d%% of noise ceiling" % roundi(ControlFigures.d_ceiling_share(tune) * 100.0)
	return TestResult.new("control rows: Tune reads its D against the gyro's noise ceiling, marked ~",
		row.get("number") == want, "'%s' want '%s'" % [row.get("number"), want])


static func _tune_row_fits_the_line(build: Build, tune: RateTune) -> TestResult:
	var text := str(_row(SectionRows.rows("Control", build, [], {"tune": tune}), &"tune").get("number"))
	return TestResult.new("control rows: the Tune number fits a row's line 3",
		text != "" and text.length() <= WarningRows.SHORT_MAX + 2, "'%s' %d" % [text, text.length()])


static func _tune_row_without_a_tune_is_empty(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Control", build, []), &"tune")
	return TestResult.new("control rows: with no tune in hand the Tune row states no number",
		row.get("number") == "" and row.get("choice") == "derived", "'%s'" % row.get("number"))


static func _tune_row_says_hand_tuned_when_overridden(build: Build) -> TestResult:
	var tune := RateTune.derive(build)
	tune.set_gains(0, Vector3(3.0, 0.2, 0.05))
	var row := _row(SectionRows.rows("Control", build, [], {"tune": tune}), &"tune")
	return TestResult.new("control rows: Tune reads 'hand-tuned' once an axis is set by hand",
		row.get("choice") == "hand-tuned", "'%s'" % row.get("choice"))


static func _tune_row_owns_the_tunes_warnings(build: Build) -> TestResult:
	var tune := RateTune.derive(build)
	tune.set_gains(0, Vector3(3.0, 0.2, 0.05))
	var row := _row(SectionRows.rows("Control", build, tune.warnings(), {"tune": tune}), &"tune")
	var owned: Array = row.get("warnings", [])
	return TestResult.new("control rows: the tune's own warnings land on the Tune row",
		owned.size() == 1 and (owned[0] as BuildWarning).id == &"tune_override", str(owned.size()))


# ---------------------------------------------------------------------------
# The page numbers
# ---------------------------------------------------------------------------

static func _fc_page_numbers(build: Build, tune: RateTune) -> TestResult:
	var got := SectionRows.page_numbers(&"fc", build, {"tune": tune})
	var want := [["Serial ports used", "2 of ~4–5"],
		["Gyro noise at the motors", "~%.1f%% at D %.3f" % [
			ControlFigures.d_noise_fraction(build, tune) * 100.0, tune.kd.x]]]
	return TestResult.new("page numbers: Flight controller shows ports used and gyro noise at the motors",
		got == want, "%s want %s" % [got, want])


static func _receiver_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"receiver", build)
	var want := [["Link mass", "%.1f g" % ControlFigures.link_mass_g(build)], ["UARTs it takes", "1"]]
	return TestResult.new("page numbers: Receiver & link shows the link's mass and the UARTs it takes",
		got == want, "%s want %s" % [got, want])


static func _tune_page_numbers(build: Build, tune: RateTune) -> TestResult:
	var got := SectionRows.page_numbers(&"tune", build, {"tune": tune})
	var tau := ControlFigures.time_constants_ms(tune)
	var want := [["Roll D vs noise ceiling", "%.3f of %.3f" % [tune.kd.x, tune.kd_ceiling]],
		["Loop τ roll · pitch · yaw", "%d · %d · %d ms" % [roundi(tau.x), roundi(tau.y), roundi(tau.z)]]]
	return TestResult.new("page numbers: Tune shows roll D against the ceiling and the loop time constants",
		got == want, "%s want %s" % [got, want])


# ---------------------------------------------------------------------------
# The drawings
# ---------------------------------------------------------------------------

static func _diagram(build: Build, mode: String, tune: RateTune = null) -> ControlDiagram:
	var d := ControlDiagram.new()
	d.show_build(build, mode, tune)
	return d


static func _fc_drawing_holds_the_three_patterns(build: Build) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_FC)
	var want := Vector2(30.5, 30.5)
	var ok: bool = d.stack.get("frame") == want and d.stack.get("fc") == want and d.stack.get("esc") == want
	var detail := str(d.stack)
	d.free()
	return TestResult.new("control drawing: the stack is the frame's, the FC's and the ESC's patterns, mm",
		ok, detail)


static func _states(d: ControlDiagram) -> Array:
	var out: Array = []
	for slot in d.slots:
		out.append(str(slot["state"]))
	return out


static func _fc_slots_are_the_parts_then_the_range(build: Build) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_FC)
	var states := _states(d)
	var names := [str(d.slots[0]["label"]), str(d.slots[1]["label"])] if d.slots.size() >= 2 else []
	d.free()
	return TestResult.new("control drawing: 5 slots — the receiver and the VTX, 2 empty to the low end, 1 dashed to the high",
		states == ["used", "used", "empty", "empty", "maybe"] and names == ["Receiver", "VTX"],
		"%s %s" % [states, names])


static func _fc_slots_past_a_typed_count_are_over(build: Build) -> TestResult:
	var copy := ReferenceBuild.build()
	PortBudget.set_count(copy.config, 1)
	var d := _diagram(copy, ControlDiagram.MODE_FC)
	var states := _states(d)
	d.free()
	return TestResult.new("control drawing: a part past the board's count is drawn over, in its own slot",
		states == ["used", "over"], str(states))


static func _fc_slots_with_no_published_count_are_the_parts_alone(build: Build) -> TestResult:
	var copy := _with_fc_catalog(build, {"processor": "F405"})
	var d := _diagram(copy, ControlDiagram.MODE_FC)
	var states := _states(d)
	var caption := d.ports_caption
	d.free()
	return TestResult.new("control drawing: with no published count only the parts are drawn, and it says so",
		states == ["used", "used"] and caption.contains("not published"), "%s '%s'" % [states, caption])


static func _link_drawing_lands_the_receiver_on_a_uart(build: Build) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_LINK)
	var receiver: Dictionary = d.wiring[0] if not d.wiring.is_empty() else {}
	d.free()
	return TestResult.new("control drawing: the receiver lands on a UART, with its name and mass",
		receiver.get("category") == "receiver" and bool(receiver.get("fitted"))
			and receiver.get("lands") == "UART"
			and receiver.get("name") == str(build.components["receiver"]["name"])
			and is_equal_approx(float(receiver.get("mass_g")), 2.0), str(receiver))


static func _link_drawing_marks_empty_bays(build: Build) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_LINK)
	var fitted: Array = []
	for bay in d.wiring:
		fitted.append(bool(bay["fitted"]))
	d.free()
	return TestResult.new("control drawing: all three bays are drawn, the GPS and buzzer bays empty",
		fitted == [true, false, false], str(fitted))


static func _link_drawing_names_the_mast_and_the_buzzers_power() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {"camera": "", "vtx": "", "antenna": "", "receiver": "rx_elrs_2400",
			"gps": "gps_masted_compact", "buzzer": "buzz_active_5v"})
	var d := _diagram(build, ControlDiagram.MODE_LINK)
	var gps: Dictionary = d.wiring[1]
	var buzzer: Dictionary = d.wiring[2]
	d.free()
	var mast := "mast %d mm" % roundi(build.rise_m_for(build.components["gps"]) * 1000.0)
	return TestResult.new("control drawing: the GPS carries its mast, the FC-powered buzzer says it dies with the pack",
		gps.get("note") == mast and gps.get("lands") == "UART" and buzzer.get("lands") == "beeper pad"
			and buzzer.get("note") == "FC 5 V · dies with the pack", "%s / %s" % [gps, buzzer])


static func _tune_drawing_gains_are_the_tunes(build: Build, tune: RateTune) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_TUNE, tune)
	var ok := d.gains.size() == 3
	for axis in d.gains.size():
		ok = ok and d.gains[axis]["in_force"] == tune.gains_for(axis) \
			and d.gains[axis]["derived"] == tune.derived_gains_for(axis) \
			and not bool(d.gains[axis]["overridden"])
	var detail := str(d.gains)
	d.free()
	return TestResult.new("control drawing: the tune table is the gains in force and the derived ones",
		ok, detail)


static func _tune_drawing_marks_a_hand_axis(build: Build) -> TestResult:
	var tune := RateTune.derive(build)
	tune.set_gains(2, Vector3(7.0, 0.4, 0.0))
	var d := _diagram(build, ControlDiagram.MODE_TUNE, tune)
	var flags: Array = []
	for row in d.gains:
		flags.append(bool(row["overridden"]))
	var yaw: Vector3 = d.gains[2]["in_force"] if d.gains.size() == 3 else Vector3.ZERO
	d.free()
	return TestResult.new("control drawing: an axis set by hand is marked, and shows the hand gains",
		flags == [false, false, true] and yaw == Vector3(7.0, 0.4, 0.0), "%s %s" % [flags, yaw])


static func _tune_drawing_ceiling_is_the_tunes(build: Build, tune: RateTune) -> TestResult:
	var d := _diagram(build, ControlDiagram.MODE_TUNE, tune)
	var got := d.kd_ceiling
	d.free()
	return TestResult.new("control drawing: the D ceiling drawn is the tune's own",
		is_equal_approx(got, tune.kd_ceiling) and got > 0.1, "%.4f" % got)


static func _page_definitions_name_their_drawings() -> TestResult:
	var modes := {}
	for definition in SectionRows.DEFINITIONS["Control"]:
		modes[definition["id"]] = str((definition["page"] as Dictionary).get("diagram", ""))
	return TestResult.new("control rows: each Control page names its drawing",
		modes == {&"fc": ControlDiagram.MODE_FC, &"receiver": ControlDiagram.MODE_LINK,
			&"tune": ControlDiagram.MODE_TUNE}, str(modes))
