class_name FrameEdits
extends RefCounted
## Every change the plan editor can make to a frame — airframe.md §7.1, slice A7.
##
## ## Pure on purpose
##
## Nothing here is a Node, nothing here draws, and nothing here reads a mouse. An edit is a function
## from a document to the same document changed, which is what lets `test_frame_edits.gd` prove the
## whole editor headless: drag a corner and assert the mass doubled, insert a vertex and assert the
## area did not move. The canvas above this file decides WHERE the mouse is; this file decides what
## that means for the geometry, and the split is why the risky half is the testable half.
##
## ## Millimetres, and doubles
##
## Same contract as the rest of the Airframe system: every coordinate here is millimetres in the
## plate's own plane, and outlines are stored as `PackedFloat64Array`. `Vector2` appears in the
## signatures because that is what a caller holding a cursor position has, and it is converted at
## the boundary — see `ArmProfile`'s header for what a float32 round-trip costs a measurement.
##
## ## What an edit may NOT do
##
## It may not write a mass, a resonance, or any other derived figure into the document. §2 is
## explicit — mass is computed, never typed — and the whole point of editing geometry is that every
## number follows from it. So the operations below add, move and remove POINTS, and that is all they
## do. If an edit ever needs to store a derived value to be fast enough, the answer is a cache
## outside the document, not a field inside it.

## Where a brand new frame's default plate stock comes from. 2 mm is the commonest centre-plate
## stock in the catalog and the thinnest anybody builds a 5" out of; it is a starting point a
## builder immediately changes, not a claim about their frame.
const DEFAULT_PLATE_THICKNESS_MM := 2.0
const DEFAULT_ARM_THICKNESS_MM := 5.0

## The grid a drag lands on unless the caller says otherwise, in mm. Fine enough to place a bolt
## hole, coarse enough that a hand-drawn outline comes out with numbers on it rather than
## 12.34871 mm.
const DEFAULT_SNAP_MM := 0.5

## How many segments a drilled hole is drawn with, via `PolygonProps.tessellate_circle`'s chord
## tolerance. A hole is the one curve in a frame that is always a true circle, and its area feeds
## the mass sum, so the tolerance is the kernel's own default rather than a number chosen here.
const HOLE_CHORD_TOLERANCE_MM := PolygonProps.DEFAULT_CHORD_TOLERANCE_MM


# ---------------------------------------------------------------------------
# Making frames and plates
# ---------------------------------------------------------------------------

## An empty frame: a real document with no plates.
##
## EMPTY, not a starter shape. §7.1's canvas opens on nothing, and a blank frame that quietly
## contained a centre plate would mean every frame anybody drew inherited a rectangle they did not
## choose — and, worse, that the first mass they saw was partly this file's opinion.
static func new_frame(frame_name: String = "Untitled frame") -> AirframeDocument:
	var document := AirframeDocument.new()
	document.id = "frame_%d" % Time.get_ticks_usec()
	document.name = frame_name
	document.author = ""
	document.revision = ""
	# No published mass: this frame has no vendor. See `AirframeDocument.published_mass_g` — the
	# Structure tab reads the absence and shows no vendor comparison at all rather than one against
	# zero.
	document.published_mass_g = 0.0
	return document


## A rectangular plate, centred on `centre`, wound counter-clockwise so its signed area is positive.
##
## WINDING IS NOT COSMETIC. `PolygonProps` integrates the signed area, so a clockwise outline gives
## a negative mass and a negative inertia, and the frame quietly weighs less than nothing. Holes use
## the opposite winding for exactly that reason, which is how they subtract.
static func add_rectangle(
	document: AirframeDocument,
	centre: Vector2,
	width_mm: float,
	height_mm: float,
	thickness_mm: float,
	z_mm: float,
	role: String
) -> int:
	var half_w := absf(width_mm) * 0.5
	var half_h := absf(height_mm) * 0.5
	var outline := PackedVector2Array([
		centre + Vector2(-half_w, -half_h),
		centre + Vector2(half_w, -half_h),
		centre + Vector2(half_w, half_h),
		centre + Vector2(-half_w, half_h),
	])
	document.plates.append(
		AirframeDocument.make_plate(outline, [], absf(thickness_mm), z_mm, role))
	return document.plates.size() - 1


