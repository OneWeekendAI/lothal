class_name SiteLibrary
extends RefCounted
## The places a builder flies, and which one they are at.
##
## `user://sites.json`, alongside the courses and the assembly tweaks, under the same four rules
## `AssemblyTweaks` set out and `CourseLibrary`'s header restates — because a format decided twice
## is a format that disagrees with itself. Two of the four are pure file handling and already live
## in `JsonStore`; the two that are about what a document MEANS are honoured here and in `site.gd`.
##
##     {
##       "schema": 1,
##       "selected": "default_site",
##       "sites": [
##         {"id": "default_site", "name": "Field", "elevation_m": 0.0,
##          "terrain": {"shape": "flat", "width_m": 120.0, "length_m": 120.0},
##          "obstacles": []}
##       ]
##     }
##
## ---------------------------------------------------------------------------
## THE MIGRATION: ONE SITE PER COURSE, AND NEVER MERGED
## ---------------------------------------------------------------------------
##
## Every course on disk today carries its own `air` block, and air is now a fact about the PLACE.
## So each existing course gets a site made for it, named after the course, flat, sized off the
## course's own gates.
##
## Merging them into one shared site is one line shorter and would be wrong. Two courses may carry
## two different elevations, typed by a builder who meant them — the whole reason the air block
## exists is that Bangalore is 920 m and Leh is 3500 m — and merging discards whichever one loses.
## No error, no crash, just a thrust-to-weight that quietly describes somewhere else. One site per
## course over-produces sites, which a builder can delete in a second; merging destroys typed data,
## which they cannot get back.
##
## The migration is ONE-WAY. It runs on a v1 document and stamps the file v2, and a v2 document is
## left alone. That check is load-bearing rather than an optimisation: running it a second time
## would find no `air` block, read the silence as standard air, and reset every elevation the first
## run had just rescued.

const SAVE_PATH := "user://sites.json"
const SCHEMA_VERSION := 1

## The `courses.json` schema this migration produces. Named here rather than read off
## `CourseLibrary.SCHEMA_VERSION` because it is the version this code knows how to WRITE — the day
## a v3 arrives, the constant CourseLibrary advertises moves and this comparison must not follow it
## silently.
const COURSES_SCHEMA_V2 := 2

## How much ground to leave around a migrated course's own bounding box, on every side.
##
## A CHOSEN NUMBER, NOT A MEASURED ONE. Nothing is known about where the edge of a real field was —
## a v1 course records gates and nothing else — so 20 m is a judgement: enough to overshoot a gate
## and turn around in on a 5" machine, small enough that the site still reads as the course's own
## patch rather than as a prairie. A builder who knows their field types its real size, and the
## day they do this number stops applying to them.
const MIGRATION_MARGIN_M := 20.0

## Which site is being flown at.
var selected_id := ""

## id -> Site, in insertion order, which is the order a rail lists them in.
var _sites: Dictionary = {}
## Top-level blocks a later version wrote. Per-site unknowns live on the Site itself, because only
## the site knows which of its own fields it recognises.
var _unknown_top: Dictionary = {}


## A library with just the default field in it — what a fresh install has, and what every failure
## mode falls back to.
static func with_default() -> SiteLibrary:
	var library := SiteLibrary.new()
	library.put(Site.new())
	library.selected_id = Site.DEFAULT_ID
	return library


static func load_from(path: String = SAVE_PATH) -> SiteLibrary:
	# Every file-level failure — missing, unreadable, invalid JSON, JSON that is not an object —
	# comes back as an empty document from the one place that handles them.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return with_default()

	var library := SiteLibrary.new()
	library._unknown_top = JsonStore.unknown_fields(document, ["schema", "selected", "sites"])

	var stored: Variant = document.get("sites", [])
	if stored is Array:
		for entry in (stored as Array):
			if not (entry is Dictionary):
				continue
			var record: Dictionary = entry
			# A site with no id cannot be pointed at by a course, so there is nothing that could
			# reach it. Dropped rather than given a generated id, which would look like a place the
			# builder had made.
			if String(record.get("id", "")) == "":
				push_warning("%s: skipping a site with no id" % path)
				continue
			var loaded := Site.from_data(record)
			library._sites[loaded.site_id] = loaded

	if library._sites.is_empty():
		return with_default()

	library.selected_id = String(document.get("selected", ""))
	if not library._sites.has(library.selected_id):
		library.selected_id = String(library._sites.keys()[0])
	return library


