class_name PolygonProps
extends RefCounted
## Closed-form area integrals of a closed polygon — airframe.md §3.1, the workhorse every
## later slice multiplies by.
##
## UNITS AND CONVENTIONS
##   Inputs are millimetres. Area comes out in mm^2, first moments in mm^3, second moments
##   in mm^4. Nothing here knows about metres, kilograms or Godot's Y-up world: it is plane
##   geometry and nothing else, so it can be tested against textbook answers with no
##   scene, no nodes and no build.
##
##   A COUNTER-CLOCKWISE outline has POSITIVE area. That single sentence is the whole hole
##   mechanism: wind a hole the other way and its area, its first moments and its second
##   moments all come out negative, so an outline plus its holes is a plain sum. There is
##   deliberately no boolean geometry in this file — a bolt hole, a strap slot and a
##   lightening cutout are the same operation as the outline, which is why the annulus test
##   is the one that proves the design rather than merely exercising it.
##
##   Second moments are AREA moments (∫y² dA), not mass moments. Multiplying by ρ·t happens
##   in §3.4, not here, so that this file stays material-agnostic and a plate of any
##   thickness reuses the same integral.
##
##   `second_moments()` is about the ORIGIN because that is the form that sums across parts
##   sitting at different places on the plate. `second_moments_centroidal()` is what beam
##   and inertia maths actually wants. Both are exposed rather than only the centroidal one:
##   summing centroidal moments of several polygons is a classic silent error, and having
##   the origin form named makes the correct composition path the obvious one.

## Below this the polygon is treated as degenerate: a signed area smaller than this is
## indistinguishable from a line for anything downstream. In mm^2 this is a hundredth of a
## square micron, far under any real cut feature, so it only ever catches genuine
## degeneracy — never a small-but-real bolt hole.
const AREA_EPSILON := 1e-9

## Default chord tolerance for tessellating curves, in millimetres. 0.1 mm is finer than
## any CNC router will hold, so the polygon is not an approximation of the design — it is
## an exact description of the part that actually gets cut.
const DEFAULT_CHORD_TOLERANCE_MM := 0.1

## Even a tolerance that would mathematically allow a triangle gets this many segments, so
## a "circle" never degenerates into something with visible corners in the 3D view. Curves
## feed both the maths and the extrusion, and the extrusion has the stricter eye.
const MIN_ARC_SEGMENTS := 8

## Guards against a caller passing an absurdly tight tolerance on a large radius and
## silently generating a million-vertex polygon that stalls the editor.
const MAX_ARC_SEGMENTS := 4096


## Signed shoelace area. Positive for counter-clockwise, negative for clockwise — the sign
## is the point, not an artefact, so it is never abs()'d here.
static func area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var total := 0.0
	var n := points.size()
	for i in n:
		var p := points[i]
		var q := points[(i + 1) % n]
		total += p.x * q.y - q.x * p.y
	return 0.5 * total


## Area centroid. Independent of winding: both the numerator and the denominator flip sign
## with the winding, so a reversed outline describes the same place. A degenerate polygon
## has no centroid to speak of, and returning the vertex average instead of dividing by a
## zero area keeps a caller from propagating INF through a CG sum.
static func centroid(points: PackedVector2Array) -> Vector2:
	var a := area(points)
	if points.size() < 3 or absf(a) < AREA_EPSILON:
		return _vertex_average(points)

	var acc := Vector2.ZERO
	var n := points.size()
	for i in n:
		var p := points[i]
		var q := points[(i + 1) % n]
		var cross := p.x * q.y - q.x * p.y
		acc += (p + q) * cross
	return acc / (6.0 * a)


## Second moments about the ORIGIN: {"ixx": ∫y² dA, "iyy": ∫x² dA, "ixy": ∫xy dA}.
##
## `ixy` is the term nobody notices being wrong, because every axis-aligned test shape has
## `ixy == 0` and so does a wrong implementation. It is only a rotated shape that separates
## them, which is why the test suite carries a 30° case.
static func second_moments(points: PackedVector2Array) -> Dictionary:
	if points.size() < 3:
		return {"ixx": 0.0, "iyy": 0.0, "ixy": 0.0}

	var ixx := 0.0
	var iyy := 0.0
	var ixy := 0.0
	var n := points.size()
	for i in n:
		var p := points[i]
		var q := points[(i + 1) % n]
		var cross := p.x * q.y - q.x * p.y
		ixx += (p.y * p.y + p.y * q.y + q.y * q.y) * cross
		iyy += (p.x * p.x + p.x * q.x + q.x * q.x) * cross
		ixy += (p.x * q.y + 2.0 * p.x * p.y + 2.0 * q.x * q.y + q.x * p.y) * cross

	return {"ixx": ixx / 12.0, "iyy": iyy / 12.0, "ixy": ixy / 24.0}


## The same moments shifted to the polygon's own centroid by the parallel-axis theorem.
## Signed area is used, not its magnitude, so this stays correct for a clockwise hole:
## a hole's centroidal moments must come out negative for the sum-of-parts rule to hold.
static func second_moments_centroidal(points: PackedVector2Array) -> Dictionary:
	var m := second_moments(points)
	var a := area(points)
	if points.size() < 3 or absf(a) < AREA_EPSILON:
		return m
	var c := centroid(points)
	return {
		"ixx": float(m["ixx"]) - a * c.y * c.y,
		"iyy": float(m["iyy"]) - a * c.x * c.x,
		"ixy": float(m["ixy"]) - a * c.x * c.y,
	}


