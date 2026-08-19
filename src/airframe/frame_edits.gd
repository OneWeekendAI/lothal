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
# Hardware, and the joints it makes
# ---------------------------------------------------------------------------

## The M3 joint every generated frame is built from, kept here so a hand-added standoff is the same
## part as a generated one rather than this file's own opinion of a standoff.
const DEFAULT_STANDOFF_OUTER_D_MM := 5.5
const DEFAULT_STANDOFF_BORE_D_MM := 3.0
const DEFAULT_SCREW_THREAD_D_MM := 3.0
const DEFAULT_SCREW_SHANK_MM := 8.0
const DEFAULT_STANDOFF_MATERIAL := "aluminium_6061"
const DEFAULT_SCREW_MATERIAL := "steel_fastener"

## The motor bolt pattern a mount is cut to unless the caller says otherwise: 16×16 with 3.2 mm
## clearance holes, which is what a 22xx motor takes and what `FrameLayouts` generates.
const DEFAULT_MOTOR_PITCH_MM := 16.0
const SMALL_MOTOR_PITCH_MM := 12.0
const MOTOR_HOLE_D_MM := 3.2
const SMALL_MOTOR_HOLE_D_MM := 2.2


## A standoff and the two screws that hold it, at one point on the plate stack.
##
## THE SET, not a lone standoff. A standoff by itself is not a joint and carries no check: only when
## the screws exist does `HardwareMass` have a thread engagement to test against the plate it lands
## in, a bottoming-out length to compare with the bore, and a hole-to-edge margin to measure. A
## builder who added a bare standoff would see a mass go up and no warnings at all, which is exactly
## the state where the three §5 failures hide.
##
## `length_mm` is the standoff's own length; the screws sit at the bottom and top of the stack it
## makes, and their z values are what the checks read. Returns the index of the standoff.
static func add_hardware(
	document: AirframeDocument,
	position: Vector2,
	length_mm: float,
	base_z_mm: float = 0.0,
	plate_thickness_mm: float = DEFAULT_PLATE_THICKNESS_MM
) -> int:
	if document == null or length_mm <= 0.0:
		return -1
	var standoff := absf(length_mm)
	var index := document.hardware.size()
	document.hardware.append({
		"kind": "standoff_round", "material_id": DEFAULT_STANDOFF_MATERIAL,
		"outer_d_mm": DEFAULT_STANDOFF_OUTER_D_MM, "bore_d_mm": DEFAULT_STANDOFF_BORE_D_MM,
		"length_mm": standoff,
		"position_mm": [position.x, position.y],
		"z_mm": base_z_mm + absf(plate_thickness_mm) + standoff * 0.5,
	})
	for z in [base_z_mm, base_z_mm + absf(plate_thickness_mm) + standoff]:
		document.hardware.append({
			"kind": "screw", "material_id": DEFAULT_SCREW_MATERIAL,
			"thread_d_mm": DEFAULT_SCREW_THREAD_D_MM, "shank_len_mm": DEFAULT_SCREW_SHANK_MM,
			"head_d_mm": DEFAULT_SCREW_THREAD_D_MM * 1.9,
			"head_h_mm": DEFAULT_SCREW_THREAD_D_MM * 0.6,
			"position_mm": [position.x, position.y], "z_mm": z,
		})
	return index


