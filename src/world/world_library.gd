class_name WorldLibrary
extends RefCounted
## The worlds a builder has: one JSON file each in a directory (`user://worlds/<id>.world.json`), so a world is shared by
## copying its file. Also the one-way migration of the legacy user://sites.json and user://conditions.json.
##
## MIGRATION. Every site becomes a world (its terrain, obstacles, elevation, and parked temperature) and every conditions set
## becomes a world (its wind, gust, temperature, humidity, z0, reference height) on a flat default field - so the count of
## worlds made equals sites + conditions sets, nothing merged, nothing dropped. Each migrated world keeps its source record
## verbatim under `legacy` (including unknown keys a newer build wrote), which is what makes the migration lossless and testable.
## The legacy files are never written, moved or deleted: they stay as the backup until the owner removes them.

const DEFAULT_DIR := "user://worlds"
const SUFFIX := ".world.json"

var dir := DEFAULT_DIR
var selected_id := ""
var _worlds: Dictionary = {}


static func load_dir(p_dir: String = DEFAULT_DIR) -> WorldLibrary:
	var lib := WorldLibrary.new()
	lib.dir = p_dir
	var d := DirAccess.open(p_dir)
	if d != null:
		var names: Array[String] = []
		for n in d.get_files():
			if n.ends_with(SUFFIX):
				names.append(n)
		names.sort()
		for n in names:
			var w := World.load_from("%s/%s" % [p_dir, n])
			if w != null:
				lib._worlds[w.world_id] = w
	if not lib._worlds.is_empty():
		lib.selected_id = String(lib._worlds.keys()[0])
	return lib


func path_for(id: String) -> String:
	return "%s/%s%s" % [dir, id, SUFFIX]


func ids() -> Array[String]:
	var out: Array[String] = []
	for k in _worlds:
		out.append(String(k))
	return out


func count() -> int:
	return _worlds.size()


func has(id: String) -> bool:
	return _worlds.has(id)


func world(id: String) -> World:
	return _worlds.get(id) as World


func selected() -> World:
	return world(selected_id)


func select(id: String) -> bool:
	if not _worlds.has(id):
		return false
	selected_id = id
	return true


## Adds (or replaces) a world and writes its file.
func put(w: World, write := true) -> bool:
	_worlds[w.world_id] = w
	if selected_id == "":
		selected_id = w.world_id
	return w.save(path_for(w.world_id)) if write else true


## Share: copy a world to any path. Import: read one from any path into this library (id kept; a clash gets a suffix).
func export_to(id: String, path: String) -> bool:
	var w := world(id)
	return w != null and w.save(path)


func import_from(path: String) -> World:
	var w := World.load_from(path)
	if w == null:
		return null
	var base := w.world_id
	var n := 2
	while _worlds.has(w.world_id):
		w.world_id = "%s_%d" % [base, n]
		n += 1
	put(w)
	return w


## Seeds the library with the shipped presets that are not already in it. Returns how many were added.
func ensure_presets() -> int:
	var added := 0
	for w in WorldPresets.all():
		if not _worlds.has(w.world_id):
			put(w)
			added += 1
	return added


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

## Reads the two legacy files and returns the worlds they become (does not write anything).
static func worlds_from_legacy(sites_path: String, conditions_path: String) -> Array[World]:
	var out: Array[World] = []
	var sdoc := JsonStore.read_document(sites_path)
	if not sdoc.is_empty() and sdoc.get("sites") is Array:
		for rec in (sdoc["sites"] as Array):
			if rec is Dictionary and String((rec as Dictionary).get("id", "")) != "":
				out.append(_from_site_record(rec))
	var cdoc := JsonStore.read_document(conditions_path)
	if not cdoc.is_empty() and cdoc.get("conditions") is Array:
		for rec in (cdoc["conditions"] as Array):
			if rec is Dictionary and String((rec as Dictionary).get("id", "")) != "":
				out.append(_from_conditions_record(rec))
	return out


## Migrates into `lib` once: worlds already present (by id) are left alone, so running it twice adds nothing. Returns the
## number of worlds added.
static func migrate(lib: WorldLibrary, sites_path: String = SiteLibrary.SAVE_PATH, conditions_path: String = ConditionsLibrary.SAVE_PATH) -> int:
	var added := 0
	for w in worlds_from_legacy(sites_path, conditions_path):
		if not lib.has(w.world_id):
			lib.put(w)
			added += 1
	return added


static func _from_site_record(rec: Dictionary) -> World:
	var site := Site.from_data(rec)
	var w := World.new()
	w.world_id = "site_%s" % site.site_id
	w.world_name = "Site: %s" % site.site_name
	w.description = "Migrated from sites.json"
	w.origin_elevation_m = site.elevation_m
	w.terrain = site.terrain
	w.obstacles = site.obstacles
	if site.parked_temperature_c is float or site.parked_temperature_c is int:
		w.temperature_c = float(site.parked_temperature_c)
	w.legacy = {"kind": "site", "record": rec.duplicate(true)}
	_label_migrated(w)
	return w


static func _from_conditions_record(rec: Dictionary) -> World:
	var c := Conditions.from_data(rec)
	var w := World.new()
	w.world_id = "conditions_%s" % c.conditions_id
	w.world_name = "Weather: %s" % c.conditions_name
	w.description = "Migrated from conditions.json"
	w.wind_speed_mps = c.wind_speed_mps
	w.wind_from_deg = c.wind_from_deg
	w.gustiness_mps = c.gustiness_mps
	w.gust_tau_s = c.gust_tau_s
	w.temperature_c = c.temperature_c
	w.humidity_pct = c.humidity_pct
	w.z0_m = c.roughness_z0_m
	w.wind_ref_height_m = c.wind_ref_height_m
	w.legacy = {"kind": "conditions", "record": rec.duplicate(true)}
	_label_migrated(w)
	return w


static func _label_migrated(w: World) -> void:
	var note := "typed by the builder in the old Field room (migrated)"
	for k in World.SOURCE_KEYS:
		w.set_source(k, "estimated", note)
	w.set_source("origin", "estimated", "no geographic position in the old files; lat/lon is a placeholder")


## The legacy record a migrated world was made from, rebuilt as the old object - used by the migration test to show nothing is lost.
func legacy_site_data(id: String) -> Dictionary:
	var w := world(id)
	return {} if w == null or String(w.legacy.get("kind", "")) != "site" else (w.legacy["record"] as Dictionary)
