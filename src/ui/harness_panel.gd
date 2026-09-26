class_name HarnessPanel
extends VBoxContainer
## Power's third inspector panel: what the current path is made of, and the door into the room that
## draws it — plans/2026-09-10-power-room-plan.md, slice PW5.
##
## **This replaces `HarnessStub`.** That panel said "the model is built, the view is not" and named
## PW5 as what it waited on. PW5 is this commit, so the promise is either kept or it becomes a lie
## that ships — and a stub left standing beside the room it was waiting for is the worst of the two
## states it could be in.
##
## The panel is a summary and a door, which is the shape the ESC panel already uses: the rows say
## what is fitted, and the button opens the workbench where it can be changed. It does not
## duplicate the schematic. A second, smaller drawing in a 320 px column would be two answers to
## the question the room exists to answer, at the size that answers it worst.
##
## It opens nothing itself — `EscDetails`' posture, and for its reason: the button says what
## happened and the shell decides what to do about it, so the room lifecycle stays in one place.

## Emitted when the builder asks for the Power room. The shell opens it.
signal harness_room_requested()

## The width the wrapped prose is laid out to. `HarnessStub`'s constant, kept with its reason: an
## autowrapping Label reports its whole unwrapped string as its minimum width, and `_fit_columns`
## measures minimums — a panel that asked for 900 px would widen the inspector for every system
## that shares the column.
const WRAP_WIDTH := 300.0

var _rows: VBoxContainer
var _caption: Label


func _init() -> void:
	name = "Harness"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", LothalTheme.SPACE_3)

	var title := Label.new()
	title.text = "Harness"
	title.theme_type_variation = &"TitleLabel"
	add_child(title)

	var door := Button.new()
	door.text = "Open harness designer…"
	door.tooltip_text = ("Draw the current path to scale — every wire at its own gauge and its own "
		+ "length — and change the gauge or the length of any segment.")
	door.pressed.connect(func() -> void: harness_room_requested.emit())
	add_child(door)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(_rows)

	_caption = Label.new()
	_caption.theme_type_variation = &"SmallLabel"
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	_caption.text = ("Lead lengths and gauges are class-typical defaults, not measured figures — "
		+ "the designer shows what the parts imply beside anything you type.")
	add_child(_caption)


## The current path on THIS aircraft. Rebuilt rather than updated in place, because the row list is
## short and a panel that edited labels it created earlier is a panel that can be pointed at a
## build it is no longer describing.
##
## The wire rows come from `HarnessChecks.segments` — the same list the schematic draws and the
## ampacity check walks. A panel with its own idea of what the segments are would be the private
## copy this section's whole rule is about, arriving in the quietest possible place.
func render(build: Build) -> void:
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)
	if build == null or build.battery.is_empty():
		_row("—", "no aircraft")
		return

	var harness := build.harness
	_row("Connector", String(harness.connector_row(build).get("name", "none")))
	for segment in HarnessChecks.segments(build):
		_row(String(segment["label"]), "%d AWG, %.0f mm" % [
			int(segment["awg"]), float(segment["length_mm"])])
	_row("Capacitor", String(harness.capacitor_row(build).get("name", "none")))
	_row("Harness mass", "%.1f g" % harness.total_mass_g(build))


## Shows or hides the "class-typical defaults" caption. Off on the Lab dock's Harness page, where
## the `~` on the page's numbers says it without a paragraph (lab dock design §3).
func set_caption_visible(shown: bool) -> void:
	_caption.visible = shown


func caption_visible() -> bool:
	return _caption.visible


func _row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)

	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"MutedLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	row.add_child(value)
	_rows.add_child(row)
