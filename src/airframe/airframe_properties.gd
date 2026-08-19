class_name AirframeProperties
extends RefCounted
## Mass, centre of gravity and the full 3×3 inertia tensor of an AirframeDocument, computed from
## its geometry and nothing else — airframe.md §3.2–§3.4.
##
## ## What this replaces, and why it is not a refinement of it
##
## `MassProperties` composes an aircraft out of PartMass entries, and for the frame it is handed
## ONE entry: a box at the origin, sized `arm_m × FRAME_PLATE_TO_ARM_RATIO`, weighing whatever
## `frames.json` says. That box is a stand-in for a distribution — build.gd says so at length and
## is honest about it — and it has two properties that make it un-refinable. It is at the origin,
## so it contributes exactly zero to the CG whatever the frame actually looks like. And its size is
## a RATIO chosen so the m·r² came out plausible, which means the number it produces is a number
## somebody picked, not a number anything measured.
##
## Here mass is ρ·t·A over real outlines, the CG is a real first-moment sum, and the tensor is the
## thin-plate closed form shifted by the parallel-axis theorem. Nothing in this file may be
## authored: if a quantity is not an integral of a polygon or a published density, it does not
## appear.
##
## ## THE COORDINATE TRAP (§3.4), which is the whole reason this file is dangerous
##
## Godot is Y-up. A plate lies FLAT — its outline is in the world XZ plane and its normal is world
## Y. AirframeDocument fixes the mapping: plate `u` → world X, plate `v` → world Z, `z_mm` → world
## Y. So for a plate:
##
##     the polygon's ∫v² dA  (PolygonProps "ixx")  is the world-X moment   → PITCH
##     the polygon's ∫u² dA  (PolygonProps "iyy")  is the world-Z moment   → ROLL
##     their SUM, the perpendicular-axis term,     is the world-Y moment   → YAW
##
## §3.4 writes those three as `I_xx`, `I_yy`, `I_zz` in a frame where the plate normal is z. That
## is the standard textbook framing and it is NOT this engine's frame: the doc's `I_zz` is this
## engine's `I_YY`. Read the block and the callout under it together or you will transpose them,
## and a transposed tensor is the worst kind of wrong — every number stays the right order of
## magnitude, every mass check still passes, and the aircraft rolls like it yaws. `tests/
## test_airframe_properties.gd` carries a deliberately stretched frame for exactly this, because a
## symmetric X cannot tell the two apart and every fixture anybody writes first is a symmetric X.
##
## Which body axis is which rate is physics.md §1 and MotorLayout's, not a new opinion here:
## +Pitch is about +X, +Roll is about −Z, +Yaw is about −Y. A rotation's SIGN is about a signed
## axis; a rotation's INERTIA is about an unsigned one, so `roll_inertia_kg_m2()` is `I_ZZ` and the
## minus sign is irrelevant to it. That sentence exists because the sign looks like it should
## matter and it does not.
##
## ## Doubles, deliberately
##
## Every sum here accumulates in GDScript `float`, which is a double. NOT in Vector3 and not in
## Vector2 — both are single precision, and §3.1 measures what that costs: the parallel-axis
## subtraction is a catastrophic cancellation for geometry far from the origin, ~7e-6 relative on a
## rectangle at (123, −47), and a 300 mm frame accumulates that across a dozen plates and forty
## fasteners. The tensor is packed into a `Basis` only at the very end, where it has to be to match
## what `RigidBodyState.integrate` takes, and the double-precision components stay available beside
## it for anything that wants them.

## The material a pad is cut from when it does not say. A pad is not made of the frame's material —
## falling back to the document's `material_id` would quietly weigh a foam pad as carbon — so the
## fallback is the soft material §6 actually specifies rather than the document default.
const PAD_DEFAULT_MATERIAL_ID := "tpu_95a"

const MM2_TO_M2 := 1.0e-6
const MM4_TO_M4 := 1.0e-12
const MM_TO_M := 1.0e-3
const G_TO_KG := 1.0e-3

