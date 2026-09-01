class_name TestPropulsionRoom
extends RefCounted
## The Propulsion room and its three authoring views — slice P10d.
##
## ## What these checks are for, and what they leave to a photograph
##
## `test_planform_edits.gd` covers what a gesture MEANS. This suite covers everything between the
## gesture and the model: that a drag lands on the chord the pixel says, that an edit reaches the
## 3D blade, that the section drawn is the section the mesh builds, and that the mount profile is
## the motor's own geometry rather than a redrawing of it. None of that is visible in a screenshot,
## and all of it is where the room could be wrong while looking right.
##
## What is deliberately NOT here is anything about layout — column widths, whether the shelf
## scrolls, whether the caption fits. `Label.update_minimum_size()` does nothing on a node outside
## the tree (`test_frame_workbench.gd`'s own finding), so those assertions would report the same
## number for correct and broken code alike. They are checked by photographing the shell.
##
## ## MUTATION NOTES
##
##   - `_test_an_edit_in_the_room_reaches_the_3d_blade` is the slice's own reason to exist. It
##     fails against any `PropellerMesh` that computes its own chord — which is the code that
##     shipped until P10d — by millimetres, not by rounding.
##   - `_test_the_section_view_draws_the_meshs_own_section` fails if either side grows a second
##     copy of the section geometry, including the sign flip on the face normal that would turn the
##     blade inside out while leaving every chord and angle correct.
##   - `_test_the_profile_height_is_the_motor_meshs_own` fails if the profile derives any height
##     from `MotorMesh.dimensions()` instead of reading the built cylinders.
##   - `_test_moving_the_caret_rebuilds_nothing` fails if `caret_moved` is wired to `_refresh`,
##     which is the obvious wiring and the one that re-integrates a blade on every mouse motion.

const CANVAS_SIZE := Vector2(420.0, 220.0)


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_room_opens_on_the_reference_blade())
	results.append(_test_the_shelf_shows_every_catalog_blade())
	results.append(_test_a_drag_lands_on_the_chord_the_pixel_means())
	results.append(_test_an_edit_clears_the_assumed_chord_caveat())
	results.append(_test_the_measured_toggle_reads_the_way_it_is_written())
	results.append(_test_an_edit_in_the_room_reaches_the_3d_blade())
	results.append(_test_the_section_view_draws_the_meshs_own_section())
	results.append(_test_the_profile_height_is_the_motor_meshs_own())
	results.append(_test_a_pad_moves_both_the_picture_and_the_frequency())
	results.append(_test_moving_the_caret_rebuilds_nothing())
	results.append(_test_the_prop_panel_carries_the_door_and_opens_nothing_itself())
	results.append(_test_a_drag_is_one_undo_step_and_two_undos_reach_the_start())
	results.append(_test_redo_walks_back_up_and_a_new_edit_forgets_the_branch())
	results.append(_test_a_refused_edit_leaves_nothing_to_undo())
	results.append(_test_undo_cannot_reach_across_an_open())
	results.append(_test_undoing_back_to_the_published_shape_says_so())
	return results


# ---------------------------------------------------------------------------
# §7d — undo, which P10d owed
# ---------------------------------------------------------------------------

## The blade the room opened on, and the far side of a preset that is not it. Named here rather
## than inline so the cross-document check reads as what it is.
const OTHER_PRESET := "prop_3x3x3"


## Lets go of the mouse, through the canvas's own handler. A gesture is bounded by a press and a
## release, and the release is what re-arms `edit_began` — so a test that called `drag_station_to`
## six times without one would be testing a single six-motion drag, not two drags.
static func _release_mouse(editor: PropellerPlanformEditor) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	editor._gui_input(event)


## One gesture: several motions on one station, then a release.
static func _drag_gesture(room: PropulsionWorkbench, index: int, to_mm: float) -> void:
	var r_frac: float = float(PlanformEdits.points(room.document.chord)[index][0])
	var from_mm: float = float(PlanformEdits.points(room.document.chord)[index][1])
	# Four motions, because the failure this is aimed at is per-motion recording and one motion
	# cannot tell the two apart.
	for step in [0.25, 0.5, 0.75, 1.0]:
		var at_mm: float = from_mm + (to_mm - from_mm) * float(step)
		room.editor.drag_station_to(index, room.editor.to_pixels(r_frac, at_mm))
	_release_mouse(room.editor)


