class_name TestPlanformEdits
extends RefCounted
## `PlanformEdits` — every change the propulsion room can make to a blade's planform, checked
## without a window. Slice P10d.
##
## ## Why these, and why they are here rather than in the canvas's suite
##
## The room's split is `FramePlanEditor`/`FrameEdits`': the canvas holds what a human has to look
## at, and the arithmetic holds everything that can be wrong in a way a screenshot would not show.
## These are that everything. The three invariants the file names — two stations minimum, strictly
## ascending r/R, no negative chord — are properties `PropellerDocument.chord_at` DEPENDS ON and
## does not check, so a break here is silent downstream: an out-of-order station does not look
## wrong, it makes a whole span of the blade unreachable and the mass integral quietly changes.
##
## ## MUTATION NOTES
##
##   - `_test_a_refused_edit_changes_nothing` fails if any function "repairs" its input instead of
##     returning it — which is the tempting implementation and the one that edits a blade the
##     builder did not ask to edit.
##   - `_test_inserting_a_station_does_not_move_the_curve` fails if `insert_station` interpolates
##     the new chord itself rather than asking the document; the two agree today and would part
##     company the moment `chord_at` gained a spline.
##   - `_test_every_edit_keeps_the_table_ascending` fails for any function that appends without
##     sorting, which reads correct until a builder inserts a station before an existing one.

const SAMPLES := 21


static func run() -> Array:
	var results: Array = []
	results.append(_test_setting_one_chord_leaves_the_others_alone())
	results.append(_test_a_refused_edit_changes_nothing())
	results.append(_test_inserting_a_station_does_not_move_the_curve())
	results.append(_test_removing_the_last_two_stations_is_refused())
	results.append(_test_every_edit_keeps_the_table_ascending())
	results.append(_test_scaling_multiplies_every_chord_and_no_radius())
	return results


static func _reference() -> PropellerDocument:
	var catalog := PartsCatalog.load_default()
	return PropellerDocument.from_catalog_prop(catalog.get_part("prop_5x43x3"))


## The commonest edit: one station moves, and every other number in the table is untouched TO THE
## BIT. Asserted as bit-equality rather than approximately, because "close enough" is exactly the
## failure a rebuild-the-whole-table implementation would produce.
static func _test_setting_one_chord_leaves_the_others_alone() -> TestResult:
	var doc := _reference()
	var before := doc.chord.duplicate()
	var index := 12
	var edited := PlanformEdits.set_chord(before, index, 4.25)

	var moved := 0
	var wrong: Array = []
	for i in PlanformEdits.station_count(before):
		var was: float = before[i * 2 + 1]
		var now: float = edited[i * 2 + 1]
		if before[i * 2] != edited[i * 2]:
			wrong.append("station %d changed radius" % i)
		if i == index:
			if now != 4.25:
				wrong.append("station %d is %.6f, wanted 4.25" % [i, now])
			elif was != now:
				moved += 1
		elif was != now:
			wrong.append("station %d moved from %.9f to %.9f" % [i, was, now])

	return TestResult.new(
		"[P10d] setting one station's chord moves that station and nothing else",
		wrong.is_empty() and moved == 1,
		"%d stations, %d moved, %s" % [PlanformEdits.station_count(before), moved,
			"no other value changed" if wrong.is_empty() else "; ".join(wrong)])


## Every refusal in the file, as one check: a negative chord, a non-finite chord, an out-of-range
## index, a duplicate insert radius, a non-positive scale. Each must return the array UNCHANGED —
## not a clamped version, not an empty one.
static func _test_a_refused_edit_changes_nothing() -> TestResult:
	var doc := _reference()
	var original := doc.chord.duplicate()

	var cases := {
		"negative chord": PlanformEdits.set_chord(original, 5, -1.0),
		"NAN chord": PlanformEdits.set_chord(original, 5, NAN),
		"index past the end": PlanformEdits.set_chord(original, 999, 3.0),
		"negative index": PlanformEdits.set_chord(original, -1, 3.0),
		"insert at an existing station": PlanformEdits.insert_station(
			original, original[0], doc),
		"insert at NAN": PlanformEdits.insert_station(original, NAN, doc),
		"remove past the end": PlanformEdits.remove_station(original, 999),
		"scale by zero": PlanformEdits.scale_chord(original, 0.0),
		"scale by a negative": PlanformEdits.scale_chord(original, -2.0),
	}

	var wrong: Array = []
	for label in cases:
		if cases[label] != original:
			wrong.append(str(label))

	return TestResult.new(
		"[P10d] a refused planform edit returns the table unchanged rather than repairing it",
		wrong.is_empty(),
		"%d refusals, all inert" % cases.size() if wrong.is_empty()
			else "changed the table: %s" % "; ".join(wrong))