var total_mass_kg := 0.0
## Centre of gravity in the airframe's own frame, metres, relative to the document's origin.
var cg_m := Vector3.ZERO

## The six independent components of the inertia tensor about the CG, in kg·m², as doubles.
## Named for the WORLD axes, not for the plate's — see the coordinate trap above.
var i_xx := 0.0
var i_yy := 0.0
var i_zz := 0.0
var i_xy := 0.0
var i_xz := 0.0
var i_yz := 0.0

## The same tensor as a Basis, which is the form RigidBodyState.integrate and MassProperties both
## speak. Built once at the end; single precision, and that is fine — the integrator is.
var inertia: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

## What contributed, in order: {"label", "mass_kg", "position_m"}. Inert — nothing reads it back
## into a number — so a mislabelled entry is a wrong caption and never a wrong tensor, which is the
## same posture PartMass.label takes and for the same reason. The frame bench needs it to say "the
## arms are 70% of the roll inertia" without a second derivation.
var contributions: Array = []


## Mass in grams — the number §3.2 makes a falsifiable claim about. Grams because that is what
## `frames.json` publishes and what a builder's scale reads; every other figure here is SI.
func total_mass_g() -> float:
	return total_mass_kg / G_TO_KG


## Inertia about the roll axis. Roll is rotation about the fore/aft axis (−Z), so this is I_ZZ —
## the moment built out of how far mass sits SIDEWAYS. Widen a frame laterally and this grows.
func roll_inertia_kg_m2() -> float:
	return i_zz


## Inertia about the pitch axis (+X), the moment built out of how far mass sits FORE AND AFT.
## Stretch a frame nose-to-tail and this grows.
func pitch_inertia_kg_m2() -> float:
	return i_xx


## Inertia about the yaw axis (−Y). For flat plates this is the perpendicular-axis sum of the other
## two, which is why a frame can never yaw more easily than it rolls.
func yaw_inertia_kg_m2() -> float:
	return i_yy


## Everything, from the document plus whatever else the build has positioned on it.
##
## `extra_parts` is an Array of PartMass — the motors, the stack, the camera, the pack. They are
## NOT in the AirframeDocument and must not be: a frame is a frame whatever is bolted to it, and
## the alternative is a document that changes when you fit a different camera. §3.3 is explicit
## that the pack has to stop being lumped at the origin, and this is the seam where it stops:
## whoever positions the pack passes it in already positioned.
static func compute(
	document: AirframeDocument,
	materials: FrameMaterials,
	extra_parts: Array = []
) -> AirframeProperties:
	var out := AirframeProperties.new()
	if document == null:
		return out

	# Every mass-bearing element, reduced to: how heavy, where, and its own tensor about its own
	# centroid. Two passes are unavoidable — the parallel-axis shift needs the composite CG, and
	# the composite CG needs every mass — and doing them as two explicit passes over one list is
	# what stops the second pass from disagreeing with the first about what was in the first.
	var elements: Array = []
	for plate in document.plates:
		var element: Variant = _plate_element(plate, document.plate_material_id(plate), materials,
			str(plate.get("role", "plate")))
		if element != null:
			elements.append(element)
	for pad in document.pads:
		var pad_material := str(pad.get("material_id", PAD_DEFAULT_MATERIAL_ID))
		var element: Variant = _plate_element(pad, pad_material, materials, "pad")
		if element != null:
			elements.append(element)
	for item in document.hardware:
		var element: Variant = _hardware_element(item, materials)
		if element != null:
			elements.append(element)
	for strap in document.straps:
		elements.append(_point_element(
			float(strap.get("mass_g", 0.0)) * G_TO_KG,
			AirframeDocument.point_of(strap.get("position_mm", [0.0, 0.0])),
			float(strap.get("z_mm", 0.0)),
			"strap"))
	for part in extra_parts:
		elements.append(_part_mass_element(part))

	# --- Pass one: mass and the first moments. Scalars, not a Vector3: §3.1's precision note. ---
	var mass := 0.0
	var moment_x := 0.0
	var moment_y := 0.0
	var moment_z := 0.0
	for element in elements:
		var m: float = element["mass_kg"]
		mass += m
		moment_x += m * float(element["x"])
		moment_y += m * float(element["y"])
		moment_z += m * float(element["z"])

	var cg_x := 0.0
	var cg_y := 0.0
	var cg_z := 0.0
	if mass > 0.0:
		cg_x = moment_x / mass
		cg_y = moment_y / mass
		cg_z = moment_z / mass

	# --- Pass two: the tensor, each element's own plus its parallel-axis shift to the CG. ---
	for element in elements:
		var m: float = element["mass_kg"]
		var dx := float(element["x"]) - cg_x
		var dy := float(element["y"]) - cg_y
		var dz := float(element["z"]) - cg_z
		var d_sq := dx * dx + dy * dy + dz * dz

		out.i_xx += float(element["i_xx"]) + m * (d_sq - dx * dx)
		out.i_yy += float(element["i_yy"]) + m * (d_sq - dy * dy)
		out.i_zz += float(element["i_zz"]) + m * (d_sq - dz * dz)
		out.i_xy += float(element["i_xy"]) - m * dx * dy
		out.i_xz += float(element["i_xz"]) - m * dx * dz
		out.i_yz += float(element["i_yz"]) - m * dy * dz

		out.contributions.append({
			"label": element["label"],
			"mass_kg": m,
			"position_m": Vector3(element["x"], element["y"], element["z"]),
		})

	out.total_mass_kg = mass
	out.cg_m = Vector3(cg_x, cg_y, cg_z)
	# Columns, matching MassProperties. The tensor is symmetric so rows and columns agree, but the
	# convention is stated by matching rather than by comment.
	out.inertia = Basis(
		Vector3(out.i_xx, out.i_xy, out.i_xz),
		Vector3(out.i_xy, out.i_yy, out.i_yz),
		Vector3(out.i_xz, out.i_yz, out.i_zz))
	return out


