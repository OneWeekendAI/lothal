class_name TestPropExport
## PD12: the file, the refusals and the sheet. Reads the STL back off disk rather than the triangles
## the writer was handed, so bore and volume are facts about the file.

const TMP := "user://pd12_test.stl"
const TMP_TXT := "user://pd12_test.txt"
const SHELF_8 := "prop_8x45x3"


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new("prop export: %s" % name, ok, detail)


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var mats := FrameMaterials.load_default()
	results.append_array(_test_broken_meshes(catalog))
	results.append_array(_test_blade_count(catalog))
	results.append_array(_test_file_geometry(catalog))
	results.append_array(_test_volume(catalog, mats))
	results.append_array(_test_refusals(catalog))
	results.append_array(_test_sheet(catalog, mats))
	results.append_array(_test_panel(catalog, mats))
	DirAccess.remove_absolute(TMP)
	DirAccess.remove_absolute(TMP_TXT)
	return results


static func _good(catalog: PartsCatalog) -> PropellerDocument:
	var doc := PropellerDocument.from_catalog_prop(catalog.get_part(SHELF_8))
	doc.thickness_ratio = 0.15
	doc.name = "Eight inch"
	return doc


## All the vertices and the facet list, from the file's own text.
static func _read_stl(path: String) -> Array:
	var tris: Array = []
	var cur := PackedVector3Array()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("vertex "):
			var p := l.split(" ", false)
			cur.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
			if cur.size() == 3:
				tris.append(cur)
				cur = PackedVector3Array()
	return tris


