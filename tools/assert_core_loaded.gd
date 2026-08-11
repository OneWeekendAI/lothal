extends SceneTree
## Fail fast if the Rust core did not load.
##
## Every class here is registered by rust/ and by nothing else — the GDScript implementations
## were deleted when the port landed — so if ClassDB does not know them, res://build/
## lothal_core.dll was not loaded and the build has no powertrain and no activation.
##
## This exists because the test suite is NOT a reliable detector of that failure. With the
## extension unloaded, run_tests.gd does not fail: the missing types surface as parse errors,
## a suite returns null, and the runner dies inside its own reporting loop without ever
## reaching quit() — the process then hangs until the CI job's timeout. A hung job an hour
## later reads like an infrastructure flake rather than a missing .dll, which is exactly the
## wrong diagnosis. Run this before the suite so the failure is one line and immediate.
##
## The failure it most recently caught: lothal.gdextension's comments were written with "#",
## which Godot's ConfigFile parser does not accept, so parsing stopped at the first comment
## and every windows.* key below it was dropped. The .dll was present and correct.

const REQUIRED := ["Powertrain", "MotorModel", "BatteryModel", "Licence"]

func _init() -> void:
	var missing: Array[String] = []
	for cls in REQUIRED:
		if not ClassDB.class_exists(cls):
			missing.append(cls)

	if missing.is_empty():
		print("CORE OK — GDExtension loaded, ClassDB knows: ", ", ".join(REQUIRED))
		quit(0)
		return

	printerr("error: the Rust core did not load — ClassDB is missing: ", ", ".join(missing))
	printerr("       Expected res://build/lothal_core.dll, loaded via res://lothal.gdextension.")
	printerr("       Check, in this order:")
	printerr("         1. build/lothal_core.dll exists (the cargo build and the copy step)")
	printerr("         2. lothal.gdextension parses — comments must start with ';', not '#'")
	printerr("         3. a [libraries] key matches the tags from tools/print_features.gd")
	quit(1)
