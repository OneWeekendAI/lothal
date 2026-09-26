class_name ArmingNotes
## The arming list: what a flight controller says when it refuses to arm, in the words the
## Configurator itself uses — Config room slice C7 (plans/2026-09-20-config-room-design.md §4.4).
##
## ---------------------------------------------------------------------------
## THIS MODULE TEACHES. IT DOES NOT CHECK, AND IT CANNOT.
## ---------------------------------------------------------------------------
##
## §4.4 splits the arming question in two. Three refusals are predictable from a build, and C6
## built those as warnings in `ConfigPlausibility` and `ControlPlausibility`. The rest are RUNTIME
## facts — the gyro did not calibrate, the board is not level, the throttle is up, the receiver has
## not bound, the arm switch was already on at power-up — and Lothal cannot predict a single one of
## them from parts and settings. The design's instruction for that half is exact: "Teach, do not
## check."
##
## So nothing here is handed a Build, and nothing here has an argument at all. That is not a style
## choice: an accessor taking a Build is a seam through which a verdict about an aircraft would
## eventually arrive, and the test asserts the absence against this script's own method list rather
## than trusting this comment. A guess may never be presented as measured, and a live flag is not
## even a guess — it is a fact about a powered aircraft sitting on a bench, which this program has
## never seen.
##
## ---------------------------------------------------------------------------
## WHERE THE NAMES COME FROM, AND WHY THAT MATTERED ENOUGH TO CHECK
## ---------------------------------------------------------------------------
##
## The whole value of this list is that a builder who has read it RECOGNISES the word when their
## Configurator prints `ARMING DISABLED` with a flag beside it. A paraphrase — "no gyro", "arm
## switch" — destroys exactly that value while looking just as helpful, which is why §4.4 flagged
## the names as "domain knowledge, unverified against firmware source" and said the check happens
## inside the slice that writes them.
##
## It happened. On 2026-09-21 the thirty names below were read off betaflight/betaflight master:
## `armingDisableFlagNames` in `src/main/fc/runtime_config.c`, cross-read against
## `armingDisableFlags_e` in `src/main/fc/runtime_config.h`. Two corrections fell out of doing it:
## the gyro flag is `NOGYRO` and not `NO_GYRO`, and the GPS-rescue switch flag is `RESCUE_SW`,
## which older recollection has as `RESC`. Both are the kind of confidently-wrong detail that this
## list exists to avoid.
##
## FIRMWARE ORDER IS KEPT because the firmware's own last element carries a teaching point: the
## header says ARM_SWITCH "needs to be the last element, since it's always activated if one of the
## others is active when arming". A builder who sees ARM_SWITCH beside something else is looking at
## the something else.
##
## WHAT THIS LIST REFUSES: being complete. Thirty flags is a reference page; this is fifteen, the
## ones a first build actually meets, and the rest are the Configurator's to show.
const FIRMWARE_FLAG_NAMES := ["NOGYRO", "FAILSAFE", "RXLOSS", "NOT_DISARMED", "BOXFAILSAFE",
	"RUNAWAY", "CRASH", "THROTTLE", "ANGLE", "BOOTGRACE", "NOPREARM", "LOAD", "CALIB", "CLI",
	"CMS", "BST", "MSP", "PARALYZE", "GPS", "RESCUE_SW", "DSHOT_TELEM", "REBOOT_REQD",
	"DSHOT_BBANG", "NO_ACC_CAL", "MOTOR_PROTO", "FLIP_SWITCH", "ALT_HOLD_SW", "POS_HOLD_SW",
	"AUTOPILOT_SW", "ARM_SWITCH"]

## The sentence that ends every line, including — especially — the two lines that carry a
## build-side note. Pasted whole rather than rewritten per entry, because a disclaimer that is
## reworded fifteen times is a disclaimer that goes missing from one of them.
const CANNOT_SEE := "Lothal cannot see the live flag."

