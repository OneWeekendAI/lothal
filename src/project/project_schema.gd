class_name ProjectSchema
extends RefCounted
## What a project file is allowed to contain, and how it survives being changed.
##
## This class exists because of one honest admission: WE DO NOT YET KNOW WHAT GOES IN A PROJECT.
## Wiring, configuration, ground kit, printed parts and half of §3 of end-to-end.md are all going
## to want a home in this document, and several of them will want to change shape after their
## first version ships. A format that assumes it is finished is a format that starts losing
## builders' work the second time it changes.
##
## So the rules below are not tidiness. Each one is there to make a specific future edit safe.
##
## ---------------------------------------------------------------------------
## 1. TWO NUMBERS, AND THEY MEAN DIFFERENT THINGS
## ---------------------------------------------------------------------------
##
## `schema: {major, minor}`.
##
## - **Minor goes up when something is ADDED.** A new block, a new key, a new part category. An
##   older Lothal opening the file still understands every field it knows about, and carries the
##   ones it does not straight back out (rule 3). It opens.
## - **Major goes up when something CHANGES MEANING.** A field that used to be millimetres and is
##   now metres; a key whose absence used to mean one thing and now means another. An older Lothal
##   cannot read that correctly, and the only safe thing it can do is REFUSE — because the failure
##   mode of guessing is a drone silently described wrong, which is the one failure this project
##   is not allowed to have.
##
## Refusing to open is a real cost and it is the smaller one. A major bump is therefore a decision
## somebody makes deliberately, and the migration ladder (rule 4) exists so it is rarely needed.
##
## An `int` is accepted where the object is expected, and read as that major with minor 0. Every
## other document in Lothal writes `"schema": 1`, and a format that cannot read the convention its
## own codebase uses would be an odd thing to ship.
##
## ---------------------------------------------------------------------------
## 2. DENSE WHERE ABSENCE IS AMBIGUOUS, SPARSE WHERE ABSENCE IS USEFUL
## ---------------------------------------------------------------------------
##
## These two rules look contradictory and are not. They are the same question — *what does a
## missing key mean?* — answered per block, by whether the answer is knowable.
##
## **`parts` is written DENSE.** Every category this version knows is written, including the ones
## that are not fitted (as ""). The reason is the case that will actually happen: a GPS category
## is added next month, and a file written today has no `gps` key. If absent meant "fit the
## default", every project a builder already owns silently gains a GPS receiver and a few grams —
## the app would change their aircraft without being asked. Writing every known category densely
## makes absence unambiguous: **an absent category is one the writer had never heard of, and
## nothing is fitted for it.** Adding a category is then a data change with no migration at all.
##
## **`assembly`, `tune`, `air` and `printing` are SPARSE.** Here absence has a genuinely useful
## meaning: "whatever the parts imply". An absent `plate_gap_mm` follows the frame you chose
## instead of freezing at the number some other frame happened to have, and an absent tune axis
## re-derives when you swap the airframe. That is a feature, and it is the rule AssemblyTweaks and
## PidTunes already live by.
##
## ---------------------------------------------------------------------------
## 3. NOTHING UNRECOGNISED IS EVER DESTROYED
## ---------------------------------------------------------------------------
##
## A file written by a later Lothal will contain blocks and keys this one has never heard of. They
## are read out, held, and written back untouched — **at every level of nesting**, not just the
## top. Open a 0.6 project in 0.4, rename it, save: the wiring block a later version put in it is
## still there.
##
## This is what makes "add something and see if it works" a safe way to develop the format. A
## field can be added on a branch, written by that branch, and survive the builder going back to
## a release build in between.
##
## ---------------------------------------------------------------------------
## 4. MIGRATIONS ARE A LADDER, AND THE LADDER IS INJECTABLE
## ---------------------------------------------------------------------------
##
## When meaning does change, a migration rewrites the old document into the new shape on load, one
## rung at a time, in order. `migrate()` takes the ladder as an argument, defaulting to the real
## one — which is presently EMPTY, because nothing has changed meaning yet.
##
## An empty ladder is exactly the situation in which migration machinery gets written, shipped,
## never executed, and turns out to be broken the first time it matters. So it is injectable, and
## the suite drives it with synthetic rungs that prove the ordering, the stopping condition and
## the refusal — a test that would pass against a `migrate()` returning its argument unchanged
## would be worth nothing, and this one does not.

## Bumped when a field is ADDED. Old Lothals still open the file.
##
## 1 (P10f, 2026-09-08): `guard` joined the optional categories. An older Lothal reading a file
## that names one ignores the key and opens the aircraft without its guard, which is the correct
## outcome for a version that has no guard physics at all — and is exactly why an added field is a
## MINOR bump rather than a major one.
##
## 2 (C1, 2026-09-21): the `config` decision block joined `decisions`. An older Lothal reading a
## file that carries one keeps the block intact (rule 3) and flies the aircraft with none of it
## applied — which is the correct outcome for a version with no config model at all, and is the
## same argument `guard` made at minor 1.
const SCHEMA_MINOR := 2
## Bumped when a field CHANGES MEANING. Old Lothals refuse the file.
const SCHEMA_MAJOR := 1

## The six categories an aircraft cannot fly without. There is no "not fitted" for these: a quad
## with no flight controller is not a build with something missing, it is not an aircraft.
const REQUIRED_CATEGORIES := ["frame", "motor", "propeller", "battery", "esc", "flight_controller"]

