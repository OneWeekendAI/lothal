class_name FrameModel
extends Node3D
## Procedural frame geometry, generated from a chosen frame part's real specs rather than
## authored as a fixed asset. Picking the 7" frame over the 3" one must make the arms
## genuinely longer because arm_mm changed — a hand-modelled mesh (even one that gets
## uniformly scaled to "look right") would decouple the geometry the pilot sees from the
## arm_mm that drives the physics, and the whole point of this workbench (architecture.md:
## "Models: Godot primitives (v1)") is that picking a part changes what you see AND what you
## fly, from the same number. Motors, props and batteries are out of scope here — frame only.
##
## Node layout after rebuild():
##   Arm_M1..Arm_M4  — one BoxMesh per MotorLayout.MOTOR_NAMES, spanning centre to arm tip
##   Pad_M1..Pad_M4  — motor-mount pad at each arm tip; arm_tips[name] points at these
##   PlateTop, PlateBottom — the twin centre plates
##
## It also publishes `mount_points`: the places on this frame where something attaches. See
## mount_points_for(), and MountPoint for what a mount point is.
const INCH_M := 0.0254

## Arm cross-section for a frame the plate model cannot describe — see `_build_placeholder_body`.
##
## THESE ARE NO LONGER HOW A FRAME IS DRAWN. Every plate frame is now extruded from the polygons in
## its `AirframeDocument` (airframe.md §7.2), so an arm is as wide as it is drawn and as thick as
## its stock. What is left of the old ratios is a fallback for MOULDED frames, which have no plate
## geometry at all (§0) and which §7.3 says need a primitive that does not exist yet. It is a
## placeholder for a shape nobody has modelled, and it is named as one; nothing reads it.
const ARM_WIDTH_TO_LENGTH_RATIO := 1.0 / 8.0
const ARM_THICKNESS_TO_WIDTH_RATIO := 0.5

## How a frame is LAID OUT — plate size, standoff height, strap-slot minimum — now lives in
## MountLayout, next to the mount table it decides. These aliases keep the names readable at the
## drawing call sites below; they are the same constants, not copies of them.
const CENTRE_PLATE_TO_ARM_RATIO := MountLayout.CENTRE_PLATE_TO_ARM_RATIO

## Fallback bolt spacing (metres) when a frame's motor_mount string cannot be parsed, e.g.
## "16x16" -> 0.016. Falls back to a fraction of arm_m so an odd/missing string still
## produces a sane pad instead of a magic constant with no relation to this frame at all.
const PAD_SIZE_TO_ARM_RATIO := 0.12
const PAD_THICKNESS_M := 0.003

## dict of MotorLayout motor name -> the Node3D sitting exactly at that motor's position
## (the mount pad). Tests assert against this rather than walking get_children().
var arm_tips: Dictionary = {}

## The top centre plate. Named alongside arm_tips and for the same reason: it is a MOUNTING
## SURFACE, and anything bolted to it should hang off it rather than be positioned next to it, so a
## frame rebuild takes its payload with it. The battery is the first such thing.
var plate_top: MeshInstance3D
## Side length of the centre plates, in metres. What the pack's overhang is measured against, so
## the number the fit check uses is the plate that is actually on screen.
var plate_side_m := 0.0
## Every place on this frame where something attaches, in the order mount_points_for() lists them.
## Regenerated on every rebuild, because a mount is a position on a plate and the plates move.
var mount_points: Array[MountPoint] = []

## Height of the top plate's upper face above the datum, metres. Stored rather than measured back
## off the mesh: an extruded plate is an ArrayMesh with no `size` to read, and the number was always
## a property of the document rather than of the box that happened to represent it.
var _plate_top_face_m := 0.0


