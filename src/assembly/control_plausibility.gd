class_name ControlPlausibility
extends RefCounted
## What a build says about the parts the pilot's intent passes through — control-room design §6,
## slice C6. The sibling to FcPlausibility, registered beside it in `Build.warnings()`, and under
## the same standing rule: WARN, NEVER BLOCK. Severity changes how a thing is said, never whether
## a part can be chosen.
##
## Three statements, and each one quotes the number it was computed from, which is the house rule
## every Power check follows.
##
## ---------------------------------------------------------------------------
## WHY THE PORT ROW NOW STATES A NUMBER, AND WHAT IT SAYS IN THE SAME BREATH
## ---------------------------------------------------------------------------
##
## A GPS needs a UART and so does a receiver. A buzzer does not — it takes a dedicated beeper pad.
## So "do the peripherals fit the board" is a real question a builder has to answer, and until C5
## Lothal REFUSED TO ANSWER IT: no board published a port count, and a headroom figure derived from
## a count nobody published would have been a construction wearing a measurement's confidence.
##
## C5 does not source those counts — config-room design §0.1 declines that route, because sourcing
## tasks stall. It ships a CLASS-TYPICAL RANGE per entry plus an editable per-build override, and
## the refusal above is replaced by a narrower and still honest one: THE ROW STATES THE FIGURE AND
## ITS PROVENANCE TOGETHER, NEVER THE FIGURE ALONE. Three provenances, three different kinds of
## claim — the catalog's guess about a class, the builder's own typed number, and the silence that
## is still reachable for an entry carrying no range at all. `PortBudget` owns all three, and this
## file asks it rather than reading the catalog itself.
##
## What is still refused: a headroom or spare-port count. The verdict ("four does not fit") is what
## a builder acts on and it survives the range; "you have two ports spare" would not.
## `tests/test_control_warnings.gd` and `tests/test_config_ports.gd` assert both halves — the
## figure's provenance, and the absence of the spare count.

## Which fitted components occupy a serial port on the flight controller.
##
## WAS `["receiver", "gps"]`, and config-room design §4.2 calls that short IN THE DANGEROUS
## DIRECTION: it under-reports demand, so a build reads as fitting when it does not. A VTX is the
## row that was missing — an analog board's channel and power control (SmartAudio, Tramp) takes a
## UART, and a digital board's OSD and telemetry link takes one too. Which sentence applies is read
## off `catalog.signal`, which every VTX entry already carries; NO CATALOG ENTRY WAS EDITED TO ADD
## ANY OF THIS.
##
## The buzzer is still deliberately absent: it lands on the beeper pad, which is not a UART, and
## folding it in would inflate a count whose whole value is that it is truthful. The camera is
## absent too — joystick-over-UART OSD control exists, but whether a given analog camera has it is
## not in any field here, and a row that fires on every camera would be a guess counted as a fact.
##
## THE ESC IS NOT IN THIS LIST AND IS NOT AN OVERSIGHT: whether it wants a port depends on its
## protocol rather than on its presence. See `_esc_telemetry_demand`.
const SERIAL_PERIPHERALS := ["receiver", "gps", "vtx"]

## How a protocol name announces that the ESC can return telemetry on the signal wire it already
## has. Matched as a PREFIX on the lowered string, so DShot300 and DShot600 both answer, and
## Multishot — which contains no such thing — does not.
const DSHOT_PREFIX := "dshot"

## What a board publishing no range reads as. Re-exported from `PortBudget`, which owns the supply
## side outright, under the name this row shipped with in C4 so the text has one spelling.
const PORTS_UNPUBLISHED := PortBudget.UNPUBLISHED_TEXT


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	_no_receiver(build, out)
	_buzzer_dies_with_the_pack(build, out)
	_serial_peripherals(build, out)

	return out


