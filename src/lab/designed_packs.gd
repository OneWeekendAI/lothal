class_name DesignedPacks
extends CustomParts
## The packs a builder designed (or typed, in the older form), in user://custom_parts.json under
## the same `batteries` key the hand-typed form used, so nothing is moved. Read CustomParts first
## for the id space, the shared document and the generic refusals.
##
## SCHEMA 2 and the migration. A record with no `design` block is an older hand-typed battery. On
## load it gets a `design` block marking it "legacy (typed figures)" and nothing else changes: its
## specs, mass_g, part_id and name are the very same values, so it flies exactly as before and its
## pack_charge.json state (keyed by part_id) still belongs to it. The migration is in memory; the
## file is rewritten only when something saves it.
##
## CHARGE RULES (spec call 3). Changing S, P, the cell or the capacity of a saved pack puts it back
## to full under the same id. A rename keeps id and state. "Save as" makes a new id at full charge.
## Wiring-only edits keep the charge: the cells did not change.

const BATTERIES_KEY := "batteries"
const STRAP_ATTACHMENT := "strap"

var _path: String = CustomParts.SAVE_PATH


func array_key() -> String:
	return BATTERIES_KEY


func category() -> String:
	return "battery"


static func load_from(path: String = SAVE_PATH) -> DesignedPacks:
	var doc := DesignedPacks.new()
	doc._path = path
	doc.read_from(path)
	return doc


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

func _migrate(document: Dictionary, _from_version: int) -> Dictionary:
	var stored: Variant = document.get(BATTERIES_KEY, null)
	if not (stored is Array):
		return document
	var out := document.duplicate(false)
	var migrated: Array = []
	for entry in (stored as Array):
		if entry is Dictionary and not (entry as Dictionary).has("design"):
			migrated.append(migrate_v1_record(entry as Dictionary))
		else:
			migrated.append(entry)
	out[BATTERIES_KEY] = migrated
	return out


## An older hand-typed battery record plus a legacy design block. specs, mass_g, part_id, name and
## every other field are carried over untouched; only `design` is added.
static func migrate_v1_record(rec: Dictionary) -> Dictionary:
	var out := rec.duplicate(true)
	var specs: Dictionary = out.get("specs", {}) if out.get("specs") is Dictionary else {}
	var cells := maxi(int(specs.get("cells", 1)), 1)
	var mah := float(specs.get("mah", 0.0))
	var cont := float(specs.get("c_rating", 0.0)) * mah / 1000.0
	var cell := CellLibrary.custom_cell(
		"%s (typed cell)" % String(out.get("name", "pack")),
		String(specs.get("chemistry", "LiPo")), mah, cont, cont,
		float(specs.get("internal_r_ohm", 0.0)) / float(cells) * 1000.0,
		float(out.get("mass_g", 0.0)) / float(cells),
		Vector3(float(specs.get("length_mm", 0.0)), float(specs.get("width_mm", 0.0)),
			float(specs.get("height_mm", 0.0)) / float(cells)), "pouch")
	out["design"] = {
		"legacy": true,
		"basis": PackDesign.LEGACY_BASIS,
		"series": cells,
		"parallel": 1,
		"custom_cell": cell,
	}
	return out


# ---------------------------------------------------------------------------
# Designs
# ---------------------------------------------------------------------------

func designs(lib: CellLibrary) -> Array[PackDesign]:
	var out: Array[PackDesign] = []
	for rec in _records:
		out.append(PackDesign.from_record(rec, lib))
	return out


