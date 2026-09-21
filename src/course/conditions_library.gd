class_name ConditionsLibrary
extends RefCounted
## The named weathers a builder has, and which one they are flying in.
##
## `user://conditions.json`, alongside the courses, the sites and the assembly tweaks, under the
## same four rules `AssemblyTweaks` set out and `SiteLibrary`'s header restates — because a format
## decided twice is a format that disagrees with itself.
##
##     {
##       "schema": 1,
##       "selected": "standard",
##       "conditions": [
##         {"id": "standard", "name": "Standard", "wind_speed_mps": 0.0, "wind_from_deg": 0.0,
##          "gustiness_mps": 0.0, "temperature_c": 15.0}
##       ]
##     }
##
## ---------------------------------------------------------------------------
## THERE IS NO MIGRATION HERE, THERE IS AN ABSORPTION
## ---------------------------------------------------------------------------
##
## F1 left a temperature parked on every site — one from a v1 course's `air` block, or one the
## field editor typed, and `site.gd`'s header is emphatic that NOTHING DISTINGUISHES THEM. So this
## does the same thing with both: `absorb_parked_temperatures()` moves each one into a set and
## clears the slot.
##
## It is not a schema migration because there is no old schema: `conditions.json` is created by
## this slice. It is a hand-off between two files, and the thing that makes it safe is
## `at_temperature()` — a set per DISTINCT temperature, found before it is created. Two sites both
## parked at 35 °C produce one "35 °C" set, and a site parked at 15 °C produces NO new set at all,
## because 15 °C calm is `Standard` and it is already here. A builder who never typed a temperature
## ends with exactly one set and no invented rows, which is the whole of the test for this.
##
## Clearing the slot sets it back to `null` rather than to 15.0, and the difference is the point:
## `null` is "the builder never said", and writing 15.0 into that slot would turn a silence into an
## authored fact on the next save. See `site.gd`.

const SAVE_PATH := "user://conditions.json"
const SCHEMA_VERSION := 1

## How close two temperatures have to be to be the same temperature. Exact equality, to within a
## double's noise: these numbers come off a spinbox and out of a JSON file, and neither introduces
## drift. A loose tolerance here would silently merge a 20 °C set into a 20.5 °C one.
const SAME_TEMPERATURE_C := 1.0e-9

## Which weather is being flown in.
var selected_id := ""

## id -> Conditions, in insertion order, which is the order a rail lists them in.
var _sets: Dictionary = {}
## Top-level blocks a later version wrote. Per-set unknowns live on the Conditions itself, because
## only the set knows which of its own fields it recognises.
var _unknown_top: Dictionary = {}


## A library with just `Standard` in it — what a fresh install has, and what every failure mode
## falls back to.
static func with_default() -> ConditionsLibrary:
	var library := ConditionsLibrary.new()
	library.put(Conditions.new())
	library.selected_id = Conditions.STANDARD_ID
	return library


static func load_from(path: String = SAVE_PATH) -> ConditionsLibrary:
	# Every file-level failure — missing, unreadable, invalid JSON, JSON that is not an object —
	# comes back as an empty document from the one place that handles them.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return with_default()

	var library := ConditionsLibrary.new()
	library._unknown_top = JsonStore.unknown_fields(document, ["schema", "selected", "conditions"])

	var stored: Variant = document.get("conditions", [])
	if stored is Array:
		for entry in (stored as Array):
			if not (entry is Dictionary):
				continue
			var record: Dictionary = entry
			# A set with no id cannot be selected, so there is nothing that could reach it.
			# Dropped rather than given a generated id, which would look like a weather the
			# builder had made.
			if String(record.get("id", "")) == "":
				push_warning("%s: skipping conditions with no id" % path)
				continue
			var loaded := Conditions.from_data(record)
			library._sets[loaded.conditions_id] = loaded

	if library._sets.is_empty():
		return with_default()

	library.selected_id = String(document.get("selected", ""))
	if not library._sets.has(library.selected_id):
		library.selected_id = String(library._sets.keys()[0])
	return library


func save(path: String = SAVE_PATH) -> bool:
	var sets: Array = []
	for id in _sets:
		sets.append((_sets[id] as Conditions).to_data())

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["selected"] = selected_id
	document["conditions"] = sets
	return JsonStore.write_document(path, document)


# ---------------------------------------------------------------------------
# What is in it
# ---------------------------------------------------------------------------

func ids() -> Array[String]:
	var out: Array[String] = []
	for id in _sets:
		out.append(String(id))
	return out


func names() -> Array[String]:
	var out: Array[String] = []
	for id in _sets:
		out.append((_sets[id] as Conditions).conditions_name)
	return out


func has(id: String) -> bool:
	return _sets.has(id)


func conditions(id: String) -> Conditions:
	return _sets.get(id) as Conditions


func selected() -> Conditions:
	return conditions(selected_id)


## Chooses a weather. Returns false — and changes nothing — for an id that is not here, rather than
## falling back to something arbitrary, for `SiteLibrary.select()`'s reason: silently flying in
## weather other than the one you asked for is the same class of quiet wrongness as a stale best
## lap.
##
## IT WRITES NOTHING. Selecting a weather is not editing a site and not editing a course, and the
## suite asserts the bytes of both those files are untouched across a select — because "switch the
## conditions, read the new thrust-to-weight" is the one interaction this whole object exists for,
## and a version of it that rewrote the field every time would be editing the builder's data to
## answer a question.
func select(id: String) -> bool:
	if not _sets.has(id):
		return false
	selected_id = id
	return true


func put(p_conditions: Conditions) -> void:
	_sets[p_conditions.conditions_id] = p_conditions
	if selected_id == "":
		selected_id = p_conditions.conditions_id


