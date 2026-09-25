class_name TestRealFiles
extends RefCounted
## The hold that puts the builder's files back when a section does not finish.
##
## ---------------------------------------------------------------------------
## THIS SUITE PRINTS THREE `SCRIPT ERROR` LINES ON A GREEN RUN, AND THEY ARE THE TEST
## ---------------------------------------------------------------------------
##
## A hard `SCRIPT ERROR` cannot be caught in GDScript, so the only way to prove a mechanism
## survives one is to raise one. Two null dereferences below are deliberate and they are RAISED
## THREE TIMES: `_a_section_that_poisons_then_aborts` is called from two different checks (:91 and
## :113) and `_a_section_that_creates_then_aborts` from one. This said "two" until the final
## review counted them, and the count is what a future reader uses to decide whether the
## `SCRIPT ERROR` noise in a passing log is expected — so it has to be the number of LINES, not
## the number of `null`s.
##
## A run of this suite that prints NO error line is a run in which the thing being tested did not
## happen — which is why "the section really did abort" is asserted separately from "the file came
## back".
##
## ---------------------------------------------------------------------------
## WHY THIS DOES NOT HOLD A REAL `user://` PATH
## ---------------------------------------------------------------------------
##
## Every other user of `RealFiles` holds the builder's own `sites.json` or `conditions.json`,
## because the code under test reads those by name. This suite must not. It exists to trigger the
## exact failure the hold is there to survive, and a check that deliberately abandons a write
## half-way through must not be pointed at somebody's home field: if the mechanism is broken, the
## test IS the damage it was written to detect. The hold is path-agnostic — it reads bytes, it
## writes bytes back — so a test-owned path exercises all of it and risks none of it. The real
## paths are covered from the other side, by the suites that hold them asserting `intact()` after
## their own sections have run.

## A file this suite owns outright. Not beside any real one, and removed at the end.
const HELD_PATH := "user://test_real_files_held.json"
const ORIGINAL := "{\"this\": \"is the builder's own file\", \"elevation_m\": 0.0}"
const POISON := "{\"this\": \"is what a half-finished section leaves behind\"}"


static func run() -> Array:
	var results: Array = []
	var sections := {
		"an aborting section": _an_aborting_section_still_puts_the_file_back(),
		"a file that was not there": _a_file_that_was_not_there_stays_absent(),
		"the report": _the_report_names_what_happened(),
	}
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


static func _write(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle != null:
		handle.store_string(text)
		handle.close()


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Writes the poison, then dereferences null. THE LAST LINE NEVER RUNS, and neither would a
## restore written here — which is precisely the shape of every hand-rolled restore this mechanism
## replaces. Returns an Array so the abort hands the caller `[]`, exactly as a real section does.
static func _a_section_that_poisons_then_aborts() -> Array:
	var out: Array = []
	_write(HELD_PATH, POISON)
	var nothing: Site = null
	out.append(nothing.terrain)
	_write(HELD_PATH, ORIGINAL)   # unreachable, and that is the point
	return out


## The same, for a path that did not exist when the hold was taken.
static func _a_section_that_creates_then_aborts() -> Array:
	var out: Array = []
	_write(HELD_PATH, POISON)
	var nothing: Site = null
	out.append(nothing.terrain)
	return out


# ---------------------------------------------------------------------------
# 1. The case that actually happened
# ---------------------------------------------------------------------------

static func _an_aborting_section_still_puts_the_file_back() -> Array:
	var results: Array = []

	_write(HELD_PATH, ORIGINAL)
	var held := RealFiles.hold([HELD_PATH])
	var section := _a_section_that_poisons_then_aborts()
	held.restore()

	# NON-VACUITY FIRST. If the section ran to the end, everything below is true for the wrong
	# reason — it would be asserting that a file nobody damaged is undamaged.
	results.append(TestResult.new(
		"the section really did abort part-way — it produced nothing",
		section.is_empty(),
		"the section returned %d result(s); its last line writes the file back and must not run"
			% section.size()
	))

	results.append(TestResult.new(
		"and the held file is byte-identical to what was there before the hold",
		FileAccess.get_file_as_string(HELD_PATH) == ORIGINAL and held.intact(),
		"on disk: %s" % FileAccess.get_file_as_string(HELD_PATH)
	))

	# And the poison was real: the same section, with the hold NOT released, leaves it behind.
	# This is what the disk looked like before this mechanism existed.
	_write(HELD_PATH, ORIGINAL)
	var unheld := RealFiles.hold([HELD_PATH])
	var ignored := _a_section_that_poisons_then_aborts()
	results.append(TestResult.new(
		"and without the release the poison survives — the damage this prevents is real",
		FileAccess.get_file_as_string(HELD_PATH) == POISON and ignored.is_empty()
			and not unheld.intact(),
		"on disk without a restore: %s (intact() says %s)" % [
			FileAccess.get_file_as_string(HELD_PATH), unheld.intact()]
	))
	unheld.restore()

	_forget(HELD_PATH)
	return results


# ---------------------------------------------------------------------------
# 2. Absent is a state too
# ---------------------------------------------------------------------------

## A file that was NOT there has to go back to not being there. Leaving a `conditions.json` behind
## on a machine that had none is the same class of damage as changing one — the app reads a file
## its owner never made — and it is the case a "write the old text back" restore misses entirely.
static func _a_file_that_was_not_there_stays_absent() -> Array:
	var results: Array = []

	_forget(HELD_PATH)
	var held := RealFiles.hold([HELD_PATH])
	var section := _a_section_that_creates_then_aborts()
	results.append(TestResult.new(
		"the file really was created by the aborting section, so there is something to remove",
		FileAccess.file_exists(HELD_PATH) and section.is_empty(),
		"exists after the abort: %s" % FileAccess.file_exists(HELD_PATH)
	))
	held.restore()
	results.append(TestResult.new(
		"and the release removes it again — absent is restored to absent",
		not FileAccess.file_exists(HELD_PATH) and held.intact(),
		"exists after the release: %s (intact() says %s)" % [
			FileAccess.file_exists(HELD_PATH), held.intact()]
	))

	_forget(HELD_PATH)
	return results


# ---------------------------------------------------------------------------
# 3. The detail line a failure would be read from
# ---------------------------------------------------------------------------

static func _the_report_names_what_happened() -> Array:
	var results: Array = []

	_write(HELD_PATH, ORIGINAL)
	var held := RealFiles.hold([HELD_PATH])
	results.append(TestResult.new(
		"an untouched hold reports the file as identical and names it",
		held.intact() and held.report().contains("identical")
			and held.report().contains(HELD_PATH.get_file()),
		held.report()
	))

	_write(HELD_PATH, POISON)
	results.append(TestResult.new(
		"a changed file is reported as CHANGED before the release, not after the damage is done",
		not held.intact() and held.report().contains("CHANGED"),
		held.report()
	))
	held.restore()

	_forget(HELD_PATH)
	return results
