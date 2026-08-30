class_name PropellerDocument
extends RefCounted
## A propeller as DATA — propulsion.md §2. One fixed-geometry rotor: `N` identical blades, each a
## 1D stack of sections in `r` carrying a chord `c(r)` and a pitch `β(r)`. Deliberately shaped like
## `AirframeDocument` — same schema/persistence discipline, same no-authored-mass rule, same
## unknown-field survival — applied to the other half of the aircraft.
##
## ## Why this file has no `mass` field, and never will
##
## The same sentence as `airframe.md` §2, transplanted: **mass is computed, never typed.** The moment
## a builder can type a blade mass, the planform and the mass can disagree, and every number
## downstream — spin-up τ, the inertia sum, hover throttle — inherits the lie. So there is no
## `mass_g` here, and `BladeGeometry` computes mass from `ρ·thickness_ratio·∫c²dr` and nothing else.
##
## The corollary, again from `airframe.md`: a preset is a geometry that HAPPENS to weigh what the
## catalog says, and when it does not, that is a measurement worth reporting rather than a number
## worth editing (see `from_catalog_prop`, and §9a's precedent).
##
## ## Coordinates and units, stated once
##
## Everything here is MILLIMETRES. Diameter and pitch are the published figures converted from the
## catalog's inches. Chord is stored as points in **(r/R, chord_mm)** — a fraction of radius against
## a millimetre chord — because the planform is a shape, and normalising the radius makes the shape
## comparable across prop sizes. The first coordinate is `r/R`, so a 1.6" whoop and a 10" xoar land
## on the same c(r/R) curve when they share a planform, which is exactly the property §3.3's k²
## band exploits.
##
## ## Why chord is a flat PackedFloat64Array and not a typed object
##
## Same reason `AirframeDocument` stores outlines flat: a planform is a list of (r, chord) pairs that
## a later Lothal may author at any resolution, and an unknown future field (a camber distribution,
## a section table) must survive a save/load untouched. Holding the planform as a typed object would
## mean enumerating its fields, and every field not enumerated is a field thrown away on save.
## Doubles round-trip through JSON exactly, so "the document is unchanged" is assertable literally
## rather than approximately.

const SCHEMA_VERSION := 1

## The top-level keys this version reads. Everything else is unknown and is kept verbatim — the
## JsonStore.unknown_fields mechanism, unchanged from `airframe.md` §2.
const KNOWN_KEYS := [
	"schema", "id", "name", "author", "revision",
	"diameter_mm", "pitch_mm", "blades",
	"chord", "twist_mode", "twist",
	"material_id", "thickness_ratio", "chord_is_assumed",
	"published_mass_g",
]

## §3.2's discriminator. Default is `geometric`: `β(r) = atan(P / 2πr)` derives from pitch, which is
## what every preset and every constant-pitch helix is. `authored` exists for a real blade that
## unloads its tip; a preset never authors twist (authoring one would be inventing a spec).
const TWIST_MODE_GEOMETRIC := "geometric"
const TWIST_MODE_AUTHORED := "authored"

## Set on a planform whose chord distribution was generated rather than measured or authored. Read by
## every figure derived from the planform, in the wording §3.1 establishes: *"engineering-grade;
## blade chord assumed."* Absent means authored, which is the right default: a planform a builder
## drew has exactly the chord they drew.
const CHORD_ASSUMED := "chord_is_assumed"

var id := ""
var name := ""
var author := ""
var revision := ""
## Millimetres. The published diameter, converted from the catalog's inches — the number §7.1's disc
## plan is drawn from, and the `R` every inertia integral is normalised by.
var diameter_mm := 0.0
## Millimetres. The geometric pitch at the reference station, converted from the catalog's inches.
var pitch_mm := 0.0
## `N`, the number of identical blades.
var blades := 2

## The planform: a flat PackedFloat64Array of [r/R, chord_mm, r/R, chord_mm, …] pairs, piecewise
## linear in r/R. This is c(r), the whole shape the mesh draws and the integrals read — §0's rule,
## made true of propulsion. Generated for a preset, authored for a custom blade.
var chord := PackedFloat64Array()

