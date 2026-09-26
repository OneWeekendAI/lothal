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
	(out["specs"] as Dictionary)["arm_mm"] = float(edit["arm_mm"])
	out["drawn_edit"] = edit.duplicate()
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
