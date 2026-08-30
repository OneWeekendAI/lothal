class_name BladeLibrary
extends RefCounted
## The blades a builder has drawn — the propulsion room's half of what `FrameLibrary` is for the
## airframe designer, slice P10d.
##
## ## One shelf, two kinds of thing on it
##
## A preset is a `PropellerDocument` generated from a catalog entry; a drawn blade is a
## `PropellerDocument` somebody edited. They are the same class and answer the same questions, and
## the only difference is provenance — a preset carries `published_mass_g` to be falsified against
## and `chord_is_assumed` to say its planform is a guess, and a drawn blade carries neither once
## the planform has been touched. So this library holds documents and `entries()` lists them.
##
## ## Files, not a database
##
## One JSON document per blade under `user://blades/`, through `PropellerDocument.save_to` — the
## same shape and the same reasoning `FrameLibrary` states: a blade is a thing a builder will want
## to send to somebody, and a directory of readable files makes that possible without an export
## feature. A file that will not parse is LISTED anyway, named by its filename, rather than
## vanishing.

const DIRECTORY := "user://blades"
const EXTENSION := ".blade.json"


## Where one blade lives. From the id rather than the name, on `FrameLibrary.path_for`'s reason: a
## filename that followed the name would orphan the old file on every rename.
static func path_for(document_id: String) -> String:
	return "%s/%s%s" % [DIRECTORY, _safe(document_id), EXTENSION]


## Every drawn blade: `{id, name, author, path, diameter_mm, blades, chord_is_assumed}`, by name.
static func entries() -> Array:
	var out: Array = []
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return out
	for file_name in directory.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var path := "%s/%s" % [DIRECTORY, file_name]
		var document := PropellerDocument.load_from(path)
		out.append({
			"id": document.id if document.id != "" else file_name.trim_suffix(EXTENSION),
			"name": document.name if document.name != "" else file_name.trim_suffix(EXTENSION),
			"author": document.author,
			"diameter_mm": document.diameter_mm,
			"blades": document.blades,
			"chord_is_assumed": document.chord_is_assumed,
			"path": path,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Writes a blade, creating the directory on first use. False rather than an exception, so a caller
## can tell the builder their blade is not saved instead of assuming it is.
static func save(document: PropellerDocument) -> bool:
	if document == null or document.id == "":
		return false
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK:
			return false
	return document.save_to(path_for(document.id))


static func load_blade(path: String) -> PropellerDocument:
	return PropellerDocument.load_from(path)


## A copy under a new id and name — how most blades will actually start, since editing a planform
## that already flies is easier than drawing one from nothing.
##
## **The vendor's mass does not come with the copy, and neither does the assumed-chord flag.** The
## first is `FrameLibrary.duplicate_of`'s own rule: `published_mass_g` is a fact about a product and
## a duplicate is not that product, so keeping it would show a mass gap against a blade that does
## not exist. The second is this room's: a copy a builder is about to draw on is a planform they are
## authoring, and carrying "chord assumed" into it would keep the caveat on figures that are no
## longer a guess. Both are cleared here rather than on the first edit, so the two never disagree.
static func duplicate_of(source: PropellerDocument, new_name: String) -> PropellerDocument:
	var copy := PropellerDocument.from_dictionary(source.to_dictionary())
	copy.id = "blade_%d" % Time.get_ticks_usec()
	copy.name = new_name
	copy.author = ""
	copy.revision = "copied from %s" % source.name
	copy.published_mass_g = 0.0
	copy.chord_is_assumed = false
	return copy


static func delete(document_id: String) -> bool:
	var path := path_for(document_id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## Anything that is not a letter, a digit, a dash or an underscore becomes an underscore, so a
## blade called `../../etc/passwd` writes a file called `_______etc_passwd`.
static func _safe(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c == "-" or c == "_") else "_"
	return out
