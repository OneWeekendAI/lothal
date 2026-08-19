class_name FrameWorkbench
extends Control
## The Airframe room: a plan canvas, the tools that act on it, and the frame you have open.
##
## ## What this adds over `FramePlanEditor`
##
## The canvas knows how to draw a frame and how to move its points. It does not know what frames
## exist, which one is open, or how a new plate comes into being — and it should not, because those
## are questions about a workspace rather than about a drawing. This node answers them: it holds the
## open document, it owns the toolbar, and it is the one place that talks to `FrameLibrary`.
##
## ## Why a toolbar and not a menu
##
## Everything here is something you do WHILE looking at the frame — add an arm, mirror it, change
## the stock, undo. A menu would put each of those two clicks and a moved cursor away from the shape
## they change, and the whole argument of §7.1 is that editing the outline and watching the numbers
## move is one activity rather than two.
##
## ## The one rule this file exists to keep
##
## Every button does exactly one thing to the document and then says so, once, through
## `document_changed`. The four inspector tabs listen to that signal, so mass, inertia, stiffness
## and the assembly checks repaint the instant an outline moves — which is §0's claim made literal:
## if you widen an arm on screen, the resonance moves, because they are the same polygon.

signal document_changed(document: AirframeDocument)

## New plates arrive at this size, in mm — big enough to see and grab at the default zoom, small
## enough that it is obviously a starting point rather than a suggestion about your frame.
const NEW_PLATE_MM := 40.0
## A new arm: a 5"-ish arm at a real stock thickness, tapering the way a real one does.
const NEW_ARM_LENGTH_MM := 110.0
const NEW_ARM_ROOT_MM := 14.0
const NEW_ARM_TIP_MM := 10.0

const SNAP_CHOICES := [
	{"label": "0.5 mm", "value": 0.5},
	{"label": "1 mm", "value": 1.0},
	{"label": "5 mm", "value": 5.0},
	{"label": "off", "value": 0.0},
]

var editor: FramePlanEditor
## The same document, extruded. Airframe is a STACK, and a top view cannot show a stack — plate
## roles, standoff height and which plate an arm is sandwiched between are numbers in the plan view
## and are the whole shape here.
var view_3d: Frame3DView
var catalog: PartsCatalog

var _canvas_host: Control
var _view_2d_button: Button
var _view_3d_button: Button
var _zoom_label: Label
## The catalog entry the open document was started from. Kept for one reason only: `FrameModel`
## needs the surface material and the mount table, and neither of those is in the document.
var _source_frame: Dictionary = {}
var _open_button: MenuButton
var _role_picker: OptionButton
var _thickness_field: SpinBox
var _symmetry_button: CheckButton
var _status: Label
var _selected_plate := -1
## Guards the property strip while it is being repopulated: setting an OptionButton's selection or a
## SpinBox's value fires the same signal a builder's click does, and without this an open would be
## indistinguishable from an edit and would push a spurious entry onto the undo stack.
var _syncing := false