## A DRAG IS ONE UNDO STEP, and undoing twice reaches the shape the room opened on.
##
## Two failures live here and the check is built to separate them. The first is granularity: the
## canvas changes the document on every mouse motion, so a history recorded off `document_changed`
## would hold one entry per pixel and undo would crawl back along the cursor's path — the first
## clause is the station count of the stack, and it is 1 per gesture or the feature is useless.
##
## The second is `FrameHistory`'s own aliasing trap, restated because it is the one that looks like
## it works: a stack holding the live `PropellerDocument` rather than its dictionary would have
## every later edit mutating the memory of the earlier shape, so the FIRST undo appears to do
## nothing much and the second cannot reach the start. Hence two gestures and two undos.
##
## Both mutations were run and both went red, and neither split the way it was predicted to — worth
## recording, because the prediction was the reason to believe the clauses were independent.
##
##   - Dropping the `_edit_open` latch (emit `edit_began` on every motion): depth reads 4/8 instead
##     of 1/2, AND both chord clauses go red. The guess was that the shapes on the stack are still
##     real ones so the chords would survive; they do not, because one undo then lands a quarter of
##     the way back along the drag rather than at its start. The depth clause and the chord clauses
##     are measuring the same defect from two ends.
##   - Storing the live document (`_undone.append(document)` with `undo` returning it unchanged):
##     both chord clauses go red and the depth clauses stay green, which is the aliasing bug wearing
##     its usual disguise — the stack is the right SIZE and every entry on it is the present.
static func _test_a_drag_is_one_undo_step_and_two_undos_reach_the_start() -> TestResult:
	var room := _room()
	var opened := room.document.chord.duplicate()

	_drag_gesture(room, 12, 3.0)
	var depth_after_one: int = room.history.depth()
	var after_first := room.document.chord.duplicate()

	_drag_gesture(room, 20, 2.0)
	var depth_after_two: int = room.history.depth()

	room.undo()
	var back_to_first := room.document.chord.duplicate()
	room.undo()
	var back_to_opened := room.document.chord.duplicate()
	room.free()

	var moved: bool = after_first != opened
	var one_step_each: bool = depth_after_one == 1 and depth_after_two == 2
	var first_undo_lands: bool = back_to_first == after_first
	var second_undo_lands: bool = back_to_opened == opened

	return TestResult.new(
		"[§7d] a drag is ONE undo step, and two undos put the blade back where the room opened it",
		moved and one_step_each and first_undo_lands and second_undo_lands,
		"drag moved the blade %s, depth 1/2 -> %d/%d, undo lands on the first shape %s, second undo lands on the opened shape %s" % [
			str(moved), depth_after_one, depth_after_two,
			str(first_undo_lands), str(second_undo_lands)])


## Redo is the other half of the loop the room is for — push a station, look at the section, put it
## back, look again — and the branch rule is what keeps it honest: once a new edit is made from an
## undone state, the shapes that used to lie ahead are unreachable, and offering to redo into one
## would move the blade sideways into a history nobody is in any more.
##
## Mutations that turn this red: dropping `_redone.clear()` from `BladeHistory.record` reddens the
## last clause alone; having `redo()` fail to push the current state back onto the undo stack
## reddens the "undo is available again" clause and leaves the chord clauses green.
static func _test_redo_walks_back_up_and_a_new_edit_forgets_the_branch() -> TestResult:
	var room := _room()
	var opened := room.document.chord.duplicate()
	_drag_gesture(room, 12, 3.0)
	var edited := room.document.chord.duplicate()

	room.undo()
	var redo_offered: bool = room.history.can_redo()
	var undone := room.document.chord.duplicate()

	room.redo()
	var redone := room.document.chord.duplicate()
	var undo_offered_again: bool = room.history.can_undo()

	# A fresh edit from here. The redo branch is now unreachable and must be gone.
	room.undo()
	_drag_gesture(room, 25, 1.5)
	var branch_forgotten: bool = not room.history.can_redo()
	room.free()

	var undone_right: bool = undone == opened
	var redone_right: bool = redone == edited and edited != opened
	return TestResult.new(
		"[§7d] redo returns the undone shape, and an edit made from an undone state forgets it",
		redo_offered and undone_right and redone_right and undo_offered_again
			and branch_forgotten,
		"redo offered %s, undo landed on the opened shape %s, redo landed on the edited shape %s, undo offered again %s, branch forgotten after a new edit %s" % [
			str(redo_offered), str(undone_right), str(redone_right),
			str(undo_offered_again), str(branch_forgotten)])


