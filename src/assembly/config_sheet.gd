class_name ConfigSheet
## THE CONFIG SHEET — the artifact that leaves the room. Config room slice C9
## (plans/2026-09-20-config-room-design.md §3), built on `2026-08-17-build-sheet-design.md`'s
## decisions rather than on a second set of its own.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE IS ALLOWED TO DO, WHICH IS ALMOST NOTHING
## ---------------------------------------------------------------------------
##
## It arranges. It does not judge, derive, or word anything that another module already words.
##
## That is not modesty, it is the slice's entire safety property. C5, C6 and C8 each ended with the
## same instruction in their headers — PASTE THE SENTENCE WHOLE, do not pick the number out and
## write your own — because a caller that writes its own is exactly how a class-typical guess comes
## to read as a measurement, and how Betaflight's quoted default comes to read as Lothal's advice.
## Inside the app that mistake is recoverable: the panel is right there, and so is the builder.
##
## ON THIS SHEET IT IS NOT. The sheet's whole purpose is to be somewhere else — on a phone propped
## against a soldering iron at 11pm, with the app closed. Every hedge that goes missing here goes
## missing permanently, and a guess presented as measured gets typed into a real aircraft and
## flown. So the rule is stricter here than anywhere it came from: this file owns exactly three
## sentences of its own (`PREAMBLE`, `TUNE_BOUNDARY`, `FILTER_REFUSAL`), each about a BOUNDARY
## rather than about a figure, and every other line is another module's string moved verbatim.
##
## ---------------------------------------------------------------------------
## THE BUILD SHEET'S DECISIONS, REUSED AS THEY STAND
## ---------------------------------------------------------------------------
##
##   §2.1 ONE ARTIFACT, BOTH HALVES. The settings to type and the verdict on them ship together;
##     neither is useful alone. `## What is wrong with this build` is not an appendix.
##
##   §2.4 CONFIDENCE IS PER CLAIM, NEVER AGGREGATED. No config score. That antipattern has been
##     turned down twice already in this project, and a sheet is precisely the door it would come
##     back through — a single number at the top is what a printable artifact seems to want.
##
##   §2.5 A DATED MARKDOWN FILE, WITH A DETERMINISTIC BODY. `body()` takes no date and reads no
##     clock; `to_markdown()` adds the one dated line. A sheet whose body moved run to run could
##     not be the pre-registration §2.5 makes it, because there would be no single set of
##     predictions to hold it to.
##
##   §4 EMITTING AUTHORS NOTHING. The build sheet asserts `PackCharge` is untouched by an
##     emission; here the equivalent is the drone's `config` block, and everything below reads it
##     through the accessors that never write.
##
##   §7 A BAD PATH DEGRADES. `write()` returns false. An evening is lost to a save that failed
##     silently, not to one that said so.
##
## WHAT IT REFUSES: blocking (warn, never block — an aircraft Lothal thinks is misconfigured still
## gets a sheet, with the warnings on it), filters (§4.1/§9, named on the sheet so the absence is
## visible where a builder would look for them), and your ESC's motor order (§4.3's refusal, pasted
## from the panel that already says it).

## Where sheets land, on `FrameWorkbench.EXPORT_DIRECTORY`'s precedent: a fixed folder beside the
## project rather than a dialog, because the builder who just pressed the button knows what they
## meant and a file they cannot find has not been exported.
const DIRECTORY := "user://sheets"

## §2.1 of the CONFIG design, in the sheet's own voice. Lothal does not run Betaflight; SITL is a
## separate track. Said at the top rather than in a footnote, because everything underneath reads
## like a report on a tested aircraft otherwise.
const PREAMBLE := ("Lothal has not run any of these settings. This is a list to work through with "
	+ "a USB cable in your hand and your Configurator open: it is what to set and what to check, "
	+ "not a record of anything that has been flown. Every figure below says where it came from — "
	+ "read those labels, because some of them are guesses and they are marked as such.")

## §4.1's boundary on the tune, and it is deliberately the WEAKER claim. The derivation is
## confident about the PROPORTIONS between axes; it is not confident that these numbers belong in
## another firmware's loop, which has filters and feedforward Lothal does not model.
const TUNE_BOUNDARY := ("These gains come out of Lothal's own loop, not Betaflight's — Betaflight "
	+ "has filters and feedforward this model does not have. Treat them as a starting point with "
	+ "roughly the right ratio between the axes, not as numbers to type and trust.")

## §4.1 and §9. The refusal is printed, not omitted: the sheet is the one place a builder would go
## looking for a notch setting, and a silence there reads as "nothing needed".
const FILTER_REFUSAL := ("Nothing here recommends a filter setting — no gyro or D-term lowpass, no "
	+ "RPM filtering, no dynamic notch. Lothal models a gyro and one first-order filter, so any "
	+ "number it produced would be a guess wearing a measurement's confidence, and this is the one "
	+ "place that is not good enough: a filter setting gets typed into a real quad and flown.")

## The warning id whose message carries the whole ports row — demand, supply, provenance and
## verdict, already composed by `ControlPlausibility` from `PortBudget`'s own sentence. Looked up
## by id rather than re-derived here, so the sheet and the panel cannot disagree.
const PORTS_WARNING_ID := &"serial_peripherals"


## The sheet, minus the one dated line. Deterministic for a given build — see the header.
static func body(build: Build, drone_name: String) -> String:
	return _compose(build, drone_name, "")


## The whole sheet. The date is the ONLY thing here that is not a function of the build, and it
## lives on one line of its own so that two sheets a day apart can be diffed and seen to agree.
static func to_markdown(build: Build, drone_name: String, date: String) -> String:
	return _compose(build, drone_name, "Written: %s. Project schema %d.%d." % [
		date, ProjectSchema.SCHEMA_MAJOR, ProjectSchema.SCHEMA_MINOR])