## The broken ones first: a green here means nothing unless these go red.
static func _test_broken_meshes(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := PropExport.build(_good(catalog), 5.4)
	out.append(_t("the good solid passes, with facets in every body", bool(s.ok) and (s.bodies as Array).size() == 4
		and (s.bodies as Array).all(func(b): return (b as Array).size() > 12), String(s.reason)))
	for i in (s.bodies as Array).size():
		var bodies: Array = (s.bodies as Array).duplicate()
		var holed: Array = (bodies[i] as Array).duplicate()
		holed.remove_at(int(holed.size() * 0.5))
		bodies[i] = holed
		var report := StlWriter.check_bodies(bodies)
		out.append(_t("body %d with a face deleted is refused" % i, not bool(report.ok), str(report.reasons)))
		DirAccess.remove_absolute(TMP)
		var w := StlWriter.write_bodies("broken", bodies, TMP)
		out.append(_t("body %d with a face deleted writes no file" % i, not bool(w.ok) and not FileAccess.file_exists(TMP)))
	var flipped: Array = (s.bodies as Array).duplicate()
	var inv: Array = []
	for t in flipped[1]:
		inv.append(PackedVector3Array([t[0], t[2], t[1]]))
	flipped[1] = inv
	out.append(_t("a blade turned inside out is refused", not bool(StlWriter.check_bodies(flipped).ok)))
	return out


static func _test_blade_count(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for n in [2, 3, 4, 5]:
		var doc := _good(catalog)
		doc.blades = n
		var s := PropExport.build(doc, 5.4)
		out.append(_t("%d blades: hub plus %d shells" % [n, n], bool(s.ok) and (s.bodies as Array).size() == n + 1))
		if (s.bodies as Array).size() != n + 1:
			continue
		var angles: Array = []
		for k in n:
			var far := Vector3.ZERO
			for t in s.bodies[k + 1]:
				for p: Vector3 in t:
					if Vector2(p.x, p.y).length() > Vector2(far.x, far.y).length():
						far = p
			angles.append(fposmod(rad_to_deg(atan2(far.y, far.x)) - rad_to_deg(TAU * k / n), 360.0))
		var spread := 0.0
		for a: float in angles:
			spread = maxf(spread, absf(a - float(angles[0])))
		out.append(_t("%d blades: evenly spaced in the file" % n, spread < 0.01, str(angles)))
	return out


static func _test_file_geometry(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for bore: float in [3.4, 5.4]:
		var doc := _good(catalog)
		var done := PropExport.write(doc, bore, TMP)
		out.append(_t("bore %.1f: the file is written" % bore, bool(done.ok), String(done.reason)))
		var tris := _read_stl(TMP)
		var inner := INF
		var outer := 0.0
		var bottom := INF
		for t in tris:
			for p: Vector3 in t:
				var r := Vector2(p.x, p.y).length()
				inner = minf(inner, r)
				outer = maxf(outer, r)
				bottom = minf(bottom, p.z)
		out.append(_t("bore %.1f: the file's hole is that size" % bore, absf(inner * 2.0 - bore) < 0.001, "%f" % (inner * 2.0)))
		var tip := Vector2(doc.radius_mm(), doc.chord_at(1.0) * 0.5 * cos(doc.beta_rad(1.0))).length()
		out.append(_t("bore %.1f: the file reaches the tip" % bore, absf(outer - tip) < 0.05, "%f vs %f" % [outer, tip]))
		out.append(_t("bore %.1f: it sits on the bed" % bore, absf(bottom) < 1e-3, "%f" % bottom))
	return out


static func _test_volume(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var doc := _good(catalog)
	var bore := 5.4
	var s := PropExport.build(doc, bore)
	var rho := mats.density(doc.material_id)
	var blades_expected := BladeGeometry.blade_mass_g(doc, mats) / (rho * 1e-6)
	var hub_v := PI * (pow(float(s.hub_radius_mm), 2.0) - pow(bore * 0.5, 2.0)) * float(s.hub_height_mm)
	var blades_file := float(s.solid_mm3) - hub_v
	out.append(_t("blades' volume within 1% of mass / density", absf(blades_file / blades_expected - 1.0) < 0.01,
		"%.1f vs %.1f" % [blades_file, blades_expected]))
	PropExport.write(doc, bore, TMP)
	var tris := _read_stl(TMP)
	var report := StlWriter.check_manifold(tris)
	var sum_shells := 0.0
	for b in s.bodies:
		sum_shells += float(StlWriter.check_manifold(b).volume_mm3)
	out.append(_t("the file on disk holds every shell's volume", absf(float(report.volume_mm3) / sum_shells - 1.0) < 1e-3,
		"%.1f vs %.1f" % [report.volume_mm3, sum_shells]))
	var hub_g := PropDesigner.default_hub_g(doc, mats)
	var whole_expected := BladeGeometry.prop_mass_g(doc, mats, hub_g) / (rho * 1e-6)
	out.append(_t("whole solid within 15% of mass / density, default hub", absf(float(s.solid_mm3) / whole_expected - 1.0) < 0.15,
		"%.1f vs %.1f" % [s.solid_mm3, whole_expected]))
	return out


static func _test_refusals(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var thin := _good(catalog)
	thin.thickness_ratio = 0.10
	var s := PropExport.build(thin, 5.4)
	out.append(_t("a section under the minimum is refused", not bool(s.ok) and String(s.reason).contains("Too thin"), String(s.reason)))
	out.append(_t("the refusal names the real thinnest section", absf(float(s.thinnest_mm) - thin.chord_at(1.0) * 0.10) < 1e-6))
	DirAccess.remove_absolute(TMP)
	var w := PropExport.write(thin, 5.4, TMP)
	out.append(_t("a refused prop writes no file", not bool(w.ok) and not FileAccess.file_exists(TMP)))
	var just := _good(catalog)
	just.thickness_ratio = (PropExport.MIN_SECTION_MM + 0.001) / just.chord_at(1.0)
	out.append(_t("a section just over the minimum passes", bool(PropExport.build(just, 5.4).ok), String(PropExport.build(just, 5.4).reason)))
	just.thickness_ratio = (PropExport.MIN_SECTION_MM - 0.001) / just.chord_at(1.0)
	out.append(_t("a section just under the minimum is refused", not bool(PropExport.build(just, 5.4).ok)))
	out.append(_t("a bore eating the hub wall is refused", String(PropExport.build(_good(catalog), 19.0).reason).contains("hub wall")))
	out.append(_t("no bore is refused", String(PropExport.build(_good(catalog), 0.0).reason).contains("shaft")))
	var wide := _good(catalog)
	wide.thickness_ratio = 0.15
	wide.pitch_mm = 5.0
	wide.chord[1] = 40.0
	out.append(_t("a root wider than the hub is refused", String(PropExport.build(wide, 5.4).reason).contains("root"), String(PropExport.build(wide, 5.4).reason)))
	return out


static func _designer(catalog: PartsCatalog, mats: FrameMaterials) -> PropDesigner:
	var d := PropDesigner.new(catalog, mats)
	d.size = Vector2(1280, 720)
	d.doc = _good(catalog)
	d.hub_g = 3.3
	d.structure.heavy_mg = 25.0
	d._rederive()
	return d


static func _line(text: String, start: String) -> String:
	for l in text.split("\n"):
		if l.begins_with(start):
			return l
	return ""


static func _test_sheet(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	var text := d.copy_specs()
	var f := d.figures()
	var doc := d.doc
	out.append(_t("sheet: mass equals the figure", _line(text, "Mass:").contains("%.2f g" % float(f.mass_g)), _line(text, "Mass:")))
	out.append(_t("sheet: the hub is the set hub", _line(text, "Mass:").contains("3.3 g hub")))
	out.append(_t("sheet: material is named", _line(text, "Material:").contains(String(mats.get_material(doc.material_id).name))))
	var over := PropStructure.overspeed_rpm(doc, mats, d.rpm)
	out.append(_t("sheet: safe rpm is the overspeed figure", over > 0.0 and _line(text, "Safe rpm:").contains(str(roundi(over))), _line(text, "Safe rpm:")))
	var force := BladeGeometry.imbalance_force_n(25.0, float(f.cg_mm), d.rpm)
	out.append(_t("sheet: tolerance is the set heavy blade and its force",
		_line(text, "Balance").contains("25 mg") and _line(text, "Balance").contains("%.1f N" % force), _line(text, "Balance")))
	out.append(_t("sheet: bore equals the motor's shaft plus fit", _line(text, "Bore:").contains("%.2f mm" % (d.shaft_mm() + 0.4)), _line(text, "Bore:")))
	out.append(_t("sheet: flat-section note", text.contains(PropSheet.FLAT_NOTE)))
	out.append(_t("sheet: ideal / model label", text.contains("ideal / model")))
	out.append(_t("sheet: names the flat section in words a reader finds", text.contains("not an airfoil")))
	var rows: Array = []
	for l in text.split("\n"):
		if l.begins_with("  ") and l.contains(" | ") and not l.contains("radius"):
			rows.append(l.split("|"))
	out.append(_t("sheet: a row every 5 % of radius", rows.size() == 19, str(rows.size())))
	var bad: Array = []
	for i in rows.size():
		var r: float = float(rows[i][0])
		var frac := r / doc.radius_mm()
		var c := doc.chord_at(frac)
		if absf(float(rows[i][1]) - c) > 0.02 or absf(float(rows[i][2]) - rad_to_deg(doc.beta_rad(frac))) > 0.05 \
				or absf(float(rows[i][3]) - c * doc.thickness_ratio) > 0.002:
			bad.append(rows[i])
	out.append(_t("sheet: every row is radius, chord, angle, thickness of the document", bad.is_empty() and rows.size() > 0, str(bad)))
	out.append(_t("sheet: radius runs to the tip", absf(float(rows[-1][0]) - doc.radius_mm()) < 0.01))
	var solid := PropExport.build(doc, d.bore_mm())
	out.append(_t("sheet: the STL's solid mass is stated",
		_line(text, "STL solid").contains("%.2f g" % (float(solid.solid_mm3) * mats.density(doc.material_id) * 1e-6)), _line(text, "STL solid")))
	doc.thickness_ratio = 0.10
	out.append(_t("sheet: a refused prop's sheet says so, and is still a sheet",
		d.copy_specs().contains("STL refused: Too thin") and d.copy_specs().contains("STATIONS")))
	d.free()
	return out


static func _hole(path: String) -> float:
	var inner := INF
	for t in _read_stl(path):
		for p: Vector3 in t:
			inner = minf(inner, Vector2(p.x, p.y).length())
	return inner * 2.0


static func _test_panel(catalog: PartsCatalog, mats: FrameMaterials) -> Array:
	var out: Array = []
	var d := _designer(catalog, mats)
	d.show_tab("make")
	var m := d.make
	out.append(_t("panel: shows only on its tab", m.visible and not d.figures_box.visible and not d.structure.visible))
	out.append(_t("panel: a makeable prop can export", not m.stl_button.disabled and not m.refusal_label.visible))
	DirAccess.remove_absolute(TMP)
	out.append(_t("panel: the button's path writes the file", m.export_stl(TMP) and FileAccess.file_exists(TMP)))
	out.append(_t("panel: the file's bore is the panel's", absf(float(m.last.bore_mm) - d.bore_mm()) < 1e-9))
	out.append(_t("panel: Copy specs is live", not d.copy_button.disabled))
	out.append(_t("panel: Save as .txt writes the copied sheet", d.save_specs(TMP_TXT) and FileAccess.get_file_as_string(TMP_TXT) == d.copy_specs()))
	out.append(_t("panel: a failed .txt says so", not d.save_specs("user://no_such_folder/x.txt") and d.status_label.text.begins_with("Not saved")))
	var bare := {"specs": {"stator_diameter_mm": 22.0}}
	out.append(_t("shaft: a 22 mm stator with no record assumes 5 mm, not the picture's 2.4", PropDesigner.assumed_shaft_mm(bare) == 5.0))
	d.motor = bare
	d.shaft_set_mm = 0.0
	out.append(_t("shaft: the assumption is said on the sheet", d.shaft_is_assumed() and d.copy_specs().contains("assumed")))
	d.motor = {"specs": {"shaft_mm": 3.0, "stator_diameter_mm": 22.0}}
	out.append(_t("shaft: a record's shaft wins and is not called assumed", d.shaft_mm() == 3.0 and not d.shaft_is_assumed() and not d.copy_specs().contains("assumed")))
	d.step_shaft(1.0)
	out.append(_t("shaft: the stepper sets the bore", d.shaft_mm() == 4.0 and absf(d.bore_mm() - 4.4) < 1e-9 and m.shaft_value.text == "4.0 mm", m.shaft_value.text))
	out.append(_t("shaft: the set shaft reaches the file", m.export_stl(TMP) and absf(_hole(TMP) - 4.4) < 0.001, "%f" % _hole(TMP)))
	d.set_thickness(0.10)
	out.append(_t("panel: a thin prop cannot export", m.stl_button.disabled and m.refusal_label.visible and m.refusal_label.text.contains("Too thin")))
	DirAccess.remove_absolute(TMP)
	out.append(_t("panel: a thin prop's export press writes nothing and says why",
		not m.export_stl(TMP) and not FileAccess.file_exists(TMP) and m.result_label.text.contains("Too thin")))
	d.free()
	return out
