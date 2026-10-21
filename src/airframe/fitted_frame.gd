class_name FittedFrame
extends RefCounted
## The fitted frame as ONE object: the document the Airframe pages draw, and the frame the physics
## flies. Before this file they were two: the designer opened on a generated Quad X (77 g) while
## the Frame row and the mass model read the catalogue's weighed 110 g, the Screws & standoffs row
## flagged a hole on a frame nobody had fitted, and an edit in the designer never reached the
## aircraft. The builder's ruling was "whatever is closer to the real world" — so the fitted
## frame's document is the single source, and this file is the one place it turns into physics.
##
## ## What flies, and why it is a DELTA on the weighed figure
##
## The document is generated from the frame's published dimensions (`from_catalog_frame`), and for
## the reference 5" it weighs 107.9 g against the vendor's 110 g. The vendor's figure is a scale
## reading of the real part; the document's is plates times density with side details, chamfers and
## a guessed arm width left out. The scale is closer to the real world, so an UNEDITED frame flies
## exactly as it did before this file existed — its catalogue mass and arm, bit for bit.
##
## An edit moves the flown frame by what the edit changed: flown = weighed + (drawn now − drawn as
## fitted), and likewise for arm length. That keeps what the scale knows and the drawing does not
## (the 2 g the generator misses) and adds what the drawing knows and the scale cannot (you just
## took 12 g of carbon off the arms). The result is an estimate, so it carries `~` wherever shown.
##
## ## What does NOT cross, and why (the two reasons the designer was kept apart)
##
## 1. The Build-free rule. The designer's panels still never read a `Build`: nothing here hands one
##    to them. The flow is one-way — document to Build — through `edit_of` and `Build.set_frame_edit`,
##    and what the Frame page says about flying is computed from the frame DICTIONARY
##    (`flown_text`), not from an aircraft.
## 2. The datum debt. The document measures height from the frame's bottom and `MountLayout` from
##    its middle, with one authored plate thickness for every frame. So an edit carries only PLAN
##    quantities — mass and arm length, which both models agree about — and never a plate
##    thickness or standoff height, which would reach the mount table through a second datum.
##    Moving a plate up in the designer therefore changes the flown mass (if it changed the part)
##    but not where the stack seats; that stays the mount table's until its own slice.
##
## A document the sim cannot fly (not four motors: MotorLayout is a quad mixer) is NOT applied, and
## `unflown_warning` says so on the Frame row rather than letting the designer and the aircraft
## silently disagree.

## Below these the document is the frame as fitted, and the catalogue flies untouched. A tenth of
## a gram and a hundredth of a millimetre are far under anything a builder can draw on purpose and
## far over the float32 noise a round trip through the document leaves (~1e-6 relative).
const MASS_EPSILON_G := 0.1
const ARM_EPSILON_MM := 0.01
const QUAD_MOTORS := 4
## Nothing flies lighter than this: an edit that deleted every plate must not produce a massless
## (or negative-mass) frame, whose inertia would divide by zero downstream.
const MIN_FLOWN_MASS_G := 1.0


## What the document weighs and how long its arms are: `{mass_g, arm_mm, motors}`. Arm length is
## the mean motor distance from the centre — the same quantity `specs.arm_mm` is.
static func drawn(document: AirframeDocument) -> Dictionary:
	if document == null:
		return {"mass_g": 0.0, "arm_mm": 0.0, "motors": 0}
	var props := AirframeProperties.compute(document, AirframePanel.materials())
	var arm := 0.0
	for motor in document.motors:
		arm += AirframeDocument.point_of((motor as Dictionary).get("position_mm", [0.0, 0.0])).length()
	var count := document.motors.size()
	return {"mass_g": props.total_mass_g(), "arm_mm": arm / count if count > 0 else 0.0,
		"motors": count}


## The fitted frame's own document, as generated — what `drawn` is measured against.
static func baseline(frame: Dictionary) -> Dictionary:
	return drawn(AirframeDocument.from_catalog_frame(frame))


## What the designer's edits change about the frame that flies, or `{}` when nothing does (the
## document is the frame as fitted, or cannot be flown). `baseline` is `baseline(frame)`, passed in
## so a caller that asks every frame computes the generated document once per fitted frame.
static func edit_of(frame: Dictionary, document: AirframeDocument, p_baseline: Dictionary) -> Dictionary:
	if frame.is_empty() or document == null or p_baseline.is_empty():
		return {}
	var now := drawn(document)
	if int(now["motors"]) != QUAD_MOTORS:
		return {}
	if is_replacement(frame, document):
		return _replacement_edit(frame, document, now)
	var delta_g := float(now["mass_g"]) - float(p_baseline["mass_g"])
	var delta_arm := float(now["arm_mm"]) - float(p_baseline["arm_mm"])
	if absf(delta_g) < MASS_EPSILON_G and absf(delta_arm) < ARM_EPSILON_MM:
		return {}
	var published := float(frame.get("mass_g", 0.0))
	var specs: Dictionary = frame.get("specs", {})
	# A frame nobody weighed (published 0) flies as drawn; one somebody weighed keeps the scale.
	var mass := published + delta_g if published > 0.0 else float(now["mass_g"])
	return {
		"part_id": str(frame.get("part_id", "")),
		"mass_g": maxf(mass, MIN_FLOWN_MASS_G),
		"arm_mm": float(specs.get("arm_mm", now["arm_mm"])) + delta_arm,
		"published_mass_g": published,
		"drawn_delta_g": delta_g,
	}


## The frame the physics reads: `frame` with the edit's mass and arm, marked so every caller can
## tell a flown estimate from a weighed figure. `frame` itself is never mutated — it is the
## catalogue's dictionary, shared by every build in the process.
static func apply(frame: Dictionary, edit: Dictionary) -> Dictionary:
	if edit.is_empty() or frame.is_empty() or str(edit.get("part_id", "")) != str(frame.get("part_id", "")):
		return frame
	var out := frame.duplicate(true)
	out["mass_g"] = float(edit["mass_g"])
	if not (out.get("specs") is Dictionary):
		out["specs"] = {}
	(out["specs"] as Dictionary)["arm_mm"] = float(edit["arm_mm"])
	# A REPLACEMENT (another frame drawn in the designer) also carries the specs it can measure and
	# its own name, so no warning quotes the fitted catalogue frame's clearance or drilling about a
	# frame that is not on the bench. See `_replacement_edit`.
	if edit.has("name"):
		out["name"] = str(edit["name"])
	for key in (edit.get("specs", {}) as Dictionary):
		(out["specs"] as Dictionary)[key] = (edit["specs"] as Dictionary)[key]
	if edit.get("catalog") is Dictionary:
		out["catalog"] = (edit["catalog"] as Dictionary).duplicate(true)
	out["drawn_edit"] = edit.duplicate(true)
	return out


static func is_edited(frame: Dictionary) -> bool:
	return frame.has("drawn_edit")


## The Frame row's number: the weighed figure as it stands, or the flown estimate with its `~`.
static func row_mass_text(frame: Dictionary) -> String:
	if frame.is_empty():
		return ""
	var grams := roundi(float(frame.get("mass_g", 0.0)))
	return "~%d g" % grams if is_edited(frame) else "%d g" % grams


## What the Frame page says flies, beside the drawn mass — the line that explains why the two
## numbers differ. "110 g, as weighed" / "~98 g: 110 weighed − 12 drawn".
static func flown_text(frame: Dictionary) -> String:
	if frame.is_empty():
		return "—"
	if not is_edited(frame):
		return "%d g, as weighed" % roundi(float(frame.get("mass_g", 0.0)))
	var edit: Dictionary = frame["drawn_edit"]
	var published := float(edit.get("published_mass_g", 0.0))
	if published <= 0.0:
		return "~%d g, as drawn" % roundi(float(frame["mass_g"]))
	var delta := roundi(float(edit.get("drawn_delta_g", 0.0)))
	return "~%d g: %d weighed %s %d drawn" % [roundi(float(frame["mass_g"])), roundi(published),
		"+" if delta >= 0 else "−", absi(delta)]