## AN EDIT THE MODEL REFUSED IS NOT AN EDIT. `+ Station` at a radius that already carries one,
## `− Station` on a two-station planform and a toggle set to the value it already holds all leave
## the document exactly as it was, and a history entry for any of them is a press of undo that
## appears to do nothing — which a builder reads as undo being broken, not as their own no-op.
##
## The three are checked together because they are one rule with three call sites, and the obvious
## wrong implementation — `history.record` as the first line of each handler — breaks all three.
##
## Mutation that turns this red: move `history.record(document)` above the refusal check in
## `_on_add_station`. All four clauses go red — 1, 1, 1 and 3 steps — and the reason is worth
## stating rather than tidying, since it was not the predicted result: the depth is CUMULATIVE
## across the four presses, so one bad call site drags every later count with it. This check
## therefore names the rule and not the call site; the "a refused insert left 1 step" line in the
## detail is what names the call site.
static func _test_a_refused_edit_leaves_nothing_to_undo() -> TestResult:
	var room := _room()
	var faults: Array = []

	# A station already sits at the caret's own radius: put the caret exactly on one.
	room.editor.caret_r_frac = float(PlanformEdits.points(room.document.chord)[7][0])
	room._on_add_station()
	if room.history.depth() != 0:
		faults.append("a refused insert left %d step(s)" % room.history.depth())

	# The floor. Two stations left, and `− Station` must refuse.
	room.document.chord = PackedFloat64Array([0.2, 5.0, 0.9, 3.0])
	room._on_remove_station()
	if room.history.depth() != 0:
		faults.append("a refused remove left %d step(s)" % room.history.depth())

	# The toggle, set to what it already says.
	room.document.chord_is_assumed = true
	room._on_assumed_toggled(false)
	if room.history.depth() != 0:
		faults.append("a no-op toggle left %d step(s)" % room.history.depth())

	# And the control: a station the planform CAN take is one step, so the check above is not
	# passing because nothing is ever recorded.
	room.editor.caret_r_frac = 0.55
	room._on_add_station()
	var real_edit_recorded: bool = room.history.depth() == 1
	if not real_edit_recorded:
		faults.append("a real insert recorded %d step(s)" % room.history.depth())
	room.free()

	return TestResult.new(
		"[§7d] an insert, a remove or a toggle the model refused leaves nothing on the undo stack",
		faults.is_empty(),
		"three refusals recorded nothing and a real insert recorded one step"
			if faults.is_empty() else "; ".join(faults))


## UNDO MUST NOT REACH ACROSS AN OPEN. The shelf is one click from the canvas, so a builder edits a
## 5", picks a 3" off the shelf, presses Ctrl-Z — and on a history that survived the open, the 3"
## on screen is silently replaced by the 5" they thought they had left.
##
## Both clauses are needed. "Nothing to undo" alone would pass on a room that had stopped recording
## altogether, so the diameter is asserted after a real edit on the new blade: the history works,
## it just does not contain the other propeller.
##
## Mutation that turns this red: remove `history.clear()` from `set_document`. The first clause goes
## red immediately and the second follows it, since the undo then lands on the 5".
static func _test_undo_cannot_reach_across_an_open() -> TestResult:
	var room := _room()
	var first_diameter := room.document.diameter_mm
	_drag_gesture(room, 12, 3.0)

	room.open_preset(OTHER_PRESET)
	var second_diameter := room.document.diameter_mm
	var nothing_carried_over: bool = not room.history.can_undo()

	room.undo()
	var still_the_new_blade: bool = room.document.diameter_mm == second_diameter

	# The history is alive on THIS blade, which is what makes the clause above a statement about
	# the clear rather than about a room that records nothing.
	var before := room.document.chord.duplicate()
	_drag_gesture(room, 5, 1.2)
	room.undo()
	var records_here: bool = room.document.chord == before
	room.free()

	return TestResult.new(
		"[§7d] opening a different blade forgets the last one's history — undo cannot cross the shelf",
		nothing_carried_over and still_the_new_blade and records_here
			and first_diameter != second_diameter,
		"%.1f mm -> %.1f mm; nothing carried over %s, undo left the new blade alone %s, history works on the new blade %s" % [
			first_diameter, second_diameter, str(nothing_carried_over),
			str(still_the_new_blade), str(records_here)])


