class_name FrameToolRow
extends VBoxContainer
## The frame tools (PLAN Section 4), shown while a frame region of an editable frame is selected:
## Drill (M2, M3 or a free diameter), Pocket (rectangle or slot, dragged), Fill, the selected plate's
## thickness and the selected arm's width, undo and redo, and the plan editor hand-off.
##
## It only shows and reports: every button and slider emits, and DesignSpace runs the session op,
## so a test drives the same DesignSpace method a press does. The refusal line is the warning accent;
## the change line and the "not modelled" tags (FrameTools.NOT_MODELLED, PLAN §4.3) sit under it.

signal tool_chosen(tool: String)
signal drill_size_chosen(d_mm: float)
signal pocket_shape_chosen(shape: String)
signal fill_pressed
signal thickness_committed(mm: float)
signal width_committed(scale: float)
signal undo_pressed
signal redo_pressed
signal plan_editor_pressed

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)

var tool_buttons := {}
var size_buttons := {}
var shape_buttons := {}
var free_size: SpinBox
var thickness_slider: HSlider
var thickness_value: Label
var thickness_box: VBoxContainer
var width_slider: HSlider
var width_value: Label
var width_box: VBoxContainer
var undo_button: Button
var redo_button: Button
var plan_button: Button
var reason_label: Label
var change_label: Label
var tags_box: HFlowContainer
var _sizes_row: HBoxContainer
var _shapes_row: HBoxContainer


func _init() -> void:
	name = "FrameTools"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	var head := _label("FRAME TOOLS", INK_FAINT)
	add_child(head)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	add_child(tools)
	for pair in [["drill", "Drill"], ["pocket", "Pocket"], ["fill", "Fill"]]:
		var b := _button(String(pair[1]), true)
		var id := String(pair[0])
		if id == "fill":
			b.toggle_mode = false
			b.pressed.connect(func(): fill_pressed.emit())
		else:
			b.pressed.connect(func(): tool_chosen.emit(id if b.button_pressed else ""))
		tools.add_child(b)
		tool_buttons[id] = b
	_sizes_row = HBoxContainer.new()
	_sizes_row.add_theme_constant_override("separation", 4)
	add_child(_sizes_row)
	for key in FrameTools.DRILL_SIZES:
		var d := float(FrameTools.DRILL_SIZES[key])
		var b := _button(String(key), true)
		b.pressed.connect(func(): drill_size_chosen.emit(d))
		_sizes_row.add_child(b)
		size_buttons[d] = b
	free_size = SpinBox.new()
	free_size.min_value = FrameTools.FREE_MIN_D_MM
	free_size.max_value = FrameTools.FREE_MAX_D_MM
	free_size.step = 0.1
	free_size.value = 4.0
	free_size.suffix = "mm"
	free_size.custom_minimum_size = Vector2(92, 0)
	free_size.tooltip_text = "Free diameter"
	# The theme's focus ring is the accent blue; here the one accent is the warning amber.
	var field_focus := StyleBoxFlat.new()
	field_focus.bg_color = Color(0, 0, 0, 0)
	field_focus.border_color = INK_MUTED
	field_focus.set_border_width_all(1)
	field_focus.set_corner_radius_all(3)
	free_size.get_line_edit().add_theme_stylebox_override("focus", field_focus)
	free_size.get_line_edit().add_theme_color_override("caret_color", INK)
	free_size.get_line_edit().add_theme_color_override("selection_color", Color(1, 1, 1, 0.2))
	free_size.value_changed.connect(func(v: float): drill_size_chosen.emit(v))
	_sizes_row.add_child(free_size)
	_shapes_row = HBoxContainer.new()
	_shapes_row.add_theme_constant_override("separation", 4)
	add_child(_shapes_row)
	for pair in [["rect", "Rectangle"], ["slot", "Slot"]]:
		var b := _button(String(pair[1]), true)
		var id := String(pair[0])
		b.pressed.connect(func(): pocket_shape_chosen.emit(id))
		_shapes_row.add_child(b)
		shape_buttons[id] = b
	thickness_box = _slider_box("Plate thickness", FrameTools.THICKNESS_MIN_MM, FrameTools.THICKNESS_MAX_MM, 0.5)
	thickness_slider = thickness_box.get_meta("slider")
	thickness_value = thickness_box.get_meta("value")
	thickness_slider.drag_ended.connect(func(changed: bool):
		if changed:
			thickness_committed.emit(thickness_slider.value))
	thickness_slider.value_changed.connect(func(v: float): thickness_value.text = "%.1f mm" % v)
	add_child(thickness_box)
	width_box = _slider_box("Arm width", FrameTools.ARM_WIDTH_MIN * 100.0, FrameTools.ARM_WIDTH_MAX * 100.0, 5.0)
	width_slider = width_box.get_meta("slider")
	width_value = width_box.get_meta("value")
	width_slider.drag_ended.connect(func(changed: bool):
		if changed:
			width_committed.emit(width_slider.value / 100.0))
	width_slider.value_changed.connect(func(v: float): width_value.text = "%d %% of as drawn" % roundi(v))
	add_child(width_box)
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 4)
	add_child(history)
	undo_button = _button("Undo", false)
	undo_button.pressed.connect(func(): undo_pressed.emit())
	history.add_child(undo_button)
	redo_button = _button("Redo", false)
	redo_button.pressed.connect(func(): redo_pressed.emit())
	history.add_child(redo_button)
	plan_button = _button("Open in plan editor", false)
	plan_button.pressed.connect(func(): plan_editor_pressed.emit())
	history.add_child(plan_button)
	reason_label = _label("", LothalTheme.WARNING)
	reason_label.name = "Refusal"
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.visible = false
	add_child(reason_label)
	change_label = _label("", INK)
	change_label.name = "Change"
	change_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	change_label.visible = false
	add_child(change_label)
	tags_box = HFlowContainer.new()
	tags_box.name = "NotModelled"
	tags_box.add_theme_constant_override("h_separation", 6)
	tags_box.add_theme_constant_override("v_separation", 4)
	tags_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tags_box)
	# Muted, not faint: this line says what the mass change leaves out, so it must be read.
	var lead := _label("Not modelled:", INK_MUTED)
	tags_box.add_child(lead)
	for t in FrameTools.NOT_MODELLED:
		tags_box.add_child(_tag(String(t)))


