class_name AirframeDocument
extends RefCounted
## An airframe as DATA — airframe.md §2. Plates with real outlines, arms that are plates with an
## authored centreline, motors at real positions, and the hardware that bolts it together.
##
## ## Why this file has no `mass` field, and never will
##
## §2 states it and it is the reason this document exists rather than a sixth field on
## `frames.json`: **mass is computed, never typed.** The moment a builder can type a mass, the
## geometry and the mass can disagree, and every number downstream — hover throttle, thrust-to-
## weight, the inertia tensor, the whole flight model — inherits the lie without any way to notice.
## So there is no `mass_g` here, no `mass_kg`, and no cache of one. AirframeProperties multiplies
## ρ·t·A and that is the only mass this project's airframe has.
##
## The corollary is that a preset is not a mass with a picture attached: it is a geometry that
## HAPPENS to weigh what the catalog says, and when it does not, that is a measurement worth
## reporting rather than a number worth editing (see `from_catalog_frame` below).
##
## ## Coordinates, stated once
##
## Everything in this file is MILLIMETRES, in PLAN VIEW. A plate's outline lives in its own 2D
## plane with coordinates `(u, v)`, and the mapping into Godot's Y-up world is fixed:
##
##     plate u  →  world X   (right, +)
##     plate v  →  world Z   (aft, +; the nose is −Z — physics.md §1)
##     z_mm     →  world Y   (up)
##
## A plate therefore lies FLAT and its normal is world Y. That single sentence is where the
## coordinate trap in §3.4 is defused; AirframeProperties restates it at the point of use because
## restating it there is cheaper than the bug. THE ONE EXCEPTION is a `side` plate, which stands up
## (airframe gaps G5) — see "Upright plates" below for its own mapping.
##
## ## Why plates are Dictionaries and not a PlateResource
##
## Forward compatibility. A `.lothal` written by a later version of Lothal will carry plate fields
## this version has never heard of — a fillet radius, a ply schedule, a nesting rotation — and the
## project's standing rule (json_store.gd) is that opening an older build must not silently destroy
## a newer one's data. Holding a plate as its own typed object means enumerating its fields, and
## every field not enumerated is a field thrown away on save. Holding it as the Dictionary it
## arrived as means unknown fields survive **by construction** rather than by a `_unknown_plate`
## side-table that somebody has to remember to update. The cost is that callers reach through
## accessors (`plate_outline`, `plate_thickness_mm`) instead of dot syntax, which is a small price
## for a guarantee that cannot rot.
##
## ## Why outlines are PackedFloat64Array and not PackedVector2Array
##
## `PackedVector2Array` is single precision. §3.1 measures what that costs — ~1e-7 relative on a
## vertex, ~7e-6 after a parallel-axis subtraction far from the origin — and that is genuinely
## harmless for the maths. It is NOT harmless for a round trip: authoring `0.1` and reading back
## `0.10000000149011612` makes "the document is unchanged" a claim nobody can assert exactly, and a
## save/load test that has to use `is_equal_approx` on geometry has stopped testing persistence and
## started testing floating point. So the stored form is a flat `[u0, v0, u1, v1, …]` of doubles,
## which JSON round-trips exactly, and `points_of()` converts to PackedVector2Array at the one
## boundary that needs it — PolygonProps' signature. The precision floor is then a property of the
## maths, where §3.1 already documents it, and not of the file format.

const SCHEMA_VERSION := 1

## Plate roles, from §2. `arm` is not a different KIND of thing — §10 q1 settled that an arm is a
## plate with a declared centreline — it is a plate whose role says beam analysis may run on it.
const ROLE_BOTTOM := "bottom"
const ROLE_TOP := "top"
const ROLE_ARM := "arm"
const ROLE_SIDE := "side"
const ROLE_MID := "mid"

## The top-level keys this version reads. Everything else in a loaded file is unknown and is kept
## verbatim — see the class docs and JsonStore.unknown_fields.
const KNOWN_KEYS := [
	"schema", "id", "name", "author", "revision", "material_id",
	"plates", "arms", "motors", "hardware", "straps", "pads", "payload_mounts",
	"published_mass_g", "cutting_bit_mm",
]

## The plate keys whose VALUE SHAPE this version rewrites on load (mm-doubles ⇄ PackedFloat64Array).
## Every other key on a plate passes through untouched, which is the whole forward-compatibility
## mechanism. Listed as a constant rather than inlined because the save path must convert exactly
## the same set the load path did, and two hand-kept lists is one list too many.
const PLATE_GEOMETRY_KEYS := ["outline", "holes"]

## Set on an arm plate whose width came from this file's scaling rather than from a vendor figure.
## Read by the Arms tab to caveat every beam number derived from it. Absent means authored, which is
## the right default: a plate a builder drew has exactly the width they drew.
const PLATE_WIDTH_ASSUMED := "width_is_assumed"

## `specs.construction` in `frames.json`. Absence means `plate` — see `from_catalog_frame`.
const CONSTRUCTION_PLATE := "plate"
const CONSTRUCTION_MOULDED := "moulded"

## 1/16" (1.5875 mm): the end mill most carbon-cutting services quote for frame plates. A TYPICAL SHOP
## VALUE, labelled as such wherever it is shown — a shop with a 1/8" bit is just as real, which is why
## it is a document setting rather than a constant the checks read.
const DEFAULT_CUTTING_BIT_MM := 1.5875

