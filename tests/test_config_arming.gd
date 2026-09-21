class_name TestConfigArming
extends RefCounted
## Config room slice C7 — THE ARMING LIST. Design: plans/2026-09-20-config-room-design.md §4.4.
##
## C6 built the three refusals predictable from a build. This slice is the other half of §4.4's
## table — the row that reads "Throttle up / not level / gyro calibrating / not bound — **No.**
## Runtime. **Teach, do not check**" — and everything here exists to stop that half turning into a
## check by accident.
##
## THREE THINGS ARE LOAD-BEARING, and each has its own assertions below:
##
##   IT TEACHES, IT DOES NOT CHECK.  `ArmingNotes` is handed no build and has no function that
##     could take one, so there is no seam through which a verdict about an aircraft could appear.
##     That is asserted against the script's own method list rather than trusted, because the way
##     this half goes wrong is one convenience function in six months' time.
##
##   IT USES THE CONFIGURATOR'S OWN WORDS.  Every flag taught is a string Betaflight itself prints
##     next to `ARMING DISABLED`, spelled its way. §4.4 says the names were domain knowledge and
##     unverified, and that "the check happens inside the slice that writes them": it happened, on
##     2026-09-21, against `src/main/fc/runtime_config.c` (`armingDisableFlagNames`) and
##     `runtime_config.h` (`armingDisableFlags_e`) on betaflight/betaflight master. The verified
##     list is pinned in `ArmingNotes.FIRMWARE_FLAG_NAMES`, and the taught list is asserted to be a
##     subset of it IN THE FIRMWARE'S ORDER — so a paraphrase ("NO_GYRO", "ARM SWITCH") or a
##     plausible invention cannot reach a builder's screen looking like a firmware string.
##
##   A GUESS IS NEVER PRESENTED AS MEASURED.  Lothal cannot see a live flag: not one of the thirty
##     is a fact about a build. So EVERY line says so, including the two whose BUILD side Config
##     genuinely does check — those two are the dangerous ones, because a sheet that says "Config
##     checks this" a line away from a flag name is one reading away from "Lothal says you will
##     arm". The build-side notes are also asserted to name a check this sheet actually shows, so
##     the prose cannot point at a warning that does not exist.
##
## WHAT IS DELIBERATELY NOT ASSERTED: that the prose is good. A test that only checks a string is
## non-empty cannot fail for any reason worth knowing, so nothing below does that.


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_the_words_are_the_firmwares_own())
	results.append_array(_no_line_claims_to_know_a_live_flag())
	results.append_array(_the_runtime_refusals_the_design_names_are_all_taught())
	results.append_array(_it_is_handed_no_build_and_could_not_take_one())
	results.append_array(_the_sheet_carries_the_list_unchanged_by_the_build(catalog))
	return results


## The Configurator's own words, verified against the firmware source in this slice. Two failures
## are prevented separately: a name that is not the firmware's at all, and a name that is the
## firmware's but in an order the firmware does not use — the second matters because ARM_SWITCH is
## documented in `runtime_config.h` as necessarily last ("it's always activated if one of the
## others is active when arming"), which is exactly the teaching point of its own line.
static func _the_words_are_the_firmwares_own() -> Array:
	var results: Array = []

	var strays: Array = []
	for entry in ArmingNotes.FLAGS:
		if not ArmingNotes.FIRMWARE_FLAG_NAMES.has(String(entry["flag"])):
			strays.append(String(entry["flag"]))
	results.append(TestResult.new(
		"every flag taught is one Betaflight itself prints, spelled its way",
		strays.is_empty(), "not in the firmware's list: %s" % [strays]))

	var taught_order: Array = []
	for entry in ArmingNotes.FLAGS:
		taught_order.append(ArmingNotes.FIRMWARE_FLAG_NAMES.find(String(entry["flag"])))
	var ascending := true
	for i in range(1, taught_order.size()):
		if taught_order[i] <= taught_order[i - 1]:
			ascending = false
	results.append(TestResult.new(
		"and they are taught in the firmware's own order",
		ascending and not taught_order.has(-1), "firmware indices %s" % [taught_order]))

	results.append(TestResult.new(
		"and ARM_SWITCH is last, as the firmware requires and as its line teaches",
		String(ArmingNotes.FLAGS[-1]["flag"]) == "ARM_SWITCH"
			and String(ArmingNotes.FIRMWARE_FLAG_NAMES[-1]) == "ARM_SWITCH",
		"last taught \"%s\", last firmware \"%s\"" % [ArmingNotes.FLAGS[-1]["flag"],
			ArmingNotes.FIRMWARE_FLAG_NAMES[-1]]))

	return results


