class_name SectionList
extends PanelContainer
## The Lab's right-hand list — lab dock design §2/§3 (plans/2026-09-26-lab-dock-design.md).
##
## One section at a time: a header with the section's name and "N of M" (rows decided of rows
## modelled), then one row per item, three lines each — name and a status dot, the choice, and the
## one deciding number or a `⚠` limit. It DRAWS `SectionRows.rows()` and decides nothing: clicking a
## row asks the shell to open that row's page, clicking a row's choice line asks it to open the
## part finder, and the `›|` button asks to collapse.
##
## ## Collapsed
##
## A thin strip carrying the section name, drawn vertically, which restores the list when clicked.
## Collapsing does not change which section is selected (§2). The shell saves the state per project.
##
## ## Why rows never wrap
##
## Every label clips with an ellipsis and none autowraps, and a row is a fixed height. A row that
## grew a fourth line would push the list past the window — the thing §5.5 checks for in a picture.

signal row_opened(row_id: StringName)
signal pick_requested(row_id: StringName)
signal collapse_toggled(collapsed: bool)

const WIDTH := 280.0
const STRIP_WIDTH := 30.0
const ROW_HEIGHT := 60.0
const SOON_HEIGHT := 30.0
const HEADER_HEIGHT := 36.0

const STATUS_COLORS := {
	SectionRows.OK: LothalTheme.SUCCESS,
	SectionRows.WARN: LothalTheme.WARNING,
	SectionRows.BAD: LothalTheme.DANGER,
	SectionRows.SOON: LothalTheme.TEXT_FAINT,
}

var collapsed := false
var section := ""
var open_row: StringName = &""

var _rows: Array = []
var _full: VBoxContainer
var _title: Label
var _count: Label
var _collapse_button: Button
var _list: VBoxContainer
var _strip: Button
## row id -> the row's Control, for tests and for the highlight.
var _row_controls: Dictionary = {}


func _init() -> void:
	name = "SectionList"
	custom_minimum_size = Vector2(WIDTH, 0)
	clip_contents = true

	_full = VBoxContainer.new()
	_full.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(_full)

	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	head.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	_full.add_child(head)

	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)

	_count = Label.new()
	_count.theme_type_variation = "MutedLabel"
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)

	_collapse_button = Button.new()
	_collapse_button.name = "Collapse"
	_collapse_button.text = "›|"
	_collapse_button.flat = true
	_collapse_button.tooltip_text = "Hide the list. The strip that stays brings it back."
	_collapse_button.pressed.connect(func() -> void: set_collapsed(true, true))
	head.add_child(_collapse_button)

	_full.add_child(HSeparator.new())

	# CLIPPED, NOT SCROLLED, as the mockup's list is: no section has more rows than fit at 720.
	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.clip_contents = true
	_list.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	_full.add_child(_list)

	_strip = VerticalLabelButton.new()
	_strip.name = "Strip"
	_strip.tooltip_text = "Show the list"
	_strip.visible = false
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip.pressed.connect(func() -> void: set_collapsed(false, true))
	add_child(_strip)


## Shows `rows` (from `SectionRows.rows`) under `section_name`.
func show_section(section_name: String, section_rows: Array) -> void:
	section = section_name
	_rows = section_rows
	_title.text = section_name
	_count.text = SectionRows.header_text(section_rows)
	(_strip as VerticalLabelButton).caption = section_name
	_strip.queue_redraw()
	_rebuild()


func rows() -> Array:
	return _rows


func header_text() -> String:
	return "%s %s" % [_title.text, _count.text]


## Highlights the row whose page is open, or none for `&""`.
func set_open_row(row_id: StringName) -> void:
	open_row = row_id
	for id in _row_controls:
		var control: Control = _row_controls[id]
		control.add_theme_stylebox_override("panel", _row_box(id == row_id))


func set_collapsed(value: bool, emit := false) -> void:
	collapsed = value
	_full.visible = not value
	_strip.visible = value
	custom_minimum_size = Vector2(STRIP_WIDTH if value else WIDTH, 0)
	if emit:
		collapse_toggled.emit(value)


## The width this list takes on screen right now.
func current_width() -> float:
	return STRIP_WIDTH if collapsed else WIDTH


## The three lines a row shows, as drawn. For tests: asserts what is on screen, not the data.
func row_lines(row_id: StringName) -> PackedStringArray:
	var control: Control = _row_controls.get(row_id)
	if control == null:
		return PackedStringArray()
	return control.get_meta("lines", PackedStringArray())


