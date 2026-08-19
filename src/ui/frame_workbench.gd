class_name FrameWorkbench
extends Control
## The Airframe room: a shelf of layouts to start from, a canvas to shape them on, a column of
## controls to dimension them with, and a strip of numbers that moves while you do it.
##
## ## What this room is FOR, stated so the furniture follows from it
##
## A builder in here has no aircraft. They have a topology in mind — six arms, flat, motors
## alternating — and a size they are guessing at, and what they want out of the room is a set of
## plates a cutter can make. Everything in the layout follows from that one sentence:
##
##   - **Left: the shelf.** Nine layouts as diagrams, because "Hex V" and "Hex I" are the same
##     three words to anybody who has not built one and completely different aircraft.
##   - **Centre: the canvas.** 2D to draw in, 3D to check the stack in, one rectangle, one toggle.
##   - **Right: the controls.** Every dimension as a slider you can drag and a box you can type in.
##     This is where the frame actually gets its size; the canvas is where you find out what that
##     size looks like.
##   - **Below: the numbers.** Mass, CG and inertia always visible, the four detail tabs one click
##     behind them.
##
## The one thing the room deliberately does NOT show is anything about an aircraft: no hover
## throttle, no thrust-to-weight, no prop size, no vendor's published mass. Those are questions
## about a build, they belong to Lab, and a frame you are drawing has no answer to any of them.
##
## ## The rule this file exists to keep
##
## Every button does one thing to the document and then says so, once, through `document_changed`.
## The canvas, the 3D view, the controls column and the numbers strip all listen to that signal, so
## widening an arm moves the mass, the inertia and the arm's first mode at the same instant — which
## is §0's claim made literal: they are the same polygon.

signal document_changed(document: AirframeDocument)

## New plates arrive at this size, in mm — big enough to see and grab at the default zoom, small
## enough that it is obviously a starting point rather than a suggestion about your frame.
const NEW_PLATE_MM := 40.0
const NEW_ARM_LENGTH_MM := 110.0
const NEW_ARM_ROOT_MM := 14.0
const NEW_ARM_TIP_MM := 10.0

## Where an exported sheet lands. Beside the frames rather than in a dialog: a builder who has just
## drawn something wants the file, and the shell opens the folder so they can see it arrive.
const EXPORT_DIRECTORY := "user://exports"

const SNAP_CHOICES := [
	{"label": "0.5 mm", "value": 0.5},
	{"label": "1 mm", "value": 1.0},
	{"label": "5 mm", "value": 5.0},
	{"label": "off", "value": 0.0},
]

## What the Export menu offers, in the order a builder needs them: the sheet you print, the sheet
## you cut, the file a machine reads, and the solid another program opens.
const EXPORTS := [
	{"label": "Print sheet (SVG, 1:1)", "extension": "svg", "layout": FrameExport.LAYOUT_ASSEMBLY},
	{"label": "Cut sheet (SVG, nested)", "extension": "svg", "layout": FrameExport.LAYOUT_NEST},
	{"label": "Cut file (DXF)", "extension": "dxf", "layout": FrameExport.LAYOUT_NEST},
	{"label": "Assembly (STL)", "extension": "stl", "layout": FrameExport.LAYOUT_ASSEMBLY},
]

var editor: FramePlanEditor
## The same document, extruded. Airframe is a STACK, and a top view cannot show a stack — plate
## roles, standoff height and which plate an arm is sandwiched between are numbers in the plan view
## and are the whole shape here.
var view_3d: Frame3DView
var shelf: FrameLayoutShelf
var controls: FrameControls
var numbers: FrameNumbersDrawer
var catalog: PartsCatalog

var _canvas_host: Control
var _view_2d_button: Button
var _view_3d_button: Button
var _zoom_label: Label
## The catalog entry the open document was started from, when it was. Kept for one reason only:
## `FrameModel` needs the surface material and the mount table, and neither is in the document.
var _source_frame: Dictionary = {}
var _open_button: MenuButton
var _export_button: MenuButton
var _import_dialog: FileDialog
var _symmetry_button: CheckButton
var _status: Label
var _selected_plate := -1
## True while a document is being opened. `FramePlanEditor.open` emits `document_changed` like any
## other edit, and without this flag every open would immediately mark the frame it just opened as
## hand-drawn — which would hide the layout sliders on a layout the builder had only just chosen.
var _opening := false


