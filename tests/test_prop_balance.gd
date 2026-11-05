class_name TestPropBalance
extends RefCounted
## PD4: where a blade's mass sits, what an error in it costs, and that the error reaches the
## vibration model. Closed forms use triangles as well as a uniform chord, because a uniform chord
## cannot tell a c² mass law from a c one. Interface and consequence are checked as a pair.

const EPS := 1e-9


static func run() -> Array:
	var results: Array = []
	var materials := FrameMaterials.load_default()
	_closed_forms(results, materials)
	_force_law(results)
	_tracking(results, materials)
	_shelf(results, materials)
	_link(results)
	return results


static func _doc(diameter_mm: float, points: Array) -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.diameter_mm = diameter_mm
	doc.blades = 2
	doc.material_id = "polycarbonate"
	for pt in points:
		doc.chord.append(pt[0])
		doc.chord.append(pt[1])
	return doc


static func _near(results: Array, name: String, got: float, want: float, eps := EPS) -> void:
	results.append(TestResult.new(name, absf(got - want) < eps, "%.9f (want %.9f)" % [got, want]))


## chord_points are Vector2, so a station at 0.2 is only good to 32 bits: those two checks use 1e-5.
static func _closed_forms(results: Array, materials: FrameMaterials) -> void:
	var uniform := _doc(127.0, [[0.0, 10.0], [1.0, 10.0]])
	var apex_root := _doc(127.0, [[0.0, 0.0], [1.0, 10.0]])
	var apex_tip := _doc(127.0, [[0.0, 10.0], [1.0, 0.0]])
	var hub_cut := _doc(100.0, [[0.2, 10.0], [1.0, 10.0]])
	_near(results, "uniform chord: blade CG at mid-span", BladeGeometry.blade_cg_mm(uniform), 31.75)
	_near(results, "triangle, apex at root: CG at 3R/4 by the c² law (c alone gives 2R/3)",
		BladeGeometry.blade_cg_mm(apex_root), 47.625)
	_near(results, "triangle, apex at tip: CG at R/4 by the c² law (c alone gives R/3)",
		BladeGeometry.blade_cg_mm(apex_tip), 15.875)
	_near(results, "uniform blade starting at 0.2 R: CG at 0.6 R, measured from the axis",
		BladeGeometry.blade_cg_mm(hub_cut), 30.0, 1e-5)
	_near(results, "a blade cut into more stations has the same CG",
		BladeGeometry.blade_cg_mm(_doc(127.0, [[0.0, 0.0], [0.3, 3.0], [0.7, 7.0], [1.0, 10.0]])),
		47.625, 1e-5)

	# rho 1200 kg/m³ (the existing mass test's polycarbonate), t/c 0.1, 10 mm x 63.5 mm.
	var one_blade_g := 1200.0 * 0.1 * 100.0 * 63.5 * 1e-9 * 1000.0
	_near(results, "one blade is the set's mass over the blade count",
		BladeGeometry.single_blade_mass_g(uniform, materials), one_blade_g)
	_near(results, "section mass of a uniform blade is mass per mm of span",
		BladeGeometry.section_mass_g_per_mm(uniform, materials, 0.5), one_blade_g / 63.5)
	_near(results, "section mass goes as c²: half chord, quarter mass",
		BladeGeometry.section_mass_g_per_mm(apex_root, materials, 0.5), one_blade_g / 63.5 * 0.25)
	_near(results, "no blade drawn inboard of the hub cut means no section mass there",
		BladeGeometry.section_mass_g_per_mm(hub_cut, materials, 0.1), 0.0)

	var hub_g := 2.0
	var total_g := one_blade_g * 2.0 + hub_g
	_near(results, "prop mass is the blades plus the hub field",
		BladeGeometry.prop_mass_g(uniform, materials, hub_g), total_g)
	_near(results, "a set with no error has its prop CG on the axis",
		BladeGeometry.prop_cg_offset_mm(uniform, materials, hub_g, 0.0), 0.0)
	_near(results, "10 mg over moves the prop CG by m·r_cg over the total",
		BladeGeometry.prop_cg_offset_mm(uniform, materials, hub_g, 10.0),
		0.01 * 31.75 / (total_g + 0.01))


