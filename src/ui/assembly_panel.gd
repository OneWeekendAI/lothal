class_name AssemblyPanel
extends PanelContainer
## The fit adjustments: a mount dropdown, four sliders and a reset, over the AssemblyTweaks the
## builder's configuration lives in.
##
## This panel owns no dimensions and no ranges. Every slider's minimum, maximum and default come
## from AssemblyTweaks.limits() for the CURRENT build, which derives them from the parts on screen
## — so choosing a smaller motor narrows the shim slider while you watch, and a slider can never
## offer a shim the motor has no thread for. A panel with its own numbers in it would be a second
## opinion about what the hardware allows, and the whole point of deriving the limits is that there
## is only one.
##
## Each row also shows what the value IS in millimetres, because a slider position is not a
## dimension and a builder thinks in millimetres. The rows are described by AssemblyTweaks.ROWS
## rather than here, so this file has no opinion about what a tweak means.

## Slider granularity. Real shim washers come in half-millimetres and standoffs in whole ones, so a
## tenth of a millimetre is finer than anything you could actually fit — which is deliberate: the
## range is what has to be honest, and rounding the builder's intent up to the nearest available
## washer is a decision for the build sheet, not for the input.
const STEP_MM := 0.1

## The three fit measurements, all taken off the assembled geometry rather than off the catalog.
## Fore/aft overhang is reported and never warned about — a 75 mm pack on a 60 mm plate is what
## every real 5" build looks like — while being wider than the plate, or reaching the props, is.
const FIT_ROWS := [
	{"key": "fore_aft", "label": "Overhang, fore/aft"},
	{"key": "lateral", "label": "Overhang, each side"},
	{"key": "prop_clearance", "label": "Clearance to props"},
]

signal tweaks_changed

var tweaks: AssemblyTweaks

var _mount_buttons: Dictionary = {}   # CHOICE_ROWS key -> OptionButton
## key -> Array[String] of the mount ids currently in that dropdown, in the order they were added.
## Held because an OptionButton stores an index and the configuration stores a NAME, and the map
## between the two changes with the frame.
var _mount_ids: Dictionary = {}
var _sliders: Dictionary = {}   # key -> HSlider
var _values: Dictionary = {}    # key -> Label
var _fit_values: Dictionary = {}   # FIT_ROWS key -> Label
var _fit_warning_label: Label
## Set while the panel is writing its own controls from the model, so that programmatic slider
## moves do not read back as the builder having dragged something.
var _updating := false

