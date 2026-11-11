class_name DesignFileBar
extends Control
## The Design Space's save/load controls (PLAN Section 9): a one-line row beside "Classes" (the
## design's name, Save, Save as, Open and a small status) and a small dialog under it for the name
## to save as or the recent designs to open. Monochrome on the dark stage; the only colour is the
## warning amber, used for a refusal's one-line reason inside the dialog.
##
## It only shows and reports. Every press emits, and DesignSpace runs DesignFile, so a test drives
## the same DesignSpace method a press does. The whole control ignores the mouse outside its own
## buttons, so the stage stays draggable around it.

signal save_pressed
signal save_as_pressed
signal open_pressed
signal fly_pressed
signal identity_pressed
signal field_pressed
signal mission_pressed
## A room from the menu's Rooms group (the DesignApp opens it): setup, frame_bench, bench, esc_bench, studio, projects.
signal room_pressed(room_id: String)
signal save_as_confirmed(design_name: String)
signal open_chosen(file_name: String)
signal dialog_closed

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const WARN_INK := LothalTheme.WARNING
const ROW_LEFT := 150.0
const ROW_TOP := 20.0
const DIALOG_W := 360.0
const MENU_W := 130.0
const DIALOG_TOP := 60.0
## How many recent designs the open dialog lists.
const MAX_RECENT := 8
## The Rooms group of the menu: every room that is not the design itself. [id, label, tooltip].
const ROOMS := [
	["setup", "Setup pages", "Frame, propulsion, power, control, video, printed and config sheets"],
	["bench", "Thrust bench", "Run the fitted motor and prop on the stand"],
	["esc_bench", "ESC bench", "Run the fitted ESC under load"],
	["frame_bench", "Frame bench", "Shake and load the frame"],
	["studio", "Studio", "Flights already flown"],
	["projects", "Projects", "All saved drones"],
]

var name_label: Label
var status_label: Label
var save_button: Button
var save_as_button: Button
var open_button: Button
var fly_button: Button
## The identity chip (B5): build name, class and weight; press for the sheet.
var identity_button: Button
## Under the row: refusals and short notices ("Cannot fly: ...").
var toast: DsToast
## True while Fly it is loading the sim: the button is disabled and reads "Loading...".
var fly_busy := false
var field_button: Button
var mission_button: Button
var room_buttons := {}
var menu_button: Button
var menu: PanelContainer
var dialog: PanelContainer
var dialog_title: Label
var name_edit: LineEdit
var confirm_button: Button
var cancel_button: Button
var reason_label: Label
var list_box: VBoxContainer
var recent_buttons: Array = []
var mode := ""    ## "", "save_as" or "open"
var _row: HBoxContainer
var _save_row: HBoxContainer


func _init() -> void:
	name = "DesignFileBar"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "FileRow"
	_row.offset_left = ROW_LEFT
	_row.offset_top = ROW_TOP
	_row.offset_right = ROW_LEFT + 660.0
	_row.offset_bottom = ROW_TOP + 32.0
	_row.add_theme_constant_override("separation", 4)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	name_label = _label("Untitled", INK, LothalTheme.FONT_SIZE_BODY)
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(name_label)
	fly_button = DsUi.button("Fly it", false, true)
	fly_button.tooltip_text = "Fly this build in the simulator (F)"
	fly_button.pressed.connect(func(): fly_pressed.emit())
	_row.add_child(fly_button)
	menu_button = _button("⋯")
	menu_button.name = "MenuButton"
	menu_button.tooltip_text = "Save, Open, Field, Mission"
	menu_button.pressed.connect(func(): set_menu_open(not menu.visible))
	_row.add_child(menu_button)
	_build_menu()
	identity_button = DsUi.button("")
	identity_button.name = "IdentityChip"
	identity_button.tooltip_text = "What is being designed: class, parts, weight, where it came from"
	identity_button.visible = false
	identity_button.clip_text = true
	identity_button.custom_minimum_size = Vector2(200, 0)
	identity_button.pressed.connect(func(): identity_pressed.emit())
	_row.add_child(identity_button)
	status_label = _label("", INK_FAINT, LothalTheme.FONT_SIZE_SMALL)
	status_label.custom_minimum_size = Vector2(150, 0)
	status_label.clip_text = true
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(status_label)
	_build_dialog()
	toast = DsToast.new()
	toast.offset_left = ROW_LEFT
	toast.offset_top = ROW_TOP + 38.0
	add_child(toast)


## Fly it's busy state: disabled and "Loading..." while the sim builds, restored after.
func set_fly_busy(busy: bool) -> void:
	fly_busy = busy
	DsUi.set_busy(fly_button, busy, "Loading...")


## The one menu behind the dots: every action that is not the primary one, each still a button of its own.
func _build_menu() -> void:
	menu = PanelContainer.new()
	menu.name = "FileMenu"
	menu.visible = false
	menu.offset_left = ROW_LEFT + 120.0 + 4.0 + 72.0 + 4.0 + 34.0 - MENU_W
	menu.offset_top = ROW_TOP + 36.0
	menu.offset_right = menu.offset_left + MENU_W
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := DsUi.panel_style()
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	menu.add_theme_stylebox_override("panel", box)
	add_child(menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	menu.add_child(v)
	var items := [["Save", "save_button", "save_pressed", ""], ["Save as", "save_as_button", "save_as_pressed", ""],
		["Open", "open_button", "open_pressed", ""], ["Field", "field_button", "field_pressed", "Open the Field room: courses, sites, weather and worlds"],
		["Mission", "mission_button", "mission_pressed", "Pick a mission and an environment, then watch or run this design"]]
	for it in items:
		if it[0] == "Field":
			v.add_child(DsUi.rule())
		var b := _button(String(it[0]))
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = String(it[3])
		var which := String(it[2])
		b.pressed.connect(_menu_item.bind(which))
		set(StringName(it[1]), b)
		v.add_child(b)
	v.add_child(DsUi.rule())
	for room in ROOMS:
		var rb := _button(String(room[1]))
		rb.name = "Room_" + String(room[0])
		rb.flat = true
		rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rb.tooltip_text = String(room[2])
		rb.pressed.connect(_room_item.bind(String(room[0])))
		room_buttons[String(room[0])] = rb
		v.add_child(rb)


func _room_item(room_id: String) -> void:
	set_menu_open(false)
	room_pressed.emit(room_id)


func _menu_item(which: String) -> void:
	set_menu_open(false)
	if which == "save_pressed":
		save_pressed.emit()
	elif which == "save_as_pressed":
		save_as_pressed.emit()
	elif which == "open_pressed":
		open_pressed.emit()
	elif which == "field_pressed":
		field_pressed.emit()
	else:
		mission_pressed.emit()


func set_menu_open(want: bool) -> void:
	if want and menu_button.size.x > 0.0:
		menu.offset_left = _row.offset_left + menu_button.position.x + menu_button.size.x - MENU_W
		menu.offset_right = menu.offset_left + MENU_W
	menu.visible = want


func _input(event: InputEvent) -> void:
	if menu != null and menu.visible and event is InputEventMouseButton and event.pressed:
		var p := (event as InputEventMouseButton).position
		if not menu.get_global_rect().has_point(p) and not menu_button.get_global_rect().has_point(p):
			set_menu_open(false)


func _build_dialog() -> void:
	dialog = PanelContainer.new()
	dialog.name = "FileDialog"
	dialog.visible = false
	dialog.anchor_left = 0.5
	dialog.anchor_right = 0.5
	dialog.offset_left = -DIALOG_W * 0.5
	dialog.offset_right = DIALOG_W * 0.5
	dialog.offset_top = DIALOG_TOP
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.075, 0.085, 0.96)
	box.border_color = Color(1, 1, 1, 0.14)
	box.set_border_width_all(1)
	box.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	dialog.add_theme_stylebox_override("panel", box)
	add_child(dialog)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dialog.add_child(v)
	dialog_title = _label("", INK_FAINT, LothalTheme.FONT_SIZE_SMALL)
	v.add_child(dialog_title)
	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 6)
	v.add_child(_save_row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name this design"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.max_length = 60
	name_edit.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	name_edit.add_theme_color_override("font_color", INK)
	name_edit.add_theme_color_override("caret_color", INK)
	# The theme's focus ring is accent blue; this stays monochrome.
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.05)
	field.border_color = Color(1, 1, 1, 0.22)
	field.set_border_width_all(1)
	field.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	field.content_margin_left = 8
	field.content_margin_right = 8
	field.content_margin_top = 5
	field.content_margin_bottom = 5
	name_edit.add_theme_stylebox_override("normal", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = Color(1, 1, 1, 0.55)
	name_edit.add_theme_stylebox_override("focus", field_focus)
	name_edit.text_submitted.connect(func(t: String): save_as_confirmed.emit(t))
	_save_row.add_child(name_edit)
	confirm_button = _button("Save")
	confirm_button.pressed.connect(func(): save_as_confirmed.emit(name_edit.text))
	_save_row.add_child(confirm_button)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 2)
	v.add_child(list_box)
	reason_label = _label("", WARN_INK, LothalTheme.FONT_SIZE_SMALL)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(DIALOG_W - 28.0, 0)
	reason_label.visible = false
	v.add_child(reason_label)
	cancel_button = _button("Cancel")
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_button.pressed.connect(close_dialog)
	v.add_child(cancel_button)


