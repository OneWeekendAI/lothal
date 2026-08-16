class_name FlightLogLibrary
extends RefCounted
## The flights a builder has already flown (LTHL-54).
##
## ===========================================================================
## THIS LISTS HEADERS. IT NEVER OPENS A ROW.
## ===========================================================================
##
## The single most important property of this class, and the one every method below is shaped
## around. A three-minute log is roughly 197 MB and 180 000 rows. Twenty of them on disk is about
## 4 GB, and a library that read files to enumerate them would take tens of seconds to open a
## room — growing worse every time the builder flew.
##
## FlightRecorder.read_header() opens a file, reads ONE line and closes it. That is the whole cost
## of listing a log here: twenty flights is twenty lines, about 3 kB, and the room opens instantly.
## Nothing reads a row until something asks for one, which nothing in this slice does.
##
## ===========================================================================
## WHY THIS IS NOT CourseLibrary, DESPITE COPYING ITS API
## ===========================================================================
##
## CourseLibrary is the model for the shape — ids(), has(), remove(), an injectable path — and it
## is deliberately NOT the model for the storage. Courses are one JSON document read whole, and
## that works because the whole thing is a few kilobytes. Logs are FILES IN A DIRECTORY and the
## smallest of them is tens of megabytes, so this is a directory lister with a header cache.
##
## There is no save() and there is no writer. The recorder writes logs; this reads them and can
## delete one. A library with a save() would be a second thing that could author a log's contents,
## which is a race with the flight loop over a file that is 200 MB long.
##
## SELECTION IS NOT HERE, unlike CourseLibrary's. A selected course is persisted because it decides
## what you fly next time the app opens; a selected log is where a builder's eye happens to be, and
## persisting that would be inventing a preference nobody expressed. Studio holds it.
##
## ===========================================================================
## READING A LOG MUST NEVER RECONSTRUCT A BUILD
## ===========================================================================
##
## flight_recorder.gd's header states the rule and tests/test_flight_recorder.gd enforces it by
## reading source. THIS FILE IS NOW COVERED BY THAT SAME CHECK, and it had to be: before Studio the
## check guarded the only file that read logs, and a check that guards the wrong file goes on
## passing while the guarantee it describes quietly stops holding.
##
## So: headers out, plain Dictionaries, no route to Build.from_ids or PartsCatalog. A log NAMES an
## aircraft. Turning that name back into a flyable one would make this a second and much worse
## parts catalog — one written by a flight, drifting from the real one the day a part's mass is
## corrected.

## Where logs live, and the ONE place that decides it. src/scenes/main.gd writes here by reading
## this constant rather than declaring its own: a writer and a reader that each spell the
## directory out separately agree right up until one of them is edited.
const LOG_DIR := "user://logs"

## Only files this class will list. A builder's log directory is a plain folder they may well open
## in Finder, and a stray .txt or .DS_Store there should not become a row.
const EXTENSION := ".csv"

## The directory being listed. Injectable for the same reason CourseLibrary's save path is: a test
## that has to touch the real user:// directory is a test that can destroy a builder's flights.
var dir: String

## One entry per file, newest first. Each is {"id", "path", "header"}, where a header of {} means
## the file is there and unreadable — see _scan().
var _entries: Array[Dictionary] = []


static func load_from(p_dir: String = LOG_DIR) -> FlightLogLibrary:
	var library := FlightLogLibrary.new()
	library.dir = p_dir
	library.refresh()
	return library


## Re-reads the directory. Cheap by construction (one line per file), so callers re-scan rather
## than maintaining a cache that could disagree with the disk after a delete or a flight.
func refresh() -> void:
	_entries.clear()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return

	var names := DirAccess.get_files_at(dir)
	# NEWEST FIRST, by sorting the filenames backwards and nothing else. This works only because
	# LTHL-51 named logs flight-YYYYMMDD-HHMMSS.csv with zero padding, which makes chronological
	# order and lexical order the same order. No mtime is read: mtime is the time the file was
	# COPIED as often as it is the time the flight happened, and a builder restoring a backup
	# would find their whole history reordered by it.
	names.sort()
	names.reverse()

	for name in names:
		if not name.ends_with(EXTENSION):
			continue
		var path := "%s/%s" % [dir, name]
		# A header that will not parse gives {} rather than an error, per json_store.gd's rule
		# that a bad file is a warning and a defaulted result. The ENTRY IS STILL LISTED: a log
		# truncated by closing the laptop mid-write is exactly the file a builder wants to find
		# and delete, and a library that hid unreadable files would hide the only ones they need
		# to act on.
		_entries.append({
			"id": name,
			"path": path,
			"header": FlightRecorder.read_header(path),
		})


