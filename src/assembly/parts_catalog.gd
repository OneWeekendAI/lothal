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
	"esc": "res://data/parts/escs.json",
	"flight_controller": "res://data/parts/flight_controllers.json",
}

## The id prefix a builder-entered part MUST carry, and which a SHIPPED part may never carry.
##
## This is the whole of the collision defence, and it is deliberately structural rather than a
## convention anyone has to remember. PartsCatalog.by_id is one flat dictionary, and load_default()
## is what ReferenceBuild calls — so a custom frame that managed to call itself
## "frame_5in_freestyle" would not merely shadow the catalog entry, it would BECOME the 496 g
## oracle that six test files assert against, and every one of them would go on passing against a
## number the builder typed. Two id spaces that cannot intersect is the only version of this that
## does not depend on anybody being careful.
##
## Enforced from both ends: _load_category refuses it below, and CustomFrames requires it.
const CUSTOM_PREFIX := "custom_"


## Whether a part id belongs to a builder rather than to the catalog. The id IS the mark — there is
## no `is_custom` FIELD on the record, because a field can be absent, mistyped or copied off, and
## the thing asking is usually holding nothing but the id.
static func is_custom(part_id: String) -> bool:
	return part_id.begins_with(CUSTOM_PREFIX)

## category -> Array[Dictionary], in catalog file order (which is the dropdown order).
var by_category: Dictionary = {}
## part_id -> Dictionary, for direct lookup.
var by_id: Dictionary = {}
var load_errors: Array[String] = []

## The SHIPPED catalog, and nothing else. It cannot contain a builder's custom part — the prefix
## rule above makes that a load error rather than a matter of trust — which is what lets
## ReferenceBuild go on calling this and stay pinned at 496 g no matter what is in user://.
## Lab and Sim call load_with_custom() instead.
static func load_default() -> PartsCatalog:
	var catalog := PartsCatalog.new()
	for category in CATEGORY_FILES:
		catalog._load_category(category, CATEGORY_FILES[category])
	return catalog

## The catalog Lab and Sim read: everything shipped, plus the frames this builder entered.
##
## A SECOND constructor rather than a flag on the first, and that is the load-bearing decision in
## this whole slice. Forty-odd test files and ReferenceBuild call load_default(), and a flag
## defaulting to "no custom parts" would put one boolean between a hand-edited file and the 496 g
## oracle. Two functions cannot be got wrong by forgetting an argument.
##
## Custom frames are APPENDED, so the catalog's own order — which is the dropdown order, and which
## every category file is authored smallest-part-first to produce — is untouched and a builder's
## own frames collect at the end of the rail where they can be found.
static func load_with_custom(path: String = CustomFrames.SAVE_PATH) -> PartsCatalog:
	var catalog := load_default()
	for frame in CustomFrames.load_from(path).frames():
		# Cannot collide: the prefix rule in _load_category refuses these ids in a shipped file and
		# CustomFrames refuses anything without the prefix. Asserted rather than assumed, because
		# "cannot happen" is exactly the class of thing that starts happening.
		if catalog.by_id.has(frame["part_id"]):
			catalog.load_errors.append("%s: custom frame %s collides with a shipped part" % [
				path, frame["part_id"]])
			continue
		catalog.by_category["frame"].append(frame)
		catalog.by_id[frame["part_id"]] = frame
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
		if is_custom(str(entry["part_id"])):
			load_errors.append("%s: %s claims the reserved \"%s\" prefix, which only a builder's own parts may use" % [
				path, entry["part_id"], CUSTOM_PREFIX])
			continue
		if entry.get("category", category) != category:
			load_errors.append("%s: %s declares category %s" % [path, entry["part_id"], entry["category"]])
			continue
		by_category[category].append(entry)
		by_id[entry["part_id"]] = entry

## The `_schema` prose a category file carries. Nothing in the app reads it — it exists for the
## next contributor, which is exactly why a test holds it to what it claims. Read off disk rather
## than kept as parsed state, so it cannot become one more thing to keep in step.
static func schema_for(category: String) -> String:
	var path: String = CATEGORY_FILES.get(category, "")
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("_schema", ""))

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
