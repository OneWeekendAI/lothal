class_name DesignFile
extends RefCounted
## Save and load of a Design Space drone (PLAN Section 9, the logic half). No Node, no drawing.
##
## A design file is versioned JSON: the class, the part id of every category ("" = taken off), and
## the frame document as edited (when the class has one). Undo history is NOT saved. The shelf is
## not stored either: it is the catalog minus what is fitted, so the selection already carries it.
##
## Floats are written at full precision, so a reload is bit for bit. A load never crashes: it returns
## {ok: false, reason} with one line for a missing/unknown part, an unknown category, a malformed
## frame document, a newer version, or a file that is not a design at all.
##
## The authored harness ("harness"), the assembly tweaks ("assembly") and the Config decisions ("config"), the printing decisions and print records ("printing", "print_records") ride in the file when they are
## not the as-built defaults; a file without them opens as built. Not covered yet: a project that flies a
## drawn `Project.airframe`.

const FORMAT := "lothal-design"
const VERSION := 1
const EXTENSION := "lothaldesign"
## Where designs live by default. Tests point this at a scratch folder.
static var dir := "user://designs"


## The file's content for `session`.
static func to_dict(session: DesignSession, design_name: String = "") -> Dictionary:
	var out := {"format": FORMAT, "version": VERSION, "name": design_name,
		"class": session.drone_class, "parts": session.selection.duplicate(true)}
	var doc := session.frame_document()
	if doc != null:
		out["frame_document"] = doc.to_dictionary()
	if not session.harness_overrides.is_empty():
		out["harness"] = session.harness_overrides.duplicate(true)
	if not session.config().is_empty():
		out["config"] = session.config()
	if not session.printing().is_empty():
		out["printing"] = session.printing()
	if not session.print_records().is_empty():
		out["print_records"] = session.print_records()
	if not session.tweaks.is_default():
		out["assembly"] = session.tweaks.to_dict()
	return out


## Writes the design to `path` (default: dir/<name>.lothaldesign), atomically. {ok, reason, path}.
static func save(session: DesignSession, design_name: String, path: String = "") -> Dictionary:
	if path == "":
		path = path_for(design_name)
	if not DirAccess.dir_exists_absolute(path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := JSON.stringify(to_dict(session, design_name), "  ", true, true)
	var temp := path + ".tmp"
	var handle := FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		return _no("Could not write %s." % path.get_file())
	handle.store_string(text)
	handle.close()
	var d := DirAccess.open(path.get_base_dir())
	if d == null or d.rename(temp.get_file(), path.get_file()) != OK:
		if d != null:
			d.remove(temp.get_file())
		return _no("Could not replace %s." % path.get_file())
	return {"ok": true, "reason": "", "path": path}


static func path_for(design_name: String) -> String:
	var safe := design_name.strip_edges().validate_filename()
	if safe == "":
		safe = "design"
	return "%s/%s.%s" % [dir, safe, EXTENSION]


## Design file names in `dir`, sorted.
static func list() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension() == EXTENSION:
			out.append(f)
	out.sort()
	return out


## {ok, reason, session, name}. On refusal `session` is null.
static func load_file(path: String, catalog: PartsCatalog) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _no("%s does not exist." % path.get_file())
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return _no("%s is not a readable design file." % path.get_file())
	if not (parser.data is Dictionary):
		return _no("%s is not a design file." % path.get_file())
	return from_dict(parser.data, catalog)


static func from_dict(d: Dictionary, catalog: PartsCatalog) -> Dictionary:
	if d.get("format", null) != FORMAT:
		return _no("This is not a Lothal design file.")
	var v: Variant = d.get("version", null)
	if not (v is float or v is int) or float(v) != floorf(float(v)) or int(v) < 1:
		return _no("The design file has no usable version.")
	if int(v) > VERSION:
		return _no("This design was saved by a newer Lothal (version %d); this one reads up to %d." % [int(v), VERSION])
	var cls: Variant = d.get("class", null)
	if not (cls is String) or not DroneClass.is_available(cls):
		return _no("Unknown drone class \"%s\"." % str(cls))
	var parts: Variant = d.get("parts", null)
	if not (parts is Dictionary):
		return _no("The design lists no parts.")
	var categories := ProjectSchema.all_categories()
	for key in parts:
		if not categories.has(key):
			return _no("Unknown part category \"%s\"." % str(key))
	var selection := {}
	for category in categories:
		if not parts.has(category):
			return _no("The design does not say what %s is fitted." % category)
		var id: Variant = parts[category]
		if not (id is String):
			return _no("The %s entry is not a part id." % category)
		if id != "" and not _in_category(catalog, category, id):
			return _no("Unknown %s part \"%s\"." % [category, id])
		selection[category] = id
	var session := DesignSession.default_for_class(cls)
	if session == null:
		return _no("Could not open a %s drone." % cls)
	var frame: Variant = d.get("frame_document", null)
	var fd: Dictionary = {}
	if session.frame_document() != null:
		if not (frame is Dictionary):
			return _no("The design has no frame document.")
		var why := _frame_problem(frame, session.frame_document())
		if why != "":
			return _no(why)
		fd = frame
	elif frame != null:
		return _no("This class has no editable frame, but the design carries one.")
	var harness: Variant = d.get("harness", {})
	var assembly: Variant = d.get("assembly", {})
	var config: Variant = d.get("config", {})
	session.restore_state(selection, fd, harness if harness is Dictionary else {}, assembly if assembly is Dictionary else {},
		config if config is Dictionary else {},
		(d.get("printing", {}) as Dictionary) if d.get("printing", {}) is Dictionary else {},
		(d.get("print_records", []) as Array) if d.get("print_records", []) is Array else [])
	return {"ok": true, "reason": "", "session": session, "name": str(d.get("name", ""))}


static func _in_category(catalog: PartsCatalog, category: String, id: String) -> bool:
	for p in catalog.list_category(category):
		if p is Dictionary and String(p.get("part_id", "")) == id:
			return true
	return false


## One line on what is wrong with a saved frame document, "" when it is the drawn frame's own kind.
static func _frame_problem(saved: Dictionary, drawn: AirframeDocument) -> String:
	if str(saved.get("id", "")) != drawn.id:
		return "The frame document is for a different frame (\"%s\")." % str(saved.get("id", ""))
	var plates: Variant = saved.get("plates", null)
	if not (plates is Array) or (plates as Array).size() != drawn.plates.size():
		return "The frame document has the wrong plates."
	for p in plates:
		if not (p is Dictionary) or not (p as Dictionary).has("outline") or not ((p as Dictionary)["outline"] is Array):
			return "The frame document has a malformed plate."
		var holes: Variant = (p as Dictionary).get("holes", [])
		if not (holes is Array):
			return "The frame document has malformed holes."
	return ""


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "session": null, "name": ""}
