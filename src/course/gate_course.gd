class_name GateCourse
extends RefCounted
## A circuit: an ordered list of gates, and the rule for what counts as flying through one.
## Pure geometry and state — no nodes, no scene, no rendering. The scene renders what this
## describes; it never decides anything.
##
## Gates must be taken in order. Passing the last one completes a lap and re-arms the first.
##
## ---------------------------------------------------------------------------
## THE WORLD IS DATA, NOT CONSTANTS
## ---------------------------------------------------------------------------
##
## This file used to BE the course. COURSE_RADIUS_M, GATE_COUNT and two gate heights sat at the
## top of it, and `build_gates()` was the definition of the world rather than one course among
## many. That put the field on the wrong side of labs-and-sim.md §1: a gate's position is what
## the world IS, and what the world is gets authored in the garage. Lothal honoured that
## boundary for the aircraft — every millimetre of the airframe comes from a selected part — and
## quietly broke it for the ground the aircraft flies over.
##
## So a GateCourse now CARRIES its gates. `build_gates()` survives unchanged as the factory for
## the default circuit, which is what a fresh install flies and what every existing test pins,
## but it is one course now and not the world. CourseLibrary holds the rest, the field editor
## writes them, and Sim reads a finished field exactly as it reads a finished aircraft.
##
## Nothing downstream may assume eight gates in a circle. The audit that came with this change
## is written up in labs-and-sim.md §2.4; the load-bearing pieces are in this file and are
## commented where they sit — the lap wrap, the start line's setback, and the respawn fallback.

## The default circuit's dimensions. These are the arithmetic of ONE course — the eight-gate
## carousel a fresh install flies — and deliberately not the shape of every course. Anything
## reading these to reason about "the course" is reading the wrong thing and should ask the
## GateCourse it was handed instead.
const COURSE_RADIUS_M := 18.0
const GATE_INNER_RADIUS_M := 1.5
const GATE_COUNT := 8

## The default circuit's gates alternate between two heights so it is flown in three dimensions
## rather than as a flat carousel. Both are comfortably above the ground plane.
const GATE_LOW_M := 2.5
const GATE_HIGH_M := 4.0

## How thick a gate's tubing is. A property of what a gate IS rather than of how one is drawn,
## which is why it lives here and not in CourseRenderer any more: CourseWarnings has to ask
## whether two hoops physically collide, and a second copy of the tube thickness would let the
## picture and the answer drift apart — exactly what gate_course.gd's opening line forbids.
const RING_THICKNESS_M := 0.18

const DEFAULT_ID := "default_circuit"
const DEFAULT_NAME := "Circuit"

## position, normal (the direction of travel through the ring), radius
var gates: Array[Dictionary] = []
## Which course this is. The id is stable and machine-readable — it is what a library keys on and
## what a saved selection names. The name is the builder's, and it may be changed or duplicated
## without anything downstream noticing.
var course_id := DEFAULT_ID
var course_name := DEFAULT_NAME

## The SITE this course is laid out in — the place you fly, which owns the ground, the obstacles
## and the elevation (site.gd).
##
## This replaced `var air`, and the replacement is the point rather than a tidy-up. Air was a
## property of the WORLD living on the ROUTE, so laying out a second route at the same spot meant
## typing the elevation twice, and the two copies were free to disagree the first time one was
## edited. Now the place holds it once and every route in it reads the same number.
##
## Defaults to the default field, which is the correct reading of a course that has never been
## told where it is rather than a fallback.
var site_id := Site.DEFAULT_ID

var next_gate_index := 0
## Where to put the drone back after a crash: the gate it most recently flew through,
## facing the way it was going. -1 until the first gate is taken.
var last_gate_passed := -1

## Empty gates mean the default circuit, so `GateCourse.new()` is exactly what it has always been
## and a fresh install flies precisely what it flew before this slice.
func _init(p_gates: Array[Dictionary] = [], p_id := DEFAULT_ID, p_name := DEFAULT_NAME) -> void:
	gates = build_gates() if p_gates.is_empty() else p_gates
	course_id = p_id
	course_name = p_name

