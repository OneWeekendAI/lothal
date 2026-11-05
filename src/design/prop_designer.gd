class_name PropDesigner
extends DesignerShell
## The prop designer: a pop-up over the Design Space, opened from the "+" tile at the end of the
## Prop shelf, on the shell the pack and motor designers share. Left: the numbered choices. Middle:
## the blade in 3D with its section below. Right: one number per figure.
##
## DERIVED, NOT TYPED. Each figure comes from the code the rest of the app already flies or tests
## with (PropTunnel, BladeGeometry, PropStructure, SoftMount); every setter ends in _rederive().
##
## The root safety factor is deliberately NOT a figure here: at a t/c 0.10 root it reads pessimistic
## on real props (see PropStructure's header), and the Structure tab decides how to show it.

const LEFT_W := 300.0
const RIGHT_W := 440.0
const FIGURE_ROWS := ["thrust", "power", "mass", "cg", "inertia", "tip_speed", "tip_mach", "blade_pass", "mount"]
const FIGURE_NAMES := {
	"thrust": "Thrust", "power": "Power", "mass": "Mass", "cg": "Blade CG", "inertia": "Inertia",
	"tip_speed": "Tip speed", "tip_mach": "Tip Mach", "blade_pass": "Blade pass", "mount": "Mount",
}
const MATERIALS := ["polycarbonate", "glass_filled_nylon", "carbon_filled_nylon", "pa12_sls"]
const MATERIAL_LABELS := ["PC", "PA6+GF", "PA6+CF", "PA12"]
const VIEW_LABELS := {"iso": "3D", "front": "Front", "top": "Top", "side": "Side"}
const FALLBACK_CLASS := "five_inch"
const SECTION_R_FRAC := 0.7
const DIAMETER_RANGE_IN := Vector2(1.0, 13.0)
const PITCH_RANGE_IN := Vector2(0.5, 12.0)
const BLADES_RANGE := Vector2i(2, 6)
const HUB_RANGE_G := Vector2(0.0, 20.0)
const STEP_IN := 0.1
const STEP_HUB_G := 0.1
const STEP_PAD_MM := 0.5
const THICKNESS_RANGE := Vector2(0.04, 0.20)
const STEP_THICKNESS := 0.01
const THICKNESS_NOTE := "Thickness moves mass and strength. Thrust and power here ignore it."
const TWIST_HELIX_NOTE := "Twist follows the pitch."
const TWIST_DRAWN_NOTE := "Twist is drawn. Pitch does not set the angles."
const TWIST_CAP_NOTE := "Hover sits on the lift cap, so pitch and twist show mostly at forward speed."
const PITCH_OFFER_NOTE := "Pitch changed, angles did not: the twist is drawn."

var catalog: PartsCatalog
var materials: FrameMaterials
var doc: PropellerDocument
## Not on the document: a blade document holds the blades, and a hub's grams are the prop's.
var hub_g := 0.0
var pad_mm := 0.0
var rpm := 0.0
var motor: Dictionary = {}
var mount_spec: Dictionary = {}
var source_name := ""
var derive_count := 0
var pitch_offer_open := false

var save_button: Button
var copy_button: Button
var diameter_value: Label
var pitch_value: Label
var blades_value: Label
var hub_value: Label
var pad_value: Label
var material_row: HFlowContainer
var blade_view: BladeView3D
var section_view: PropellerSectionView
var chord_editor: PropellerPlanformEditor
var twist_editor: PropTwistEditor
var measured_toggle: CheckButton
var twist_note: Label
var thickness_value: Label
var pitch_offer: Control
var section_caption: Label
var undo_button: Button
var redo_button: Button
var caret_r_frac := SECTION_R_FRAC
var _undo: Array = []
var _redo: Array = []
var summary_label: Label
var figures_box: GridContainer
var _figs: Dictionary = {}


