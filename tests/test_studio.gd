class_name TestStudio
extends RefCounted
## Studio and the flight log library (LTHL-54).
##
## ## The one that shapes the rest: listing must not read rows
##
## A three-minute log is ~197 MB. The whole design of FlightLogLibrary rests on listing costing one
## line of I/O per file, and the failure it exists to prevent — a library that parses files to
## enumerate them — is INVISIBLE in a suite of small fixtures. A three-row fixture lists instantly
## whether the library reads one line or all three, which would make the check a test that cannot
## fail.
##
## So the fixture below is deliberately large, and the bound it is judged against is MEASURED on
## the machine running the test rather than written down here. See _test_listing_is_cheap, and the
## note above the constants for the version of this test that could not fail.
##
## ## What this suite does NOT do
##
## It does not render anything. No frame is processed by the test runner, so every screen here is
## constructed, driven by calling its own methods, asserted against its own state, and freed —
## the pattern tests/test_build_panel.gd established.

## A directory of this suite's own, never the builder's. FlightLogLibrary takes an injected
## directory for exactly this reason: a test that swept user://logs would delete real flights.
const TEST_DIR := "user://test_studio_logs"

## Big enough that a row-parsing library is measurably slower than a header-only one. At 55 columns
## this is a little over 2 MB per file — small next to a real log, and measured: parsing all eight
## costs ~85 ms against ~10 ms for one, which is the gap the bound below is drawn through.
const FIXTURE_ROWS := 2000
const FIXTURE_FILES := 8

## THE BUDGET IS MEASURED, NOT DECLARED, and the first version of this test is why.
##
## It asserted listing came in under a fixed 250 ms. That number was a guess, and the guess was
## wrong in the direction that matters: a deliberately row-parsing library was measured at 84 ms
## on this fixture and PASSED. The check could not fail, which is the exact thing
## feedback_plans_that_cannot_fail exists to catch, and it was caught only by building the broken
## library and watching the test stay green.
##
## Enlarging the fixture until 250 ms bit would have worked on this machine and nowhere else. So
## the bound is now the cost of the work being ruled out, measured on the same machine in the same
## run: **listing every log must cost less than fully reading ONE of them.** A header-only library
## reads FIXTURE_FILES lines and comes in far under a single file read. A row-parsing one reads
## every file and cannot come in under one of them. The ratio is what is being asserted, so a slow
## machine slows both sides and the check holds.


static func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for name in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [TEST_DIR, name]))
	DirAccess.remove_absolute(absolute)


static func _fresh_dir() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))


## Writes a real log through the real recorder, so the fixtures carry a real header rather than a
## hand-written approximation of one. A suite whose fixtures were written by hand would agree with
## itself about a header format the recorder had since changed.
static func _write_log(name: String, rows: int, jumps: int = 0) -> String:
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	var throttle := ReferenceBuild.hover_throttle()
	core.prime_motors(throttle)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	var recorder := FlightRecorder.new(build, 1, null, core.gyro)
	recorder.discontinuities = jumps

	for _i in rows:
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, 0.001)
		core.step(cmds, 0.001)
		recorder.capture(core.observables)

	var path := "%s/%s" % [TEST_DIR, name]
	recorder.save(path)
	return path


static func run() -> Array:
	var results: Array = []
	results.append_array(_test_listing_is_cheap())
	results.append_array(_test_ordering_and_rows())
	results.append_array(_test_bad_files())
	results.append_array(_test_screen())
	results.append_array(_test_report_fits())
	results.append_array(_test_shell_room())
	results.append_array(_test_log_reader())
	results.append_array(_test_trace_decimation())
	results.append_array(_test_trace_legend())
	results.append_array(_test_channel_picker())
	results.append_array(_test_trace_lanes())
	results.append_array(_test_gap_view())
	_clean()
	return results


## THE ROOM OPENS ON ITS OWN QUESTION. Two anonymous lines on one axis hid the gap at every ratio,
## because at overlay scale gyro and omega sit on top of each other whether the answer is 1.0x or
## 7x. The difference, drawn at ITS OWN scale beneath them, is what makes the answer visible.
static func _test_gap_view() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260816-120000.csv", 300)

	var studio := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	studio.select("flight-20260816-120000.csv")

	results.append(TestResult.new(
		"Studio opens in the gap view, on roll, rather than on a free channel picker",
		studio.view_mode == StudioScreen.ViewMode.GAP and studio.gap_axis == 0,
		"mode=%d axis=%d" % [studio.view_mode, studio.gap_axis]))

	var names := studio._trace.channel_names()
	results.append(TestResult.new(
		"the gap view draws the sensor, the truth, and their difference — three series, not two",
		names.size() == 3 and Array(names).has("gyro_x_rad_s")
			and Array(names).has("omega_x_rad_s")
			and Array(names).has(StudioScreen.DIFFERENCE_CHANNEL),
		"drawn: %s" % ", ".join(names)))

	# The overlay pair shares one lane because they share a unit — that is what makes them
	# comparable. The difference is its OWN lane, at its own scale, which is the entire point: at
	# overlay scale a 1.0x gap and a 7x gap look identical.
	var lanes := studio._trace.lanes()
	results.append(TestResult.new(
		"the difference gets its own lane, so a small gap is still visible",
		lanes.size() == 2,
		"%d lanes in the gap view" % lanes.size()))

	# The difference must be the ACTUAL subtraction, not a copy of either input. Asserted against
	# the file through an independent reader, so a bug that drew gyro twice cannot pass.
	var path := "%s/flight-20260816-120000.csv" % TEST_DIR
	var gyro_oracle := TestFlightRecorder._column(path, "gyro_x_rad_s")
	var omega_oracle := TestFlightRecorder._column(path, "omega_x_rad_s")
	var drawn_here := studio._trace.value_at(StudioScreen.DIFFERENCE_CHANNEL,
		studio._trace.times[100])
	results.append(TestResult.new(
		"the difference series is sensor minus truth, sample for sample",
		gyro_oracle.size() > 100
			and absf(drawn_here - (gyro_oracle[100] - omega_oracle[100])) < 1e-9,
		"difference at row 100 reads %.9f, oracle %.9f" % [
			drawn_here, gyro_oracle[100] - omega_oracle[100]]))

	# Switching axis re-reads a different pair rather than relabelling the same one.
	studio.set_gap_axis(1)
	var pitch_names := studio._trace.channel_names()
	results.append(TestResult.new(
		"the axis selector reads a different pair rather than relabelling the same one",
		Array(pitch_names).has("gyro_y_rad_s") and Array(pitch_names).has("omega_y_rad_s")
			and not Array(pitch_names).has("gyro_x_rad_s"),
		"pitch view draws: %s" % ", ".join(pitch_names)))

	# The 55-channel explorer is still reachable, and is still the header's list.
	studio.set_view_mode(StudioScreen.ViewMode.EXPLORE)
	results.append(TestResult.new(
		"the free channel explorer is still there, still offering every header column",
		studio._channel_list.item_count == FlightRecorder.COLUMNS.size() - 1
			and studio._channel_list.visible,
		"%d channels offered in explore mode" % studio._channel_list.item_count))

	# And the picker is hidden in gap view rather than sitting there as a wall of names below a
	# chart it is not driving.
	studio.set_view_mode(StudioScreen.ViewMode.GAP)
	results.append(TestResult.new(
		"the channel wall is not on screen while the gap view is driving the chart",
		not studio._channel_list.visible,
		"picker hidden in gap view"))

	studio.free()
	return results


