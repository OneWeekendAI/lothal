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
## The pack, strapped to the top centre plate. Parented onto the plate for the same reason the
## motors hang off the arm-tip pads: the plate's height is FrameModel's, the standoff tweak moves
## it, and a second copy of that arithmetic here is a second thing to get wrong.
var battery_mesh: BatteryMesh
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
## `tweaks` is the builder's own assembly configuration (shims, soft mounts, standoff height), or
## null for the geometry the parts imply on their own. It is resolved to plain metres HERE, once,
## and handed to the mesh generators as numbers — a generator that could reach into settings for
## itself would be a second source for a dimension the assembler already knows.
func rebuild(build: Build, tweaks: AssemblyTweaks = null) -> void:
	var tweak_m := {"prop_spacer_m": 0.0, "soft_mount_m": 0.0, "plate_gap_m": -1.0}
	if tweaks != null:
		tweak_m = tweaks.resolved_m(build)

	frame_model.rebuild(build.frame, tweak_m["plate_gap_m"])
	motor_meshes.clear()
	propeller_meshes.clear()
	arm_m = build.arm_m

	# The pack, strapped to the top centre plate — where a 5" pack goes, and where the standoff
	# tweak can move it from underneath without anything here being told. Parented onto the plate
	# rather than positioned beside it, so a frame rebuild takes it with the plate exactly as it
	# takes the motors with the arm tips; there is no path by which a stale pack survives a frame
	# change, and no second copy of the plate stack's height.
	#
	# It is seated on its UNDERSIDE, not centred: the pack rests on the plate, so a taller pack has
	# to grow upward. Both terms come from the parts — the plate's own top face and the pack's own
	# reported height — so this line stays right for a 1S stick and a 6S brick alike.
	battery_mesh = BatteryMesh.new()
	battery_mesh.name = "Battery"
	battery_mesh.rebuild(build.battery)
	var plate_top: Node3D = frame_model.plate_top
	battery_mesh.position = Vector3(
		0,
		frame_model.plate_top_face_m() - plate_top.position.y + battery_mesh.size_m.y * 0.5,
		0)
	plate_top.add_child(battery_mesh)

	for motor_name in MotorLayout.MOTOR_NAMES:
		var pad: Node3D = frame_model.arm_tips[motor_name]

		# The prop is generated FIRST, even though it is mounted last, because the motor needs to
		# know how tall it is: the nut goes on top of the prop, and the shaft has to be long
		# enough to reach the nut. Nothing here measures the prop itself — it reports its own
		# stack height, the same way the motor reports its own seat height.
		var propeller := PropellerMesh.new()
		propeller.name = "Propeller_%s" % motor_name
		propeller.rebuild(build.propeller)

		var motor := MotorMesh.new()
		motor.name = "Motor_%s" % motor_name
		motor.rebuild(build.motor, propeller.stack_height_m,
			tweak_m["prop_spacer_m"], tweak_m["soft_mount_m"])
		# Sits on top of the pad, not centred in it — MotorMesh measures upward from y = 0.
		motor.position = Vector3(0, FrameModel.PAD_THICKNESS_M * 0.5, 0)
		pad.add_child(motor)
		motor_meshes[motor_name] = motor

		# The prop's UNDERSIDE rests on the seat face the motor reports, so the prop's origin sits
		# half a hub above it. Neither side of that sum is guessed here: the motor knows how high
		# its adapter is and the prop knows how deep its own hub is, which is what keeps the blade
		# roots clear of the bell for every pairing in the catalog rather than for the one that
		# was on screen when the number was chosen.
		propeller.position = Vector3(0, motor.prop_mount_height_m + propeller.underside_m, 0)
		# Direction from MotorLayout, not from anything this file decides: it is the same table the
		# yaw torque is computed from, so the rotor you can see and the rotor the physics is
		# integrating cannot disagree about which way they go. Diagonals together, adjacents opposed.
		propeller.spin = MotorLayout.SPIN[motor_name]
		motor.add_child(propeller)
		propeller_meshes[motor_name] = propeller


## Hands each propeller the RPM of its own motor, in MotorLayout.MOTOR_NAMES order — which is the
## order Observables publishes in, so Sim passes `observables.rpm` straight through. This is the only
## way a rate reaches a propeller in the field, and it starts at the one place that computes RPM.
func set_rates_rpm(rpm: PackedFloat32Array) -> void:
	for i in MotorLayout.MOTOR_NAMES.size():
		if i >= rpm.size():
			return
		var motor_name: String = MotorLayout.MOTOR_NAMES[i]
		(propeller_meshes[motor_name] as PropellerMesh).set_rate_rpm(rpm[i])


## One rate for all four, which is what Lab has to offer: there is no powertrain in the garage, so
## there is nothing to make the four differ. Kept as its own method rather than a four-element array
## at the call site so Lab is not pretending to know something per motor that it does not.
func set_all_rates_rpm(rpm: float) -> void:
	for motor_name in MotorLayout.MOTOR_NAMES:
		(propeller_meshes[motor_name] as PropellerMesh).set_rate_rpm(rpm)


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
