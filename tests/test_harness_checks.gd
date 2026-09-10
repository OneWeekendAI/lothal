class_name TestHarnessChecks
extends RefCounted
## The four power checks — plans/2026-09-10-power-room-plan.md slice PW3, design §3.1-§3.4.
##
## Every check below was shown to fail without its fix. The mutation named in each doc comment was
## inserted IN `src/power/harness_checks.gd`, the suite was run, the failure text was read, and the
## mutation was reverted and the revert verified before the check was kept. That is the project's
## oldest standing rule and it caught two things in this slice:
##
##   1. The ampacity check, quoted at the full-throttle peak, fired on EVERY BUILD IN THE CATALOG
##      including the reference build — a check with no power to discriminate, which is the failure
##      shape that most resembles a working feature. It is quoted at the sustained draw now, which
##      is what a continuous rating means and what design §3.3 asks for in those words.
##   2. `_test_burst_rating_gates_nothing` is not trivial and was not skipped. It is the `burst_a`
##      precedent test, and it exists so that the day someone starts reading burst as a limit is a
##      day something says so.
##
## THE FIXTURES, and why each is the one it is:
##
##   - the reference 5" is the build that must stay CLEAN on ampacity. If it warns, the check is
##     noise.
##   - `_six_s_cinelifter` is a 10" on 6S — the only build in the catalog whose sustained draw is
##     large enough that 22 AWG motor leads are genuinely under-rated. A 7" on 6S is not: it draws
##     17 A sustained, 4.3 A per lead, and 22 AWG clears that. The plan's row-one wording ("a 6S
##     build") is satisfied by both and only one of them can actually fail, which is the difference
##     between a fixture and a decoration.

## Currents here are tenths of an amp and volts are hundredths. 1e-9 is six orders under either and
## can only be met by the same arithmetic rather than by a number that is merely close.
const EPS := 1.0e-9


static func run() -> Array:
	var results: Array = []

	results.append(_test_the_reference_build_has_no_ampacity_complaint())
	results.append(_test_thin_motor_leads_on_a_six_s_build_name_the_segment_and_a_fix())
	results.append(_test_the_drop_is_reported_apart_from_the_sag_and_they_add_up())
	results.append(_test_halving_the_lead_halves_the_drop())
	results.append(_test_a_mismatched_plug_is_impossible())
	results.append(_test_an_under_rated_plug_is_limiting_and_not_impossible())
	results.append(_test_burst_rating_gates_nothing())
	results.append(_test_six_s_without_a_capacitor_warns_and_two_s_does_not())
	results.append(_test_the_capacitor_severity_scales_with_cell_count())
	results.append(_test_the_capacitor_rule_speaks_in_the_guess_voice())
	results.append(_test_every_warning_carries_the_current_it_was_computed_from())
	results.append(_test_the_current_is_the_powertrains_own_published_figure())

	return results


# ---------------------------------------------------------------------------
# §3.1 — ampacity
# ---------------------------------------------------------------------------

## THE CHECK THAT STOPS THE OTHER ONE BEING NOISE, and it is here first for that reason.
##
## An ordinary, correctly-specified 5" freestyle build must say nothing about its wire. This is the
## assertion the first draft of `harness_checks.gd` failed: quoted at the 116 A full-throttle peak
## rather than at the 16 A sustained draw, the reference build's own 14 AWG main lead and 20 AWG
## motor leads both warned, and so did every other build in the catalog.
##
## MUTATION CONFIRMED RED: quote `_ampacity` at `peak_a` instead of `sustained_a`.
static func _test_the_reference_build_has_no_ampacity_complaint() -> TestResult:
	var build := ReferenceBuild.build()
	var reading := HarnessChecks.draw(build)
	var found := _ids_of(HarnessChecks.warnings_for(build), &"harness_ampacity")

	return TestResult.new(
		"a correctly-specified 5\" build says nothing about its own wire",
		found.is_empty(),
		"%.1f A sustained / %.1f A peak through 14 AWG and 20 AWG: %d ampacity warning(s)" % [
			reading["sustained_a"], reading["peak_a"], found.size()]
	)


