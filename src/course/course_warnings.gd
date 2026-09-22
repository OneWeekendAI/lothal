class_name CourseWarnings
extends RefCounted
## What Lothal is entitled to say about a course you have laid out.
##
## The vocabulary is build_warning.gd's, unchanged and deliberately not extended: impossible where
## the geometry refuses, limiting where something binds, characteristic where the honest thing is
## to describe the course rather than judge it. A second severity scale for the field would mean
## the garage had two rules, and labs-and-sim.md §2.3 spent a whole section arriving at one.
##
## ---------------------------------------------------------------------------
## WHAT IS NOT HERE, AND WHY
## ---------------------------------------------------------------------------
##
## **There is no difficulty score, and there must not be one.** A course cannot be graded without
## someone deciding what hard means, and that decision cannot be derived from the gates — it would
## be taste wearing physics clothing, which is precisely what the warnings slice was written to
## remove. The 2.0:1 thrust-to-weight threshold is the cautionary tale: a number nobody could say
## where it came from, told a cinelifter builder they had made a mistake for correctly building a
## cinelifter.
##
## **Nothing warns that a course is tight.** A 6 m box of 0.6 m rings is a whoop course, and it is
## a valid thing to build. So the tight-course facts are reported as measurements with units — the
## route is this long, the sharpest corner is this many degrees — and the pilot judges. Both tests
## of a proposed threshold (labs-and-sim.md §2.3) are applied here as they are to a build: can you
## say where the number comes from, and is it independent of the others? The two impossibles below
## pass both — the ground is where the site's own terrain says it is (F4) and the aircraft's span
## is arithmetic off the parts — and every judgement about tightness fails the first.

const GATE_BELOW_GROUND := &"course_gate_below_ground"
const RING_SMALLER_THAN_AIRCRAFT := &"course_ring_smaller_than_aircraft"
const RINGS_INTERSECT := &"course_rings_intersect"
const ROUTE_THROUGH_GATE := &"course_route_through_gate"
const ROUTE_LENGTH := &"course_route_length"
const TIGHTEST_TURN := &"course_tightest_turn"

## F6 — obstacles. Two known geometries compared (a gate's own ring, an obstacle's own solid), not
## a proximity bubble: see `Obstacle.intersects_sphere`/`intersects_segment`, which this file asks
## rather than inventing a second collision test.
const GATE_INTERSECTS_OBSTACLE := &"course_gate_intersects_obstacle"
const ROUTE_THROUGH_OBSTACLE := &"course_route_through_obstacle"
const OUTSIDE_SITE_EXTENT := &"course_outside_site_extent"

## How finely a leg is sampled against the site's own extent — arithmetic against a stated size
## (`Terrain.contains()`), not a threshold: a leg that leaves the extent and comes back must be
## caught even though both of its gates are inside, so the whole leg is walked rather than just
## its ends.
const EXTENT_SAMPLE_STEP_M := 0.5

## How finely a ring is sampled when asking whether two hoops collide. At 48 points a 1.5 m ring
## is sampled every 20 cm, which resolves an intersection an order of magnitude finer than the
## 36 cm of tubing the test is looking for.
const RING_SAMPLES := 48


## `p_site` is the place this course is laid out in (F4). **Null means flat at zero**, which is
## exactly what every caller got before terrain existed — the default is what keeps the existing
## call sites honest rather than silently re-judged, and it is the one thing the F4 suite pins as
## bit-identical.
static func evaluate(course: GateCourse, build: Build,
		p_site: Site = null) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if course == null or course.gates.is_empty():
		return out

	out.append_array(_impossible(course, build, p_site))
	out.append_array(_limiting(course, p_site))
	out.append_array(_characteristic(course))
	return BuildWarning.by_severity(out)


# ---------------------------------------------------------------------------
# Impossible — there is a boundary to point at
# ---------------------------------------------------------------------------

