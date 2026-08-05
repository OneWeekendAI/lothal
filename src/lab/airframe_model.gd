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
## The pack. Parented onto the frame for the same reason the motors hang off the arm-tip pads: the
## mount's height is FrameModel's, the standoff tweak moves it, and a frame rebuild frees it rather
## than leaving a stale pack behind.
var battery_mesh: BatteryMesh
## The mount point the pack is currently attached to, or null before the first rebuild. Held rather
## than re-derived, so every fit measurement below is taken against the mount the pack is ACTUALLY
## on — the failure that would otherwise be invisible is a fit check still describing the pack's
## previous home while the picture shows it somewhere else.
var battery_mount: MountPoint
## How far forward the pack is slid on that mount, in metres. Positive is forward.
var battery_offset_m := 0.0
## The FC/ESC stack, sandwiched into the frame's centre-plate bolt pattern. Parented onto the frame
## for the same reason the motors hang off the arm-tip pads: the mount's height is FrameModel's, the
## standoff tweak moves it, and a frame rebuild frees it rather than leaving a stale board behind.
var stack_mesh: StackMesh
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
	# The parts-implied defaults are Build's, not a second list here: the mass model falls back to
	# the same ones, and two lists of defaults is two things to get out of step.
	var tweak_m := Build.DEFAULT_ASSEMBLY.duplicate()
	if tweaks != null:
		tweak_m = tweaks.resolved_m(build)

	frame_model.rebuild(build.frame, tweak_m["plate_gap_m"])
	motor_meshes.clear()
	propeller_meshes.clear()
	arm_m = build.arm_m

	# The pack, on whichever of the frame's strap mounts the builder chose, slid to wherever they
	# put it. There is deliberately no branch here on WHICH mount that is: a mount point knows its
	# own seat, which way a component grows from it, and how far along it there is room — so top and
	# bottom are two entries in a table rather than two code paths, and a payload mount the day it
	# exists is a third entry and no new code at all.
	#
	# The pack is seated on the face the mount names and grows AWAY from it: upward on the top
	# plate, downward under the bottom one. Both terms come from the parts — the mount's own
	# position and the pack's own reported height — so this stays right for a 1S stick and a 6S
	# brick alike. Forward is -Z (physics.md §1), which is why a positive offset subtracts.
	battery_mesh = BatteryMesh.new()
	battery_mesh.name = "Battery"
	battery_mesh.rebuild(build.battery)
	battery_offset_m = tweak_m["battery_offset_m"]
	battery_mount = mount_point(String(tweak_m["battery_mount"]))
	if battery_mount == null:
		battery_mount = mount_point("strap_top")
	if battery_mount != null:
		# The seating sum is MountLayout's, and is the SAME call Build.mass_parts() makes to decide
		# where the pack's mass is. That is what makes labs-and-sim.md §2.2 — "the fit check and the
		# picture are the same geometry" — true of mass as well as of clearance.
		battery_mesh.position = MountLayout.seated_centre_m(
			battery_mount, battery_mesh.size_m, battery_offset_m)
	frame_model.add_child(battery_mesh)

	# The stack, in the frame's own standoff stack. Nothing here decides where that is: the mount
	# point does, from the frame's specs and the standoff height currently fitted, and this line
	# only seats the board on it. That is what makes the same call right for a 30.5 stack on a 5"
	# freestyle and for the same board hanging off a 65 mm whoop's 18 mm plate — which is warned
	# about (mount_warnings) and still mounted, because Lothal never blocks.
	stack_mesh = StackMesh.new()
	stack_mesh.name = "Stack"
	stack_mesh.rebuild(Build.STACK_MOUNT_PATTERN)
	var stack_mount := mount_point("stack")
	if stack_mount != null:
		stack_mesh.position = stack_mount.position
	frame_model.add_child(stack_mesh)

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


## One of the frame's mount points by id, or null. Named accessor rather than callers walking
## frame_model.mount_points, so the airframe stays the one place that knows what is mounted where.
func mount_point(id: String) -> MountPoint:
	for point in frame_model.mount_points:
		if point.id == id:
			return point
	return null


## What is wrong with how the mounted components are attached, in words: the mount system's own
## verdict on each of them, in one list. Separate from battery_fit_warnings() below, which is what
## the assembled GEOMETRY does, in the same way Build.warnings() is separate from both.
func mount_warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var stack_mount := mount_point("stack")
	if stack_mount != null:
		out.append_array(stack_mount.fit_warnings(
			"The FC/ESC stack", Build.stack_mounting(),
			StackMesh.size_m(Build.STACK_MOUNT_PATTERN)))
	if battery_mount != null and battery_mesh != null:
		out.append_array(battery_mount.fit_warnings(
			"The pack", {"attachment": MountPoint.STRAP, "pattern": ""}, battery_mesh.size_m))
	return out


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


# ---------------------------------------------------------------------------
# Does the pack fit?
# ---------------------------------------------------------------------------