## The plan's row one. A segment over its rating is named, with a gauge that clears it, at LIMITING
## and never at IMPOSSIBLE — thin wire gets hot and sags, it does not refuse to conduct.
##
## MUTATION CONFIRMED RED: widen the ampacity threshold (`segment_a <= rating_a * 4.0`).
static func _test_thin_motor_leads_on_a_six_s_build_name_the_segment_and_a_fix() -> TestResult:
	var build := _six_s_cinelifter()
	build.harness.set_value(Harness.MOTOR_LEAD_AWG, 22)
	var entry := _find(HarnessChecks.warnings_for(build), &"harness_ampacity")

	var passed := entry != null
	if passed:
		passed = entry.severity == BuildWarning.Severity.LIMITING
		# The SEGMENT, by name, and not merely "a wire somewhere".
		passed = passed and String(entry.values["segment"]) == "motor_lead"
		passed = passed and int(entry.values["awg"]) == 22
		# And a gauge that CLEARS it, which is the half that turns a complaint into a shopping
		# list — asserted by re-checking the named gauge against the same rating table.
		var clears := int(entry.values["gauge_that_clears"])
		passed = passed and clears > 0
		passed = passed and WireGauge.ampacity_a(clears) >= float(entry.values["segment_current_a"])
		passed = passed and entry.message.contains("%d AWG clears it" % clears)
		# Nothing in this file is ever IMPOSSIBLE on a wire.
		for other in HarnessChecks.warnings_for(build):
			if other.id == &"harness_ampacity":
				passed = passed and other.severity != BuildWarning.Severity.IMPOSSIBLE

	return TestResult.new(
		"22 AWG motor leads on a 6S build name the segment and a gauge that clears it, at limiting",
		passed,
		"no ampacity warning at all" if entry == null else "\"%s\"" % entry.message
	)


# ---------------------------------------------------------------------------
# §3.2 — the drop, apart from the sag
# ---------------------------------------------------------------------------

## THE POINT OF THE WHOLE CHECK. Those two terms have been one number in this sim since packs had
## an internal resistance, and a builder could not tell how much of a soft-feeling 6S build was the
## pack and how much was thin leads. They are different purchases.
##
## Asserted as an IDENTITY rather than as two plausible numbers: the pack's open-circuit voltage,
## less its own sag, less the harness's drop, is what the ESC's pads see. Both terms are also
## re-derived here from `BatteryModel` and `WireGauge` independently of the warning, so a check
## that folded one into the other could not satisfy both halves.
##
## MUTATION CONFIRMED RED: fold the drop back into sag (`pack_sag_v` computed as
## `open_circuit_v - terminal_v + drop_v` and `harness_drop_v` reported as 0.0).
static func _test_the_drop_is_reported_apart_from_the_sag_and_they_add_up() -> TestResult:
	var build := ReferenceBuild.build()
	var reading := HarnessChecks.draw(build)
	var entry := _find(HarnessChecks.warnings_for(build), &"harness_voltage_drop")
	if entry == null:
		return TestResult.new(
			"the harness drop is reported apart from the pack's sag, and the two add up",
			false, "no harness_voltage_drop warning at all")

	var drop_v := float(entry.values["harness_drop_v"])
	var sag_v := float(entry.values["pack_sag_v"])
	var open_circuit_v := float(entry.values["open_circuit_v"])
	var esc_input_v := float(entry.values["esc_input_v"])

	# The identity.
	var passed: bool = absf(open_circuit_v - sag_v - drop_v - esc_input_v) < EPS
	# Both terms are real and NEITHER IS THE OTHER. A fold would leave one of them at zero.
	passed = passed and drop_v > 0.0 and sag_v > 0.0
	# The sag is the pack's own I*R, computed here from the pack rather than read back.
	var pack := build.battery_model()
	passed = passed and absf(sag_v - float(reading["peak_a"]) * pack.internal_r_ohm) < 1.0e-6
	# The drop is I*R down the trunk, computed here from WireGauge rather than read back.
	var expected_drop := float(reading["peak_a"]) * (
		Harness.MAIN_LEAD_CONDUCTORS * WireGauge.resistance_ohm(
			int(build.harness.value(Harness.MAIN_LEAD_AWG, build)),
			float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build)) / 1000.0)
		+ HarnessChecks.CONNECTOR_CONTACTS_IN_LOOP * float(
			build.harness.connector_row(build)["specs"]["contact_resistance_ohm"]))
	passed = passed and absf(drop_v - expected_drop) < EPS
	# And the sentence names both, or the separation exists only in a dictionary.
	passed = passed and entry.message.contains("in its own cells")

	return TestResult.new(
		"the harness drop is reported apart from the pack's sag, and the two add up",
		passed,
		"%.3f V open circuit - %.3f V sag - %.3f V harness = %.3f V at the pads (independently %.3f V of harness)" % [
			open_circuit_v, sag_v, drop_v, esc_input_v, expected_drop]
	)