## A motor mount: the four bolt holes cut into a plate, and the motor that sits on them.
##
## Both halves, for the same reason `add_arm` brings a motor with it — a bolt pattern with no motor
## is holes that weaken a plate and contribute nothing to the mixer, and a motor with no pattern is
## a thrust vector floating above a plate it is not attached to. `ControlEffectiveness` reads the
## motor; `HardwareMass`'s edge check reads the holes; both need to appear at once or the frame is
## briefly, silently wrong in one of two directions.
##
## The spin is not chosen here — `alternate_spins` runs afterwards, which is what makes a mount
## added to a three-motor frame come out balanced rather than making the builder notice and fix it.
## `angle_deg` rotates the pattern, because a motor on a diagonal arm is bolted square to the arm.
##
## Returns the motor's index, or -1 when the plate does not exist or the pattern will not fit
## inside it — a mount whose holes fall outside the plate is not a warning, it is nothing.
static func add_motor_mount(
	document: AirframeDocument,
	plate_index: int,
	centre: Vector2,
	pitch_mm: float = DEFAULT_MOTOR_PITCH_MM,
	angle_deg: float = 0.0
) -> int:
	if not _has_plate(document, plate_index) or pitch_mm <= 0.0:
		return -1
	var plate: Dictionary = document.plates[plate_index]
	var outline := AirframeDocument.plate_outline(plate)
	var pattern := FrameLayouts.bolt_pattern(centre, pitch_mm, deg_to_rad(angle_deg))
	for corner in pattern:
		if not Geometry2D.is_point_in_polygon(corner, outline):
			return -1

	var hole_d := MOTOR_HOLE_D_MM if pitch_mm >= DEFAULT_MOTOR_PITCH_MM else SMALL_MOTOR_HOLE_D_MM
	var holes: Array = plate.get("holes", [])
	for corner in pattern:
		holes.append(AirframeDocument.flatten(PolygonProps.tessellate_circle(
			corner, hole_d * 0.5, HOLE_CHORD_TOLERANCE_MM, true)))
	plate["holes"] = holes

	document.motors.append({
		"position_mm": [centre.x, centre.y],
		"z_mm": AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate),
		"spin": 1.0,
		"tilt_deg": 0.0,
	})
	alternate_spins(document)
	return document.motors.size() - 1


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


# ---------------------------------------------------------------------------
# Numeric editing — the controls panel's half of §7.1
# ---------------------------------------------------------------------------
#
# Everything above this line is what a MOUSE does to a frame: grab a corner, drag it, drop it. What
# follows is what a NUMBER does, and the two are not the same activity. Dragging is how you find a
# shape; typing is how you commit to one, and a builder who wants a 137 mm arm has no way to reach
# it with a cursor and a 0.5 mm grid. The functions below are therefore not conveniences layered on
# the drag path — they are the primary way most of a frame gets its dimensions, and the drag path
# is the exploratory one.
#
# They stay pure for the same reason the drag edits do: "setting the arm length to 137 mm moves the
# motor to 137 mm and the mass with it" is an assertion about arithmetic, and arithmetic is the
# half that can be wrong without looking wrong.


## Re-cuts one arm to a stated angle, length and taper, carrying its holes, its centreline and its
## motor(s) with it.
##
## THE HOLES ARE TRANSFORMED, NOT REGENERATED. An arm's holes are its motor's bolt pattern plus
## whatever the builder has since drilled, and this function cannot tell those apart — so it moves
## all of them by the same rigid rotation-and-shift the tip took. Regenerating "the" pattern would
## silently delete a builder's own holes, which is data loss dressed up as a feature.
##
## The outline is rebuilt rather than transformed, because the taper is a parameter here: a wider
## root is a different quadrilateral, not the same one moved.
static func set_arm_geometry(
	document: AirframeDocument,
	plate_index: int,
	angle_deg: float,
	length_mm: float,
	root_width_mm: float,
	tip_width_mm: float
) -> bool:
	if not _has_plate(document, plate_index) or length_mm <= 0.0:
		return false
	var plate: Dictionary = document.plates[plate_index]
	var old_tip := AirframeDocument.point_of(plate.get("tip_point", [0.0, 0.0]))
	var angle := deg_to_rad(angle_deg)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	var tip := along * length_mm

	plate["outline"] = AirframeDocument.flatten(PackedVector2Array([
		-across * absf(root_width_mm) * 0.5,
		tip - across * absf(tip_width_mm) * 0.5,
		tip + across * absf(tip_width_mm) * 0.5,
		across * absf(root_width_mm) * 0.5,
	]))
	plate["root_point"] = [0.0, 0.0]
	plate["tip_point"] = [tip.x, tip.y]

	# The rigid motion the tip underwent: turn about the origin by the change of angle, then take
	# up the change of length along the new direction.
	var turn := 0.0
	if old_tip.length() > 0.001:
		turn = angle - old_tip.angle()
	var holes: Array = []
	for hole in plate.get("holes", []):
		var moved := _rotated_flat(hole, cos(turn), sin(turn))
		holes.append(_translated(moved, tip - old_tip.rotated(turn)))
	plate["holes"] = holes

	for motor in document.motors:
		var position := AirframeDocument.point_of(motor.get("position_mm", [0.0, 0.0]))
		if position.distance_to(old_tip) < 0.001:
			motor["position_mm"] = [tip.x, tip.y]
	return true


