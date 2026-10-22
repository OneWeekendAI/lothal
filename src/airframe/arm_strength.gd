class_name ArmStrength
extends RefCounted
## How hard an arm is to break, said against frames a builder knows (airframe gaps G4, airframe.md §4.5).
##
## ## Why not MPa
##
## The Arms page already prints root stress per newton. It is correct and nobody can use it: a
## builder does not know what 4.2 MPa/N means for their arm, and the only thing they would do with it
## is compare it against another frame's — which they cannot, because no vendor prints one. So this
## file does that comparison for them. It computes ONE capacity figure per arm, computes the same
## figure for every plate frame in the catalog from the preset the app already generates for it, and
## says where the arm falls: "about as strong as the 5" Freestyle, stronger than 9 of 14".
##
## ## The capacity figure
##
## The tip load that first brings some section of the arm to the material's strength:
##
##     F_break = min over s of  sigma_u * b(s) * t^2 / (6 * (L - s))
##
## — `ArmBeam.bending_stress_pa` per newton, inverted, at every authored station. The minimum is
## taken over the whole span, not only the root: a necked arm (a lightening cut, a narrow waist
## between root and motor) breaks at the neck, and a root-only figure would rank it as strong as the
## un-necked arm. On a piecewise-linear width profile b/(L-s) is linear-over-linear on each segment
## and so monotone there, which means the minimum lies ON a station: checking the stations is exact,
## not a sampling. The tip station (s = L, zero moment) is excluded.
##
## Also reported: the ROOT MOMENT CAPACITY, sigma_u * b(0) * t^2 / 6 — the bending moment the root
## section takes before it reaches strength. Both are ENGINEERING-GRADE physics (§8: root stress is
## a standard closed form) multiplied by a strength figure whose own tier is read from
## materials.json (`FrameMaterials.strength_tier`) and printed beside it.
##
## ## What this does NOT say, and must never say
##
## A crash is an impact. How hard an arm is hit depends on the motor's mass, the speed, what it lands
## on and how much the frame gives — none of which is modelled. §4.5's crash case is an `n`-g tip
## load with `n` a stated assumption, CHARACTERISTIC. So this file never names a fall height and never
## says an arm "survives" anything. It says which arms are stronger than which, under the same tip
## load: a RANKING (§8 characteristic), and the page footnote says so in those words.
##
## ## The references, honestly
##
## Every reference is a catalog frame's GENERATED preset (`AirframeDocument.from_catalog_frame`):
## its arm thickness is sourced (A2b), but its arm WIDTH is the generator's assumption for every
## frame that publishes none — which is all of them but one (§9a). The ranking is therefore against
## what the app believes those frames are, and the page says that, rather than implying the vendor's
## real arm was measured. Moulded frames (the 65 mm whoop) have no plate arm and are left out, and
## the count says "of N plate frames" so the omission is visible.

## Within this fraction of a reference's capacity, the arm is "about as strong as" it. Beyond it the
## wording becomes "between A and B". Not fitted to anything: ±10% is half the ±20% §8 allows the
## engineering-grade stress itself, so "about as strong" never claims more precision than the physics
## underneath has.
const ABOUT_SAME_FRACTION := 0.10

## A drawn arm belongs to a size class when the nearest catalog frame's arm length is within this
## fraction of its own AND every catalog frame inside that window is of the same `size_class`. When
## either fails, the class is not decidable and the comparison is against all frames (the brief:
## compare against all rather than guess a class).
const CLASS_ARM_FRACTION := 0.10

## Two references closer than this are the same capacity to print (the 5" Deadcat and the Evoque F5
## V3 are both 6 mm arms at 118 mm on the same generator — the same arm). Relative.
const TIE_FRACTION := 1.0e-6

## How the strength figure is labelled when materials.json states no tier for it. Not
## "engineering": an unstated tier is not a claimed one.
const UNSTATED_TIER := "tier unstated"

static var _default_references: Array = []
static var _shared_materials: FrameMaterials


## The shipped material table, loaded once — for callers (FrameWarnings) that are handed no table.
static func shared_materials() -> FrameMaterials:
	if _shared_materials == null:
		_shared_materials = FrameMaterials.load_default()
	return _shared_materials


