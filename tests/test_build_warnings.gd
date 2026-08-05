class_name TestBuildWarnings
extends RefCounted
## The severity vocabulary, and the claim that a build is told what it IS rather than what it is
## not (labs-and-sim.md §2.1).
##
## A user built a 7" cinelifter and was told "thrust-to-weight is only 1.7:1 — this will barely
## leave the ground". They then flew it: it hovered at the 76% the readout had predicted to within
## half a percent. The model was right and the sentence was wrong, which is the worse of the two
## failures — the numbers are for people who already know what they mean, and the sentence is what
## a beginner believes.
##
## Every check here exists to keep the sentences accountable to the same physics the numbers come
## from: what has a hard boundary is warned about, what is a continuum is described.

## The reported build, by name. Its figures are pinned here as well as its wording, because a test
## that only asserted the wording would go green if someone "fixed" the warning by breaking the
## model underneath it.
const CINELIFTER := ["frame_7in_cinelifter", "motor_2808_1300kv", "prop_5x43x2",
	"battery_6s_1300", "esc_4in1_80a_30x30"]
## A build that genuinely cannot hold itself up: a 700 g 6S Li-ion on a 3" toothpick, through a
## whoop's 5 A board. Nothing about this one is a matter of taste.
const CANNOT_FLY := ["frame_3in_toothpick", "motor_1103_8000kv", "prop_3x3x3",
	"battery_6s_4000_liion", "esc_aio_5a_whoop"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_every_entry_carries_a_severity_an_id_and_its_numbers(catalog))
	results.append(_test_geometry_that_refuses_is_impossible(catalog))
	results.append(_test_what_merely_binds_is_limiting())
	results.append(_test_a_build_that_cannot_fly_still_says_so(catalog))
	results.append(_test_severity_orders_most_severe_first())
	results.append_array(_test_the_geometry_sources_share_the_vocabulary(catalog))
	results.append_array(_test_the_cinelifter_is_described_not_scolded(catalog))
	results.append(_test_climb_margin_is_the_acceleration_it_actually_has(catalog))
	results.append(_test_manoeuvre_headroom_comes_from_the_mixer(catalog))
	results.append(_test_both_facts_are_told_every_time(catalog))
	results.append(_test_hover_throttle_and_thrust_to_weight_are_one_fact(catalog))
	results.append(_test_the_readout_is_accountable_to_the_sim(catalog))
	results.append_array(_test_the_panels_show_severity(catalog))
	results.append_array(_test_vibration_is_described_never_blocked(catalog))

	return results


static func _build(catalog: PartsCatalog, ids: Array) -> Build:
	return Build.from_ids(catalog, ids[0], ids[1], ids[2], ids[3], ids[4])


## Warnings are data, not prose. The physics layer is the only place that knows the numbers, so the
## sentence is written here — but the severity, a stable id and the values it was derived from
## travel with it, so the UI can sort, group and colour without re-deriving anything.
static func _test_every_entry_carries_a_severity_an_id_and_its_numbers(catalog: PartsCatalog) -> TestResult:
	var entries := _build(catalog, CINELIFTER).warnings()
	var ids: Array = []
	var well_formed := not entries.is_empty()
	for entry in entries:
		ids.append(String(entry.id))
		if not (entry is BuildWarning) or String(entry.id) == "" or entry.message == "" \
				or entry.values.is_empty():
			well_formed = false

	return TestResult.new(
		"every warning carries a severity, a stable id, a message and the values behind it",
		well_formed,
		"%d entries: %s" % [entries.size(), ", ".join(ids)]
	)


## The geometry refuses: 7" props on a 5" freestyle frame would strike it. That is a fact, not a
## preference, and it is the severity a builder must be able to tell apart at a glance.
static func _test_geometry_that_refuses_is_impossible(catalog: PartsCatalog) -> TestResult:
	var oversized := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		"prop_7x4x3", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID)
	var found: BuildWarning = null
	for entry in oversized.warnings():
		if entry.id == &"prop_clearance":
			found = entry

	return TestResult.new(
		"props that would strike the frame are impossible, not merely worth mentioning",
		found != null and found.severity == BuildWarning.Severity.IMPOSSIBLE,
		"prop_clearance %s" % ("absent" if found == null else BuildWarning.severity_name(found.severity))
	)


