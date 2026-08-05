class_name AssemblyTweaks
extends RefCounted
## The builder's own adjustments to how the parts fit together, and the first CONFIGURATION in
## Lothal that survives closing the app. (Not the first write to user:// — LapTimer has kept a best
## lap there since day 6. That file is one scalar with no schema and no forward compatibility, which
## is fine for what it holds and not a pattern to grow persistent pack charge on, so the rules below
## are set out properly here. It does share the one rule that matters most: a corrupt save must not
## stop the app.)
##
## Real builders shim. A prop that sits too close to the arm gets a washer under it, a motor that
## buzzes gets a soft mount, a stack that will not close gets taller standoffs. None of that is a
## part you buy from the catalog; it is what you do to the parts you have. So it does not live in
## data/parts/ — those files are the shared, version-controlled catalog — and it is not a Build
## field either. It is per-user configuration, and it lives here.
##
## Three tweaks to start with: shim washers under the prop, a soft-mount pad under the motor, and
## the centre-plate standoff height. Since the mount points arrived, two more — WHERE the pack is
## strapped and how far fore or aft it sits on that mount. Those two are not dimensions of a part;
## they are which of the frame's mount points the pack is attached to, which is the same category
## of thing as a shim: it is what you did with the parts you have.
##
## ---------------------------------------------------------------------------
## THE DECISION: GEOMETRY ALWAYS, AND MASS WHERE THE TWEAK IS A POSITION
## ---------------------------------------------------------------------------
##
## Raising a prop 2 mm changes real-world clearance and changes nothing in this project's
## dynamics. Where a 185 g pack is strapped changes where the aircraft's mass is. Those are not the
## same kind of tweak, and this file used to treat them as one because when it was written there
## was only the first kind.
##
## **A tweak that is a SHIM changes the assembled geometry, what clears what, and every measurement
## taken off that geometry. It does not change mass, inertia, thrust, or any flight number.**
##
## **A tweak that is a POSITION — which mount the pack is on, how far along it is slid — does all of
## that AND moves the mass. It reaches the centre of mass and the inertia tensor. It does not reach
## the collective figures, because mass is mass wherever it sits.**
##
## The original reasoning, and what happened to each part of it:
##
## 1. *The physics had nowhere to put it.* True when written: the mass model was a lumped centre
##    box plus four point masses, with no term a 2 mm shim could enter. It now has one. Every
##    mounted part sits where MountLayout seats it, so a mount offset has somewhere to go that is
##    not invented — the pack's position is read from the same table that draws it.
## 2. *The oracles have to stay reproducible.* Still true, and still asserted. All-up weight,
##    thrust-to-weight and hover throttle do not move with any tweak wound to its limit; those are
##    collective figures and none of them depends on where the mass sits. What DOES move is inertia
##    and the centre of mass, which are properties of an aircraft's arrangement and are supposed to.
##    tests/test_assembly_tweaks.gd asserts both halves — the collective figures pinned, the
##    rotational ones moving — because an invariant with no counterpart would still pass if these
##    tweaks were disconnected at the wall.
## 3. *It is where the real consequence is anyway.* Half true, and the half that was wrong is why
##    this changed. Fit IS the real consequence of a shim. But the real consequence of sliding a
##    pack forward is a nose-heavy aircraft that needs differential thrust to hover level, and a
##    workbench that showed the pack hanging over the nose while the physics flew a balanced quad
##    was contradicting labs-and-sim.md §2.2 in the one place it is hardest to notice.
##
## The door this file left open is the one that got used: "when the mass model grows a real
## centre-of-gravity term, these values are already the single source for it. Nothing has to be
## re-decided; a consumer is added. What must NOT happen is a second copy of a shim height living
## in the physics." That held exactly. Build.mass_parts() reads MountLayout — the same table
## AirframeModel draws from — and there is no second copy of a mount position anywhere.
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
##       "tweaks": { "prop_spacer_mm": 1.5, "plate_gap_mm": 6.0,
##                   "battery_mount": "strap_bottom", "battery_offset_mm": -8.0 }
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
##   builder actually says out loud. Metres appear only at the geometry boundary (resolved_m). A
##   CHOICE is stored as the mount point's own id, not as an index — an index would silently mean
##   something else the day a frame gained a mount.
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