## The standing rule, applied to prose. Lothal can see a build; it cannot see a flag. Every line
## has to say so — and the two lines that carry a build-side note are the ones this assertion is
## really for, because those are the lines that could be read as a verdict.
static func _no_line_claims_to_know_a_live_flag() -> Array:
	var results: Array = []

	var preamble := ArmingNotes.preamble().to_lower()
	results.append(TestResult.new(
		"the preamble says plainly that Lothal does not know which of these is set",
		preamble.contains("cannot") and preamble.contains("which of these"),
		"\"%s\"" % [ArmingNotes.preamble()]))

	var silent: Array = []
	for line in ArmingNotes.lines():
		if not line.contains(ArmingNotes.CANNOT_SEE):
			silent.append(line.split(" ")[0])
	results.append(TestResult.new(
		"and every line says Lothal cannot see the live flag, the build-side ones included",
		silent.is_empty(), "lines missing the disclaimer: %s" % [silent]))

	var with_notes: Array = []
	var dangling: Array = []
	for entry in ArmingNotes.FLAGS:
		var checked := String(entry["checked"])
		if checked == "":
			continue
		with_notes.append(String(entry["flag"]))
		if not ConfigFailsafePanel.SHOWN_WARNINGS.has(StringName(checked)):
			dangling.append(checked)
	results.append(TestResult.new(
		"and a build-side note names a check this sheet actually shows, never an invented one",
		dangling.is_empty() and not with_notes.is_empty(),
		"noted %s, dangling %s" % [with_notes, dangling]))

	return results


## §4.4 names five runtime refusals by hand — "the gyro did not calibrate, the board is not level,
## the throttle is up, the receiver has not bound, the arm switch was already on at power-up" —
## and calls them the half worth more to a first build than any number in the document. They are
## the coverage floor, asserted one per line so a gap says which one.
static func _the_runtime_refusals_the_design_names_are_all_taught() -> Array:
	var results: Array = []
	var wanted := {
		"NOGYRO": "the gyro the board could not find",
		"CALIB": "the gyro still calibrating",
		"ANGLE": "the board not level",
		"THROTTLE": "the throttle up",
		"RXLOSS": "the receiver not bound",
		"ARM_SWITCH": "the arm switch already on at power-up",
	}
	var taught: Array = []
	for entry in ArmingNotes.FLAGS:
		taught.append(String(entry["flag"]))
	for flag in wanted:
		results.append(TestResult.new(
			"§4.4's \"%s\" is taught, as %s" % [wanted[flag], flag],
			taught.has(flag), "taught: %s" % [taught]))
	return results


## Teach, not check — asserted structurally rather than promised in a comment. A module that takes
## a Build is a module that can return a verdict about one, so the absence of any argument at all
## is the property worth pinning: it is what makes "it cannot pretend to know the aircraft's live
## state" true by construction instead of by discipline.
static func _it_is_handed_no_build_and_could_not_take_one() -> Array:
	var script: GDScript = load("res://src/assembly/arming_notes.gd")
	var with_args: Array = []
	for method in script.get_script_method_list():
		if not (method["args"] as Array).is_empty():
			with_args.append(String(method["name"]))
	return [TestResult.new(
		"ArmingNotes asks nothing about an aircraft: not one of its functions takes an argument",
		with_args.is_empty(), "functions taking arguments: %s" % [with_args])]


## On the sheet, and the same on every sheet. §4.4: "the section has two halves and they must look
## different on screen" — the checks move with the build, the teaching does not. Two builds chosen
## to disagree about every check C6 makes must still read the same arming list, which is the
## difference between prose and a verdict stated as prose.
static func _the_sheet_carries_the_list_unchanged_by_the_build(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var panel := ConfigFailsafePanel.new()
	var clean := _build(catalog, {"receiver": "rx_elrs_2400", "buzzer": "buzz_active_5v"}, {})
	panel.render(clean)
	var clean_text := panel.arming_text()

	var missing: Array = []
	for entry in ArmingNotes.FLAGS:
		if not clean_text.contains(String(entry["flag"])):
			missing.append(String(entry["flag"]))
	results.append(TestResult.new(
		"the Failsafe sheet carries every flag of the arming list, in the module's own words",
		missing.is_empty() and clean_text.contains(ArmingNotes.preamble()),
		"missing %s" % [missing]))

	var bad_config := {}
	FailsafeSettings.set_stage2(bad_config, FailsafeSettings.GPS_RESCUE)
	FailsafeSettings.set_bidir_dshot(bad_config, true)
	var broken := _build(catalog, {}, bad_config)
	broken.esc = broken.esc.duplicate(true)
	(broken.esc["catalog"] as Dictionary)["protocol"] = "Multishot"
	panel.render(broken)
	results.append(TestResult.new(
		"and a build that fails every check C6 makes reads exactly the same arming list",
		panel.arming_text() == clean_text,
		"differs by %d characters" % [panel.arming_text().length() - clean_text.length()]))
	results.append(TestResult.new(
		"while the checks beside it did move, so the comparison above was not of two blank sheets",
		panel.warning_text() != "" and panel.warning_text().to_lower().contains("rescue"),
		"warnings: \"%s\"" % [panel.warning_text()]))

	return results


static func _build(catalog: PartsCatalog, components: Dictionary, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, components)
	build.set_config(config)
	return build