## §3.2. `geometric` (default) derives β from pitch; `authored` carries an explicit twist table.
var twist_mode := TWIST_MODE_GEOMETRIC
## Flat [r/R, beta_rad, …] pairs. Present only when `twist_mode` is `authored`.
var twist := PackedFloat64Array()

## Which stock the blade is moulded from, by FrameMaterials id. Density feeds blade mass and
## inertia (`BladeGeometry`); §2.1 moves `material` out of the catalog's browsing block for exactly
## this reason — the day density is read is the day material enters `specs`.
var material_id := "polycarbonate"
## Section thickness-to-chord ratio, t/c. Scales the solid-blade mass (A(r) = c(r)·t(r),
## t = thickness_ratio·c) and will feed the drag polar (§4.2). 0.10 is the figure the mesh draws.
var thickness_ratio := 0.10

## False when the chord was authored or measured. True on every generated preset, and the flag every
## number derived from that planform must carry (see `BladeGeometry`'s callers).
var chord_is_assumed := false

## What the vendor says the whole propeller (blades plus hub) weighs, grams. ZERO FOR A BLADE
## SOMEBODY DREW, for the same reason `AirframeDocument.published_mass_g` is zero on a drawn frame.
##
## §2 bans a mass field — "mass is computed, never typed" — and this does not breach it, because
## nothing reads it into any physics. It is a CLAIM BY A THIRD PARTY, kept so the mass falsification
## can print the disagreement between it and the computed figure. A preset carries the vendor's
## number; a blade you drew has no vendor, so the comparison is not shown at all rather than shown
## against zero.
var published_mass_g := 0.0

## Fields from a file this version does not understand, kept for the save path. See class docs.
var _unknown_top: Dictionary = {}


# ---------------------------------------------------------------------------
# Geometry accessors
# ---------------------------------------------------------------------------

func radius_mm() -> float:
	return diameter_mm * 0.5


## The planform as points: an Array of Vector2(r/R, chord_mm), in file order. The boundary between
## the flat storage and everything that thinks in points.
func chord_points() -> Array:
	var out: Array = []
	var i := 0
	while i + 1 < chord.size():
		out.append(Vector2(chord[i], chord[i + 1]))
		i += 2
	return out


## c(r) by piecewise-linear interpolation of the planform, at a stated fraction of radius. Linear
## interpolation is exactly what the integrals assume, so asking `chord_at` and integrating over the
## same points cannot disagree.
##
## **It reads the flat `PackedFloat64Array` and NOT `chord_points()`, and that is not tidiness.**
## The accessor returns `Vector2`, which is SINGLE precision, so routing this function through it
## put a 4e-7 relative haircut on the one chord every caller reads — the mesh, the mass integral,
## the tip length scale the guard closure is measured against, and since P10d the room's own
## editor. It was found by the check that `PlanformEdits.insert_station` adds a point without
## MOVING the curve: inserting a station at the chord this function reported changed `c(r)`
## elsewhere by 7e-9 mm, which is float32 noise and not an insert. Small, and the wrong kind of
## small — a rounding that enters through a shared accessor is one every downstream number
## inherits.
func chord_at(r_frac: float) -> float:
	var count := chord.size()
	if count < 2:
		return 0.0
	if r_frac <= chord[0]:
		return chord[1]
	if r_frac >= chord[count - 2]:
		return chord[count - 1]
	var i := 0
	while i + 3 < count:
		var a_r: float = chord[i]
		var b_r: float = chord[i + 2]
		if r_frac >= a_r and r_frac <= b_r:
			var span := b_r - a_r
			if span <= 0.0:
				return chord[i + 1]
			var t := (r_frac - a_r) / span
			return chord[i + 1] + (chord[i + 3] - chord[i + 1]) * t
		i += 2
	return 0.0


## β(r) in radians at a stated fraction of radius. For `geometric` twist this is the helix formula
## the mesh already draws and §3.2 says is the default; for `authored` it interpolates the table.
## The ONE place the blade angle is defined — mesh, integral and Campbell line all read it here.
func beta_rad(r_frac: float) -> float:
	if twist_mode == TWIST_MODE_AUTHORED:
		return _twist_at(r_frac, twist)
	if r_frac <= 0.0 or pitch_mm <= 0.0:
		return 0.0
	var r_mm := r_frac * radius_mm()
	return atan(pitch_mm / (TAU * r_mm))


