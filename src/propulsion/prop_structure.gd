class_name PropStructure
extends RefCounted
## PD5: whether a blade survives its rpm, and the exact figures that go with it. No UI.
##
## The blade is a beam clamped at its root: the first drawn chord station, where the BEMT's own
## annuli start. Section is the solid rectangle the mesh and the mass integrals already use, chord c
## wide and t = thickness_ratio·c thick, so A = τc² and everything here shares one mass law.
##
##     centrifugal   σc = ρ·τ·ω²·∫c²r dr / A(root), root to tip
##     bending       σb = M / Z, M from this blade's share of the BEMT thrust at each station
##     section       Z = c·t²/6 and I = c·t³/12, flatwise: thrust bends a blade across its thickness
##     flex          δ = ∫ M(r)/(E·I(r))·(R − r) dr
##
## Stress is the tension-side fibre, σc + σb, against the material's table strength.
##
## All of it is *(est.)* and stays so on screen. Left out, and stated here so nobody assumes them:
## blade pitch tilting the section's axes, in-plane bending from torque, centrifugal stiffening
## (δ reads high), a moulded root that is thicker than the mid-blade's t/c (stress reads high), any
## waist narrower than the root, and layer lines in a printed part. Flex does not reach the aero.

## Midpoint cells along the span. Enough for 1e-4 on the closed forms.
const SPAN_CELLS := 400
const OVERSPEED_TOLERANCE := 1e-9
const OVERSPEED_STEPS := 30

const REASON_RPM := "Set an rpm above zero."
const REASON_ROOT := "This blade has no section at its root."
const REASON_NO_STRENGTH := "This material has no strength figure, so it has no safety factor."
const REASON_NO_MODULUS := "This material has no stiffness figure, so it has no flex figure."
const REASON_OVERSPEED := "No overspeed figure: the factor never settled at 1."


## Everything at one rpm, static air. `{ok, reason}` plus `centrifugal_mpa, bending_mpa, stress_mpa,
## strength_mpa, factor, overspeed_rpm, flex_mm, flex_pct_radius` and the exact figures.
static func assess(doc: PropellerDocument, materials: FrameMaterials, rpm: float) -> Dictionary:
	if rpm <= 0.0:
		return _refuse(REASON_RPM)
	if root_chord_mm(doc) <= 0.0 or doc.thickness_ratio <= 0.0:
		return _refuse(REASON_ROOT)
	var strength := materials.strength_mpa(doc.material_id)
	if strength <= 0.0:
		return _refuse(REASON_NO_STRENGTH)
	var modulus := materials.modulus_gpa(doc.material_id)
	if modulus <= 0.0:
		return _refuse(REASON_NO_MODULUS)
	var g := PropTunnel.geometry_of(doc)
	var at := _stress(doc, materials, g, rpm)
	if not at.ok:
		return at
	var loads: Array = at.loads
	var flex := tip_flex_mm(doc, modulus, loads)
	var overspeed := overspeed_rpm(doc, materials, rpm)
	var out := {
		"ok": true, "reason": "", "rpm": rpm,
		"centrifugal_mpa": at.centrifugal_mpa, "bending_mpa": at.bending_mpa, "stress_mpa": at.stress_mpa,
		"strength_mpa": strength, "factor": strength / at.stress_mpa, "overspeed_rpm": overspeed,
		"flex_mm": flex, "flex_pct_radius": flex / doc.radius_mm() * 100.0,
		"tip_speed_mps": tip_speed_mps(doc, rpm),
		"tip_mach": PropTunnel.tip_mach(doc.diameter_mm * 0.001, rpm),
		"blade_pass_hz": blade_pass_hz(doc, rpm),
	}
	return out


## The rpm where the factor reaches 1, or -1 if it never settles. Stress goes nearly as ω², so each
## step lands close; the real solve is rerun each step because thrust is not exactly ω².
static func overspeed_rpm(doc: PropellerDocument, materials: FrameMaterials, from_rpm: float) -> float:
	var strength := materials.strength_mpa(doc.material_id)
	if strength <= 0.0 or from_rpm <= 0.0:
		return -1.0
	var g := PropTunnel.geometry_of(doc)
	var rpm := from_rpm
	for i in OVERSPEED_STEPS:
		var at := _stress(doc, materials, g, rpm)
		if not at.ok or at.stress_mpa <= 0.0:
			return -1.0
		var factor: float = strength / at.stress_mpa
		if absf(factor - 1.0) < OVERSPEED_TOLERANCE:
			return rpm
		rpm *= sqrt(factor)
	return -1.0


