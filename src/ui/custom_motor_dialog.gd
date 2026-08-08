class_name CustomMotorDialog
extends AcceptDialog
## Lab's form for entering a motor Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not). Nothing in
## src/scenes/ constructs this, and Sim's build panel reads the merged catalog without any way to
## add to it.
##
## THE FORM IS A PRODUCT PAGE, IN THE ORDER A PRODUCT PAGE PRINTS IT. Every field here is
## something the builder can read off the listing in front of them and copy across — stator size,
## KV, max thrust, max current, mass, bolt pattern, pole count — plus the name it is shown under
## and the provenance that stops it being mistaken for a checked part. Nothing is asked for that
## has to be worked out, and nothing is asked for that goes nowhere: a field that does not feed
## the physics does not go in `specs` (motors.json's _schema), and a field that feeds nothing at
## all should not be a question on a form.
##
## THE TWO FIELDS THAT ARE NOT SPECS, AND WHY THEY ARE THE MOST IMPORTANT TWO. `Thrust measured
## on` and `at voltage` are the heading of the column the thrust figure was read out of. They are
## mandatory (CustomMotors refuses a record without them), and they are on the form immediately
## under the thrust figure rather than in some advanced section, because a thrust number without
## them is not a weaker number — it is not a number at all. k_t is fitted from that exact pairing,
## and a motor missing it would fly as though it made no thrust.
##
## The prop is a DROPDOWN of props Lothal knows, not a text field. A typo in a free-text prop id
## is a refusal the builder cannot act on ("which ones do you know?"), and the answer is a list.
##
## The dialog builds NO record of its own. It collects values, hands them to
## CustomMotors.make_record, and shows whatever CustomMotors.add refuses — so the rules about what
## a motor is live in exactly one place and a form that has drifted cannot produce a record no
## reader understands.

signal motor_saved(part_id: String)

const MOUNT_HINT := "e.g. 16x16"

var _catalog: PartsCatalog
var _prop_ids: Array[String] = []
## What set_fields was asked for when the dropdown had no such prop. Kept so the refusal can name
## the id the builder actually gave rather than reporting an empty one.
var _unresolved_prop_id := ""

var _name := LineEdit.new()
var _mass := SpinBox.new()
var _stator_diameter := SpinBox.new()
var _stator_height := SpinBox.new()
var _kv := SpinBox.new()
var _max_thrust := SpinBox.new()
var _max_amps := SpinBox.new()
var _poles := SpinBox.new()
var _mount := LineEdit.new()
var _test_prop := OptionButton.new()
var _test_voltage := SpinBox.new()
var _source := LineEdit.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom motor"
	ok_button_text = "Save motor"
	# `confirmed` rather than the OK button's `pressed`, and re-shown on a refusal — see
	# _on_confirmed. The engine closes this window itself; nothing a `pressed` handler does stops
	# it, which is how a refused part came to look exactly like a saved one.
	confirmed.connect(_on_confirmed)

	# Shipped catalog plus the custom props the builder has already defined — the dropdown must
	# offer every prop this motor's thrust_test could legitimately name, or a builder who entered a
	# custom prop for the express purpose of testing a custom motor against it would find it
	# missing from the list.
	_catalog = PartsCatalog.new()
	for cat in PartsCatalog.CATEGORY_FILES:
		_catalog._load_category(cat, PartsCatalog.CATEGORY_FILES[cat])
	_catalog._merge_custom(CustomParts.SAVE_PATH, CustomPropellers.load_from())

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)
	_add_row(grid, "Motor mass (g)", _configure(_mass, 0.0, 1000.0, 0.1))
	_add_row(grid, "Stator diameter (mm)", _configure(_stator_diameter, 0.0, 100.0, 0.5))
	_add_row(grid, "Stator height (mm)", _configure(_stator_height, 0.0, 50.0, 0.5))
	_add_row(grid, "KV (rpm per volt)", _configure(_kv, 0.0, 30000.0, 10.0))
	_add_row(grid, "Max thrust (g)", _configure(_max_thrust, 0.0, 20000.0, 1.0))
	_add_row(grid, "Max current (A)", _configure(_max_amps, 0.0, 200.0, 0.1))
	_add_row(grid, "Poles", _configure(_poles, 0.0, 36.0, 2.0))
	_mount.placeholder_text = MOUNT_HINT
	_add_row(grid, "Mount pattern", _mount)

	for prop in _catalog.list_category("propeller"):
		_prop_ids.append(str((prop as Dictionary)["part_id"]))
		_test_prop.add_item(str((prop as Dictionary).get("name", (prop as Dictionary)["part_id"])))
	_add_row(grid, "Thrust measured on", _test_prop)
	_add_row(grid, "…at voltage (V)", _configure(_test_voltage, 0.0, 60.0, 0.1))

	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	# Says out loud what the two fields above are for, because a builder who does not know why
	# they are mandatory will read them as bureaucracy and pick whatever is at the top of the list.
	var note := Label.new()
	note.text = "Thrust figures only mean something alongside the prop and voltage they were measured on — that pairing is what Lothal fits this motor's thrust from. Copy them off the heading of the manufacturer's table."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	root.add_child(note)

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


## Fills the form. Public because it is how a test drives the dialog and how "edit this one"
## would populate it later; there is no second path into these controls.
##
## An unknown prop id selects nothing and is passed through to the refusal, rather than being
## quietly replaced by the first prop in the list — a form that silently picks a different
## propeller than the one asked for would fit k_t off a prop the builder never mentioned.
func set_fields(part_name: String, mass_g: float, stator_diameter_mm: float,
		stator_height_mm: float, kv: float, max_thrust_g: float, max_amps: float, poles: int,
		mount_pattern: String, test_prop_id: String, test_voltage_v: float, source: String) -> void:
	_name.text = part_name
	_mass.value = mass_g
	_stator_diameter.value = stator_diameter_mm
	_stator_height.value = stator_height_mm
	_kv.value = kv
	_max_thrust.value = max_thrust_g
	_max_amps.value = max_amps
	_poles.value = poles
	_mount.text = mount_pattern
	var index := _prop_ids.find(test_prop_id)
	_test_prop.select(index)
	_unresolved_prop_id = "" if index >= 0 else test_prop_id
	_test_voltage.value = test_voltage_v
	_source.text = source


## The prop id the dropdown is on, or whatever was asked for and not found. Separate from
## set_fields so that submit() has one place to ask, and so an unresolvable id survives to be
## refused by name instead of being lost.
func _selected_prop_id() -> String:
	var index := _test_prop.selected
	if index < 0 or index >= _prop_ids.size():
		return _unresolved_prop_id
	return _prop_ids[index]


## Everything wrong with the last submit(), for a caller that wants it without re-submitting.
func problems() -> Array[String]:
	return _last_problems


## Builds the record, asks CustomMotors to accept it, and writes the file. Returns the refusals —
## empty means it was saved. The document is RELOADED rather than held, because the builder may
## have another Lothal window open or may have hand-edited the file, and holding a stale copy is
## how one of the two silently loses the other's part.
func submit() -> Array[String]:
	var document := CustomMotors.load_from()
	var record := CustomMotors.make_record(
		_name.text.strip_edges(), _mass.value, _stator_diameter.value, _stator_height.value,
		_kv.value, _max_thrust.value, _max_amps.value, int(_poles.value),
		_mount.text.strip_edges(), _selected_prop_id(), _test_voltage.value,
		_source.text.strip_edges())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	motor_saved.emit(str(record["part_id"]))
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