## Which of the frame's strap mounts the pack is on. A CHOICE rather than a dimension: the options
## are whatever the frame offers (FrameModel.mount_points_for), and a frame with no bottom plate to
## strap to simply does not offer one.
const BATTERY_MOUNT := "battery_mount"
## How far fore or aft the pack is slid on that mount, in millimetres. Positive is forward, and
## forward is -Z (physics.md §1).
const BATTERY_OFFSET := "battery_offset_mm"

## How well the props are balanced: the residual offset mass at the blade radius, in grams.
##
## A BUILD QUALITY PROPERTY, NOT A PART PROPERTY, which is why it is a tweak rather than a spec on
## the propeller. The same prop out of the same bag is balanced or not depending on what has
## happened to it since — a catalog figure would be asserting something about an object nobody has
## weighed. See VibrationModel, which is what reads it.
const PROP_IMBALANCE := "prop_imbalance_g"

## Keys whose value is a plain number the panel draws as a slider.
##
## Every one of these was a length in millimetres until prop imbalance arrived, which is a mass in
## grams — so `value_mm` is now a slightly wrong name for "the value in whatever unit its row is
## quoted in". The machinery underneath (clamping to limits, sparse overrides, persistence) never
## cared about the unit, and renaming the function across the panel and its tests is a bigger diff
## than this slice should carry. Noted rather than hidden.
const KEYS := [PROP_SPACER, SOFT_MOUNT, PLATE_GAP, BATTERY_OFFSET, PROP_IMBALANCE]
## Keys whose value is one of a set of named options rather than a number. Held separately because
## a slider and a dropdown are read, clamped and persisted differently — but the four file rules
## above apply to both without change.
const CHOICE_KEYS := [BATTERY_MOUNT]

## Labels and the unit suffix the UI shows. Here rather than in the panel so the panel has no
## opinion about what a tweak is, only about how to draw a row.
const ROWS := [
	{"key": PROP_SPACER, "label": "Prop spacer", "hint": "Washers on the shaft, under the prop."},
	{"key": SOFT_MOUNT, "label": "Motor soft mount", "hint": "Pad between the motor and the arm."},
	{"key": PLATE_GAP, "label": "Stack standoffs", "hint": "Height between the centre plates."},
	{"key": BATTERY_OFFSET, "label": "Pack fore/aft", "hint": "Slide the pack along the strap. Forward is positive."},
	{"key": PROP_IMBALANCE, "label": "Prop imbalance", "hint": "Residual offset mass per prop, in grams. Wind it up and watch the D term."},
]

## The choice rows, drawn as dropdowns rather than sliders. Same idea as ROWS and same reason: the
## panel knows how to draw a row and nothing about what a mount is.
const CHOICE_ROWS := [
	{"key": BATTERY_MOUNT, "label": "Pack mount", "hint": "Which plate the pack straps to."},
]

## Only the keys the builder has actually set. Sparse on purpose — see the file rules above.
var _overrides: Dictionary = {}
## Only the choice keys the builder has actually made. Sparse for the same reason and under the
## same rules; an absent key means "whatever the frame implies", not the first option.
var _choices: Dictionary = {}
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
		BATTERY_OFFSET: {
			"min": -battery_travel_mm(build),
			"max": battery_travel_mm(build),
			"default": 0.0,
		},
		# The only limits here that are AUTHORED rather than derived from the parts, and they are
		# authored because there is nothing to derive them from: no prop in the catalog publishes a
		# balance tolerance and none ever will. The range spans what a balancer can achieve at the
		# bottom to a prop with a visible nick at the top, and the default is a decently balanced
		# one — low, on gyro.gd's DEFAULT_NOISE_RAD_S precedent, so the stock aircraft flies clean
		# and winding it up is how a builder finds out what it does.
		PROP_IMBALANCE: {
			"min": 0.0,
			"max": 0.5,
			"default": VibrationModel.DEFAULT_IMBALANCE_KG * 1000.0,
		},
	}


## How far the pack may be slid fore or aft, in millimetres. The frame's own forward reach less
## half the pack's own length — both terms from the parts, neither from this file — so choosing a
## longer pack narrows the range while you watch, which is the §2.5 rule made arithmetic. Zero for
## a pack already as long as the frame reaches, which reads as "there is nowhere to slide it".
static func battery_travel_mm(build: Build) -> float:
	return maxf(
		FrameModel.mount_reach_m(build.arm_m) - build.battery_size_m().z * 0.5, 0.0) * 1000.0


