class_name PrintPanel
extends PanelContainer
## The Printed room's one panel: how this drone's parts are printed, and the parts to print —
## printed-room slice PR0 (plans/2026-09-14-printed-room-plan.md).
##
## NO RAIL. There is nothing to shop for: printed parts are generated from the build (design §3), so
## the list lives on this panel beside the clearance that shapes every one of them, rather than on a
## left-hand rail that would look like a catalog.
##
## THE PANEL WRITES NOTHING, on CameraPanel's rule. The slider announces `clearance_edited` and each
## Export button announces `export_requested`; LabScreen owns the `printing` copy and the shell owns
## the files. What is shown is re-read on the next render, never taken from the slider.

signal clearance_edited(mm: float)
signal export_requested(part_id: String)
## An arm-guard setting moved under the mouse: `ArmGuard.FITTED` with a bool, or a length key in mm.
signal arm_guard_edited(key: String, value: Variant)
## A camera-mount setting moved: `CameraMount.FITTED` with a bool (PR19), or `PLATE_SPACING` in mm.
signal camera_mount_edited(key: String, value: Variant)
## An antenna-mount setting moved: `AntennaMount.FITTED` with a bool (PR20), or `STANDOFF_SPACING` or `STANDOFF_DIAMETER` in mm.
signal antenna_mount_edited(key: String, value: Variant)
## PR7: a "Printed before" finding's Keep or Reprint button, by part id.
signal divergence_kept(part_id: String)
## PR10: a GPS-mast setting moved: `GpsMast.FITTED` with a bool, or a length key in mm.
signal gps_mast_edited(key: String, value: Variant)
## PR11: a battery-pad setting moved: `BatteryPad.FITTED` with a bool, or a length key in mm.
signal battery_pad_edited(key: String, value: Variant)
signal divergence_reprint_requested(part_id: String)

var _slider: HSlider
var _value: Label
var _hint: Label
var _parts: VBoxContainer
var _buttons: Dictionary = {}
var _fit_toggles: Dictionary = {}
var _gap_sliders: Dictionary = {}
var _before: VBoxContainer
var _divergence_buttons: Dictionary = {}
var _rows: Array = []
var _updating := false
## The column of rows, kept so its natural height can be measured.
var _root: VBoxContainer
## Lab dock (lab dock design §3): "" for the whole room, or the one part whose page this is — the
## sheet then shows only that part's line and its own "Printed before" buttons, and drops the
## panel's explanatory sentences (the page's drawing and numbers say them).
var _dock_part := ""
var _title: Label
var _intro: Label
var _parts_title: Label
var _before_title: Label
## part id → its line (VBox) in `_parts`.
var _lines: Dictionary = {}
## part id → [message Label, button row] in `_before`.
var _before_entries: Dictionary = {}


## How tall the panel's rows are, unscrolled.
func content_height() -> float:
	return _root.get_combined_minimum_size().y


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root = root
	# Scrolls, on TunePanel's pattern: one row per printed part, each with its note and sliders, is
	# taller than a laptop window. Without the ScrollContainer the rows' whole height becomes this
	# panel's MINIMUM height, which beats the inspector's bottom offset, so the column grew past
	# BOTTOM_KEEPOUT, ran under the Lab / Sim / Rooms dock and off the window. Vertical only.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	AssemblyPanel._padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "PRINTED"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)
	_title = title

	var note := Label.new()
	note.text = "Parts this drone needs printed, generated from what is fitted. Saved with this drone, not across drones."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)
	_intro = note

	root.add_child(HSeparator.new())

	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = "Fit clearance"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	_value = Label.new()
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value)
	root.add_child(header)

	_slider = HSlider.new()
	_slider.min_value = PrintSettings.MIN_CLEARANCE_MM
	_slider.max_value = PrintSettings.MAX_CLEARANCE_MM
	_slider.step = PrintSettings.CLEARANCE_STEP_MM
	_slider.value_changed.connect(_on_slider_moved)
	root.add_child(_slider)

	_hint = Label.new()
	_hint.text = PrintSettings.CLEARANCE_HINT
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(280, 0)
	_hint.theme_type_variation = &"MutedLabel"
	root.add_child(_hint)

	root.add_child(HSeparator.new())

	var parts_title := Label.new()
	parts_title.text = "Parts"
	root.add_child(parts_title)
	_parts_title = parts_title

	_parts = VBoxContainer.new()
	root.add_child(_parts)

	_before = VBoxContainer.new()
	_before.visible = false
	root.add_child(_before)


