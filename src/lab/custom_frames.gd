class_name CustomFrames
extends CustomParts
## The frames a builder entered themselves. Read CustomParts first: the id space, the shared
## document, the refusals that are not about frames and the degradation rules all live there.
## What is left here is what is actually about a FRAME.
##
## A person holding a frame Lothal does not stock should be able to put its numbers in and get a
## trustworthy aircraft out. Nothing about that needs new geometry: FrameModel is procedural off
## `arm_mm` alone, so a 350 mm frame draws correctly with zero rendering work.
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
## ---------------------------------------------------------------------------
## WHAT IS REFUSED, AND WHY SO LITTLE IS
## ---------------------------------------------------------------------------
##
## On top of CustomParts' generic list, exactly one thing: a missing or non-positive `arm_mm`.
## That is a case where there is no aircraft to draw or fly — FrameModel divides by arm_mm.
##
## Everything else warns. A 900 mm arm, a 4 g 10" frame, a prop that geometrically cannot fit
## between its neighbours: all of those are aircraft, they are just surprising ones, and
## labs-and-sim.md §2 is explicit that Lab warns and never blocks. The bounds themselves live in
## FramePlausibility, next to the build that carries them, not here — this file decides what is a
## FRAME, not what is a SENSIBLE frame.

const FRAMES_KEY := "frames"

## The three appearances FrameModel._material_for actually distinguishes, in its own words. Offered
## as a closed list rather than free text for one reason: the renderer substring-matches on
## "carbon" and "nylon" and gives everything else a neutral grey, so a fourth option would be a
## word on screen that changes nothing about the picture. Values are what goes in
## catalog.material, and they read the way the shipped catalog's do.
const MATERIALS := ["carbon fibre", "injection-moulded nylon (PA12)", "unspecified"]


func array_key() -> String:
	return FRAMES_KEY


func category() -> String:
	return "frame"


## Reads as `frames()` at every call site that existed before there was more than one category,
## and reads better than `records()` at the ones written since. Both are the same array.
func frames() -> Array:
	return records()


func get_frame(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomFrames:
	var doc := CustomFrames.new()
	doc.read_from(path)
	return doc


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


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "frame")


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
# The one frame-specific refusal
# ---------------------------------------------------------------------------

func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []
	var specs: Variant = record.get("specs", null)
	if not (specs is Dictionary) or not (specs as Dictionary).has("arm_mm"):
		problems.append("specs.arm_mm (centre to motor, in mm) is required — the whole frame is drawn from it")
	elif float((specs as Dictionary)["arm_mm"]) <= 0.0:
		problems.append("specs.arm_mm must be positive — at zero there is no geometry to draw")
	return problems