## One plate's mass and its own-centroid tensor, §3.2 and §3.4, or null if it has no material.
##
## Returning null rather than a zero-mass element is deliberate: a plate whose material_id is not
## in the table is a DOCUMENT ERROR, and weighing it as nothing would hide it behind a mass that is
## merely a bit light. A caller wanting to know can compare `contributions.size()` to the plate
## count — and A7's editor will want to, because that is a warning to draw.
static func _plate_element(
	plate: Dictionary, material_id: String, materials: FrameMaterials, label: String
) -> Variant:
	var density := materials.density(material_id)
	if density <= 0.0:
		return null

	var outline := AirframeDocument.plate_outline(plate)
	var holes := AirframeDocument.plate_holes(plate)
	# The COMPOSITE region — outline plus holes summed at the ORIGIN and shifted once. Not the sum
	# of each part's centroidal moments, which §3.1 flags as the silent bug that gives the right
	# answer for concentric holes and the wrong one for everything else.
	var region := PolygonProps.region_properties(outline, holes)

	var area_m2 := float(region["area"]) * MM2_TO_M2
	var thickness_m := AirframeDocument.plate_thickness_mm(plate) * MM_TO_M
	var mass := density * thickness_m * area_m2

	# Area moments about the composite centroid, in m⁴.
	var ixx_c := float(region["ixx_c"]) * MM4_TO_M4
	var iyy_c := float(region["iyy_c"]) * MM4_TO_M4
	var ixy_c := float(region["ixy_c"]) * MM4_TO_M4
	var rho_t := density * thickness_m

	# THE MAPPING. Read the class docs before touching these three lines.
	#   polygon ixx = ∫v² dA, v is world Z  →  world X moment (pitch)
	#   polygon iyy = ∫u² dA, u is world X  →  world Z moment (roll)
	#   their sum                            →  world Y moment (yaw), perpendicular-axis theorem
	# The m·t²/12 terms are the through-thickness contribution of §3.4. Negligible on a 2 mm plate
	# and not on a 6 mm one, and they cost one multiply, so they are always carried. The yaw term
	# gets none of it: the perpendicular-axis sum already contains both in-plane extents, and the
	# thickness lies ALONG the yaw axis, where it contributes nothing.
	var through_thickness := mass * thickness_m * thickness_m / 12.0
	var centroid: Vector2 = region["centroid"]
	var position := AirframeDocument.world_m(centroid, AirframeDocument.plate_z_mm(plate))

	return {
		"label": label,
		"mass_kg": mass,
		"x": float(position.x), "y": float(position.y), "z": float(position.z),
		"i_xx": rho_t * ixx_c + through_thickness,
		"i_yy": rho_t * (ixx_c + iyy_c),
		"i_zz": rho_t * iyy_c + through_thickness,
		# I_xz = −∫xz dm = −ρ·t·∫uv dA. The sign is the tensor convention's, and it is the opposite
		# of PolygonProps' `+∫xy dA` — §3.1's own note says having the formula in one place and its
		# sign in another is a trap, so both live on this line.
		"i_xy": 0.0,
		"i_xz": -rho_t * ixy_c,
		"i_yz": 0.0,
	}


