class_name CustomBatteryDialog
extends AcceptDialog
## Lab's form for entering a pack Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not). Nothing in
## src/scenes/ constructs this, and Sim's build panel reads the merged catalog without any way to
## add to it.
##
## THE FORM IS THE PACK'S WRAPPER, IN THE ORDER THE WRAPPER PRINTS IT. Cells, chemistry, capacity,
## C-rating, then the mass and the three dimensions a builder takes with a scale and a ruler, then
## the connector. Every one of them is read off the pack or measured directly. Nothing here has to
## be worked out, which is the whole reason the two fields that WOULD have to be worked out are
## not on the form as questions.
##
## ---------------------------------------------------------------------------
## THE TWO DERIVED FIELDS
## ---------------------------------------------------------------------------
##
## `nominal_v` and `internal_r_ohm` are DERIVED by CustomBatteries, not asked for. Read that file's
## header for why — briefly: no manufacturer prints internal resistance, and a builder who types a
## nominal voltage is one keystroke away from entering 6 V for a 6S pack and having the physics
## absorb it silently.
##
## But derived is not the same as hidden. Both are SHOWN, live, as the builder types, and labelled
## as derived — a number the sim will fly on that the builder never sees is exactly the kind of
## thing that gets discovered three flights later. The resistance carries CustomBatteries' honesty
## caveat in the panel, because a derived resistance reproduces the shipped catalog's own
## assumption and proves nothing about a real pack, and presenting it as a measurement would be a
## lie the pack itself never told.
##
## The override field is for someone who has actually put a meter on the pack. Left at zero it
## means "no measurement" and the derivation stands — CustomBatteries.make_record takes NAN rather
## than 0.0 for that reason, so this dialog converts.
##
## The dialog builds NO record of its own. It collects values, hands them to
## CustomBatteries.make_record, and shows whatever CustomBatteries.add refuses.

signal battery_saved(part_id: String)

## Spelled as batteries.json spells them, because a custom pack lands in the shipped catalog's own
## filter buckets rather than in a bucket of one.
const CONNECTORS := ["BT2.0", "PH2.0", "XT30", "XT60"]

## Read off CustomBatteries rather than written again here — a chemistry this dialog offered that
## the model had no curve for would fall back to LiPo and mean something different in flight from
## what the record says.
var _chemistries: Array[String] = []

var _name := LineEdit.new()
var _cells := SpinBox.new()
var _chemistry := OptionButton.new()
var _mah := SpinBox.new()
var _c_rating := SpinBox.new()
var _mass := SpinBox.new()
var _length := SpinBox.new()
var _width := SpinBox.new()
var _height := SpinBox.new()
var _connector := OptionButton.new()
var _resistance_override := SpinBox.new()
var _source := LineEdit.new()
var _derived := Label.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom pack"
	ok_button_text = "Save pack"
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
	_add_row(grid, "Cells (S)", _configure(_cells, 1.0, 12.0, 1.0))

	for chemistry in CustomBatteries.NOMINAL_V_PER_CELL:
		_chemistries.append(str(chemistry))
		_chemistry.add_item(str(chemistry))
	_add_row(grid, "Chemistry", _chemistry)

	_add_row(grid, "Capacity (mAh)", _configure(_mah, 0.0, 30000.0, 10.0))
	_add_row(grid, "C-rating", _configure(_c_rating, 0.0, 300.0, 1.0))
	_add_row(grid, "Pack mass (g)", _configure(_mass, 0.0, 5000.0, 0.1))
	_add_row(grid, "Length (mm)", _configure(_length, 0.0, 400.0, 0.5))
	_add_row(grid, "Width (mm)", _configure(_width, 0.0, 200.0, 0.5))
	_add_row(grid, "Height (mm)", _configure(_height, 0.0, 200.0, 0.5))

	for connector in CONNECTORS:
		_connector.add_item(connector)
	_add_row(grid, "Connector", _connector)

	_resistance_override.tooltip_text = "Leave at 0 unless you have measured this pack with a meter."
	# Step 0.0001, not 0.001. A quad pack's internal resistance lives around 0.01 Ω, so a
	# milliohm step is a ~10% quantisation of the whole quantity — it would round a builder's
	# measured 0.0123 Ω to 0.012 and fly a pack they did not measure. Matches the %.4f the derived
	# panel prints, so the field and the readout cannot disagree about precision.
	_add_row(grid, "Measured resistance (Ω)", _configure(_resistance_override, 0.0, 1.0, 0.0001))

	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	# The two derived values, live. Everything that feeds them is a `value_changed` away, so the
	# panel is recomputed off every editor rather than only on submit — a builder who changes 4S to
	# 6S should see the nominal voltage move under their hand, which is also the fastest way to
	# notice they entered the wrong cell count.
	_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_derived.custom_minimum_size = Vector2(420, 0)
	root.add_child(_derived)

	for box in [_cells, _mah, _c_rating, _resistance_override]:
		(box as SpinBox).value_changed.connect(func(_v: float) -> void: _refresh_derived())
	_chemistry.item_selected.connect(func(_i: int) -> void: _refresh_derived())
	_refresh_derived()

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


