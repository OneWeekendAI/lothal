class_name ReadyToCut
extends RefCounted
## Can a router actually cut this plate as drawn? Airframe gaps G3, the ready-to-cut check.
##
## ## What the cutter cannot do
##
## Carbon plate is routed with a ROUND end mill. Its centre follows a path offset from the part by
## the bit's radius, so wherever the part's edge turns away from the bit — an INSIDE corner, where
## the material wraps around the cut — the bit cannot get into the corner and leaves a fillet of its
## own radius behind. And wherever the cut region is narrower than the bit, the bit does not fit at
## all. Outer corners are fine: the bit swings round them and the corner comes out sharp.
##
## None of this blocks anything (warn, never block). A fillet the bit leaves is often harmless; a
## corner where a part was meant to seat square, or a slot a strap was meant to pass through, is not.
## The warning says which, the builder decides, and `FrameEdits.round_inside_corner` is the optional
## fix: it draws the fillet the bit would have left anyway, so the mass, the 3D view and the export
## all describe the part that comes back from the shop.
##
## ## Which side is material — one rule for outlines and holes
##
## In the document's normal winding (outline counter-clockwise, holes clockwise — §3.1), walking along
## ANY contour puts the material on your LEFT: inside an outline, outside a hole. So an inside corner
## of the material is a RIGHT turn on any contour, outline or hole, and the cut side of every edge is
## its right-hand side. An outline stored clockwise flips all of it, which is what `orientation()`
## carries. One rule, no special case for holes: a hole's corners are inside corners because the
## bit is cutting from inside the hole.
##
## ## The local fillet radius
##
## A polygon has no curves, only vertices. A drawn fillet is a RUN of consecutive inside-turning
## vertices that sample an arc; a sharp corner is a run of one. So the radius of a corner is read off
## its run: `step` = the run's total turn over its internal edges, the mean chord over those edges,
## and the circle that chord subtends at that step, `R = c / (2 sin(step/2))` — exact for the arcs
## `PolygonProps.tessellate_arc` produces. A run of one vertex has no internal edge: radius ZERO.
##
## A run is only believed to be an arc if it looks like one: no step coarser than 60°, a sagitta under
## `ARC_FIT_TOLERANCE_MM`, chords within a factor of two of each other, and turns within half a step of
## the mean. Otherwise, if the run's edges disagree in length, it is opened at its longest edge (arcs
## joined by straight runs — a rounded slot turns one way all the way round); if they agree, the vertex
## that turns hardest is a sharp corner (radius 0). Either way the pieces are judged again. That is what stops a rectangular notch — two 90° turns joined by a
## 10 mm edge — reading as one 3 mm-radius "arc" and passing.

const TIGHT_CORNER := &"cut_corner_tighter_than_bit"
const NARROW_GAP := &"cut_gap_narrower_than_bit"

## The outline's contour index; a hole's is its index in the plate's `holes`.
const OUTLINE := -1

## A corner whose radius is within this of the bit's counts as following it, mm. Covers float32
## read-back of a fillet drawn at exactly the bit radius (~1e-6 mm), and nothing a cutter could see.
const RADIUS_TOLERANCE_MM := 0.001
## A corner whose uncut fillet is shallower than this is not worth a warning, mm. It is how a vertex
## that turns by a degree on an imported curve stays quiet: the bit misses it by microns.
const MIN_LEFTOVER_MM := 0.02
## A gap within this of the bit diameter still counts as passing, mm.
const GAP_TOLERANCE_MM := 0.01

## Arc-run acceptance (see class docs).
const MAX_ARC_STEP_RAD := PI / 3.0
const ARC_FIT_TOLERANCE_MM := 0.25

## Two walls "face" each other across a gap when both their cut-side normals point along the line
## between them to within 20°. Walls of a slot face at 0°; neighbouring facets of a round hole are
## a few tens of degrees apart and must not read as a gap.
const FACING_COS := 0.94

const _ANGLE_EPS := 1.0e-9


## +1 when the plate's outline is wound the document's normal way (counter-clockwise), -1 if not.
static func orientation(plate: Dictionary) -> float:
	return -1.0 if PolygonProps.area(AirframeDocument.plate_outline(plate)) < 0.0 else 1.0


## Every contour of a plate as {"index": OUTLINE or hole index, "points": PackedVector2Array}.
static func contours(plate: Dictionary) -> Array:
	var out: Array = []
	var outline := AirframeDocument.plate_outline(plate)
	if outline.size() >= 3:
		out.append({"index": OUTLINE, "points": outline})
	var holes := AirframeDocument.plate_holes(plate)
	for index in holes.size():
		if (holes[index] as PackedVector2Array).size() >= 3:
			out.append({"index": index, "points": holes[index]})
	return out