## THE ONE THE DESIGN RESTS ON: listing must read headers, not rows.
##
## Measured against the cost of the thing being ruled out rather than against a number — see
## LISTING_BUDGET_MS above for what happened to the version that used a number.
static func _test_listing_is_cheap() -> Array:
	_fresh_dir()
	var first := ""
	for i in FIXTURE_FILES:
		var path := _write_log("flight-2026081%d-120000.csv" % i, FIXTURE_ROWS)
		if first.is_empty():
			first = path

	# The reference: what parsing ONE log costs, done here so the bound is calibrated on the
	# machine actually running the test rather than on the machine that wrote it.
	var reference_start := Time.get_ticks_usec()
	var _sink := 0.0
	for line in FileAccess.get_file_as_string(first).split("\n"):
		for cell in line.split(","):
			_sink += float(cell)
	var one_file_us := Time.get_ticks_usec() - reference_start

	var started := Time.get_ticks_usec()
	var library := FlightLogLibrary.load_from(TEST_DIR)
	var listing_us := Time.get_ticks_usec() - started

	return [TestResult.new(
		"listing %d logs costs less than reading ONE of them — headers, not rows" % FIXTURE_FILES,
		library.count() == FIXTURE_FILES and listing_us < one_file_us,
		"%d logs (%d rows on disk) listed in %d us; parsing one file costs %d us" % [
			library.count(), FIXTURE_FILES * FIXTURE_ROWS, listing_us, one_file_us])]


static func _test_ordering_and_rows() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260815-090400.csv", 40)
	_write_log("flight-20260816-143200.csv", 60, 3)
	_write_log("flight-20260816-141900.csv", 20)

	var library := FlightLogLibrary.load_from(TEST_DIR)
	var ids := library.ids()

	# Newest first, off the FILENAME. This works only because LTHL-51 zero-padded the timestamp,
	# which is what makes lexical order and chronological order the same order. A library sorting
	# by mtime would reorder a builder's whole history the day they restored a backup.
	results.append(TestResult.new(
		"flights list newest first, from the zero-padded filename rather than mtime",
		ids.size() == 3 and ids[0] == "flight-20260816-143200.csv"
			and ids[1] == "flight-20260816-141900.csv"
			and ids[2] == "flight-20260815-090400.csv",
		"order: %s" % ", ".join(ids)))

	# THE WARNING BELONGS TO THE ROW. A builder about to compute a spectrum across a teleport must
	# learn it before they pick the file, not after — a warning that only appears once you have
	# committed to a flight arrives too late to change the decision it exists to inform. Both
	# directions are asserted: a clean flight must NOT be marked, or the mark means nothing.
	var warned := library.row("flight-20260816-143200.csv")
	var clean := library.row("flight-20260816-141900.csv")
	results.append(TestResult.new(
		"a respawn teleport marks the LIST ROW, and a clean flight does not",
		bool(warned["warn"]) and not bool(clean["warn"]),
		"3-teleport log warn=%s, clean log warn=%s" % [warned["warn"], clean["warn"]]))

	results.append(TestResult.new(
		"a row carries when, how long and which aircraft",
		str(warned["when"]) == "2026-08-16  14:32"
			# 60 rows one millisecond apart span 59 ms, not 60 — duration is last minus first, and
			# a log's first row is the state after the first step rather than before it.
			and absf(float(warned["duration_s"]) - 0.059) < 1e-6
			and str(warned["aircraft"]).begins_with("frame_5in_freestyle/"),
		"%s | %.3f s | %s" % [warned["when"], warned["duration_s"], warned["aircraft"]]))

	# Display only, and it must stay that way — a truncated fingerprint treated as an identity
	# would be the lossy second spelling the whole "a log does not define an aircraft" rule guards.
	results.append(TestResult.new(
		"the list truncates a six-part fingerprint to three and marks it as truncated",
		FlightLogLibrary.short_fingerprint("a/b/c/d/e/f") == "a/b/c/…"
			and FlightLogLibrary.short_fingerprint("a/b") == "a/b",
		"a/b/c/d/e/f -> %s" % FlightLogLibrary.short_fingerprint("a/b/c/d/e/f")))

	return results


