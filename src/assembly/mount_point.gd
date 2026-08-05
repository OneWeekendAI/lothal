class_name MountPoint
extends RefCounted
## A place on the aircraft where something attaches: where it is, how it holds on, and what it
## offers whatever is bolted or strapped to it.
##
## This is the vocabulary the project was missing. Before it existed the battery was hardcoded to
## the top plate and the flight controller had no physical presence at all, and those look like two
## unrelated gaps until you notice they are the same one: nothing in Lothal could say "here is a
## place where a thing attaches". Adding a second hardcoded position would have been a third
## instance of the same absence rather than a fix.
##
## A mount point is deliberately DUMB about what mounts to it. It knows its own geometry; the
## component knows its own requirements; fit is a comparison between the two (fit_warnings below).
## That is what lets one mechanism carry the stack, the pack, and — the day it exists — a payload,
## rather than three special cases that each know about one component.
##
## GEOMETRY-BEARING, NOT PHYSICS-BEARING. Same rule and same reasoning as the assembly tweaks
## (labs-and-sim.md §2.5): where a thing is mounted changes what clears what and changes nothing
## in the dynamics. The mass model is a lumped centre box plus four point masses and has no term a
## mount offset could enter, so no mount position reaches mass_properties(). When the mass model
## grows a real centre-of-gravity term these positions are already the single source for it; what
## must not happen is a second copy of a mount position living inside the physics.

## How a component is held on. Two, because there are two in a real build: things that bolt through
## a pattern of holes, and things a strap goes round.
const BOLT := "bolt"
const STRAP := "strap"

## Stable identifier, used by the saved configuration and by the panel. Not a label.
var id := ""
## What a builder calls this place.
var label := ""
var attachment := BOLT
## The bolt spacing as the catalog writes it ("30.5x30.5"), empty for a strap mount.
var pattern := ""
## The same spacing in metres, across X and along Z. Zero for a strap mount.
var pattern_m := Vector2.ZERO
## Where the mounted component's SEAT is, in the airframe's own space: the face it rests against,
## not the centre of whatever ends up there. The component's own height is added by whoever mounts
## it, which is what keeps this right for a 1.6 mm board and a 40 mm pack alike.
var position := Vector3.ZERO
## Which way the component grows from that seat: +1 up, -1 down. A bottom-plate strap mount faces
## down, and a pack on it hangs below the plate rather than sinking into it.
var normal := 1
## The surface this mount has to offer, across X and along Z, in metres. What a board has to fit
## inside before it is a board resting on air.
var span_m := Vector2.ZERO
## How far fore and aft a component on this mount may be slid before it is inside a propeller hub.
## The mount's own contribution to the travel; the component's length takes the rest of it, which
## is why a longer pack has less room (AssemblyTweaks.limits).
var reach_m := 0.0


## "30.5x30.5" -> (0.0305, 0.0305). Vector2.ZERO for anything that does not parse, which is the
## honest answer for a strap mount and for a frame whose contributor has not filled the field in —
## a fabricated spacing would read as a pattern that agrees with nothing.
static func parse_pattern_m(text: String) -> Vector2:
	var halves := text.split("x")
	if halves.size() != 2 or not halves[0].is_valid_float() or not halves[1].is_valid_float():
		return Vector2.ZERO
	return Vector2(float(halves[0]), float(halves[1])) / 1000.0


## What a component declares about how it attaches, read out of a catalog entry's `mounting` block
## with the defaults a part that says nothing implies. Static and here rather than in each caller,
## so "what does this part need" has one answer.
##
## `size_m` is not read from the block: a part's dimensions already live in `specs` and are already
## the one answer to how big it is (Build.battery_size_of). Whoever asks about fit passes the size
## they DREW, so the fit check and the picture stay the same geometry (labs-and-sim.md §2.2).
static func mounting_of(part: Dictionary) -> Dictionary:
	var block: Dictionary = part.get("mounting", {})
	return {
		"attachment": String(block.get("attachment", STRAP)),
		"pattern": String(block.get("pattern", "")),
	}


## What is wrong with putting this component here, in words. Empty when it fits.
##
## WARN, NEVER BLOCK (labs-and-sim.md §2.2). Zip-tying a 20x20 board onto a 30.5x30.5 stack is a
## thing real builders do on a Saturday afternoon, and the useful answer is "this does not bolt
## down and will need adapting", not a dropdown that has greyed itself out. Every condition below
## is a sentence a builder could act on.
##
## `size_m` is the component's drawn footprint in BODY axes (width across X, height up Y, length
## along Z), or Vector3.ZERO to skip the clearance half of the check.
## Severity follows the same rule as everywhere else (labs-and-sim.md §2.1): what the geometry
## REFUSES is impossible, what merely binds is limiting. A pattern that does not line up does not
## bolt down — that is a fact about two sets of holes. A board that bolts down but overhangs the
## plate is mounted, with its corners over air: a real trade-off a builder may accept.
func fit_warnings(part_name: String, mounting: Dictionary, size_m: Vector3 = Vector3.ZERO) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var wants: String = mounting.get("attachment", STRAP)

	if wants != attachment:
		if wants == BOLT:
			out.append(BuildWarning.impossible(&"mount_attachment",
				"%s bolts through a %s pattern, and %s has nothing to bolt into — it would have to be zip-tied or trayed." % [
					part_name, mounting.get("pattern", "?"), label],
				{"wants": wants, "offers": attachment, "mount": label}))
		else:
			out.append(BuildWarning.impossible(&"mount_attachment",
				"%s straps down, and %s is a bolt pattern — a strap has nothing to pass through there." % [
					part_name, label],
				{"wants": wants, "offers": attachment, "mount": label}))
		return out

	if attachment == BOLT:
		var wanted := parse_pattern_m(String(mounting.get("pattern", "")))
		if wanted == Vector2.ZERO or pattern_m == Vector2.ZERO:
			out.append(BuildWarning.limiting(&"mount_pattern_unknown",
				"%s does not say what pattern it is drilled for, so nothing here can confirm it lines up with %s." % [
					part_name, pattern if pattern != "" else "this mount"],
				{"mount": label, "mount_pattern": pattern}))
		elif (wanted - pattern_m).length() > 0.0005:
			out.append(BuildWarning.impossible(&"mount_pattern",
				"%s is drilled %s and %s is %s — it will not bolt down, and needs an adapter plate or soft mounts." % [
					part_name, mounting.get("pattern", "?"), label, pattern],
				{"part_pattern": str(mounting.get("pattern", "?")), "mount_pattern": pattern}))

		# A board wider than the plate it bolts to has its corners over open air. This is the
		# geometry half of "the patterns agree AND the geometry clears": a 30.5 stack is a 36 mm
		# board, and a 65 mm whoop's centre plate is 18 mm across.
		if size_m != Vector3.ZERO and span_m != Vector2.ZERO:
			var over_x := size_m.x - span_m.x
			var over_z := size_m.z - span_m.y
			var worst := maxf(over_x, over_z)
			if worst > 0.0005:
				out.append(BuildWarning.limiting(&"mount_overhang",
					"%s is %.0f mm across and %s offers %.0f mm — it overhangs the plate it is bolted to." % [
						part_name, maxf(size_m.x, size_m.z) * 1000.0, label,
						minf(span_m.x, span_m.y) * 1000.0],
					{"overhang_mm": worst * 1000.0, "plate_mm": minf(span_m.x, span_m.y) * 1000.0}))

	return out