func count() -> int:
	return _entries.size()


## Filenames, newest first. These are the ids everything else here takes.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _entries:
		out.append(entry["id"])
	return out


func has(id: String) -> bool:
	return _index_of(id) >= 0


## The header block as the file states it, or {} for a log that cannot be read. A plain Dictionary
## and nothing else — see the class header.
func header(id: String) -> Dictionary:
	var index := _index_of(id)
	return {} if index < 0 else _entries[index]["header"]


func path_of(id: String) -> String:
	var index := _index_of(id)
	return "" if index < 0 else _entries[index]["path"]


## Whether a log's header could be read at all. A row for an unreadable file still appears in the
## list; this is what lets the screen say so rather than showing a row of blanks.
func is_readable(id: String) -> bool:
	return not header(id).is_empty()


## Deletes a log and drops it from the listing. The one destructive thing here, and the only write
## of any kind.
func remove(id: String) -> bool:
	var index := _index_of(id)
	if index < 0:
		return false
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(_entries[index]["path"]))
	if error != OK:
		push_warning("could not delete %s (error %d)" % [_entries[index]["path"], error])
		return false
	_entries.remove_at(index)
	return true


## ---------------------------------------------------------------------------
## What a list row says
## ---------------------------------------------------------------------------
##
## Three facts, because a builder scanning a list is answering "which one was that": when, how
## long, and which aircraft. Assembled here rather than in the screen so the list and any future
## reader of it agree, and so the assembly is testable without constructing a Control.
##
## THE WARNING IS PART OF THE ROW AND NOT ONLY OF THE DETAIL. discontinuities > 0 means the trace
## contains a respawn teleport, and a builder about to compute a spectrum over one should learn
## that BEFORE they pick the file rather than after. A warning that only appears once you have
## committed to a flight is a warning that arrives too late to change the decision it exists to
## inform.
func row(id: String) -> Dictionary:
	var head := header(id)
	if head.is_empty():
		return {
			"when": _when_from_id(id),
			"duration_s": 0.0,
			"aircraft": "unreadable",
			"warn": true,
			"readable": false,
		}

	var aircraft: Dictionary = head.get("aircraft", {})
	return {
		"when": _when_from_id(id),
		"duration_s": float(head.get("duration_s", 0.0)),
		"aircraft": short_fingerprint(str(aircraft.get("fingerprint", ""))),
		"warn": int(head.get("discontinuities", 0)) > 0,
		"readable": true,
	}


## The first three part ids of a six-part fingerprint — frame, motor, propeller.
##
## DISPLAY ONLY, and the distinction matters. Build.fingerprint() joins six ids and the whole
## string does not fit in a 292 px rail at any size a builder would want to read, so the list
## shows the three that tell two aircraft apart at a glance and the report pane shows all six.
## A truncated fingerprint that got treated as an IDENTITY anywhere would be a lossy second
## spelling of the thing the full fingerprint exists to be, which is the failure the whole
## "a log names an aircraft, it does not define one" rule is guarding.
static func short_fingerprint(fingerprint: String) -> String:
	var parts := fingerprint.split("/")
	if parts.size() <= 3:
		return fingerprint
	return "/".join([parts[0], parts[1], parts[2]]) + "/…"


## The flight's date and time, read from the FILENAME rather than the header.
##
## Deliberate, and the reason is that the header has no wall clock in it and must not gain one:
## tests/test_flight_recorder.gd asserts two identical flights produce byte-identical files, which
## a timestamp inside the header would break instantly. The filename is where wall time is allowed
## to live, which is precisely why LTHL-51 put it there.
##
## A name that does not match the pattern falls back to itself, so a log a builder renamed by hand
## still lists under the name they gave it.
static func _when_from_id(id: String) -> String:
	var stem := id.trim_suffix(EXTENSION)
	if not stem.begins_with("flight-") or stem.length() != 22:
		return stem
	var digits := stem.substr(7)
	return "%s-%s-%s  %s:%s" % [
		digits.substr(0, 4), digits.substr(4, 2), digits.substr(6, 2),
		digits.substr(9, 2), digits.substr(11, 2)]


func _index_of(id: String) -> int:
	for i in _entries.size():
		if _entries[i]["id"] == id:
			return i
	return -1
