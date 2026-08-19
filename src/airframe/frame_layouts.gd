class_name FrameLayouts
extends RefCounted
## The motor layouts a builder can start from — quad, hex and octo, in their plus, X, V and coaxial
## arrangements — as a PARAMETRIC generator rather than as a shelf of fixed products.
##
## ## Why this is not `frames.json`
##
## The catalog holds fifteen *products*: a named 5" freestyle frame with a vendor, a published mass
## and a size in inches. That is the right shelf for somebody CHOOSING a frame to fly and the wrong
## one for somebody DESIGNING one, because every question it answers ("what does this weigh?",
## "what prop fits?") is a question about a finished aircraft. A builder opening the Airframe room
## has not got an aircraft yet; they have a topology in mind — six arms, flat, motors alternating —
## and they want the geometry that expresses it, at whatever size they then type.
##
## So a layout here carries NO size, NO mass and NO vendor. It carries the thing the diagrams in
## every flight-controller manual carry and nothing else: how many arms, where they point, which way
## each motor spins, and whether the motors are stacked coaxially. Size arrives as `Params`, which
## the controls panel drives; the same `hex_x` template produces a 3" and a 10" hexacopter, and the
## difference between them is a number in a spin box rather than a second row on a shelf.
##
## ## Angles, stated once
##
## Plan space, degrees, measured from +u (right) toward +v (aft) — the same convention
## `FrameEdits.add_arm` takes, because there must not be two. The nose is −v, so:
##
##     270°  forward        0°  right        90°  aft        180°  left
##
## Every template below is written nose-first: its first arm is the one nearest the front, so a
## reader can check the table against the picture in a manual without doing arithmetic.
##
## ## Spin, and why it alternates around the ring
##
## Yaw comes from the difference between clockwise and counter-clockwise reaction torque, so a
## layout whose motors do not balance cannot hold heading. Alternating around the ring is what
## every even-count multirotor does, and it makes opposite arms match, which is also what balances
## the gyroscopic couple in a roll. An ODD count cannot alternate — a tricopter yaws with a servo,
## which this model does not have — and nothing here pretends otherwise: `Y6` and `IY6` have three
## ARMS but six motors, and it is the coaxial pairs that balance.
##
## A coaxial pair is two motors at the same plan position and different heights, turning opposite
## ways. `ControlEffectiveness` reads position and spin, so it sees a balanced pair with no special
## case; the only thing the document needs to carry is the height, and it already has `z_mm`.

## One entry of the shelf. `arms` are the angles above; `motors_per_arm` is 1 for a flat layout and
## 2 for a coaxial one.
const TEMPLATES := [
	{
		"id": "quad_plus", "name": "Quad I", "class": "quad", "motors_per_arm": 1,
		"arms": [270.0, 0.0, 90.0, 180.0],
	},
	{
		"id": "quad_x", "name": "Quad X", "class": "quad", "motors_per_arm": 1,
		"arms": [315.0, 45.0, 135.0, 225.0],
	},
	{
		"id": "hex_plus", "name": "Hex I", "class": "hex", "motors_per_arm": 1,
		"arms": [270.0, 330.0, 30.0, 90.0, 150.0, 210.0],
	},
	{
		"id": "hex_v", "name": "Hex V", "class": "hex", "motors_per_arm": 1,
		"arms": [300.0, 0.0, 60.0, 120.0, 180.0, 240.0],
	},
	{
		# Two arms forward, one aft, two motors on each — the Y6.
		"id": "y6", "name": "Hex Y", "class": "hex", "motors_per_arm": 2,
		"arms": [210.0, 330.0, 90.0],
	},
	{
		# The Y inverted: one arm forward, two aft.
		"id": "iy6", "name": "Hex IY", "class": "hex", "motors_per_arm": 2,
		"arms": [270.0, 30.0, 150.0],
	},
	{
		"id": "oct_x", "name": "Oct X", "class": "oct", "motors_per_arm": 1,
		"arms": [292.5, 337.5, 22.5, 67.5, 112.5, 157.5, 202.5, 247.5],
	},
	{
		"id": "oct_plus", "name": "Oct I", "class": "oct", "motors_per_arm": 1,
		"arms": [270.0, 315.0, 0.0, 45.0, 90.0, 135.0, 180.0, 225.0],
	},
	{
		# Four arms, eight motors: the X8.
		"id": "oct_v", "name": "Oct V", "class": "oct", "motors_per_arm": 2,
		"arms": [315.0, 45.0, 135.0, 225.0],
	},
]

