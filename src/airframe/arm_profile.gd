class_name ArmProfile
extends RefCounted
## The width of an arm, measured off the arm's own outline — airframe.md §10, question 1.
##
## ## What this file is for
##
## §10 q1 decided that an arm is a plate with a DECLARED CENTRELINE: the axis is authored because a
## polygon cannot tell you which way it is meant to bend, and the width `b(s)` is then MEASURED by
## intersecting the outline with perpendiculars along that axis. This is the measuring half, and it
## is the bridge between the two halves of the whole Airframe design: a shape you draw on the left,
## and `ArmBeam`'s stiffness, resonance and stress on the right.
##
## Until now that bridge did not exist, and the consequence was severe: every beam figure in the app
## came from `frames.json`'s `arm_width_mm`, a field present on ONE of fifteen frames because no
## vendor publishes it (§9a). Fourteen frames therefore showed dashes, and a frame a builder drew
## themselves could show nothing at all — there being no catalog row to read. Measuring the polygon
## removes the dependency entirely: an arm you drew has a width because you drew one.
##
## ## The measurement, in one paragraph
##
## The centreline runs `root_point` → `tip_point` in the plate's own plane, in millimetres. At each
## station `s` along it, take the line through that point perpendicular to the axis, intersect it
## with every edge of the outline, and sort the crossings by their signed offset from the
## centreline. The width is the span of the interval CONTAINING THE CENTRELINE — the nearest
## crossing below zero to the nearest crossing above it — and not the outer extent of all crossings.
## The difference matters exactly where it should: on a solid arm the two are identical, and on an
## arm with a cutout the outer extent reports material that is not there.
##
## ## Why this is not "just" a bounding box, and why it is not a solid modeller either
##
## §0's argument for the whole plate model applies here in miniature. A bounding box would be wrong
## on every tapered arm, which is all of them. A general 2D boolean library would be right and would
## be a dependency and a month. A line-polygon intersection is fifty lines, is exact for the
## straight-edged plates a CNC router actually cuts, and its error on a curved outline is bounded by
## the tessellation `PolygonProps` already applies everywhere else.
##
## ## Millimetres in, millimetres out
##
## Every number in an `AirframeDocument` is in millimetres, and so is everything here. The single
## conversion to metres happens in `beam()`, which is the only function that hands numbers to
## physics — because physics.md §1 keeps the simulation SI, and a unit conversion that happens in
## two places is a unit conversion that eventually happens differently in two places.

## How many stations the width is sampled at, root to tip inclusive.
##
## Seventeen is not a tuning knob and nothing is fitted to it. `ArmBeam.compliance_integral()`
## integrates the AUTHORED breakpoints with panel boundaries on the kinks, so the only error this
## number controls is how finely a curved or stepped outline is followed. Seventeen puts a station
## every 6-7 mm on a 110 mm arm — finer than the features anyone cuts into one — and a straight
## taper is reproduced EXACTLY at any count, which is why the taper test asserts to 1e-6 rather than
## to a tolerance that would have to grow if this changed.
const DEFAULT_STATIONS := 17

## Two numbers within this fraction of the arm's length are the same number — see `tolerance_for`.
const RELATIVE_TOLERANCE := 1.0e-6
## The floor under that fraction, in mm, so a degenerate zero-length arm still has a usable
## tolerance rather than an infinitely strict one.
const ABSOLUTE_TOLERANCE_MM := 1.0e-9


## The width profile of one arm, from an outline stored as flat doubles.
##
## THIS IS THE REAL ENTRY POINT, and the flat `[x0, y0, x1, y1, ...]` shape is not an inconvenience
## to be wrapped away. Godot's `Vector2` IS 32-BIT — `ArmBeam`'s own header spends a paragraph on
## the same fact — and an `AirframeDocument` therefore stores every outline as `PackedFloat64Array`
## rather than as points. Measuring through `Vector2` would silently round every coordinate to about
## seven significant figures, which is 7e-6 mm of noise on a 100 mm arm: invisible in a drawing, and
## enough to make a perpendicular miss the vertex it is supposed to pass through. The measurement
## below is the one place where "the tip station found no material" and "the arm is 7 nanometres
## shorter than you think" are the same event, so it reads the doubles the document actually holds.
##
## Returns `{stations_mm, widths_mm, length_mm, errors}`. `errors` non-empty means the shape and the
## centreline do not describe an arm, and BOTH arrays come back empty rather than partially filled:
## a caller that ignores the errors then gets an obviously broken profile instead of a plausible one
## measured over the half of the arm that happened to work.
static func measure_flat(
	flat_outline: PackedFloat64Array,
	root_x: float, root_y: float,
	tip_x: float, tip_y: float,
	stations: int = DEFAULT_STATIONS
) -> Dictionary:
	var errors: Array[String] = []
	var axis_x := tip_x - root_x
	var axis_y := tip_y - root_y
	var length := sqrt(axis_x * axis_x + axis_y * axis_y)
	var vertices := int(flat_outline.size() / 2.0)

	if length <= 0.0:
		errors.append("centreline has zero length")
	if vertices < 3:
		errors.append("outline has fewer than three points")
	if stations < 2:
		errors.append("a profile needs at least two stations")
	if not errors.is_empty():
		return _failed(errors, length)

	var along_x := axis_x / length
	var along_y := axis_y / length
	# The perpendicular, in the plate's plane. Rotating the axis rather than using a global up
	# vector is the whole reason this file measures the arm you drew: every arm on a generated
	# preset lies on a diagonal, and a global axis would measure the wrong dimension on all of them.
	var across_x := -along_y
	var across_y := along_x
	var tolerance := tolerance_for(length)

	var stations_mm := PackedFloat64Array()
	var widths_mm := PackedFloat64Array()

	for i in range(stations):
		var s := length * float(i) / float(stations - 1)
		var width := _width_at(
			flat_outline,
			root_x + along_x * s, root_y + along_y * s,
			along_x, along_y, across_x, across_y,
			tolerance)
		if width <= 0.0:
			# Not clamped, not skipped. A station with no material on the centreline means the
			# centreline leaves its own plate, and §0's rule is that a number the geometry does not
			# support may not appear. The arm is refused whole.
			errors.append("the centreline leaves the outline at s = %.2f mm" % s)
			return _failed(errors, length)
		stations_mm.append(s)
		widths_mm.append(width)

	return {
		"stations_mm": stations_mm,
		"widths_mm": widths_mm,
		"length_mm": length,
		"errors": errors,
	}


## The same measurement for a caller holding points rather than flat doubles — a test fixture, or
## an editor mid-drag. Lossy by construction (see `measure_flat`), which is why nothing that reads a
## document comes through this door.
static func measure(
	outline: PackedVector2Array,
	root_point: Vector2,
	tip_point: Vector2,
	stations: int = DEFAULT_STATIONS
) -> Dictionary:
	return measure_flat(
		AirframeDocument.flatten(outline),
		root_point.x, root_point.y, tip_point.x, tip_point.y,
		stations)


## How close two numbers have to be before this file calls them equal, in mm, for an arm of the
## given length.
##
## RELATIVE, not absolute, and both halves of that matter. Absolute would have to be chosen for the
## worst case — a 300 mm cinelifter arm carrying float32 noise — and would then be coarse enough to
## merge real features on a 60 mm whoop arm. Relative at 1e-6 is 0.1 micrometres on a 100 mm arm:
## comfortably above the ~1e-5 mm of noise a float32 round-trip leaves behind, and far below
## anything a router can cut, so it can never merge two crossings that are really there.
static func tolerance_for(length_mm: float) -> float:
	return maxf(ABSOLUTE_TOLERANCE_MM, length_mm * RELATIVE_TOLERANCE)


## An `ArmBeam` built from a measured outline, or null when the outline cannot be measured.
##
## THE ONLY UNIT BOUNDARY IN THIS FILE. Millimetres are the document's language and metres are
## physics'; the measurement speaks the first and `ArmBeam` speaks the second, and the conversion
## lives here so that there is exactly one line to get wrong.
static func beam_flat(
	flat_outline: PackedFloat64Array,
	root_x: float, root_y: float,
	tip_x: float, tip_y: float,
	thickness_mm: float,
	material_id: String,
	materials: FrameMaterials,
	tip_mass_kg: float = 0.0
) -> ArmBeam:
	var profile := measure_flat(flat_outline, root_x, root_y, tip_x, tip_y)
	if not profile["errors"].is_empty():
		return null

	var stations_m := PackedFloat64Array()
	var widths_m := PackedFloat64Array()
	for value in profile["stations_mm"]:
		stations_m.append(float(value) / 1000.0)
	for value in profile["widths_mm"]:
		widths_m.append(float(value) / 1000.0)

	var built := ArmBeam.make(
		float(profile["length_mm"]) / 1000.0,
		stations_m,
		widths_m,
		thickness_mm / 1000.0,
		material_id,
		materials,
		tip_mass_kg)
	return built if built.is_valid() else null