func save(path: String = SAVE_PATH) -> bool:
	var sites: Array = []
	for id in _sites:
		sites.append((_sites[id] as Site).to_data())

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["selected"] = selected_id
	document["sites"] = sites
	return JsonStore.write_document(path, document)


# ---------------------------------------------------------------------------
# What is in it
# ---------------------------------------------------------------------------

func ids() -> Array[String]:
	var out: Array[String] = []
	for id in _sites:
		out.append(String(id))
	return out


func names() -> Array[String]:
	var out: Array[String] = []
	for id in _sites:
		out.append((_sites[id] as Site).site_name)
	return out


func has(id: String) -> bool:
	return _sites.has(id)


func site(id: String) -> Site:
	return _sites.get(id) as Site


func selected() -> Site:
	return site(selected_id)


## Chooses a site. Returns false — and changes nothing — for an id that is not here, rather than
## falling back to something arbitrary, for CourseLibrary.select()'s reason: silently being
## somewhere other than where you asked to be is the same class of quiet wrongness as a stale
## best lap.
func select(id: String) -> bool:
	if not _sites.has(id):
		return false
	selected_id = id
	return true


func put(p_site: Site) -> void:
	_sites[p_site.site_id] = p_site
	if selected_id == "":
		selected_id = p_site.site_id


## A new site, flat and at sea level, with a generated id.
func create(p_name: String) -> Site:
	var made := Site.new()
	made.site_id = _unique_id(p_name)
	made.site_name = p_name
	put(made)
	return made


## Removes a site, and REFILLS the library when that was the last one — where `CourseLibrary`
## refuses instead.
##
## The two differ on purpose. A course is a route the builder drew, and refusing to delete the last
## one leaves them with something they made and cannot get rid of, which is why that rule is worth
## revisiting elsewhere. A site is a place, and there has to BE a place: Sim opens somewhere, and a
## library with no sites is an app with no ground. Refilling with the default field is the same
## answer `load_from` gives a damaged file, arrived at from the other direction.
func remove(id: String) -> bool:
	if not _sites.has(id):
		return false
	_sites.erase(id)
	if _sites.is_empty():
		var replacement := Site.new()
		_sites[replacement.site_id] = replacement
	if not _sites.has(selected_id):
		selected_id = String(_sites.keys()[0])
	return true


## Renames without changing the id, so a rename cannot orphan a course that points here.
func rename(id: String, p_name: String) -> bool:
	if not _sites.has(id):
		return false
	(_sites[id] as Site).site_name = p_name
	return true


## A machine-readable id derived from the name, suffixed when that is already taken. Derived rather
## than random so a hand-edited file stays readable — `CourseLibrary._unique_id`'s reasoning, and
## deliberately the same arithmetic.
func _unique_id(p_name: String) -> String:
	var base := ""
	for character in p_name.to_lower():
		base += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	base = base.strip_edges().lstrip("_").rstrip("_")
	if base == "":
		base = "site"
	if not _sites.has(base):
		return base
	var index := 2
	while _sites.has("%s_%d" % [base, index]):
		index += 1
	return "%s_%d" % [base, index]


# ---------------------------------------------------------------------------
# courses.json v1 -> v2
# ---------------------------------------------------------------------------

## The sites file that pairs with a given courses file. The real courses file pairs with the real
## sites file; anything else — a test's scratch library, a future import — pairs with a sites file
## beside it. One place knows the pairing, so a caller cannot hand the app's own sites file to a
## scratch course library and overwrite a builder's fields.
static func path_beside(courses_path: String) -> String:
	if courses_path == CourseLibrary.SAVE_PATH:
		return SAVE_PATH
	return "%s_sites.json" % courses_path.get_basename()