## Saves `design` under `previous_id` (an edit) or under a fresh id (a new pack), writes the file
## and returns the id; "" when the record is refused (the stored version is left as it was).
## The caller owns saving `charge`.
func save_design(design: PackDesign, charge: PackCharge, previous_id: String = "") -> String:
	var rec := design.to_record()
	var old := get_record(previous_id) if previous_id != "" else {}
	var id := previous_id if not old.is_empty() else _fresh_id(design.name)
	rec["part_id"] = id

	# Fields this version does not know survive an edit.
	var merged := old.duplicate(true)
	for k in rec:
		merged[k] = rec[k]

	var reset := not old.is_empty() and _electrically_changed(old, merged)

	var old_index := _index_of(id)
	var held: Dictionary = {}
	if old_index >= 0:
		held = _records[old_index]
		_records.remove_at(old_index)
	var problems := _add_against(merged, _catalog_for_add())
	if not problems.is_empty():
		if old_index >= 0:
			_records.insert(old_index, held)
		push_warning("pack not saved: %s" % "; ".join(problems))
		return ""
	if old_index >= 0:
		# Keep the shelf order: the edited pack stays where it was.
		var added: Dictionary = _records.pop_back()
		_records.insert(old_index, added)
	if reset and charge != null:
		charge.set_used_mah(id, 0.0)
	save(_path)
	return id


## A new pack from this design, at full charge. Never touches the pack it was copied from.
func save_as(design: PackDesign, charge: PackCharge = null) -> String:
	var copy := PackDesign.from_record(design.to_record(), CellLibrary.load_default())
	copy.cell = design.cell
	copy.part_id = ""
	var id := save_design(copy, charge, "")
	if id != "" and charge != null:
		charge.set_used_mah(id, 0.0)
	return id


func _index_of(part_id: String) -> int:
	for i in _records.size():
		if str(_records[i].get("part_id", "")) == part_id:
			return i
	return -1


func _fresh_id(name: String) -> String:
	var base := CustomParts.id_for_name(name, "battery")
	var id := base
	var n := 2
	while _index_of(id) >= 0:
		id = "%s_%d" % [base, n]
		n += 1
	return id


## S, P, the cell or the capacity differ from what is stored.
static func _electrically_changed(old: Dictionary, new: Dictionary) -> bool:
	var a: Dictionary = old.get("design", {})
	var b: Dictionary = new.get("design", {})
	if int(a.get("series", -1)) != int(b.get("series", -2)) \
			or int(a.get("parallel", -1)) != int(b.get("parallel", -2)):
		return true
	if JSON.stringify(a.get("cell_id", "")) != JSON.stringify(b.get("cell_id", "")) \
			or JSON.stringify(a.get("custom_cell", {})) != JSON.stringify(b.get("custom_cell", {})):
		return true
	return not is_equal_approx(float((old.get("specs", {}) as Dictionary).get("mah", 0.0)),
		float((new.get("specs", {}) as Dictionary).get("mah", 0.0)))


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

## The same refusals the hand-typed form made, with the chemistry list now what BatteryModel knows.
## A refusal exists only where the alternative is silence; whether a pack is SENSIBLE is
## BatteryPlausibility's job, and it warns.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: cells, chemistry, mah, c_rating and the pack's three dimensions")
		return problems
	var specs := raw_specs as Dictionary

	if not specs.has("cells") or int(specs["cells"]) < 1:
		problems.append("specs.cells must be present and at least 1 — a zero-cell pack has no voltage to flow through anything")

	var chemistry := str(specs.get("chemistry", "")).strip_edges()
	if chemistry == "":
		problems.append("specs.chemistry is required")
	elif not BatteryModel.is_known_chemistry(chemistry):
		problems.append("specs.chemistry \"%s\" is not a chemistry Lothal knows about (%s)" % [
			chemistry, ", ".join(BatteryModel.known_chemistries())])

	for field in ["mah", "c_rating"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive" % field)

	for field in ["length_mm", "width_mm", "height_mm"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — the pack is drawn from these three numbers" % field)

	if specs.has("nominal_v") and float(specs["nominal_v"]) <= 0.0:
		problems.append("specs.nominal_v must be positive if present")
	if specs.has("internal_r_ohm") and float(specs["internal_r_ohm"]) <= 0.0:
		problems.append("specs.internal_r_ohm must be positive if present")

	var mounting: Variant = record.get("mounting", null)
	if not (mounting is Dictionary) or str((mounting as Dictionary).get("attachment", "")) != STRAP_ATTACHMENT:
		problems.append("mounting.attachment must be \"%s\" — packs strap, they do not bolt" % STRAP_ATTACHMENT)

	return problems