func _init(p_catalog: PartsCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()

	# AN OPAQUE BACKDROP, UNDER EVERYTHING ELSE IN THE ROOM. This room covers the 3D view rather
	# than sitting beside it, and a transparent Control let Lab's turntable show through every gap
	# around the canvas — so a builder drawing a frame watched a different drone's props turning
	# behind their own toolbar.
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

	# The three columns of the room. An HBox rather than anchors so the canvas takes whatever the
	# shelf and the controls do not — the two side columns have fixed widths because they are
	# control surfaces and a control that moves as the window resizes is a control you re-find
	# every time.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	column.add_child(body)

	shelf = FrameLayoutShelf.new()
	shelf.layout_chosen.connect(_on_layout_chosen)
	shelf.frame_chosen.connect(_on_saved_frame_chosen)
	body.add_child(shelf)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	body.add_child(middle)

	# The plan view and the 3D view share one rectangle and one visibility switch, rather than
	# splitting it. Half a canvas to draw in and half a model too small to read is worse than
	# either whole, and the toggle is one click — see `set_view_3d`.
	_canvas_host = Control.new()
	_canvas_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_host.clip_contents = true
	middle.add_child(_canvas_host)

	editor = FramePlanEditor.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.document_changed.connect(_on_canvas_edited)
	editor.selection_changed.connect(_on_selection_changed)
	editor.view_changed.connect(_refresh_zoom_label)
	_canvas_host.add_child(editor)

	view_3d = Frame3DView.new()
	view_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_3d.visible = false
	view_3d.plate_picked.connect(_on_selection_changed)
	view_3d.plate_dragged.connect(_on_3d_drag)
	_canvas_host.add_child(view_3d)

	numbers = FrameNumbersDrawer.new()
	middle.add_child(numbers)

	controls = FrameControls.new()
	controls.document_changed.connect(_on_document_edited)
	controls.edit_began.connect(func() -> void: editor.history.record(editor.document))
	body.add_child(controls)


# ---------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------

## The tools, in a FLOW container rather than a row: a toolbar whose length is fixed and whose
## window is not has to wrap, or its last controls draw underneath the column beside it.
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

	_export_button = MenuButton.new()
	_export_button.text = "Export"
	for spec in EXPORTS:
		_export_button.get_popup().add_item(str(spec["label"]))
	_export_button.get_popup().id_pressed.connect(_on_export_chosen)
	row.add_child(_export_button)
	row.add_child(_button("Import", _on_import,
		"Bring an outline in from an SVG or DXF — it arrives as plates you can edit"))
	# Print is a BUTTON and Export is a menu, because they are different acts. Export is a choice
	# between four files; printing is the one thing a builder does over and over while drawing, and
	# burying it two clicks down a menu made the 1:1 check — the only check that catches a scale
	# error — the most expensive thing in the room to reach.
	row.add_child(_button("Print", _on_print,
		"Open the 1:1 sheet in your viewer, ready to print at 100%"))
	row.add_child(VSeparator.new())

	row.add_child(_button("+ Plate", _on_add_plate))
	row.add_child(_button("+ Arm", _on_add_arm))
	row.add_child(_button("+ Hardware", _on_add_hardware,
		"An M3 standoff and its two screws, on the selected plate"))
	row.add_child(_button("+ Motor mount", _on_add_motor_mount,
		"A motor and its four bolt holes, cut into the selected plate"))
	row.add_child(_button("Copy", _on_duplicate_plate, "Copy the selected plate"))
	row.add_child(_button("Mirror", _on_replicate,
		"Repeat the selected arm around the origin, once per arm the layout has"))
	row.add_child(_button("Delete", _on_delete))
	row.add_child(VSeparator.new())

	row.add_child(_button("Undo", func() -> void: editor.undo()))
	row.add_child(VSeparator.new())

	row.add_child(_button("−", func() -> void: _zoom(1.0 / FramePlanEditor.ZOOM_STEP), "Zoom out"))
	row.add_child(_button("+", func() -> void: _zoom(FramePlanEditor.ZOOM_STEP), "Zoom in"))
	row.add_child(_button("Fit", _on_fit, "Frame the whole drawing  (F)"))

	_view_2d_button = _button("2D", func() -> void: set_view_3d(false), "The plan you draw in")
	_view_2d_button.toggle_mode = true
	_view_2d_button.button_pressed = true
	row.add_child(_view_2d_button)

	_view_3d_button = _button("3D", func() -> void: set_view_3d(true),
		"The same frame, extruded — click a plate to select it, drag it to move it, orbit on empty space")
	_view_3d_button.toggle_mode = true
	row.add_child(_view_3d_button)

	_zoom_label = Label.new()
	_zoom_label.theme_type_variation = &"SmallLabel"
	_zoom_label.custom_minimum_size = Vector2(46, 0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_zoom_label)
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

	_status = Label.new()
	_status.theme_type_variation = &"SmallLabel"
	# The only thing here whose length is unbounded — it carries sentences about what just happened.
	# Clipped rather than allowed to push the toolbar wider than the room.
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)

	_compact(_open_button)
	_compact(_export_button)
	return row


