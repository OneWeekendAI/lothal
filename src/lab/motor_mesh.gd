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
##   SoftMount — the anti-vibration pad under the motor, only when one has been shimmed in
##   Base      — the mounting boss that sits on the frame's arm-tip pad
##   Bell      — the rotating can, derived from stator diameter and height; the part you see
##   Adapter   — the prop adapter on top of the bell; the prop's underside seats on its top face
##   Spacer    — shim washers on the shaft, only when the builder has added any
##   Shaft     — the output shaft, running from inside the base to above the nut
##   Nut       — the prop nut, only when a prop's height has been declared to rebuild()
##
## Everything is measured from y = 0 at the pad's top face, upward, so this node can be
## parented straight onto FrameModel's arm_tips pads with no offset arithmetic at the call
## site.
##
## THE MOUNT IS A STACK, AND ITS HEIGHTS ARE ALL DERIVED. Before this slice the prop's seat
## was `bell_top + protrusion * 0.3` — a fraction of a fraction, with no hardware in the gap
## it implied — and the blade ROOTS, which dip several millimetres below the hub centreline
## because a root is steeply feathered, sat down inside the bell. Motor and prop read as one
## merged object, which is the opposite of what Lab is for: if the render is the engineering
## check (labs-and-sim.md §2.2), a mount that cannot physically fit must not look fitted.
##
## So the seat is now the sum of the real parts underneath it — soft-mount pad, mounting boss,
## bell (from stator_height_mm), prop adapter, shim washers — and the daylight between the bell
## and the blades is the adapter's own thickness. Nothing in that sum is a magic constant, which
## is what makes it right for a 0802 and a 2807 at the same time. tests/test_mounting.gd measures
## the gap from the generated blade vertices for every motor in the catalog.

## The bell is what you see; the stator is what the catalog publishes, and the two are not
## the same size. A 2207's stator is 22 mm across and its bell is about 28 mm — the winding
## sits inside a can with a wall, a magnet ring and an air gap. Same story vertically: 7 mm of
## stator sits inside roughly 18 mm of can, because the bell also has to cover the bearings
## and the magnets above and below the winding.
##
## PRE-P7 THESE WERE LOCAL CONSTANTS: 1.27 and 2.6, "class-typical from 14xx through 28xx",
## kept off the JSON because "parts.md's spec-field table has no body-dimension field for a
## motor". P7 (propulsion.md §3.4) reads them from `specs` because MotorSpinUp's J_rotor
## depends on the bell radius — the same rule airframe.md §6.1 applied to `material` and §9b
## applied to `construction`: the moment a drawing constant is read by physics, it stops
## being visual and becomes a spec. `_FALLBACK_*` here is only for motors authored through
## the custom-motor form (which does not ask for these fields) — every motor in motors.json
## carries its own values.
const _FALLBACK_BELL_TO_STATOR_DIAMETER_RATIO := 1.27
const _FALLBACK_BELL_HEIGHT_TO_STATOR_HEIGHT_RATIO := 2.6


## Reads the diameter ratio from specs, falling back for a custom motor authored without one.
## Static so `MotorSpinUp` and other callers get the same value MotorMesh draws — one number
## for the geometry and the physics.
static func bell_diameter_ratio(motor: Dictionary) -> float:
	var specs: Dictionary = motor.get("specs", {})
	return float(specs.get("bell_diameter_ratio", _FALLBACK_BELL_TO_STATOR_DIAMETER_RATIO))


static func bell_height_ratio(motor: Dictionary) -> float:
	var specs: Dictionary = motor.get("specs", {})
	return float(specs.get("bell_height_ratio", _FALLBACK_BELL_HEIGHT_TO_STATOR_HEIGHT_RATIO))

## The mounting boss under the bell: the stator's own footprint, and thin. The can overhangs
## what it bolts to, which is why this is not the bell radius.
const BASE_HEIGHT_TO_STATOR_DIAMETER_RATIO := 0.14

## Output shaft. A 2207 runs a 2.5 mm shaft on a 22 mm stator, and shaft diameter tracks
## stator size closely across the range because it is sized by the torque the motor makes.
const SHAFT_TO_STATOR_DIAMETER_RATIO := 1.0 / 9.0

