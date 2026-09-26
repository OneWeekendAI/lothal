class_name AppSettings
extends RefCounted
## Global application preferences (e.g. UI scaling factor) saved in `user://app_settings.json`.
## Uses JsonStore so corrupted or missing settings fall back gracefully to defaults.

const SAVE_PATH := "user://app_settings.json"
const SCHEMA_VERSION := 1

const TOP_KEYS := ["schema", "ui_scale", "recent_projects", "lab_list_collapsed"]

## How many recent drones the menu remembers. A list long enough to scroll is a list nobody reads,
## and the ones past the eighth are found through Open… anyway.
const RECENT_LIMIT := 8

var ui_scale: float = 1.0
## Paths to recently opened containers, newest first.
##
## A LIST OF PATHS, NOT AN INDEX OF PROJECTS. It is allowed to be wrong — a path can point at a
## file the builder moved or deleted, and the menu simply does not offer it. That tolerance is why
## this is not the same mistake as a builds index: it never claims to be the set of drones that
## exist, only the set somebody opened.
var recent_projects: Array = []
## Whether the Lab's right-hand list is collapsed, per project id (lab dock design §2: "The state is
## saved per project"). Here rather than in the .lothal container because it is how this person
## likes to look at the drone, not a decision about the drone — a shared drone file must not
## carry it.
var lab_list_collapsed: Dictionary = {}
var _unknown: Dictionary = {}

static func load_from(path: String = SAVE_PATH) -> AppSettings:
	var settings := AppSettings.new()
	var doc := JsonStore.read_document(path)
	if doc.is_empty():
		return settings

	settings.ui_scale = float(doc.get("ui_scale", 1.0))
	settings.ui_scale = clampf(settings.ui_scale, 0.75, 2.5)

	var recent: Variant = doc.get("recent_projects", [])
	if recent is Array:
		for entry in (recent as Array):
			if entry is String:
				settings.recent_projects.append(String(entry))

	var collapsed: Variant = doc.get("lab_list_collapsed", {})
	if collapsed is Dictionary:
		for key in (collapsed as Dictionary):
			settings.lab_list_collapsed[str(key)] = bool((collapsed as Dictionary)[key])

	settings._unknown = JsonStore.unknown_fields(doc, TOP_KEYS)
	return settings


## Moves `path` to the front, without duplicating it. Called on every open and every new drone, so
## the ordering it produces is "most recently worked on", which is what the menu claims to show.
func remember_project(path: String) -> void:
	if path == "":
		return
	recent_projects.erase(path)
	recent_projects.push_front(path)
	while recent_projects.size() > RECENT_LIMIT:
		recent_projects.pop_back()


## Removes `path` from the recent list, for a drone Lothal itself just moved to the trash.
##
## The list is deliberately tolerant of paths that vanish OUTSIDE the app — a Finder move, a
## deleted folder — because there Lothal cannot know. An in-app delete DOES know, and knowing is
## different from tolerating: a path the app itself moved should not sit in the list until it
## scrolls off the limit, as if the drone still existed somewhere.
func forget_project(path: String) -> void:
	recent_projects.erase(path)


## The remembered paths that still exist. The menu asks for these rather than for the raw list,
## so a drone deleted in Finder disappears from the menu instead of offering an error.
func existing_recent_projects() -> Array:
	var out: Array = []
	for path in recent_projects:
		if FileAccess.file_exists(String(path)):
			out.append(String(path))
	return out

## Whether this project's Lab list was left collapsed. False for a project never seen.
func list_collapsed(project_id: String) -> bool:
	return bool(lab_list_collapsed.get(project_id, false))


func set_list_collapsed(project_id: String, collapsed: bool) -> void:
	if project_id == "":
		return
	lab_list_collapsed[project_id] = collapsed


func save(path: String = SAVE_PATH) -> bool:
	var doc: Dictionary = _unknown.duplicate()
	doc["schema"] = SCHEMA_VERSION
	doc["ui_scale"] = ui_scale
	doc["recent_projects"] = recent_projects.duplicate()
	doc["lab_list_collapsed"] = lab_list_collapsed.duplicate()
	return JsonStore.write_document(path, doc)