## The Frame row's warning when the document in the designer is not a frame the sim can fly, so it
## is NOT what the aircraft is flying. Null when it is (or when there is no document).
static func unflown_warning(document: AirframeDocument) -> BuildWarning:
	if document == null or document.motors.size() == QUAD_MOTORS or document.motors.is_empty():
		return null
	var w := BuildWarning.limiting(&"drawn_frame_not_flown",
		"The frame in the designer has %d motors, and the sim flies four-motor frames only, so the aircraft is still flying the fitted frame as published. Save the drawing to keep it; fit a quad to fly your changes."
			% document.motors.size(), {"motors": document.motors.size()})
	return w


# ---------------------------------------------------------------------------
# A different frame drawn in the designer (a REPLACEMENT, not an edit)
# ---------------------------------------------------------------------------
##
## The delta rule above is right for an EDIT: a document generated from the fitted frame and then
## changed, where the scale's reading of the real part is still the best number and the drawing
## only says what moved. It is wrong for a frame drawn from scratch or opened off the shelf (a
## 3" printed quad on a build whose rail says 5" freestyle): "110 g weighed + (drawn − 5" generated)"
## is the catalogue frame's mass wearing the drawing's clothes. A saved build is where that stops
## being a session's curiosity — the projects list would weigh one frame and the room draw another.
##
## So a document whose id is not the fitted frame's flies AS DRAWN: its own mass, its own arm, and
## every spec the geometry states (prop clearance from the motor spacing, the motor and stack
## drilling from the holes). A spec the drawing does not state comes out "" rather than the
## catalogue's, and `Build.warnings` already reads an empty stack pattern as "nothing to compare".

## Whether `document` is a different frame from `frame` (drawn or opened, not generated from it).
static func is_replacement(frame: Dictionary, document: AirframeDocument) -> bool:
	return document != null and document.id != str(frame.get("part_id", ""))


static func _replacement_edit(frame: Dictionary, document: AirframeDocument,
		now: Dictionary) -> Dictionary:
	var mass := float(now["mass_g"])
	return {
		"part_id": str(frame.get("part_id", "")),
		"mass_g": maxf(mass, MIN_FLOWN_MASS_G),
		"arm_mm": float(now["arm_mm"]),
		# Nobody weighed it: `flown_text` says "as drawn", and the delta is the whole drawing.
		"published_mass_g": 0.0,
		"drawn_delta_g": mass,
		"drawn_id": document.id,
		"name": document.name if document.name != "" else "Drawn frame",
		"specs": {
			"max_prop_inches": max_prop_inches(document),
			"motor_mount": motor_mount_of(document),
			"stack_mount": stack_mount_of(document),
		},
		# And its own browsing block. Left as the fitted frame's, a 3" PA12 drawing was described as
		# "5\"" and "carbon fibre 3K" by the Frame and Arms rows and drawn in carbon. The material is
		# the drawing's; the size class is a published label nobody published for a drawing, so it is
		# "" and the Frame row names the frame instead of guessing a class off its clearance.
		"catalog": {
			"material": material_name_of(document),
			"size_class": "",
			"frame_type": "",
		},
	}


## The drawing's material by name ("PA12 (SLS nylon)"), or its id when the library does not know it.
static func material_name_of(document: AirframeDocument) -> String:
	var record := AirframePanel.materials().get_material(document.material_id)
	return str(record.get("name", document.material_id))