## The knobs the controls panel drives. Defaults are a 5"-ish build because it is the size most
## people are holding when they open this room, and because every figure below is a real one: 5 mm
## arm stock, 2 mm plates, a 16×16 motor pattern, a 30.5 mm stack.
const DEFAULTS := {
	"arm_length_mm": 110.0,
	"arm_root_width_mm": 16.0,
	"arm_tip_width_mm": 12.0,
	"arm_thickness_mm": 5.0,
	"plate_thickness_mm": 2.0,
	"plate_side_mm": 40.0,
	"standoff_len_mm": 25.0,
	"motor_pitch_mm": 16.0,
	"stack_pitch_mm": 30.5,
	"material_id": "carbon_3k_twill_0_90",
	"coaxial_gap_mm": 60.0,
}

## Vertical clearance between the two motors of a coaxial pair, as a fraction of arm length, when
## the caller does not state one. A puller above and a pusher below need enough room for two
## propeller discs and the frame between them; 55% of arm length is roughly one prop diameter,
## which is the rule of thumb these builds are laid out with.
const COAXIAL_GAP_PER_ARM := 0.55

## `AirframeDocument.ROLE_ARM`, aliased so the measuring pass reads as a table of roles.
const ROLE_ARM_KEY := "arm"


static func template(layout_id: String) -> Dictionary:
	for entry in TEMPLATES:
		if str(entry["id"]) == layout_id:
			return entry
	return {}


## Every template's id, in shelf order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in TEMPLATES:
		out.append(str(entry["id"]))
	return out


