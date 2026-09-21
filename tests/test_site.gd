class_name TestSite
extends RefCounted
## The site — the PLACE you fly — and the one-way migration that gives every existing course one.
##
## What is worth asserting here is not that a dictionary round-trips. It is the three things that
## could go wrong quietly, and each would go wrong on a builder's own disk rather than on a screen:
##
## **1. The migration could discard a typed fact.** Two courses may carry two different elevations.
## Merging them into one site is one line of code, produces no error, and silently throws away
## whatever one of the two builders typed. §3 below writes the file with two elevations in it and
## demands two sites out.
##
## **2. The file could be rewritten on first launch.** A site loaded and saved untouched has to
## come back byte-identical, or opening Lothal once edits every site a builder owns. §2 compares
## the bytes against a fixture written by the same writer the app uses.
##
## **3. The air could quietly become standard.** `GateCourse` loses `air` in this slice, and every
## reader of it has to move to the site. A reader that moved to a HARD-CODED standard instead
## reads identically on a fresh install and is wrong for everybody who typed an elevation. §5 puts
## a 3500 m site on the real path and asks the garage what air it is quoting.
##
## The default circuit's fingerprint is pinned here too, with no argument. That value predates air
## existing at all, and it is what stands between this slice and every best lap ever set.

const SITES_PATH := "user://test_site_sites.json"
const COURSES_PATH := "user://test_site_courses.json"

## The default circuit's fingerprint BEFORE air existed — the same golden value
## `tests/test_air_density.gd` pins as PRE_AIR_DEFAULT_FINGERPRINT, captured from the shipped code
## rather than pasted out of this slice's output.
const PRE_AIR_DEFAULT_FINGERPRINT := "f106fd00d916b853"


static func run() -> Array:
	var results: Array = []
	var sections := {
		"a fresh install": _a_fresh_install(),
		"the file": _the_file(),
		"the migration": _the_migration(),
		"the course lost its air": _the_course_lost_its_air(),
		"the garage": _the_garage_asks_the_site(),
	}
	# A runtime error partway through a section aborts only that section and its append never runs,
	# so the suite would pass with its best checks silently deleted. Asserting each section
	# produced something is what makes the count trustworthy — and what makes a mutation run
	# evidence rather than an anecdote.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# 1. A fresh install, and every damaged file, opens somewhere flyable
# ---------------------------------------------------------------------------

static func _a_fresh_install() -> Array:
	var results: Array = []
	_forget(SITES_PATH)

	# CHECK 1.
	var fresh := SiteLibrary.load_from(SITES_PATH)
	var only: Site = fresh.selected() if fresh != null else null
	results.append(TestResult.new(
		"a fresh install has exactly one site: the default field, flat, at sea level",
		fresh != null and fresh.ids().size() == 1 and fresh.selected_id == Site.DEFAULT_ID
			and only != null and only.site_id == Site.DEFAULT_ID
			and String(only.terrain.get("shape", "")) == Site.FLAT_SHAPE
			and absf(only.elevation_m) < 1.0e-9,
		"%d site(s): %s" % [
			0 if fresh == null else fresh.ids().size(),
			"none" if fresh == null else ", ".join(fresh.ids())]))

	# And it has an extent, which is what every later slice frames the camera on. A site with a
	# zero extent is a field you cannot draw and cannot walk out of.
	results.append(TestResult.new(
		"and the default field has a real extent rather than a zero one",
		only != null and only.extent().x > 0.0 and only.extent().y > 0.0,
		"none" if only == null else "%.0f x %.0f m" % [only.extent().x, only.extent().y]))

	# CHECK 4. Every file-level failure there is, each landing on the default site rather than on
	# an error dialog. Written the way JsonStore's own rule reads: a bad file is not a fatal error.
	var damaged := {
		"a file that is not there": "",
		"a truncated document": "{\"schema\": 1, \"sites\": [",
		"a document that is not an object": "[1, 2, 3]",
		"a document of the wrong shape": "{\"schema\": 1, \"sites\": \"lots\"}",
		"an empty file": "",
	}
	for label in damaged:
		_forget(SITES_PATH)
		var contents: String = damaged[label]
		if label != "a file that is not there":
			var handle := FileAccess.open(SITES_PATH, FileAccess.WRITE)
			handle.store_string(contents)
			handle.close()
		var opened := SiteLibrary.load_from(SITES_PATH)
		results.append(TestResult.new(
			"%s opens on the default site rather than stopping the app" % label,
			opened != null and opened.selected() != null
				and opened.selected().site_id == Site.DEFAULT_ID,
			"nothing at all" if opened == null else "opened \"%s\"" % opened.selected_id))

	_forget(SITES_PATH)
	return results


