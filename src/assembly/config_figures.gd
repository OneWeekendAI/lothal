class_name ConfigFigures
extends RefCounted
## The figures the Config rows, their page numbers and their drawings all read (lab dock design §3):
## one computation per figure, so the list, the page and the drawing cannot disagree. The
## `ControlFigures` / `VideoFigures` pattern, for Config.
##
## Nothing here is a second model. The spin map is `MotorLayout.spin_map` (the mixer reads it) and
## its check is the one `ConfigPlausibility` warns from; the port demand is `ControlFigures`'
## (ControlPlausibility's list) and the supply `PortBudget`'s with its provenance; the failsafe and
## the rates are `FailsafeSettings` / `RateSettings`; the sim's rate is `RateModeController`'s.
##
## WHAT IS DELIBERATELY NOT HERE:
##   - a UART NUMBER for any part. Lothal counts the ports a build wants; which UART each lands on
##     is the builder's wiring, and naming "UART2" would be invented. The drawing fills slots in the
##     demand list's order and says so.
##   - an expo curve. Expo is carried for the radio and the sim does not fly it (RateSettings);
##     the curve's shape depends on the radio's rates type, which Lothal does not know.
##   - per-axis rates. The sim flies one full-stick rate on roll, pitch and yaw, and the config
##     stores one; three numbers would be one number said three times as if they could differ.

## What a serial part is called in a row, where the catalogue name will not fit.
const SHORT_NAMES := {"receiver": "RX", "gps": "GPS", "vtx": "VTX", "esc": "ESC telemetry"}

## Provenance words for the Sheet's four settings.
const YOURS := "yours"
const DEFAULT := "default"
const GUESS := "class guess"
const UNPUBLISHED := "unpublished"


# ---------------------------------------------------------------------------
# Motor direction
# ---------------------------------------------------------------------------

## The map the mixer flies and its check: `{spin: {M1..M4: ±1}, net, broken: ["M1/M4", …]}`.
## `net` is the sum of the four reaction-torque signs, in one motor's worth: zero cancels.
## `ConfigPlausibility` warns from THIS, so the ✓ and the warning are one test.
static func spin_check(build: Build) -> Dictionary:
	var spin := MotorLayout.spin_map(build.config)
	var net := 0.0
	for name in MotorLayout.MOTOR_NAMES:
		net += float(spin[name])
	var broken: Array[String] = []
	for pair in ConfigPlausibility.DIAGONALS:
		if float(spin[pair[0]]) != float(spin[pair[1]]):
			broken.append("%s/%s" % [pair[0], pair[1]])
	return {"spin": spin, "net": net, "broken": broken}


static func spin_flies(build: Build) -> bool:
	var check := spin_check(build)
	return float(check["net"]) == 0.0 and (check["broken"] as Array).is_empty()


## "props out", "props in", or "custom" for a per-motor map — the Motor direction row's line 2.
static func spin_choice(build: Build) -> String:
	var spin: Variant = build.config.get("motor_spin", "props_out")
	return "custom" if spin is Dictionary else str(spin).replace("_", " ")


## Line 3 when the map flies; empty otherwise (the impossible warning takes the line).
static func spin_text(build: Build) -> String:
	return "✓ yaw torques cancel" if spin_flies(build) else ""


# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------

## "RX · VTX" — the parts that want a serial port, in ControlPlausibility's order.
static func ports_choice(build: Build) -> String:
	var names: Array[String] = []
	for part in ControlFigures.serial_parts(build):
		names.append(str(SHORT_NAMES.get(str(part["category"]), part["name"])))
	return " · ".join(names) if not names.is_empty() else "nothing needs a UART"


## True when the demand exceeds even the top of the board's figure. False when no figure is known:
## a count nobody published cannot be exceeded.
static func ports_over(build: Build) -> bool:
	var supply := PortBudget.for_build(build)
	if String(supply["provenance"]) == PortBudget.UNPUBLISHED:
		return false
	return ControlFigures.serial_demand(build) > int(supply["high"])