## An arm: a tapered plate from the origin out to `length_mm` at `angle_deg`, with its centreline
## authored along that axis (§10 q1) and a motor at its tip.
##
## The motor comes with it because an arm without one is not a thing anybody draws — the arm exists
## to hold a motor, `ControlEffectiveness` needs the position, and an arm added without a motor
## would make the frame read as uncontrollable until the builder noticed a second step they had no
## reason to expect.
static func add_arm(
	document: AirframeDocument,
	angle_deg: float,
	length_mm: float,
	root_width_mm: float,
	tip_width_mm: float,
	thickness_mm: float,
	spin: float = 1.0
) -> int:
	var angle := deg_to_rad(angle_deg)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	var tip := along * length_mm
	var root_half := absf(root_width_mm) * 0.5
	var tip_half := absf(tip_width_mm) * 0.5
	# Counter-clockwise, same as `add_rectangle`: down one side, across the tip, back up the other.
	var outline := PackedVector2Array([
		-across * root_half,
		tip - across * tip_half,
		tip + across * tip_half,
		across * root_half,
	])
	document.plates.append(AirframeDocument.make_arm_plate(
		outline, [], absf(thickness_mm), 0.0, Vector2.ZERO, tip))
	document.motors.append({
		"position_mm": [tip.x, tip.y],
		"z_mm": absf(thickness_mm),
		"spin": spin,
		"tilt_deg": 0.0,
	})
	return document.plates.size() - 1


## A circular hole in one plate. Subtracts, because `tessellate_circle` is asked for the reversed
## winding — the same mechanism `AirframeDocument`'s preset generator uses for bolt holes.
static func add_hole(
	document: AirframeDocument,
	plate_index: int,
	centre: Vector2,
	diameter_mm: float
) -> bool:
	if not _has_plate(document, plate_index) or diameter_mm <= 0.0:
		return false
	var plate: Dictionary = document.plates[plate_index]
	var holes: Array = plate.get("holes", [])
	holes.append(AirframeDocument.flatten(PolygonProps.tessellate_circle(
		centre, diameter_mm * 0.5, HOLE_CHORD_TOLERANCE_MM, true)))
	plate["holes"] = holes
	return true


# ---------------------------------------------------------------------------
# Editing an outline
# ---------------------------------------------------------------------------

## Moves one vertex of one plate's outline to a new position.
static func move_vertex(
	document: AirframeDocument,
	plate_index: int,
	vertex_index: int,
	to: Vector2
) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	var flat: PackedFloat64Array = plate.get("outline", PackedFloat64Array())
	if vertex_index < 0 or vertex_index * 2 + 1 >= flat.size():
		return false
	flat[vertex_index * 2] = to.x
	flat[vertex_index * 2 + 1] = to.y
	plate["outline"] = flat
	return true


## Inserts a vertex immediately AFTER `after_index`, which is the edge between it and the next
## point. Stated that way round because that is what a click on an edge means: the two endpoints of
## the edge you clicked stay put and a handle appears between them.
static func insert_vertex(
	document: AirframeDocument,
	plate_index: int,
	after_index: int,
	at: Vector2
) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	var points := AirframeDocument.plate_outline(plate)
	if after_index < 0 or after_index >= points.size():
		return false
	var out := PackedVector2Array()
	for i in points.size():
		out.append(points[i])
		if i == after_index:
			out.append(at)
	plate["outline"] = AirframeDocument.flatten(out)
	return true