## `R = rho*L/A` is arithmetic, not a model — so halving the length halves the drop exactly, and
## the length field a builder edits is not partly inert.
##
## MUTATION CONFIRMED RED: make length a no-op in the resistance path
## (`WireGauge.resistance_ohm(awg, 0.12)` in `trunk_resistance_ohm`).
static func _test_halving_the_lead_halves_the_drop() -> TestResult:
	var long_lead := ReferenceBuild.build()
	var full_mm := float(long_lead.harness.value(Harness.MAIN_LEAD_LENGTH_MM, long_lead))
	var short_lead := ReferenceBuild.build()
	short_lead.harness.set_value(Harness.MAIN_LEAD_LENGTH_MM, full_mm * 0.5)

	# The connector's contact resistance is in the trunk and is NOT a length, so it does not halve.
	# Taking it out of both sides is what makes this a statement about the wire — leaving it in
	# would make the ratio 0.53 and the check would have to be loosened until it proved nothing.
	var contact := HarnessChecks.CONNECTOR_CONTACTS_IN_LOOP * float(
		long_lead.harness.connector_row(long_lead)["specs"]["contact_resistance_ohm"])
	var full_r := HarnessChecks.trunk_resistance_ohm(long_lead) - contact
	var half_r := HarnessChecks.trunk_resistance_ohm(short_lead) - contact

	var passed: bool = full_r > 0.0 and absf(half_r - full_r * 0.5) < EPS
	# And it must reach the warning, not just the helper.
	var full_drop := float(_find(HarnessChecks.warnings_for(long_lead),
		&"harness_voltage_drop").values["harness_drop_v"])
	var half_drop := float(_find(HarnessChecks.warnings_for(short_lead),
		&"harness_voltage_drop").values["harness_drop_v"])
	passed = passed and half_drop < full_drop

	return TestResult.new(
		"halving the main lead halves the wire's share of the drop",
		passed,
		"%.1f mm: %.6f ohm / %.4f V   ->   %.1f mm: %.6f ohm / %.4f V" % [
			full_mm, full_r, full_drop, full_mm * 0.5, half_r, half_drop]
	)


# ---------------------------------------------------------------------------
# §3.3 — the plug
# ---------------------------------------------------------------------------