## Everything an arm is, as numbers, for a controls panel to show. `{}` for a plate that is not an
## arm — the caller shows the plate controls instead rather than a set of dashes.
static func arm_geometry(document: AirframeDocument, plate_index: int) -> Dictionary:
	if not _has_plate(document, plate_index):
		return {}
	var plate: Dictionary = document.plates[plate_index]
	if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM or not plate.has("tip_point"):
		return {}
	var tip := AirframeDocument.point_of(plate["tip_point"])
	var root := AirframeDocument.point_of(plate.get("root_point", [0.0, 0.0]))
	var axis := tip - root
	var across := Vector2(-axis.normalized().y, axis.normalized().x)
	var points := AirframeDocument.plate_outline(plate)
	# Width MEASURED off the outline rather than remembered, so an arm somebody has since dragged
	# reports what it now is. `ArmProfile` does the same thing for the beam maths; this is the
	# cheap version of it — the extent across the axis at each end — because a controls field needs
	# a number to put in a box rather than a profile.
	return {
		"angle_deg": rad_to_deg(axis.angle()),
		"length_mm": axis.length(),
		"root_width_mm": _extent_across(points, root, across),
		"tip_width_mm": _extent_across(points, tip, across),
		"thickness_mm": AirframeDocument.plate_thickness_mm(plate),
	}


## Scales a plate about its own centroid. The one control that changes a plate's SIZE without
## changing its shape, which is what "make the centre plate 10% bigger" means and what dragging four
## corners cannot do without also changing the aspect ratio by hand.
static func scale_plate(document: AirframeDocument, plate_index: int, factor: float) -> bool:
	if not _has_plate(document, plate_index) or factor <= 0.0:
		return false
	var plate: Dictionary = document.plates[plate_index]
	var points := AirframeDocument.plate_outline(plate)
	if points.size() < 3:
		return false
	var centroid := PolygonProps.centroid(points)
	plate["outline"] = AirframeDocument.flatten(_scaled(points, centroid, factor))
	var holes: Array = []
	for hole in plate.get("holes", []):
		holes.append(AirframeDocument.flatten(
			_scaled(AirframeDocument.points_of(hole), centroid, factor)))
	plate["holes"] = holes
	for key in ["root_point", "tip_point"]:
		if plate.has(key):
			var point := centroid + (AirframeDocument.point_of(plate[key]) - centroid) * factor
			plate[key] = [point.x, point.y]
	return true


## Rotates a plate about the origin. About the ORIGIN and not the plate's own centre, because an
## arm's angle is measured from the origin and rotating it in place would leave it pointing
## somewhere its motor is not.
static func rotate_plate(document: AirframeDocument, plate_index: int, degrees: float) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	var old_tip := AirframeDocument.point_of(plate.get("tip_point", [INF, INF]))
	document.plates[plate_index] = _rotated_plate(plate, deg_to_rad(degrees))
	var motor := _motor_at(document, old_tip)
	if not motor.is_empty():
		var moved := old_tip.rotated(deg_to_rad(degrees))
		motor["position_mm"] = [moved.x, moved.y]
	return true


## How high a plate sits in the stack. The single number that turns a top view into an assembly:
## `AirframeProperties` puts it in the inertia tensor and `Frame3DView` extrudes from it.
static func set_plate_z(document: AirframeDocument, plate_index: int, z_mm: float) -> bool:
	if not _has_plate(document, plate_index):
		return false
	(document.plates[plate_index] as Dictionary)["z_mm"] = z_mm
	return true


## Which stock a plate is cut from, overriding the document's. Erasing the override rather than
## writing the document's own id back means a plate follows a later change of frame material, which
## is what "the same as the rest of the frame" has to mean to be worth having.
static func set_plate_material(
	document: AirframeDocument, plate_index: int, material_id: String
) -> bool:
	if not _has_plate(document, plate_index):
		return false
	var plate: Dictionary = document.plates[plate_index]
	if material_id.is_empty() or material_id == document.material_id:
		plate.erase("material_id")
	else:
		plate["material_id"] = material_id
	return true


