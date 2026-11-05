class_name TestPropStructure
extends RefCounted
## PD5: root stress, factor, overspeed, flex, and the exact figures. Closed forms come first, with a
## triangle as well as a uniform chord, because uniform chord cancels out of the centrifugal stress.

const EPS := 1e-4
const R_MM := 63.5
## apcprop.com/files/PER3_5x45E.dat, v2022-0915, Mach column at V = 0: rpm, Mach, D = 5". The whole
## file's 1139 rows bracket APC's sound speed to 335.279-335.284 m/s, which is 1100 ft/s.
const APC_ROWS := [[10000.0, 0.20], [20000.0, 0.40], [30000.0, 0.59]]
const APC_SOUND_MPS := 335.28


static func run() -> Array:
	var results: Array = []
	var materials := FrameMaterials.load_default()
	_exact(results)
	_beam(results)
	_centrifugal(results, materials)
	_stress(results, materials)
	_overspeed(results, materials)
	_material(results, materials)
	_refusals(results, materials)
	return results


static func _doc(points: Array, material := "polycarbonate") -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.diameter_mm = R_MM * 2.0
	doc.pitch_mm = 109.0
	doc.blades = 3
	doc.material_id = material
	for pt in points:
		doc.chord.append(pt[0])
		doc.chord.append(pt[1])
	return doc


static func _uniform(chord_mm: float, material := "polycarbonate") -> PropellerDocument:
	return _doc([[0.1, chord_mm], [1.0, chord_mm]], material)


static func _near(results: Array, name: String, got: float, want: float, eps := EPS) -> void:
	results.append(TestResult.new(name, absf(got - want) <= eps * maxf(absf(want), 1e-12),
		"%.9f (want %.9f)" % [got, want]))


static func _exact(results: Array) -> void:
	var doc := _uniform(12.0)
	for row in APC_ROWS:
		var got := PropTunnel.tip_mach(0.127, row[0], 0.0, 0.0, APC_SOUND_MPS)
		results.append(TestResult.new("mach: APC 5x4.5E at %d rpm with APC's own sound speed" % int(row[0]),
			snappedf(got, 0.01) == float(row[1]), "%.4f want %.2f" % [got, row[1]]))
	# In the tunnel's 15 C air the same tip reads 0.391. That is the difference, stated and pinned.
	_near(results, "mach: 20,000 rpm at 340.3 m/s", PropTunnel.tip_mach(0.127, 20000.0),
		20000.0 * TAU / 60.0 * 0.0635 / 340.3, 1e-12)
	results.append(TestResult.new("mach: the tunnel's point reads the same helper",
		PropTunnel.point(PropTunnel.geometry_of(_real_doc()), 20000.0, 0.0).tip_mach
			== PropTunnel.tip_mach(0.127, 20000.0), ""))
	results.append(TestResult.new("blade pass: 3 blades at 25,000 rpm is exactly 1250 Hz",
		PropStructure.blade_pass_hz(doc, 25000.0) == 1250.0, str(PropStructure.blade_pass_hz(doc, 25000.0))))
	_near(results, "tip speed: ωR", PropStructure.tip_speed_mps(doc, 30000.0), 3141.592653589793 * 0.0635, 1e-12)


static func _real_doc() -> PropellerDocument:
	return PropellerDocument.from_catalog_prop(PartsCatalog.load_default().get_part("prop_5x45x3"))


