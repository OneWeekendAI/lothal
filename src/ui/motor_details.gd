class_name MotorDetails
extends PartDetails
## The motor panel. All the machinery is PartDetails' — read its header.
##
## The row worth explaining is "Thrust measured on". A motor's headline thrust figure is
## meaningless without the propeller and pack it was measured with, and Build fits the thrust
## coefficient from exactly that pairing (physics.md §4). Showing it puts the provenance of the
## number on screen next to the number, which is the difference between a spec sheet and a
## claim. It is also the row that makes an over-propped build legible: when the max thrust says
## 1450 g and the pairing says a 5x4.3 on 4S, a 7" prop fitted to it is visibly not the test
## condition.
##
## ## THE TWO BUTTONS AT THE BOTTOM — P10f
##
## **The thrust stand opens from here**, and that is the whole of P10f's navigation change. It used
## to be the first entry in the Rooms menu, which put a machine that tests a motor-and-propeller
## pairing in a list of destinations next to the field editor. `room_menu.gd`'s own header states
## the arrangement it was a holding position for: *a bench belongs to the system it tests*, reached
## from that system's inspector. This panel is that inspector, the pairing is what the two rows
## above ("Max thrust", "Thrust measured on") are about, and the bench is where that pairing is put
## under load. The Prop panel's "Design this blade…" already established the pattern.
##
## The button says what happened; the shell decides what to do about it. This panel opens nothing,
## on the rule every control in this UI follows, and the room lifecycle stays `RoomHost`'s — the
## bench is the same `BenchScreen` the menu used to construct, opened the same way, retracting the
## same chrome.
##
## **And the mount stack exports as STL**, because the stack drawn under the propeller is the one
## piece of geometry a builder needs OUTSIDE this app: to check a camera clears the bell, or that
## the frame they are drawing has room for the pad. It is not a printed part and the export does
## not pretend it is — `PropulsionExport` says so in its own header. The guard, which IS printed,
## exports from the Prop panel's guard row, because a guard wraps the disc rather than the motor.

## Emitted when the builder asks for the thrust stand. The shell opens it.
signal thrust_bench_requested()

## Emitted with the motor record when the builder asks for the mount stack as an STL. The shell
## owns the file dialog, for the same reason it owns the room: a details panel that opened a save
## dialog would be a panel that knows where this app puts files.
signal mount_stl_requested(motor: Dictionary)

## THE SOFT MOUNT'S PICKER — slice SM3's persistence half, on the guard's pattern exactly
## (`PropellerDetails.guard_changed`). The selector lives on THIS panel rather than the Prop's for
## the geometric reason the guard lives on the Prop's: the grommets sit under the motor, between
## its boss and the arm, and every number they produce (`SoftMount`'s f_n) hangs off the mass this
## panel's rows describe.
##
## `Build.mount_id` has been reachable from `Build.from_ids` since SM2 and from nowhere else — the
## state P10b's guard was in before P10f gave it a dropdown. "Not fitted" is the first row and the
## default, so the reference build's oracles stay bit-identical while nothing is picked, and an
## old project file (which has never heard of a mount) reopens as the aircraft it was saved as.
signal mount_changed(mount_id: String)

const SPEC_ROWS := [
	{"key": "stator_class", "label": "Stator class"},
	{"key": "kv_class", "label": "KV class"},
	{"key": "intended_use", "label": "Intended for"},
	{"key": "mass_g", "label": "Motor mass"},
	{"key": "kv", "label": "KV"},
	{"key": "stator", "label": "Stator (Ø × height)"},
	{"key": "max_thrust_g", "label": "Max thrust (each)"},
	{"key": "max_amps", "label": "Max current"},
	{"key": "poles", "label": "Poles"},
	{"key": "mount_pattern", "label": "Mount"},
	{"key": "thrust_test", "label": "Thrust measured on"},
]

var _catalog: PartsCatalog
var _mount_selector: OptionButton
## Selector index -> mount part id, "" first — an index into THIS and never into
## `catalog.list_category("mount")`, which lacks the "Not fitted" row (the guard row's off-by-one).
var _mount_ids: Array = [""]
## The mount's sheet (SM3): hardness, area, count, f_n and the damping band, one label each.
var _mount_grid: GridContainer
var _mount_values: Dictionary = {}
var _bench_button: Button
var _stl_button: Button
## The build the panel last rendered against, for the f_n row — the pad's thickness is the Lab's
## tweak on THAT build, not a property of the part.
var _mount_build: Build
var _dock_sheet := ""

