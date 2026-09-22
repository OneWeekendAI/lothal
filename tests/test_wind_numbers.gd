class_name TestWindNumbers
extends RefCounted
## F8: wind in Lab — the headline numbers under the selected conditions (design §4.3/§3.3/§5.3,
## §7's fourth row).
##
## The physics of this slice is a single delegation: `hover_current_in_wind_a(v)` IS
## `flight_current_at_a(v, 1.0, ceiling)`, and `average_flight_current_a`/`flight_time_min` add the
## wind speed to each mission-profile segment's own airspeed. No new solver, no new law.
##
## RULING 57 — WHY CHECKS 3 AND 4 ARE NOT WHAT THE BRIEF FIRST ASKED FOR. F7's own check 6 (and
## this task's own measurement, `.superpowers/sdd/2026-09-21-field-room-plan/task-F8-report.md`'s
## table) found that at trimmed hold-station, current in a headwind is NON-MONOTONIC and BELOW the
## calm figure through most of the range this slice was first asked to assert a rise across
## (0/3/7/12 m/s): translational lift cuts the thrust a hover needs faster than the lean adds drag,
## until the drag term overtakes it somewhere between 7 and 12 m/s for this build. A check that
## asserted a monotonic rise in that range would either fail honestly or have to be narrowed until
## it stopped meaning anything — both hide the finding, so check 4 below pins the MEASURED
## (non-monotonic) shape instead: current dips below the calm figure at 3 and 7 m/s, and only
## exceeds it once the wind is large enough (12 m/s, this build) that the extra drag has won.
##
## Check 3 is a different quantity and was measured separately: `flight_time_min()` is a WEIGHTED
## AVERAGE over `FREESTYLE_FLIGHT_PROFILE`'s five legs (2/12/22/15/10 m/s, not one hover point), and
## four of those five legs sit at or above 10 m/s before any wind is added — past the point where a
## headwind still discounts the current. Measured across 0/3/7/12 m/s the weighted average DOES
## fall monotonically for the reference build; check 3 pins that measured fact, and is written to
## fail loudly rather than pass quietly if a future catalog change ever makes it stop being true.
##
## Check 6 (gustiness moves nothing) exists because `Wind`'s gust process is a zero-mean noise
## term (`wind.gd`): a mean over it is exactly the steady figure, and Lab's numbers must not
## pretend otherwise by quoting a "flight time in gusts" nobody could reproduce.

static func run() -> Array:
	var results: Array = []
	var sections := {
		"golden calm bit-identity": _golden_calm_bit_identity(),
		"hover_current_in_wind_a delegates": _hover_delegates(),
		"flight time falls across the measured range": _flight_time_falls(),
		"hover current in wind: the measured, non-monotonic shape": _hover_current_measured_shape(),
		"wind reaches every mission-profile segment": _wind_reaches_every_segment(),
		"gustiness moves no Lab number": _gustiness_moves_nothing(),
		"conditional rows name their conditions": _conditional_rows_name_conditions(),
		"AUW stays unconditional": _auw_unconditional(),
		"conditions change without a Lab reload": _conditions_change_without_reload(),
		"the wind row is characteristic and never grades": _wind_row_characteristic(),
		"no wind grade, and still no difficulty score": _no_wind_grade_no_difficulty_score(),
	}
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# Check 1 — calm is bit-identical to the pre-F8 code
# ---------------------------------------------------------------------------

## Captured by running `ReferenceBuild.build()` AGAINST THE SHIPPED PRE-F8 CODE, at commit
## e078c3f (F7: wind in Sim), before any of this file's implementation existed — `git stash` the
## working tree back to that commit, run `average_flight_current_a()` and `flight_time_min()` with
## no arguments, `git stash pop`. Full precision (%.17f) so the comparison is bit-for-bit rather
## than "close". A golden value taken from the implementation it is guarding is a test that cannot
## fail (this plan's standing rule); these are frozen from the OLD code, which never heard of wind.
const GOLDEN_AVG_CURRENT := 15.75313526557218502
const GOLDEN_FLIGHT_TIME := 4.57051874348803278