## The reference build's pack runs out of current before anything else does, and sags well below
## its bench figure. Both are real, both are worth naming the part for, and neither stops it
## flying — 496 g at 11.7:1 is the aircraft the whole project is calibrated on.
static func _test_what_merely_binds_is_limiting() -> TestResult:
	var entries := ReferenceBuild.build().warnings()
	var impossible: Array = []
	var limiting: Array = []
	for entry in entries:
		if entry.severity == BuildWarning.Severity.IMPOSSIBLE:
			impossible.append(String(entry.id))
		elif entry.severity == BuildWarning.Severity.LIMITING:
			limiting.append(String(entry.id))

	return TestResult.new(
		"the reference build's current cap and pack sag are limiting, and nothing about it is impossible",
		impossible.is_empty() and limiting.has("current_limit") and limiting.has("pack_sag"),
		"impossible: %s; limiting: %s" % [str(impossible), str(limiting)]
	)


static func _test_a_build_that_cannot_fly_still_says_so(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, CANNOT_FLY)
	var found: BuildWarning = null
	for entry in build.warnings():
		if entry.id == &"cannot_hover":
			found = entry

	return TestResult.new(
		"a build that cannot lift its own weight says so, at impossible severity",
		not build.can_hover() and found != null
			and found.severity == BuildWarning.Severity.IMPOSSIBLE,
		"can_hover=%s, cannot_hover %s" % [build.can_hover(),
			"absent" if found == null else BuildWarning.severity_name(found.severity)]
	)


## Sorting is by severity and stable within it, so the impossible ones are never below the
## descriptive ones and the order the physics emitted them in survives otherwise.
static func _test_severity_orders_most_severe_first() -> TestResult:
	var shuffled: Array[BuildWarning] = [
		BuildWarning.characteristic(&"c1", "first characteristic", {"n": 1}),
		BuildWarning.limiting(&"l1", "first limiting", {"n": 2}),
		BuildWarning.impossible(&"i1", "impossible", {"n": 3}),
		BuildWarning.characteristic(&"c2", "second characteristic", {"n": 4}),
		BuildWarning.limiting(&"l2", "second limiting", {"n": 5}),
	]
	var order: Array = []
	for entry in BuildWarning.by_severity(shuffled):
		order.append(String(entry.id))

	return TestResult.new(
		"warnings sort impossible first, then limiting, then characteristic, stably within each",
		order == ["i1", "l1", "l2", "c1", "c2"],
		"got %s" % str(order)
	)


## The three warning sources stay separate — what the parts DECLARE about each other, what the
## mount system says, and what the assembled geometry does are deliberately different questions
## (airframe_model.gd:173, :286). But a UI with one rule needs one vocabulary, so all three speak
## the same severities.
static func _test_the_geometry_sources_share_the_vocabulary(catalog: PartsCatalog) -> Array:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion"))
	var mount := airframe.mount_warnings()
	var fit := airframe.battery_fit_warnings()
	var into_the_discs: BuildWarning = null
	for entry in fit:
		if entry.id == &"pack_in_prop_disc":
			into_the_discs = entry
	airframe.free()

	return [
		TestResult.new(
			"mount_warnings speaks the same severity vocabulary as Build.warnings",
			not mount.is_empty() and _all_are_warnings(mount),
			"%d entries: %s" % [mount.size(), str(_ids(mount))]
		),
		TestResult.new(
			"a pack sitting inside the propeller discs is impossible, not a trade-off",
			into_the_discs != null
				and into_the_discs.severity == BuildWarning.Severity.IMPOSSIBLE,
			"pack_in_prop_disc %s (of %s)" % [
				"absent" if into_the_discs == null else BuildWarning.severity_name(into_the_discs.severity),
				str(_ids(fit))]
		),
	]


static func _all_are_warnings(entries: Array) -> bool:
	for entry in entries:
		if not (entry is BuildWarning) or String(entry.id) == "" or entry.message == "":
			return false
	return true


static func _ids(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String(entry.id))
	return out


# ---------------------------------------------------------------------------
# The flight-quality block: what the aircraft DOES, in numbers with units
# ---------------------------------------------------------------------------

