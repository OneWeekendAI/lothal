class_name TestPropDesigner
extends RefCounted
## PD6: the prop designer's skeleton. The control table below presses the real buttons and reads the
## text on screen, so a control wired to nothing, or a figure that stopped being redrawn, goes red.

const SIZE := Vector2(1280, 720)


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var mats := FrameMaterials.load_default()
	results.append_array(_test_opens_valid(catalog, mats))
	results.append_array(_test_figures_match_their_sources(catalog, mats))
	for row in _control_table():
		results.append_array(_test_control(catalog, mats, row))
	results.append_array(_test_name(catalog, mats))
	results.append_array(_test_limits(catalog, mats))
	results.append_array(_test_authored_scales(catalog, mats))
	results.append_array(_test_mesh_follows(catalog, mats))
	results.append_array(_test_snap_views(catalog, mats))
	results.append_array(_test_no_stress_warning(catalog, mats))
	results.append_array(_test_preset_untouched(catalog, mats))
	results.append_array(_test_shelf_tile(catalog))
	results.append_array(_test_twist_drag(catalog, mats))
	results.append_array(_test_chord_controls(catalog, mats))
	results.append_array(_test_undo(catalog, mats))
	results.append_array(_test_thickness(catalog, mats))
	results.append_array(_test_pitch_offer(catalog, mats))
	results.append_array(_test_caret(catalog, mats))
	results.append_array(_test_monochrome(catalog, mats))
	results.append_array(_test_no_stress_on_new_text(catalog, mats))
	return results


static func _designer(catalog: PartsCatalog, mats: FrameMaterials) -> PropDesigner:
	var d := PropDesigner.new(catalog, mats)
	d.size = SIZE
	return d


## Screen text of every figure, plus every stepper's own value.
static func _screen(d: PropDesigner) -> Dictionary:
	var out := {}
	for key: String in PropDesigner.FIGURE_ROWS:
		out[key] = (d._figs[key] as Label).text
	return out


## control button -> the figures it must move, and those it must leave alone.
static func _control_table() -> Array:
	return [
		{"button": "DiameterPlus", "moves": ["thrust", "power", "mass", "cg", "inertia", "tip_speed", "tip_mach"], "still": ["blade_pass"], "value": "diameter_value"},
		{"button": "DiameterMinus", "moves": ["thrust", "power", "mass", "cg", "inertia", "tip_speed", "tip_mach"], "still": ["blade_pass"], "value": "diameter_value"},
		{"button": "PitchPlus", "moves": ["thrust", "power"], "still": ["mass", "cg", "tip_speed"], "value": "pitch_value"},
		{"button": "PitchMinus", "moves": ["thrust", "power"], "still": ["mass", "cg", "tip_speed"], "value": "pitch_value"},
		{"button": "BladesPlus", "moves": ["thrust", "power", "mass", "inertia", "blade_pass"], "still": ["tip_speed"], "value": "blades_value"},
		{"button": "BladesMinus", "moves": ["thrust", "power", "mass", "inertia", "blade_pass"], "still": ["tip_speed"], "value": "blades_value"},
		{"button": "HubPlus", "moves": ["mass"], "still": ["thrust", "inertia"], "value": "hub_value"},
		{"button": "HubMinus", "moves": ["mass"], "still": ["thrust", "inertia"], "value": "hub_value"},
		{"button": "PadPlus", "moves": ["mount"], "still": ["thrust", "mass"], "value": "pad_value"},
		{"button": "Material_carbon_filled_nylon", "moves": ["mass", "inertia"], "still": ["thrust", "tip_speed"], "value": ""},
		{"button": "Material_pa12_sls", "moves": ["mass", "inertia"], "still": ["thrust", "tip_speed"], "value": ""},
	]