## Exact: the tone the blades make, Hz.
static func blade_pass_hz(doc: PropellerDocument, rpm: float) -> float:
	return float(doc.blades) * rpm / 60.0


static func tip_speed_mps(doc: PropellerDocument, rpm: float) -> float:
	return rpm * TAU / 60.0 * doc.radius_mm() * 0.001


## The clamp, mm from the axis.
static func root_mm(doc: PropellerDocument) -> float:
	return doc.chord[0] * doc.radius_mm() if doc.chord.size() >= 2 else 0.0


static func root_chord_mm(doc: PropellerDocument) -> float:
	return doc.chord[1] if doc.chord.size() >= 2 else 0.0


## Flatwise, the weak axis, mm³.
static func section_modulus_mm3(chord_mm: float, thickness_ratio: float) -> float:
	var t := thickness_ratio * chord_mm
	return chord_mm * t * t / 6.0


## Flatwise, mm⁴.
static func second_moment_mm4(chord_mm: float, thickness_ratio: float) -> float:
	var t := thickness_ratio * chord_mm
	return chord_mm * t * t * t / 12.0


## Pull at the root, newtons: the mass outboard of it, swung at ω.
static func centrifugal_force_n(doc: PropellerDocument, density_kg_m3: float, rpm: float) -> float:
	var omega := rpm * TAU / 60.0
	var root := root_mm(doc)
	var dr := (doc.radius_mm() - root) / float(SPAN_CELLS)
	var first_moment_mm4 := 0.0
	for i in SPAN_CELLS:
		var r := root + (float(i) + 0.5) * dr
		var c := BladeGeometry.chord_mm_at(doc, r / doc.radius_mm())
		first_moment_mm4 += c * c * r * dr
	return density_kg_m3 * doc.thickness_ratio * first_moment_mm4 * 1e-12 * omega * omega


## N·mm at `r_mm` from `[[r_mm, force_n], …]`, the loads outboard of it.
static func bending_moment_nmm(loads: Array, r_mm: float) -> float:
	var moment := 0.0
	for entry in loads:
		if float(entry[0]) > r_mm:
			moment += float(entry[1]) * (float(entry[0]) - r_mm)
	return moment


## Tip deflection, mm, for loads on one blade. Modulus in GPa, so N·mm² on the bottom.
static func tip_flex_mm(doc: PropellerDocument, modulus_gpa: float, loads: Array) -> float:
	var root := root_mm(doc)
	var tip := doc.radius_mm()
	var dr := (tip - root) / float(SPAN_CELLS)
	var total := 0.0
	for i in SPAN_CELLS:
		var r := root + (float(i) + 0.5) * dr
		var inertia := second_moment_mm4(BladeGeometry.chord_mm_at(doc, r / tip), doc.thickness_ratio)
		if inertia > 0.0:
			total += bending_moment_nmm(loads, r) / (modulus_gpa * 1000.0 * inertia) * (tip - r) * dr
	return total


static func _stress(doc: PropellerDocument, materials: FrameMaterials, g: Dictionary, rpm: float) -> Dictionary:
	var solved := PropTunnel.stations(g, rpm, 0.0)
	if not solved.ok:
		return solved
	var loads: Array = []
	for row in solved.stations:
		loads.append([float(row.r_m) * 1000.0, float(row.thrust_n) / float(doc.blades)])
	var chord := root_chord_mm(doc)
	var area := doc.thickness_ratio * chord * chord
	var centrifugal := centrifugal_force_n(doc, materials.density(doc.material_id), rpm) / area
	var bending := bending_moment_nmm(loads, root_mm(doc)) \
		/ section_modulus_mm3(chord, doc.thickness_ratio)
	return {"ok": true, "centrifugal_mpa": centrifugal, "bending_mpa": bending,
		"stress_mpa": centrifugal + bending, "loads": loads}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
