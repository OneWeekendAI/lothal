class_name CustomBatteries
extends CustomParts
## The batteries a builder entered themselves. Read CustomParts first for the id space, the shared
## document and the refusals that are not about batteries.
##
## A builder enters what is printed on the pack's wrapper and Lothal flies it. Batteries only. The
## pack is the biggest single mass in most builds and the only source of voltage sag, so this is
## the category where a wrong number is felt most.
##
## ---------------------------------------------------------------------------
## THE ONE FIELD NO PACK PRINTS
## ---------------------------------------------------------------------------
##
## specs.internal_r_ohm drives everything sag-related — punch throttle, current spikes, voltage
## drops, RPM ceiling drops, thrust drops. NO manufacturer publishes it. Asking a builder to type
## it guarantees either a blank field or a guess worse than one Lothal could make.
##
## But it is predictable from mAh and C, which ARE printed. Fitted across the shipped catalog:
##
##     K = r_per_cell(mOhm) * Ah * C
##     LiPo, 2S-6S (9 packs):  median K = 336, spread 236..422 (1.79x)
##     Li-ion   (2 packs):     median K = 1229, spread 1125..1333 (1.19x)
##     1S whoop (2 packs):     K = 810, 1540 — a different regime, kept separate
##
## So `internal_r_ohm` is DERIVED by default from mAh, C and cells, and left overridable by anyone
## who has actually measured their pack with a meter. The form asks for what is on the wrapper;
## the derived value is shown, labelled as derived, and edited when there is a measurement.
##
## HONESTY CAVEAT, stated here and repeated in the UI. These K values were fitted against a
## catalog whose own `internal_r_ohm` figures were mostly authored as "representative" rather than
## measured. This is therefore a SELF-CONSISTENCY relationship, not a validated one: deriving from
## it reproduces the catalog's assumption faithfully and proves nothing about real packs. That is
## still the right default — better a stated assumption than a user's blind guess — but a derived
## resistance must not be presented as a measurement, and the custom-provenance warning names the
## caveat every build a derived pack flies on.
##
## ---------------------------------------------------------------------------
## nominal_v IS ALSO DERIVED
## ---------------------------------------------------------------------------
##
## The catalog is internally consistent: LiPo is 3.7 V/cell, Li-ion is 3.6 V/cell. Deriving
## nominal_v from cells+chemistry closes a real error path — a builder who types 6 for a 6S pack
## gets 6 V instead of 22.2 V, the physics absorbs it silently, and every downstream number is
## wrong. The chemistry table matches BatteryModel.NOMINAL_CELL_V because the curve fit around
## nominal must agree with the value that names it.

const BATTERIES_KEY := "batteries"

## The chemistries this document knows, and the per-cell nominal that goes with each. Kept in step
## with BatteryModel.NOMINAL_CELL_V by a test — a chemistry admitted here that the model has no
## curve for would silently fall back to LiPo and mean something different in flight from what the
## record says.
const NOMINAL_V_PER_CELL := {
	"LiPo": 3.70,
	"Li-ion": 3.60,
}

## Pre-registered from the shipped catalog before any custom pack was measured against them. See the
## header for the derivation and the honesty caveat. These numbers do not move to fit user data;
## they move only when the shipped catalog changes.
##
## The 1S regime is separate because two data points is not a fit — its K is documented as the
## weakest branch in this file and the derivation labels it so.
const K_LIPO_MULTICELL := 336.0
const K_LIPO_MULTICELL_SPREAD := 1.8
const K_LI_ION := 1229.0
const K_LI_ION_SPREAD := 1.2
const K_LIPO_1S := 1175.0
const K_LIPO_1S_SPREAD := 2.0

## The strap is the only attachment a real quad pack uses. Every shipped entry declares it.
const STRAP_ATTACHMENT := "strap"


func array_key() -> String:
	return BATTERIES_KEY


func category() -> String:
	return "battery"


func batteries() -> Array:
	return records()


