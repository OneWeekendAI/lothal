class_name AssemblyTweaks
extends RefCounted
## The builder's own adjustments to how the parts fit together, and the first thing in Lothal
## that survives closing the app.
##
## Real builders shim. A prop that sits too close to the arm gets a washer under it, a motor that
## buzzes gets a soft mount, a stack that will not close gets taller standoffs. None of that is a
## part you buy from the catalog; it is what you do to the parts you have. So it does not live in
## data/parts/ — those files are the shared, version-controlled catalog — and it is not a Build
## field either. It is per-user configuration, and it lives here.
##
## Three tweaks, deliberately: shim washers under the prop, a soft-mount pad under the motor, and
## the centre-plate standoff height. The set is small because the point of this slice is to
## establish the pattern, not to expose every dimension in the project.
##
## ---------------------------------------------------------------------------
## THE DECISION: THESE ARE GEOMETRY-BEARING, NOT PHYSICS-BEARING
## ---------------------------------------------------------------------------
##
## Raising a prop 2 mm changes real-world clearance and changes nothing in this project's
## dynamics. Both halves of that sentence needed a decision rather than a default, so:
##
## **A tweak changes the assembled geometry, what clears what, and every measurement taken off
## that geometry. It does not change mass, inertia, thrust, or any flight number.**
##
## Three reasons, in the order they mattered.
##
## 1. *The physics has nowhere to put it.* physics.md's mass model is a lumped centre box plus
##    four point masses; it has no term a 2 mm shim could enter. Feeding one in would mean
##    inventing a moment arm the model does not claim to resolve — precision the numbers have not
##    earned, which is the failure physics.md is written to prevent.
## 2. *The oracles have to stay reproducible.* The reference build's 11.7:1 and 29% hover are the
##    project's fixed points. If a slider on a panel could move them, then every figure Lothal
##    reports would be a function of one user's saved file, and no two people could compare
##    anything. tests/test_assembly_tweaks.gd asserts the numbers do not move with all three
##    tweaks wound to their limits.
## 3. *It is where the real consequence is anyway.* The thing a shim actually changes is fit —
##    whether the blade roots clear the bell, whether the props clear the arms — and fit is what
##    Lab measures off the generated geometry (labs-and-sim.md §2.2, "the render is the
##    engineering check"). So the tweak lands exactly where its real effect is.
##
## The door that leaves open: when the mass model grows a real centre-of-gravity term, or a
## clearance warning starts reading the vertical gap, these values are already the single source
## for it. Nothing has to be re-decided; a consumer is added. What must NOT happen is a second
## copy of a shim height living in the physics.
##
## ---------------------------------------------------------------------------
## THE FILE
## ---------------------------------------------------------------------------
##
## `user://assembly_tweaks.json`, which is Godot's per-user writable location (on macOS,
## ~/Library/Application Support/Godot/app_userdata/Lothal/). Not res://, which is read-only in an
## exported build, and not data/parts/, which is the catalog.
##
##     {
##       "schema": 1,
##       "tweaks": { "prop_spacer_mm": 1.5, "plate_gap_mm": 6.0 }
##     }
##
## Four rules, chosen now because persistent pack charge lands in this same file later and a
## format decided twice is a format that disagrees with itself:
##
## - **Only what was SET is stored.** An absent key means "whatever the parts imply", not zero.
##   That is what lets a default follow the frame you chose instead of freezing at the value the
##   frame happened to have the first time the file was written.
## - **Unknown fields are kept, not dropped.** A file written by a later version of Lothal will
##   contain tweaks this version has never heard of. They are read back out untouched on save, so
##   opening an older build does not silently destroy a newer one's settings.
## - **A bad file is not a fatal error.** Missing, truncated, invalid JSON, valid JSON of the
##   wrong shape, or a value of the wrong type: each loads as defaults. Lab opens. A workbench
##   that will not start because a preferences file is half-written has made a preference more
##   important than the product.
## - **Values are stored in millimetres**, matching the catalog's own units and the numbers a
##   builder actually says out loud. Metres appear only at the geometry boundary (resolved_m).
##
## `schema` is written but not yet branched on — there is one version. It exists so a future
## change of meaning (as opposed to a new field, which the unknown-field rule already handles)
## has somewhere to declare itself.

const SAVE_PATH := "user://assembly_tweaks.json"
const SCHEMA_VERSION := 1

## Shim washers between the prop adapter and the prop.
const PROP_SPACER := "prop_spacer_mm"
## The anti-vibration pad between the arm-tip pad and the motor.
const SOFT_MOUNT := "soft_mount_mm"
## Standoff height between the two centre plates.
const PLATE_GAP := "plate_gap_mm"

const KEYS := [PROP_SPACER, SOFT_MOUNT, PLATE_GAP]

## Labels and the unit suffix the UI shows. Here rather than in the panel so the panel has no
## opinion about what a tweak is, only about how to draw a row.
const ROWS := [
	{"key": PROP_SPACER, "label": "Prop spacer", "hint": "Washers on the shaft, under the prop."},
	{"key": SOFT_MOUNT, "label": "Motor soft mount", "hint": "Pad between the motor and the arm."},
	{"key": PLATE_GAP, "label": "Stack standoffs", "hint": "Height between the centre plates."},
]

## Only the keys the builder has actually set. Sparse on purpose — see the file rules above.
var _overrides: Dictionary = {}
## Everything in the loaded file this version did not recognise, kept verbatim for the next save.
## Top-level blocks and unknown entries under "tweaks" are held separately because they go back
## to different places.
var _unknown_top: Dictionary = {}
var _unknown_tweaks: Dictionary = {}