# ---------------------------------------------------------------------------
# 2. The file, and the promise that Lothal does not rewrite a builder's sites
# ---------------------------------------------------------------------------

static func _the_file() -> Array:
	var results: Array = []
	_forget(SITES_PATH)

	# Written through JsonStore, the same writer the app uses, for the reason test_air_density
	# records: hand-rolling a fixture with JSON.stringify fails the byte comparison on the indent
	# string rather than on anything under test.
	#
	# KEYS IN THE ORDER THE WRITER EMITS THEM, which is not fussiness: JSON preserves insertion
	# order and this check compares BYTES, so a fixture in any other order would fail for a reason
	# that has nothing to do with what is under test. Read it as a file Lothal itself wrote — which
	# is what the promise is about. The unrecognised keys lead, at both levels, because that is
	# where the unknown half goes back out.
	var fixture := {
		"weather": {"wind_mps": 4.0},
		"schema": 1,
		"selected": "bando",
		"sites": [{
			"surface": "concrete",
			"id": "bando",
			"name": "The bando",
			"elevation_m": 920.5,
			"terrain": {"shape": "flat", "width_m": 200.0, "length_m": 150.0},
			"obstacles": [],
			"migrated_temperature_c": 35.0,
		}],
	}
	JsonStore.write_document(SITES_PATH, fixture)
	var before := FileAccess.get_file_as_string(SITES_PATH)

	var loaded := SiteLibrary.load_from(SITES_PATH)
	loaded.save(SITES_PATH)
	var after := FileAccess.get_file_as_string(SITES_PATH)

	# CHECK 2. Bytes, not keys. A site's numbers are doubles all the way through — unlike a gate's
	# float32 Vector3 components, which is why the courses file can only promise its key set — so
	# byte-identity is available here and it is the strongest form of "we did not touch it".
	results.append(TestResult.new(
		"a site round-trips to a byte-identical file",
		before == after,
		"%d bytes in, %d bytes out, %s" % [
			before.length(), after.length(),
			"identical" if before == after else "CHANGED"]))

	# CHECK 3. Fields a later version wrote, at the top level and inside a site.
	var raw := JsonStore.read_document(SITES_PATH)
	var kept: Dictionary = {}
	for entry in (raw.get("sites", []) as Array):
		if (entry as Dictionary).get("id", "") == "bando":
			kept = entry
	results.append(TestResult.new(
		"fields a later version wrote survive a load and save, at the top level and inside a site",
		raw.has("weather") and String(kept.get("surface", "")) == "concrete",
		"kept top-level %s, and the site's surface = \"%s\"" % [
			"weather" if raw.has("weather") else "NOTHING", kept.get("surface", "")]))

	# The extent is read through terrain rather than off the site, because F3 puts a shape behind
	# that block and must not have to migrate this file to do it.
	var bando := loaded.site("bando")
	results.append(TestResult.new(
		"the extent comes out of the terrain block, so F3 can change its shape without a migration",
		bando != null and absf(bando.extent().x - 200.0) < 1.0e-9
			and absf(bando.extent().y - 150.0) < 1.0e-9,
		"nothing" if bando == null else "%.1f x %.1f m" % [bando.extent().x, bando.extent().y]))

	# CHECK 11. There has to be somewhere to fly. Removing the last site is allowed — an editor
	# that refuses is an editor with a site you can never get rid of — but it leaves the default
	# behind rather than an empty library, and the selection has to resolve.
	var emptied := SiteLibrary.with_default()
	emptied.put(_site_at("bando", 920.0))
	emptied.select("bando")
	emptied.remove(Site.DEFAULT_ID)
	emptied.remove("bando")
	results.append(TestResult.new(
		"removing the last site leaves the default field behind and a selection that resolves",
		emptied.ids().size() >= 1 and emptied.selected() != null
			and emptied.has(emptied.selected_id),
		"%d site(s), selected \"%s\" which %s" % [
			emptied.ids().size(), emptied.selected_id,
			"resolves" if emptied.selected() != null else "RESOLVES TO NOTHING"]))

	_forget(SITES_PATH)
	return results


