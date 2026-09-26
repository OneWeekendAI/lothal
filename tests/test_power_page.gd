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
	out.append(_harness_row_fits_the_line(build))

	# --- the page numbers
	out.append(_battery_page_numbers(build))
	out.append(_esc_page_numbers(build))
	out.append(_harness_page_numbers(build))
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
	var want := "~%.2f V lost in leads at %d A" % [PowerFigures.harness_drop_v(build),
		roundi(PowerFigures.worst_draw_a(build))]
	return TestResult.new("power rows: Harness reads the worst lead drop, marked ~",
		row.get("number") == want, "'%s' want '%s'" % [row.get("number"), want])


static func _harness_row_fits_the_line(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Power", build, []), &"harness")
	var text := str(row.get("number"))
	return TestResult.new("power rows: the Harness number fits a row's line 3",
		text != "" and text.length() <= WarningRows.SHORT_MAX + 2, "'%s' %d" % [text, text.length()])


static func _battery_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"battery", build)
	var want := [["Full-throttle draw", "%d A of %d A" % [roundi(PowerFigures.worst_draw_a(build)),
			roundi(PowerFigures.pack_limit_a(build))]],
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
	var want := [["Lead drop, full throttle", "~%.2f V at %d A" % [PowerFigures.harness_drop_v(build),
			roundi(PowerFigures.worst_draw_a(build))]],
		["Harness mass", "~%d g" % roundi(PowerFigures.harness_mass_g(build))]]
	return TestResult.new("page numbers: Harness shows the lead drop and the harness mass, both ~",
		got == want, "%s want %s" % [got, want])
