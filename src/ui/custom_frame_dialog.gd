class_name CustomFrameDialog
extends AcceptDialog
## Lab's form for entering a frame Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not). Nothing in
## src/scenes/ constructs this, and Sim's build panel reads the merged catalog without any way to
## add to it.
##
## Eight fields, which are the six the physics needs plus the name it is shown under and the
## provenance that stops it being mistaken for a checked part. Nothing else is asked for: a field
## that does not feed the physics does not go in `specs` (frames.json's _schema), and a field that
## goes nowhere at all should not be a question on a form.
##
## The dialog builds NO record of its own. It collects strings, hands them to
## CustomFrames.make_record, and shows whatever CustomFrames.add refuses — so the rules about what
## a frame is live in exactly one place and a form that has drifted cannot produce a record no
## reader understands.

signal frame_saved(part_id: String)

const MOUNT_HINT := "e.g. 16x16"
const STACK_HINT := "e.g. 30.5x30.5"

var _name := LineEdit.new()
var _mass := SpinBox.new()
var _arm := SpinBox.new()
var _prop := SpinBox.new()
var _motor_mount := LineEdit.new()
var _stack_mount := LineEdit.new()
var _material := OptionButton.new()
var _source := LineEdit.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom frame"
	ok_button_text = "Save frame"
	# The dialog's own OK must not close it on a refusal, or the builder loses everything they
	# typed the moment they forget the provenance field.
	get_ok_button().pressed.connect(func() -> void: submit())

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)
	_add_row(grid, "Frame mass (g)", _configure(_mass, 0.0, 5000.0, 0.5))
	_add_row(grid, "Arm, centre→motor (mm)", _configure(_arm, 0.0, 2000.0, 0.5))
	_add_row(grid, "Max prop (in)", _configure(_prop, 0.0, 40.0, 0.1))
	_motor_mount.placeholder_text = MOUNT_HINT
	_add_row(grid, "Motor mount", _motor_mount)
	_stack_mount.placeholder_text = STACK_HINT
	_add_row(grid, "Stack mount", _stack_mount)
	for material in CustomFrames.MATERIALS:
		_material.add_item(material)
	_add_row(grid, "Material", _material)
	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	# Every refusal at once rather than one per attempt — see CustomFrames.add.
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


## Fills the form. Public because it is how a test drives the dialog and how "edit this one"
## would populate it later; there is no second path into these controls.
func set_fields(part_name: String, mass_g: float, arm_mm: float, max_prop_inches: float,
		motor_mount: String, stack_mount: String, material: String, source: String) -> void:
	_name.text = part_name
	_mass.value = mass_g
	_arm.value = arm_mm
	_prop.value = max_prop_inches
	_motor_mount.text = motor_mount
	_stack_mount.text = stack_mount
	var index := CustomFrames.MATERIALS.find(material)
	_material.select(index if index >= 0 else CustomFrames.MATERIALS.size() - 1)
	_source.text = source


## Everything wrong with the last submit(), for a caller that wants it without re-submitting.
func problems() -> Array[String]:
	return _last_problems


## Builds the record, asks CustomFrames to accept it, and writes the file. Returns the refusals —
## empty means it was saved. The document is RELOADED rather than held, because the builder may
## have another Lothal window open or may have hand-edited the file, and holding a stale copy is
## how one of the two silently loses the other's frame.
func submit() -> Array[String]:
	var document := CustomFrames.load_from()
	var record := CustomFrames.make_record(
		_name.text.strip_edges(), _mass.value, _arm.value, _prop.value,
		_motor_mount.text.strip_edges(), _stack_mount.text.strip_edges(),
		CustomFrames.MATERIALS[_material.selected], _source.text.strip_edges())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	frame_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems
