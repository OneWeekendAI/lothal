class_name StackMesh
extends Node3D
## The FC/ESC stack, as a real object on the aircraft: two boards on standoffs, sandwiched into the
## frame's centre-plate bolt pattern.
##
## It exists because the flight controller was 55 g of mass at the origin and nothing on screen.
## Lab's stated job is that the fit check and the picture are the same geometry (labs-and-sim.md
## §2.2), and a component with no picture cannot be fit-checked at all — you could not see that the
## board you had chosen was drilled for a pattern your frame does not carry.
##
## THE MASS DID NOT GO UP. What is drawn here was already in Build.ELECTRONICS_MASS_G, and giving it
## physical form takes it OUT of that lump rather than adding beside it — see Build.mass_parts().
## The reference build's all-up weight, thrust-to-weight and hover throttle are unchanged.
##
## Its size comes from its PATTERN, not from a typed board dimension: a 30.5x30.5 board is 36.5 mm
## square and a 20x20 board is 26 mm square, because the difference is the strip of PCB outside the
## bolt circle and that strip is the same on both.
##
## Node layout after rebuild():
##   Board_ESC, Board_FC — the two boards, ESC underneath
##   Standoff_0..3       — the four M3 posts at the bolt pattern's corners
##   Connector           — the USB port and plug block on the FC's rear edge

## PCB outside the bolt circle, per side. 2.75-3 mm is what every board in this class carries, which
## is why a 30.5 board is 36 and a 20x20 is 26.
const BOARD_EDGE_M := 0.003
## A 1.6 mm PCB, which is the standard every FC and 4-in-1 in FPV is fabricated on.
const BOARD_THICKNESS_M := 0.0016
## The gap the standoffs hold between the two boards.
const BOARD_GAP_M := 0.007
## The standoff posts: M3 hardware, so a 2.2 mm radius over the thread.
const STANDOFF_RADIUS_M := 0.0022
## The USB/plug block on the FC's rear edge: a fraction of the board wide, and its own height.
const CONNECTOR_WIDTH_RATIO := 0.28
const CONNECTOR_HEIGHT_M := 0.0035

## The board footprint and the whole stack's height, in BODY axes: width across X, height up Y,
## length along Z. The one answer to how big the stack is — Build reads it for the inertia box and
## MountPoint reads it for the clearance check, exactly as Build.battery_size_of is the one answer
## for the pack.
static func size_m(pattern: String) -> Vector3:
	var spacing := MountPoint.parse_pattern_m(pattern)
	if spacing == Vector2.ZERO:
		spacing = MountPoint.parse_pattern_m(Build.STACK_MOUNT_PATTERN)
	var board := spacing + Vector2(BOARD_EDGE_M, BOARD_EDGE_M) * 2.0
	return Vector3(board.x, BOARD_THICKNESS_M * 2.0 + BOARD_GAP_M, board.y)
