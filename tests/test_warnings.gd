class_name TestWarnings
extends RefCounted
## The standing guard against GDScript warnings, run as part of the ordinary test command.
##
## Six warnings appeared in one slice because nothing checked for them, and three of those six were
## the same duplicated formatter reported three times — so the count was the only thing pointing at
## the duplication. A sweep that nobody runs would not have found it, which is why this is a SUITE
## rather than a separate script: `godot --headless --script res://tests/run_tests.gd` is the
## command that already exists, and a guard that needs remembering is not a guard.
##
## ---------------------------------------------------------------------------
## HOW IT SEES A WARNING AT ALL
## ---------------------------------------------------------------------------
##
## Godot does not print GDScript warnings from the command line. `--check-only` reports parse
## ERRORS and stays silent about warnings, and the editor keeps them in a panel rather than on
## stdout — which is why six of them accumulated in a project whose test suite runs on every change.
##
## So project.godot promotes every warning Godot enables by default from level 1 (warn) to level 2
## (error). That is the opposite of suppressing them: an error cannot be scrolled past, the editor
## marks it while you type, and a warning anywhere makes the script fail to load — so the existing
## runner already fails loudly even before this suite gets a chance to name the file. Godot only
## evaluates warnings in debug builds, so a release template is unaffected.
##
## What this suite adds on top of that is COVERAGE and a NAME. run_tests.gd only loads what the
## suites reach; a warning in a capture tool, or in a screen no test instantiates, would sit there
## unnoticed. This walks every .gd file in the project and reports the file and line.
##
## ---------------------------------------------------------------------------
## WHY A HARD FAILURE RATHER THAN A REPORTED COUNT
## ---------------------------------------------------------------------------
##
## A reported count is a number that goes up. It went from zero to six without anyone deciding it
## should, and it would have gone to seven the same way. Every one of the six was a one-line fix —
## a rename, a floori(), a scoped @warning_ignore — so the cost of the strict rule is a minute, and
## what it buys is that the duplication behind three of them cannot hide behind an accepted
## baseline. A warning that is genuinely intended has an escape hatch that says so out loud, on the
## line, with a comment: `@warning_ignore("integer_division")`. That is a decision left in the
## code, which is what a suppression should be, rather than a number nobody reads in a log.

## Where the sweep looks. Everything that ships or is run by hand; nothing generated.
const ROOTS := ["res://src", "res://tests"]

## Godot's own timeout for a single file check. A check is a parse and takes well under a second;
## anything near this has hung and should say so rather than stall the suite.
const CHECK_TIMEOUT_MS := 30000


static func run() -> Array:
	var results: Array = []
	var files := _gd_files()

	results.append(TestResult.new(
		"the sweep actually found the project's scripts to check",
		files.size() > 50,
		"%d .gd files under %s" % [files.size(), ", ".join(ROOTS)]
	))
	if files.size() <= 50:
		return results

	var offenders: Array = []
	for file in files:
		offenders.append_array(_warnings_in(file))

	results.append(TestResult.new(
		"the project reports zero GDScript warnings",
		offenders.is_empty(),
		"%d files clean" % files.size() if offenders.is_empty()
			else "%d warning(s): %s" % [offenders.size(), "; ".join(offenders)]
	))
	return results


## Every .gd file under the roots, recursively. DirAccess rather than a glob, because the project
## has no build step that could hand over a file list.
static func _gd_files() -> Array:
	var out: Array = []
	for root in ROOTS:
		_collect(root, out)
	out.sort()
	return out


static func _collect(dir: String, out: Array) -> void:
	for child in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(child), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))


## Runs one file through a fresh `--check-only` and returns whatever it complained about, as
## "file:line — message" strings.
##
## A SUBPROCESS PER FILE, deliberately, and it costs about a fifth of a second each. Doing it
## in-process was tried and does not work: reloading a script that declares a class_name from
## anywhere other than its own path makes the parser report "hides a global script class" for
## every one of them, which is a hundred false positives, and setting the path back collides with
## the already-registered script. A separate process starts from a clean global class table, which
## is the same state the editor is in when it reports these.
static func _warnings_in(path: String) -> Array:
	var output: Array = []
	var args := [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--check-only",
		"--script", path,
	]
	OS.execute(OS.get_executable_path(), args, output, true)

	var found: Array = []
	# The message and the site it came from arrive on consecutive lines, and the site is what makes
	# a report actionable — "integer division somewhere" is the report that produced three copies
	# of one formatter and no clue that they were three copies.
	var lines: PackedStringArray = ("\n".join(PackedStringArray(output))).split("\n")
	var pending := ""
	for line in lines:
		var text := line.strip_edges()
		if text.begins_with("SCRIPT ERROR: Parse Error:"):
			pending = text.trim_prefix("SCRIPT ERROR: Parse Error:").strip_edges()
		elif pending != "" and text.begins_with("at: GDScript::reload"):
			var site := text.get_slice("(", 1).get_slice(")", 0)
			found.append("%s — %s" % [site, pending])
			pending = ""
	return found