## THE STATUS LINE COMES BACK BY ITSELF, and that is the finding worth pinning rather than the
## feature. §2.1's comparison is BY VALUE — `document.to_dictionary() == _published` — so an undo
## that lands on the published shape must make the room say the aircraft flies this blade again
## with no undo-aware code anywhere in the publish path. It only holds because undo goes through
## `_show_document` and NOT through `set_document`, which clears `_published` on purpose.
##
## The middle clause is the one that makes this more than a tautology: the room must say "edited
## since publishing" first, or the final line could be the line it never stopped showing.
##
## Mutation that turns this red: have `undo()` call `set_document` instead of `_show_document` —
## the obvious wiring, since `set_document` is documented as the one path in. The published-again
## clause goes red and the edited clause stays green.
static func _test_undoing_back_to_the_published_shape_says_so() -> TestResult:
	# The builder's own parts file, captured through the same helpers `test_authored_blade.gd`
	# wrote for this — one definition of "put it back", not two.
	var captured := TestAuthoredBlade._capture_custom_parts()

	var room := _room()
	room.document.name = "Undo status fixture blade"
	room._on_publish()
	var published_line := room._status.text

	_drag_gesture(room, 12, 3.0)
	var edited_line := room._status.text

	room.undo()
	var undone_line := room._status.text
	var snapshot_survived: bool = not room._published.is_empty()
	room.free()

	var restored := TestAuthoredBlade._restore_custom_parts(captured)

	var said_published: bool = published_line.contains("this is the blade your aircraft flies")
	var said_edited: bool = edited_line.contains("Edited since publishing")
	var said_published_again: bool = undone_line.contains("this is the blade your aircraft flies")
	return TestResult.new(
		"[§7d] undoing back to the published shape makes the room say the aircraft flies it again",
		said_published and said_edited and said_published_again and snapshot_survived
			and restored,
		"published \"%s\", edited \"%s\", undone \"%s\", snapshot survived %s, user file restored %s" % [
			published_line, edited_line, undone_line, str(snapshot_survived), str(restored)])


static func _room() -> PropulsionWorkbench:
	var room := PropulsionWorkbench.new(PartsCatalog.load_default())
	room.size = Vector2(1200.0, 700.0)
	room.editor.size = CANVAS_SIZE
	room.section.size = Vector2(240.0, 200.0)
	room.profile.size = Vector2(240.0, 320.0)
	return room


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

## A room opened cold shows the blade the rest of the app is pinned to, with a real planform on it.
## The station count is asserted too, because a document that opened EMPTY would satisfy every
## "is there a document" check and draw nothing.
static func _test_the_room_opens_on_the_reference_blade() -> TestResult:
	var room := _room()
	var document := room.document
	var stations := PlanformEdits.station_count(document.chord) if document != null else 0
	var shared := document != null and room.editor.document == document \
		and room.section.document == document
	room.free()

	return TestResult.new(
		"[P10d] the room opens on the reference blade, and all three views hold that one document",
		document != null and stations == PropellerDocument.PLANFORM_STATIONS and shared,
		"%d stations; editor and section share the room's document: %s" % [stations, shared])


## The shelf is the catalog, not a list somebody typed. Asserted against the catalog's own count
## with a vacuity guard, because an empty shelf and a correct shelf look identical to a check that
## only asks whether the numbers match.
static func _test_the_shelf_shows_every_catalog_blade() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var room := PropulsionWorkbench.new(catalog)
	var shown := room.shelf.preset_count()
	var expected := catalog.list_category("propeller").size()
	room.free()

	return TestResult.new(
		"[P10d] the shelf carries one chip per catalog blade",
		expected > 0 and shown == expected,
		"%d chips against %d catalog propellers" % [shown, expected])


# ---------------------------------------------------------------------------
# The planform canvas
# ---------------------------------------------------------------------------

## The canvas's mm-to-pixel mapping, checked in the direction a drag uses it: a station drawn at a
## pixel, dragged to a DIFFERENT pixel, must end up with the chord that second pixel means.
##
## The round trip is asserted first and separately. A mapping that was self-consistent but wrong —
## the chord not halved for the symmetric drawing, say — would pass the drag check on its own,
## because the drag reads the pixel back through the same broken function.
static func _test_a_drag_lands_on_the_chord_the_pixel_means() -> TestResult:
	var room := _room()
	var editor := room.editor
	var index := 15
	var station: Array = PlanformEdits.points(room.document.chord)[index]
	var r_frac := float(station[0])

	var wrong: Array = []

	# The round trip, at four chords across the blade's range.
	for chord_mm in [1.0, 4.0, 8.5, 13.0]:
		var back := editor.chord_from_pixels(editor.to_pixels(r_frac, float(chord_mm)))
		# RELATIVE, and at the float32 floor: `Control.size` and every pixel derived from it are
		# single precision, so a round trip through them cannot be bit-exact. A halving error —
		# the thing this check is really for, since the blade is drawn symmetric about its
		# centreline — is a factor of two and clears this by five orders.
		if absf(back - float(chord_mm)) / float(chord_mm) > 1e-5:
			wrong.append("round trip at %.1f mm came back %.6f" % [chord_mm, back])

	# And the drag itself, to a pixel that is NOT where the station already is.
	var target_mm := float(station[1]) * 0.5
	var target := editor.to_pixels(r_frac, target_mm)
	editor.drag_station_to(index, target)
	var landed: float = float(PlanformEdits.points(room.document.chord)[index][1])
	if absf(landed - target_mm) / target_mm > 1e-5:
		wrong.append("drag to %.4f mm landed at %.4f mm" % [target_mm, landed])
	# The station's RADIUS must not move: dragging sideways past a neighbour is the invariant
	# `PlanformEdits` refuses, and the canvas must not be the thing that does it.
	if float(PlanformEdits.points(room.document.chord)[index][0]) != r_frac:
		wrong.append("the drag moved the station's radius")

	room.free()
	return TestResult.new(
		"[P10d] a station dragged to a pixel takes the chord that pixel means, at its own radius",
		wrong.is_empty(),
		"4 round trips and a drag to %.4f mm at r/R %.3f" % [target_mm, r_frac]
			if wrong.is_empty() else "; ".join(wrong))


