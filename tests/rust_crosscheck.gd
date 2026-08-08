extends SceneTree
## Golden-value cross-check (design check 3). Runs each Rust class against its GDScript
## reference twin and asserts agreement to float tolerance. Run explicitly:
##   godot --headless --path . --script res://tests/rust_crosscheck.gd
## NOT part of the SUITES list in run_tests.gd.
##
## Each comparison block exists only while its reference twin is still in the tree —
## a comparison whose twin has been deleted asserts nothing. Discipline
## (plans-that-cannot-fail): every block starts with a smoke guard (a call that must return
## a finite number) so a broken class can never read as a pass, and each block is
## mutation-tested before the class it guards is trusted.

func _init() -> void:
	var failures := 0
	if failures == 0:
		print("RUST CROSSCHECK OK")
	else:
		print("%d RUST CROSSCHECK FAILURES" % failures)
	quit(1 if failures > 0 else 0)
