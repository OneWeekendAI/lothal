class_name CustomGuardDialog
extends AcceptDialog
## The Design Space's form for a prop guard the catalog does not stock (plan item 7).
##
## The fields are what `PropGuard.compute` consumes and nothing else: kind, the gap to the blade tip,
## wall, height, material density, and the mount radius (arm length for a per-motor ring, 0 for a
## cage round the whole aircraft). Mass is NOT a field: it is the ring's own geometry integral, shown
## under the form so a builder sees what the ring will weigh before saving. The outer radius is not a
## field either: it is the prop's tip radius plus the gap plus the wall, because on any aircraft the
## ring is resized to the prop it wraps (PropGuard.fitted_guard).
##
## VALIDATED AGAINST THE PROP ON THE BENCH. `bench` is the drone the form was opened over; its prop's
## tip radius and tip chord feed `PropGuard.clearance_check` — the one clearance check, not a copy.
## Refused: a clearance that is not positive, a ring the physics cannot read, a duct with no stated
## gap, and a `kind` that the geometry contradicts (a ring whose gap is more than a tip chord is not
## a duct, and one inside a chord is not a bumper — `clearance_check` says which, this form refuses
## and names the other kind rather than silently relabelling).
##
## Refusals keep the dialog open (AcceptDialog hides on OK before any handler: `_on_confirmed` re-shows).

signal guard_saved(part_id: String)

const KINDS := [PropGuard.KIND_BUMPER, PropGuard.KIND_DUCT]
## Labelled starting numbers for the SpinBoxes, a class-typical ABS ring (guards.json's 5" bumper).
const DEFAULT_WALL_MM := 3.0
const DEFAULT_HEIGHT_MM := 12.0
const DEFAULT_DENSITY := 1050.0

var bench: Build

var _name := LineEdit.new()
var _kind := OptionButton.new()
var _gap := LineEdit.new()
var _wall := SpinBox.new()
var _height := SpinBox.new()
var _density := SpinBox.new()
var _mount := SpinBox.new()
var _material := LineEdit.new()
var _source := LineEdit.new()
var _preview := Label.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init(p_bench: Build = null) -> void:
	bench = p_bench
	title = "New custom prop guard"
	ok_button_text = "Save guard"
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)
	for k in KINDS:
		_kind.add_item(String(k))
	_kind.select(0)
	_kind.tooltip_text = "A bumper claims mass, inertia and clearance only; a duct (shroud) also suppresses tip loss."
	_add_row(grid, "Kind", _kind)
	_gap.placeholder_text = "%.1f if left empty (assumed)" % PropGuard.DEFAULT_TIP_GAP_MM
	_gap.tooltip_text = "Radial gap from the blade tip to the ring's inner wall. A duct must state it; a bumper may leave it empty."
	_add_row(grid, "Tip gap (mm)", _gap)
	_add_row(grid, "Wall (mm)", _configure(_wall, 0.0, 30.0, 0.1, DEFAULT_WALL_MM))
	_add_row(grid, "Height (mm)", _configure(_height, 0.0, 100.0, 0.5, DEFAULT_HEIGHT_MM))
	_add_row(grid, "Density (kg/m³)", _configure(_density, 0.0, 3000.0, 10.0, DEFAULT_DENSITY))
	var arm := 0.0
	if bench != null and not bench.frame.is_empty():
		arm = float((bench.frame.get("specs", {}) as Dictionary).get("arm_mm", 0.0))
	_mount.tooltip_text = "Distance from the roll axis to each ring's centre: the arm length for one ring per motor, 0 for a cage round the whole aircraft."
	_add_row(grid, "Mount radius (mm)", _configure(_mount, 0.0, 400.0, 0.5, arm))
	_material.placeholder_text = "e.g. ABS, TPU"
	_add_row(grid, "Material", _material)
	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(420, 0)
	root.add_child(_preview)
	for box in [_wall, _height, _density, _mount]:
		(box as SpinBox).value_changed.connect(func(_v: float): _preview.text = preview_text())
	_gap.text_changed.connect(func(_t: String): _preview.text = preview_text())
	_preview.text = preview_text()
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(420, 0)
	DsUi.warn(_problems)
	_problems.add_theme_color_override("font_color", LothalTheme.WARNING)
	_problems.visible = false
	root.add_child(_problems)