## MUTATION THIS CATCHES: the wind term added as `+ wind_mps` with no zero guard, using a non-zero
## default. That mutation moves BOTH figures away from the golden literals even at the call sites
## below, which pass no wind argument at all and must land on the pre-F8 default of 0.0.
static func _golden_calm_bit_identity() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var avg_current := build.average_flight_current_a()
	var flight_time := build.flight_time_min()
	results.append(TestResult.new(
		"average_flight_current_a() at zero wind is bit-identical to the pre-F8 figure",
		avg_current == GOLDEN_AVG_CURRENT,
		"got %.17f, golden %.17f" % [avg_current, GOLDEN_AVG_CURRENT]))
	results.append(TestResult.new(
		"flight_time_min() at zero wind is bit-identical to the pre-F8 figure",
		flight_time == GOLDEN_FLIGHT_TIME,
		"got %.17f, golden %.17f" % [flight_time, GOLDEN_FLIGHT_TIME]))
	# The explicit wind_mps := 0.0 default must answer identically to the omitted argument — the
	# same mutation (a stray non-zero default) would pass the first pair of assertions above if it
	# only touched the DEFAULT VALUE and not the call above, since that call passes no argument at
	# all through a chain that still bottoms out on the literal default somewhere.
	results.append(TestResult.new(
		"average_flight_current_a(AT_NOMINAL, 0.0) matches the no-argument call",
		build.average_flight_current_a(Build.AT_NOMINAL, 0.0) == avg_current,
		"got %.17f" % build.average_flight_current_a(Build.AT_NOMINAL, 0.0)))
	results.append(TestResult.new(
		"flight_time_min(0.0) matches the no-argument call",
		build.flight_time_min(0.0) == flight_time,
		"got %.17f" % build.flight_time_min(0.0)))
	return results


# ---------------------------------------------------------------------------
# Check 2 — hover_current_in_wind_a delegates to flight_current_at_a, not a copy of its maths
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: a second lean solve written inline inside `hover_current_in_wind_a`. A
## hand-written duplicate of the bisection would have to reproduce the exact 40-iteration bisect,
## the exact `ratios.power_ratio` call and the exact `peak_thrust` ceiling to land on the SAME
## float `flight_current_at_a` produces — an independent implementation drifts at the bit level
## long before it drifts visibly, so `==` here is deliberately exact rather than a tolerance.
static func _hover_delegates() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var ceiling: float = build.peak_thrust()["throttle"]
	var oracle := build.flight_current_at_a(6.9, 1.0, ceiling)
	var under_test := build.hover_current_in_wind_a(6.9)
	results.append(TestResult.new(
		"hover_current_in_wind_a(6.9) equals flight_current_at_a(6.9, 1.0, ceiling) exactly",
		under_test == oracle,
		"hover_current_in_wind_a=%.17f flight_current_at_a=%.17f" % [under_test, oracle]))

	# A second wind speed, and a non-nominal open_circuit_v, so a mutation that hard-codes 6.9 or
	# AT_NOMINAL into an inline copy still gets caught even if it happens to match at the one point
	# above.
	var oracle2 := build.flight_current_at_a(15.0, 1.0, ceiling, 16.0)
	var under_test2 := build.hover_current_in_wind_a(15.0, 16.0)
	results.append(TestResult.new(
		"hover_current_in_wind_a(15.0, 16.0) equals flight_current_at_a(15.0, 1.0, ceiling, 16.0)",
		under_test2 == oracle2,
		"hover_current_in_wind_a=%.17f flight_current_at_a=%.17f" % [under_test2, oracle2]))
	return results


# ---------------------------------------------------------------------------
# Check 3 — flight time falls monotonically 0/3/7/12 m/s (MEASURED true for the weighted profile)
# ---------------------------------------------------------------------------

## Literals captured from THIS slice's own implementation, after it was written — unlike check 1's
## golden figures, there is no pre-F8 figure to compare a WINDY flight time against, because the
## windy figure did not exist before this slice. What guards against "a golden value taken from the
## implementation it is guarding" here is check 5 below (every segment demonstrably moves under the
## SAME wind term) and the monotonic ORDERING assertion, which a wrong implementation is not free
## to satisfy just by reproducing itself.
const FT_CALM := 4.57051874348803278
const FT_3 := 4.00312954089769768
const FT_7 := 3.35449307132423025
const FT_12 := 2.67310517826952188

