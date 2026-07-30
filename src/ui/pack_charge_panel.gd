class_name PackChargePanel
extends PanelContainer
## The charger, which is a thing in the garage and not a thing in the field (labs-and-sim.md §5).
##
## It sits with the battery panel rather than becoming a rail of its own, because charging is not
## a part choice — there is nothing to browse and nothing to filter. What it shows is the state of
## the pack currently selected: how much is in it, and how long it would take to fill.
##
## THE ASYMMETRY IS THE POINT, and it is worth saying on screen rather than only in a design doc.
## Draining runs at 1:1 — a four-minute pack gives four minutes, in the air or on a bench — because
## that is the part that teaches something true. Charging runs compressed, because the realism of
## sitting through 45 minutes costs the user's patience and buys no transferable intuition. 1:1 is
## there for anyone who disagrees, which is also the honest way to hold an opinion like this one.

signal charge_changed

const OPTIONS := [
	{"label": "10 : 1  (compressed)", "value": PackCharge.DEFAULT_COMPRESSION},
	{"label": "1 : 1  (real time)", "value": 1.0},
]

var charge: PackCharge

var _bar: ProgressBar
var _summary: Label
var _button: Button
var _compression: OptionButton
var _note: Label

## Whether the charger is running. Lab ticks it; nothing else does.
var charging := false

var _pack: Dictionary = {}


func _init(p_charge: PackCharge) -> void:
	charge = p_charge
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	PartDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = "CHARGER"
	title.add_theme_color_override("font_color", InstrumentPanel.LABEL_COLOUR)
	root.add_child(title)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 22)
	root.add_child(_summary)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	root.add_child(_bar)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)

	_button = Button.new()
	_button.toggle_mode = true
	_button.custom_minimum_size = Vector2(110, 28)
	_button.pressed.connect(func() -> void: set_charging(not charging))
	controls.add_child(_button)

	_compression = OptionButton.new()
	_compression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in OPTIONS:
		_compression.add_item(option["label"])
	_compression.item_selected.connect(_on_compression_selected)
	controls.add_child(_compression)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(InstrumentPanel.CAPTION_WIDTH, 0)
	_note.add_theme_color_override("font_color", InstrumentPanel.MUTED_COLOUR)
	_note.text = "Flying and bench runs drain at 1:1. Charging is compressed, because waiting " \
		+ "45 minutes teaches nothing that waiting four does not."
	root.add_child(_note)

	_select_current_compression()


## Points the charger at a pack. Called whenever Lab's selection changes.
func render(build: Build) -> void:
	_pack = build.battery
	charging = false
	_refresh()


## Puts `delta` seconds on the charger, if it is running. Returns true if anything changed, so
## Lab only writes the file on a frame that actually moved something.
func tick(delta: float) -> bool:
	if not charging or _pack.is_empty():
		return false
	var restored := charge.charge(_part_id(), delta, _capacity_mah())
	if restored <= 0.0:
		# Full. Stop rather than sit there running against a pack that cannot take any more.
		set_charging(false)
		return true
	_refresh()
	return true


func set_charging(value: bool) -> void:
	charging = value and not charge.is_full(_part_id())
	_refresh()
	charge_changed.emit()


func _on_compression_selected(index: int) -> void:
	charge.set_compression(float(OPTIONS[index]["value"]))
	_refresh()
	charge_changed.emit()


func _select_current_compression() -> void:
	for i in OPTIONS.size():
		if is_equal_approx(float(OPTIONS[i]["value"]), charge.charge_compression):
			_compression.select(i)
			return
	_compression.select(0)


func _part_id() -> String:
	return str(_pack.get("part_id", ""))


func _capacity_mah() -> float:
	return float(_pack.get("specs", {}).get("mah", 0.0))


func _refresh() -> void:
	if _pack.is_empty():
		return

	var fraction := charge.remaining_fraction(_part_id(), _capacity_mah())
	_bar.value = fraction * 100.0
	_summary.text = "%.0f %%   ·   %.0f of %.0f mAh" % [
		fraction * 100.0, _capacity_mah() * fraction, _capacity_mah()]
	# The same colour the bench uses below the knee, so "nearly flat" reads the same in both rooms.
	_summary.add_theme_color_override("font_color",
		InstrumentPanel.SAG_COLOUR if fraction < 0.2 else InstrumentPanel.VALUE_COLOUR)

	if charge.is_full(_part_id()):
		_button.text = "Full"
		_button.disabled = true
		_button.button_pressed = false
	else:
		_button.disabled = false
		_button.button_pressed = charging
		_button.text = "Stop" if charging else "Charge (%s)" % _format(
			charge.seconds_to_full(_part_id(), _capacity_mah()))


## Readable text of everything on the panel, so tests can assert what the charger says without
## reading pixels.
func readout_text() -> Dictionary:
	return {"summary": _summary.text, "button": _button.text, "note": _note.text}


static func _format(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0f s" % seconds
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
