class_name ItemPageView
extends VBoxContainer
## The head of an item's page in the Lab dock (lab dock design §2, §3): the page's two summary
## numbers, then ONLY the warnings its row owns — each a short line with a "Why?" that reveals the
## long text — then the page's body (a drawing) filling what is left.
##
## Built for the Airframe pages and meant for every section's: it draws a row from
## `SectionRows.rows` (`row.warnings`, most severe first) and a pair from
## `SectionRows.page_numbers`, and decides nothing itself. No paragraph is on screen until a
## "Why?" is pressed.

const WHY_WIDTH := 420.0

var body: Control

var _numbers: HBoxContainer
var _warnings: VBoxContainer
var _clear: Label
## One entry per shown warning: `{short: Label, button: Button, long: Label}`.
var _entries: Array = []


func _init() -> void:
	add_theme_constant_override("separation", LothalTheme.SPACE_3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_numbers = HBoxContainer.new()
	_numbers.name = "Numbers"
	_numbers.add_theme_constant_override("separation", LothalTheme.SPACE_4 * 2)
	add_child(_numbers)

	_warnings = VBoxContainer.new()
	_warnings.name = "Warnings"
	_warnings.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(_warnings)

	_clear = Label.new()
	_clear.text = "Nothing to fix"
	_clear.add_theme_color_override("font_color", LothalTheme.SUCCESS)
	_warnings.add_child(_clear)


## Puts `control` under the head, taking the rest of the height.
func set_body(control: Control) -> void:
	if body != null and body.get_parent() == self:
		remove_child(body)
	body = control
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)


## Shows or hides the head (numbers and warnings), leaving the body — for a room whose body is
## also its own screen outside the dock (the Field room's site view).
func set_head_visible(on: bool) -> void:
	_head_on = on
	_numbers.visible = on and _numbers.get_child_count() > 0
	_warnings.visible = on


var _head_on := true


## `row` from SectionRows.rows; `numbers` as SectionRows.page_numbers returns them.
func show_item(row: Dictionary, numbers: Array) -> void:
	for child in _numbers.get_children():
		_numbers.remove_child(child)
		child.queue_free()
	for pair in numbers:
		_numbers.add_child(_number_tile(str(pair[0]), str(pair[1])))
	_numbers.visible = _head_on and not numbers.is_empty()

	for entry in _entries:
		(entry["box"] as Control).queue_free()
		_warnings.remove_child(entry["box"])
	_entries.clear()
	for w in row.get("warnings", []):
		_add_warning(w as BuildWarning)
	_clear.visible = _entries.is_empty()


func _number_tile(caption_text: String, value_text: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	caption.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	column.add_child(caption)
	var value := Label.new()
	value.name = "Value"
	value.text = value_text
	value.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_TITLE + 4)
	column.add_child(value)
	return column


func _add_warning(w: BuildWarning) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	box.add_child(line)

	var colour: Color = {BuildWarning.Severity.IMPOSSIBLE: LothalTheme.DANGER,
		BuildWarning.Severity.LIMITING: LothalTheme.WARNING}.get(w.severity, LothalTheme.TEXT_MUTED)
	var short := Label.new()
	short.text = ("⚠ " if w.severity != BuildWarning.Severity.CHARACTERISTIC else "") + w.short
	short.add_theme_color_override("font_color", colour)
	line.add_child(short)

	var button := Button.new()
	button.text = "Why?"
	button.flat = true
	button.toggle_mode = true
	button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	line.add_child(button)

	var long := Label.new()
	long.text = w.long()
	long.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	long.custom_minimum_size = Vector2(WHY_WIDTH, 0)
	long.theme_type_variation = &"MutedLabel"
	long.visible = false
	box.add_child(long)

	var index := _entries.size()
	button.toggled.connect(func(_on: bool) -> void: toggle_why(index))
	_warnings.add_child(box)
	_entries.append({"box": box, "short": short, "button": button, "long": long})


# ---------------------------------------------------------------------------
# Reads, for tests and captures
# ---------------------------------------------------------------------------

func number_text(index: int) -> String:
	if index >= _numbers.get_child_count():
		return ""
	var tile := _numbers.get_child(index)
	return "%s %s" % [(tile.get_node("Caption") as Label).text, (tile.get_node("Value") as Label).text]


func warning_count() -> int:
	return _entries.size()


func short_text(index: int) -> String:
	return (_entries[index]["short"] as Label).text if index < _entries.size() else ""


func why_text(index: int) -> String:
	return (_entries[index]["long"] as Label).text if index < _entries.size() else ""


func why_visible(index: int) -> bool:
	return index < _entries.size() and (_entries[index]["long"] as Label).visible


## Shows or hides one warning's long text — what its "Why?" does.
func toggle_why(index: int) -> void:
	if index >= _entries.size():
		return
	var long := _entries[index]["long"] as Label
	long.visible = not long.visible
	var button := _entries[index]["button"] as Button
	button.set_pressed_no_signal(long.visible)
	button.text = "Hide" if long.visible else "Why?"


func clear_text() -> String:
	return _clear.text if _clear.visible else ""
