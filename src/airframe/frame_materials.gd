class_name FrameMaterials
extends RefCounted
## The material table of airframe.md §6.1, loaded off disk the way PartsCatalog loads a part
## category — same JSON-in-repo reasoning (architecture.md: a binary file cannot be reviewed in a
## pull request), same strict-about-structure/silent-about-extra-fields parsing, same
## `load_errors` + `is_valid()` shape, so a caller that already knows one knows this.
##
## ## Why materials became their own file, and not one more field on a frame
##
## `material` currently lives in frames.json's `catalog` block — browsing metadata — for the honest
## reason that nothing read it. airframe.md §6.1 moves it into physics: the day the model grows a
## stiffness term is the day material becomes physics-bearing. A density and a modulus that the
## mass, resonance and stress maths all multiply by cannot be a free-text string on twelve frames;
## it has to be one table with one number per property and a citation beside it.
##
## ## The direction-dependent modulus, and the tier it is quoted at
##
## A 3K twill plate is NOT isotropic. It is stiff along the weave (0° and 90°) and roughly 30% less
## stiff at 45°, so an arm cut diagonally across a sheet is a different arm from one cut along it.
## That is modelled here as two parameters — `youngs_modulus_gpa` (the stiff axis) and
## `youngs_modulus_45_gpa` — and `modulus_at_angle_gpa()` interpolates between them. §8 puts E(θ)
## in the CHARACTERISTIC tier: it may say which of two layups is stiffer and it may never put an
## error bar on the difference, which is why the data file labels it and why anything drawing this
## must carry the label through to its legend. A quasi-isotropic layup genuinely is
## direction-independent — which is exactly what builders pay extra for, and now the app can say
## why — so it carries no 45° value and `is_anisotropic()` is false for it.
##
## Nothing here is a part. Materials have no mass and no part_id: mass is always geometry times
## `density_kg_m3` (§5.1), computed by HardwareMass and by the polygon integrals, never tabulated.

const MATERIALS_PATH := "res://data/materials.json"

## The physically sane band any density must land in, fixed before the table was read rather than
## around it. The floor is below TPU and printed nylon (930 kg/m³ is the lightest thing on an
## airframe; a foam pad is modelled as a pad, not as bulk material). The ceiling is above steel
## (7850) with room, and well below the point where a number is a units slip — a density quoted in
## g/cm³ by mistake lands near 1-8, three orders low, and one quoted in g/m³ lands absurdly high.
## This is a TYPO NET, not a claim about materials science.
const DENSITY_MIN_KG_M3 := 500.0
const DENSITY_MAX_KG_M3 := 9000.0

## material_id -> Dictionary, the whole record.
var by_id: Dictionary = {}
## In file order, which is the order §6.1 tabulates them and the order any list should show.
var ordered: Array = []
var load_errors: Array[String] = []


static func load_default(path: String = MATERIALS_PATH) -> FrameMaterials:
	var table := FrameMaterials.new()
	table._load(path)
	return table


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		load_errors.append("%s: file not found" % path)
		return

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not parsed is Dictionary or not parsed.has("materials"):
		load_errors.append("%s: not a JSON object with a \"materials\" array" % path)
		return

	for entry in parsed["materials"]:
		# Structure only. A record missing an id, a density or a citation is a record the physics
		# would silently multiply by zero, so it is refused loudly here; a record carrying a field
		# this version does not read yet is fine and is kept.
		if not entry is Dictionary or not entry.has("material_id") or not entry.has("specs"):
			load_errors.append("%s: entry missing material_id or specs" % path)
			continue
		var specs: Dictionary = entry["specs"]
		if not specs.has("density_kg_m3"):
			load_errors.append("%s: %s has no density_kg_m3" % [path, entry["material_id"]])
			continue
		if str(entry.get("source", "")).strip_edges().is_empty():
			load_errors.append("%s: %s has no source" % [path, entry["material_id"]])
			continue
		by_id[str(entry["material_id"])] = entry
		ordered.append(entry)


## The `_schema` prose the file carries. Nothing in the app reads it — it exists for the next
## contributor, which is exactly why a test holds it to what it claims. Read off disk rather than
## kept as parsed state, so it cannot become one more thing to keep in step.
static func schema(path: String = MATERIALS_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("_schema", ""))


func get_material(material_id: String) -> Dictionary:
	return by_id.get(material_id, {})

func ids() -> Array:
	var out: Array = []
	for entry in ordered:
		out.append(str(entry["material_id"]))
	return out

func is_valid() -> bool:
	return load_errors.is_empty() and not ordered.is_empty()


## kg/m³. The number every mass in the airframe is geometry multiplied by, which is why it is the
## one field a record may not load without.
func density(material_id: String) -> float:
	return float(get_material(material_id).get("specs", {}).get("density_kg_m3", 0.0))

## GPa along the stiff axis (0°/90° for a weave; the only axis there is for everything else).
func modulus_gpa(material_id: String) -> float:
	return float(get_material(material_id).get("specs", {}).get("youngs_modulus_gpa", 0.0))

## MPa, or 0.0 where the material has no meaningful structural strength and the table declines to
## invent one (TPU 95A). A caller wanting a stress margin must treat 0.0 as "not answerable here"
## rather than as "fails" — §8 forbids a number where there is no source for one.
func strength_mpa(material_id: String) -> float:
	return float(get_material(material_id).get("specs", {}).get("strength_mpa", 0.0))

## Whether this material's stiffness depends on which way the part was cut out of the sheet.
func is_anisotropic(material_id: String) -> bool:
	return get_material(material_id).get("specs", {}).has("youngs_modulus_45_gpa")


## E(θ) for a part cut at `angle_deg` to the sheet's 0° weave direction.
##
## CHARACTERISTIC (§8): ranking only, no error bar, ever, until something is measured. The shape is
## the simplest thing that has the two facts we actually have — E(0°) = E(90°) = stiff axis,
## E(45°) = the knockdown value — and nothing else: a cos(4θ) blend between them, which is periodic
## in 90° exactly as a balanced 0/90 weave is. It is not a laminate-theory solution and does not
## pretend to be one; laminate theory would need ply-by-ply data this table does not have and the
## builder does not know. For an isotropic material this returns the single modulus at every angle,
## which is the whole point of paying for a quasi-isotropic layup.
func modulus_at_angle_gpa(material_id: String, angle_deg: float) -> float:
	var stiff := modulus_gpa(material_id)
	if not is_anisotropic(material_id):
		return stiff
	var soft := float(get_material(material_id)["specs"]["youngs_modulus_45_gpa"])
	# 1 at 0° and 90°, 0 at 45°. deg_to_rad(4 * angle) has period 90° in angle.
	var blend := (cos(deg_to_rad(4.0 * angle_deg)) + 1.0) * 0.5
	return soft + (stiff - soft) * blend
