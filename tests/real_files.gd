class_name RealFiles
extends RefCounted
## A hold on the builder's own files, taken by a suite that has to write to a real `user://` path,
## and released in the ONE place GDScript can guarantee it runs.
##
## ---------------------------------------------------------------------------
## WHY THE SUITES WRITE REAL PATHS AT ALL, AND WHY THAT IS NOT THE BUG
## ---------------------------------------------------------------------------
##
## `RoomHost.new()` reads `user://sites.json`, `user://courses.json` and `user://conditions.json`
## by name. It takes no paths, and it must not be given any here: the checks that use it exist to
## prove that the SHIPPED default reads the right three files in the right order — a Critical
## defect once already — and a RoomHost pointed at scratch files would pass while the shipping one
## was wrong. So "write to a scratch path instead" is not available to these checks without
## deleting what they check. The state has to be real, and it has to be put back.
##
## ---------------------------------------------------------------------------
## GDSCRIPT HAS NO `finally`, AND THIS IS THE THING IT HAS INSTEAD
## ---------------------------------------------------------------------------
##
## A hard `SCRIPT ERROR` — a null dereference, a bad index — **cannot be caught**. There is no
## try/except and no error hook that resumes. What it does do is precise, and it was measured on
## this repo rather than assumed: **it aborts the function it is in, and hands that function's
## caller the return type's default value.** The caller then runs normally. Measured:
##
##     SCRIPT ERROR: Invalid access to property or key 'terrain' on a base object of type 'Nil'.
##     caller resumed: section = [] (size 0)
##     RESTORE RAN with SNAPSHOT
##
## So a restore written at the END OF A SECTION is skipped by exactly the failure it most needs to
## survive, and a restore written in the section's CALLER is not. Every suite here already has that
## caller — `run()`, which builds its sections dictionary — and the section that aborted comes back
## as an empty array, which the existing `section "x" produced results` guard already turns red. The
## hold is therefore taken in `run()`, before the sections are built, and released in `run()`,
## after.
##
## ---------------------------------------------------------------------------
## WHAT ACTUALLY RUNS BETWEEN `hold()` AND THE SECTIONS, STATED PRECISELY
## ---------------------------------------------------------------------------
##
## Several of the eleven callers of `RealFiles.hold()` in this directory, as of this writing, do a
## small amount of setup in `run()` between the hold and the sections dict — most commonly
## `PartsCatalog.load_default()` or `Build.OPTIONAL_COMPONENTS`, e.g. `tests/test_assembly_tweaks.gd`
## and `tests/test_component_registration.gd`; four callers have no setup at all in that gap. THIS
## GAP IS NOT COVERED BY THE GUARANTEE ABOVE, and an earlier version of this file claimed `run()`
## "does nothing else but call sections and append results" — that was never true of every
## converted suite and should not be read as a rule the callers follow. What is actually true:
##
## - A `SCRIPT ERROR` inside a SECTION (a function called and appended from inside the sections
##   dict, or into `results` after it) is covered: `run()` resumes, `held.restore()` still runs,
##   the aborted section still appears as an empty array or (via `results.append(_test_x())`
##   suites) a `null` element the section-count guard and `run_one_suite.gd`'s null-guard both
##   catch.
## - A `SCRIPT ERROR` in the SETUP CALLS between `hold()` and the sections dict is NOT covered —
##   it is exactly case 2 below, just with a name attached to what currently occupies that gap.
##   For most callers this has not been a live hazard, because their setup is a catalog/constant
##   load with no property access on anything that could plausibly be null or missing. That is a
##   property of what those callers' setup HAPPENS to do today, not a structural guarantee — if a
##   future suite's setup grows a real property access there, this file's protection silently
##   stops applying to it, with nothing here to flag that it happened. **`tests/test_video_panel.gd`
##   is already the exception, not a hypothetical one**: its setup gap builds a `GlassShell` and
##   walks `shell.lab.camera_panel`, `shell.lab.assembly_panel` and `shell.lab.panels`, where
##   `GlassShell.lab` (`src/ui/glass_shell.gd:297-298`) is a getter over `rooms.lab`
##   (`var lab: LabScreen`, `src/ui/room_host.gd:32`) with no non-null guarantee at that point in
##   construction. That suite is relying on the gap being narrow in practice, not on it being safe.
##
## ---------------------------------------------------------------------------
## WHAT IS STILL NOT GUARANTEED, STATED PLAINLY
## ---------------------------------------------------------------------------
##
## 1. A process death — a segfault in the engine, an OOM kill, `--quit` or ^C between the hold and
##    the release. No in-process mechanism can survive that, and none is claimed.
## 2. An abort between the hold and the release that is NOT inside a section — whether that is
##    setup work in `run()` (see above; every converted suite currently has some) or, in principle,
##    an abort inside `held.restore()`'s own caller after the sections are built but before
##    `restore()` is reached. The safest `run()` keeps this gap as small and as free of real
##    property access as possible; it does not eliminate the gap.
## 3. An abort inside `hold()` or `restore()`. They are deliberately file operations and arithmetic
##    with no property access on anything that could be null.
## 4. A file written by a DIFFERENT suite that never held it. The hold restores what it holds.
##
## The residue this was written after was case 1's cousin: a mutation run raised a `SCRIPT ERROR`
## mid-section, the end-of-section restore never ran, and a 3500 m elevation and an invented
## "30 °C" row survived into every later suite — and onto the developer's own disk, where they sat
## until a re-review read the files directly. A suite count that is only reproducible when the
## previous run exited cleanly is not a measurement.

