class_name TestFramePlanEditor
extends RefCounted
## The plan canvas — airframe.md §7.1: the view a frame is actually drawn in.
##
## ## What is testable here, and what is not
##
## The arithmetic of every edit is `test_frame_edits.gd`'s job and is not repeated. What this suite
## covers is the layer above it, which has its own failure modes and none of them are visible in a
## screenshot:
##
##   - **The transform round trip.** Screen to millimetres and back has to be exact, or a dragged
##     vertex lands slightly off where the cursor is and the error accumulates over a drag.
##   - **Hit testing.** The vertex you can see must be the vertex you grab, including when plates
##     overlap — which they always do at the centre of a frame, where four arms meet two plates.
##   - **What a gesture MEANS.** Press on a vertex is a vertex drag; press on a plate is a plate
##     drag; press on nothing is a pan and a deselect. Getting these confused is how a canvas
##     silently moves a whole plate when the builder meant to nudge one corner.
##   - **Symmetry.** With it on, dragging one arm has to move all four to the ROTATED positions, or
##     the frame stops being a quad while still looking like one.
##
## Input is fed in as synthesised `InputEvent`s through `_gui_input`, which is the same entry point
## a real click arrives on. Nothing here reads a pixel: the assertions are about the document that
## comes out the other side.
##
## ## MUTATION NOTES
##
##   - `_test_the_topmost_plate_is_the_one_you_grab` fails if hit testing walks the plates forwards
##     instead of backwards. Drawing order and hit order must be opposites, and at the centre of
##     every frame there are six overlapping plates to get it wrong on.
##   - `_test_symmetry_moves_every_arm_to_its_rotated_place` fails if the counterpart vertex is
##     found by index alone rather than by rotation — which looks right on a frame whose arms were
##     just replicated and mangles one that has been edited since.
##   - `_test_a_whole_drag_is_one_undo` fails if the history snapshot is taken per motion event
##     rather than once on press: undo then walks back along the path the mouse took, one pixel at
##     a time.

const EPS := 1.0e-9


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_transform_round_trips())
	results.append(_test_zoom_keeps_the_point_under_the_cursor())
	results.append(_test_fitting_an_empty_frame_does_not_blow_up_the_scale())
	results.append(_test_the_grid_stays_legible_at_every_zoom())
	results.append(_test_clicking_a_vertex_selects_and_drags_it())
	results.append(_test_the_topmost_plate_is_the_one_you_grab())
	results.append(_test_clicking_empty_space_deselects())
	results.append(_test_symmetry_moves_every_arm_to_its_rotated_place())
	results.append(_test_symmetry_off_moves_only_the_arm_you_dragged())
	results.append(_test_a_whole_drag_is_one_undo())
	return results


# ---------------------------------------------------------------------------
# The transform
# ---------------------------------------------------------------------------

## Exact both ways, to the precision the screen itself has.
##
## THE BOUND IS 1e-4 mm HERE AND 1e-9 mm IN `test_arm_profile.gd`, and the difference between those
## two is worth stating because it looks like one of them is sloppy. `Vector2` is 32-bit, so any
## number that passes through a screen position carries about 1e-5 mm of noise on a 300 mm frame.
##
## In `ArmProfile` that noise is fatal: it decides whether a perpendicular finds the vertex it
## passes through, which is a DISCRETE outcome — two crossings or none, an arm measured or an arm
## refused — so the measurement reads the document's doubles and never a point.
##
## Here it is 20 nanometres of cursor position. It is four orders of magnitude below the 0.5 mm snap
## grid, six below anything a router cuts, and it changes no decision at all. Demanding 1e-9 of a
## mouse would mean carrying a doubles copy of the view transform to make a drag land on a vertex
## nobody could tell from the one beside it.
static func _test_the_transform_round_trips() -> TestResult:
	var transform := PlanTransform.make(Vector2(640.0, 360.0), 3.25)
	var worst := 0.0
	for point in [Vector2.ZERO, Vector2(110.0, -55.0), Vector2(-233.7, 91.4), Vector2(0.5, 0.5)]:
		var back := transform.to_mm(transform.to_pixels(point))
		worst = maxf(worst, back.distance_to(point))
	return TestResult.new(
		"screen and millimetres convert back and forth to the precision the screen has",
		worst < 1.0e-4,
		"worst round-trip error %.12f mm" % worst)


