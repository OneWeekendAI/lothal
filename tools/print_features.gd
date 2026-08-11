extends SceneTree
## Prints the feature tags Godot reports for this OS/arch/build. Run explicitly during CI
## debugging (windows.yml's "Diagnostic" step) to see why a .gdextension [libraries] key does
## or does not match: every tag in a key like "windows.debug.x86_64" must be reported here.
func _init() -> void:
	for feat in ["windows", "macos", "linux", "debug", "release", "editor", "template",
			"x86_64", "x86_32", "arm64", "pc"]:
		print("FEATURE ", feat, "=", OS.has_feature(feat))
	print("OS_NAME ", OS.get_name())
	quit(0)