## The terrain a site carries, or null for a site that is not there. One place, so that "no site
## means flat" is a single statement rather than a branch in every consumer.
static func _terrain_of(p_site: Site) -> Terrain:
	return p_site.terrain if p_site != null else null


static func _impossible(course: GateCourse, build: Build,
		p_site: Site) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var terrain := _terrain_of(p_site)

	# THE GROUND IS THE TERRAIN, NOT y = 0. A ring whose lower edge is beneath the ground under it
	# has part of its hoop buried, and the aperture the pilot is aiming at is not the aperture that
	# is there. The height is read AT THE GATE'S OWN x/z — a slope is a different ground at each
	# end of it, and asking once at the site origin would call a buried gate clear at one end and a
	# clear gate buried at the other. A null terrain reads 0 everywhere, which is what this check
	# has always said.
	for i in course.gates.size():
		var gate: Dictionary = course.gates[i]
		var at: Vector3 = gate["position"]
		var ground := terrain.height_at(at.x, at.z) if terrain != null else 0.0
		# Relative to the ground under this gate, so the depth quoted is the depth a shovel would
		# have to dig — not the distance to a datum that may be nowhere near the surface.
		var lower_edge := float(at.y) - float(gate["radius"]) - ground
		if lower_edge > 0.0:
			continue
		out.append(BuildWarning.impossible(GATE_BELOW_GROUND,
			"Gate %d reaches %.2f m below the ground. Raise it above %.2f m." % [
				i + 1, -lower_edge, ground + float(gate["radius"])],
			{"gate": i + 1, "lower_edge_m": lower_edge, "radius_m": float(gate["radius"])}))

	# Two known dimensions compared, which is what makes this a measurement rather than a policy
	# about small gates: the ring's own aperture, and the span of the aircraft that has to go
	# through it. The same 0.5 m ring is impossible for a 10" long-range and unremarkable for a
	# 65 mm whoop, and neither answer was typed in.
	if build != null:
		var span_m := build.airframe_span_m()
		for i in course.gates.size():
			var aperture_m := float(course.gates[i]["radius"]) * 2.0
			if aperture_m >= span_m:
				continue
			out.append(BuildWarning.impossible(RING_SMALLER_THAN_AIRCRAFT,
				"Gate %d's ring is %.0f mm across and this aircraft spans %.0f mm — it cannot fit through." % [
					i + 1, aperture_m * 1000.0, span_m * 1000.0],
				{"gate": i + 1, "aperture_m": aperture_m, "span_m": span_m}))

	# A gate whose ring's own tube overlaps an obstacle's own solid. Two known geometries — the
	# ring sampled the same way `_rings_intersect` samples a second ring, and the obstacle's exact
	# surface via `intersects_sphere` — never an inflated box: check 2 (a gate 10 cm clear of the
	# same box) is the proof this is geometry rather than a safety margin.
	for obstacle in _obstacles_of(p_site):
		for i in course.gates.size():
			var gate: Dictionary = course.gates[i]
			var hit := false
			for point in _ring_points(gate):
				if obstacle.intersects_sphere(point, GateCourse.RING_THICKNESS_M):
					hit = true
					break
			if not hit:
				continue
			out.append(BuildWarning.impossible(GATE_INTERSECTS_OBSTACLE,
				"Gate %d's ring passes through an obstacle." % [i + 1],
				{"gate": i + 1}))

	return out


# ---------------------------------------------------------------------------
# Limiting — it works, but something binds
# ---------------------------------------------------------------------------