## Zoom about the cursor, not about the centre. The geometry under the pointer must not move, or
## looking closer at something slides it away from you.
##
## MUTATION: zoom about `size * 0.5` and the anchor moves by tens of pixels here.
static func _test_zoom_keeps_the_point_under_the_cursor() -> TestResult:
	var transform := PlanTransform.make(Vector2(100.0, 100.0), 2.0)
	var anchor := Vector2(430.0, 260.0)
	var before := transform.to_mm(anchor)
	transform.zoom_at(anchor, 1.15)
	transform.zoom_at(anchor, 1.15)
	transform.zoom_at(anchor, 1.0 / 1.15)
	var after := transform.to_mm(anchor)
	return TestResult.new(
		"zooming holds the point under the cursor still",
		before.distance_to(after) < 1.0e-6,
		"%s -> %s at %.3f px/mm" % [before, after, transform.scale_px_per_mm])


## An empty frame has no bounding box. Fitting to it must not send the scale to its limit and drop
## the builder into a blank view at 60 px/mm.
static func _test_fitting_an_empty_frame_does_not_blow_up_the_scale() -> TestResult:
	var editor := FramePlanEditor.new()
	editor.size = Vector2(800.0, 600.0)
	editor.open(FrameEdits.new_frame("empty"))
	editor.fit_to_document()
	var scale := editor.transform.scale_px_per_mm
	# The 200 mm default box in an 800 x 600 view: roughly 2.6 px/mm, and certainly not the ceiling.
	var sane := scale > 0.5 and scale < 10.0
	var origin := editor.transform.to_pixels(Vector2.ZERO)
	var centred := origin.distance_to(Vector2(400.0, 300.0)) < 1.0
	editor.free()
	return TestResult.new(
		"fitting an empty frame gives a usable scale centred on the origin",
		sane and centred,
		"%.3f px/mm, origin at %s" % [scale, origin])


## The grid has to stay readable from a whole 10" frame down to a single bolt hole, so its step is
## chosen from the zoom. Asserted as a PROPERTY — every step is at least the minimum spacing and no
## more than ten times it — rather than against a table of expected steps, which would just be the
## implementation written twice.
static func _test_the_grid_stays_legible_at_every_zoom() -> TestResult:
	var wrong: Array[String] = []
	for scale_value in [0.08, 0.5, 1.0, 2.5, 7.0, 20.0, 55.0]:
		var scale := float(scale_value)
		var transform := PlanTransform.make(Vector2.ZERO, scale)
		var step := transform.grid_step_mm(12.0)
		var pixels := step * scale
		if pixels < 12.0 or pixels > 120.0:
			wrong.append("%.2f px/mm -> %.3f mm (%.1f px)" % [scale, step, pixels])
	return TestResult.new(
		"the grid step keeps grid lines between 12 and 120 pixels apart at any zoom",
		wrong.is_empty(),
		"none wrong" if wrong.is_empty() else ", ".join(wrong))


# ---------------------------------------------------------------------------
# Gestures
# ---------------------------------------------------------------------------

## The core interaction: press on a corner, move, release, and the plate is a different shape — and
## its mass has changed, because §0's rule is that they are the same polygon.
static func _test_clicking_a_vertex_selects_and_drags_it() -> TestResult:
	var editor := _editor_with_a_square()
	var materials := FrameMaterials.load_default()
	var before := AirframeProperties.compute(editor.document, materials).total_mass_g()

	# The square is 40 x 40 centred on the origin; grab its (20, -20) corner and pull it to (60,-20).
	var corner := editor.transform.to_pixels(Vector2(20.0, -20.0))
	_press(editor, corner)
	_move(editor, editor.transform.to_pixels(Vector2(60.0, -20.0)))
	_release(editor, editor.transform.to_pixels(Vector2(60.0, -20.0)))

	var after := AirframeProperties.compute(editor.document, materials).total_mass_g()
	var moved := AirframeDocument.plate_outline(editor.document.plates[0])[1]
	var selected := editor.selected_plate
	editor.free()
	return TestResult.new(
		"pressing a vertex selects its plate and dragging moves it, and the mass follows",
		selected == 0 and moved.distance_to(Vector2(60.0, -20.0)) < 0.01 and after > before * 1.4,
		"vertex at %s, %.3f g -> %.3f g, selected %d" % [moved, before, after, selected])