static func _button(text: String, action: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	_compact(button)
	return button


## Shrinks a control to workbench scale. Applied per control rather than by editing the theme,
## because everywhere else in the app these sizes are right; it is the DENSITY here that is wrong.
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

## What the room opens on: a quad X at a sensible size.
##
## A GENERATED LAYOUT, NOT A CATALOG PRODUCT, and that is the change this version of the room is
## built around. Opening on somebody's 5" freestyle frame put a vendor, a published mass and an
## inch size on screen in front of a builder who has not chosen any of those, and invited them to
## edit a product rather than design a part. A Quad X at 110 mm is the same amount of geometry to
## look at and makes no claim about anything: it is a starting point, and every number on it is a
## number they can move.
##
## `frame` is still accepted, and still used when it is non-empty, because Lab hands the room the
## frame currently fitted to the build and starting from what you were just looking at is worth
## keeping. It opens as a copy: the moment you move an outline it is no longer the product the
## vendor published.
func start_from(frame: Dictionary) -> void:
	_source_frame = frame
	if frame.is_empty():
		_open(FrameLayouts.build("quad_x"), "Quad X, 110 mm arms. Everything on the right is yours to move.")
		return
	var preset := AirframeDocument.from_catalog_frame(frame)
	_open(FrameLibrary.duplicate_of(preset, "%s (copy)" % preset.name),
		"Started from %s — a copy, so the vendor's mass no longer applies." % preset.name)


func _on_new() -> void:
	_open(FrameEdits.new_frame("Untitled frame"),
		"New frame. Pick a layout on the left, or add a plate.")


func _on_layout_chosen(layout_id: String) -> void:
	var entry := FrameLayouts.template(layout_id)
	_open(FrameLayouts.build(layout_id),
		"%s — %d arms, %d motors. Size it on the right." % [
			str(entry.get("name", layout_id)), (entry.get("arms", []) as Array).size(),
			(entry.get("arms", []) as Array).size() * int(entry.get("motors_per_arm", 1))])


func _on_saved_frame_chosen(path: String) -> void:
	var document := FrameLibrary.load_frame(path)
	_open(document, "Opened %s." % document.name)


## Opens a document into every part of the room at once. One function, because a room where the
## canvas, the controls and the numbers are pointed at a new frame by three separate call sites is
## a room where one of them eventually is not.
func _open(document: AirframeDocument, status: String) -> void:
	_opening = true
	editor.open(document)
	_opening = false
	_selected_plate = -1
	controls.show_document(document)
	numbers.show_document(document)
	if view_3d.visible:
		view_3d.show_document(document, _source_frame)
	_set_status(status)


## The Open menu, rebuilt each time it is shown: the builder's own frames first, then the catalog
## presets as starting points. Rebuilt rather than cached because the library is a directory of
## files, and a menu built at startup would not know about a frame saved five minutes ago.
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
		_on_saved_frame_chosen(metadata as String)
		return
	if metadata is Dictionary:
		# A PRESET OPENS AS A COPY. Editing one in place would mean a builder's changes lived in the
		# app's own catalog and vanished on update.
		var preset := AirframeDocument.from_catalog_frame(metadata as Dictionary)
		_open(FrameLibrary.duplicate_of(preset, "%s (copy)" % preset.name),
			"Started from %s. It is a copy — the vendor's mass no longer applies." % preset.name)


func _on_save() -> void:
	if editor.document == null:
		return
	if FrameLibrary.save(editor.document):
		shelf.refresh_saved()
		_set_status("Saved %s." % editor.document.name)
	else:
		# Said out loud. A save that failed silently would let somebody close the app believing an
		# evening's drawing was on disk.
		_set_status("COULD NOT SAVE %s — check disk permissions." % editor.document.name)


func _on_duplicate() -> void:
	if editor.document == null:
		return
	_open(FrameLibrary.duplicate_of(editor.document, "%s (copy)" % editor.document.name),
		"Duplicated. This copy has no vendor figures.")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

## Writes one of the four formats and shows the builder where it went.
##
## The folder is opened rather than a path being printed, because a file you cannot find has not
## been exported. On a headless run `OS.shell_open` does nothing and the status line still names
## the path, which is why the path is in the message as well.
func _on_export_chosen(id: int) -> void:
	if editor.document == null or id < 0 or id >= EXPORTS.size():
		return
	var spec: Dictionary = EXPORTS[id]
	DirAccess.make_dir_recursive_absolute(EXPORT_DIRECTORY)
	var path := "%s/%s.%s" % [EXPORT_DIRECTORY,
		_safe_file_name(editor.document.name), str(spec["extension"])]
	if str(spec["layout"]) == FrameExport.LAYOUT_NEST and str(spec["extension"]) == "svg":
		path = "%s/%s-cut.svg" % [EXPORT_DIRECTORY, _safe_file_name(editor.document.name)]
	if not FrameExport.write(editor.document, path, str(spec["layout"])):
		_set_status("COULD NOT WRITE %s." % path)
		return
	_set_status("Wrote %s — %s" % [ProjectSettings.globalize_path(path), str(spec["label"])])
	OS.shell_open(ProjectSettings.globalize_path(EXPORT_DIRECTORY))


## A frame name as a file name. Same rule as `FrameLibrary._safe`: anything that is not a letter, a
## digit or a dash becomes an underscore, so a frame called `5" X / v2` still lands on disk.
static func _safe_file_name(text: String) -> String:
	var out := ""
	for index in text.length():
		var character := text[index]
		out += character if character.is_valid_identifier() or character.is_valid_int() \
			or character == "-" else "_"
	return "frame" if out.is_empty() else out


# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------

## The picker. Built on first use rather than in `_init`, because a `FileDialog` is a window and a
## room that constructs one at startup pays for it in every headless test that never opens a file.
func _on_import() -> void:
	if _import_dialog == null:
		_import_dialog = FileDialog.new()
		_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		# ACCESS_FILESYSTEM, not ACCESS_RESOURCES: the file a builder wants is on their disk, in
		# whatever folder their drawing program saves to, and a dialog rooted at res:// can never
		# reach it.
		_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_dialog.use_native_dialog = true
		_import_dialog.add_filter("*.svg,*.dxf", "Outlines (SVG, DXF)")
		_import_dialog.add_filter("*.svg", "SVG")
		_import_dialog.add_filter("*.dxf", "DXF")
		_import_dialog.file_selected.connect(import_file)
		add_child(_import_dialog)
	_import_dialog.popup_centered_ratio(0.7)


## Reads a file into the open frame. Public and path-taking so the whole import path is testable
## without a dialog — the dialog's only job is to choose the string this takes.
##
## ATOMIC. A file that cannot be read leaves the document untouched and says why on the status
## line: `FrameImport` returns either every loop or none, and the history entry below is recorded
## only once the read has already succeeded, so a refused import cannot leave an undo step that
## undoes nothing.
func import_file(path: String) -> bool:
	var result := FrameImport.read_file(path)
	if str(result["error"]) != "":
		_set_status(str(result["error"]))
		return false

	if editor.document == null:
		_open(FrameEdits.new_frame(path.get_file().get_basename()), "")
	editor.history.record(editor.document)
	var added := FrameImport.into_document(editor.document, result["loops"])
	if int(added["count"]) == 0:
		_set_status("Nothing in %s was a closed outline big enough to be a part." % path.get_file())
		return false

	_select(int(added["first_index"]))
	# An imported outline is a drawing, whatever the frame was before it: the layout sliders cannot
	# regenerate a shape somebody drew elsewhere, and leaving them live would let one drag throw the
	# imported geometry away.
	mark_hand_edited()
	_on_document_edited(editor.document)
	editor.fit_to_document()
	var span: Vector2 = added["span_mm"]
	# The SPAN IS IN THE MESSAGE, always. It is the one number that catches a unit mistake, and a
	# builder who sees 118 mm where they drew 90 knows in a second — which is the whole reason
	# `FrameImport` reports what it assumed rather than assuming quietly.
	_set_status("Imported %d plate%s from %s — %.1f × %.1f mm. %s" % [
		int(added["count"]), "" if int(added["count"]) == 1 else "s", path.get_file(),
		span.x, span.y, str(result["note"])])
	return true


# ---------------------------------------------------------------------------
# Print
# ---------------------------------------------------------------------------

## Writes the 1:1 sheet and hands it to whatever opens SVGs on this machine.
##
## THE FILE, not the folder Export opens. Godot has no print dialog of its own and cannot get one,
## so the honest maximum is to open the sheet in the viewer that does have one — the builder is
## then one Cmd-P away, rather than in a folder hunting for a file whose name they must recognise.
##
## The message names the two things that ruin a 1:1 print, because both are one click away in every
## print dialog there is: a scale other than 100%, and "fit to page", which silently rescales the
## sheet by a few percent and produces a plate that is wrong by a millimetre across a 5" frame.
func _on_print() -> void:
	if editor.document == null:
		return
	DirAccess.make_dir_recursive_absolute(EXPORT_DIRECTORY)
	var path := "%s/%s.svg" % [EXPORT_DIRECTORY, _safe_file_name(editor.document.name)]
	if not FrameExport.write(editor.document, path, FrameExport.LAYOUT_ASSEMBLY):
		_set_status("COULD NOT WRITE %s." % path)
		return
	var absolute := ProjectSettings.globalize_path(path)
	OS.shell_open(absolute)
	_set_status("Opened %s — print at 100%%, not \"fit to page\", then check the 50 mm bar." %
		absolute)


# ---------------------------------------------------------------------------
# Edits
# ---------------------------------------------------------------------------

func _on_add_plate() -> void:
	editor.history.record(editor.document)
	var index := FrameEdits.add_rectangle(editor.document, Vector2.ZERO,
		NEW_PLATE_MM, NEW_PLATE_MM, FrameEdits.DEFAULT_PLATE_THICKNESS_MM, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	_select(index)
	_on_document_edited(editor.document)
	_set_status("Added a %.0f mm plate. Size it on the right, or drag its corners." % NEW_PLATE_MM)


func _on_add_arm() -> void:
	editor.history.record(editor.document)
	# Added on the 45 degree diagonal, which is where the first arm of an X goes, and then mirrored.
	# Starting anywhere else would make the common case two steps.
	var index := FrameEdits.add_arm(editor.document, 45.0, NEW_ARM_LENGTH_MM,
		NEW_ARM_ROOT_MM, NEW_ARM_TIP_MM, FrameEdits.DEFAULT_ARM_THICKNESS_MM)
	_select(index)
	_on_document_edited(editor.document)
	_set_status("Added an arm with a motor at its tip. Mirror it to make a ring.")


## An M3 standoff and its two screws, on the selected plate.
##
## ON THE SELECTED PLATE, at its centroid, and at that plate's own height in the stack. A standoff
## dropped at the origin at z=0 regardless of what is selected would be right for the one frame
## whose centre plate is at the origin and wrong for every arm, every side plate, and every frame
## drawn off-centre — and wrong in a way that reads as correct, because the Fasteners tab would show
## a perfectly plausible joint through nothing.
func _on_add_hardware() -> void:
	if editor.document == null:
		return
	editor.history.record(editor.document)
	var at := Vector2.ZERO
	var base_z := 0.0
	var thickness := FrameEdits.DEFAULT_PLATE_THICKNESS_MM
	if _selected_plate >= 0:
		var plate: Dictionary = editor.document.plates[_selected_plate]
		at = PolygonProps.centroid(AirframeDocument.plate_outline(plate))
		base_z = AirframeDocument.plate_z_mm(plate)
		thickness = AirframeDocument.plate_thickness_mm(plate)
	var length := float(FrameLayouts.DEFAULTS["standoff_len_mm"])
	if FrameEdits.add_hardware(editor.document, at, length, base_z, thickness) < 0:
		_set_status("Could not add hardware to this frame.")
		return
	_on_document_edited(editor.document)
	_set_status("Added an M3 standoff, %.0f mm, and its two screws. " % length +
		"Length and thread are on the Fasteners tab.")


## A motor and the four holes it bolts through, cut into the selected plate.
##
## Placed at the arm's TIP when the selected plate is an arm and at the plate's centroid otherwise,
## and rotated to the arm's own bearing: a motor is bolted square to the arm it sits on, and a
## pattern left axis-aligned on a 45 degree arm puts two of its four holes nearer the edge than the
## other two for no reason the builder chose.
func _on_add_motor_mount() -> void:
	if editor.document == null:
		return
	if _selected_plate < 0:
		# Named rather than silently ignored: the button did nothing, and a builder who is not told
		# why presses it three more times.
		_set_status("Select the plate the motor bolts to first.")
		return
	var plate: Dictionary = editor.document.plates[_selected_plate]
	var centre := PolygonProps.centroid(AirframeDocument.plate_outline(plate))
	var angle := 0.0
	var tip := AirframeDocument.point_of(plate.get("tip_point", [INF, INF]))
	if is_finite(tip.x):
		var root := AirframeDocument.point_of(plate.get("root_point", [0.0, 0.0]))
		centre = tip
		angle = rad_to_deg((tip - root).angle())

	editor.history.record(editor.document)
	var pitch := float(FrameLayouts.DEFAULTS["motor_pitch_mm"])
	var motor := FrameEdits.add_motor_mount(editor.document, _selected_plate, centre, pitch, angle)
	if motor < 0:
		_set_status("A %.0f mm bolt pattern does not fit inside that plate." % pitch)
		return
	mark_hand_edited()
	_on_document_edited(editor.document)
	var balance := FrameEdits.spin_balance(editor.document)
	_set_status("Added a motor on a %.0f×%.0f pattern. %s" % [pitch, pitch,
		"Spins balance." if is_zero_approx(balance) else
		"Spins are off by %.0f — the count cannot balance until it is even." % absf(balance)])


## Copies the selected plate on top of itself, offset enough to grab.
##
## OFFSET, not in place. A duplicate that lands exactly on its original is invisible, un-selectable
## and indistinguishable from nothing having happened — and the builder's next click picks the copy
## while they believe they have the original.
func _on_duplicate_plate() -> void:
	if _selected_plate < 0 or editor.document == null:
		return
	editor.history.record(editor.document)
	var copy: Dictionary = (editor.document.plates[_selected_plate] as Dictionary).duplicate(true)
	editor.document.plates.append(copy)
	var index := editor.document.plates.size() - 1
	FrameEdits.move_plate(editor.document, index, Vector2(NEW_PLATE_MM * 0.25, NEW_PLATE_MM * 0.25))
	_select(index)
	_on_document_edited(editor.document)
	_set_status("Copied the plate. Drag it, or set its height on the right.")


## Repeats the selected arm around the origin, once per arm the frame's layout calls for.
##
## The count comes from the layout when there is one and defaults to four when there is not, rather
## than always being four: a builder drawing a hexacopter pressed "Mirror ×4" and got a six-arm
## frame with four arms in it, which is a shape nothing warns about because every individual part
## of it is fine.
func _on_replicate() -> void:
	if _selected_plate < 0:
		_set_status("Select an arm first, then mirror it.")
		return
	editor.history.record(editor.document)
	var count := 4
	var entry := FrameLayouts.template(FrameLayouts.layout_id_of(editor.document))
	if not entry.is_empty():
		count = (entry["arms"] as Array).size()
	FrameEdits.replicate_radially(editor.document, _selected_plate, count)
	_on_document_edited(editor.document)
	_set_status("Repeated %d ways around the origin." % count)


## Deletes whatever is selected — a plate, and the motor standing on its tip.
##
## THE MOTOR GOES WITH THE ARM. Leaving it behind gives a frame with a motor hanging in mid-air at
## the end of an arm that no longer exists: `ControlEffectiveness` still counts it, the mixer still
## drives it, and the aircraft flies on thrust applied to nothing.
func _on_delete() -> void:
	if _selected_plate < 0 or editor.document == null:
		return
	editor.history.record(editor.document)
	var plate: Dictionary = editor.document.plates[_selected_plate]
	var tip := AirframeDocument.point_of(plate.get("tip_point", [INF, INF]))
	if is_finite(tip.x):
		for index in range(editor.document.motors.size() - 1, -1, -1):
			var motor: Dictionary = editor.document.motors[index]
			if AirframeDocument.point_of(motor.get("position_mm", [0, 0])).distance_to(tip) < 0.001:
				editor.document.motors.remove_at(index)
	editor.document.plates.remove_at(_selected_plate)
	_select(-1)
	_on_document_edited(editor.document)
	_set_status("Deleted a plate.")


# ---------------------------------------------------------------------------
# Keeping the room in step
# ---------------------------------------------------------------------------

## The one place an edit is published. Everything in the room hangs off this, and every edit —
## a dragged vertex, a typed number, a 3D move — arrives here.
##
## A HAND EDIT CLEARS THE GENERATED TAG. The layout sliders regenerate arms from parameters, which
## is exactly right until somebody has drawn a swept front end onto one of them: from then on there
## is no single "arm length" to set, and a slider that regenerated would silently throw the drawing
## away. Clearing the tag hides those sliders, which is the honest outcome — the frame stopped
## being a layout the moment it became a drawing.
func _on_document_edited(document: AirframeDocument) -> void:
	editor.queue_redraw()
	numbers.show_document(document)
	controls.show_document(document, _selected_plate, controls.selected_motor)
	_refresh_zoom_label()
	# The 3D view is rebuilt only while it is the view you are looking at: extruding every plate on
	# every mouse motion of a drag is a full mesh rebuild per frame for a picture nobody is at.
	if view_3d.visible:
		view_3d.show_document(document, _source_frame)
	document_changed.emit(document)


## Marks the open document as hand-drawn rather than generated. Called by the canvas, not by the
## controls column, which is what keeps the layout sliders working while they are the thing being
## dragged.
func mark_hand_edited() -> void:
	if editor.document != null and FrameLayouts.layout_id_of(editor.document) != "":
		editor.document.revision = "drawn"


## An edit that arrived from the canvas: the same publication as any other, plus the note that this
## frame is now a drawing rather than a set of layout parameters.
func _on_canvas_edited(document: AirframeDocument) -> void:
	if not _opening:
		mark_hand_edited()
	_on_document_edited(document)


func _on_selection_changed(plate_index: int) -> void:
	_select(plate_index)
	controls.show_document(editor.document, _selected_plate, -1)


## A plate moved in the 3D view: the same edit the plan canvas makes, arriving from the other view.
func _on_3d_drag(plate_index: int, delta_mm: Vector2, delta_z_mm: float) -> void:
	if editor.document == null:
		return
	if not is_zero_approx(delta_z_mm):
		var plate: Dictionary = editor.document.plates[plate_index]
		FrameEdits.set_plate_z(editor.document, plate_index,
			AirframeDocument.plate_z_mm(plate) + delta_z_mm)
	if delta_mm != Vector2.ZERO:
		FrameEdits.move_plate(editor.document, plate_index, delta_mm)
	mark_hand_edited()
	_on_document_edited(editor.document)


func _select(plate_index: int) -> void:
	_selected_plate = plate_index
	editor.selected_plate = plate_index
	view_3d.selected_plate = plate_index
	editor.queue_redraw()


# ---------------------------------------------------------------------------
# The two views
# ---------------------------------------------------------------------------

## Switches between the plan you draw in and the frame you drew.
##
## BOTH VIEWS NOW HAVE HANDS, which is the change from the first version of this room. 3D used to
## be look-only, and that made the one property a plan view cannot show — height in the stack —
## the one property you could not edit where you could see it. Clicking a plate in 3D selects it,
## dragging moves it in plan, and dragging with Shift raises or lowers it.
func set_view_3d(on: bool) -> void:
	view_3d.visible = on
	editor.visible = not on
	_view_2d_button.button_pressed = not on
	_view_3d_button.button_pressed = on
	if on:
		view_3d.show_document(editor.document, _source_frame)
		view_3d.selected_plate = _selected_plate
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
	# Blank in 3D. The number means "times the scale Fit chose", which is a statement about a flat
	# drawing; the orbit has a camera distance instead.
	_zoom_label.text = "" if view_3d.visible else "%.1f×" % editor.zoom_ratio()


func _set_status(text: String) -> void:
	_status.text = text
