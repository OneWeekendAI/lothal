class_name ProjectRows
extends RefCounted
## The drones on disk as rows (M14): what the Open dialog's Projects section and the Projects home screen both list.
## One reader, so the two cannot disagree about a drone's name, weight or age.

const SORT_EDITED := 0
const SORT_NAME := 1


## Every drone in the builds folder (not the trash), as `[{path, name, updated_unix, size, dry_g, auw_g}]`.
## `catalog` null skips the weight figures (the Open dialog wants names and ages only, and is opened often). A file that will not open is left out rather than shown as a row that cannot be opened.
static func list(catalog: PartsCatalog) -> Array:
	ProjectLibrary.ensure_dir()
	var out: Array = []
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.root)
	for file in DirAccess.get_files_at(absolute):
		if not file.ends_with(".%s" % ProjectContainer.EXTENSION):
			continue
		var path := "%s/%s" % [ProjectLibrary.root, file]
		var opened := ProjectContainer.open(path)
		if opened == null:
			continue
		var project := opened.project
		var entry := {
			"path": path,
			"name": project.name,
			"updated_unix": unix_of(project.updated_at),
			"size": "—", "dry_g": -1.0, "auw_g": -1.0,
		}
		var build: Build = project.to_build(catalog) if catalog != null else null
		if build != null:
			entry["auw_g"] = build.all_up_weight_g()
			entry["dry_g"] = build.all_up_weight_g() - float(build.battery.get("mass_g", 0.0))
			var specs: Dictionary = build.propeller.get("specs", {})
			if specs.has("diameter_inches"):
				entry["size"] = "%s\"" % trim(float(specs["diameter_inches"]))
		out.append(entry)
	return out


## `entries` ordered by `mode` (SORT_EDITED: newest first; SORT_NAME: natural, case-blind). A new array.
static func sorted(entries: Array, mode: int) -> Array:
	var out := entries.duplicate()
	if mode == SORT_NAME:
		out.sort_custom(func(a, b) -> bool: return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	else:
		out.sort_custom(func(a, b) -> bool: return int(a["updated_unix"]) > int(b["updated_unix"]))
	return out


static func trim(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


static func unix_of(iso: String) -> int:
	if iso == "":
		return 0
	return int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))
