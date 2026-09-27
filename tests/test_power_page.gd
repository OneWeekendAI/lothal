class_name TestPowerPage
extends RefCounted
## The Power item pages (lab dock design §3, §4): Battery, ESC and Harness, headless.
##
## What this suite guards: each page's numbers and its drawing come from ONE computation
## (`PowerFigures`), shared with the row, so the list, the two page numbers and the chart cannot
## disagree — and the worst-case draw the three pages quote is the one the harness checks use.
##
## One test per case.


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()

	# --- the shared figures
	out.append(_worst_draw_is_the_harness_checks_peak(build))
	out.append(_worst_draw_exceeds_the_nominal_datum(build))
	out.append(_worst_sag_is_draw_times_r(build))
	out.append(_pack_limit_is_mah_times_c(build))
	out.append(_hover_draw_is_the_hover_current(build))
	out.append(_flight_draw_is_the_profile_average(build))
	out.append(_load_line_falls_by_i_r(build))
	out.append(_esc_channel_reads_the_board_and_the_motors(build))
	out.append(_esc_drawn_is_a_quarter_of_the_worst(build))
	out.append(_harness_drop_is_the_checks_drop(build))

	# --- the rows
	out.append(_harness_row_reads_the_lead_drop(build))
	out.append(_pack_chart_worst_draw_label_matches_the_page(build))
	out.append(_harness_row_fits_the_line(build))

	# --- the page numbers
	out.append(_battery_page_numbers(build))
	out.append(_esc_page_numbers(build))
	out.append(_harness_page_numbers(build))

	# --- the drawings
	out.append(_pack_chart_lines_are_the_packs(build))
	out.append(_pack_chart_marks_the_rating(build))
	out.append(_pack_chart_marks_the_worst_draw(build))
	out.append(_pack_chart_flight_point_carries_flight_time(build))
	out.append(_esc_chart_bars_are_the_channel(build))
	out.append(_esc_chart_headroom_is_the_builds(build))
	out.append(_page_definitions_name_their_drawings())

	# --- the sheets beside the drawings
	out.append(_battery_sheet_hides_the_whole_builds_warnings(build))
	out.append(_esc_sheet_hides_the_whole_builds_warnings(build))
	out.append(_harness_sheet_drops_its_prose_on_the_dock(build))
	out.append(_harness_sheet_keeps_its_prose_off_the_dock(build))
	out.append(_charger_drops_its_prose_on_the_dock(build))
	return out


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


static func _worst_draw_is_the_harness_checks_peak(build: Build) -> TestResult:
	var got := PowerFigures.worst_draw_a(build)
	var want := float(HarnessChecks.draw(build)["peak_a"])
	return TestResult.new("power figures: the worst draw is HarnessChecks' peak (fresh pack, ceiling)",
		absf(got - want) < 0.01 and got > 50.0, "%.3f vs %.3f" % [got, want])


## A fresh pack rests above nominal and drives the motors harder: the worst case is not the datum.
static func _worst_draw_exceeds_the_nominal_datum(build: Build) -> TestResult:
	var worst := PowerFigures.worst_draw_a(build)
	var nominal := PowerFigures.nominal_full_throttle_a(build)
	return TestResult.new("power figures: a fresh pack draws more at the ceiling than the nominal datum",
		worst > nominal + 5.0 and is_equal_approx(nominal,
			build.hover_current_a(build.max_throttle_fraction())), "%.1f vs %.1f" % [worst, nominal])


static func _worst_sag_is_draw_times_r(build: Build) -> TestResult:
	var reading := HarnessChecks.draw(build)
	var want := float(reading["open_circuit_v"]) - float(reading["terminal_v"])
	var got := PowerFigures.worst_sag_v(build)
	return TestResult.new("power figures: the worst sag is I × R, the powertrain's own drop",
		absf(got - want) < 0.001 and got > 0.5, "%.3f vs %.3f" % [got, want])


