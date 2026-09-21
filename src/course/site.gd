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
## `parked_temperature_c` below is the one exception, and F2 has now landed on the other side of
## it. It had TWO writers — the v1 migration and the field editor's temperature spinbox — and
## nothing distinguished them, which is why F2 does the same thing with both:
## `ConditionsLibrary.absorb_parked_temperatures()` MOVES the value into a named set and clears
## this back to `null`.
##
## SINCE F2 THE FIELD EDITOR IS NO LONGER ONE OF THE WRITERS. Its spinbox selects the calm
## conditions set at the temperature typed, creating one if there is none, so a builder's
## temperature reaches the weather directly instead of via this slot. What is left here is the
## migration's, and it is drained at startup — the slot survives only because a v1 file on a
## builder's disk can still arrive on any future launch.
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
## THE BLOCK CARRIES A CENTRE AS WELL AS A SIZE, and the first version did not. A width and a
## length alone describe a rectangle with no position, which reads as "centred on the origin"
## whether or not anybody decided that — so a course laid out 100 m east of the origin migrated to
## a site containing none of its own gates. No error; the gates simply are not in the field. The
## centre is why `contains()` exists beside `extent()`, and F4 needs the same origin the moment
## `height_at(x, z)` becomes the ground authority, so this is a debt paid now rather than deferred.
##
## SINCE F3 IT IS A `Terrain`, AND THE FILE FORMAT DID NOT MOVE. The block on disk is the same five
## keys, with the shape's own numbers as siblings beside them; `Terrain` reads it, answers
## `height_at(x, z)` over it, and writes it back byte-identically. `extent()` was the seam and it
## held: its body changed and no caller did.

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
## The ground: `{"shape": "flat", "width_m": …, "length_m": …, "center_x_m": …, "center_z_m": …}`
## today, more behind the same key in F3. Read through `extent()`, `center()` and `contains()`,
## never reached into by a caller outside this file.
##
## EMPTY MEANS THE RECORD DID NOT HAVE ONE, which is different from a block saying "flat, 120 by
## 120". An empty block reads as the defaults and is not written back out — see `to_data()`.
var terrain: Terrain = flat_terrain(DEFAULT_WIDTH_M, DEFAULT_LENGTH_M)
## Whether the record this site came from carried a terrain block. The same statement-versus-
## silence split `_had_obstacles` makes: a block that was never in the file is not written back.
var _had_terrain := true
## What is standing in the field. F6 fills this; until then it is empty and round-trips untouched,
## which is what stops a builder on a later version losing theirs by opening this one.
var obstacles: Array = []
## Whether the record this site came from had an `obstacles` key at all. An empty list that WAS in
## the file is a statement — this field has nothing standing in it — and one that was never there
## is a question nobody asked; the two have to round-trip differently or the first save of a
## hand-edited file grows a key its author never wrote.
var _had_obstacles := true

## A temperature waiting for F2's conditions — parked by the v1 migration OR typed in the field
## editor; see the header, and do not assume the first. `null` means there is nothing parked, which
## is different from 15 °C, and the difference is the whole reason this is a Variant: writing 15.0
## into a record whose author never typed one would be manufacturing an authored fact.
var parked_temperature_c: Variant = null

## Everything the file held that this version does not recognise, kept so that opening an older
## build does not silently destroy a newer one's settings.
var _unknown: Dictionary = {}


static func flat_terrain(width_m: float, length_m: float,
		center_x_m := 0.0, center_z_m := 0.0) -> Terrain:
	return Terrain.flat(width_m, length_m, center_x_m, center_z_m)


## Width and length in metres. THE SEAM: F3 gives this a body that asks the terrain's shape, and
## no caller changes.
func extent() -> Vector2:
	return terrain.extent()


## Where the middle of the ground is, in world x and z. Zero for every site anybody authored by
## hand, and not zero for one the migration sized around a course that was laid out away from the
## origin. The second seam F3 and F4 need: a height at (x, z) is meaningless without it.
func center() -> Vector2:
	return terrain.center()