func _init(p_catalog: PartsCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()

	# AN OPAQUE BACKDROP, UNDER EVERYTHING ELSE IN THE ROOM.
	#
	# This room covers the 3D view rather than sitting beside it, and it used to do so with a
	# transparent Control: the canvas painted its own rectangle, and every gap around it — the
	# toolbar strip, the margins, the space beside the property row — let Lab's turntable show
	# through. So a builder drawing a frame watched a DIFFERENT drone's props turning behind their
	# toolbar, which reads as a rendering fault rather than as a feature.
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
	column.add_child(_build_property_strip())

	# The plan view and the 3D view share one rectangle and one visibility switch, rather than
	# splitting it. Half a canvas to draw in and half a model too small to read is worse than
	# either whole, and the toggle is one click — see `set_view_3d`.
	_canvas_host = Control.new()
	_canvas_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_host.clip_contents = true
	column.add_child(_canvas_host)

	editor = FramePlanEditor.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.document_changed.connect(_on_document_changed)
	editor.selection_changed.connect(_on_selection_changed)
	editor.view_changed.connect(_refresh_zoom_label)
	_canvas_host.add_child(editor)

	view_3d = Frame3DView.new()
	view_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_3d.visible = false
	_canvas_host.add_child(view_3d)




# ---------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------

## The tools, in a FLOW container rather than a row.
##
## An `HBoxContainer` does not shrink below its contents: at a narrow window the last few controls —
## the snap step and the symmetry toggle — simply drew underneath the inspector column and could not
## be clicked. A flow container wraps to a second line instead, which is the right answer for a
## toolbar whose length is fixed and whose window is not.
func _build_toolbar() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", LothalTheme.SPACE_2)
	row.add_theme_constant_override("v_separation", LothalTheme.SPACE_1)

	row.add_child(_button("New", _on_new))

	_open_button = MenuButton.new()
	_open_button.text = "Open"
	_open_button.about_to_popup.connect(_refresh_open_menu)
	_open_button.get_popup().id_pressed.connect(_on_open_chosen)
	row.add_child(_open_button)

	row.add_child(_button("Save", _on_save))
	row.add_child(_button("Duplicate", _on_duplicate))
	row.add_child(VSeparator.new())

	row.add_child(_button("+ Plate", _on_add_plate))
	row.add_child(_button("+ Arm", _on_add_arm))
	row.add_child(_button("Mirror ×4", _on_replicate))
	row.add_child(_button("Delete", _on_delete))
	row.add_child(VSeparator.new())

	row.add_child(_button("Undo", func() -> void: editor.undo()))
	row.add_child(VSeparator.new())

	# THE VIEW CONTROLS, IN ONE CLUSTER, AND VISIBLE.
	#
	# Zoom was previously the mouse wheel and nothing else. A wheel is a fine way to zoom and a bad
	# way to DISCOVER that zooming exists, and a canvas whose scale can only be changed by a gesture
	# nobody has been told about is a canvas that appears to be stuck at whatever it opened on. The
	# readout beside them is the other half of the same argument: it says how far in you are, so
	# "1.0×" is a state you can see yourself leave and a state Fit visibly returns you to.
	row.add_child(_button("−", func() -> void: _zoom(1.0 / FramePlanEditor.ZOOM_STEP), "Zoom out"))
	row.add_child(_button("+", func() -> void: _zoom(FramePlanEditor.ZOOM_STEP), "Zoom in"))
	row.add_child(_button("Fit", _on_fit, "Frame the whole drawing  (F)"))

	_zoom_label = Label.new()
	_zoom_label.theme_type_variation = &"SmallLabel"
	_zoom_label.custom_minimum_size = Vector2(46, 0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_zoom_label)

	_view_2d_button = _button("2D", func() -> void: set_view_3d(false), "The plan you draw in")
	_view_2d_button.toggle_mode = true
	_view_2d_button.button_pressed = true
	row.add_child(_view_2d_button)

	_view_3d_button = _button("3D", func() -> void: set_view_3d(true),
		"The same frame, extruded — drag to orbit, wheel to zoom")
	_view_3d_button.toggle_mode = true
	row.add_child(_view_3d_button)
	row.add_child(VSeparator.new())

	var snap := OptionButton.new()
	for choice in SNAP_CHOICES:
		snap.add_item("snap %s" % choice["label"])
	snap.item_selected.connect(func(index: int) -> void:
		editor.snap_mm = float(SNAP_CHOICES[index]["value"]))
	_compact(snap)
	row.add_child(snap)

	_symmetry_button = CheckButton.new()
	_symmetry_button.text = "Symmetry"
	_symmetry_button.button_pressed = true
	_symmetry_button.toggled.connect(func(on: bool) -> void: editor.symmetric_arms = on)
	_compact(_symmetry_button)
	row.add_child(_symmetry_button)

	_compact(_open_button)
	return row


## The properties of whatever is selected. Two fields, because two are what the physics reads off a
## plate that the outline does not already say: how thick the stock is, and what the plate is FOR.
## Both change numbers immediately — thickness is cubed in the bending maths (§4.2) — so they live
## beside the drawing rather than in a dialog.
func _build_property_strip() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", LothalTheme.SPACE_2)

	var role_label := Label.new()
	role_label.text = "Selected plate"
	role_label.theme_type_variation = &"SmallLabel"
	row.add_child(role_label)

	_role_picker = OptionButton.new()
	for role in [AirframeDocument.ROLE_BOTTOM, AirframeDocument.ROLE_TOP,
			AirframeDocument.ROLE_ARM, AirframeDocument.ROLE_SIDE, AirframeDocument.ROLE_MID]:
		_role_picker.add_item(role)
	_role_picker.item_selected.connect(_on_role_chosen)
	_compact(_role_picker)
	row.add_child(_role_picker)

	var thickness_label := Label.new()
	thickness_label.text = "stock"
	thickness_label.theme_type_variation = &"SmallLabel"
	row.add_child(thickness_label)

	_thickness_field = SpinBox.new()
	_thickness_field.min_value = 0.5
	_thickness_field.max_value = 12.0
	_thickness_field.step = 0.5
	_thickness_field.value = FrameEdits.DEFAULT_PLATE_THICKNESS_MM
	_thickness_field.suffix = "mm"
	_thickness_field.value_changed.connect(_on_thickness_changed)
	_thickness_field.custom_minimum_size = Vector2(96, 0)
	_compact(_thickness_field)
	row.add_child(_thickness_field)

	_status = Label.new()
	_status.theme_type_variation = &"SmallLabel"
	# The status line is the only thing here whose length is unbounded — it carries sentences about
	# what just happened, and one of them is a whole explanation of why a preset opened as a copy.
	# Clipped rather than allowed to push the toolbar wider than the room.
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)

	return row