static func _pack_limit_is_mah_times_c(build: Build) -> TestResult:
	var got := PowerFigures.pack_limit_a(build)
	return TestResult.new("power figures: the pack limit is mAh × C (1500 mAh × 75C = 112.5 A)",
		is_equal_approx(got, 112.5), "%.2f" % got)


static func _hover_draw_is_the_hover_current(build: Build) -> TestResult:
	var got := PowerFigures.hover_draw_a(build)
	var want := build.hover_current_a(build.hover_throttle())
	return TestResult.new("power figures: hover draw is the current at hover throttle",
		is_equal_approx(got, want) and got > 1.0, "%.2f vs %.2f" % [got, want])


static func _flight_draw_is_the_profile_average(build: Build) -> TestResult:
	var got := PowerFigures.flight_draw_a(build)
	var want := build.average_flight_current_a()
	return TestResult.new("power figures: flight draw is the profile average flight time uses",
		is_equal_approx(got, want) and got > PowerFigures.hover_draw_a(build), "%.2f vs %.2f" % [got, want])


static func _load_line_falls_by_i_r(build: Build) -> TestResult:
	var line := PowerFigures.load_line(build, 16.8, 100.0, 4)
	var first: Vector2 = line[0]
	var last: Vector2 = line[line.size() - 1]
	var r := float(build.battery["specs"]["internal_r_ohm"])
	return TestResult.new("power figures: the load line starts at rest and falls by I × R",
		line.size() == 5 and first == Vector2(0.0, 16.8)
			and is_equal_approx(last.x, 100.0) and is_equal_approx(last.y, 16.8 - 100.0 * r),
		"%s … %s" % [first, last])


static func _esc_channel_reads_the_board_and_the_motors(build: Build) -> TestResult:
	var got := PowerFigures.esc_channel(build)
	return TestResult.new("power figures: an ESC channel is the board's 45/55 A against the motors' 32 A",
		is_equal_approx(float(got["rating"]), 45.0) and is_equal_approx(float(got["burst"]), 55.0)
			and is_equal_approx(float(got["motor_max"]), build.motor_demand_per_channel_a())
			and is_equal_approx(float(got["headroom"]), build.esc_channel_headroom_a()), str(got))


static func _esc_drawn_is_a_quarter_of_the_worst(build: Build) -> TestResult:
	var got := float(PowerFigures.esc_channel(build)["drawn"])
	return TestResult.new("power figures: the draw per channel is a quarter of the worst total",
		is_equal_approx(got, PowerFigures.worst_draw_a(build) / 4.0), "%.2f" % got)


static func _harness_drop_is_the_checks_drop(build: Build) -> TestResult:
	var w := _warning(build, &"harness_voltage_drop")
	var want := float(w.values["harness_drop_v"]) if w != null else -1.0
	var got := PowerFigures.harness_drop_v(build)
	return TestResult.new("power figures: the lead drop is the harness check's own drop",
		absf(got - want) < 0.0005 and got > 0.0, "%.4f vs %.4f" % [got, want])


static func _harness_row_reads_the_lead_drop(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Power", build, []), &"harness")
	# "at 112 A", literally (2026-09-27): the draw at the pack-limited ceiling IS the 112.5 A rating,
	# and roundi() printed it "113" beside the Battery page's "112 A of 112 A". One formatter now.
	var want := "~%.2f V lost in leads at 112 A" % PowerFigures.harness_drop_v(build)
	return TestResult.new("power rows: Harness reads the worst lead drop, marked ~",
		row.get("number") == want, "'%s' want '%s'" % [row.get("number"), want])


static func _harness_row_fits_the_line(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Power", build, []), &"harness")
	var text := str(row.get("number"))
	return TestResult.new("power rows: the Harness number fits a row's line 3",
		text != "" and text.length() <= WarningRows.SHORT_MAX + 2, "'%s' %d" % [text, text.length()])


static func _battery_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"battery", build)
	# "of 112 A": the rating as the Pack sheet prints it ("75C (112 A)"), not rounded up to 113.
	# The draw is printed the same way (2026-09-27): at a binding pack limit it IS the rating, and
	# "%d" rounded 112.5 up to 113 beside its own rating's 112.
	var want := [["Full-throttle draw", "112 A of 112 A"],
		["Sag at full throttle", "−%.1f V" % PowerFigures.worst_sag_v(build)]]
	return TestResult.new("page numbers: Battery shows the worst draw against its rating, and the sag",
		got == want, "%s want %s" % [got, want])


static func _esc_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"esc", build)
	var want := [["Headroom per channel", "13 A · 29%"], ["Motors' max per channel", "32 A of 45 A"]]
	return TestResult.new("page numbers: ESC shows headroom per channel and the motors' ask",
		got == want, "%s want %s" % [got, want])