## §3.1's caveat, and the room's reason for existing: a planform a builder has DRAWN is not the
## generator's assumption any more, and every figure derived from it must stop saying so.
##
## The check asserts the flag is set on the way in, or it would pass on a document that never
## carried the caveat at all.
static func _test_an_edit_clears_the_assumed_chord_caveat() -> TestResult:
	var room := _room()
	var assumed_before := room.document.chord_is_assumed
	room.editor.drag_station_to(10, room.editor.to_pixels(0.5, 6.0))
	var assumed_after := room.document.chord_is_assumed
	room.free()

	return TestResult.new(
		"[P10d] a preset's planform stops being 'assumed' the moment a builder edits it",
		assumed_before and not assumed_after,
		"chord_is_assumed %s -> %s" % [assumed_before, assumed_after])


## The toggle says "Chord measured" and the flag says `chord_is_assumed`, so exactly one of the two
## is inverted and the inversion is a place to get it backwards. Both directions are driven.
static func _test_the_measured_toggle_reads_the_way_it_is_written() -> TestResult:
	var room := _room()
	room.document.chord_is_assumed = true

	room._on_assumed_toggled(true)
	var measured_on := room.document.chord_is_assumed
	room._on_assumed_toggled(false)
	var measured_off := room.document.chord_is_assumed
	room.free()

	return TestResult.new(
		"[P10d] 'Chord measured' ON means chord_is_assumed FALSE, and OFF means true",
		measured_on == false and measured_off == true,
		"on -> assumed %s, off -> assumed %s" % [measured_on, measured_off])


# ---------------------------------------------------------------------------
# The coupling the slice is FOR
# ---------------------------------------------------------------------------

## THE CHECK THIS ROOM EXISTS TO PASS. A builder narrows the blade; the blade in Lab must narrow.
##
## Before P10d it did not: `PropellerMesh` held its own copy of the chord law, so an edit moved the
## physics and left the picture alone. This drives the room's own editor — one drag per station,
## the real gesture repeated — then builds a mesh from the room's own document and reads the chord
## back out of the generated vertices. The far end of the wire, not the near end.
##
## **The edit is the WHOLE planform and not one station, and that is a correction the first version
## of this test needed.** The mesh samples 14 stations against the document's 40, so a spike at one
## document station falls between two mesh stations and is invisible in the geometry — a correct
## mesh reading a correctly edited document would have failed. Sampling density is not the thing
## under test, so the edit is one the mesh can resolve: every station scaled, which is what
## "the blade is narrower than the catalog says" actually looks like.
static func _test_an_edit_in_the_room_reaches_the_3d_blade() -> TestResult:
	var room := _room()
	var factor := 0.4
	var before := room.document.chord.duplicate()

	for index in PlanformEdits.station_count(before):
		var station: Array = PlanformEdits.points(before)[index]
		room.editor.drag_station_to(index,
			room.editor.to_pixels(float(station[0]), float(station[1]) * factor))

	var mesh := PropellerMesh.new()
	mesh.rebuild(room._as_catalog_prop(), room.document)

	var checked := 0
	var worst := 0.0
	var worst_where := ""
	var moved := 0.0
	for sample in [0.3, 0.5, 0.7, 0.9]:
		var want := room.document.chord_at(float(sample))
		var drawn := _mesh_chord_mm_at(mesh, float(sample))
		var unedited := want / factor
		moved = maxf(moved, absf(unedited - want))
		checked += 1
		var error := absf(drawn - want)
		if error > worst:
			worst = error
			worst_where = "r/R %.2f: drew %.3f mm, document says %.3f mm (unedited would be %.3f)" % [
				sample, drawn, want, unedited]
	mesh.free()
	room.free()

	return TestResult.new(
		"[P10d] a planform edited in the room is the planform the 3D blade is built from",
		checked == 4 and moved > 1.0 and worst < 0.05,
		"every station scaled to %.0f%%; %d radii checked, worst %.4f mm against an edit of up to %.3f mm — %s" % [
			factor * 100.0, checked, worst, moved, worst_where])


