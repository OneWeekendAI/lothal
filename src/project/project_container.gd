class_name ProjectContainer
extends RefCounted
## The `.lothal` file: one thing a builder can find, move, back up and reopen, holding everything
## about one drone.
##
## Internally it is a zip, written with Godot's own ZIPPacker and read with ZIPReader. Three
## alternatives were considered and each fails something this needs. One JSON with base64 meshes
## inflates binary by a third and makes the document unreadable in a text editor. A folder the OS
## treats as a bundle is a bundle on macOS and a naked directory on Windows, and Lothal ships on
## both. A Godot `.res` is opaque to every tool that is not Godot — and a builder should be able to
## rename their drone to `.zip` and find their own STLs in it.
##
##     Weekend 5in.lothal
##       MANIFEST.json            what kind of container this is, and what wrote it
##       project.json             the decisions (Project)
##       parts/custom_parts.json  copies of the custom parts this drone uses
##       printed/…                what has actually been printed: one STL per export, each named by
##                                a print record in project.json (PrintedExport, printed-room PR4).
##       thumbnail.png            a cache. Deletable. Nothing writes it yet.
##
## ---------------------------------------------------------------------------
## THE CONTAINER DOES NOT UNDERSTAND THE DOCUMENT
## ---------------------------------------------------------------------------
##
## An earlier draft of the design put each named version in its own member, `versions/<id>.json`.
## That is corrected here and the correction is worth stating: **splitting the document across
## members makes the container a second author of the document's shape.** Every change to what a
## version is would then have to be made in Project and again here, and the two would drift.
##
## So the container stores members and does not interpret them. Versions stay inside
## `project.json`, where Project already round-trips them. The cost is that adding a version
## rewrites a few kilobytes; the benefit is that this file needs no opinion about what a version is.
##
## ---------------------------------------------------------------------------
## THE MANIFEST HOLDS NO INDEX, AND THAT IS DELIBERATE
## ---------------------------------------------------------------------------
##
## The same draft had `MANIFEST.json` carry a member index. A zip already has a central directory
## that lists every member exactly, so an index inside it is a second source of truth about a set
## the format itself describes — and it goes wrong the moment anybody adds a file with a zip tool.
## The manifest carries only what the archive genuinely cannot say about itself: which kind of
## container this is, and which Lothal wrote it.
##
## ---------------------------------------------------------------------------
## WHAT AUTOSAVE ACTUALLY COSTS, HONESTLY
## ---------------------------------------------------------------------------
##
## The design said autosave would rewrite `project.json` and copy the meshes through untouched.
## **ZIPPacker cannot do that**, and pretending otherwise would have been a performance claim with
## no code behind it: there is no raw-copy of an already-compressed member, so every save rebuilds
## the archive and recompresses everything in it. `APPEND_ADDINZIP` exists and is not the answer —
## it appends a second member under the same name and leaves which one wins to the reader.
##
## Three things make that acceptable today and none of them is an optimisation that does not exist:
##
## - `has_unsaved_changes()` is checked first, so an idle app writes nothing at all.
## - There are no meshes yet. A project is a few kilobytes.
## - When there are meshes, this is the place to measure — and the answer may be that autosave
##   writes the document and printing writes the archive. That is a decision to take with a
##   number in hand, and it is open question 5 in the design.

const EXTENSION := "lothal"
const MANIFEST_MEMBER := "MANIFEST.json"
const PROJECT_MEMBER := "project.json"
const CUSTOM_PARTS_MEMBER := "parts/custom_parts.json"

## Bumped when the LAYOUT changes — a member renamed or given a new meaning. Separate from
## ProjectSchema's version, which is about the document inside: a container whose layout this
## version cannot read is a different problem from a document whose fields have changed meaning,
## and conflating them would make one refusal impossible to explain.
const CONTAINER_MAJOR := 1
const CONTAINER_MINOR := 0

## The members this class writes itself. Everything else found in an opened container is carried
## through untouched — the same rule ProjectSchema applies to unknown FIELDS, applied to files.
const AUTHORED_MEMBERS := [MANIFEST_MEMBER, PROJECT_MEMBER, CUSTOM_PARTS_MEMBER]

var project: Project
## Where this container was opened from, or last written to. A document does not know its own
## path; a container is the thing that does.
var path: String = ""
## What was wrong with the file, in a builder's words. Empty for a clean open.
var load_warnings: Array = []

## Every member not in AUTHORED_MEMBERS, held as bytes so it can be written straight back out.
var _members: Dictionary = {}
## The custom-part records that travelled with this container, as the raw document shape.
var _custom_parts: Dictionary = {}
## What was last written, so an unchanged project writes nothing.
var _written_document: String = ""


static func make(p_project: Project) -> ProjectContainer:
	var container := ProjectContainer.new()
	container.project = p_project
	return container


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