func _selected_chemistry() -> String:
	var index := _chemistry.selected
	if index < 0 or index >= _chemistries.size():
		return ""
	return _chemistries[index]


## The override as make_record wants it: NAN for "no measurement", so a builder who left the field
## alone cannot be confused with one who measured a superconductor.
func _override_or_nan() -> float:
	return _resistance_override.value if _resistance_override.value > 0.0 else NAN


## The derived panel. Public in effect through derived_text() below, which is how a test reads it
## without a running scene tree.
func _refresh_derived() -> void:
	_derived.text = derived_text()
	# Amber only when the resistance is the derivation's rather than a measurement, because that is
	# precisely the case the caveat is about.
	var colour := LothalTheme.WARNING if is_nan(_override_or_nan()) else LothalTheme.TEXT_MUTED
	_derived.add_theme_color_override("font_color", colour)


## What the derived panel says, as a string. Separate from the Label so a test can assert the
## numbers and the caveat without instantiating a Control — the same reasoning
## PartPicker.display_name is static for.
func derived_text() -> String:
	var cells := int(_cells.value)
	var chemistry := _selected_chemistry()
	var nominal := CustomBatteries.nominal_v_for(cells, chemistry)

	var override := _override_or_nan()
	if not is_nan(override):
		return "Nominal %.1f V (derived from %d cells of %s). Resistance %.4f Ω — your measurement, used as given." % [
			nominal, cells, chemistry, override]

	var resistance := CustomBatteries.derived_internal_r_ohm_for(
		cells, chemistry, _mah.value, _c_rating.value)
	if resistance <= 0.0:
		return "Nominal %.1f V (derived from %d cells of %s). Resistance needs capacity and C-rating before it can be derived." % [
			nominal, cells, chemistry]

	return "Nominal %.1f V (derived from %d cells of %s). Resistance %.4f Ω — DERIVED from capacity and C-rating, not measured. It is fitted against a catalog whose own figures are mostly representative rather than measured, so treat it as a stated assumption, not a fact about your pack. Measure it and enter it above if you can." % [
		nominal, cells, chemistry, resistance]


## Fills the form. Public because it is how a test drives the dialog and how "edit this one" would
## populate it later; there is no second path into these controls.
##
## An unknown chemistry or connector selects nothing and is passed through to the refusal, rather
## than being quietly replaced by the first in the list — a form that silently picked LiPo for a
## pack the builder called Li-ion would fly a different discharge curve than the one asked for.
func set_fields(part_name: String, cells: int, chemistry: String, mah: float, c_rating: float,
		mass_g: float, length_mm: float, width_mm: float, height_mm: float, connector: String,
		source: String, internal_r_ohm_override: float = NAN) -> void:
	_name.text = part_name
	_cells.value = cells
	_chemistry.select(_chemistries.find(chemistry))
	_mah.value = mah
	_c_rating.value = c_rating
	_mass.value = mass_g
	_length.value = length_mm
	_width.value = width_mm
	_height.value = height_mm
	_connector.select(CONNECTORS.find(connector))
	_source.text = source
	_resistance_override.value = 0.0 if is_nan(internal_r_ohm_override) else internal_r_ohm_override
	_refresh_derived()


func problems() -> Array[String]:
	return _last_problems


## Builds the record, asks CustomBatteries to accept it, and writes the file. Returns the refusals
## — empty means it was saved. The document is RELOADED rather than held, because the builder may
## have another Lothal window open or may have hand-edited the file, and holding a stale copy is
## how one of the two silently loses the other's part.
func submit() -> Array[String]:
	var document := CustomBatteries.load_from()
	var connector_index := _connector.selected
	var connector: String = CONNECTORS[connector_index] if connector_index >= 0 else ""
	var record := CustomBatteries.make_record(
		_name.text.strip_edges(), int(_cells.value), _selected_chemistry(), _mah.value,
		_c_rating.value, _mass.value, _length.value, _width.value, _height.value,
		connector, _source.text.strip_edges(), _override_or_nan())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	battery_saved.emit(str(record["part_id"]))
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