## The chord the MESH drew at a fraction of radius, interpolated between its two nearest stations.
## The mesh samples 14 stations and the document 40, so an exact station match is not available and
## interpolating between the mesh's own is the honest read — the tolerance above is sized for it.
static func _mesh_chord_mm_at(mesh: PropellerMesh, r_frac: float) -> float:
	var blade := mesh.get_node("Blade_0") as MeshInstance3D
	var arrays: Array = (blade.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	var by_radius: Dictionary = {}
	for v in vertices:
		var key := "%.6f" % v.x
		if not by_radius.has(key):
			by_radius[key] = {"radius": v.x, "points": []}
		by_radius[key]["points"].append(Vector2(v.z, v.y))

	var stations: Array = []
	for key in by_radius:
		stations.append(by_radius[key])
	stations.sort_custom(func(a, b): return float(a["radius"]) < float(b["radius"]))

	var target := r_frac * mesh.radius_m
	var previous: Dictionary = {}
	for station in stations:
		var radius: float = station["radius"]
		if radius >= target and not previous.is_empty():
			var lo: float = previous["radius"]
			var t: float = (target - lo) / maxf(radius - lo, 1e-12)
			return lerpf(_station_chord_mm(previous["points"]),
				_station_chord_mm(station["points"]), t)
		previous = station
	return _station_chord_mm(stations[stations.size() - 1]["points"]) if not stations.is_empty() \
		else 0.0


## One station's chord in millimetres: the extent of its four corners along their MAJOR principal
## axis, which for a thin rectangle is the chord line exactly. Not the diagonal.
static func _station_chord_mm(points: Array) -> float:
	var mean := Vector2.ZERO
	for p in points:
		mean += p
	mean /= float(points.size())
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in points:
		var d: Vector2 = (p as Vector2) - mean
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var theta := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var axis := Vector2(cos(theta), sin(theta))
	var lo := INF
	var hi := -INF
	for p in points:
		var t: float = (p as Vector2).dot(axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return (hi - lo) * 1000.0


# ---------------------------------------------------------------------------
# The section view
# ---------------------------------------------------------------------------

## The section drawn and the section BUILT are one shape, corner for corner and in the same order.
##
## Order matters and is asserted rather than sorted away: the mesh stitches consecutive stations
## into faces by index, so a section whose corners are correct but permuted on ONE side is a
## drawing that agrees about the shape and disagrees about which edge is which. Comparing after a
## sort would pass on exactly that.
##
## **What this check CANNOT catch, measured rather than assumed:** a sign flip inside
## `section_corners_mm` itself. Both sides read that one function, so flipping the face normal
## flips the mesh and the drawing together and every assertion here still holds — verified by
## making that mutation and watching all ten checks pass. That is the price of the shared
## definition P10d exists to create, and the fault it hides is real: reversing the face vector
## reverses every generated normal and turns the blade inside out. It is caught one file over, by
## `test_propeller_mesh.gd`'s outward-normals check, which is where a claim about winding belongs.
##
## The comparison is done in the view's own pixels against the mesh's own metres, through the
## view's published scale, so it tests the mapping too rather than only the geometry. Verified by
## dropping the view's Y flip: the drawn corners land 35 px from the mesh's and the check fires.
static func _test_the_section_view_draws_the_meshs_own_section() -> TestResult:
	var room := _room()
	var document := room.document
	var r_frac := 0.7
	room.section.set_r_frac(r_frac)

	var mesh := PropellerMesh.new()
	mesh.rebuild(room._as_catalog_prop(), document)
	var target := r_frac * mesh.radius_m

	# The mesh station nearest the caret, and its four corners relative to that station's own
	# centre — which is what the section view draws about the middle of its canvas.
	var blade := mesh.get_node("Blade_0") as MeshInstance3D
	var arrays: Array = (blade.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var best_radius := 0.0
	var best_error := INF
	for v in vertices:
		if absf(v.x - target) < best_error:
			best_error = absf(v.x - target)
			best_radius = v.x
	var mesh_corners: Array = []
	for v in vertices:
		if is_equal_approx(v.x, best_radius):
			mesh_corners.append(Vector2(v.z, v.y))

	room.section.set_r_frac(best_radius / mesh.radius_m)
	var drawn := room.section.corner_pixels()
	var centre := room.section.size * 0.5
	var px_per_mm := room.section.scale_px_per_mm()

	var wrong: Array = []
	if drawn.size() != 4 or mesh_corners.size() != 4:
		wrong.append("%d drawn corners against %d mesh corners" % [
			drawn.size(), mesh_corners.size()])
	else:
		for i in 4:
			# Mesh metres to view pixels: millimetres, then the view's scale, then Y down.
			var from_mesh: Vector2 = Vector2((mesh_corners[i] as Vector2).x,
				-(mesh_corners[i] as Vector2).y) * 1000.0 * px_per_mm + centre
			if from_mesh.distance_to(drawn[i]) > 0.01:
				wrong.append("corner %d: drawn %s, mesh %s" % [i, drawn[i], from_mesh])

	mesh.free()
	room.free()
	return TestResult.new(
		"[P10d] the section view draws the mesh's own four corners, in the mesh's own order",
		wrong.is_empty(),
		"4 corners agree at r/R %.4f, scale %.3f px/mm" % [best_radius, px_per_mm]
			if wrong.is_empty() else "; ".join(wrong))


# ---------------------------------------------------------------------------
# The mount stack profile
# ---------------------------------------------------------------------------

## One number, two places. The profile is a side elevation of the cylinders `MotorMesh` generated,
## so its total height IS the mesh's `total_height_m` — and a profile that re-derived the stack
## from `MotorMesh.dimensions()` would agree today and drift the first time the stack gained a
## part. The part count is asserted alongside, because a profile that drew NOTHING would report a
## height of zero against a mesh whose height is also read as zero if the mesh failed to build.
##
## The bound is RELATIVE and sits at the float32 floor rather than at bit-equality, and the reason
## is the mechanism: `Node3D.position` is single precision, so a height read back off a built
## cylinder has been through float32 while `total_height_m` is a float64 sum. That is a property of
## reading the geometry — which is the thing being asserted — and not a slack tolerance.
static func _test_the_profile_height_is_the_motor_meshs_own() -> TestResult:
	var room := _room()
	room._on_pad_changed(0.002)
	var parts := room.profile.parts()
	var drawn := room.profile.drawn_height_m()
	var model := room.profile.motor_mesh.total_height_m if room.profile.motor_mesh != null else -1.0

	# And the rectangles must be ordered the way the stack is: the pad at the bottom, the nut on
	# top. A `parts()` that returned them unsorted would still total correctly.
	var names: Array = []
	for part in parts:
		names.append(str(part["name"]))

	var pad_first: bool = not names.is_empty() and str(names[0]) == "SoftMount"
	room.free()

	return TestResult.new(
		"[P10d] the mount profile's height is the motor mesh's own, and the pad is at the bottom",
		parts.size() >= 5 and model > 0.0 and absf(drawn - model) / model < 1e-6 and pad_first,
		"%d parts %s; drawn %.9f m against the mesh's %.9f m (relative %.12f)" % [
			parts.size(), names, drawn, model, absf(drawn - model) / maxf(model, 1e-12)])


## The plan's own proof for this view: a pad swap must move BOTH the picture and `f_n`. Either
## alone is satisfiable by a wrong implementation — a profile that drew a pad it did not model, or
## a frequency that changed while the drawing stayed put.
##
## The direction is asserted, not just the difference: a thicker pad is a SOFTER spring (k = EA/t),
## so its frequency must FALL. A check on inequality alone would pass on a sign error.
static func _test_a_pad_moves_both_the_picture_and_the_frequency() -> TestResult:
	var room := _room()

	room._on_pad_changed(0.001)
	var thin_rect := _pad_rect(room)
	var thin_hz := room.profile.mount_f_n_hz

	room._on_pad_changed(0.003)
	var thick_rect := _pad_rect(room)
	var thick_hz := room.profile.mount_f_n_hz

	room._on_pad_changed(0.0)
	var bare_pads := 0
	for part in room.profile.parts():
		if str(part["name"]) == "SoftMount":
			bare_pads += 1
	var bare_hz := room.profile.mount_f_n_hz
	room.free()

	var grew := thick_rect.size.y > thin_rect.size.y * 1.5
	var fell := is_finite(thin_hz) and is_finite(thick_hz) and thick_hz < thin_hz
	return TestResult.new(
		"[P10d] a thicker pad draws taller AND drops the mount frequency, and no pad draws none",
		grew and fell and bare_pads == 0 and not is_finite(bare_hz),
		"1 mm: %.1f px / %.0f Hz -> 3 mm: %.1f px / %.0f Hz; bare: %d pad rects, f_n %s" % [
			thin_rect.size.y, thin_hz, thick_rect.size.y, thick_hz, bare_pads, bare_hz])


static func _pad_rect(room: PropulsionWorkbench) -> Rect2:
	for part in room.profile.parts():
		if str(part["name"]) == "SoftMount":
			return room.profile.part_rect(part)
	return Rect2()


## Moving the caret changes where the room is LOOKING and nothing about the blade. Wiring it to
## the refresh is the obvious mistake and it costs a mesh rebuild and a mount solve on every mouse
## motion of a hover — the same class of waste `FramePlanEditor.view_changed` exists to avoid.
##
## Asserted through OBJECT IDENTITY and not through the numbers, and the difference is the whole
## check. `MotorMesh.rebuild` frees its children and builds new ones, so a spurious rebuild
## produces a stack that is identical in every dimension and made of different nodes — measured:
## with `_refresh()` wired into the caret handler, a value-by-value comparison of the part list
## passes and reports nothing. The instance ids are what move. The section is required to have
## followed the caret in the same check, so the caret is proven to have done its own job rather
## than to have done nothing at all.
static func _test_moving_the_caret_rebuilds_nothing() -> TestResult:
	var room := _room()
	room._on_pad_changed(0.002)
	var before := room.profile.parts()
	var section_before := room.section.r_frac

	room.editor.set_caret(0.42)
	var after := room.profile.parts()

	var moved := not is_equal_approx(room.section.r_frac, section_before) \
		and is_equal_approx(room.section.r_frac, 0.42)

	var same := before.size() == after.size() and before.size() > 0
	if same:
		for i in before.size():
			var a: Dictionary = before[i]
			var b: Dictionary = after[i]
			if a["id"] != b["id"]:
				same = false
				break
	room.free()

	return TestResult.new(
		"[P10d] moving the caret moves the section and leaves the mount stack untouched",
		moved and same,
		"section r/R %.2f -> %.2f; %d stack parts, unchanged: %s" % [
			section_before, 0.42, after.size(), same])


# ---------------------------------------------------------------------------
# The door
# ---------------------------------------------------------------------------

## The room needs a way in, and the way in is a button on the Prop inspector — `room_menu.gd`'s own
## stated arrangement, a workspace reached from the system it works on.
##
## **Two halves, and only one of them can be checked here.** The panel's half is: the button exists,
## it carries the propeller the panel is RENDERING, and pressing it opens nothing — it emits and
## lets the shell decide, which is the rule every other control in this UI follows. That is what
## this check drives, and the identity of the emitted record is the load-bearing part: a button that
## emitted a hardcoded default would open the room on the wrong blade and look entirely correct
## doing it.
##
## The shell's half — that the signal opens the overlay, switches the 3D world off, and that walking
## to another system closes it — cannot be checked in this harness. `GlassShell` wires itself in
## `_ready()`, which needs a tree, a rendered frame and a real catalog, and `run_tests.gd` processes
## no frames by design; `test_glass_shell.gd` says the same about itself and tests a static function
## for exactly this reason. It is covered by driving the real shell with frames, through
## `tests/capture_glass_shell.gd`.
static func _test_the_prop_panel_carries_the_door_and_opens_nothing_itself() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var panel := PropellerDetails.new()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, Build.DEFAULT_COMPONENT_IDS)

	# A propeller that is NOT the reference build's own, so "it emitted the right record" cannot be
	# satisfied by a default.
	var shown := "prop_7x35x2"
	panel.render(catalog.get_part(shown), build)

	var emitted: Array = []
	panel.design_blade_requested.connect(func(prop: Dictionary) -> void: emitted.append(prop))

	var buttons: Array = []
	for child in panel.find_children("*", "Button", true, false):
		if str((child as Button).text).begins_with("Design"):
			buttons.append(child)
	for button in buttons:
		(button as Button).pressed.emit()

	var emitted_id := str((emitted[0] as Dictionary).get("part_id", "")) if not emitted.is_empty() \
		else ""
	panel.free()

	return TestResult.new(
		"[P10d] the Prop panel carries the door to the room, and emits the blade it is showing",
		buttons.size() == 1 and emitted.size() == 1 and emitted_id == shown
			and shown != ReferenceBuild.PROPELLER_ID,
		"%d button(s), %d emission(s), carried %s while the build fits %s" % [
			buttons.size(), emitted.size(), emitted_id, ReferenceBuild.PROPELLER_ID])
