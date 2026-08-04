class_name InstrumentPanel
extends PanelContainer
## The readout beside a bench: one or two numbers given real weight, a grid of supporting rows
## under them, and two notes at the bottom.
##
## This was BenchInstruments, and it was the thrust stand's alone until the battery bench needed
## the same panel with different numbers in it. Generalised rather than copied, because the shape
## is an opinion worth holding in one place:
##
## **ONE NUMBER GETS THE WEIGHT.** A panel that renders six figures at the same size teaches
## nothing about which one to read. Every bench has a number that actually decides the question —
## grams per watt on the thrust stand, sag on the battery bench — and it is set apart and set
## large. The rest are context for it.
##
## Nothing here computes anything. It is given strings and it draws them, which is what lets both
## benches feed it straight off the published Observables without either one growing a second
## opinion about what the numbers are.

## Named against LothalTheme rather than restated as literals: a copied colour that agrees with
## the theme today is a colour that disagrees with it after the next palette change, silently.
const LABEL_COLOUR := LothalTheme.TEXT_MUTED
const VALUE_COLOUR := LothalTheme.TEXT_MAIN
const EFFICIENCY_COLOUR := LothalTheme.SUCCESS
const SAG_COLOUR := LothalTheme.DANGER
const LIMIT_COLOUR := LothalTheme.WARNING
const MUTED_COLOUR := LothalTheme.TEXT_MUTED

const PANEL_WIDTH := 336
const CAPTION_WIDTH := 280

var _headlines: Dictionary = {}   # key -> Label holding the big value
var _values: Dictionary = {}      # row key -> Label
var _note_top: Label
var _note_bottom: Label

## `headlines` is an Array of {"key", "label", "caption", "colour"} — one or two, never six.
## `rows` is an Array of {"key", "label"} for the supporting grid.
func _init(headlines: Array, rows: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PartDetails._padded(scroll).add_child(root)

	for headline in headlines:
		var box := VBoxContainer.new()
		root.add_child(box)

		var name_label := Label.new()
		name_label.text = headline["label"]
		name_label.theme_type_variation = &"MutedLabel"
		box.add_child(name_label)

		var value := Label.new()
		value.text = "—"
		value.theme_type_variation = &"HeroReadoutLabel" if headlines.size() == 1 else &"SubHeroReadoutLabel"
		# Exception: Dynamic headline color initialization
		value.add_theme_color_override("font_color", headline.get("colour", VALUE_COLOUR))
		box.add_child(value)
		_headlines[headline["key"]] = value

		var caption := Label.new()
		caption.text = headline.get("caption", "")
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
		caption.theme_type_variation = &"MutedLabel"
		box.add_child(caption)

	root.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	for row in rows:
		var name_label := Label.new()
		name_label.text = row["label"]
		name_label.theme_type_variation = &"MutedLabel"
		grid.add_child(name_label)

		var value := Label.new()
		value.text = "—"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.theme_type_variation = &"ReadoutLabel"
		grid.add_child(value)
		_values[row["key"]] = value

	root.add_child(HSeparator.new())

	_note_top = _note(root, LIMIT_COLOUR)
	_note_bottom = _note(root, MUTED_COLOUR)


func _note(root: VBoxContainer, colour: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
	# Exception: Note role color override
	label.add_theme_color_override("font_color", colour)
	root.add_child(label)
	return label


func set_headline(key: String, text: String) -> void:
	_headlines[key].text = text

func set_headline_colour(key: String, colour: Color) -> void:
	# Exception: Dynamic headline readout color change
	_headlines[key].add_theme_color_override("font_color", colour)

func set_value(key: String, text: String) -> void:
	_values[key].text = text

func set_value_colour(key: String, colour: Color) -> void:
	# Exception: Dynamic grid readout color change
	_values[key].add_theme_color_override("font_color", colour)

func set_notes(top: String, bottom: String) -> void:
	_note_top.text = top
	_note_bottom.text = bottom


## Everything on the panel, as data. Exposed so tests can assert the bench shows what
## labs-and-sim.md says it must without depending on label wording or on reading pixels.
func readout_text() -> Dictionary:
	var out: Dictionary = {}
	for key in _headlines:
		out[key] = _headlines[key].text
	for key in _values:
		out[key] = _values[key].text
	out["note_top"] = _note_top.text
	out["note_bottom"] = _note_bottom.text
	return out