## Removes a vertex, unless doing so would leave fewer than three.
##
## THE GUARD IS THE FUNCTION. Two points enclose no area, so the plate would keep drawing as a line
## while contributing nothing to mass, CG or inertia — a plate that is visibly there and physically
## absent, which is the worst failure this editor could have.
static func delete_vertex(document: AirframeDocument, plate_index: int, vertex_index: int) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	var points := AirframeDocument.plate_outline(plate)
	if points.size() <= 3 or vertex_index < 0 or vertex_index >= points.size():
		return false
	var out := PackedVector2Array()
	for i in points.size():
		if i != vertex_index:
			out.append(points[i])
	plate["outline"] = AirframeDocument.flatten(out)
	return true


## Slides a whole plate, its holes and its centreline together. All three, because an arm whose
## outline moved without its centreline is an arm `ArmProfile` refuses to measure.
static func move_plate(document: AirframeDocument, plate_index: int, delta: Vector2) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	plate["outline"] = _translated(plate.get("outline", PackedFloat64Array()), delta)
	var holes: Array = []
	for hole in plate.get("holes", []):
		holes.append(_translated(hole, delta))
	plate["holes"] = holes
	for key in ["root_point", "tip_point"]:
		if plate.has(key):
			var point := AirframeDocument.point_of(plate[key]) + delta
			plate[key] = [point.x, point.y]
	return true


## The stock a plate is cut from. Not snapped to the stock list: §2 keeps that list for authoring
## convenience and refuses to round a figure somebody typed on purpose.
static func set_thickness(document: AirframeDocument, plate_index: int, thickness_mm: float) -> bool:
	if not _has_plate(document, plate_index) or thickness_mm <= 0.0:
		return false
	(document.plates[plate_index] as Dictionary)["thickness_mm"] = thickness_mm
	return true


## Which of §2's five roles a plate plays. Changing a plate INTO an arm gives it a centreline along
## its own longest axis, because an arm without one cannot be analysed and asking the builder to
## draw a second thing before the first one works is a worse default than a sensible guess they can
## drag.
static func set_role(document: AirframeDocument, plate_index: int, role: String) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	plate["role"] = role
	if role != AirframeDocument.ROLE_ARM:
		plate.erase("root_point")
		plate.erase("tip_point")
		return true
	if not plate.has("root_point") or not plate.has("tip_point"):
		var axis := _longest_axis(AirframeDocument.plate_outline(plate))
		plate["root_point"] = [axis[0].x, axis[0].y]
		plate["tip_point"] = [axis[1].x, axis[1].y]
	return true


# ---------------------------------------------------------------------------
# Symmetry
# ---------------------------------------------------------------------------

## §7.1's "edit one arm, get four": copies one plate `count` ways around the origin.
##
## ROTATIONAL, NOT MIRRORED, and the difference is the propellers. A mirrored copy of an arm is the
## same arm reflected, which is right for a shape and wrong for a quad: the four motors of an X sit
## at 90 degree intervals, and mirroring a 45 degree arm about both axes happens to land in the same
## places only because 45 degrees is special. At any other angle — a stretched frame, a deadcat, a
## hexacopter — mirroring puts arms where no motor goes. Rotation is what "N-fold symmetry" means.
##
## The source plate's own motor, if it has one, is replicated with it; the copies alternate spin
## direction, because that is what makes the layout yawable and it is what every quad does.
static func replicate_radially(document: AirframeDocument, plate_index: int, count: int) -> bool:
	if not _has_plate(document, plate_index) or count < 2:
		return false
	var source: Dictionary = document.plates[plate_index]
	var source_motor := _motor_at(document, AirframeDocument.point_of(
		source.get("tip_point", [INF, INF])))

	for step in range(1, count):
		var angle := TAU * float(step) / float(count)
		var copy: Dictionary = _rotated_plate(source, angle)
		document.plates.append(copy)
		if source_motor.is_empty():
			continue
		var position := AirframeDocument.point_of(source_motor["position_mm"]).rotated(angle)
		var motor := source_motor.duplicate(true)
		motor["position_mm"] = [position.x, position.y]
		# Alternating, so a four-arm frame comes out with two counter-rotating pairs. An odd count
		# cannot alternate evenly and does not pretend to: a tricopter yaws with a tilt servo, which
		# is a thing this model does not have, and `FrameWarnings` will say the layout cannot yaw.
		motor["spin"] = float(source_motor.get("spin", 1.0)) * (1.0 if step % 2 == 0 else -1.0)
		document.motors.append(motor)
	return true