static func _compose(build: Build, drone_name: String, dated_line: String) -> String:
	var out := PackedStringArray()
	out.append("# Config sheet — %s" % drone_name)
	if not dated_line.is_empty():
		out.append("")
		out.append(dated_line)
	out.append("")
	out.append(PREAMBLE)

	_motors(build, out)
	_ports(build, out)
	_failsafe(build, out)
	_rates(build, out)
	_tune(build, out)
	_warnings(build, out)
	_arming(out)

	out.append("")
	return "\n".join(out)


## Writes the sheet and says whether it landed. False for a path that cannot be opened — §7's
## "degrades rather than crashes", and the caller is expected to say so out loud.
static func write(build: Build, drone_name: String, path: String, date: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_markdown(build, drone_name, date))
	file.close()
	return true


## Where this drone's sheet goes: dated, named, and safe to put on a disk. Dated rather than
## overwritten, because §2.5's pre-registration argument only works if yesterday's sheet survives
## today's edit.
static func default_path(drone_name: String, date: String) -> String:
	return "%s/%s-%s.md" % [DIRECTORY, date, _safe_file_name(drone_name)]


# ---------------------------------------------------------------------------
# The sections, in the order a builder meets the Configurator's tabs
# ---------------------------------------------------------------------------

## §4.3. The map as the mixer flies it, through the one accessor, and the refusal that says what
## Lothal cannot know about it.
static func _motors(build: Build, out: PackedStringArray) -> void:
	_heading(out, "Motors")
	var spin := MotorLayout.spin_map(build.config)
	for motor_name in MotorLayout.MOTOR_NAMES:
		var place := "%s %s" % [
			"front" if MotorLayout.IS_FRONT[motor_name] else "rear",
			"right" if MotorLayout.IS_RIGHT[motor_name] else "left"]
		out.append("- %s %s — %s arm." % [motor_name,
			MotorLayout.direction_name(float(spin[motor_name])), place])
	out.append("")
	out.append(ConfigMotorsPanel.REFUSAL)


## §4.2. One line, and it is not this file's line: `ControlPlausibility` composes demand, supply
## and verdict from `PortBudget`'s own words, and the sheet moves that string unaltered.
static func _ports(build: Build, out: PackedStringArray) -> void:
	_heading(out, "Ports and UARTs")
	var message := ""
	for warning in ControlPlausibility.warnings_for(build):
		if warning.id == PORTS_WARNING_ID:
			message = warning.message
	out.append(message if not message.is_empty()
		else "Lothal has nothing to say about this board's ports.")


static func _failsafe(build: Build, out: PackedStringArray) -> void:
	_heading(out, "Failsafe")
	out.append(FailsafeSettings.stage2_sentence(build.config))
	out.append("")
	out.append("Bidirectional DShot and RPM telemetry: %s." % [
		"on" if FailsafeSettings.bidir_dshot(build.config) else "off"])


static func _rates(build: Build, out: PackedStringArray) -> void:
	_heading(out, "Rates and modes")
	out.append(RateSettings.max_rate_sentence(build.config))
	out.append("")
	out.append(RateSettings.sim_versus_real_sentence(build.config))
	out.append("")
	out.append(RateSettings.expo_sentence(build.config))
	out.append("")
	out.append(RateSettings.modes_sentence())


## The tune's export row (§4.1). Gains first, because they are the useful part; the boundary
## immediately under them, because they are also the part most easily mistaken for a Betaflight
## tune. The axis names come off `RateTune`'s own list.
static func _tune(build: Build, out: PackedStringArray) -> void:
	_heading(out, "Tune")
	var tune := RateTune.derive(build)
	for axis in RateTune.AXIS_NAMES.size():
		var gains := tune.gains_for(axis)
		out.append("- %s — P %.4f, I %.4f, D %.4f" % [
			String(RateTune.AXIS_NAMES[axis]), gains.x, gains.y, gains.z])
	out.append("")
	out.append(TUNE_BOUNDARY)
	out.append("")
	out.append(FILTER_REFUSAL)


## §2.1's other half, and §2.4's refusal of an aggregate. Each warning at the severity it already
## carries, in the order `Build.warnings()` already puts them.
static func _warnings(build: Build, out: PackedStringArray) -> void:
	_heading(out, "What is wrong with this build")
	var warnings := build.warnings()
	if warnings.is_empty():
		out.append("Nothing flagged. That is not a verdict on the aircraft — it is the absence of "
			+ "the specific things Lothal knows how to look for.")
		return
	for warning in warnings:
		out.append("- [%s] %s" % [
			BuildWarning.severity_name(warning.severity), warning.message])


## C7's list, whole. It teaches and it is handed no build, exactly as it is on screen.
static func _arming(out: PackedStringArray) -> void:
	_heading(out, "If it will not arm")
	out.append(ArmingNotes.preamble())
	out.append("")
	for line in ArmingNotes.lines():
		out.append("- " + line)


static func _heading(out: PackedStringArray, title: String) -> void:
	out.append("")
	out.append("## " + title)
	out.append("")


## A drone name as a file name, on `FrameWorkbench._safe_file_name`'s rule — a quad called `5" / v2`
## still lands on disk.
static func _safe_file_name(text: String) -> String:
	var out := ""
	for index in text.length():
		var character := text[index]
		out += character if character.is_valid_identifier() or character.is_valid_int() \
			or character == "-" else "_"
	return "drone" if out.is_empty() else out