## Adding a control point must change the SHAPE not at all — the builder adds it and then drags it,
## and an insert with a side effect makes the drag that follows untrustworthy.
##
## Checked as `chord_at` over the whole span rather than at the inserted radius alone: an insert
## that landed the right value at the wrong index would pass a single-point check and bend the
## curve either side of it.
static func _test_inserting_a_station_does_not_move_the_curve() -> TestResult:
	var doc := _reference()
	var before: Array = []
	for i in SAMPLES:
		before.append(doc.chord_at(float(i) / float(SAMPLES - 1)))

	var at := 0.634
	doc.chord = PlanformEdits.insert_station(doc.chord, at, doc)

	var worst := 0.0
	for i in SAMPLES:
		var r := float(i) / float(SAMPLES - 1)
		worst = maxf(worst, absf(doc.chord_at(r) - float(before[i])))

	var added := PlanformEdits.station_count(doc.chord) - SAMPLES
	return TestResult.new(
		"[P10d] adding a station changes the number of points and not the curve",
		PlanformEdits.station_count(doc.chord) == PropellerDocument.PLANFORM_STATIONS + 1
			and worst == 0.0,
		"%d stations, worst c(r) change over %d samples: %.12f mm (added %d)" % [
			PlanformEdits.station_count(doc.chord), SAMPLES, worst, added])


## A planform of one point is a cylinder pretending to be a blade — `chord_at` would return that
## one value at every radius. The floor is asserted by removing down TO it and then once more.
static func _test_removing_the_last_two_stations_is_refused() -> TestResult:
	var doc := _reference()
	var chord := doc.chord.duplicate()
	var removed := 0
	while PlanformEdits.station_count(chord) > PlanformEdits.MIN_STATIONS:
		var next := PlanformEdits.remove_station(chord, 0)
		if next == chord:
			break
		chord = next
		removed += 1

	var at_floor := PlanformEdits.station_count(chord)
	var one_more := PlanformEdits.remove_station(chord, 0)

	return TestResult.new(
		"[P10d] a planform cannot be reduced below two stations",
		at_floor == PlanformEdits.MIN_STATIONS and one_more == chord,
		"removed %d down to %d stations; the next removal was %s" % [
			removed, at_floor, "refused" if one_more == chord else "ALLOWED"])


## Invariant 2, over every function that can break it. `chord_at` walks the list in order, so a
## station out of sequence makes a span unreachable rather than wrong-looking.
static func _test_every_edit_keeps_the_table_ascending() -> TestResult:
	var doc := _reference()
	var wrong: Array = []

	var after_insert_low := PlanformEdits.insert_station(doc.chord, 0.11, doc)
	if not PlanformEdits.is_valid(after_insert_low):
		wrong.append("insert before an existing station")
	# Inserting BELOW the first station is the case an append-without-sort gets wrong, so it is
	# checked by position rather than only by validity.
	if after_insert_low.size() >= 2 and after_insert_low[0] > 0.11:
		wrong.append("insert did not land first")

	var after_set := PlanformEdits.set_chord(doc.chord, 0, 99.0)
	if not PlanformEdits.is_valid(after_set):
		wrong.append("set_chord")
	var after_remove := PlanformEdits.remove_station(doc.chord, 3)
	if not PlanformEdits.is_valid(after_remove):
		wrong.append("remove_station")
	var after_scale := PlanformEdits.scale_chord(doc.chord, 1.4)
	if not PlanformEdits.is_valid(after_scale):
		wrong.append("scale_chord")

	# And the guard itself must be able to say no, or every line above is vacuous.
	var descending := PackedFloat64Array([0.5, 3.0, 0.2, 4.0])
	if PlanformEdits.is_valid(descending):
		wrong.append("is_valid accepted a descending table")

	return TestResult.new(
		"[P10d] every planform edit leaves the table ascending, and is_valid can say no",
		wrong.is_empty(),
		"4 edits + the guard's own negative case" if wrong.is_empty() else "; ".join(wrong))


static func _test_scaling_multiplies_every_chord_and_no_radius() -> TestResult:
	var doc := _reference()
	var before := doc.chord.duplicate()
	var scaled := PlanformEdits.scale_chord(before, 1.25)

	var wrong: Array = []
	for i in PlanformEdits.station_count(before):
		if before[i * 2] != scaled[i * 2]:
			wrong.append("station %d moved in radius" % i)
		var want: float = float(before[i * 2 + 1]) * 1.25
		if absf(float(scaled[i * 2 + 1]) - want) > 1e-12:
			wrong.append("station %d is %.9f, wanted %.9f" % [i, scaled[i * 2 + 1], want])

	return TestResult.new(
		"[P10d] scaling a planform multiplies every chord and moves no radius",
		wrong.is_empty() and PlanformEdits.station_count(before) > 0,
		"%d stations scaled by 1.25" % PlanformEdits.station_count(before)
			if wrong.is_empty() else "; ".join(wrong))
