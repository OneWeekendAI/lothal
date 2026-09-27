class_name HarnessChecks
extends RefCounted
## What a build's current path says about itself — plans/2026-09-10-power-room-plan.md slice PW3,
## design §3.1-§3.4.
##
## The shape is `FramePlausibility`'s and `EscPlausibility`'s: pure static functions over a
## `Build`, returning `BuildWarning`s, each carrying in `values` every number it was computed from
## so a panel can present it without a second derivation that could drift from the sentence beside
## it.
##
## ---------------------------------------------------------------------------
## THE CURRENT COMES FROM WHAT THE APP ALREADY COMPUTES, AND NOT FROM HERE
## ---------------------------------------------------------------------------
##
## `draw` reads two figures back off the app and derives neither of them.
##
## **The peak** is `Build.fresh_draw_at_a` at this build's throttle ceiling — the one draw the pack
## and ESC ceilings are solved on and every Power screen prints. (Until 2026-09-27 it was a primed
## `Powertrain`'s `last_current_total_a`; that agrees to ~3e-7 A, and at a binding pack limit the
## difference printed "113 A" beside "112 A". A test still holds the two within 1e-5 A.) It does
## NOT multiply four motors by anything of its own. The reason is drift, and it is worse here than almost anywhere else in the app: a second
## current expression would agree with the first on the day it was written and would be a slowly
## widening lie afterwards, and nothing on screen would look wrong, because a voltage drop and an
## ampacity margin are both plausible at any value.
##
## **The sustained figure** is `Build.average_flight_current_a()` — the model's own answer at each
## row of `FREESTYLE_FLIGHT_PROFILE`, time-weighted, and the identical number every flight-time
## estimate in the app is computed from. Also not a second derivation: it is the existing one,
## called.
##
## WHY TWO, AND THIS IS THE FINDING THAT REWROTE THIS FILE ONCE. Ampacity and a connector's
## continuous rating are CONTINUOUS ratings, and design §3.3 asks for the build's "continuous draw"
## against them in those words. Checked against the full-throttle peak instead, the ampacity
## warning fired on EVERY BUILD IN THE CATALOG including the reference build — which is not even
## false (a 5" quad really does pull 116 A through 14 AWG on a punch-out, which is why wires get
## hot) but it is a check with no power to discriminate, and design §2.1 pictures a builder seeing
## four hairlines on a 6S build precisely because an ordinary build does not draw them.
##
## So: the ratings are checked against the sustained draw and the peak is quoted beside it, and the
## voltage drop is quoted at the peak, where the volts are actually lost and where a builder feels
## a build go soft. Every warning carries both currents in `values`, labelled, so a panel can never
## put one of them under the other one's sentence.
##
## ---------------------------------------------------------------------------
## THE SEGMENTS, AND WHAT EACH ONE CARRIES
## ---------------------------------------------------------------------------
##
## Design §3.1 fixes the split and it is deliberately coarse: **the trunk carries the whole
## aircraft's draw and each motor lead carries a quarter of it.** Four motors, four leads, one
## quarter each — which is exactly right on a hovering aircraft with four equal commands, and an
## approximation on a rolling one, where the two motors on the rising side are drawing more than
## the two on the falling side. Modelling that split would need a manoeuvre to model it during, and
## an ampacity rating is not a temperature (§3.5); a wire sized for the mean of a roll is sized for
## the roll.
##
## Within one motor lead the quarter is what each of the three phases carries, near enough. A
## brushless drive puts a similar RMS current in all three phases, so the phase conductor and the
## per-motor share are the same number to the precision anything here is quoted at, and inventing a
## sqrt(2/3) commutation factor would be three-figure confidence on top of a quarter.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE DOES NOT MODEL (design §3.5), NAMED RATHER THAN LEFT MISSING
## ---------------------------------------------------------------------------
##
##   - **Ripple current.** §3.4. There is no switching frequency published for any board in
##     escs.json and there never will be, so `capacitors.json`'s `esr_ohm` is carried, shown, and
##     read by nothing here. That is the same treatment `burst_a` gets and it is future work with a
##     field already waiting for it.
##   - **Harness thermal state.** Ampacity is a rating. A wire over its rating is warned about at
##     `LIMITING`, never `IMPOSSIBLE`: thin wire gets hot and sags, it does not refuse to conduct,
##     and Lothal warns rather than blocks. A temperature belongs to the heat overlay (track W2.7).
##   - **Connector contact resistance as a model.** It is real, small, and unpublished per product,
##     so it is folded into `connectors.json`'s own editable `contact_resistance_ohm` at a
##     class-typical default and added to the trunk's resistance — not modelled, not derived, and
##     visible as a guess in that file's every `source` string.
##   - **The BEC.** The flight controller's supply is a real load on this bus and is future work
##     (design §7). Nothing here pretends the FC draws nothing; it simply is not in the sum, and
##     `draw` reads the motor current the powertrain publishes, which is what it says.
##
## And `burst_a` is READ BY NOTHING, on the ESC's precedent and for its argument: modelling burst
## honestly needs a thermal state, and applied as though it were continuous it is a larger
## continuous rating wearing a misleading name. tests/test_harness_checks.gd asserts two builds
## differing only in connector burst rating behave identically, so the day that changes, something
## says so.