## Clears any previously generated geometry and rebuilds it from `frame`. Safe to call
## repeatedly with different frames; the only state that survives a call is this node
## itself and the `arm_tips` dictionary, which is fully replaced each time.
## `plate_gap_m` is the standoff height the builder has chosen (AssemblyTweaks). A negative value
## means "whatever this frame implies", which is what every caller with no opinion passes — the
## default is derived, so a frame change moves it rather than freezing it at whatever the frame
## on screen happened to be when the file was first written.
func rebuild(frame: Dictionary, plate_gap_m: float = -1.0) -> void:
	rebuild_document(AirframeDocument.from_catalog_frame(frame), frame, plate_gap_m)


## Draws one `AirframeDocument`. The door the Airframe room's editor uses, and the one `rebuild`
## goes through — a preset and a frame somebody drew reach the same code, which is the whole point
## of §2 making them the same object.
##
## `frame` is still taken, and only for two things the DOCUMENT does not carry: the catalog material
## name that decides how the surface looks, and the mount table, which is MountLayout's and is keyed
## off published specs. Neither is geometry.
func rebuild_document(
	document: AirframeDocument,
	frame: Dictionary,
	plate_gap_m: float = -1.0
) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	arm_tips.clear()
	plate_top = null
	plate_side_m = 0.0
	_plate_top_face_m = 0.0

	var arm_m: float = float(frame.get("specs", {}).get("arm_mm", 0.0)) / 1000.0
	var material := _material_for(frame)

	if document != null and not document.plates.is_empty():
		_build_plates(document, material, plate_gap_m)
	else:
		# A moulded frame, or a document with nothing drawn in it yet. §7.3: a duct or a moulded
		# body is genuinely three-dimensional and the plate model cannot describe it, so this is an
		# explicit stand-in rather than a claim about the shape.
		_build_placeholder_body(arm_m, frame, material, plate_gap_m)

	_build_pads(arm_m, frame, material)
	mount_points = mount_points_for(frame, plate_gap_m)
	_seat_top_plate_on_its_mount()


## Standoff height when nobody has chosen one. Forwards to MountLayout, which decides it — asking
## a frame about its own standoffs is a reasonable thing to do, and these accessors stay so that
## every existing caller keeps asking the question where it makes sense to ask it.
static func default_plate_gap_m() -> float:
	return MountLayout.default_plate_gap_m()


## The shortest standoff that still leaves two plates: one plate thickness. Below that the gap is
## thinner than the parts either side of it and the stack reads as a single slab.
static func min_plate_gap_m() -> float:
	return MountLayout.min_plate_gap_m()


## Height of the top plate's UPPER face above the airframe's origin — the surface anything strapped
## to the top of the stack rests on. Read off the generated plate rather than recomputed from the
## gap, so a standoff tweak carries whatever sits on it without the caller knowing there is a
## standoff at all. Zero before the first rebuild().
func plate_top_face_m() -> float:
	return _plate_top_face_m


## Every place on this frame where something attaches. The table itself is MountLayout's, because
## the MASS MODEL needs it too and Build must not instantiate a Node3D to find out where its own
## pack is — see MountLayout for why the arithmetic moved down rather than being copied up.
static func mount_points_for(frame: Dictionary, plate_gap_m: float) -> Array[MountPoint]:
	return MountLayout.for_frame(frame, plate_gap_m)


## How far fore or aft anything mounted on this frame may be slid before it is inside a propeller
## hub. MountLayout's, for the same reason.
static func mount_reach_m(arm_m: float) -> float:
	return MountLayout.reach_m(arm_m)


static func max_plate_gap_m(arm_m: float) -> float:
	return MountLayout.max_plate_gap_m(arm_m)