static func _site_at(id: String, elevation_m: float) -> Site:
	var out := Site.new()
	out.site_id = id
	out.site_name = id
	out.elevation_m = elevation_m
	return out


# ---------------------------------------------------------------------------
# 3. courses.json v1 -> v2
# ---------------------------------------------------------------------------

## Two courses, at two different elevations, with two different footprints. Every property the
## migration has to hold is visible in this one fixture, and the fixture is the shape that is on a
## builder's disk today.
static func _v1_fixture() -> Dictionary:
	return {
		"schema": 1,
		"selected": "bando",
		"courses": [
			{
				"id": "bando", "name": "The bando",
				"air": {"elevation_m": 920.0, "temperature_c": 35.0},
				"gates": GateCourse.gates_to_data(_gates_spanning(10.0, 6.0)),
			},
			{
				"id": "leh", "name": "Leh",
				"air": {"elevation_m": 3500.0, "temperature_c": 5.0},
				"gates": GateCourse.gates_to_data(_gates_spanning(40.0, 80.0)),
			},
		],
	}


## Three gates whose bounding box is exactly `span_x` by `span_z`, so the margin arithmetic is
## checkable rather than approximately checkable.
static func _gates_spanning(span_x: float, span_z: float) -> Array[Dictionary]:
	return [
		{"position": Vector3(0.0, 2.0, 0.0), "normal": Vector3(0, 0, 1), "radius": 1.5},
		{"position": Vector3(span_x, 2.0, 0.0), "normal": Vector3(0, 0, 1), "radius": 1.5},
		{"position": Vector3(span_x, 2.0, span_z), "normal": Vector3(1, 0, 0), "radius": 1.5},
	]


