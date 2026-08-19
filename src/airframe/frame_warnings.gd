class_name FrameWarnings
extends RefCounted
## What is wrong with a frame, derived from the frame — airframe.md §7.1's "every check warns rather
## than blocks", and §5.3's assemblability checks.
##
## ## Why a frame needs its own warning source
##
## Every warning the app could previously show came from `Build.warnings()`, `AirframeModel` or the
## plausibility checks, and all of them are about an AIRCRAFT: this pack will not lift this frame,
## this prop strikes that arm, this ESC is under-rated for that motor. None of them can say anything
## about a frame on its own, so the Airframe room either borrowed an aircraft's warnings — which is
## how a frame editor came to be showing hover throttle — or showed none.
##
## These are the frame's own. Every one of them is answerable from the document with no propulsion,
## no pack and no flight: either the geometry is self-consistent or it is not.
##
## ## Warn, never block (parts.md), and say which kind of wrong it is
##
## The severities are `BuildWarning`'s, and the line between them is the same one labs-and-sim.md
## §2.1 draws. A centreline that leaves its own plate is IMPOSSIBLE — the beam maths has nothing to
## integrate, and there is a hard boundary in the geometry to point at. A frame whose roll and pitch
## inertias differ by a factor of two is CHARACTERISTIC: that is a deadcat, or a stretched frame,
## and it is a description of what you drew rather than a mistake in it.
##
## ## What is deliberately NOT checked here
##
## Nothing that needs a part. "Will this pack fit", "do these props overlap", "is this arm stiff
## enough for a 2207" are all real questions and all belong to the room that knows the answer to
## "which 2207". A check here that quietly assumed a motor would put the drone back in the frame
## editor by the back door.

## Above this, roll and pitch inertia differ enough that the frame is worth describing as
## directional rather than symmetric. 1.15 is not a threshold anything is fitted to — it is roughly
## where a stretched frame stops being a rounding error and starts being a design choice, and the
## warning it produces is CHARACTERISTIC, so nothing downstream branches on it.
const DIRECTIONAL_RATIO := 1.15

## Millimetres of CG offset from the geometric origin that count as "not centred". Half a
## millimetre is finer than anyone cuts and coarser than the arithmetic noise of summing a few
## hundred plate elements.
const CG_OFFSET_TOLERANCE_MM := 0.5

## The Q/T ratio used only to ask whether the layout CAN yaw.
##
## Yaw authority is the one column of §4.1's B matrix that is not pure geometry: it scales with a
## propeller's torque-to-thrust ratio, and this room has no propeller. But that ratio multiplies the
## whole yaw row UNIFORMLY, so it cannot change the matrix's rank — only its magnitude. One is
## therefore not a stand-in for a real Q/T and no number derived from it is ever shown; it is the
## arbitrary positive scale that makes "can this layout yaw at all" answerable without a prop.
const REFERENCE_DRAG_RATIO := 1.0


## Everything worth saying about this frame, most severe first.
static func of(document: AirframeDocument, props: AirframeProperties) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if document == null:
		return out

	_check_has_plates(document, out)
	_check_arms_measure(document, out)
	_check_layout(document, out)
	_check_balance(props, out)

	out.sort_custom(func(a: BuildWarning, b: BuildWarning) -> bool:
		return a.severity < b.severity)
	return out


## A document with no plates is not a frame yet. Said plainly rather than left to produce a mass of
## zero grams, which reads as a measurement.
static func _check_has_plates(document: AirframeDocument, out: Array[BuildWarning]) -> void:
	if document.plates.is_empty():
		out.append(BuildWarning.new(
			BuildWarning.Severity.IMPOSSIBLE,
			&"frame_has_no_plates",
			"This frame has no plates yet, so it has no mass, no inertia and no arms.",
			{"plates": 0}))


