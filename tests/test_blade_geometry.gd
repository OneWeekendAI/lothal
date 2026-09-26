class_name TestBladeGeometry
extends RefCounted
## BladeGeometry computes mass, blade inertia and the dimensionless radius of gyration k² of a
## PropellerDocument (§3.3). This file's subject is k²: the shape-only number that decides how much
## a prop's blades contribute to spin-up, and the band of plausible values that is the honest error
## bar on that number (P2).
##
## The closed forms are the load-bearing tests — the doc's proof obligations, corrected. A wrong
## quadrature here would not look wrong anywhere; it would produce plausible spin-up figures that
## disagree with the textbook answers by a factor that nobody would notice (the same failure mode
## airframe.md §3.1 names for PolygonProps). So uniform chord must give k² = 1/3, a triangle with
## its apex at the root must give 3/5, and a triangle tapering to a point at the TIP must give 1/10
## — NOT 3/5, which is what §3.3's proof obligation currently claims, and which this file corrects.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var materials := FrameMaterials.load_default()

	results.append(_test_uniform_chord_gives_one_third())
	results.append(_test_triangle_apex_root_gives_three_fifths())
	results.append(_test_triangle_apex_tip_gives_one_tenth())
	results.append(_test_mass_uses_published_density_and_thickness())
	results.append(_test_inertia_is_mass_times_k2_times_R2(catalog, materials))
	results.append(_test_catalog_planforms_sit_in_a_reported_band(catalog))
	results.append(_test_plausible_planforms_narrow_band())
	results.append(_test_published_band_constants_bracket_the_real_band())

	return results


## Builds a PropellerDocument with a synthetic chord (uniform, triangular, …) over r/R ∈ [0, 1].
## The planform spans the whole radius on purpose: the closed forms are the full-blade integrals,
## and a hub cut would move the answer off the textbook value for no reason.
static func _doc_with_chord(diameter_mm: float, points: Array) -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.diameter_mm = diameter_mm
	doc.blades = 2
	doc.material_id = "polycarbonate"
	for pt in points:
		doc.chord.append(pt[0])
		doc.chord.append(pt[1])
	return doc


static func _test_uniform_chord_gives_one_third() -> TestResult:
	# A rectangle of constant chord from axis to tip. Closed form: ∫c²r²dr / (R²·∫c²dr) = 1/3.
	var doc := _doc_with_chord(127.0, [[0.0, 10.0], [1.0, 10.0]])
	var k2 := BladeGeometry.radius_of_gyration_sq(doc)
	var expected := 1.0 / 3.0
	return TestResult.new(
		"uniform chord gives k² = 1/3 exactly",
		absf(k2 - expected) < 1e-12,
		"k² = %.15f (want %.15f)" % [k2, expected])


static func _test_triangle_apex_root_gives_three_fifths() -> TestResult:
	# c(r) ∝ r/R — narrow at the root, full at the tip. Closed form: 3/5.
	var doc := _doc_with_chord(127.0, [[0.0, 0.0], [1.0, 10.0]])
	var k2 := BladeGeometry.radius_of_gyration_sq(doc)
	var expected := 3.0 / 5.0
	return TestResult.new(
		"triangle with apex at the root gives k² = 3/5 exactly",
		absf(k2 - expected) < 1e-12,
		"k² = %.15f (want %.15f)" % [k2, expected])


static func _test_triangle_apex_tip_gives_one_tenth() -> TestResult:
	# c(r) ∝ (1 − r/R) — tapering to a point at the TIP. Closed form: 1/10.
	#
	# §3.3's proof obligation says this shape must give 3/5. It does not: 3/5 is the APEX-AT-ROOT
	# triangle, and a blade that tapers to a point at the tip has its area far inboard, so k² is
	# small (1/10). The document is corrected by this test; the comment in BladeGeometry says the
	# same thing so nobody "fixes" the test to match the doc.
	var doc := _doc_with_chord(127.0, [[0.0, 10.0], [1.0, 0.0]])
	var k2 := BladeGeometry.radius_of_gyration_sq(doc)
	var expected := 1.0 / 10.0
	return TestResult.new(
		"triangle tapering to a point at the tip gives k² = 1/10, not the doc's 3/5",
		absf(k2 - expected) < 1e-12,
		"k² = %.15f (want %.15f)" % [k2, expected])