# ---------------------------------------------------------------------------
# The thresholds, and every one of them is labelled
# ---------------------------------------------------------------------------

## Where a harness voltage drop stops being a fact and starts being worth naming, as a share of the
## pack's own open-circuit voltage. Design §3.2 asks for "a share of pack voltage worth naming" and
## does not name it, so this is a WORKSHOP FIGURE and it is stated as one.
##
## 3%. On a 4S that is half a volt, which is about a hundred RPM at 1960 KV — the same order as the
## difference between two packs' internal resistances, and the point at which a builder who
## shortened their leads would be able to feel it. Below it the drop is real and is reported as a
## description; above it, something in the harness is binding the build and the builder should be
## told which segment.
##
## Design §6 counts one added constant outside the flight model (the capacitor's cell threshold).
## This is a second, and it is here because §3.2 requires a threshold to exist. It changes no
## physics: it selects a severity.
const DROP_SHARE_WORTH_NAMING := 0.03

## The capacitor rule's cell thresholds — design §6's one named constant, and it is a workshop
## convention stated as one.
##
## At and above SIX cells the missing cap is `LIMITING`: "6S needs a cap" is the one part of §3.4
## that is not in dispute among people who fly 6S, and CONTINUE-HERE.md §7 calls it "not optional
## on 6S, the most commonly forgotten essential part". From three cells up it is
## `CHARACTERISTIC` — worth saying, not worth implying a fault. At one and two cells it is silent,
## because a whoop AIO has nowhere to put a can and the people flying them do not fit one.
const CAP_RULE_LIMITING_CELLS := 6
const CAP_RULE_MENTION_CELLS := 3

## What the rule actually recommends, by cell count: `[cell ceiling, low uF, high uF, volts]`,
## ascending, last row the catch-all. EVERY NUMBER HERE IS A WORKSHOP RULE AND NONE OF IT IS
## COMPUTED — see the message `_capacitor_rule` writes, which says so on screen rather than in this
## comment where a builder will never see it. The 6S row is design §3.4's own wording verbatim.
const CAP_RULE_ROWS := [
	[5, 220.0, 470.0, 35.0],
	[99, 470.0, 1000.0, 35.0],
]

## Conductors in the trunk that the contact resistance is counted on. A plug has two mated contacts
## in the loop — positive out and negative back — and `connectors.json`'s figure is per contact.
const CONNECTOR_CONTACTS_IN_LOOP := 2