## The design's name beside the buttons ("Untitled" until it has one).
func show_name(design_name: String) -> void:
	name_label.text = design_name if design_name != "" else "Untitled"
	name_label.add_theme_color_override("font_color", INK if design_name != "" else INK_MUTED)


## The chip's words; empty hides it.
func show_identity(chip_text: String) -> void:
	identity_button.text = chip_text
	identity_button.visible = chip_text != ""


func show_status(text: String) -> void:
	status_label.text = text


## The one-line reason of a refused save or load, in the warning amber, inside the open dialog.
func show_reason(text: String) -> void:
	reason_label.text = text
	reason_label.visible = text != ""


func open_save_as(default_name: String) -> void:
	mode = "save_as"
	dialog_title.text = "SAVE AS"
	_save_row.visible = true
	list_box.visible = false
	name_edit.text = default_name
	show_reason("")
	dialog.visible = true
	if is_inside_tree():
		name_edit.grab_focus()
		name_edit.select_all()


## `files` are design file names, newest first; at most MAX_RECENT are listed.
func open_open(files: Array) -> void:
	mode = "open"
	dialog_title.text = "OPEN  ·  RECENT"
	_save_row.visible = false
	list_box.visible = true
	for b in recent_buttons:
		list_box.remove_child(b)
		(b as Node).queue_free()
	recent_buttons = []
	if files.is_empty():
		var none := _label("No saved designs yet.", INK_MUTED, LothalTheme.FONT_SIZE_BODY)
		list_box.add_child(none)
		recent_buttons.append(none)
	for f in files.slice(0, MAX_RECENT):
		var file_name := String(f)
		var b := _button(file_name.get_basename())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.set_meta("file", file_name)
		b.pressed.connect(func(): open_chosen.emit(file_name))
		list_box.add_child(b)
		recent_buttons.append(b)
	show_reason("")
	dialog.visible = true


func close_dialog() -> void:
	var was := dialog.visible
	mode = ""
	dialog.visible = false
	show_reason("")
	if was:
		dialog_closed.emit()


func dialog_open() -> bool:
	return dialog.visible


## The screen rects the bar occupies (px, from offsets and minimum sizes so it holds headless):
## the row, and the dialog while it shows.
func rects(view_size: Vector2) -> Array:
	var out: Array = [Rect2(_row.offset_left, _row.offset_top, _row.offset_right - _row.offset_left, 32.0)]
	if menu.visible:
		out.append(Rect2(menu.offset_left, menu.offset_top, MENU_W, 5 * 30.0 + 20.0))
	if dialog.visible:
		var m := dialog.get_combined_minimum_size()
		var w := maxf(DIALOG_W, m.x)
		# A headless control reports no minimum height until it is laid out, so the rect also carries
		# an estimate from the rows it holds: a title, the rows, the reason line and Cancel.
		var rows := 1 if mode == "save_as" else maxi(recent_buttons.size(), 1)
		var est := 72.0 + 30.0 * rows + (36.0 if reason_label.visible else 0.0)
		out.append(Rect2(view_size.x * 0.5 - w * 0.5, DIALOG_TOP, w, maxf(maxf(dialog.size.y, m.y), est)))
	return out


func _label(text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	return DsUi.button(text)