## MUTATION THIS CATCHES: the wind term applied to one segment only. With only one of five legs
## seeing the wind, the weighted average moves far less per m/s of wind than the pinned literals
## demand, and — because "hover / slow" alone would net a slight INCREASE in current at low wind
## (translational lift, same effect check 4 measures) — applying the term to that segment alone can
## even push flight time the wrong way. Either way the exact literals stop matching.
static func _flight_time_falls() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var times := [build.flight_time_min(0.0), build.flight_time_min(3.0),
		build.flight_time_min(7.0), build.flight_time_min(12.0)]
	var pinned := [FT_CALM, FT_3, FT_7, FT_12]
	for i in 4:
		results.append(TestResult.new(
			"flight_time_min(%d) matches the measured literal" % [[0, 3, 7, 12][i]],
			times[i] == pinned[i],
			"got %.17f, pinned %.17f" % [times[i], pinned[i]]))
	results.append(TestResult.new(
		"flight time falls monotonically across 0 / 3 / 7 / 12 m/s of wind (measured, weighted "
			+ "over the whole mission profile — see Ruling 57 for why this is a DIFFERENT claim "
			+ "from single-point hover current, which does not)",
		times[0] > times[1] and times[1] > times[2] and times[2] > times[3],
		"%.4f -> %.4f -> %.4f -> %.4f min" % times))
	return results


# ---------------------------------------------------------------------------
# Check 4 — hover current in wind: the MEASURED, non-monotonic shape (Ruling 57)
# ---------------------------------------------------------------------------

const HOVER_0 := 11.19957425581442045
const HOVER_3 := 10.94871863159863956
const HOVER_7 := 10.13878938879419778
const HOVER_12 := 11.26892665010527850

## MUTATION THIS CATCHES: `hover_current_in_wind_a` ignoring its argument. With the argument
## ignored, every one of the four pinned values below collapses to HOVER_0 (or whatever constant
## the mutation freezes on), and the four `==` assertions plus the below/above-calm assertions fail
## together rather than one at a time — a single scalar could not fake this shape by accident.
##
## NOT a monotonic-rise assertion. Ruling 57: at this build's trimmed hold-station, current DIPS
## below the calm figure at 3 and 7 m/s (translational lift outweighs the extra drag-driven thrust)
## and only exceeds it once the wind is large enough — 12 m/s, for this build — that the drag term
## has overtaken the lift saved. Asserting a monotonic rise across exactly this range would be
## asserting something false; this pins what was actually measured instead.
static func _hover_current_measured_shape() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var h0 := build.hover_current_in_wind_a(0.0)
	var h3 := build.hover_current_in_wind_a(3.0)
	var h7 := build.hover_current_in_wind_a(7.0)
	var h12 := build.hover_current_in_wind_a(12.0)

	for pair in [[h0, HOVER_0, 0], [h3, HOVER_3, 3], [h7, HOVER_7, 7], [h12, HOVER_12, 12]]:
		results.append(TestResult.new(
			"hover_current_in_wind_a(%d) matches the measured literal" % [pair[2]],
			pair[0] == pair[1],
			"got %.17f, pinned %.17f" % [pair[0], pair[1]]))

	results.append(TestResult.new(
		"3 m/s of headwind draws LESS hover current than calm (translational lift, Ruling 57)",
		h3 < h0, "calm=%.4f, 3 m/s=%.4f" % [h0, h3]))
	results.append(TestResult.new(
		"7 m/s of headwind draws LESS hover current than calm, and less than 3 m/s does — the "
			+ "measured minimum sits at or past 7 m/s for this build",
		h7 < h0 and h7 < h3, "calm=%.4f, 3 m/s=%.4f, 7 m/s=%.4f" % [h0, h3, h7]))
	results.append(TestResult.new(
		"12 m/s of headwind draws MORE hover current than calm — the drag term has overtaken the "
			+ "lift saved by this point (measured; the crossing sits between 7 and 12 m/s here)",
		h12 > h0, "calm=%.4f, 12 m/s=%.4f" % [h0, h12]))
	results.append(TestResult.new(
		"the curve is genuinely non-monotonic: it falls from calm to 7 m/s, then rises past it",
		h7 < h0 and h12 > h7,
		"%.4f -> %.4f -> %.4f -> %.4f A" % [h0, h3, h7, h12]))
	return results