static func _the_migration() -> Array:
	var results: Array = []
	_forget(SITES_PATH)
	_forget(COURSES_PATH)
	JsonStore.write_document(COURSES_PATH, _v1_fixture())

	var sites := SiteLibrary.migrate_courses(COURSES_PATH, SITES_PATH)
	var bando: Site = sites.site("site_bando") if sites != null else null
	var leh: Site = sites.site("site_leh") if sites != null else null

	# CHECK 5. ONE SITE PER COURSE, NEVER MERGED. Merging is one line, raises nothing, and throws
	# away whichever elevation loses — so the two courses in the fixture disagree on purpose.
	results.append(TestResult.new(
		"two courses at two elevations migrate to two sites, each keeping its own elevation",
		bando != null and leh != null
			and absf(bando.elevation_m - 920.0) < 1.0e-9
			and absf(leh.elevation_m - 3500.0) < 1.0e-9,
		"%s, %s" % [
			"no bando site" if bando == null else "bando at %.0f m" % bando.elevation_m,
			"no leh site" if leh == null else "leh at %.0f m" % leh.elevation_m]))

	# The temperature is not the site's — it is the conditions' (design §3.1) — so it is parked on
	# the site for F2 to consume rather than being thrown away here.
	results.append(TestResult.new(
		"and each course's temperature is parked for the conditions to pick up, not discarded",
		bando != null and leh != null
			and absf(float(bando.migrated_temperature_c) - 35.0) < 1.0e-9
			and absf(float(leh.migrated_temperature_c) - 5.0) < 1.0e-9,
		"bando %s C, leh %s C" % [
			"none" if bando == null else str(bando.migrated_temperature_c),
			"none" if leh == null else str(leh.migrated_temperature_c)]))

	# CHECK 6. The extent has to CONTAIN the course, on BOTH axes, with the margin on both. A
	# margin applied to width only gives a site whose far edge runs through a gate.
	var margin := SiteLibrary.MIGRATION_MARGIN_M
	var fits_x: bool = bando != null and bando.extent().x >= 10.0 + 2.0 * margin - 1.0e-6
	var fits_z: bool = bando != null and bando.extent().y >= 6.0 + 2.0 * margin - 1.0e-6
	results.append(TestResult.new(
		"a migrated site's extent contains every gate of its course plus the margin, on both axes",
		fits_x and fits_z,
		"none" if bando == null else "%.1f x %.1f m around a %.0f x %.0f m course (margin %.0f m)" % [
			bando.extent().x, bando.extent().y, 10.0, 6.0, margin]))

	# And the same for the big course, so a check that happened to pass on one shape is not the
	# whole of the evidence.
	var big_x: bool = leh != null and leh.extent().x >= 40.0 + 2.0 * margin - 1.0e-6
	var big_z: bool = leh != null and leh.extent().y >= 80.0 + 2.0 * margin - 1.0e-6
	results.append(TestResult.new(
		"and on a course that is longer than it is wide, so the two axes cannot be confused",
		big_x and big_z,
		"none" if leh == null else "%.1f x %.1f m around a 40 x 80 m course" % [
			leh.extent().x, leh.extent().y]))

	# CHECK 7. The course has to POINT at the site that was made for it, or the sites are orphans
	# and the course still has nowhere to be.
	var migrated := CourseLibrary.load_from(COURSES_PATH)
	var bando_course := migrated.course("bando")
	var leh_course := migrated.course("leh")
	results.append(TestResult.new(
		"each migrated course points at the site that was made for it",
		bando_course != null and leh_course != null
			and bando_course.site_id == "site_bando" and leh_course.site_id == "site_leh",
		"bando -> \"%s\", leh -> \"%s\"" % [
			"missing" if bando_course == null else bando_course.site_id,
			"missing" if leh_course == null else leh_course.site_id]))

	# CHECK 8. Lossless. Every id, every name, every gate count and every gate position survives.
	var v1: Dictionary = _v1_fixture()
	var kept := true
	var lost := ""
	for entry in (v1["courses"] as Array):
		var record: Dictionary = entry
		var id := String(record["id"])
		var course := migrated.course(id)
		if course == null:
			kept = false
			lost += "%s is gone; " % id
			continue
		var expected := GateCourse.gates_from_data(record["gates"])
		if course.course_name != String(record["name"]) or course.gates.size() != expected.size():
			kept = false
			lost += "%s changed shape; " % id
			continue
		for i in expected.size():
			if course.gates[i]["position"].distance_to(expected[i]["position"]) > 1.0e-4:
				kept = false
				lost += "%s gate %d moved; " % [id, i + 1]
	results.append(TestResult.new(
		"the migration is lossless: every course id, name, gate count and gate position survives",
		kept and migrated.ids().size() == 2,
		"%d course(s) out of 2%s" % [migrated.ids().size(), "" if lost == "" else "; " + lost]))

	# CHECK 10. ONE-WAY. Running the app a second time re-reads a v2 file, and a migration that
	# ignored the schema would lift an `air` block that is no longer there — which reads as
	# standard air and resets every elevation the first run just rescued.
	var second := SiteLibrary.migrate_courses(COURSES_PATH, SITES_PATH)
	var bando_again: Site = second.site("site_bando") if second != null else null
	results.append(TestResult.new(
		"a v2 file is not migrated again: no duplicate sites, and no elevation reset to zero",
		second != null and second.ids().size() == sites.ids().size()
			and bando_again != null and absf(bando_again.elevation_m - 920.0) < 1.0e-9,
		"%d site(s), bando at %s" % [
			0 if second == null else second.ids().size(),
			"nothing" if bando_again == null else "%.0f m" % bando_again.elevation_m]))

	results.append(TestResult.new(
		"and the file it left behind says schema 2",
		int(JsonStore.read_document(COURSES_PATH).get("schema", 0)) == 2,
		"schema %s" % JsonStore.read_document(COURSES_PATH).get("schema", "absent")))

	_forget(SITES_PATH)
	_forget(COURSES_PATH)
	return results


# ---------------------------------------------------------------------------
# 4. The course no longer carries the air, and no record was orphaned by that
# ---------------------------------------------------------------------------

