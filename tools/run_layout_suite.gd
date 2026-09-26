extends SceneTree
## Runs the ONE suite that needs frames: godot --headless --script res://tools/run_layout_suite.gd
##
## `tools/run_one_suite.gd` cannot reach `TestShellLayout` — that suite takes a `SceneTree`, builds
## a shell in a `SubViewport` and awaits `process_frame`, and the generic runner calls `run()` with
## no arguments and does not await. A development aid for the same reason its sibling is one:
## mutation-testing a layout check is a revert/break/check loop, and the full runner is minutes per
## turn. Neither file is the gate; `tests/run_tests.gd` is.
func _init() -> void:
	var results: Array = await TestShellLayout.run(self)
	var failed := 0
	for r in results:
		if not r.passed: failed += 1
		print("[%s] %s (%s)" % ["PASS" if r.passed else "FAIL", r.name, r.detail])
	print("%d/%d failed in shell layout" % [failed, results.size()])
	quit(1 if failed > 0 else 0)