## §6.1 — the one warning in the project that catches an aircraft NOBODY CAN FLY.
##
## Lothal has been silent about this since the receiver category existed: a build with no receiver
## and no receiver on the board has no path from the sticks to the motors at all, and every other
## number the app reports about it is about an aircraft that will sit there.
##
## It fires on "not fitted" ALONE, and names the AIO case in its own text rather than pretending to
## a check it cannot make: no board in `flight_controllers.json` carries a `has_receiver` flag, so
## Lothal cannot tell a whoop AIO with the receiver on the board — which is the commonest reason a
## real small build has no separate receiver — from a 5" freestyle build that has simply forgotten
## one. Adding that flag is design §9's second item and would turn this from a prompt into a check.
static func _no_receiver(build: Build, out: Array[BuildWarning]) -> void:
	if build.components.has("receiver"):
		return

	out.append(BuildWarning.limiting(&"no_receiver",
		("Nothing on this build receives the sticks: no receiver is fitted, so there is no path "
		+ "from the transmitter to the flight controller. If your board is an AIO with the "
		+ "receiver built in — which is the commonest reason a small build carries none — this is "
		+ "correct and Lothal cannot tell, because no board in this catalog says whether it has "
		+ "one. Otherwise the aircraft will arm and never respond."),
		{"receiver_fitted": false, "fc": str(build.fc.get("name", "")),
			"fc_publishes_receiver": false}))


## §6.2 — a buzzer wired to the flight controller's 5 V rail.
##
## NOT AN ERROR, and the severity says so: most buzzers are wired to the FC and that is a
## legitimate choice a builder makes knowingly. What the warning does is say what it costs, at the
## only moment the cost lands — the pack has ejected on impact, the quad is somewhere in long
## grass, and the thing you were relying on to find it went silent when the pack came off.
##
## NOT FITTING A BUZZER AT ALL IS NOT WARNED ABOUT. A racer flying over concrete in line of sight
## does not need one, and a warning that fires on every build is a warning nobody reads.
static func _buzzer_dies_with_the_pack(build: Build, out: Array[BuildWarning]) -> void:
	if not build.components.has("buzzer"):
		return

	var buzzer: Dictionary = build.components["buzzer"]
	var self_powered := bool((buzzer.get("specs", {}) as Dictionary).get("self_powered", false))
	if self_powered:
		return

	out.append(BuildWarning.limiting(&"buzzer_not_self_powered",
		("%s takes its power from the flight controller, so it goes silent the moment the pack "
		+ "disconnects — which is the moment it is for, because that is what happens on a hard "
		+ "landing. A buzzer with its own cell keeps sounding after the pack has ejected.") % [
			buzzer.get("name", "This buzzer")],
		{"self_powered": false, "buzzer": str(buzzer.get("name", "")),
			"mass_g": float(buzzer.get("mass_g", 0.0))}))


## §6.3 — how many fitted parts want a serial port, and the honest silence about how many there are.
##
## Fires on EVERY build, including the one with nothing fitted, because the count is a description
## rather than a fault and a builder comparing two boards wants it either way. CHARACTERISTIC for
## exactly that reason: this is what the build IS, not something wrong with it.
##
## SLICE C4 WIDENED THE DEMAND SIDE AND NOT THE SUPPLY SIDE. A VTX now counts, and an ESC counts
## when its protocol cannot carry telemetry home on the signal wire. C5 THEN GAVE IT A SUPPLY SIDE:
## the board's figure comes from `PortBudget` with its provenance attached, and the row ends on a
## verdict when one can be reached.
##
## An ESC that publishes no protocol at all is counted, deliberately: the failure this row exists
## to prevent is under-reporting demand, so the unknown case errs toward wanting a wire and the
## sentence names what it did not know.
##
## `values` carries the demand count, the names, and the board's figure WITH `uart_provenance`
## beside it — never one without the other, because the sheet and the panel read `values` rather
## than the sentence. It still carries NO headroom and no spare-ports figure; see the header.
static func _serial_peripherals(build: Build, out: Array[BuildWarning]) -> void:
	var fitted: Array[String] = []
	var reasons := {}
	for part in serial_parts(build):
		fitted.append(str(part["name"]))
		reasons[part["category"]] = part["reason"]

	var subject := "Nothing fitted needs a serial port"
	if fitted.size() == 1:
		subject = "One fitted part needs a serial port (%s)" % fitted[0]
	elif fitted.size() > 1:
		subject = "%d fitted parts need a serial port (%s)" % [fitted.size(), ", ".join(fitted)]

	# The supply side, asked of the one accessor that owns it. The sentence it returns CARRIES ITS
	# OWN PROVENANCE, which is why it is pasted in whole rather than having a number picked out of
	# it here — a caller that took `low` and `high` and wrote its own sentence is exactly how a
	# guess loses its label.
	var budget := PortBudget.for_build(build)
	var verdict := PortBudget.verdict(fitted.size(), budget)

	var values := {"serial_peripherals": fitted.size(), "peripherals": fitted, "reasons": reasons,
		"fc": str(build.fc.get("name", "")), "uart_provenance": String(budget["provenance"])}
	# NO PORT FIGURE IN `values` WHEN NONE IS KNOWN, rather than a zero that reads as a count.
	if String(budget["provenance"]) != PortBudget.UNPUBLISHED:
		values["uart_low"] = int(budget["low"])
		values["uart_high"] = int(budget["high"])

	var sentences: Array[String] = ["%s." % subject, String(budget["sentence"])]
	if not verdict.is_empty():
		sentences.append(verdict)
	sentences.append("The buzzer is not counted: it lands on the beeper pad, not a UART.")

	out.append(BuildWarning.characteristic(&"serial_peripherals", " ".join(sentences), values))


