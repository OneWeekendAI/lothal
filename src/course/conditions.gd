class_name Conditions
extends RefCounted
## The weather you fly a site in: a steady wind, the direction it comes from, how gusty it is, and
## how warm it is. A named, switchable set — because unlike the field, the weather is the thing you
## CHANGE while holding the place and the route still (design §3).
##
## ---------------------------------------------------------------------------
## WHY THE TEMPERATURE IS HERE AND THE ELEVATION IS NOT
## ---------------------------------------------------------------------------
##
## They look like a pair, because rho is a function of both. `site.gd`'s header spends a section on
## why they are not one, and this is the other half of it: where a field sits above sea level is
## the same on Tuesday as on Wednesday, and how warm it is is exactly what you switch when you ask
## what a build does on a hot afternoon. So the elevation stays on the place and the temperature
## travels with the weather, and `AirDensity.compose()` is the one place that puts them back
## together.
##
## The consequence is worth stating plainly rather than discovering: THE TEMPERATURE IS NOT PER
## SITE ANY MORE. Selecting "35 °C" and then walking to a different field gives you that field at
## 35 °C, which is the correct reading — a set of conditions is a question you are asking ("what
## does this build do when it is hot?"), not a property of the ground.
##
## ---------------------------------------------------------------------------
## FOUR AUTHORED FIELDS, AND A FIFTH IS A DESIGN CHANGE
## ---------------------------------------------------------------------------
##
## `wind_speed_mps`, `wind_from_deg`, `gustiness_mps`, `temperature_c`. Humidity is not here for
## `air_density.gd`'s measured reason; a turbulence length scale, a gust period and an air-pressure
## offset are all things somebody could want and none of them are things a builder can ANSWER, and
## a field nobody can fill honestly is a guess wearing a spinbox. `tests/test_conditions.gd`
## enumerates `to_data()`'s keys against a literal list so that a fifth arrives through the design
## rather than through a commit.
##
## `gustiness_mps` IS NOT A FREE CONSTANT. It is the amplitude of the gust process Sim runs, and
## Sim authors nothing: the number lives here, where a builder typed it, and the process reads it.
##
## `wind_from_deg` IS THE BEARING THE WIND COMES FROM — 0 = north, clockwise — which is the
## meteorological convention and the one every wind app a builder has ever looked at uses. The
## opposite convention (the direction it blows towards) is equally defensible and silently gives a
## build a tailwind where it should have a headwind, so it is named in the field and said here.

const STANDARD_ID := "standard"
const STANDARD_NAME := "Standard"

## Below this, a wind is not a wind. A CHOSEN number rather than an exact zero, because a set
## typed as 0.004 m/s is calm in every sense a pilot means and an exact comparison would call it
## weather. One centimetre per second is far below anything a 5" machine can respond to and far
## below anything a builder would type on purpose.
const CALM_TOLERANCE_MPS := 0.01

## Stable and machine-readable — what the library keys on.
var conditions_id := STANDARD_ID
## The builder's own. May be changed or duplicated without anything downstream noticing.
var conditions_name := STANDARD_NAME
## Steady wind speed in m/s at the site.
var wind_speed_mps := 0.0
## The bearing the wind COMES FROM, degrees, 0 = north, clockwise. See the header.
var wind_from_deg := 0.0
## The amplitude of the gust process, m/s. Authored here, read by Sim.
var gustiness_mps := 0.0
## How warm it is, °C. The temperature half of every density this app quotes.
var temperature_c := AirDensity.STANDARD_TEMPERATURE_C

## Everything the file held that this version does not recognise, kept so that opening an older
## build does not silently destroy a newer one's settings.
var _unknown: Dictionary = {}


## Still air at 15 °C: the air every number in this project was quoted in before any of this
## existed, and what a fresh install flies in.
static func standard() -> Conditions:
	return Conditions.new()


