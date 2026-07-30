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


## Splits a loaded document's keys into the ones a version recognises and the ones it does not,
## so the unrecognised half can be written straight back out. Returns only the unknown half —
## the known half is the caller's business and it reads those keys itself.
static func unknown_fields(document: Dictionary, known_keys: Array) -> Dictionary:
	var out: Dictionary = {}
	for key in document:
		if not known_keys.has(key):
			out[key] = document[key]
	return out