## What one motor lead carries, as a share of the aircraft's draw. Design §3.1, and see the header
## for why it is a flat quarter rather than a manoeuvre.
const MOTOR_LEAD_CURRENT_SHARE := 0.25


# ---------------------------------------------------------------------------
# The current, off the powertrain
# ---------------------------------------------------------------------------

## What this aircraft draws, and what its pack is sitting at while it draws it. See the header;
## this is the whole reason the file has a header.
##
## Keys: `peak_a` (the four motors together at the throttle ceiling on a fresh pack, `Build.fresh_draw_at_a`),
## `sustained_a` (the flight-profile average, off `Build`), `terminal_v` (what the pack's own posts
## are at under the peak), `open_circuit_v` (what they would be at with the throttle shut),
## `throttle` (the ceiling all of that is quoted at).
##
## `open_circuit_v - terminal_v` is the pack's internal-resistance sag, EXACTLY — `BatteryModel`'s
## `voltage_live` is `resting_voltage_v() - I*R` and nothing else — which is what lets §3.2's two
## terms be reported apart and still add back up to what the ESC sees.
##
## The ceiling is `max_throttle_fraction()`: the highest throttle this aircraft can actually be
## commanded to once the motors, the pack and the board have each had their say. That is the same
## ceiling peak thrust, hover and top speed are evaluated under, so the harness is checked against
## the aircraft that flies rather than against a throttle nobody can reach.
static func draw(build: Build) -> Dictionary:
	# ONE DRAW (2026-09-27): the peak is Build.fresh_draw_at_a at the ceiling — the draw the pack and
	# ESC ceilings are solved on and PowerFigures.worst_draw_a prints — not a primed Powertrain's.
	# The two agree to ~3e-7 A, but at a binding pack limit that was enough to print "At 113 A"
	# (112.5000003) beside every other screen's 112 A (112.5). The terminal voltage follows from it
	# by the pack's own rest - I*R, which is all BatteryModel.voltage_live is.
	var throttle := build.max_throttle_fraction()
	var pack := build.battery_model()
	var peak_a := build.fresh_draw_at_a(throttle)
	return {
		"peak_a": peak_a,
		"sustained_a": build.average_flight_current_a(),
		"terminal_v": pack.resting_voltage_v() - peak_a * pack.internal_r_ohm,
		"open_circuit_v": pack.resting_voltage_v(),
		"throttle": throttle,
	}


# ---------------------------------------------------------------------------
# The four checks
# ---------------------------------------------------------------------------

## Every warning this slice has to say about a build, in the order design §3 lists them.
##
## One `draw` for all four, both because it primes a powertrain and because four checks quoting
## four separately-obtained currents would be exactly the drift the header refuses.
static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if build == null or build.battery.is_empty():
		return out

	var reading := draw(build)
	out.append_array(_ampacity(build, reading))
	out.append_array(_voltage_drop(build, reading))
	out.append_array(_connector(build, reading))
	out.append_array(_capacitor_rule(build, reading))
	return out