## THE REGRESSION, BY NAME. This is the reported build, and against the old three-branch ladder it
## failed: 1.73:1 tripped `thrust_to_weight() < 2.0` and it was told it would barely leave the
## ground, having in fact hovered, climbed and completed laps at the 76.5% the readout predicted.
##
## 2.0:1 was never a boundary between flying and not flying. It is roughly the boundary between
## sluggish and sporty, which is taste, and cinelifters and camera rigs fly at and below it on
## purpose. Nothing here may claim this aircraft will not fly, and nothing here may be impossible.
static func _test_the_cinelifter_is_described_not_scolded(catalog: PartsCatalog) -> Array:
	var build := _build(catalog, CINELIFTER)
	var entries := build.warnings()

	var impossible: Array = []
	var alarming: Array = []
	for entry in entries:
		if entry.severity == BuildWarning.Severity.IMPOSSIBLE:
			impossible.append(String(entry.id))
		var text := entry.message.to_lower()
		for phrase in ["barely", "will not leave the ground", "cannot lift", "won't fly",
				"almost no headroom", "only %.1f:1" % build.thrust_to_weight()]:
			if text.contains(phrase):
				alarming.append(entry.message)

	return [
		TestResult.new(
			"the 7\" cinelifter is not told it will barely leave a ground it demonstrably left",
			impossible.is_empty() and alarming.is_empty(),
			"impossible: %s; alarming: %s" % [str(impossible), str(alarming)]
		),
		# The wording is only right if the numbers under it did not move to make it right.
		TestResult.new(
			"...and the figures it is described by are the ones the pilot flew",
			absf(build.thrust_to_weight() - 1.73) < 0.02
				and absf(build.hover_throttle() - 0.765) < 0.005
				and build.can_hover(),
			"%.2f:1, hover %.1f%%, can_hover=%s" % [build.thrust_to_weight(),
				build.hover_throttle() * 100.0, build.can_hover()]
		),
	]


## "Climbs at 0.7 g" is a physical statement with units that a builder can reason about. It beats
## "barely leaves the ground", it is true, and — the point — it needs no threshold to say it.
static func _test_climb_margin_is_the_acceleration_it_actually_has(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, CINELIFTER)
	var entry := _entry(build.warnings(), &"climb_margin")
	var expected := 9.81 * (build.thrust_to_weight() - 1.0)

	return TestResult.new(
		"climb margin is g(TWR - 1), reported as an acceleration and not as a verdict",
		entry != null and entry.severity == BuildWarning.Severity.CHARACTERISTIC
			and absf(float(entry.values.get("climb_accel_mps2", -1.0)) - expected) < 1e-6
			and absf(expected - 7.16) < 0.05
			and entry.message.contains("m/s"),
		"expected %.2f m/s^2; %s" % [expected, "absent" if entry == null else entry.message]
	)


## The honest reason a high hover throttle matters, and it was not modelled in the warning at all —
## `hover_throttle() > 0.6` was a second arbitrary cut on the same axis as the TWR one.
##
## MotorMixer gives attitude priority over collective (airmode): it builds the per-motor attitude
## deltas first and then shifts the collective until they fit, so the throttle actually held is
## capped at 1 - hi, where hi is the largest delta. A full simultaneous roll+pitch+yaw demand puts
## exactly one motor at +3 * MIX_GAIN, so hover is holdable up to a demand fraction of
## (1 - hover) / (3 * MIX_GAIN). That is the mixer's real clipping point, computed here from its
## own published constant rather than from the number in the branch.
static func _test_manoeuvre_headroom_comes_from_the_mixer(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, CINELIFTER)
	var entry := _entry(build.warnings(), &"manoeuvre_headroom")
	var expected := clampf((1.0 - build.hover_throttle()) / (3.0 * MotorMixer.MIX_GAIN), 0.0, 1.0)

	return TestResult.new(
		"manoeuvre headroom is the mixer's own clipping point, not a threshold typed into a branch",
		entry != null and entry.severity == BuildWarning.Severity.CHARACTERISTIC
			and absf(float(entry.values.get("attitude_demand_fraction", -1.0)) - expected) < 0.005
			and absf(expected - 0.39) < 0.02,
		"expected %.3f of full demand; %s" % [expected, "absent" if entry == null else entry.message]
	)


## They are different facts about the build, so the `elif` ladder that let the alarming one hide the
## useful one is gone. The reported build never saw the headroom sentence — the accurate and
## actionable one — because the TWR branch consumed it first.
static func _test_both_facts_are_told_every_time(catalog: PartsCatalog) -> TestResult:
	var missing: Array = []
	for entry in [{"name": "cinelifter", "build": _build(catalog, CINELIFTER)},
			{"name": "reference", "build": ReferenceBuild.build()}]:
		var warnings: Array[BuildWarning] = (entry["build"] as Build).warnings()
		for id in [&"climb_margin", &"manoeuvre_headroom"]:
			if _entry(warnings, id) == null:
				missing.append("%s: %s" % [entry["name"], id])

	return TestResult.new(
		"climb margin and manoeuvre headroom are both reported for any build that flies",
		missing.is_empty(),
		"missing: %s" % ("none" if missing.is_empty() else str(missing))
	)


