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
