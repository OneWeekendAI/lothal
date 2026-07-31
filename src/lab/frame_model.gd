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

## Arm cross-section, not in the JSON: parts.md's spec-field table has no body-dimension
## field for a frame's arm, so — same precedent as Build.FRAME_PLATE_TO_ARM_RATIO — it is
## derived from arm_m instead of authored. An arm on a real quad is roughly 1/8 as wide as
## it is long, and noticeably thinner than it is wide (carbon plate, not a square rod).
const ARM_WIDTH_TO_LENGTH_RATIO := 1.0 / 8.0
const ARM_THICKNESS_TO_WIDTH_RATIO := 0.5

## Vertical gap between the top and bottom centre plates (standoff height), also not a
## parts.md spec field. Expressed relative to the plate thickness Build already derives,
## rather than as a fresh authored number.
const PLATE_STACK_GAP_TO_THICKNESS_RATIO := 1.5

## The tallest standoffs this frame can sensibly take, as a fraction of the centre plate's own
## side length. Past this the stack is taller than the plate is wide and the thing has stopped
## being a quadcopter — the same class of documented rule of thumb as the arm cross-section
## above, and the DERIVED limit behind the standoff tweak (see AssemblyTweaks.limits).
const MAX_PLATE_GAP_TO_PLATE_SIDE_RATIO := 0.5

## Centre-plate side length as a fraction of arm length. This deliberately does NOT reuse
## Build.FRAME_PLATE_TO_ARM_RATIO, and the distinction matters: Build's box (150 mm for a
## 110 mm arm) is a lumped stand-in for the mass distribution of the WHOLE airframe, arms
## included — which is why it is wider than the arms reach. Using it as the literal centre
## plate drew a slab that swallowed the arms entirely, so the one thing this screen exists to
## show was invisible. A real 5" frame carries roughly a 60 mm centre plate on a 110 mm arm.
const CENTRE_PLATE_TO_ARM_RATIO := 0.55

## Fallback bolt spacing (metres) when a frame's motor_mount string cannot be parsed, e.g.
## "16x16" -> 0.016. Falls back to a fraction of arm_m so an odd/missing string still
## produces a sane pad instead of a magic constant with no relation to this frame at all.
const PAD_SIZE_TO_ARM_RATIO := 0.12
const PAD_THICKNESS_M := 0.003

## The narrowest strip of plate a battery strap slot can be cut into, either side of the centre
## bolt pattern. Below this there is no carbon left to cut, which is what decides whether a frame
## offers a bottom-plate mount at all — see mount_points_for().
const MIN_STRAP_SLOT_M := 0.010

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


## Clears any previously generated geometry and rebuilds it from `frame`. Safe to call
## repeatedly with different frames; the only state that survives a call is this node
## itself and the `arm_tips` dictionary, which is fully replaced each time.
## `plate_gap_m` is the standoff height the builder has chosen (AssemblyTweaks). A negative value
## means "whatever this frame implies", which is what every caller with no opinion passes — the
## default is derived, so a frame change moves it rather than freezing it at whatever the frame
## on screen happened to be when the file was first written.
func rebuild(frame: Dictionary, plate_gap_m: float = -1.0) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	arm_tips.clear()

	var arm_m: float = float(frame["specs"]["arm_mm"]) / 1000.0
	var material := _material_for(frame)

	_build_arms_and_pads(arm_m, frame, material)
	_build_centre_plates(arm_m, material, plate_gap_m)
	mount_points = mount_points_for(frame, plate_gap_m)


## Standoff height when nobody has chosen one: the ratio above, applied to the plate thickness
## Build already derives. Static so AssemblyTweaks can quote it as a default without building a
## frame to ask.
static func default_plate_gap_m() -> float:
	return Build.FRAME_PLATE_THICKNESS_M * PLATE_STACK_GAP_TO_THICKNESS_RATIO


