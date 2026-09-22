extends SceneTree
## Runs ONE suite: godot --headless --script res://tools/run_one_suite.gd -- <SuiteClass>
##
## A development aid, deliberately not in run_tests.gd's SUITES and not a gate: the full runner is
## still what "the tests pass" means. This exists because mutation-testing a single suite — revert,
## break something on purpose, check that the right assertion fires, revert again — is a loop you
## run a dozen times, and the full suite is minutes per turn.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: run_one_suite.gd -- <SuiteClass>")
		quit(2)
		return

	var suite_name := args[0]
	if not ClassDB.class_exists(suite_name) and not _is_global_class(suite_name):
		print("no such registered class: %s" % suite_name)
		quit(2)
		return

	var script: Script = load(_path_of(suite_name))
	var results: Array = script.run()

	# RULING 27. A `null` element means a section aborted mid-way and its `results.append(...)`
	# received the aborted function's return-type default rather than a TestResult — see
	# tests/real_files.gd for why that is expected, survivable behaviour and not a crash. Before
	# this guard existed, `result.passed` on that `null` threw its OWN SCRIPT ERROR here, which
	# aborted `_init()` before it reached `quit()` below — the whole process then sat idle forever,
	# reporting nothing, indistinguishable from a stuck test without reading the engine's own log.
	# Reported LOUD and FAILED rather than skipped: a null element is itself the defect a mutation
	# run exists to catch, and silently passing over it would trade a hang for a false green, which
	# is worse than either.
	var failed := 0
	for i in results.size():
		var result = results[i]
		if result == null:
			failed += 1
			print("[FAIL] suite \"%s\" produced a null result at index %d (a section aborted and never appended a TestResult — see tests/real_files.gd)" % [suite_name, i])
			continue
		if not result.passed:
			failed += 1
		print("[%s] %s (%s)" % ["PASS" if result.passed else "FAIL", result.name, result.detail])

	print("")
	print("%d/%d failed in %s" % [failed, results.size(), suite_name])
	quit(1 if failed > 0 else 0)


func _is_global_class(suite_name: String) -> bool:
	return _path_of(suite_name) != ""


func _path_of(suite_name: String) -> String:
	for entry in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == suite_name:
			return str(entry.get("path", ""))
	return ""