## Every plate in the document, extruded from its own outline at its own thickness and height.
##
## §7.2's whole claim in one loop: change a polygon, the mesh changes, because there is no second
## representation. The plate you see IS the polygon `AirframeProperties` integrates and `ArmProfile`
## measures — so an arm that looks 5 mm thick on screen is the 5 mm that is cubed in the bending
## stiffness, rather than a box scaled by a constant that nothing else reads.
func _build_plates(
	document: AirframeDocument,
	material: StandardMaterial3D,
	plate_gap_m: float
) -> void:
	# THE TWO VERTICAL DATUMS, RECONCILED IN ONE PLACE.
	#
	# An `AirframeDocument` measures height from the BOTTOM of the frame: the bottom plate sits at
	# z = 0 and everything else stacks above it (§2). `MountLayout` — which is where the mass model
	# and every mount position come from — measures from the MIDDLE: the bottom plate's centre is at
	# −gap/2 and the top plate's at +gap/2, so the origin sits between them.
	#
	# Both are right for what they do. A document is a thing you cut and bolt together, and its
	# natural zero is the table it lies on; the simulation's natural zero is the point it rotates
	# about. What is NOT allowed is for the picture to use one and the mount table the other, which
	# is what happened when plates first became extrusions: the pack floated 10 mm above a plate that
	# had moved out from under it.
	#
	# So the drawing is mapped onto the mount table's convention here, and only here: centre the
	# stack on the origin, and rescale it to whatever standoff the builder has chosen.
	var centres := PackedFloat64Array()
	for plate in document.plates:
		centres.append(AirframeDocument.plate_z_mm(plate)
			+ AirframeDocument.plate_thickness_mm(plate) * 0.5)
	var lowest := 0.0
	var highest := 0.0
	if not centres.is_empty():
		lowest = centres[0]
		highest = centres[0]
		for value in centres:
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	var authored_gap := highest - lowest
	var middle := (lowest + highest) * 0.5
	# Centre-to-centre, matching MountLayout's meaning of "gap" exactly — see its `for_frame`, where
	# the top plate's centre is at +gap/2.
	var target_gap := plate_gap_m * 1000.0 if plate_gap_m >= 0.0 else authored_gap
	var stretch := 1.0
	if authored_gap > 0.0 and target_gap > 0.0:
		stretch = target_gap / authored_gap

	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		var outline := AirframeDocument.plate_outline(plate)
		var thickness := AirframeDocument.plate_thickness_mm(plate)
		var role := str(plate.get("role", "plate"))
		# Its centre, on the shared datum. The mesh is centred on its own origin, so this is the
		# node's height and not part of the geometry.
		var centre := (centres[index] - middle) * stretch
		var mesh := PlateMesh.extrude(outline, thickness)
		if mesh == null:
			# A self-intersecting or degenerate outline. Skipped rather than drawn wrong, and it is
			# not silent: FrameWarnings has already told the builder in the room where they drew it.
			continue

		var node := MeshInstance3D.new()
		# The two structural plates keep the names they have always had. Several callers and tests
		# ask this node for "PlateTop" by name, and a rename would be a change to everything that
		# has ever mounted anything on a frame in exchange for nothing.
		node.name = _node_name_for(role, index)
		node.mesh = mesh
		node.material_override = material
		node.position = Vector3(0.0, centre / 1000.0, 0.0)
		add_child(node)

		# The top plate is a MOUNTING SURFACE, not just geometry — the pack is strapped to it and
		# hangs off this node, so a frame rebuild takes its payload with it.
		if role == AirframeDocument.ROLE_TOP or plate_top == null:
			var face := (centre + thickness * 0.5) / 1000.0
			if role == AirframeDocument.ROLE_TOP or face > _plate_top_face_m:
				plate_top = node
				_plate_top_face_m = face
				plate_side_m = _outline_side_m(outline)


