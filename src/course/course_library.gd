class_name CourseLibrary
extends RefCounted
## The courses a builder has laid out, and which one they are flying.
##
## Without this, the field editor would be a level editor with one level. A catalog that spans a
## 65 mm whoop and a 10" long-range needs more than one place to fly them: the default circuit is
## an 18 m ring of 1.5 m gates, which is a 5"-class track and is wrong for both ends of the range.
##
## ---------------------------------------------------------------------------
## THE FILE
## ---------------------------------------------------------------------------
##
## `user://courses.json`, alongside the assembly tweaks and the pack charge, and under the same
## four rules AssemblyTweaks sets out — because a format decided twice is a format that disagrees
## with itself. Two of the four are pure file handling and already live in JsonStore; the two that
## are about what a document MEANS are honoured here:
##
##     {
##       "schema": 2,
##       "selected": "default_circuit",
##       "courses": [
##         {"id": "default_circuit", "name": "Circuit", "site_id": "default_site",
##          "gates": [{"position": [18, 2.5, 0], "normal": [0, 0, 1], "radius": 1.5}, ...]}
##       ]
##     }
##
## - **Only what was authored is stored.** A fresh install has no file at all and gets the default
##   circuit from GateCourse.build_gates(), which is the same arithmetic that used to be the world.
##   WHERE a course is no longer lives here: v1 carried an `air` block, and v2 carries a `site_id`
##   pointing at `sites.json`, which is where the elevation, the ground and the obstacles are.
##   `SiteLibrary.migrate_courses` does that conversion once, one-way, and stamps the schema.
## - **Unknown fields are kept, not dropped** — at the top level (a later version's `weather`
##   block) and inside each course (a later version's `surface`). A gate's own unknown fields are
##   not preserved, and that is the one deliberate exception: gates are rewritten wholesale every
##   time the editor moves one, so there is no edit that could preserve them anyway.
## - **A bad file is not a fatal error.** Missing, truncated, invalid JSON, the wrong shape, a
##   course with no readable gates: every one of them lands on the default circuit and the app
##   opens. A workbench that will not start because a course file is half-written has made a
##   course more important than the product.
##
## ---------------------------------------------------------------------------
## WHO WRITES IT
## ---------------------------------------------------------------------------
##
## Lab, and only Lab (labs-and-sim.md §1, §4). The field editor is the writer; Sim loads this file
## and never touches it, exactly as it reads the assembly tweaks and never touches those. A gate's
## position is what the world IS, and what the world is gets authored in the garage.

const SAVE_PATH := "user://courses.json"
const SCHEMA_VERSION := 2

## Which course is flown when the door to the field is opened.
var selected_id := ""

## id -> GateCourse, in insertion order, which is the order the editor lists them in.
var _courses: Dictionary = {}
## Everything the file held that this version does not recognise. Top-level blocks and per-course
## fields go back to different places, so they are kept apart.
var _unknown_top: Dictionary = {}
var _unknown_course: Dictionary = {}


## A library with just the default circuit in it — what a fresh install has, and what every
## failure mode falls back to.
static func with_default() -> CourseLibrary:
	var library := CourseLibrary.new()
	library.put(GateCourse.new())
	library.selected_id = GateCourse.DEFAULT_ID
	return library


static func load_from(path: String = SAVE_PATH) -> CourseLibrary:
	# Every file-level failure — missing, unreadable, invalid JSON, JSON that is not an object —
	# comes back as an empty document from the one place that handles them.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return with_default()

	var library := CourseLibrary.new()
	library._unknown_top = JsonStore.unknown_fields(document, ["schema", "selected", "courses"])

	var stored: Variant = document.get("courses", [])
	if stored is Array:
		for entry in (stored as Array):
			if not (entry is Dictionary):
				continue
			var record: Dictionary = entry
			var id := String(record.get("id", ""))
			var gates := GateCourse.gates_from_data(record.get("gates"))
			# A course with no readable gates is dropped rather than kept as an empty field. An
			# empty course is one you cannot fly and cannot see, which would read as Lothal being
			# broken rather than as a damaged file.
			if id == "" or gates.is_empty():
				push_warning("%s: skipping a course with no readable gates" % path)
				continue
			var loaded := GateCourse.new(gates, id, String(record.get("name", id)))
			# Where this course IS. An absent id reads as the default field, which is the correct
			# reading of a v1 record rather than a fallback — though a v1 record should not reach
			# here at all, because `SiteLibrary.migrate_courses` runs first and writes one in.
			loaded.site_id = String(record.get("site_id", Site.DEFAULT_ID))
			library._courses[id] = loaded
			# `air` is in the KNOWN list although nothing reads it any more, and that is
			# deliberate: it is the v1 block, both of its numbers now live on the site, and letting
			# it fall through to the unknown half would preserve a second spelling of the site's
			# elevation for ever — free to drift the first time either was edited.
			library._unknown_course[id] = JsonStore.unknown_fields(
					record, ["id", "name", "gates", "air", "site_id"])

	if library._courses.is_empty():
		return with_default()

	library.selected_id = String(document.get("selected", ""))
	if not library._courses.has(library.selected_id):
		library.selected_id = String(library._courses.keys()[0])
	return library


