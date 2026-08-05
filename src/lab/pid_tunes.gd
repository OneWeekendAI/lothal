class_name PidTunes
extends RefCounted
## The builder's own PID gains, per build, surviving the app closing.
##
## ---------------------------------------------------------------------------
## THE DECISION: TUNING LIVES IN LAB (labs-and-sim.md §7, item 3, resolved)
## ---------------------------------------------------------------------------
##
## §7 asked where PID tuning belongs and said §1's rule did not cleanly settle it. It does, and the
## answer is Lab. The reasoning, in the order it mattered:
##
## 1. *§1's rule, applied properly.* "Does it change what the drone IS?" A tune is stored on the
##    flight controller, it persists across flights, and it changes how the aircraft behaves before
##    it leaves the ground. That is a property of the aircraft in exactly the way a propeller is.
## 2. *The objection does not survive contact with the rest of the app.* "A tune can only be judged
##    by flying" is true — and it is equally true of a propeller, a pack and a frame, all of which
##    are unambiguously Lab. Judging in the field and changing in the garage IS the loop; §2.1
##    already describes it for the component benches. If "only judgeable by flying" put a thing in
##    Sim, the parts rails would be in Sim.
## 3. *It is the real workflow, which is most of why the split exists at all.* Builders change gains
##    in a configurator on the bench, fly, land, and change them again. Nobody tunes mid-air.
##
## The corollary holds and is load-bearing: **Sim authors nothing.** Sim reads the tune it was
## handed and may not write one back. There is no in-flight tuning slider, and the absence is the
## boundary rather than an omission — if a future slice wants one, that want is the boundary saying
## something and should be listened to rather than routed around.
##
## ---------------------------------------------------------------------------
## PER BUILD, WHICH IS THE WHOLE POINT
## ---------------------------------------------------------------------------
##
## Keyed on Build.fingerprint() — all six part ids. A tune that followed the builder from a 65 mm
## whoop to a 10" long-range would recreate exactly the bug RateTune exists to fix, with their own
## numbers instead of the project's, which would be worse: they would have every reason to trust it.
##
## All six rather than the frame alone, because the plant is the whole aircraft. Same frame,
## different motors is a different thing to fly, and the frame bench measures it as one.
##
## ---------------------------------------------------------------------------
## THE FILE
## ---------------------------------------------------------------------------
##
## `user://pid_tunes.json`, under the four rules AssemblyTweaks set out and JsonStore now holds two
## of. Restated here only where this document's schema makes them concrete:
##
##     {
##       "schema": 1,
##       "tunes": {
##         "frame_5in_freestyle/motor_2207_1960kv/prop_5x43x3/battery_4s_1500/esc_.../fc_...": {
##           "roll": {"p": 2.8, "i": 0.18, "d": 0.05}
##         }
##       }
##     }
##
## - **Only what was SET is stored** — and here that means only the AXES the builder touched, and
##   only the builds they touched them on. An absent axis means "whatever the aircraft implies",
##   which is what lets the derived baseline follow a part change instead of freezing at the gains
##   the build happened to have the first time it was saved. It is also why a fresh install has no
##   file at all rather than a file full of the catalog's derived tunes.
## - **Unknown fields are kept, not dropped** — at both levels. A later Lothal with feedforward or
##   TPA will write keys this version has never heard of, and some of them will be inside a build's
##   own block. Both are read back out untouched.
## - **A bad file is not a fatal error.** Every failure mode lands on the derived tune, which is a
##   working aircraft. That matters more here than it does for a shim: a half-read gain is a flight
##   controller with a plausible-looking wrong number in it.
## - **Gains are stored as the three numbers a builder says out loud**, p/i/d per axis, in the same
##   normalised units the loop works in and the panel shows. Not as a scale factor against the
##   derived tune — a stored multiplier would silently mean something different the day the
##   derivation improved, which is the one thing a saved tune must never do.

const SAVE_PATH := "user://pid_tunes.json"
const SCHEMA_VERSION := 1
const TUNES_KEY := "tunes"

## fingerprint -> Dictionary of axis name -> {p, i, d}. Sparse at both levels.
var _stored: Dictionary = {}
## Everything this version did not recognise, kept verbatim for the next save. Top-level blocks and
## per-build entries are held separately because they go back to different places.
var _unknown_top: Dictionary = {}
## fingerprint -> Dictionary of the unrecognised keys inside that build's block.
var _unknown_per_build: Dictionary = {}


## The tune in force for `build`: the derived baseline, with whatever the builder saved on THIS
## build laid over it.
##
## A fresh object every call rather than a cached one, because a RateTune is mutable — the panel
## edits it in place — and handing two callers the same instance is how a screen and a flight loop
## come to disagree about what is installed.
func tune_for(build: Build) -> RateTune:
	var tune := RateTune.derive(build)
	var key := build.fingerprint()
	if _stored.has(key):
		tune.adopt_overrides(_stored[key])
	return tune


## Records what the builder has set on this build, and forgets the entry entirely when they have
## set nothing — so "reset to derived" leaves no residue in the file to be resurrected by a later
## version that reads it differently.
func remember(build: Build, tune: RateTune) -> void:
	var key := build.fingerprint()
	var overrides := tune.overrides_as_dictionary()
	if overrides.is_empty():
		_stored.erase(key)
		return
	_stored[key] = overrides


func forget(build: Build) -> void:
	_stored.erase(build.fingerprint())


func has_tune(build: Build) -> bool:
	return _stored.has(build.fingerprint())


func save(path: String = SAVE_PATH) -> bool:
	var tunes := {}
	for key in _stored:
		var block: Dictionary = (_unknown_per_build.get(key, {}) as Dictionary).duplicate(true)
		block.merge(_stored[key], true)
		tunes[key] = block
	# A build whose overrides were cleared but which a later version left keys on keeps those keys.
	# Dropping them would be this version deciding that a field it does not understand is worthless.
	for key in _unknown_per_build:
		if not tunes.has(key):
			tunes[key] = (_unknown_per_build[key] as Dictionary).duplicate(true)

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document[TUNES_KEY] = tunes
	return JsonStore.write_document(path, document)


static func load_from(path: String = SAVE_PATH) -> PidTunes:
	var tunes := PidTunes.new()

	var document := JsonStore.read_document(path)
	if document.is_empty():
		return tunes

	tunes._unknown_top = JsonStore.unknown_fields(document, [TUNES_KEY, "schema"])

	var stored: Variant = document.get(TUNES_KEY, {})
	if not (stored is Dictionary):
		push_warning("%s has no readable tunes block; using the derived tunes" % path)
		return tunes

	for key in (stored as Dictionary):
		var block: Variant = (stored as Dictionary)[key]
		if not (block is Dictionary):
			push_warning("%s: the entry for %s is not a tune; using the derived one" % [path, key])
			continue
		tunes._unknown_per_build[key] = JsonStore.unknown_fields(block, RateTune.AXIS_NAMES)
		var axes: Dictionary = {}
		for axis_name in RateTune.AXIS_NAMES:
			if (block as Dictionary).has(axis_name):
				axes[axis_name] = (block as Dictionary)[axis_name]
		# Per-axis shape and type checking is RateTune.adopt_overrides()' job, because it is the
		# thing that knows what a gain triple is. Anything it rejects simply is not an override,
		# which lands on the derived tune — a working aircraft.
		if not axes.is_empty():
			tunes._stored[key] = axes

	return tunes
