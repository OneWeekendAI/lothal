extends SceneTree
## Headless test runner: godot --headless --script res://tests/run_tests.gd
## Orchestrates each test module and prints PASS/FAIL per week1.md's Day 2 gate:
## all seven checks must print PASS before Day 3 (wiring into 3D) may begin.
##
## Each suite's results print as that suite finishes rather than being collected and
## dumped at the end, so a suite that hangs or crashes names itself instead of leaving
## the runner silent.

const SUITES := ["mass properties", "hover", "torque signs", "hover stability",
	"rate step response", "rate mode release", "translation", "parts system", "build panel",
	"gate course", "hud", "keyboard throttle", "observables", "rotor synth",
	"frame model", "motor mesh", "propeller mesh", "airframe", "mounting",
	"assembly tweaks", "prop rotation", "lab", "powertrain", "validation"]

func _init() -> void:
	var total := 0
	var fail_count := 0

	for suite_name in SUITES:
		var results := _run_suite(suite_name)
		# A suite that returns nothing has crashed, or its class failed to register. Left
		# unchecked that reads as zero failures, and the runner cheerfully reports success
		# for tests it never ran — the one outcome a test runner must never produce.
		if results.is_empty():
			fail_count += 1
			total += 1
			print("[FAIL] suite \"%s\" produced no results (crashed, or class not registered)" % suite_name)
			continue

		for result in results:
			var status: String = "PASS" if result.passed else "FAIL"
			if not result.passed:
				fail_count += 1
			total += 1
			print("[%s] %s (%s)" % [status, result.name, result.detail])

	print("")
	if fail_count == 0:
		print("ALL %d TESTS PASSED" % total)
	else:
		print("%d/%d TESTS FAILED" % [fail_count, total])

	quit(1 if fail_count > 0 else 0)

func _run_suite(suite_name: String) -> Array:
	match suite_name:
		"mass properties": return TestMassProperties.run()
		"hover": return TestHover.run()
		"torque signs": return TestTorqueSigns.run()
		"hover stability": return TestHoverStability.run()
		"rate step response": return TestRateStepResponse.run()
		"rate mode release": return TestRateModeRelease.run()
		"translation": return TestTranslation.run()
		"parts system": return TestPartsSystem.run()
		"build panel": return TestBuildPanel.run()
		"gate course": return TestGateCourse.run()
		"hud": return TestHud.run()
		"keyboard throttle": return TestKeyboardThrottle.run()
		"observables": return TestObservables.run()
		"rotor synth": return TestRotorSynth.run()
		"frame model": return TestFrameModel.run()
		"motor mesh": return TestMotorMesh.run()
		"propeller mesh": return TestPropellerMesh.run()
		"airframe": return TestAirframeModel.run()
		"mounting": return TestMounting.run()
		"assembly tweaks": return TestAssemblyTweaks.run()
		"prop rotation": return TestPropRotation.run()
		"lab": return TestLab.run()
		"powertrain": return TestPowertrain.run()
		"validation": return TestValidation.run()
	push_error("unknown suite: %s" % suite_name)
	return []