## json_store.gd's rule, carried into a directory of files a builder can open in Finder: a bad file
## is a warning and a defaulted result, never a crash. The entry STAYS LISTED, because a log
## truncated by closing the laptop mid-write is exactly the file they want to find and delete.
static func _test_bad_files() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260816-120000.csv", 30)

	var truncated := FileAccess.open("%s/flight-20260816-130000.csv" % TEST_DIR, FileAccess.WRITE)
	truncated.store_line("#{\"schema\": 1, \"aircraft\": {")
	truncated.close()

	var garbage := FileAccess.open("%s/flight-20260816-140000.csv" % TEST_DIR, FileAccess.WRITE)
	garbage.store_line("this is not a log at all")
	garbage.close()

	var empty := FileAccess.open("%s/flight-20260816-150000.csv" % TEST_DIR, FileAccess.WRITE)
	empty.close()

	# A builder's log folder is a real folder. A stray note or a .DS_Store must not become a row.
	var stray := FileAccess.open("%s/notes.txt" % TEST_DIR, FileAccess.WRITE)
	stray.store_line("remember to check the 6S pack")
	stray.close()

	var library := FlightLogLibrary.load_from(TEST_DIR)
	results.append(TestResult.new(
		"a truncated, garbage or empty log is LISTED and marked unreadable rather than hidden or fatal",
		library.count() == 4
			and library.is_readable("flight-20260816-120000.csv")
			and not library.is_readable("flight-20260816-130000.csv")
			and not library.is_readable("flight-20260816-140000.csv")
			and not library.is_readable("flight-20260816-150000.csv"),
		"%d rows listed, 1 readable" % library.count()))

	results.append(TestResult.new(
		"a non-csv file in the log directory is not a flight",
		not library.has("notes.txt"),
		"notes.txt is not listed"))

	# The unreadable row must still describe itself well enough to be acted on, since deleting it
	# is the only thing a builder can do with it.
	var row := library.row("flight-20260816-130000.csv")
	results.append(TestResult.new(
		"an unreadable log still says when it was and that it cannot be read",
		str(row["when"]) == "2026-08-16  13:00" and not bool(row["readable"])
			and bool(row["warn"]),
		"%s | %s" % [row["when"], row["aircraft"]]))

	results.append(TestResult.new(
		"a missing directory lists as empty rather than failing",
		FlightLogLibrary.load_from("user://no_such_log_dir").count() == 0,
		"absent directory reads as 0 flights"))

	return results


static func _test_screen() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260816-120000.csv", 30)
	_write_log("flight-20260816-130000.csv", 40, 2)

	var studio := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	results.append(TestResult.new(
		"Studio opens listing every flight, with nothing selected",
		studio._list.item_count == 2 and studio.selected_id.is_empty()
			and studio._delete_button.disabled,
		"%d rows, selection %s" % [studio._list.item_count,
			"(none)" if studio.selected_id.is_empty() else studio.selected_id]))

	studio.select("flight-20260816-130000.csv")
	var report_text := ""
	for child in studio._report.get_children():
		if child is Label:
			report_text += (child as Label).text + "\n"
		for grandchild in child.get_children():
			if grandchild is Label:
				report_text += (grandchild as Label).text + "\n"

	# The FULL fingerprint in the pane, against the rail's truncation.
	results.append(TestResult.new(
		"the report names the whole aircraft, all six parts, not the truncated form",
		report_text.contains(ReferenceBuild.build().fingerprint()),
		"pane carries the six-part fingerprint"))

	# The count is in the header so a reader cannot compute a spectrum across a teleport without
	# being told. A count rendered as one more grey number is a count told to nobody, so this
	# asserts it reads as a WARNING and says what it costs.
	results.append(TestResult.new(
		"the pane warns about respawn teleports and says what they do to the data",
		report_text.contains("2 respawn teleports")
			and report_text.to_lower().contains("acceleration that never happened"),
		"the discontinuity warning is present and explains itself"))

	# validation.md §9: vibration is tier-three and LTHL-18 could not promote it. The ranking
	# between builds is trustworthy, the absolute number is not, and a pane showing a sharp
	# resonance with no caveat has told a builder something Lothal does not know.
	results.append(TestResult.new(
		"the vibration caveat sits in the pane beside the number, not in a tooltip",
		report_text.contains("resonance") and report_text.contains("not sourced"),
		"the caveat travels with the figure"))

	# A clean flight must not carry the warning, or the warning means nothing.
	studio.select("flight-20260816-120000.csv")
	var clean_text := ""
	for child in studio._report.get_children():
		if child is Label:
			clean_text += (child as Label).text + "\n"
	results.append(TestResult.new(
		"a clean flight's pane says it is continuous rather than warning about nothing",
		not clean_text.contains("respawn teleport"),
		"no teleport warning on a continuous flight"))

	var deleted := studio.delete_selected()
	results.append(TestResult.new(
		"deleting a flight removes the file and the row, and clears the selection",
		deleted and studio._list.item_count == 1 and studio.selected_id.is_empty()
			and not FileAccess.file_exists("%s/flight-20260816-120000.csv" % TEST_DIR),
		"%d rows left, file gone" % studio._list.item_count))

	studio.free()

	_fresh_dir()
	var empty_studio := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	results.append(TestResult.new(
		"a builder who has never pressed R sees an instruction, not a blank screen",
		empty_studio._list.item_count == 1 and not empty_studio._list.is_item_selectable(0),
		"empty state: %s" % empty_studio._list.get_item_text(0)))
	empty_studio.free()

	return results


## THE CROP IS ARITHMETIC. 120 + 190 of forced minimum width plus separation does not fit in a
## 336 px pane once its margins and scrollbar are taken, which is why the gap readout rendered as
## "... rad/" with the rest past the pane edge. The check is on the WIDTHS, not on pixels, because
## the suite renders no frames — and on the sum per row, because each label is individually under
## the pane width and only their sum is not.
static func _test_report_fits() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260816-120000.csv", 30)

	var studio := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	studio.select("flight-20260816-120000.csv")

	var usable := StudioScreen.usable_report_width()
	var widest := 0.0
	var offender := ""
	for section in studio._report.get_children():
		var demanded := 0.0
		var _labels := 0
		for child in section.get_children():
			if child is Control:
				demanded += (child as Control).custom_minimum_size.x
				_labels += 1
		if section is Control and section.get_child_count() == 0:
			demanded = (section as Control).custom_minimum_size.x
		if demanded > widest:
			widest = demanded
			offender = str(section.name)

	results.append(TestResult.new(
		"no report row demands more width than the pane can give it",
		widest <= usable,
		"widest row demands %.0f px of a usable %.0f (%s)" % [widest, usable, offender]))

	# A long value must WRAP, not force the row wider. autowrap alone does not do this while a
	# custom_minimum_size.x is set — the label wins and the pane clips.
	studio._render_report_reset()
	studio._add_report_row("fingerprint", "x".repeat(200))
	var row: Node = studio._report.get_child(studio._report.get_child_count() - 1)
	var value_label: Label = null
	for child in row.get_children():
		if child is Label:
			value_label = child as Label
	results.append(TestResult.new(
		"a long value wraps inside the pane instead of forcing the row past its edge",
		value_label != null
			and value_label.autowrap_mode != TextServer.AUTOWRAP_OFF
			and is_zero_approx(value_label.custom_minimum_size.x),
		"value label min width %.0f, autowrap %s" % [
			0.0 if value_label == null else value_label.custom_minimum_size.x,
			"off" if value_label == null else str(value_label.autowrap_mode)]))

	# The value column is MONOSPACE, and that is legibility rather than decoration: a column of
	# readouts in a proportional font does not line up, and these are numbers a builder scans
	# rather than reads. It carries no minimum width, which is what distinguishes restoring the
	# font from restoring the crop.
	results.append(TestResult.new(
		"report values keep the monospace readout font, without regaining a minimum width",
		value_label != null and value_label.theme_type_variation == &"ReadoutLabel"
			and is_zero_approx(value_label.custom_minimum_size.x),
		"variation %s, min width %.0f" % [
			"(none)" if value_label == null else str(value_label.theme_type_variation),
			0.0 if value_label == null else value_label.custom_minimum_size.x]))

	studio.free()
	return results