static func _beam(results: Array) -> void:
	_near(results, "section: flatwise Z = c·t²/6, c 10, t 1", PropStructure.section_modulus_mm3(10.0, 0.1),
		10.0 / 6.0, 1e-12)
	_near(results, "section: flatwise I = c·t³/12, c 10, t 1", PropStructure.second_moment_mm4(10.0, 0.1),
		10.0 / 12.0, 1e-12)
	var doc := _doc([[0.0, 10.0], [1.0, 10.0]])
	var inertia := 10.0 / 12.0
	var e_mpa := 2400.0
	_near(results, "flex: tip load gives F·L³/3EI",
		PropStructure.tip_flex_mm(doc, 2.4, [[R_MM, 1.0]]),
		pow(R_MM, 3.0) / (3.0 * e_mpa * inertia))
	var spread: Array = []
	var cells := 2000
	for i in cells:
		spread.append([(float(i) + 0.5) * R_MM / float(cells), 1.0 / float(cells)])
	_near(results, "flex: even load gives W·L³/8EI",
		PropStructure.tip_flex_mm(doc, 2.4, spread), pow(R_MM, 3.0) / (8.0 * e_mpa * inertia))
	_near(results, "moment: only the load outboard counts",
		PropStructure.bending_moment_nmm([[10.0, 5.0], [30.0, 2.0]], 20.0), 20.0, 1e-12)
	var thin := _uniform(10.0)
	thin.thickness_ratio = 0.08
	_near(results, "root: a thinner blade's root reads the sourced figure", PropStructure.root_thickness_ratio(thin), 0.11, 1e-12)
	thin.thickness_ratio = 0.14
	_near(results, "root: a thicker blade keeps its own", PropStructure.root_thickness_ratio(thin), 0.14, 1e-12)


static func _centrifugal(results: Array, materials: FrameMaterials) -> void:
	var rho := materials.density("polycarbonate")
	var omega := 30000.0 * TAU / 60.0
	var want := rho * omega * omega * (pow(0.0635, 2.0) - pow(0.00635, 2.0)) * 0.5 * 1e-6
	for chord in [6.0, 12.0]:
		var drawn := _uniform(chord)
		var area: float = drawn.thickness_ratio * chord * chord
		_near(results, "centrifugal: uniform chord %d gives ρω²(R²−r²)/2" % int(chord),
			PropStructure.centrifugal_force_n(drawn, rho, 30000.0) / area, want)
	var tri := _doc([[0.0, 10.0], [1.0, 0.0]])
	_near(results, "centrifugal: apex-tip triangle gives ρω²R²/12, the c² law",
		PropStructure.centrifugal_force_n(tri, rho, 30000.0) / (tri.thickness_ratio * 100.0),
		rho * omega * omega * pow(0.0635, 2.0) / 12.0 * 1e-6)
	var from_hub := _doc([[0.0, 10.0], [1.0, 10.0]])
	var mass_kg := BladeGeometry.single_blade_mass_g(from_hub, materials) * 0.001
	_near(results, "centrifugal: full span equals blade mass · CG · ω²",
		PropStructure.centrifugal_force_n(from_hub, rho, 30000.0),
		mass_kg * BladeGeometry.blade_cg_mm(from_hub) * 0.001 * omega * omega)
	var doc := _uniform(12.0)
	_near(results, "centrifugal: scales with ω²",
		PropStructure.centrifugal_force_n(doc, rho, 40000.0) / PropStructure.centrifugal_force_n(doc, rho, 20000.0),
		4.0, 1e-9)


static func _stress(results: Array, materials: FrameMaterials) -> void:
	# The spec's hand check: 5", 3 blades, 30,000 rpm, a 14 mm² root. About 20 MPa pull, the bending
	# twice that. A tripwire on the size of each term, not a claim about a real prop.
	var doc := _uniform(12.0)
	var a := PropStructure.assess(doc, materials, 30000.0)
	results.append(TestResult.new("stress: hand check, pull near 20 MPa", a.centrifugal_mpa > 18.0 and a.centrifugal_mpa < 30.0,
		"%.1f MPa" % a.centrifugal_mpa))
	results.append(TestResult.new("stress: hand check, bending is comparable and larger",
		a.bending_mpa > a.centrifugal_mpa and a.bending_mpa < 5.0 * a.centrifugal_mpa, "%.1f MPa" % a.bending_mpa))
	# The whole: bending recomputed here from the real solve, so leaving it out or using the wrong
	# axis cannot pass by reading the same code twice.
	var solved := PropTunnel.stations(PropTunnel.geometry_of(doc), 30000.0, 0.0)
	var moment := 0.0
	for row in solved.stations:
		moment += float(row.thrust_n) / 3.0 * (float(row.r_m) * 1000.0 - 6.35)
	var t := 12.0 * PropStructure.ROOT_THICKNESS_RATIO
	_near(results, "stress: bending is the BEMT moment over c·t²/6, across the thin axis",
		a.bending_mpa, moment / (12.0 * t * t / 6.0))
	_near(results, "stress: the total is pull plus bending", a.stress_mpa, a.centrifugal_mpa + a.bending_mpa, 1e-12)
	_near(results, "stress: factor is strength over stress", a.factor, 65.0 / a.stress_mpa, 1e-12)
	var thin := PropStructure.assess(_uniform(8.0), materials, 30000.0)
	results.append(TestResult.new("stress: a thinner chord raises the stress",
		thin.stress_mpa > a.stress_mpa and thin.factor < a.factor,
		"%.1f vs %.1f MPa" % [thin.stress_mpa, a.stress_mpa]))
	results.append(TestResult.new("flex: a real number in mm and % of radius",
		a.flex_mm > 0.0 and absf(a.flex_pct_radius - a.flex_mm / R_MM * 100.0) < 1e-9, "%.2f mm" % a.flex_mm))
	_near(results, "flex: read from the same thrust loads, E is the only divisor",
		PropStructure.assess(_uniform(12.0, "glass_filled_nylon"), materials, 30000.0).flex_mm, a.flex_mm * 2.4 / 6.2)


