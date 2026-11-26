class_name HarnessStraps
extends VBoxContainer
## The "Straps and sundries" block under the Harness tab's inspector: which battery strap holds the
## pack, how many (1 or 2), and the labelled estimate for solder, heat-shrink, tape and zip ties.
##
## It edits NOTHING. Like `HarnessInspector` it emits `value_edited(key, value)` and
## `default_restored(key)` and stops; `PowerWorkbench` applies the edit, records the undo step and
## hands this block back a state to render through `show_build`. Rendering a state never emits (the
## picker is `select`ed, the spin boxes `set_value_no_signal`), so opening the tab is not an edit.

signal value_edited(key: String, value: Variant)
signal default_restored(key: String)

var _strap_picker: OptionButton
var _count_spin: SpinBox
var _sundries_spin: SpinBox
var _strap_note: Label
var _sundries_note: Label
var _facts: Label
## Part id behind each picker item, index for index ("" is None).
var _strap_ids: Array[String] = []


func _init() -> void:
	name = "HarnessStraps"
	add_theme_constant_override("separation", LothalTheme.SPACE_1)

	var title := Label.new()
	title.text = "Straps and sundries"
	DsUi.title(title)
	add_child(title)

	_strap_picker = OptionButton.new()
	_strap_picker.name = "StrapPicker"
	_strap_picker.custom_minimum_size = Vector2(150, 0)
	_strap_picker.item_selected.connect(_on_strap_selected)
	add_child(_row("Strap", _strap_picker, Harness.STRAP))

	_count_spin = SpinBox.new()
	_count_spin.name = "StrapCount"
	_count_spin.min_value = Harness.STRAP_COUNT_MIN
	_count_spin.max_value = Harness.STRAP_COUNT_MAX
	_count_spin.step = 1.0
	_count_spin.custom_minimum_size = Vector2(96, 0)
	_count_spin.value_changed.connect(_on_count_changed)
	add_child(_row("Count", _count_spin, Harness.STRAP_COUNT))

	_strap_note = _note()

	_sundries_spin = SpinBox.new()
	_sundries_spin.name = "SundriesMass"
	_sundries_spin.min_value = 0.0
	_sundries_spin.max_value = Harness.SUNDRIES_MAX_G
	_sundries_spin.step = 0.1
	_sundries_spin.suffix = "g est."
	_sundries_spin.custom_minimum_size = Vector2(110, 0)
	_sundries_spin.value_changed.connect(_on_sundries_changed)
	add_child(_row("Solder, shrink, tape", _sundries_spin, Harness.SUNDRIES_G))

	_sundries_note = _note()

	_facts = Label.new()
	DsUi.quiet(_facts, LothalTheme.FONT_SIZE_BODY)
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.custom_minimum_size = Vector2(HarnessInspector.WRAP_WIDTH, 0)
	add_child(_facts)


func _row(caption_text: String, control: Control, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var caption := Label.new()
	caption.text = caption_text
	caption.custom_minimum_size = Vector2(56, 0)
	row.add_child(caption)
	row.add_child(control)
	var button := Button.new()
	button.text = "Default"
	button.flat = true
	button.name = "Default_" + key
	button.tooltip_text = "Forget what was chosen here and follow the parts again."
	button.pressed.connect(func() -> void: default_restored.emit(key))
	row.add_child(button)
	return row


func _note() -> Label:
	var label := Label.new()
	DsUi.quiet(label)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(HarnessInspector.WRAP_WIDTH, 0)
	add_child(label)
	return label


## Renders the harness as it stands. Never emits.
func show_build(build: Build) -> void:
	var harness := build.harness
	_strap_picker.clear()
	_strap_ids.clear()
	_strap_picker.add_item("None")
	_strap_ids.append("")
	var fitted := String(harness.value(Harness.STRAP, build))
	var selected := 0
	if build.catalog != null:
		for part in build.catalog.list_category("strap"):
			var id := String(part.get("part_id", ""))
			_strap_picker.add_item("%s  %.1f g" % [part.get("name", id), float(part.get("mass_g", 0.0))])
			_strap_ids.append(id)
			if id == fitted:
				selected = _strap_ids.size() - 1
	_strap_picker.select(selected)
	_count_spin.set_value_no_signal(harness.strap_count(build))
	_sundries_spin.set_value_no_signal(harness.sundries_mass_g(build))

	var defaults := Harness.defaults(build)
	var default_strap: Dictionary = build.catalog.get_part(String(defaults[Harness.STRAP])) \
		if build.catalog != null else {}
	_strap_note.text = ("authored — carried at the pack" if harness.straps_authored()
		else "from the parts (1 x %s), carried with the sundries at the aircraft's origin until "
			% String(default_strap.get("name", "no strap"))
			+ "you choose a strap")
	_sundries_note.text = ("authored estimate" if harness.has_override(Harness.SUNDRIES_G)
		else "estimate, from the parts (%.1f g)" % Harness.SUNDRIES_DEFAULT_G) \
		+ " — nobody publishes this; weigh yours"

	var row := harness.strap_row(build)
	var specs: Dictionary = row.get("specs", {})
	_facts.text = "Straps %.1f g%s. Sundries %.1f g, est.%s" % [
		harness.strap_mass_g(build),
		"" if row.is_empty() else " (%d x %.1f g, %.0f x %.0f mm)" % [harness.strap_count(build),
			float(row.get("mass_g", 0.0)), float(specs.get("width_mm", 0.0)), float(specs.get("length_mm", 0.0))],
		harness.sundries_mass_g(build),
		"" if row.is_empty() else "\nSource: %s" % String(row.get("source", ""))]


func _on_strap_selected(index: int) -> void:
	if index < 0 or index >= _strap_ids.size():
		return
	value_edited.emit(Harness.STRAP, _strap_ids[index])


func _on_count_changed(value: float) -> void:
	value_edited.emit(Harness.STRAP_COUNT, int(roundf(value)))


func _on_sundries_changed(value: float) -> void:
	value_edited.emit(Harness.SUNDRIES_G, value)