## The shortest standoff that still leaves two plates: one plate thickness. Below that the gap is
## thinner than the parts either side of it and the stack reads as a single slab.
static func min_plate_gap_m() -> float:
	return Build.FRAME_PLATE_THICKNESS_M


## Height of the top plate's UPPER face above the airframe's origin — the surface anything strapped
## to the top of the stack rests on. Read off the generated plate rather than recomputed from the
## gap, so a standoff tweak carries whatever sits on it without the caller knowing there is a
## standoff at all. Zero before the first rebuild().
func plate_top_face_m() -> float:
	if plate_top == null:
		return 0.0
	return plate_top.position.y + (plate_top.mesh as BoxMesh).size.y * 0.5


## Every place on this frame where something attaches, derived from the frame's own specs and the
## standoff height currently fitted. Static because the limits on the fit panel are needed before
## anything is drawn (AssemblyTweaks.limits), and because a mount table that could only be obtained
## by generating geometry would tempt somebody into writing a second one that could not.
##
## WHICH MOUNTS A FRAME HAS IS A PROPERTY OF THAT FRAME, not a constant this file knows. Every
## frame has a centre-plate bolt pattern and a top-plate strap location — a pack goes on top of
## even a 65 mm whoop. A BOTTOM-plate strap location has to be earned: the bottom plate is the one
## the stack bolts down onto and the arms clamp against, so a pack underneath has to strap through
## slots cut BESIDE the bolt pattern, and on a small frame the pattern has already eaten the plate.
## A 3" toothpick carries a 25.5 pattern through a 41 mm plate and has 8 mm of carbon either side
## of it; a 5" freestyle has 15 mm either side of a 30.5 pattern on a 60 mm plate. That is why the
## toothpick offers two mounts and the freestyle three, and it is arithmetic rather than a policy.
static func mount_points_for(frame: Dictionary, plate_gap_m: float) -> Array[MountPoint]:
	var arm_m: float = float(frame.get("specs", {}).get("arm_mm", 0.0)) / 1000.0
	var side: float = arm_m * CENTRE_PLATE_TO_ARM_RATIO
	var thickness: float = Build.FRAME_PLATE_THICKNESS_M
	var gap: float = plate_gap_m
	if gap < 0.0:
		gap = default_plate_gap_m()

	var span := Vector2(side, side)
	var reach := mount_reach_m(arm_m)
	var pattern: String = String(frame.get("specs", {}).get("stack_mount", ""))
	var pattern_m := MountPoint.parse_pattern_m(pattern)

	var out: Array[MountPoint] = []

	# The standoff stack. The seat is the bottom plate's UPPER face, which is where the standoffs
	# start and where the lower board in a stack actually sits; the stack then grows upward into the
	# gap between the plates — the gap the standoff tweak sets.
	var stack := MountPoint.new()
	stack.id = "stack"
	stack.label = "the standoff stack"
	stack.attachment = MountPoint.BOLT
	stack.pattern = pattern
	stack.pattern_m = pattern_m
	stack.position = Vector3(0.0, -gap * 0.5 + thickness * 0.5, 0.0)
	stack.normal = 1
	stack.span_m = span
	stack.reach_m = 0.0
	out.append(stack)

	var top := MountPoint.new()
	top.id = "strap_top"
	top.label = "the top plate"
	top.attachment = MountPoint.STRAP
	top.position = Vector3(0.0, gap * 0.5 + thickness * 0.5, 0.0)
	top.normal = 1
	top.span_m = span
	top.reach_m = reach
	out.append(top)

	if side - pattern_m.x >= 2.0 * MIN_STRAP_SLOT_M:
		var bottom := MountPoint.new()
		bottom.id = "strap_bottom"
		bottom.label = "the bottom plate"
		bottom.attachment = MountPoint.STRAP
		bottom.position = Vector3(0.0, -(gap * 0.5 + thickness * 0.5), 0.0)
		bottom.normal = -1
		bottom.span_m = span
		bottom.reach_m = reach
		out.append(bottom)

	return out