func get_battery(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomBatteries:
	var doc := CustomBatteries.new()
	doc.read_from(path)
	return doc


# ---------------------------------------------------------------------------
# Building a record
# ---------------------------------------------------------------------------

## A catalog-shaped record from what a builder reads off the pack's wrapper. Static, and the ONE
## place a record's shape is written down.
##
## `internal_r_ohm_override` is the escape hatch for a measurement: a positive value survives as
## the pack's `internal_r_ohm`; anything else defers to the derivation from mAh and C. The default
## is `NAN` rather than `0.0` so a caller passing "no override" cannot be confused with a caller
## measuring a superconductor.
static func make_record(name: String, cells: int, chemistry: String, mah: float, c_rating: float,
		mass_g: float, length_mm: float, width_mm: float, height_mm: float,
		connector: String, source: String, internal_r_ohm_override: float = NAN) -> Dictionary:
	var derived_nominal := nominal_v_for(cells, chemistry)
	var internal_r: float
	if internal_r_ohm_override > 0.0:
		internal_r = internal_r_ohm_override
	else:
		internal_r = derived_internal_r_ohm(cells, mah, c_rating)
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "battery",
		"mass_g": mass_g,
		"mounting": {
			"attachment": STRAP_ATTACHMENT,
		},
		"specs": {
			"cells": cells,
			"nominal_v": derived_nominal,
			"mah": mah,
			"internal_r_ohm": internal_r,
			"chemistry": chemistry,
			"c_rating": c_rating,
			"length_mm": length_mm,
			"width_mm": width_mm,
			"height_mm": height_mm,
		},
		"catalog": {
			"cell_class": cell_class_for(cells),
			"connector": connector,
		},
		"source": source,
		"derivation": {
			"nominal_v": true,
			# True when the derivation supplied the value, false when a measurement overrode it.
			# Preserved so a later save does not silently recompute over a user override, and so
			# the UI can label the field honestly.
			"internal_r_ohm": not (internal_r_ohm_override > 0.0),
		},
	}


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "battery")


## The picker's cell bucket. Spelled the way batteries.json spells it: "1S", "4S", "6S". A custom
## pack lands in the shipped catalog's own bucket rather than in a bucket of one — same reasoning
## as CustomFrames.size_class_for.
static func cell_class_for(cells: int) -> String:
	return "%dS" % cells


## The chemistry's per-cell nominal, times cells. NOT cells * 3.7: a 4S LiPo is 14.8 V and a 4S
## Li-ion is 14.4 V, and the difference matters because the discharge curve hangs off it. Falls
## back to LiPo for an unknown chemistry, matching BatteryModel's own fallback so the two agree.
static func nominal_v_for(cells: int, chemistry: String) -> float:
	var per_cell: float = float(NOMINAL_V_PER_CELL.get(chemistry, NOMINAL_V_PER_CELL["LiPo"]))
	return float(cells) * per_cell


## The K constant this pack sits under. Public because the self-check test asks for it directly —
## and because the branch matters (1S is the weakest of the three) and a caller ought to be able
## to say so.
static func k_for(cells: int, chemistry: String) -> float:
	if chemistry == "Li-ion":
		return K_LI_ION
	if cells <= 1:
		return K_LIPO_1S
	return K_LIPO_MULTICELL


static func spread_for(cells: int, chemistry: String) -> float:
	if chemistry == "Li-ion":
		return K_LI_ION_SPREAD
	if cells <= 1:
		return K_LIPO_1S_SPREAD
	return K_LIPO_MULTICELL_SPREAD


## Pack internal resistance in ohms, derived from mAh, C, cells and chemistry. Zero for a
## degenerate pack (no cells, no capacity or no C), because there is no meaningful sag figure to
## invent and a downstream reader will notice a zero where a positive is expected.
static func derived_internal_r_ohm(cells: int, mah: float, c_rating: float) -> float:
	if cells <= 0 or mah <= 0.0 or c_rating <= 0.0:
		return 0.0
	# Default to LiPo K if we cannot ask about chemistry — this helper takes the two nameplate
	# numbers, and derived_internal_r_ohm_for below is the chemistry-aware form. Kept as two
	# functions rather than one with a default, because the physics is chemistry-first and a
	# LiPo default hiding inside a helper is exactly the seam that silently applies a LiPo K
	# to a Li-ion pack.
	return _r_ohm_from_k(K_LIPO_MULTICELL if cells > 1 else K_LIPO_1S, cells, mah, c_rating)