## The blade's SECTION at a stated fraction of radius: the four corners of the thin rectangle the
## blade occupies there, in millimetres, in the (chordwise, face-normal) plane of the section —
## chord wide, `thickness_ratio · chord` thick, rotated about the radial axis by `beta_rad`.
##
## THIS EXISTS SO THE SECTION IS DEFINED ONCE. `PropellerMesh` builds its vertices from these
## corners and the room's section view draws them, which is the same rule P10d applied to chord:
## the picture and the physics may not each own a copy of the same shape. Corners are returned in
## the mesh's own order — (+half chord, +half thickness) first, then anticlockwise — because the
## mesh stitches consecutive stations into faces by index and a reordering here would turn the
## blade inside out.
##
## Millimetres, not metres, on the document's own convention: `chord` is a millimetre table and a
## unit change belongs at the boundary that draws, not in the middle of the geometry.
##
## The plane's axes are (TANGENTIAL, AXIAL) in that order — `x` runs the way the blade sweeps and
## `y` is up the shaft — so the mesh maps a corner to blade-local space as `Vector3(0, v.y, v.x)`
## and nothing here has to know that the mesh's radial direction is +X.
func section_corners_mm(r_frac: float) -> PackedVector2Array:
	# `chord_mm` and `twist_rad` rather than `chord` and `twist`: both are MEMBER names on this
	# class, and `project.godot` treats shadowing as an error.
	var chord_mm := chord_at(r_frac)
	var thickness_mm := chord_mm * thickness_ratio
	var twist_rad := beta_rad(r_frac)

	# Chord direction, rotated about the radial axis by the twist: at zero twist it lies
	# tangentially and the section is flat; at 90 degrees it stands on edge.
	var chordwise := Vector2(cos(twist_rad), sin(twist_rad))
	# NOT the left-hand normal. The mesh caps its root and tip with a fixed winding and stitches
	# consecutive stations by index, so flipping this vector reverses every face's normal and turns
	# the blade inside out — a change that looks like a lighting bug and is a geometry one.
	var face := Vector2(sin(twist_rad), -cos(twist_rad))

	var out := PackedVector2Array()
	for corner in [Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]:
		out.append(chordwise * (chord_mm * corner.x) + face * (thickness_mm * corner.y))
	return out


static func _twist_at(r_frac: float, twist_table: PackedFloat64Array) -> float:
	var pts: Array = []
	var i := 0
	while i + 1 < twist_table.size():
		pts.append(Vector2(twist_table[i], twist_table[i + 1]))
		i += 2
	if pts.is_empty():
		return 0.0
	if r_frac <= pts[0].x:
		return pts[0].y
	if r_frac >= pts[pts.size() - 1].x:
		return pts[pts.size() - 1].y
	for j in pts.size() - 1:
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[j + 1]
		if r_frac >= a.x and r_frac <= b.x:
			var t := (r_frac - a.x) / (b.x - a.x)
			return a.y + (b.y - a.y) * t
	return 0.0


# ---------------------------------------------------------------------------
# Planform generation — the migration of the catalog props, §3.1
# ---------------------------------------------------------------------------
#
# §3.1 hits the wall head-on: nobody publishes a chord distribution. Not HQProp, not Gemfan, not
# T-Motor. They publish diameter, pitch and blade count, and the outline as a photograph. So a
# PRESET gets a GENERATED planform and carries `chord_is_assumed: true`, and every figure derived
# from it says so. A drawn or measured blade carries no caveat.
#
# The generator produces the SAME sine-arch shape `PropellerMesh` already draws (§7.2). That is the
# point rather than a convenience: §0's rule is that a dimension exists because it is in the model,
# and the picture and the physics must agree about the only prop property you cannot read off a spec
# line. The mesh still holds its own copy of these constants today; rewiring it to read the
# document is §7.2's "small, contained change", and the tests pin the two copies together so they
# cannot drift in the meantime (the `test_rust_constants` pattern).

