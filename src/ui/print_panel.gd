class_name PrintPanel
extends PanelContainer
## The Printed room's one panel: how this drone's parts are printed, and the parts to print —
## printed-room slice PR0 (plans/2026-09-14-printed-room-plan.md).
##
## NO RAIL. There is nothing to shop for: printed parts are generated from the build (design §3), so
## the list lives on this panel beside the clearance that shapes every one of them, rather than on a
## left-hand rail that would look like a catalog.
##
## THE PANEL WRITES NOTHING, on CameraPanel's rule. The slider announces `clearance_edited` and each
## Export button announces `export_requested`; LabScreen owns the `printing` copy and the shell owns
## the files. What is shown is re-read on the next render, never taken from the slider.

signal clearance_edited(mm: float)
signal export_requested(part_id: String)

var _slider: HSlider
var _value: Label
var _hint: Label
var _parts: VBoxContainer
var _buttons: Dictionary = {}
var _rows: Array = []
var _updating := false


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssemblyPanel._padded(self).add_child(root)

	var title := Label.new()
	title.text = "PRINTED"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = "Parts this drone needs printed, generated from what is fitted. Saved with this drone, not across drones."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = "Fit clearance"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	_value = Label.new()
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value)
	root.add_child(header)

	_slider = HSlider.new()
	_slider.min_value = PrintSettings.MIN_CLEARANCE_MM
	_slider.max_value = PrintSettings.MAX_CLEARANCE_MM
	_slider.step = PrintSettings.CLEARANCE_STEP_MM
	_slider.value_changed.connect(_on_slider_moved)
	root.add_child(_slider)

	_hint = Label.new()
	_hint.text = PrintSettings.CLEARANCE_HINT
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(280, 0)
	_hint.theme_type_variation = &"MutedLabel"
	root.add_child(_hint)

	root.add_child(HSeparator.new())

	var parts_title := Label.new()
	parts_title.text = "Parts"
	root.add_child(parts_title)

	_parts = VBoxContainer.new()
	root.add_child(_parts)


func render(build: Build, printing: Dictionary) -> void:
	_updating = true
	_slider.value = PrintSettings.clearance_mm(printing)
	_updating = false
	_value.text = PrintSettings.clearance_row_text(printing)

	for child in _parts.get_children():
		_parts.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_rows = PrintedParts.for_build(build)

	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Nothing on this build is printed yet."
		empty.theme_type_variation = &"MutedLabel"
		_parts.add_child(empty)
		return

	for row in _rows:
		var line := VBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(row["label"])
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size = Vector2(280, 0)
		line.add_child(name_label)
		var row_note := Label.new()
		row_note.text = String(row["note"])
		row_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_note.custom_minimum_size = Vector2(280, 0)
		row_note.theme_type_variation = &"MutedLabel"
		line.add_child(row_note)
		var button := Button.new()
		button.text = "Export STL…"
		button.disabled = not bool(row["exportable"])
		var id := String(row["id"])
		button.pressed.connect(func() -> void: export_requested.emit(id))
		line.add_child(button)
		_parts.add_child(line)
		_buttons[id] = button


func clearance_row_text() -> String:
	return _value.text


func hint_text() -> String:
	return _hint.text


func slider_range() -> Vector2:
	return Vector2(_slider.min_value, _slider.max_value)


## The rows rendered last, as PrintedParts gave them.
func rows() -> Array:
	return _rows


## The Export button for one part, or null when the part is not listed. For tests.
func export_button(part_id: String) -> Button:
	return _buttons.get(part_id, null)


func _on_slider_moved(mm: float) -> void:
	if _updating:
		return
	clearance_edited.emit(mm)