## A new set, still and standard, with a generated id.
func create(p_name: String) -> Conditions:
	var made := Conditions.new()
	made.conditions_id = _unique_id(p_name)
	made.conditions_name = p_name
	put(made)
	return made


## Removes a set, and REFILLS the library when that was the last one — `SiteLibrary.remove()`'s
## rule and for its reason: there has to BE weather. A library with no conditions is an app that
## cannot say what air it is quoting.
func remove(id: String) -> bool:
	if not _sets.has(id):
		return false
	_sets.erase(id)
	if _sets.is_empty():
		var replacement := Conditions.new()
		_sets[replacement.conditions_id] = replacement
	if not _sets.has(selected_id):
		selected_id = String(_sets.keys()[0])
	return true


## Renames without changing the id, so a rename cannot orphan anything pointing here.
func rename(id: String, p_name: String) -> bool:
	if not _sets.has(id):
		return false
	(_sets[id] as Conditions).conditions_name = p_name
	return true


# ---------------------------------------------------------------------------
# A set per distinct temperature, and the parked slot it drains
# ---------------------------------------------------------------------------

## The calm set at this temperature: the one that is already here if there is one, and a new one
## named after the temperature if there is not.
##
## FOUND BEFORE IT IS CREATED, and that is what makes both callers behave. The migration hands this
## a temperature parked on a site; the field editor hands it a temperature the builder just typed;
## neither should end up with a second "35 °C" beside the first. 15 °C finds `Standard`, because
## `Standard` is calm at 15 °C and a search that matches it needs no special case for it — which
## is also why a builder who never typed a temperature finishes with exactly one row.
##
## ONLY CALM SETS MATCH. A set the builder made at 35 °C in a 6 m/s wind is a different question
## from "what does this do at 35 °C", and handing it back would silently add a wind nobody asked
## for to the garage's numbers.
func at_temperature(temperature_c: float) -> Conditions:
	for id in _sets:
		var candidate: Conditions = _sets[id]
		if candidate.is_calm() and absf(candidate.temperature_c - temperature_c) < SAME_TEMPERATURE_C:
			return candidate
	var made := create(name_for_temperature(temperature_c))
	made.temperature_c = temperature_c
	return made


## What a set found by its temperature alone is called: "35 °C", and "22.5 °C" when the builder
## typed a half degree. One decimal place, with a trailing ".0" trimmed — the row should say back
## what they typed rather than a float's idea of it.
##
## NOT `%g`: GDScript's format strings do not implement it, and "%g °C" prints the two characters
## rather than the number. Measured — it is what the first version of this shipped, and the row was
## called "%g °C".
static func name_for_temperature(temperature_c: float) -> String:
	var text := String.num(temperature_c, 1)
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return "%s °C" % text


## Drains F1's parking slot: every site carrying a temperature gets it moved into a set here, and
## the slot is cleared to `null`.
##
## Returns whether anything moved, so a caller knows whether it has a reason to write two files.
## A startup that saved unconditionally would rewrite every builder's `sites.json` on every launch
## for ever, which is the quiet-rewrite failure `test_site.gd` §2 exists to prevent, arriving
## through a hand-off instead of through a writer.
##
## THE TEMPERATURE OF THE PLACE THE BUILDER IS AT IS THE ONE THAT ENDS UP SELECTED, and this is a
## decision rather than an accident. The sets are global and the parked temperatures were per-site,
## so absorbing more than one of them has to pick; picking the one belonging to the place they are
## standing in is the only choice that leaves the app quoting the same density after the hand-off
## as before it. Every other site's temperature is still here as a named row, one click away,
## rather than lost.
##
## `p_here` IS AN ARGUMENT RATHER THAN `sites.selected()`, and the difference is measurable. On a
## first launch against a v1 file the migration appends a site per course and leaves the library's
## own selection on the default field, while the place the builder is actually at is the site of
## the SELECTED COURSE. Reading the library's selection lost the 28 °C a builder had typed into
## their only course — the garage quoted their 2500 m at 15 °C — and `test_site.gd` §5 caught it.
## A library cannot know which course is open, so the caller that does says so.
func absorb_parked_temperatures(sites: SiteLibrary, p_here: Site = null) -> bool:
	if sites == null:
		return false
	var moved := false
	var here := p_here if p_here != null else sites.selected()
	for id in sites.ids():
		var where := sites.site(id)
		if where == null:
			continue
		var parked: Variant = where.parked_temperature_c
		if not (parked is float or parked is int):
			continue
		var into := at_temperature(float(parked))
		if where == here:
			selected_id = into.conditions_id
		# BACK TO null, NOT TO 15.0. See the header: the slot is a Variant precisely so that
		# "nothing parked" and "parked at standard" are different states.
		where.parked_temperature_c = null
		moved = true
	return moved


## The conditions file that pairs with a given courses file — `SiteLibrary.path_beside()`'s rule
## and for its reason: a caller handing a scratch course library to a room must not be able to
## overwrite the builder's own weather.
static func path_beside(courses_path: String) -> String:
	if courses_path == CourseLibrary.SAVE_PATH:
		return SAVE_PATH
	return "%s_conditions.json" % courses_path.get_basename()


## A machine-readable id derived from the name, suffixed when that is already taken. Derived rather
## than random so a hand-edited file stays readable — `SiteLibrary._unique_id`'s reasoning, and
## deliberately the same arithmetic.
func _unique_id(p_name: String) -> String:
	var base := ""
	for character in p_name.to_lower():
		base += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	base = base.strip_edges().lstrip("_").rstrip("_")
	if base == "":
		base = "conditions"
	if not _sets.has(base):
		return base
	var index := 2
	while _sets.has("%s_%d" % [base, index]):
		index += 1
	return "%s_%d" % [base, index]