## Plates overlap wherever a frame is interesting — four arms and two plates all meet at the origin.
## The one drawn last is the one on top, so it must be the one a click finds.
static func _test_the_topmost_plate_is_the_one_you_grab() -> TestResult:
	var editor := FramePlanEditor.new()
	editor.size = Vector2(800.0, 600.0)
	var document := FrameEdits.new_frame("stack")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 80.0, 80.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	FrameEdits.add_rectangle(document, Vector2.ZERO, 30.0, 30.0, 2.0, 10.0,
		AirframeDocument.ROLE_TOP)
	editor.open(document)
	editor.fit_to_document()

	# Dead centre: inside both plates. The later one wins.
	_press(editor, editor.transform.to_pixels(Vector2.ZERO))
	var picked := editor.selected_plate
	_release(editor, editor.transform.to_pixels(Vector2.ZERO))
	editor.free()
	return TestResult.new(
		"a click in overlapping plates picks the topmost one",
		picked == 1,
		"picked plate %d of 2" % picked)


## Pressing empty space clears the selection and starts a pan, rather than doing nothing or dragging
## whatever happened to be selected before.
static func _test_clicking_empty_space_deselects() -> TestResult:
	var editor := _editor_with_a_square()
	_press(editor, editor.transform.to_pixels(Vector2(20.0, -20.0)))
	_release(editor, editor.transform.to_pixels(Vector2(20.0, -20.0)))
	var selected_first := editor.selected_plate

	var empty := editor.transform.to_pixels(Vector2(500.0, 500.0))
	var origin_before := editor.transform.origin_px
	_press(editor, empty)
	_move(editor, empty + Vector2(40.0, 20.0))
	var panned := editor.transform.origin_px - origin_before
	_release(editor, empty + Vector2(40.0, 20.0))
	var selected_after := editor.selected_plate
	editor.free()
	return TestResult.new(
		"pressing empty space deselects and pans instead of editing",
		selected_first == 0 and selected_after == -1
			and panned.distance_to(Vector2(40.0, 20.0)) < 0.01,
		"selected %d -> %d, panned by %s" % [selected_first, selected_after, panned])


## §7.1's "edit one arm, get four". The other three arms must land on the ROTATED position, which is
## what keeps a quad a quad — asserted through the inertia tensor, because four arms that merely
## look symmetric but are not would show up there and nowhere else.
static func _test_symmetry_moves_every_arm_to_its_rotated_place() -> TestResult:
	var editor := _editor_with_four_arms()
	editor.symmetric_arms = true
	var materials := FrameMaterials.load_default()

	# Vertex 1 of arm 0 is its tip corner. Drag it outward along the arm.
	var arm: Dictionary = editor.document.plates[0]
	var vertex := AirframeDocument.plate_outline(arm)[1]
	var target := vertex * 1.25
	_press(editor, editor.transform.to_pixels(vertex))
	_move(editor, editor.transform.to_pixels(target))
	_release(editor, editor.transform.to_pixels(target))

	var props := AirframeProperties.compute(editor.document, materials)
	# A symmetric X has equal roll and pitch inertia. If only one arm moved, it does not.
	var balanced := absf(props.roll_inertia_kg_m2() - props.pitch_inertia_kg_m2()) \
		< props.roll_inertia_kg_m2() * 1.0e-6
	# And every arm must still be measurable: a counterpart moved to the wrong place drags its
	# outline off its own centreline.
	var measurable := _all_arms_measurable(editor.document)
	editor.free()
	return TestResult.new(
		"with symmetry on, dragging one arm moves all four to their rotated places",
		balanced and measurable,
		"roll %.9f vs pitch %.9f, all measurable: %s" % [
			props.roll_inertia_kg_m2(), props.pitch_inertia_kg_m2(), measurable])