## ---------------------------------------------------------------------------
## The Rust reader (LTHL-55)
## ---------------------------------------------------------------------------
##
## The crate is panic = "abort", so a single unwrap on a malformed CSV takes the whole application
## down while a builder is browsing. Every case below is a file a builder could plausibly have on
## disk, and the assertion is always the same: a reason, not a crash. If any of these panics, the
## test runner dies rather than reporting a failure — which is itself the loudest possible signal.
static func _test_log_reader() -> Array:
	var results: Array = []
	_fresh_dir()
	var good := _write_log("flight-20260816-120000.csv", 200)

	var read: Dictionary = LogReader.read_columns(good,
		PackedStringArray(["t_s", "gyro_x_rad_s", "m1_rpm"]))
	var columns: Dictionary = read.get("columns", {})
	var times: PackedFloat64Array = columns.get("t_s", PackedFloat64Array())
	var gyro: PackedFloat64Array = columns.get("gyro_x_rad_s", PackedFloat64Array())

	results.append(TestResult.new(
		"the Rust reader returns the requested columns, with one value per row",
		bool(read.get("ok", false)) and int(read.get("rows", 0)) == 200
			and times.size() == 200 and gyro.size() == 200 and columns.size() == 3,
		"ok=%s, %d rows, %d columns" % [
			read.get("ok"), read.get("rows"), columns.size()]))

	# The values must be the FILE's, not merely the right shape. Checked against the same dumb CSV
	# reader test_flight_recorder.gd uses, which knows nothing about the Rust path and so cannot
	# agree with it about a shared mistake.
	var oracle := TestFlightRecorder._column(good, "gyro_x_rad_s")
	var matches := oracle.size() == gyro.size()
	if matches:
		for i in gyro.size():
			if absf(gyro[i] - oracle[i]) > 1e-12:
				matches = false
				break
	results.append(TestResult.new(
		"the Rust reader's floats are the file's floats, checked against an independent reader",
		matches,
		"%d values agree with a GDScript parse of the same column" % gyro.size()))

	# A name the file does not carry is absent, not fatal. This is what lets Studio open a log
	# written before LTHL-52 without special-casing it.
	var partial: Dictionary = LogReader.read_columns(good,
		PackedStringArray(["t_s", "axisP_roll", "gyro_x_rad_s"]))
	var partial_columns: Dictionary = partial.get("columns", {})
	results.append(TestResult.new(
		"a column the log does not carry comes back absent rather than failing the read",
		bool(partial.get("ok", false)) and partial_columns.size() == 2
			and not partial_columns.has("axisP_roll"),
		"asked for 3, got %d, no axisP_roll" % partial_columns.size()))

	# --- Every way a file on disk can be wrong ---------------------------------------------
	var truncated_path := "%s/truncated.csv" % TEST_DIR
	var handle := FileAccess.open(truncated_path, FileAccess.WRITE)
	handle.store_line("#{\"schema\": 1}")
	handle.store_line("t_s,gyro_x_rad_s,m1_rpm")
	handle.store_line("0.001,0.5,1000")
	handle.store_line("0.002,0.6,1100")
	handle.store_line("0.003,0.7")          # the half-written last row of a log that died
	handle.close()

	var cut: Dictionary = LogReader.read_columns(truncated_path, PackedStringArray(["t_s"]))
	# A TRUNCATED FILE IS A SUCCESSFUL READ OF WHAT WAS THERE. Returning a failure would throw
	# away a flight because its last line was half written — and the flight that ended by the app
	# dying is usually the one worth looking at.
	results.append(TestResult.new(
		"a log truncated mid-row keeps the rows it had, and says where it stopped",
		bool(cut.get("ok", false)) and int(cut.get("rows", 0)) == 2
			and str(cut.get("reason", "")).contains("truncated"),
		"%d rows, reason: %s" % [cut.get("rows"), cut.get("reason")]))

	var junk_path := "%s/junk.csv" % TEST_DIR
	var junk := FileAccess.open(junk_path, FileAccess.WRITE)
	junk.store_line("this is not a log at all")
	junk.close()

	var empty_path := "%s/empty.csv" % TEST_DIR
	FileAccess.open(empty_path, FileAccess.WRITE).close()

	var junk_read: Dictionary = LogReader.read_columns(junk_path, PackedStringArray(["t_s"]))
	var empty_read: Dictionary = LogReader.read_columns(empty_path, PackedStringArray(["t_s"]))
	var missing_read: Dictionary = LogReader.read_columns("user://no_such_log.csv",
		PackedStringArray(["t_s"]))

	results.append(TestResult.new(
		"garbage, empty and missing files each return a reason rather than aborting the process",
		not bool(junk_read.get("ok", true)) and not bool(empty_read.get("ok", true))
			and not bool(missing_read.get("ok", true))
			and not str(junk_read.get("reason", "")).is_empty()
			and not str(missing_read.get("reason", "")).is_empty(),
		"junk: %s | empty: %s | missing: %s" % [
			junk_read.get("reason"), empty_read.get("reason"), missing_read.get("reason")]))

	# A cell that will not parse becomes NaN and is COUNTED, rather than becoming zero. Zero is a
	# plausible reading — it looks like a moment the aircraft was still — and NaN is visibly absent.
	var bad_path := "%s/bad_cell.csv" % TEST_DIR
	var bad := FileAccess.open(bad_path, FileAccess.WRITE)
	bad.store_line("#{\"schema\": 1}")
	bad.store_line("t_s,gyro_x_rad_s")
	bad.store_line("0.001,0.5")
	bad.store_line("0.002,not-a-number")
	bad.close()
	var bad_read: Dictionary = LogReader.read_columns(bad_path,
		PackedStringArray(["gyro_x_rad_s"]))
	var bad_values: PackedFloat64Array = bad_read.get("columns", {}).get(
		"gyro_x_rad_s", PackedFloat64Array())
	results.append(TestResult.new(
		"an unparseable cell reads as NaN and is counted, never as a plausible zero",
		int(bad_read.get("bad_cells", 0)) == 1 and bad_values.size() == 2
			and is_nan(bad_values[1]),
		"bad_cells=%s, %d values back" % [bad_read.get("bad_cells"), bad_values.size()]))

	# --- Only the requested columns are parsed -----------------------------------------------
	#
	# Measured against the cost of the alternative in the same run, never against a declared
	# number — see LISTING_BUDGET_MS for what happened the one time this suite used a number.
	var wide := _write_log("flight-20260816-130000.csv", FIXTURE_ROWS)
	var all_names := PackedStringArray()
	for column_name in FlightRecorder.COLUMNS:
		all_names.append(str(column_name))

	var all_start := Time.get_ticks_usec()
	LogReader.read_columns(wide, all_names)
	var all_us := Time.get_ticks_usec() - all_start

	var two_start := Time.get_ticks_usec()
	LogReader.read_columns(wide, PackedStringArray(["t_s", "gyro_x_rad_s"]))
	var two_us := Time.get_ticks_usec() - two_start

	results.append(TestResult.new(
		"reading two columns costs less than half of reading all %d" % all_names.size(),
		two_us * 2 < all_us,
		"2 columns in %d us against %d columns in %d us" % [
			two_us, all_names.size(), all_us]))

	# The §7 rule reaches Rust too. The GDScript readers are grepped by
	# tests/test_flight_recorder.gd; this file is not GDScript, so it is checked here.
	var rust_source := FileAccess.get_file_as_string("res://rust/src/log_reader.rs")
	results.append(TestResult.new(
		"the Rust reader cannot reconstruct a build, and does not unwrap on a builder's file",
		not rust_source.is_empty()
			and not rust_source.contains("Build::")
			and not rust_source.contains(".unwrap()")
			and not rust_source.contains(".expect("),
		"log_reader.rs: no Build, no unwrap, no expect"))

	return results


