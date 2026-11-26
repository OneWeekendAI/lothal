class_name CustomGuards
extends CustomParts
## The prop guards a builder entered themselves (plan item 7). Read CustomParts for the id space and
## the shared document, and src/propulsion/prop_guard.gd for the physics — NOTHING here duplicates it.
##
## ---------------------------------------------------------------------------
## WHAT THE STORE ASKS, AND WHAT IT DERIVES
## ---------------------------------------------------------------------------
##
## A guard's spec is exactly what `PropGuard.compute` reads: kind, outer radius, wall, height,
## density, mount radius, and (optionally) `tip_gap_mm`. The store holds those and refuses what the
## physics itself refuses, using the physics' own verdict (`compute`'s tier, `clearance_check`):
##
##   - `mass_g` is DERIVED (`PropGuard.mass_kg(specs)`), never typed, which is the invariant
##     tests/test_parts_system.gd holds the shipped guards.json to. The base class's "mass must be
##     positive" refusal then also catches a ring whose geometry is unreadable (mass 0).
##   - the tip gap must be POSITIVE when entered. A zero or negative gap is a ring through the
##     blade; `PropGuard.tip_clearance_mm` would report it honestly, but a part a builder SAVES
##     should not begin life interfering with the prop it was drawn against.
##   - a DUCT must state its gap. `ring_tip_gap_mm` falls back to a labelled 5.5 mm default for a
##     spec with none, which is right for a bumper (it claims no thrust) and wrong for a duct,
##     whose gap IS its thrust claim (propulsion.md §6.3).
##
## The ring is saved as sold against the prop it was entered beside: outer = tip + gap + wall. On any
## build `PropGuard.fitted_guard` resizes it to the fitted prop anyway (PG1), so the saved outer
## radius only matters to the catalog rail and to `clearance_check` at entry time.

const GUARDS_KEY := "guards"


func array_key() -> String:
	return GUARDS_KEY


func category() -> String:
	return "guard"


func guards() -> Array:
	return records()


static func load_from(path: String = SAVE_PATH) -> CustomGuards:
	var document := CustomGuards.new()
	document.read_from(path)
	return document


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "guard")


## The spec a guard record carries. `tip_gap_mm` NAN means "not entered" and becomes an ABSENT key,
## which `PropGuard.clearance_is_assumed` reads as the labelled default.
static func make_specs(kind: String, outer_radius_mm: float, wall_mm: float, height_mm: float,
		density_kg_m3: float, mount_radius_mm: float, tip_gap_mm: float) -> Dictionary:
	var specs := {
		"kind": kind,
		"outer_radius_mm": outer_radius_mm,
		"wall_mm": wall_mm,
		"height_mm": height_mm,
		"density_kg_m3": density_kg_m3,
		"mount_radius_mm": mount_radius_mm,
	}
	if not is_nan(tip_gap_mm):
		specs["tip_gap_mm"] = tip_gap_mm
	return specs


static func make_record(name: String, specs: Dictionary, prop_class: String, material: String,
		source: String) -> Dictionary:
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "guard",
		"mass_g": PropGuard.mass_kg(specs) * 1000.0,
		"specs": specs,
		"catalog": {"prop_class": prop_class, "intended_use": "custom", "material": material},
		"source": source,
	}


func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []
	var raw: Variant = record.get("specs", null)
	if not (raw is Dictionary):
		problems.append("specs is required: the ring's kind, outer radius, wall, height, density and mount radius")
		return problems
	var specs := raw as Dictionary

	var result := PropGuard.compute(specs)
	if String(result["tier"]) != "computed":
		problems.append("the ring cannot be read (%s) — kind must be \"bumper\" or \"duct\", and radius, wall, height and density must be positive with the wall thinner than the ring" % String(result["tier"]))
	else:
		var derived_g := float(result["mass_kg"]) * 1000.0
		if absf(float(record.get("mass_g", 0.0)) - derived_g) > 1.0e-6:
			problems.append("mass_g must be what the ring weighs (%.4f g), computed from its geometry — it is not a number to type" % derived_g)

	if specs.has("tip_gap_mm"):
		var gap: Variant = specs["tip_gap_mm"]
		if not (gap is float or gap is int):
			problems.append("specs.tip_gap_mm must be a number of millimetres, not %s" % type_string(typeof(gap)))
		elif float(gap) <= 0.0:
			problems.append("specs.tip_gap_mm must be positive — a ring with no gap to the blade tip is a ring through the prop")
	elif String(specs.get("kind", "")) == PropGuard.KIND_DUCT:
		problems.append("specs.tip_gap_mm is required for a duct — its gap is its thrust claim, and the 5.5 mm default is a bumper's")
	return problems
