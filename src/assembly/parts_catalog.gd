class_name PartsCatalog
extends RefCounted
## Loads the JSON component catalog from data/parts/ (architecture.md: JSON in-repo, not
## SQLite — a binary file cannot be reviewed in a pull request, which kills the
## contribution loop). One file per category, each holding a "parts" array.
##
## Parsing is strict about structure and silent about extra fields: a contributor adding a
## spec the sim does not read yet should not break the build, but a malformed file should
## say so loudly rather than producing a drone with zero mass.

const CATEGORY_FILES := {
	"frame": "res://data/parts/frames.json",
	"motor": "res://data/parts/motors.json",
	"propeller": "res://data/parts/propellers.json",
	"battery": "res://data/parts/batteries.json",
}

## category -> Array[Dictionary], in catalog file order (which is the dropdown order).
var by_category: Dictionary = {}
## part_id -> Dictionary, for direct lookup.
var by_id: Dictionary = {}
var load_errors: Array[String] = []

static func load_default() -> PartsCatalog:
	var catalog := PartsCatalog.new()
	for category in CATEGORY_FILES:
		catalog._load_category(category, CATEGORY_FILES[category])
	return catalog

func _load_category(category: String, path: String) -> void:
	by_category[category] = []

	if not FileAccess.file_exists(path):
		load_errors.append("%s: file not found" % path)
		return

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary or not parsed.has("parts"):
		load_errors.append("%s: not a JSON object with a \"parts\" array" % path)
		return

	for entry in parsed["parts"]:
		if not entry is Dictionary or not entry.has("part_id") or not entry.has("mass_g"):
			load_errors.append("%s: entry missing part_id or mass_g" % path)
			continue
		if entry.get("category", category) != category:
			load_errors.append("%s: %s declares category %s" % [path, entry["part_id"], entry["category"]])
			continue
		by_category[category].append(entry)
		by_id[entry["part_id"]] = entry

func get_part(part_id: String) -> Dictionary:
	return by_id.get(part_id, {})

func list_category(category: String) -> Array:
	return by_category.get(category, [])

func is_valid() -> bool:
	if not load_errors.is_empty():
		return false
	for category in CATEGORY_FILES:
		if list_category(category).is_empty():
			return false
	return true