## Hover throttle and thrust-to-weight are ONE quantity, not two: thrust goes as the square of RPM
## and RPM as the throttle command, so hover sits at sqrt(1 / TWR) of the way up. TWR 2.0 IS hover
## 70.7%. The old block cut that single continuum in two places, at 2.0:1 and at 60%, and the two
## constants could be edited into disagreeing with each other about the same aircraft.
##
## The residual against real builds is pack sag, which lifts the real hover a little above the
## square-law figure — a percent or so on these two, and it is a physical effect rather than slack
## in the identity.
static func _test_hover_throttle_and_thrust_to_weight_are_one_fact(catalog: PartsCatalog) -> TestResult:
	var worst := 0.0
	var details: Array = []
	for build in [ReferenceBuild.build(), _build(catalog, CINELIFTER)]:
		var ideal := sqrt(1.0 / build.thrust_to_weight())
		var error := absf(build.hover_throttle() - ideal) / ideal
		worst = maxf(worst, error)
		details.append("%.1f:1 -> %.1f%% against sqrt(1/TWR) = %.1f%%" % [
			build.thrust_to_weight(), build.hover_throttle() * 100.0, ideal * 100.0])

	return TestResult.new(
		"hover throttle is sqrt(1 / thrust-to-weight): one fact, so it cannot be cut twice",
		worst < 0.03 and absf(sqrt(1.0 / 2.0) - 0.707) < 0.001,
		"worst deviation %.1f%% (%s)" % [worst * 100.0, "; ".join(details)]
	)


## What makes the readout accountable to the physics rather than to itself, and what would have
## settled the report on the spot: fly the cinelifter at the throttle the panel quotes for its own
## pack and see whether it holds altitude. tests/test_hover_at_charge.gd asks this of the reference
## build across the discharge; nothing asked it of a build outside the 5" class.
##
## Four motors commanded directly, no flight controller, for the reason that file gives: a
## controller between the command and the motors is a second thing that could hold the aircraft up.
static func _test_the_readout_is_accountable_to_the_sim(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, CINELIFTER)
	var core := build.build_drone_core()
	var throttle := build.hover_throttle_for(core.powertrain.battery)
	core.prime_motors(throttle)

	var commands: Dictionary = {}
	for name in MotorLayout.MOTOR_NAMES:
		commands[name] = throttle

	var dt := 1.0 / 500.0
	var start_m: float = core.rigid_body.position_m.y
	for _i in int(3.0 / dt):
		core.step(commands, dt)
	var drift := core.rigid_body.position_m.y - start_m

	return TestResult.new(
		"the throttle the panel quotes for the cinelifter is the throttle that hovers it",
		absf(drift) < 0.5 and throttle > 0.5,
		"commanded %.1f%%, altitude moved %+.2f m over 3 s" % [throttle * 100.0, drift]
	)


static func _entry(entries: Array[BuildWarning], id: StringName) -> BuildWarning:
	for entry in entries:
		if entry.id == id:
			return entry
	return null


# ---------------------------------------------------------------------------
# The panels: severity is visible, or it may as well not exist
# ---------------------------------------------------------------------------

## Both panels used to dump every warning into one amber block, which is the UI half of the same
## bug: a build that cannot be assembled and a build that is merely heavy arrived looking
## identical. Impossible has to read as a problem and characteristic has to read as information,
## and the impossible ones must never sit below the descriptive ones.
##
## The colours are the theme's existing roles — no new literals, no icon font.
static func _test_the_panels_show_severity(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# A build with all three severities at once: 7" props on the 5" freestyle frame (impossible),
	# its pack's current cap and sag (limiting), and what it flies like (characteristic).
	var mixed := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		"prop_7x4x3", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID)

	var panel := BuildPanel.new(catalog, {"propeller": "prop_7x4x3"})
	panel._rebuild()
	results.append_array(_assert_panel_shows_severity("build panel", panel._warnings))
	panel.free()

	var details := PartDetails.new([])
	details.render(catalog.list_category("frame")[0], mixed)
	results.append_array(_assert_panel_shows_severity("part details", details._warnings))
	details.free()

	return results


