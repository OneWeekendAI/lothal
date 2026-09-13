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
## WHY THE PORT ROW STATES NO NUMBER, AND WHY THAT IS THE POINT
## ---------------------------------------------------------------------------
##
## A GPS needs a UART and so does a receiver. A buzzer does not — it takes a dedicated beeper pad.
## So "do the peripherals fit the board" is a real question a builder has to answer, and Lothal
## CANNOT ANSWER IT: there are zero occurrences of `uart` in `src/`, and not one of the six boards
## in `flight_controllers.json` publishes a port count. None ever has.
##
## The honest thing available is the half that is knowable: count the fitted parts that need a
## serial port, state that count, and say plainly that the board's own count is not published in
## this catalog. That is a row a builder can act on — two peripherals, go and look up your board —
## and it is not a claim Lothal cannot support.
##
## THE FAILURE MODE HERE IS NOT A WRONG NUMBER, IT IS A CONFIDENT ONE. A headroom figure derived
## from a port count nobody published would be a construction wearing a measurement's confidence,
## which is the one thing design §0's relaxation still refuses: values may be rough, but a guess
## may never be presented as measured. `tests/test_control_warnings.gd` asserts the ABSENCE of the
## claim, which is an odd-looking check and the most important one in this file.
##
## Adding `uarts` to the six catalog entries turns this row into a real check. It is a sourcing
## task rather than a code task, and it is the first item on design §9's list.

## Which fitted components occupy a serial port on the flight controller.
##
## The buzzer is deliberately absent: it lands on the beeper pad, which is not a UART, and folding
## it in would inflate a count whose whole value is that it is truthful.
const SERIAL_PERIPHERALS := ["receiver", "gps"]

## What the board's port count reads as, everywhere it is shown. A single constant rather than a
## literal per site, so the row and the panel beside it cannot come to say it two different ways.
const PORTS_UNPUBLISHED := "not published in this catalog"


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
## `values` carries the count and the names. It carries NO port count, no headroom, and no
## remaining-ports figure, and there is no key here for one to arrive in later by accident — see
## the header, and see the check that asserts this absence.
static func _serial_peripherals(build: Build, out: Array[BuildWarning]) -> void:
	var fitted: Array[String] = []
	for category in SERIAL_PERIPHERALS:
		if build.components.has(category):
			fitted.append(str(build.components[category].get("name", category)))

	var subject := "Nothing fitted needs a serial port"
	if fitted.size() == 1:
		subject = "One fitted part needs a serial port (%s)" % fitted[0]
	elif fitted.size() > 1:
		subject = "%d fitted parts need a serial port (%s)" % [fitted.size(), ", ".join(fitted)]

	out.append(BuildWarning.characteristic(&"serial_peripherals",
		("%s. How many this board has is %s, so Lothal cannot tell you whether they fit — check "
		+ "your board's own documentation. The buzzer is not counted: it lands on the beeper pad, "
		+ "not a UART.") % [subject, PORTS_UNPUBLISHED],
		{"serial_peripherals": fitted.size(), "peripherals": fitted,
			"fc": str(build.fc.get("name", ""))}))