const INCH_TO_MM := 25.4

## Blade chord at its widest, as a fraction of diameter, for a 3-blade prop. The mesh's own
## `CHORD_TO_DIAMETER_AT_3_BLADE` — a 5" tri-blade is about 13 mm wide on a 127 mm diameter.
const CHORD_TO_DIAMETER_AT_3_BLADE := 0.105
## Fewer blades, wider each, keeping total blade area roughly constant. The mesh's own exponent.
const CHORD_BLADE_COUNT_EXPONENT := 0.45
## Where along the blade the chord peaks, as a slice of a sine arch. The mesh's own fractions.
const CHORD_ROOT_FRACTION := 0.18
const CHORD_TIP_FRACTION := 0.98
const CHORD_FULLNESS := 0.7
## The centre boss as a fraction of radius; the blade starts at its edge. The mesh's own ratio.
const HUB_RADIUS_TO_RADIUS := 0.10
## Stations the generated planform is sampled at. 40 is §3.1's "~40 annuli" — fine enough that
## piecewise-linear interpolation of a smooth arch is exact to well past the k² band's resolution.
const PLANFORM_STATIONS := 40

## Section thickness-to-chord ratio the generator stamps on a preset — the mesh's
## `THICKNESS_TO_CHORD_RATIO`. A preset carries it so the blade mass has a t/c to multiply by; the
## drag polar (§4.2) will read the same number.
const DEFAULT_THICKNESS_RATIO := 0.10