static func _force_law(results: Array) -> void:
	_near(results, "10 mg at 50 mm at 25,000 rpm is 3.43 N",
		BladeGeometry.imbalance_force_n(10.0, 50.0, 25000.0), 3.4269, 1e-4)
	_near(results, "force goes as ω²: half the rpm, quarter the force",
		BladeGeometry.imbalance_force_n(10.0, 50.0, 12500.0), 3.4269 * 0.25, 1e-4)
	_near(results, "force goes as the arm",
		BladeGeometry.imbalance_force_n(10.0, 25.0, 25000.0), 3.4269 * 0.5, 1e-4)
	var doc := _doc(100.0, [[0.0, 10.0], [1.0, 10.0]])
	var at_radius_g := BladeGeometry.imbalance_g_at_radius(doc, 10.0)
	_near(results, "a blade 10 mg over, CG at R/2, is 5 mg at the blade radius", at_radius_g, 0.005)
	_near(results, "and that conversion keeps the force",
		BladeGeometry.imbalance_force_n(at_radius_g * 1000.0, 50.0, 25000.0),
		BladeGeometry.imbalance_force_n(10.0, 25.0, 25000.0))


static func _tracking(results: Array, materials: FrameMaterials) -> void:
	var doc := _doc(127.0, [[0.0, 10.0], [1.0, 10.0]])
	var m_kg := 1200.0 * 0.1 * 100.0 * 63.5 * 1e-9
	var omega := 25000.0 * TAU / 60.0
	# Tip 1 mm out: CG 0.5 mm out, at 31.75 mm.
	_near(results, "tracking couple is m·r_cg·ω² times the CG's height out of the disc",
		BladeGeometry.tracking_couple_nm(doc, materials, 1.0, 25000.0),
		m_kg * 0.03175 * omega * omega * 0.0005)
	_near(results, "a blade in track has no couple",
		BladeGeometry.tracking_couple_nm(doc, materials, 0.0, 25000.0), 0.0)


static func _shelf(results: Array, materials: FrameMaterials) -> void:
	var catalog := PartsCatalog.load_default()
	var checked := 0
	var worst_mass := 0.0
	var outside: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var id := str(prop["part_id"])
		checked += 1
		var cg := BladeGeometry.blade_cg_mm(doc)
		var pts := doc.chord_points()
		if cg <= pts[0].x * doc.radius_mm() or cg >= pts[-1].x * doc.radius_mm():
			outside.append(id)
		# Section mass by midpoint rule against the closed-form integral.
		var steps := 2000
		var x0: float = pts[0].x
		var dx: float = (pts[-1].x - x0) / steps
		var sum := 0.0
		for i in steps:
			sum += BladeGeometry.section_mass_g_per_mm(doc, materials, x0 + (i + 0.5) * dx)
		sum *= dx * doc.radius_mm()
		var want := BladeGeometry.single_blade_mass_g(doc, materials)
		worst_mass = maxf(worst_mass, absf(sum - want) / want)
	results.append(TestResult.new("every shelf prop's CG sits on its own blade",
		checked >= 20 and outside.is_empty(), "%d props, outside: %s" % [checked, outside]))
	results.append(TestResult.new("section mass integrates to the blade's mass on every shelf prop",
		checked >= 20 and worst_mass < 1e-3, "worst relative error %.6f" % worst_mass))


## The pair: the interface (the value lands where the model reads it) and the consequence (the
## vibration read-out moves, through the path the gyro uses).
static func _link(results: Array) -> void:
	var kd := 40.0
	var build := ReferenceBuild.build()
	var stock_force := BladeGeometry.build_imbalance_force_n(build, 25000.0)
	var stock_read := RateTune.vibration_noise_fraction(build, kd)
	var radius_mm := VibrationModel.for_build(build).prop_radius_m * 1000.0
	_near(results, "the stock build's figure is 20 mg at its own prop radius", stock_force,
		BladeGeometry.imbalance_force_n(20.0, radius_mm, 25000.0))

	BladeGeometry.set_build_imbalance(build, 0.4)
	_near(results, "interface: the vibration model reads the imbalance that was set",
		VibrationModel.for_build(build).imbalance_kg, 0.0004, 1e-12)
	_near(results, "interface: 20x the imbalance is 20x the force",
		BladeGeometry.build_imbalance_force_n(build, 25000.0), stock_force * 20.0, 1e-9)
	var chipped_read := RateTune.vibration_noise_fraction(build, kd)
	results.append(TestResult.new("consequence: more imbalance moves the vibration read-out",
		chipped_read > stock_read * 4.0, "%.5f -> %.5f" % [stock_read, chipped_read]))

	BladeGeometry.set_build_imbalance(build, VibrationModel.DEFAULT_IMBALANCE_KG * 1000.0)
	results.append(TestResult.new("setting the default back restores the read-out exactly",
		RateTune.vibration_noise_fraction(build, kd) == stock_read,
		"%.9f vs %.9f" % [RateTune.vibration_noise_fraction(build, kd), stock_read]))

	var record: Dictionary = build.propeller
	results.append(TestResult.new("imbalance stays on the build: the prop record never learns it",
		not record.has("prop_imbalance_g"), "propeller keys: %s" % [record.keys()]))