# ---------------------------------------------------------------------------
# The arm
# ---------------------------------------------------------------------------

## The first arm plate of a document as a beam, measured off its own outline, or null. The ONE
## definition — `AirframePanel.arm_beam` calls this, so the Arms page and the reference table cannot
## be measuring two different arms.
static func beam_of(document: AirframeDocument, materials: FrameMaterials) -> ArmBeam:
	if document == null:
		return null
	for plate in document.plates:
		if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
			continue
		if not plate.has("root_point") or not plate.has("tip_point"):
			return null
		var root := AirframeDocument.point_of(plate["root_point"])
		var tip := AirframeDocument.point_of(plate["tip_point"])
		var outline: PackedFloat64Array = plate.get("outline", PackedFloat64Array())
		return ArmProfile.beam_flat(
			outline, root.x, root.y, tip.x, tip.y,
			AirframeDocument.plate_thickness_mm(plate),
			document.plate_material_id(plate),
			materials)
	return null


## The capacity of one arm. `known` false when the beam is missing or its material quotes no
## strength — "not answerable", never a zero that would rank as the weakest arm on the list.
static func capacity(beam: ArmBeam, materials: FrameMaterials) -> Dictionary:
	var out := {
		"known": false, "break_load_n": 0.0, "root_moment_nm": 0.0, "weakest_s_m": 0.0,
		"length_m": 0.0, "strength_mpa": 0.0, "strength_tier": UNSTATED_TIER,
	}
	if beam == null or not beam.is_valid() or materials == null:
		return out
	var strength_mpa := materials.strength_mpa(beam.material_id)
	out["length_m"] = beam.length_m
	out["strength_mpa"] = strength_mpa
	out["strength_tier"] = strength_tier_of(materials, beam.material_id)
	if strength_mpa <= 0.0:
		return out
	var strength_pa := strength_mpa * 1.0e6

	var best := INF
	var best_s := 0.0
	for i in range(beam.profile_s_m.size()):
		var s: float = beam.profile_s_m[i]
		if s >= beam.length_m:
			continue
		# Stress per newton at this station, from ArmBeam's own §4.5 law.
		var per_newton := beam.bending_stress_pa(1.0, s)
		if per_newton <= 0.0:
			continue
		var force := strength_pa / per_newton
		if force < best:
			best = force
			best_s = s
	if not is_finite(best):
		return out

	var root_b := beam.width_at(0.0)
	out["known"] = true
	out["break_load_n"] = best
	out["weakest_s_m"] = best_s
	out["root_moment_nm"] = strength_pa * root_b * beam.thickness_m * beam.thickness_m / 6.0
	return out


## materials.json's `catalog.strength_tier` for a material, or UNSTATED_TIER.
static func strength_tier_of(materials: FrameMaterials, material_id: String) -> String:
	var tier := str((materials.get_material(material_id).get("catalog", {}) as Dictionary).get(
		"strength_tier", ""))
	return tier if tier != "" else UNSTATED_TIER


# ---------------------------------------------------------------------------
# The references
# ---------------------------------------------------------------------------

## Every plate frame in `catalog` with an analysable arm, weakest first: `{part_id, name,
## size_class, arm_mm, break_load_n, root_moment_nm, width_assumed}`. The order is stable — ties
## are broken by part_id — so a rank is a function of the data and not of dictionary iteration.
static func references(catalog: PartsCatalog, materials: FrameMaterials) -> Array:
	return references_of_frames(catalog.list_category("frame"), materials)