func row_control(row_id: StringName) -> Control:
	return _row_controls.get(row_id)


func row_status(row_id: StringName) -> String:
	for row in _rows:
		if row["id"] == row_id:
			return str(row["status"])
	return ""


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_row_controls.clear()
	for row in _rows:
		var control := _soon_row(row) if bool(row.get("soon", false)) else _row(row)
		_list.add_child(control)
		_row_controls[row["id"]] = control
	set_open_row(open_row)


func _row(row: Dictionary) -> Control:
	var id: StringName = row["id"]
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % String(id).replace(":", "_")
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = "\n\n".join(PackedStringArray(row.get("why", [])))
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			row_opened.emit(id))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_label := _line(str(row["name"]), "MutedLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var dot := StatusDot.new(STATUS_COLORS.get(str(row["status"]), LothalTheme.TEXT_FAINT))
	dot.name = "Dot"
	top.add_child(dot)
	var chevron := _line("›", "MutedLabel")
	top.add_child(chevron)

	var choice_text := str(row["choice"])
	if row.has("pick"):
		# THE PART LINE SUMMONS THE FINDER (§2), not the row — a click on the row opens its page.
		var choice := Button.new()
		choice.name = "Choice"
		choice.flat = true
		choice.text = choice_text if choice_text != "" else "Choose…"
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.clip_text = true
		choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choice.tooltip_text = "Choose a different part"
		choice.add_theme_constant_override("h_separation", 0)
		choice.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		choice.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		choice.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		choice.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		choice.add_theme_color_override("font_hover_color", LothalTheme.ACCENT)
		choice.custom_minimum_size = Vector2(0, 20)
		choice.pressed.connect(func() -> void: pick_requested.emit(id))
		box.add_child(choice)
	else:
		box.add_child(_line(choice_text, ""))

	var line3 := str(row["line3"])
	var third := _line(line3, "SmallLabel")
	third.name = "Number"
	if line3.begins_with("⚠"):
		third.add_theme_color_override("font_color",
			LothalTheme.DANGER if str(row["status"]) == SectionRows.BAD else LothalTheme.WARNING)
	box.add_child(third)

	panel.set_meta("lines", PackedStringArray([str(row["name"]), choice_text, line3]))
	return panel


func _soon_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % String(row["id"])
	panel.custom_minimum_size = Vector2(0, SOON_HEIGHT)
	panel.tooltip_text = "Not modelled yet."
	var top := HBoxContainer.new()
	panel.add_child(top)
	var name_label := _line(str(row["name"]), "MutedLabel")
	name_label.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var pill := _line("soon", "SmallLabel")
	pill.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
	top.add_child(pill)
	panel.set_meta("lines", PackedStringArray([str(row["name"]), "soon", ""]))
	return panel


func _line(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	if variation != "":
		label.theme_type_variation = variation
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _row_box(open: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = LothalTheme.ACCENT_FILL if open else Color(0, 0, 0, 0)
	box.border_color = LothalTheme.ACCENT if open else LothalTheme.BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(LothalTheme.RADIUS_SMALL)
	box.content_margin_left = LothalTheme.SPACE_3
	box.content_margin_right = LothalTheme.SPACE_2
	box.content_margin_top = LothalTheme.SPACE_1
	box.content_margin_bottom = LothalTheme.SPACE_1
	return box


## The status dot: a filled circle in the status colour. A Control rather than a "●" glyph so the
## colour cannot depend on which font happens to carry the character.
class StatusDot extends Control:
	var color: Color

	func _init(p_color: Color) -> void:
		color = p_color
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_circle(size * 0.5, 4.0, color, true, -1.0, true)


## The collapsed strip: a button whose caption is drawn top-to-bottom, so a 30 px strip can still
## say which section's list it will bring back.
class VerticalLabelButton extends Button:
	var caption := ""

	func _init() -> void:
		flat = true
		custom_minimum_size = Vector2(STRIP_WIDTH - LothalTheme.SPACE_2 * 2, 0)

	func _draw() -> void:
		var font := get_theme_font("font")
		var font_size := get_theme_font_size("font_size")
		var shown := "‹  " + caption
		draw_set_transform(Vector2(size.x * 0.5 + font_size * 0.35, LothalTheme.SPACE_3), PI * 0.5)
		draw_string(font, Vector2.ZERO, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			LothalTheme.TEXT_MUTED)
		draw_set_transform(Vector2.ZERO)
