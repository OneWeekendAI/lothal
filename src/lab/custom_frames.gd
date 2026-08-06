class_name CustomFrames
extends RefCounted
## The frames a builder entered themselves, in `user://custom_parts.json`.
##
## A person holding a frame Lothal does not stock should be able to put its numbers in and get a
## trustworthy aircraft out. Nothing about that needs new geometry: FrameModel is procedural off
## `arm_mm` alone, so a 350 mm frame draws correctly with zero rendering work. What it needs is a
## place to put the numbers, a refusal for the ones that make the geometry undefined, and — above
## everything — an id space that cannot touch the catalog's.
##
## ---------------------------------------------------------------------------
## WHAT A RECORD IS, AND WHY IT IS EXACTLY THIS
## ---------------------------------------------------------------------------
##
## A record is catalog-SHAPED: the same `specs` / `catalog` two-tier split, the same `source`, the
## same `part_id` / `name` / `mass_g` / `category`. Deliberately the same rather than a simplified
## cousin, because the whole point is that FrameModel, Build, FramePicker and FrameDetails read it
## through the code paths they already have. A second shape would mean a second reader for every
## one of them.
##
## The required fields ARE the physics contract and nothing more:
##
##   mass_g               — the mass model
##   specs.arm_mm         — centre-to-motor. Inertia, drag scaling, resonance, every dimension of
##                          the drawn frame. The sleeper spec: it is squared in the parallel axis
##                          theorem (frames.json's _schema).
##   specs.max_prop_inches — the prop-clearance warning
##   specs.motor_mount    — the motor-fit warning, and the mount pad's size
##   specs.stack_mount    — the ESC/FC fit warning
##   catalog.material     — appearance only, and only the three FrameModel._material_for
##                          distinguishes are offered, because offering a fourth would put a word
##                          on screen that changes nothing.
##
## `catalog.size_class` is DERIVED from max_prop_inches rather than asked for. It exists to drive
## the picker's Size filter, and a builder who typed "5 inch" for a 5.1" frame would land in a
## filter bucket of one that nothing else can ever join.
##
## `source` IS REQUIRED AND IS NOT OPTIONAL. Every shipped part carries provenance; a
## builder-entered frame's honest provenance is "measured on my scale" or "off the product page",
## and the field's EXISTENCE is what stops a custom part from being mistaken for a validated one.
## Free text, because there is no vocabulary to constrain it to, but it cannot be empty.
##
## ---------------------------------------------------------------------------
## WHAT IS REFUSED, AND WHY SO LITTLE IS
## ---------------------------------------------------------------------------
##
## Refused: an id that is not custom_-prefixed or that collides with one already held; a missing
## or non-positive `arm_mm`; a non-positive `mass_g`; an empty `name`; an empty `source`. That is
## the complete list, and every entry on it is a case where there is no aircraft to draw or fly —
## FrameModel divides by arm_mm, and a zero-mass airframe has infinite thrust-to-weight.
##
## Everything else warns. A 900 mm arm, a 4 g 10" frame, a prop that geometrically cannot fit
## between its neighbours: all of those are aircraft, they are just surprising ones, and
## labs-and-sim.md §2 is explicit that Lab warns and never blocks. The bounds themselves live in
## FramePlausibility, next to the build that carries them, not here — this file decides what is a
## FRAME, not what is a SENSIBLE frame.
##
## ---------------------------------------------------------------------------
## THE FILE
## ---------------------------------------------------------------------------
##
##     {
##       "schema": 1,
##       "frames": [ { ...one catalog-shaped record... } ]
##     }
##
## `frames` rather than `parts` because motors, props, batteries, ESCs and FCs are follow-on
## slices and each wants its own array — a sibling key is the cheapest seam there is, and a single
## flat list would need a category discriminator on every read.
##
## json_store.gd's four rules apply unchanged, and two of them are worth restating here because
## this document holds a LIST rather than a set of scalars:
##
## - **A bad file is not a fatal error.** Invalid JSON, JSON of the wrong shape, `frames` that is
##   not an array, an entry that is not an object: each is reported through push_warning and each
##   loads as no custom frames. Lab opens. One bad record does not discard the good ones.
## - **Unknown fields are kept, not dropped.** Top-level blocks a later Lothal wrote (a `motors`
##   array, say) are held verbatim and written back. Inside a record it is simpler still: an
##   accepted record is stored WHOLE, so a field this version never heard of survives by never
##   being looked at.