## The default circuit: laid out around a circle. Each gate's normal is the tangent — the
## direction a drone flying the circuit is travelling as it goes through — so "forward through
## the ring" is well defined and a gate cannot be scored by drifting backwards through it.
##
## This is the DEFAULT-COURSE FACTORY, not the definition of the world. The arithmetic is
## untouched from when it was the latter, because a fresh install has to fly what it always flew.
static func build_gates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in GATE_COUNT:
		var angle := TAU * float(i) / float(GATE_COUNT)
		var position := Vector3(
			cos(angle) * COURSE_RADIUS_M,
			GATE_LOW_M if i % 2 == 0 else GATE_HIGH_M,
			sin(angle) * COURSE_RADIUS_M
		)
		# d/dangle of the position above, normalised: the tangent, pointing counter-clockwise.
		var normal := Vector3(-sin(angle), 0.0, cos(angle)).normalized()
		out.append({"position": position, "normal": normal, "radius": GATE_INNER_RADIUS_M})
	return out

## One gate, from a place and a heading. The editor authors in these terms — you put a gate
## somewhere and point it — and this is the one place that turns that into the position/normal/
## radius triple the rest of the file reads, so an editor cannot invent a fourth field.
static func make_gate(position: Vector3, heading_rad: float, radius: float) -> Dictionary:
	return {
		"position": position,
		# Flat, deliberately. A gate tilted out of the vertical is a ring you can only score by
		# climbing or diving through it, and nothing in the catalog or the physics asks for one.
		"normal": Vector3(sin(heading_rad), 0.0, -cos(heading_rad)).normalized(),
		"radius": radius,
	}

## The heading a gate faces, in radians, as make_gate() would take it. The inverse of the line
## above rather than a stored field, so there is one description of which way a gate points.
static func gate_heading_rad(gate: Dictionary) -> float:
	var normal: Vector3 = gate["normal"]
	return atan2(normal.x, -normal.z)

func gate_count() -> int:
	return gates.size()

func next_gate() -> Dictionary:
	return gates[next_gate_index]

## How far back down the course the drone sits at the start.
const START_SETBACK_M := 7.0

## The start line: behind gate 1, already lined up with it. NOT the middle of the circle —
## every gate's ring faces along the circuit tangent, so a drone parked at the centre and
## pointed at gate 1 is looking at the ring edge-on and cannot fly through it no matter how
## well it flies. Day 6's gate is that a stranger completes a lap with no explanation, and
## step one of that is "push the stick forward and you go through the lit hoop".
##
## That reasoning has to survive an authored course, and the fixed 7 m setback does not: on a
## course whose last gate sits 4 m behind gate 1, backing up 7 m puts the start line on the far
## side of a gate the pilot has not flown yet, pointed at its back. So the setback is capped at
## most of the way back to the gate that precedes gate 1 — the drone still starts short of gate 1
## and lined up with it, which is the whole of what the paragraph above asks for, and on the
## default circuit (13.8 m between gates) the cap does not bind and the start line is unmoved.
const START_SETBACK_FRACTION := 0.6

func start_position() -> Vector3:
	var gate := gates[0]
	return gate["position"] - gate["normal"] * start_setback_m()

## The setback actually used, which is the shorter of the nominal 7 m and most of the way back to
## the preceding gate. A one-gate course has nothing behind it and keeps the full 7 m.
func start_setback_m() -> float:
	if gates.size() < 2:
		return START_SETBACK_M
	var previous: Vector3 = gates[gates.size() - 1]["position"]
	var room := float(gates[0]["position"].distance_to(previous)) * START_SETBACK_FRACTION
	return minf(START_SETBACK_M, room)

func start_forward() -> Vector3:
	return gates[0]["normal"]

