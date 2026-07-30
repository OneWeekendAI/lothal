class_name AssemblyPanel
extends PanelContainer
## The fit adjustments: three sliders and a reset, over the AssemblyTweaks the builder's
## configuration lives in.
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

signal tweaks_changed

var tweaks: AssemblyTweaks

var _sliders: Dictionary = {}   # key -> HSlider
var _values: Dictionary = {}    # key -> Label
## Set while the panel is writing its own controls from the model, so that programmatic slider
## moves do not read back as the builder having dragged something.
var _updating := false

func _init(p_tweaks: AssemblyTweaks) -> void:
	tweaks = p_tweaks

	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_padded(self).add_child(root)

	var title := Label.new()
	title.text = "FIT"
	root.add_child(title)

	var note := Label.new()
	note.text = "Shims and standoffs. Changes the fit, not the flight numbers."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	root.add_child(note)

	root.add_child(HSeparator.new())

	for row in AssemblyTweaks.ROWS:
		_add_row(root, row)

	root.add_child(HSeparator.new())

	var reset_button := Button.new()
	reset_button.text = "Reset to as-built"
	reset_button.pressed.connect(reset)
	root.add_child(reset_button)


## Same inset as PartDetails, for the same reason: right-aligned values flush against the window
## edge read as clipped text even when nothing is cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	parent.add_child(margin)
	return margin


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
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	parent.add_child(hint)


## Re-reads the limits for `build` and shows the values in force. Called on every selection change
## as well as after a tweak, because a part change moves the limits — and a slider still sitting at
## a range the current motor does not have is exactly the disagreement between panel and geometry
## this screen is built to make impossible.
func render(build: Build) -> void:
	_updating = true
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


## The reset button, pressed.
func reset() -> void:
	tweaks.reset()
	tweaks_changed.emit()


func _on_slider_moved(key: String, millimetres: float) -> void:
	if _updating:
		return
	set_tweak_mm(key, millimetres)
