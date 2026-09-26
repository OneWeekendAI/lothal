class_name TestPrintedInfill
extends RefCounted
## One infill convention for every printed part that has mass — printed-room slice PR15.
##
## Where each check could pass while proving nothing, and what stops it:
##   - "mass = volume × density × infill" read through the part's own constants proves nothing about
##     SHARING. So the expected mass is built from PrintSettings alone; a part with a private infill or
##     density misses it.
##   - "the row names the infill guess" as a bare `contains("(guess)")` passes on the other guesses every
##     row already carries (the G9/P9 trap). So the row must contain the infill label itself, and the
##     label must follow the fraction: a label hard-coded to "solid" is caught at 40%.

const EPS := 1e-12


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var cases := _cases(catalog)
	for part in cases:
		var c: Dictionary = cases[part]
		var expected := float(c["volume_mm3"]) * 1.0e-9 * PrintSettings.DENSITY_KG_M3 * PrintSettings.INFILL_FRACTION
		results.append(TestResult.new(
			"%s: mass is volume × PrintSettings density × PrintSettings infill" % part,
			float(c["volume_mm3"]) > 0.0 and absf(float(c["mass_kg"]) - expected) < EPS,
			"%.6f g vs %.6f g" % [float(c["mass_kg"]) * 1000.0, expected * 1000.0]))
		results.append(TestResult.new(
			"%s: its row names the infill guess, \"%s\"" % [part, PrintSettings.infill_label()],
			String(c["note"]).contains(PrintSettings.infill_label()),
			String(c["note"])))
	results.append(TestResult.new(
		"every weighted part is solid, and the label says so and follows the fraction",
		PrintSettings.INFILL_FRACTION == 1.0 and PrintSettings.infill_label() == "solid infill (guess)"
			and PrintSettings.infill_label(0.4) == "40% infill (guess)",
		"%.2f → \"%s\"; 0.4 → \"%s\"" % [PrintSettings.INFILL_FRACTION, PrintSettings.infill_label(),
			PrintSettings.infill_label(0.4)]))
	return results


static func _note(build: Build, id: String) -> String:
	for row in PrintedParts.for_build(build):
		if String((row as Dictionary).get("id", "")) == id:
			return String(row.get("note", ""))
	return "(no %s row)" % id


static func _cases(catalog: PartsCatalog) -> Dictionary:
	var guarded := ReferenceBuild.build()
	guarded.frame = catalog.get_part("frame_5in_freestyle")
	var arm := ArmGuard.dimensions(guarded.frame, guarded.printing)
	var masted := TestGpsMast._masted_build(catalog)
	var mast := GpsMast.dimensions(masted, masted.printing)
	var padded := ReferenceBuild.build()
	var pad := BatteryPad.dimensions(padded.battery, padded.printing)
	return {
		"arm guard": {"volume_mm3": ArmGuard.volume_mm3(arm), "mass_kg": ArmGuard.mass_kg(arm),
			"note": _note(guarded, PrintedParts.ARM_GUARD)},
		"gps mast": {"volume_mm3": GpsMast.volume_mm3(mast), "mass_kg": GpsMast.mass_kg(mast),
			"note": _note(masted, PrintedParts.GPS_MAST)},
		"battery pad": {"volume_mm3": BatteryPad.volume_mm3(pad), "mass_kg": BatteryPad.mass_kg(pad),
			"note": _note(padded, PrintedParts.BATTERY_PAD)},
	}