## `build` is the drone on the bench: its prop is the starting blade and its motor sets the rpm and
## the pad's limit. With none, the five-inch class's parts stand in.
func _init(p_catalog: PartsCatalog = null, p_materials: FrameMaterials = null, build: Build = null) -> void:
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	materials = p_materials if p_materials != null else FrameMaterials.load_default()
	_init_shell("PropDesigner")
	theme = MotorDesigner.mono_theme()
	_start_from(build)
	_build_shell(_build_top_bar(), _build_left(), _build_middle(), _build_right())
	_rederive()


func _start_from(build: Build) -> void:
	var prop: Dictionary
	if build != null:
		prop = build.propeller
		motor = build.motor
		mount_spec = VibrationModel.soft_mount_spec_for(build)
		pad_mm = float(build.assembly_value("soft_mount_m")) * 1000.0
	else:
		var parts := DroneClass.parts_for(FALLBACK_CLASS)
		prop = catalog.get_part(String(parts["propeller"]))
		motor = catalog.get_part(String(parts["motor"]))
	var authored := PropellerDocument.authored_blade_of(prop)
	doc = authored if authored != null else PropellerDocument.from_catalog_prop(prop)
	source_name = String(prop.get("name", ""))
	# A new prop, not the one it started from: no id to overwrite, and no vendor's weight to claim.
	doc.id = ""
	doc.name = "New prop"
	doc.published_mass_g = 0.0
	hub_g = default_hub_g(doc, materials)
	rpm = Fitting.rated_rpm(float(motor["specs"]["kv"]), float(motor["thrust_test"]["voltage_v"])) \
		* PropulsionWorkbench.DESIGN_RPM_FRACTION


## The boss the mesh draws, as a solid cylinder of the blade's material, to 0.1 g. A starting value
## the builder can change, not a measurement.
static func default_hub_g(p_doc: PropellerDocument, p_materials: FrameMaterials) -> float:
	var r := p_doc.radius_mm() * PropellerDocument.HUB_RADIUS_TO_RADIUS
	var h := p_doc.radius_mm() * PropellerMesh.HUB_HEIGHT_TO_RADIUS
	return snappedf(PI * r * r * h * p_materials.density(p_doc.material_id) * 1e-6, STEP_HUB_G)


func pad_limit_mm() -> float:
	return MotorMesh.max_soft_mount_m(motor) * 1000.0


# ---------------------------------------------------------------------------
# Columns
# ---------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := _top_bar_start("Name this prop", set_prop_name)
	name_field.text = doc.name
	undo_button = _bar_button("Undo", "Undo", undo, "Step back one edit (Ctrl-Z)")
	bar.add_child(undo_button)
	redo_button = _bar_button("Redo", "Redo", redo, "Step forward again (Ctrl-Shift-Z)")
	bar.add_child(redo_button)
	bar.add_child(_fill())
	copy_button = _bar_button("CopySpecs", "Copy specs", func(): pass, "Not available yet")
	copy_button.disabled = true
	bar.add_child(copy_button)
	save_button = _bar_button("Save", "Save", func(): pass, "Saving is not available yet")
	save_button.disabled = true
	bar.add_child(save_button)
	return bar


func _build_left() -> Control:
	var out: Array = []
	var scroll := _left_column(LEFT_W, out)
	var col: VBoxContainer = out[0]
	col.add_child(_section("1 · Size"))
	diameter_value = _add_stepper(col, "Diameter", "Diameter", "Tip to tip",
		func(): step_diameter(-STEP_IN), func(): step_diameter(STEP_IN), 56.0)
	pitch_value = _add_stepper(col, "Pitch", "Pitch", "Advance per turn, at the helix",
		func(): step_pitch(-STEP_IN), func(): step_pitch(STEP_IN), 56.0)
	pitch_offer = _build_pitch_offer()
	col.add_child(pitch_offer)
	blades_value = _add_stepper(col, "Blades", "Blades", "Identical blades on the hub",
		func(): set_blades(doc.blades - 1), func(): set_blades(doc.blades + 1), 56.0)
	col.add_child(_spacer(LothalTheme.SPACE_2))
	col.add_child(_section("2 · Blade"))
	_build_blade_section(col)
	col.add_child(_spacer(LothalTheme.SPACE_2))
	col.add_child(_section("3 · Hub & material"))
	hub_value = _add_stepper(col, "Hub", "Hub", "Grams of hub, added to the blades",
		func(): set_hub_g(hub_g - STEP_HUB_G), func(): set_hub_g(hub_g + STEP_HUB_G), 56.0)
	pad_value = _add_stepper(col, "Pad", "Pad", "Soft mount under the motor; limited by its boss height",
		func(): set_pad_mm(pad_mm - STEP_PAD_MM), func(): set_pad_mm(pad_mm + STEP_PAD_MM), 56.0)
	material_row = _chip_row("MaterialRow", "Material_")
	_set_chips(material_row, MATERIALS, MATERIAL_LABELS, set_blade_material)
	col.add_child(material_row)
	return scroll


