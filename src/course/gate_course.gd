class_name GateCourse
extends RefCounted
## The circuit: eight gates in a closed loop, and the rule for what counts as flying
## through one. Pure geometry and state — no nodes, no scene, no rendering. The scene
## renders what this describes; it never decides anything.
##
## Gates must be taken in order. Passing gate 8 completes a lap and re-arms gate 1.

## Circuit radius, and the ring the drone actually has to fit through.
const COURSE_RADIUS_M := 18.0
const GATE_INNER_RADIUS_M := 1.5
const GATE_COUNT := 8

## Gates alternate between two heights so the course is flown in three dimensions rather
## than as a flat carousel. Both are comfortably above the ground plane.
const GATE_LOW_M := 2.5
const GATE_HIGH_M := 4.0

## position, normal (the direction of travel through the ring), radius
var gates: Array[Dictionary] = []
var next_gate_index := 0
## Where to put the drone back after a crash: the gate it most recently flew through,
## facing the way it was going. -1 until the first gate is taken.
var last_gate_passed := -1

func _init() -> void:
	gates = build_gates()

## Laid out around a circle. Each gate's normal is the tangent — the direction a drone
## flying the circuit is travelling as it goes through — so "forward through the ring" is
## well defined and a gate cannot be scored by drifting backwards through it.
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

func next_gate() -> Dictionary:
	return gates[next_gate_index]

## How far back down the course the drone sits at the start.
const START_SETBACK_M := 7.0

## The start line: behind gate 1, already lined up with it. NOT the middle of the circle —
## every gate's ring faces along the circuit tangent, so a drone parked at the centre and
## pointed at gate 1 is looking at the ring edge-on and cannot fly through it no matter how
## well it flies. Day 6's gate is that a stranger completes a lap with no explanation, and
## step one of that is "push the stick forward and you go through the lit hoop".
func start_position() -> Vector3:
	var gate := gates[0]
	return gate["position"] - gate["normal"] * START_SETBACK_M

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
	var gate := gates[next_gate_index]
	if not segment_passes_gate(previous_position, current_position, gate):
		return false

	last_gate_passed = next_gate_index
	next_gate_index = (next_gate_index + 1) % GATE_COUNT
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

## True when a lap has just been completed — gate 8 taken, wrapping back to gate 1.
func just_completed_lap() -> bool:
	return next_gate_index == 0 and last_gate_passed == GATE_COUNT - 1

## Where a crashed drone resumes: at the last gate it cleared, already pointed down the
## course. Respawning at the original spawn point after every clip would make the back half
## of the circuit effectively unreachable for a new pilot (week1.md day 6's gate is that a
## stranger completes a lap).
func respawn_position() -> Vector3:
	if last_gate_passed < 0:
		return Vector3(0.0, GATE_LOW_M, 0.0)
	var gate := gates[last_gate_passed]
	# Just past the ring, so the drone does not immediately re-trigger the gate it left.
	return gate["position"] + gate["normal"] * 1.0

func reset() -> void:
	next_gate_index = 0
	last_gate_passed = -1
