class_name CustomParts
extends RefCounted
## The parts a builder entered themselves, in `user://custom_parts.json`. This is the part of
## that job which is the same for every category; CustomFrames and CustomMotors are the parts
## that are not.
##
## LTHL-21 wrote all of this frame-shaped, which was right when there was one category and wrong
## the moment there were two — four more follow. What generalised cleanly is exactly what was
## never about frames in the first place, and it is worth naming because it is the whole of the
## safety story:
##
##   THE ID SPACE. `custom_` is reserved, from both ends: PartsCatalog._load_category refuses a
##   shipped part that claims it, and this file refuses a builder's part that does not. A custom
##   part that managed to call itself `motor_2207_1960kv` would not shadow the catalog entry, it
##   would BECOME the 496 g oracle that six test files assert against, and every one of them
##   would go on passing against a number the builder typed. Two id spaces that cannot intersect
##   is the only version of this that does not depend on anybody being careful.
##
##   THE DOCUMENT. One file, one array per category, unknown top-level blocks handed back
##   verbatim on save. That last rule is what lets two categories share a file without a
##   coordinating writer: a motors save reads the document, replaces `motors`, and writes
##   `frames` back exactly as it found it.
##
##   THE REFUSALS THAT ARE NOT ABOUT ANY PARTICULAR PART. An id outside the reserved space or
##   colliding with one already held; an empty name; a category that is not this document's; a
##   non-positive mass; an empty `source`.
##
##   THE DEGRADATION. A bad file is not a fatal error and a bad RECORD does not take its
##   neighbours down with it. Lab opens either way. One hand-edited line costs the builder that
##   line and nothing else.
##
## `source` IS REQUIRED AND IS NOT OPTIONAL, for every category. Every shipped part carries
## provenance; a builder-entered part's honest provenance is "measured on my scale" or "off the
## product page", and the field's EXISTENCE is what stops a custom part from being mistaken for a
## validated one. Free text, because there is no vocabulary to constrain it to, but not empty.
##
## What does NOT live here is any judgement about whether a part is SENSIBLE. This file decides
## what is a PART; FramePlausibility and MotorPlausibility decide what is a surprising one, next
## to the build that carries them, and they warn rather than refuse (labs-and-sim.md §2).
##
## Subclasses supply four things: the array key, the category, the fields that make their
## category's geometry or physics defined, and a make_record. Nothing else.

const SAVE_PATH := "user://custom_parts.json"
const SCHEMA_VERSION := 1

var _records: Array = []
var _rejections: Array[String] = []
var _unknown_top: Dictionary = {}


# ---------------------------------------------------------------------------
# What a subclass says about itself
# ---------------------------------------------------------------------------

## The document key this category's records live under. `frames`, `motors`, and four to come —
## a sibling key per category rather than one flat list, because a flat list would need a
## category discriminator on every read and would make one bad record everyone's problem.
func array_key() -> String:
	return ""


## The value a record's `category` field must carry. The same word PartsCatalog.CATEGORY_FILES
## uses, because these records are read through the catalog's own code paths.
func category() -> String:
	return ""