## Shows the state DesignSpace hands it. `plate` is the selected plate's dictionary ({} for none).
func show_state(tool: String, d_mm: float, shape: String, plate: Dictionary, arm_scale: float,
		can_undo: bool, can_redo: bool) -> void:
	for id in tool_buttons:
		(tool_buttons[id] as Button).set_pressed_no_signal(id == tool)
	_sizes_row.visible = tool == "drill"
	for d in size_buttons:
		(size_buttons[d] as Button).set_pressed_no_signal(absf(float(d) - d_mm) < 1.0e-6)
	free_size.set_value_no_signal(d_mm)
	_shapes_row.visible = tool == "pocket"
	for id in shape_buttons:
		(shape_buttons[id] as Button).set_pressed_no_signal(id == shape)
	thickness_box.visible = not plate.is_empty()
	if not plate.is_empty():
		var t := AirframeDocument.plate_thickness_mm(plate)
		thickness_slider.set_value_no_signal(t)
		thickness_value.text = "%.1f mm" % t
	width_box.visible = not plate.is_empty() and String(plate.get("role", "")) == AirframeDocument.ROLE_ARM
	width_slider.set_value_no_signal(arm_scale * 100.0)
	width_value.text = "%d %% of as drawn" % roundi(arm_scale * 100.0)
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo


## The one-line refusal, in the warning accent ("" hides it).
func show_reason(reason: String) -> void:
	reason_label.text = reason
	reason_label.visible = reason != ""


func show_change(text: String) -> void:
	change_label.text = text
	change_label.visible = text != ""


## The "not modelled" tags as text, for tests.
func tag_texts() -> Array:
	var out: Array = []
	for c in tags_box.get_children():
		if c is PanelContainer:
			out.append(((c as PanelContainer).get_child(0) as Label).text)
	return out


func _label(text: String, ink: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", ink)
	return l


func _tag(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = INK_FAINT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, INK_MUTED))
	return p


func _button(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	b.add_theme_color_override("font_color", INK_MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	# Selected = lighter fill and an ink border, never the theme's accent blue (monochrome, with
	# the warning amber as the only accent).
	var on := StyleBoxFlat.new()
	on.bg_color = Color(1, 1, 1, 0.16)
	on.border_color = INK_MUTED
	on.set_border_width_all(1)
	on.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	on.content_margin_left = LothalTheme.SPACE_3
	on.content_margin_right = LothalTheme.SPACE_3
	on.content_margin_top = LothalTheme.SPACE_2
	on.content_margin_bottom = LothalTheme.SPACE_2
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b


func _slider_box(caption: String, lo: float, hi: float, step: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	var cap := _label(caption, INK_MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var value := _label("", INK)
	row.add_child(value)
	box.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(240, 18)
	# The theme draws no track for a bare HSlider here; a thin rule, and the filled part in ink.
	var track := StyleBoxFlat.new()
	track.bg_color = INK_FAINT
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = INK_MUTED
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	box.add_child(s)
	box.set_meta("slider", s)
	box.set_meta("value", value)
	return box