## Line 3: "✓ 2 of ~4–5 UARTs used" when it fits on any figure; "5 of ~4–5 UARTs · check board"
## when the range straddles it; "3 want a UART · count unpublished"; empty when over (the warning).
static func ports_text(build: Build) -> String:
	var demand := ControlFigures.serial_demand(build)
	var figure := ControlFigures.ports_figure(build)
	if figure == "":
		return "%d want a UART · count unpublished" % demand
	if ports_over(build):
		return ""
	if demand <= int(PortBudget.for_build(build)["low"]):
		return "✓ %d of %s UARTs used" % [demand, figure]
	return "%d of %s UARTs · check board" % [demand, figure]


# ---------------------------------------------------------------------------
# Failsafe
# ---------------------------------------------------------------------------

const STAGE2_SHORT := {FailsafeSettings.DROP: "drop", FailsafeSettings.LAND: "land",
	FailsafeSettings.GPS_RESCUE: "GPS rescue"}


## "stage 2 drop · BF default" / "stage 2 land · yours".
static func failsafe_choice(build: Build) -> String:
	var whose := "BF default" if FailsafeSettings.stage2_provenance(build.config) \
		== FailsafeSettings.BETAFLIGHT_DEFAULT else YOURS
	return "stage 2 %s · %s" % [STAGE2_SHORT[FailsafeSettings.stage2(build.config)], whose]


## Whether the build carries what its stage 2 needs — GPS rescue needs a GPS; drop and land need
## nothing fitted. The same test `ConfigPlausibility._gps_rescue_without_gps` makes.
static func failsafe_can_run(build: Build) -> bool:
	return FailsafeSettings.stage2(build.config) != FailsafeSettings.GPS_RESCUE \
		or build.components.has("gps")


static func failsafe_text(build: Build) -> String:
	return "✓ this build can carry it out" if failsafe_can_run(build) else ""


## The ESC's published protocol, "" when unpublished or no ESC.
static func esc_protocol(build: Build) -> String:
	return str((build.esc.get("catalog", {}) as Dictionary).get("protocol", ""))


# ---------------------------------------------------------------------------
# Rates
# ---------------------------------------------------------------------------

static func sim_rate_deg_s() -> float:
	return RateSettings.sim_max_rate_deg_s()


static func set_rate_deg_s(build: Build) -> float:
	return RateSettings.intended_max_rate_deg_s(build.config)


## "800°/s each axis", with the expo when one is set.
static func rates_choice(build: Build) -> String:
	var text := "%d°/s each axis" % roundi(set_rate_deg_s(build))
	var expo := RateSettings.expo(build.config)
	return text + (" · expo %.2f" % expo if expo > 0.0 else "")


static func rates_text(build: Build) -> String:
	var sim := sim_rate_deg_s()
	if absf(sim - set_rate_deg_s(build)) < RateSettings.SAME_RATE_EPSILON_DEG_S:
		return "✓ same as the sim flies"
	return "sim flies %d°/s" % roundi(sim)


# ---------------------------------------------------------------------------
# Sheet
# ---------------------------------------------------------------------------

## The four settings the sheet states, each `{name, value, whose}` — `whose` is YOURS when the
## builder set it, else where the sheet's figure comes from (DEFAULT, GUESS, UNPUBLISHED).
static func sheet_settings(build: Build) -> Array:
	var spin_yours := build.config.has("motor_spin")
	var supply := PortBudget.for_build(build)
	var provenance := String(supply["provenance"])
	var ports_whose: String = {PortBudget.TYPED: YOURS, PortBudget.CLASS_TYPICAL: GUESS}.get(
		provenance, UNPUBLISHED)
	var figure := ControlFigures.ports_figure(build)
	return [
		{"name": "Motor direction", "value": spin_choice(build),
			"whose": YOURS if spin_yours else DEFAULT},
		{"name": "Board UARTs", "value": figure if figure != "" else "—", "whose": ports_whose},
		{"name": "Failsafe stage 2", "value": STAGE2_SHORT[FailsafeSettings.stage2(build.config)],
			"whose": YOURS if FailsafeSettings.stage2_provenance(build.config)
				== FailsafeSettings.CHOSEN else DEFAULT},
		{"name": "Max rate", "value": "%d°/s" % roundi(set_rate_deg_s(build)),
			"whose": YOURS if RateSettings.max_rate_provenance(build.config)
				== RateSettings.CHOSEN else DEFAULT},
	]


