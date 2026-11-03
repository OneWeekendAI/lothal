class_name DesignerShell
extends Control
## The screen shell every part designer shares (the pack designer, the motor designer): a dimmed
## backdrop, one glass window, a top bar that starts with Back and the part's name, and three
## columns under it (left: the numbered choices, middle: the part in 3D, right: its figures and
## the bench). A designer extends this, builds its own columns, and hands them to _build_shell().
##
## Also the small widgets the columns are made of (section titles, faint notes, labelled rows,
## steppers, the figures grid), so both designers read the same at the same size.

signal closed

const BACKDROP := Color(0.0, 0.0, 0.0, 0.58)
const MARGIN_X := 36
const MARGIN_Y := 24

var window: PanelContainer
var back_button: Button
var name_field: LineEdit
## True while the screen is being filled from the model, so control signals are not taken as edits.
var _syncing := false


func _init_shell(p_name: String) -> void:
	name = p_name
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## Backdrop, window, top bar and the three columns.
func _build_shell(top_bar: Control, left: Control, middle: Control, right: Control) -> void:
	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.color = BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	window = PanelContainer.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = MARGIN_X
	window.offset_right = -MARGIN_X
	window.offset_top = MARGIN_Y
	window.offset_bottom = -MARGIN_Y
	var box := LothalTheme.glass_box(Color(0.075, 0.083, 0.105, 0.98), LothalTheme.RADIUS_PANEL)
	box.content_margin_left = LothalTheme.SPACE_4
	box.content_margin_right = LothalTheme.SPACE_4
	box.content_margin_top = LothalTheme.SPACE_3
	box.content_margin_bottom = LothalTheme.SPACE_4
	window.add_theme_stylebox_override("panel", box)
	add_child(window)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	window.add_child(root)
	root.add_child(top_bar)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", LothalTheme.SPACE_4)
	root.add_child(body)
	body.add_child(left)
	body.add_child(middle)
	body.add_child(right)


## The top bar's start: Back, then the name field. `on_name` gets the typed text (never while
## _syncing). The designer appends its own buttons after this.
func _top_bar_start(placeholder: String, on_name: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "‹  Back"
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(close)
	bar.add_child(back_button)
	name_field = LineEdit.new()
	name_field.name = "NameField"
	name_field.placeholder_text = placeholder
	name_field.custom_minimum_size = Vector2(240, 0)
	name_field.max_length = 40
	name_field.text_changed.connect(func(t: String): if not _syncing: on_name.call(t))
	bar.add_child(name_field)
	return bar


## A control that fills the rest of a row (pushes what follows to the right).
func _fill() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _bar_button(node_name: String, text: String, on_press: Callable, tip := "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


## The left column: a fixed-width scroll holding one VBox (returned through `col_out[0]`).
func _left_column(width: float, col_out: Array) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "LeftScroll"
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	scroll.add_child(col)
	col_out.append(col)
	return scroll


func _middle_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Middle"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	return col


func _right_column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Right"
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	return col


## The figures grid: one row per key (name, value, how-it-was-arrived-at tag). The value and tag
## labels are stored in `values` under `key` and `key + "_tag"`.
func _figure_grid(keys: Array, name_of: Callable, values: Dictionary, value_w := 214.0) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "Figures"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", LothalTheme.SPACE_3)
	grid.add_theme_constant_override("v_separation", 2)
	for key in keys:
		var n := Label.new()
		n.text = String(name_of.call(key))
		n.custom_minimum_size = Vector2(88, 0)
		n.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		n.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
		grid.add_child(n)
		var v := Label.new()
		v.name = "Fig_" + key
		v.custom_minimum_size = Vector2(value_w, 0)
		v.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
		v.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
		grid.add_child(v)
		values[key] = v
		var t := Label.new()
		t.name = "Tag_" + key
		t.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL - 1)
		t.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
		grid.add_child(t)
		values[key + "_tag"] = t
	return grid


func _section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	return l


func _faint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _labelled(text: String, ctl: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(88, 0)
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctl)
	return row


## A "label  −  value  +" row. Returns the value label; buttons are named <title>Minus/<title>Plus.
func _add_stepper(parent: Control, title: String, caption: String, hint: String, on_minus: Callable,
		on_plus: Callable, value_w := 44.0) -> Label:
	var row := HBoxContainer.new()
	row.name = "Stepper_" + title
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(l)
	var minus := Button.new()
	minus.name = "%sMinus" % title
	minus.text = "−"
	minus.custom_minimum_size = Vector2(32, 0)
	minus.pressed.connect(on_minus)
	row.add_child(minus)
	var v := Label.new()
	v.name = "%sValue" % title
	v.custom_minimum_size = Vector2(value_w, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(v)
	var plus := Button.new()
	plus.name = "%sPlus" % title
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 0)
	plus.pressed.connect(on_plus)
	row.add_child(plus)
	l.tooltip_text = hint
	parent.add_child(row)
	return v


## A row of toggle chips (one per option); `on_pick` gets the option. Chips are named
## <prefix><option with spaces/dots removed>.
func _chip_row(node_name: String, prefix: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = node_name
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.set_meta("prefix", prefix)
	return row


func _set_chips(row: HFlowContainer, options: Array, labels: Array, on_pick: Callable) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var prefix := String(row.get_meta("prefix", ""))
	for i in options.size():
		var opt: Variant = options[i]
		var b := Button.new()
		b.name = prefix + String(str(opt)).replace(" ", "").replace(".", "_").replace(",", "")
		b.text = String(labels[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): on_pick.call(opt))
		_monochrome_chip(b)
		row.add_child(b)


## A chosen chip reads by a light edge and brighter ink, not by the theme's blue: the designers are
## monochrome, and amber is kept for warnings.
static func _monochrome_chip(b: Button) -> void:
	# The theme's own normal box, re-inked: same margins and corners, so choosing does not resize.
	var base := LothalTheme.get_theme().get_stylebox("normal", "Button")
	var on: StyleBoxFlat = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
	on.bg_color = Color(1, 1, 1, 0.10)
	on.border_color = Color(1, 1, 1, 0.55)
	on.set_border_width_all(1)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	for st in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, LothalTheme.TEXT_MAIN)


## Presses the chip whose option equals `value` and releases the others.
func _mark_chips(row: HFlowContainer, options: Array, value: Variant) -> void:
	var kids := row.get_children()
	for i in mini(kids.size(), options.size()):
		var same: bool = str(options[i]) == str(value)
		if options[i] is float or options[i] is int:
			same = is_equal_approx(float(options[i]), float(value))
		(kids[i] as Button).set_pressed_no_signal(same)


func close() -> void:
	_before_close()
	closed.emit()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


## Override to stop animations etc. before the screen goes.
func _before_close() -> void:
	pass


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