## Whether writing would change anything. Cheap enough to call on every autosave tick, which is
## the point — the cost of an idle app is one JSON stringify, not one archive.
func has_unsaved_changes() -> bool:
	return JSON.stringify(project.to_dict()) != _written_document


## Writes the container to `to_path`, atomically.
##
## Beside, then rename — the same rule and the same reasoning as JsonStore.write_document_atomic,
## and more load-bearing here: a half-written zip is not a document with a bad field, it is a file
## no reader can open at all. A kill mid-write leaves the previous container whole.
func write(to_path: String = "", custom_parts_path: String = CustomParts.SAVE_PATH) -> bool:
	var target := to_path if to_path != "" else path
	if target == "":
		push_warning("a container cannot be written without a path")
		return false

	project.touch()
	var document := project.to_dict()
	_custom_parts = _collect_custom_parts(custom_parts_path)

	var temp := target + ".tmp"
	var packer := ZIPPacker.new()
	if packer.open(temp, ZIPPacker.APPEND_CREATE) != OK:
		push_warning("could not write %s" % temp)
		return false
	packer.set_compression_level(ZIPPacker.COMPRESSION_DEFAULT)

	var ok := _write_member(packer, MANIFEST_MEMBER, _manifest_bytes())
	ok = _write_member(packer, PROJECT_MEMBER, _json_bytes(document)) and ok
	if not _custom_parts.is_empty():
		ok = _write_member(packer, CUSTOM_PARTS_MEMBER, _json_bytes(_custom_parts)) and ok
	# Everything a later Lothal put in here, put back. A wiring diagram or a print this version
	# knows nothing about must survive this version saving the file.
	for member in _members:
		ok = _write_member(packer, str(member), _members[member]) and ok
	packer.close()

	if not ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false

	var directory := DirAccess.open(target.get_base_dir())
	if directory == null:
		push_warning("could not open %s to rename into" % target.get_base_dir())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	if directory.rename(temp.get_file(), target.get_file()) != OK:
		push_warning("could not replace %s" % target)
		directory.remove(temp.get_file())
		return false

	path = target
	_written_document = JSON.stringify(document)
	return true


static func _write_member(packer: ZIPPacker, member: String, data: PackedByteArray) -> bool:
	if packer.start_file(member) != OK:
		push_warning("could not start %s in the container" % member)
		return false
	var wrote := packer.write_file(data)
	packer.close_file()
	if wrote != OK:
		push_warning("could not write %s into the container" % member)
		return false
	return true


func _manifest_bytes() -> PackedByteArray:
	return _json_bytes({
		"container": {"major": CONTAINER_MAJOR, "minor": CONTAINER_MINOR},
		"written_by": LothalVersion.CURRENT,
	})


static func _json_bytes(document: Dictionary) -> PackedByteArray:
	return JSON.stringify(document, "  ").to_utf8_buffer()


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Opens a container, or returns null if it cannot be opened at all.
##
## Null covers exactly two cases — the file is not a readable zip, or its document is unreadable —
## and both are reported by the caller as "this project would not open", with every other project
## in the folder unaffected. A container is never rewritten or repaired on open: a file that
## puzzled Lothal is a file a builder may still be able to rescue by hand, and rewriting it is the
## one action that makes that impossible.
static func open(from_path: String) -> ProjectContainer:
	var reader := ZIPReader.new()
	if reader.open(from_path) != OK:
		push_warning("%s is not a readable Lothal container" % from_path)
		return null

	var container := ProjectContainer.new()
	container.path = from_path

	for member in reader.get_files():
		var name := String(member)
		if name.ends_with("/"):
			continue
		if AUTHORED_MEMBERS.has(name):
			continue
		container._members[name] = reader.read_file(name)

	var manifest := _read_json(reader, MANIFEST_MEMBER)
	var container_major := int((manifest.get("container", {}) as Dictionary).get(
		"major", CONTAINER_MAJOR))
	if container_major > CONTAINER_MAJOR:
		reader.close()
		push_warning("%s was written by a later Lothal (container %d)" % [
			from_path, container_major])
		return null

	var document := _read_json(reader, PROJECT_MEMBER)
	if document.is_empty():
		reader.close()
		push_warning("%s has no readable project in it" % from_path)
		return null

	container.project = Project.from_dict(document)
	if container.project == null:
		reader.close()
		# The document's own major is ahead — a field has changed meaning, and reading it with this
		# version's meanings would describe a different aircraft. See ProjectSchema.
		push_warning("%s was written by a later Lothal (document schema)" % from_path)
		return null

	container._custom_parts = _read_json(reader, CUSTOM_PARTS_MEMBER)
	container.load_warnings = container.project.load_warnings.duplicate()
	container._written_document = JSON.stringify(container.project.to_dict())
	reader.close()
	return container