static func _the_course_lost_its_air() -> Array:
	var results: Array = []

	# CHECK 9. Asserted on the property list rather than on a value, because "the air is standard"
	# passes against a course that still carries one.
	var course := GateCourse.new()
	results.append(TestResult.new(
		"a course no longer carries the air — the site does",
		not ("air" in course),
		"GateCourse %s" % ("STILL HAS an `air` property" if "air" in course else "has no `air` property")))

	results.append(TestResult.new(
		"and it carries a site id instead, defaulting to the default field",
		"site_id" in course and course.site_id == Site.DEFAULT_ID,
		"site_id = \"%s\"" % (course.site_id if "site_id" in course else "absent")))

	# CHECK 13. THE GOLDEN VALUE, called with NO ARGUMENT. This is what stands between this slice
	# and every best lap ever set: `fingerprint()` appends its rho term only when the air is
	# non-standard, and an absent argument has to mean standard. A default that meant anything else
	# would change every existing course's hash and orphan every record, silently — an orphaned
	# record looks exactly like no record. Slice F9 rests on this line.
	results.append(TestResult.new(
		"the default circuit's fingerprint with no air argument is still the pre-air value",
		course.fingerprint() == PRE_AIR_DEFAULT_FINGERPRINT,
		"%s (was %s)" % [course.fingerprint(), PRE_AIR_DEFAULT_FINGERPRINT]))

	# And explicitly standard air is the same thing as no air, or the two spellings would disagree
	# the first time a caller started passing the site's.
	results.append(TestResult.new(
		"and passing standard air explicitly gives the same hash as passing nothing",
		course.fingerprint(AirDensity.standard()) == course.fingerprint(),
		"%s vs %s" % [course.fingerprint(AirDensity.standard()), course.fingerprint()]))

	return results


# ---------------------------------------------------------------------------
# 5. The garage quotes the air of the place it is going to fly
# ---------------------------------------------------------------------------

## CHECK 12. RoomHost used to read `course_library.selected().air`. The course has none to give
## now, and the wrong fix — a hard-coded `AirDensity.standard()` — is invisible on a fresh install
## and wrong for everybody who has typed an elevation. So this poisons the REAL sites file, the
## way test_air_density's oracle section poisons the real courses file and for the same reason: a
## test that guards against reading real state has to CREATE the real state.
static func _the_garage_asks_the_site() -> Array:
	var results: Array = []

	var real_sites := SiteLibrary.SAVE_PATH
	var real_courses := CourseLibrary.SAVE_PATH
	var had_sites := FileAccess.file_exists(real_sites)
	var had_courses := FileAccess.file_exists(real_courses)
	var saved_sites := FileAccess.get_file_as_string(real_sites) if had_sites else ""
	var saved_courses := FileAccess.get_file_as_string(real_courses) if had_courses else ""

	var high := Site.new()
	high.site_id = "test_high_field"
	high.site_name = "Leh"
	high.elevation_m = 3500.0
	high.migrated_temperature_c = 30.0
	var library := SiteLibrary.with_default()
	library.put(high)
	library.select(high.site_id)
	library.save(real_sites)

	var courses := CourseLibrary.with_default()
	courses.selected().site_id = high.site_id
	courses.save(real_courses)

	var expected := AirDensity.new(3500.0, 30.0).kgm3()
	var host := RoomHost.new()
	var quoted := host.lab.air.kgm3()

	results.append(TestResult.new(
		"a 3500 m site really is selected and saved, so this check has something to fail on",
		absf(expected - AirDensity.standard_kgm3()) > 0.1,
		"the site's air is %.4f kg/m3 against %.4f at sea level" % [
			expected, AirDensity.standard_kgm3()]))
	results.append(TestResult.new(
		"the garage quotes the air of the SITE, not a hard-coded standard and not the course's",
		absf(quoted - expected) < 1.0e-12,
		"garage %.4f kg/m3, site %.4f kg/m3" % [quoted, expected]))

	host.free()

	# Put the builder's own files back. A test that left somebody's home field at 3500 m would be a
	# worse bug than any it could catch, and it would poison every suite that runs after it.
	_restore(real_sites, had_sites, saved_sites)
	_restore(real_courses, had_courses, saved_courses)
	return results


static func _restore(path: String, had_file: bool, contents: String) -> void:
	if had_file:
		var handle := FileAccess.open(path, FileAccess.WRITE)
		handle.store_string(contents)
		handle.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