## Every fitted part that wants a serial port, `{category, name, reason}`, in the order the row
## names them: the SERIAL_PERIPHERALS that are fitted, then the ESC when its protocol has no return
## path. ONE LIST, read by this row and by the Lab dock's Control figures (`ControlFigures`), so the
## count the list quotes and the count this warning states cannot differ.
static func serial_parts(build: Build) -> Array:
	var out: Array = []
	for category in SERIAL_PERIPHERALS:
		if not build.components.has(category):
			continue
		var part: Dictionary = build.components[category]
		out.append({"category": category, "name": str(part.get("name", category)),
			"reason": _reason_for(category, part)})
	var esc_reason := _esc_telemetry_demand(build)
	if not esc_reason.is_empty():
		out.append({"category": "esc", "name": str(build.esc.get("name", "esc")),
			"reason": esc_reason})
	return out


## WHY EACH COUNTED PART WANTS A PORT, in the words a builder acts on — they go to different wires,
## and one sentence covering both VTX kinds would send half of them to the wrong pad.
##
## Read off `catalog.signal` alone. A VTX entry with no signal published gets the weaker sentence,
## because the control link is the reason that is true of analog and digital boards alike.
static func _reason_for(category: String, part: Dictionary) -> String:
	if category != "vtx":
		if category == "gps":
			return "position over a UART; its compass rides I²C and costs no port"
		return "the link from the transmitter"

	var signal_kind := str((part.get("catalog", {}) as Dictionary).get("signal", "")).to_lower()
	if signal_kind == "digital":
		return "the OSD and telemetry link of a digital system"
	if signal_kind == "analog":
		return "channel and power control over SmartAudio or Tramp"
	return "its control link, whichever the board speaks"


## The ESC telemetry wire — design §4.2's third correction, and the one that is CONDITIONAL.
##
## A DShot ESC can return rpm and temperature bidirectionally on the signal wire it already has, so
## it costs no port. An older protocol has no return path there and wants a dedicated telemetry
## UART. That is a lookup against `catalog.protocol`, which every entry already carries — design
## §8's third row, the one that is explicitly not a guess.
##
## Returns the reason, or an empty string when the ESC wants nothing. NOT a claim that bidirectional
## DShot is switched ON: it is the weaker and true claim that the wire is there, and it stayed that
## way when C6 gave the setting somewhere to live (`FailsafeSettings.bidir_dshot`). A DShot ESC has
## its return path whether or not the feature is enabled, so the port count does not move with the
## switch — `ConfigPlausibility._bidir_dshot_unsupported` asks the OTHER question of the same field,
## which is whether the setting can do what it says.
static func _esc_telemetry_demand(build: Build) -> String:
	if build.esc.is_empty():
		return ""
	var protocol := str((build.esc.get("catalog", {}) as Dictionary).get("protocol", ""))
	if protocol.to_lower().begins_with(DSHOT_PREFIX):
		return ""
	return ("telemetry over a wire of its own: %s has no return path on the signal wire, "
		+ "which a DShot ESC would have") % [protocol if not protocol.is_empty()
			else "this ESC's protocol"]