## THE ONE `IMPOSSIBLE` THIS SLICE EARNS, and it is earned by being literally true: a pack
## terminating in XT30 and a lead specified as XT60 is a build that cannot be plugged in.
##
## The join is `connectors.json`'s `catalog.family` against `batteries.json`'s `catalog.connector`,
## one spelling, which tests/test_power_parts.gd asserts in both directions. This is the check that
## would silently pass on every build forever if that join were broken, which is why PW1 wrote that
## test before this one existed.
##
## MUTATION CONFIRMED RED: compare rating only, not family (delete the `pack_family != lead_family`
## branch).
static func _test_a_mismatched_plug_is_impossible() -> TestResult:
	# An XT60 pack — the reference 4S 1500 — with an XT30 lead specified on the aircraft.
	var build := ReferenceBuild.build()
	build.harness.set_value(Harness.CONNECTOR, "connector_xt30")
	var entry := _find(HarnessChecks.warnings_for(build), &"connector_mismatch")

	var passed := entry != null
	if passed:
		passed = entry.severity == BuildWarning.Severity.IMPOSSIBLE
		passed = passed and String(entry.values["pack_family"]) == "XT60"
		passed = passed and String(entry.values["lead_family"]) == "XT30"

	# And the matching build says nothing, or the check fires on everything.
	var matched := ReferenceBuild.build()
	var silent := _find(HarnessChecks.warnings_for(matched), &"connector_mismatch") == null

	return TestResult.new(
		"an XT30 lead on an XT60 pack is impossible, and a matched plug says nothing",
		passed and silent,
		"mismatched: %s; matched build silent: %s" % [
			"absent" if entry == null else BuildWarning.severity_name(entry.severity), silent]
	)


## The rating half stays LIMITING. An under-rated connector gets warm; it does not refuse. The
## severity scale is the whole content of this check — the same build with a small plug on it is a
## build that flies, and telling a builder otherwise is the failure BuildWarning exists to prevent.
##
## MUTATION CONFIRMED RED: raise `connector_rating` to `BuildWarning.impossible`.
static func _test_an_under_rated_plug_is_limiting_and_not_impossible() -> TestResult:
	var build := ReferenceBuild.build()
	# PH2.0, 5 A continuous, on an aircraft drawing sixteen. Also a family mismatch, which fires
	# its own IMPOSSIBLE — that is expected and is why this asserts the RATING entry by id rather
	# than asserting that nothing in the list is impossible.
	build.harness.set_value(Harness.CONNECTOR, "connector_ph20")
	var entry := _find(HarnessChecks.warnings_for(build), &"connector_rating")

	var passed := entry != null
	if passed:
		passed = entry.severity == BuildWarning.Severity.LIMITING
		passed = passed and float(entry.values["sustained_a"]) > float(entry.values["rating_a"])

	# The reference build's own XT60 is ample and says nothing.
	var ample := _find(HarnessChecks.warnings_for(ReferenceBuild.build()), &"connector_rating")

	return TestResult.new(
		"an under-rated plug is limiting, never impossible, and an ample one says nothing",
		passed and ample == null,
		"absent" if entry == null else "%s: \"%s\"" % [
			BuildWarning.severity_name(entry.severity), entry.message]
	)


## THE `burst_a` PRECEDENT TEST — the plan's row five, and it is not skipped for looking trivial.
##
## `burst_a` is carried in connectors.json, shown to the builder, and read by NOTHING. The argument
## is escs.json's own, verbatim: modelling burst honestly needs a thermal state, and applied as
## though it were continuous it is a larger continuous rating wearing a misleading name. This check
## exists so that the day someone starts reading it as a limit is a day something says so.
##
## Two builds differing in NOTHING BUT the connector's burst rating, compared on the full warning
## list — every id, every severity, every message and every value. A check on the warning count
## alone would pass on a burst term that changed a severity.
##
## MUTATION CONFIRMED RED: let burst gate the rating check
## (`if rating_a > 0.0 and sustained_a > burst_a * 0.05`).
static func _test_burst_rating_gates_nothing() -> TestResult:
	var plain := ReferenceBuild.build()
	var boosted := ReferenceBuild.build()

	# The build's own catalog row, mutated in place — the ONE difference between the two aircraft.
	# Deep-duplicated first so the shared catalog dictionary is not edited under the other build.
	var row := boosted.catalog.get_part("connector_xt60").duplicate(true)
	var before := float(row["specs"]["burst_a"])
	row["specs"]["burst_a"] = before * 10.0
	boosted.catalog.by_id["connector_xt60"] = row

	var left := HarnessChecks.warnings_for(plain)
	var right := HarnessChecks.warnings_for(boosted)

	var passed: bool = left.size() == right.size()
	var differences: PackedStringArray = []
	if passed:
		for i in left.size():
			if left[i].id != right[i].id or left[i].severity != right[i].severity \
					or left[i].message != right[i].message or left[i].values != right[i].values:
				passed = false
				differences.append(String(left[i].id))

	return TestResult.new(
		"two builds differing only in connector burst rating behave identically",
		passed,
		"%.0f A burst: %d warnings; %.0f A burst: %d warnings; contents differ in %s" % [
			before, left.size(), before * 10.0, right.size(),
			"nothing" if differences.is_empty() else str(differences)]
	)


