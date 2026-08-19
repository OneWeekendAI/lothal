class_name JsonStore
extends RefCounted
## Reading and writing the small JSON documents Lothal keeps in `user://` — the builder's assembly
## tweaks, and how much charge is left in each pack.
##
## Factored out when the second one arrived, rather than copied. The four rules AssemblyTweaks set
## out are the reason: they are easy to state, easy to lose, and two independent copies of them
## would drift apart the first time somebody fixed a bug in one. Two of the four are pure file
## handling and live here; the other two are about what a document MEANS and stay with each
## document, because only the document knows which of its fields it recognises.
##
## Here:
##
## - **A bad file is not a fatal error.** Missing, truncated, invalid JSON, or valid JSON of the
##   wrong shape: every one of them reads as an empty document, and the caller falls back to
##   defaults. Lab opens. A workbench that will not start because a preferences file is
##   half-written has made a preference more important than the product.
## - **A tolerated condition must not LOOK like a failure.** Parsing goes through JSON.new().parse
##   rather than JSON.parse_string, because the latter prints an engine-level ERROR line for a
##   malformed document — which in the test runner's output is indistinguishable from a failing
##   test. The condition is reported as a warning, which is what it is.
##
## With each document, because they need to know its schema:
##
## - **Only what was SET is stored.** An absent key means "whatever the defaults imply", not zero.
## - **Unknown fields are kept, not dropped.** A file written by a later version of Lothal will
##   hold fields this one has never heard of. They are read back out untouched on save, so opening
##   an older build does not silently destroy a newer one's settings.

## Reads a JSON object from `path`. Returns an empty Dictionary for every failure mode there is,
## which is what makes "a bad file loads as defaults" one code path rather than five.
static func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("%s is not valid JSON (line %d: %s); using defaults" % [
			path, reader.get_error_line(), reader.get_error_message()])
		return {}

	var parsed: Variant = reader.data
	if not (parsed is Dictionary):
		push_warning("%s is not a JSON object; using defaults" % path)
		return {}

	return parsed


## Writes `document` to `path`, pretty-printed so the file stays reviewable and hand-editable.
## Returns false if it could not be opened — a caller may report that, but nothing in Lab depends
## on it, since an unsaveable preference is a lost preference and not a broken workbench.
static func write_document(path: String, document: Dictionary) -> bool:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		push_warning("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	handle.store_string(JSON.stringify(document, "  "))
	handle.close()
	return true


## Writes `document` to `path` so that a process killed mid-write leaves the PREVIOUS file
## intact, rather than a truncated one.
##
## `write_document` above overwrites in place, which is fine for a preference — the cost of losing
## a slider position to a crash is a slider position. It is not fine for a drone. A project is
## rewritten on every autosave, so the window in which a kill would truncate it is open more or
## less permanently, and what is in it is hours of somebody's design.
##
## Write beside, then rename. A rename over an existing file is atomic on both platforms Lothal
## ships on, so at no instant does `path` hold half a document: it holds the old one, then the new
## one. The temporary is removed on a failed write so a dead `.tmp` cannot accumulate next to a
## builder's files or be mistaken for a recovery copy.
static func write_document_atomic(path: String, document: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	if not write_document(temp_path, document):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false

	var directory := DirAccess.open(path.get_base_dir())
	if directory == null:
		push_warning("could not open %s to rename into (error %d)" % [
			path.get_base_dir(), DirAccess.get_open_error()])
		return false

	var renamed := directory.rename(temp_path.get_file(), path.get_file())
	if renamed != OK:
		push_warning("could not replace %s (error %d)" % [path, renamed])
		directory.remove(temp_path.get_file())
		return false
	return true


## Splits a loaded document's keys into the ones a version recognises and the ones it does not,
## so the unrecognised half can be written straight back out. Returns only the unknown half —
## the known half is the caller's business and it reads those keys itself.
static func unknown_fields(document: Dictionary, known_keys: Array) -> Dictionary:
	var out: Dictionary = {}
	for key in document:
		if not known_keys.has(key):
			out[key] = document[key]
	return out
