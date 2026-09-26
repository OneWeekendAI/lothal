class_name Project
extends RefCounted
## A saved drone: everything a builder DECIDED, and nothing Lothal can work out for itself.
##
## Not to be confused with Build, which is what you get when you hand one of these the catalog.
## Build is the computed aircraft — mass, thrust, hover throttle, a gyro, an integrator's worth of
## physics. Project is the short list of choices Build is computed FROM. Storing the two in one
## object is how a save file ends up carrying a hover-throttle percentage that disagrees with the
## app the day somebody measures a better thrust table.
##
##     project.to_build(catalog) -> Build
##
## That call is the entire coupling between this file and the physics. Nothing in src/assembly/
## or src/sim/ knows projects exist.
##
## ---------------------------------------------------------------------------
## WHAT IS STORED, AND THE ONE RULE THAT DECIDES IT
## ---------------------------------------------------------------------------
##
## - **A decision is stored.** Which motor; how far the pack is slid; a PID override; the
##   clearance to leave on a printed part.
## - **A derivation is not.** Mass, thrust-to-weight, hover throttle, warnings, the on-screen
##   mesh. All of it recomputes, and — this is the point — all of it gets BETTER when the catalog
##   does. A stored figure could only ever go stale or disagree.
## - **Something made physical is stored**, because it has stopped being a derivation. An STL that
##   has been printed is a record of an object that exists on a bench; regenerating it later does
##   not change the part in the builder's hand. That is `prints`, and src/print/ fills it in.
##
## ---------------------------------------------------------------------------
## THIS FILE IS EXPECTED TO CHANGE SHAPE, AND IS BUILT FOR IT
## ---------------------------------------------------------------------------
##
## Wiring, configuration, ground kit and printed parts all want a home in this document and none
## of them are designed yet. ProjectSchema holds the four rules that make adding, removing and
## re-meaning a field safe; the loader and saver below are written to obey them rather than to be
## short. In particular `_unknown` carries every unrecognised key at every level of nesting, so a
## project touched by a newer Lothal and saved by an older one comes back whole.
##
## The path is NOT stored in the file and NOT held here. A container knows where it lives;
## a document does not, which is what makes "save a copy" and "import" ordinary operations rather
## than special cases.

## Set once, never changed — not even by fitting a different pack. See ProjectSchema.new_id().
var project_id: String = ""
var name: String = "Untitled build"
var created_at: String = ""
var updated_at: String = ""
## Which Lothal wrote it, for diagnostics. NOTHING BRANCHES ON THIS. The catalog is deliberately
## not pinned: a project opened after a measured thrust table lands should get the truer number.
var lothal_version: String = ""
var notes: String = ""

## category -> part_id. Written dense (ProjectSchema rule 2): every known category appears, and ""
## means the builder said no. An ABSENT category is one the writer had never heard of.
var parts: Dictionary = {}
## Sparse. Absent means "whatever the frame implies", which is what lets a default follow a frame
## swap instead of freezing at the old frame's number.
var assembly: Dictionary = {}
## Sparse. Absent axes re-derive from the airframe.
var tune: Dictionary = {}
## Sparse. Absent means sea-level standard.
var air: Dictionary = {}
## Sparse. Absent means the app's defaults — including a fit clearance that is a labelled guess.
var printing: Dictionary = {}
## Sparse. The Config room's decisions — motor map, ports, failsafe, rates (C1). Absent means the
## app's defaults, which is what lets a default follow the app rather than freeze in the file.
var config: Dictionary = {}

## Named versions (⌘S), newest last. Each is {version_id, label, saved_at, decisions}.
var versions: Array = []
## What has been printed, and by which generator. See src/print/ and PrintRecord. Named
## `print_records` rather than `prints`, which GDScript reserves.
var print_records: Array = []

## Everything a loaded document contained that this version did not recognise, keyed by the block
## it came from ("" for the top level). Written back exactly where it was found.
var _unknown: Dictionary = {}
## What went wrong while loading, in the builder's language. Not warnings about the aircraft —
## those are Build's job and need the catalog. These are about the FILE.
var load_warnings: Array = []