const SAVE_PATH := "user://custom_parts.json"
const SCHEMA_VERSION := 1
const FRAMES_KEY := "frames"

## The three appearances FrameModel._material_for actually distinguishes, in its own words. Offered
## as a closed list rather than free text for one reason: the renderer substring-matches on
## "carbon" and "nylon" and gives everything else a neutral grey, so a fourth option would be a
## word on screen that changes nothing about the picture. Values are what goes in
## catalog.material, and they read the way the shipped catalog's do.
const MATERIALS := ["carbon fibre", "injection-moulded nylon (PA12)", "unspecified"]

## Every key this version writes at the top level. Anything else in the file is somebody else's
## and is handed straight back on save.
const KNOWN_TOP := ["schema", FRAMES_KEY]

var _frames: Array = []
var _rejections: Array[String] = []
var _unknown_top: Dictionary = {}


func frames() -> Array:
	return _frames


## Why each refused record was refused, in words a panel can show. Held rather than pushed as
## warnings alone, because a builder who hand-edited the file needs to be told which line is wrong
## and the engine log is not where they are looking.
func rejections() -> Array[String]:
	return _rejections


func get_frame(part_id: String) -> Dictionary:
	for frame in _frames:
		if str(frame.get("part_id", "")) == part_id:
			return frame
	return {}


# ---------------------------------------------------------------------------
# Building a record
# ---------------------------------------------------------------------------

## A catalog-shaped record from the eight things a builder is asked for. Static, and the ONE place
## a record's shape is written down — the dialog calls this rather than assembling a dictionary of
## its own, so a UI that has drifted cannot produce a record that no reader understands.
static func make_record(name: String, mass_g: float, arm_mm: float, max_prop_inches: float,
		motor_mount: String, stack_mount: String, material: String, source: String) -> Dictionary:
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "frame",
		"mass_g": mass_g,
		"specs": {
			"arm_mm": arm_mm,
			"max_prop_inches": max_prop_inches,
			"motor_mount": motor_mount,
			"stack_mount": stack_mount,
		},
		"catalog": {
			"frame_type": "custom",
			"material": material,
			"size_class": size_class_for(max_prop_inches),
		},
		"source": source,
	}


## The reserved prefix plus a slug of the name. Derived from the name rather than asked for,
## because a part_id is a key and not a thing a builder should have to think about — and derived
## rather than random so the file stays readable when someone opens it in an editor, which they
## will.
static func id_for(name: String) -> String:
	var slug := ""
	for character in name.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			slug += character
		elif slug != "" and not slug.ends_with("_"):
			slug += "_"
	slug = slug.trim_suffix("_")
	if slug == "":
		slug = "frame"
	return PartsCatalog.CUSTOM_PREFIX + slug


## The picker's Size bucket, derived from max_prop_inches rather than asked for — see the header.
## The boundaries are the ones the shipped catalog already browses along (frames.json's
## size_class values), so a custom 5" frame lands in the same bucket as the catalog's 5" frames
## instead of in a bucket of one. FramePicker's Size filter builds its options straight off these
## strings (PartPicker._derive_options), so the SHAPE of the string is not decoration — a value
## the catalog does not already use is a filter bucket with exactly one frame in it, forever.
##
## The mark is `"`, not the letters "in" — frames.json spells it 5", 3.5", 10". This is NOT fully
## derivable in general: the catalog is inconsistent by hand (3.5" appears both as "3\"" and as
## "3.5\"", and 1.6" is spelled "65mm", a diameter rather than a radius figure). No formula
## reproduces that; a 3.5" custom frame lands in the "3.5\"" bucket, matching the more literal of
## the catalog's two spellings, and a sub-2" custom frame gets an inch bucket rather than "65mm"
## as there is nothing here to derive a millimetre figure from. Both are the honest limit of
## deriving from one number, not a bug to chase further.
static func size_class_for(max_prop_inches: float) -> String:
	if max_prop_inches <= 0.0:
		return "unspecified"
	var rounded_inches := snappedf(max_prop_inches, 0.5)
	# str(float) always carries a decimal (13.0, 12.5); trimming a trailing ".0" gives whole
	# numbers their bare form ("13"), matching the shipped catalog's own size_class values.
	var text := str(rounded_inches)
	if text.ends_with(".0"):
		text = text.trim_suffix(".0")
	return "%s\"" % text


# ---------------------------------------------------------------------------
# Accepting and refusing
# ---------------------------------------------------------------------------