## Chemistry-aware derivation. `make_record` calls this; the two-arg version above is left for
## callers that already know they mean LiPo.
static func derived_internal_r_ohm_for(cells: int, chemistry: String, mah: float, c_rating: float) -> float:
	if cells <= 0 or mah <= 0.0 or c_rating <= 0.0:
		return 0.0
	return _r_ohm_from_k(k_for(cells, chemistry), cells, mah, c_rating)


static func _r_ohm_from_k(k: float, cells: int, mah: float, c_rating: float) -> float:
	# K = r_per_cell(mOhm) * Ah * C  ->  r_per_cell(mOhm) = K / (Ah * C)
	# pack r(Ohm) = r_per_cell(mOhm) * cells / 1000
	var ah := mah / 1000.0
	var r_per_cell_mohm := k / (ah * c_rating)
	return r_per_cell_mohm * float(cells) / 1000.0


# ---------------------------------------------------------------------------
# The battery-specific refusals
# ---------------------------------------------------------------------------

## Each of these is a case where the sim would produce a number rather than a complaint — a
## refusal is only defensible where the alternative is silence.
##
## Nothing here is about whether a pack is SENSIBLE. A 300 mAh 200C claim is accepted, flown, and
## warned about by BatteryPlausibility, because labs-and-sim.md §2 warns and never blocks.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: cells, chemistry, mah, c_rating and the pack's three dimensions, as printed on the wrapper")
		return problems
	var specs := raw_specs as Dictionary

	if not specs.has("cells") or int(specs["cells"]) < 1:
		problems.append("specs.cells must be present and at least 1 — a zero-cell pack has no voltage to flow through anything")

	# Chemistry decides which discharge curve BatteryModel runs. An unknown chemistry would silently
	# fall back to LiPo, which is a different pack from a different regime — Li-ion's 10x internal
	# resistance is not a rounding error next to a LiPo's, it is the whole reason a long-range pack
	# feels different in the air.
	var chemistry := str(specs.get("chemistry", "")).strip_edges()
	if chemistry == "":
		problems.append("specs.chemistry is required — \"LiPo\" or \"Li-ion\"")
	elif not NOMINAL_V_PER_CELL.has(chemistry):
		problems.append("specs.chemistry \"%s\" is not a chemistry Lothal knows about (\"LiPo\" or \"Li-ion\")" % chemistry)

	for field in ["mah", "c_rating"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — it is on the wrapper and nothing here can stand in for it" % field)

	for field in ["length_mm", "width_mm", "height_mm"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — the pack is drawn from these three numbers and its fit against the frame is checked from them" % field)

	# nominal_v and internal_r_ohm are DERIVED, not asked for. But if a record somehow arrived here
	# with a non-positive value in either — a hand-edited file that zeroed one out — nothing in the
	# physics would complain: nominal 0 V makes an aircraft that never lifts, internal_r 0 makes a
	# superconductor. Both are silent failures the pack itself would never announce, so they are
	# refused here rather than let past.
	if specs.has("nominal_v") and float(specs["nominal_v"]) <= 0.0:
		problems.append("specs.nominal_v must be positive if present — leave it out to derive from cells and chemistry")
	if specs.has("internal_r_ohm") and float(specs["internal_r_ohm"]) <= 0.0:
		problems.append("specs.internal_r_ohm must be positive if present — leave it out to derive from mAh and C")

	# The catalog authors every pack with `mounting.attachment = "strap"` and nothing else reads a
	# bolt pattern off a battery. A pack that arrived without the block would fall through the
	# assembly panel's fit checks silently, so require it.
	var mounting: Variant = record.get("mounting", null)
	if not (mounting is Dictionary) or str((mounting as Dictionary).get("attachment", "")) != STRAP_ATTACHMENT:
		problems.append("mounting.attachment must be \"%s\" — packs strap, they do not bolt, and every reader assumes it" % STRAP_ATTACHMENT)

	return problems