static func _assert_panel_shows_severity(panel_name: String, list: WarningList) -> Array:
	var impossible := list.text_for(BuildWarning.Severity.IMPOSSIBLE)
	var limiting := list.text_for(BuildWarning.Severity.LIMITING)
	var characteristic := list.text_for(BuildWarning.Severity.CHARACTERISTIC)
	var whole := list.ordered_text()

	return [
		TestResult.new(
			"%s: the impossible warning is above the descriptive one, never below it" % panel_name,
			impossible != "" and characteristic != "" and limiting != ""
				and whole.find(impossible) < whole.find(limiting)
				and whole.find(limiting) < whole.find(characteristic),
			"impossible at %d, limiting at %d, characteristic at %d" % [
				whole.find(impossible), whole.find(limiting), whole.find(characteristic)]
		),
		TestResult.new(
			"%s: impossible reads as a problem and characteristic reads as information" % panel_name,
			list.color_for(BuildWarning.Severity.IMPOSSIBLE) == LothalTheme.DANGER
				and list.color_for(BuildWarning.Severity.LIMITING) == LothalTheme.WARNING
				and list.color_for(BuildWarning.Severity.CHARACTERISTIC) == LothalTheme.TEXT_MUTED,
			"impossible %s, limiting %s, characteristic %s" % [
				list.color_for(BuildWarning.Severity.IMPOSSIBLE),
				list.color_for(BuildWarning.Severity.LIMITING),
				list.color_for(BuildWarning.Severity.CHARACTERISTIC)]
		),
	]


# ---------------------------------------------------------------------------
# Vibration describes a continuum (LTHL-15)
# ---------------------------------------------------------------------------

## Where physics has a hard boundary, warn; where it has a continuum, describe (parts.md).
## Frame resonance is the purest continuum in the project: there is no throttle at which the
## aircraft stops working, only one at which the gyro gets noisy and the D term starts costing
## motor heat. So a build whose hover harmonic sits on its frame mode is DESCRIBED, and a
## severity that implied otherwise would be telling a builder they had made a mistake for
## building a perfectly ordinary quad — which is the exact failure the cinelifter above suffered.
static func _test_vibration_is_described_never_blocked(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var found: BuildWarning = null
	for w in build.warnings():
		if w.id == &"frame_resonance":
			found = w

	out.append(TestResult.new(
		"every build is told where its frame mode is",
		found != null,
		"warning ids: %s" % str(_ids(build.warnings()))))
	if found == null:
		return out

	out.append(TestResult.new(
		"frame resonance is characteristic, never limiting or impossible",
		found.severity == BuildWarning.Severity.CHARACTERISTIC,
		"severity %s: \"%s\"" % [BuildWarning.severity_name(found.severity), found.message]))

	# The sentence must be accountable to the model that produced it, the way climb margin is.
	# A wording test alone would go green if someone "fixed" the warning by breaking the physics.
	var model := VibrationModel.for_build(build)
	out.append(TestResult.new(
		"the sentence quotes the model's own frame mode rather than a second derivation",
		absf(float(found.values["resonance_hz"]) - model.resonance_hz) < 0.01,
		"warning says %.1f Hz, VibrationModel says %.1f Hz"
			% [float(found.values["resonance_hz"]), model.resonance_hz]))

	# The throttle at which a harmonic crosses the mode is the actionable half — it is what a
	# builder would go and listen for. Checked against the build's own rpm curve rather than
	# against a number typed into the test.
	var crossing := float(found.values["imbalance_crossing_throttle"])
	var rpm_there := build.rpm_at_throttle(crossing)
	out.append(TestResult.new(
		"the throttle it quotes is the one where rotation frequency actually meets the mode",
		absf(rpm_there / 60.0 - model.resonance_hz) < model.resonance_hz * 0.02,
		"crossing quoted at %.0f%% throttle, where the build turns %.0f rpm = %.0f Hz against a %.0f Hz mode"
			% [crossing * 100.0, rpm_there, rpm_there / 60.0, model.resonance_hz]))

	# NOTHING here may quote an error bar. VibrationModel rests on one guessed scale constant and
	# no held-out measurement exists to check it against, so a percentage in this sentence would
	# be a fabricated accuracy claim — worse than no error bar at all (labs-and-sim.md §2.1's
	# converse). Frequencies and throttles are fine: those come from laws and from the rpm curve.
	out.append(TestResult.new(
		"the sentence claims no accuracy it cannot back — no error bar on a characteristic model",
		not found.message.contains("±") and not found.message.contains("+/-")
			and not found.values.has("error_fraction"),
		"\"%s\"" % found.message))

	return out
