class_name CustomEscDialog
extends AcceptDialog
## Lab's form for entering an ESC Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not).
##
## THE FORM IS THE PRODUCT PAGE, IN THE ORDER THE PRODUCT PAGE PRINTS IT, and it is the shortest of
## the six because the ESC is the simplest part on the aircraft: two current ratings, a channel
## count, a mass and a bolt pattern. Nothing is derived, because nothing has to be worked out.
##
## ---------------------------------------------------------------------------
## THE LABEL THAT IS DOING THE REAL WORK
## ---------------------------------------------------------------------------
##
## The continuous and burst fields say PER MOTOR (PER CHANNEL) in the form itself, not in a tooltip
## a builder has to hover to find. escs.json's `_schema` names this as the single most important
## thing to get right, and this dialog is the first place in the project where somebody can get it
## wrong: a "60A 4-in-1" prints 60 on the product page and may well print 240 on the box.
##
## The live panel below the fields says what the entered figure means across the whole board — 60 A
## per channel becomes "240 A across 4 channels" as the builder types — because the fastest way to
## notice you have entered the whole-board figure is to be shown the whole-board figure it implies.
## EscPlausibility catches it afterwards on the build; this catches it before it is saved.
##
## The dialog builds NO record of its own. It collects values, hands them to CustomEscs.make_record,
## and shows whatever CustomEscs.add refuses.

signal esc_saved(part_id: String)

## Spelled as escs.json spells them, because a custom board lands in the shipped catalog's own
## filter buckets rather than in a bucket of one.
const CELL_RANGES := ["1-2S", "2-4S", "3-6S", "3-8S"]
const PROTOCOLS := ["DShot300", "DShot600", "DShot1200"]

var _name := LineEdit.new()
var _continuous := SpinBox.new()
var _burst := SpinBox.new()
var _channels := SpinBox.new()
var _mass := SpinBox.new()
var _pattern := LineEdit.new()
var _cell_range := OptionButton.new()
var _protocol := OptionButton.new()
var _source := LineEdit.new()
var _implied := Label.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom ESC"
	ok_button_text = "Save ESC"
	# `confirmed` rather than the OK button's `pressed`, and re-shown on a refusal — see
	# _on_confirmed, and CustomBatteryDialog's copy of the same note for why there is no other way.
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)

	# The label carries the warning. Not the tooltip: a tooltip is read by someone who already
	# suspects there is something to know.
	_continuous.tooltip_text = "The figure printed on the product page — one channel, one motor."
	_add_row(grid, "Continuous (A) PER MOTOR", _configure(_continuous, 0.0, 500.0, 1.0))
	_burst.tooltip_text = "Carried and shown, never modelled as a limit — see the build panel."
	_add_row(grid, "Burst (A) PER MOTOR", _configure(_burst, 0.0, 500.0, 1.0))
	_add_row(grid, "Channels", _configure(_channels, 1.0, 8.0, 1.0))
	_add_row(grid, "Board mass (g)", _configure(_mass, 0.0, 200.0, 0.1))

	_pattern.placeholder_text = "30.5x30.5"
	_add_row(grid, "Bolt pattern", _pattern)

	for cell_range in CELL_RANGES:
		_cell_range.add_item(cell_range)
	_add_row(grid, "Cell range", _cell_range)

	for protocol in PROTOCOLS:
		_protocol.add_item(protocol)
	_add_row(grid, "Protocol", _protocol)

	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	# The whole-board figure the entry implies, live. Recomputed off every editor that feeds it,
	# because a builder who has entered 240 should see "960 A across 4 channels" appear under their
	# hand — which is a number nobody can look at and still believe.
	_implied.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_implied.custom_minimum_size = Vector2(420, 0)
	root.add_child(_implied)

	for box in [_continuous, _burst, _channels]:
		(box as SpinBox).value_changed.connect(func(_v: float) -> void: _refresh_implied())
	_channels.value = CustomEscs.DEFAULT_CHANNELS
	_refresh_implied()

	# Every refusal at once rather than one per attempt — see CustomParts.add.
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(420, 0)
	_problems.theme_type_variation = &"WarnLabel"
	_problems.add_theme_color_override("font_color", LothalTheme.WARNING)
	_problems.visible = false
	root.add_child(_problems)


static func _configure(box: SpinBox, minimum: float, maximum: float, step: float) -> SpinBox:
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.custom_minimum_size = Vector2(140, 0)
	return box


func _add_row(grid: GridContainer, label_text: String, editor: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(editor)


func _refresh_implied() -> void:
	_implied.text = implied_text()


## What the entered rating means across the whole board, as a string. Separate from the Label so a
## test can assert it without instantiating a Control — the same reasoning
## CustomBatteryDialog.derived_text carries.
func implied_text() -> String:
	var channels := int(_channels.value)
	var continuous := _continuous.value
	if channels < 1 or continuous <= 0.0:
		return "Enter the PER-MOTOR continuous rating — the figure on the product page — and the channel count."
	return "%.0f A per motor is %.0f A across %d channels. If %.0f A is what the whole board is rated for, divide it by %d and enter %.0f instead. Burst (%.0f A) is carried and never used as a limit." % [
		continuous, continuous * float(channels), channels, continuous, channels,
		continuous / float(channels), _burst.value]


## Fills the form. Public because it is how a test drives the dialog and how "edit this one" would
## populate it later; there is no second path into these controls.
func set_fields(part_name: String, continuous_a: float, burst_a: float, channels: int,
		mass_g: float, pattern: String, cell_range: String, protocol: String,
		source: String) -> void:
	_name.text = part_name
	_continuous.value = continuous_a
	_burst.value = burst_a
	_channels.value = channels
	_mass.value = mass_g
	_pattern.text = pattern
	_cell_range.select(CELL_RANGES.find(cell_range))
	_protocol.select(PROTOCOLS.find(protocol))
	_source.text = source
	_refresh_implied()


func problems() -> Array[String]:
	return _last_problems


## Builds the record, asks CustomEscs to accept it, and writes the file. Returns the refusals —
## empty means it was saved. The document is RELOADED rather than held, for the reason
## CustomBatteryDialog.submit gives: a stale copy is how one window silently loses another's part.
func submit() -> Array[String]:
	var document := CustomEscs.load_from()
	var cell_index := _cell_range.selected
	var protocol_index := _protocol.selected
	var record := CustomEscs.make_record(
		_name.text.strip_edges(), _continuous.value, _burst.value, int(_channels.value),
		_mass.value, _pattern.text.strip_edges(),
		CELL_RANGES[cell_index] if cell_index >= 0 else "",
		PROTOCOLS[protocol_index] if protocol_index >= 0 else "",
		_source.text.strip_edges())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	esc_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems


## Save, and re-open the form if the record was refused. See CustomBatteryDialog._on_confirmed for
## why the window has to be put back up rather than kept from closing.
func _on_confirmed() -> void:
	if not submit().is_empty():
		show()