func _build_pitch_offer() -> Control:
	var box := VBoxContainer.new()
	box.name = "PitchOffer"
	box.visible = false
	box.add_child(_faint(PITCH_OFFER_NOTE))
	var row := HBoxContainer.new()
	row.add_child(_bar_button("PitchUseHelix", "Use helix", use_helix, "Set the angles from the pitch; undo brings the drawing back"))
	row.add_child(_bar_button("PitchKeepDrawn", "Keep drawn", keep_drawn))
	box.add_child(row)
	return box


func _build_blade_section(col: VBoxContainer) -> void:
	col.add_child(_faint("Chord"))
	chord_editor = PropellerPlanformEditor.new(doc)
	chord_editor.name = "ChordEditor"
	chord_editor.custom_minimum_size = Vector2(260, 104)
	chord_editor.ink = DesignSpace.INK
	chord_editor.caret_ink = DesignSpace.INK_MUTED
	chord_editor.hover_ink = DesignSpace.INK_MUTED
	chord_editor.station_radius_px = 1.5
	chord_editor.caret_r_frac = caret_r_frac
	chord_editor.edit_began.connect(_record)
	chord_editor.document_changed.connect(func(_d): _rederive())
	chord_editor.caret_moved.connect(set_caret)
	col.add_child(chord_editor)
	var chord_row := HBoxContainer.new()
	chord_row.add_child(_bar_button("ChordAdd", "+ Station", add_chord_station, "Add a station at the caret"))
	chord_row.add_child(_bar_button("ChordRemove", "− Station", remove_chord_station, "Remove the station nearest the caret"))
	measured_toggle = CheckButton.new()
	measured_toggle.name = "ChordMeasured"
	measured_toggle.text = "Measured"
	measured_toggle.tooltip_text = "On: this chord was drawn or measured. Off: it is assumed."
	measured_toggle.toggled.connect(set_chord_measured)
	chord_row.add_child(measured_toggle)
	col.add_child(chord_row)

	col.add_child(_faint("Twist"))
	twist_editor = PropTwistEditor.new(doc)
	twist_editor.name = "TwistEditor"
	twist_editor.caret_r_frac = caret_r_frac
	twist_editor.edit_began.connect(_record)
	twist_editor.document_changed.connect(func(_d): _rederive())
	twist_editor.caret_moved.connect(set_caret)
	col.add_child(twist_editor)
	var twist_row := HBoxContainer.new()
	twist_row.add_child(_bar_button("TwistAdd", "+ Station", add_twist_station, "Add a station at the caret"))
	twist_row.add_child(_bar_button("TwistRemove", "− Station", remove_twist_station, "Remove the station nearest the caret"))
	twist_row.add_child(_bar_button("TwistHelix", "Use helix", use_helix, "Set the angles from the pitch"))
	col.add_child(twist_row)
	twist_note = _faint("")
	twist_note.name = "TwistNote"
	col.add_child(twist_note)
	var cap := _faint(TWIST_CAP_NOTE)
	cap.name = "TwistCapNote"
	col.add_child(cap)

	thickness_value = _add_stepper(col, "Thickness", "Thickness", "Section thickness as a share of chord",
		func(): set_thickness(doc.thickness_ratio - STEP_THICKNESS),
		func(): set_thickness(doc.thickness_ratio + STEP_THICKNESS), 56.0)
	var note := _faint(THICKNESS_NOTE)
	note.name = "ThicknessNote"
	col.add_child(note)