## Everything wrong with a record that is specific to this category — the fields without which
## there is no geometry to draw or no physics to run. Empty for a good record. Called only after
## the generic checks have passed nothing on to it that is not at least a part.
func _category_problems(_record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	return []


# ---------------------------------------------------------------------------
# Reading what is held
# ---------------------------------------------------------------------------

func records() -> Array:
	return _records


## Why each refused record was refused, in words a panel can show. Held rather than pushed as
## warnings alone, because a builder who hand-edited the file needs to be told which line is
## wrong and the engine log is not where they are looking.
func rejections() -> Array[String]:
	return _rejections


func get_record(part_id: String) -> Dictionary:
	for record in _records:
		if str(record.get("part_id", "")) == part_id:
			return record
	return {}


# ---------------------------------------------------------------------------
# Accepting and refusing
# ---------------------------------------------------------------------------

## Adds a record, or explains why not. An empty return means it was accepted; anything else is
## the complete list of what is wrong with it, so a dialog can show every problem at once rather
## than one per attempt.
##
## Loads the shipped catalog once, here, rather than letting _problems_with reach for it per call
## — load_default() parses all six data/parts/ files, and a caller adding several records in a
## row (load_from) has no reason to pay that six times over.
func add(record: Dictionary) -> Array[String]:
	return _add_against(record, _catalog_for_add())


## The catalog THIS category's `add` checks a record against. Default is the shipped catalog, which
## is right for every category whose records only cross-reference the shipped id space. The one
## exception is CustomMotors, whose `thrust_test.prop_id` can name a custom PROPELLER — that
## subclass overrides this to hand in a catalog that has the neighbouring custom props already
## merged, or the dialog would refuse a motor citing a prop the very same file defines.
func _catalog_for_add() -> PartsCatalog:
	return PartsCatalog.load_default()


func _add_against(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems := _problems_with(record, catalog)
	if problems.is_empty():
		_records.append(record)
	return problems


func remove(part_id: String) -> bool:
	for i in _records.size():
		if str(_records[i].get("part_id", "")) == part_id:
			_records.remove_at(i)
			return true
	return false


## The generic refusals, then the category's own.
##
## The collision check runs against the SHIPPED catalog as well as against what is already held,
## which is belt and braces on top of the prefix rule: the prefix alone already makes a collision
## impossible, and this catches the case where a future edit weakens the prefix rule without
## anybody noticing that this is what the prefix rule was FOR.
func _problems_with(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var part_id := str(record.get("part_id", ""))
	if part_id == "" or not PartsCatalog.is_custom(part_id):
		problems.append("part_id \"%s\" must start with \"%s\" — that prefix is what keeps a part you entered out of the shipped catalog's id space" % [
			part_id, PartsCatalog.CUSTOM_PREFIX])
	elif not get_record(part_id).is_empty():
		problems.append("there is already a part you entered called \"%s\"" % part_id)
	elif not catalog.get_part(part_id).is_empty():
		problems.append("\"%s\" is a shipped catalog part" % part_id)

	if str(record.get("name", "")).strip_edges() == "":
		problems.append("a %s needs a name" % category())

	if str(record.get("category", category())) != category():
		problems.append("this document holds %ss; \"%s\" is not one" % [
			category(), record.get("category")])

	if float(record.get("mass_g", 0.0)) <= 0.0:
		problems.append("mass_g must be positive — a zero-mass part has infinite thrust-to-weight")

	if str(record.get("source", "")).strip_edges() == "":
		problems.append("source is required: where these numbers came from. \"Measured on my scale\" is a complete answer; nothing is not")

	problems.append_array(_category_problems(record, catalog))
	return problems


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Writes this category's array, and hands every other top-level block back exactly as it was
## read. That is what lets the frames dialog and the motors dialog share one file with no
## coordination between them: each one owns its own key and is a faithful copyist about the rest.
func save(path: String = SAVE_PATH) -> bool:
	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document[array_key()] = _records
	return JsonStore.write_document(path, document)


## Fills this document from the file. Every failure mode lands in the same place, and a refused
## RECORD does not take the good records down with it. Subclasses wrap this in a static
## `load_from` of their own type, because a static method in GDScript cannot ask what class it
## was called on.
func read_from(path: String, catalog: PartsCatalog = null) -> void:
	# Missing, unreadable, invalid JSON, or JSON that is not an object: all handled in the one
	# place, and all reported as warnings rather than errors.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return

	_unknown_top = JsonStore.unknown_fields(document, ["schema", array_key()])

	var stored: Variant = document.get(array_key(), [])
	if not (stored is Array):
		push_warning("%s has no readable \"%s\" array; nothing you entered was loaded" % [
			path, array_key()])
		return

	# Loaded once for the whole file, not once per record — see the note on add(). Caller may hand
	# in a catalog that already has neighbouring custom parts merged (PartsCatalog.load_with_custom
	# does this for CustomMotors so that a motor citing a custom prop resolves), and if nothing is
	# handed in, this subclass's own default answers the question.
	if catalog == null:
		catalog = _catalog_for_add()
	for entry in (stored as Array):
		if not (entry is Dictionary):
			_rejections.append("an entry in \"%s\" is not an object" % array_key())
			continue
		_rejections.append_array(_add_against(entry as Dictionary, catalog))

	if not _rejections.is_empty():
		push_warning("%s: %d record(s) refused: %s" % [
			path, _rejections.size(), "; ".join(_rejections)])


# ---------------------------------------------------------------------------
# Ids
# ---------------------------------------------------------------------------

## The reserved prefix plus a slug of the name. Derived from the name rather than asked for,
## because a part_id is a key and not a thing a builder should have to think about — and derived
## rather than random so the file stays readable when someone opens it in an editor, which they
## will. `fallback` is what an unsluggable name (punctuation only) becomes, and is the category
## word, so the id still says what kind of thing it is.
static func id_for_name(name: String, fallback: String) -> String:
	var slug := ""
	for character in name.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			slug += character
		elif slug != "" and not slug.ends_with("_"):
			slug += "_"
	slug = slug.trim_suffix("_")
	if slug == "":
		slug = fallback
	return PartsCatalog.CUSTOM_PREFIX + slug