func render(build: Build, printing: Dictionary) -> void:
	_updating = true
	_slider.value = PrintSettings.clearance_mm(printing)
	_updating = false
	_value.text = PrintSettings.clearance_row_text(printing)

	for child in _parts.get_children():
		_parts.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_fit_toggles.clear()
	_gap_sliders.clear()
	_lines.clear()
	_rows = PrintedParts.for_build(build)

	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Nothing on this build is printed yet."
		empty.theme_type_variation = &"MutedLabel"
		_parts.add_child(empty)
		_apply_dock_part()
		return

	for row in _rows:
		var line := VBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(row["label"])
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size = Vector2(280, 0)
		line.add_child(name_label)
		var note_label := Label.new()
		note_label.text = String(row["note"])
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.custom_minimum_size = Vector2(280, 0)
		note_label.theme_type_variation = &"MutedLabel"
		line.add_child(note_label)
		var id := String(row["id"])
		if bool(row.get("fittable", false)) and id == PrintedParts.ARM_GUARD:
			var fit := CheckBox.new()
			fit.text = "Fitted — count their weight"
			fit.button_pressed = bool(row["fitted"])
			fit.toggled.connect(func(on: bool) -> void: arm_guard_edited.emit(ArmGuard.FITTED, on))
			line.add_child(fit)
			_fit_toggles[id] = fit
		if bool(row.get("fittable", false)) and id == PrintedParts.GPS_MAST:
			var mast_fit := CheckBox.new()
			mast_fit.text = "Fitted — count its weight"
			mast_fit.button_pressed = bool(row["fitted"])
			mast_fit.toggled.connect(func(on: bool) -> void: gps_mast_edited.emit(GpsMast.FITTED, on))
			line.add_child(mast_fit)
			_fit_toggles[id] = mast_fit
		if bool(row.get("fittable", false)) and id == PrintedParts.BATTERY_PAD:
			var pad_fit := CheckBox.new()
			pad_fit.text = "Fitted — count its weight"
			pad_fit.button_pressed = bool(row["fitted"])
			pad_fit.toggled.connect(func(on: bool) -> void: battery_pad_edited.emit(BatteryPad.FITTED, on))
			line.add_child(pad_fit)
			_fit_toggles[id] = pad_fit
		if bool(row.get("fittable", false)) and id == PrintedParts.CAMERA_MOUNT:
			var cheek_fit := CheckBox.new()
			cheek_fit.text = "Fitted — draw them (no weight of their own)"
			cheek_fit.button_pressed = bool(row["fitted"])
			cheek_fit.toggled.connect(func(on: bool) -> void: camera_mount_edited.emit(CameraMount.FITTED, on))
			line.add_child(cheek_fit)
			_fit_toggles[id] = cheek_fit
		if id == PrintedParts.CAMERA_MOUNT and row.has("plate_spacing_mm"):
			var gap := HSlider.new()
			gap.min_value = CameraMount.MIN_PLATE_SPACING_MM
			gap.max_value = CameraMount.MAX_PLATE_SPACING_MM
			gap.step = 0.5
			gap.value = float(row["plate_spacing_mm"])
			gap.tooltip_text = CameraMount.PLATE_SPACING_HINT
			gap.value_changed.connect(func(mm: float) -> void:
				camera_mount_edited.emit(CameraMount.PLATE_SPACING, mm))
			line.add_child(gap)
			_gap_sliders[id] = gap
		if bool(row.get("fittable", false)) and id == PrintedParts.ANTENNA_MOUNT:
			var tube_fit := CheckBox.new()
			tube_fit.text = "Fitted — draw it (no weight of its own)"
			tube_fit.button_pressed = bool(row["fitted"])
			tube_fit.toggled.connect(func(on: bool) -> void: antenna_mount_edited.emit(AntennaMount.FITTED, on))
			line.add_child(tube_fit)
			_fit_toggles[id] = tube_fit
		if id == PrintedParts.ANTENNA_MOUNT and row.has("standoff_spacing_mm"):
			for setting in [
					[AntennaMount.STANDOFF_SPACING, AntennaMount.MIN_STANDOFF_SPACING_MM,
						AntennaMount.MAX_STANDOFF_SPACING_MM, "standoff_spacing_mm", AntennaMount.STANDOFF_SPACING_HINT],
					[AntennaMount.STANDOFF_DIAMETER, AntennaMount.MIN_STANDOFF_DIAMETER_MM,
						AntennaMount.MAX_STANDOFF_DIAMETER_MM, "standoff_diameter_mm", AntennaMount.STANDOFF_DIAMETER_HINT]]:
				var key: String = setting[0]
				var slider := HSlider.new()
				slider.min_value = float(setting[1])
				slider.max_value = float(setting[2])
				slider.step = 0.5
				slider.value = float(row[setting[3]])
				slider.tooltip_text = String(setting[4])
				slider.value_changed.connect(func(mm: float) -> void: antenna_mount_edited.emit(key, mm))
				line.add_child(slider)
		var button := Button.new()
		button.text = "Export STL…"
		button.disabled = not bool(row["exportable"])
		button.pressed.connect(func() -> void: export_requested.emit(id))
		line.add_child(button)
		_parts.add_child(line)
		_buttons[id] = button
		_lines[id] = line
	_apply_dock_part()