## Whether a point in the world is on this site's ground. Horizontal only — how high a gate is hung
## is the course's business, and a site is a patch of ground.
##
## Inclusive on the edge, deliberately: a gate exactly on the boundary of a field sized to contain
## it is contained, and a strict comparison would make the migration's own arithmetic fail its own
## test by a floating-point hair.
func contains(position: Vector3) -> bool:
	return terrain.contains(position.x, position.z)


## THERE IS NO `air()` HERE, AND THAT IS F2's ANSWER RATHER THAN AN OMISSION.
##
## F1 had one, and it read the parked temperature. It could not survive this slice: half of the
## air is not a fact about a place, so a site asked what air it is has to make the other half up,
## and the version that made it up out of the parking slot would go on quietly answering 15 °C for
## ever once F2 drained the slot. Ask `AirDensity.compose(site, conditions)` instead — the one
## place that knows which two typed facts the density comes from.
##
## NOT because of a class cycle. That reason was written here and it is false: `Conditions` names
## `AirDensity.STANDARD_TEMPERATURE_C` and `AirDensity.compose()` names `Conditions`, which is the
## same shape and compiles. A false constraint left in a comment steers a later slice away from
## something it is allowed to do, so it is corrected rather than quietly dropped.


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

const KNOWN_KEYS := ["id", "name", "elevation_m", "terrain", "obstacles",
	"parked_temperature_c"]


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

	# ABSENT RATHER THAN DEFAULTED. A record with no terrain block keeps an EMPTY one, so that
	# `to_data()` can put the file back exactly as it found it; `extent()` and `center()` read the
	# defaults out of the emptiness, which is the same answer without the invented key.
	var block: Variant = record.get("terrain")
	out._had_terrain = block is Dictionary and not (block as Dictionary).is_empty()
	out.terrain = Terrain.from_data(block) if out._had_terrain \
		else Terrain.flat(DEFAULT_WIDTH_M, DEFAULT_LENGTH_M)
	out._had_obstacles = record.has("obstacles")
	var standing: Variant = record.get("obstacles")
	if standing is Array:
		out.obstacles = (standing as Array).duplicate(true)

	var temperature: Variant = record.get("parked_temperature_c")
	if temperature is float or temperature is int:
		out.parked_temperature_c = float(temperature)

	out._unknown = JsonStore.unknown_fields(record, KNOWN_KEYS)
	return out


## The site as plain JSON values. The unknown half goes out first so the known keys land on top of
## it rather than being shadowed by a stale copy.
##
## THREE KEYS ARE MANDATORY AND THREE ARE NOT, and the split is a decision rather than an accident.
##
## `id`, `name` and `elevation_m` are always written. A site is a place; where it is is the one
## thing it must state, and 0 m is a statement and not a silence — it is precisely what every
## course saved before any of this existed was flown at.
##
## `terrain`, `obstacles` and `parked_temperature_c` are written only when there is something to
## write, on the "only what was authored is stored" rule. An empty obstacle list that CAME from the
## file is something to write — it says this field has nothing standing in it — and one that was
## never in the file is not. This matters because the alternative is that opening Lothal once adds
## two keys to every hand-edited record on a builder's disk: the quiet-rewrite failure the
## byte-identity test exists to prevent, arriving through the writer rather than through a number.
func to_data() -> Dictionary:
	var record := _unknown.duplicate(true)
	record["id"] = site_id
	record["name"] = site_name
	record["elevation_m"] = elevation_m
	if not _had_terrain:
		record.erase("terrain")
	else:
		record["terrain"] = terrain.to_data()
	if obstacles.is_empty() and not _had_obstacles:
		record.erase("obstacles")
	else:
		record["obstacles"] = obstacles.duplicate(true)
	if parked_temperature_c is float or parked_temperature_c is int:
		record["parked_temperature_c"] = float(parked_temperature_c)
	else:
		record.erase("parked_temperature_c")
	return record
