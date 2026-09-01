class_name PropulsionWorkbench
extends Control
## The Propulsion room: a shelf of blades to start from, the planform to draw on, the section under
## the caret, and the mount stack the whole thing bolts to — propulsion.md §7.1, slice P10d.
##
## ## What a builder in here is doing, stated so the furniture follows from it
##
## They have a propeller — a catalog line, or one they drew last weekend — and a question the spec
## line cannot answer: how much blade is there, where, and at what angle. The catalog gives them
## three numbers (diameter, pitch, blades) and the model turns those into a planform it GUESSED
## (§3.1's `chord_is_assumed`). This room is where that guess stops being a guess.
##
##   - **Left: the shelf.** Every catalog blade as its own silhouette, and every blade they have
##     drawn under it.
##   - **Centre: the planform.** `c(r)` as a polyline with a control point per station. This is the
##     room's subject; everything else on screen is a consequence of it.
##   - **Right, upper: the section.** The blade at the caret's radius — chord, thickness and
##     `beta(r)` as one shape, at scale.
##   - **Right, lower: the mount stack.** The motor, the pad, the seat and the prop in elevation,
##     which is where a pad thickness stops being a number and becomes an argument.
##
## ## The rule this file exists to keep
##
## **Nothing in this room writes a mesh, and nothing computes a shape.** Every button changes the
## open `PropellerDocument` and then says so, once, through `document_changed`; the three views all
## read that document back. The airframe designer calls this its Build-free rule and it is the
## reason the picture and the physics cannot disagree: they are not two representations kept in
## step, they are one function called twice.
##
## That rule is the whole point of the slice this room shipped in. Before P10d `PropellerMesh` held
## its own copy of the chord law, so an edited planform moved the physics and left the picture
## alone — the room would have been an editor for a shape nobody could see.
##
## ## Undo, which P10d left owed and §7d pays
##
## The room holds a `BladeHistory` and every edit records into it BEFORE changing anything. The
## history lives here rather than in the canvas — the opposite of `FramePlanEditor`, which owns its
## own — because in this room the canvas is not the only thing that edits: `+ Station`,
## `− Station` and the measured-chord toggle are all on the toolbar, and a history inside the
## canvas would step back through drags and straight past everything a button did. The canvas says
## `edit_began` and the room decides what that is worth, which is the arrangement `FrameControls`
## already uses for the airframe inspector.
##
## Undo does NOT go through `set_document`. That function clears the publish snapshot, which is
## right for opening a different blade and wrong for stepping back within one — a builder who
## published, dragged and undid would be told the room has never published anything about a blade
## it published a minute ago. Both paths share `_show_document`; only the open path clears.

## Emitted after any edit to the open document, so an inspector can repaint against it.
signal document_changed(document: PropellerDocument)

## Emitted when a blade is published as a propeller. Carries the record, so a listener does not have
## to re-read the parts file to know what appeared — and the shell needs to know, because a catalog
## it loaded at startup does not contain a part that was made five minutes ago.
signal parts_published(record: Dictionary)

## The blade a new document starts from when the room is opened with nothing. The reference 5" the
## rest of the app is pinned to, so a room opened cold shows the aircraft the oracles describe.
const DEFAULT_PRESET := "prop_5x43x3"

## The motor the mount profile draws when the room is opened outside a build. A stack has to be a
## stack of SOMETHING, and this is the reference build's own motor — the same posture the default
## preset takes.
const DEFAULT_MOTOR := "motor_2306_1700kv"

var catalog: PartsCatalog
var document: PropellerDocument

## The shapes this blade has been through. Public for the same reason `FramePlanEditor.history` is:
## the toolbar asks it whether its buttons mean anything.
var history := BladeHistory.new()

var shelf: PropellerShelf
var editor: PropellerPlanformEditor
var section: PropellerSectionView
var profile: PropellerMountProfile

## The motor whose stack the profile draws, and the pad on it. Held as a record and a thickness
## rather than as a built mesh, because the mesh is rebuilt from them on every change.
var motor: Dictionary = {}
var soft_mount_m := 0.0

var _motor_mesh: MotorMesh
var _prop_mesh: PropellerMesh
var _assumed_button: CheckButton
var _status: Label

## The blade document as it was last PUBLISHED, or empty for a blade that never was. Compared
## against the open document to say whether the aircraft is flying this shape or an older one
## (§2.1). Held as the dictionary rather than the object so the comparison is by value: the open
## document is edited in place, and a reference would always equal itself.
var _published: Dictionary = {}
var _pad_slider: HSlider


