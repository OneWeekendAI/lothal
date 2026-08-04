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
##
## BOTH NUMBERS ARE ON SCREEN, which is the whole reason the compression is a visible setting
## rather than a constant. "4:30" alone would be a lie of omission; "4:30 of a real 45:00" says
## what is being compressed and by how much, and a user who wants the real wait can take it.
##
## WHAT IS SHOWN, AND WHO OWNS IT. State of charge, capacity in mAh, resting voltage, per-cell
## voltage, and time to full. Not one of them is computed here: the charge and both clocks come
## from PackCharge, and the voltages come from a BatteryModel seeded from that same store — the
## same class the bench plots and the aircraft flies. This panel formats numbers and owns none of
## them, which is what stops the garage and the field from quoting different figures for one pack.
##
## PER-CELL VOLTAGE is on the panel because it is the number a real builder actually reads. Pack
## voltage means nothing without the cell count beside it; 3.79 V per cell is the figure a storage
## charge, a low-voltage alarm and a decision to land are all quoted in, and it is the same number
## whether the pack is a 1S whoop or a 6S long-range brick.

signal charge_changed

const OPTIONS := [
	{"label": "10 : 1  (compressed)", "value": PackCharge.DEFAULT_COMPRESSION},
	{"label": "1 : 1  (real time)", "value": 1.0},
]

## Below this fraction the pack reads as flat on the shelf, matching the bench's knee colour.
const LOW_FRACTION := 0.2

var charge: PackCharge
var catalog: PartsCatalog

var _bar: ProgressBar
var _summary: Label
var _volts: Label
var _clock: Label
var _button: Button
var _compression: OptionButton
var _shelf: Label
var _note: Label

## WHAT IS ON THE CHARGER IS NOT WHAT IS ON SCREEN. The charger holds the pack that was put on
## it and keeps hold of it while the builder goes and reads about something else — which is the
## only behaviour a charger can have and still be worth walking away from. Selection decides what
## this panel DISPLAYS; these three decide what is actually filling.
##
## Held as an id, a capacity and a name rather than as a Build, precisely because the pack being
## charged may be one the panel is no longer showing and can no longer ask.
var _charging_id := ""
var _charging_capacity_mah := 0.0
var _charging_name := ""

## Whether the charger is running at all, on any pack. Lab ticks it; nothing else does.
var charging: bool:
	get:
		return _charging_id != ""

var _pack: Dictionary = {}
## The build the selected pack belongs to, so the panel can ask it for a BatteryModel rather than
## assembling one out of raw catalog fields and acquiring a second opinion about the pack.
var _build: Build = null


func _init(p_charge: PackCharge, p_catalog: PartsCatalog = null) -> void:
	charge = p_charge
	catalog = p_catalog
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	PartDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = "CHARGER"
	title.theme_type_variation = &"MutedLabel"
	root.add_child(title)

	_summary = Label.new()
	_summary.theme_type_variation = &"SubHeroReadoutLabel"
	root.add_child(_summary)

	# Resting voltage and per-cell voltage, on their own line under the capacity. Two views of one
	# fact, because a pack is bought and charged in pack volts and JUDGED in cell volts.
	_volts = Label.new()
	_volts.theme_type_variation = &"MutedLabel"
	root.add_child(_volts)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	root.add_child(_bar)

	# The countdown, and what it is a compression of. Updated on every tick while charging, so it
	# actually counts down rather than being a figure quoted once when the button was pressed.
	# Wraps, like the shelf and the note below it: the longest form of this line names the pack
	# being charged as well as both clocks, and a Label that cannot wrap answers a string that
	# long by widening the whole rail.
	_clock = Label.new()
	_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock.custom_minimum_size = Vector2(InstrumentPanel.CAPTION_WIDTH, 0)
	_clock.theme_type_variation = &"ReadoutLabel"
	root.add_child(_clock)

	var controls := HBoxContainer.new()
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

	# The shelf: every pack you own, and whether it is worth fitting. The one thing a charger
	# screen has to answer that the selected pack cannot — labs-and-sim.md §5's point about owning
	# two packs only means something if you can see both at once.
	_shelf = Label.new()
	_shelf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shelf.custom_minimum_size = Vector2(InstrumentPanel.CAPTION_WIDTH, 0)
	_shelf.theme_type_variation = &"MutedLabel"
	root.add_child(_shelf)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(InstrumentPanel.CAPTION_WIDTH, 0)
	_note.theme_type_variation = &"MutedLabel"
	_note.text = "Flying and bench runs drain at 1:1. Charging is compressed, because waiting " \
		+ "45 minutes teaches nothing that waiting four does not."
	root.add_child(_note)

	_select_current_compression()


## Points the panel at a pack. Called whenever Lab's selection changes — which is on EVERY part
## change, frames and motors included. It therefore does not touch what is on the charger: this
## used to stop it, so picking a different frame silently unplugged a pack that was halfway full.
func render(build: Build) -> void:
	_pack = build.battery
	_build = build
	_refresh()


## Puts `delta` seconds on the charger, if it is running. Returns true if anything changed, so
## Lab only writes the file on a frame that actually moved something.
func tick(delta: float) -> bool:
	if _charging_id == "":
		return false
	# The pack on the charger and its capacity, NOT the selected pack's — otherwise a 1500 mAh
	# pack would fill at whatever rate the pack you happen to be reading about implies.
	var restored := charge.charge(_charging_id, delta, _charging_capacity_mah)
	if restored <= 0.0:
		# Full. Stop rather than sit there running against a pack that cannot take any more.
		_stop()
		return true
	_refresh()
	return true


