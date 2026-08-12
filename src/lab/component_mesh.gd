class_name ComponentMesh
extends Node3D
## The four components LTHL-11 unbundled — camera, VTX, antenna, receiver — as real objects on the
## aircraft, generated from the box each part publishes.
##
## It exists for the same reason StackMesh does, and the argument in that file's header is verbatim
## the one that applies here: Build.mass_parts() has been flying a camera at a specific place on
## this airframe since LTHL-11, the centre of mass and the inertia tensor move when one is fitted,
## and there was no picture of any of it. Lab's stated job is that the fit check and the picture are
## the same geometry (labs-and-sim.md §2.2), and four components with a fit consequence and no
## picture is that promise unkept four times over.
##
## THE MASS DID NOT GO UP. Everything drawn here was already weighed and already placed; this slice
## draws mass that was already there. The reference build's 496 g, 11.7:1 and 4.1 min are unmoved,
## and if any of them moves this class is wrong.
##
## ONE CLASS FOR FOUR CATEGORIES, following CustomComponents rather than the six older part
## categories, and for the reason its header gives: these four are one question asked four times —
## a box with a mass sitting in a bay it did not choose, with no coefficient, no rating and no
## curve. Four mesh classes would be four copies of one file.
##
## NOTHING DRAWN HERE COMES FROM ANYWHERE BUT `specs`. The size is Build.component_size_of() — the
## same call the mass model makes — and every proportion below is a fraction OF that box. That is
## what makes this class need no change the day custom electronics parts exist: a custom part
## publishes the same three dimensions, and if this file ever has to be edited to serve one, it has
## read something it should not have.
##
## IT DOES NOT POSITION ITSELF, exactly as StackMesh and MotorMesh do not. The seating call is
## AirframeModel's and is the SAME MountLayout.seated_centre_m() call the mass model makes — the
## moment it is a second sum, the picture and the tensor can drift.
##
## Node layout after rebuild(), by category:
##   camera    Body, Lens, Eye (a marker, not geometry)
##   vtx       Board, Can
##   antenna   Whip (rotated), containing Pigtail and Tip
##   receiver  Board, Wire

## The lens barrel on the camera's nose, as fractions of the published box. A micro FPV camera is a
## square-fronted body with a round lens standing proud of it; the barrel is most of the width and
## a fifth of the depth, which is what makes the silhouette read as a camera and not as a die.
const LENS_RADIUS_TO_WIDTH := 0.34
const LENS_DEPTH_TO_LENGTH := 0.22

## The VTX's metal can, as a fraction of the board's footprint. A shielded transmitter is a can
## soldered to a PCB with a margin of board showing round it, and that margin is what makes the
## board visible at all from above.
const CAN_TO_BOARD := 0.78

## The antenna's coax pigtail, as fractions of the published box: a thin cable standing off the
## mount, carrying the radiating tip. Its length is a fraction of the WHOLE published length, so a
## 40 mm nano dipole and a 95 mm long-range whip are the same object at two sizes.
const PIGTAIL_LENGTH_TO_LENGTH := 0.42
const PIGTAIL_RADIUS_TO_WIDTH := 0.16
## How far aft the whip leans from vertical, in degrees. An antenna stands up and back: up so the
## props do not take it off, back so it is behind everything else on the aircraft. This is the one
## number here that is not a fraction of a published dimension, and it is a pose rather than a
## dimension — the extent ALONG the whip's own axis is still exactly `length_mm`.
const WHIP_LEAN_DEGREES := 25.0

## The receiver's antenna wire: a thin tail out of the back, which is the only recognisable feature
## a receiver has. Nose is -Z, so it exits +Z.
const WIRE_LENGTH_TO_LENGTH := 1.6
const WIRE_RADIUS_TO_WIDTH := 0.05

## Drawn, but NOT measured: geometry that is soft, floppy, or routed rather than placed. Nothing in
## it participates in a fit check, and the receiver's antenna wire is the whole of it today.
##
## BatteryMesh set this precedent and stated the reason — its straps are drawn proud of the pack and
## excluded from the pack's measured extent, because a strap is not part of how big a pack is. A
## receiver's wire is the same kind of object one step further: it is a length of coax a builder
## routes wherever there is room, and measuring it made the receiver read as a 41 mm object on every
## frame in the catalog, which reported the reference build's VTX and receiver as colliding. They do
## not collide; a wire was lying between them. Anything added here must be genuinely soft — a rigid
## part left off this list is a fit consequence with no picture, which is the failure this whole
## class exists to end.
const UNMEASURED_PARTS := ["Wire"]