## `references` over a plain list of frame records — the seam a test uses to hand in a tie.
static func references_of_frames(frames: Array, materials: FrameMaterials) -> Array:
	var out: Array = []
	for frame in frames:
		var document := AirframeDocument.from_catalog_frame(frame)
		var beam := beam_of(document, materials)
		var cap := capacity(beam, materials)
		if not bool(cap["known"]):
			continue
		var assumed := false
		for plate in document.plates:
			if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
				assumed = bool(plate.get(AirframeDocument.PLATE_WIDTH_ASSUMED, false))
				break
		out.append({
			"part_id": str(frame.get("part_id", "")),
			"name": str(frame.get("name", "")),
			"size_class": str((frame.get("catalog", {}) as Dictionary).get("size_class", "")),
			"arm_mm": float((frame.get("specs", {}) as Dictionary).get("arm_mm", 0.0)),
			"break_load_n": float(cap["break_load_n"]),
			"root_moment_nm": float(cap["root_moment_nm"]),
			"width_assumed": assumed,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["break_load_n"]) != float(b["break_load_n"]):
			return float(a["break_load_n"]) < float(b["break_load_n"])
		return str(a["part_id"]) < str(b["part_id"]))
	return out


## The shipped catalog's references, computed once. Shipped only — never a builder's custom frames,
## which would make one builder's rating move when they add a part.
static func default_references(materials: FrameMaterials) -> Array:
	if _default_references.is_empty():
		_default_references = references(PartsCatalog.load_default(), materials)
	return _default_references


## The size class an arm of `arm_mm` belongs to: `{clean, size_class, members}`. `members` are the
## references to compare against for the weaker-than-class note — the class's frames when the class
## is decidable, otherwise every reference.
static func size_class_of(arm_mm: float, refs: Array) -> Dictionary:
	var all := {"clean": false, "size_class": "", "members": refs.duplicate()}
	if arm_mm <= 0.0 or refs.is_empty():
		return all
	var nearest: Dictionary = {}
	var nearest_gap := INF
	for ref in refs:
		var gap := absf(float(ref["arm_mm"]) - arm_mm) / arm_mm
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = ref
	if nearest_gap > CLASS_ARM_FRACTION:
		return all
	var size_class := str(nearest["size_class"])
	if size_class == "":
		return all
	for ref in refs:
		var gap := absf(float(ref["arm_mm"]) - arm_mm) / arm_mm
		if gap <= CLASS_ARM_FRACTION and str(ref["size_class"]) != size_class:
			# Two classes inside the window: an arm between a 3" and a 3.5" is not either.
			return all
	var members: Array = []
	for ref in refs:
		if str(ref["size_class"]) == size_class:
			members.append(ref)
	return {"clean": true, "size_class": size_class, "members": members}


# ---------------------------------------------------------------------------
# The rating
# ---------------------------------------------------------------------------

## Where this arm sits among `refs`. Keys: `known`, the capacity's own keys, `stronger_than` (count
## of references with a strictly lower capacity), `total`, `nearest` (Array of names at the nearest
## capacity), `nearest_ratio` (this / nearest), `phrase` (the sentence's comparison half),
## `size_class`, `class_clean`, `class_count`, `weaker_than_class`, `class_weakest` (name).
static func rate(beam: ArmBeam, materials: FrameMaterials, refs: Array) -> Dictionary:
	var cap := capacity(beam, materials)
	var out := cap.duplicate()
	out["total"] = refs.size()
	out["stronger_than"] = 0
	out["nearest"] = []
	out["nearest_ratio"] = 0.0
	out["phrase"] = ""
	out["size_class"] = ""
	out["class_clean"] = false
	out["class_count"] = 0
	out["weaker_than_class"] = false
	out["class_weakest"] = ""
	if not bool(cap["known"]) or refs.is_empty():
		return out
	var force := float(cap["break_load_n"])

	var stronger_than := 0
	for ref in refs:
		if float(ref["break_load_n"]) < force * (1.0 - TIE_FRACTION):
			stronger_than += 1
	out["stronger_than"] = stronger_than

	# Nearest on a LOG scale: 2x and 0.5x are equally far. Every reference tied at that distance is
	# named, so a tie is never resolved by list order into a claim about one frame.
	var best_gap := INF
	for ref in refs:
		best_gap = minf(best_gap, absf(log(float(ref["break_load_n"]) / force)))
	var nearest: Array = []
	var nearest_load := 0.0
	for ref in refs:
		if absf(log(float(ref["break_load_n"]) / force)) <= best_gap + TIE_FRACTION:
			nearest.append(str(ref["name"]))
			nearest_load = float(ref["break_load_n"])
	out["nearest"] = nearest
	out["nearest_ratio"] = force / nearest_load
	out["phrase"] = _phrase(force, refs, nearest)

	var size := size_class_of(beam.length_m * 1000.0, refs)
	var members: Array = size["members"]
	out["size_class"] = size["size_class"]
	out["class_clean"] = size["clean"]
	out["class_count"] = members.size()
	var weakest: Dictionary = {}
	for ref in members:
		if weakest.is_empty() or float(ref["break_load_n"]) < float(weakest["break_load_n"]):
			weakest = ref
	if not weakest.is_empty():
		out["class_weakest"] = str(weakest["name"])
		# STRICTLY below the weakest of the class, beyond the tie band: an arm equal to the class's
		# weakest IS in the class's range, and saying otherwise about a catalog frame's own preset
		# would be the note firing on the frame it is measured against.
		out["weaker_than_class"] = force < float(weakest["break_load_n"]) * (1.0 - TIE_FRACTION)
	return out