## One contour's points, by index.
static func contour_points(plate: Dictionary, contour_index: int) -> PackedVector2Array:
	if contour_index == OUTLINE:
		return AirframeDocument.plate_outline(plate)
	var holes := AirframeDocument.plate_holes(plate)
	if contour_index < 0 or contour_index >= holes.size():
		return PackedVector2Array()
	return holes[contour_index]


## Signed turn at each vertex, radians: POSITIVE for an inside corner of the material (a right turn
## in the normal winding), negative for an outer corner, zero on a straight run or a zero-length edge.
static func turns(points: PackedVector2Array, orient: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var n := points.size()
	out.resize(n)
	for i in n:
		var d_in := points[i] - points[(i - 1 + n) % n]
		var d_out := points[(i + 1) % n] - points[i]
		if d_in.length_squared() < 1e-18 or d_out.length_squared() < 1e-18:
			out[i] = 0.0
			continue
		out[i] = -atan2(d_in.cross(d_out), d_in.dot(d_out)) * orient
	return out


## Every inside corner of one contour: {"first", "last", "count", "turn_rad", "radius_mm", "point"}.
## `first`..`last` is the run of vertices (cyclic, in stored order); a sharp corner has first == last
## and radius 0.
static func corners(points: PackedVector2Array, orient: float) -> Array:
	var out: Array = []
	var n := points.size()
	if n < 3:
		return out
	var turn := turns(points, orient)
	var inside: Array[bool] = []
	var any_inside := false
	var all_inside := true
	for i in n:
		var flag := turn[i] > _ANGLE_EPS
		inside.append(flag)
		any_inside = any_inside or flag
		all_inside = all_inside and flag
	if not any_inside:
		return out
	if all_inside:
		var every: Array[int] = []
		for i in n:
			every.append(i)
		_resolve(points, turn, every, true, out)
		return out
	# Start just after an outside/straight vertex so no run is cut in two by the array's end.
	var start := 0
	while inside[start]:
		start += 1
	var run: Array[int] = []
	for step in n:
		var i := (start + 1 + step) % n
		if inside[i]:
			run.append(i)
		elif not run.is_empty():
			_resolve(points, turn, run, false, out)
			run = []
	if not run.is_empty():
		_resolve(points, turn, run, false, out)
	return out


## The inside corners of one contour that a bit of `bit_mm` diameter cannot follow, each with the
## depth of material it leaves in the corner, `depth_mm`. Runs that turn through 180° or more (slot
## ends, whole round holes) are left to `narrowest_gap`: whether a bit fits there is a width question.
static func tight_corners(points: PackedVector2Array, orient: float, bit_mm: float) -> Array:
	var out: Array = []
	var bit_r := bit_mm * 0.5
	for corner in corners(points, orient):
		var turn: float = corner["turn_rad"]
		var radius: float = corner["radius_mm"]
		if turn >= PI - 1e-6 or radius >= bit_r - RADIUS_TOLERANCE_MM:
			continue
		var depth := leftover_mm(radius, turn, bit_r)
		if depth <= MIN_LEFTOVER_MM:
			continue
		var entry: Dictionary = corner.duplicate()
		entry["depth_mm"] = depth
		out.append(entry)
	return out


## How far into a corner of radius `radius_mm`, turning through `turn_rad`, the bit fails to reach:
## the bit's centre sits `r/cos(θ/2)` from a sharp corner, so it misses by `r(1/cos(θ/2) - 1)`, and a
## fillet of radius R shrinks that by the homothety (r - R).
static func leftover_mm(radius_mm: float, turn_rad: float, bit_radius_mm: float) -> float:
	var half := clampf(turn_rad, 0.0, PI - 1e-6) * 0.5
	return maxf(bit_radius_mm - radius_mm, 0.0) * (1.0 / cos(half) - 1.0)


## The narrowest place on one contour where two walls face each other across the CUT side closer
## than `limit_mm`: {"width_mm", "at"} or {} if there is none. Adjacent edges are a corner, not a gap,
## and are never compared.
static func narrowest_gap(points: PackedVector2Array, orient: float, limit_mm: float) -> Dictionary:
	var n := points.size()
	if n < 4 or limit_mm <= 0.0:
		return {}
	# Edges bucketed into a grid one limit wide, so only walls that could be within `limit_mm` of
	# each other are ever compared — an imported outline can carry thousands of vertices.
	var cell := maxf(limit_mm, 0.5)
	var grid: Dictionary = {}
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var lo := Vector2i(floori((minf(a.x, b.x) - limit_mm) / cell),
			floori((minf(a.y, b.y) - limit_mm) / cell))
		var hi := Vector2i(floori((maxf(a.x, b.x) + limit_mm) / cell),
			floori((maxf(a.y, b.y) + limit_mm) / cell))
		for gx in range(lo.x, hi.x + 1):
			for gy in range(lo.y, hi.y + 1):
				var key := Vector2i(gx, gy)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(i)
	var best := {}
	var seen: Dictionary = {}
	for key in grid:
		var bucket: Array = grid[key]
		for x in bucket.size():
			for y in range(x + 1, bucket.size()):
				var i: int = bucket[x]
				var j: int = bucket[y]
				if i == j or (i + 1) % n == j or (j + 1) % n == i:
					continue
				var pair := mini(i, j) * n + maxi(i, j)
				if seen.has(pair):
					continue
				seen[pair] = true
				var found := _facing_gap(points, orient, i, j, limit_mm)
				if found.is_empty():
					continue
				if best.is_empty() or float(found["width_mm"]) < float(best["width_mm"]):
					best = found
	return best


## Every ready-to-cut warning for a document: per plate, one for its tight inside corners and one for
## its narrowest gap. LIMITING: the part can be made, but not as drawn, and the message names where.
static func warnings(document: AirframeDocument) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if document == null:
		return out
	var bit := bit_diameter_mm(document)
	for plate_index in document.plates.size():
		var plate: Dictionary = document.plates[plate_index]
		var orient := orientation(plate)
		var tight: Array = []
		var gap := {}
		for contour in contours(plate):
			for corner in tight_corners(contour["points"], orient, bit):
				var entry: Dictionary = corner
				entry["contour"] = contour["index"]
				tight.append(entry)
			var found := narrowest_gap(contour["points"], orient, bit)
			if not found.is_empty() and (gap.is_empty()
					or float(found["width_mm"]) < float(gap["width_mm"])):
				gap = found
				gap["contour"] = contour["index"]
		var label := plate_label(document, plate_index)
		if not tight.is_empty():
			var deepest := 0.0
			for corner in tight:
				deepest = maxf(deepest, float(corner["depth_mm"]))
			out.append(BuildWarning.limiting(TIGHT_CORNER,
				("%s: %d inside corner%s sharper than the %.2f mm cutting bit can follow — the router " +
				"leaves up to %.2f mm of material in %s. Round %s to %.2f mm, or expect that fillet " +
				"on the cut part.") % [label, tight.size(), "" if tight.size() == 1 else "s",
					bit, deepest, "it" if tight.size() == 1 else "them",
					"it" if tight.size() == 1 else "them", bit * 0.5],
				{"plate": plate_index, "corners": tight, "bit_mm": bit, "depth_mm": deepest}))
		if not gap.is_empty():
			out.append(BuildWarning.limiting(NARROW_GAP,
				"%s: a gap %.2f mm wide is narrower than the %.2f mm cutting bit, which cannot cut it."
					% [label, float(gap["width_mm"]), bit],
				{"plate": plate_index, "width_mm": gap["width_mm"], "at": gap["at"],
					"contour": gap["contour"], "bit_mm": bit}))
	return out


## The document's bit, guarded: a zero or negative setting reads as the default rather than as a bit
## that fits everywhere.
static func bit_diameter_mm(document: AirframeDocument) -> float:
	if document == null or document.cutting_bit_mm <= 0.0:
		return AirframeDocument.DEFAULT_CUTTING_BIT_MM
	return document.cutting_bit_mm


## "Plate 2 (bottom)" — how a warning and an export note name a plate.
static func plate_label(document: AirframeDocument, plate_index: int) -> String:
	var role := ""
	if document != null and plate_index >= 0 and plate_index < document.plates.size():
		role = str((document.plates[plate_index] as Dictionary).get("role", ""))
	return "Plate %d (%s)" % [plate_index + 1, role] if not role.is_empty() \
		else "Plate %d" % (plate_index + 1)


## The corner whose run contains `vertex_index`, or {} if that vertex is not an inside corner.
static func corner_at(points: PackedVector2Array, orient: float, vertex_index: int) -> Dictionary:
	var n := points.size()
	for corner in corners(points, orient):
		var first: int = corner["first"]
		var count: int = corner["count"]
		for k in count:
			if (first + k) % n == vertex_index:
				return corner
	return {}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _resolve(points: PackedVector2Array, turn: PackedFloat64Array, run: Array[int],
		cyclic: bool, out: Array) -> void:
	var k := run.size()
	if k == 0:
		return
	if k == 1:
		out.append(_corner(points, run, turn[run[0]], 0.0))
		return
	var edges := k if cyclic else k - 1
	var total := 0.0
	for index in run:
		total += turn[index]
	var chord_sum := 0.0
	var lengths: Array[float] = []
	for j in edges:
		var length := points[run[j]].distance_to(points[run[(j + 1) % k]])
		lengths.append(length)
		chord_sum += length
	var step := total / float(edges)
	var chord := chord_sum / float(edges)
	var consistent := step > 0.0 and step <= MAX_ARC_STEP_RAD and chord > 0.0
	var radius := 0.0
	if consistent:
		radius = chord / (2.0 * sin(step * 0.5))
		consistent = radius * (1.0 - cos(step * 0.5)) <= ARC_FIT_TOLERANCE_MM
	if consistent:
		for length in lengths:
			if length < chord * 0.5 or length > chord * 2.0:
				consistent = false
	var hardest := 0
	for j in k:
		var t: float = turn[run[j]]
		if t > turn[run[hardest]]:
			hardest = j
		var is_end := not cyclic and (j == 0 or j == k - 1)
		if t > step * 1.5 or (not is_end and t < step * 0.5):
			consistent = false
	if consistent:
		out.append(_corner(points, run, total, radius))
		return
	# Not one arc. If its edges disagree in length, it is arcs joined by straight runs whose ends
	# happen to turn the same way (a rounded slot is one such run all the way round): open it at
	# the longest edge, which removes no vertex, and judge each side again.
	var longest := 0
	var shortest := INF
	for j in edges:
		if lengths[j] > lengths[longest]:
			longest = j
		shortest = minf(shortest, lengths[j])
	if edges >= 2 and lengths[longest] > shortest * 2.0:
		var left_part: Array[int] = []
		var right_part: Array[int] = []
		if cyclic:
			for m in k:
				left_part.append(run[(longest + 1 + m) % k])
		else:
			for j in k:
				if j <= longest:
					left_part.append(run[j])
				else:
					right_part.append(run[j])
		_resolve(points, turn, left_part, false, out)
		_resolve(points, turn, right_part, false, out)
		return
	# Otherwise the hardest-turning vertex is a sharp corner, and each side is judged again.
	var single: Array[int] = [run[hardest]]
	out.append(_corner(points, single, turn[run[hardest]], 0.0))
	if cyclic:
		var rest: Array[int] = []
		for m in range(1, k):
			rest.append(run[(hardest + m) % k])
		_resolve(points, turn, rest, false, out)
	else:
		var left: Array[int] = []
		var right: Array[int] = []
		for j in k:
			if j < hardest:
				left.append(run[j])
			elif j > hardest:
				right.append(run[j])
		_resolve(points, turn, left, false, out)
		_resolve(points, turn, right, false, out)


static func _corner(points: PackedVector2Array, run: Array[int], turn_rad: float,
		radius_mm: float) -> Dictionary:
	return {
		"first": run[0],
		"last": run[run.size() - 1],
		"count": run.size(),
		"turn_rad": turn_rad,
		"radius_mm": radius_mm,
		"point": points[run[floori(run.size() * 0.5)]],
	}


static func _facing_gap(points: PackedVector2Array, orient: float, i: int, j: int,
		limit_mm: float) -> Dictionary:
	var n := points.size()
	var a0 := points[i]
	var a1 := points[(i + 1) % n]
	var b0 := points[j]
	var b1 := points[(j + 1) % n]
	var da := a1 - a0
	var db := b1 - b0
	if da.length_squared() < 1e-18 or db.length_squared() < 1e-18:
		return {}
	var closest := Geometry2D.get_closest_points_between_segments(a0, a1, b0, b1)
	var across: Vector2 = closest[1] - closest[0]
	var width := across.length()
	if width < 1e-6 or width >= limit_mm - GAP_TOLERANCE_MM:
		return {}
	# The cut side is the right-hand side in the normal winding (class docs).
	var normal_a := Vector2(da.y, -da.x).normalized() * orient
	var normal_b := Vector2(db.y, -db.x).normalized() * orient
	var direction := across / width
	if normal_a.dot(direction) < FACING_COS or normal_b.dot(-direction) < FACING_COS:
		return {}
	return {"width_mm": width, "at": (closest[0] + closest[1]) * 0.5}
