class_name FrameControls
extends ScrollContainer
## The Airframe room's right-hand column: every dimension of the open frame, as a slider you can
## drag and a box you can type in.
##
## ## Why this replaced a readout
##
## The column used to be four tabs of NUMBERS ABOUT the frame — mass, inertia, stiffness, warnings.
## They are the right thing to show somebody evaluating a frame and the wrong thing to hand
## somebody designing one, because none of them can be changed. A builder who wanted a 137 mm arm
## had exactly one route to it: zoom in, grab a corner, drag it against a 0.5 mm grid, and check
## the result on a readout that was three clicks away. The mouse is how you FIND a shape; it is a
## terrible way to commit to one.
##
## So this column is the frame's parameters, and the readouts moved into the drawer under the
## canvas where they belong — visible, one glance away, and not occupying the space where the
## controls have to be. Nothing was deleted; the two swapped places, because only one of them is
## something you do.
##
## ## Context-sensitive, and never showing a control that acts on nothing
##
## What is on screen follows the selection: nothing selected shows the whole-frame controls, an
## arm shows its angle and taper, a plate shows its stock and height, a motor shows its spin and
## tilt. A slider that acts on nothing is worse than an absent one — it invites a drag that changes
## something the builder cannot see, or nothing at all, and both teach them not to trust the panel.
##
## ## Every control emits ONE edit, and the edit is `FrameEdits`'
##
## Nothing here computes geometry. A slider reads a number out of the document and writes a number
## back through a pure, tested function, which is the same split the canvas keeps: the risky half
## is the arithmetic, and the arithmetic lives where it can be proved headless. What is left here is
## which box holds which number.

## Emitted after any control changes the document. The workbench listens, repaints and pushes it
## onward, so a slider drag repaints the canvas, the 3D view and the numbers drawer with no control
## here knowing that any of them exist.
signal document_changed(document: AirframeDocument)
## Emitted BEFORE a change, so the workbench can snapshot for undo. Its own signal rather than the
## panel reaching into the history: a drag is one undo step, and only the thing that owns the
## history can know whether a `value_changed` is the start of a gesture or the middle of one.
signal edit_began

## Fixed rather than sized to the content: this column is a control surface and its boxes must not
## move sideways as the numbers in them get longer. 300 px fits a label, a slider and a four-digit
## field with a unit.
const COLUMN_WIDTH := 300.0

const SECTION_GAP := 10

var document: AirframeDocument
## Which plate is selected, or −1. Motors are selected separately because a motor is not a plate —
## see `selected_motor`.
var selected_plate := -1
var selected_motor := -1

var materials := FrameMaterials.load_default()

var _content: VBoxContainer
## The live controls, by key, so a repopulate can write values in without rebuilding the column on
## every mouse motion of a drag. Rebuilding would destroy the very slider under the cursor.
var _fields: Dictionary = {}
var _sections: Dictionary = {}
## Guards the write-back while values are being pushed IN. Setting a SpinBox's value fires the same
## signal a builder's typing does; without this, opening a frame would look like eleven edits.
var _syncing := false


func _init() -> void:
	custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", SECTION_GAP)
	add_child(_content)
	_build()


# ---------------------------------------------------------------------------
# Building the column, once
# ---------------------------------------------------------------------------

func _build() -> void:
	_build_frame_section()
	_build_layout_section()
	_build_arm_section()
	_build_plate_section()
	_build_motor_section()


