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

	for motor_name in MotorLayout.MOTOR_NAMES:
		var pad: Node3D = frame_model.arm_tips[motor_name]

		var motor := MotorMesh.new()
		motor.name = "Motor_%s" % motor_name
		motor.rebuild(build.motor)
		# Sits on top of the pad, not centred in it — MotorMesh measures upward from y = 0.
		motor.position = Vector3(0, FrameModel.PAD_THICKNESS_M * 0.5, 0)
		pad.add_child(motor)
		motor_meshes[motor_name] = motor