static func _test_mass_uses_published_density_and_thickness() -> TestResult:
	# m = N_b · ρ · thickness_ratio · ∫c²dr. Hand-checked on a uniform blade: c = 10 mm over
	# r ∈ [0, 63.5 mm] is a rectangle of "area" 635 mm³ in ∫c²dr space... no — ∫c²dr with c in mm
	# over r in mm is mm³: c = 10 mm, ∫₀^63.5 100 dr = 6350 mm³. × 2 blades × 1200 kg/m³ × 0.1
	# (thickness ratio) × 1e-9 (mm³→m³) = 0.001524 kg = 1.524 g.
	var doc := _doc_with_chord(127.0, [[0.0, 10.0], [1.0, 10.0]])
	var materials := FrameMaterials.load_default()
	var mass_g := BladeGeometry.blade_mass_g(doc, materials)
	var expected_g := 2.0 * 1200.0 * 0.1 * 6350.0 * 1e-9 * 1000.0
	return TestResult.new(
		"blade mass is N_b·ρ·thickness_ratio·∫c²dr with the right units",
		absf(mass_g - expected_g) < 1e-9,
		"mass = %.6f g (want %.6f g)" % [mass_g, expected_g])


## J = m·k²·R², checked as a relationship between the two computed quantities rather than against a
## stored number — the way test_airframe_properties checks parallel-axis shifts. This is the equation
## §3.3 actually uses (published mass × shape k² × R²), so a drift in either integral that left the
## ratio intact would still be caught by this.
static func _test_inertia_is_mass_times_k2_times_R2(
	catalog: PartsCatalog, materials: FrameMaterials
) -> TestResult:
	var problems: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var j := BladeGeometry.blade_inertia_kg_m2(doc, materials)
		var m := BladeGeometry.blade_mass_g(doc, materials) * 1e-3
		var r2 := pow(doc.radius_mm() * 1e-3, 2.0)
		var expected := m * BladeGeometry.radius_of_gyration_sq(doc) * r2
		# J is computed directly from the integrals; the m·k²·R² route must reconstruct it.
		if absf(j - expected) > 1e-12:
			problems.append("%s: J %.6e vs m·k²·R² %.6e" % [prop["part_id"], j, expected])
	return TestResult.new(
		"blade inertia equals mass × k² × R² on every preset",
		problems.is_empty(),
		"%d presets agree" % catalog.list_category("propeller").size()
			if problems.is_empty() else "; ".join(problems))


## The 19 catalog planforms share ONE generated shape, so their k² is a single degenerate value —
## which is exactly why the BAND in the next test is the honest error bar and this value is not.
## Reported, not asserted, because the value is a property of the current generator's shape; if that
## shape is ever changed to sit inside the plausible band, this number moves with it.
##
## "One number" means a relative spread under 1e-6, not bit-identical: k² is scale-invariant in
## chord, so all 19 SHOULD agree exactly, but `chord_points()` rounds to float32 (Vector2), and a
## 40-station planform at a different diameter carries ~1e-7 quantization. A relative tolerance of
## 1e-6 still fails a planform that genuinely differs by a per-prop tweak — which is what this test
## is here to catch, since the generator is supposed to produce the same shape for every size.
static func _test_catalog_planforms_sit_in_a_reported_band(catalog: PartsCatalog) -> TestResult:
	var values: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		values.append(BladeGeometry.radius_of_gyration_sq(doc))
	var min_k2 := INF
	var max_k2 := -INF
	for v in values:
		min_k2 = minf(min_k2, v)
		max_k2 = maxf(max_k2, v)
	var degenerate := max_k2 / min_k2 < 1.0 + 1e-6
	return TestResult.new(
		"catalog planforms share one generated shape, so their k² is one number",
		degenerate and values.size() == 19,
		"%d presets, k² = %.4f (relative spread %.8f)" % [
			values.size(), min_k2, max_k2 / min_k2 - 1.0])


