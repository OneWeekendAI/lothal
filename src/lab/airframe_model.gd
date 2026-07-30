class_name AirframeModel
extends Node3D
## The whole aircraft as generated geometry: the frame, the four motors on its arm tips, and
## (from the next slice on) the propellers on their shafts. Everything derived from the same
## Build the physics reads.
##
## This node exists so there is exactly ONE assembled airframe in the project. Lab shows it in
## the garage and Sim flies it in the field, from the same class and the same Build — which is
## the project's core thesis made literal (labs-and-sim.md §3: "Everything you saw in Lab is
## what you fly"). Before it existed, main.tscn hardcoded the drone as a box plus four
## cylinders with the 5" arm's motor positions baked in as 0.0778, so choosing the 7" frame
## left the physics on a 150 mm arm while the visual stayed a 5" box. Two implementations of
## one aircraft is exactly the divergence this replaces.
##
## Motors are parented onto FrameModel's arm_tips pads rather than positioned independently.
## That is deliberate: the arm-tip positions are MotorLayout's, the physics reads them from
## MotorLayout too, and a second copy of that arithmetic here is a second thing to get wrong.
## It also means a frame rebuild — which frees the pads — takes its motors with it, so there
## is no path by which a stale motor survives a frame change.

var frame_model: FrameModel
## motor name -> MotorMesh, in MotorLayout.MOTOR_NAMES order.
var motor_meshes: Dictionary = {}
## motor name -> PropellerMesh. Each one is parented onto its motor, because that is where a
## propeller physically bolts — so a taller motor lifts its prop without anything recomputing
## a clearance, and a frame change moves motors and props together in one step.
var propeller_meshes: Dictionary = {}
## Arm length of the build currently drawn, kept so clearance can be reported against the
## geometry actually on screen rather than against whatever Build was asked about last.
var arm_m := 0.0

func _init() -> void:
	frame_model = FrameModel.new()
	frame_model.name = "Frame"
	add_child(frame_model)


## Regenerates the whole airframe from `build`. Safe to call on every part change; the frame
## rebuild clears the pads and everything hanging off them, so nothing from the previous
## build can survive into this one.
func rebuild(build: Build) -> void:
	frame_model.rebuild(build.frame)
	motor_meshes.clear()
	propeller_meshes.clear()
	arm_m = build.arm_m

	for motor_name in MotorLayout.MOTOR_NAMES:
		var pad: Node3D = frame_model.arm_tips[motor_name]

		var motor := MotorMesh.new()
		motor.name = "Motor_%s" % motor_name
		motor.rebuild(build.motor)
		# Sits on top of the pad, not centred in it — MotorMesh measures upward from y = 0.
		motor.position = Vector3(0, FrameModel.PAD_THICKNESS_M * 0.5, 0)
		pad.add_child(motor)
		motor_meshes[motor_name] = motor

		var propeller := PropellerMesh.new()
		propeller.name = "Propeller_%s" % motor_name
		propeller.rebuild(build.propeller)
		# On the shaft, at the height the motor itself reports. Nothing here knows how tall a
		# 2807 is; asking the motor is what keeps the prop seated for every motor in the catalog.
		propeller.position = Vector3(0, motor.prop_mount_height_m, 0)
		motor.add_child(propeller)
		propeller_meshes[motor_name] = propeller


## Clearance between two adjacent propeller discs, measured from the geometry on screen: the
## distance between their hubs, less the two radii they actually sweep. Negative means the
## discs intersect — the props would strike each other and the arms between them.
##
## This is the number behind "incompatible is something you can see" (labs-and-sim.md §2.2).
## Build.warnings() says the same thing in words, from max_prop_inches, and the two are
## deliberately independent: the warning is the frame manufacturer's stated limit, and this is
## what the generated parts do when placed. A build where those disagree is worth catching.
func adjacent_prop_gap_m() -> float:
	if propeller_meshes.size() < 2:
		return 0.0
	# M1 (rear-right) and M2 (front-right) are adjacent on the same side.
	var first: PropellerMesh = propeller_meshes["M1"]
	var second: PropellerMesh = propeller_meshes["M2"]
	var separation: float = MotorLayout.motor_position("M1", arm_m) \
		.distance_to(MotorLayout.motor_position("M2", arm_m))
	return separation - (first.radius_m + second.radius_m)