## §3.1 — the current in each segment against that segment's rating.
##
## `LIMITING`, never `IMPOSSIBLE`, and the message names the segment AND a gauge that clears it,
## because "your motor leads are too thin" sends nobody anywhere and "18 AWG clears it" is a
## shopping list.
static func _ampacity(build: Build, reading: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var sustained_a := float(reading["sustained_a"])
	var peak_a := float(reading["peak_a"])
	for segment in segments(build):
		var rating_a := WireGauge.ampacity_a(int(segment["awg"]))
		var share := float(segment["current_share"])
		var segment_a := sustained_a * share
		if segment_a <= rating_a:
			continue
		var clears := gauge_that_clears(segment_a)
		# A draw past the thickest wire the table carries. Naming no gauge is the honest answer —
		# the fix is a second pack lead or a different aircraft, not a gauge — and inventing a row
		# for 10 AWG so the sentence could end tidily is the thing WireGauge._row refuses.
		var remedy := "no gauge in the table clears it, which means this segment wants more than one run of wire" \
			if clears == 0 else "%d AWG clears it" % clears
		out.append(BuildWarning.limiting(&"harness_ampacity",
			"%s is %d AWG, rated %.1f A, and carries %.1f A of this build's %.0f A sustained draw — %s. It sees %.1f A on a full-throttle punch, which is a rating this table has nothing to say about. Wire over its rating gets hot and sags voltage; it does not refuse to conduct." % [
				segment["label"], int(segment["awg"]), rating_a, segment_a, sustained_a, remedy,
				peak_a * share],
			{"segment": String(segment["id"]), "awg": int(segment["awg"]),
				"ampacity_a": rating_a, "segment_current_a": segment_a,
				"segment_peak_a": peak_a * share, "current_share": share,
				"sustained_a": sustained_a, "peak_a": peak_a,
				"gauge_that_clears": clears, "throttle": float(reading["throttle"])}))
	return out


## §3.2 — `I*R` down the trunk, REPORTED APART FROM THE PACK'S OWN SAG.
##
## That separation is the whole point of the check. Those two terms have been one number in this
## sim since packs had an internal resistance, and a builder could not tell how much of a
## soft-feeling 6S build was the pack and how much was thin leads. They are different purchases.
##
## ONLY THE TRUNK IS IN THIS NUMBER, and that is not an omission: the question is what the ESC's
## input pads see, and the motor leads are downstream of those pads. Their drop is a real loss in
## the motor circuit and it is not a loss of bus voltage. The motor leads are checked for ampacity
## above and drawn to scale in PW5; what they cost the ESC's input is zero, exactly.
static func _voltage_drop(build: Build, reading: Dictionary) -> Array[BuildWarning]:
	var peak_a := float(reading["peak_a"])
	var open_circuit_v := float(reading["open_circuit_v"])
	var pack_sag_v := open_circuit_v - float(reading["terminal_v"])
	var harness_r := trunk_resistance_ohm(build)
	var drop_v := peak_a * harness_r
	var esc_input_v := float(reading["terminal_v"]) - drop_v
	var share := drop_v / open_circuit_v if open_circuit_v > 0.0 else 0.0

	var values := {
		"peak_a": peak_a, "sustained_a": float(reading["sustained_a"]),
		"harness_drop_v": drop_v, "pack_sag_v": pack_sag_v,
		"open_circuit_v": open_circuit_v, "terminal_v": float(reading["terminal_v"]),
		"esc_input_v": esc_input_v, "trunk_resistance_ohm": harness_r,
		"drop_share": share, "share_worth_naming": DROP_SHARE_WORTH_NAMING,
		"throttle": float(reading["throttle"]),
	}
	var sentence := "At %.0f A the pack rests at %.2f V, sags %.2f V in its own cells and loses a further %.2f V in the main lead and its plug — %.2f V at the ESC's pads. The %.2f V is the harness's alone: shorter or thicker leads recover it, a better pack does not." % [
		peak_a, open_circuit_v, pack_sag_v, drop_v, esc_input_v, drop_v]

	var out: Array[BuildWarning] = []
	if share > DROP_SHARE_WORTH_NAMING:
		out.append(BuildWarning.limiting(&"harness_voltage_drop",
			sentence + " That is %.0f%% of pack voltage thrown away between the pack and the board, which is past the %.0f%% worth naming." % [
				share * 100.0, DROP_SHARE_WORTH_NAMING * 100.0], values))
	else:
		out.append(BuildWarning.characteristic(&"harness_voltage_drop", sentence, values))
	return out


## §3.3 — the plug, in two halves with two severities.
##
## The COMPATIBILITY half is the one `IMPOSSIBLE` this slice earns, and it is earned not because it
## is dangerous but because it is literally true and completely invisible today: a pack terminating
## in XT30 and a lead specified as XT60 is a build that cannot be plugged in. The join is
## `connectors.json`'s `catalog.family` against `batteries.json`'s `catalog.connector`, one
## spelling, asserted in both directions by tests/test_power_parts.gd.
##
## The RATING half stays `LIMITING`. An under-rated connector gets warm; it does not refuse.
##
## `burst_a` is not read. See the header.
static func _connector(build: Build, reading: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var row := connector_row(build)
	var pack_family := pack_connector_family(build)
	var sustained_a := float(reading["sustained_a"])
	var peak_a := float(reading["peak_a"])

	# No plug fitted at all. Silent rather than warned about: `Harness._connector_for_pack` returns
	# empty for a pack in a family with no row, which is a catalog gap the parts suite already
	# fails on, and planting a warning here would report the same defect twice in two vocabularies.
	if row.is_empty():
		return out

	var lead_family := String((row.get("catalog", {}) as Dictionary).get("family", ""))
	if pack_family != "" and lead_family != "" and pack_family != lead_family:
		out.append(BuildWarning.impossible(&"connector_mismatch",
			"The %s terminates in %s and this build's lead is %s. They do not mate — this aircraft cannot be plugged into this pack." % [
				build.battery.get("name", "pack"), pack_family, lead_family],
			{"pack_family": pack_family, "lead_family": lead_family,
				"connector": String(row.get("part_id", "")),
				"sustained_a": sustained_a, "peak_a": peak_a}))

	var rating_a := float((row.get("specs", {}) as Dictionary).get("continuous_a", 0.0))
	if rating_a > 0.0 and sustained_a > rating_a:
		out.append(BuildWarning.limiting(&"connector_rating",
			"The %s is rated %.1f A continuous and this build draws %.1f A sustained, peaking at %.0f A. The plug gets warm and drops voltage across its contacts; it does not refuse." % [
				row.get("name", "connector"), rating_a, sustained_a, peak_a],
			{"connector": String(row.get("part_id", "")), "rating_a": rating_a,
				"sustained_a": sustained_a, "peak_a": peak_a,
				"throttle": float(reading["throttle"])}))
	return out


## §3.4 — A RULE, SPOKEN AS A RULE. THIS DOES NOT COMPUTE ANYTHING.
##
## Sizing a low-ESR capacitor properly needs the ESC's switching frequency and the bus inductance
## of the harness. Neither is published for any board in escs.json and neither will be, so a ripple
## current derived from them would be a construction wearing a measurement's confidence — the one
## thing design §0 still refuses even after relaxing everything else about values.
##
## So the message states the rule, says WHY it is a rule, and says the field is editable. A rule
## that reads like a computation is worse than no rule.
##
## Severity scales with cell count (CAP_RULE_LIMITING_CELLS), because "6S wants a cap" is the one
## part of this nobody argues about. The message is only emitted when NO capacitor is fitted: a
## build that has one has already answered the question, and repeating the rule at it on every
## refresh would be the app talking to itself.
static func _capacitor_rule(build: Build, reading: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not build.harness.capacitor_row(build).is_empty():
		return out

	var cells := pack_cells(build)
	if cells < CAP_RULE_MENTION_CELLS:
		return out

	var rule := _cap_rule_row(cells)
	var values := {
		"cells": cells, "recommended_low_uf": float(rule[1]),
		"recommended_high_uf": float(rule[2]), "recommended_volts": float(rule[3]),
		"limiting_at_cells": CAP_RULE_LIMITING_CELLS,
		"sustained_a": float(reading["sustained_a"]), "peak_a": float(reading["peak_a"]),
	}
	var message := "A %dS build wants a low-ESR capacitor across the ESC's input pads, and none is fitted. For a board this size that is roughly %.0f-%.0f uF at %.0f V. This is a workshop rule, not a computed ripple current — Lothal has no switching frequency for this board, and no manufacturer publishes one. Adjust it if you know better; the capacitor is a field like any other." % [
		cells, float(rule[1]), float(rule[2]), float(rule[3])]

	if cells >= CAP_RULE_LIMITING_CELLS:
		out.append(BuildWarning.limiting(&"capacitor_rule", message, values))
	else:
		out.append(BuildWarning.characteristic(&"capacitor_rule", message, values))
	return out


# ---------------------------------------------------------------------------
# The topology, shared with the checks above and with PW5's drawing
# ---------------------------------------------------------------------------

## The current path as a list of segments — id, label, gauge, length, how many conductors, and what
## share of the aircraft's draw is in each one.
##
## PUBLIC, and that is deliberate: PW5 draws this harness at gauge-as-stroke-width and
## length-as-length, coloured by each segment's share of its own ampacity. A room that built its
## own segment list would be the P10d defect again — a picture and a physics kept in step by hand.
## One list, read twice.
static func segments(build: Build) -> Array:
	var harness := build.harness
	return [
		{
			"id": "main_lead", "label": "The main lead",
			"awg": int(harness.value(Harness.MAIN_LEAD_AWG, build)),
			"length_mm": float(harness.value(Harness.MAIN_LEAD_LENGTH_MM, build)),
			"conductors": Harness.MAIN_LEAD_CONDUCTORS,
			"current_share": 1.0,
		},
		{
			"id": "motor_lead", "label": "Each motor lead",
			"awg": int(harness.value(Harness.MOTOR_LEAD_AWG, build)),
			"length_mm": float(harness.value(Harness.MOTOR_LEAD_LENGTH_MM, build)),
			"conductors": Harness.MOTOR_LEAD_CONDUCTORS,
			"current_share": MOTOR_LEAD_CURRENT_SHARE,
		},
	]


## The resistance the pack's current sees on its way to the ESC's pads: down the main lead, through
## the plug, and back. Both conductors, because a circuit is a loop and a drop measured at the pads
## is the drop around the whole of it — counting one conductor would halve the answer.
##
## The contact resistance term is a labelled guess, per connector family, and every `source` string
## in connectors.json says so. It is FOLDED IN here rather than modelled (§3.5): a real contact's
## resistance depends on how many times the plug has been mated and how hard it was crimped, and
## Lothal knows neither.
static func trunk_resistance_ohm(build: Build) -> float:
	var length_m := float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build)) / 1000.0
	var wire := Harness.MAIN_LEAD_CONDUCTORS * WireGauge.resistance_ohm(
		int(build.harness.value(Harness.MAIN_LEAD_AWG, build)), length_m)
	var contact := float((connector_row(build).get("specs", {}) as Dictionary)
		.get("contact_resistance_ohm", 0.0)) * CONNECTOR_CONTACTS_IN_LOOP
	return wire + contact


## The thinnest gauge in the table that still carries `current_a`, or 0 for a draw past the
## thickest row there is. Thin-first would name 28 AWG for everything; this walks thick to thin and
## keeps the last one that clears, which is the gauge a builder would actually buy.
static func gauge_that_clears(current_a: float) -> int:
	var best := 0
	for awg in WireGauge.gauges():
		if WireGauge.ampacity_a(int(awg)) >= current_a:
			best = int(awg)
	return best


static func connector_row(build: Build) -> Dictionary:
	return build.harness.connector_row(build)


## What the PACK terminates in, off `batteries.json`'s `catalog.connector`. One spelling, one join —
## see connectors.json's `_schema` block, which spends a paragraph on why this string lives in
## `catalog` on both sides.
static func pack_connector_family(build: Build) -> String:
	return String((build.battery.get("catalog", {}) as Dictionary).get("connector", ""))


static func pack_cells(build: Build) -> int:
	return int(float((build.battery.get("specs", {}) as Dictionary).get("cells", 0)))


static func _cap_rule_row(cells: int) -> Array:
	for row in CAP_RULE_ROWS:
		if cells <= int(row[0]):
			return row
	return CAP_RULE_ROWS[CAP_RULE_ROWS.size() - 1]