## ---------------------------------------------------------------------------
## Min/max decimation — this slice's axisI
## ---------------------------------------------------------------------------
##
## THE FIXTURE IS ADVERSARIAL ON PURPOSE. A one-sample spike placed anywhere convenient passes for
## every-Nth decimation too, whenever the spike happens to land on a kept index — which makes the
## check a test that cannot fail. The spike below sits at an index no every-Nth stride at either
## width would keep, and the assertion is that both widths report the SAME extent and that the
## extent is the true one.
##
## Verified by mutation: swapping TraceView's bucketing for drop-decimation makes this go red.
static func _test_trace_decimation() -> Array:
	var results: Array = []

	const SAMPLES := 10000
	const SPIKE_AT := 4517       # prime-ish index, divisible by neither stride below
	const SPIKE := 0.4
	const BASELINE := 0.01

	var times := PackedFloat64Array()
	var values := PackedFloat64Array()
	for i in SAMPLES:
		times.append(float(i) * 0.001)
		values.append(SPIKE if i == SPIKE_AT else BASELINE)

	var narrow := TraceView.new()
	narrow.size = Vector2(500, 300)
	narrow.show_log(times, {"gyro_x_rad_s": values})
	var narrow_extent := narrow.channel_extent("gyro_x_rad_s")

	var wide := TraceView.new()
	wide.size = Vector2(740, 300)
	wide.show_log(times, {"gyro_x_rad_s": values})
	var wide_extent := wide.channel_extent("gyro_x_rad_s")

	results.append(TestResult.new(
		"a one-sample spike survives decimation, and reads the SAME at two window widths",
		absf(narrow_extent.y - SPIKE) < 1e-6 and absf(wide_extent.y - SPIKE) < 1e-6,
		"peak drawn: %.4f at 500 px, %.4f at 740 px (true peak %.4f)" % [
			narrow_extent.y, wide_extent.y, SPIKE]))

	# The bucket the spike lands in must carry it as an EXTENT, not as a midpoint. A polyline
	# through bucket midpoints would draw [-0.4, 0.4] as a flat line through zero, which is the
	# tempting simplification this widget exists to refuse.
	var spike_bucket := int(times[SPIKE_AT] / (times[SAMPLES - 1] - times[0])
		* float(narrow.bucket_count() - 1))
	var extent := narrow.bucket_extent("gyro_x_rad_s", spike_bucket)
	results.append(TestResult.new(
		"the spike's bucket draws a vertical extent from baseline to peak, not a midpoint",
		absf(extent.y - SPIKE) < 1e-6 and absf(extent.x - BASELINE) < 1e-6,
		"bucket %d spans %.4f to %.4f" % [spike_bucket, extent.x, extent.y]))

	# A NaN from an unparseable cell must not blank the axis: min/max against NaN propagates in
	# GDScript, so one bad cell in a 180 000-row log would leave the whole channel unscaled.
	var with_nan := values.duplicate()
	with_nan[10] = NAN
	var nan_view := TraceView.new()
	nan_view.size = Vector2(500, 300)
	nan_view.show_log(times, {"gyro_x_rad_s": with_nan})
	var nan_extent := nan_view.channel_extent("gyro_x_rad_s")
	results.append(TestResult.new(
		"one NaN cell does not blank the channel's range",
		absf(nan_extent.y - SPIKE) < 1e-6 and is_finite(nan_extent.x),
		"extent with a NaN present: %.4f to %.4f" % [nan_extent.x, nan_extent.y]))

	narrow.free()
	wide.free()
	nan_view.free()
	return results


