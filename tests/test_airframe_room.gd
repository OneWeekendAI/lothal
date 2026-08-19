class_name TestAirframeRoom
extends RefCounted
## The Airframe room as a room: the shelf you start from, the controls that dimension a frame, the
## numbers strip under the canvas, and the wiring that keeps the four in step.
##
## ## Why this is testable at all
##
## Because nothing in the room computes geometry. A control reads a number out of the document and
## writes one back through `FrameEdits`, which is pure; the shelf emits an id; the drawer reads
## `AirframeProperties`. What is left to test is the WIRING — that the slider is connected to the
## edit somebody thinks it is, that a repopulate does not look like an edit, that a selection
## reaches the panel that acts on it — and every one of those is a fault that leaves the screen
## looking completely normal.
##
## ## MUTATION NOTES
##
##   - `_test_showing_a_frame_is_not_an_edit` fails if the `_syncing` guard goes. Without it,
##     opening a frame pushes a dozen spurious entries onto the undo stack and the first Ctrl-Z
##     does nothing visible — the classic version of this bug, and invisible until somebody undoes.
##   - `_test_the_layout_controls_hide_once_a_frame_is_drawn` fails if the hand-edit tag is not
##     cleared. The arm-length slider would then still be live on a frame with a hand-drawn swept
##     front end, and one drag would silently regenerate it away.
##   - `_test_deleting_an_arm_takes_its_motor` fails if the motor is left behind: the aircraft then
##     has thrust applied at the end of an arm that does not exist, which every downstream
##     computation happily accepts.
##   - `_test_the_numbers_strip_follows_the_frame` fails if the drawer caches its properties — the
##     whole claim of the room is that the numbers move WHILE you drag.

static func run() -> Array:
	var results: Array = []
	results.append(_test_the_shelf_offers_every_layout_and_names_the_one_you_click())
	results.append(_test_showing_a_frame_is_not_an_edit())
	results.append(_test_an_arm_slider_re_cuts_the_arm())
	results.append(_test_the_layout_controls_hide_once_a_frame_is_drawn())
	results.append(_test_a_layout_slider_regenerates_the_frame())
	results.append(_test_the_numbers_strip_follows_the_frame())
	results.append(_test_choosing_a_layout_opens_it_in_the_room())
	results.append(_test_deleting_an_arm_takes_its_motor())
	results.append(_test_mirroring_repeats_as_many_ways_as_the_layout_has_arms())
	return results


static func _materials() -> FrameMaterials:
	return FrameMaterials.load_default()


static func _mass_g(document: AirframeDocument) -> float:
	return AirframeProperties.compute(document, _materials()).total_mass_g()


## One chip per layout, and the chip emits the layout it draws. A shelf whose third chip opened the
## fourth layout would be a room where the picture and the button disagree, which is precisely the
## fault the diagrams exist to prevent.
static func _test_the_shelf_offers_every_layout_and_names_the_one_you_click() -> TestResult:
	var shelf := FrameLayoutShelf.new()
	# A one-element array rather than a local, because a lambda captures by value and reassigning
	# the capture would leave the outer variable empty — a test that then passes only when the
	# signal never fires.
	var chosen: Array = [""]
	shelf.layout_chosen.connect(func(id: String) -> void: chosen[0] = id)
	var chips: Array = []
	for child in shelf.get_children():
		_collect_buttons(child, chips)
	# The chips come first, before the saved-frame buttons, in `FrameLayouts.TEMPLATES` order.
	var wanted := FrameLayouts.ids()
	var third := chips[2] as Button if chips.size() > 2 else null
	if third != null:
		third.pressed.emit()
	shelf.free()
	return TestResult.new(
		"the shelf carries a chip per layout and each one opens the layout it draws",
		chips.size() >= wanted.size() and str(chosen[0]) == str(wanted[2]),
		"%d chips for %d layouts; the third emitted \"%s\" (wanted \"%s\")" % [
			chips.size(), wanted.size(), str(chosen[0]), wanted[2] if wanted.size() > 2 else ""])


## Pointing the controls at a frame writes a dozen values into a dozen controls, and every one of
## them fires the same `value_changed` a builder's typing does. Without the guard, opening a frame
## is indistinguishable from editing it.
static func _test_showing_a_frame_is_not_an_edit() -> TestResult:
	var controls := FrameControls.new()
	var counts: Array = [0, 0]
	controls.document_changed.connect(func(_document: AirframeDocument) -> void: counts[0] += 1)
	controls.edit_began.connect(func() -> void: counts[1] += 1)
	controls.show_document(FrameLayouts.build("hex_v"))
	controls.show_document(FrameLayouts.build("quad_x"), 0, 0)
	controls.free()
	return TestResult.new(
		"pointing the controls at a frame is not an edit and does not touch the undo stack",
		int(counts[0]) == 0 and int(counts[1]) == 0,
		"%d edits, %d undo snapshots from two opens" % [counts[0], counts[1]])