func _build_middle() -> Control:
	var col := _middle_column()
	blade_view = BladeView3D.new()
	blade_view.name = "BladeView"
	blade_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blade_view.size_flags_stretch_ratio = 2.4
	blade_view.caret_ink = DesignSpace.INK
	col.add_child(blade_view)
	var snaps := HBoxContainer.new()
	snaps.name = "SnapViews"
	snaps.add_theme_constant_override("separation", 4)
	for view_id: String in VIEW_LABELS:
		var b := _bar_button("View_" + view_id, String(VIEW_LABELS[view_id]), func(): blade_view.snap_to(view_id))
		b.focus_mode = Control.FOCUS_NONE
		snaps.add_child(b)
	col.add_child(snaps)
	section_caption = _faint("")
	section_caption.name = "SectionCaption"
	col.add_child(section_caption)
	section_view = PropellerSectionView.new()
	section_view.ink = DesignSpace.INK
	section_view.chord_ink = DesignSpace.INK_MUTED
	section_view.name = "SectionView"
	section_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(section_view)
	blade_view.set_caret(SECTION_R_FRAC)
	section_view.set_r_frac(SECTION_R_FRAC)
	return col


func _build_right() -> Control:
	var col := _right_column(RIGHT_W)
	summary_label = _faint("")
	summary_label.name = "Summary"
	col.add_child(summary_label)
	figures_box = _figure_grid(FIGURE_ROWS, func(k: String) -> String: return FIGURE_NAMES[k], _figs, 110.0)
	col.add_child(figures_box)
	return col


# ---------------------------------------------------------------------------
# Choices
# ---------------------------------------------------------------------------

func set_prop_name(text: String) -> void:
	doc.name = text
	_rederive()


func step_diameter(delta_in: float) -> void:
	var before := _snapshot()
	var inches := snappedf(doc.diameter_mm / PropellerDocument.INCH_TO_MM + delta_in, STEP_IN)
	inches = clampf(inches, DIAMETER_RANGE_IN.x, DIAMETER_RANGE_IN.y)
	var new_mm := inches * PropellerDocument.INCH_TO_MM
	if doc.chord_is_assumed:
		doc.chord = PropellerDocument.generate_chord(new_mm, doc.blades)
	else:
		# A drawn planform keeps its shape: same chord-to-diameter at every station.
		var k := new_mm / doc.diameter_mm
		for i in range(1, doc.chord.size(), 2):
			doc.chord[i] *= k
	doc.diameter_mm = new_mm
	_commit(before)


## On a drawn twist the pitch moves no angle, so the page says that and offers the helix.
func step_pitch(delta_in: float) -> void:
	var before := _snapshot()
	var inches := snappedf(doc.pitch_mm / PropellerDocument.INCH_TO_MM + delta_in, STEP_IN)
	doc.pitch_mm = clampf(inches, PITCH_RANGE_IN.x, PITCH_RANGE_IN.y) * PropellerDocument.INCH_TO_MM
	pitch_offer_open = not doc.flown_twist().is_empty() and _snapshot() != before
	_commit(before)


func set_blades(count: int) -> void:
	var before := _snapshot()
	doc.blades = clampi(count, BLADES_RANGE.x, BLADES_RANGE.y)
	if doc.chord_is_assumed:
		doc.chord = PropellerDocument.generate_chord(doc.diameter_mm, doc.blades)
	_commit(before)


func set_hub_g(grams: float) -> void:
	var before := _snapshot()
	hub_g = clampf(snappedf(grams, STEP_HUB_G), HUB_RANGE_G.x, HUB_RANGE_G.y)
	_commit(before)


func set_pad_mm(millimetres: float) -> void:
	var before := _snapshot()
	pad_mm = clampf(snappedf(millimetres, STEP_PAD_MM), 0.0, pad_limit_mm())
	_commit(before)