## How far in front of the lens's own front face the eye sits, in metres. Just enough that the
## barrel it is looking out of is behind the near plane rather than filling the frame — a camera
## cannot see its own glass, and a view that opened on the inside of a cylinder would read as a
## broken render rather than as an eye placed one millimetre too far back.
const EYE_STANDOFF_M := 0.001

## The part's published box in BODY axes: width across X, height up Y, length along Z. Straight from
## Build.component_size_of(), which is what the inertia box is built from — so the object drawn here
## and the object the physics spins are one set of numbers.
var size_m := Vector3.ZERO
## Which of the four this is, kept so callers can name what they are looking at without a lookup.
var category := ""


## Clears any previous component and rebuilds it as `p_category` from `part`. Safe to call on every
## selection change; nothing survives a call except this node.
##
## Measured from its own CENTRE, like BatteryMesh and unlike StackMesh: the box the mass model
## weighs is centred on seated_centre_m(), so a mesh centred on its own origin is drawn exactly
## where that mass is. The antenna is the one silhouette that reaches outside its box — see
## _build_antenna() for why that is honest rather than sloppy.
func rebuild(p_category: String, part: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	category = p_category
	size_m = Build.component_size_of(part)

	match category:
		"camera": _build_camera()
		"vtx": _build_vtx()
		"antenna": _build_antenna()
		"receiver": _build_receiver()
		_: _build_block()


## The box this component's DRAWN geometry actually occupies, in the parent's space, measured off the
## meshes rather than taken from `size_m` — and that difference is the whole point of the method.
##
## A camera's lens fills its nose and an antenna's whip leans a long way aft and well above its box,
## so a fit check fed `size_m` would report a comfortable gap for geometry that is visibly in a
## propeller disc or visibly through the plate above it. labs-and-sim.md §2.2 says the fit check and
## the picture are the same geometry; this is that sentence made literal for a silhouette that has
## stopped being a box.
##
## Merges the mesh instances' transformed AABBs, so it stays right for any silhouette added later
## without anybody remembering to update a second footprint table.
func drawn_aabb_m() -> AABB:
	var bounds := AABB()
	var found := false
	for node in _mesh_instances(self, Transform3D.IDENTITY):
		var mesh := node["mesh"] as MeshInstance3D
		if UNMEASURED_PARTS.has(String(mesh.name)):
			continue
		var box: AABB = node["transform"] * mesh.get_aabb()
		if found:
			bounds = bounds.merge(box)
		else:
			bounds = box
			found = true
	return bounds


## The same box in plan view: across X and along Z, which is the projection every propeller-disc
## measurement is taken in.
func plan_bounds_m() -> Rect2:
	var box := drawn_aabb_m()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## How much of the bay's surface this part actually stands on, across X and along Z, in metres —
## which for three of the four is simply the published box read the usual way round.
##
## THE ANTENNA IS NOT ONE OF THE THREE, and this method exists for it. Its published 95 x 22 x 22 is
## a bounding box for a whip, and the whip stands UP: it occupies 22 mm of plate and 95 mm of air
## above it, so reading `length_mm` as a fore/aft footprint asks a 5" freestyle whether it can seat a
## 55 mm object it is not being asked to seat. Measured that way every antenna in the catalog
## overhangs every frame, which is the same noise battery_fit_warnings() deliberately refuses to
## make about the pack's normal 7 mm fore/aft overhang.
##
## This is the seat, not the silhouette: what the whip does in the air above the plate is the
## propeller-disc check's business, and it is measured there off the drawn geometry.
func seat_footprint_m() -> Vector2:
	if category == "antenna":
		return Vector2(size_m.x, size_m.x)
	return Vector2(size_m.x, size_m.z)


## Every MeshInstance3D under `node`, each with its transform relative to this component. Recursive
## because the antenna's parts hang off a rotated child, which is exactly the case a flat loop over
## get_children() would silently get wrong.
func _mesh_instances(node: Node, accumulated: Transform3D) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Node3D:
			var placement: Transform3D = accumulated * (child as Node3D).transform
			if child is MeshInstance3D:
				out.append({"mesh": child, "transform": placement})
			out.append_array(_mesh_instances(child, placement))
	return out


## How far the antenna reaches along ITS OWN axis, in metres — pigtail plus radiating tip, measured
## off the drawn cylinders in the whip's own frame. Zero for the other three, which have no axis
## distinct from their box.
##
## Its own accessor because it is the number that has to equal the published `length_mm`: the
## silhouette is allowed to differ from the inertia box, its SIZE is not.
func axis_extent_m() -> float:
	var whip := get_node_or_null("Whip")
	if whip == null:
		return 0.0
	var low := INF
	var high := -INF
	for child in whip.get_children():
		if child is MeshInstance3D:
			var box: AABB = (child as MeshInstance3D).transform * (child as MeshInstance3D).get_aabb()
			low = minf(low, box.position.y)
			high = maxf(high, box.position.y + box.size.y)
	if low == INF:
		return 0.0
	return high - low


# ---------------------------------------------------------------------------
# The four silhouettes
# ---------------------------------------------------------------------------

## A body cube with a lens barrel on its nose. A micro FPV camera is exactly that, and the reason it
## is worth drawing rather than leaving as a grey rectangle is that MountLayout's camera bay sits on
## the centre plate's FRONT EDGE precisely so the body straddles it and the lens pokes out the front
## — a comment in that file which, until this class existed, nobody could see was true.
func _build_camera() -> void:
	var lens_depth := size_m.z * LENS_DEPTH_TO_LENGTH
	_box("Body", Vector3(size_m.x, size_m.y, size_m.z - lens_depth),
		Vector3(0.0, 0.0, lens_depth * 0.5), _case_material())

	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var barrel := CylinderMesh.new()
	barrel.top_radius = size_m.x * LENS_RADIUS_TO_WIDTH
	barrel.bottom_radius = barrel.top_radius
	barrel.height = lens_depth
	barrel.radial_segments = 12
	barrel.rings = 1
	lens.mesh = barrel
	lens.material_override = _glass_material()
	# Cylinders are generated up Y, so the barrel is laid down to point forward (-Z).
	lens.rotate_x(PI * 0.5)
	lens.position = Vector3(0.0, 0.0, -size_m.z * 0.5 + lens_depth * 0.5)
	add_child(lens)

	# Where the glass is, looking where the camera looks. A marker rather than geometry, so it draws
	# nothing and — being no MeshInstance3D — is excluded from every measurement here for free.
	#
	# It exists so that FpvView has ONE answer to where the lens is: this node is seated by the
	# same MountLayout.seated_centre_m() call the mass model uses, so Sim's feed is taken from the
	# camera that is drawn and weighed rather than from a third opinion about where a camera sits.
	# A Node3D looks down its own -Z, which is already forward (physics.md §1), so there is no
	# rotation here and no tilt — see FpvView for why tilt is a separate slice.
	var eye := Marker3D.new()
	eye.name = "Eye"
	eye.position = Vector3(0.0, 0.0, -size_m.z * 0.5 - EYE_STANDOFF_M)
	add_child(eye)


## A board with a shield can, not a brick. The published boxes give it away — the 400 mW analog
## board is 30 x 20 x 6 mm and a whoop's VTX is 4 mm tall — so a solid block would be the wrong
## object at every size in the catalog.
##
## The PCB is StackMesh.BOARD_THICKNESS_M and the materials are StackMesh's, deliberately: a VTX and
## a flight controller are the same kind of object and should look it, and re-authoring 1.6 mm here
## would be a second opinion about what a PCB is.
func _build_vtx() -> void:
	var board_thickness := minf(StackMesh.BOARD_THICKNESS_M, size_m.y)
	_box("Board", Vector3(size_m.x, board_thickness, size_m.z),
		Vector3(0.0, -size_m.y * 0.5 + board_thickness * 0.5, 0.0), _board_material())

	var can_height := size_m.y - board_thickness
	if can_height <= 0.0:
		return
	_box("Can", Vector3(size_m.x * CAN_TO_BOARD, can_height, size_m.z * CAN_TO_BOARD),
		Vector3(0.0, -size_m.y * 0.5 + board_thickness + can_height * 0.5, 0.0), _can_material())


## The one that is not a box. 95 x 22 x 22 mm published is a whip on a pigtail, not a slab, and
## drawing it as a rectangle would be the least honest of the four silhouettes.
##
## THE DRAWN SHAPE AND THE INERTIA BOX LEGITIMATELY DIFFER HERE, and this is the only place in the
## project where they do. The physics still weighs the published box (Build.component_size_of), and
## that is a small error for a thin whip — an inertia box is linear in mass and quadratic in size,
## and this is 5-12 g. Drawing the slab instead would be a large lie, in the one place a builder
## most needs to see the truth: the antenna is the furthest-out mass on the aircraft and the thing
## most likely to be in a propeller's way. Small numeric error, honest picture; the reverse trade
## would be the divergence this whole layer exists to prevent.
##
## It stands UP AND AFT off its mount: up because the props are up there, aft because everything
## else is forward of it. The whole assembly hangs off a rotated child so that its extent along its
## own axis is exactly the published length however far it leans — see axis_extent_m().
func _build_antenna() -> void:
	var whip := Node3D.new()
	whip.name = "Whip"
	# Seated on the box's underside rather than its centre: an antenna rises OFF its mount, and
	# starting at the centre would sink half of it into the plate it stands on.
	whip.position = Vector3(0.0, -size_m.y * 0.5, 0.0)
	# Leaning aft is a rotation about X. Nose is -Z, so a positive angle tips the top backwards.
	whip.rotate_x(deg_to_rad(WHIP_LEAN_DEGREES))
	add_child(whip)

	var pigtail_length := size_m.z * PIGTAIL_LENGTH_TO_LENGTH
	_cylinder_into(whip, "Pigtail", size_m.x * PIGTAIL_RADIUS_TO_WIDTH, pigtail_length,
		pigtail_length * 0.5, _cable_material())

	var tip_length := size_m.z - pigtail_length
	_cylinder_into(whip, "Tip", size_m.x * 0.5, tip_length,
		pigtail_length + tip_length * 0.5, _case_material())


## A bare board with a wire. It lives under the top plate on the centreline and is mostly hidden, so
## the recognisable feature is the antenna wire rather than the PCB. Nothing clever.
func _build_receiver() -> void:
	_box("Board", size_m, Vector3.ZERO, _board_material())

	var wire_length := size_m.z * WIRE_LENGTH_TO_LENGTH
	var wire := MeshInstance3D.new()
	wire.name = "Wire"
	var mesh := CylinderMesh.new()
	mesh.top_radius = size_m.x * WIRE_RADIUS_TO_WIDTH
	mesh.bottom_radius = mesh.top_radius
	mesh.height = wire_length
	mesh.radial_segments = 6
	mesh.rings = 1
	wire.mesh = mesh
	wire.material_override = _cable_material()
	# Cylinders are generated up Y, so it is laid flat and trailed aft (+Z) out of the back edge.
	wire.rotate_x(PI * 0.5)
	wire.position = Vector3(0.0, 0.0, size_m.z * 0.5 + wire_length * 0.5)
	add_child(wire)


## Anything else: the published box, plainly. Not reachable from the four categories above, and here
## so a fifth category added to Build.OPTIONAL_COMPONENTS draws SOMETHING rather than nothing while
## its own silhouette is being written — the failure this whole slice exists to end is a component
## with mass and no picture.
func _build_block() -> void:
	_box("Body", size_m, Vector3.ZERO, _case_material())


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

func _box(box_name: String, size: Vector3, centre: Vector3,
		material: StandardMaterial3D) -> void:
	var node := MeshInstance3D.new()
	node.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = centre
	add_child(node)


## A cylinder standing up Y, centred `centre_y` above the parent's origin.
func _cylinder_into(parent: Node3D, node_name: String, radius: float, height: float,
		centre_y: float, material: StandardMaterial3D) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(0.0, centre_y, 0.0)
	parent.add_child(node)


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------

## A moulded plastic case: the camera body and the antenna's radome. Lifted above true reflectance
## for the reason FrameModel's header sets out — this viewport is read against a dark background and
## a near-black airframe, and a part at its real darkness is a hole between the plates.
func _case_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.27, 0.30)
	mat.roughness = 0.55
	mat.metallic = 0.05
	return mat


## The lens: dark and glossy, so it reads as glass rather than as another lump of the case.
func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.12)
	mat.roughness = 0.08
	mat.metallic = 0.2
	return mat


## Solder mask, shared in spirit with StackMesh's boards — a VTX and a receiver are the same kind of
## object as a flight controller and should look it.
func _board_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.30, 0.24)
	mat.roughness = 0.45
	mat.metallic = 0.1
	return mat


## The VTX's shield can: bright aluminium, the same reading as the stack's standoffs.
func _can_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.70, 0.74)
	mat.roughness = 0.28
	mat.metallic = 0.75
	return mat


## Coax and antenna wire: black silicone, matte.
func _cable_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	mat.roughness = 0.8
	mat.metallic = 0.0
	return mat
