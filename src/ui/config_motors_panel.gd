class_name ConfigMotorsPanel
extends PanelContainer
## Config's Motors panel: which way each motor turns, and the props-in / props-out choice behind it
## — Config room slice C3 (plans/2026-09-20-config-room-design.md §4.3).
##
## THE PANEL WRITES NOTHING, on CameraPanel's and PrintPanel's rule. The choice announces itself
## (`motor_spin_edited`) and LabScreen writes it into the drone's `config` block, which is the block
## the Build, the mixer and the drawn aircraft all read. A second writer here would be a second
## place the map lives, and this is a value the physics reads.
##
## THE PANEL IS NOT THE PICTURE. The map itself is drawn on the aircraft in the viewport
## (`MotorMapMarkers`) — that is §4.3's whole argument, and the reason this room is in a 3D app
## rather than in a blog post. The rows here are the same four facts in words, for the builder who
## is reading them off a screen into a Configurator, and they come from the same accessor the
## drawing does so the two cannot disagree.
##
## WHAT IT REFUSES, said here rather than only in the design: Lothal cannot know your ESC's motor
## order. That is a property of how the wires landed on the pads; it is discovered with a battery
## and a Configurator, not predicted. What it can say is what the order SHOULD be and how to check
## it, which is the useful half and is honest about being half.

## The two conventions, in the order they are offered. props-out first because §8 ships it as the
## default — as a convention, not as a finding.
const SPIN_CHOICES := [
	{"value": "props_out", "label": "Props out (default)"},
	{"value": "props_in", "label": "Props in"},
]

## What a per-motor authored map reads as in the chooser: neither convention, and saying so is
## better than silently showing one of them (§5.3 — a map Lothal did not write is still flown).
const CUSTOM_LABEL := "Per-motor map"

## §4.3's refusal, in the room where the order is read.
const REFUSAL := ("Lothal cannot tell you your ESC's motor order — that is how the wires landed on "
	+ "the pads, and it is found with a battery, not predicted. Check each one in the Motors tab "
	+ "of your Configurator and correct it there.")

signal motor_spin_edited(value: String)

var _chooser: OptionButton
var _rows: Dictionary = {}   # motor name -> Label
var _refusal: Label
var _warnings: WarningList
var _updating := false


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
	title.text = "MOTORS"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = ("Which way each motor turns, drawn on your aircraft. Both conventions fly; what "
		+ "changes is how each propeller is mounted and which way the quad washes out.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	_chooser = OptionButton.new()
	for choice in SPIN_CHOICES:
		_chooser.add_item(String(choice["label"]))
	_chooser.item_selected.connect(_on_choice)
	root.add_child(_chooser)

	root.add_child(HSeparator.new())

	for motor_name in MotorLayout.MOTOR_NAMES:
		var row := Label.new()
		row.text = "%s —" % motor_name
		root.add_child(row)
		_rows[motor_name] = row

	_refusal = Label.new()
	_refusal.text = REFUSAL
	_refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refusal.custom_minimum_size = Vector2(280, 0)
	_refusal.theme_type_variation = &"MutedLabel"
	root.add_child(_refusal)

	_warnings = WarningList.new(280)
	root.add_child(_warnings)


## Shows the map this build is configured for, and what is wrong with it. Everything read through
## `MotorLayout.spin_map` and `ConfigPlausibility`, so the words, the picture and the physics are
## one fact seen three ways.
func render(build: Build) -> void:
	var spin := MotorLayout.spin_map(build.config)
	for motor_name in MotorLayout.MOTOR_NAMES:
		(_rows[motor_name] as Label).text = "%s %s" % [
			motor_name, MotorLayout.direction_name(float(spin[motor_name]))]

	var authored := String(build.config.get("motor_spin", "props_out")) \
		if not (build.config.get("motor_spin", null) is Dictionary) else ""
	_updating = true
	# A per-motor map is neither choice. It gets an item of its own rather than lighting one of the
	# two conventions, which would say the builder had chosen something they had not.
	_remove_custom_item()
	var selected := -1
	for i in SPIN_CHOICES.size():
		if String(SPIN_CHOICES[i]["value"]) == authored:
			selected = i
	if selected < 0:
		_chooser.add_item(CUSTOM_LABEL)
		selected = _chooser.item_count - 1
	_chooser.select(selected)
	_updating = false

	var entries: Array[BuildWarning] = ConfigPlausibility.warnings_for(build)
	_warnings.show_warnings(entries)


## The convention in force — "props_out", "props_in", or "" for a per-motor map that is neither.
func selected_spin() -> String:
	var index := _chooser.selected
	if index < 0 or index >= SPIN_CHOICES.size():
		return ""
	return String(SPIN_CHOICES[index]["value"])


## What one motor's row reads — the same string the marker on the aircraft carries.
func map_row_text(motor_name: String) -> String:
	if not _rows.has(motor_name):
		return ""
	return String((_rows[motor_name] as Label).text)


func refusal_text() -> String:
	return _refusal.text


func warning_text() -> String:
	return _warnings.ordered_text() if _warnings.visible else ""


func _remove_custom_item() -> void:
	while _chooser.item_count > SPIN_CHOICES.size():
		_chooser.remove_item(_chooser.item_count - 1)


func _on_choice(index: int) -> void:
	if _updating or index < 0 or index >= SPIN_CHOICES.size():
		return
	motor_spin_edited.emit(String(SPIN_CHOICES[index]["value"]))