func save(path: String = SAVE_PATH) -> bool:
	var courses: Array = []
	for id in _courses:
		var entry_course: GateCourse = _courses[id]
		var record: Dictionary = (_unknown_course.get(id, {}) as Dictionary).duplicate(true)
		record["id"] = entry_course.course_id
		record["name"] = entry_course.course_name
		record["gates"] = GateCourse.gates_to_data(entry_course.gates)
		record["site_id"] = entry_course.site_id
		courses.append(record)

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["selected"] = selected_id
	document["courses"] = courses
	return JsonStore.write_document(path, document)


# ---------------------------------------------------------------------------
# What is in it
# ---------------------------------------------------------------------------

func ids() -> Array[String]:
	var out: Array[String] = []
	for id in _courses:
		out.append(String(id))
	return out


func names() -> Array[String]:
	var out: Array[String] = []
	for id in _courses:
		out.append((_courses[id] as GateCourse).course_name)
	return out


func has(id: String) -> bool:
	return _courses.has(id)


func course(id: String) -> GateCourse:
	return _courses.get(id) as GateCourse


func selected() -> GateCourse:
	return course(selected_id)


## Chooses a course. Returns false — and changes nothing — for an id that is not here, rather than
## falling back to something arbitrary: an editor that silently selected a different course from
## the one asked for would be the same class of quiet wrongness as a stale best lap.
func select(id: String) -> bool:
	if not _courses.has(id):
		return false
	selected_id = id
	return true


## Adds a course, or replaces the one with the same id. Replacing in place is what the editor does
## on every gate move, and it is why the courses dictionary is keyed rather than a list — a list
## position means something different the moment a course is deleted.
func put(p_course: GateCourse) -> void:
	_courses[p_course.course_id] = p_course
	if selected_id == "":
		selected_id = p_course.course_id


## A new course, starting as a copy of the default circuit rather than as an empty field. An empty
## field has no start line, nothing to see and nothing to drag, so it is a worse place to begin
## editing from than a working circuit you can move gates on.
func create(p_name: String) -> GateCourse:
	var id := _unique_id(p_name)
	var new_course := GateCourse.new(GateCourse.build_gates(), id, p_name)
	put(new_course)
	return new_course


## Removes a course. The last one cannot be removed — there has to be somewhere to fly, and an
## empty library would mean Sim opening on nothing. Removing the SELECTED course moves the
## selection to whatever is left rather than leaving it pointing at a course that is gone.
func remove(id: String) -> bool:
	if not _courses.has(id) or _courses.size() <= 1:
		return false
	_courses.erase(id)
	_unknown_course.erase(id)
	if selected_id == id:
		selected_id = String(_courses.keys()[0])
	return true


## Renames without changing the id, so a rename cannot orphan a best lap or a saved selection.
func rename(id: String, p_name: String) -> bool:
	if not _courses.has(id):
		return false
	(_courses[id] as GateCourse).course_name = p_name
	return true


## A machine-readable id derived from the name, with a numeric suffix when that is already taken.
## Derived rather than random so a hand-edited file stays readable, and suffixed rather than
## overwriting so making two courses called "Test" gives you two courses.
func _unique_id(p_name: String) -> String:
	var base := ""
	for character in p_name.to_lower():
		base += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	base = base.strip_edges().lstrip("_").rstrip("_")
	if base == "":
		base = "course"
	if not _courses.has(base):
		return base
	var index := 2
	while _courses.has("%s_%d" % [base, index]):
		index += 1
	return "%s_%d" % [base, index]