## The whole frame: what it is called and what it is cut from. Both change every mass on screen —
## the material by density, the name by nothing at all, and the name is here because a frame you
## are going to export needs to be called something before the file lands in a folder.
func _build_frame_section() -> void:
	var box := _section("frame", "Frame")

	var name_field := LineEdit.new()
	name_field.placeholder_text = "Frame name"
	name_field.text_changed.connect(func(text: String) -> void:
		if _syncing or document == null:
			return
		document.name = text
		document_changed.emit(document))
	_fields["name"] = name_field
	box.add_child(_labelled("Name", name_field))

	var stock := OptionButton.new()
	for id in materials.ids():
		stock.add_item(str(materials.get_material(id).get("name", id)))
		stock.set_item_metadata(stock.item_count - 1, id)
	stock.item_selected.connect(func(index: int) -> void:
		if _syncing or document == null:
			return
		edit_began.emit()
		document.material_id = str(stock.get_item_metadata(index))
		document_changed.emit(document))
	_fields["material"] = stock
	box.add_child(_labelled("Material", stock))


## The layout controls: the parameters `FrameLayouts` generated the frame from, still live.
##
## SHOWN ONLY FOR A GENERATED FRAME, and that is not a limitation — it is the honest scope of the
## control. "Arm length" is a meaningful number for four identical arms radiating from an origin,
## and it is meaningless for a frame somebody has drawn a swept deadcat front end onto: there is no
## single length to set, and a slider that regenerated the arms would silently throw the drawing
## away. So the moment a vertex is dragged, the document stops being generated (the workbench
## clears the tag) and this section is replaced by a button that regenerates deliberately.
func _build_layout_section() -> void:
	var box := _section("layout", "Layout")

	var template := OptionButton.new()
	for id in FrameLayouts.ids():
		template.add_item(str(FrameLayouts.template(id).get("name", id)))
		template.set_item_metadata(template.item_count - 1, id)
	template.item_selected.connect(func(index: int) -> void:
		if _syncing:
			return
		_regenerate(str(template.get_item_metadata(index))))
	_fields["template"] = template
	box.add_child(_labelled("Type", template))

	for spec in [
		{"key": "arm_length_mm", "label": "Arm length", "min": 30.0, "max": 400.0, "step": 1.0},
		{"key": "arm_root_width_mm", "label": "Arm width, root", "min": 4.0, "max": 60.0,
			"step": 0.5},
		{"key": "arm_tip_width_mm", "label": "Arm width, tip", "min": 4.0, "max": 60.0,
			"step": 0.5},
		{"key": "arm_thickness_mm", "label": "Arm stock", "min": 1.0, "max": 12.0, "step": 0.5},
		{"key": "plate_thickness_mm", "label": "Plate stock", "min": 0.5, "max": 8.0,
			"step": 0.5},
		{"key": "plate_side_mm", "label": "Centre plate", "min": 20.0, "max": 200.0,
			"step": 1.0},
		{"key": "standoff_len_mm", "label": "Stack height", "min": 5.0, "max": 80.0,
			"step": 1.0},
		{"key": "motor_pitch_mm", "label": "Motor pattern", "min": 6.0, "max": 30.0,
			"step": 0.5},
		{"key": "stack_pitch_mm", "label": "Stack pattern", "min": 16.0, "max": 45.0,
			"step": 0.5},
	]:
		var key := str(spec["key"])
		box.add_child(_slider_row(key, str(spec["label"]), float(spec["min"]),
			float(spec["max"]), float(spec["step"]), func(_number: float) -> void:
				_regenerate(FrameLayouts.layout_id_of(document))))

	var alternate := Button.new()
	alternate.text = "Alternate motor directions"
	alternate.pressed.connect(func() -> void:
		if document == null:
			return
		edit_began.emit()
		FrameEdits.alternate_spins(document)
		document_changed.emit(document))
	box.add_child(alternate)

	var balance := Label.new()
	balance.theme_type_variation = &"SmallLabel"
	balance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields["balance"] = balance
	box.add_child(balance)


