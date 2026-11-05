class_name BladeGeometry
extends RefCounted
## Mass, blade inertia and the dimensionless radius of gyration of a PropellerDocument, computed
## from its planform and nothing else — propulsion.md §3.3.
##
## ## What this replaces, and why it is not a refinement of it
##
## The propeller's contribution to spin-up today is a scalar `SPIN_UP_TAU_S` that is the same for
## every motor in the catalog (§0). The number that actually sets spin-up is the rotor's second
## moment of mass — `J_rotor + J_blade` against available torque (§3.4). `J_blade` is the part this
## file computes: the blades are a solid of density `ρ`, thickness `thickness_ratio·c(r)`, swept
## `N_b` times around the axis, so
##
##     J_blade = N_b · ρ · thickness_ratio · ∫ c(r)² r² dr
##     m_blade = N_b · ρ · thickness_ratio · ∫ c(r)² dr
##
## Nothing here may be authored: if a quantity is not an integral of the planform or a published
## density, it does not appear.
##
## ## Why the radius of gyration is the figure of merit, and what it depends on
##
## §3.3's move is to write `J_blade = m_prop · k² · R²` and make `k²` the whole question. Mass is
## published; R is published; `k²` depends ONLY on the SHAPE of `c(r/R)`, not its scale:
##
##     k² = [∫ c(r)² r² dr] / [R² · ∫ c(r)² dr]
##
## The `N_b · ρ · thickness_ratio` factors cancel, which is the point — a 15% fat chord moves the
## scale and barely moves `k²`, and scale is exactly what §4.4's calibration absorbs. The band of
## `k²` across plausible planforms is the honest error bar on every spin-up number (P2), and it is
## computed here and asserted against its closed forms:
##
##     uniform chord        → k² = 1/3   (a rectangle from axis to tip)
##     triangle, apex root  → k² = 3/5   (c ∝ r)
##     triangle, apex tip   → k² = 1/10  (c ∝ 1 − r/R)
##
## NOTE the middle line against §3.3's proof obligation, which says "a triangular blade tapering to
## a point at the tip must give k² = 3/5". That pairing is wrong — 3/5 is the triangle whose APEX
## is at the ROOT and whose base is at the tip; a blade tapering to a point at the TIP gives 1/10.
## The closed forms above are the correct ones and the tests enforce them; this comment exists so
## the document's error is corrected rather than silently copied into code.
##
## ## Doubles, deliberately
##
## Same rule as `AirframeProperties`: every sum accumulates in GDScript `float` (a double). The
## planform is already stored as doubles, so a mass sum has no single-precision floor to argue about.

## The band of k² across the planforms propulsion.md §3.3 calls plausible — root-tapered, peak
## chord at 0.60–0.75 R, tip 5–15% of max chord. PUBLISHED BY P2 BEFORE ANYTHING READ IT, which is
## the point of the cheap early check: the band is the honest error bar on every spin-up number, and
## quoting a k² without it is quoting a number nobody can interpret.
##
## These are constants rather than a live computation because they are a CLAIM about a family of
## shapes, not a property of any one document — but they are not free to drift: the band test in
## `test_blade_geometry.gd` recomputes the family and asserts these two numbers bracket it, so a
## generator change that moved the real band would fail rather than quietly widen the caveat.
##
## Note where the shipped generator sits: its sine arch peaks at ≈0.46 R, inboard of anything in
## this family, so every preset lands at k² ≈ 0.278 — BELOW the band. That is §3.3's finding, and
## the panel reports it rather than smoothing it over.
const PLAUSIBLE_K2_MIN := 0.358
const PLAUSIBLE_K2_MAX := 0.460

## mm³ → m³, for converting the blade-volume integral to SI.
const MM3_TO_M3 := 1.0e-9
## mm⁵ → m⁵, for the inertia integral.
const MM5_TO_M5 := 1.0e-15
const G_TO_KG := 1.0e-3


## Blade mass in grams — the number P1's falsification compares against `published_mass_g`.
## Grams because that is what the catalog publishes and what a builder's scale reads.
static func blade_mass_g(doc: PropellerDocument, materials: FrameMaterials) -> float:
	if doc == null or materials == null:
		return 0.0
	var rho := materials.density(doc.material_id)
	if rho <= 0.0:
		return 0.0
	var integral := integral_c2_mm3(doc)
	var mass_kg := float(doc.blades) * rho * doc.thickness_ratio * integral * MM3_TO_M3
	return mass_kg / G_TO_KG


