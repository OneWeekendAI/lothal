class_name LapTimer
extends RefCounted
## Times laps of a GateCourse and remembers the best one **for that course** across sessions.
##
## The clock starts when the first gate is taken, not when the scene loads — otherwise
## every first lap of a session carries however long the pilot spent reading the build
## panel, and the best time becomes unbeatable-by-accident rather than earned.
##
## ---------------------------------------------------------------------------
## WHY A BEST LAP IS KEYED ON THE COURSE'S GEOMETRY
## ---------------------------------------------------------------------------
##
## This file used to keep ONE best lap in one file, which was correct for exactly as long as
## there was one course. The moment the field editor landed, that file was comparing times set
## on different tracks and reporting a record that meant nothing. It is the worst kind of bug —
## no error, no crash, just a number that quietly became a lie — and it is the same class of
## failure as a fit check measured against the pack's old mount position (labs-and-sim.md §2.6):
## a stale reading that still looks healthy.
##
## So best laps are stored per course, and the key is **the course's geometry, not its id and not
## its name.** GateCourse.fingerprint() hashes every gate's position, heading and radius, rounded
## to a millimetre.
##
## That choice answers the harder half of the question — what happens to a record when its course
## is EDITED — by making it not need answering. Move a gate and the fingerprint changes, so the
## record does not follow: the lap on screen is the best lap set on the track you are flying, and
## there is no code path in which it is anything else. An id-keyed record would have needed an
## explicit "the course changed, throw the record away" call at every mutation site, and the day
## somebody added a sixth way to move a gate and forgot it, the bug would come back silently.
##
## The consequence to state out loud, because it is a design decision rather than an accident:
## **records are not deleted when a course is edited — they are unreachable until the geometry
## comes back.** Nudge a gate 20 cm and the old best disappears; put it back and it returns. That
## is the honest reading. A time is a fact about a specific track, and the track you have just
## restored IS the track that time was set on. Deleting the record on edit would throw away a true
## fact to make the file tidier.
##
## Two smaller consequences, both deliberate:
##
## - The old `user://best_lap.json` is abandoned rather than migrated. Its single number cannot be
##   attributed to any course — it is a time set on whatever the file happened to hold — and
##   inventing an attribution for it would be manufacturing exactly the false record this change
##   exists to remove.
## - Rounding to a millimetre means a gate dragged by less than that is the same course. That is
##   the right side to err on: float coordinates round-trip through JSON, and a record that
##   vanished because a save-and-load moved a gate by 1e-16 m would be the stale-reading bug
##   inverted.

const SAVE_PATH := "user://best_laps.json"
const SCHEMA_VERSION := 1

var current_lap_s := 0.0
var last_lap_s := 0.0
var best_lap_s := 0.0     ## 0.0 means "no lap recorded on THIS course yet"
var running := false
var save_path: String
## The course this timer is timing, as GateCourse.fingerprint() returns it.
var course_key: String
## Every other course's record, held verbatim so writing this one back does not destroy them.
var _other_bests: Dictionary = {}
## Anything in the file this version did not recognise, kept for the next save — the same rule
## AssemblyTweaks sets out, now that this file has a schema worth keeping compatible.
var _unknown_top: Dictionary = {}

## Tests pass their own path; the game uses user://. Left injectable so the suite can
## never write over a real best time.
func _init(p_course_key: String, p_save_path: String = SAVE_PATH) -> void:
	course_key = p_course_key
	save_path = p_save_path
	load_best()

func tick(delta: float) -> void:
	if running:
		current_lap_s += delta

## Called when a gate is cleared. The first gate starts the clock; completing a lap
## records it and immediately starts the next one, so a flown circuit times continuously.
func on_gate_passed(completed_lap: bool) -> void:
	if not running:
		running = true
		current_lap_s = 0.0
		return

	if completed_lap:
		last_lap_s = current_lap_s
		if best_lap_s <= 0.0 or last_lap_s < best_lap_s:
			best_lap_s = last_lap_s
			save_best()
		current_lap_s = 0.0

## A crash voids the lap in progress. Timing through a reset would reward crashing into
## the ground as a shortcut, since the respawn skips whatever was between here and the
## last gate.
func invalidate_lap() -> void:
	running = false
	current_lap_s = 0.0

static func format(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	@warning_ignore("integer_division")
	var minutes := int(seconds) / 60
	var remainder := seconds - float(minutes * 60)
	return "%d:%05.2f" % [minutes, remainder]

## Reads the whole file, keeps every course's record, and takes this course's as the best to beat.
## A corrupt or hand-edited save must not take the game down with it — a missing best time is a
## cosmetic loss, and refusing to boot over it is not. Every failure mode lands in the same place,
## from the one place that handles them.
func load_best() -> void:
	var document := JsonStore.read_document(save_path)
	_unknown_top = JsonStore.unknown_fields(document, ["schema", "best_laps"])

	var stored: Variant = document.get("best_laps", {})
	if not (stored is Dictionary):
		return

	for key in (stored as Dictionary):
		var value: Variant = (stored as Dictionary)[key]
		if not (value is float or value is int):
			continue
		var seconds := maxf(float(value), 0.0)
		if seconds <= 0.0:
			continue
		if String(key) == course_key:
			best_lap_s = seconds
		else:
			_other_bests[String(key)] = seconds

func save_best() -> void:
	var bests := _other_bests.duplicate()
	if best_lap_s > 0.0:
		bests[course_key] = best_lap_s

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["best_laps"] = bests
	JsonStore.write_document(save_path, document)