## And with symmetry off, exactly one arm moves — the frame becomes asymmetric, which is a thing a
## builder is allowed to want (§7.1 warns, never blocks).
static func _test_symmetry_off_moves_only_the_arm_you_dragged() -> TestResult:
	var editor := _editor_with_four_arms()
	editor.symmetric_arms = false
	var materials := FrameMaterials.load_default()

	var vertex := AirframeDocument.plate_outline(editor.document.plates[0])[1]
	var target := vertex * 1.5
	_press(editor, editor.transform.to_pixels(vertex))
	_move(editor, editor.transform.to_pixels(target))
	_release(editor, editor.transform.to_pixels(target))

	var props := AirframeProperties.compute(editor.document, materials)
	var off_axis := Vector2(props.cg_m.x, props.cg_m.z).length() * 1000.0
	var second := AirframeDocument.plate_outline(editor.document.plates[1])[1]
	var second_moved := second.distance_to(
		AirframeDocument.plate_outline(_four_arm_document().plates[1])[1]) > 0.01
	editor.free()
	return TestResult.new(
		"with symmetry off, only the dragged arm moves and the frame goes off-centre",
		off_axis > 0.5 and not second_moved,
		"CG %.2f mm off axis, other arm moved: %s" % [off_axis, second_moved])


## A drag is ONE edit. Undo must return to where the vertex started, not to the previous mouse
## position — the difference is invisible until you try to undo a drag and it takes forty presses.
static func _test_a_whole_drag_is_one_undo() -> TestResult:
	var editor := _editor_with_a_square()
	var start := AirframeDocument.plate_outline(editor.document.plates[0])[1]

	_press(editor, editor.transform.to_pixels(start))
	# Several motion events, as a real drag produces.
	for step in 6:
		_move(editor, editor.transform.to_pixels(start + Vector2(5.0 * float(step + 1), 0.0)))
	_release(editor, editor.transform.to_pixels(start + Vector2(30.0, 0.0)))

	var dragged := AirframeDocument.plate_outline(editor.document.plates[0])[1]
	var depth := editor.history.depth()
	editor.undo()
	var restored := AirframeDocument.plate_outline(editor.document.plates[0])[1]
	var can_undo_again := editor.history.can_undo()
	editor.free()
	return TestResult.new(
		"a drag records one undo step, and undoing it returns the vertex to where it started",
		depth == 1 and dragged.distance_to(start) > 25.0
			and restored.distance_to(start) < 0.01 and not can_undo_again,
		"%d history entries; %s -> %s -> %s" % [depth, start, dragged, restored])


# ---------------------------------------------------------------------------
# Fixtures and input
# ---------------------------------------------------------------------------

static func _editor_with_a_square() -> FramePlanEditor:
	var editor := FramePlanEditor.new()
	editor.size = Vector2(800.0, 600.0)
	var document := FrameEdits.new_frame("square")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	editor.open(document)
	editor.fit_to_document()
	# Snapping off: these tests are about where a drag PUTS a vertex, and a grid would quantise the
	# answer and make an off-by-a-little bug pass.
	editor.snap_mm = 0.0
	return editor


static func _four_arm_document() -> AirframeDocument:
	var document := FrameEdits.new_frame("quad")
	FrameEdits.add_arm(document, 45.0, 100.0, 12.0, 12.0, 5.0)
	FrameEdits.replicate_radially(document, 0, 4)
	return document


static func _editor_with_four_arms() -> FramePlanEditor:
	var editor := FramePlanEditor.new()
	editor.size = Vector2(800.0, 600.0)
	editor.open(_four_arm_document())
	editor.fit_to_document()
	editor.snap_mm = 0.0
	return editor


static func _all_arms_measurable(document: AirframeDocument) -> bool:
	for plate in document.plates:
		if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
			continue
		var root := AirframeDocument.point_of(plate.get("root_point", [0.0, 0.0]))
		var tip := AirframeDocument.point_of(plate.get("tip_point", [0.0, 0.0]))
		var profile := ArmProfile.measure_flat(
			plate.get("outline", PackedFloat64Array()), root.x, root.y, tip.x, tip.y)
		if not profile["errors"].is_empty():
			return false
	return true


static func _press(editor: FramePlanEditor, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	editor._gui_input(event)


static func _move(editor: FramePlanEditor, to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	editor._gui_input(event)


static func _release(editor: FramePlanEditor, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	editor._gui_input(event)
