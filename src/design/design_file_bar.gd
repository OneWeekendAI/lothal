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
signal field_pressed
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
const DIALOG_TOP := 60.0
## How many recent designs the open dialog lists.
const MAX_RECENT := 8

var name_label: Label
var status_label: Label
var save_button: Button
var save_as_button: Button
var open_button: Button
var fly_button: Button
var field_button: Button
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
	_row.offset_right = ROW_LEFT + 620.0
	_row.offset_bottom = ROW_TOP + 32.0
	_row.add_theme_constant_override("separation", 4)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	name_label = _label("Untitled", INK, LothalTheme.FONT_SIZE_BODY)
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(name_label)
	save_button = _button("Save")
	save_button.pressed.connect(func(): save_pressed.emit())
	_row.add_child(save_button)
	save_as_button = _button("Save as")
	save_as_button.pressed.connect(func(): save_as_pressed.emit())
	_row.add_child(save_as_button)
	open_button = _button("Open")
	open_button.pressed.connect(func(): open_pressed.emit())
	_row.add_child(open_button)
	fly_button = _button("Fly it")
	fly_button.tooltip_text = "Fly this build in the simulator (F)"
	fly_button.pressed.connect(func(): fly_pressed.emit())
	_row.add_child(fly_button)
	field_button = _button("Field")
	field_button.tooltip_text = "Open the Field room: courses, sites, weather and worlds"
	field_button.pressed.connect(func(): field_pressed.emit())
	_row.add_child(field_button)
	status_label = _label("", INK_FAINT, LothalTheme.FONT_SIZE_SMALL)
	status_label.custom_minimum_size = Vector2(150, 0)
	status_label.clip_text = true
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(status_label)
	_build_dialog()


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
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	b.add_theme_color_override("font_color", INK_MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(1, 1, 1, 0.05)
	flat.border_color = Color(1, 1, 1, 0.12)
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	flat.content_margin_left = LothalTheme.SPACE_3
	flat.content_margin_right = LothalTheme.SPACE_3
	flat.content_margin_top = LothalTheme.SPACE_2
	flat.content_margin_bottom = LothalTheme.SPACE_2
	b.add_theme_stylebox_override("normal", flat)
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b