## The mount sheet's rows. Every one is read through `mount_row_text`, a pure function, so the sheet
## and its test share one answer.
const MOUNT_ROWS := [
	{"key": "hardness", "label": "Hardness"},
	{"key": "area", "label": "Contact area"},
	{"key": "count", "label": "Grommets"},
	{"key": "f_n", "label": "Mount frequency"},
	{"key": "damping", "label": "Damping"},
]

## What the mount row's empty selection reads as, on `PropellerDetails.NOT_FITTED`'s argument.
const NOT_FITTED := "Not fitted"

## The catalog is held so the thrust_test row can name the propeller rather than its part_id —
## "5x4.3x3 at 14.8 V" is provenance a builder can read; "prop_5x43x3" is a database key.
func _init(p_catalog: PartsCatalog) -> void:
	_catalog = p_catalog
	super(SPEC_ROWS)

## The bench door and the stack export, under the spec rows and above PartDetails' own footer —
## the same placement, and the same argument, as the Prop panel's "Design this blade…": the button
## sits directly under the rows that motivate pressing it.
func _build_footer(root: VBoxContainer) -> void:
	var bench_button := Button.new()
	_bench_button = bench_button
	bench_button.text = "Open thrust bench…"
	bench_button.tooltip_text = ("Run this motor and propeller up under load: thrust, current and "
		+ "the RPM they actually reach, against the pairing the row above was measured on.")
	bench_button.pressed.connect(func() -> void: thrust_bench_requested.emit())
	root.add_child(bench_button)

	var stl_button := Button.new()
	_stl_button = stl_button
	stl_button.text = "Export mount stack (STL)…"
	stl_button.tooltip_text = ("The motor, its soft-mount pad, the adapter and the shaft as a "
		+ "solid, in millimetres — for checking fit in someone else's CAD, not for printing.")
	stl_button.pressed.connect(func() -> void: mount_stl_requested.emit(_rendered_part))
	root.add_child(stl_button)

	_build_mount_row(root)

	super(root)


## The mount selector. Clipped and not sized to its longest entry, for the guard selector's reason:
## a long part name would otherwise set the sheet column's width.
func _build_mount_row(root: VBoxContainer) -> void:
	_mount_selector = OptionButton.new()
	_mount_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mount_selector.clip_text = true
	_mount_selector.fit_to_longest_item = false
	_mount_selector.custom_minimum_size = Vector2(280, 0)
	_mount_selector.add_item(NOT_FITTED)
	_mount_ids = [""]
	for mount in _catalog.list_category("mount"):
		_mount_selector.add_item(PartPicker.display_name(mount))
		_mount_ids.append(str(mount["part_id"]))
	_mount_selector.select(0)
	_mount_selector.item_selected.connect(_on_mount_selected)
	root.add_child(_mount_selector)

	_mount_grid = GridContainer.new()
	_mount_grid.columns = 2
	root.add_child(_mount_grid)
	for row in MOUNT_ROWS:
		_mount_values[row["key"]] = _add_row(_mount_grid, row["label"])


func _on_mount_selected(index: int) -> void:
	mount_changed.emit(String(_mount_ids[index]))


## The fitted mount, "" for none. What LabScreen reads to assemble a Build and what the project
## file records.
func mount_id() -> String:
	if _mount_selector == null:
		return ""
	return String(_mount_ids[_mount_selector.selected])


## Fits a mount by id, as opening a saved drone does. Returns whether the id was one this catalog
## knows; an unknown one leaves the row where it was, to be reported (`LabScreen.apply_selection`).
func select_mount(p_mount_id: String) -> bool:
	if _mount_selector == null:
		return p_mount_id == ""
	var index := _mount_ids.find(p_mount_id)
	if index < 0:
		return false
	_mount_selector.select(index)
	return true


func render(part: Dictionary, build: Build) -> void:
	super(part, build)
	_mount_build = build
	_render_mount()
	_apply_dock_sheet()


## The fitted mount's catalog record, `{}` for none.
func fitted_mount() -> Dictionary:
	return _catalog.get_part(mount_id()) if mount_id() != "" else {}


func _render_mount() -> void:
	if _mount_grid == null:
		return
	var mount := fitted_mount()
	for row in MOUNT_ROWS:
		(_mount_values[row["key"]] as Label).text = mount_row_text(row["key"], mount, _mount_build)