## The drone's NAME, without opening the drone.
##
## The recent list needs one string per file and nothing else. `open()` reads every member, parses
## the document, resolves the schema and copies the custom parts — all of it thrown away to print
## a label, and multiplied by eight entries every time the menu is built.
##
## The name is also the only honest label there is: the file is named after the project id, because
## a drone may be called "5 inch" or carry a slash. So a recent list built from filenames shows
## `01m0ajmppre0j35fytky0gtczr`, which is a list nobody can read — and it is what the menu showed
## until this existed.
##
## Falls back to the file's stem rather than to an empty string. A container that will not open is
## still a file the builder can point at, and a blank row would be the one entry they cannot even
## describe when asking what happened to it.
static func read_name(from_path: String) -> String:
	var fallback := from_path.get_file().get_basename()
	var reader := ZIPReader.new()
	if reader.open(from_path) != OK:
		return fallback
	var document := _read_json(reader, PROJECT_MEMBER)
	reader.close()
	var found := str(document.get("name", ""))
	return found if found != "" else fallback


static func _read_json(reader: ZIPReader, member: String) -> Dictionary:
	if not reader.file_exists(member):
		return {}
	var parser := JSON.new()
	if parser.parse(reader.read_file(member).get_string_from_utf8()) != OK:
		push_warning("%s in the container is not valid JSON" % member)
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# Custom parts travel with the drone
# ---------------------------------------------------------------------------

## One carried-through member's bytes — a `printed/…` STL, say — or empty when there is none.
##
## The container still does not interpret it: PrintedExport decides what a printed member is, and the
## print record in the document says which one it is. This only stores bytes by name.
func member_bytes(name: String) -> PackedByteArray:
	return _members.get(name, PackedByteArray())


## Adds or replaces a member this class does not author; it is written on the next `write`. Refuses
## the three authored names, which this class rebuilds from the document on every write.
func set_member_bytes(name: String, data: PackedByteArray) -> void:
	if AUTHORED_MEMBERS.has(name):
		push_warning("%s is written by the container itself" % name)
		return
	_members[name] = data


## The custom-part records this container carries, in `custom_parts.json`'s own shape.
func custom_parts() -> Dictionary:
	return _custom_parts.duplicate(true)


## Which of the builder's custom parts this drone actually uses — as records, copied into the file.
##
## A container handed to another machine has to describe its own aircraft. Without this, opening a
## shared file would find a part id in nobody's catalog and the drone would be missing a motor.
##
## The copy is TRANSITIVE, and that is not a detail. A custom motor's thrust table may cite a
## custom PROPELLER by id — PartsCatalog.load_with_custom loads props first for exactly this
## reason — so copying only what is fitted would produce a file whose motor refuses to load on
## arrival, with a message about a propeller the builder never chose. The closure below follows
## every id a copied record mentions, wherever it appears in the record.
##
## Nothing here knows what a category is. It walks the document's sibling arrays, so a custom
## category added later travels without this function being touched.
func _collect_custom_parts(custom_parts_path: String) -> Dictionary:
	var stored := JsonStore.read_document(custom_parts_path)
	if stored.is_empty():
		return {}

	var by_id: Dictionary = {}
	for key in stored:
		if not (stored[key] is Array):
			continue
		for record in (stored[key] as Array):
			if record is Dictionary and (record as Dictionary).has("part_id"):
				by_id[String((record as Dictionary)["part_id"])] = {"key": key, "record": record}

	var wanted: Dictionary = {}
	var frontier: Array = []
	for category in project.parts:
		var part_id := String(project.parts[category])
		if by_id.has(part_id):
			frontier.append(part_id)

	while not frontier.is_empty():
		var part_id: String = frontier.pop_back()
		if wanted.has(part_id):
			continue
		wanted[part_id] = true
		var record: Dictionary = (by_id[part_id] as Dictionary)["record"]
		for referenced in _ids_mentioned_by(record, by_id):
			if not wanted.has(referenced):
				frontier.append(referenced)

	var out: Dictionary = {}
	for part_id in wanted:
		var entry: Dictionary = by_id[part_id]
		var key := String(entry["key"])
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(entry["record"])
	if not out.is_empty():
		out["schema"] = CustomParts.SCHEMA_VERSION
	return out


## Every custom part id this record mentions, at any depth. A string that happens to equal a
## custom part id IS a reference — there is no field list here on purpose, because a field list
## would be a fourth place to remember that `thrust_test.prop_id` exists.
static func _ids_mentioned_by(value: Variant, by_id: Dictionary) -> Array:
	var out: Array = []
	if value is String:
		if by_id.has(value):
			out.append(String(value))
	elif value is Dictionary:
		for key in (value as Dictionary):
			out.append_array(_ids_mentioned_by((value as Dictionary)[key], by_id))
	elif value is Array:
		for item in (value as Array):
			out.append_array(_ids_mentioned_by(item, by_id))
	return out