var _paths: Array[String] = []
## Whether each path was on disk when the hold was taken. A file that was ABSENT has to go back to
## absent: leaving a `conditions.json` behind on a machine that had none is the same class of
## damage as changing one, and it is the case a naive "write the old text back" misses.
var _existed: Array[bool] = []
var _contents: Array[String] = []


## Takes the hold. Reads every path once, now, and remembers exactly what was there.
static func hold(paths: Array) -> RealFiles:
	var out := RealFiles.new()
	for entry in paths:
		var path := String(entry)
		var here := FileAccess.file_exists(path)
		out._paths.append(path)
		out._existed.append(here)
		out._contents.append(FileAccess.get_file_as_string(path) if here else "")
	return out


## Puts every held file back the way it was found. Safe to call twice, and safe to call when
## nothing was touched.
func restore() -> void:
	for i in _paths.size():
		var path := _paths[i]
		if _existed[i]:
			var handle := FileAccess.open(path, FileAccess.WRITE)
			if handle != null:
				handle.store_string(_contents[i])
				handle.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Whether every held path is now byte-identical to what was found. ASKED AFTER `restore()`, so it
## is an assertion about the restore having worked rather than about the section having behaved —
## a restore that silently stopped working is invisible from inside the suite that broke it, and
## shows up as somebody else's home field, weeks later, in a different file.
func intact() -> bool:
	for i in _paths.size():
		if FileAccess.file_exists(_paths[i]) != _existed[i]:
			return false
		if _existed[i] and FileAccess.get_file_as_string(_paths[i]) != _contents[i]:
			return false
	return true


## One line naming each held file and what became of it, for the check's detail column.
func report() -> String:
	var parts: Array[String] = []
	for i in _paths.size():
		parts.append("%s %s" % [_paths[i].get_file(), _state(i)])
	return ", ".join(parts)


func _state(index: int) -> String:
	var path := _paths[index]
	if FileAccess.file_exists(path) != _existed[index]:
		return "MISSING" if _existed[index] else "LEFT BEHIND"
	if not _existed[index]:
		return "still absent"
	return "identical" if FileAccess.get_file_as_string(path) == _contents[index] else "CHANGED"
