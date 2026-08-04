class_name AppSettings
extends RefCounted
## Global application preferences (e.g. UI scaling factor) saved in `user://app_settings.json`.
## Uses JsonStore so corrupted or missing settings fall back gracefully to defaults.

const SAVE_PATH := "user://app_settings.json"
const SCHEMA_VERSION := 1

const TOP_KEYS := ["schema", "ui_scale"]

var ui_scale: float = 1.0
var _unknown: Dictionary = {}

static func load_from(path: String = SAVE_PATH) -> AppSettings:
	var settings := AppSettings.new()
	var doc := JsonStore.read_document(path)
	if doc.is_empty():
		return settings

	settings.ui_scale = float(doc.get("ui_scale", 1.0))
	settings.ui_scale = clampf(settings.ui_scale, 0.75, 2.5)

	settings._unknown = JsonStore.unknown_fields(doc, TOP_KEYS)
	return settings

func save(path: String = SAVE_PATH) -> bool:
	var doc: Dictionary = _unknown.duplicate()
	doc["schema"] = SCHEMA_VERSION
	doc["ui_scale"] = ui_scale
	return JsonStore.write_document(path, doc)