static func _limiting(course: GateCourse, p_site: Site = null) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var gates := course.gates

	# Hoops that physically pass through each other. Flyable — you can still take them in order —
	# but one gate's structure is inside the other's aperture, so part of the ring the pilot is
	# aiming at is blocked by tubing.
	for i in gates.size():
		for j in range(i + 1, gates.size()):
			if not _rings_intersect(gates[i], gates[j]):
				continue
			out.append(BuildWarning.limiting(RINGS_INTERSECT,
				"Gates %d and %d overlap — their rings pass through each other." % [i + 1, j + 1],
				{"gates": [i + 1, j + 1],
					"separation_m": float(gates[i]["position"].distance_to(gates[j]["position"]))}))

	# A gate sitting on the straight line between two others. The pilot flies through a ring that
	# is not the one due, which scores nothing and — worse — trains the wrong line. Measured with
	# the course's OWN passage test rather than a second piece of geometry, so a route that
	# "passes through" a gate here is a route that would actually score it if it were due.
	for i in gates.size():
		var from: Vector3 = gates[i]["position"]
		var next_index := (i + 1) % gates.size()
		var to: Vector3 = gates[next_index]["position"]
		for j in gates.size():
			if j == i or j == next_index:
				continue
			if not GateCourse.segment_passes_gate(from, to, gates[j]):
				continue
			out.append(BuildWarning.limiting(ROUTE_THROUGH_GATE,
				"The line from gate %d to gate %d runs through gate %d." % [
					i + 1, next_index + 1, j + 1],
				{"leg": [i + 1, next_index + 1], "through": j + 1}))

	# A leg that runs through an obstacle's solid. Flyable in the sense that the geometry lets you
	# take the next gate, but the straight line between them is blocked — the honest word is
	# "limiting", the same as a gate you have to route around rather than one you cannot pass.
	# Sampled the WHOLE segment (`intersects_segment`), not just its endpoints — check 4 (a leg
	# that goes round the wall raises nothing) only holds because a leg that clips a wall in the
	# middle is still caught.
	var obstacles := _obstacles_of(p_site)
	if not obstacles.is_empty():
		for i in gates.size():
			var from: Vector3 = gates[i]["position"]
			var next_index := (i + 1) % gates.size()
			var to: Vector3 = gates[next_index]["position"]
			for obstacle in obstacles:
				if not obstacle.intersects_segment(from, to):
					continue
				out.append(BuildWarning.limiting(ROUTE_THROUGH_OBSTACLE,
					"The line from gate %d to gate %d runs through an obstacle." % [
						i + 1, next_index + 1],
					{"leg": [i + 1, next_index + 1]}))

	# A gate or a leg that leaves the site's own ground. Arithmetic against a stated size —
	# `Terrain.contains()`, the same boundary `height_at` clamps to — never a second rule for
	# "outside": going THROUGH `half_extent()` is what keeps a negative width from reading as
	# inside on one call and outside on another (see terrain.gd's header). Inclusive on the
	# boundary, the same hair `Site.contains()` already promises.
	var terrain := _terrain_of(p_site)
	if terrain != null:
		for i in gates.size():
			var from: Vector3 = gates[i]["position"]
			var next_index := (i + 1) % gates.size()
			var to: Vector3 = gates[next_index]["position"]
			if not _leg_leaves_extent(from, to, terrain):
				continue
			out.append(BuildWarning.limiting(OUTSIDE_SITE_EXTENT,
				"The line from gate %d to gate %d leaves the site." % [i + 1, next_index + 1],
				{"leg": [i + 1, next_index + 1]}))

	return out


## Whether any point along `from` -> `to`, sampled every `EXTENT_SAMPLE_STEP_M`, falls outside
## `terrain`'s own extent. Endpoints included, so a gate placed outside the boundary is caught even
## on a course of one leg back to itself.
static func _leg_leaves_extent(from: Vector3, to: Vector3, terrain: Terrain) -> bool:
	var length := from.distance_to(to)
	var steps := maxi(1, ceili(length / EXTENT_SAMPLE_STEP_M))
	for i in steps + 1:
		var point := from.lerp(to, float(i) / float(steps))
		if not terrain.contains(point.x, point.z):
			return true
	return false


## The terrain's obstacles, or an empty list for a site that is not there. One place, matching
## `_terrain_of` right below it, so "no site means nothing standing" is a single statement.
static func _obstacles_of(p_site: Site) -> Array[Obstacle]:
	var out: Array[Obstacle] = []
	if p_site != null:
		out = p_site.obstacles
	return out


