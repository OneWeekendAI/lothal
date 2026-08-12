class_name MountLayout
extends RefCounted
## Where a frame's mount points ARE, as pure arithmetic on the frame's own specs.
##
## This class exists to answer one question that had no good answer: Build needs to know where the
## pack is in order to put its mass there, and where the pack is was known only by FrameModel — a
## Node3D that Lab draws and Sim flies. Build is pure computation; it must not instantiate a scene
## node to find out where its own battery is. But a second copy of the mount arithmetic living in
## the mass model is the exact divergence airframe_model.gd was written to end, and the one this
## project has already been bitten by (a hardcoded 0.0778 arm in main.tscn against MotorLayout's
## real one).
##
## So neither: the arithmetic moves DOWN, into the layer both can see. FrameModel asks this class
## where the mounts are and draws them there; Build asks the same class and puts mass there. There
## is one table, it is a pure function of (frame specs, standoff height), and nothing has to be
## instantiated to read it.
##
## FrameModel keeps its static accessors as one-line forwarders — every caller that already asks it
## is asking a frame about its own mounts, which is a reasonable thing to ask a frame, and churning
## them would hide the actual change in this slice behind a rename.
##
## The consts below were FrameModel's and are unchanged in value. They live here now because they
## are properties of how a frame is laid out rather than of how one is drawn, which is the same
## distinction that put MountPoint next to them rather than in src/lab/.

## Centre-plate side length as a fraction of arm length. This deliberately does NOT reuse
## Build.FRAME_PLATE_TO_ARM_RATIO, and the distinction matters: Build's box (150 mm for a
## 110 mm arm) is a lumped stand-in for the mass distribution of the WHOLE airframe, arms
## included — which is why it is wider than the arms reach. Using it as the literal centre
## plate drew a slab that swallowed the arms entirely, so the one thing the frame screen exists to
## show was invisible. A real 5" frame carries roughly a 60 mm centre plate on a 110 mm arm.
const CENTRE_PLATE_TO_ARM_RATIO := 0.55

## Vertical gap between the top and bottom centre plates (standoff height), not a parts.md spec
## field. Expressed relative to the plate thickness Build already derives, rather than as a fresh
## authored number.
const PLATE_STACK_GAP_TO_THICKNESS_RATIO := 1.5

## The tallest standoffs a frame can sensibly take, as a fraction of the centre plate's own side
## length. Past this the stack is taller than the plate is wide and the thing has stopped being a
## quadcopter — a documented rule of thumb, and the DERIVED limit behind the standoff tweak.
const MAX_PLATE_GAP_TO_PLATE_SIDE_RATIO := 0.5

## The narrowest strip of plate a battery strap slot can be cut into, either side of the centre
## bolt pattern. Below this there is no carbon left to cut, which is what decides whether a frame
## offers a bottom-plate mount at all — see for_frame().
const MIN_STRAP_SLOT_M := 0.010


## Standoff height when nobody has chosen one: the ratio above, applied to the plate thickness
## Build already derives.
static func default_plate_gap_m() -> float:
	return Build.FRAME_PLATE_THICKNESS_M * PLATE_STACK_GAP_TO_THICKNESS_RATIO


## The shortest standoff that still leaves two plates: one plate thickness. Below that the gap is
## thinner than the parts either side of it and the stack reads as a single slab.
static func min_plate_gap_m() -> float:
	return Build.FRAME_PLATE_THICKNESS_M


static func max_plate_gap_m(arm_m: float) -> float:
	return arm_m * CENTRE_PLATE_TO_ARM_RATIO * MAX_PLATE_GAP_TO_PLATE_SIDE_RATIO


## How far fore or aft anything mounted on a frame may be slid before it is inside a propeller
## hub: the front motors' own forward extent, from the same MotorLayout table the physics reads.
## Nothing may be positioned past it, and a component long enough to reach it at zero offset has no
## travel at all — which is how a longer pack narrows its own range (AssemblyTweaks.limits).
static func reach_m(arm_m: float) -> float:
	return absf(MotorLayout.motor_position("M2", arm_m).z)


## Centre plate side length in metres, for a frame of this arm length.
static func centre_plate_side_m(arm_m: float) -> float:
	return arm_m * CENTRE_PLATE_TO_ARM_RATIO


## Every place on this frame where something attaches, derived from the frame's own specs and the
## standoff height currently fitted. A negative `plate_gap_m` means "whatever this frame implies".
##
## WHICH MOUNTS A FRAME HAS IS A PROPERTY OF THAT FRAME, not a constant this file knows. Every
## frame has a centre-plate bolt pattern and a top-plate strap location — a pack goes on top of
## even a 65 mm whoop. A BOTTOM-plate strap location has to be earned: the bottom plate is the one
## the stack bolts down onto and the arms clamp against, so a pack underneath has to strap through
## slots cut BESIDE the bolt pattern, and on a small frame the pattern has already eaten the plate.
## A 3" toothpick carries a 25.5 pattern through a 41 mm plate and has 8 mm of carbon either side
## of it; a 5" freestyle has 15 mm either side of a 30.5 pattern on a 60 mm plate. That is why the
## toothpick offers two mounts and the freestyle three, and it is arithmetic rather than a policy.
static func for_frame(frame: Dictionary, plate_gap_m: float) -> Array[MountPoint]:
	var arm_m: float = float(frame.get("specs", {}).get("arm_mm", 0.0)) / 1000.0
	var side := centre_plate_side_m(arm_m)
	var thickness: float = Build.FRAME_PLATE_THICKNESS_M
	var gap: float = plate_gap_m
	if gap < 0.0:
		gap = default_plate_gap_m()

	var span := Vector2(side, side)
	var reach := reach_m(arm_m)
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

	out.append_array(_component_bays(side, gap, thickness, span))

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