## `DEFAULTS`, with anything the caller states written over the top. Its own function so a caller
## may pass two keys and get a complete parameter set, rather than every call site carrying its own
## copy of eleven defaults that will drift.
static func params(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for key in overrides:
		out[key] = overrides[key]
	return out


## An `AirframeDocument` for a layout at a size — the whole point of this file.
##
## What it generates, and why each piece is there rather than being left to the builder: one arm
## per angle with its motor(s) at the tip (an arm without a motor is not a thing anybody draws —
## `FrameEdits.add_arm` says so at length), a bottom and a top centre plate sized off the stack
## pattern, and the standoffs and screws that hold the sandwich together. `HardwareMass` weighs the
## fasteners from those dimensions, so the mass on screen is complete the instant the frame appears
## rather than growing later when somebody remembers the hardware bag.
##
## NO PUBLISHED MASS, ever: a generated frame has no vendor to disagree with, and the Structure
## panel prints the comparison only when there is one.
static func build(layout_id: String, overrides: Dictionary = {}) -> AirframeDocument:
	var entry := template(layout_id)
	var p := params(overrides)
	var document := FrameEdits.new_frame(str(entry.get("name", "Untitled frame")))
	if entry.is_empty():
		return document
	document.material_id = str(p["material_id"])
	document.revision = "generated: %s" % layout_id
	apply_layout(document, entry, p)
	return document


## Rebuilds a document's arms, motors, centre plates and hardware from a template and a parameter
## set, leaving the document's identity — name, id, author, material — alone.
##
## SEPARATE FROM `build` because this is what the controls panel calls on every drag of the arm
## length slider, and it must not rename the frame the builder is working on or hand them a new
## document each time. It replaces the generated parts wholesale, which is honest about what it is:
## the layout controls regenerate a layout, and a frame whose arms have been hand-drawn is one the
## builder should not still be dragging the arm-count slider on.
static func apply_layout(document: AirframeDocument, entry: Dictionary, p: Dictionary) -> void:
	document.plates.clear()
	document.motors.clear()
	document.hardware.clear()
	document.payload_mounts.clear()

	var arms: Array = entry.get("arms", [])
	var per_arm := int(entry.get("motors_per_arm", 1))
	var arm_len := float(p["arm_length_mm"])
	var t_arm := float(p["arm_thickness_mm"])
	var t_plate := float(p["plate_thickness_mm"])
	var motor_pitch := float(p["motor_pitch_mm"])
	var stack_pitch := float(p["stack_pitch_mm"])
	var plate_side := maxf(float(p["plate_side_mm"]), stack_pitch + 8.0)
	var standoff := float(p["standoff_len_mm"])
	var gap: float = float(p.get("coaxial_gap_mm", arm_len * COAXIAL_GAP_PER_ARM))
	var top_z := t_plate + standoff

	for slot in arms.size():
		var angle_deg := float(arms[slot])
		var index := FrameEdits.add_arm(document, angle_deg, arm_len,
			float(p["arm_root_width_mm"]), float(p["arm_tip_width_mm"]), t_arm,
			1.0 if slot % 2 == 0 else -1.0)
		var arm_plate: Dictionary = document.plates[index]
		var direction := Vector2(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)))
		var tip := direction * arm_len
		# The motor's own bolt pattern, cut out of the arm's tip. Four holes is what a motor takes,
		# and they are real geometry rather than decoration: they remove mass exactly where the
		# beam is thinnest, which is a thing `ArmBeam` reads off the outline.
		var holes: Array = arm_plate.get("holes", [])
		for corner in bolt_pattern(tip, motor_pitch, deg_to_rad(angle_deg)):
			holes.append(AirframeDocument.flatten(PolygonProps.tessellate_circle(
				corner, (3.2 if motor_pitch >= 16.0 else 2.2) * 0.5,
				PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true)))
		arm_plate["holes"] = holes
		# The width was authored by whoever moved the slider, so no `width_is_assumed` flag: the
		# Arms tab caveats a width this project INVENTED, and this one the builder chose.
		arm_plate["layout_slot"] = slot

		# `add_arm` already put one motor on the tip. A coaxial layout gets its partner underneath,
		# turning the other way, and the pair balances on its own.
		var upper: Dictionary = document.motors[document.motors.size() - 1]
		upper["z_mm"] = t_arm + (gap * 0.5 if per_arm > 1 else 0.0)
		upper["arm_slot"] = slot
		if per_arm > 1:
			var lower: Dictionary = upper.duplicate(true)
			lower["z_mm"] = t_arm - gap * 0.5
			lower["spin"] = -float(upper.get("spin", 1.0))
			lower["coaxial"] = true
			document.motors.append(lower)

		for i in 4:
			document.hardware.append({
				"kind": "screw", "material_id": "steel_fastener",
				"thread_d_mm": 3.0 if motor_pitch >= 16.0 else 2.0,
				"shank_len_mm": 8.0,
				"head_d_mm": (3.0 if motor_pitch >= 16.0 else 2.0) * 1.9,
				"head_h_mm": (3.0 if motor_pitch >= 16.0 else 2.0) * 0.6,
				"position_mm": [tip.x, tip.y], "z_mm": t_arm,
			})

	var stack_holes: Array = []
	for corner in bolt_pattern(Vector2.ZERO, stack_pitch, 0.0):
		stack_holes.append(PolygonProps.tessellate_circle(corner, 1.6,
			PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true))
	document.plates.append(AirframeDocument.make_plate(
		square(plate_side), stack_holes, t_plate, 0.0, AirframeDocument.ROLE_BOTTOM))
	document.plates.append(AirframeDocument.make_plate(
		square(plate_side), stack_holes, t_plate, top_z, AirframeDocument.ROLE_TOP))

	for corner in bolt_pattern(Vector2.ZERO, stack_pitch, 0.0):
		document.hardware.append({
			"kind": "standoff_round", "material_id": "aluminium_6061",
			"outer_d_mm": 5.5, "bore_d_mm": 3.0, "length_mm": standoff,
			"position_mm": [corner.x, corner.y], "z_mm": t_plate + standoff * 0.5,
		})
		for z in [0.0, top_z]:
			document.hardware.append({
				"kind": "screw", "material_id": "steel_fastener",
				"thread_d_mm": 3.0, "shank_len_mm": 8.0, "head_d_mm": 5.7, "head_h_mm": 1.8,
				"position_mm": [corner.x, corner.y], "z_mm": z,
			})

	document.payload_mounts.append({
		"id": "stack", "position_mm": [0.0, 0.0], "z_mm": t_plate,
		"span_mm": [plate_side, plate_side],
	})