func _init(p_tweaks: AssemblyTweaks) -> void:
	tweaks = p_tweaks

	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# It scrolls, and for the same reason Lab's pack tab does: this panel now carries a mount
	# dropdown, four sliders with their hints, three fit rows and a warning block, which on a
	# laptop-height window puts the warning below the bottom of the screen — and the warning is the
	# one thing on here nobody can afford to miss. Vertical only: a details column that scrolls
	# sideways has a layout bug rather than a scrollbar.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "FIT"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = "Mounts, shims and standoffs. Changes the fit, not the flight numbers."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	for row in AssemblyTweaks.CHOICE_ROWS:
		_add_mount_row(root, row)

	for row in AssemblyTweaks.ROWS:
		_add_row(root, row)

	root.add_child(HSeparator.new())

	# What the pack actually does on this frame. It sits with the sliders rather than in the Pack
	# panel deliberately: the Pack panel describes the part, and this describes the FIT — the same
	# distinction that put shims here instead of in the catalog. It is read-only, because where the
	# pack sits is not one of the three tweaks (that is its own decision, not a fourth slider).
	var fit_title := Label.new()
	fit_title.text = "PACK ON THE PLATE"
	fit_title.theme_type_variation = &"TitleLabel"
	root.add_child(fit_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	for row in FIT_ROWS:
		var label := Label.new()
		label.text = row["label"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		_fit_values[row["key"]] = value

	# Same amber as the part panels' warnings, because it is the same kind of statement: warn,
	# never block.
	_fit_warning_label = Label.new()
	_fit_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fit_warning_label.custom_minimum_size = Vector2(280, 0)
	_fit_warning_label.theme_type_variation = &"WarnLabel"
	# Exception: Warning label explicit amber color override
	_fit_warning_label.add_theme_color_override("font_color", LothalTheme.WARNING)
	root.add_child(_fit_warning_label)

	root.add_child(HSeparator.new())

	var reset_button := Button.new()
	reset_button.text = "Reset to as-built"
	reset_button.pressed.connect(reset)
	root.add_child(reset_button)


## Same inset as PartDetails, for the same reason: right-aligned values flush against the window
## edge read as clipped text even when nothing is cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	# Exception: Programmatic margin container insets using spacing scale
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	parent.add_child(margin)
	return margin


## A dropdown rather than a slider, because where a pack is strapped is a choice between named
## places and not a dimension. Its ENTRIES are filled in by render() from the frame that is fitted,
## never here — a panel holding its own list of mounts would be exactly the second opinion about
## what the hardware allows that deriving the limits exists to prevent.
func _add_mount_row(parent: VBoxContainer, row: Dictionary) -> void:
	var key: String = row["key"]

	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = row["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	parent.add_child(header)

	var button := OptionButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.item_selected.connect(func(index: int) -> void: _on_mount_selected(key, index))
	parent.add_child(button)
	_mount_buttons[key] = button
	_mount_ids[key] = ([] as Array[String])

	var hint := Label.new()
	hint.text = row["hint"]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.theme_type_variation = &"MutedLabel"
	parent.add_child(hint)


func _add_row(parent: VBoxContainer, row: Dictionary) -> void:
	var key: String = row["key"]

	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = row["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value)
	_values[key] = value
	parent.add_child(header)

	var slider := HSlider.new()
	slider.step = STEP_MM
	slider.value_changed.connect(func(v: float) -> void: _on_slider_moved(key, v))
	parent.add_child(slider)
	_sliders[key] = slider

	var hint := Label.new()
	hint.text = row["hint"]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.theme_type_variation = &"MutedLabel"
	parent.add_child(hint)


## Re-reads the limits for `build` and shows the values in force. Called on every selection change
## as well as after a tweak, because a part change moves the limits — and a slider still sitting at
## a range the current motor does not have is exactly the disagreement between panel and geometry
## this screen is built to make impossible.
## `airframe` is the assembled aircraft the fit rows are measured off. It is passed in rather than
## reached for, and it is the AIRFRAME rather than the Build, because these three numbers are
## properties of the assembled geometry and not of the parts list — the same reason
## AirframeModel.adjacent_prop_gap_m() lives on the airframe and Build.warnings() does not. Null
## leaves the rows blank, which is what a panel rendered before anything has been assembled should
## show.
func render(build: Build, airframe: AirframeModel = null) -> void:
	_render_fit(airframe)

	_updating = true
	for row in AssemblyTweaks.CHOICE_ROWS:
		var choice_key: String = row["key"]
		var choices: Dictionary = AssemblyTweaks.mount_choices(build)[choice_key]
		var button: OptionButton = _mount_buttons[choice_key]
		var ids: Array[String] = []
		button.clear()
		for i in (choices["options"] as Array).size():
			ids.append(String(choices["options"][i]))
			button.add_item(String(choices["labels"][i]))
		_mount_ids[choice_key] = ids
		var in_force := tweaks.value_choice(choice_key, build)
		if ids.has(in_force):
			button.selected = ids.find(in_force)

	for row in AssemblyTweaks.ROWS:
		var key: String = row["key"]
		var limits: Dictionary = AssemblyTweaks.limits(build)[key]
		var slider: HSlider = _sliders[key]
		slider.min_value = limits["min"]
		slider.max_value = limits["max"]
		var current := tweaks.value_mm(key, build)
		slider.value = current
		var suffix := ""
		if not tweaks.has_override(key):
			suffix = "  (as built)"
		_values[key].text = "%.1f mm%s" % [current, suffix]
	_updating = false


## The three fit rows and any warning, straight from the airframe's own measurements. Signed and
## labelled in words rather than as a bare number: "+18 mm over" and "-28 mm clear" are the same
## measurement, and which of the two you are looking at is the whole point.
func _render_fit(airframe: AirframeModel) -> void:
	if airframe == null or airframe.battery_mesh == null:
		for key in _fit_values:
			_fit_values[key].text = "—"
		_fit_warning_label.visible = false
		return

	var overhang := airframe.battery_overhang_m()
	for key in ["fore_aft", "lateral"]:
		_fit_values[key].text = _signed_mm(overhang[key], "over", "clear")
	_fit_values["prop_clearance"].text = _signed_mm(
		-airframe.battery_prop_clearance_m(), "into disc", "clear")

	# Both lists: what the MOUNT SYSTEM says about how each component attaches, and what the
	# assembled geometry says about where it ended up. They are separate checks for the same reason
	# Build.warnings() is separate from both — one is what the parts declare, the other is what they
	# do when placed — and one amber block is where a builder looks for either.
	var warnings := airframe.mount_warnings()
	warnings.append_array(airframe.battery_fit_warnings())
	_fit_warning_label.text = "\n".join(warnings)
	_fit_warning_label.visible = not warnings.is_empty()


## What one fit row currently reads, and what the warning currently says. Named accessors rather
## than tests reaching into _fit_values, so the panel's internals stay its own.
func fit_row_text(key: String) -> String:
	return (_fit_values[key] as Label).text if _fit_values.has(key) else ""


func fit_warning_text() -> String:
	return _fit_warning_label.text if _fit_warning_label.visible else ""


static func _signed_mm(metres: float, over_word: String, clear_word: String) -> String:
	if metres > 0.0:
		return "%.0f mm %s" % [metres * 1000.0, over_word]
	return "%.0f mm %s" % [-metres * 1000.0, clear_word]


## Sets one row, and returns the value that actually landed: the asked-for value snapped to STEP_MM
## and held inside the slider's derived range, which is not necessarily what was asked for.
##
## THIS is the single path a change takes. The slider's own value_changed hands straight through to
## it rather than writing the model itself, deliberately — Godot's Range does not emit that signal
## for a value set from code (verified on 4.7.1), so a panel whose model was only ever updated from
## inside the signal would work under the mouse and do nothing when driven any other way, including
## from a test. One function, and the mouse is just one of its callers.
func set_tweak_mm(key: String, millimetres: float) -> float:
	var slider: HSlider = _sliders[key]
	var applied := clampf(snappedf(millimetres, STEP_MM), slider.min_value, slider.max_value)

	_updating = true
	slider.value = applied
	_updating = false

	tweaks.set_mm(key, applied)
	tweaks_changed.emit()
	return applied


## The mount ids currently in one dropdown, in order. Named accessor rather than tests reaching
## into the OptionButton, for the reason fit_row_text exists: the panel's internals stay its own.
func mount_options(key: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_mount_ids.get(key, []))
	return out


## Sets one mount, and it is the single path a mount change takes — the dropdown's own
## item_selected hands straight through to it rather than writing the model itself. Same reasoning
## as set_tweak_mm: a panel whose model was only updated from inside a signal works under the mouse
## and does nothing when driven any other way, including from a test.
##
## A mount id this frame does not offer is recorded anyway rather than rejected. That is the
## unclamped-storage rule the shims already follow: a pack mounted underneath has to still be
## underneath when you come back from trying the build on a toothpick.
func set_mount(key: String, mount_id: String) -> void:
	var ids: Array = _mount_ids.get(key, [])
	if ids.has(mount_id):
		_updating = true
		(_mount_buttons[key] as OptionButton).selected = ids.find(mount_id)
		_updating = false

	tweaks.set_choice(key, mount_id)
	tweaks_changed.emit()


func _on_mount_selected(key: String, index: int) -> void:
	if _updating:
		return
	var ids: Array = _mount_ids.get(key, [])
	if index < 0 or index >= ids.size():
		return
	set_mount(key, String(ids[index]))


## The reset button, pressed.
func reset() -> void:
	tweaks.reset()
	tweaks_changed.emit()


func _on_slider_moved(key: String, millimetres: float) -> void:
	if _updating:
		return
	set_tweak_mm(key, millimetres)