## The "Printed before" list (PR7): one line per divergence the shell found on open, each with Keep and
## Reprint. Separate from `render`, which runs on every selection change; findings change only when the
## shell checks again.
func set_divergence(findings: Array) -> void:
	for child in _before.get_children():
		_before.remove_child(child)
		child.queue_free()
	_divergence_buttons.clear()
	_before_entries.clear()
	_before.visible = not findings.is_empty()
	if findings.is_empty():
		_apply_dock_part()
		return
	var title := Label.new()
	title.text = "Printed before — differs from today"
	_before.add_child(title)
	_before_title = title
	for finding in findings:
		var part := String(finding["part"])
		var message := Label.new()
		message.text = String(finding["message"])
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.custom_minimum_size = Vector2(280, 0)
		message.theme_type_variation = &"MutedLabel"
		_before.add_child(message)
		var row := HBoxContainer.new()
		var keep := Button.new()
		keep.text = "Keep the printed one"
		keep.pressed.connect(func() -> void: divergence_kept.emit(part))
		row.add_child(keep)
		var reprint := Button.new()
		reprint.text = "Reprint"
		reprint.disabled = String(finding["kind"]) == "gone"
		reprint.pressed.connect(func() -> void: divergence_reprint_requested.emit(part))
		row.add_child(reprint)
		_before.add_child(row)
		_divergence_buttons["%s|keep" % part] = keep
		_divergence_buttons["%s|reprint" % part] = reprint
		_before_entries[part] = [message, row]
	_apply_dock_part()


## Cuts the panel to one part's page (lab dock design §3: each page shows only its own item): its
## line — note, settings and Export — the clearance that shapes it, and its own Keep / Reprint.
## The finding's sentence goes too: the page lists it behind Why?. "" puts the whole room back.
func set_dock_part(part_id: String) -> void:
	_dock_part = part_id
	_apply_dock_part()


func _apply_dock_part() -> void:
	var whole := _dock_part == ""
	_intro.visible = whole
	_hint.visible = whole
	_parts_title.visible = whole
	_title.text = "PRINTED"
	for id in _lines:
		(_lines[id] as Control).visible = whole or id == _dock_part
		if id == _dock_part:
			for row in _rows:
				if String(row["id"]) == id:
					_title.text = String(row["label"]).split(" — ")[0].to_upper()
	var own_finding := false
	for part in _before_entries:
		var mine: bool = part == _dock_part
		own_finding = own_finding or mine
		(_before_entries[part][0] as Control).visible = whole
		(_before_entries[part][1] as Control).visible = whole or mine
	if _before_title != null and is_instance_valid(_before_title):
		_before_title.text = "Printed before — differs from today" if whole \
			else "Printed before — keep it, or reprint?"
	_before.visible = not _before_entries.is_empty() and (whole or own_finding)


## Which part's lines are showing, in order, for tests.
func shown_parts() -> Array:
	var out: Array = []
	for row in _rows:
		var id := String(row["id"])
		if _lines.has(id) and (_lines[id] as Control).visible:
			out.append(id)
	return out


## The panel's explanatory sentences (the room's intro, the clearance hint) are showing.
func prose_visible() -> bool:
	return _intro.visible or _hint.visible


## The "Printed before" block, and one part's sentence in it, are showing. For tests.
func before_visible() -> bool:
	return _before.visible


func finding_text_visible(part_id: String) -> bool:
	return _before_entries.has(part_id) and (_before_entries[part_id][0] as Control).is_visible_in_tree()


## A "Printed before" button, `which` = "keep" or "reprint", or null. For tests.
func divergence_button(part_id: String, which: String) -> Button:
	return _divergence_buttons.get("%s|%s" % [part_id, which], null)


func clearance_row_text() -> String:
	return _value.text


func hint_text() -> String:
	return _hint.text


func slider_range() -> Vector2:
	return Vector2(_slider.min_value, _slider.max_value)


## The rows rendered last, as PrintedParts gave them.
func rows() -> Array:
	return _rows


## The Export button for one part, or null when the part is not listed. For tests.
func export_button(part_id: String) -> Button:
	return _buttons.get(part_id, null)


## The fitted toggle for one part, or null. For tests.
func fit_toggle(part_id: String) -> CheckBox:
	return _fit_toggles.get(part_id, null)


## The note printed under one part, or "" when it is not listed. For tests.
func row_note(part_id: String) -> String:
	for row in _rows:
		if String(row["id"]) == part_id:
			return String(row["note"])
	return ""


func _on_slider_moved(mm: float) -> void:
	if _updating:
		return
	clearance_edited.emit(mm)