# ---------------------------------------------------------------------------
# §3.4 — the capacitor rule
# ---------------------------------------------------------------------------

## Severity scales with cell count, and below the mention threshold there is no sentence at all: a
## whoop AIO has nowhere to put a can and the people flying them do not fit one.
##
## Both halves are required. "6S warns" alone would pass on a rule that warned about everything,
## which is exactly what removing the cell-count term produces.
##
## MUTATION CONFIRMED RED: remove the cell-count term (`if false and cells <
## CAP_RULE_MENTION_CELLS` in place of the mention gate) — and, separately, replace the severity
## gate `cells >= CAP_RULE_LIMITING_CELLS` with `true`, which the 4S clause is what catches.
static func _test_six_s_without_a_capacitor_warns_and_two_s_does_not() -> TestResult:
	var six_s := _six_s_cinelifter()
	six_s.harness.set_value(Harness.CAPACITOR, "")
	var two_s := _two_s_micro()
	two_s.harness.set_value(Harness.CAPACITOR, "")
	# THE MIDDLE OF THE SCALE, and it is here because without it the SEVERITY half of the rule is
	# untested: with only a 6S and a 2S fixture, `if cells >= CAP_RULE_LIMITING_CELLS` could be
	# replaced by `if true` and nothing would notice. A 4S with no cap is worth saying and is not
	# worth implying a fault about.
	var four_s := ReferenceBuild.build()
	four_s.harness.set_value(Harness.CAPACITOR, "")

	var loud := _find(HarnessChecks.warnings_for(six_s), &"capacitor_rule")
	var quiet := _find(HarnessChecks.warnings_for(two_s), &"capacitor_rule")
	var middle := _find(HarnessChecks.warnings_for(four_s), &"capacitor_rule")

	var passed := loud != null and quiet == null and middle != null
	if passed:
		passed = loud.severity == BuildWarning.Severity.LIMITING
		passed = passed and int(loud.values["cells"]) == 6
		passed = passed and middle.severity == BuildWarning.Severity.CHARACTERISTIC
		passed = passed and int(middle.values["cells"]) == 4

	# And a build that HAS a capacitor is not lectured about one. The rule answers a question; a
	# build that has already answered it does not need to be asked again on every refresh.
	var fitted := _find(HarnessChecks.warnings_for(_six_s_cinelifter()), &"capacitor_rule")

	return TestResult.new(
		"a 6S build with no capacitor warns at limiting; a 2S build with none does not, and a fitted one is not lectured",
		passed and fitted == null,
		"6S: %s | 4S: %s | 2S: %s | 6S with a cap fitted: %s" % [
			"absent" if loud == null else BuildWarning.severity_name(loud.severity),
			"absent" if middle == null else BuildWarning.severity_name(middle.severity),
			"absent" if quiet == null else BuildWarning.severity_name(quiet.severity),
			"absent" if fitted == null else BuildWarning.severity_name(fitted.severity)]
	)


