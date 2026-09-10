class_name PowerWorkbench
extends Control
## The Power room — plans/2026-09-10-power-room-design.md §2, slice PW5.
##
## A builder in here has a warning that says their motor leads are 22 AWG and too thin, and no way
## to see what that means or to do anything about it. This room is the harness as a picture and as
## two editable numbers per segment. §2.2's pack view is PW6 and is deliberately not here; the
## right-hand column is the inspector until it arrives.
##
## ---------------------------------------------------------------------------
## THE RULE THIS ROOM IS BUILT ON
## ---------------------------------------------------------------------------
##
## **Nothing in this room computes a shape or writes a mesh.** Every control mutates the open
## `Harness` and then says so, ONCE, through `document_changed`; the views read that harness back.
## `PropulsionWorkbench` states this at length and it is the same rule for the same reason: P10d
## exists because `PropellerMesh` held its own copy of the chord law, so an edited planform moved
## the physics and left the picture alone. The version of that defect in this room would be a
## harness you can edit and cannot see.
##
## The room is the only writer. `HarnessInspector` emits and stops, `HarnessSchematic` draws and
## selects and stops, and neither of them touches the document — which is also the only arrangement
## in which the undo below can be correct, because the room has to remember the table BEFORE the
## edit and it cannot do that if the edit has already happened somewhere else.
##
## ---------------------------------------------------------------------------
## UNDO LIVES HERE, NOT IN THE CANVAS
## ---------------------------------------------------------------------------
##
## `FramePlanEditor` owns its own history and this room does not, and `PropulsionWorkbench` gives
## the deciding reason: the canvas is not the only thing that edits. The gauge picker and the length
## box are on the INSPECTOR, so a history inside the schematic would step back through selections
## and straight past everything a field did. The schematic reports what was clicked; the room
## decides what that is worth, and the answer for a selection is "nothing" — see `_on_selected`.
##
## ---------------------------------------------------------------------------
## WHAT THE VIEW IS COLOURED BY, AND WHY IT GOES THROUGH HERE
## ---------------------------------------------------------------------------
##
## `HarnessChecks.warnings_for` is run HERE and handed to the schematic, rather than the schematic
## running it. Two reasons, and the second is the load-bearing one:
##
##   - It primes a `Powertrain` (see `HarnessChecks.draw`). That is not work a `_draw` should do.
##   - It makes the drawing's colours a consequence of the room having announced an edit. A view
##     that re-derived its own warnings would be right without being told, which is precisely the
##     private copy the Build-free rule forbids — and `tests/test_power_room.gd` asserts the
##     staleness that proves it is not doing that.

## Emitted after any edit to the open harness, so the shell can rebuild the aircraft around it: the
## harness is real mass at real positions, and a lead that just got 60 mm longer moved the centre
## of mass. Carries the harness rather than the build, because the harness is what changed.
signal document_changed(harness: Harness)

## The gap between the two columns and the room's own inset, in the shell's spacing vocabulary.
const GUTTER := LothalTheme.SPACE_2

## The aircraft on the bench. The harness edited here is `build.harness` — the same object the mass
## properties read — which is what makes this room an editor for the flying aircraft rather than
## for a copy of it.
var build: Build = null

## Where the harness has been. Public for `PropulsionWorkbench.history`'s reason: the toolbar asks
## it whether its buttons mean anything.
var history := HarnessHistory.new()

var schematic: HarnessSchematic
var inspector: HarnessInspector

var _undo_button: Button
var _redo_button: Button
var _status: Label


func _init() -> void:
	# AN OPAQUE BACKDROP, UNDER EVERYTHING ELSE — `PropulsionWorkbench`'s own finding, and it is not
	# cosmetic: this room covers the 3D viewport rather than sitting beside it, and a transparent
	# Control let Lab's turntable show through every gap the layout did not paint.
	var backdrop := Panel.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = GUTTER
	column.offset_right = -GUTTER
	column.offset_top = GUTTER
	column.offset_bottom = -GUTTER
	column.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(column)

	column.add_child(_build_toolbar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GUTTER)
	column.add_child(body)

	schematic = HarnessSchematic.new()
	schematic.selection_changed.connect(_on_selected)
	body.add_child(schematic)

	inspector = HarnessInspector.new()
	inspector.value_edited.connect(_on_value_edited)
	inspector.default_restored.connect(_on_default_restored)
	body.add_child(inspector)

	_status = Label.new()
	_status.theme_type_variation = &"SmallLabel"
	column.add_child(_status)


func _build_toolbar() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", LothalTheme.SPACE_2)
	row.add_theme_constant_override("v_separation", LothalTheme.SPACE_1)

	var title := Label.new()
	title.text = "Harness"
	title.theme_type_variation = &"TitleLabel"
	row.add_child(title)
	row.add_child(VSeparator.new())

	# Buttons as well as keys, `PropulsionWorkbench`'s arrangement and its reason: an undo only a
	# keyboard can find is an undo half the builders never learn is there. Both call the same two
	# methods.
	_undo_button = _button("Undo", undo, "Step back one harness edit (Ctrl-Z)")
	row.add_child(_undo_button)
	_redo_button = _button("Redo", redo, "Step forward again (Ctrl-Shift-Z)")
	row.add_child(_redo_button)
	return row