## Feed it the movement since the last frame. Returns true when that movement passed the
## gate that was due.
##
## Deliberately a SEGMENT test rather than a proximity test. At 100 km/h a 120 Hz frame
## moves 23 cm, and a fast run at a gate can step from one side of the ring to the other
## between two samples — a "am I within the ring right now" check silently misses exactly
## the passes a pilot is proudest of. So: find where the travel segment crosses the gate's
## plane, then ask whether THAT point is inside the ring.
func advance(previous_position: Vector3, current_position: Vector3) -> bool:
	if gates.is_empty():
		return false
	var gate := gates[next_gate_index]
	if not segment_passes_gate(previous_position, current_position, gate):
		return false

	last_gate_passed = next_gate_index
	# Wraps on THIS course's own length. It used to wrap on GATE_COUNT, which is the same number
	# for the default circuit and a silent off-by-however-many for every other course: a
	# six-gate course would have re-armed gate 7 of six and taken the whole field down.
	next_gate_index = (next_gate_index + 1) % gates.size()
	return true

## True when the segment crosses the gate's plane in the forward direction, inside the ring.
static func segment_passes_gate(from: Vector3, to: Vector3, gate: Dictionary) -> bool:
	var normal: Vector3 = gate["normal"]
	var origin: Vector3 = gate["position"]

	var distance_from := (from - origin).dot(normal)
	var distance_to := (to - origin).dot(normal)

	# Must start behind the plane and end on or past it. Flying backwards through a gate
	# leaves both distances negative-going and scores nothing, which is the intent: the
	# course has a direction.
	if distance_from >= 0.0 or distance_to < 0.0:
		return false

	var denominator := distance_from - distance_to
	if is_zero_approx(denominator):
		return false

	var t := distance_from / denominator
	var crossing := from.lerp(to, t)
	# Radial offset within the gate's plane: the part of the crossing point that is not
	# along the normal.
	var offset := crossing - origin
	var radial := offset - normal * offset.dot(normal)
	return radial.length() <= float(gate["radius"])

## True when a lap has just been completed — the last gate taken, wrapping back to the first.
func just_completed_lap() -> bool:
	return not gates.is_empty() and next_gate_index == 0 and last_gate_passed == gates.size() - 1

## Where a crashed drone resumes: at the last gate it cleared, already pointed down the
## course. Respawning at the original spawn point after every clip would make the back half
## of the circuit effectively unreachable for a new pilot (week1.md day 6's gate is that a
## stranger completes a lap).
func respawn_position() -> Vector3:
	if last_gate_passed < 0:
		# Nothing cleared yet, so the last gate cleared is the start line. Derived rather than the
		# old fixed Vector3(0, GATE_LOW_M, 0), which was the centre of the default circle and is
		# an arbitrary point in a field for any other course — on a course laid out 200 m away it
		# put a crashed pilot in an empty field with no gate in sight.
		return start_position()
	var gate := gates[last_gate_passed]
	# Just past the ring, so the drone does not immediately re-trigger the gate it left.
	return gate["position"] + gate["normal"] * 1.0

func reset() -> void:
	next_gate_index = 0
	last_gate_passed = -1


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## How precisely two courses have to agree to be the same course. A millimetre — finer than any
## gate can be placed and far coarser than the noise a float picks up going through JSON, which is
## the accidental "edit" this has to tolerate. See LapTimer's header.
const FINGERPRINT_PRECISION_M := 0.001
## Headings quantise on the same idea: fine enough that a gate you turned is a different gate,
## coarse enough that a round trip through the file is not. A ten-thousandth of a unit normal is
## about 0.006 deg.
const FINGERPRINT_PRECISION_NORMAL := 0.0001
## Air quantises on the same idea. A thousandth of a kg/m3 is 0.08% of standard air — far finer
## than any effect on a lap time, and far coarser than a float's round trip through JSON.
const FINGERPRINT_PRECISION_RHO := 0.001

