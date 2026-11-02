class_name CellLibrary
extends RefCounted
## The named cells the pack designer builds packs from (data/cells/cells.json), plus the typed
## "custom cell" escape hatch. Every datasheet figure is ideal / datasheet; the file cites a
## source and a basis per cell.

const DEFAULT_PATH := "res://data/cells/cells.json"

## Pre-registered resistance constants from the shipped pack catalog (K = r_per_cell(mOhm) * Ah * C),
## the same ones the retired hand-typed battery form used. A self-consistency relationship, not a
## measurement: a derived resistance is labelled "estimated".
const K_LIPO := 336.0
const K_LI_ION := 1229.0

var _cells: Array = []


static func load_default() -> CellLibrary:
	var lib := CellLibrary.new()
	var doc := JsonStore.read_document(DEFAULT_PATH)
	var raw: Variant = doc.get("cells", [])
	if raw is Array:
		for c in (raw as Array):
			if c is Dictionary:
				lib._cells.append(c)
	return lib


func cells() -> Array:
	return _cells


func by_chemistry(chem: String) -> Array:
	var out: Array = []
	for c in _cells:
		if String(c.get("chemistry", "")) == chem:
			out.append(c)
	return out


func get_cell(cell_id: String) -> Dictionary:
	for c in _cells:
		if String(c.get("cell_id", "")) == cell_id:
			return c
	return {}


## A typed cell. For a cylindrical cell dims_mm is (diameter, length, unused); for a pouch it is
## (length, width, thickness).
static func custom_cell(name: String, chemistry: String, mah: float, max_cont_a: float,
		max_burst_a: float, r_mohm: float, mass_g: float, dims_mm: Vector3, form: String) -> Dictionary:
	var specs := {
		"mah": mah,
		"nominal_v": _nominal_for(chemistry),
		"max_cont_a": max_cont_a,
		"max_burst_a": max_burst_a,
		"r_mohm": r_mohm,
		"mass_g": mass_g,
	}
	if form == "cylindrical":
		specs["diameter_mm"] = dims_mm.x
		specs["length_mm"] = dims_mm.y
	else:
		specs["length_mm"] = dims_mm.x
		specs["width_mm"] = dims_mm.y
		specs["thickness_mm"] = dims_mm.z
	return {
		"cell_id": "custom_cell",
		"name": name,
		"chemistry": chemistry,
		"form": form,
		"specs": specs,
		"source": "typed by the builder",
		"basis": "custom",
	}


## Per-cell resistance in ohms estimated from mAh and C: r = K / (Ah * C). Estimated, not measured.
static func custom_cell_r_ohm(chemistry: String, mah: float, c_rating: float) -> float:
	if mah <= 0.0 or c_rating <= 0.0:
		return 0.0
	var k := K_LI_ION if chemistry == "Li-ion" else K_LIPO
	return k / ((mah / 1000.0) * c_rating) / 1000.0


static func _nominal_for(chemistry: String) -> float:
	match chemistry:
		"LiPo HV": return 3.85
		"Li-ion": return 3.6
		"LiFePO4": return 3.2
		_: return 3.7