## Puts the SELECTED pack on the charger, or takes whatever is on it off. Pressing Charge while
## looking at a second pack moves the charger to that pack: there is one charger in the garage,
## and putting a pack on it is the act of taking the other one off.
func set_charging(value: bool) -> void:
	if value and not _pack.is_empty() and not charge.is_full(_part_id()):
		_charging_id = _part_id()
		_charging_capacity_mah = _capacity_mah()
		_charging_name = str(_pack.get("name", _charging_id))
	else:
		_charging_id = ""
		_charging_capacity_mah = 0.0
		_charging_name = ""
	_refresh()
	charge_changed.emit()


## Takes `part_id` off the charger, if that is what is on it. Returns whether anything came off.
##
## A pack cannot be on the charger and in the aircraft at the same time, and the rooms that fly
## or bench one do not merely disagree with a charger that keeps running into them: they snapshot
## the pack on the way in and write it back on the way out, so the charger's whole contribution
## is overwritten the moment you walk back to the garage. Leaving with a pack unplugs it.
## Charging a pack you are NOT taking with you is untouched — that is the case worth having.
func release(part_id: String) -> bool:
	if part_id == "" or _charging_id != part_id:
		return false
	_stop()
	return true


func _stop() -> void:
	_charging_id = ""
	_charging_capacity_mah = 0.0
	_charging_name = ""
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

	var capacity := _capacity_mah()
	var fraction := charge.remaining_fraction(_part_id(), capacity)
	_bar.value = fraction * 100.0
	_summary.text = "%.0f %%   ·   %.0f of %.0f mAh" % [
		fraction * 100.0, capacity * fraction, capacity]
	# Exception: Dynamic runtime color shift based on low battery state threshold
	_summary.add_theme_color_override("font_color",
		InstrumentPanel.SAG_COLOUR if fraction < LOW_FRACTION else InstrumentPanel.VALUE_COLOUR)

	_volts.text = _voltage_text()
	_clock.text = _clock_text()
	_shelf.text = _shelf_text()

	# The button acts on the pack ON SCREEN, so it reads against that pack rather than against
	# the charger: "Stop" only while the thing you are looking at is the thing that is filling.
	var showing_the_charged_pack := _charging_id != "" and _charging_id == _part_id()
	if charge.is_full(_part_id()):
		_button.text = "Full"
		_button.disabled = true
		_button.button_pressed = false
	else:
		_button.disabled = false
		_button.button_pressed = showing_the_charged_pack
		_button.text = "Stop" if showing_the_charged_pack else "Charge"


## Where this pack is resting at its current state of charge, at the pack and per cell. Seeded
## from the same store the aircraft is, through the same BatteryModel — this panel does not own a
## discharge curve and must never grow one.
func _voltage_text() -> String:
	var pack := _battery_model()
	if pack == null:
		return ""
	return "%.2f V resting   ·   %.2f V per cell   ·   %dS" % [
		pack.resting_voltage_v(), pack.resting_cell_v(), pack.cells]


## The countdown, and the real wait it stands for. Both, always, while there is charging left to
## do — the compression is only honest if the thing being compressed is legible beside it.
##
## When the charger is running on a pack that is NOT the one on screen, the countdown is about
## that pack and has to name it. A time with no subject beside a different pack's percentage is
## worse than no time at all — it reads as a claim about the pack you are looking at.
func _clock_text() -> String:
	var id := _part_id()
	var capacity := _capacity_mah()
	var away := _charging_id != "" and _charging_id != id
	if away:
		id = _charging_id
		capacity = _charging_capacity_mah
	elif charge.is_full(id):
		return "Full — nothing to put back."
	var compressed := charge.seconds_to_full(id, capacity)
	var real := charge.real_seconds_to_full(id, capacity)
	var verb := ("Charging %s: " % _charging_name) if away \
		else ("Charging: " if charging else "To full: ")
	if is_equal_approx(charge.charge_compression, 1.0):
		return "%s%s, in real time." % [verb, Duration.spoken(real)]
	return "%s%s left, compressed %.0f:1 from a real %s." % [
		verb, Duration.spoken(compressed), charge.charge_compression, Duration.spoken(real)]


## Every pack on the shelf and whether it is worth fitting, shortest form that still distinguishes
## them. Absent from the store means never flown, which is a full pack.
func _shelf_text() -> String:
	if catalog == null:
		return ""
	var charged: Array = []
	var flat: Array = []
	for pack in catalog.list_category("battery"):
		var capacity := float(pack["specs"]["mah"])
		var fraction := charge.remaining_fraction(str(pack["part_id"]), capacity)
		var entry := "%s %.0f%%" % [pack["name"], fraction * 100.0]
		if fraction < LOW_FRACTION:
			flat.append(entry)
		elif fraction < 0.999:
			charged.append(entry)
	if charged.is_empty() and flat.is_empty():
		return "Shelf: every pack full."
	var parts: Array = []
	if not flat.is_empty():
		parts.append("flat — %s" % ", ".join(flat))
	if not charged.is_empty():
		parts.append("part-used — %s" % ", ".join(charged))
	return "Shelf: %s. Everything else is full." % "; ".join(parts)


## The selected pack as a BatteryModel, at the charge the shelf says it has.
func _battery_model() -> BatteryModel:
	if _build == null:
		return null
	var pack := _build.battery_model()
	charge.apply_to(_part_id(), pack)
	return pack


## Readable text of everything on the panel, so tests can assert what the charger says without
## reading pixels.
func readout_text() -> Dictionary:
	return {
		"summary": _summary.text,
		"volts": _volts.text,
		"clock": _clock.text,
		"button": _button.text,
		"shelf": _shelf.text,
		"note": _note.text,
	}