## Where the four components LTHL-11 unbundled out of the electronics lump actually sit.
##
## THIS IS THE PART OF THE SLICE THAT MOVES THE CENTRE OF MASS, so every term below comes from the
## frame's own geometry and none of it is authored. There are exactly two lengths in play — the
## centre plate's own side, and the standoff gap the builder set — and each bay is named for the
## face and the edge it sits on:
##
##   camera_bay      the bottom plate's upper face, at the plate's FRONT edge. A real FPV camera
##                   straddles that edge: the body is between the plates and the lens pokes out
##                   the front of them, which is why the seat is the edge itself rather than a
##                   position inset from it by a number nobody measured.
##   vtx_bay         the same face, at the REAR edge. The back of the plate stack is where a
##                   transmitter goes on every build big enough to have a back.
##   antenna_mount   the top plate's upper face, at the rear edge — an antenna stands proud of the
##                   airframe and points up and back, and this is the furthest-out mass of the
##                   four.
##   rx_bay          under the top plate, ON THE CENTRELINE. A receiver is taped wherever it fits;
##                   there is no edge it belongs to, so it is given none, and it contributes
##                   nothing fore or aft to the centre of mass whichever one is fitted.
##
## Every frame offers all four, unconditionally, and that is the difference between these and the
## bottom strap mount above: a strap slot has to be CUT into carbon that may not be there, whereas
## a bay is space, and there is always somewhere on an aircraft to put a camera. Whether a build
## fits anything into them is the build's business — omitting all four is a whoop, and costs the
## aircraft the whole of their share of the electronics budget (Build.mass_parts).
##
## TRAY rather than BOLT or STRAP throughout; see MountPoint.TRAY for why, and for the specific
## accident — a camera bay turning up in the battery-mount dropdown — that naming them STRAP would
## have caused.
static func _component_bays(side: float, gap: float, thickness: float, span: Vector2) -> Array[MountPoint]:
	var front := -side * 0.5
	var rear := side * 0.5
	var lower_face := -gap * 0.5 + thickness * 0.5
	var upper_face := gap * 0.5 + thickness * 0.5

	return [
		_bay("camera_bay", "the camera bay", Vector3(0.0, lower_face, front), 1, span),
		_bay("vtx_bay", "the transmitter bay", Vector3(0.0, lower_face, rear), 1, span),
		_bay("antenna_mount", "the antenna mount", Vector3(0.0, upper_face, rear), 1, span),
		_bay("rx_bay", "under the top plate", Vector3(0.0, gap * 0.5 - thickness * 0.5, 0.0), -1, span),
	] as Array[MountPoint]


## One bay. A bay has no fore/aft travel — `reach_m` is zero — because nothing in Lothal offers to
## slide a camera, and a non-zero reach would be an offer the UI does not make.
static func _bay(id: String, label: String, position: Vector3, normal: int,
		span: Vector2) -> MountPoint:
	var mount := MountPoint.new()
	mount.id = id
	mount.label = label
	mount.attachment = MountPoint.TRAY
	mount.position = position
	mount.normal = normal
	mount.span_m = span
	mount.reach_m = 0.0
	return mount


## One mount by id from a table, or null. Here rather than in each caller because both Lab and the
## mass model need it and neither should be walking the array itself.
static func by_id(mounts: Array[MountPoint], id: String) -> MountPoint:
	for mount in mounts:
		if mount.id == id:
			return mount
	return null


## Where a component's CENTRE sits when it is mounted on `mount`, slid `offset_m` forward, given its
## own size in body axes.
##
## THE ONE PLACE THIS SUM IS WRITTEN. AirframeModel had it for the pack it draws and the mass model
## needs the same answer for the pack it weighs; two copies of it is precisely the divergence where
## the picture and the physics would drift apart while both looked right. The component is seated on
## the face the mount names and grows AWAY from it — upward on the top plate, downward under the
## bottom one — so both terms come from the parts and this stays right for a 1S stick and a 6S brick
## alike. Forward is -Z (physics.md §1), which is why a positive offset subtracts.
static func seated_centre_m(mount: MountPoint, size_m: Vector3, offset_m: float = 0.0) -> Vector3:
	if mount == null:
		return Vector3.ZERO
	return mount.position + Vector3(0.0, mount.normal * size_m.y * 0.5, -offset_m)