## A CHART THAT NAMES NOTHING IS THE EXPENSIVE BUG, not a missing nicety. TraceView opens on
## omega_x and gyro_x deliberately — the gap between them is the figure no real drone can produce
## about itself — and drawn as two anonymous overlapping lines that gap is invisible at every
## ratio. So: every drawn channel is named on screen, and its unit is the file's.
static func _test_trace_legend() -> Array:
	var results: Array = []

	var times := PackedFloat64Array()
	var gyro := PackedFloat64Array()
	var rpm := PackedFloat64Array()
	for i in 400:
		times.append(float(i) * 0.001)
		gyro.append(sin(float(i) * 0.05) * 0.5)
		rpm.append(28000.0 + float(i))

	var view := TraceView.new()
	view.size = Vector2(700, 300)
	view.show_log(times, {"gyro_x_rad_s": gyro, "m1_rpm": rpm},
		{"gyro_x_rad_s": "rad/s", "m1_rpm": "rpm"})

	var entries := view.legend_entries()
	var named := entries.size() == 2
	if named:
		named = str(entries[0]["name"]) == "gyro_x_rad_s" and str(entries[1]["name"]) == "m1_rpm"

	results.append(TestResult.new(
		"every drawn channel is named on screen, in draw order",
		named,
		"%d legend entries for 2 channels" % entries.size()))

	# Distinct colours, or the legend names two channels a reader still cannot tell apart.
	results.append(TestResult.new(
		"each channel's legend swatch is the colour it is actually drawn in, and they differ",
		entries.size() == 2 and Color(entries[0]["colour"]) != Color(entries[1]["colour"])
			and Color(entries[0]["colour"]) == TraceView.SERIES_COLOURS[0],
		"swatches: %s, %s" % [entries[0]["colour"], entries[1]["colour"]]))

	# THE FILE'S UNIT, UNCONVERTED. A viewer that helpfully showed degrees because degrees are more
	# familiar would undo the discipline the UNITS table exists to enforce.
	results.append(TestResult.new(
		"the unit shown is the one the file declared, with no conversion",
		view.unit_of("gyro_x_rad_s") == "rad/s" and view.unit_of("m1_rpm") == "rpm"
			and not view.unit_of("gyro_x_rad_s").contains("deg"),
		"gyro reads %s, rpm reads %s" % [view.unit_of("gyro_x_rad_s"), view.unit_of("m1_rpm")]))

	# A log whose header carries no unit for a column must still draw and still be named.
	var bare := TraceView.new()
	bare.size = Vector2(700, 300)
	bare.show_log(times, {"gyro_x_rad_s": gyro})
	results.append(TestResult.new(
		"a channel with no declared unit is still named, with an empty unit rather than a guess",
		bare.legend_entries().size() == 1 and bare.unit_of("gyro_x_rad_s").is_empty(),
		"unnamed-unit channel: %d entries" % bare.legend_entries().size()))

	# ADVERSARIAL: six channels, long names — the picker's cap (MAX_CHANNELS in studio_screen.gd)
	# is the worst case the legend must survive at ordinary panel widths. A legend that drops
	# entries past whatever fit on one row is worse than none: a reader matches the wrong colour
	# to the wrong channel. legend_entries() alone cannot catch that bug — the drop lived in
	# drawing, not in the model — so this asserts on legend_rows(), the drawn layout as data.
	var wide := TraceView.new()
	wide.size = Vector2(700, 300)
	var many_channels: Dictionary = {}
	var long_names := [
		"gyro_x_rad_s", "omega_x_rad_s", "gyro_y_rad_s", "omega_y_rad_s",
		"gyro_z_rad_s", "omega_z_rad_s",
	]
	for name in long_names:
		many_channels[name] = gyro
	wide.show_log(times, many_channels)

	var wide_entries := wide.legend_entries()
	results.append(TestResult.new(
		"every one of six selected channels is named, not just however many fit on one row",
		wide_entries.size() == 6,
		"%d legend entries for 6 channels" % wide_entries.size()))

	var rows := wide.legend_rows()
	var accounted := {}
	for row in rows:
		for idx in row:
			accounted[int(idx)] = true
	results.append(TestResult.new(
		"the drawn legend layout accounts for all six channels across its rows, none dropped",
		rows.size() <= TraceView.LEGEND_MAX_ROWS and accounted.size() == 6,
		"%d rows, %d distinct channel indices accounted for" % [rows.size(), accounted.size()]))

	# THE LEGEND IS THE CURSOR READOUT. TraceView's own _init has said "a viewer wants a cursor.
	# Nothing reads it yet" since it was written; this is the thing that reads it.
	#
	# The fixture is a RAMP rather than the sine above, because a sine takes the same value at many
	# times and a wrong lookup could land on a right answer.
	var ramp_times := PackedFloat64Array()
	var ramp := PackedFloat64Array()
	for i in 1000:
		ramp_times.append(float(i) * 0.001)
		ramp.append(float(i) * 0.25)

	var cursored := TraceView.new()
	cursored.size = Vector2(700, 300)
	cursored.show_log(ramp_times, {"gyro_x_rad_s": ramp}, {"gyro_x_rad_s": "rad/s"})

	# ON a sample, the answer is exact — no ambiguity, so no tolerance band. t=0.400 lands exactly
	# on times[400] (value 100.0); an off-by-one neighbour would read 99.75 or 100.25, a miss this
	# bound catches that a 0.26 band could not.
	results.append(TestResult.new(
		"on a sample, the cursor reads that sample's value exactly",
		absf(cursored.value_at("gyro_x_rad_s", 0.400) - 100.0) < 1e-9,
		"value at t=0.400 s reads %.6f, true 100.000000" % cursored.value_at(
			"gyro_x_rad_s", 0.400)))

	# STRICTLY CLOSER TO THE EARLIER SAMPLE — the one query shape that actually exercises the
	# "step back if the previous sample is closer" correction branch. t=0.4004 is 0.0004 from
	# times[400] (100.0) and 0.0006 from times[401] (100.25): binary search converges to lo=401
	# (first index whose time is >= t), and the correction must step back to 400. The answer is
	# unambiguous here, so this asserts equality, not membership.
	var nearer := cursored.value_at("gyro_x_rad_s", 0.4004)
	results.append(TestResult.new(
		"strictly closer to the earlier sample, the correction branch steps back and reads it exactly",
		absf(nearer - 100.0) < 1e-9,
		"value at t=0.4004 s reads %.6f, true 100.000000" % nearer))
	results.append(TestResult.new(
		"strictly closer to the earlier sample, the cursor never interpolates a value the log does not contain",
		absf(nearer - 100.1) > 1e-9,
		"value at t=0.4004 s reads %.6f; 100.100000 would be the invented lerp" % nearer))

	# A FLOAT64 TIE — times[400] and times[401] are exactly equidistant from t=0.4005 in float64
	# (both distances compute to 0.0005000000000000004), so the strict `<` correction test never
	# fires here and either neighbour is a correct answer. This does NOT exercise the correction
	# branch — the query above does that — it only re-confirms no interpolation happens on a tie.
	var tied := cursored.value_at("gyro_x_rad_s", 0.4005)
	results.append(TestResult.new(
		"on a float64 tie, the cursor picks one of the two neighbours exactly rather than a tolerance band",
		absf(tied - 100.0) < 1e-9 or absf(tied - 100.25) < 1e-9,
		"value at t=0.4005 s reads %.6f, neighbours are 100.000000 and 100.250000" % tied))
	results.append(TestResult.new(
		"on a float64 tie, the cursor never interpolates a value the log does not contain",
		absf(tied - 100.125) > 1e-9,
		"value at t=0.4005 s reads %.6f; 100.125000 would be the invented midpoint" % tied))

	cursored.cursor_t = 0.400
	var cursor_entry: Dictionary = cursored.legend_entries()[0]
	results.append(TestResult.new(
		"with a cursor set, the legend shows the value there rather than the channel's range",
		str(cursor_entry["value"]).contains("100") and not str(cursor_entry["value"]).contains("…"),
		"legend under cursor reads: %s" % cursor_entry["value"]))

	cursored.cursor_t = -1.0
	results.append(TestResult.new(
		"with no cursor, the legend falls back to the channel's drawn range",
		str(cursored.legend_entries()[0]["value"]).contains("…"),
		"legend with no cursor reads: %s" % cursored.legend_entries()[0]["value"]))

	# Off the end of the log is not a number, not the last sample — a readout that clamped would
	# report a value for a time the flight did not have.
	results.append(TestResult.new(
		"a cursor time outside the log's span reads as absent rather than clamping",
		is_nan(cursored.value_at("gyro_x_rad_s", 99.0))
			and is_nan(cursored.value_at("no_such_channel", 0.4)),
		"off-span and unknown-channel both read NaN"))

	cursored.free()

	view.free()
	bare.free()
	wide.free()
	return results


