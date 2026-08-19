class_name FrameLibrary
extends RefCounted
## The frames a builder has drawn — airframe.md §2's "custom frames stop being a second, thinner
## shape and become the same document with a different author".
##
## ## One shelf, two kinds of thing on it
##
## A preset is an `AirframeDocument` generated from a catalog entry; a drawn frame is an
## `AirframeDocument` somebody made. They are the same class, they answer the same questions, and
## the only differences are provenance: a preset has a vendor's published mass to be checked
## against, and a drawn frame has an author. So this library holds documents, and `entries()` lists
## both — the picker does not need to know which is which except to say so.
##
## That is a real simplification and not a cosmetic one. `custom_frames.gd` exists because a builder
## could previously only describe a frame with six numbers (name, mass, arm length, prop size, mount
## patterns), which is all the old model could hold. Everything downstream then had two code paths:
## one for a catalog frame and one for a thinner custom record. A drawn frame has an outline, so it
## has a real mass and a real inertia tensor, and the second path stops being needed.
##
## ## Files, not a database
##
## One JSON document per frame under `user://frames/`, written atomically through `JsonStore` —
## json_store.gd's third rule, and the same path `AirframeDocument.save_to` already uses. A frame is
## a thing a builder will want to send to somebody, and a directory of readable files is the format
## that makes that possible without an export feature.

const DIRECTORY := "user://frames"
const EXTENSION := ".frame.json"


## Where one frame lives. Derived from the document id rather than from its name, because a name is
## something a builder changes and a filename that follows it would orphan the old file on every
## rename.
static func path_for(document_id: String) -> String:
	return "%s/%s%s" % [DIRECTORY, _safe(document_id), EXTENSION]


## Every drawn frame on the shelf: `{id, name, author, path, plates, published_mass_g}`, sorted by
## name.
##
## Reads each file to get the name, which is a real cost and a deliberate one: the alternative is an
## index file beside the frames, and an index is a second source of truth that goes stale the moment
## anybody copies a frame in by hand. A builder with a hundred frames is not a case worth breaking
## that for.
static func entries() -> Array:
	var out: Array = []
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return out
	for file_name in directory.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var path := "%s/%s" % [DIRECTORY, file_name]
		var document := AirframeDocument.load_from(path)
		# A file that will not parse loads as an empty document (json_store.gd's first rule). It is
		# LISTED anyway, named by its filename, rather than vanishing: a frame somebody spent an
		# evening on that silently disappears from the list is worse than one that opens empty and
		# says so.
		out.append({
			"id": document.id if document.id != "" else file_name.trim_suffix(EXTENSION),
			"name": document.name if document.name != "" else file_name.trim_suffix(EXTENSION),
			"author": document.author,
			"plates": document.plates.size(),
			"published_mass_g": document.published_mass_g,
			"path": path,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Writes a frame, creating the directory on first use. Returns false rather than throwing, so a
## caller can tell the builder their frame is not saved instead of assuming it is.
static func save(document: AirframeDocument) -> bool:
	if document == null or document.id == "":
		return false
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
		if error != OK:
			return false
	return document.save_to(path_for(document.id))


static func load_frame(path: String) -> AirframeDocument:
	return AirframeDocument.load_from(path)


## A copy under a new id and name, for "duplicate this preset and make it mine" — which is how most
## frames will actually start, since editing a shape that already flies is easier than drawing one
## from nothing.
##
## THE VENDOR'S MASS DOES NOT COME WITH THE COPY. The moment a builder changes an outline, the
## published figure describes a different object, and a copy that kept it would show a mass gap
## against a frame that no longer exists. `published_mass_g` is a fact about a product, and a
## duplicate is not that product.
static func duplicate_of(source: AirframeDocument, new_name: String) -> AirframeDocument:
	var copy := AirframeDocument.from_dictionary(source.to_dictionary())
	copy.id = "frame_%d" % Time.get_ticks_usec()
	copy.name = new_name
	copy.author = ""
	copy.revision = "copied from %s" % source.name
	copy.published_mass_g = 0.0
	return copy


static func delete(document_id: String) -> bool:
	var path := path_for(document_id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## Filenames come from ids, and an id comes from a document that may have been written by hand or by
## an older version. Anything that is not a letter, a digit, a dash or an underscore becomes an
## underscore, so a frame called `../../etc/passwd` writes a file called `_______etc_passwd`.
static func _safe(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c == "-" or c == "_") else "_"
	return out if out != "" else "frame"
