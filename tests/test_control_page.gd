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