## Plate key: indices into that plate's `holes` of the holes to countersink after cutting (G3). Kept as
## indices because a hole is a bare polygon with nowhere to hang a flag, and holes are only ever
## appended or replaced in place, never removed, so an index stays pointing at its hole.
const PLATE_COUNTERSUNK_HOLES := "countersunk_holes"

var id := ""
var name := ""
var author := ""
var revision := ""
## Which stock the plates are cut from, by FrameMaterials id. A plate may override it (mixed
## carbon-and-nylon frames are real — the cinewhoop is one), which is why the density lookup in
## AirframeProperties reads the plate first and this second.
var material_id := "carbon_3k_twill_0_90"

## Each entry: {"outline": PackedFloat64Array, "holes": Array[PackedFloat64Array],
##              "thickness_mm": float, "z_mm": float, "role": String,
##              optional "material_id", "root_point": [u,v], "tip_point": [u,v]}
var plates: Array = []
## Each entry: {"position_mm": [u, v], "z_mm": float, "spin": +1/-1, "tilt_deg": float}
var motors: Array = []
## Each entry: {"kind": "standoff_round"|"standoff_hex"|"screw", "material_id": String,
##              "position_mm": [u, v], "z_mm": float, plus that kind's own dimensions}.
## Mass is HardwareMass' job, from those dimensions — never a `mass_g` field here, for the same
## reason plates have none.
var hardware: Array = []
## Straps: {"mass_g": float, "position_mm": [u,v], "z_mm": float}. A strap is the one item whose
## mass is genuinely a published figure rather than a geometry — it is a woven loop of stated
## length and stated weight — so it is the one place a mass may be typed, and it is labelled as
## such rather than smuggled in as "geometry".
var straps: Array = []
## Pads: a pad IS a plate — an outline of TPU at a thickness — so it carries plate keys and is
## weighed by exactly the same ρ·t·A path. Kept in its own array because §6 treats pads as a
## separate concern (they are springs, not structure) and A6 will give them a stiffness.
var pads: Array = []
## Where the stack, camera, VTX and pack attach: {"id": String, "position_mm": [u,v], "z_mm": float,
##              "span_mm": [u,v]}. No mass — a mount is a place, and what is mounted on it is a
## part with its own mass that Build already knows about.
var payload_mounts: Array = []

## What the vendor says this frame weighs, grams. ZERO FOR A FRAME SOMEBODY DREW, and that is the
## whole reason it exists as a separate field rather than as a mass anyone can type.
##
## §2 bans a mass field outright — "mass is computed, never typed" — and this does not breach that,
## because nothing reads it into any physics. It is a CLAIM BY A THIRD PARTY, kept so the Structure
## tab can print the disagreement between it and the computed figure, which is the falsification
## §3.2 asks for and the measurement §9a's whole finding rests on. A preset carries the vendor's
## number; a frame you drew has no vendor, so the comparison is not shown at all rather than being
## shown against zero.
var published_mass_g := 0.0

## The diameter of the round end mill the plates will be routed with, mm (airframe gaps G3). A SETTING
## FOR THE CUT, not a property of the frame: it decides which inside corners the cutter can follow
## (`ReadyToCut`) and is printed on every exported plate's notes so the shop knows what the file
## assumed. Defaults to 1/16" — `DEFAULT_CUTTING_BIT_MM`, a typical shop value, not a measured one.
var cutting_bit_mm := DEFAULT_CUTTING_BIT_MM

## Fields from a file this version does not understand, kept for the save path. See class docs.
var _unknown_top: Dictionary = {}


# ---------------------------------------------------------------------------
# Geometry helpers — the mm-doubles ⇄ PackedVector2Array boundary
# ---------------------------------------------------------------------------