## Puts the top plate exactly where the mount table says its face is.
##
## THE MOUNT TABLE WINS, and it is worth being explicit about why, because the drawing has the
## better number. `MountLayout` builds the stack from one authored plate thickness for every frame;
## the document has the frame's own sourced thickness, which for the 5" freestyle is 2.5 mm rather
## than the constant. So the extruded plate's face and the strap mount sat about a millimetre apart,
## and the pack — which hangs off the mount — floated that millimetre above the plate it is strapped
## to.
##
## A millimetre is nothing to look at and everything to reason about: the mount table is what the
## MASS MODEL uses to place the pack, so the two must not be allowed to differ at all. One of them
## has to be the authority and it cannot be this file, because a picture that moved the pack's
## centre of mass would be geometry deciding physics from the wrong end. So the plate is seated on
## its mount, and the honest fix — teaching `MountLayout` each frame's real plate thickness — is a
## change to the mass model, which belongs in its own slice with its own tests rather than as a
## side effect of a drawing change.
func _seat_top_plate_on_its_mount() -> void:
	var top_mount: MountPoint = null
	var stack_mount: MountPoint = null
	for mount in mount_points:
		if mount.id == "strap_top":
			top_mount = mount
		elif mount.id == "stack":
			stack_mount = mount
	if top_mount == null or stack_mount == null:
		return

	# The two structural plates go exactly where the table puts their CENTRES: ±gap/2 about the
	# origin. Both, not just the top one — moving one of them alone changes the distance between
	# them, which is the standoff height the builder chose and the thing the tweak is named after.
	var gap := top_mount.position.y - stack_mount.position.y
	for child in get_children():
		if child.name == "PlateTop":
			(child as Node3D).position = Vector3(0.0, gap * 0.5, 0.0)
		elif child.name == "PlateBottom":
			(child as Node3D).position = Vector3(0.0, -gap * 0.5, 0.0)

	# And the seating surface is the mount's, not the mesh's. See the note above: where the table and
	# the drawing disagree about plate thickness, the table wins, because the mass model reads it.
	_plate_top_face_m = top_mount.position.y


## What a plate's node is called. `bottom` and `top` keep their historical names; everything else
## is named for its role and its index, so two side plates are tellable apart in a scene tree.
static func _node_name_for(role: String, index: int) -> String:
	match role:
		AirframeDocument.ROLE_TOP:
			return "PlateTop"
		AirframeDocument.ROLE_BOTTOM:
			return "PlateBottom"
	return "Plate_%s_%d" % [role, index]


## The side of the smallest square that covers an outline, metres. What the pack's overhang is
## measured against, so the number the fit check uses is the plate that is actually on screen.
static func _outline_side_m(outline: PackedVector2Array) -> float:
	if outline.is_empty():
		return 0.0
	var min_mm := outline[0]
	var max_mm := outline[0]
	for point in outline:
		min_mm = min_mm.min(point)
		max_mm = max_mm.max(point)
	return maxf(max_mm.x - min_mm.x, max_mm.y - min_mm.y) / 1000.0


