class_name CustomPropellerDialog
extends AcceptDialog
## Lab's form for entering a propeller Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not). Nothing in
## src/scenes/ constructs this, and Sim's build panel reads the merged catalog without any way to
## add to it.
##
## Six fields: diameter, pitch, blades, mass, material and the name and provenance that stops it
## from being mistaken for a checked part. Nothing else is asked for: a field that does not feed
## the physics does not go in `specs` (propellers.json's _schema), and material lives in `catalog`
## because nothing here reads blade stiffness.
##
## The dialog builds NO record of its own. It collects values, hands them to
## CustomPropellers.make_record, and shows whatever CustomPropellers.add refuses.

signal propeller_saved(part_id: String)

const MATERIALS := ["polycarbonate", "glass-filled nylon", "carbon-filled nylon", "unspecified"]

var _name := LineEdit.new()
var _mass := SpinBox.new()
var _diameter := SpinBox.new()
var _pitch := SpinBox.new()
var _blades := SpinBox.new()
var _material := OptionButton.new()
var _source := LineEdit.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom propeller"
	ok_button_text = "Save propeller"
	# `confirmed` rather than the OK button's `pressed`, and re-shown on a refusal — see
	# _on_confirmed. The engine closes this window itself; nothing a `pressed` handler does stops
	# it, which is how a refused part came to look exactly like a saved one.
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)
	_add_row(grid, "Prop mass, each (g)", _configure(_mass, 0.0, 500.0, 0.1))
	_add_row(grid, "Diameter (in)", _configure(_diameter, 0.0, 40.0, 0.1))
	_add_row(grid, "Pitch (in)", _configure(_pitch, 0.0, 40.0, 0.1))
	_add_row(grid, "Blades", _configure(_blades, 1.0, 8.0, 1.0))
	for material in MATERIALS:
		_material.add_item(material)
	_add_row(grid, "Material", _material)
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


## Fills the form. Public because it is how a test drives the dialog.
func set_fields(part_name: String, mass_g: float, diameter_inches: float, pitch_inches: float,
		blades: int, material: String, source: String) -> void:
	_name.text = part_name
	_mass.value = mass_g
	_diameter.value = diameter_inches
	_pitch.value = pitch_inches
	_blades.value = blades
	var index := MATERIALS.find(material)
	_material.select(index if index >= 0 else MATERIALS.size() - 1)
	_source.text = source


func problems() -> Array[String]:
	return _last_problems


func submit() -> Array[String]:
	var document := CustomPropellers.load_from()
	var record := CustomPropellers.make_record(
		_name.text.strip_edges(), _mass.value, _diameter.value, _pitch.value,
		int(_blades.value), MATERIALS[_material.selected], _source.text.strip_edges())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	propeller_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems


## Save, and re-open the form if the record was refused.
##
## AcceptDialog hides itself the moment OK is pressed or Enter is hit, before `confirmed` reaches
## us, and there is no hook that prevents it: `_ok_pressed` is a C++ callable bound to the button,
## not a script virtual this class can override. So the honest form is to let it close and put it
## straight back up, within the same handler — the window never repaints in between, and the
## builder sees a form that simply did not go away, with every refusal listed on it.
##
## This is what a builder actually met before: a frame with the arm left at zero, or a part with no
## source, closed the dialog exactly as a saved one does. Nothing was written, nothing said so, and
## the part was missing the next time Lothal opened.
func _on_confirmed() -> void:
	if not submit().is_empty():
		show()
