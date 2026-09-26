class_name CustomComponentDialog
extends AcceptDialog
## Lab's form for entering a camera, VTX, antenna, receiver, GPS or buzzer Lothal does not stock (C7).
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not).
##
## ---------------------------------------------------------------------------
## ONE DIALOG FOR SIX CATEGORIES, AND WHY THAT IS NOT THE MISTAKE CustomParts WARNS ABOUT
## ---------------------------------------------------------------------------
##
## The six older categories each have their own form, because each asks a different question — a
## frame's is geometry, a motor's is a thrust test, an FC's is a noise floor it derives for you.
## These six ask ONE question, the same one CustomComponents' header says they ask: what does it
## weigh, what box does it occupy, and where did those numbers come from. Six copies of that form
## would be six places for the three dimensions to be wired to the wrong arguments, and the one
## that drifted would be the one nobody opened.
##
## What genuinely differs is small and lives in two tables below: which browsing strings a category
## carries (EXTRA_TEXT), and the two physics-bearing extras C2 added — the GPS's mast and the
## buzzer's power source. Those two are NOT text fields, and the difference is the point of them.
##
## ---------------------------------------------------------------------------
## THE MAST IS A TEXT BOX AND THE POWER SOURCE STARTS UNANSWERED
## ---------------------------------------------------------------------------
##
## A SpinBox always holds a number. A mast SpinBox would open on 0, and a builder who never looked
## at it would save a masted module as a flat one — exactly the silent default CustomGps refuses.
## So the mast is typed: empty is "not entered" and reaches that refusal, 0 is a flat module said
## out loud, and anything that is not a number is refused here by name.
##
## The buzzer's power source is a dropdown whose first row is a question rather than an answer, for
## the same reason: CustomBuzzers' header explains why neither true nor false is safe to assume, and
## a dropdown that opened on either would be assuming it.
##
## Refusals keep the dialog open: AcceptDialog hides itself on OK before any handler runs, so
## `_on_confirmed` shows it again (tests/test_custom_parts_ui.gd presses the real button).

signal component_saved(part_id: String)

## The browsing strings each category's make_record takes, in its parameter order. Keys are the
## record's own `catalog` keys, so a stored record and this form name a field the same way.
const EXTRA_TEXT := {
	"camera": [["signal", "Signal (analog/digital)"], ["size_class", "Size class"], ["sensor", "Sensor"]],
	"vtx": [["signal", "Signal (analog/digital)"], ["power_class", "Power class"], ["band", "Band"]],
	"antenna": [["polarisation", "Polarisation"], ["connector", "Connector"], ["gain_class", "Gain class"]],
	"receiver": [["protocol", "Protocol"], ["band", "Band"], ["antenna_type", "Antenna type"]],
	"gps": [["constellations", "Constellations"], ["protocol", "Protocol"]],
	"buzzer": [],
}

## The buzzer's power rows. Index 0 is the unanswered question and maps to null.
const POWER_UNANSWERED := "Choose how it is powered…"
const POWER_OWN_CELL := "Own cell — keeps sounding when the pack ejects"
const POWER_FC_RAIL := "Flight controller 5 V — silent when the pack ejects"

var category: String

var _name := LineEdit.new()
var _mass := SpinBox.new()
var _length := SpinBox.new()
var _width := SpinBox.new()
var _height := SpinBox.new()
var _source := LineEdit.new()
var _text: Dictionary = {}            # catalog key -> LineEdit
var _mast := LineEdit.new()           # gps only
var _compass := CheckBox.new()        # gps only
var _power := OptionButton.new()      # buzzer only
var _loudness := LineEdit.new()       # buzzer only
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init(p_category: String) -> void:
	category = p_category
	title = "New custom %s" % str(ElectronicsPicker.CATEGORY_LABELS.get(category, category))
	ok_button_text = "Save part"
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)
	_add_row(grid, "Mass (g)", _configure(_mass, 0.0, 500.0, 0.1))
	_add_row(grid, "Length (mm)", _configure(_length, 0.0, 300.0, 0.5))
	_add_row(grid, "Width (mm)", _configure(_width, 0.0, 300.0, 0.5))
	_add_row(grid, "Height (mm)", _configure(_height, 0.0, 300.0, 0.5))

	for field in EXTRA_TEXT.get(category, []):
		var edit := LineEdit.new()
		_text[field[0]] = edit
		_add_row(grid, field[1], edit)

	if category == "gps":
		_mast.placeholder_text = "0 for a flat module"
		_mast.tooltip_text = "How far the module stands above the top plate on its stalk. Required: 0 is a flat module, and leaving it empty is refused rather than read as 0."
		_add_row(grid, "Mast height (mm)", _mast)
		_compass.text = "Has a compass"
		_add_row(grid, "", _compass)
	elif category == "buzzer":
		for row in [POWER_UNANSWERED, POWER_OWN_CELL, POWER_FC_RAIL]:
			_power.add_item(row)
		_power.select(0)
		_add_row(grid, "Powered by", _power)
		_loudness.placeholder_text = "leave empty if unpublished"
		_add_row(grid, "Loudness (dB)", _loudness)

	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

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


## The store a category's records live in, freshly read from `path`. One table for the dialog AND
## the rail's Delete, so the two cannot disagree about where a camera is kept. Null for a category
## with no store — which the rail treats as "no authoring here", and C4's registration row reddens.
static func document_for(p_category: String, path: String = CustomParts.SAVE_PATH) -> CustomComponents:
	match p_category:
		"camera": return CustomCameras.load_from(path)
		"vtx": return CustomVtxs.load_from(path)
		"antenna": return CustomAntennas.load_from(path)
		"receiver": return CustomReceivers.load_from(path)
		"gps": return CustomGps.load_from(path)
		"buzzer": return CustomBuzzers.load_from(path)
	return null


## Fills the form. `meta` holds the category's extras by their record keys: EXTRA_TEXT's strings,
## and for a GPS `mast_height_mm` (a float; absent or NAN leaves the field empty) and `compass`, for
## a buzzer `self_powered` (a bool; absent or null leaves the question unanswered) and `loudness_db`.
func set_fields(part_name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, meta: Dictionary, source: String) -> void:
	_name.text = part_name
	_mass.value = mass_g
	_length.value = length_mm
	_width.value = width_mm
	_height.value = height_mm
	for key in _text:
		(_text[key] as LineEdit).text = str(meta.get(key, ""))
	if category == "gps":
		var mast: Variant = meta.get("mast_height_mm", NAN)
		_mast.text = "" if (mast is float and is_nan(mast)) else str(mast)
		_compass.button_pressed = bool(meta.get("compass", false))
	elif category == "buzzer":
		var powered: Variant = meta.get("self_powered", null)
		_power.select(0 if powered == null else (1 if bool(powered) else 2))
		var loud: Variant = meta.get("loudness_db", null)
		_loudness.text = "" if loud == null else str(loud)
	_source.text = source


func problems() -> Array[String]:
	return _last_problems


func _meta_text(key: String) -> String:
	return (_text[key] as LineEdit).text.strip_edges()


## Builds the record through the category's own make_record, asks its store to accept it, and
## writes the file. Form-level refusals (a mast or loudness that is not a number) are reported
## alongside the store's, so a builder sees every problem at once.
func submit() -> Array[String]:
	var document := document_for(category)
	var form_problems: Array[String] = []
	var name_text := _name.text.strip_edges()
	var source_text := _source.text.strip_edges()
	var record: Dictionary

	match category:
		"camera":
			record = CustomCameras.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, _meta_text("signal"), _meta_text("size_class"), _meta_text("sensor"),
				source_text)
		"vtx":
			record = CustomVtxs.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, _meta_text("signal"), _meta_text("power_class"), _meta_text("band"),
				source_text)
		"antenna":
			record = CustomAntennas.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, _meta_text("polarisation"), _meta_text("connector"),
				_meta_text("gain_class"), source_text)
		"receiver":
			record = CustomReceivers.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, _meta_text("protocol"), _meta_text("band"), _meta_text("antenna_type"),
				source_text)
		"gps":
			var mast_text := _mast.text.strip_edges()
			var mast := NAN
			if mast_text != "":
				if mast_text.is_valid_float():
					mast = mast_text.to_float()
				else:
					form_problems.append("mast height \"%s\" is not a number of millimetres" % mast_text)
			record = CustomGps.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, mast, _meta_text("constellations"), _compass.button_pressed,
				_meta_text("protocol"), source_text)
		"buzzer":
			var powered: Variant = null
			if _power.selected == 1:
				powered = true
			elif _power.selected == 2:
				powered = false
			var loud_text := _loudness.text.strip_edges()
			var loud: Variant = null
			if loud_text != "":
				if loud_text.is_valid_float():
					loud = loud_text.to_float()
				else:
					form_problems.append("loudness \"%s\" is not a number of dB — leave it empty if nobody publishes one" % loud_text)
			record = CustomBuzzers.make_record(name_text, _mass.value, _length.value, _width.value,
				_height.value, powered, loud, source_text)

	if document == null:
		var none: Array[String] = ["\"%s\" has no custom-parts store" % category]
		_last_problems = none
	else:
		_last_problems = form_problems
		# Asked even when the form already refused, so every problem shows at once — and add() only
		# holds the record in memory; nothing is written unless both lists are empty.
		_last_problems.append_array(document.add(record))

	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	component_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems


func _on_confirmed() -> void:
	if not submit().is_empty():
		show()