## One arm's own geometry, for the arm that is selected. These act on THAT arm and nothing else,
## which is what makes a deadcat possible: sweep the two front arms forward and leave the rear pair
## where they are.
func _build_arm_section() -> void:
	var box := _section("arm", "Selected arm")
	for spec in [
		{"key": "arm_angle", "label": "Angle", "min": -180.0, "max": 360.0, "step": 0.5},
		{"key": "arm_length", "label": "Length", "min": 10.0, "max": 500.0, "step": 0.5},
		{"key": "arm_root", "label": "Width, root", "min": 3.0, "max": 80.0, "step": 0.5},
		{"key": "arm_tip", "label": "Width, tip", "min": 3.0, "max": 80.0, "step": 0.5},
	]:
		box.add_child(_slider_row(str(spec["key"]), str(spec["label"]), float(spec["min"]),
			float(spec["max"]), float(spec["step"]), func(_number: float) -> void: _apply_arm()))


## A plate's own properties: what it is for, how thick it is, how high it sits and how big it is.
##
## `z` is the one that turns a top view into an assembly — it is what stacks a top plate above a
## bottom one — and it is unreachable with a mouse in a plan view by definition, which is the
## clearest case in the room for a number rather than a drag.
func _build_plate_section() -> void:
	var box := _section("plate", "Selected plate")

	var role := OptionButton.new()
	for entry in [AirframeDocument.ROLE_BOTTOM, AirframeDocument.ROLE_TOP,
			AirframeDocument.ROLE_ARM, AirframeDocument.ROLE_SIDE, AirframeDocument.ROLE_MID]:
		role.add_item(entry)
	role.item_selected.connect(func(index: int) -> void:
		if _syncing or selected_plate < 0:
			return
		edit_began.emit()
		FrameEdits.set_role(document, selected_plate, role.get_item_text(index))
		document_changed.emit(document))
	_fields["role"] = role
	box.add_child(_labelled("Role", role))

	box.add_child(_slider_row("thickness", "Stock", 0.5, 12.0, 0.1,
		func(value: float) -> void:
			if selected_plate < 0:
				return
			edit_began.emit()
			FrameEdits.set_thickness(document, selected_plate, value)
			document_changed.emit(document)))

	box.add_child(_slider_row("z", "Height", -60.0, 120.0, 0.5,
		func(value: float) -> void:
			if selected_plate < 0:
				return
			edit_began.emit()
			FrameEdits.set_plate_z(document, selected_plate, value)
			document_changed.emit(document)))

	# Scale and rotate are RELATIVE, so they read 100% and 0° whatever the plate is: they are
	# gestures with a number attached rather than a property of the plate. A "current scale" would
	# be a lie the moment somebody dragged a corner.
	box.add_child(_slider_row("scale", "Resize", 25.0, 400.0, 1.0,
		func(value: float) -> void:
			if selected_plate < 0:
				return
			edit_began.emit()
			FrameEdits.scale_plate(document, selected_plate, value / 100.0)
			_set_value("scale", 100.0)
			document_changed.emit(document), "%"))

	box.add_child(_slider_row("rotate", "Rotate", -180.0, 180.0, 1.0,
		func(value: float) -> void:
			if selected_plate < 0:
				return
			edit_began.emit()
			FrameEdits.rotate_plate(document, selected_plate, value)
			_set_value("rotate", 0.0)
			document_changed.emit(document), "°"))


func _build_motor_section() -> void:
	var box := _section("motor", "Selected motor")

	var spin := CheckButton.new()
	spin.text = "Clockwise"
	spin.toggled.connect(func(on: bool) -> void:
		if _syncing or selected_motor < 0:
			return
		edit_began.emit()
		FrameEdits.set_motor_spin(document, selected_motor, 1.0 if on else -1.0)
		document_changed.emit(document))
	_fields["spin"] = spin
	box.add_child(spin)

	box.add_child(_slider_row("tilt", "Tilt", -45.0, 45.0, 0.5,
		func(value: float) -> void:
			if selected_motor < 0:
				return
			edit_began.emit()
			FrameEdits.set_motor_tilt(document, selected_motor, value)
			document_changed.emit(document), "°"))


# ---------------------------------------------------------------------------
# Showing the open frame
# ---------------------------------------------------------------------------

