class_name NewBladeDialog
extends AcceptDialog
## The Propulsion room's "New blade…" form — §3.2 of
## plans/2026-09-01-authored-blade-design.md.
##
## Five fields: name, diameter, pitch, blade count, material. That is not an arbitrary five — it is
## exactly what `PlanformEdits.new_blade` needs to hand back a document the room can draw, and
## nothing else is asked for. There is no mass field here for the same reason there is none on the
## publish path: `CustomPropellers.record_from_document` derives mass from the geometry, and a
## number typed in this form would be a second answer waiting to disagree with the integral.
##
## ## Why a form at all, when the airframe room's "New" is a bare button
##
## `FrameWorkbench._on_new` opens an empty frame with no questions, because an empty frame is a
## real thing to look at — a datum and a canvas — and every dimension is added by drawing. A
## propeller is not like that. A blade has a radius before it has a shape: the planform canvas
## scales to it, the section view sections it, `chord_at` is a function of `r/R`, and the generated
## arch that gives the builder something to drag is itself a function of diameter and blade count.
## So the three numbers are asked once, up front, rather than left at zero for a room that would
## then be drawing a propeller of no size.
##
## ## What this dialog refuses, and what it deliberately does not judge
##
## It refuses only what stops a DOCUMENT from existing: a blade with no name has no id to be saved
## under, and a blade with no diameter or no pitch has no radius and no twist, which every view in
## the room divides by. It does NOT ask whether the blade is a sensible one. Whether a 5" three-blade
## at this chord is plausible is `PropPlausibility`'s question, asked of the fitted build where every
## other plausibility check lives (§6), and whether the published record is one the parts system will
## accept is `CustomPropellers`'s, asked at publish time. Answering either here would be a second
## opinion in a worse place.

signal blade_created(document: PropellerDocument)

## The same vocabulary `CustomPropellerDialog` offers, read through
## `PropellerDocument.material_id_for_catalog` rather than listed again in the document's own id
## space. One list of words a builder picks from, one mapping into the model — the alternative is
## two lists that drift, and the drift would be silent because both sides are strings.
const MATERIALS := CustomPropellerDialog.MATERIALS

var _name := LineEdit.new()
var _diameter := SpinBox.new()
var _pitch := SpinBox.new()
var _blades := SpinBox.new()
var _material := OptionButton.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New blade"
	ok_button_text = "Start drawing"
	# `confirmed` rather than the OK button's `pressed`, and re-shown on a refusal — see
	# `_on_confirmed`, and `CustomPropellerDialog` for the finding that produced this shape: the
	# engine closes an AcceptDialog itself, so a refused form looked exactly like an accepted one.
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_name.text = "Untitled blade"
	_add_row(grid, "Name", _name)
	_add_row(grid, "Diameter (in)", _configure(_diameter, 0.0, 40.0, 0.1))
	_add_row(grid, "Pitch (in)", _configure(_pitch, 0.0, 40.0, 0.1))
	_add_row(grid, "Blades", _configure(_blades, 1.0, 8.0, 1.0))
	for material in MATERIALS:
		_material.add_item(material)
	_add_row(grid, "Material", _material)

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


## Fills the form. Public because it is how a test drives the dialog, and because the room opens it
## on the blade currently in front of the builder rather than on nothing.
func set_fields(blade_name: String, diameter_inches: float, pitch_inches: float, blades: int,
		material: String) -> void:
	_name.text = blade_name
	_diameter.value = diameter_inches
	_pitch.value = pitch_inches
	_blades.value = blades
	var index := MATERIALS.find(material)
	_material.select(index if index >= 0 else MATERIALS.size() - 1)


func problems() -> Array[String]:
	return _last_problems


## Builds the document and emits it, or returns everything wrong with the form. Public for the same
## reason `CustomPropellerDialog.submit` is: the OK button is one caller and a test is the other.
func submit() -> Array[String]:
	_last_problems = _form_problems()
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	# The conversion is `PropellerDocument.INCH_TO_MM`'s, not a local 25.4: the catalog quotes props
	# in inches because the real world does, and the document is metric because the model is.
	var document := PlanformEdits.new_blade(
		_name.text.strip_edges(),
		_diameter.value * PropellerDocument.INCH_TO_MM,
		_pitch.value * PropellerDocument.INCH_TO_MM,
		int(_blades.value),
		PropellerDocument.material_id_for_catalog(MATERIALS[_material.selected]))
	blade_created.emit(document)
	hide()
	return _last_problems


## The three absences that leave no document, each said in the terms the builder can act on.
func _form_problems() -> Array[String]:
	var faults: Array[String] = []
	if _name.text.strip_edges() == "":
		faults.append("A blade needs a name — it is what the saved file and the published part are called.")
	if _diameter.value <= 0.0:
		faults.append("Diameter must be positive — every station on the planform is a fraction of the radius, and there is no blade to draw without one.")
	if _pitch.value <= 0.0:
		faults.append("Pitch must be positive — it is what the blade's twist is computed from, and a zero-pitch blade makes no thrust at any RPM.")
	return faults


## Start drawing, and put the form straight back up if it was refused. `AcceptDialog` hides itself
## the moment OK is pressed, before `confirmed` reaches us, and no script hook prevents it — see
## `CustomPropellerDialog._on_confirmed` for the whole finding. Re-showing within the same handler
## means the window never repaints in between, so the builder sees a form that simply did not go
## away, with every refusal listed on it.
func _on_confirmed() -> void:
	if not submit().is_empty():
		show()