## One mount-sheet row, from the part and the build. Static and pure so the test reads the rule.
##
## **A FIELD THE CATALOG GUESSED SAYS SO, ON THE NUMBER** (the blade rows' rule, `PropellerDetails`):
## every value whose field is in the entry's `assumed` list carries "(assumed)", and the frequency
## built from any assumed field carries its `~`. The damping band is ALWAYS assumed: no grommet
## vendor publishes a damping ratio, and `SoftMount.DAMPING_RATIO_LOW`/`HIGH` are the range the
## vibration overlay draws, not a reading. With nothing fitted the material rows are a dash — the
## class-typical default is not a part the builder chose, and naming its Shore value here would
## read as one.
static func mount_row_text(key: String, mount: Dictionary, build: Build) -> String:
	var specs: Dictionary = mount.get("specs", {})
	var assumed: Array = mount.get("assumed", [])
	match key:
		"hardness":
			if not specs.has("shore_a"):
				return "—"
			return _assumed("Shore %dA" % roundi(float(specs["shore_a"])), assumed, "shore_a")
		"area":
			if not specs.has("contact_area_mm2"):
				return "—"
			return _assumed("%.1f mm² each" % float(specs["contact_area_mm2"]), assumed,
				"contact_area_mm2")
		"count":
			if not specs.has("grommets_per_motor"):
				return "—"
			return _assumed("%d per motor" % int(specs["grommets_per_motor"]), assumed,
				"grommets_per_motor")
		"f_n":
			if build == null:
				return "—"
			var model := VibrationModel.for_build(build)
			var tier := model.mount_tier()
			if tier == "no_mount":
				return "no pad"
			if tier.begins_with("insufficient_data:"):
				return "not read (%s)" % tier.trim_prefix("insufficient_data:")
			# Any guessed input makes the frequency a guess: the `~` the house uses for one.
			var guessed := mount.is_empty() or not assumed.is_empty()
			return "%s%d Hz" % ["~" if guessed else "", roundi(model.mount_hz())]
		"damping":
			if mount.is_empty():
				return "—"
			if specs.has("damping_ratio"):
				return "ζ %.2f" % float(specs["damping_ratio"])
			return "ζ %.2f–%.2f (assumed)" % [SoftMount.DAMPING_RATIO_LOW, SoftMount.DAMPING_RATIO_HIGH]
	return "—"


static func _assumed(text: String, assumed: Array, field: String) -> String:
	return text + " (assumed)" if assumed.has(field) else text


## Rendered mount rows, label and value, for tests.
func mount_rendered_text() -> String:
	var lines: Array[String] = []
	for row in MOUNT_ROWS:
		lines.append("%s: %s" % [row["label"], (_mount_values[row["key"]] as Label).text])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Half a panel on a Lab dock page — PropellerDetails.set_dock_sheet's pattern
# ---------------------------------------------------------------------------

## "motor" (the Motors page: the spec rows and the two doors, no mount), "mount" (the Soft mounts
## page: the selector and its sheet alone), or "" for the whole panel, as the old shell and Sim's
## build panel show it. Calm by subtraction: each page shows only its own item.
func set_dock_sheet(sheet: String) -> void:
	_dock_sheet = sheet
	_apply_dock_sheet()


func _apply_dock_sheet() -> void:
	if _mount_grid == null:
		return
	var motor := _dock_sheet != "mount"
	var mount := _dock_sheet != "motor"
	_specs_grid.visible = motor
	_bench_button.visible = motor
	_stl_button.visible = motor
	_mount_selector.visible = mount
	_mount_grid.visible = mount
	if _dock_sheet == "mount":
		_title.text = "SOFT MOUNT"


## Which blocks are showing, for tests: `{rows, bench, mount}`.
func sheet_parts() -> Dictionary:
	return {"rows": _specs_grid.visible, "bench": _bench_button.visible,
		"mount": _mount_selector.visible and _mount_grid.visible}


func _read(motor: Dictionary, key: String) -> String:
	var specs: Dictionary = motor.get("specs", {})

	match key:
		"mass_g":
			return "%.0f g" % float(motor.get("mass_g", 0.0))
		"kv":
			return "%.0f KV" % float(specs.get("kv", 0.0))
		"stator":
			return "%.0f × %.0f mm" % [
				float(specs.get("stator_diameter_mm", 0.0)), float(specs.get("stator_height_mm", 0.0))]
		"max_thrust_g":
			return "%.0f g" % float(specs.get("max_thrust_g", 0.0))
		"max_amps":
			return "%.0f A" % float(specs.get("max_amps", 0.0))
		"poles":
			return "%.0f" % float(specs.get("poles", 0.0))
		"mount_pattern":
			return _or_dash(str(motor.get("mount_pattern", "")))
		"thrust_test":
			var test: Dictionary = motor.get("thrust_test", {})
			var prop: Dictionary = _catalog.get_part(str(test.get("prop_id", "")))
			if prop.is_empty():
				return "—"
			return "%s at %.1f V" % [prop.get("name", "?"), float(test.get("voltage_v", 0.0))]
	return super(motor, key)