## The prop adapter: the collar that sits on the bell's top face and that the propeller's
## underside rests on. Its THICKNESS is the axial clearance between the bell and the blades, so
## it is the one dimension in this file that the acceptance criterion is written about. A real
## adapter is roughly as thick as the shaft is wide — 2.5 mm on a 2207's 2.4 mm shaft — which is
## also why expressing it against the shaft rather than the bell is right: it is a part that
## fits the shaft, and it scales with the shaft the way the real hardware does.
const ADAPTER_THICKNESS_TO_SHAFT_DIAMETER_RATIO := 1.1
## And wide enough to be a collar rather than a thickening of the shaft.
const ADAPTER_RADIUS_TO_SHAFT_RADIUS_RATIO := 2.4

## The prop nut. Across-flats width against shaft diameter is close to 2 on the M5-on-2.5 mm
## hardware these motors actually ship with. Drawn with enough radial segments to read as a
## round knurled cap rather than a hexagon: a 6-sided nut on a shaft that is not itself drawn
## spinning would be the only visibly STILL thing in a rotating assembly, and at speed a 6-fold
## pattern is exactly what aliases (see PropellerMesh's blur disc).
const NUT_WIDTH_TO_SHAFT_DIAMETER_RATIO := 1.9
const NUT_HEIGHT_TO_SHAFT_DIAMETER_RATIO := 0.9

## Spare thread above the adapter, as a fraction of bell height. This is what a real motor gives
## you to shim into, and it is therefore the DERIVED LIMIT on the prop-spacer tweak
## (max_prop_spacer_m below) rather than a separate authored number: shim past the thread and
## there is nothing left for the nut to bite on. The shaft is drawn long enough that the nut sits
## flush with its top when the spacer is at that limit.
const SHAFT_SHIM_RESERVE_TO_BELL_HEIGHT_RATIO := 0.25

## A motor whose specs a contributor has not filled in yet renders as a mid-catalog 2207
## rather than as a zero-size invisible node. Same posture as FrameModel's fallback pad size:
## an incomplete part should look wrong, not disappear.
const FALLBACK_STATOR_DIAMETER_MM := 22.0
const FALLBACK_STATOR_HEIGHT_MM := 7.0

## Height above the pad of the face a propeller's UNDERSIDE seats on — the top of the prop
## adapter. AirframeModel reads this rather than guessing, so the prop lands on the shaft for
## every motor in the catalog. Note the change of meaning from the previous slice, where it was
## where the hub's CENTRE went: a hub centre clearing the bell says nothing about the blade
## roots hanging below it, which is precisely how the merged-prop bug survived.
var prop_mount_height_m := 0.0
## Total extent above the pad, up to the top of the shaft — which now includes whatever is
## bolted on, so Lab's framing knows how tall the assembled mount is.
var total_height_m := 0.0
var bell_radius_m := 0.0


## Every derived dimension of a motor, in metres, from its published stator size. Static and
## separate from rebuild() so the limits on the assembly tweaks can be derived from the same
## arithmetic the geometry uses — two copies of it would be two answers to "how much thread is
## left to shim into".
static func dimensions(motor: Dictionary) -> Dictionary:
	var specs: Dictionary = motor.get("specs", {})
	var stator_diameter_m: float = float(specs.get("stator_diameter_mm", FALLBACK_STATOR_DIAMETER_MM)) / 1000.0
	var stator_height_m: float = float(specs.get("stator_height_mm", FALLBACK_STATOR_HEIGHT_MM)) / 1000.0
	if stator_diameter_m <= 0.0:
		stator_diameter_m = FALLBACK_STATOR_DIAMETER_MM / 1000.0
	if stator_height_m <= 0.0:
		stator_height_m = FALLBACK_STATOR_HEIGHT_MM / 1000.0

	var bell_height := stator_height_m * bell_height_ratio(motor)
	var shaft_diameter := stator_diameter_m * SHAFT_TO_STATOR_DIAMETER_RATIO
	return {
		"stator_radius": stator_diameter_m * 0.5,
		"bell_radius": stator_diameter_m * bell_diameter_ratio(motor) * 0.5,
		"bell_height": bell_height,
		"base_height": stator_diameter_m * BASE_HEIGHT_TO_STATOR_DIAMETER_RATIO,
		"shaft_radius": shaft_diameter * 0.5,
		"adapter_thickness": shaft_diameter * ADAPTER_THICKNESS_TO_SHAFT_DIAMETER_RATIO,
		"adapter_radius": shaft_diameter * 0.5 * ADAPTER_RADIUS_TO_SHAFT_RADIUS_RATIO,
		"nut_radius": shaft_diameter * NUT_WIDTH_TO_SHAFT_DIAMETER_RATIO * 0.5,
		"nut_height": shaft_diameter * NUT_HEIGHT_TO_SHAFT_DIAMETER_RATIO,
		"shim_reserve": bell_height * SHAFT_SHIM_RESERVE_TO_BELL_HEIGHT_RATIO,
	}


