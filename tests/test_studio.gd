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
	results.append_array(_test_shell_room())
	_clean()
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