## The picker is the header's `columns` array, which is what makes LTHL-52 free.
static func _test_channel_picker() -> Array:
	var results: Array = []
	_fresh_dir()
	_write_log("flight-20260816-120000.csv", 50)

	var studio := StudioScreen.new(FlightLogLibrary.load_from(TEST_DIR))
	studio.select("flight-20260816-120000.csv")
	studio.set_view_mode(StudioScreen.ViewMode.EXPLORE)

	# One entry per column in the header, minus t_s, which is the clock rather than a channel.
	var expected := FlightRecorder.COLUMNS.size() - 1
	results.append(TestResult.new(
		"the picker offers exactly the channels the header lists, less the clock",
		studio._channel_list.item_count == expected,
		"%d channels offered against %d columns in the header" % [
			studio._channel_list.item_count, FlightRecorder.COLUMNS.size()]))

	# A COLUMN THE PICKER WAS NEVER TOLD ABOUT. This is the LTHL-52 case in miniature: a log
	# carrying a name no version of this screen has heard of must still offer it. A hardcoded
	# picker fails here, and it is the only check that distinguishes the two designs.
	var future_path := "%s/flight-20270101-000000.csv" % TEST_DIR
	var future := FileAccess.open(future_path, FileAccess.WRITE)
	future.store_line("#" + JSON.stringify({
		"schema": 1,
		"columns": ["t_s", "axisP_roll", "gyro_x_rad_s"],
		"units": {"t_s": "s", "axisP_roll": "unit", "gyro_x_rad_s": "rad/s"},
		"aircraft": {"fingerprint": "a/b/c/d/e/f"},
	}))
	future.store_line("t_s,axisP_roll,gyro_x_rad_s")
	future.store_line("0.001,12.5,0.5")
	future.store_line("0.002,12.6,0.6")
	future.close()

	studio.library.refresh()
	studio.select("flight-20270101-000000.csv")
	studio.set_view_mode(StudioScreen.ViewMode.EXPLORE)
	var offered := PackedStringArray()
	for i in studio._channel_list.item_count:
		offered.append(studio._channel_list.get_item_text(i))

	results.append(TestResult.new(
		"a column no version of this screen has heard of is still offered — LTHL-52 costs Studio nothing",
		studio._channel_list.item_count == 2
			and str(offered[0]).begins_with("axisP_roll"),
		"offered: %s" % ", ".join(offered)))

	# THE UNIT IS THE FILE'S AND IS SHOWN, NEVER CONVERTED. Lothal is rad/s and Betaflight is
	# deg/s; a viewer that helpfully showed degrees would undo the discipline the UNITS table
	# exists to enforce.
	results.append(TestResult.new(
		"the picker shows each channel's unit as the file states it, with no conversion",
		str(offered[1]).contains("rad/s") and not str(offered[1]).contains("deg"),
		"gyro channel reads: %s" % offered[1]))

	studio.free()
	return results


## Studio as a room, against the invariants every other room holds to.
static func _test_shell_room() -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.show_studio()
	var opened := shell.studio != null
	shell.show_lab()
	var closed_on_leaving := shell.studio == null

	results.append(TestResult.new(
		"Studio is a room: built fresh on entry, freed on the way out",
		opened and closed_on_leaving,
		"opened=%s, freed on leaving=%s" % [opened, closed_on_leaving]))

	# Reading files cannot drain a pack, and a write-back "for symmetry" would be inventing a
	# consequence out of having opened a room — the field editor's argument, verbatim.
	var shell_code := TestPidTunes._code_only(
		FileAccess.get_file_as_string("res://src/ui/app_shell.gd"))
	var studio_block := shell_code.split("if studio != null:")
	results.append(TestResult.new(
		"closing Studio does not persist a pack charge — reading files turns no motors",
		studio_block.size() == 2 and not studio_block[1].split("studio = null")[0]
			.contains("persist_pack_charge"),
		"no pack write-back on the Studio path"))

	shell.free()
	return results


