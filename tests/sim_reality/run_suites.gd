extends SceneTree
## SR1: runs the suites that touch the powertrain, battery, sim and Design Space classes (the set the
## SR0 plan names) plus the new SR1 subsystem suite. Not the full run_tests.gd.
##   godot --headless --script res://tests/sim_reality/run_suites.gd [-- only=<name>]
func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.get_slice("=", 1)
	var suites := {
		"powertrain": TestPowertrain, "battery model": TestBatteryModel, "forward flight": TestForwardFlight,
		"hover": TestHover, "hover at charge": TestHoverAtCharge, "validation": TestValidation,
		"build validation": TestBuildValidation, "battery audit": TestBatteryAudit, "air density": TestAirDensity,
		"wind": TestWind, "wind numbers": TestWindNumbers, "motor spin up": TestMotorSpinUp, "bemt": TestBemt,
		"bemt forward": TestBemtForward, "esc": TestEsc, "motor dc": TestMotorDc, "observables": TestObservables,
		"pack current limit": TestPackCurrentLimit, "rust constants": TestRustConstants, "bmp classes": TestBmpClasses,
		"motor current": TestMotorCurrent, "designed pack flies": TestDesignedPackFlies, "bench": TestBench,
		"hover stability": TestHoverStability, "sr1 physics": TestSr1Physics, "sr1 flight": TestSr1Flight, "sr4 nav": TestSr4Nav, "sr4 survey": TestSr4Survey, "sr4 mission": TestSr4Mission, "sr2 wind": TestSr2Wind, "sr3 world": TestSr3World,
	}
	var total := 0
	var failed := 0
	for name in suites:
		if only != "" and name != only:
			continue
		var results: Array = suites[name].run()
		var bad := 0
		for r in results:
			total += 1
			if not r.passed:
				bad += 1
				failed += 1
				print("  [FAIL] %s: %s (%s)" % [name, r.name, r.detail])
		print("%-22s %4d checks  %s" % [name, results.size(), "ok" if bad == 0 and results.size() > 0 else "FAILED %d" % bad])
	print("TOTAL %d checks, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