## Whether there is any air moving at all. The steady wind AND the gust amplitude, because a set
## with no steady wind and a 4 m/s gust amplitude is not calm — it is the worst kind of day.
func is_calm() -> bool:
	return absf(wind_speed_mps) < CALM_TOLERANCE_MPS and absf(gustiness_mps) < CALM_TOLERANCE_MPS


## Whether the STEADY wind — and only the steady wind — is saying anything. THE PREDICATE F9'S
## FINGERPRINT READS, and it exists because `is_calm()` is the wrong question for that one caller.
##
## `is_calm()` counts the gust amplitude, correctly: a day with no steady wind and a 4 m/s gust
## amplitude is not a still day. But only the steady speed and bearing reach the lap fingerprint —
## gustiness is deliberately not hashed (gate_course.gd's `fingerprint` says why). So gating the
## wind term on `is_calm()` would let a typed gust value open the gate, append `wind=0,0`, change
## the hash, and retire every best lap on the course by a side door, for a number that never
## touched the hash and never moved the steady wind.
##
## The tolerance is the same one: below a centimetre per second there is no steady wind to hash.
func has_steady_wind() -> bool:
	return absf(wind_speed_mps) >= CALM_TOLERANCE_MPS


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

const KNOWN_KEYS := ["id", "name", "wind_speed_mps", "wind_from_deg", "gustiness_mps",
	"temperature_c"]

## The four the builder authors, as distinct from the two that identify the set. The literal the
## suite checks `to_data()` against, kept here rather than in the test so that the design statement
## and the code are the same sentence.
const AUTHORED_KEYS := ["wind_speed_mps", "wind_from_deg", "gustiness_mps", "temperature_c"]


## A set from a record. An unreadable field falls back to its standard value rather than dropping
## the set, on `Site.from_data`'s rule: a named set of conditions is something the builder made,
## and losing it because one number was a string is a worse answer than reading that one number as
## still air.
##
## NOTHING IS NORMALISED ON THE WAY IN. A `wind_from_deg` of 370 is left at 370 rather than wrapped
## to 10, and a negative wind speed is left negative, because this file round-trips BYTES: wrapping
## on load means opening Lothal once rewrites a hand-edited file to say something its author did
## not write. Anything that cares about the domain clamps at the point of use, the way
## `AirDensity` clamps in its constructor.
static func from_data(data: Variant) -> Conditions:
	var out := Conditions.new()
	if not (data is Dictionary):
		return out
	var record: Dictionary = data

	out.conditions_id = String(record.get("id", STANDARD_ID))
	out.conditions_name = String(record.get("name", out.conditions_id))
	out.wind_speed_mps = _number(record.get("wind_speed_mps"), 0.0)
	out.wind_from_deg = _number(record.get("wind_from_deg"), 0.0)
	out.gustiness_mps = _number(record.get("gustiness_mps"), 0.0)
	out.temperature_c = _number(record.get("temperature_c"), AirDensity.STANDARD_TEMPERATURE_C)

	out._unknown = JsonStore.unknown_fields(record, KNOWN_KEYS)
	return out


## The set as plain JSON values. The unknown half goes out first so the known keys land on top of
## it rather than being shadowed by a stale copy — `Site.to_data()`'s arrangement, deliberately.
##
## EVERY KEY IS ALWAYS WRITTEN, where a site omits three of its six. The two files differ because
## the records do: a site's terrain block and obstacle list are things a builder may never have
## touched, and inventing them puts structure into a file nobody authored. A set of conditions has
## four numbers and nothing else; a set with no wind speed in it is not a set that said nothing
## about wind, it is a damaged record. So the four go out every time and the round-trip promise is
## about the bytes of what was there, not about which keys were.
func to_data() -> Dictionary:
	var record := _unknown.duplicate(true)
	record["id"] = conditions_id
	record["name"] = conditions_name
	record["wind_speed_mps"] = wind_speed_mps
	record["wind_from_deg"] = wind_from_deg
	record["gustiness_mps"] = gustiness_mps
	record["temperature_c"] = temperature_c
	return record


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback
