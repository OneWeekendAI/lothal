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


## Clears any previous stack and rebuilds it for `pattern`. Safe to call on every part change;
## nothing survives a call except this node.
##
## Seated on y = 0 and growing UPWARD, like MotorMesh: the mount point knows where its seat is, and
## a component that placed itself would need to know the plate stack's height — which is
## FrameModel's, and the standoff tweak's, and a second copy of arithmetic that already exists.
func rebuild(pattern: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var size := size_m(pattern)
	var spacing := Vector2(size.x, size.z) - Vector2(BOARD_EDGE_M, BOARD_EDGE_M) * 2.0

	_build_board("Board_ESC", size, esc_centre_height_m(), _esc_material())
	_build_board("Board_FC", size, fc_centre_height_m(), _fc_material())
	_build_standoffs(spacing, size.y)
	_build_connector(size)


## How high each board's CENTRE sits above the mount's seat. Static and named, because the mass
## model puts the ESC's and the FC's mass at these same two heights (Build.mass_parts) — the seat
## is MountLayout's and these are the boards' own offsets from it, so the stack that is drawn and
## the stack that is weighed cannot end up at different heights. The ESC is the lower board, which
## is how a 4-in-1 is actually stacked: it carries the pack leads in from below.
static func esc_centre_height_m() -> float:
	return BOARD_THICKNESS_M * 0.5


static func fc_centre_height_m() -> float:
	return BOARD_THICKNESS_M * 1.5 + BOARD_GAP_M


## One board, centred on the bolt pattern at the given height above the seat.
func _build_board(board_name: String, size: Vector3, height: float, material: StandardMaterial3D) -> void:
	var board := MeshInstance3D.new()
	board.name = board_name
	var box := BoxMesh.new()
	box.size = Vector3(size.x, BOARD_THICKNESS_M, size.z)
	board.mesh = box
	board.material_override = material
	board.position = Vector3(0.0, height, 0.0)
	add_child(board)


## The four posts at the bolt pattern's corners, running the whole height of the stack. They are
## what makes it read as a STACK rather than as two boards floating apart, and they are the reason
## the pattern is visible on screen at all: the spacing between them is the number the fit check
## warns about.
func _build_standoffs(spacing: Vector2, height: float) -> void:
	var material := _standoff_material()
	var index := 0
	for x in [-spacing.x * 0.5, spacing.x * 0.5]:
		for z in [-spacing.y * 0.5, spacing.y * 0.5]:
			var post := MeshInstance3D.new()
			post.name = "Standoff_%d" % index
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = STANDOFF_RADIUS_M
			cylinder.bottom_radius = STANDOFF_RADIUS_M
			cylinder.height = height
			cylinder.radial_segments = 8
			cylinder.rings = 1
			post.mesh = cylinder
			post.material_override = material
			post.position = Vector3(x, height * 0.5, z)
			add_child(post)
			index += 1


## The USB port and plug block on the FC's rear edge. Nose is -Z, so the connectors face aft — the
## cheapest possible cue for which way round the stack is fitted, exactly as the pack's leads are.
func _build_connector(size: Vector3) -> void:
	var block := MeshInstance3D.new()
	block.name = "Connector"
	var box := BoxMesh.new()
	box.size = Vector3(size.x * CONNECTOR_WIDTH_RATIO, CONNECTOR_HEIGHT_M, size.z * 0.18)
	block.mesh = box
	block.material_override = _standoff_material()
	block.position = Vector3(
		0.0,
		size.y + CONNECTOR_HEIGHT_M * 0.5 - BOARD_THICKNESS_M,
		size.z * 0.5 - size.z * 0.09)
	add_child(block)


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------

## A flight controller board: dark solder mask with a faint sheen, lifted above true reflectance
## for the reason FrameModel's header sets out — this viewport is read against a dark background
## and a near-black airframe, and a board at its real darkness is a hole between the plates.
func _fc_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.30, 0.24)
	mat.roughness = 0.45
	mat.metallic = 0.1
	return mat


## The 4-in-1 underneath, cooler and slightly darker so the two boards are separable at a glance.
func _esc_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.19, 0.30)
	mat.roughness = 0.5
	mat.metallic = 0.1
	return mat


## Aluminium standoffs and connector shells: bright and metallic, which is what lets the pattern
## be picked out from outside the frame.
func _standoff_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.70, 0.74)
	mat.roughness = 0.28
	mat.metallic = 0.75
	return mat