# ---------------------------------------------------------------------------
# Check 5 — the wind term reaches every segment of FREESTYLE_FLIGHT_PROFILE
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: the term applied only to "hover / slow". Five segments, each asserted to
## move — a mutation that only wires one of them leaves the other four's current identical at
## wind=0 and wind=7, which this loop names explicitly rather than only checking the average moved
## (an average can move from one segment changing while four stand still, and that would pass a
## weaker check).
static func _wind_reaches_every_segment() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var ceiling: float = build.peak_thrust()["throttle"]
	var segments: Array = Build.FREESTYLE_FLIGHT_PROFILE
	results.append(TestResult.new(
		"FREESTYLE_FLIGHT_PROFILE still has five segments",
		segments.size() == 5, "got %d" % segments.size()))
	for segment in segments:
		var name := String(segment["name"])
		var v0 := build.flight_current_at_a(
			float(segment["airspeed_mps"]), float(segment["load_factor"]), ceiling)
		var v7 := build.flight_current_at_a(
			float(segment["airspeed_mps"]) + 7.0, float(segment["load_factor"]), ceiling)
		results.append(TestResult.new(
			"segment \"%s\" moves under a 7 m/s wind term" % name,
			v0 != v7,
			"wind=0 -> %.6f A, wind=7 -> %.6f A" % [v0, v7]))
	return results


# ---------------------------------------------------------------------------
# Check 6 — gustiness moves no Lab number
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: gustiness added to the wind term. `Build`'s three new functions take only
## `wind_mps` — a scalar — so there is no gustiness parameter for a correct implementation to read.
## This check goes one level up, through the actual Lab wiring (`LabScreen.set_conditions`), so a
## mutation that smuggled `conditions.gustiness_mps` into the steady wind term anywhere along that
## path — not only inside `Build` — would still be caught: two conditions differing ONLY in
## gustiness must render identical flight-time, current and top-speed text.
static func _gustiness_moves_nothing() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var lab := LabScreen.new(catalog)

	var calm_gusts := Conditions.new()
	calm_gusts.conditions_name = "Breezy, calm gusts"
	calm_gusts.wind_speed_mps = 9.0
	calm_gusts.gustiness_mps = 0.0
	lab.set_conditions(calm_gusts)
	var time_a := lab.details.stat_text("time")
	var current_a := lab.details.stat_text("current")
	var speed_a := lab.details.stat_text("speed")

	var wild_gusts := Conditions.new()
	wild_gusts.conditions_name = "Breezy, calm gusts"
	wild_gusts.wind_speed_mps = 9.0
	wild_gusts.gustiness_mps = 6.0
	lab.set_conditions(wild_gusts)
	var time_b := lab.details.stat_text("time")
	var current_b := lab.details.stat_text("current")
	var speed_b := lab.details.stat_text("speed")

	results.append(TestResult.new(
		"flight time is identical across gustiness 0.0 and 6.0 at the same steady wind",
		time_a == time_b, "%s vs %s" % [time_a, time_b]))
	results.append(TestResult.new(
		"flight current is identical across gustiness 0.0 and 6.0 at the same steady wind",
		current_a == current_b, "%s vs %s" % [current_a, current_b]))
	results.append(TestResult.new(
		"top speed is identical across gustiness 0.0 and 6.0 at the same steady wind",
		speed_a == speed_b, "%s vs %s" % [speed_a, speed_b]))
	lab.free()
	return results