## The slider drives `FrameEdits.set_arm_geometry`, which re-cuts the plate AND moves the motor.
## Asserted through the consequences — the motor is at the new length and the mass went up —
## because a version that moved only the outline would leave the geometry and the thrust point
## describing two different aircraft.
static func _test_an_arm_slider_re_cuts_the_arm() -> TestResult:
	var controls := FrameControls.new()
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 100.0})
	var arm_index := _first_arm(document)
	var tip := AirframeDocument.point_of(document.plates[arm_index]["tip_point"])
	var before := _mass_g(document)
	var holes: int = (document.plates[arm_index]["holes"] as Array).size()

	controls.show_document(document, arm_index)
	var reported := FrameEdits.arm_geometry(document, arm_index)
	# Driven through the box the way a builder's typing does, so the test exercises the wiring
	# rather than calling the edit it is supposed to be checking.
	_type_into(controls, "arm_length", 160.0)
	var after_tip := AirframeDocument.point_of(document.plates[arm_index]["tip_point"])
	var moved_motor := false
	for motor in document.motors:
		if AirframeDocument.point_of(motor["position_mm"]).distance_to(after_tip) < 0.01:
			moved_motor = true
	var after := _mass_g(document)
	controls.free()
	return TestResult.new(
		"typing an arm length re-cuts the plate, carries its holes and takes the motor with it",
		absf(float(reported["length_mm"]) - 100.0) < 0.01
			and absf(after_tip.length() - 160.0) < 0.01 and moved_motor and after > before
			and (document.plates[arm_index]["holes"] as Array).size() == holes,
		"%.0f mm → %.0f mm, %.1f g → %.1f g, motor followed: %s, %d holes kept" % [
			tip.length(), after_tip.length(), before, after, moved_motor, holes])


## "Arm length" means something for four identical arms radiating from an origin and nothing at all
## for a frame somebody has drawn on. The controls therefore follow the document's own tag rather
## than remembering what was opened.
static func _test_the_layout_controls_hide_once_a_frame_is_drawn() -> TestResult:
	var controls := FrameControls.new()
	var document := FrameLayouts.build("hex_plus")
	controls.show_document(document)
	var shown_for_layout := controls.section_visible("layout")

	# What the workbench does when the canvas reports a hand edit.
	document.revision = "drawn"
	controls.show_document(document)
	var hidden_for_drawing := not controls.section_visible("layout")
	controls.free()
	return TestResult.new(
		"the layout sliders are live for a generated frame and gone once it has been drawn on",
		shown_for_layout and hidden_for_drawing,
		"generated: %s, drawn: %s" % [shown_for_layout, not hidden_for_drawing])


## The parametric half of the room, end to end: move one slider, get a different aircraft — same
## topology, same motor count, bigger.
static func _test_a_layout_slider_regenerates_the_frame() -> TestResult:
	var controls := FrameControls.new()
	var document := FrameLayouts.build("hex_v", {"arm_length_mm": 120.0})
	var motors := document.motors.size()
	var before := _mass_g(document)
	var edits: Array = [0]
	controls.document_changed.connect(func(_document: AirframeDocument) -> void: edits[0] += 1)
	controls.show_document(document)
	_type_into(controls, "arm_length_mm", 200.0)
	var reach := AirframeDocument.point_of(document.motors[0]["position_mm"]).length()
	var after := _mass_g(document)
	controls.free()
	return TestResult.new(
		"dragging the layout's arm length rebuilds the same topology at the new size",
		int(edits[0]) == 1 and document.motors.size() == motors and absf(reach - 200.0) < 0.01
			and after > before and FrameLayouts.layout_id_of(document) == "hex_v",
		"%d motors at %.0f mm, %.1f g → %.1f g, %d edit(s)" % [
			document.motors.size(), reach, before, after, edits[0]])