func _button(text: String, action: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	return button


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

## Puts an aircraft on the bench. THE ONE PATH — every open and every test goes through here, so
## there is exactly one place that has to remember to refresh both views.
##
## The history is cleared, `BladeHistory.clear`'s reason applied to wire: an undo that reached
## across an open would put a cinelifter's 12 AWG trunk on the whoop now on screen, and the
## dropdown is one click away so it happens.
func set_build(p_build: Build) -> void:
	build = p_build
	history.clear()
	schematic.select("")
	_refresh()


## Both views against the document as it stands, and one announcement. THE ONLY WRITER TO THE
## SCREEN — see the header; every edit below ends here and nothing else repaints anything.
func _refresh() -> void:
	if build == null:
		schematic.show_harness(null, [] as Array[BuildWarning])
		inspector.show_nothing()
		_refresh_toolbar()
		return

	# ONE `warnings_for` PER REFRESH, handed to the view. Not called by the view — see the header
	# for the check that depends on that being true.
	var warnings := HarnessChecks.warnings_for(build)
	schematic.show_harness(build, warnings)
	_render_selection()
	_refresh_toolbar()
	_status.text = "Harness %.1f g — %s" % [build.harness.total_mass_g(build),
		"no warnings on the current path" if warnings.is_empty()
			else "%d thing(s) to say about the current path" % warnings.size()]
	document_changed.emit(build.harness)


## The inspector against whatever the schematic says is selected. Looked up in
## `HarnessChecks.segments` rather than in a table of this room's own, so the panel and the drawing
## and the ampacity check are all reading one list.
func _render_selection() -> void:
	var id := schematic.selected()
	if id == HarnessSchematic.CAPACITOR_ID:
		inspector.show_capacitor(build)
		return
	for segment in HarnessChecks.segments(build):
		if String(segment["id"]) == id:
			inspector.show_segment(build, segment)
			return
	inspector.show_nothing()


func _refresh_toolbar() -> void:
	_undo_button.disabled = not history.can_undo()
	_redo_button.disabled = not history.can_redo()


# ---------------------------------------------------------------------------
# Edits
# ---------------------------------------------------------------------------

## A selection is NOT an edit. It records no history and it does not touch the harness — it only
## changes which segment the inspector is describing. Undo stepping back through clicks is the
## defect the room-owned history exists to avoid, and it would arrive here first.
func _on_selected(_id: String) -> void:
	if build == null:
		return
	_render_selection()


## The one path from the inspector to the document: remember, apply, announce.
##
## `record` takes the table BEFORE the change, which is `HarnessHistory.record`'s stated contract —
## a caller that recorded afterwards would have a stack that is always one edit behind.
func _on_value_edited(key: String, value: Variant) -> void:
	if build == null:
		return
	history.record(build.harness.overrides())
	build.harness.set_value(key, value)
	_refresh()


## "Follow the parts again." A separate path because clearing an override is not setting one:
## `Harness` stores absence, and writing the default back as a number would freeze it at whatever
## the frame happened to be today — which is exactly the sparseness `Harness`'s header is built on.
func _on_default_restored(key: String) -> void:
	if build == null or key == "":
		return
	history.record(build.harness.overrides())
	build.harness.clear(key)
	_refresh()


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------

## Steps back one edit. Public because the toolbar button, Ctrl-Z and the tests all drive it, and
## all three must be the same path.
##
## The override table is REPLACED wholesale rather than reverted key by key, which is what makes
## undo able to step back over a "Default" press: absence is a state, and only a whole-table
## assignment can restore it.
func undo() -> void:
	if build == null or not history.can_undo():
		return
	_adopt(history.undo(build.harness.overrides()))


func redo() -> void:
	if build == null or not history.can_redo():
		return
	_adopt(history.redo(build.harness.overrides()))


## Puts a whole override table back on the aircraft and repaints.
##
## `Harness.from_overrides` builds a new harness rather than this reaching into the old one, so the
## filtering that function does — unknown keys dropped — happens on the way back in as well as on
## the way in from a saved project. One door into a harness, and undo goes through it.
func _adopt(overrides: Dictionary) -> void:
	build.harness = Harness.from_overrides(overrides)
	_refresh()


## Ctrl-Z and Ctrl-Shift-Z, and Cmd on macOS. `_unhandled_key_input` for
## `PropulsionWorkbench._unhandled_key_input`'s reason: this room has no single focused canvas —
## the schematic takes focus for a click and the toolbar buttons take it for theirs — so a handler
## hung on either would work until the builder clicked the other. This is the half with no test, and
## for the reason stated there: a synthesised key needs a real window and a tree that processes
## frames, and this suite has neither. What is tested is everything below it — `undo()` and `redo()`
## are driven directly.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_Z:
		return
	if not (key.ctrl_pressed or key.meta_pressed):
		return
	if key.shift_pressed:
		redo()
	else:
		undo()
	accept_event()