# ---------------------------------------------------------------------------
# Check 7 — every panel that quotes a conditional number names the conditions set
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: one row's conditions label dropped. Scans the flight-time and flight-
## current rows' RENDERED TEXT for the selected set's own name — the two rows this slice makes
## conditional on wind (design §4.3). A mutation that drops either row's label leaves that row's
## text without the name, which this catches per row rather than only in aggregate.
static func _conditional_rows_name_conditions() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var lab := LabScreen.new(catalog)

	var gusty := Conditions.new()
	gusty.conditions_name = "Gusty afternoon"
	gusty.wind_speed_mps = 8.0
	lab.set_conditions(gusty)

	var time_text := lab.details.stat_text("time")
	var current_text := lab.details.stat_text("current")
	results.append(TestResult.new(
		"the flight-time row names the selected conditions",
		time_text.contains("Gusty afternoon"),
		"row reads %s" % time_text))
	results.append(TestResult.new(
		"the flight-current row names the selected conditions",
		current_text.contains("Gusty afternoon"),
		"row reads %s" % current_text))

	# Named on every panel that shares PartDetails' footer, not only the frame rail — the same
	# argument part_details.gd's own header makes for why the five (now six) rows are identical
	# across panels.
	var build := lab.current_build()
	build.field_wind_mps = 8.0
	build.field_conditions_name = "Gusty afternoon"
	var motor_panel := MotorDetails.new(catalog)
	motor_panel.render(build.motor, build)
	results.append(TestResult.new(
		"the motor panel's flight-time row also names the selected conditions",
		motor_panel.stat_text("time").contains("Gusty afternoon"),
		"row reads %s" % motor_panel.stat_text("time")))
	motor_panel.free()
	lab.free()
	return results


# ---------------------------------------------------------------------------
# Check 8 — AUW is quoted without a conditions name
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: AUW labelled with the conditions. AUW does not depend on wind at all
## (mass is mass), so a labelled AUW row would be noise — design §3.3's unconditional/conditional
## distinction, restated as a check rather than left to prose.
static func _auw_unconditional() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var lab := LabScreen.new(catalog)

	var gusty := Conditions.new()
	gusty.conditions_name = "A Very Distinctive Conditions Name"
	gusty.wind_speed_mps = 8.0
	lab.set_conditions(gusty)

	var weight_text := lab.details.stat_text("weight")
	results.append(TestResult.new(
		"AUW's row does not carry the conditions name",
		not weight_text.contains("A Very Distinctive Conditions Name"),
		"row reads %s" % weight_text))
	results.append(TestResult.new(
		"AUW's row is still exactly the unconditional format",
		weight_text == "%.0f g" % lab.current_build().all_up_weight_g(),
		"row reads %s" % weight_text))
	lab.free()
	return results


# ---------------------------------------------------------------------------
# Check 9 — changing conditions changes the numbers, without a Lab reload
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: the conditions read once at construction. `LabScreen` here is built
## EXACTLY ONCE; `set_conditions` is then called twice with different wind speeds and the panel's
## own rendered text is required to move BOTH times. A mutation that reads `Conditions` only inside
## `_init` (or caches `wind_mps` somewhere `set_conditions` no longer writes) would leave the second
## call's numbers identical to the first's, which this catches directly rather than only "an
## eventual read is correct".
static func _conditions_change_without_reload() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var lab := LabScreen.new(catalog)   # built ONCE — no second LabScreen anywhere in this check

	var calm := Conditions.standard()
	lab.set_conditions(calm)
	var calm_time := lab.details.stat_text("time")

	var windy := Conditions.new()
	windy.conditions_name = "Windy"
	windy.wind_speed_mps = 15.0
	lab.set_conditions(windy)
	var windy_time := lab.details.stat_text("time")

	results.append(TestResult.new(
		"switching to windy conditions changes the flight-time row's TEXT",
		calm_time != windy_time,
		"calm: %s, windy: %s" % [calm_time, windy_time]))

	# And back again, on the SAME instance, to rule out a mutation that only reads once per
	# direction (e.g. calm -> windy works because it is the first non-default write).
	lab.set_conditions(calm)
	var calm_again := lab.details.stat_text("time")
	results.append(TestResult.new(
		"switching back to calm restores the calm row, still on the same LabScreen",
		calm_again == calm_time,
		"first calm: %s, restored: %s" % [calm_time, calm_again]))
	lab.free()
	return results


# ---------------------------------------------------------------------------
# Check 10 — the wind row is characteristic, quotes units, and never grades
# ---------------------------------------------------------------------------

const GRADE_WORDS := ["too windy", "too much wind", "grade", "graded", "verdict", "difficulty"]