## A new project with every required category empty. Deliberately not "the reference build": a
## caller that wants a starting point picks one, and a document that invented parts nobody chose
## would be the app deciding what somebody is building.
static func create(p_name: String = "Untitled build") -> Project:
	var project := Project.new()
	project.project_id = ProjectSchema.new_id()
	project.name = p_name
	project.created_at = _now_iso()
	project.updated_at = project.created_at
	project.lothal_version = _version_string()
	for category in ProjectSchema.all_categories():
		project.parts[category] = ""
	return project


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Reads a document into a Project, or returns null if it cannot be read at all.
##
## NULL IS RESERVED FOR ONE CASE: a file whose schema major is ahead of this Lothal. Everything
## else — a missing block, a block of the wrong type, a part id that is not a string — loads as
## much as it can and records a warning, because a builder whose file has one bad field should get
## their drone back with one field missing, not an error dialog.
##
## The exception is deliberate and is the opposite trade: a document written under a LATER major
## means at least one field's meaning has changed, and reading it with this version's meanings
## would silently describe a different aircraft. Refusing is the smaller cost.
static func from_dict(document: Dictionary, ladder: Array = ProjectSchema.MIGRATIONS) -> Project:
	var version := ProjectSchema.read_version(document.get("schema", null))
	if not ProjectSchema.can_read(version):
		return null

	var doc := ProjectSchema.migrate(document, version, ladder)
	var project := Project.new()
	project._unknown[""] = JsonStore.unknown_fields(doc, ProjectSchema.TOP_KEYS)

	project.project_id = _string_or(doc, "project_id", "")
	project.name = _string_or(doc, "name", "Untitled build")
	project.created_at = _string_or(doc, "created_at", "")
	project.updated_at = _string_or(doc, "updated_at", project.created_at)
	project.lothal_version = _string_or(doc, "lothal_version", "")
	project.notes = _string_or(doc, "notes", "")

	if project.project_id == "":
		project.project_id = ProjectSchema.new_id()
		project.load_warnings.append("this file had no project id; a new one was assigned")

	var decisions: Variant = doc.get("decisions", {})
	if not (decisions is Dictionary):
		project.load_warnings.append("the decisions block is unreadable; defaults were used")
		decisions = {}
	project._unknown["decisions"] = JsonStore.unknown_fields(
		decisions as Dictionary, ProjectSchema.DECISION_BLOCKS)

	project.parts = project._read_parts((decisions as Dictionary).get("parts", {}))
	project.assembly = project._read_block(decisions as Dictionary, "assembly")
	project.tune = project._read_block(decisions as Dictionary, "tune")
	project.air = project._read_block(decisions as Dictionary, "air")
	project.printing = project._read_block(decisions as Dictionary, "printing")
	project.config = project._read_block(decisions as Dictionary, "config")

	project.versions = _array_or(doc, "versions")
	project.print_records = _array_or(doc, "prints")
	return project