func _init(p_catalog: PartsCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	motor = catalog.get_part(DEFAULT_MOTOR)

	# AN OPAQUE BACKDROP, UNDER EVERYTHING ELSE. `FrameWorkbench`'s own finding: this room covers
	# the 3D view rather than sitting beside it, and a transparent Control let Lab's turntable show
	# through every gap — a builder drawing a blade watching a different drone's props turn behind
	# their toolbar.
	var backdrop := Panel.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", _backdrop_stylebox())
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = LothalTheme.SPACE_2
	column.offset_right = -LothalTheme.SPACE_2
	column.offset_top = LothalTheme.SPACE_2
	column.offset_bottom = -LothalTheme.SPACE_2
	column.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(column)

	column.add_child(_build_toolbar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	column.add_child(body)

	shelf = PropellerShelf.new(catalog)
	shelf.preset_chosen.connect(_on_preset_chosen)
	shelf.blade_chosen.connect(_on_blade_chosen)
	body.add_child(shelf)

	editor = PropellerPlanformEditor.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.document_changed.connect(_on_planform_edited)
	editor.edit_began.connect(_on_edit_began)
	editor.caret_moved.connect(_on_caret_moved)
	body.add_child(editor)

	# The two read-only views share the right column: the section is what the caret is for, and the
	# stack is the context the blade is turning in. Both are consequences of the document, so
	# neither takes a click.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	body.add_child(right)

	section = PropellerSectionView.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(section)

	profile = PropellerMountProfile.new()
	profile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(profile)

	_status = Label.new()
	_status.theme_type_variation = &"SmallLabel"
	column.add_child(_status)

	open_preset(DEFAULT_PRESET)


# ---------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------

func _build_toolbar() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", LothalTheme.SPACE_2)
	row.add_theme_constant_override("v_separation", LothalTheme.SPACE_1)

	# THE THIRD WAY IN (§3.2). The shelf opens a preset and `Duplicate` copies one; until this
	# button there was no way to start a blade that was not descended from a product. It sits first
	# because it is where a blade begins.
	row.add_child(_button("New blade…", _on_new_blade,
		"Start a blade of your own — not a copy of anything in the catalog"))
	row.add_child(_button("Save", _on_save, "Write this blade to your own library"))
	# THE SECOND DOOR (plans/2026-09-01-authored-blade-design.md §3). `Save` keeps a draft;
	# this makes the blade a propeller the build can fit and the sim can fly. Two buttons rather
	# than one because they are two different acts: a draft is private to this room, and a
	# published propeller is a part that shows up in the rail beside the ones a builder bought.
	row.add_child(_button("Publish as propeller", _on_publish,
		"Add this blade to your parts as a propeller you can fit to an aircraft and fly"))
	row.add_child(_button("Duplicate", _on_duplicate,
		"Copy this blade so the preset stays as it shipped"))
	row.add_child(_button("+ Station", _on_add_station,
		"Add a control point at the caret, at the chord the blade already has there"))
	row.add_child(_button("− Station", _on_remove_station,
		"Remove the control point nearest the caret"))
	row.add_child(VSeparator.new())

	# Buttons as well as keys, `FrameWorkbench`'s arrangement: the room is reachable by mouse alone
	# and an undo only a keyboard can find is an undo half the builders never learn is there. Both
	# call the same two methods.
	row.add_child(_button("Undo", undo, "Step back one edit (Ctrl-Z)"))
	row.add_child(_button("Redo", redo, "Step forward again (Ctrl-Shift-Z)"))
	row.add_child(VSeparator.new())

	# THE CAVEAT, AS A SWITCH. §3.1 puts "blade chord assumed" on every figure derived from a
	# generated planform, and until this room existed there was no way to take it off — a builder
	# who had measured their blade had no way to say so. It is a CheckButton rather than a menu
	# item because it is a statement about the open document, and the document is what the room is.
	_assumed_button = CheckButton.new()
	_assumed_button.text = "Chord measured"
	_assumed_button.tooltip_text = ("On: this planform is authored, and figures derived from it "
		+ "drop the \"blade chord assumed\" caveat. Off: it is the generator's guess.")
	_assumed_button.toggled.connect(_on_assumed_toggled)
	row.add_child(_assumed_button)
	row.add_child(VSeparator.new())

	var pad_caption := Label.new()
	pad_caption.text = "Pad"
	pad_caption.theme_type_variation = &"SmallLabel"
	row.add_child(pad_caption)

	# The pad slider lives on the TOOLBAR rather than in the profile, because the profile is a view
	# and a view that edits is the thing this room's own rule forbids.
	_pad_slider = HSlider.new()
	_pad_slider.min_value = 0.0
	_pad_slider.step = 0.0001
	_pad_slider.custom_minimum_size = Vector2(120, 0)
	# `max_value` is the motor's own boss height — the screw thread a pad has to give up, which
	# `MotorMesh.max_soft_mount_m` already derives from the geometry it draws. A picked millimetre
	# ceiling here would be a second, wronger answer to a question the model has answered.
	_pad_slider.max_value = MotorMesh.max_soft_mount_m(motor)
	_pad_slider.value_changed.connect(_on_pad_changed)
	row.add_child(_pad_slider)

	return row


func _button(text: String, on_press: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_press)
	return button


static func _backdrop_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = LothalTheme.SURFACE_BASE
	return box


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

## Opens a catalog preset as a fresh document.
func open_preset(part_id: String) -> void:
	var prop: Dictionary = catalog.get_part(part_id)
	if prop.is_empty():
		_status.text = "No such blade: %s" % part_id
		return
	set_document(PropellerDocument.from_catalog_prop(prop))


## Opens a document the builder drew.
func open_blade(path: String) -> void:
	var loaded := BladeLibrary.load_blade(path)
	if loaded == null:
		_status.text = "Could not open %s" % path
		return
	set_document(loaded)


## Puts a document in the room. THE ONE PATH — every open, every preset and every test goes through
## here, so there is exactly one place that has to remember to refresh all three views.
func set_document(p_document: PropellerDocument) -> void:
	# THE PREVIOUS BLADE'S HISTORY IS NOT THIS BLADE'S. `FramePlanEditor.open` clears for the same
	# reason and it is worth restating: an undo that reached across an open would replace the blade
	# just opened with the one just left, silently, and the shelf is one click away so it happens.
	history.clear()
	# A DIFFERENT BLADE HAS NO PUBLISH HISTORY IN THIS ROOM. Cleared here rather than left standing,
	# because a snapshot carried across an open would have the room comparing the blade on screen
	# against a different blade's published shape and reporting "edited since publishing" about an
	# aircraft that is flying neither.
	_published = {}
	# And so is the sentence the snapshot produced. `_refresh_publish_state` says nothing when there
	# is no snapshot, which leaves whatever it said LAST on screen — so without this line a builder
	# who publishes a blade and then opens a different one reads "your aircraft still flies the
	# published shape" over a blade that was never published. The stale comparison and the stale
	# sentence are one thing, and they are cleared in one place.
	_status.text = ""
	_show_document(p_document)


## Puts a document in front of the three views and says so, WITHOUT touching the publish snapshot
## or the history. The half of `set_document` that undo also needs: stepping back inside one blade
## is not opening a different one, and the two differ in exactly what this function leaves alone.
func _show_document(p_document: PropellerDocument) -> void:
	document = p_document
	editor.set_document(document)
	section.set_document(document)
	_assumed_button.set_pressed_no_signal(not document.chord_is_assumed)
	_refresh()
	document_changed.emit(document)


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------

## Steps back one edit. Public because the toolbar button, Ctrl-Z and the tests all drive it, and
## all three must be the same path — a button that did its own thing diverges from the key the
## first time either changes.
##
## The status line is NOT written here. It is `_refresh`'s job, through `_refresh_publish_state`,
## and that comparison is BY VALUE against the published dictionary — so an undo that lands back on
## the published shape makes the room say the aircraft flies this blade again, for free, with no
## undo-aware code in the publish path at all.
func undo() -> void:
	if not history.can_undo():
		return
	_show_document(history.undo(document))


## Steps forward again, into the state the last undo left.
func redo() -> void:
	if not history.can_redo():
		return
	_show_document(history.redo(document))


## The canvas is about to change the blade for the first time in this drag.
func _on_edit_began() -> void:
	history.record(document)


## Ctrl-Z and Ctrl-Shift-Z, and Cmd on macOS — `FramePlanEditor._handle_key` accepts both modifiers
## for the same reason, and that is the whole of the platform difference in this app.
##
## `_unhandled_key_input` rather than `_gui_input`, because this room has no single focused canvas:
## the planform editor takes focus for its own drags and the toolbar buttons take it for theirs, so
## a handler hung on any one of them would work until the builder clicked somewhere else. This is
## the thin half of the feature and it is the half with no test — a synthesised key needs a real
## window and a tree that processes frames, which this suite has neither of (tests/test_lab.gd
## states the same constraint from the other side). What is tested is everything below the key:
## `undo()` and `redo()` are driven directly.
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


# ---------------------------------------------------------------------------
# Edits
# ---------------------------------------------------------------------------

func _on_preset_chosen(part_id: String) -> void:
	open_preset(part_id)


func _on_blade_chosen(path: String) -> void:
	open_blade(path)


func _on_planform_edited(edited: PropellerDocument) -> void:
	_assumed_button.set_pressed_no_signal(not edited.chord_is_assumed)
	_refresh()
	document_changed.emit(edited)


func _on_caret_moved(r_frac: float) -> void:
	# The caret changes nothing about the document, so this must NOT go through `_refresh` — the
	# mount stack and the blade mass cannot have moved because somebody looked somewhere else.
	section.set_r_frac(r_frac)


## The toggle, in the direction that reads: ON means "I measured this", which is `chord_is_assumed`
## FALSE. The inversion lives here, in one line, rather than in the flag's name — §3.1 wrote the
## flag as the caveat it stamps, and renaming it to suit a switch would move a modelling word to
## suit a widget.
func _on_assumed_toggled(measured: bool) -> void:
	if document == null:
		return
	if document.chord_is_assumed == (not measured):
		return
	history.record(document)
	document.chord_is_assumed = not measured
	_refresh()
	document_changed.emit(document)


func _on_add_station() -> void:
	if document == null:
		return
	var edited := PlanformEdits.insert_station(document.chord, editor.caret_r_frac, document)
	if edited == document.chord:
		_status.text = "There is already a station at r/R %.3f" % editor.caret_r_frac
		return
	# RECORDED AFTER THE REFUSAL, never before it: a press that changed nothing must not leave a
	# step on the stack, or a builder pressing "+ Station" twice at one radius has to press undo
	# twice to get back one edit.
	history.record(document)
	document.chord = edited
	editor.queue_redraw()
	_refresh()
	document_changed.emit(document)


func _on_remove_station() -> void:
	if document == null:
		return
	var index := PlanformEdits.nearest_station(document.chord, editor.caret_r_frac)
	var edited := PlanformEdits.remove_station(document.chord, index)
	if edited == document.chord:
		_status.text = "A planform needs at least %d stations" % PlanformEdits.MIN_STATIONS
		return
	history.record(document)
	document.chord = edited
	editor.queue_redraw()
	_refresh()
	document_changed.emit(document)


func _on_pad_changed(value: float) -> void:
	soft_mount_m = value
	_refresh()


func _on_save() -> void:
	if document == null:
		return
	if document.id == "":
		document.id = "blade_%d" % Time.get_ticks_usec()
	_status.text = "Saved as %s" % BladeLibrary.path_for(document.id) if BladeLibrary.save(document) \
		else "Could not save this blade"
	shelf.refresh_saved()


## Publishes the open blade as a propeller a build can fit (§3).
##
## The record's every field comes from the document — mass included, and mass ESPECIALLY: see
## `CustomPropellers.record_from_document` for why a typed mass would let half the model follow the
## geometry while the other half kept the numbers of the blade this one was copied from.
##
## Refusals come from `CustomPropellers` rather than from here. The room knows how to draw a blade;
## whether a record is one the parts system will accept is the parts system's own question, and it
## already refuses a propeller with no diameter in the one place every other custom part is judged.
func _on_publish() -> void:
	if document == null:
		return
	var store := CustomPropellers.load_from()
	var record := CustomPropellers.record_from_document(
		document, PropellerDetails.materials(), "designed in the Propulsion room")
	# A republish of the same blade REPLACES rather than collides: the id is derived from the name,
	# so publishing twice is the builder revising their own part, not adding a second one. Removing
	# first is what makes that an update — `add` refuses a duplicate id, and it is right to.
	store.remove(str(record.get("part_id", "")))
	var problems := store.add(record)
	if not problems.is_empty():
		_status.text = "Could not publish: %s" % ", ".join(problems)
		return
	if not store.save():
		_status.text = "Could not write your parts file"
		return
	_published = record[PropellerDocument.AUTHORED_BLADE_KEY].duplicate(true)
	_refresh_publish_state()
	parts_published.emit(record)


## What the room says about the gap between the draft on screen and the part that was published.
##
## §2.1's cost, made visible. Publishing takes a SNAPSHOT — the blade document is copied into the
## parts record, so a later drag in this room does not reach an aircraft until it is published
## again. That is the honest behaviour for a store whose other records are things a builder bought,
## and it is also the behaviour most likely to be experienced as a bug. Saying it out loud is the
## whole mitigation, so this line is not decoration.
func _refresh_publish_state() -> void:
	if document == null or _published.is_empty():
		return
	if document.to_dictionary() == _published:
		_status.text = "Published — this is the blade your aircraft flies"
	else:
		_status.text = "Edited since publishing — your aircraft still flies the published shape"


## Opens the "New blade…" form, seeded with the open blade's own numbers (§3.2).
##
## SEEDED, NOT BLANK, and the two are different: the form arrives holding a 5x4.3x3 because that is
## what is on screen, and a builder making a 5" of their own then changes a name rather than typing
## four numbers they already know. What the new document does NOT inherit is the product — no part
## number, no vendor mass, no planform copied across. That is the whole distinction §3.2 draws
## between "from nothing" and "a blank shape".
##
## The dialog is created per press and freed when it closes rather than held as a field, the same
## arrangement `PropellerPicker._open_dialog` uses: a form that survives its own dismissal is a form
## holding last week's numbers the next time it opens.
func _on_new_blade() -> void:
	var dialog := NewBladeDialog.new()
	if document != null:
		dialog.set_fields("Untitled blade",
			document.diameter_mm / PropellerDocument.INCH_TO_MM,
			document.pitch_mm / PropellerDocument.INCH_TO_MM,
			document.blades,
			document.material_id)
	dialog.blade_created.connect(func(created: PropellerDocument) -> void:
		adopt_new_blade(created)
		dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


## Puts a freshly-created blade in the room and says what happened. Separate from the lambda above
## so a test can drive the outcome without a window: `popup_centered` needs the node in a tree, and
## `set_document` plus the status line is the whole of what the button is for.
func adopt_new_blade(created: PropellerDocument) -> void:
	set_document(created)
	_status.text = ("New blade \"%s\" — the arch is a starting guess, not a measurement. "
		+ "Drag a station and it stops being one.") % created.name


func _on_duplicate() -> void:
	if document == null:
		return
	set_document(BladeLibrary.duplicate_of(document, "%s copy" % document.name))
	_status.text = "Working on a copy — the preset is untouched"


# ---------------------------------------------------------------------------
# Repaint
# ---------------------------------------------------------------------------

## Rebuilds everything that follows from the document, in one place. Called after every edit and
## never from a view: a view that refreshed itself would be a second opinion about when the model
## changed.
func _refresh() -> void:
	if document == null:
		return

	# The prop mesh is built to get its `stack_height_m` — how much room the propeller takes on the
	# shaft — which is what decides where the nut goes. Read from the mesh rather than estimated,
	# because the mesh measures it off the blade it generated and an estimate here would be a
	# second answer to a question the geometry has already answered.
	if _prop_mesh == null:
		_prop_mesh = PropellerMesh.new()
	_prop_mesh.rebuild(_as_catalog_prop(), document)

	if _motor_mesh == null:
		_motor_mesh = MotorMesh.new()
	_motor_mesh.rebuild(motor, _prop_mesh.stack_height_m, 0.0, soft_mount_m)

	# The tip mass the pad carries: the motor and the propeller it is holding up. `SoftMount` owns
	# the frequency; this room owns neither the formula nor a second copy of it.
	var tip_mass_kg := float(motor.get("mass_g", 0.0)) * 0.001 \
		+ document.published_mass_g * 0.001
	profile.set_stack(_motor_mesh, soft_mount_m,
		SoftMount.f_n_hz(soft_mount_m, tip_mass_kg))

	section.queue_redraw()
	editor.queue_redraw()

	# Last, because it describes the state the rest of this function just produced: whether the
	# shape on screen is still the shape that was published (§2.1).
	_refresh_publish_state()


## The open document as the record `PropellerMesh.rebuild` reads — diameter, blade count and the
## material description it colours by. The document is the truth about SHAPE and the catalog record
## is the truth about the product, and this is the one place the two meet.
func _as_catalog_prop() -> Dictionary:
	return {
		"part_id": document.id,
		"name": document.name,
		"specs": {
			"diameter_inches": document.diameter_mm / PropellerDocument.INCH_TO_MM,
			"pitch_inches": document.pitch_mm / PropellerDocument.INCH_TO_MM,
			"blades": document.blades,
		},
		"catalog": {"material": document.material_id},
	}
