class_name BenchStand
extends Node3D
## One arm of the airframe, on a stand, at eye level (labs-and-sim.md §2.1).
##
## The motor and propeller are the SAME generated meshes the assembled airframe uses, at the
## same real scale, mounted the same way — MotorMesh measuring upward from the pad's top face,
## the prop's underside resting on the seat the motor reports. That is not code reuse for its
## own sake: a bench whose geometry was drawn separately could show a pairing fitting that the
## airframe shows striking, and the whole claim of labs-and-sim.md §2.2 is that the render is
## the engineering check.
##
## The stand itself — plate, column, boom — is the only geometry in Lothal that is not derived
## from a part, because it is not a part. It is the bench, and its dimensions are chosen to hold
## the thing under test at eye level and to stay out of the way of the disc. They are expressed
## against the prop's own radius so that a 3" pairing and a 10" pairing are both framed sensibly,
## rather than the 10" prop cutting through a column sized for the 5".
##
## Node layout after rebuild():
##   Plate  — the base the column stands on
##   Column — the upright
##   Boom   — the horizontal arm reaching out from the column
##   Pad    — the arm-tip pad the motor bolts to, standing in for FrameModel's arm_tips
##     Motor      — MotorMesh, generated from the chosen motor
##       Propeller — PropellerMesh, generated from the chosen prop

## Which of the airframe's four positions is on the stand. M1 is rear-right, and it spins the
## direction MotorLayout says it does — the bench does not get an opinion about rotor direction
## any more than the airframe does.
##
## It lives here rather than on BenchScreen because this is the file that mounts the motor, and
## because BenchScreen already builds a BenchStand: a constant on the screen that the stand read
## back would be a reference cycle between the two class names, which GDScript resolves by
## failing to register either of them.
const BENCH_MOTOR := "M1"

## The boom has to be long enough that the disc clears the column. Expressed as a multiple of
## the prop's radius plus a fixed margin, so a bigger prop pushes itself further out.
const BOOM_CLEARANCE_RATIO := 1.25
const BOOM_MARGIN_M := 0.02

const COLUMN_RADIUS_M := 0.012
const BOOM_RADIUS_M := 0.008
const PLATE_RADIUS_M := 0.075
const PLATE_THICKNESS_M := 0.012

## Where the motor sits above the plate. A thrust stand is worked at standing height, and
## labs-and-sim.md asks for the pairing "at eye level" — the camera is placed level with this.
const MOUNT_HEIGHT_M := 0.26

## The pad the motor bolts onto, matching FrameModel's so MotorMesh's y = 0 convention holds.
const PAD_THICKNESS_M := 0.004
const PAD_RADIUS_M := 0.011

var motor_mesh: MotorMesh
var propeller_mesh: PropellerMesh
## Where the rotor actually sits, in this node's space — the subject, and what a camera must
## aim at. It is NOT above the origin: the motor hangs off the end of a boom whose length is
## chosen by the prop's radius, so it can be over 100 mm out along +X. Aiming at the origin
## instead points the camera at the column and leaves the thing under test off the edge of
## the frame, which is exactly what the first version of this did.
var mount_position_m := Vector3(0, MOUNT_HEIGHT_M, 0)
## Height of that mounting face above this node's origin, kept as its own name because the
## height and the position are asked different questions.
var mount_height_m := MOUNT_HEIGHT_M
## The radius the rotor actually sweeps, for whoever is framing the shot.
var prop_radius_m := 0.0


## Regenerates the stand and the pairing on it. Safe to call on every selection change; every
## child is cleared first, so nothing from the previous pairing can survive into this one.
func rebuild(build: Build) -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	var geometry := build.prop_geometry()
	prop_radius_m = geometry.diameter_m * 0.5
	var boom_length := prop_radius_m * BOOM_CLEARANCE_RATIO + BOOM_MARGIN_M + COLUMN_RADIUS_M

	_add_cylinder("Plate", PLATE_RADIUS_M, PLATE_THICKNESS_M,
		Vector3(0, PLATE_THICKNESS_M * 0.5, 0), _steel_material())
	_add_cylinder("Column", COLUMN_RADIUS_M, MOUNT_HEIGHT_M,
		Vector3(0, MOUNT_HEIGHT_M * 0.5, 0), _steel_material())

	# The boom lies along +X, so it is a cylinder laid on its side rather than a stretched box.
	var boom := _add_cylinder("Boom", BOOM_RADIUS_M, boom_length,
		Vector3(boom_length * 0.5, MOUNT_HEIGHT_M, 0), _steel_material())
	boom.rotation = Vector3(0, 0, deg_to_rad(90.0))

	var pad := _add_cylinder("Pad", PAD_RADIUS_M, PAD_THICKNESS_M,
		Vector3(boom_length, MOUNT_HEIGHT_M + PAD_THICKNESS_M * 0.5, 0), _anodised_material())
	pad.name = "Pad"

	# From here on this is exactly AirframeModel's mounting sequence, deliberately: the prop is
	# generated FIRST because the motor needs to know how tall it is (the nut goes on top of the
	# prop and the shaft has to reach it), then the motor is built around that stack height, then
	# the prop's underside is seated on the face the motor reports.
	propeller_mesh = PropellerMesh.new()
	propeller_mesh.name = "Propeller"
	propeller_mesh.rebuild(build.propeller)

	motor_mesh = MotorMesh.new()
	motor_mesh.name = "Motor"
	motor_mesh.rebuild(build.motor, propeller_mesh.stack_height_m)
	motor_mesh.position = Vector3(0, PAD_THICKNESS_M * 0.5, 0)
	pad.add_child(motor_mesh)

	propeller_mesh.position = Vector3(0, motor_mesh.prop_mount_height_m + propeller_mesh.underside_m, 0)
	# Direction from MotorLayout, exactly as the airframe takes it — the bench does not get to
	# have an opinion about which way a rotor goes.
	propeller_mesh.spin = MotorLayout.SPIN[BENCH_MOTOR]
	motor_mesh.add_child(propeller_mesh)

	mount_height_m = MOUNT_HEIGHT_M + PAD_THICKNESS_M + motor_mesh.prop_mount_height_m
	mount_position_m = Vector3(boom_length, mount_height_m, 0.0)


## Hands the rotor a rate, in RPM. The bench's only job here is to pass along what the
## powertrain published — see PropellerMesh's header on why it never picks its own.
func set_rate_rpm(rpm: float) -> void:
	if propeller_mesh != null:
		propeller_mesh.set_rate_rpm(rpm)


## Advances the rotor's rotation. Driven explicitly rather than left to PropellerMesh's own
## _process so a headless test can step the bench without a scene tree processing frames.
func advance(delta: float) -> void:
	if propeller_mesh != null:
		propeller_mesh.advance(delta)


func _add_cylinder(node_name: String, radius: float, height: float, centre: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = centre
	add_child(instance)
	return instance


func _steel_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.40, 0.44)
	material.metallic = 0.85
	material.roughness = 0.38
	return material


func _anodised_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.26, 0.32)
	material.metallic = 0.7
	material.roughness = 0.35
	return material