## Reads `courses_path`, gives every v1 course a site of its own, and stamps the file v2. Returns
## the sites — migrated or simply loaded — so a caller does both in one line at startup.
##
## Lossless: nothing about a course is removed but its `air` block, and that block's two numbers
## both land on the site (the temperature parked for F2). One-way: a v2 document is read and
## returned untouched.
static func migrate_courses(courses_path: String = CourseLibrary.SAVE_PATH,
		sites_path: String = SAVE_PATH) -> SiteLibrary:
	var sites := load_from(sites_path)

	var document := JsonStore.read_document(courses_path)
	# No courses file at all is a fresh install, and a fresh install has nothing to migrate. It
	# must not write one either: a `courses.json` that appeared without the builder laying out a
	# course would be the app authoring on their behalf.
	if document.is_empty():
		return sites
	if int(document.get("schema", 1)) >= COURSES_SCHEMA_V2:
		return sites

	var records: Variant = document.get("courses", [])
	if records is Array:
		for entry in (records as Array):
			if not (entry is Dictionary):
				continue
			var record: Dictionary = entry
			var id := String(record.get("id", ""))
			var gates := GateCourse.gates_from_data(record.get("gates"))
			if id == "" or gates.is_empty():
				continue
			sites.put(_site_for(id, String(record.get("name", id)),
				AirDensity.from_data(record.get("air")), gates))
			record["site_id"] = "site_%s" % id
			# The one thing the migration removes, and only because both of its numbers have
			# landed somewhere else. Left in place it would be a second spelling of the site's
			# elevation, free to drift the first time either was edited.
			record.erase("air")

	document["schema"] = COURSES_SCHEMA_V2
	JsonStore.write_document(courses_path, document)
	sites.save(sites_path)
	return sites


## The site a single v1 course becomes: flat, named after the course, elevation lifted off its air,
## temperature parked, and sized to hold every gate with the margin clear on all four sides.
static func _site_for(course_id: String, course_name: String, air: AirDensity,
		gates: Array[Dictionary]) -> Site:
	var made := Site.new()
	made.site_id = "site_%s" % course_id
	made.site_name = course_name
	made.elevation_m = air.elevation_m
	made.parked_temperature_c = air.temperature_c

	# THE BOX, NOT THE SIZE OF THE BOX. A width and a length describe a rectangle with no position,
	# and a site with no position is one centred on the origin whether or not anybody decided that.
	# A course laid out 100 m east — which is what you get the moment somebody drags a gate rather
	# than starting from the default circle — then migrated to a 50 m field containing none of its
	# own gates. So the centre of the gates' own box goes on the block beside the size.
	var box := _gate_box(gates)
	# The margin on BOTH axes and on BOTH sides of each, which is why it is doubled. Applied to one
	# axis only, the far edge of the site runs through a gate.
	made.terrain = Site.flat_terrain(
		box.size.x + 2.0 * MIGRATION_MARGIN_M, box.size.y + 2.0 * MIGRATION_MARGIN_M,
		box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5)
	return made


## The ground footprint of a set of gates: the bounding box of their positions in the two
## horizontal axes, as a Rect2 of (min x, min z) and (width, length). Height is not in it — a site
## is a patch of ground, and how high the gates are hung above it is the course's business.
##
## A Rect2 rather than the size alone, because the caller needs where the box IS. That was the
## defect: returning only `maximum - minimum` threw away the position, and nothing downstream could
## tell a course at the origin from the same course 100 m away.
static func _gate_box(gates: Array[Dictionary]) -> Rect2:
	if gates.is_empty():
		return Rect2()
	var first: Vector3 = gates[0]["position"]
	var minimum := Vector2(first.x, first.z)
	var maximum := minimum
	for gate in gates:
		var position: Vector3 = gate["position"]
		minimum.x = minf(minimum.x, position.x)
		minimum.y = minf(minimum.y, position.z)
		maximum.x = maxf(maximum.x, position.x)
		maximum.y = maxf(maximum.y, position.z)
	return Rect2(minimum, maximum - minimum)