## The categories that may be left off. "" means the builder said no; see rule 2 for why that is
## not the same as the key being absent.
##
## ADDING A CATEGORY IS A ONE-LINE CHANGE HERE. Rule 2 is what makes it a one-line change: every
## existing file gets "" for it, because their writer had never heard of it.
##
## `guard` arrived with P10f and is the first entry that proves the claim on a real category: every
## project file written before it exists reopens with no guard fitted, which is the aircraft it was
## saved as. It is NOT one of `Build.OPTIONAL_COMPONENTS` — those four are a payload the mass model
## weighs from a dictionary, and the guard is a trailing argument to `Build.from_ids` because it is
## the one optional part that also changes the aerodynamics. `Project.to_build` pulls it out of the
## components block and hands it over separately for that reason.
## `gps` and `buzzer` arrived with C2 and are registered here by C4 rather than by C5, which the
## plan had owning this line. C4 asserts that every member of `Build.OPTIONAL_COMPONENTS` persists,
## and that assertion is red for both of them until this list names them — so the slice that makes
## the claim is the slice that has to make it true. C5 still owns the persistence BEHAVIOUR: the
## round trip, the pre-existence fixture, and "" versus absent.
const OPTIONAL_CATEGORIES := ["camera", "vtx", "antenna", "receiver", "guard", "gps", "buzzer"]

## Sparse blocks under `decisions`. Named here rather than in Project so that adding a block is a
## data change in one place — the unknown-field carry, the round trip and the defaults all read
## this list.
## `config` (C1) is SPARSE like its four neighbours, and for the same reason: absence means "the
## app's default", so a builder who never opened the Config room gets today's behaviour, and a
## default that later changes follows rather than freezing at the value some build happened to
## have. It has no key whitelist — C2..C9 each add keys to it without this list changing.
const DECISION_BLOCKS := ["parts", "assembly", "tune", "air", "printing", "config"]

const TOP_KEYS := ["schema", "project_id", "name", "created_at", "updated_at", "lothal_version",
	"decisions", "versions", "prints", "notes"]


static func all_categories() -> Array:
	var out: Array = []
	out.append_array(REQUIRED_CATEGORIES)
	out.append_array(OPTIONAL_CATEGORIES)
	return out


static func current_version() -> Dictionary:
	return {"major": SCHEMA_MAJOR, "minor": SCHEMA_MINOR}


## Reads a `schema` value in either shape. A missing or unreadable one is treated as the CURRENT
## version rather than as version zero: a document with no schema block is one this version wrote
## before the field existed, or one somebody hand-edited, and neither deserves to be run through
## every migration ever written.
static func read_version(value: Variant) -> Dictionary:
	if value is int or value is float:
		return {"major": int(value), "minor": 0}
	if value is Dictionary:
		var major: Variant = (value as Dictionary).get("major", SCHEMA_MAJOR)
		var minor: Variant = (value as Dictionary).get("minor", 0)
		if (major is int or major is float) and (minor is int or minor is float):
			return {"major": int(major), "minor": int(minor)}
	return current_version()


## Whether this Lothal can read a document at `version` at all. Minor ahead is fine — rule 3 keeps
## the parts it does not understand intact. Major ahead is not, and the answer is no rather than a
## guess.
static func can_read(version: Dictionary) -> bool:
	return int(version.get("major", SCHEMA_MAJOR)) <= SCHEMA_MAJOR


## Runs `document` up the ladder until it is at the current major. Each rung is
## `{"from_major": int, "note": String, "apply": Callable}` and is applied at most once, in order.
##
## `ladder` is injectable for the reason in rule 4: the real ladder is empty, and empty machinery
## that has never run is machinery nobody has checked.
static func migrate(document: Dictionary, version: Dictionary, ladder: Array = MIGRATIONS) -> Dictionary:
	var out := document
	var major := int(version.get("major", SCHEMA_MAJOR))
	for rung in ladder:
		var from_major := int((rung as Dictionary).get("from_major", -1))
		if from_major != major:
			continue
		var apply: Variant = (rung as Dictionary).get("apply")
		if not (apply is Callable):
			push_warning("migration from schema %d has no apply(); stopping" % from_major)
			break
		out = (apply as Callable).call(out)
		major += 1
	return out


## The real ladder. EMPTY, DELIBERATELY, and it is meant to stay short: rule 2 means adding a
## field or a part category needs no rung at all. A rung here is a record that something once
## meant a different thing.
const MIGRATIONS: Array = []


## A new project id: 26 lowercase base32 characters, the first 10 encoding the creation time in
## milliseconds so a directory listing sorts into creation order for free.
##
## Not Build.fingerprint(), and the difference matters. Fingerprint joins six part ids and answers
## "which aircraft is this, physically" — swap the pack and it changes, which is correct for a
## physics question and wrong for a document: a project that changed identity when you fitted a
## different battery could not be renamed, versioned or duplicated coherently.
static func new_id(now_ms: int = -1) -> String:
	const ALPHABET := "0123456789abcdefghjkmnpqrstvwxyz"
	var ms := now_ms if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var out := ""
	for i in 10:
		out = ALPHABET[ms % 32] + out
		ms /= 32
	for i in 16:
		out += ALPHABET[randi() % 32]
	return out
