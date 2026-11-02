class_name PackDesign
extends RefCounted
## A pack built from cells: a cell, an S x P layout and the pack's own pigtail. derive() turns that
## into figures and to_record() into the catalog-shaped battery record, which is the ONLY thing the
## drone ever sees (Build reads specs.{cells,nominal_v,mah,internal_r_ohm,chemistry,c_rating} and
## mass_g exactly as it does for a shelf preset).
##
## NO DOUBLE COUNT WITH THE HARNESS. Harness owns the aircraft half of the connector, the main lead
## from connector to stack, and the connector's contact resistance (HarnessChecks.trunk_resistance_ohm).
## So the figures here include only the PACK side: two conductors of pigtail, and the pack half of the
## connector's mass. Contact resistance is reported as read-only info and never enters internal_r_ohm.
##
## All figures are ideal / datasheet: cell values come from cells.json, wiring from WireGauge. The
## interconnect/wrap allowance is a labelled guess.

const BASIS := "ideal / datasheet"
const LEGACY_BASIS := "legacy (typed figures)"

## Nickel strip, solder and heat-shrink per cell. A guess, shown to the user as an estimate.
const INTERCONNECT_WRAP_G_PER_CELL := 1.0

## Matches the shelf's CELLS chips.
const S_RANGE := Vector2i(1, 6)
const P_RANGE := Vector2i(1, 4)

const PIGTAIL_CONDUCTORS := 2

static var _catalog_cache: PartsCatalog = null

var name: String = "My pack"
## Set once the pack has been saved; empty means "derive it from the name on save".
var part_id: String = ""
var cell: Dictionary = {}
var series: int = 4
var parallel: int = 1
var connector_family: String = "XT60"
var lead_awg: int = 14
var lead_length_mm: float = 100.0
## Non-empty only for a migrated pack: the typed specs it keeps exactly, and its typed mass.
var legacy_specs: Dictionary = {}
var legacy_mass_g: float = 0.0


static func default_design(lib: CellLibrary) -> PackDesign:
	var d := PackDesign.new()
	d.cell = lib.get_cell("cell_lipo_1500")
	return d


func is_legacy() -> bool:
	return not legacy_specs.is_empty()


## Back to a derived pack: figures may change from here on.
func rebuild_from_cells() -> PackDesign:
	legacy_specs = {}
	legacy_mass_g = 0.0
	return self


func chemistry() -> String:
	if is_legacy():
		return String(legacy_specs.get("chemistry", cell.get("chemistry", "LiPo")))
	return String(cell.get("chemistry", "LiPo"))


func derive() -> Dictionary:
	if is_legacy():
		return _derive_legacy()
	var s := clampi(series, S_RANGE.x, S_RANGE.y)
	var p := clampi(parallel, P_RANGE.x, P_RANGE.y)
	var chem := String(cell.get("chemistry", "LiPo"))
	var cs: Dictionary = cell.get("specs", {})
	var n := float(s * p)
	# The cell's own datasheet nominal when it has one (A123 LiFePO4 is 3.3 V, the chemistry default 3.2 V).
	var cell_nominal := float(cs.get("nominal_v", 0.0))
	var nominal_v := float(s) * (cell_nominal if cell_nominal > 0.0 else BatteryModel.nominal_cell_v(chem))
	var mah := float(cs.get("mah", 0.0)) * float(p)

	var length_m := lead_length_mm / 1000.0
	var mass_parts := {
		"cells": n * float(cs.get("mass_g", 0.0)),
		"interconnect_wrap": n * INTERCONNECT_WRAP_G_PER_CELL,
		"lead": PIGTAIL_CONDUCTORS * WireGauge.mass_g(lead_awg, length_m),
		"connector_half": _connector_pair_mass_g() * (1.0 - Harness.AIRCRAFT_SIDE_SHARE),
	}
	var mass := 0.0
	for k in mass_parts:
		mass += float(mass_parts[k])

	var r_parts := {
		"cells": float(cs.get("r_mohm", 0.0)) / 1000.0 * float(s) / float(p),
		"lead": PIGTAIL_CONDUCTORS * WireGauge.resistance_ohm(lead_awg, length_m),
	}
	var cont := float(cs.get("max_cont_a", 0.0)) * float(p)
	return {
		"nominal_v": nominal_v,
		"full_v": float(s) * BatteryModel.max_cell_v(chem),
		"empty_v": float(s) * BatteryModel.min_cell_v(chem),
		"mah": mah,
		"wh": nominal_v * mah / 1000.0,
		"mass_g": mass,
		"mass_parts": mass_parts,
		"dims_mm": _dims_mm(cs, s, p),
		"cont_a": cont,
		"burst_a": float(cs.get("max_burst_a", 0.0)) * float(p),
		"internal_r_ohm": float(r_parts["cells"]) + float(r_parts["lead"]),
		"r_parts": r_parts,
		"connector_contact_r_ohm_info": _connector_contact_ohm(),
		"basis": BASIS,
	}


## Catalog-shaped record. Legacy designs hand back exactly the typed figures they were loaded with.
func to_record() -> Dictionary:
	var f := derive()
	var dims: Vector3 = f["dims_mm"]
	var specs: Dictionary
	var mass: float
	if is_legacy():
		specs = legacy_specs.duplicate(true)
		mass = legacy_mass_g
	else:
		var ah := float(f["mah"]) / 1000.0
		specs = {
			"cells": clampi(series, S_RANGE.x, S_RANGE.y),
			"nominal_v": f["nominal_v"],
			"mah": f["mah"],
			"internal_r_ohm": f["internal_r_ohm"],
			"chemistry": chemistry(),
			"c_rating": float(f["cont_a"]) / ah if ah > 0.0 else 0.0,
			"length_mm": dims.x,
			"width_mm": dims.y,
			"height_mm": dims.z,
		}
		mass = float(f["mass_g"])
	var design := {
		"series": series,
		"parallel": parallel,
		"lead_awg": lead_awg,
		"lead_length_mm": lead_length_mm,
		"basis": LEGACY_BASIS if is_legacy() else BASIS,
	}
	if is_legacy():
		design["legacy"] = true
	if String(cell.get("basis", "")) == "custom" or is_legacy():
		design["custom_cell"] = cell.duplicate(true)
	else:
		design["cell_id"] = String(cell.get("cell_id", ""))
	return {
		"part_id": part_id if part_id != "" else CustomParts.id_for_name(name, "battery"),
		"name": name,
		"category": "battery",
		"mass_g": mass,
		"mounting": {"attachment": "strap"},
		"specs": specs,
		"catalog": {
			"cell_class": "%dS" % int(specs.get("cells", series)),
			"connector": connector_family,
		},
		"source": "pack designer: %s, ideal / datasheet figures" % String(cell.get("name", "custom cell")),
		"design": design,
	}


static func from_record(rec: Dictionary, lib: CellLibrary) -> PackDesign:
	var d := PackDesign.new()
	d.name = String(rec.get("name", ""))
	d.part_id = String(rec.get("part_id", ""))
	d.connector_family = String((rec.get("catalog", {}) as Dictionary).get("connector", "XT60"))
	var block: Dictionary = rec.get("design", {})
	d.series = int(block.get("series", (rec.get("specs", {}) as Dictionary).get("cells", 1)))
	d.parallel = int(block.get("parallel", 1))
	d.lead_awg = int(block.get("lead_awg", 14))
	d.lead_length_mm = float(block.get("lead_length_mm", 100.0))
	if block.has("custom_cell"):
		d.cell = (block["custom_cell"] as Dictionary).duplicate(true)
	else:
		d.cell = lib.get_cell(String(block.get("cell_id", "")))
	if bool(block.get("legacy", false)):
		d.legacy_specs = (rec.get("specs", {}) as Dictionary).duplicate(true)
		d.legacy_mass_g = float(rec.get("mass_g", 0.0))
	return d


func _derive_legacy() -> Dictionary:
	var chem := chemistry()
	var s := int(legacy_specs.get("cells", series))
	var mah := float(legacy_specs.get("mah", 0.0))
	var nominal_v := float(legacy_specs.get("nominal_v", 0.0))
	var cont := float(legacy_specs.get("c_rating", 0.0)) * mah / 1000.0
	return {
		"nominal_v": nominal_v,
		"full_v": float(s) * BatteryModel.max_cell_v(chem),
		"empty_v": float(s) * BatteryModel.min_cell_v(chem),
		"mah": mah,
		"wh": nominal_v * mah / 1000.0,
		"mass_g": legacy_mass_g,
		"mass_parts": {"cells": legacy_mass_g},
		"dims_mm": Vector3(float(legacy_specs.get("length_mm", 0.0)),
			float(legacy_specs.get("width_mm", 0.0)), float(legacy_specs.get("height_mm", 0.0))),
		"cont_a": cont,
		"burst_a": cont,
		"internal_r_ohm": float(legacy_specs.get("internal_r_ohm", 0.0)),
		"r_parts": {"pack": float(legacy_specs.get("internal_r_ohm", 0.0))},
		"connector_contact_r_ohm_info": _connector_contact_ohm(),
		"basis": LEGACY_BASIS,
	}


## Cells lie along the aircraft's forward axis; the series string runs across, parallel groups stack.
## Pouch cells keep their own footprint and stack by thickness.
func _dims_mm(cs: Dictionary, s: int, p: int) -> Vector3:
	if String(cell.get("form", "pouch")) == "cylindrical":
		var d := float(cs.get("diameter_mm", 0.0))
		return Vector3(float(cs.get("length_mm", 0.0)), d * float(s), d * float(p))
	return Vector3(float(cs.get("length_mm", 0.0)), float(cs.get("width_mm", 0.0)),
		float(cs.get("thickness_mm", 0.0)) * float(s * p))


func _connector_row() -> Dictionary:
	if _catalog_cache == null:
		_catalog_cache = PartsCatalog.load_default()
	for row in _catalog_cache.list_category("connector"):
		if String((row.get("catalog", {}) as Dictionary).get("family", "")) == connector_family:
			return row
	return {}


func _connector_pair_mass_g() -> float:
	return float(_connector_row().get("mass_g", 0.0))


## The connector family's continuous rating in amps (0.0 when the family is unknown).
func connector_continuous_a() -> float:
	return float((_connector_row().get("specs", {}) as Dictionary).get("continuous_a", 0.0))


## Read-only: the harness counts this, the designer only displays it.
func _connector_contact_ohm() -> float:
	return float((_connector_row().get("specs", {}) as Dictionary).get("contact_resistance_ohm", 0.0)) \
		* HarnessChecks.CONNECTOR_CONTACTS_IN_LOOP