## THE RULE MUST READ AS A RULE. Design §3.4 is explicit that a rule which reads like a computation
## is worse than no rule, and this is the check that holds the wording to it: the sentence must say
## it is a workshop rule, say WHY (Lothal has no switching frequency for this board), and say the
## field is editable.
##
## Asserted on the SENTENCE and not on an id, deliberately, and it is the one test in this file
## that does that. Everything else here is machine-readable on purpose; this one is about what a
## human reads, and there is nowhere else for that claim to live.
##
## MUTATION CONFIRMED RED: shorten the message to the recommendation alone.
static func _test_the_capacitor_rule_speaks_in_the_guess_voice() -> TestResult:
	var build := _six_s_cinelifter()
	build.harness.set_value(Harness.CAPACITOR, "")
	var entry := _find(HarnessChecks.warnings_for(build), &"capacitor_rule")
	if entry == null:
		return TestResult.new("the capacitor rule speaks in the guess voice", false,
			"no capacitor_rule warning at all")

	var passed: bool = entry.message.contains("workshop rule")
	passed = passed and entry.message.contains("not a computed ripple current")
	passed = passed and entry.message.contains("switching frequency")
	passed = passed and entry.message.contains("Adjust it if you know better")
	# And the numbers it recommends are in `values`, so a panel prefills the field from the same
	# figures the sentence quotes rather than from a second copy of the rule.
	passed = passed and float(entry.values["recommended_low_uf"]) > 0.0
	passed = passed and float(entry.values["recommended_high_uf"]) \
		> float(entry.values["recommended_low_uf"])
	passed = passed and entry.message.contains("%.0f uF" % float(entry.values["recommended_high_uf"]))

	return TestResult.new(
		"the capacitor rule says it is a rule, says why, and says the field is editable",
		passed,
		"\"%s\"" % entry.message
	)


## The severity gate on its own, walked across the whole cell range the catalog stocks: silent,
## then described, then limiting, and NEVER the other way round. The check above pins three points;
## this one pins the shape, so a threshold moved to a number that happens to keep those three
## points right still has to keep the ordering right everywhere else.
##
## MUTATION CONFIRMED RED: `if cells >= CAP_RULE_LIMITING_CELLS` replaced with `if true`.
static func _test_the_capacitor_severity_scales_with_cell_count() -> TestResult:
	var seen: Array = []
	var passed := true
	var previous := 3   # one past the least severe ordinal, so the first reading cannot regress
	for pack in ["battery_1s_300", "battery_2s_450", "battery_3s_650", "battery_4s_1500",
			"battery_5s_1200", "battery_6s_1300"]:
		var build := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
			ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, pack,
			ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, Build.no_components())
		build.harness.set_value(Harness.CAPACITOR, "")
		var entry := _find(HarnessChecks.warnings_for(build), &"capacitor_rule")
		# Absent is the least severe reading there is, and it sorts one past CHARACTERISTIC.
		var ordinal: int = 3 if entry == null else int(entry.severity)
		seen.append("%dS:%s" % [HarnessChecks.pack_cells(build),
			"silent" if entry == null else BuildWarning.severity_name(entry.severity)])
		# Severity is an enum with IMPOSSIBLE at zero, so more cells must never sort HIGHER.
		passed = passed and ordinal <= previous
		previous = ordinal
	# And it must actually move, or a rule that said the same thing at every cell count passes.
	passed = passed and previous == int(BuildWarning.Severity.LIMITING)

	return TestResult.new(
		"the capacitor rule's severity scales with cell count and never runs backwards",
		passed,
		" ".join(PackedStringArray(seen))
	)


# ---------------------------------------------------------------------------
# The values contract, and where the current comes from
# ---------------------------------------------------------------------------