## The generator parameters a document currently EMBODIES, measured off its own geometry.
##
## ## Why measured and not remembered
##
## The obvious design is to store the parameters on the document — a `layout_params` block written
## when it was generated. It is also the design that lets the two disagree: a builder drags an arm
## tip 20 mm outward, the stored `arm_length_mm` still says 110, and the next touch of any slider
## regenerates the frame back to a size nothing on screen ever showed. Measuring means the controls
## always open on what is actually there, and a value they cannot measure falls back to a default
## rather than to a stale claim.
##
## Everything here is read off the FIRST arm and the FIRST bottom plate: a generated layout has
## identical arms by construction, and for a frame that no longer does, these controls are hidden
## anyway (see `FrameControls`).
static func params_of(document: AirframeDocument) -> Dictionary:
	var out: Dictionary = params()
	if document == null:
		return out
	out["material_id"] = document.material_id

	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		var role := str(plate.get("role", ""))
		if role == ROLE_ARM_KEY and not out.has("_arm_seen"):
			var geometry := FrameEdits.arm_geometry(document, index)
			if not geometry.is_empty():
				out["arm_length_mm"] = float(geometry["length_mm"])
				out["arm_root_width_mm"] = maxf(float(geometry["root_width_mm"]), 1.0)
				out["arm_tip_width_mm"] = maxf(float(geometry["tip_width_mm"]), 1.0)
			out["arm_thickness_mm"] = AirframeDocument.plate_thickness_mm(plate)
			out["motor_pitch_mm"] = _hole_pitch_mm(plate, out["motor_pitch_mm"])
			out["_arm_seen"] = true
		elif role == AirframeDocument.ROLE_BOTTOM and not out.has("_plate_seen"):
			out["plate_thickness_mm"] = AirframeDocument.plate_thickness_mm(plate)
			out["plate_side_mm"] = _plate_side_mm(plate, out["plate_side_mm"])
			out["stack_pitch_mm"] = _hole_pitch_mm(plate, out["stack_pitch_mm"])
			out["_plate_seen"] = true

	for item in document.hardware:
		if str(item.get("kind", "")).begins_with("standoff"):
			out["standoff_len_mm"] = float(item.get("length_mm", out["standoff_len_mm"]))
			break

	# The two coaxial motors of a Y6 or an X8, as the vertical gap the controls show.
	for i in document.motors.size():
		for j in range(i + 1, document.motors.size()):
			var a: Dictionary = document.motors[i]
			var b: Dictionary = document.motors[j]
			if AirframeDocument.point_of(a.get("position_mm", [0, 0])).distance_to(
					AirframeDocument.point_of(b.get("position_mm", [0, 0]))) < 0.001:
				out["coaxial_gap_mm"] = absf(float(a.get("z_mm", 0.0)) - float(b.get("z_mm", 0.0)))

	out.erase("_arm_seen")
	out.erase("_plate_seen")
	return out


## The bolt pitch of a plate's holes: the largest gap between hole centres, taken as the diagonal
## of a square pattern. Returns the fallback for a plate with fewer than two holes, because one
## hole has no pitch and inventing one would put a number in a box that nothing on the plate
## supports.
static func _hole_pitch_mm(plate: Dictionary, fallback: float) -> float:
	var centres: Array = []
	for hole in AirframeDocument.plate_holes(plate):
		if hole.size() >= 3:
			centres.append(PolygonProps.centroid(hole))
	if centres.size() < 2:
		return fallback
	var widest := 0.0
	for i in centres.size():
		for j in range(i + 1, centres.size()):
			widest = maxf(widest, (centres[i] as Vector2).distance_to(centres[j]))
	return widest / sqrt(2.0)


## A centre plate's side, as the wider of its two bounding-box extents. The generator makes it
## square; a builder may not have, and reporting the larger of the two is the value that, typed
## back in, contains the plate that is there.
static func _plate_side_mm(plate: Dictionary, fallback: float) -> float:
	var points := AirframeDocument.plate_outline(plate)
	if points.size() < 3:
		return fallback
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	for point in points:
		lowest = lowest.min(point)
		highest = highest.max(point)
	return maxf(highest.x - lowest.x, highest.y - lowest.y)


## Which template a document was generated from, or "" for one that was drawn. Read off the
## document rather than remembered by the UI, so it survives a save, a reload and a session.
static func layout_id_of(document: AirframeDocument) -> String:
	if document == null:
		return ""
	var revision := document.revision
	if not revision.begins_with("generated: "):
		return ""
	return revision.substr("generated: ".length())


## Four bolt holes of a square pattern, centred and rotated with the arm.
static func bolt_pattern(centre: Vector2, pitch_mm: float, angle_rad: float) -> Array:
	var half := pitch_mm * 0.5
	var out: Array = []
	for corner in [Vector2(half, half), Vector2(half, -half),
			Vector2(-half, -half), Vector2(-half, half)]:
		out.append(centre + corner.rotated(angle_rad))
	return out


## A counter-clockwise square of side `side_mm` centred on the origin.
static func square(side_mm: float) -> PackedVector2Array:
	var h := absf(side_mm) * 0.5
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
