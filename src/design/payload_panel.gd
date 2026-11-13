class_name PayloadPanel
extends VBoxContainer
## The payload controls of the Design Space: pick a kind (or none), then type the mass and the box if the
## kind's own figures are not yours. Every edit is one undo step on the session (`set_payload`), saved
## sparsely: only what differs from the kind is written (PayloadPart.to_saved).
##
## Below it, the lift line: "Can't lift: needs X g thrust, max Y g (T/W 0.zz)" in amber when peak thrust is
## under the weight, a quieter "Marginal lift" under T/W 1.5. It reads LiftVerdict, i.e. Build.can_hover.

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)

var ds: DesignSpace
var kind_option: OptionButton
var mass_stepper: DsStepper
var dim_fields: Array = []       ## LineEdit x3: length, width, height (mm)
var note_label: Label
var lift_label: Label
var _detail: VBoxContainer
var _syncing := false


func _init(p_ds: DesignSpace) -> void:
	ds = p_ds
	name = "PayloadPanel"
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	lift_label = DsUi.label("", DsUi.WARN)
	lift_label.name = "LiftNote"
	lift_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lift_label.visible = false
	add_child(lift_label)

	add_child(DsUi.section("Payload"))
	kind_option = OptionButton.new()
	kind_option.name = "PayloadKind"
	kind_option.clip_text = true
	# Sized by the panel, not by its longest kind: "Mapping camera (multispectral)" would push the panel off screen.
	kind_option.fit_to_longest_item = false
	kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DsUi.style_button(kind_option)
	kind_option.add_item("None")
	kind_option.set_item_metadata(0, PayloadPart.NONE)
	for e in PayloadPart.kinds():
		kind_option.add_item(String(e["name"]))
		kind_option.set_item_metadata(kind_option.item_count - 1, String(e["part_id"]))
	kind_option.item_selected.connect(_on_kind)
	add_child(kind_option)

	_detail = VBoxContainer.new()
	_detail.name = "PayloadDetail"
	_detail.add_theme_constant_override("separation", 6)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)

	_detail.add_child(DsUi.label("Mass, g"))
	mass_stepper = DsStepper.new(0.0, PayloadPart.MAX_MASS_G, 1.0)
	mass_stepper.name = "PayloadMass"
	mass_stepper.edit.custom_minimum_size = Vector2(40, 0)
	mass_stepper.value_changed.connect(func(_v: float) -> void: _on_edit())
	_detail.add_child(mass_stepper)

	_detail.add_child(DsUi.label("Length, width, height, mm"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for axis in ["PayloadLength", "PayloadWidth", "PayloadHeight"]:
		var e := LineEdit.new()
		e.name = axis
		e.alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.custom_minimum_size = Vector2(0, 0)
		e.expand_to_text_length = false
		DsUi.style_field(e)
		# Three fields share a 212 px panel; the default four-character minimum would not.
		e.add_theme_constant_override("minimum_character_width", 1)
		for state in ["normal", "focus"]:
			var box := (e.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
			box.content_margin_left = 3
			box.content_margin_right = 3
			e.add_theme_stylebox_override(state, box)
		e.text_submitted.connect(func(_t: String) -> void: _on_edit())
		e.focus_exited.connect(_on_edit)
		row.add_child(e)
		dim_fields.append(e)
	_detail.add_child(row)

	# No note row: the 720 px window has no room for one beside the lift line. What it would say, and the kind's
	# source note, ride on the picker's tooltip.
	note_label = DsUi.label("")
	refresh()


## Reads the session into the controls and the lift line. Setting a control here never edits the design.
func refresh() -> void:
	_syncing = true
	var saved := ds.session.payload()
	var spec := PayloadPart.resolve(saved)
	var kind := String(spec.get("kind", PayloadPart.NONE))
	for i in kind_option.item_count:
		if String(kind_option.get_item_metadata(i)) == kind:
			kind_option.select(i)
	if kind != PayloadPart.NONE and kind_option.selected >= 0 and String(kind_option.get_item_metadata(kind_option.selected)) != kind:
		kind_option.select(0)
	_detail.visible = not spec.is_empty()
	if not spec.is_empty():
		mass_stepper.set_value_no_signal(float(spec["mass_g"]))
		var vals := [spec["length_mm"], spec["width_mm"], spec["height_mm"]]
		for i in 3:
			var e := dim_fields[i] as LineEdit
			if not e.has_focus():
				e.text = "%.0f" % float(vals[i])
		var edited := bool(spec["mass_edited"]) or bool(spec["size_edited"])
		note_label.text = "Your figures." if edited else "Approximate, type your own."
		kind_option.tooltip_text = "%s\n%s" % [note_label.text, String(spec["source"])]
	_syncing = false
	var b := ds.session.build(ds._catalog)
	var verdict := LiftVerdict.of(b)
	lift_label.text = String(verdict["text"])
	lift_label.visible = lift_label.text != ""
	var ink: Color = DsUi.WARN if String(verdict["state"]) == LiftVerdict.CANNOT else INK_MUTED
	lift_label.add_theme_color_override("font_color", ink)


func _on_kind(index: int) -> void:
	if _syncing:
		return
	var kind := String(kind_option.get_item_metadata(index))
	# A new kind starts from its own figures: the previous kind's edits do not follow it.
	ds.session.set_payload({} if kind == PayloadPart.NONE else {"kind": kind})


func _on_edit() -> void:
	if _syncing:
		return
	var kind := String(kind_option.get_item_metadata(kind_option.selected))
	if kind == PayloadPart.NONE:
		return
	var dims: Array = []
	for e in dim_fields:
		var t := (e as LineEdit).text
		dims.append(clampf(float(t) if t.is_valid_float() else 0.0, PayloadPart.MIN_DIM_MM, PayloadPart.MAX_DIM_MM))
	ds.session.set_payload(PayloadPart.to_saved(kind, mass_stepper.value, dims[0], dims[1], dims[2]))