static func _overspeed(results: Array, materials: FrameMaterials) -> void:
	var catalog := PartsCatalog.load_default()
	var presets := PropellerDocument.presets_from_catalog(catalog)
	for id in presets:
		var preset: PropellerDocument = presets[id]
		var over := PropStructure.overspeed_rpm(preset, materials, 12000.0)
		var fed := PropStructure.assess(preset, materials, over)
		results.append(TestResult.new("overspeed: %s fed back gives factor 1" % id,
			over > 0.0 and fed.ok and absf(fed.factor - 1.0) < 1e-6, "%.0f rpm, factor %.9f" % [over, fed.get("factor", 0.0)]))
	var doc := _uniform(12.0)
	var low := PropStructure.overspeed_rpm(doc, materials, 5000.0)
	var high := PropStructure.overspeed_rpm(doc, materials, 90000.0)
	_near(results, "overspeed: one figure, from below or above", low, high, 1e-6)


static func _material(results: Array, materials: FrameMaterials) -> void:
	for id in ["polycarbonate", "glass_filled_nylon", "carbon_filled_nylon", "pa12_sls"]:
		var entry := materials.get_material(id)
		results.append(TestResult.new("material: %s has modulus, strength, tier and source" % id,
			materials.modulus_gpa(id) > 0.0 and materials.strength_mpa(id) > 0.0
				and entry.catalog.has("strength_tier") and str(entry.source).length() > 20, str(entry.specs)))
	var pc := PropStructure.assess(_uniform(12.0, "polycarbonate"), materials, 25000.0)
	var gf := PropStructure.assess(_uniform(12.0, "glass_filled_nylon"), materials, 25000.0)
	_near(results, "material: pull goes as this material's density, not another's",
		gf.centrifugal_mpa / pc.centrifugal_mpa, 1400.0 / 1200.0, 1e-9)
	_near(results, "material: bending does not care", gf.bending_mpa, pc.bending_mpa, 1e-12)
	results.append(TestResult.new("material: swap moves the factor, by this material's strength",
		gf.factor != pc.factor and absf(gf.factor - 115.0 / gf.stress_mpa) < 1e-9, "%.3f vs %.3f" % [gf.factor, pc.factor]))
	results.append(TestResult.new("material: swap moves the mass",
		BladeGeometry.blade_mass_g(_uniform(12.0, "glass_filled_nylon"), materials)
			> BladeGeometry.blade_mass_g(_uniform(12.0, "polycarbonate"), materials), ""))


static func _refusals(results: Array, materials: FrameMaterials) -> void:
	results.append(TestResult.new("refused: no rpm",
		PropStructure.assess(_uniform(12.0), materials, 0.0).reason == PropStructure.REASON_RPM, ""))
	results.append(TestResult.new("refused: no section at the root",
		PropStructure.assess(_doc([[0.1, 0.0], [1.0, 10.0]]), materials, 20000.0).reason == PropStructure.REASON_ROOT, ""))
	results.append(TestResult.new("refused: TPU has no strength, so no factor, rather than a factor of zero",
		PropStructure.assess(_uniform(12.0, "tpu_95a"), materials, 20000.0).reason == PropStructure.REASON_NO_STRENGTH, ""))