## How far the pack hangs over the edge of the centre plate it is strapped to, fore/aft and
## laterally, in metres. Positive hangs over; negative clears.
##
## Measured off the DRAWN parts — the plate's own mesh and the pack's own reported size — in the
## manner of adjacent_prop_gap_m() above, and for the same reason: labs-and-sim.md §2.2 says "the
## fit check and the picture are the same geometry", and a fit check recomputed from arm_mm times a
## ratio would be a second opinion that could agree with the render for a long time and then stop.
##
## Both axes are reported, but only one of them is a problem — see battery_fit_warnings().
##
## Measured against the plate the pack is actually on, and INCLUDING the fore/aft offset: sliding a
## pack forward puts more of it past the front edge, and reporting the centred figure while the
## picture shows it hanging off the nose would be exactly the divergence §2.2 forbids. The fore/aft
## figure is therefore the WORST end, which is the end a strap loses its grip at.
func battery_overhang_m() -> Dictionary:
	if battery_mesh == null or battery_mount == null:
		return {"fore_aft": 0.0, "lateral": 0.0}
	var plate := battery_mount.span_m
	return {
		"fore_aft": battery_mesh.size_m.z * 0.5 + absf(battery_offset_m) - plate.y * 0.5,
		"lateral": (battery_mesh.size_m.x - plate.x) * 0.5,
	}


## The narrowest gap in PLAN VIEW between the pack's footprint and any propeller's swept disc, in
## metres. Negative means the pack is inside the disc: the props would strike it.
##
## Plan view, deliberately, and it is the honest reading rather than a simplification. The pack sits
## on the top plate and the props turn above the motors, so they are at different heights and a
## three-dimensional test would report a comfortable gap for a build that is obviously absurd on
## screen. But a propeller is a rotor, not a fixed object: it is what gets pitched into and struck
## by anything the airframe hits, its disc is where nothing may be, and a pack occupying that
## airspace is a build with no room for the props whatever the current standoff height happens to
## put between them.
##
## Each prop's radius is the one it drew, and the hub positions are MotorLayout's — the same table
## the physics reads, so the discs measured here are the discs on screen.
func battery_prop_clearance_m() -> float:
	if battery_mesh == null or propeller_meshes.is_empty():
		return 0.0

	var half_x: float = battery_mesh.size_m.x * 0.5
	var half_z: float = battery_mesh.size_m.z * 0.5
	# Where the pack's centre actually is along the aircraft, which is what makes this measurement
	# follow the pack rather than describe where it used to live. Forward is -Z.
	var centre_z := -battery_offset_m
	var narrowest := INF

	for motor_name in MotorLayout.MOTOR_NAMES:
		var propeller: PropellerMesh = propeller_meshes[motor_name]
		var hub := MotorLayout.motor_position(motor_name, arm_m)
		# Distance from the hub to the nearest point of the pack's rectangle. Zero on each axis the
		# hub is already inside, which is what makes this correct for a pack the props sit over as
		# well as for one they sit clear of.
		var gap := Vector2(
			maxf(absf(hub.x) - half_x, 0.0),
			maxf(absf(hub.z - centre_z) - half_z, 0.0)).length()
		narrowest = minf(narrowest, gap - propeller.radius_m)

	return narrowest


## What is wrong with how this pack fits, in words, measured off the geometry above. Empty for a
## build that fits — including the reference build, which overhangs its own plate by 7 mm fore and
## aft and is not being warned about, because that is what every real 5" build does and a warning
## nobody can act on is noise.
##
## Two conditions, and they are the two that mean something:
##
##   - the pack is WIDER than the plate. A strap runs across the pack and through the plate, so a
##     pack wider than what it is strapped to has nothing holding its edges down. Overhanging fore
##     and aft is normal; overhanging sideways is a mounting problem.
##   - the pack reaches into the propeller discs. Warn, never block: a 6S Li-ion on a 3" toothpick
##     is exactly the curiosity worth having, and seeing it dwarf the airframe is the answer.
##
## Separate from Build.warnings(), which is the same split the prop clearance already uses: that
## list is what the parts DECLARE about each other, and this is what the assembled geometry does.
func battery_fit_warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if battery_mesh == null:
		return out

	var overhang := battery_overhang_m()
	if overhang["lateral"] > 0.0:
		out.append(BuildWarning.limiting(&"pack_wider_than_plate",
			"The pack is %.0f mm wider than the centre plate — %.0f mm hangs over each side, with nothing for a strap to hold down." % [
				overhang["lateral"] * 2000.0, overhang["lateral"] * 1000.0],
			{"lateral_overhang_mm": overhang["lateral"] * 1000.0}))

	var clearance := battery_prop_clearance_m()
	if clearance < 0.0:
		out.append(BuildWarning.impossible(&"pack_in_prop_disc",
			"The pack reaches %.0f mm into the propeller discs — there is no room on this airframe for it." % [
				-clearance * 1000.0],
			{"intrusion_mm": -clearance * 1000.0}))

	return out