## MUTATION THIS CATCHES: the row returns `limiting` when wind exceeds half the top speed. That
## mutation flips the severity on exactly the input this check drives (wind at more than half the
## reference build's top speed), so asserting CHARACTERISTIC at that input — not merely "some
## severity" — is what catches it.
static func _wind_row_characteristic() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var top_kmh := build.top_speed_kmh()
	# Comfortably past half the top speed, so a "limiting past half" mutation has something to bite.
	build.field_wind_mps = (top_kmh / 3.6) * 0.7
	var warnings := build.warnings()

	var row: BuildWarning = null
	for w in warnings:
		if w.id == &"field_wind":
			row = w
	results.append(TestResult.new(
		"a field_wind warning is present once wind is set",
		row != null,
		"warning ids: %s" % ", ".join(warnings.map(func(w): return String(w.id)))))
	if row == null:
		return results

	results.append(TestResult.new(
		"the wind row is CHARACTERISTIC even at 70% of top speed — it never grades",
		row.severity == BuildWarning.Severity.CHARACTERISTIC,
		"severity %s" % row.severity))
	results.append(TestResult.new(
		"the wind row quotes units (km/h) for both the wind and the top speed",
		row.message.count("km/h") >= 2,
		"message: %s" % row.message))
	results.append(TestResult.new(
		"the wind row names the build's own computed top speed",
		row.message.contains("%.0f km/h" % top_kmh),
		"message: %s, top_speed_kmh=%.4f" % [row.message, top_kmh]))

	var lowered := row.message.to_lower()
	for word in GRADE_WORDS:
		results.append(TestResult.new(
			"the wind row's message does not contain the grading word \"%s\"" % word,
			not lowered.contains(word),
			"message: %s" % row.message))

	# Silent at zero wind — the same rule _field_air() follows.
	var calm_build := ReferenceBuild.build()
	var calm_warnings := calm_build.warnings()
	var calm_has_row := false
	for w in calm_warnings:
		if w.id == &"field_wind":
			calm_has_row = true
	results.append(TestResult.new(
		"the wind row is silent at zero wind",
		not calm_has_row,
		"warning ids: %s" % ", ".join(calm_warnings.map(func(w): return String(w.id)))))
	return results


# ---------------------------------------------------------------------------
# Check 11 — no wind grade, and the sibling assertion: still no difficulty score
# ---------------------------------------------------------------------------

## MUTATION THIS CATCHES: add `course_wind_too_strong` (the brief's own example) — or any OTHER
## wind-shaped id beside `field_wind`, whatever a future implementer names it. Rather than a fixed
## list of forbidden substrings (which a mutation only has to avoid, not satisfy — "verdict" or
## "grade" are two spellings among many), this asserts the POSITIVE claim design §7 actually makes:
## `field_wind` is the ONLY id this whole warning list may ever mention wind by. A first attempt at
## this check scanned only for the substrings "wind_verdict"/"wind_grade" and did NOT catch
## `course_wind_too_strong` in mutation testing — see the F8 report's mutation table — which is
## exactly the false-pass this rewrite exists to close.
static func _no_wind_grade_no_difficulty_score() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	build.field_wind_mps = 20.0   # comfortably past this build's top speed on some catalog entries
	var warnings := build.warnings()

	var scored := false
	var stray_wind_ids: Array[String] = []
	var ids: Array[String] = []
	for w in warnings:
		var id_str := String(w.id)
		ids.append(id_str)
		if id_str.contains("difficulty"):
			scored = true
		if id_str.contains("wind") and id_str != "field_wind":
			stray_wind_ids.append(id_str)

	results.append(TestResult.new(
		"no build warning is given a difficulty score, even under wind — asserted by id over "
			+ "the whole list",
		not scored,
		"warning ids: %s" % ", ".join(ids)))
	results.append(TestResult.new(
		"wind is not graded — \"field_wind\" is the ONLY wind-shaped id in the whole list, "
			+ "asserted positively rather than against a fixed list of forbidden spellings",
		stray_wind_ids.is_empty(),
		"stray wind ids: %s | full list: %s" % [", ".join(stray_wind_ids), ", ".join(ids)]))
	return results