static func _button(text: String, action: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	_compact(button)
	return button


## Shrinks a control to workbench scale.
##
## The room carries about twenty controls in a strip above the drawing, and at the theme's default
## body size and button padding they took two wrapped rows and about a fifth of the height of the
## window — chrome outweighing the thing it acts on. Applied per control rather than by editing the
## theme, because everywhere else in the app these sizes are right; it is the DENSITY here that is
## wrong, and a global change would shrink the readouts a builder is meant to read.
static func _compact(control: Control) -> void:
	control.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	if control is Button:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := control.get_theme_stylebox(state, "Button")
			if box == null:
				continue
			var tight := box.duplicate() as StyleBox
			tight.content_margin_left = LothalTheme.SPACE_2
			tight.content_margin_right = LothalTheme.SPACE_2
			tight.content_margin_top = 2
			tight.content_margin_bottom = 2
			control.add_theme_stylebox_override(state, tight)


## The room's own ground. Opaque, and a shade off the canvas so the drawing still reads as a surface
## sitting on a bench rather than as the bench itself.
static func _backdrop_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(LothalTheme.PANEL_BG, 0.97)
	box.border_color = LothalTheme.BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box


# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

## Opens a catalog frame as an editable copy, which is what the room opens on.
##
## A BLANK CANVAS IS THE WRONG FIRST SCREEN, even though `New` gives you one. Every number in the
## four inspector tabs is an integral over plates, so an empty document shows eleven dashes and
## teaches a builder nothing about what this room does. Starting from a real frame means the mass,
## the inertia and the arm's mode are on screen before anything is clicked, and dragging one corner
## shows all three move — which is the claim the whole system is built on. It opens as a COPY for
## the reason `_on_open_chosen` gives: an edited preset is no longer the product the vendor
## published.
func start_from(frame: Dictionary) -> void:
	_source_frame = frame
	if frame.is_empty():
		editor.open(FrameEdits.new_frame("Untitled frame"))
		return
	var preset := AirframeDocument.from_catalog_frame(frame)
	editor.open(FrameLibrary.duplicate_of(preset, "%s (copy)" % preset.name))
	_set_status("Started from %s — a copy, so the vendor's mass no longer applies." % preset.name)


func _on_new() -> void:

	_set_status("New frame. Add a plate or an arm to begin.")


## The Open menu, rebuilt each time it is shown: the builder's own frames first, then the catalog
## presets as starting points.
##
## Rebuilt rather than cached because the library is a directory of files, and a menu that was built
## at startup would not know about a frame saved five minutes ago — or one copied in from somewhere
## else, which is a thing a directory of readable JSON is FOR.
func _refresh_open_menu() -> void:
	var popup := _open_button.get_popup()
	popup.clear()
	var index := 0
	var mine := FrameLibrary.entries()
	if not mine.is_empty():
		popup.add_separator("Your frames")
		for entry in mine:
			popup.add_item("%s  (%d plates)" % [entry["name"], entry["plates"]], index)
			popup.set_item_metadata(popup.get_item_index(index), entry["path"])
			index += 1
	popup.add_separator("Start from a catalog frame")
	for frame in catalog.list_category("frame"):
		popup.add_item(str(frame.get("name", "?")), index)
		popup.set_item_metadata(popup.get_item_index(index), frame)
		index += 1


func _on_open_chosen(id: int) -> void:
	var popup := _open_button.get_popup()
	var metadata: Variant = popup.get_item_metadata(popup.get_item_index(id))
	if metadata is String:
		var document := FrameLibrary.load_frame(metadata as String)
		editor.open(document)
		_set_status("Opened %s." % document.name)
		return
	if metadata is Dictionary:
		# A PRESET OPENS AS A COPY, not as the catalog entry. Editing a preset in place would mean a
		# builder's changes lived in the app's own catalog and vanished on update; opening a copy is
		# also the honest thing, because the moment you move an outline it is no longer the product
		# the vendor published — which is why `duplicate_of` drops the published mass with it.
		var preset := AirframeDocument.from_catalog_frame(metadata as Dictionary)
		editor.open(FrameLibrary.duplicate_of(preset, "%s (copy)" % preset.name))
		_set_status("Started from %s. It is a copy — the vendor's mass no longer applies." % preset.name)


func _on_save() -> void:
	if editor.document == null:
		return
	if FrameLibrary.save(editor.document):
		_set_status("Saved %s." % editor.document.name)
	else:
		# Said out loud. A save that silently failed would let somebody close the app believing an
		# evening's drawing was on disk.
		_set_status("COULD NOT SAVE %s — check disk permissions." % editor.document.name)


func _on_duplicate() -> void:
	if editor.document == null:
		return
	editor.open(FrameLibrary.duplicate_of(editor.document, "%s (copy)" % editor.document.name))
	_set_status("Duplicated. This copy has no vendor figures.")


# ---------------------------------------------------------------------------
# Edits
# ---------------------------------------------------------------------------

func _on_add_plate() -> void:
	editor.history.record(editor.document)
	var index := FrameEdits.add_rectangle(editor.document, Vector2.ZERO,
		NEW_PLATE_MM, NEW_PLATE_MM, float(_thickness_field.value), 0.0,
		AirframeDocument.ROLE_BOTTOM)
	editor.selected_plate = index
	_on_document_changed(editor.document)
	_set_status("Added a %.0f mm plate. Drag its corners." % NEW_PLATE_MM)


func _on_add_arm() -> void:
	editor.history.record(editor.document)
	# Arms are added on the 45 degree diagonal, which is where the first arm of an X goes, and then
	# mirrored. Starting anywhere else would make the common case two steps.
	var index := FrameEdits.add_arm(editor.document, 45.0, NEW_ARM_LENGTH_MM,
		NEW_ARM_ROOT_MM, NEW_ARM_TIP_MM, FrameEdits.DEFAULT_ARM_THICKNESS_MM)
	editor.selected_plate = index
	_on_document_changed(editor.document)
	_set_status("Added an arm with a motor at its tip. Mirror it to make a quad.")


func _on_replicate() -> void:
	if _selected_plate < 0:
		_set_status("Select an arm first, then mirror it.")
		return
	editor.history.record(editor.document)
	FrameEdits.replicate_radially(editor.document, _selected_plate, 4)
	_on_document_changed(editor.document)
	_set_status("Mirrored four ways. Editing one arm now edits all four.")


func _on_delete() -> void:
	if _selected_plate < 0 or editor.document == null:
		return
	editor.history.record(editor.document)
	editor.document.plates.remove_at(_selected_plate)
	editor.selected_plate = -1
	_selected_plate = -1
	_on_document_changed(editor.document)
	_set_status("Deleted a plate.")


func _on_role_chosen(index: int) -> void:
	if _syncing or _selected_plate < 0:
		return
	editor.history.record(editor.document)
	FrameEdits.set_role(editor.document, _selected_plate, _role_picker.get_item_text(index))
	_on_document_changed(editor.document)


func _on_thickness_changed(value: float) -> void:
	if _syncing or _selected_plate < 0:
		return
	editor.history.record(editor.document)
	FrameEdits.set_thickness(editor.document, _selected_plate, value)
	_on_document_changed(editor.document)


# ---------------------------------------------------------------------------
# Keeping the strip and the world in step
# ---------------------------------------------------------------------------

func _on_document_changed(document: AirframeDocument) -> void:
	editor.queue_redraw()
	_sync_property_strip()
	_refresh_zoom_label()
	# The 3D view is rebuilt only while it is the view you are looking at. Extruding every plate on
	# every mouse motion of a vertex drag would cost a full mesh rebuild per frame for a picture
	# nobody is looking at; switching to 3D rebuilds it once, from the document as it then stands.
	if view_3d.visible:
		view_3d.show_document(document, _source_frame)
	document_changed.emit(document)


func _on_selection_changed(plate_index: int) -> void:
	_selected_plate = plate_index
	_sync_property_strip()


func _sync_property_strip() -> void:
	var has_selection := _selected_plate >= 0 and editor.document != null \
		and _selected_plate < editor.document.plates.size()
	_role_picker.disabled = not has_selection
	_thickness_field.editable = has_selection
	if not has_selection:
		return
	var plate: Dictionary = editor.document.plates[_selected_plate]
	_syncing = true
	for index in _role_picker.item_count:
		if _role_picker.get_item_text(index) == str(plate.get("role", "")):
			_role_picker.select(index)
	_thickness_field.value = AirframeDocument.plate_thickness_mm(plate)
	_syncing = false


# ---------------------------------------------------------------------------
# The two views
# ---------------------------------------------------------------------------

## Switches between the plan you draw in and the frame you drew.
##
## THE PLAN VIEW IS THE ONE WITH HANDS. Nothing in 3D is editable and nothing pretends to be —
## dragging there orbits the camera — so the switch is a way to LOOK at what you made, and the
## drawing controls stay live behind it because coming back to a canvas with the wrong snap step
## selected would be its own small betrayal.
func set_view_3d(on: bool) -> void:
	view_3d.visible = on
	editor.visible = not on
	_view_2d_button.button_pressed = not on
	_view_3d_button.button_pressed = on
	if on:
		view_3d.show_document(editor.document, _source_frame)
	_refresh_zoom_label()


func showing_3d() -> bool:
	return view_3d.visible


## Fit, meaning whichever view is in front. One button rather than two, because a builder who has
## lost the drawing does not first want to work out which of two Fits they need.
func _on_fit() -> void:
	if view_3d.visible:
		view_3d.reset_view()
	else:
		editor.fit_to_document()
	_refresh_zoom_label()


func _zoom(factor: float) -> void:
	if view_3d.visible:
		view_3d.zoom_by(factor)
	else:
		editor.zoom_by(factor)
	_refresh_zoom_label()


func _refresh_zoom_label() -> void:
	if _zoom_label == null:
		return
	# The 3D view has a camera distance rather than a scale, and a "×" against a fitted distance is
	# the same sentence in both: one is what Fit gives you.
	_zoom_label.text = "3D" if view_3d.visible else "%.1f×" % editor.zoom_ratio()


func _set_status(text: String) -> void:
	_status.text = text