## True when the two rings' tubing collides. Sampled off the ring curves rather than solved
## analytically, and the two circles' actual closed curves rather than their discs: two hoops whose
## discs overlap but which sit a metre apart along the course do not touch, and calling that an
## overlap would fire on most of a tightly-packed but perfectly good course.
static func _rings_intersect(a: Dictionary, b: Dictionary) -> bool:
	var centre_a: Vector3 = a["position"]
	var centre_b: Vector3 = b["position"]
	var radius_a := float(a["radius"])
	var radius_b := float(b["radius"])
	var touching := GateCourse.RING_THICKNESS_M * 2.0

	# Cheap necessary condition first: two rings further apart than the sum of their radii cannot
	# have their curves meet, whatever their orientations.
	if centre_a.distance_to(centre_b) > radius_a + radius_b + touching:
		return false

	var samples_a := _ring_points(a)
	var samples_b := _ring_points(b)
	for point_a in samples_a:
		for point_b in samples_b:
			if point_a.distance_to(point_b) <= touching:
				return true
	return false


## Points around a gate's ring, in world space.
static func _ring_points(gate: Dictionary) -> Array[Vector3]:
	var normal: Vector3 = gate["normal"]
	var centre: Vector3 = gate["position"]
	var radius := float(gate["radius"])
	# Any two axes spanning the ring's plane will do; the ring is a circle and has no preferred
	# start. UP is never parallel to a gate normal, which is flat by construction (make_gate).
	var right := normal.cross(Vector3.UP).normalized()
	var up := right.cross(normal).normalized()

	var out: Array[Vector3] = []
	for i in RING_SAMPLES:
		var angle := TAU * float(i) / float(RING_SAMPLES)
		out.append(centre + (right * cos(angle) + up * sin(angle)) * radius)
	return out


# ---------------------------------------------------------------------------
# Characteristic — what this course IS
# ---------------------------------------------------------------------------

static func _characteristic(course: GateCourse) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var gates := course.gates

	var route_length_m := 0.0
	for i in gates.size():
		route_length_m += float(gates[i]["position"].distance_to(
			gates[(i + 1) % gates.size()]["position"]))
	out.append(BuildWarning.characteristic(ROUTE_LENGTH,
		"A lap is %.0f m over %d gates." % [route_length_m, gates.size()],
		{"route_length_m": route_length_m, "gate_count": gates.size()}))

	# The sharpest change of heading the route demands, measured in the horizontal plane. Heading
	# is what a turn IS to a pilot — the climb or descent between two gates is a separate thing and
	# folding it in here would report a gentle corner taken uphill as a tight one.
	#
	# Reported, never judged. There is no angle above which a course is "too tight": a hairpin is a
	# thing people build tracks around, and the frame bench has already put a number on why one
	# aircraft takes it and another does not (41x roll inertia across the catalog).
	if gates.size() >= 3:
		var tightest_deg := 0.0
		var tightest_gate := 1
		for i in gates.size():
			var previous: Vector3 = gates[(i - 1 + gates.size()) % gates.size()]["position"]
			var here: Vector3 = gates[i]["position"]
			var next: Vector3 = gates[(i + 1) % gates.size()]["position"]
			var incoming := _flat(here - previous)
			var outgoing := _flat(next - here)
			if incoming.length() < 0.001 or outgoing.length() < 0.001:
				continue
			var turn_deg := rad_to_deg(incoming.angle_to(outgoing))
			if turn_deg > tightest_deg:
				tightest_deg = turn_deg
				tightest_gate = i + 1
		out.append(BuildWarning.characteristic(TIGHTEST_TURN,
			"The tightest corner is %.0f deg, at gate %d." % [tightest_deg, tightest_gate],
			{"turn_deg": tightest_deg, "gate": tightest_gate}))

	return out


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