## The parts block, with every known category resolved and every unknown one KEPT.
##
## An unrecognised category is not dropped, and that is the "subtract a field" half of the format
## being editable: a category retired from this version is still in the file when a version that
## has it opens it again.
func _read_parts(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		if raw != null:
			load_warnings.append("the parts block is unreadable; nothing was fitted")
		for category in ProjectSchema.all_categories():
			out[category] = ""
		return out

	var block := raw as Dictionary
	_unknown["decisions.parts"] = JsonStore.unknown_fields(block, ProjectSchema.all_categories())

	for category in ProjectSchema.all_categories():
		var value: Variant = block.get(category, null)
		if value == null:
			# ABSENT, WHICH IS NOT "". The writer had never heard of this category, so nothing is
			# fitted for it — the alternative would silently add a part, and mass, to every
			# project a builder already owns the day a category is introduced.
			out[category] = ""
		elif value is String:
			out[category] = value
		else:
			out[category] = ""
			load_warnings.append("%s was not a part id; nothing was fitted for it" % category)
	return out


## One sparse block, with unrecognised keys kept. No key list is enforced: the keys inside
## `assembly`, `tune`, `air`, `printing` and `config` belong to AssemblyTweaks, RateTune, the print
## settings and the Config room respectively, and a whitelist here would be a fourth place to remember a field.
func _read_block(decisions: Dictionary, block_name: String) -> Dictionary:
	var raw: Variant = decisions.get(block_name, {})
	if not (raw is Dictionary):
		if raw != null:
			load_warnings.append("the %s block is unreadable; defaults were used" % block_name)
		return {}
	return (raw as Dictionary).duplicate(true)


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var decisions: Dictionary = (_unknown.get("decisions", {}) as Dictionary).duplicate(true)
	decisions["parts"] = _parts_out()
	decisions["assembly"] = assembly.duplicate(true)
	decisions["tune"] = tune.duplicate(true)
	decisions["air"] = air.duplicate(true)
	decisions["printing"] = printing.duplicate(true)
	decisions["config"] = config.duplicate(true)

	var out: Dictionary = (_unknown.get("", {}) as Dictionary).duplicate(true)
	out["schema"] = ProjectSchema.current_version()
	out["project_id"] = project_id
	out["name"] = name
	out["created_at"] = created_at
	out["updated_at"] = updated_at
	out["lothal_version"] = lothal_version
	out["decisions"] = decisions
	out["versions"] = versions.duplicate(true)
	out["prints"] = print_records.duplicate(true)
	out["notes"] = notes
	return out


## Dense, per ProjectSchema rule 2 — plus any category this version does not know, put back where
## it was found.
func _parts_out() -> Dictionary:
	var out: Dictionary = (_unknown.get("decisions.parts", {}) as Dictionary).duplicate(true)
	for category in ProjectSchema.all_categories():
		out[category] = String(parts.get(category, ""))
	return out


func touch() -> void:
	updated_at = _now_iso()
	lothal_version = _version_string()


# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------

## Snapshots the WHOLE decisions block under a label. Whole rather than a diff, and the reason is
## that a restore must never be able to produce a half-updated aircraft: restoring is one
## assignment, and a snapshot cannot be internally inconsistent.
##
## The name is not snapshotted. Restoring a version should not rename the project under the
## builder — they asked for yesterday's parts, not yesterday's title.
func add_version(label: String) -> Dictionary:
	var entry := {
		"version_id": ProjectSchema.new_id(),
		"label": label,
		"saved_at": _now_iso(),
		"decisions": (to_dict()["decisions"] as Dictionary).duplicate(true),
	}
	versions.append(entry)
	return entry


func restore_version(version_id: String) -> bool:
	for entry in versions:
		if String((entry as Dictionary).get("version_id", "")) != version_id:
			continue
		var decisions: Variant = (entry as Dictionary).get("decisions", {})
		if not (decisions is Dictionary):
			return false
		parts = _read_parts((decisions as Dictionary).get("parts", {}))
		assembly = _read_block(decisions as Dictionary, "assembly")
		tune = _read_block(decisions as Dictionary, "tune")
		air = _read_block(decisions as Dictionary, "air")
		printing = _read_block(decisions as Dictionary, "printing")
		config = _read_block(decisions as Dictionary, "config")
		touch()
		return true
	return false


# ---------------------------------------------------------------------------
# The bridge into physics
# ---------------------------------------------------------------------------

## The aircraft these decisions describe.
##
## Returns null when a REQUIRED category is empty or unknown to the catalog: an aircraft with no
## frame is not a build with something missing. `missing` is filled with the category names and
## the ids that failed, so the caller can say WHICH part went — "this build used
## motor_custom_ab12, which is no longer in your parts" — rather than silently fitting a default
## and quietly changing the drone's mass.
func to_build(catalog: PartsCatalog, missing: Array = []) -> Build:
	for category in ProjectSchema.REQUIRED_CATEGORIES:
		var part_id := String(parts.get(category, ""))
		if part_id == "" or catalog.get_part(part_id).is_empty():
			missing.append({"category": category, "part_id": part_id})

	var components: Dictionary = {}
	for category in ProjectSchema.OPTIONAL_CATEGORIES:
		var part_id := String(parts.get(category, ""))
		if part_id != "" and catalog.get_part(part_id).is_empty():
			missing.append({"category": category, "part_id": part_id})
			part_id = ""
		components[category] = part_id

	if not missing.is_empty():
		return null

	# The guard leaves the components dictionary and becomes the trailing argument, because
	# `Build.from_ids` reads `component_ids` for `Build.OPTIONAL_COMPONENTS` only and the guard is
	# not one of them — it is the optional part that also changes the aerodynamics, so it arrives
	# on its own parameter. Erased rather than left in place, so the two paths cannot both claim it.
	var guard_id := String(components.get("guard", ""))
	components.erase("guard")

	var build := Build.from_ids(catalog,
		String(parts["frame"]), String(parts["motor"]), String(parts["propeller"]),
		String(parts["battery"]), String(parts["esc"]), String(parts["flight_controller"]),
		components, to_air(), guard_id)
	# The configuration decisions travel with the aircraft (C2). Set rather than passed to
	# `from_ids`, because nothing in this block is a part and none of it moves a mass.
	if build != null:
		build.set_config(config.duplicate(true))
	return build


## Sea-level standard when the block is absent — Build's own default, so a project written before
## air existed means exactly what it meant.
func to_air() -> AirDensity:
	if air.is_empty():
		return AirDensity.standard()
	var elevation: Variant = air.get("elevation_m", AirDensity.STANDARD_ELEVATION_M)
	var temperature: Variant = air.get("temperature_c", AirDensity.STANDARD_TEMPERATURE_C)
	var e := float(elevation) if (elevation is float or elevation is int) else AirDensity.STANDARD_ELEVATION_M
	var t := float(temperature) if (temperature is float or temperature is int) else AirDensity.STANDARD_TEMPERATURE_C
	return AirDensity.new(e, t)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

static func _string_or(document: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = document.get(key, fallback)
	return value if value is String else fallback


static func _array_or(document: Dictionary, key: String) -> Array:
	var value: Variant = document.get(key, [])
	return (value as Array).duplicate(true) if value is Array else []


static func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


static func _version_string() -> String:
	return LothalVersion.CURRENT