static func sheet_yours(build: Build) -> int:
	var yours := 0
	for setting in sheet_settings(build):
		if str(setting["whose"]) == YOURS:
			yours += 1
	return yours


static func sheet_choice(build: Build) -> String:
	return "%d of %d settings yours" % [sheet_yours(build), sheet_settings(build).size()]


static func sheet_text(build: Build) -> String:
	return "✓ ready to export" if sheet_yours(build) == sheet_settings(build).size() else ""


## How many warnings the sheet's "What is wrong" section lists — `ConfigSheet._warnings` lists
## `build.warnings()` whole.
static func sheet_flag_count(build: Build) -> int:
	return build.warnings().size()


# ---------------------------------------------------------------------------
# The two warnings only this section raises
# ---------------------------------------------------------------------------

## Demand over the board's top figure (Ports), and settings the sheet quotes that the builder has
## not set (Sheet). Neither is in `Build.warnings()`: the first is ControlPlausibility's
## characteristic row read against its own verdict, the second is about the sheet, not the aircraft.
static func warnings(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if ports_over(build):
		var supply := PortBudget.for_build(build)
		var demand := ControlFigures.serial_demand(build)
		var names: Array[String] = []
		for part in ControlFigures.serial_parts(build):
			names.append(str(part["name"]))
		out.append(BuildWarning.limiting(&"ports_over_budget",
			"%d fitted parts want a serial port (%s). %s %s" % [demand, ", ".join(names),
				String(supply["sentence"]), PortBudget.verdict(demand, supply)],
			{"demand": demand, "figure": ControlFigures.ports_figure(build)}))
	var missing: Array[String] = []
	for setting in sheet_settings(build):
		if str(setting["whose"]) != YOURS:
			missing.append("%s (%s, %s)" % [str(setting["name"]).to_lower(), str(setting["value"]),
				str(setting["whose"])])
	if not missing.is_empty():
		out.append(BuildWarning.limiting(&"config_sheet_defaults",
			("The sheet quotes %d %s you have not set: %s. Each is labelled with where it came "
			+ "from, so the sheet is not wrong — but it is not yet your aircraft. Set them on their "
			+ "pages.") % [missing.size(), "setting" if missing.size() == 1 else "settings",
				"; ".join(missing)],
			{"missing": missing.size()}))
	return out


# ---------------------------------------------------------------------------
# The Ports drawing's slots
# ---------------------------------------------------------------------------

## The UART map the Ports page draws: `{known, slots: [{part, maybe}], over: [part]}`. One slot per
## port at the top of the board's figure; a slot past the bottom of a class-guess range is `maybe`.
## The parts that want a UART fill the slots in ControlPlausibility's order — an ORDER, not a UART
## number: which UART each lands on is the builder's wiring. `over` is what no slot holds. With no
## published count, `known` is false, there are no slots, and every part is listed without a verdict.
static func uart_slots(build: Build) -> Dictionary:
	var supply := PortBudget.for_build(build)
	var known := String(supply["provenance"]) != PortBudget.UNPUBLISHED
	var parts: Array[String] = []
	for part in ControlFigures.serial_parts(build):
		parts.append(str(SHORT_NAMES.get(str(part["category"]), part["name"])))
	var slots: Array = []
	var over: Array[String] = []
	if not known:
		return {"known": false, "slots": slots, "over": over, "parts": parts}
	for i in int(supply["high"]):
		slots.append({"part": parts[i] if i < parts.size() else "", "maybe": i >= int(supply["low"])})
	for i in range(int(supply["high"]), parts.size()):
		over.append(parts[i])
	return {"known": true, "slots": slots, "over": over, "parts": parts}