## A screw or a standoff: its mass from HardwareMass' own geometry formulas (§5.1), at a point.
##
## No local tensor. A standoff is 20 mm long and 5.5 mm across at 25 mm from the CG, so its own
## moment is under a thousandth of its m·d² term — carrying it would be arithmetic theatre. Where
## a part's own tensor DOES matter (a motor, the pack), it arrives through `extra_parts` as a
## PartMass that already has one.
static func _hardware_element(item: Dictionary, materials: FrameMaterials) -> Variant:
	var density := materials.density(str(item.get("material_id", "")))
	if density <= 0.0:
		return null

	var mass_g := 0.0
	match str(item.get("kind", "")):
		"standoff_round":
			mass_g = HardwareMass.standoff_round_mass_g(
				float(item.get("outer_d_mm", 0.0)), float(item.get("bore_d_mm", 0.0)),
				float(item.get("length_mm", 0.0)), density)
		"standoff_hex":
			mass_g = HardwareMass.standoff_hex_mass_g(
				float(item.get("across_flats_mm", 0.0)), float(item.get("bore_d_mm", 0.0)),
				float(item.get("length_mm", 0.0)), density)
		"screw":
			mass_g = HardwareMass.screw_mass_g(
				float(item.get("thread_d_mm", 0.0)), float(item.get("shank_len_mm", 0.0)),
				float(item.get("head_d_mm", 0.0)), float(item.get("head_h_mm", 0.0)), density)
		_:
			return null

	return _point_element(
		mass_g * G_TO_KG,
		AirframeDocument.point_of(item.get("position_mm", [0.0, 0.0])),
		float(item.get("z_mm", 0.0)),
		str(item.get("kind", "hardware")))


static func _point_element(mass_kg: float, plan_mm: Vector2, z_mm: float, label: String) -> Dictionary:
	var position := AirframeDocument.world_m(plan_mm, z_mm)
	return {
		"label": label, "mass_kg": mass_kg,
		"x": float(position.x), "y": float(position.y), "z": float(position.z),
		"i_xx": 0.0, "i_yy": 0.0, "i_zz": 0.0, "i_xy": 0.0, "i_xz": 0.0, "i_yz": 0.0,
	}


## A PartMass — a motor, the stack, the pack — as an element. Its local tensor is a diagonal in
## body axes, which is what PartMass has promised since MassProperties was written; nothing here
## rotates it, and nothing may, until a part can be mounted at an angle.
static func _part_mass_element(part: PartMass) -> Dictionary:
	return {
		"label": part.label if part.label != "" else "part",
		"mass_kg": part.mass_kg,
		"x": float(part.position_m.x), "y": float(part.position_m.y), "z": float(part.position_m.z),
		"i_xx": float(part.local_inertia_diag.x),
		"i_yy": float(part.local_inertia_diag.y),
		"i_zz": float(part.local_inertia_diag.z),
		"i_xy": 0.0, "i_xz": 0.0, "i_yz": 0.0,
	}