func set_blade_material(material_id: Variant) -> void:
	var before := _snapshot()
	doc.material_id = String(material_id)
	_commit(before)


func set_thickness(ratio: float) -> void:
	var before := _snapshot()
	doc.thickness_ratio = clampf(snappedf(ratio, STEP_THICKNESS), THICKNESS_RANGE.x, THICKNESS_RANGE.y)
	_commit(before)


func set_chord_measured(measured: bool) -> void:
	var before := _snapshot()
	doc.chord_is_assumed = not measured
	_commit(before)


func add_chord_station() -> void:
	var before := _snapshot()
	doc.chord = PlanformEdits.insert_station(doc.chord, caret_r_frac, doc)
	_commit(before)


func remove_chord_station() -> void:
	var before := _snapshot()
	doc.chord = PlanformEdits.remove_station(doc.chord, PlanformEdits.nearest_station(doc.chord, caret_r_frac))
	_commit(before)


func add_twist_station() -> void:
	var before := _snapshot()
	_write_twist(PlanformEdits.insert_twist_station(twist_editor.table(), caret_r_frac, doc))
	_commit(before)


func remove_twist_station() -> void:
	var before := _snapshot()
	var table := twist_editor.table()
	_write_twist(PlanformEdits.remove_station(table, PlanformEdits.nearest_station(table, caret_r_frac)))
	_commit(before)


func _write_twist(table: PackedFloat64Array) -> void:
	doc.twist = table
	doc.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED


func use_helix() -> void:
	var before := _snapshot()
	doc.twist_mode = PropellerDocument.TWIST_MODE_GEOMETRIC
	doc.twist = PackedFloat64Array()
	pitch_offer_open = false
	_commit(before)


func keep_drawn() -> void:
	pitch_offer_open = false
	_rederive()


## Where chord, twist, section and ring all look. Moves no figure.
func set_caret(r_frac: float) -> void:
	caret_r_frac = clampf(r_frac, 0.0, 1.0)
	chord_editor.set_caret(caret_r_frac)
	twist_editor.set_caret(caret_r_frac)
	section_view.set_r_frac(caret_r_frac)
	blade_view.set_caret(caret_r_frac)
	_show_caret()


func _show_caret() -> void:
	section_caption.text = "Section at %d%% of radius" % roundi(caret_r_frac * 100.0)


# ---------------------------------------------------------------------------
# History: the blade plus the hub and pad, which are edits here but not yet in the document. The name
# is not a step, so an undo never retypes it.
# ---------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var blade := doc.to_dictionary()
	blade.erase("name")
	return {"doc": blade, "hub_g": hub_g, "pad_mm": pad_mm}


func _push(snapshot: Dictionary) -> void:
	_undo.append(snapshot)
	if _undo.size() > BladeHistory.MAX_DEPTH:
		_undo.remove_at(0)
	_redo.clear()


## Called by a canvas just before its gesture's first change.
func _record() -> void:
	_push(_snapshot())


## A press that changed nothing leaves no step.
func _commit(before: Dictionary) -> void:
	if _snapshot() != before:
		_push(before)
	_rederive()


func _restore(snapshot: Dictionary) -> void:
	var kept_name := doc.name
	doc = PropellerDocument.from_dictionary(snapshot["doc"])
	doc.name = kept_name
	hub_g = float(snapshot["hub_g"])
	pad_mm = float(snapshot["pad_mm"])
	chord_editor.set_document(doc)
	twist_editor.set_document(doc)
	pitch_offer_open = false
	_rederive()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_Z and (key.ctrl_pressed or key.meta_pressed):
		if key.shift_pressed:
			redo()
		else:
			undo()
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	super(event)


# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------