## Turns one motor the other way.
static func set_motor_spin(document: AirframeDocument, motor_index: int, spin: float) -> bool:
	if document == null or motor_index < 0 or motor_index >= document.motors.size():
		return false
	(document.motors[motor_index] as Dictionary)["spin"] = 1.0 if spin >= 0.0 else -1.0
	return true


## Motor tilt, degrees. Real on a racing build — tilted motors trade a little hover thrust for
## forward speed — and it is a per-motor property because a tilt applied to only the front pair is
## a thing people build.
static func set_motor_tilt(
	document: AirframeDocument, motor_index: int, tilt_deg: float
) -> bool:
	if document == null or motor_index < 0 or motor_index >= document.motors.size():
		return false
	(document.motors[motor_index] as Dictionary)["tilt_deg"] = tilt_deg
	return true


## Alternates spin around the ring, so the layout can hold heading.
##
## SORTED BY BEARING, not by document order. Motors are appended in whatever order arms were drawn,
## and alternating by index would give a frame whose arms were added clockwise a perfectly balanced
## document and a frame whose arms were added at random four motors that fight. Bearing is the
## thing that actually has to alternate, so bearing is what this sorts on.
##
## Coaxial partners — two motors at the same plan position — are handled as a pair: the upper keeps
## the ring's spin and the lower takes the opposite, which is what makes an X8 balance.
static func alternate_spins(document: AirframeDocument) -> bool:
	if document == null or document.motors.is_empty():
		return false
	var positions: Array = []
	for index in document.motors.size():
		var motor: Dictionary = document.motors[index]
		positions.append({
			"index": index,
			"position": AirframeDocument.point_of(motor.get("position_mm", [0.0, 0.0])),
			"z": float(motor.get("z_mm", 0.0)),
		})
	positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var angle_a: float = (a["position"] as Vector2).angle()
		var angle_b: float = (b["position"] as Vector2).angle()
		if absf(angle_a - angle_b) > 1.0e-6:
			return angle_a < angle_b
		return float(a["z"]) > float(b["z"]))

	var slot := 0
	var previous := Vector2(INF, INF)
	for entry in positions:
		var position: Vector2 = entry["position"]
		var is_partner := position.distance_to(previous) < 0.001
		var motor: Dictionary = document.motors[int(entry["index"])]
		if is_partner:
			# Same mast, opposite rotation. The pair cancels on its own, so the ring's alternation
			# is not advanced by it.
			motor["spin"] = -_last_spin(document, positions, entry)
		else:
			motor["spin"] = 1.0 if slot % 2 == 0 else -1.0
			slot += 1
		previous = position
	return true


## Whether the motors as they stand can hold heading: the sum of their spins, which must be zero.
## Reported as a number rather than a bool so a panel can say HOW unbalanced a layout is — a
## hexacopter with one motor turned the wrong way is off by two, and that is a different fix from
## an odd count that can never balance.
static func spin_balance(document: AirframeDocument) -> float:
	if document == null:
		return 0.0
	var total := 0.0
	for motor in document.motors:
		total += float(motor.get("spin", 1.0))
	return total


static func _last_spin(
	document: AirframeDocument, positions: Array, entry: Dictionary
) -> float:
	var found := positions.find(entry)
	if found <= 0:
		return 1.0
	var previous: Dictionary = document.motors[int(positions[found - 1]["index"])]
	return float(previous.get("spin", 1.0))


static func _scaled(
	points: PackedVector2Array, about: Vector2, factor: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(about + (point - about) * factor)
	return out


## The full extent of an outline across an axis, measured through a point on it — the crude width
## the controls panel puts in a box. `ArmProfile` is the honest version and this is not a substitute
## for it: this measures the whole plate's spread perpendicular to the axis, which for a straight
## tapered arm is its width at that station and for a bent one is an over-estimate.
static func _extent_across(points: PackedVector2Array, through: Vector2, across: Vector2) -> float:
	var lowest := INF
	var highest := -INF
	for point in points:
		# Only points near the station contribute, so a root measurement is not widened by the tip.
		var along_axis := (point - through).dot(Vector2(-across.y, across.x))
		if absf(along_axis) > 1.0:
			continue
		var offset := (point - through).dot(across)
		lowest = minf(lowest, offset)
		highest = maxf(highest, offset)
	if not is_finite(lowest) or not is_finite(highest):
		return 0.0
	return highest - lowest