static func _configure(box: SpinBox, minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.value = value
	box.custom_minimum_size = Vector2(140, 0)
	return box


func _add_row(grid: GridContainer, label_text: String, editor: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(editor)


## Fills the form (tests, and a future edit). `gap_mm` NAN leaves the gap empty.
func set_fields(part_name: String, kind: String, gap_mm: float, wall_mm: float, height_mm: float,
		density: float, mount_mm: float, material: String, source: String) -> void:
	_name.text = part_name
	_kind.select(maxi(KINDS.find(kind), 0))
	_gap.text = "" if is_nan(gap_mm) else str(gap_mm)
	_wall.value = wall_mm
	_height.value = height_mm
	_density.value = density
	_mount.value = mount_mm
	_material.text = material
	_source.text = source


func problems() -> Array[String]:
	return _last_problems


## The prop on the bench: its tip radius (the figure `Build` sizes the ring by), its tip chord, and
## its class word as guards.json spells it.
func _prop_tip_mm() -> float:
	if bench == null or bench.propeller.is_empty():
		return 0.0
	return float((bench.propeller.get("specs", {}) as Dictionary).get("diameter_inches", 0.0)) * Build.INCH_M * 500.0


func _prop_class() -> String:
	var d := float((bench.propeller.get("specs", {}) as Dictionary).get("diameter_inches", 0.0)) if bench != null and not bench.propeller.is_empty() else 0.0
	return "%s\"" % ("%.1f" % d).trim_suffix(".0")


## The ring as entered, sized to the bench prop. `form_problems` gets what the form itself refuses.
func spec_from_form(form_problems: Array[String]) -> Dictionary:
	var gap := NAN
	var gap_text := _gap.text.strip_edges()
	if gap_text != "":
		if gap_text.is_valid_float():
			gap = gap_text.to_float()
		else:
			form_problems.append("tip gap \"%s\" is not a number of millimetres" % gap_text)
	var wall := _wall.value
	var tip := _prop_tip_mm()
	var ring_gap := gap if not is_nan(gap) else PropGuard.DEFAULT_TIP_GAP_MM
	return CustomGuards.make_specs(String(KINDS[_kind.selected]), tip + ring_gap + wall, wall,
		_height.value, _density.value, _mount.value, gap)


## What the form's ring would weigh, and where it clears the prop, for the line under the form.
func preview_text() -> String:
	var ignored: Array[String] = []
	var specs := spec_from_form(ignored)
	var g := PropGuard.mass_kg(specs) * 1000.0
	if g <= 0.0:
		return "The ring cannot be read yet: check the wall, height and density."
	return "Each ring weighs %.2f g (%.2f g for the four)." % [g, g * 4.0]


func submit() -> Array[String]:
	var form_problems: Array[String] = []
	var specs := spec_from_form(form_problems)
	var name_text := _name.text.strip_edges()

	# Clearance against the prop on the bench, by the physics' own check.
	var tip := _prop_tip_mm()
	if tip <= 0.0:
		form_problems.append("there is no propeller on the bench to measure the ring against")
	elif String(PropGuard.compute(specs).get("tier", "")) == "computed":
		var doc := PropellerDetails.document_for(bench.propeller)
		var chord := doc.chord_at(1.0) if doc != null else 0.0
		var check := PropGuard.clearance_check(specs, tip, chord)
		var clearance := float(check["clearance_mm"])
		if is_nan(clearance) or clearance <= 0.0:
			form_problems.append("clearance to the prop must be greater than 0 mm (it is %.2f mm): the ring passes through the blade tips" % clearance)
		elif bool(check["kind_disagrees"]):
			form_problems.append("a %s's gap is the other side of a tip chord: this ring's %.2f mm gap is %.2f tip chords, which makes it a %s. Pick \"%s\", or change the gap" % [
				String(check["declared_kind"]), clearance, float(check["gap_ratio"]),
				String(check["geometric_kind"]), String(check["geometric_kind"])])

	var record := CustomGuards.make_record(name_text, specs, _prop_class(), _material.text.strip_edges(),
		_source.text.strip_edges())
	var document := CustomGuards.load_from()
	_last_problems = form_problems
	# Asked even when the form already refused, so every problem shows at once; add() holds the
	# record in memory only, nothing is written unless both lists are empty.
	_last_problems.append_array(document.add(record))
	_preview.text = preview_text()

	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	guard_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems


func _on_confirmed() -> void:
	if not submit().is_empty():
		show()
