class_name DsStepper
extends HBoxContainer
## A number as Design Space draws one: "−  value  +" with the value typed or stepped. The SpinBox replacement, with its
## small API: value (setting it never emits), set_value_no_signal, min_value, max_value, step, and value_changed(v) when the
## user steps or types a value.

signal value_changed(v: float)

var min_value := 0.0
var max_value := 100.0
var step := 1.0
var value: float:
	set(v):
		value = clampf(snappedf(v, step) if step >= 0.01 else v, min_value, max_value)
		_show()
var edit: LineEdit


func _init(lo := 0.0, hi := 100.0, p_step := 1.0) -> void:
	min_value = lo
	max_value = hi
	step = p_step
	add_theme_constant_override("separation", 4)
	var minus := DsUi.button("−")
	minus.custom_minimum_size = Vector2(26, 0)
	minus.pressed.connect(func() -> void: _nudge(-1.0))
	add_child(minus)
	edit = LineEdit.new()
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(72, 0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DsUi.style_field(edit)
	edit.text_submitted.connect(func(t: String) -> void: _typed(t))
	edit.focus_exited.connect(func() -> void: _typed(edit.text))
	add_child(edit)
	var plus := DsUi.button("+")
	plus.custom_minimum_size = Vector2(26, 0)
	plus.pressed.connect(func() -> void: _nudge(1.0))
	add_child(plus)
	_show()


func set_value_no_signal(v: float) -> void:
	value = v


func _decimals() -> int:
	var d := 0
	var s := step
	while d < 6 and not is_equal_approx(s, round(s)):
		s *= 10.0
		d += 1
	return d


func _show() -> void:
	if edit != null:
		edit.text = ("%." + str(_decimals()) + "f") % value


func _nudge(dir: float) -> void:
	_apply(value + dir * step)


func _typed(t: String) -> void:
	if t.is_valid_float() and not is_equal_approx(float(t), value):
		_apply(float(t))
	else:
		_show()


func _apply(v: float) -> void:
	value = v
	value_changed.emit(value)