## Points the column at a document and a selection, and writes every value into its control.
func show_document(
	p_document: AirframeDocument, plate_index: int = -1, motor_index: int = -1
) -> void:
	document = p_document
	selected_plate = plate_index
	selected_motor = motor_index
	refresh()


func refresh() -> void:
	if document == null:
		return
	_syncing = true

	(_fields["name"] as LineEdit).text = document.name
	var stock := _fields["material"] as OptionButton
	for index in stock.item_count:
		if str(stock.get_item_metadata(index)) == document.material_id:
			stock.select(index)

	var layout_id := FrameLayouts.layout_id_of(document)
	_sections["layout"].visible = not layout_id.is_empty()
	if not layout_id.is_empty():
		var template := _fields["template"] as OptionButton
		for index in template.item_count:
			if str(template.get_item_metadata(index)) == layout_id:
				template.select(index)
		# MEASURED OFF THE DOCUMENT, never read back out of these same boxes. Filling the controls
		# from `_layout_params()` — which reads the controls — would make `refresh` a no-op that
		# preserved whatever the panel last showed, so opening a 200 mm hexacopter would present the
		# previous frame's 110 mm arms and the first slider touch would rebuild it at that size.
		var p := FrameLayouts.params_of(document)
		for key in p:
			if _fields.has(key) and (p[key] is float or p[key] is int):
				_set_value(key, float(p[key]))
		var balance := FrameEdits.spin_balance(document)
		(_fields["balance"] as Label).text = ("Motors balanced — the layout can hold heading."
			if absf(balance) < 0.001
			else "Motor directions are unbalanced by %+.0f — it will drift in yaw." % balance)

	var arm := FrameEdits.arm_geometry(document, selected_plate)
	_sections["arm"].visible = not arm.is_empty()
	if not arm.is_empty():
		_set_value("arm_angle", float(arm["angle_deg"]))
		_set_value("arm_length", float(arm["length_mm"]))
		_set_value("arm_root", float(arm["root_width_mm"]))
		_set_value("arm_tip", float(arm["tip_width_mm"]))

	var has_plate := selected_plate >= 0 and selected_plate < document.plates.size()
	_sections["plate"].visible = has_plate
	if has_plate:
		var plate: Dictionary = document.plates[selected_plate]
		var role := _fields["role"] as OptionButton
		for index in role.item_count:
			if role.get_item_text(index) == str(plate.get("role", "")):
				role.select(index)
		_set_value("thickness", AirframeDocument.plate_thickness_mm(plate))
		_set_value("z", AirframeDocument.plate_z_mm(plate))
		_set_value("scale", 100.0)
		_set_value("rotate", 0.0)

	var has_motor := selected_motor >= 0 and selected_motor < document.motors.size()
	_sections["motor"].visible = has_motor
	if has_motor:
		var motor: Dictionary = document.motors[selected_motor]
		(_fields["spin"] as CheckButton).button_pressed = float(motor.get("spin", 1.0)) > 0.0
		_set_value("tilt", float(motor.get("tilt_deg", 0.0)))

	_syncing = false


# ---------------------------------------------------------------------------
# Applying
# ---------------------------------------------------------------------------

## Rebuilds the frame from the layout controls. One function for all ten of them, because they are
## ten parameters of one generator and changing any of them means the same thing.
func _regenerate(layout_id: String) -> void:
	if _syncing or document == null or layout_id.is_empty():
		return
	edit_began.emit()
	var entry := FrameLayouts.template(layout_id)
	if entry.is_empty():
		return
	FrameLayouts.apply_layout(document, entry, _layout_params())
	document.revision = "generated: %s" % layout_id
	selected_plate = -1
	selected_motor = -1
	refresh()
	document_changed.emit(document)


## The four arm fields, applied together. Together because they describe one quadrilateral: setting
## the length and then the taper as two edits would put an intermediate shape in the undo stack
## that the builder never asked for.
func _apply_arm() -> void:
	if _syncing or selected_plate < 0:
		return
	edit_began.emit()
	FrameEdits.set_arm_geometry(document, selected_plate,
		_value("arm_angle"), _value("arm_length"), _value("arm_root"), _value("arm_tip"))
	document_changed.emit(document)