## THE BAND: k² over plausible FPV planforms — root-tapered, peak chord around 0.6–0.75 R, narrow
## tip. §3.3 asks for exactly this: "the resulting spread is the honest error bar on spin-up". The
## band is asserted to be NARROW (max/min < 1.35) because that is the load-bearing claim — a wide
## band would make every spin-up number characteristic, and the panel must say so.
##
## The family is deliberately the doc's own words, not a wider net: peak chord "around 0.6–0.75 R"
## and a "narrow tip". Sweeping the peak across that range with tip fractions a real FPV prop would
## have (5–15% of max chord) gives the band this test enforces. Adding shapes the doc does not call
## plausible — peak at 0.55 R, a 25% tip — widens the band to 0.33..0.47, which would fail this, and
## that is correct: those shapes are not in the claim's territory.
static func _test_plausible_planforms_narrow_band() -> TestResult:
	var values: Array = []
	# c(r/R) linear up to a peak, linear down to a tip fraction, hub cut at 0.10 R.
	for peak in [0.60, 0.65, 0.70, 0.75]:
		for tip_frac in [0.05, 0.10, 0.15]:
			var doc := _doc_with_chord(127.0, _realish_planform(peak, tip_frac))
			values.append(BladeGeometry.radius_of_gyration_sq(doc))

	var min_k2 := INF
	var max_k2 := -INF
	for v in values:
		min_k2 = minf(min_k2, v)
		max_k2 = maxf(max_k2, v)
	# A narrow band is the honest claim. 1.35 = about ±15% around the middle — tight enough that
	# spin-up can be engineering-grade for an authored planform, loose enough that it is not pretend.
	var narrow := max_k2 / min_k2 < 1.35
	return TestResult.new(
		"k² over plausible FPV planforms is a narrow band, not a spread",
		narrow and min_k2 > 0.35 and max_k2 < 0.50,
		"%d planforms, k² band %.3f..%.3f (ratio %.2f)" % [values.size(), min_k2, max_k2, max_k2 / min_k2])


## A root-tapered planform: zero at the hub, linear up to `peak` (r/R), linear down to `tip_frac` at
## the tip. The family of shapes §3.3 calls "plausible FPV".
static func _realish_planform(peak: float, tip_frac: float) -> Array:
	var hub := 0.10
	var points: Array = [[hub, 0.0]]
	var n := 40
	for i in n + 1:
		var x := hub + (1.0 - hub) * float(i) / float(n)
		if x <= peak:
			points.append([x, (x - hub) / (peak - hub)])
		else:
			points.append([x, 1.0 - (1.0 - tip_frac) * (x - peak) / (1.0 - peak)])
	return points


## The band constants are what the propeller panel quotes, so they must not be free to drift away
## from the family they claim to describe. This recomputes the same twelve planforms as the test
## above and asserts BladeGeometry's published constants bracket them tightly — a generator or
## family change that moved the real band fails here rather than quietly making the panel's caveat
## wrong. Tight on both sides: constants far wider than the band would pass a mere containment
## check while telling the reader nothing.
static func _test_published_band_constants_bracket_the_real_band() -> TestResult:
	var min_k2 := INF
	var max_k2 := -INF
	for peak in [0.60, 0.65, 0.70, 0.75]:
		for tip_frac in [0.05, 0.10, 0.15]:
			var k2 := BladeGeometry.radius_of_gyration_sq(
				_doc_with_chord(127.0, _realish_planform(peak, tip_frac)))
			min_k2 = minf(min_k2, k2)
			max_k2 = maxf(max_k2, k2)
	# Within 0.002 on each side: the constants ARE the band, rounded to three places, not a loose
	# envelope around it.
	var tight := absf(BladeGeometry.PLAUSIBLE_K2_MIN - min_k2) < 0.002 \
		and absf(BladeGeometry.PLAUSIBLE_K2_MAX - max_k2) < 0.002
	return TestResult.new(
		"the k² band constants the panel quotes are the band the integrals actually produce",
		tight,
		"published %.3f..%.3f vs computed %.3f..%.3f" % [
			BladeGeometry.PLAUSIBLE_K2_MIN, BladeGeometry.PLAUSIBLE_K2_MAX, min_k2, max_k2])
