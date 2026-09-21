class_name Site
extends RefCounted
## A place you fly: a name, a patch of ground with an extent, a list of obstacles, and how high
## above sea level it sits. It owns its courses — a course is a lap route *inside* a site.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS, WHEN A COURSE ALREADY CARRIED ITS AIR
## ---------------------------------------------------------------------------
##
## Because laying out a second route at the same spot meant re-authoring the whole place, including
## its elevation — and the two copies silently disagreed the first time one of them was edited.
## That is the stale-reading failure `labs-and-sim.md` §2.6 and §2.4 each spend a section on,
## arriving through a third door. Site-owns-course closes it by construction: there is one bando,
## and three routes in it.
##
## ---------------------------------------------------------------------------
## ELEVATION LIVES HERE. TEMPERATURE DOES NOT.
## ---------------------------------------------------------------------------
##
## They look like a pair, because rho is a function of both. They are not one. Where a field sits
## above sea level is a fact about the PLACE, and it is the same on Tuesday as on Wednesday. How
## warm it is on the day is exactly the thing you switch when you ask what a build does on a hot
## afternoon — so it belongs to the conditions, which are switchable while the place and the route
## are held still.
##
## `migrated_temperature_c` below is the one exception, and it is a TEMPORARY one with an owner
## named: it is where a v1 course's typed temperature is parked so the migration does not have to
## throw it away before the conditions exist to receive it. F2 consumes it and clears it.
##
## ---------------------------------------------------------------------------
## THE TERRAIN IS A BLOCK FROM DAY ONE, THOUGH TODAY IT ONLY HOLDS TWO NUMBERS
## ---------------------------------------------------------------------------
##
## The extent could have been two floats on this object, and F3 could have moved them into a
## terrain block when it added real shapes. That would be the format decided twice that
## `course_library.gd`'s own header warns about — two schema shapes under one version number, and
## a migration to write for a file this slice has only just created. So the block is written now,
## `shape` says `flat`, and F3 fills in the rest behind `extent()` and `height_at()` without
## touching anybody's file.
##
## It is a plain Dictionary rather than a `Terrain` class because `Terrain` does not exist yet, and
## inventing an empty one to hold two numbers would be the class arriving before its behaviour.
## `extent()` is the seam: it exists from day one so that F3 changes its body and no caller.

const DEFAULT_ID := "default_site"
const DEFAULT_NAME := "Field"

## The only shape there is until F3. Named rather than spelled inline so the day a second shape
## arrives there is one place that knows what the first one was called.
const FLAT_SHAPE := "flat"

## The default field's extent. A chosen number, not a measured one: 120 m square is comfortably
## bigger than the 18 m default circuit and small enough to see the far edge of, which is the whole
## of the reasoning. A builder who cares types their own.
const DEFAULT_WIDTH_M := 120.0
const DEFAULT_LENGTH_M := 120.0

## Stable and machine-readable — what a library keys on and what a course's `site_id` names.
var site_id := DEFAULT_ID
## The builder's own. May be changed or duplicated without anything downstream noticing.
var site_name := DEFAULT_NAME
## Metres above sea level at the site's origin. Once terrain has relief (F3), the elevation at a
## gate is this plus `terrain.height_at(x, z)`.
var elevation_m := 0.0
## The ground: `{"shape": "flat", "width_m": …, "length_m": …}` today, more behind the same key
## in F3. Read through `extent()`, never reached into by a caller outside this file.
var terrain: Dictionary = flat_terrain(DEFAULT_WIDTH_M, DEFAULT_LENGTH_M)
## What is standing in the field. F6 fills this; until then it is empty and round-trips untouched,
## which is what stops a builder on a later version losing theirs by opening this one.
var obstacles: Array = []

## A v1 course's typed temperature, parked here by the migration for F2 to consume and clear.
## `null` means there is nothing parked — which is different from 15 °C, and the difference is the
## whole reason this is a Variant: writing 15.0 into a record whose author never typed one would be
## manufacturing an authored fact.
var migrated_temperature_c: Variant = null

## Everything the file held that this version does not recognise, kept so that opening an older
## build does not silently destroy a newer one's settings.
var _unknown: Dictionary = {}


static func flat_terrain(width_m: float, length_m: float) -> Dictionary:
	return {"shape": FLAT_SHAPE, "width_m": width_m, "length_m": length_m}


## Width and length in metres. THE SEAM: F3 gives this a body that asks the terrain's shape, and
## no caller changes.
func extent() -> Vector2:
	return Vector2(
		float(terrain.get("width_m", DEFAULT_WIDTH_M)),
		float(terrain.get("length_m", DEFAULT_LENGTH_M)))


## The air at this site, composed rather than stored (design §3.1). Two typed facts in, one number
## out, and one place that knows the formula.
##
## The temperature half is the parked migration value until F2 lands, and standard when there is
## nothing parked — which is the correct reading of a site nobody has told about its weather,
## exactly as an absent `air` block always read as 1.225.
func air() -> AirDensity:
	var temperature := AirDensity.STANDARD_TEMPERATURE_C
	if migrated_temperature_c is float or migrated_temperature_c is int:
		temperature = float(migrated_temperature_c)
	return AirDensity.new(elevation_m, temperature)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

const KNOWN_KEYS := ["id", "name", "elevation_m", "terrain", "obstacles",
	"migrated_temperature_c"]


## A site from a record. Anything unreadable falls back to the default for that field rather than
## dropping the site: a site is a PLACE, and a place with an unreadable extent is still somewhere
## the builder's courses point at. Dropping it would orphan every one of them.
static func from_data(data: Variant) -> Site:
	var out := Site.new()
	if not (data is Dictionary):
		return out
	var record: Dictionary = data

	out.site_id = String(record.get("id", DEFAULT_ID))
	out.site_name = String(record.get("name", out.site_id))
	var elevation: Variant = record.get("elevation_m", 0.0)
	if elevation is float or elevation is int:
		out.elevation_m = float(elevation)

	var block: Variant = record.get("terrain")
	if block is Dictionary:
		out.terrain = (block as Dictionary).duplicate(true)
	var standing: Variant = record.get("obstacles")
	if standing is Array:
		out.obstacles = (standing as Array).duplicate(true)

	var temperature: Variant = record.get("migrated_temperature_c")
	if temperature is float or temperature is int:
		out.migrated_temperature_c = float(temperature)

	out._unknown = JsonStore.unknown_fields(record, KNOWN_KEYS)
	return out


## The site as plain JSON values. The unknown half goes out first so the known keys land on top of
## it rather than being shadowed by a stale copy.
##
## `migrated_temperature_c` is written only when there is something parked, on the "only what was
## authored is stored" rule: writing 15.0 into a site whose author never typed a temperature would
## manufacture an authored fact, and F2 would then consume it as one.
##
## `obstacles` is written unconditionally, empty or not, and the difference is not an
## inconsistency. An empty obstacle list is a STATEMENT — this field has nothing standing in it —
## whereas an absent temperature is a question nobody has answered yet. The file format is new in
## this slice, so there is no older document for the empty array to appear in uninvited.
func to_data() -> Dictionary:
	var record := _unknown.duplicate(true)
	record["id"] = site_id
	record["name"] = site_name
	record["elevation_m"] = elevation_m
	record["terrain"] = terrain.duplicate(true)
	record["obstacles"] = obstacles.duplicate(true)
	if migrated_temperature_c is float or migrated_temperature_c is int:
		record["migrated_temperature_c"] = float(migrated_temperature_c)
	else:
		record.erase("migrated_temperature_c")
	return record
