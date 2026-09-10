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
	# The four LTHL-11 unbundled out of Build.ELECTRONICS_BUDGET_G. Unlike the six above, a build
	# may fit NONE of these — see Build.OPTIONAL_COMPONENTS — so their presence in this table is
	# what makes them selectable, not what makes them required.
	"camera": "res://data/parts/cameras.json",
	"vtx": "res://data/parts/vtxs.json",
	"antenna": "res://data/parts/antennas.json",
	"receiver": "res://data/parts/receivers.json",
	# P10a (propulsion.md §9 P10 row / plans/2026-08-26-propulsion-room-design.md §3): guards enter
	# on the same shape as the four above — a build may fit NONE, in which case nothing here
	# touches the reference-build oracle (496 g / 11.69:1 / 29.6%). Physics is
	# src/propulsion/prop_guard.gd; wiring into AirframeProperties.extra_parts is
	# PropGuard.as_part_mass(), which plants the guard's mass at the motor's plan position and
	# lets parallel-axis supply the R² bite exactly once — P9's row spells out the double-count
	# trap that would otherwise result.
	"guard": "res://data/parts/guards.json",
	# PW1 (plans/2026-09-10-power-room-design.md §4.1). The two halves of the current path that are
	# products you buy; the third — wire — is deliberately NOT here, because wire is a gauge and a
	# length rather than a part, and a row per gauge could not answer "what if I shorten these
	# leads". That lives in src/power/wire_gauge.gd on HardwareMass's argument.
	#
	# `connector` carries the join this slice exists to get right: its catalog.family must match
	# batteries.json's catalog.connector character for character, or PW3's compatibility check
	# compares two strings that never match and passes on every build forever.
	"connector": "res://data/parts/connectors.json",
	"capacitor": "res://data/parts/capacitors.json",
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

## The catalog Lab and Sim read: everything shipped, plus the parts this builder entered.
##
## A SECOND constructor rather than a flag on the first, and that is the load-bearing decision in
## the whole custom-parts feature. Forty-odd test files and ReferenceBuild call load_default(),
## and a flag defaulting to "no custom parts" would put one boolean between a hand-edited file and
## the 496 g oracle. Two functions cannot be got wrong by forgetting an argument.
##
## Custom parts are APPENDED, so the catalog's own order — which is the dropdown order, and which
## every category file is authored smallest-part-first to produce — is untouched and a builder's
## own parts collect at the end of the rail where they can be found.
##
## One loop per category rather than one document read: each CustomParts subclass owns its own
## array key and refuses records its category cannot use, so a motor with no thrust test is gone
## before it reaches here.
static func load_with_custom(path: String = CustomParts.SAVE_PATH) -> PartsCatalog:
	var catalog := load_default()
	# Propellers FIRST: a custom motor's thrust_test.prop_id may name a custom prop, and
	# CustomMotors.read_from resolves it against a catalog whose props have already been merged.
	# Reversed load order would refuse a motor citing a custom prop at load time, with a message
	# saying the prop is not one Lothal knows about — a silent-fail via ordering, not via missing
	# data. tests/test_custom_propellers.gd asserts the order from both sides.
	var custom_props := CustomPropellers.load_from(path)
	catalog._merge_custom(path, custom_props)
	catalog._merge_custom(path, CustomFrames.load_from(path))
	catalog._merge_custom(path, CustomMotors.load_from(path, catalog))
	catalog._merge_custom(path, CustomBatteries.load_from(path))
	# The two halves of the stack. Order between them does not matter — neither cross-references the
	# other, and neither cross-references anything else — but they come after the four above so that
	# the merged catalog is assembled in the same order the categories were built.
	catalog._merge_custom(path, CustomEscs.load_from(path))
	catalog._merge_custom(path, CustomFlightControllers.load_from(path))
	# The four LTHL-11 unbundled. Last, in the order Build.OPTIONAL_COMPONENTS weighs them, and
	# order among them does not matter for the same reason it does not for the stack's two: none of
	# them cross-references anything.
	catalog._merge_custom(path, CustomCameras.load_from(path))
	catalog._merge_custom(path, CustomVtxs.load_from(path))
	catalog._merge_custom(path, CustomAntennas.load_from(path))
	catalog._merge_custom(path, CustomReceivers.load_from(path))
	return catalog


func _merge_custom(path: String, document: CustomParts) -> void:
	for record in document.records():
		# Cannot collide: the prefix rule in _load_category refuses these ids in a shipped file and
		# CustomParts refuses anything without the prefix. Asserted rather than assumed, because
		# "cannot happen" is exactly the class of thing that starts happening.
		if by_id.has(record["part_id"]):
			load_errors.append("%s: %s %s collides with a shipped part" % [
				path, document.category(), record["part_id"]])
			continue
		by_category[document.category()].append(record)
		by_id[record["part_id"]] = record

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
