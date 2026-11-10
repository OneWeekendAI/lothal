class_name DsList
extends VBoxContainer
## A pick-one list of Design Space toggle rows (the ItemList / OptionButton replacement). Same small API as those two:
## add_item, clear, select, set_item_text, item_count, selected, get_selected_items, and item_selected(index) on a user press.
## `flow`: chips wrapping across the width instead of a column. `allow_none`: pressing the picked row again clears it
## (item_selected(-1)).

signal item_selected(index: int)

var item_count: int:
	get:
		return _buttons.size()
var selected: int:
	get:
		for i in _buttons.size():
			if _buttons[i].button_pressed:
				return i
		return -1
var allow_none := false
var _buttons: Array[Button] = []
var _group := ButtonGroup.new()
var _holder: Container


func _init(p_flow := false, p_allow_none := false) -> void:
	allow_none = p_allow_none
	mouse_filter = Control.MOUSE_FILTER_PASS
	if p_flow:
		var f := HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 4)
		f.add_theme_constant_override("v_separation", 4)
		_holder = f
	else:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		_holder = v
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_holder)
	_group.allow_unpress = p_allow_none


func add_item(text: String) -> void:
	var i := _buttons.size()
	var b := DsUi.button(text, true)
	if _holder is VBoxContainer:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.button_group = _group
	b.pressed.connect(func() -> void: _pressed(i))
	_holder.add_child(b)
	_buttons.append(b)


func clear() -> void:
	for b in _buttons:
		_holder.remove_child(b)
		b.queue_free()
	_buttons = []


func _pressed(i: int) -> void:
	item_selected.emit(i if _buttons[i].button_pressed else -1)


func select(i: int) -> void:
	for k in _buttons.size():
		_buttons[k].set_pressed_no_signal(k == i)


func get_selected_items() -> PackedInt32Array:
	var s := selected
	return PackedInt32Array([s] if s >= 0 else [])


func set_item_text(i: int, text: String) -> void:
	_buttons[i].text = text


func button_at(i: int) -> Button:
	return _buttons[i]