## Blade inertia about the spin axis, kg·m² — §3.3's J_blade, the "larger half of spin-up on most
## builds". Computed from the planform's own second moment; §3.3 then replaces the scale factor with
## the published mass, which is why `radius_of_gyration_sq` exists as the shape-only form.
static func blade_inertia_kg_m2(doc: PropellerDocument, materials: FrameMaterials) -> float:
	if doc == null or materials == null:
		return 0.0
	var rho := materials.density(doc.material_id)
	if rho <= 0.0:
		return 0.0
	# integral_c2_r2_mm5 already includes the R³ factor — it returns ∫c²r²dr in mm⁵ directly.
	# Convert mm⁵ → m⁵.
	var integral_m5 := integral_c2_r2_mm5(doc) * MM5_TO_M5
	return float(doc.blades) * rho * doc.thickness_ratio * integral_m5


## The dimensionless radius of gyration, k² — J/(m·R²), shape-only and scale-free.
##
## This is §3.3's whole question. It is an honest number for a GENERATED planform only in the
## "characteristic" sense P2 establishes — it sits where it sits, and if the generated shape is not
## representative of a real FPV planform, the band (not this value) is the error bar. A builder who
## authors a real planform gets an engineering-grade k² from this same function.
static func radius_of_gyration_sq(doc: PropellerDocument) -> float:
	if doc == null or doc.chord.size() < 4:
		return 0.0
	var c2 := integral_c2_mm3(doc)
	if c2 <= 0.0:
		return 0.0
	# k² = [∫c²r²dr] / [R²·∫c²dr]. Both integrals are in real-mm space (mm⁵ and mm³), so R does not
	# cancel by itself — it is divided out here.
	var radius_mm := doc.radius_mm()
	return integral_c2_r2_mm5(doc) / (radius_mm * radius_mm * c2)


## ∫ c(r)² dr in mm³, over the planform's own span. The kernel both mass figures reduce to.
##
## c(r) is piecewise linear between the document's (r/R, chord_mm) points, so c(r)² is piecewise
## quadratic and each segment integrates in closed form — no quadrature error, and the exact closed
## forms the tests assert are reproduced to machine precision.
static func integral_c2_mm3(doc: PropellerDocument) -> float:
	var pts := doc.chord_points()
	if pts.size() < 2:
		return 0.0
	var radius_mm := doc.radius_mm()
	var total := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		# Segment in r (mm): x goes x0→x1 (r/R), c goes c0→c1 (mm).
		#   ∫_{x0}^{x1} c(x)² dx = (x1-x0) · (c0² + c0·Δc + Δc²/3), Δc = c1−c0
		var dx := (b.x - a.x) * radius_mm
		var dc := b.y - a.y
		total += dx * (a.y * a.y + a.y * dc + dc * dc / 3.0)
	return total


## ∫ c(r)² r² dr in mm⁵, the second-moment kernel behind blade inertia and k².
##
## Same piecewise-linear-exact approach: over a segment c(t) = c0 + Δc·t and x(t) = x0 + Δx·t with
## t ∈ [0,1], the integrand c²·x² is a quartic in t, integrated in closed form. The coefficients are
## the expansion of (c0+Δc·t)²·(x0+Δx·t)².
static func integral_c2_r2_mm5(doc: PropellerDocument) -> float:
	var pts := doc.chord_points()
	if pts.size() < 2:
		return 0.0
	var radius_mm := doc.radius_mm()
	var total := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dx := b.x - a.x
		var c0 := a.y
		var dc := b.y - a.y
		var x0 := a.x
		# (c0 + dc·t)² = c0² + 2·c0·dc·t + dc²·t²
		# (x0 + dx·t)² = x0² + 2·x0·dx·t + dx²·t²
		var c_t0 := c0 * c0
		var c_t1 := 2.0 * c0 * dc
		var c_t2 := dc * dc
		var x_t0 := x0 * x0
		var x_t1 := 2.0 * x0 * dx
		var x_t2 := dx * dx
		# ∫₀¹ t^n dt = 1/(n+1). The R³ factor converts the dimensionless-x integral to mm⁵.
		total += dx * radius_mm * radius_mm * radius_mm * (
			(c_t0 * x_t0) / 1.0
			+ (c_t0 * x_t1 + c_t1 * x_t0) / 2.0
			+ (c_t0 * x_t2 + c_t1 * x_t1 + c_t2 * x_t0) / 3.0
			+ (c_t1 * x_t2 + c_t2 * x_t1) / 4.0
			+ (c_t2 * x_t2) / 5.0
		)
	return total