## What a best lap is set ON: the geometry, not the id and not the name.
##
## The reasoning is written out in lap_timer.gd's header, because that is where the bug this
## prevents would have lived. In short: a lap time is a fact about a track. Keying it on an id
## would mean every place that moves a gate has to remember to retire the record, and the day one
## of them forgot, Lothal would quietly report a record set on a different course.
##
## Order matters, and it should: the same rings taken in a different sequence is a different
## course to fly, and the times are not comparable.
## The air is passed IN rather than read off this object, because a course no longer carries one —
## the site does. `null` means standard, and that default is load-bearing rather than a
## convenience: every existing caller passes nothing, and the paragraph below says what happens to
## a hash that starts appending a term unconditionally.
func fingerprint(p_air: AirDensity = null) -> String:
	var parts := PackedStringArray()
	for gate in gates:
		var position: Vector3 = gate["position"]
		var normal: Vector3 = gate["normal"]
		parts.append("%d,%d,%d,%d,%d,%d,%d" % [
			roundi(position.x / FINGERPRINT_PRECISION_M),
			roundi(position.y / FINGERPRINT_PRECISION_M),
			roundi(position.z / FINGERPRINT_PRECISION_M),
			roundi(normal.x / FINGERPRINT_PRECISION_NORMAL),
			roundi(normal.y / FINGERPRINT_PRECISION_NORMAL),
			roundi(normal.z / FINGERPRINT_PRECISION_NORMAL),
			roundi(float(gate["radius"]) / FINGERPRINT_PRECISION_M),
		])
	# THE AIR IS PART OF THE TRACK, and leaving it out would be this function's own bug arriving
	# through a new door. The header says a lap time is a fact about a track and that nudging a
	# gate 20 cm retires the record; a lap flown in 36% thinner air at Leh differs from a sea-level
	# lap on the same rings by very much more than 20 cm of gate, and reporting one as the other is
	# exactly the record that quietly means nothing.
	#
	# Fingerprinted on RHO rather than on elevation and temperature, because rho is what changes
	# the lap — and because it means a thermometer read 0.1 C differently does not retire a record.
	#
	# Appended ONLY when the air is non-standard, which is not a special case bolted on: it is the
	# same rule the file follows, where what was never authored is not represented. It also has to
	# be true — appending a standard-air term unconditionally would change every existing course's
	# hash and orphan every best lap ever set.
	if p_air != null and not p_air.is_standard():
		parts.append("rho=%d" % roundi(p_air.kgm3() / FINGERPRINT_PRECISION_RHO))
	# Hashed rather than stored whole, so the best-lap file stays a short readable table instead of
	# growing a copy of every course anyone has ever flown. Truncated to 16 hex characters: the file
	# holds a handful of courses, and a collision there needs 2^32 of them.
	return "|".join(parts).sha256_text().substr(0, 16)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## The gates as plain JSON values. Vectors go out as three-element arrays rather than as strings,
## so the file stays reviewable and hand-editable in the way json_store.gd's pretty-printing is for.
static func gates_to_data(list: Array[Dictionary]) -> Array:
	var out: Array = []
	for gate in list:
		var position: Vector3 = gate["position"]
		var normal: Vector3 = gate["normal"]
		out.append({
			"position": [position.x, position.y, position.z],
			"normal": [normal.x, normal.y, normal.z],
			"radius": float(gate["radius"]),
		})
	return out


## Gates back from JSON. Anything unreadable is DROPPED rather than defaulted to the origin: a
## gate at (0,0,0) with a zero normal is a gate you cannot fly through and cannot see, and it
## would read as a course the pilot simply could not complete rather than as a damaged file.
static func gates_from_data(data: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (data is Array):
		return out
	for entry in (data as Array):
		if not (entry is Dictionary):
			continue
		var gate: Dictionary = entry
		var position: Variant = _vector_from(gate.get("position"))
		var normal: Variant = _vector_from(gate.get("normal"))
		var radius: Variant = gate.get("radius")
		if position == null or normal == null or not (radius is float or radius is int):
			continue
		var flat: Vector3 = normal
		if flat.length() < 0.0001 or float(radius) <= 0.0:
			continue
		out.append({"position": position, "normal": flat.normalized(), "radius": float(radius)})
	return out


## A Vector3 from a three-number array, or null for anything else. Null rather than Vector3.ZERO
## because zero is a legitimate coordinate and "absent" has to be distinguishable from "at the
## origin" — the same reason AssemblyTweaks treats a wrong-typed value as absent rather than
## coercing it to 0.0.
static func _vector_from(value: Variant) -> Variant:
	if not (value is Array) or (value as Array).size() != 3:
		return null
	var out := Vector3.ZERO
	for i in 3:
		var component: Variant = (value as Array)[i]
		if not (component is float or component is int):
			return null
		out[i] = float(component)
	return out
