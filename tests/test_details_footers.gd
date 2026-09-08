class_name TestDetailsFooters
extends RefCounted
## Every PartDetails subclass must still have PartDetails' stat block.
##
## The footer is an override point, and an override that forgets `super(root)` builds its own
## controls and silently drops the five stat labels `PartDetails.render()` writes into. That is not
## a quiet degradation — the next render dies on `_stat_values["weight"]`, an invalid key access on
## an empty Dictionary, which is exactly what EscDetails did the moment an ESC was selected.
##
## So the check is per panel, not a loop: a failure names the panel whose footer broke the chain.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var build := ReferenceBuild.build()

	var panels := {
		"frame": [FrameDetails.new(), build.frame],
		"motor": [MotorDetails.new(catalog), build.motor],
		"propeller": [PropellerDetails.new(catalog), build.propeller],
		"battery": [BatteryDetails.new(), build.battery],
		"esc": [EscDetails.new(), build.esc],
		"fc": [FcDetails.new(), build.fc],
	}

	for name: String in panels:
		var panel: PartDetails = panels[name][0]
		var part: Dictionary = panels[name][1]
		panel.render(part, build)
		results.append(TestResult.new(
			"%s panel keeps PartDetails' stat block" % name,
			panel.stat_text("weight") == "%.0f g" % build.all_up_weight_g(),
			"weight row read %s" % panel.stat_text("weight")
		))
		panel.free()

	return results