static func _test_control(catalog: PartsCatalog, mats: FrameMaterials, row: Dictionary) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var button := String(row["button"])
	var b := d.find_child(button, true, false) as Button
	out.append(_t("%s exists" % button, b != null))
	if b == null:
		d.free()
		return out
	var before := _screen(d)
	var value_key := String(row["value"])
	var value_before: String = (d.get(value_key) as Label).text if value_key != "" else ""
	b.pressed.emit()
	var after := _screen(d)
	for key: String in row["moves"]:
		out.append(_t("%s moves %s" % [button, key], before[key] != after[key], "%s -> %s" % [before[key], after[key]]))
	for key: String in row["still"]:
		out.append(_t("%s leaves %s alone" % [button, key], before[key] == after[key], "%s -> %s" % [before[key], after[key]]))
	if value_key != "":
		out.append(_t("%s shows its new value" % button, (d.get(value_key) as Label).text != value_before))
	else:
		var chip := b
		out.append(_t("%s reads as chosen" % button, chip.button_pressed))
	d.free()
	return out


static func _num(label: Label) -> float:
	return float(label.text.split(" ")[0])


static func _test_opens_valid(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	for key: String in PropDesigner.FIGURE_ROWS:
		if key == "mount":
			continue
		out.append(_t("opens with non-zero %s" % key, _num(d._figs[key]) > 0.0, (d._figs[key] as Label).text))
	out.append(_t("mount reads a stated value on open", (d._figs["mount"] as Label).text != ""))
	out.append(_t("Save is disabled until saving exists", d.save_button.disabled))
	out.append(_t("Copy specs is disabled until it exists", d.copy_button.disabled))
	out.append(_t("a new prop has no id to overwrite", d.doc.id == ""))
	out.append(_t("a new prop claims no vendor mass", d.doc.published_mass_g == 0.0))
	out.append(_t("hub starts above zero", d.hub_g > 0.0))
	d.free()
	return out


## Every figure on screen against its own source, called here with the same inputs.
static func _test_figures_match_their_sources(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.set_pad_mm(2.0)
	var doc := d.doc
	var at := PropTunnel.point(PropTunnel.geometry_of(doc), d.rpm, 0.0)
	var mass := BladeGeometry.prop_mass_g(doc, mats, d.hub_g)
	var want := {
		"thrust": "%.0f g" % (float(at.thrust_n) * 1000.0 / 9.80665),
		"power": "%.0f W" % float(at.power_w),
		"mass": "%.2f g" % mass,
		"cg": "%.1f mm" % BladeGeometry.blade_cg_mm(doc),
		"inertia": "%.1f g·cm²" % (BladeGeometry.blade_inertia_kg_m2(doc, mats) * 1e7),
		"tip_speed": "%.0f m/s" % (d.rpm * TAU / 60.0 * doc.radius_mm() * 0.001),
		"tip_mach": "%.2f" % PropTunnel.tip_mach(doc.diameter_mm * 0.001, d.rpm),
		"blade_pass": "%.0f Hz" % (d.rpm / 60.0 * doc.blades),
		"mount": "%.0f Hz" % SoftMount.f_n_hz(0.002, VibrationModel.tip_mass_kg(d.motor, mass), {}),
	}
	for key: String in want:
		out.append(_t("%s on screen equals its source" % key, (d._figs[key] as Label).text == want[key],
			"%s vs %s" % [(d._figs[key] as Label).text, want[key]]))
	d.free()
	return out


static func _test_name(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.name_field.text_changed.emit("Hill climber")
	out.append(_t("typing a name reaches the document", d.doc.name == "Hill climber"))
	out.append(_t("and the summary line", d.summary_label.text.begins_with("Hill climber")))
	d.free()
	return out


static func _test_limits(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.set_blades(99)
	out.append(_t("blades stop at the top of the range", d.doc.blades == PropDesigner.BLADES_RANGE.y))
	d.set_blades(0)
	out.append(_t("blades stop at the bottom of the range", d.doc.blades == PropDesigner.BLADES_RANGE.x))
	d.set_pad_mm(1000.0)
	out.append(_t("pad stops at the motor's boss height",
		is_equal_approx(d.pad_mm, MotorMesh.max_soft_mount_m(d.motor) * 1000.0), str(d.pad_mm)))
	d.set_hub_g(-5.0)
	out.append(_t("hub stops at zero", d.hub_g == 0.0))
	for i in 200:
		d.step_diameter(-PropDesigner.STEP_IN)
	out.append(_t("diameter stops at the bottom of the range",
		is_equal_approx(d.doc.diameter_mm, PropDesigner.DIAMETER_RANGE_IN.x * PropellerDocument.INCH_TO_MM)))
	out.append(_t("the smallest prop still has figures", _num(d._figs["thrust"]) >= 0.0 and (d._figs["thrust"] as Label).text != "–",
		(d._figs["thrust"] as Label).text))
	d.free()
	return out


static func _test_authored_scales(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.doc.chord_is_assumed = false
	d.doc.chord = PackedFloat64Array([0.1, 10.0, 1.0, 5.0])
	var d0 := d.doc.diameter_mm
	d.step_diameter(PropDesigner.STEP_IN)
	var k := d.doc.diameter_mm / d0
	out.append(_t("a drawn planform scales with diameter",
		is_equal_approx(d.doc.chord[1], 10.0 * k) and is_equal_approx(d.doc.chord[3], 5.0 * k)))
	var before := d.doc.chord.duplicate()
	d.set_blades(d.doc.blades + 1)
	out.append(_t("and a blade count leaves it alone", d.doc.chord == before))
	d.free()
	return out


## The suite has no scene tree, so BladeView3D holds no mesh of its own here. What the view was
## handed is rebuilt into a real PropellerMesh, the same call the view makes; the window capture
## covers the view drawing it.
static func _mesh_of(d: PropDesigner) -> PropellerMesh:
	var mesh := PropellerMesh.new()
	mesh.rebuild(d.blade_view._prop, d.blade_view._document)
	return mesh


static func _test_mesh_follows(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var m0 := _mesh_of(d)
	d.step_diameter(1.0)
	var m1 := _mesh_of(d)
	out.append(_t("diameter moves the mesh", m1.radius_m > m0.radius_m
		and is_equal_approx(m1.radius_m, d.doc.radius_mm() * 0.001), "%f -> %f" % [m0.radius_m, m1.radius_m]))
	out.append(_t("and the view's framing", is_equal_approx(d.blade_view.radius_m, m1.radius_m)))
	d.set_blades(m1.blade_count + 1)
	var m2 := _mesh_of(d)
	out.append(_t("blades move the mesh", m2.blade_count == m1.blade_count + 1))
	out.append(_t("the blade view has a world of its own, so no other blade shows in it",
		d.blade_view._viewport.own_world_3d))
	out.append(_t("the section draws the designer's document", d.section_view.document == d.doc))
	m0.free()
	m1.free()
	m2.free()
	d.free()
	return out


static func _test_snap_views(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	for view_id: String in PropDesigner.VIEW_LABELS:
		var d := _designer(catalog, mats)
		var b := d.find_child("View_" + view_id, true, false) as Button
		out.append(_t("%s view button exists" % view_id, b != null))
		if b != null:
			d.blade_view.yaw = 1.234
			d.blade_view.pitch = 0.0123
			b.pressed.emit()
			var want: Vector2 = BladeView3D.VIEWS[view_id]
			out.append(_t("%s view button turns the camera" % view_id,
				is_equal_approx(d.blade_view.yaw, want.x) and is_equal_approx(d.blade_view.pitch, want.y)))
		d.free()
	return out


## The owner has not decided how the root factor reads; it must not reach this screen.
static func _test_no_stress_warning(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var text := d.summary_label.text
	for key: String in PropDesigner.FIGURE_ROWS:
		text += " " + String(PropDesigner.FIGURE_NAMES[key]) + " " + (d._figs[key] as Label).text \
			+ " " + (d._figs[key + "_tag"] as Label).text
	var low := text.to_lower()
	out.append(_t("no safety factor or break warning on screen",
		not ("factor" in low or "break" in low or "stress" in low or "overspeed" in low), text))
	d.free()
	return out


## Editing the designer's blade never reaches the catalog's record.
static func _test_preset_untouched(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var id := String(DroneClass.parts_for(PropDesigner.FALLBACK_CLASS)["propeller"])
	var before := JSON.stringify(catalog.get_part(id))
	var d := _designer(catalog, mats)
	d.step_diameter(1.0)
	d.set_blades(5)
	d.set_blade_material("pa12_sls")
	out.append(_t("the shelf prop's record is unchanged", JSON.stringify(catalog.get_part(id)) == before))
	d.free()
	return out


static func _test_shelf_tile(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = SIZE
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("propeller")
	var tile := ds.shelf.find_child("AddProp", true, false) as BaseButton
	out.append(_t("the prop shelf ends with a + tile", tile != null))
	if tile != null:
		tile.pressed.emit()
	out.append(_t("pressing it opens the prop designer over the Design Space",
		ds.prop_designer != null and ds.prop_designer.get_parent() == ds))
	if ds.prop_designer != null:
		var fitted := ds.session.build(catalog)
		out.append(_t("it starts from this drone's prop",
			is_equal_approx(ds.prop_designer.doc.diameter_mm,
				float(fitted.propeller["specs"]["diameter_inches"]) * PropellerDocument.INCH_TO_MM)
				and ds.prop_designer.doc.blades == int(fitted.propeller["specs"]["blades"])))
		ds.open_prop_designer()
		ds.prop_designer.close()
	out.append(_t("Back closes it and the Design Space forgets it", ds.prop_designer == null))
	ds.free()
	return out


# ---------------------------------------------------------------------------
# PD7: chord and twist canvases
# ---------------------------------------------------------------------------

## Raises one mid-blade station by a real pixel path through the canvas.
static func _drag_twist(d: PropDesigner, deg_up: float) -> void:
	var e := d.twist_editor
	e.size = Vector2(260, 104)
	var pts := PlanformEdits.points(e.table())
	var i: int = pts.size() - 2
	e.drag_station_to(i, e.to_pixels(float(pts[i][0]), rad_to_deg(float(pts[i][1])) + deg_up))


static func _j0(d: PropDesigner) -> float:
	return float(PropTunnel.axial_sweep(PropTunnel.geometry_of(d.doc), d.rpm).get("j0", -1.0))


static func _blade_vertices(d: PropDesigner) -> PackedVector3Array:
	var m := _mesh_of(d)
	var blade := m.get_node("Blade_0") as MeshInstance3D
	var v: PackedVector3Array = blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	m.free()
	return v


static func _test_twist_drag(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	out.append(_t("opens on the helix", d.doc.flown_twist().is_empty() and d.twist_note.text == PropDesigner.TWIST_HELIX_NOTE))
	var j0 := _j0(d)
	var mesh := _blade_vertices(d)
	var thrust: String = (d._figs["thrust"] as Label).text
	_drag_twist(d, 6.0)
	out.append(_t("a drag authors the twist", not d.doc.flown_twist().is_empty()))
	out.append(_t("and the page says so", d.twist_note.text == PropDesigner.TWIST_DRAWN_NOTE))
	out.append(_t("twist drag moves tunnel J0", absf(_j0(d) - j0) > 1e-3, "%f -> %f" % [j0, _j0(d)]))
	out.append(_t("twist drag moves the mesh", _blade_vertices(d) != mesh))
	out.append(_t("twist drag redraws the thrust figure's source", (d._figs["thrust"] as Label).text
		== "%.0f g" % (float(PropTunnel.point(PropTunnel.geometry_of(d.doc), d.rpm, 0.0).thrust_n) * 1000.0 / 9.80665), thrust))
	var count := d.doc.twist.size()
	d.set_caret(0.33)
	d.add_twist_station()
	out.append(_t("+ station adds a pair", d.doc.twist.size() == count + 2))
	d.remove_twist_station()
	out.append(_t("- station removes it", d.doc.twist.size() == count))
	d.free()
	return out


static func _test_chord_controls(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var e := d.chord_editor
	e.size = Vector2(260, 104)
	var count := d.doc.chord.size()
	d.set_caret(0.333)
	d.add_chord_station()
	out.append(_t("chord + station", d.doc.chord.size() == count + 2))
	d.remove_chord_station()
	out.append(_t("chord - station", d.doc.chord.size() == count))
	out.append(_t("generated chord reads assumed", d.doc.chord_is_assumed and not d.measured_toggle.button_pressed))
	var mass := d.figures()["mass_g"] as float
	e.drag_station_to(20, e.to_pixels(float(d.doc.chord[40]), d.doc.chord[41] * 1.3))
	out.append(_t("chord drag moves mass", d.figures()["mass_g"] != mass))
	out.append(_t("a drawn chord stops being assumed, and the toggle shows it",
		not d.doc.chord_is_assumed and d.measured_toggle.button_pressed))
	d.measured_toggle.toggled.emit(false)
	out.append(_t("toggle sets it back", d.doc.chord_is_assumed and "Chord assumed" in d.summary_label.text))
	d.free()
	return out


static func _test_undo(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	out.append(_t("nothing to undo on open", d.undo_button.disabled and d.redo_button.disabled))
	var f0 := d.figures()
	var j0 := _j0(d)
	var chord0 := d.doc.chord
	_drag_twist(d, 6.0)
	_drag_twist(d, 3.0)
	out.append(_t("a gesture is one step", d._undo.size() == 1, str(d._undo.size())))
	var f1 := d.figures()
	(d.find_child("Undo", true, false) as Button).pressed.emit()
	out.append(_t("undo restores every figure bit-exact", d.figures() == f0, str(d.figures())))
	out.append(_t("undo restores J0 bit-exact", _j0(d) == j0))
	out.append(_t("undo restores the chord", d.doc.chord == chord0))
	out.append(_t("the canvases hold the restored blade", d.twist_editor.document == d.doc and d.chord_editor.document == d.doc))
	out.append(_t("the views hold it too", d.section_view.document == d.doc and d.blade_view._document == d.doc))
	(d.find_child("Redo", true, false) as Button).pressed.emit()
	out.append(_t("redo restores it bit-exact", d.figures() == f1))
	d.free()

	d = _designer(catalog, mats)
	var hub := d.hub_g
	d.set_hub_g(hub + 1.0)
	d.set_prop_name("Kept")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Z
	key.ctrl_pressed = true
	d._unhandled_key_input(key)
	out.append(_t("Ctrl-Z undoes a hub edit", d.hub_g == hub))
	out.append(_t("and leaves the typed name", d.doc.name == "Kept"))
	key.shift_pressed = true
	d._unhandled_key_input(key)
	out.append(_t("Ctrl-Shift-Z redoes it", d.hub_g == hub + 1.0))
	d.free()

	d = _designer(catalog, mats)
	d.step_diameter(100.0)
	var steps := d._undo.size()
	d.step_diameter(1.0)
	out.append(_t("a press at the limit leaves no step", d._undo.size() == steps))
	d.free()
	return out


static func _test_thickness(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var f0 := d.figures()
	var stress0 := PropStructure.assess(d.doc, mats, d.rpm)
	(d.find_child("ThicknessPlus", true, false) as Button).pressed.emit()
	var f1 := d.figures()
	var stress1 := PropStructure.assess(d.doc, mats, d.rpm)
	out.append(_t("thickness moves mass", f1["mass_g"] != f0["mass_g"]))
	out.append(_t("thickness moves stress", stress1 != stress0))
	out.append(_t("thickness leaves thrust bit-exact", f1["thrust_g"] == f0["thrust_g"]))
	out.append(_t("thickness leaves power bit-exact", f1["power_w"] == f0["power_w"]))
	var note := d.find_child("ThicknessNote", true, false) as Label
	out.append(_t("and says so", note != null and note.text == PropDesigner.THICKNESS_NOTE))
	out.append(_t("thickness shows its value", d.thickness_value.text == "11 %", d.thickness_value.text))
	d.free()
	return out


static func _test_pitch_offer(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.step_pitch(0.5)
	out.append(_t("a helix blade is not offered anything", not d.pitch_offer.visible))
	_drag_twist(d, 6.0)
	var f := d.figures()
	var j0 := _j0(d)
	var table := d.doc.twist
	d.step_pitch(0.5)
	out.append(_t("on drawn twist, pitch stays authored", d.doc.twist == table and d.figures()["thrust_g"] == f["thrust_g"]))
	out.append(_t("and the line appears", d.pitch_offer.visible))
	(d.find_child("PitchKeepDrawn", true, false) as Button).pressed.emit()
	out.append(_t("Keep drawn closes it, twist kept", not d.pitch_offer.visible and d.doc.twist == table))
	d.step_pitch(0.5)
	(d.find_child("PitchUseHelix", true, false) as Button).pressed.emit()
	out.append(_t("Use helix returns to the helix", d.doc.flown_twist().is_empty() and not d.pitch_offer.visible))
	out.append(_t("and J0 moves", _j0(d) != j0, "%f" % j0))
	out.append(_t("the page says hover hides twist", (d.find_child("TwistCapNote", true, false) as Label).text == PropDesigner.TWIST_CAP_NOTE))
	d.undo()
	out.append(_t("undo brings the drawing back", d.doc.twist == table))
	d.free()
	return out


static func _test_caret(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var f := d.figures()
	var steps := d._undo.size()
	d.twist_editor.set_caret(0.4)
	out.append(_t("the twist canvas moves the chord canvas's caret", is_equal_approx(d.chord_editor.caret_r_frac, 0.4)))
	out.append(_t("and the section", is_equal_approx(d.section_view.r_frac, 0.4)))
	out.append(_t("and the ring", is_equal_approx(d.blade_view._caret_r_frac, 0.4)))
	out.append(_t("and the caption", "40%" in d.section_caption.text, d.section_caption.text))
	d.chord_editor.set_caret(0.6)
	out.append(_t("the chord canvas moves the twist canvas's caret", is_equal_approx(d.twist_editor.caret_r_frac, 0.6)))
	out.append(_t("a caret moves no figure and leaves no step", d.figures() == f and d._undo.size() == steps))
	d.free()
	return out


## The designers are monochrome; the old room keeps its blue through the same classes.
static func _test_monochrome(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var inks := {
		"ring": d.blade_view.caret_ink, "section": d.section_view.ink, "section chord line": d.section_view.chord_ink,
		"chord canvas": d.chord_editor.ink, "chord caret": d.chord_editor.caret_ink, "chord hover": d.chord_editor.hover_ink, "twist canvas": d.twist_editor.ink,
	}
	for key: String in inks:
		var c: Color = inks[key]
		out.append(_t("%s ink is grey" % key, c.r == c.g and c.g == c.b, str(c)))
	d.free()
	return out


static func _test_no_stress_on_new_text(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var text := "%s %s %s" % [d.twist_note.text, PropDesigner.PITCH_OFFER_NOTE, PropDesigner.THICKNESS_NOTE]
	var low := text.to_lower()
	out.append(_t("no break warning in the blade section's text",
		not ("factor" in low or "break" in low or "stress" in low or "overspeed" in low), text))
	d.free()
	return out