## Adds a record, or explains why not. An empty return means it was accepted; anything else is the
## complete list of what is wrong with it, so a dialog can show every problem at once rather than
## one per attempt.
##
## Loads the shipped catalog once, here, rather than letting _problems_with reach for it per call
## — load_default() parses all six data/parts/ files, and a caller adding several records in a row
## (load_from(), below) has no reason to pay that six times over for one collision check apiece.
func add(record: Dictionary) -> Array[String]:
	return _add_against(record, PartsCatalog.load_default())


func _add_against(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems := _problems_with(record, catalog)
	if problems.is_empty():
		_frames.append(record)
	return problems


func remove(part_id: String) -> bool:
	for i in _frames.size():
		if str(_frames[i].get("part_id", "")) == part_id:
			_frames.remove_at(i)
			return true
	return false


## Everything wrong with a record, or an empty array. The complete refusal list — see the header
## for why it is this short and no shorter.
##
## The collision check runs against the SHIPPED catalog as well as against what is already held,
## which is belt and braces on top of the prefix rule: the prefix alone already makes a collision
## impossible, and this catches the case where a future edit weakens the prefix rule without
## anybody noticing that this is what the prefix rule was FOR. `catalog` is passed in rather than
## loaded here — see add() and load_from(), which each load it exactly once.
func _problems_with(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var part_id := str(record.get("part_id", ""))
	if part_id == "" or not PartsCatalog.is_custom(part_id):
		problems.append("part_id \"%s\" must start with \"%s\" — that prefix is what keeps a custom frame out of the shipped catalog's id space" % [
			part_id, PartsCatalog.CUSTOM_PREFIX])
	elif not get_frame(part_id).is_empty():
		problems.append("there is already a custom frame called \"%s\"" % part_id)
	elif not catalog.get_part(part_id).is_empty():
		problems.append("\"%s\" is a shipped catalog part" % part_id)

	if str(record.get("name", "")).strip_edges() == "":
		problems.append("a frame needs a name")

	if str(record.get("category", "frame")) != "frame":
		problems.append("this slice defines frames only; \"%s\" is not a frame" % record.get("category"))

	var mass := float(record.get("mass_g", 0.0))
	if mass <= 0.0:
		problems.append("mass_g must be positive — a zero-mass airframe has infinite thrust-to-weight")

	var specs: Variant = record.get("specs", null)
	if not (specs is Dictionary) or not (specs as Dictionary).has("arm_mm"):
		problems.append("specs.arm_mm (centre to motor, in mm) is required — the whole frame is drawn from it")
	elif float((specs as Dictionary)["arm_mm"]) <= 0.0:
		problems.append("specs.arm_mm must be positive — at zero there is no geometry to draw")

	if str(record.get("source", "")).strip_edges() == "":
		problems.append("source is required: where these numbers came from. \"Measured on my scale\" is a complete answer; nothing is not")

	return problems


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func save(path: String = SAVE_PATH) -> bool:
	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document[FRAMES_KEY] = _frames
	return JsonStore.write_document(path, document)


## Reads the file, or returns no custom frames. Every failure mode lands in the same place, and a
## refused RECORD does not take the good records down with it — one bad line in a hand-edited file
## should cost the builder that line and nothing else.
static func load_from(path: String = SAVE_PATH) -> CustomFrames:
	var doc := CustomFrames.new()

	# Missing, unreadable, invalid JSON, or JSON that is not an object: all handled in the one
	# place, and all reported as warnings rather than errors.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return doc

	doc._unknown_top = JsonStore.unknown_fields(document, KNOWN_TOP)

	var stored: Variant = document.get(FRAMES_KEY, [])
	if not (stored is Array):
		push_warning("%s has no readable \"%s\" array; no custom frames loaded" % [path, FRAMES_KEY])
		return doc

	# Loaded once for the whole file, not once per record — see the note on add().
	var catalog := PartsCatalog.load_default()
	for entry in (stored as Array):
		if not (entry is Dictionary):
			doc._rejections.append("an entry in \"%s\" is not an object" % FRAMES_KEY)
			continue
		var problems := doc._add_against(entry as Dictionary, catalog)
		for problem in problems:
			doc._rejections.append(problem)

	if not doc._rejections.is_empty():
		push_warning("%s: %d record(s) refused: %s" % [
			path, doc._rejections.size(), "; ".join(doc._rejections)])

	return doc