## How far fore or aft anything mounted on this frame may be slid before it is inside a propeller
## hub: the front motors' own forward extent, from the same MotorLayout table the physics reads.
## Nothing may be positioned past it, and a component long enough to reach it at zero offset has no
## travel at all — which is how a longer pack narrows its own range (AssemblyTweaks.limits).
static func mount_reach_m(arm_m: float) -> float:
	return absf(MotorLayout.motor_position("M2", arm_m).z)


static func max_plate_gap_m(arm_m: float) -> float:
	return arm_m * CENTRE_PLATE_TO_ARM_RATIO * MAX_PLATE_GAP_TO_PLATE_SIDE_RATIO


## One BoxMesh per motor, spanning from the centre to that motor's arm-tip position, plus
## a small mount pad centred on the tip itself. Orientation is derived from the actual
## motor_position vector via look_at, never a hardcoded 45-degree rotation, so an odd
## future layout (not a symmetric X) would still come out correct.
func _build_arms_and_pads(arm_m: float, frame: Dictionary, material: StandardMaterial3D) -> void:
	var arm_width: float = arm_m * ARM_WIDTH_TO_LENGTH_RATIO
	var arm_thickness: float = arm_width * ARM_THICKNESS_TO_WIDTH_RATIO
	var pad_size := _pad_size_m(frame, arm_m)

	for motor_name in MotorLayout.MOTOR_NAMES:
		var tip := MotorLayout.motor_position(motor_name, arm_m)
		var length := tip.length()
		var midpoint := tip * 0.5

		var arm := MeshInstance3D.new()
		arm.name = "Arm_%s" % motor_name
		var box := BoxMesh.new()
		# Box's local Y axis is the "long" axis; we lay it flat by rotating below, so length
		# goes on X here and gets pointed at the tip via basis, not by re-authoring the mesh.
		box.size = Vector3(length, arm_width, arm_thickness)
		arm.mesh = box
		arm.material_override = material
		arm.position = midpoint
		# Orient the box's local +X axis (its length) toward the tip. transform.basis.x is
		# the box's long axis, so build a basis whose X column is the tip direction.
		var forward := tip.normalized()
		var up := Vector3.UP
		if absf(forward.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var right := forward
		var new_up := right.cross(up).cross(right).normalized()
		var new_forward := new_up.cross(right).normalized()
		arm.transform.basis = Basis(right, new_up, new_forward)
		add_child(arm)

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


## Twin top/bottom centre plates. Plate THICKNESS is taken from Build.FRAME_PLATE_THICKNESS_M
## so that number stays authored in one place, but the plate's SIDE is deliberately its own
## ratio — see CENTRE_PLATE_TO_ARM_RATIO for why Build's footprint constant is the wrong
## thing to draw here.
func _build_centre_plates(arm_m: float, material: StandardMaterial3D, plate_gap_m: float) -> void:
	var side: float = arm_m * CENTRE_PLATE_TO_ARM_RATIO
	var thickness: float = Build.FRAME_PLATE_THICKNESS_M
	var gap: float = plate_gap_m
	if gap < 0.0:
		gap = default_plate_gap_m()

	plate_side_m = side

	var top := MeshInstance3D.new()
	top.name = "PlateTop"
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(side, thickness, side)
	top.mesh = top_mesh
	top.material_override = material
	top.position = Vector3(0, gap * 0.5, 0)
	add_child(top)
	plate_top = top

	var bottom := MeshInstance3D.new()
	bottom.name = "PlateBottom"
	var bottom_mesh := BoxMesh.new()
	bottom_mesh.size = Vector3(side, thickness, side)
	bottom.mesh = bottom_mesh
	bottom.material_override = material
	bottom.position = Vector3(0, -gap * 0.5, 0)
	add_child(bottom)


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