static func _harness_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"harness", build)
	# "at 112 A", literally — see _harness_row_reads_the_lead_drop.
	var want := [["Lead drop, full throttle", "~%.2f V at 112 A" % PowerFigures.harness_drop_v(build)],
		["Harness mass", "~%.1f g" % PowerFigures.harness_mass_g(build)]]
	return TestResult.new("page numbers: Harness shows the lead drop and the harness mass, both ~",
		got == want, "%s want %s" % [got, want])


static func _diagram(build: Build, mode: String) -> PowerDiagram:
	var d := PowerDiagram.new()
	d.show_build(build, mode)
	return d


static func _pack_chart_lines_are_the_packs(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_PACK)
	var ok := d.fresh_line == PowerFigures.load_line(build, PowerFigures.fresh_rest_v(build), d.max_a) \
		and d.nominal_line == PowerFigures.load_line(build, PowerFigures.nominal_v(build), d.max_a) \
		and is_equal_approx((d.fresh_line[0] as Vector2).y, 16.8) \
		and is_equal_approx((d.nominal_line[0] as Vector2).y, 14.8)
	var detail := "%s / %s" % [d.fresh_line, d.nominal_line]
	d.free()
	return TestResult.new("power drawing: the chart's two load lines are the fresh pack's and nominal's",
		ok, detail)


static func _pack_chart_marks_the_rating(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_PACK)
	var ok := is_equal_approx(d.limit_a, PowerFigures.pack_limit_a(build)) and d.max_a > d.limit_a
	var detail := "limit %.1f, axis %.1f" % [d.limit_a, d.max_a]
	d.free()
	return TestResult.new("power drawing: the pack's rated current is marked, inside the axis", ok, detail)


static func _point(d: PowerDiagram, prefix: String) -> Dictionary:
	for p in d.points:
		if str(p["label"]).begins_with(prefix):
			return p
	return {}


static func _pack_chart_marks_the_worst_draw(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_PACK)
	var p := _point(d, "full throttle, fresh")
	var ok := not p.is_empty() and is_equal_approx(float(p["amps"]), PowerFigures.worst_draw_a(build)) \
		and is_equal_approx(float(p["volts"]), 16.8 - PowerFigures.worst_sag_v(build))
	d.free()
	return TestResult.new("power drawing: full throttle on a fresh pack sits at the page's draw and sag",
		ok, str(p))


## The chart's own label for that point says the same number as the page above it: at the
## pack-limited ceiling the draw IS the 112.5 A rating, which roundi() printed "113" (2026-09-27).
static func _pack_chart_worst_draw_label_matches_the_page(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_PACK)
	var p := _point(d, "full throttle, fresh")
	var label := str(p.get("label", ""))
	d.free()
	return TestResult.new("power drawing: the fresh full-throttle label reads the page's 112 A",
		label == "full throttle, fresh 112 A", label)


static func _pack_chart_flight_point_carries_flight_time(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_PACK)
	var p := _point(d, "flying")
	var seconds := roundi(build.flight_time_min() * 60.0)
	var want := "flying %d A · ~%d:%02d" % [roundi(PowerFigures.flight_draw_a(build)),
		floori(seconds / 60.0), seconds % 60]
	var ok := not p.is_empty() and str(p["label"]) == want \
		and is_equal_approx(float(p["amps"]), PowerFigures.flight_draw_a(build))
	d.free()
	return TestResult.new("power drawing: the flight-average point carries the flight time it gives",
		ok, "%s want %s" % [p, want])