## Every figure as a number, in the units it is shown in. `thrust_g` and `power_w` are 0 when the
## solve refuses, and `refusal` says why.
func figures() -> Dictionary:
	var at := PropTunnel.point(PropTunnel.geometry_of(doc), rpm, 0.0)
	var mass := BladeGeometry.prop_mass_g(doc, materials, hub_g)
	return {
		"thrust_g": float(at.get("thrust_n", 0.0)) * 1000.0 / 9.80665,
		"power_w": float(at.get("power_w", 0.0)),
		"refusal": String(at.get("reason", "")),
		"mass_g": mass,
		"cg_mm": BladeGeometry.blade_cg_mm(doc),
		"inertia_gcm2": BladeGeometry.blade_inertia_kg_m2(doc, materials) * 1e7,
		"tip_speed_mps": PropStructure.tip_speed_mps(doc, rpm),
		"tip_mach": PropTunnel.tip_mach(doc.diameter_mm * 0.001, rpm),
		"blade_pass_hz": PropStructure.blade_pass_hz(doc, rpm),
		"mount_hz": SoftMount.f_n_hz(pad_mm * 0.001, VibrationModel.tip_mass_kg(motor, mass), mount_spec),
	}


func _set_fig(key: String, text: String, tag: String) -> void:
	(_figs[key] as Label).text = text
	(_figs[key + "_tag"] as Label).text = tag


func _rederive() -> void:
	derive_count += 1
	_syncing = true
	var inches := doc.diameter_mm / PropellerDocument.INCH_TO_MM
	diameter_value.text = "%.1f in" % inches
	pitch_value.text = "%.1f in" % (doc.pitch_mm / PropellerDocument.INCH_TO_MM)
	blades_value.text = str(doc.blades)
	hub_value.text = "%.1f g" % hub_g
	pad_value.text = "%.1f mm" % pad_mm
	_mark_chips(material_row, MATERIALS, doc.material_id)
	var material_name := String(materials.get_material(doc.material_id).get("name", doc.material_id))
	summary_label.text = "%s, from %s. %s%s" % [doc.name if doc.name != "" else "Unnamed prop", source_name,
		material_name, ". Chord assumed." if doc.chord_is_assumed else "."]

	var f := figures()
	var model := "at %d rpm, model" % int(rpm)
	if String(f["refusal"]) != "":
		_set_fig("thrust", "–", String(f["refusal"]))
		_set_fig("power", "–", "")
	else:
		_set_fig("thrust", "%.0f g" % float(f["thrust_g"]), model)
		_set_fig("power", "%.0f W" % float(f["power_w"]), model)
	_set_fig("mass", "%.2f g" % float(f["mass_g"]), "solid section, with hub")
	_set_fig("cg", "%.1f mm" % float(f["cg_mm"]), "from the shaft")
	_set_fig("inertia", "%.1f g·cm²" % float(f["inertia_gcm2"]), "blades only")
	_set_fig("tip_speed", "%.0f m/s" % float(f["tip_speed_mps"]), model)
	_set_fig("tip_mach", "%.2f" % float(f["tip_mach"]), model)
	_set_fig("blade_pass", "%.0f Hz" % float(f["blade_pass_hz"]), model)
	if is_inf(float(f["mount_hz"])):
		_set_fig("mount", "No pad", "motor bolted hard")
	else:
		_set_fig("mount", "%.0f Hz" % float(f["mount_hz"]), "pad natural frequency (est.)")

	thickness_value.text = "%d %%" % roundi(doc.thickness_ratio * 100.0)
	var drawn := not doc.flown_twist().is_empty()
	twist_note.text = TWIST_DRAWN_NOTE if drawn else TWIST_HELIX_NOTE
	(find_child("TwistHelix", true, false) as Button).disabled = not drawn
	measured_toggle.set_pressed_no_signal(not doc.chord_is_assumed)
	pitch_offer.visible = pitch_offer_open and drawn
	undo_button.disabled = _undo.is_empty()
	redo_button.disabled = _redo.is_empty()
	chord_editor.queue_redraw()
	twist_editor.queue_redraw()
	_show_caret()

	blade_view.show_propeller({"specs": {"diameter_inches": inches, "blades": doc.blades}}, doc)
	section_view.set_document(doc)
	_syncing = false