## Design's own convention, and the plan's row seven: every warning carries in `values` every
## number it was computed from, so a panel can present it without a second derivation that could
## drift from the sentence beside it. The current is the one that matters — it is the input all
## four checks share and the one a panel is most likely to want to re-quote.
##
## Run across a build that fires ALL FOUR, so this is a statement about every warning the file can
## produce rather than about the two an ordinary build happens to raise.
##
## MUTATION CONFIRMED RED: blank one `values` entry (`"sustained_a": 0.0` in `_connector`'s
## mismatch warning).
static func _test_every_warning_carries_the_current_it_was_computed_from() -> TestResult:
	var build := _six_s_cinelifter()
	build.harness.set_value(Harness.MOTOR_LEAD_AWG, 22)
	build.harness.set_value(Harness.CONNECTOR, "connector_xt30")
	build.harness.set_value(Harness.CAPACITOR, "")
	var reading := HarnessChecks.draw(build)
	var entries := HarnessChecks.warnings_for(build)

	# All four checks must actually be represented, or "every warning carries it" is a claim about
	# a short list. This is the clause that stops the check passing vacuously.
	var ids: Array = []
	for entry in entries:
		if not ids.has(String(entry.id)):
			ids.append(String(entry.id))
	var passed: bool = ids.has("harness_ampacity") and ids.has("harness_voltage_drop") \
		and ids.has("connector_mismatch") and ids.has("capacitor_rule")

	var offenders: PackedStringArray = []
	for entry in entries:
		var has_current: bool = entry.values.has("sustained_a") and entry.values.has("peak_a")
		if has_current:
			has_current = absf(float(entry.values["sustained_a"])
				- float(reading["sustained_a"])) < EPS
			has_current = has_current and absf(float(entry.values["peak_a"])
				- float(reading["peak_a"])) < EPS
		if not has_current:
			offenders.append(String(entry.id))
	passed = passed and offenders.is_empty()

	return TestResult.new(
		"every warning carries the currents it was computed from, matching the reading exactly",
		passed,
		"%d warnings across %s; missing or wrong: %s" % [entries.size(), str(ids),
			"none" if offenders.is_empty() else str(offenders)]
	)


## THE INSTRUCTION THIS FILE WAS WRITTEN UNDER: the current is the powertrain's own published
## figure, not a second calculation.
##
## Asserted by priming a powertrain here, independently of `HarnessChecks`, and requiring the
## number in the warning to be that figure TO THE BIT. An approximate band would pass on a
## re-derivation that happened to agree today, which is precisely the drift this is guarding.
##
## MUTATION CONFIRMED RED: derive the peak in `draw` as `4.0 * build.current_at_rpm(
## build.rpm_at_throttle(throttle))` instead of reading `last_current_total_a`.
static func _test_the_current_is_the_powertrains_own_published_figure() -> TestResult:
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	core.prime_motors(build.max_throttle_fraction())
	var published: float = core.powertrain.last_current_total_a
	var published_v: float = core.powertrain.last_voltage_v

	var reading := HarnessChecks.draw(build)
	var passed: bool = reading["peak_a"] == published
	passed = passed and reading["terminal_v"] == published_v
	# And the sustained figure is Build's own flight-profile average, likewise not re-derived.
	passed = passed and reading["sustained_a"] == build.average_flight_current_a()

	return TestResult.new(
		"the checks read the powertrain's published current rather than deriving one",
		passed,
		"published %.6f A / %.6f V vs read %.6f A / %.6f V" % [
			published, published_v, reading["peak_a"], reading["terminal_v"]]
	)


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

## A 10" long-range on 6S — 33 A sustained, which is the only build in the shipped catalog that
## draws enough for 22 AWG motor leads to be genuinely under-rated. See the header.
static func _six_s_cinelifter() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), "frame_10in_long_range",
		"motor_2808_1300kv", "prop_10x5x2", "battery_6s_1300", "esc_4in1_80a_30x30",
		Build.DEFAULT_FC_ID, Build.no_components())


static func _two_s_micro() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), "frame_3in_toothpick",
		"motor_1103_8000kv", "prop_3x3x3", "battery_2s_450", Build.DEFAULT_ESC_ID,
		Build.DEFAULT_FC_ID, Build.no_components())


static func _find(entries: Array[BuildWarning], id: StringName) -> BuildWarning:
	for entry in entries:
		if entry.id == id:
			return entry
	return null


static func _ids_of(entries: Array[BuildWarning], id: StringName) -> Array:
	var out: Array = []
	for entry in entries:
		if entry.id == id:
			out.append(entry)
	return out