## Outline plus holes, as one region. Returns
## {"area", "centroid", "ixx", "iyy", "ixy", "ixx_c", "iyy_c", "ixy_c"} — origin moments and
## centroidal moments of the COMPOSITE, which is not the sum of the parts' centroidal
## moments and never can be. That is exactly why this function exists rather than leaving
## callers to add up `second_moments_centroidal()` results and get a plausible wrong answer.
##
## Holes must be wound opposite to the outline. This is not validated and deliberately so:
## the same summation is what supports an outline made of several disjoint plates, and a
## rule that "fixed" winding would quietly make a two-lobed region impossible to express.
## Callers that want the check should compare `sign(area(hole))` themselves.
static func region_properties(outline: PackedVector2Array, holes: Array = []) -> Dictionary:
	var a := area(outline)
	var m := second_moments(outline)
	var ixx := float(m["ixx"])
	var iyy := float(m["iyy"])
	var ixy := float(m["ixy"])
	# First moments about the origin, accumulated as area*centroid so that the composite
	# centroid falls out of a single division at the end.
	var qx := a * centroid(outline).x
	var qy := a * centroid(outline).y

	for hole in holes:
		var h: PackedVector2Array = hole
		var ha := area(h)
		var hm := second_moments(h)
		var hc := centroid(h)
		a += ha
		qx += ha * hc.x
		qy += ha * hc.y
		ixx += float(hm["ixx"])
		iyy += float(hm["iyy"])
		ixy += float(hm["ixy"])

	var c := Vector2.ZERO
	if absf(a) >= AREA_EPSILON:
		c = Vector2(qx / a, qy / a)

	return {
		"area": a,
		"centroid": c,
		"ixx": ixx,
		"iyy": iyy,
		"ixy": ixy,
		"ixx_c": ixx - a * c.y * c.y,
		"iyy_c": iyy - a * c.x * c.x,
		"ixy_c": ixy - a * c.x * c.y,
	}


## Points along an arc, from `start_rad` sweeping `sweep_rad` (positive = counter-clockwise),
## at a stated maximum chord deviation. Both endpoints are included, so an arc can be
## spliced into an outline between two straight runs without a duplicate or a gap.
##
## The segment count comes from the sagitta, r·(1 − cos(Δ/2)) ≤ tol, rather than from a
## fixed "segments per circle": tolerance is a property of the machine, and tying vertex
## count to radius is what keeps a 2 mm bolt hole cheap while a 200 mm outline arc stays
## smooth.
## The shortest distance from a point to a polygon's boundary, mm. Always positive — this is the
## distance to the EDGE, not a signed inside/outside test, and a hole centre is meant to be inside.
##
## `HardwareMass.hole_to_edge_warning` names this "the geometry kernel's job to supply" and has been
## taking a hand-derived stand-in ever since: the Fasteners tab computed a margin from the arm
## generator's own padding constant, which is right for a generated preset and answers nothing about
## a frame somebody drew. This is the real measurement, so the tear-out check now reads the outline
## a builder actually cut.
static func distance_to_boundary(outline: PackedVector2Array, point: Vector2) -> float:
	var count := outline.size()
	if count < 2:
		return 0.0
	var best := INF
	for i in range(count):
		best = minf(best, _distance_to_segment(point, outline[i], outline[(i + 1) % count]))
	return best


## Point-to-segment distance, clamped at both ends so a point beyond an edge measures to that edge's
## nearer endpoint rather than to the infinite line through it.
static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span := b - a
	var length_squared := span.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(a)
	var t := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * t)


static func tessellate_arc(
	centre: Vector2,
	radius: float,
	start_rad: float,
	sweep_rad: float,
	chord_tolerance_mm: float = DEFAULT_CHORD_TOLERANCE_MM
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius <= 0.0 or is_zero_approx(sweep_rad):
		return out

	var segments := _segments_for(radius, absf(sweep_rad), chord_tolerance_mm)
	for i in segments + 1:
		var t := start_rad + sweep_rad * (float(i) / float(segments))
		out.append(centre + Vector2(cos(t), sin(t)) * radius)
	return out


## A closed circle as a polygon. `clockwise` produces the negative-area winding a hole
## needs, so a bolt hole is `tessellate_circle(p, r, tol, true)` and nothing else.
##
## The closing vertex is NOT repeated — every function here wraps indices — because a
## duplicated last point contributes a zero-length edge that is harmless to the integrals
## but shows up as a degenerate triangle the moment the outline is extruded.
static func tessellate_circle(
	centre: Vector2,
	radius: float,
	chord_tolerance_mm: float = DEFAULT_CHORD_TOLERANCE_MM,
	clockwise: bool = false
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius <= 0.0:
		return out

	var segments := _segments_for(radius, TAU, chord_tolerance_mm)
	var direction := -1.0 if clockwise else 1.0
	for i in segments:
		var t := direction * TAU * (float(i) / float(segments))
		out.append(centre + Vector2(cos(t), sin(t)) * radius)
	return out


## Reverses winding. Used to turn an authored outline into a hole without the caller
## re-deriving the point order — and, in the tests, to prove the centroid is winding-blind.
static func reversed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		out.append(points[i])
	return out


static func _segments_for(radius: float, sweep_rad: float, chord_tolerance_mm: float) -> int:
	var tol := maxf(chord_tolerance_mm, 1e-6)
	var segments := MIN_ARC_SEGMENTS
	if tol < radius:
		# sagitta = r(1 - cos(Δ/2)) ≤ tol  ⇒  Δ ≤ 2·acos(1 - tol/r)
		var max_step := 2.0 * acos(1.0 - tol / radius)
		if max_step > 0.0:
			segments = int(ceil(sweep_rad / max_step))
	return clampi(segments, MIN_ARC_SEGMENTS, MAX_ARC_SEGMENTS)


static func _vertex_average(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in points:
		acc += p
	return acc / float(points.size())