static func _esc_chart_bars_are_the_channel(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_ESC)
	var channel := PowerFigures.esc_channel(build)
	var amps: Array = []
	for bar in d.bars:
		amps.append(float(bar["amps"]))
	var ok := amps == [float(channel["rating"]), float(channel["motor_max"]), float(channel["drawn"])] \
		and is_equal_approx(d.burst_a, 55.0)
	d.free()
	return TestResult.new("power drawing: the ESC bars are the rating, the motors' ask and the draw",
		ok, str(amps))


static func _esc_chart_headroom_is_the_builds(build: Build) -> TestResult:
	var d := _diagram(build, PowerDiagram.MODE_ESC)
	var ok := is_equal_approx(d.headroom_a, build.esc_channel_headroom_a())
	var detail := "%.2f" % d.headroom_a
	d.free()
	return TestResult.new("power drawing: the marked headroom is Build's per-channel headroom", ok, detail)


static func _definition(id: StringName) -> Dictionary:
	for d in SectionRows.DEFINITIONS["Power"]:
		if d["id"] == id:
			return d["page"]
	return {}


static func _page_definitions_name_their_drawings() -> TestResult:
	var got := [_definition(&"battery"), _definition(&"esc"), _definition(&"harness")]
	var want := [{"panels": ["Pack"], "diagram": "pack"}, {"panels": ["ESC"], "diagram": "esc"},
		{"panels": ["Harness"], "diagram": "harness"}]
	return TestResult.new("power rows: each page names its drawing", got == want, str(got))


## The Pack sheet listed every warning in the build under the pack's rows; the page's own Why? list
## replaces it.
static func _battery_sheet_hides_the_whole_builds_warnings(build: Build) -> TestResult:
	var panel := BatteryDetails.new()
	panel.set_warnings_visible(false)
	panel.render(build.battery, build)
	var shown := panel.warnings_visible()
	panel.free()
	return TestResult.new("battery sheet: on a dock page the whole-build warning list stays hidden",
		not build.warnings().is_empty() and not shown, "shown %s" % shown)


static func _esc_sheet_hides_the_whole_builds_warnings(build: Build) -> TestResult:
	var panel := EscDetails.new()
	panel.set_warnings_visible(false)
	panel.render(build.esc, build)
	var shown := panel.warnings_visible()
	panel.free()
	return TestResult.new("ESC sheet: on a dock page the whole-build warning list stays hidden",
		not build.warnings().is_empty() and not shown, "shown %s" % shown)


## The "class-typical defaults" paragraph is the `~` the page's numbers carry; on the dock it goes.
static func _harness_sheet_drops_its_prose_on_the_dock(build: Build) -> TestResult:
	var panel := HarnessPanel.new()
	panel.set_caption_visible(false)
	panel.render(build)
	var shown := panel.caption_visible()
	panel.free()
	return TestResult.new("harness sheet: on a dock page the prose caption is hidden", not shown, "")


static func _harness_sheet_keeps_its_prose_off_the_dock(build: Build) -> TestResult:
	var panel := HarnessPanel.new()
	panel.render(build)
	var shown := panel.caption_visible()
	panel.free()
	return TestResult.new("harness sheet: elsewhere the prose caption stays", shown, "")


## "Flying and bench runs drain at 1:1. Charging is compressed, because…" is a paragraph; the dock's
## Battery page shows the charger's state and control, not its argument.
static func _charger_drops_its_prose_on_the_dock(build: Build) -> TestResult:
	var panel := PackChargePanel.new(PackCharge.new(), PartsCatalog.load_default())
	panel.set_note_visible(false)
	panel.render(build)
	var shown := panel.note_visible()
	panel.free()
	return TestResult.new("charger: on a dock page the compression paragraph is hidden", not shown, "")
