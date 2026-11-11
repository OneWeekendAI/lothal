class_name DsSlider
extends VBoxContainer
## One labelled setting as the tool row draws a slider: "Height" left, the value with its unit right, a tag chip, and a
## thin slider under. `value` is in the setting's own units and is kept exactly as set (the slider only shows it, clamped to
## its range); setting `value` never emits, a drag does (value_changed). `unit_scale` converts for display (a fraction shown as %).

signal value_changed(v: float)

var value: float:
	set(v):
		value = v
		_show()
var tag_label: Label
var slider: HSlider
var unit := ""
var unit_scale := 1.0
var _value_label: Label
## The value readout (a test reads its text and rect).
var value_label: Label:
	get:
		return _value_label


func _init(caption: String, p_unit: String, lo: float, hi: float, step: float, p_scale := 1.0) -> void:
	unit = p_unit
	unit_scale = p_scale
	add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cap := DsUi.label(caption, DsUi.INK_MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var t := DsUi.tag("")
	tag_label = t[1]
	row.add_child(t[0])
	_value_label = DsUi.label("", DsUi.INK)
	_value_label.custom_minimum_size = Vector2(52, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value_label)
	add_child(row)
	slider = HSlider.new()
	slider.min_value = lo * unit_scale
	slider.max_value = hi * unit_scale
	slider.step = step * unit_scale
	DsUi.style_slider(slider)
	slider.value_changed.connect(func(x: float) -> void:
		value = x / unit_scale
		value_changed.emit(value))
	add_child(slider)


func _show() -> void:
	if slider != null:
		slider.set_value_no_signal(value * unit_scale)
		var shown := value * unit_scale
		_value_label.text = ("%d" % int(round(shown)) if is_equal_approx(shown, round(shown)) else "%.1f" % shown) + unit