## The generator parameters as they now stand on screen, filled in from `FrameLayouts.DEFAULTS`
## wherever the panel has no control.
func _layout_params() -> Dictionary:
	var out: Dictionary = FrameLayouts.params()
	for key in out:
		if _fields.has(key) and out[key] is float:
			out[key] = _value(key)
	out["material_id"] = document.material_id if document != null else out["material_id"]
	return out


## Drives one control the way a builder typing into it does, firing the edit behind it.
##
## Public because it is the only honest way to test the column: the alternative is to call
## `FrameEdits` directly, which proves the arithmetic works and says nothing at all about whether
## the slider labelled "Arm length" is connected to it. The capture tooling drives the room through
## this too, for the same reason.
func set_field(key: String, value: float) -> void:
	if _fields.has(key) and _fields[key] is SpinBox:
		(_fields[key] as SpinBox).value = value


func field_value(key: String) -> float:
	return _value(key)


## The box behind a key, for a caller that needs the control itself rather than its number.
func field_box(key: String) -> SpinBox:
	return _fields.get(key) as SpinBox if _fields.has(key) else null


## Whether a section is on screen — which, for the layout section, is the whole statement about
## what kind of frame is open.
func section_visible(key: String) -> bool:
	return _sections.has(key) and (_sections[key] as Control).visible


# ---------------------------------------------------------------------------
# Widgets
# ---------------------------------------------------------------------------

## A titled group. Its own container so a whole section can be hidden in one line when it has
## nothing to act on.
func _section(key: String, title: String) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.text = title.to_upper()
	heading.theme_type_variation = &"SmallLabel"
	heading.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	panel.add_child(heading)
	_sections[key] = panel
	_content.add_child(panel)
	return panel


## A slider and a number box over the same value.
##
## BOTH, and this is the whole argument of the panel. A slider is how you find out what 130 mm looks
## like without knowing you wanted 130; a box is how you get exactly 137.5 when you do. Wired to
## each other rather than to two copies of the value, so they cannot disagree — the box is
## authoritative and the slider writes through it, which also means the box's step and range are the
## only ones that exist.
func _slider_row(
	key: String,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	on_change: Callable,
	suffix: String = "mm"
) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)

	var header := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label_text
	caption.theme_type_variation = &"SmallLabel"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)

	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.suffix = suffix
	box.custom_minimum_size = Vector2(104, 0)
	box.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	header.add_child(box)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	# One value, two views: the slider writes into the box and the box drives the change. A slider
	# that emitted its own edit would double every drag — and the two would round differently.
	slider.value_changed.connect(func(value: float) -> void:
		if _syncing:
			return
		box.value = value)
	box.value_changed.connect(func(value: float) -> void:
		slider.set_value_no_signal(value)
		if _syncing:
			return
		on_change.call(value))

	_fields[key] = box
	_fields["%s_slider" % key] = slider
	return row


static func _labelled(text: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var caption := Label.new()
	caption.text = text
	caption.theme_type_variation = &"SmallLabel"
	row.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _value(key: String) -> float:
	if not _fields.has(key) or not _fields[key] is SpinBox:
		return 0.0
	return float((_fields[key] as SpinBox).value)


## Writes a value in without firing an edit. Both halves, because the slider is set with
## `set_value_no_signal` and would otherwise keep whatever it last showed.
func _set_value(key: String, value: float) -> void:
	if not _fields.has(key) or not _fields[key] is SpinBox:
		return
	var was := _syncing
	_syncing = true
	(_fields[key] as SpinBox).value = value
	if _fields.has("%s_slider" % key):
		(_fields["%s_slider" % key] as HSlider).set_value_no_signal(
			(_fields[key] as SpinBox).value)
	_syncing = was