## Every arm plate must be measurable along its own centreline (§10 q1). When it is not, the arm
## contributes mass and inertia — it is still a plate — but no stiffness, resonance or stress
## figure, and the reason is named at the arm rather than left as a dash on the Arms tab.
static func _check_arms_measure(document: AirframeDocument, out: Array[BuildWarning]) -> void:
	var index := 0
	var arms := 0
	for plate in document.plates:
		if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
			continue
		arms += 1
		index += 1
		if not plate.has("root_point") or not plate.has("tip_point"):
			out.append(BuildWarning.new(
				BuildWarning.Severity.IMPOSSIBLE,
				&"arm_has_no_centreline",
				"Arm %d has no centreline, so it cannot be analysed as a beam. "
					% index + "Draw its root and tip.",
				{"arm": index}))
			continue
		var root := AirframeDocument.point_of(plate["root_point"])
		var tip := AirframeDocument.point_of(plate["tip_point"])
		var profile := ArmProfile.measure_flat(
			plate.get("outline", PackedFloat64Array()),
			root.x, root.y, tip.x, tip.y)
		if not profile["errors"].is_empty():
			out.append(BuildWarning.new(
				BuildWarning.Severity.IMPOSSIBLE,
				&"arm_centreline_leaves_plate",
				"Arm %d's centreline runs outside its own outline, so its width cannot be measured."
					% index,
				{"arm": index, "errors": profile["errors"]}))

	# A plate frame with no arm at all is a legitimate thing to be drawing — you have to start
	# somewhere — so this is CHARACTERISTIC and phrased as a state, not a fault.
	if arms == 0 and not document.plates.is_empty():
		out.append(BuildWarning.new(
			BuildWarning.Severity.CHARACTERISTIC,
			&"frame_has_no_arms",
			"No plate is marked as an arm yet, so there is nothing to analyse as a beam.",
			{"arms": 0}))


## §4.1: can this motor layout produce the four things a quad needs — thrust, roll, pitch, yaw?
## A rank-deficient layout is refused WITH ITS REASON rather than silently mixed into nonsense.
static func _check_layout(document: AirframeDocument, out: Array[BuildWarning]) -> void:
	var motors := document.motors
	if motors.is_empty():
		out.append(BuildWarning.new(
			BuildWarning.Severity.CHARACTERISTIC,
			&"frame_has_no_motors",
			"No motor positions yet, so there is no layout to check.",
			{"motors": 0}))
		return

	var entries: Array = []
	for motor in motors:
		var position := AirframeDocument.point_of(motor.get("position_mm", [0.0, 0.0]))
		entries.append(ControlEffectiveness.motor(
			position.x / 1000.0,
			position.y / 1000.0,
			float(motor.get("spin", 1.0)),
			REFERENCE_DRAG_RATIO))

	var b := ControlEffectiveness.build_matrix(entries)
	var rank := ControlEffectiveness.rank(b)
	if rank < 4:
		out.append(BuildWarning.new(
			BuildWarning.Severity.IMPOSSIBLE,
			&"layout_not_controllable",
			"This layout controls only %d of the four axes (thrust, roll, pitch, yaw), so it cannot be mixed."
				% rank,
			{"motors": motors.size(), "rank": rank}))


## Where the mass ended up. Both of these are descriptions of the frame you drew, never faults —
## a deadcat is meant to be nose-light and a stretched frame is meant to pitch slowly.
static func _check_balance(props: AirframeProperties, out: Array[BuildWarning]) -> void:
	if props == null or props.total_mass_kg <= 0.0:
		return

	var offset_mm := Vector2(props.cg_m.x, props.cg_m.z).length() * 1000.0
	if offset_mm > CG_OFFSET_TOLERANCE_MM:
		out.append(BuildWarning.new(
			BuildWarning.Severity.CHARACTERISTIC,
			&"frame_cg_off_axis",
			"The frame's own centre of gravity sits %.1f mm off the origin." % offset_mm,
			{"offset_mm": offset_mm}))

	var roll := props.roll_inertia_kg_m2()
	var pitch := props.pitch_inertia_kg_m2()
	if roll <= 0.0 or pitch <= 0.0:
		return
	var ratio := maxf(roll, pitch) / minf(roll, pitch)
	if ratio >= DIRECTIONAL_RATIO:
		var faster := "rolls" if roll < pitch else "pitches"
		out.append(BuildWarning.new(
			BuildWarning.Severity.CHARACTERISTIC,
			&"frame_is_directional",
			"This frame %s %.2f times more readily than the other axis." % [faster, ratio],
			{"ratio": ratio}))