static func _phrase(force: float, refs: Array, nearest: Array) -> String:
	var weakest: Dictionary = refs[0]
	var strongest: Dictionary = refs[refs.size() - 1]
	var near_load := 0.0
	for ref in refs:
		if str(ref["name"]) == str(nearest[0]):
			near_load = float(ref["break_load_n"])
	if absf(force / near_load - 1.0) <= ABOUT_SAME_FRACTION:
		return "about as strong as the %s" % _names(nearest)
	if force < float(weakest["break_load_n"]):
		return "weaker than all (%.0f%% of the %s)" % [
			force / float(weakest["break_load_n"]) * 100.0, str(weakest["name"])]
	if force > float(strongest["break_load_n"]):
		return "stronger than all (%.1f× the %s)" % [
			force / float(strongest["break_load_n"]), str(strongest["name"])]
	# refs are sorted weakest first: the last one at or below, and the first one above.
	var below: Dictionary = weakest
	var above: Dictionary = strongest
	for ref in refs:
		if float(ref["break_load_n"]) <= force:
			below = ref
	for i in range(refs.size() - 1, -1, -1):
		if float(refs[i]["break_load_n"]) > force:
			above = refs[i]
	return "between the %s and the %s" % [str(below["name"]), str(above["name"])]


static func _names(names: Array) -> String:
	if names.size() == 1:
		return str(names[0])
	if names.size() == 2:
		return "%s and the %s" % [str(names[0]), str(names[1])]
	return "%s and %d others" % [str(names[0]), names.size() - 1]


## The CHARACTERISTIC note for FrameWarnings: this arm breaks under a lower tip load than every frame
## of its size class in the catalog — or, when no class can be decided cleanly (`size_class_of`),
## than every catalog frame. Null when it does not, or when nothing is answerable.
static func warning(document: AirframeDocument, materials: FrameMaterials,
		refs: Array = []) -> BuildWarning:
	var beam := beam_of(document, materials)
	if beam == null:
		return null
	var used := refs if not refs.is_empty() else default_references(materials)
	var rating := rate(beam, materials, used)
	if not bool(rating["known"]) or not bool(rating["weaker_than_class"]):
		return null
	var class_name_text := ("%s frame" % str(rating["size_class"])) if bool(rating["class_clean"]) \
		else "catalog frame"
	return BuildWarning.new(
		BuildWarning.Severity.CHARACTERISTIC,
		&"arm_weaker_than_class",
		("This arm breaks under a lower tip force than every %s in the catalog (%.0f N against the "
			+ "%s's %.0f N). A ranking, not a crash prediction.") % [
			class_name_text, float(rating["break_load_n"]), str(rating["class_weakest"]),
			_load_of(used, str(rating["class_weakest"]))],
		{"size_class": str(rating["size_class"]), "class_clean": bool(rating["class_clean"]),
			"break_load_n": float(rating["break_load_n"]),
			"class_weakest": str(rating["class_weakest"])})


static func _load_of(refs: Array, frame_name: String) -> float:
	for ref in refs:
		if str(ref["name"]) == frame_name:
			return float(ref["break_load_n"])
	return 0.0