## The named options each choice key offers on this build, and the option in force when nothing has
## been chosen. Derived from the frame, exactly as the numeric limits are derived from the parts: a
## frame with no room for strap slots under its bottom plate offers one option, and a 5" freestyle
## offers two. A list typed into the panel would be a second opinion about what the hardware allows.
static func mount_choices(build: Build) -> Dictionary:
	var options: Array[String] = []
	var labels: Array[String] = []
	for mount in FrameModel.mount_points_for(build.frame, -1.0):
		if mount.attachment == MountPoint.STRAP:
			options.append(mount.id)
			labels.append(mount.label)
	return {
		BATTERY_MOUNT: {
			"options": options,
			"labels": labels,
			# The first strap mount the frame lists, which is the top plate — where a pack goes if
			# nobody says otherwise, on every frame in the catalog.
			"default": options[0] if not options.is_empty() else "",
		},
	}


## Records a choice. Stored UNCLAMPED against the current frame, for the same reason a shim is:
## a pack mounted underneath a 5" freestyle has to still be underneath when you come back from
## trying it on a toothpick, and silently rewriting the builder's choice because a smaller frame is
## fitted is the same mistake in a different place.
func set_choice(key: String, value: String) -> void:
	if not CHOICE_KEYS.has(key):
		push_error("unknown assembly choice: %s" % key)
		return
	_choices[key] = value


func has_choice(key: String) -> bool:
	return _choices.has(key)


## The option in force for this build: what was chosen if this frame offers it, and the derived
## default otherwise.
func value_choice(key: String, build: Build) -> String:
	var row: Dictionary = mount_choices(build)[key]
	var chosen: String = String(_choices.get(key, ""))
	if (row["options"] as Array).has(chosen):
		return chosen
	return row["default"]


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
	_choices.erase(key)


func reset() -> void:
	_overrides.clear()
	_choices.clear()


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
		# Where the pack is strapped and how far along that mount it sits. The mount is an id
		# rather than a length, which is why this dictionary is not purely metres any more — but it
		# is still the ONE place the configuration crosses into the geometry, which is what the
		# name is really about.
		"battery_mount": value_choice(BATTERY_MOUNT, build),
		"battery_offset_m": value_mm(BATTERY_OFFSET, build) / 1000.0,
		# Grams, not metres — see PROP_IMBALANCE and the note on KEYS. It crosses here with the
		# rest because this is still the ONE place the configuration reaches the physics, which is
		# what the name is really about.
		"prop_imbalance_g": value_mm(PROP_IMBALANCE, build),
	}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Writes the file, preserving anything a later version of Lothal put in it. Returns false if the
## file could not be opened — the caller may report that, but nothing in Lab depends on it, since
## an unsaveable tweak is a lost preference and not a broken workbench.
func save(path: String = SAVE_PATH) -> bool:
	var tweaks := _unknown_tweaks.duplicate(true)
	for key in _overrides:
		tweaks[key] = _overrides[key]
	for key in _choices:
		tweaks[key] = _choices[key]

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["tweaks"] = tweaks

	return JsonStore.write_document(path, document)


## Reads the file, or returns defaults. Every failure mode lands in the same place on purpose:
## missing file, unreadable file, invalid JSON, JSON that is not an object, a "tweaks" block that
## is not an object, a key this version does not know, a value that is not a number. None of them
## can stop Lab from opening, and none of them can produce a half-populated configuration —
## anything not understood is simply not an override.
static func load_from(path: String = SAVE_PATH) -> AssemblyTweaks:
	var tweaks := AssemblyTweaks.new()

	# Every file-level failure — missing, unreadable, invalid JSON, JSON that is not an object —
	# comes back as an empty document from the one place that handles them.
	var document := JsonStore.read_document(path)
	if document.is_empty():
		return tweaks

	tweaks._unknown_top = JsonStore.unknown_fields(document, ["tweaks", "schema"])

	var stored: Variant = document.get("tweaks", {})
	if not (stored is Dictionary):
		push_warning("%s has no readable tweaks block; using defaults" % path)
		return tweaks

	for key in (stored as Dictionary):
		var value: Variant = (stored as Dictionary)[key]
		if CHOICE_KEYS.has(key):
			# A choice is a name, and a name that this version does not recognise is handled at
			# READ time by value_choice() rather than dropped here — the frame decides which names
			# are real, and the frame is not known yet.
			if value is String:
				tweaks._choices[key] = String(value)
			else:
				push_warning("%s: %s is not a name; using the default" % [path, key])
			continue
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
