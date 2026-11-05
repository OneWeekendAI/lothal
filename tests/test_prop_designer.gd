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
	results.append_array(_test_tunnel(catalog, mats))
	results.append_array(_test_measured_dots(catalog, mats))
	results.append_array(_test_tunnel_colours(catalog, mats))
	results.append_array(_test_stand(catalog, mats))
	results.append_array(_test_structure(catalog, mats))
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


## The root factor stays off the figures column; it reads only, neutrally, on the Structure tab.
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


# ---------------------------------------------------------------------------
# PD8: the wind tunnel tab
# ---------------------------------------------------------------------------

static func _tunnel(catalog: PartsCatalog, mats: FrameMaterials) -> PropDesigner:
	var d := _designer(catalog, mats)
	d.show_tab("tunnel")
	return d


## The designer as a named UIUC size, reached through the real steppers' setters.
static func _sized(d: PropDesigner, dia_in: float, pitch_in: float, blades: int) -> void:
	d.doc.diameter_mm = dia_in * PropellerDocument.INCH_TO_MM
	d.doc.pitch_mm = pitch_in * PropellerDocument.INCH_TO_MM
	d.set_blades(blades)


static func _test_tunnel(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _tunnel(catalog, mats)
	var t := d.tunnel
	var g := PropTunnel.geometry_of(d.doc)

	# The subtitle, in every state a user can reach.
	var check_subtitle := func(state: String) -> void:
		out.append(_t("subtitle on screen: " + state, t.subtitle.visible and t.visible and t.subtitle.text == PropTunnelPanel.SUBTITLE
			and t.find_child("TunnelSubtitle", true, false) == t.subtitle, t.subtitle.text))
	check_subtitle.call("default")
	for m: String in PropTunnelPanel.METRICS:
		t.set_metric(m)
		check_subtitle.call(m)
	t.set_metric("thrust")
	t.set_angle(45.0)
	check_subtitle.call("mid-edgewise")
	t.set_angle(120.0)
	check_subtitle.call("refused")

	# A refusal renders as nothing but its reason.
	out.append(_t("descent is refused, not plotted", t.chart.points.is_empty() and t.warning_label.text == PropTunnel.REASON_DESCENT, t.warning_label.text))
	out.append(_t("refused: no dots, no shaded blade", t.chart.dots.is_empty() and t.shade_table.is_empty()))
	t.set_angle(0.0)

	# The curve is the sweep: one point per sweep point, ending where thrust does.
	var sw := PropTunnel.sweep(g, d.rpm, 0.0)
	out.append(_t("chart points equal the sweep's", t.chart.points.size() == (sw.points as Array).size(), "%d vs %d" % [t.chart.points.size(), (sw.points as Array).size()]))
	out.append(_t("sweep at 0 deg is the axial sweep", (sw.points as Array).size() == (PropTunnel.axial_sweep(g, d.rpm).points as Array).size()))
	out.append(_t("default curve ends at thrust zero", sw.end == "zero_thrust" and t.note_label.text.contains(PropTunnel.END_ZERO_THRUST), t.note_label.text))
	var all_positive := true
	for p: Dictionary in t.chart.points:
		all_positive = all_positive and float(p.y) > 0.0
		all_positive = all_positive and float(p.x) <= float(sw.j0)
	out.append(_t("no plotted point past the end", all_positive))
	var mid: Dictionary = t.chart.points[4]
	var direct := PropTunnel.point(g, d.rpm, 0.2 * d.rpm / 60.0 * float(g.diameter_m))
	out.append(_t("a plotted thrust equals the direct solve in g",
		absf(float(mid.y) - float(direct.thrust_n) * PropTunnelPanel.G_PER_N) < 1e-9, "%f" % float(mid.y)))
	t.set_metric("power")
	out.append(_t("power tab plots power", absf(float(t.chart.points[4].y) - float(direct.power_w)) < 1e-9))
	t.set_metric("efficiency")
	out.append(_t("efficiency tab plots J T / power form", absf(float(t.chart.points[4].y)
		- float(direct.thrust_n) * 0.2 * d.rpm / 60.0 * float(g.diameter_m) / float(direct.power_w)) < 1e-9))

	# Off axis: thrust and power only, and the J speeds are split by the angle.
	t.set_angle(45.0)
	out.append(_t("off axis has no efficiency curve, and says so", t.chart.points.is_empty() and t.warning_label.text == PropTunnelPanel.NOTE_NO_EFFICIENCY))
	t.set_metric("thrust")
	var v: float = 0.2 * d.rpm / 60.0 * float(g.diameter_m)
	var at45 := PropTunnel.point(g, d.rpm, v * cos(PI / 4.0), v * sin(PI / 4.0))
	out.append(_t("45 deg point equals the direct solve", absf(float(t.chart.points[4].y) - float(at45.thrust_n) * PropTunnelPanel.G_PER_N) < 1e-6))
	out.append(_t("off axis says thrust and power only", t.note_label.text.contains(PropTunnelPanel.NOTE_OFF_AXIS), t.note_label.text))
	t.set_angle(90.0)
	var flagged := t.chart.segment_counts().y
	out.append(_t("edgewise past the reach goes dashed with its reason", flagged > 0 and t.warning_label.text != "" , "%d, %s" % [flagged, t.warning_label.text]))
	var flag_count := 0
	for p: Dictionary in PropTunnel.sweep(g, d.rpm, 90.0).points:
		flag_count += 1 if String(p.flag) != "" else 0
	out.append(_t("every flagged point is on the dashed stretch", flag_count > 0 and flagged >= flag_count - 1, "%d %d" % [flag_count, flagged]))
	t.set_angle(0.0)

	# Controls.
	var before := float(t.chart.points[4].y)
	d.step_rpm(PropDesigner.STEP_RPM)
	out.append(_t("rpm control moves the curve", float(t.chart.points[4].y) != before))
	out.append(_t("rpm control moves the figures too", (d._figs["blade_pass"] as Label).text.contains("Hz") and t.rpm_value.text == "%d rpm" % roundi(d.rpm)))
	var shade_before := t.shade_table
	t.set_look_j(0.5)
	out.append(_t("looked-at J moves the shading", t.shade_table != shade_before and t.chart.caret_x == 0.5))
	var alpha_shade := t.shade_table
	t.set_shade("thrust")
	out.append(_t("shade choice moves the shading", t.shade_table != alpha_shade))
	out.append(_t("shading reaches the blade's own mesh", _mesh_greys(d)))
	t.set_look_j(99.0)
	out.append(_t("looked-at J cannot pass the curve's end", t.look_j <= float(t.result.j0)))
	d.step_diameter(1.0)
	out.append(_t("a blade change reruns the active tab", absf(float(t.result.points[1].j) - PropTunnel.J_STEP) < 1e-9
		and t.result == PropTunnel.sweep(PropTunnel.geometry_of(d.doc), d.rpm, 0.0)))
	d.show_tab("figures")
	out.append(_t("figures tab clears the shading", _plain_mesh(d) and not t.visible and d.figures_box.visible))
	d.free()
	return out


## The view's own mesh exists only in the tree, so this builds one from what the view holds. The
## capture is what sees the view hand it over.
static func _blade_colors(d: PropDesigner) -> PackedColorArray:
	var mesh := PropellerMesh.new()
	mesh.station_shade = d.blade_view._station_shade
	mesh.rebuild({"specs": {"diameter_inches": d.doc.diameter_mm / PropellerDocument.INCH_TO_MM, "blades": d.doc.blades}}, d.doc)
	var c: Variant = (mesh.get_node("Blade_0") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	mesh.free()
	return PackedColorArray() if c == null else c


static func _mesh_greys(d: PropDesigner) -> bool:
	var c := _blade_colors(d)
	if c.is_empty():
		return false
	var lo := 1.0
	var hi := 0.0
	for x in c:
		lo = minf(lo, x.v)
		hi = maxf(hi, x.v)
		if x.s > 0.001:
			return false
	return hi - lo > 0.2


static func _plain_mesh(d: PropDesigner) -> bool:
	return _blade_colors(d).is_empty()


static func _test_measured_dots(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _tunnel(catalog, mats)
	var t := d.tunnel
	out.append(_t("no dots on a shelf 5 in that matches no table", t.chart.dots.is_empty() and t.dots_label.text == "", t.dots_label.text))
	for row: Array in [[4.2, 4.0, 2, "APC FF 4.2x4", 8067], [5.0, 3.75, 2, "DA4002 5x3.75", 6045], [9.0, 4.5, 2, "APC E 9x4.5", 6018]]:
		_sized(d, row[0], row[1], row[2])
		out.append(_t("dots on %s" % row[3], not t.chart.dots.is_empty() and t.dots_label.text.contains("measured") and t.dots_label.text.contains(row[3]), t.dots_label.text))
	_sized(d, 4.2, 4.0, 2)
	d.rpm = 8067.0
	t.set_metric("efficiency")
	var table: Array = PropMeasured.match_for(d.doc).rows
	out.append(_t("a dot is the table's row", absf(t.chart.dots[3].x - float(table[3][0])) < 1e-6 and absf(t.chart.dots[3].y - float(table[3][1 + 2])) < 1e-6))
	out.append(_t("tested rpm: no scaling claimed", not t.dots_label.text.contains("scaled"), t.dots_label.text))
	t.set_metric("thrust")
	var n := 8067.0 / 60.0
	var want := float(table[3][1]) * 1.225 * n * n * pow(d.doc.diameter_mm * 0.001, 4.0) * PropTunnelPanel.G_PER_N
	out.append(_t("a thrust dot is Ct in grams", absf(t.chart.dots[3].y - want) < 1e-3, "%f vs %f" % [t.chart.dots[3].y, want]))
	var fence := t.chart.data_range()
	var lowest := INF
	for dot in t.chart.dots:
		lowest = minf(lowest, dot.y)
	out.append(_t("the frame holds a measured dot below zero thrust", lowest < 0.0 and fence.position.y <= lowest, "%f, %f" % [lowest, fence.position.y]))
	d.step_rpm(5000.0)
	out.append(_t("another rpm says it is scaled", t.dots_label.text.contains("scaled")))
	t.set_angle(45.0)
	out.append(_t("no dots off axis: the tables are straight-on", t.chart.dots.is_empty() and t.dots_label.text == ""))
	t.set_angle(0.0)
	d.set_blades(3)
	out.append(_t("no dots on another blade count", t.chart.dots.is_empty()))
	d.set_blades(2)
	_sized(d, 4.4, 4.0, 2)
	out.append(_t("no dots on another diameter", t.chart.dots.is_empty()))
	_sized(d, 4.2, 4.2, 2)
	out.append(_t("no dots on another pitch", t.chart.dots.is_empty()))
	d.free()
	return out


static func _test_tunnel_colours(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _tunnel(catalog, mats)
	var low := "%s %s %s %s" % [d.tunnel.warning_label.text, d.tunnel.note_label.text, PropTunnelPanel.SUBTITLE, d.tunnel.station_label.text]
	low = low.to_lower()
	out.append(_t("no break warning on the tunnel tab", not ("factor" in low or "break" in low or "stress" in low or "overspeed" in low), low))
	out.append(_t("no flow-field words on the tab", not ("streamline" in low or "smoke" in low or "pressure" in low), low))
	d.free()
	return out


static func _near_eq(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-9 * maxf(absf(b), 1.0)


static func _test_stand(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.step_diameter(0.5)
	d.step_pitch(0.5)
	d.show_tab("stand")
	var s := d.stand
	out.append(_t("stand: shows only on its tab", s.visible and not d.figures_box.visible and not d.tunnel.visible))
	# The same parts, built the ordinary way.
	var parts := s.parts()
	var c := s.bench_catalog()
	var rec := s.motor_record().duplicate(true)
	rec["part_id"] = MotorBench.BENCH_MOTOR_ID
	c.by_id[MotorBench.BENCH_MOTOR_ID] = rec
	var b := Build.from_ids(c, parts.frame, MotorBench.BENCH_MOTOR_ID, PropStandPanel.BENCH_PROP_ID, parts.battery)
	var voc := b.resolve_open_circuit_v(Build.AT_NOMINAL)
	var p := b.uncapped_point(1.0, voc)
	out.append(_t("stand: full-throttle thrust equals a Build with this prop",
		_near_eq(float(s.result.max_thrust_g), float(p.thrust_n) / Build.GRAVITY_MPS2 * 1000.0)))
	out.append(_t("stand: full-throttle current equals a Build with this prop",
		_near_eq(float(s.result.max_current_a), float(p.pack_current_a))))
	var with_default := MotorBench.sweep_of_record(s.motor_record(), {"frame": parts.frame, "battery": parts.battery}, {}, catalog)
	out.append(_t("stand: not the default prop's result",
		absf(float(s.result.max_thrust_g) - float(with_default.max_thrust_g)) > 1.0,
		"%s vs %s" % [s.result.max_thrust_g, with_default.max_thrust_g]))
	out.append(_t("stand: the flown record weighs blades plus hub", _near_eq(float(d.flyable_record("x").mass_g), BladeGeometry.prop_mass_g(d.doc, mats, d.hub_g))))
	out.append(_t("stand: flying it does not stamp the open document", d.doc.published_mass_g == 0.0))
	out.append(_t("stand: Limited by line on screen", s.limited_label.text.begins_with("Limited by:"), s.limited_label.text))
	out.append(_t("stand: the shelf catalog never gets this prop", catalog.get_part(PropStandPanel.BENCH_PROP_ID).is_empty()))
	# Pack swap reruns, through the picker's own signal.
	var before_runs := s.run_count
	var before_a := float(s.result.max_current_a)
	var before_text := s.result_label.text
	var moved := false
	for i in range(1, s.pack_option.item_count):
		s.pack_option.select(i)
		s.pack_option.item_selected.emit(i)
		moved = moved or absf(float(s.result.max_current_a) - before_a) > 0.01
	out.append(_t("stand: pack picker reruns", s.run_count > before_runs and moved))
	out.append(_t("stand: screen follows the pack", s.result_label.text != before_text, s.result_label.text))
	s.pack_option.select(0)
	s.pack_option.item_selected.emit(0)
	out.append(_t("stand: back to this drone's pack restores it", _near_eq(float(s.result.max_current_a), before_a)))
	s.pick_pack(String(s.pack_ids()[1]))
	out.append(_t("stand: the picker shows the pack in use", String(s.pack_option.get_selected_metadata()) == s.pack_pick))
	s.pick_pack(PropStandPanel.DRONE)
	# Motor swap reruns.
	var moved_m := false
	for i in range(1, s.motor_option.item_count):
		s.motor_option.select(i)
		s.motor_option.item_selected.emit(i)
		moved_m = moved_m or (not s.result.is_empty() and absf(float(s.result.max_current_a) - before_a) > 0.01)
	out.append(_t("stand: motor picker reruns", moved_m))
	s.pick_motor(PropStandPanel.DRONE)
	# A prop edit reruns; three views, one chart.
	var t0 := float(s.result.max_thrust_g)
	d.step_diameter(0.5)
	out.append(_t("stand: a prop edit reruns", absf(float(s.result.max_thrust_g) - t0) > 0.1))
	for v: String in PropStandPanel.VIEWS:
		s.set_view(v)
		out.append(_t("stand: one chart on view " + v, s.charts.charts.size() == 1))
	out.append(_t("stand: views differ", String(s.charts.charts[0].title) == "g per watt"))
	d.free()
	return out


static func _test_structure(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.show_tab("structure")
	var s := d.structure
	var want := PropStructure.assess(d.doc, mats, d.rpm)
	out.append(_t("structure: factor on screen is PropStructure's", (s.figs["factor"] as Label).text == "%.2f" % float(want.factor)))
	out.append(_t("structure: stress on screen is PropStructure's", (s.figs["stress"] as Label).text == "%.0f MPa" % float(want.stress_mpa)))
	out.append(_t("structure: flex on screen is PropStructure's", (s.figs["flex"] as Label).text == "%.1f mm" % float(want.flex_mm)))
	for key: String in ["stress", "factor", "overspeed", "flex"]:
		out.append(_t("structure: %s labelled an estimate" % key, "(est.)" in (s.figs[key + "_tag"] as Label).text))
	out.append(_t("structure: the neutral line is on screen", s.note_label.text == PropStructurePanel.NEUTRAL_NOTE))
	var f0 := (s.figs["balance"] as Label).text
	s.set_heavy(50.0)
	out.append(_t("structure: heavy blade moves the balance", (s.figs["balance"] as Label).text != f0))
	s.set_details(false)
	out.append(_t("structure: details closed by default", not s.details_label.visible))
	s.set_details(true)
	out.append(_t("structure: details name the root t/c and its source",
		PropStructure.ROOT_THICKNESS_SOURCE in s.details_label.text, s.details_label.text))
	# Warning: Mach only, either side of its stated threshold. Factor far under and far over 1: none.
	var mach_rpm := PropTunnel.MACH_FLAG * 340.3 * 60.0 / (PI * d.doc.diameter_mm * 0.001)
	d.rpm = mach_rpm * 0.99
	d._rederive()
	out.append(_t("structure: no warning just under Mach 0.7", s.warning_label.text == "" and not s.warning_label.visible))
	d.rpm = mach_rpm * 1.01
	d._rederive()
	out.append(_t("structure: warning just over Mach 0.7", s.warning_label.text == PropTunnel.FLAG_MACH and s.warning_label.visible))
	d.rpm = 2000.0
	d._rederive()
	out.append(_t("structure: no warning with factor well over 1", float(s.last.factor) > 1.0 and s.warning_label.text == ""))
	d.rpm = minf(mach_rpm * 0.99, float(PropStructure.overspeed_rpm(d.doc, mats, 2000.0)) * 1.3)
	d._rederive()
	out.append(_t("structure: no warning with factor under 1", float(s.last.factor) < 1.0 and s.warning_label.text == "",
		"f %s m %s" % [s.last.factor, s.last.tip_mach]))
	var ink := s.warning_label.get_theme_color("font_color")
	out.append(_t("structure: warning is amber", ink == DesignSpace.WARN_INK))
	var low := (s.note_label.text + " " + s.details_label.text).to_lower()
	out.append(_t("structure: no will-break wording", not ("will break" in low or "unsafe" in low or "fail" in low), low))
	d.free()
	return out

