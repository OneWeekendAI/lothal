class_name MotorMesh
extends Node3D
## Procedural motor geometry, generated from the chosen motor's real stator dimensions.
## Same reasoning as FrameModel — read its header — but the failure mode here is subtler and
## worth naming on its own: a motor is a small object at the end of an arm, so a single
## authored bell under a uniform scale factor would look entirely convincing. It would also
## be a lie, because the two numbers that define a motor's size are INDEPENDENT. A 2207 is
## 22 mm wide and 7 mm tall; a 2306 is 23 mm wide and 6 mm tall. No scale factor produces
## wider-and-shorter, and tests/test_motor_mesh.gd asserts exactly that pair.
##
## Node layout after rebuild():
##   Base   — the mounting boss that sits on the frame's arm-tip pad
##   Bell   — the rotating can, derived from stator diameter and height; the part you see
##   Shaft  — the output shaft standing above the bell, where a propeller bolts on
##
## Everything is measured from y = 0 at the pad's top face, upward, so this node can be
## parented straight onto FrameModel's arm_tips pads with no offset arithmetic at the call
## site.

## The bell is what you see; the stator is what the catalog publishes, and the two are not
## the same size. A 2207's stator is 22 mm across and its bell is about 28 mm — the winding
## sits inside a can with a wall, a magnet ring and an air gap. Same story vertically: 7 mm of
## stator sits inside roughly 18 mm of can, because the bell also has to cover the bearings
## and the magnets above and below the winding. Both ratios are class-typical from 14xx
## through 28xx, which is why they are ratios here rather than two more fields in the JSON —
## parts.md's spec-field table has no body-dimension field for a motor, and the precedent for
## deriving rather than authoring is FrameModel's arm cross-section.
const BELL_TO_STATOR_DIAMETER_RATIO := 1.27
const BELL_HEIGHT_TO_STATOR_HEIGHT_RATIO := 2.6

## The mounting boss under the bell: the stator's own footprint, and thin. The can overhangs
## what it bolts to, which is why this is not the bell radius.
const BASE_HEIGHT_TO_STATOR_DIAMETER_RATIO := 0.14

## Output shaft. A 2207 runs a 2.5 mm shaft on a 22 mm stator, and shaft diameter tracks
## stator size closely across the range because it is sized by the torque the motor makes.
const SHAFT_TO_STATOR_DIAMETER_RATIO := 1.0 / 9.0
## How far the shaft stands proud of the bell — enough for a prop and its nut.
const SHAFT_PROTRUSION_TO_BELL_HEIGHT_RATIO := 0.38
## Where up the protruding shaft a propeller's hub seats. Low, so the prop sits just clear of
## the bell the way a real one does rather than floating at the top of the thread.
const PROP_SEAT_UP_THE_PROTRUSION := 0.3

## A motor whose specs a contributor has not filled in yet renders as a mid-catalog 2207
## rather than as a zero-size invisible node. Same posture as FrameModel's fallback pad size:
## an incomplete part should look wrong, not disappear.
const FALLBACK_STATOR_DIAMETER_MM := 22.0
const FALLBACK_STATOR_HEIGHT_MM := 7.0

## Height above the pad at which a propeller's hub sits. AirframeModel reads this rather than
## guessing, so the prop lands on the shaft for every motor in the catalog.
var prop_mount_height_m := 0.0
## Total extent above the pad: base, plus bell, plus the shaft standing above it.
var total_height_m := 0.0
var bell_radius_m := 0.0


## Clears any previously generated geometry and rebuilds it from `motor`. Safe to call
## repeatedly with different motors; nothing survives a call except this node itself.
func rebuild(motor: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var specs: Dictionary = motor.get("specs", {})
	var stator_diameter_m: float = float(specs.get("stator_diameter_mm", FALLBACK_STATOR_DIAMETER_MM)) / 1000.0
	var stator_height_m: float = float(specs.get("stator_height_mm", FALLBACK_STATOR_HEIGHT_MM)) / 1000.0
	if stator_diameter_m <= 0.0:
		stator_diameter_m = FALLBACK_STATOR_DIAMETER_MM / 1000.0
	if stator_height_m <= 0.0:
		stator_height_m = FALLBACK_STATOR_HEIGHT_MM / 1000.0

	bell_radius_m = stator_diameter_m * BELL_TO_STATOR_DIAMETER_RATIO * 0.5
	var bell_height := stator_height_m * BELL_HEIGHT_TO_STATOR_HEIGHT_RATIO
	var base_height := stator_diameter_m * BASE_HEIGHT_TO_STATOR_DIAMETER_RATIO
	var shaft_radius := stator_diameter_m * SHAFT_TO_STATOR_DIAMETER_RATIO * 0.5
	var protrusion := bell_height * SHAFT_PROTRUSION_TO_BELL_HEIGHT_RATIO

	var bell_top := base_height + bell_height
	total_height_m = bell_top + protrusion
	prop_mount_height_m = bell_top + protrusion * PROP_SEAT_UP_THE_PROTRUSION

	_add_cylinder("Base", stator_diameter_m * 0.5, base_height, base_height * 0.5,
		_anodised_material(), 20)
	_add_cylinder("Bell", bell_radius_m, bell_height, base_height + bell_height * 0.5,
		_bell_material(), 28)
	# The shaft spans from inside the base to the top of the protrusion, so it reads as one
	# shaft running through the motor rather than a peg sitting on the lid.
	var shaft_length := total_height_m - base_height * 0.5
	_add_cylinder("Shaft", shaft_radius, shaft_length, base_height * 0.5 + shaft_length * 0.5,
		_steel_material(), 10)


func _add_cylinder(node_name: String, radius: float, height: float, centre_y: float,
		material: StandardMaterial3D, segments: int) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = segments
	cylinder.rings = 1
	node.mesh = cylinder
	node.material_override = material
	node.position = Vector3(0, centre_y, 0)
	add_child(node)


## Anodised aluminium, which is what a motor bell is. Read bright enough to separate from a
## near-black carbon arm — the same perceptual transform FrameModel's header defends, since
## the whole reason these are on screen is to be compared by eye.
func _bell_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.60, 0.66)
	mat.roughness = 0.28
	mat.metallic = 0.75
	return mat


func _anodised_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.25, 0.29)
	mat.roughness = 0.45
	mat.metallic = 0.6
	return mat


func _steel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.79, 0.82)
	mat.roughness = 0.18
	mat.metallic = 0.9
	return mat
