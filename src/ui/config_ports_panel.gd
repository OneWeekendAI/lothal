class_name ConfigPortsPanel
extends PanelContainer
## Config's Ports panel: what wants a serial port, how many the board has, and the field that
## replaces Lothal's guess with the builder's own number — Config room slice C5
## (plans/2026-09-20-config-room-design.md §4.2).
##
## THE FIELD IS THE POINT OF THIS PANEL. The supply figure is a class-typical range, which is a
## guess, and §2.2's answer to genericness is not a better guess — it is thirty seconds with the
## board's product page and a box to type the real number into. Everything else here is the same
## two facts the warning row states, shown where the builder is standing when they type.
##
## THE PANEL WRITES NOTHING, on ConfigMotorsPanel's rule: the edit announces itself
## (`uart_count_edited`) and LabScreen writes it into the drone's `config` block, so the value lives
## in one place. A second writer here would be a second place the count lives.
##
## THE PROVENANCE SENTENCE IS TAKEN WHOLE FROM `PortBudget`, never re-written from `low` and `high`.
## A panel that formatted its own "1–2 ports" would be the exact failure §0.1 forbids — a guess
## arriving without its label — and it would drift from the warning row the first time either is
## edited.

## What the box will accept. The ceiling is generous rather than researched: it exists to stop a
## typo becoming a claim, not to express a belief about boards.
const COUNT_MAX := 16

## What the box reads when no override is set. Zero means "follow the catalog", which is exactly
## what `PortBudget.set_count` does with it.
const NO_OVERRIDE := 0

signal uart_count_edited(count: int)

var _demand: Label
var _supply: Label
var _field: SpinBox
var _warnings: WarningList


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	AssemblyPanel._padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "PORTS"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	_demand = Label.new()
	_demand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_demand.custom_minimum_size = Vector2(280, 0)
	root.add_child(_demand)
	_prose.append(_demand)

	root.add_child(HSeparator.new())

	_supply = Label.new()
	_supply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_supply.custom_minimum_size = Vector2(280, 0)
	root.add_child(_supply)
	_prose.append(_supply)

	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = "Ports"
	caption.custom_minimum_size = Vector2(56, 0)
	row.add_child(caption)
	_field = SpinBox.new()
	_field.min_value = NO_OVERRIDE
	_field.max_value = COUNT_MAX
	_field.step = 1
	_field.value_changed.connect(_on_count_changed)
	_field.custom_minimum_size = Vector2(96, 0)
	row.add_child(_field)
	root.add_child(row)

	var hint := Label.new()
	hint.text = ("Set this to your board's real UART count and every check above becomes exact. "
		+ "Zero follows the catalog's class-typical figure.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.theme_type_variation = &"MutedLabel"
	root.add_child(hint)
	_prose.append(hint)

	_warnings = WarningList.new(280)
	root.add_child(_warnings)


## Shows this build's budget. Both halves come from the same two places the warning does —
## `ControlPlausibility` for the demand and `PortBudget` for the supply — so the panel and the row
## cannot come to disagree.
func render(build: Build) -> void:
	var entries: Array[BuildWarning] = ControlPlausibility.warnings_for(build)
	var demand := 0
	for warning in entries:
		if warning.id == &"serial_peripherals":
			demand = int(warning.values.get("serial_peripherals", 0))
	_demand.text = "%d fitted %s a serial port." % [demand,
		"part wants" if demand == 1 else "parts want"]

	var budget := PortBudget.for_build(build)
	var verdict := PortBudget.verdict(demand, budget)
	_supply.text = String(budget["sentence"])
	if not verdict.is_empty():
		_supply.text += " " + verdict

	# `set_value_no_signal`, on the blade room's precedent: showing a stored override is not the
	# builder typing one, and an assignment here would announce an edit on every reopen.
	_field.set_value_no_signal(float(PortBudget.typed_count(build.config)))

	_warnings.show_warnings(entries)
	if not _warnings_shown:
		_warnings.visible = false


func demand_text() -> String:
	return _demand.text


func supply_text() -> String:
	return _supply.text


## The override in the box, or 0 for none.
func field_value() -> int:
	return int(_field.value)


## The box itself, so a headless check can drive the signal a mouse would. A `Range` assigned in a
## headless run accepts the value and announces nothing, so the connection between the box and this
## panel's own signal is otherwise untestable outside a window — and that connection is the thing
## worth checking.
func port_field() -> SpinBox:
	return _field


func _on_count_changed(value: float) -> void:
	uart_count_edited.emit(int(value))


## The explanatory sentences, off on a Lab dock page: the row, the page's numbers and the drawing
## say them there (lab dock design: no paragraphs on a page).
var _prose: Array[Control] = []


func set_prose_visible(on: bool) -> void:
	for node in _prose:
		node.visible = on


## The build's warning list, off on a Lab dock page: the page lists the row's own, short + Why?.
var _warnings_shown := true


func set_warnings_visible(on: bool) -> void:
	_warnings_shown = on
	_warnings.visible = on and _warnings.visible