## §3.3's PREFERRED inertia form, and the one the panel must show: `J = m_published · k² · R²`.
##
## `blade_inertia_kg_m2` above builds J from the planform's own mass, which is correct arithmetic
## and the wrong number to put on screen for a PRESET. §3.1 measured the generated planform's mass
## at 0.17–1.18× published — the hub is real mass and is absent from every integral here — so an
## inertia built from it carries that error ON TOP OF the shape error in k². Splitting the two is
## what makes the honest version possible: mass is published, R is published, and only k² is
## assumed, so exactly one assumption reaches the answer instead of two.
##
## Returns 0.0 when there is no published mass. A blade somebody drew has no vendor, and this
## function cannot invent one — the caller shows "no published mass" rather than a number.
static func blade_inertia_from_published_kg_m2(doc: PropellerDocument) -> float:
	if doc == null or doc.published_mass_g <= 0.0:
		return 0.0
	var radius_m := doc.radius_mm() * 0.001
	return doc.published_mass_g * G_TO_KG * radius_of_gyration_sq(doc) * radius_m * radius_m


## Where along the blade the chord peaks, as r/R — the single number that decides where k² lands,
## and therefore the finding §3.3 reports. The generator's sine arch peaks at ≈0.46 R; every
## planform in the plausible family peaks at 0.60–0.75 R. Exposed because a k² outside the band is
## only interpretable next to the shape that produced it.
static func peak_chord_station(doc: PropellerDocument) -> float:
	if doc == null:
		return 0.0
	var best_x := 0.0
	var best_c := -1.0
	for pt in doc.chord_points():
		if pt.y > best_c:
			best_c = pt.y
			best_x = pt.x
	return best_x


## The widest chord on the blade, mm. Paired with `peak_chord_station` for the planform row.
static func peak_chord_mm(doc: PropellerDocument) -> float:
	if doc == null:
		return 0.0
	var best_c := 0.0
	for pt in doc.chord_points():
		best_c = maxf(best_c, pt.y)
	return best_c


## ===========================================================================
## WHERE THE MASS IS, AND WHAT IT DOES WHEN IT IS NOT QUITE WHERE IT SHOULD BE (Prop Designer PD4)
## ===========================================================================
##
## Solid rectangular section, the same law as the mass above: a section's area is
## `thickness_ratio·c`·`c`, so section mass goes as c², not c. A real airfoil is lighter than this
## rectangle, which is why every figure below is an estimate on screen. Nothing here changes mass,
## inertia or k², so no preset figure moves.


## Chord at r/R, mm, by the same straight lines the integrals assume. Zero outside the drawn span:
## there is no material where nobody drew a blade.
static func chord_mm_at(doc: PropellerDocument, r_frac: float) -> float:
	if doc == null:
		return 0.0
	var pts := doc.chord_points()
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if r_frac >= a.x and r_frac <= b.x and b.x > a.x:
			return lerpf(a.y, b.y, (r_frac - a.x) / (b.x - a.x))
	return 0.0


## One blade's mass per millimetre of span at r/R, g/mm. Integrates to `single_blade_mass_g`.
static func section_mass_g_per_mm(doc: PropellerDocument, materials: FrameMaterials,
		r_frac: float) -> float:
	if doc == null or materials == null:
		return 0.0
	var c := chord_mm_at(doc, r_frac)
	return materials.density(doc.material_id) * doc.thickness_ratio * c * c * MM3_TO_M3 / G_TO_KG


## ∫ c(r)² r dr in mm⁴, the first-moment kernel behind the blade CG. Exact on each straight segment,
## like the two integrals above.
static func integral_c2_r_mm4(doc: PropellerDocument) -> float:
	var pts := doc.chord_points()
	if pts.size() < 2:
		return 0.0
	var radius_mm := doc.radius_mm()
	var total := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dx := b.x - a.x
		var c0 := a.y
		var dc := b.y - a.y
		var x0 := a.x
		# (c0 + dc·t)²·(x0 + dx·t), integrated over t in [0,1].
		total += dx * radius_mm * radius_mm * (
			c0 * c0 * x0
			+ (c0 * c0 * dx + 2.0 * c0 * dc * x0) / 2.0
			+ (2.0 * c0 * dc * dx + dc * dc * x0) / 3.0
			+ dc * dc * dx / 4.0
		)
	return total


