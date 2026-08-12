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

	var failed := 0
	for result in results:
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
