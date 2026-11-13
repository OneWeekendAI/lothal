class_name PayloadPart
extends RefCounted
## The payload as a PART: one box hung under the belly of any airframe, on a hook, a gimbal or a plate.
##
## What is saved is small and sparse (Project.payload): `{kind, mass_g?, size_mm?}`. `kind` names an
## entry of data/parts/payloads.json; `mass_g` and `size_mm` ([length, width, height]) are the builder's
## own numbers and, when present, win over the entry's. Absent means "whatever the kind says", so a
## catalog entry that is corrected later follows the design rather than freezing at an old figure.
## An EMPTY dictionary is no payload, and that is every project written before this existed.
##
## THIS CLASS KNOWS WHAT A PAYLOAD IS AND NOTHING ABOUT WHERE IT GOES. The place comes from the
## airframe (Build.payload_centre_m): below the lowest part, centred on the thrust centroid. One
## entry therefore fits every frame and every drone class, and no frame carries a payload offset.
##
## Axes follow the pack's convention (Build.battery_size_m): the catalog writes length (fore-aft),
## width (across) and height (up); the box in body axes is (width, height, length), nose is -Z.

const CATALOG_PATH := "res://data/parts/payloads.json"
const NONE := ""
const CUSTOM := "payload_custom"

## The heaviest payload a design can name, grams. Past this the figure is a typo, not a payload: the
## heaviest catalog drone here carries a few kilograms, and the brief for this part is "up to 20 kg".
const MAX_MASS_G := 20000.0
const MIN_DIM_MM := 5.0
const MAX_DIM_MM := 1000.0

## How far the hung box stands below the underside it hangs from, by mount type, metres. A hook is a
## strap and a hook; a gimbal needs its dampers and a swing; a plate is a bolted slab. Guesses,
## labelled as such: no catalog frame publishes a payload standoff.
const MOUNT_GAP_M := {"hook": 0.020, "gimbal": 0.015, "plate": 0.005}
const MOUNTS := ["hook", "gimbal", "plate"]

static var _entries: Array = []


## Every kind in the catalog, in file order. Each is a dictionary as the file writes it.
static func kinds() -> Array:
	if _entries.is_empty():
		var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if f != null:
			var doc: Variant = JSON.parse_string(f.get_as_text())
			if doc is Dictionary and (doc as Dictionary).get("parts") is Array:
				_entries = (doc as Dictionary)["parts"]
	return _entries


static func entry_of(kind: String) -> Dictionary:
	for e in kinds():
		if String((e as Dictionary).get("part_id", "")) == kind:
			return e
	return {}


## The saved form resolved into the numbers everything else reads: {kind, name, mass_g, length_mm,
## width_mm, height_mm, mount, mass_edited, size_edited, source}. EMPTY for no payload. A kind this
## build does not know (a file from a later version) still resolves, as a custom box of the saved
## numbers, rather than silently dropping weight the builder put on the aircraft.
static func resolve(saved: Dictionary) -> Dictionary:
	var kind := String(saved.get("kind", NONE))
	if kind == NONE:
		return {}
	var entry := entry_of(kind)
	var known := not entry.is_empty()
	if not known:
		entry = entry_of(CUSTOM)
		if entry.is_empty():
			return {}
	var specs: Dictionary = entry.get("specs", {})
	var out := {
		"kind": kind,
		"name": String(entry.get("name", kind)) if known else kind,
		"mass_g": float(entry.get("mass_g", 0.0)),
		"length_mm": float(specs.get("length_mm", 60.0)),
		"width_mm": float(specs.get("width_mm", 60.0)),
		"height_mm": float(specs.get("height_mm", 60.0)),
		"mount": String((entry.get("mounting", {}) as Dictionary).get("attachment", "plate")),
		"mass_edited": false, "size_edited": false,
		"source": String(entry.get("source", "")),
	}
	var mass: Variant = saved.get("mass_g", null)
	if mass is float or mass is int:
		out["mass_g"] = clampf(float(mass), 0.0, MAX_MASS_G)
		out["mass_edited"] = true
	var size: Variant = saved.get("size_mm", null)
	if size is Array and (size as Array).size() == 3:
		var ok := true
		for v in size:
			ok = ok and (v is float or v is int)
		if ok:
			out["length_mm"] = clampf(float(size[0]), MIN_DIM_MM, MAX_DIM_MM)
			out["width_mm"] = clampf(float(size[1]), MIN_DIM_MM, MAX_DIM_MM)
			out["height_mm"] = clampf(float(size[2]), MIN_DIM_MM, MAX_DIM_MM)
			out["size_edited"] = true
	return out


## The saved form of a choice: only what differs from the kind's own figures is written.
static func to_saved(kind: String, mass_g: float, length_mm: float, width_mm: float, height_mm: float) -> Dictionary:
	if kind == NONE:
		return {}
	var base := resolve({"kind": kind})
	var out := {"kind": kind}
	if base.is_empty():
		return out
	if not is_equal_approx(mass_g, float(base["mass_g"])):
		out["mass_g"] = mass_g
	if not (is_equal_approx(length_mm, float(base["length_mm"])) and is_equal_approx(width_mm, float(base["width_mm"]))
			and is_equal_approx(height_mm, float(base["height_mm"]))):
		out["size_mm"] = [length_mm, width_mm, height_mm]
	return out


## The box in BODY axes, metres: width across X, height up Y, length along Z.
static func size_m(spec: Dictionary) -> Vector3:
	return Vector3(float(spec["width_mm"]), float(spec["height_mm"]), float(spec["length_mm"])) / 1000.0


static func mount_gap_m(spec: Dictionary) -> float:
	return float(MOUNT_GAP_M.get(String(spec.get("mount", "plate")), MOUNT_GAP_M["plate"]))


## The mass if it has any, the way a mass_parts() entry is gated: a 0 g payload is no payload.
static func mass_kg(spec: Dictionary) -> float:
	return float(spec.get("mass_g", 0.0)) / 1000.0