# ---------------------------------------------------------------------------
# Limits, derived from the parts
# ---------------------------------------------------------------------------

## Every tweak's minimum, maximum and default for a given build, in millimetres.
##
## Nothing here is authored. The shim range is the spare thread the motor's shaft actually has
## above its adapter; the pad range is the mounting boss the screws thread into; the standoff
## range runs from one plate thickness (below which the two plates are one plate) up to a
## fraction of the centre plate's own width (beyond which the stack is taller than the airframe
## is wide, and it is not a quadcopter any more). Each of those comes from the class that draws
## the part, so there is one copy of the arithmetic rather than one here and one on screen.
static func limits(build: Build) -> Dictionary:
	return {
		PROP_SPACER: {
			"min": 0.0,
			"max": MotorMesh.max_prop_spacer_m(build.motor) * 1000.0,
			"default": 0.0,
		},
		SOFT_MOUNT: {
			"min": 0.0,
			"max": MotorMesh.max_soft_mount_m(build.motor) * 1000.0,
			"default": 0.0,
		},
		PLATE_GAP: {
			"min": FrameModel.min_plate_gap_m() * 1000.0,
			"max": FrameModel.max_plate_gap_m(build.arm_m) * 1000.0,
			"default": FrameModel.default_plate_gap_m() * 1000.0,
		},
	}


# ---------------------------------------------------------------------------
# Reading and writing values
# ---------------------------------------------------------------------------

func has_override(key: String) -> bool:
	return _overrides.has(key)


## Records a value, in millimetres. Stored UNCLAMPED, deliberately: a shim that is legal on a 2807
## and too tall for an 0802 has to come back when the 2807 goes back on. Lab never blocks a part
## choice either (labs-and-sim.md §2, "warnings, not blocks") and silently rewriting the builder's
## number because a smaller motor is currently fitted is the same mistake in a different place.
func set_mm(key: String, millimetres: float) -> void:
	if not KEYS.has(key):
		push_error("unknown assembly tweak: %s" % key)
		return
	_overrides[key] = millimetres


## Back to what the parts imply, for one tweak or for all of them.
func clear(key: String) -> void:
	_overrides.erase(key)


func reset() -> void:
	_overrides.clear()


## The value in force for this build: what was set, clamped to what this build's hardware allows,
## or the derived default if nothing was set.
func value_mm(key: String, build: Build) -> float:
	var row: Dictionary = limits(build)[key]
	if not _overrides.has(key):
		return row["default"]
	return clampf(float(_overrides[key]), row["min"], row["max"])


## The three values in metres, under the names the geometry classes take them by. This is the only
## place the tweaks cross into the geometry, and it is the reason FrameModel and MotorMesh take
## plain floats rather than this object: a mesh generator that could reach into settings is a mesh
## generator that can be given two sources of truth.
func resolved_m(build: Build) -> Dictionary:
	return {
		"prop_spacer_m": value_mm(PROP_SPACER, build) / 1000.0,
		"soft_mount_m": value_mm(SOFT_MOUNT, build) / 1000.0,
		"plate_gap_m": value_mm(PLATE_GAP, build) / 1000.0,
	}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Writes the file, preserving anything a later version of Lothal put in it. Returns false if the
## file could not be opened — the caller may report that, but nothing in Lab depends on it, since
## an unsaveable tweak is a lost preference and not a broken workbench.
func save(path: String = SAVE_PATH) -> bool:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		push_warning("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	var tweaks := _unknown_tweaks.duplicate(true)
	for key in _overrides:
		tweaks[key] = _overrides[key]

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["tweaks"] = tweaks

	handle.store_string(JSON.stringify(document, "  "))
	handle.close()
	return true


## Reads the file, or returns defaults. Every failure mode lands in the same place on purpose:
## missing file, unreadable file, invalid JSON, JSON that is not an object, a "tweaks" block that
## is not an object, a key this version does not know, a value that is not a number. None of them
## can stop Lab from opening, and none of them can produce a half-populated configuration —
## anything not understood is simply not an override.
static func load_from(path: String = SAVE_PATH) -> AssemblyTweaks:
	var tweaks := AssemblyTweaks.new()
	if not FileAccess.file_exists(path):
		return tweaks

	# JSON.new().parse rather than JSON.parse_string: the latter prints an engine-level ERROR line
	# for a malformed document, and a tolerated condition must not look like a failure in the test
	# runner's output.
	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("%s is not valid JSON (line %d: %s); using defaults" % [
			path, reader.get_error_line(), reader.get_error_message()])
		return tweaks

	var parsed: Variant = reader.data
	if not (parsed is Dictionary):
		push_warning("%s is not a tweaks document; using defaults" % path)
		return tweaks

	var document: Dictionary = parsed
	for key in document:
		if key != "tweaks" and key != "schema":
			tweaks._unknown_top[key] = document[key]

	var stored: Variant = document.get("tweaks", {})
	if not (stored is Dictionary):
		push_warning("%s has no readable tweaks block; using defaults" % path)
		return tweaks

	for key in (stored as Dictionary):
		var value: Variant = (stored as Dictionary)[key]
		if not KEYS.has(key):
			tweaks._unknown_tweaks[key] = value
			continue
		# A value of the wrong type is treated as absent rather than coerced. float("thick") is
		# 0.0, and a silent zero is indistinguishable from a deliberate one.
		if value is float or value is int:
			tweaks._overrides[key] = float(value)
		else:
			push_warning("%s: %s is not a number; using the default" % [path, key])

	return tweaks