## A stand-in body for a frame with no plate geometry (§7.3). The old ratio-drawn arms and plates,
## kept ONLY for this case: a moulded whoop has to appear on screen, and four motors floating in
## space would be a worse answer than a box that is honestly not the shape of the product.
func _build_placeholder_body(
	arm_m: float,
	frame: Dictionary,
	material: StandardMaterial3D,
	plate_gap_m: float
) -> void:
	var arm_width: float = arm_m * ARM_WIDTH_TO_LENGTH_RATIO
	var arm_thickness: float = arm_width * ARM_THICKNESS_TO_WIDTH_RATIO

	for motor_name in MotorLayout.MOTOR_NAMES:
		var tip := MotorLayout.motor_position(motor_name, arm_m)
		var arm := MeshInstance3D.new()
		arm.name = "Arm_%s" % motor_name
		var box := BoxMesh.new()
		box.size = Vector3(tip.length(), arm_width, arm_thickness)
		arm.mesh = box
		arm.material_override = material
		arm.position = tip * 0.5
		var forward := tip.normalized()
		var up := Vector3.UP
		if absf(forward.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var new_up := forward.cross(up).cross(forward).normalized()
		arm.transform.basis = Basis(forward, new_up, new_up.cross(forward).normalized())
		add_child(arm)

	var side: float = arm_m * CENTRE_PLATE_TO_ARM_RATIO
	var thickness: float = Build.FRAME_PLATE_THICKNESS_M
	var gap: float = plate_gap_m if plate_gap_m >= 0.0 else default_plate_gap_m()
	plate_side_m = side

	for entry in [["PlateTop", gap * 0.5], ["PlateBottom", -gap * 0.5]]:
		var node := MeshInstance3D.new()
		node.name = str(entry[0])
		var mesh := BoxMesh.new()
		mesh.size = Vector3(side, thickness, side)
		node.mesh = mesh
		node.material_override = material
		node.position = Vector3(0.0, float(entry[1]), 0.0)
		add_child(node)
		if entry[0] == "PlateTop":
			plate_top = node
			_plate_top_face_m = float(entry[1]) + thickness * 0.5
	# `frame` is unused here beyond what the caller already read; named in the signature so this
	# function reads the same way as the one it stands in for.
	var _unused := frame


## The motor-mount pads: one small node at each motor position, whatever drew the body.
##
## SEPARATE FROM THE PLATES, and it stays that way now that plates are extruded. A pad is not
## structure — it is the anchor a motor is parented to, so that a frame rebuild carries the motors
## with it — and the plate under it is drawn by the extrusion like every other plate.
func _build_pads(arm_m: float, frame: Dictionary, material: StandardMaterial3D) -> void:
	var pad_size := _pad_size_m(frame, arm_m)
	for motor_name in MotorLayout.MOTOR_NAMES:
		var tip := MotorLayout.motor_position(motor_name, arm_m)
		var pad := MeshInstance3D.new()
		pad.name = "Pad_%s" % motor_name
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(pad_size, PAD_THICKNESS_M, pad_size)
		pad.mesh = pad_mesh
		pad.material_override = material
		pad.position = tip
		add_child(pad)
		arm_tips[motor_name] = pad


## The motor-mount pad's bolt-spacing side length, parsed from the frame's motor_mount
## string (e.g. "16x16" -> 0.016 m) when possible. This is frame hardware (the plate the
## motor bolts to), not the motor itself, so it stays in scope here. Falls back to a
## fraction of arm_m for a frame dictionary that omits or malforms the field, which the
## missing-catalog-block test exercises.
func _pad_size_m(frame: Dictionary, arm_m: float) -> float:
	var mount: String = frame.get("specs", {}).get("motor_mount", "")
	var parts := mount.split("x")
	if parts.size() == 2 and parts[0].is_valid_float():
		return float(parts[0]) / 1000.0
	return arm_m * PAD_SIZE_TO_ARM_RATIO


## Reads material appearance from frame["catalog"]["material"] by substring match, with a
## safe default when the catalog block is absent (it is being added to frames.json
## concurrently with this file, so mid-edit reads must not crash) or unrecognised. Carbon
## fibre reads dark and glossy; nylon reads lighter and matte; anything else gets a neutral
## middle-ground so an unrecognised material is visibly a frame but not asserting a look
## it hasn't earned.
func _material_for(frame: Dictionary) -> StandardMaterial3D:
	var catalog: Dictionary = frame.get("catalog", {})
	var material_name: String = String(catalog.get("material", "")).to_lower()

	# Albedos are lifted well above the true reflectance of these materials on purpose. Real
	# 3K carbon is near-black, and rendering it honestly turned the airframe into an unreadable
	# smear against a dark viewport — the arms, which are the whole point of this screen,
	# disappeared. architecture.md already names this tradeoff: derive from physics, then
	# transform for perception. This is the vision layer's perceptual transform, and it is why
	# carbon here reads as dark grey with a sheen rather than as black.
	var mat := StandardMaterial3D.new()
	if material_name.contains("carbon"):
		mat.albedo_color = Color(0.14, 0.145, 0.16)
		mat.roughness = 0.35
		mat.metallic = 0.25
	elif material_name.contains("nylon"):
		mat.albedo_color = Color(0.62, 0.62, 0.58)
		mat.roughness = 0.85
		mat.metallic = 0.0
	else:
		mat.albedo_color = Color(0.36, 0.36, 0.38)
		mat.roughness = 0.6
		mat.metallic = 0.05
	return mat