## The claim the whole room rests on: change the frame and the numbers move, because they are
## integrals of the polygon that changed.
static func _test_the_numbers_strip_follows_the_frame() -> TestResult:
	var drawer := FrameNumbersDrawer.new()
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 110.0})
	drawer.show_document(document)
	var light := drawer.summary_text()
	FrameLayouts.apply_layout(document, FrameLayouts.template("quad_x"),
		FrameLayouts.params({"arm_length_mm": 220.0, "arm_thickness_mm": 6.0}))
	drawer.show_document(document)
	var heavy := drawer.summary_text()
	drawer.free()
	return TestResult.new(
		"the numbers strip repaints from the frame rather than caching what it first saw",
		light != heavy and light.contains("g") and heavy.contains("g"),
		"%s   →   %s" % [light, heavy])


## Clicking a chip opens that layout in the canvas, the controls and the numbers at once — the one
## place a room with four listeners can leave one of them pointed at the previous frame.
static func _test_choosing_a_layout_opens_it_in_the_room() -> TestResult:
	var workbench := FrameWorkbench.new(PartsCatalog.load_default())
	workbench.shelf.layout_chosen.emit("oct_x")
	var document := workbench.editor.document
	var controls_agree := workbench.controls.document == document
	var motors := document.motors.size()
	var numbers_agree := workbench.numbers.summary_text().contains("g")
	var still_a_layout := FrameLayouts.layout_id_of(document) == "oct_x"
	workbench.free()
	return TestResult.new(
		"clicking a layout chip opens it in the canvas, the controls and the numbers together",
		motors == 8 and controls_agree and numbers_agree and still_a_layout,
		"%d motors, controls agree: %s, numbers: %s" % [motors, controls_agree, numbers_agree])


## An arm and its motor are one thing to a builder. Deleting the plate and leaving the motor gives
## a frame that still yaws, still mixes and applies a quarter of its thrust to empty air.
static func _test_deleting_an_arm_takes_its_motor() -> TestResult:
	var workbench := FrameWorkbench.new(PartsCatalog.load_default())
	workbench.shelf.layout_chosen.emit("quad_x")
	var document := workbench.editor.document
	var motors := document.motors.size()
	workbench.editor.selection_changed.emit(_first_arm(document))
	workbench._on_delete()
	var left := document.motors.size()
	workbench.free()
	return TestResult.new(
		"deleting an arm deletes the motor that stood on it",
		motors == 4 and left == 3,
		"%d motors before, %d after" % [motors, left])


## "Mirror ×4" on a hexacopter produced a six-arm frame with four arms in it — a shape nothing
## warns about, because every individual part of it is fine.
static func _test_mirroring_repeats_as_many_ways_as_the_layout_has_arms() -> TestResult:
	var workbench := FrameWorkbench.new(PartsCatalog.load_default())
	workbench.shelf.layout_chosen.emit("hex_plus")
	var document := workbench.editor.document
	# One arm on its own, then mirrored: the frame is rebuilt to a single arm first so the count
	# after mirroring is the count the button chose rather than the count it started with.
	var arm: Dictionary = (document.plates[_first_arm(document)] as Dictionary).duplicate(true)
	document.plates.clear()
	document.motors.clear()
	document.plates.append(arm)
	document.motors.append({
		"position_mm": arm["tip_point"], "z_mm": 5.0, "spin": 1.0, "tilt_deg": 0.0})
	workbench.editor.selection_changed.emit(0)
	workbench._on_replicate()
	var arms := 0
	for plate in document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			arms += 1
	workbench.free()
	return TestResult.new(
		"mirroring repeats an arm as many ways as the open layout has arms, not always four",
		arms == 6 and document.motors.size() == 6,
		"%d arms, %d motors after mirroring a hex's single arm" % [arms, document.motors.size()])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Types a number into one of the column's boxes, the way a builder does.
##
## THE EMIT IS NOT A SHORTCUT PAST THE WIRING — it is a stand-in for the engine, and only for the
## engine. A `Range` outside the scene tree accepts a new `value` and does not notify, so a detached
## SpinBox changes its display and calls nothing. Everything from `value_changed` onwards is the
## room's own code and is exercised exactly as it runs: the box's handler, the `_syncing` guard,
## the `FrameEdits` call, the emitted signal. Building a whole window per test to get Godot to fire
## one signal would test Godot instead.
static func _type_into(controls: FrameControls, key: String, value: float) -> void:
	controls.set_field(key, value)
	var box := controls.field_box(key)
	if box != null and not box.is_inside_tree():
		box.value_changed.emit(box.value)


static func _first_arm(document: AirframeDocument) -> int:
	for index in document.plates.size():
		if str((document.plates[index] as Dictionary).get("role", "")) \
				== AirframeDocument.ROLE_ARM:
			return index
	return -1


static func _collect_buttons(node: Node, into: Array) -> void:
	if node is Button:
		into.append(node)
	for child in node.get_children():
		_collect_buttons(child, into)