## `beam_flat` for a caller holding points. Same lossiness note as `measure`.
static func beam(
	outline: PackedVector2Array,
	root_point: Vector2,
	tip_point: Vector2,
	thickness_mm: float,
	material_id: String,
	materials: FrameMaterials,
	tip_mass_kg: float = 0.0
) -> ArmBeam:
	return beam_flat(
		AirframeDocument.flatten(outline),
		root_point.x, root_point.y, tip_point.x, tip_point.y,
		thickness_mm, material_id, materials, tip_mass_kg)


# ---------------------------------------------------------------------------
# The intersection itself
# ---------------------------------------------------------------------------

## The width of the material the centreline passes through, at one station. Zero when the
## centreline is outside the outline there, which the caller treats as a refusal.
static func _width_at(
	flat_outline: PackedFloat64Array,
	origin_x: float, origin_y: float,
	along_x: float, along_y: float,
	across_x: float, across_y: float,
	tolerance: float
) -> float:
	var offsets := _crossings(
		flat_outline, origin_x, origin_y, along_x, along_y, across_x, across_y, tolerance)
	if offsets.size() < 2:
		return 0.0

	# The span containing the centreline, which is offset zero. Walking outwards from zero rather
	# than taking min/max is what makes a cutout narrow the arm instead of being invisible.
	var below := -INF
	var above := INF
	for offset in offsets:
		if offset <= 0.0:
			below = maxf(below, offset)
		if offset >= 0.0:
			above = minf(above, offset)
	if below == -INF or above == INF:
		return 0.0
	return above - below


## Signed offsets, along the perpendicular, of every point where the cutting line through the
## station crosses an edge of the outline. Sorted and de-duplicated.
static func _crossings(
	flat_outline: PackedFloat64Array,
	origin_x: float, origin_y: float,
	along_x: float, along_y: float,
	across_x: float, across_y: float,
	tolerance: float
) -> PackedFloat64Array:
	var offsets := PackedFloat64Array()
	var count := int(flat_outline.size() / 2.0)

	for i in range(count):
		var j := (i + 1) % count
		var ax := flat_outline[i * 2]
		var ay := flat_outline[i * 2 + 1]
		var bx := flat_outline[j * 2]
		var by := flat_outline[j * 2 + 1]
		# Distance of each endpoint from the cutting line, along the arm. Snapped to the tolerance,
		# because a perpendicular through a polygon VERTEX lands on it to within rounding rather
		# than exactly, and at the root and tip stations that rounding is what decides whether the
		# station finds two crossings or none.
		var da := _snapped((ax - origin_x) * along_x + (ay - origin_y) * along_y, tolerance)
		var db := _snapped((bx - origin_x) * along_x + (by - origin_y) * along_y, tolerance)
		var span := da - db
		# An edge lying IN the cutting line contributes no crossing of its own: both of its
		# endpoints are found by the two edges either side of it, and dividing by this span would be
		# a division by zero. This is the case at the blunt root of every rectangular arm.
		if span == 0.0:
			continue
		# Inclusive on both ends, deliberately. The root and tip stations sit exactly on a polygon
		# vertex, and a strict straddle test drops them and reports a zero-width arm at precisely
		# the two stations that matter most — the root, where the moment is largest, and the tip,
		# where the motor bolts on. Duplicates from shared vertices are merged below.
		if (da <= 0.0 and db >= 0.0) or (db <= 0.0 and da >= 0.0):
			var u := da / span
			var px := ax + (bx - ax) * u
			var py := ay + (by - ay) * u
			offsets.append((px - origin_x) * across_x + (py - origin_y) * across_y)

	offsets.sort()
	return _merged(offsets, tolerance)


## Adjacent offsets within the tolerance collapsed to one. Input must be sorted.
static func _merged(sorted_offsets: PackedFloat64Array, tolerance: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for offset in sorted_offsets:
		if out.is_empty() or absf(offset - out[out.size() - 1]) > tolerance:
			out.append(offset)
	return out


## Values within the tolerance of zero ARE zero, so that an inclusive straddle test stays inclusive
## after a rotation.
static func _snapped(value: float, tolerance: float) -> float:
	return 0.0 if absf(value) <= tolerance else value


static func _failed(errors: Array[String], length_mm: float) -> Dictionary:
	return {
		"stations_mm": PackedFloat64Array(),
		"widths_mm": PackedFloat64Array(),
		"length_mm": length_mm,
		"errors": errors,
	}