## The teaching list, in firmware order. `checked` is empty for everything Lothal has no build-side
## opinion about, which is nearly all of it; where it is set, it names a warning id this sheet
## already shows, so the prose and the check cannot come apart.
const FLAGS := [
	{
		"flag": "NOGYRO",
		"means": "The board found no gyro at boot. On a new build this is usually the flight "
			+ "controller itself, not the setting: a bad solder joint under the board, or a "
			+ "target flashed for a different one.",
		"checked": "",
	},
	{
		"flag": "FAILSAFE",
		"means": "A failsafe is in progress, so arming is held off until it clears. Power-cycle "
			+ "with the radio already on and it usually goes.",
		"checked": "",
	},
	{
		"flag": "RXLOSS",
		"means": "No valid control signal. Nearly always the receiver: not bound, not powered, or "
			+ "wired to a UART the firmware is not listening on.",
		"checked": "",
	},
	{
		"flag": "BOXFAILSAFE",
		"means": "The failsafe switch on your radio is active. It is a switch you set up, so it is "
			+ "a switch you can leave on by mistake.",
		"checked": "",
	},
	{
		"flag": "THROTTLE",
		"means": "The throttle is not at the bottom. On a new radio this is as often a stick "
			+ "calibration or a reversed channel as it is a stick somebody left up.",
		"checked": "",
	},
	{
		"flag": "ANGLE",
		"means": "The aircraft is tilted past the arming angle. Sitting it flat clears it; if flat "
			+ "does not clear it, the board is mounted at an angle the firmware has not been told "
			+ "about.",
		"checked": "",
	},
	{
		"flag": "BOOTGRACE",
		"means": "The board has only just powered up and is still settling. Waiting clears this "
			+ "one on its own.",
		"checked": "",
	},
	{
		"flag": "CALIB",
		"means": "The gyro is calibrating. It calibrates at every boot, and it must be still while "
			+ "it does — a hand on the frame is enough to restart it.",
		"checked": "",
	},
	{
		"flag": "CLI",
		"means": "The command line is open. The Configurator holds it open, so a board that will "
			+ "not arm on the bench is often just a board still plugged into a laptop.",
		"checked": "",
	},
	{
		"flag": "MSP",
		"means": "Something is talking to the board over MSP — again, usually the Configurator. "
			+ "Unplug the USB lead before you go looking for a fault.",
		"checked": "",
	},
	{
		"flag": "GPS",
		"means": "A GPS-dependent mode was asked for and there is no usable fix yet. Indoors there "
			+ "will never be one.",
		"checked": "failsafe_gps_rescue_no_gps",
	},
	{
		"flag": "RESCUE_SW",
		"means": "The GPS rescue switch was already on when you tried to arm.",
		"checked": "",
	},
	{
		"flag": "DSHOT_TELEM",
		"means": "Bidirectional DShot was enabled and the rpm telemetry is not coming back. The "
			+ "usual causes are an ESC whose protocol cannot do it and an ESC whose firmware was "
			+ "never built for it.",
		"checked": "bidir_dshot_unsupported",
	},
	{
		"flag": "MOTOR_PROTO",
		"means": "The motor protocol configured is not one this board can output on the pins the "
			+ "motors are on.",
		"checked": "",
	},
	{
		"flag": "ARM_SWITCH",
		"means": "The arm switch was already on. It also lights up beside every other flag on this "
			+ "list — the firmware sets it whenever something else is blocking arming — so when "
			+ "you see it next to another flag, the other flag is the one to read.",
		"checked": "",
	},
]


## What the list is and, first, what it is not. The room shows this above the flags, because a page
## of firmware strings under a failsafe sheet reads like a report on the aircraft unless the first
## sentence says otherwise.
static func preamble() -> String:
	return ("A flight controller refuses to arm for a long list of reasons, and it names the one "
		+ "it has: the Configurator prints ARMING DISABLED with a flag beside it. Almost every "
		+ "flag is a fact about a powered aircraft on a bench — which of these is set right now is "
		+ "something Lothal cannot know, and this list never claims to. It is here so the word is "
		+ "not new when you meet it.")


## The flags as they are shown: the firmware's word, what it means in a builder's terms, the note
## about the build-side check where there is one, and the disclaimer on every single line.
static func lines() -> Array[String]:
	var out: Array[String] = []
	for entry in FLAGS:
		var line := "%s — %s" % [entry["flag"], entry["means"]]
		var checked := String(entry["checked"])
		if checked != "":
			line += " Config does check the build side of this one, above. " + CANNOT_SEE
		else:
			line += " " + CANNOT_SEE
		out.append(line)
	return out
