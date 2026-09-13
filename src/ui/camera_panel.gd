class_name CameraPanel
extends PanelContainer
## Video's Camera panel: the uptilt the camera is mounted at, and what that tilt does — video slice
## V5 (plans/2026-09-13-video-room-design.md §4).
##
## WHY A PANEL OF ITS OWN rather than a row on `ElectronicsDetails`. That panel is a `PartDetails`:
## spec rows read out of the build and the five derived stats, with nothing on it a builder moves.
## A slider there would be the first control on a read-only family, and every sibling's footer would
## have to learn to ignore it. A tab beside it is one more entry in Video's `panels` list, routed by
## title like every other (`efa915c`).
##
## THE TILT IS NOT THIS PANEL'S TO WRITE, for the reason the Power room's pack offset is not that
## room's (PW6). It is an assembly tweak, it already has a row on the Fit panel, and
## `AssemblyPanel.set_tweak_mm` is the single path a tweak takes — it snaps, clamps to the range and
## emits the signal Lab rebuilds and saves on. So the slider here only ANNOUNCES (`tilt_edited`), and
## LabScreen routes that into the Fit panel's path; the value shown is re-read from the tweaks on the
## next render, never taken from the slider. A second writer would be a second place the number lives.
##
## THE FIT PANEL KEEPS ITS ROW, and that is not duplicate chrome. Fit is where every tweak is
## reset together ("Reset to as-built") and where a builder sees the whole configuration at once;
## this panel is where the tilt is FOUND, beside the warnings it causes. The two rows are one value
## read twice, and a check compares their STRINGS — the pack offset's rule — because two screens
## agreeing on the number and disagreeing about "(as built)" would still be two answers.
##
## THE WARNINGS ARE THE ONES THE TILT MOVES: `VideoPlausibility` (a tipped camera into the top
## plate, and a transmitter with no antenna) and the camera-view report, which is measured along
## the tilted boresight. Not `Build.warnings()` whole — the Electronics tab beside this one already
## shows all of those.

## Emitted when the slider moves under the mouse. Degrees. The panel does not store it.
signal tilt_edited(degrees: float)

var _slider: HSlider
var _value: Label
var _warnings: WarningList
var _updating := false


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssemblyPanel._padded(self).add_child(root)

	var title := Label.new()
	title.text = "CAMERA"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = "How the camera is mounted. Tilt changes what the lens sees and what it can hit, not the flight numbers."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	var row := _row()
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = row["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	_value = Label.new()
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value)
	root.add_child(header)

	_slider = HSlider.new()
	_slider.step = AssemblyPanel.STEP_MM
	_slider.value_changed.connect(_on_slider_moved)
	root.add_child(_slider)

	var hint := Label.new()
	hint.text = row["hint"]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.theme_type_variation = &"MutedLabel"
	root.add_child(hint)

	_warnings = WarningList.new(280)
	root.add_child(_warnings)


## Shows the tilt in force and the warnings it moves. `airframe` is optional so the panel can be
## rendered against a bare build; without it the camera-view report is simply not asked.
func render(build: Build, tweaks: AssemblyTweaks, airframe: AirframeModel = null) -> void:
	var limits: Dictionary = AssemblyTweaks.limits(build)[AssemblyTweaks.CAMERA_TILT]
	var current := tweaks.value_mm(AssemblyTweaks.CAMERA_TILT, build)
	_updating = true
	_slider.min_value = limits["min"]
	_slider.max_value = limits["max"]
	_slider.value = current
	_updating = false
	# The Fit panel's own format, unit and suffix, so the two rows read as one string.
	_value.text = "%.1f %s%s" % [current, String(_row().get("unit", "mm")),
		"" if tweaks.has_override(AssemblyTweaks.CAMERA_TILT) else "  (as built)"]

	var entries := VideoPlausibility.warnings_for(build)
	if airframe != null:
		entries.append_array(airframe.camera_view_warnings())
	_warnings.show_warnings(entries)


## What the tilt row reads — the counterpart of `AssemblyPanel.tweak_row_text`, compared as strings.
func tilt_row_text() -> String:
	return _value.text


## The slider's range, for tests: it must be the tweak's own limits, not a second opinion.
func slider_range() -> Vector2:
	return Vector2(_slider.min_value, _slider.max_value)


func warning_text() -> String:
	return _warnings.ordered_text() if _warnings.visible else ""


static func _row() -> Dictionary:
	for row in AssemblyTweaks.ROWS:
		if row["key"] == AssemblyTweaks.CAMERA_TILT:
			return row
	return {"label": "Camera uptilt", "hint": "", "unit": "°"}


func _on_slider_moved(degrees: float) -> void:
	if _updating:
		return
	tilt_edited.emit(degrees)