## One blade's mass in grams. `blade_mass_g` is the whole set.
static func single_blade_mass_g(doc: PropellerDocument, materials: FrameMaterials) -> float:
	if doc == null or doc.blades <= 0:
		return 0.0
	return blade_mass_g(doc, materials) / float(doc.blades)


## How far out one blade's centre of mass sits, mm from the axis: ∫c²r dr / ∫c²dr. Shape only.
## Uniform chord gives R/2, a triangle with its apex at the root 3R/4, apex at the tip R/4.
static func blade_cg_mm(doc: PropellerDocument) -> float:
	if doc == null:
		return 0.0
	var c2 := integral_c2_mm3(doc)
	if c2 <= 0.0:
		return 0.0
	return integral_c2_r_mm4(doc) / c2


## The whole prop's mass from geometry: blades plus a hub, which is a guess the caller holds in a
## field. This is not `published_mass_g`; a shelf prop's published figure stays what it flies on.
static func prop_mass_g(doc: PropellerDocument, materials: FrameMaterials, hub_g: float) -> float:
	return blade_mass_g(doc, materials) + maxf(hub_g, 0.0)


## How far the whole prop's CG sits off the axis, mm, when one blade is `heavy_mg` over. A set with
## no error sits on the axis by symmetry and the hub sits there anyway, so only the error moves it.
static func prop_cg_offset_mm(doc: PropellerDocument, materials: FrameMaterials, hub_g: float,
		heavy_mg: float) -> float:
	var extra_g := heavy_mg * 0.001
	var total_g := prop_mass_g(doc, materials, hub_g) + extra_g
	if total_g <= 0.0:
		return 0.0
	return extra_g * blade_cg_mm(doc) / total_g


## The 1x force of an offset mass: F = m·r·ω², newtons. The law FlightLaw.vibration_rate forces with.
static func imbalance_force_n(mass_mg: float, arm_mm: float, rpm: float) -> float:
	var omega := rpm * TAU / 60.0
	return mass_mg * 1.0e-6 * arm_mm * 0.001 * omega * omega


## A blade `heavy_mg` over carries that mass at its CG, while the build's `prop_imbalance_g` means a
## mass at the blade RADIUS. This converts one to the other at equal force, so a tolerance cannot
## reach the vibration model overstated by R / r_cg.
static func imbalance_g_at_radius(doc: PropellerDocument, heavy_mg: float) -> float:
	if doc == null or doc.radius_mm() <= 0.0:
		return 0.0
	return heavy_mg * 0.001 * blade_cg_mm(doc) / doc.radius_mm()


## The couple from one blade running out of track, N·m. `tip_error_mm` is what a builder measures
## at the tip; a blade flapped rigidly about its root has its CG out of the disc plane by
## tip·r_cg/R, and its centrifugal force m·r_cg·ω² acts at that height.
static func tracking_couple_nm(doc: PropellerDocument, materials: FrameMaterials,
		tip_error_mm: float, rpm: float) -> float:
	if doc == null or doc.radius_mm() <= 0.0:
		return 0.0
	var r_cg := blade_cg_mm(doc)
	var force_n := imbalance_force_n(single_blade_mass_g(doc, materials) * 1000.0, r_cg, rpm)
	return force_n * tip_error_mm * (r_cg / doc.radius_mm()) * 0.001


## The 1x force this BUILD's imbalance makes, read through the same model the gyro shakes with, so
## the figure and the vibration cannot be two numbers.
static func build_imbalance_force_n(build: Build, rpm: float) -> float:
	var model := VibrationModel.for_build(build)
	return imbalance_force_n(model.imbalance_kg * 1.0e6, model.prop_radius_m * 1000.0, rpm)


## Sets the build's imbalance. It stays a build value (see DEFAULT_ASSEMBLY); no prop record learns it.
static func set_build_imbalance(build: Build, imbalance_g: float) -> void:
	var resolved := build.assembly.duplicate()
	resolved["prop_imbalance_g"] = imbalance_g
	build.set_assembly(resolved)