## The most this motor can be shimmed under its prop: the spare thread above the adapter. The
## limit on the prop-spacer tweak, derived from the same geometry that draws the shaft.
static func max_prop_spacer_m(motor: Dictionary) -> float:
	return dimensions(motor)["shim_reserve"]


## The thickest soft-mount pad this motor can sit on: the height of its own mounting boss, which
## is the length of screw thread the mounting bolts have to give up to a pad. Thicker than that
## and the screws are no longer in the motor.
static func max_soft_mount_m(motor: Dictionary) -> float:
	return dimensions(motor)["base_height"]


## Clears any previously generated geometry and rebuilds it from `motor`. Safe to call
## repeatedly with different motors; nothing survives a call except this node itself.
##
## `prop_stack_m` is the total vertical extent of the propeller that will be bolted on (its hub
## height — PropellerMesh.stack_height_m). It is asked for rather than assumed because the nut
## goes ON TOP of the prop and the shaft has to be long enough to reach it: a nut floating above
## the end of the thread is the same class of invisible error as a prop inside the bell. Zero
## means no prop, and then no nut is drawn.
##
## `spacer_m` and `soft_mount_m` are the builder's assembly tweaks, already clamped to the limits
## above (see AssemblyTweaks). They are hardware, not offsets: a spacer draws washers on the
## shaft and a soft mount draws a pad under the motor.
func rebuild(motor: Dictionary, prop_stack_m: float = 0.0, spacer_m: float = 0.0,
		soft_mount_m: float = 0.0) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var d := dimensions(motor)
	bell_radius_m = d["bell_radius"]
	var stator_radius: float = d["stator_radius"]
	var bell_height: float = d["bell_height"]
	var base_height: float = d["base_height"]
	var shaft_radius: float = d["shaft_radius"]
	var adapter_thickness: float = d["adapter_thickness"]
	var nut_height: float = d["nut_height"]

	var pad := maxf(soft_mount_m, 0.0)
	var spacer := clampf(spacer_m, 0.0, d["shim_reserve"])

	var base_bottom := pad
	var bell_bottom := base_bottom + base_height
	var bell_top := bell_bottom + bell_height
	# The seat: bell, then adapter, then any shim washers. This sum IS the mounting height.
	prop_mount_height_m = bell_top + adapter_thickness + spacer
	# The shaft carries the full stack and still tops out flush with the nut when the spacer is
	# wound all the way to its limit — which is what makes that limit visible rather than a rule
	# written down somewhere else.
	var shaft_top: float = bell_top + adapter_thickness + d["shim_reserve"] \
		+ maxf(prop_stack_m, 0.0) + nut_height
	total_height_m = shaft_top

	if pad > 0.0:
		# Rubber, and slightly wider than the boss it carries, the way a real soft-mount washer is.
		_add_cylinder("SoftMount", stator_radius * 1.05, pad, pad * 0.5,
			_rubber_material(), 20)
	_add_cylinder("Base", stator_radius, base_height, base_bottom + base_height * 0.5,
		_anodised_material(), 20)
	_add_cylinder("Bell", bell_radius_m, bell_height, bell_bottom + bell_height * 0.5,
		_bell_material(), 28)
	_add_cylinder("Adapter", d["adapter_radius"], adapter_thickness,
		bell_top + adapter_thickness * 0.5, _anodised_material(), 20)
	if spacer > 0.0:
		_add_cylinder("Spacer", d["adapter_radius"] * 0.85, spacer,
			bell_top + adapter_thickness + spacer * 0.5, _steel_material(), 16)
	# The shaft spans from inside the base to the top, so it reads as one shaft running through
	# the motor rather than a peg sitting on the lid.
	var shaft_length := shaft_top - base_bottom - base_height * 0.5
	_add_cylinder("Shaft", shaft_radius, shaft_length,
		base_bottom + base_height * 0.5 + shaft_length * 0.5, _steel_material(), 10)
	if prop_stack_m > 0.0:
		_add_cylinder("Nut", d["nut_radius"], nut_height,
			prop_mount_height_m + prop_stack_m + nut_height * 0.5, _steel_material(), 16)


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


## The anti-vibration pad: matte, dark, and obviously not metal, so a soft-mounted motor reads
## as sitting on something rather than as floating off its pad.
func _rubber_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.13, 0.15)
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat


func _steel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.79, 0.82)
	mat.roughness = 0.18
	mat.metallic = 0.9
	return mat