## ONE SHARED Y AXIS WAS A LIE THE CHART TOLD ABOUT ITS OWN CONTENTS. gyro_x spans about ±4 rad/s
## and m1_rpm about 30 000; scaled together the gyro collapses to a flat line at zero — not
## clipped, not warned about, just silently unreadable while the chart claims to show both.
##
## THE FIXTURE'S TWO CHANNELS DIFFER BY FOUR ORDERS OF MAGNITUDE ON PURPOSE. Two similar-ranged
## channels pass on a shared axis by luck, which would make this a check that cannot fail.
static func _test_trace_lanes() -> Array:
	var results: Array = []

	var times := PackedFloat64Array()
	var gyro := PackedFloat64Array()
	var rpm := PackedFloat64Array()
	var thrust := PackedFloat64Array()
	for i in 500:
		times.append(float(i) * 0.001)
		gyro.append(sin(float(i) * 0.05) * 4.0)
		rpm.append(28000.0 + sin(float(i) * 0.03) * 900.0)
		thrust.append(3.0 + sin(float(i) * 0.02) * 0.4)

	var view := TraceView.new()
	view.size = Vector2(700, 400)
	view.show_log(times, {"gyro_x_rad_s": gyro, "m1_rpm": rpm},
		{"gyro_x_rad_s": "rad/s", "m1_rpm": "rpm"})

	var lanes := view.lanes()
	var separated := lanes.size() == 2
	if separated:
		# Each lane scaled to ITS OWN channels. A shared axis gives both lanes the rpm range, and
		# the gyro lane's span would come back at ~30 000 instead of ~8.
		separated = absf(float(lanes[0]["y_max"]) - float(lanes[0]["y_min"])) < 20.0 \
			and absf(float(lanes[1]["y_max"]) - float(lanes[1]["y_min"])) > 100.0
	results.append(TestResult.new(
		"channels in different units get their own lane and their own scale",
		separated,
		"%d lanes; spans %s" % [lanes.size(),
			", ".join(lanes.map(func(l): return "%.1f" % (
				float(l["y_max"]) - float(l["y_min"]))))]))

	results.append(TestResult.new(
		"a lane carries the unit its channels declared, in first-appearance order",
		lanes.size() == 2 and str(lanes[0]["unit"]) == "rad/s"
			and str(lanes[1]["unit"]) == "rpm",
		"lane units: %s" % ", ".join(lanes.map(func(l): return str(l["unit"])))))

	# Same unit stays on ONE axis, and that is the whole point: gyro against omega is comparable
	# only because they share a scale, and the gap between them is the room's headline.
	var paired := TraceView.new()
	paired.size = Vector2(700, 400)
	paired.show_log(times, {"gyro_x_rad_s": gyro, "omega_x_rad_s": gyro},
		{"gyro_x_rad_s": "rad/s", "omega_x_rad_s": "rad/s"})
	results.append(TestResult.new(
		"two channels in the SAME unit share one axis, so they stay comparable",
		paired.lanes().size() == 1
			and PackedStringArray(paired.lanes()[0]["channels"]).size() == 2,
		"%d lane for two rad/s channels" % paired.lanes().size()))

	# A channel with no declared unit is its own lane rather than being pooled with rad/s, because
	# pooling would be the chart guessing that two unlabelled things are comparable.
	var mixed := TraceView.new()
	mixed.size = Vector2(700, 400)
	mixed.show_log(times, {"gyro_x_rad_s": gyro, "m1_rpm": rpm, "m1_thrust_n": thrust},
		{"gyro_x_rad_s": "rad/s", "m1_rpm": "rpm", "m1_thrust_n": "N"})
	results.append(TestResult.new(
		"three units make three lanes, and MAX_LANES is not exceeded",
		mixed.lanes().size() == 3 and mixed.lanes().size() <= TraceView.MAX_LANES,
		"%d lanes for three units" % mixed.lanes().size()))

	# A channel that is entirely unparseable is what LogReader writes for a wholly malformed
	# column — a truncated log, a hand-edited file, a column of empty strings. channel_extent()
	# returns (NAN, NAN) for it, and minf/maxf against NAN propagate NaN rather than ignoring it,
	# so the naive guard's "-= 1.0 / += 1.0" on an already-NaN bound is still NaN. A lane must
	# never ship a non-finite range: _y_pixel() divides by (y_max - y_min), and NaN there
	# unscales the whole axis silently.
	var all_nan := PackedFloat64Array()
	for i in 500:
		all_nan.append(NAN)
	var nan_view := TraceView.new()
	nan_view.size = Vector2(700, 400)
	nan_view.show_log(times, {"bad_channel": all_nan}, {"bad_channel": "V"})
	var nan_lanes := nan_view.lanes()
	var nan_ok := nan_lanes.size() == 1 \
		and is_finite(float(nan_lanes[0]["y_min"])) \
		and is_finite(float(nan_lanes[0]["y_max"])) \
		and float(nan_lanes[0]["y_max"]) > float(nan_lanes[0]["y_min"])
	results.append(TestResult.new(
		"a wholly unparseable channel still gets a finite lane range",
		nan_ok,
		"y_min=%s y_max=%s" % [
			str(nan_lanes[0]["y_min"]) if not nan_lanes.is_empty() else "?",
			str(nan_lanes[0]["y_max"]) if not nan_lanes.is_empty() else "?"]))

	# A widget too short for its lane count must still produce lane rects with positive height and
	# no overlap. lane_height's arithmetic has no floor of its own: with 3 lanes and LANE_GAP = 10,
	# a plot shorter than 20 px drives it negative, which is an inverted Rect2 — lanes overlapping
	# and drawing upward, not merely cramped.
	var short := TraceView.new()
	short.size = Vector2(700, 90)
	short.show_log(times, {"gyro_x_rad_s": gyro, "m1_rpm": rpm, "m1_thrust_n": thrust},
		{"gyro_x_rad_s": "rad/s", "m1_rpm": "rpm", "m1_thrust_n": "N"})
	var short_rects: Array = short.lane_rects(short.lanes().size())
	var heights_ok := short_rects.size() == 3
	for r in short_rects:
		if float((r as Rect2).size.y) <= 0.0:
			heights_ok = false
	var no_overlap := true
	for i in short_rects.size() - 1:
		var a: Rect2 = short_rects[i]
		var b: Rect2 = short_rects[i + 1]
		if a.position.y + a.size.y > b.position.y + 0.001:
			no_overlap = false
	results.append(TestResult.new(
		"a widget too short for its lanes still gives every lane a positive, non-overlapping rect",
		heights_ok and no_overlap,
		"heights_ok=%s no_overlap=%s rects=%s" % [heights_ok, no_overlap,
			", ".join(short_rects.map(func(r): return str(r)))]))

	view.free()
	paired.free()
	mixed.free()
	nan_view.free()
	short.free()
	return results