## PackedVector2Array → the flat double form this document stores.
static func flatten(points: PackedVector2Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for p in points:
		out.append(p.x)
		out.append(p.y)
	return out


## The flat double form → PackedVector2Array, which is what PolygonProps takes. THIS is where the
## single-precision floor of §3.1 enters, and it is the only place, which is why it is one function
## rather than an inline loop at each call site.
##
## An odd-length array is a truncated document, not a polygon: the trailing half-vertex is dropped
## rather than read past, so a corrupt file gives a slightly wrong shape instead of an index error
## in the middle of a mass sum.
static func points_of(flat: PackedFloat64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		out.append(Vector2(flat[i], flat[i + 1]))
		i += 2
	return out


## Builds a plate dictionary. `holes` is an Array of PackedVector2Array wound OPPOSITE to the
## outline — PolygonProps needs no boolean geometry, only the winding (§3.1), and this function
## does not "fix" it for the same reason region_properties does not: a reversed hole is how a
## second disjoint lobe is expressed, and silently correcting it would make that inexpressible.
static func make_plate(
	outline: PackedVector2Array,
	holes: Array,
	thickness_mm: float,
	z_mm: float,
	role: String
) -> Dictionary:
	var flat_holes: Array = []
	for hole in holes:
		flat_holes.append(flatten(hole))
	return {
		"outline": flatten(outline),
		"holes": flat_holes,
		"thickness_mm": thickness_mm,
		"z_mm": z_mm,
		"role": role,
	}


## An arm: the same plate, plus the centreline §10 q1 decided is AUTHORED rather than inferred.
## Beam analysis (A5) measures `b(s)` by intersecting the outline with perpendiculars along this
## line; nothing here does that yet, and nothing here needs to — the point of storing it now is
## that a preset generated in A2 must not have to be regenerated in A5 to gain an arm axis.
static func make_arm_plate(
	outline: PackedVector2Array,
	holes: Array,
	thickness_mm: float,
	z_mm: float,
	root_point: Vector2,
	tip_point: Vector2
) -> Dictionary:
	var plate := make_plate(outline, holes, thickness_mm, z_mm, ROLE_ARM)
	plate["root_point"] = [root_point.x, root_point.y]
	plate["tip_point"] = [tip_point.x, tip_point.y]
	return plate


# ---------------------------------------------------------------------------
# Accessors — plates are Dictionaries, so reading one goes through here
# ---------------------------------------------------------------------------

static func plate_outline(plate: Dictionary) -> PackedVector2Array:
	return points_of(plate.get("outline", PackedFloat64Array()))


## Holes as PackedVector2Array, in file order.
static func plate_holes(plate: Dictionary) -> Array:
	var out: Array = []
	for hole in plate.get("holes", []):
		out.append(points_of(hole))
	return out


## Whether hole `hole_index` of this plate is to be countersunk (G3). Off unless set: nothing in a
## generated preset is countersunk, because whether a bottom plate takes flat heads is the builder's
## choice of screw, not something the frame's published specs say.
static func hole_is_countersunk(plate: Dictionary, hole_index: int) -> bool:
	for entry in plate.get(PLATE_COUNTERSUNK_HOLES, []):
		if int(entry) == hole_index:
			return true
	return false


static func plate_thickness_mm(plate: Dictionary) -> float:
	return float(plate.get("thickness_mm", 0.0))


static func plate_z_mm(plate: Dictionary) -> float:
	return float(plate.get("z_mm", 0.0))


# ---------------------------------------------------------------------------
# Upright plates (airframe gaps G5) — a side plate stands, every other plate lies flat
# ---------------------------------------------------------------------------
#
# A plate of role `side` is UPRIGHT: its outline is drawn in its own plane `(s, h)`, where `s` is
# fore/aft exactly as plan `v` is (world Z, aft +) and `h` is height above the plate's base (world Y).
# The plane stands parallel to the centreline at `x_mm` (world X), its base at `z_mm`, and its
# thickness is centred on `x_mm`. So:
#
#     side s  →  world Z      side h  →  world Y (above z_mm)      normal  →  world X
#
# That is a proper rotation of the flat mapping (u→X, v→Z, normal→Y), which is why the extruder,
# the integrals and the exporter can all treat the polygon as an ordinary plate and only the
# PLACEMENT differs. `side_world_m` is the one place that placement is written as code.

## Side-plate key: the lateral position of the plate's mid-plane, mm (world X).
const PLATE_X_MM := "x_mm"


## Whether a plate stands up rather than lying flat.
static func is_upright(plate: Dictionary) -> bool:
	return str(plate.get("role", "")) == ROLE_SIDE


static func plate_x_mm(plate: Dictionary) -> float:
	return float(plate.get(PLATE_X_MM, 0.0))


## An upright plate: `outline` and `holes` in its own (s, h) plane, standing at `x_mm` on a base at
## `base_z_mm`.
static func make_side_plate(
	outline: PackedVector2Array,
	holes: Array,
	thickness_mm: float,
	x_mm: float,
	base_z_mm: float
) -> Dictionary:
	var plate := make_plate(outline, holes, thickness_mm, base_z_mm, ROLE_SIDE)
	plate[PLATE_X_MM] = x_mm
	return plate


## A point of an upright plate's own plane, in the airframe's world frame, metres. The side-plate
## counterpart of `world_m`, and the only place the (s, h) → world mapping is written.
static func side_world_m(plate: Dictionary, point_sh: Vector2) -> Vector3:
	return Vector3(plate_x_mm(plate), plate_z_mm(plate) + point_sh.y, point_sh.x) / 1000.0


## What a plate covers seen from above, in plan mm. A flat plate's outline; for an upright plate, the
## thin rectangle its thickness makes along its fore/aft extent — what the plan view draws and picks,
## because its own outline is not a plan shape at all.
static func plate_plan_outline(plate: Dictionary) -> PackedVector2Array:
	var outline := plate_outline(plate)
	if not is_upright(plate) or outline.size() < 3:
		return outline
	var front := INF
	var rear := -INF
	for point in outline:
		front = minf(front, point.x)
		rear = maxf(rear, point.x)
	var x := plate_x_mm(plate)
	var half_t := plate_thickness_mm(plate) * 0.5
	return PackedVector2Array([Vector2(x - half_t, front), Vector2(x + half_t, front),
		Vector2(x + half_t, rear), Vector2(x - half_t, rear)])


## The material a plate is cut from: its own override, else the document's. Two levels and no more —
## a per-hole material is not a thing that exists.
func plate_material_id(plate: Dictionary) -> String:
	return str(plate.get("material_id", material_id))


## A point stored as `[u, v]` in the document, as a Vector2 in the plate plane.
static func point_of(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


## Plan position → world, at a stated height. The ONE place the u→X, v→Z, z→Y mapping of the class
## docs is written as code. Every position in this document goes through it, so the mapping cannot
## be applied one way in the mass sum and another way in the picture.
static func world_m(plan_mm: Vector2, z_mm: float) -> Vector3:
	return Vector3(plan_mm.x, z_mm, plan_mm.y) / 1000.0


# ---------------------------------------------------------------------------
# Persistence — json_store.gd's pattern
# ---------------------------------------------------------------------------

static func from_dictionary(document: Dictionary) -> AirframeDocument:
	var doc := AirframeDocument.new()
	doc.id = str(document.get("id", ""))
	doc.name = str(document.get("name", ""))
	doc.author = str(document.get("author", ""))
	doc.revision = str(document.get("revision", ""))
	if document.has("material_id"):
		doc.material_id = str(document["material_id"])
	doc.published_mass_g = float(document.get("published_mass_g", 0.0))
	var bit := float(document.get("cutting_bit_mm", DEFAULT_CUTTING_BIT_MM))
	doc.cutting_bit_mm = bit if bit > 0.0 else DEFAULT_CUTTING_BIT_MM

	for entry in document.get("plates", []):
		if entry is Dictionary:
			doc.plates.append(_plate_from_json(entry))
	for entry in document.get("pads", []):
		if entry is Dictionary:
			doc.pads.append(_plate_from_json(entry))

	# The rest are plain records with no geometry to reshape, so they are kept EXACTLY as they
	# arrived — which makes their unknown fields survive with no code at all.
	doc.motors = _copied(document.get("motors", []))
	doc.hardware = _copied(document.get("hardware", []))
	doc.straps = _copied(document.get("straps", []))
	doc.payload_mounts = _copied(document.get("payload_mounts", []))

	doc._unknown_top = JsonStore.unknown_fields(document, KNOWN_KEYS)
	return doc


func to_dictionary() -> Dictionary:
	# Unknown fields go in FIRST so a known key can never be shadowed by a stale unknown one of the
	# same name — the known half is authoritative, the unknown half is cargo.
	var out: Dictionary = _unknown_top.duplicate(true)
	out["schema"] = SCHEMA_VERSION
	out["id"] = id
	out["name"] = name
	out["author"] = author
	out["revision"] = revision
	out["material_id"] = material_id
	out["published_mass_g"] = published_mass_g
	out["cutting_bit_mm"] = cutting_bit_mm

	var plate_json: Array = []
	for plate in plates:
		plate_json.append(_plate_to_json(plate))
	out["plates"] = plate_json

	var pad_json: Array = []
	for pad in pads:
		pad_json.append(_plate_to_json(pad))
	out["pads"] = pad_json

	out["motors"] = _copied(motors)
	out["hardware"] = _copied(hardware)
	out["straps"] = _copied(straps)
	out["payload_mounts"] = _copied(payload_mounts)
	return out


## A bad file loads as an empty airframe rather than as a crash — json_store.gd's first rule. An
## airframe with no plates weighs nothing, which is visibly wrong on screen, and that is a better
## failure than a workbench that will not open.
static func load_from(path: String) -> AirframeDocument:
	return from_dictionary(JsonStore.read_document(path))


## Atomic, because this is a drone and not a slider position (json_store.gd's third rule).
func save_to(path: String) -> bool:
	return JsonStore.write_document_atomic(path, to_dictionary())


static func _plate_from_json(entry: Dictionary) -> Dictionary:
	var plate := entry.duplicate(true)
	plate["outline"] = _flat_from_json(entry.get("outline", []))
	var holes: Array = []
	for hole in entry.get("holes", []):
		holes.append(_flat_from_json(hole))
	plate["holes"] = holes
	return plate


static func _plate_to_json(plate: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in plate:
		if PLATE_GEOMETRY_KEYS.has(key):
			continue
		out[key] = _copied_value(plate[key])
	out["outline"] = _json_from_flat(plate.get("outline", PackedFloat64Array()))
	var holes: Array = []
	for hole in plate.get("holes", []):
		holes.append(_json_from_flat(hole))
	out["holes"] = holes
	return out


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


static func _copied(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			out.append(_copied_value(entry))
	return out


static func _copied_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


# ---------------------------------------------------------------------------
# Preset migration — the twelve (fifteen) catalog frames as documents
# ---------------------------------------------------------------------------
#
# §9's A2 row: "Every existing frame loads, and round-trips unchanged." What follows generates an
# AirframeDocument from a catalog frame's PUBLISHED specs — arm_mm, motor_mount, stack_mount — and
# nothing else. In particular it does not read `mass_g`.
#
# THAT IS THE POINT, and it is worth being blunt about it. `mass_g` is the thing §3.2 says to
# falsify against. A generator that read it — that scaled a thickness or a width until the sum came
# out at the published figure — would make the ±10% check a tautology and would be exactly the
# "bound moved to fit the data" the project's standing rules forbid. So the constants below are
# chosen from HOW THESE FRAMES ARE BUILT, stated with their reasons, and then left alone. Where a
# frame misses, the miss is the finding.
#
# What they encode, in one sentence each. NOTE (A2b): the first three are now FALLBACKS. Where
# `frames.json` carries a sourced `plate_thickness_mm`, `arm_width_mm` or `arm_thickness_mm`, that
# figure is used and the constant is not consulted; the constants remain for the frames whose
# geometry nobody publishes, and for custom frames.
#
#   - Arm thickness scales with arm length at roughly 4.5%, snapped to real plate stock. A 110 mm
#     5" arm lands on 5 mm, a 150 mm 7" on 6 mm, a 75 mm toothpick on 3 mm. Those are the plates
#     these frames are actually cut from, and 6 mm is where the stock list stops.
#   - Plate thickness scales at 2%, snapped, floored at the thinnest stock. 2 mm at 5", 2.5 mm at
#     7", 1.5 mm on the small stuff.
#   - An arm runs from the CENTRE to past the motor, because in a bolted frame the arm is a full-
#     length plate sandwiched between the centre plates, and in a unibody it is the bottom plate.
#     Stopping it at a "root radius" is what a picture does; it is not what the part is.
#   - The tip is as wide as the motor pattern's bolt circle plus an edge margin, because that is
#     what has to be there for four screws to land in it.
#   - Two centre plates, bottom and top, square, sized off the stack pattern and the arm.
#   - Four aluminium standoffs and the screws that hold it together, weighed by HardwareMass from
#     their own geometry.
#
# The generator is deliberately plain. §9 asks A2 to produce documents that mass and inertia can be
# proven against, not to produce beautiful frames; A7's editor is where a frame gets to be pretty.

## Real plate stock, in mm (§2). A generated thickness is snapped to this because you cannot buy
## 4.95 mm carbon, and a mass computed from a thickness nobody sells is a mass of nothing real.
const PLATE_STOCK_MM := [1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0]

const ARM_THICKNESS_PER_ARM_MM := 0.045
const PLATE_THICKNESS_PER_ARM_MM := 0.020
## Edge margin around a motor's bolt circle, mm. 3 mm each side of an M3 hole is the workshop
## hole-to-edge rule HardwareMass already encodes (1.5·d).
const MOUNT_EDGE_MARGIN_MM := 6.0
const ARM_ROOT_WIDTH_PER_ARM_MM := 0.12
## An arm's root is never narrower than this fraction of its tip: a taper that inverts is not a
## taper, and on the small frames the motor pad is the widest thing on the arm.
const ARM_ROOT_MIN_FRACTION := 0.55
## Centre plate side length as a fraction of arm length, floored at the stack pattern plus margin —
## a plate smaller than the boards bolted to it is not a frame.
const CENTRE_PLATE_PER_ARM_MM := 0.30
const CENTRE_PLATE_MARGIN_MM := 10.0
## Standoff height as a fraction of arm length: the stack has to fit between the plates, and it is
## the same stack on a 3" as on a 7".
const STANDOFF_PER_ARM_MM := 0.16
const STANDOFF_MIN_MM := 10.0
const STANDOFF_MAX_MM := 35.0
const STANDOFF_OUTER_D_MM := 5.5
const STANDOFF_BORE_D_MM := 3.0
## Sixteen motor screws plus eight through the plate stack. Counted, not estimated: four per motor
## is what a 16×16 pattern takes, and four corners times two plates is the stack.
const MOTOR_SCREWS := 16
const PLATE_SCREWS := 8


## The four motor positions of a symmetric X at `arm_mm`, in MotorLayout's order and at its
## azimuths, so a preset and the physics agree about where a motor is without either re-deriving it.
##
## Split out because it is the ONLY part of the generator a moulded frame can honestly use: where
## thrust is applied is published (`arm_mm`), while what holds it there is a shape this file cannot
## describe.
static func _add_motors(doc: AirframeDocument, arm_mm: float, z_mm: float) -> void:
	for motor_name in MotorLayout.MOTOR_NAMES:
		var direction := _motor_direction(motor_name)
		doc.motors.append({
			"position_mm": [direction.x * arm_mm, direction.y * arm_mm],
			"z_mm": z_mm,
			"spin": MotorLayout.SPIN[motor_name],
			"tilt_deg": 0.0,
			"name": motor_name,
		})


## An AirframeDocument for one entry of `data/parts/frames.json`. See the block above for what is
## and is not read out of it.
static func from_catalog_frame(frame: Dictionary) -> AirframeDocument:
	var doc := AirframeDocument.new()
	var specs: Dictionary = frame.get("specs", {})
	var arm_mm := float(specs.get("arm_mm", 0.0))
	var motor_pitch := _pattern_pitch_mm(str(specs.get("motor_mount", "16x16")))
	# THE STACK BY NAME, through the same parser "+ Stack mount" uses (airframe gaps G2), so a preset
	# and a drawn frame on the same pattern get the same four holes to the hundredth of a millimetre.
	var stack_spec := stack_mount_spec(str(specs.get("stack_mount", "30.5x30.5")))
	if stack_spec.is_empty():
		stack_spec = stack_mount_spec("30.5x30.5")
	var stack_pitch := float(stack_spec["pitch_mm"])
	var stack_thread := float(stack_spec["thread_d_mm"])

	doc.id = str(frame.get("part_id", ""))
	doc.name = str(frame.get("name", ""))
	doc.author = "Lothal preset"
	doc.revision = "generated from catalog specs"
	doc.material_id = material_id_for_catalog(str(frame.get("catalog", {}).get("material", "")))
	# Carried, never consulted. See `published_mass_g` — the generator below still does not read a
	# mass, and the ±10% check stays a falsification rather than a fit.
	doc.published_mass_g = float(frame.get("mass_g", 0.0))

	# A MOULDED FRAME IS NOT A PLATE ASSEMBLY, AND GETS NO PLATES.
	#
	# §0 is explicit that the plate model owes a moulded part nothing. The generator below will
	# nonetheless manufacture a complete plate frame for anything with an `arm_mm`, because every
	# fallback it owns is keyed off arm length alone — and it did, which is how a one-piece
	# injection-moulded nylon whoop came to be quoting a 278 Hz carbon arm resonance for a beam that
	# exists nowhere on the product.
	#
	# THE TEST IS THE DECLARED CONSTRUCTION, NOT A MISSING THICKNESS. Inferring "moulded" from an
	# absent `plate_thickness_mm` is the obvious shortcut and it is wrong on two of the fifteen
	# frames: the 2.5" whoop is a "nylon + CF plate hybrid" and the cinewhoop is "CF plates +
	# moulded nylon ducts". Both really do have plates and simply publish no thickness for them,
	# which is what the documented fallback is for; treating them as moulded would delete real
	# structure and their mass with it.
	#
	# The motors stay in either case: their positions come from `arm_mm`, which IS published, and
	# the layout maths is about where thrust is applied rather than about what holds it there.
	# Everything downstream already handles a document with no plates — it weighs nothing, has no
	# arm, and says so.
	if str(specs.get("construction", CONSTRUCTION_PLATE)) == CONSTRUCTION_MOULDED:
		_add_motors(doc, arm_mm, 0.0)
		return doc

	# SOURCED GEOMETRY FIRST, ASSUMPTION SECOND (A2b). `frames.json` may now carry the three
	# figures these three lines used to invent. When a figure is there it is used verbatim — no
	# snapping, because a published 5.5 mm arm is 5.5 mm whatever this file's stock list says —
	# and when it is absent the old scaling stands, unchanged, so a frame with no published
	# geometry still loads and still produces a document. Absence is expected and permanent for
	# the moulded frames (§0) and for arm WIDTH, which no surveyed vendor publishes at all.
	var t_arm := (float(specs["arm_thickness_mm"]) if specs.has("arm_thickness_mm")
		else snap_to_stock(arm_mm * ARM_THICKNESS_PER_ARM_MM))
	var t_plate := (float(specs["plate_thickness_mm"]) if specs.has("plate_thickness_mm")
		else snap_to_stock(arm_mm * PLATE_THICKNESS_PER_ARM_MM))
	var tip_width := motor_pitch * sqrt(2.0) + MOUNT_EDGE_MARGIN_MM
	var root_width := (float(specs["arm_width_mm"]) if specs.has("arm_width_mm")
		else maxf(arm_mm * ARM_ROOT_WIDTH_PER_ARM_MM, tip_width * ARM_ROOT_MIN_FRACTION))
	var tip_radius := arm_mm + tip_width * 0.5
	var motor_hole_d := 3.2 if motor_pitch >= 16.0 else 2.2
	var plate_side := maxf(arm_mm * CENTRE_PLATE_PER_ARM_MM, stack_pitch + CENTRE_PLATE_MARGIN_MM)
	var standoff_len := clampf(arm_mm * STANDOFF_PER_ARM_MM, STANDOFF_MIN_MM, STANDOFF_MAX_MM)
	# The vertical layout, and it is HardwareMass' sum rather than a second one: bottom plate, then
	# the standoffs, then the top plate.
	var top_z := t_plate + standoff_len

	# The motors first, so that the one place motor positions are written is the one place a moulded
	# frame also reaches (see the early return above).
	_add_motors(doc, arm_mm, t_arm)

	# Four arms on the diagonals, in MotorLayout's order and at MotorLayout's azimuths, so a preset
	# and the physics agree about where a motor is without either re-deriving it.
	for motor_name in MotorLayout.MOTOR_NAMES:
		var direction := _motor_direction(motor_name)
		var angle := direction.angle()
		var outline := _tapered_arm_outline(angle, tip_radius, root_width, tip_width)
		var holes: Array = []
		for corner in _bolt_pattern(direction * arm_mm, motor_pitch, angle):
			holes.append(PolygonProps.tessellate_circle(corner, motor_hole_d * 0.5,
				PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true))
		var arm_plate := make_arm_plate(outline, holes, t_arm, 0.0,
			Vector2.ZERO, direction * arm_mm)
		# WHETHER THIS ARM'S WIDTH IS A PUBLISHED FIGURE OR THIS FILE'S GUESS, recorded on the plate
		# itself. §9a established that NO surveyed vendor publishes an arm width, so for fourteen of
		# the fifteen catalog frames the outline above was drawn from `ARM_ROOT_WIDTH_PER_ARM_MM`
		# rather than from anything anybody measured.
		#
		# That matters now in a way it did not before. The Arms tab used to dash every beam row when
		# the width was unpublished, which was honest but useless; it now MEASURES the width off the
		# outline, which is honest and useful for a frame somebody drew — and would quietly launder
		# a generator constant into a "measurement" for a frame nobody drew. The flag is what keeps
		# the two apart: an arm you authored carries no caveat because you really did choose its
		# width, and a generated preset says out loud that its width is assumed.
		arm_plate["width_is_assumed"] = not specs.has("arm_width_mm")
		doc.plates.append(arm_plate)
		for i in 4:
			doc.hardware.append({
				"kind": "screw", "material_id": "steel_fastener",
				"thread_d_mm": 3.0 if motor_pitch >= 16.0 else 2.0,
				"shank_len_mm": 8.0,
				"head_d_mm": (3.0 if motor_pitch >= 16.0 else 2.0) * 1.9,
				"head_h_mm": (3.0 if motor_pitch >= 16.0 else 2.0) * 0.6,
				"position_mm": [direction.x * arm_mm, direction.y * arm_mm],
				"z_mm": t_arm,
			})

	# Bottom and top centre plates. The arms are sandwiched between them, which is why the bottom
	# plate sits at the same z as the arms rather than under them: on a bolted 5" frame the arm and
	# the bottom plate ARE the same layer of the sandwich, and on a unibody the arms are that plate.
	var stack_holes := stack_mount_holes(Vector2.ZERO, stack_spec)
	doc.plates.append(make_plate(_square(plate_side), stack_holes, t_plate, 0.0, ROLE_BOTTOM))
	# The top plate carries the pack, so it carries the two strap slots a pack is strapped through
	# (airframe.md §6.4). GUESSED, as the arm width is: the catalog publishes no slot, so these are
	# StrapSlots' preset 20 mm-strap slots, inside the stack pattern — and without them every preset
	# would be told it has nowhere to pass a strap, which is true of no frame anyone sells.
	doc.plates.append(make_plate(_square(plate_side),
		stack_holes + StrapSlots.preset_slots(plate_side, stack_pitch), t_plate, top_z, ROLE_TOP))

	for corner in _bolt_pattern(Vector2.ZERO, stack_pitch, 0.0):
		doc.hardware.append({
			"kind": "standoff_round", "material_id": "aluminium_6061",
			"outer_d_mm": STANDOFF_OUTER_D_MM, "bore_d_mm": STANDOFF_BORE_D_MM,
			"length_mm": standoff_len,
			"position_mm": [corner.x, corner.y],
			"z_mm": t_plate + standoff_len * 0.5,
		})
	for i in PLATE_SCREWS:
		var corner: Vector2 = _bolt_pattern(Vector2.ZERO, stack_pitch, 0.0)[i % 4]
		doc.hardware.append({
			"kind": "screw", "material_id": "steel_fastener",
			# The screw the stack holes were drilled for: an M2 stack is not held with M3 screws.
			"thread_d_mm": stack_thread, "shank_len_mm": 8.0,
			"head_d_mm": stack_thread * 1.9, "head_h_mm": stack_thread * 0.6,
			"position_mm": [corner.x, corner.y],
			"z_mm": 0.0 if i < 4 else top_z,
		})

	doc.payload_mounts.append({
		"id": "stack", "position_mm": [0.0, 0.0], "z_mm": t_plate,
		"span_mm": [plate_side, plate_side],
	})
	doc.payload_mounts.append({
		"id": "strap_top", "position_mm": [0.0, 0.0], "z_mm": top_z + t_plate,
		"span_mm": [plate_side, plate_side],
	})
	return doc


## Every catalog frame as a preset, keyed by part_id. The migration §9 asks A2 for.
static func presets_from_catalog(catalog: PartsCatalog) -> Dictionary:
	var out: Dictionary = {}
	for frame in catalog.list_category("frame"):
		out[str(frame["part_id"])] = from_catalog_frame(frame)
	return out


## The `catalog.material` free-text string → a FrameMaterials id.
##
## This mapping is the one honest weak point of the migration and it is named rather than hidden:
## `frames.json` describes material in prose ("CF plates + moulded nylon ducts") because until
## FrameMaterials existed nothing read it. A prose string cannot express a two-material frame, so
## a hybrid is mapped to its STRUCTURAL material and the other half is simply not modelled — which
## for the cinewhoop means its ducts weigh nothing here, and that shows up in §3.2's check as a
## large negative error. That is the correct outcome: the model is not wrong, the frame has parts
## the plate model has not been given.
static func material_id_for_catalog(description: String) -> String:
	var text := description.to_lower()
	if text.begins_with("injection-moulded nylon") or text.begins_with("nylon (") or text == "nylon":
		return "pa12_sls"
	if text.contains("4k") and text.contains("high-modulus"):
		return "carbon_quasi_isotropic"
	if text.contains("carbon") or text.contains("cf"):
		return "carbon_3k_twill_0_90"
	if text.contains("nylon"):
		return "pa12_sls"
	return "carbon_3k_twill_0_90"


## Nearest real plate stock. Snapped rather than rounded up: rounding up would bias every generated
## frame heavy, and a one-sided bias is exactly what §3.1 warns about with inscribed curves.
static func snap_to_stock(thickness_mm: float) -> float:
	var best: float = PLATE_STOCK_MM[0]
	for stock in PLATE_STOCK_MM:
		if absf(stock - thickness_mm) < absf(best - thickness_mm):
			best = stock
	return best


## "30.5x30.5" → 30.5. A pattern with one number is square; the first number is the pitch. Anything
## after whitespace ("25.5x25.5 M3") is the thread, read by `stack_mount_spec`, not here.
static func _pattern_pitch_mm(pattern: String) -> float:
	var head := pattern.strip_edges().to_lower().split(" ", false)
	if head.is_empty():
		return 0.0
	var parts := head[0].split("x")
	if parts.is_empty():
		return 0.0
	return float(parts[0])


# ---------------------------------------------------------------------------
# Standard stack mounts, by name (airframe gaps G2; airframe.md §5.3, §10 q5)
# ---------------------------------------------------------------------------

## The stack patterns a builder can ask for by name, in the order the workbench's picker lists them.
## 25.5 comes twice because both screws are sold on it: whoop AIO boards bolt with M2, and some
## 25.5 stacks take M3. The bare name is the M2 one (see `stack_mount_spec`).
const STACK_MOUNT_PATTERNS := ["20x20", "25.5x25.5", "25.5x25.5 M3", "30.5x30.5"]

## What a clearance hole is drilled over its screw: 3.2 for an M3, 2.2 for an M2 — the figures the
## generators have always drilled motor holes at, now named once.
const BOLT_CLEARANCE_MM := 0.2

## Below this pitch a stack is an M2 stack unless its name says otherwise. 20×20 and 25.5×25.5 boards
## bolt with M2; 30.5×30.5 is the M3 pattern.
const STACK_M3_FROM_PITCH_MM := 30.0


## `{pattern, pitch_mm, thread_d_mm, hole_d_mm}` for a stack pattern by name — "20x20", "25.5x25.5",
## "30.5x30.5", optionally followed by a thread ("25.5x25.5 M3"). `{}` for a name with no pitch.
##
## THE ONE PARSER. The catalog presets (`from_catalog_frame`) and "+ Stack mount"
## (`FrameEdits.add_stack_mount`) both read their holes through this and `stack_mount_holes`, so a
## preset and a drawn frame on the same pattern cut identical holes — which is what lets a drawn
## frame be compared against a preset at all.
static func stack_mount_spec(pattern: String) -> Dictionary:
	var pitch := _pattern_pitch_mm(pattern)
	if pitch <= 0.0:
		return {}
	var thread := 3.0 if pitch >= STACK_M3_FROM_PITCH_MM else 2.0
	var tokens := pattern.strip_edges().to_lower().split(" ", false)
	if tokens.size() > 1 and tokens[1].begins_with("m"):
		var stated := float(tokens[1].substr(1))
		if stated > 0.0:
			thread = stated
	return {"pattern": pattern.strip_edges(), "pitch_mm": pitch, "thread_d_mm": thread,
		"hole_d_mm": thread + BOLT_CLEARANCE_MM}


## The four holes of a stack pattern centred on `centre`, as clockwise polygons ready for a plate's
## `holes` (so they subtract, §3.1). Takes a spec from `stack_mount_spec` or a pattern name.
static func stack_mount_holes(centre: Vector2, pattern: Variant) -> Array:
	var spec: Dictionary = pattern if pattern is Dictionary else stack_mount_spec(str(pattern))
	var out: Array = []
	if spec.is_empty():
		return out
	for corner in _bolt_pattern(centre, float(spec["pitch_mm"]), 0.0):
		out.append(PolygonProps.tessellate_circle(corner, float(spec["hole_d_mm"]) * 0.5,
			PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true))
	return out


## The four hole CENTRES of a stack pattern on `centre` — what a fit check tests against an outline.
static func stack_mount_centres(centre: Vector2, pattern: String) -> Array:
	var spec := stack_mount_spec(pattern)
	if spec.is_empty():
		return []
	return _bolt_pattern(centre, float(spec["pitch_mm"]), 0.0)


## Unit vector from the origin to a motor, in the plate plane. MotorLayout's positions, converted
## through the same u→X / v→Z mapping everything else here uses — not a second table of 45°s.
static func _motor_direction(motor_name: String) -> Vector2:
	var world := MotorLayout.motor_position(motor_name, 1.0)
	return Vector2(world.x, world.z)


## Four bolt holes of a square pattern, centred on `centre`, rotated with the arm.
static func _bolt_pattern(centre: Vector2, pitch_mm: float, angle_rad: float) -> Array:
	var half := pitch_mm * 0.5
	var out: Array = []
	for corner in [Vector2(half, half), Vector2(half, -half), Vector2(-half, -half), Vector2(-half, half)]:
		out.append(centre + corner.rotated(angle_rad))
	return out


## A counter-clockwise square of side `side_mm` centred on the origin.
static func _square(side_mm: float) -> PackedVector2Array:
	var h := side_mm * 0.5
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])


## A trapezoid from the origin out to `tip_radius` along `angle_rad`, `root_width` wide at the
## centre and `tip_width` at the tip. Counter-clockwise, which for a polygon in a v-down plane is
## the winding PolygonProps calls positive.
static func _tapered_arm_outline(
	angle_rad: float, tip_radius: float, root_width: float, tip_width: float
) -> PackedVector2Array:
	var along := Vector2(cos(angle_rad), sin(angle_rad))
	var across := Vector2(-along.y, along.x)
	var points := PackedVector2Array([
		across * (root_width * 0.5),
		along * tip_radius + across * (tip_width * 0.5),
		along * tip_radius - across * (tip_width * 0.5),
		-across * (root_width * 0.5),
	])
	# Winding depends on which way the arm points, and a clockwise outline would subtract its own
	# mass from the frame. Normalise it here rather than trusting the caller's quadrant.
	if PolygonProps.area(points) < 0.0:
		return PolygonProps.reversed(points)
	return points