## The largest prop whose discs do not touch: the closest pair of motors, centre to centre, in
## inches. Tip-to-tip touching, with no margin and no plate in the way — the optimistic bound, so a
## prop over it certainly strikes; one under it may still clip a plate corner (FrameWarnings').
static func max_prop_inches(document: AirframeDocument) -> float:
	var closest := INF
	for i in document.motors.size():
		var a := AirframeDocument.point_of((document.motors[i] as Dictionary).get("position_mm", [0.0, 0.0]))
		for j in range(i + 1, document.motors.size()):
			var b := AirframeDocument.point_of((document.motors[j] as Dictionary).get("position_mm", [0.0, 0.0]))
			closest = minf(closest, a.distance_to(b))
	return closest / 25.4 if closest < INF else 0.0


## Hole centres on every flat plate (an upright plate's holes are not in plan), one per place —
## a unibody drawn as arms over a bottom plate cuts the same hole twice.
const HOLE_MATCH_MM := 0.2


static func _hole_centres(document: AirframeDocument) -> Array:
	var out: Array = []
	for plate in document.plates:
		if AirframeDocument.is_upright(plate):
			continue
		for hole in AirframeDocument.plate_holes(plate):
			var points := hole as PackedVector2Array
			if points.is_empty():
				continue
			var sum := Vector2.ZERO
			for point in points:
				sum += point
			var centre := sum / points.size()
			var seen := false
			for other in out:
				if (other as Vector2).distance_to(centre) < HOLE_MATCH_MM:
					seen = true
					break
			if not seen:
				out.append(centre)
	return out


## The motor bolt pattern as the catalogue names it ("12x12"): the four holes nearest each motor,
## on one circle and centred on it. "" when any motor's four disagree with the others' or do not
## form a pattern — a drawing that does not state its drilling plainly is not guessed at.
static func motor_mount_of(document: AirframeDocument) -> String:
	var holes := _hole_centres(document)
	var found := ""
	for motor in document.motors:
		var at := AirframeDocument.point_of((motor as Dictionary).get("position_mm", [0.0, 0.0]))
		var near: Array = []
		for centre in holes:
			var r := (centre as Vector2).distance_to(at)
			if r > 1.5 and r < 20.0:
				near.append(centre)
		if near.size() < 4:
			return ""
		near.sort_custom(func(a, b) -> bool: return (a as Vector2).distance_to(at) < (b as Vector2).distance_to(at))
		var four := near.slice(0, 4)
		var radius := (four[0] as Vector2).distance_to(at)
		var middle := Vector2.ZERO
		for centre in four:
			if absf((centre as Vector2).distance_to(at) - radius) > HOLE_MATCH_MM:
				return ""
			middle += centre
		if (middle / 4.0).distance_to(at) > HOLE_MATCH_MM:
			return ""
		var name := _pattern_name(radius * sqrt(2.0))
		if found != "" and name != found:
			return ""
		found = name
	return found


## The stack pattern on the stack mount's centre (the origin when the drawing marks none): the
## smallest square of four holes centred there. "" when there is none.
static func stack_mount_of(document: AirframeDocument) -> String:
	var at := Vector2.ZERO
	for mount in document.payload_mounts:
		if str((mount as Dictionary).get("id", "")) == "stack":
			at = AirframeDocument.point_of((mount as Dictionary).get("position_mm", [0.0, 0.0]))
	var holes := _hole_centres(document)
	var best := INF
	for centre in holes:
		var d := (centre as Vector2) - at
		var h := absf(d.x)
		if h < 1.0 or absf(absf(d.y) - h) > HOLE_MATCH_MM or 2.0 * h >= best:
			continue
		var corners := 0
		for corner in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]:
			for other in holes:
				if (other as Vector2).distance_to(at + (corner as Vector2)) < HOLE_MATCH_MM:
					corners += 1
					break
		if corners == 4:
			best = 2.0 * h
	return _pattern_name(best) if best < INF else ""


## 12.0 -> "12x12", 30.5 -> "30.5x30.5": the catalogue's spelling, to the tenth.
static func _pattern_name(pitch_mm: float) -> String:
	var tenths := roundi(pitch_mm * 10.0)
	var text := "%d" % roundi(tenths / 10.0) if tenths % 10 == 0 else "%.1f" % (tenths / 10.0)
	return "%sx%s" % [text, text]