## The planform the generator stamps: the same sine-arch `PropellerMesh._chord_at` produces, sampled
## at PLANFORM_STATIONS points from the hub edge to the tip. Static so the mesh's own test can read
## it without a node.
static func generate_chord(p_diameter_mm: float, blade_count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var radius := p_diameter_mm * 0.5
	var hub_radius := radius * HUB_RADIUS_TO_RADIUS
	var chord_max := p_diameter_mm * CHORD_TO_DIAMETER_AT_3_BLADE \
		* pow(3.0 / float(maxi(blade_count, 1)), CHORD_BLADE_COUNT_EXPONENT)
	for i in PLANFORM_STATIONS:
		var span := float(i) / float(PLANFORM_STATIONS - 1)
		var r_mm := hub_radius + (radius - hub_radius) * span
		var arch := CHORD_ROOT_FRACTION + (CHORD_TIP_FRACTION - CHORD_ROOT_FRACTION) * span
		var c := chord_max * pow(sin(PI * arch), CHORD_FULLNESS)
		out.append(r_mm / radius)
		out.append(c)
	return out


## `catalog.material` free-text → a FrameMaterials id. This is the migration's one honest weak point
## and it is named rather than hidden, exactly as `AirframeDocument.material_id_for_catalog` names
## its own: the prop files describe material in prose ("polycarbonate", "glass-filled nylon") because
## until this document existed nothing read it. The mapping is by substring, with an explicit default
## rather than an inference, and whatever it maps to must be in the materials table or the mass sum
## silently drops the blade.
static func material_id_for_catalog(description: String) -> String:
	var text := description.to_lower()
	if text.contains("carbon-filled"):
		return "carbon_filled_nylon"
	if text.contains("glass-filled") or text.contains("glass filled"):
		return "glass_filled_nylon"
	return "polycarbonate"


## A PropellerDocument for one entry of `data/parts/propellers.json`. See the block above for what is
## and is not read out of it: diameter, pitch and blade count generate the planform; `mass_g` is
## CARRIED as `published_mass_g` and never consulted, so the mass falsification stays a falsification
## rather than a fit.
static func from_catalog_prop(prop: Dictionary) -> PropellerDocument:
	var doc := PropellerDocument.new()
	var specs: Dictionary = prop.get("specs", {})

	doc.id = str(prop.get("part_id", ""))
	doc.name = str(prop.get("name", ""))
	doc.author = "Lothal preset"
	doc.revision = "generated from catalog specs"
	doc.diameter_mm = float(specs.get("diameter_inches", 0.0)) * INCH_TO_MM
	doc.pitch_mm = float(specs.get("pitch_inches", 0.0)) * INCH_TO_MM
	doc.blades = maxi(int(specs.get("blades", 2)), 1)
	doc.material_id = material_id_for_catalog(str(prop.get("catalog", {}).get("material", "")))
	doc.thickness_ratio = DEFAULT_THICKNESS_RATIO
	doc.chord = generate_chord(doc.diameter_mm, doc.blades)
	# §3.1: a generated planform is an assumption and says so out loud. This is the flag every figure
	# derived from the planform carries, and it is what keeps the generator from laundering its own
	# guess into a measurement (airframe.md §9b's named failure).
	doc.chord_is_assumed = true
	# Carried, never consulted. See `published_mass_g`.
	doc.published_mass_g = float(prop.get("mass_g", 0.0))
	return doc


## Every catalog prop as a preset, keyed by part_id. The migration §9's P1 asks for.
static func presets_from_catalog(catalog: PartsCatalog) -> Dictionary:
	var out: Dictionary = {}
	for prop in catalog.list_category("propeller"):
		out[str(prop["part_id"])] = from_catalog_prop(prop)
	return out


# ---------------------------------------------------------------------------
# Persistence — json_store.gd's pattern, unchanged from airframe.md §2
# ---------------------------------------------------------------------------

static func from_dictionary(document: Dictionary) -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.id = str(document.get("id", ""))
	doc.name = str(document.get("name", ""))
	doc.author = str(document.get("author", ""))
	doc.revision = str(document.get("revision", ""))
	doc.diameter_mm = float(document.get("diameter_mm", 0.0))
	doc.pitch_mm = float(document.get("pitch_mm", 0.0))
	doc.blades = maxi(int(document.get("blades", 2)), 1)
	doc.chord = _flat_from_json(document.get("chord", []))
	doc.twist_mode = str(document.get("twist_mode", TWIST_MODE_GEOMETRIC))
	doc.twist = _flat_from_json(document.get("twist", []))
	doc.material_id = str(document.get("material_id", "polycarbonate"))
	doc.thickness_ratio = float(document.get("thickness_ratio", DEFAULT_THICKNESS_RATIO))
	doc.chord_is_assumed = bool(document.get(CHORD_ASSUMED, false))
	doc.published_mass_g = float(document.get("published_mass_g", 0.0))
	doc._unknown_top = JsonStore.unknown_fields(document, KNOWN_KEYS)
	return doc


func to_dictionary() -> Dictionary:
	# Unknown fields go in FIRST so a known key can never be shadowed by a stale unknown one.
	var out: Dictionary = _unknown_top.duplicate(true)
	out["schema"] = SCHEMA_VERSION
	out["id"] = id
	out["name"] = name
	out["author"] = author
	out["revision"] = revision
	out["diameter_mm"] = diameter_mm
	out["pitch_mm"] = pitch_mm
	out["blades"] = blades
	out["chord"] = _json_from_flat(chord)
	out["twist_mode"] = twist_mode
	out["twist"] = _json_from_flat(twist)
	out["material_id"] = material_id
	out["thickness_ratio"] = thickness_ratio
	out[CHORD_ASSUMED] = chord_is_assumed
	out["published_mass_g"] = published_mass_g
	return out


## A bad file loads as an empty propeller rather than as a crash — json_store.gd's first rule.
static func load_from(path: String) -> PropellerDocument:
	return from_dictionary(JsonStore.read_document(path))


## Atomic, because this is a drone and not a slider position (json_store.gd's third rule).
func save_to(path: String) -> bool:
	return JsonStore.write_document_atomic(path, to_dictionary())


static func _flat_from_json(value: Variant) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if value is Array:
		for n in value:
			out.append(float(n))
	elif value is PackedFloat64Array:
		out.append_array(value)
	return out


static func _json_from_flat(flat: Variant) -> Array:
	var out: Array = []
	if flat is PackedFloat64Array:
		for n in flat:
			out.append(n)
	elif flat is Array:
		for n in flat:
			out.append(float(n))
	return out