# ---------------------------------------------------------------------------
# Snapping
# ---------------------------------------------------------------------------

## Rounds a position to the nearest grid step. A zero or negative step means no snapping, which is
## how a caller says "the builder is holding the modifier key" without a second code path.
static func snap(point: Vector2, step_mm: float = DEFAULT_SNAP_MM) -> Vector2:
	if step_mm <= 0.0:
		return point
	return Vector2(_snap_scalar(point.x, step_mm), _snap_scalar(point.y, step_mm))


## Away from zero at the exact half, which is what `round()` does and what a builder expects when
## they nudge something to 12.5 on a 1 mm grid.
static func _snap_scalar(value: float, step_mm: float) -> float:
	return round(value / step_mm) * step_mm


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _has_plate(document: AirframeDocument, plate_index: int) -> bool:
	return document != null and plate_index >= 0 and plate_index < document.plates.size()


static func _translated(flat: PackedFloat64Array, delta: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var i := 0
	while i + 1 < flat.size():
		out.append(flat[i] + delta.x)
		out.append(flat[i + 1] + delta.y)
		i += 2
	return out


## A plate rotated about the origin: outline, holes and centreline, in doubles.
##
## The rotation is done on the flat arrays rather than by round-tripping through `Vector2` for the
## reason `ArmProfile` spells out — 32-bit points would leave ~1e-5 mm of noise on a 100 mm arm, and
## the four "identical" arms of a symmetric X would then have four slightly different stiffnesses.
static func _rotated_plate(plate: Dictionary, angle: float) -> Dictionary:
	var copy: Dictionary = plate.duplicate(true)
	var c := cos(angle)
	var s := sin(angle)
	copy["outline"] = _rotated_flat(plate.get("outline", PackedFloat64Array()), c, s)
	var holes: Array = []
	for hole in plate.get("holes", []):
		holes.append(_rotated_flat(hole, c, s))
	copy["holes"] = holes
	for key in ["root_point", "tip_point"]:
		if plate.has(key):
			var point := AirframeDocument.point_of(plate[key])
			copy[key] = [point.x * c - point.y * s, point.x * s + point.y * c]
	return copy


static func _rotated_flat(flat: PackedFloat64Array, c: float, s: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var i := 0
	while i + 1 < flat.size():
		var x := flat[i]
		var y := flat[i + 1]
		out.append(x * c - y * s)
		out.append(x * s + y * c)
		i += 2
	return out


## The motor standing at a given plan position, or {} if there is none. Matched by position because
## that is the only thing an arm and its motor share — §2 keeps motors in their own array precisely
## so that a frame can have a motor without an arm and an arm without a motor.
static func _motor_at(document: AirframeDocument, position: Vector2) -> Dictionary:
	if not is_finite(position.x) or not is_finite(position.y):
		return {}
	for motor in document.motors:
		if AirframeDocument.point_of(motor.get("position_mm", [0.0, 0.0])).distance_to(position) \
				< 0.001:
			return motor
	return {}


## The two furthest-apart points of an outline, used as a default centreline when a plate is
## promoted to an arm. A guess, and a visible one — it is a line the builder can drag — rather than
## a hidden assumption feeding a number.
static func _longest_axis(points: PackedVector2Array) -> Array:
	if points.size() < 2:
		return [Vector2.ZERO, Vector2.ZERO]
	var best_a := points[0]
	var best_b := points[1]
	var best := -1.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			var distance := points[i].distance_squared_to(points[j])
			if distance > best:
				best = distance
				best_a = points[i]
				best_b = points[j]
	return [best_a, best_b]
