extends SceneTree
## Headless test runner: godot --headless --script res://tests/run_tests.gd
## Orchestrates each test module and prints PASS/FAIL per week1.md's Day 2 gate:
## all seven checks must print PASS before Day 3 (wiring into 3D) may begin.

func _init() -> void:
	var all_results: Array = []
	all_results.append_array(TestMassProperties.run())
	all_results.append_array(TestHover.run())
	all_results.append_array(TestTorqueSigns.run())
	all_results.append_array(TestHoverStability.run())
	all_results.append_array(TestRateStepResponse.run())
	all_results.append_array(TestRateModeRelease.run())

	var fail_count := 0
	for result in all_results:
		var status: String = "PASS" if result.passed else "FAIL"
		if not result.passed:
			fail_count += 1
		print("[%s] %s (%s)" % [status, result.name, result.detail])

	print("")
	if fail_count == 0:
		print("ALL %d TESTS PASSED" % all_results.size())
	else:
		print("%d/%d TESTS FAILED" % [fail_count, all_results.size()])

	quit(1 if fail_count > 0 else 0)
