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
## motor name -> GuardMesh. Empty when the build fits no guard. Parented onto the arm-tip pad
## as a sibling of the motor: the ring wraps its motor at the plan position, so it rides the
## same pad the motor does and a frame rebuild takes it with the arm rather than leaving a
## stale ring where a motor used to be. Reads its inner wall from PropGuard.tip_clearance_mm
## against the prop's own drawn radius (never a second geometry copy) — see guard_mesh.gd.
var guard_meshes: Dictionary = {}
## motor name -> ArmGuardMesh. Empty unless the build's printing block FITS arm guards (printed-room
## PR1). Parented onto the frame body rather than the pad, because a sleeve sits inboard of the motor
## along the arm and its seat is ArmGuard.seat_position_m — the point Build.mass_parts weighs it at.
var arm_guard_meshes: Dictionary = {}
## part id -> PrintedPartMesh, for the printed parts other than arm guards that the build FITS
## (printed-room PR16-PR18). Parented onto the frame body, drawn from each part's own `triangles_mm`.
var printed_part_meshes: Dictionary = {}
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
## The optional components that are FITTED, by category — camera, VTX, antenna, receiver. A category
## absent from this dictionary is a component not fitted, which is exactly what it means in
## Build.components: there is no placeholder and nothing greyed out, because a whoop on an AIO
## carries none of the four and the empty frame IS the picture. Parented onto the frame like the
## pack and the stack, so a frame rebuild — which frees the pads — takes them with it.
var component_meshes: Dictionary = {}
## Arm length of the build currently drawn, kept so clearance can be reported against the
## geometry actually on screen rather than against whatever Build was asked about last.
var arm_m := 0.0
## The motor map drawn on the aircraft — Config room C3 (design §4.3): M1..M4 in Betaflight's
## numbering, each with the direction it is configured to turn. A child of the airframe rather than
## of the frame, because it is annotation ON the aircraft rather than a part of it, and it must not
## be freed and re-parented by a frame rebuild. Hidden until Config is the focused system; the
## default picture of a drone is the drone.
var motor_map: MotorMapMarkers

func _init() -> void:
	frame_model = FrameModel.new()
	frame_model.name = "Frame"
	add_child(frame_model)
	motor_map = MotorMapMarkers.new()
	add_child(motor_map)


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
	guard_meshes.clear()
	arm_guard_meshes.clear()
	printed_part_meshes.clear()
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
			battery_mount, battery_mesh.size_m, battery_offset_m, build.battery_rise_m())
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

	# The four components LTHL-11 unbundled, each in its own bay. This loop is the whole of the gap
	# that made them 25 g of mass at four specific places with nothing on screen: everything it needs
	# already existed — the bays are MountLayout's, the mapping is Build.COMPONENT_MOUNTS, the size
	# is the part's own, and the seat is the SAME seated_centre_m() call Build.mass_parts() makes.
	# That last point is the one that matters: the moment this is a second sum, the picture and the
	# tensor can drift, and an inertia tensor does not appear on screen to say so.
	#
	# A category absent from build.components draws nothing, and that is all. Not fitted is a real
	# build rather than an incomplete one.
	component_meshes.clear()
	for category in Build.OPTIONAL_COMPONENTS:
		if not build.components.has(category):
			continue
		var bay := mount_point(String(Build.COMPONENT_MOUNTS[category]))
		# A frame that does not publish this bay skips the component rather than seating it at the
		# origin, which is where a null mount would put it — inside the stack, weighed nowhere near
		# there. Every frame in the catalog publishes all four today, so this guards a future frame
		# rather than a live case; the pack's own `battery_mount == null` fallback is the precedent.
		if bay == null:
			continue
		var component := ComponentMesh.new()
		component.name = "Component_%s" % category
		# The tilt crosses as a number from the same resolved dictionary as the plate gap, and every
		# category is handed it — only the camera reads it, so the loop stays free of a category branch.
		component.rebuild(category, build.components[category], float(tweak_m["camera_tilt_deg"]))
		# The mast rides along, and it has to: the moment this call and Build.mass_parts()'s call
		# pass different arguments, a masted GPS is drawn on the plate and weighed 70 mm above it,
		# and an inertia tensor does not appear on screen to say so. Same argument as the comment
		# above, one slice later and with a new parameter to forget.
		component.position = MountLayout.seated_centre_m(bay, component.size_m, 0.0,
			build.rise_m_for(build.components[category]))
		frame_model.add_child(component)
		component_meshes[category] = component

	# Read once, outside the loop, and handed to the drawing and the map alike — one dictionary, so
	# the propeller a builder watches and the label beside it cannot come from two reads.
	var spin_map := MotorLayout.spin_map(build.config)

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
		# Direction through MotorLayout's ONE ACCESSOR, not from the constant table: C2 made the
		# map an authored value that reaches the mixer, and C3 is what stops the drawing being the
		# one reader left behind. A props-in build whose propellers kept turning the old way would
		# teach a builder that Lothal's controls are decorative — the most expensive lesson this
		# app can give (design §5). Diagonals together, adjacents opposed, unless the builder said
		# otherwise, in which case it is drawn as they said.
		propeller.spin = float(spin_map[motor_name])
		motor.add_child(propeller)
		propeller_meshes[motor_name] = propeller

		# The prop guard, if the build fits one. Sibling of the motor under the same arm-tip
		# pad — the ring wraps the motor at the plan position, so the pad is where it belongs.
		# Y is the propeller disc's own, because a shroud is what wraps that disc and the tip
		# clearance the ring reads describes the gap between them at that plane. An empty
		# build.guard clears any previous ring and leaves the pad without one, which is what
		# "not fitted" means — same posture as component_meshes above.
		if not build.guard.is_empty():
			var guard := GuardMesh.new()
			guard.name = "Guard_%s" % motor_name
			guard.rebuild(build.guard, propeller.radius_m)
			# Position the ring at the disc plane, in the pad's own frame — the motor's y is
			# already relative to the pad, and propeller.position.y is relative to the motor,
			# so the total is the motor's y plus the prop's y for the ring's centre.
			guard.position = Vector3(0, motor.position.y + propeller.position.y, 0)
			pad.add_child(guard)
			guard_meshes[motor_name] = guard

		# The arm guard, when fitted and readable. Drawn from the same triangle list the export writes
		# and seated where the mass model weighs it — never a second seat computed here.
		if ArmGuard.is_fitted(build.printing):
			var dims := ArmGuard.dimensions(build.frame, build.printing)
			if bool(dims["ok"]):
				var sleeve := ArmGuardMesh.new()
				sleeve.name = "ArmGuard_%s" % motor_name
				sleeve.rebuild(dims)
				sleeve.transform = Transform3D(ArmGuardMesh.arm_basis(motor_name),
					ArmGuard.seat_position_m(motor_name, build.arm_m,
						ArmGuard.motor_stator_radius_m(build.motor), float(dims["length_mm"])))
				frame_model.add_child(sleeve)
				arm_guard_meshes[motor_name] = sleeve

	_draw_printed_parts(build, tweak_m)

	# The map last, so the propeller it is sized from has been generated. The radius is the drawn
	# propeller's own — never a second copy of it here.
	var disc_radius := 0.0
	if propeller_meshes.has(MotorLayout.MOTOR_NAMES[0]):
		disc_radius = (propeller_meshes[MotorLayout.MOTOR_NAMES[0]] as PropellerMesh).radius_m
	motor_map.rebuild(build, disc_radius)


## The fitted printed parts other than arm guards (printed-room PR18-PR20), each drawn from its own
## `triangles_mm` — the list the export writes. The mast and the pad are seated from the point
## `part_masses` weighs them at, never a second seat computed here. Not fitted, or refused, draws nothing.
func _draw_printed_parts(build: Build, tweak_m: Dictionary) -> void:
	# PR19: the cheeks either side of the DRAWN camera, at the drawn tilt (tweak_m's, the number the camera
	# was just drawn with). Each cheek's inner face is clearance off the camera's side; its outer face is
	# half the plate gap out.
	if CameraMount.is_fitted(build.printing) and component_meshes.has("camera"):
		var cam_dims := CameraMount.dimensions(build.components["camera"], build.printing,
			float(tweak_m["camera_tilt_deg"]))
		if bool(cam_dims["ok"]):
			var camera: ComponentMesh = component_meshes["camera"]
			var across := (float(cam_dims["camera_width_mm"]) * 0.5 + float(cam_dims["clearance_mm"])
				+ float(cam_dims["cheek_thickness_mm"]) * 0.5) / StlWriter.MM_PER_M
			var triangles := CameraMount.triangles_mm(cam_dims)
			for side in [["left", -1.0], ["right", 1.0]]:
				var cheek := _printed_mesh("%s_%s" % [CameraMount.PART_ID, side[0]], triangles, 1.0,
					PrintedPartMesh.CHEEK)
				cheek.position = camera.position + Vector3(float(side[1]) * across, 0.0, 0.0)

	# PR20: the tube's axis on the DRAWN whip — through its base (the antenna box's underside, on the plate) and
	# along its lean, which is the tube's own lean because both read ComponentMesh.WHIP_LEAN_DEGREES.
	if AntennaMount.is_fitted(build.printing) and component_meshes.has("antenna"):
		var ant_dims := AntennaMount.dimensions(build.components["antenna"], build.printing)
		if bool(ant_dims["ok"]):
			var antenna: ComponentMesh = component_meshes["antenna"]
			var whip := antenna.get_node_or_null("Whip") as Node3D
			if whip != null:
				var mount := _printed_mesh(AntennaMount.PART_ID, AntennaMount.triangles_mm(ant_dims), 1.0,
					PrintedPartMesh.AFT_Y)
				mount.position = antenna.position + whip.position \
					- PrintedPartMesh.AFT_Y * AntennaMount.tube_foot_mm(ant_dims) / StlWriter.MM_PER_M

	# The weighed point is the one gate: part_masses is empty unless the part is Fitted and readable.
	var mast_masses := GpsMast.part_masses(build, build.printing)
	if not mast_masses.is_empty():
		var mast_dims := GpsMast.dimensions(build, build.printing)
		var bay := mount_point(String(Build.COMPONENT_MOUNTS["gps"]))
		if bool(mast_dims["ok"]) and bay != null:
			var mast := _printed_mesh(GpsMast.PART_ID, GpsMast.triangles_mm(mast_dims), float(bay.normal))
			# Weighed half the mast up the post; the flange's foot is on the bay.
			mast.position = (mast_masses[0] as PartMass).position_m \
				- Vector3(0.0, float(bay.normal) * float(mast_dims["mast_height_mm"]) * 0.0005, 0.0)

	var pad_masses := BatteryPad.part_masses(build, build.printing)
	if not pad_masses.is_empty():
		var pad_dims := BatteryPad.dimensions(build.battery, build.printing)
		if bool(pad_dims["ok"]) and battery_mount != null:
			var pad := _printed_mesh(BatteryPad.PART_ID, BatteryPad.triangles_mm(pad_dims), float(battery_mount.normal))
			# Weighed at its own centre; printed from the bed up, so the node sits half a pad back towards the plate.
			pad.position = (pad_masses[0] as PartMass).position_m \
				- Vector3(0.0, float(battery_mount.normal) * float(pad_dims["thickness_mm"]) * 0.0005, 0.0)


## One printed part's node on the frame body, Z-up print frame, turned over for a mount facing down.
func _printed_mesh(id: String, triangles: Array, normal: float,
		print_frame: Basis = PrintedPartMesh.Z_UP) -> PrintedPartMesh:
	var mesh := PrintedPartMesh.new()
	mesh.name = "Printed_%s" % id
	mesh.rebuild(triangles, print_frame)
	if normal < 0.0:
		mesh.basis = Basis(Vector3.RIGHT, PI)
	frame_model.add_child(mesh)
	printed_part_meshes[id] = mesh
	return mesh


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


## The fitted camera's lens, as a node in the world — what a view taken through the camera is taken
## from — or null when no camera is fitted, which is a real build rather than a missing one.
##
## Named accessor rather than callers walking into component_meshes, for the same reason
## mount_point() exists: the airframe stays the one place that knows what is mounted where.
func camera_eye() -> Node3D:
	if not component_meshes.has("camera"):
		return null
	return (component_meshes["camera"] as ComponentMesh).get_node_or_null("Eye")


## Where the lens is IN THE AIRFRAME'S OWN FRAME, metres, or null when no camera is fitted.
##
## The same eye `camera_eye()` returns, as a number rather than as a node. Both come off the same
## marker — this reads the node's own `position` and the mesh's, and adds them — so there is one
## answer to where the lens is and not a second derivation that could drift from the drawing.
##
## It exists because `global_transform` is unusable for this: a `Node3D` outside the tree returns
## identity, so a check written against it silently measures an aircraft whose every part sits on
## the origin. That is the exact defect the 2026-08-28 review found in the guard polygon, and it
## would be a worse one here because the eye is the thing every angle is measured FROM.
##
## THE ROTATION IS COMPOSED IN, and since V2 it has to be. The camera tilt tips the eye marker up
## about the camera's centre, and the eye sits AHEAD of the box — so tilt moves where the lens is,
## not only which way it looks. Adding positions would put a 40 deg lens where a level one sits.
## So the eye is placed by the full local transforms, mesh then marker, which is exactly what
## `FpvView.world_transform_of` walks: the check and the feed cannot disagree about the lens.
func camera_eye_m() -> Variant:
	var placement = _camera_eye_transform()
	if placement == null:
		return null
	return (placement as Transform3D).origin


## The direction the fitted camera looks, in the airframe's own frame: (0, sin θ, -cos θ) for an
## uptilt of θ, and plain forward (-Z, physics.md §1) when no camera is fitted.
##
## Composed from the eye marker's own basis rather than computed from the tilt setting, and that is
## the point: the angle is stated ONCE, on the drawn camera, and this reads what was drawn. A second
## `sin(tilt)` here would agree with the picture right up until the day one of them flipped a sign.
## A named function rather than callers writing a vector, so `CameraView` is handed a number and
## never a node.
func camera_boresight() -> Vector3:
	var placement = _camera_eye_transform()
	if placement == null:
		return Vector3(0.0, 0.0, -1.0)
	return ((placement as Transform3D).basis * Vector3(0.0, 0.0, -1.0)).normalized()


## The eye marker's transform in the airframe's frame, composed from LOCAL transforms because
## `global_transform` outside the tree is identity (the 2026-08-28 defect). Null with no camera.
func _camera_eye_transform() -> Variant:
	if not component_meshes.has("camera"):
		return null
	var mesh: ComponentMesh = component_meshes["camera"]
	var eye := mesh.get_node_or_null("Eye") as Node3D
	if eye == null:
		return null
	return mesh.transform * eye.transform


## Everything the camera can be blocked by, `{name: PackedVector3Array}` in the airframe's own
## frame — what `CameraView` measures angles to.
##
## TWO KINDS OF THING ARE IN HERE AND THERE IS NO THIRD BY OVERSIGHT:
##
##   - every drawn plate, by node name. THE ARMS ARE THESE. Frames are plates in this app, so an
##     arm is part of a plate's outline rather than a solid of its own, and the outline IS the
##     silhouette. `FrameModel.plate_polygons_m()` publishes them; the plan-to-world mapping is
##     `AirframeDocument.world_m`, the same one `PlateMesh` extrudes through, so the polygon
##     measured here is the polygon drawn.
##   - every fitted guard ring, from `guard_ring_polygons_m()` unchanged — the polygon P10c shipped
##     and left waiting for exactly this caller.
##
## The propellers are NOT here, and that is a decision rather than a gap: a spinning disc is in
## front of an FPV camera on most builds and everyone flying knows it, so reporting it as an
## obstruction would bury the two findings that are actually actionable under four that are not.
## The disc's geometry is already published by `PropellerMesh` if that judgement is ever revisited.
##
## Empty for a moulded frame with no plates and no guard, which is a real aircraft and not a
## failure: `FrameModel` draws a stand-in body precisely because the plate model cannot describe
## that shape, and inventing an outline for it would be a claim about a frame nobody measured.
func camera_obstruction_points_m() -> Dictionary:
	var out := {}

	for record in frame_model.plate_polygons_m():
		var points := PackedVector3Array()
		var y: float = record["y_m"]
		for plan_mm in record["outline_mm"]:
			points.append(AirframeDocument.world_m(plan_mm, 0.0) + Vector3(0.0, y, 0.0))
		if not points.is_empty():
			out[str(record["name"])] = points

	var rings := guard_ring_polygons_m()
	for motor_name in rings:
		var guard: GuardMesh = guard_meshes[motor_name]
		# The ring's height is the propeller disc plane, which is where GuardMesh puts it and why —
		# a shroud wraps the disc. Read off the node under the arm-tip pad and added to the pad's
		# own height, because the polygon above is in the AIRCRAFT's plan frame and the node's Y is
		# in the pad's.
		var pad: Node3D = frame_model.arm_tips[motor_name]
		var y: float = pad.position.y + guard.position.y
		var points := PackedVector3Array()
		for plan_m in rings[motor_name]:
			points.append(Vector3(plan_m.x, y, plan_m.y))
		out["guard %s" % motor_name] = points

	return out


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
	return footprint_prop_clearance_m(Rect2(
		-half_x, centre_z - half_z, half_x * 2.0, half_z * 2.0))


## Every fitted guard's ring silhouette in plan view, motor name -> 32-vertex polygon, in the
## airframe's own XZ plane. Empty when the build fits no guard.
##
## For the camera-frustum containment test plans/2026-08-26-propulsion-room-design.md §5 P10c
## asks for. The arm half of that check does not exist yet, so nothing reads this — it is here
## so the guard plugs into the check on the day it lands rather than becoming a second thing to
## catch up.
##
## The plan centre comes from `MotorLayout.motor_position`, which is the SAME source
## `footprint_prop_clearance_m` reads two functions below, and not from the GuardMesh node's own
## transform: the ring is parented onto the arm-tip pad, so its local XZ is the pad's origin and
## four rings read that way would all sit on the aircraft's centre. One definition of where a
## motor is, here as there.
func guard_ring_polygons_m() -> Dictionary:
	var out := {}
	for motor_name in MotorLayout.MOTOR_NAMES:
		if not guard_meshes.has(motor_name):
			continue
		var guard: GuardMesh = guard_meshes[motor_name]
		var hub := MotorLayout.motor_position(motor_name, arm_m)
		var polygon := guard.ring_polygon_m(Vector2(hub.x, hub.z))
		if not polygon.is_empty():
			out[motor_name] = polygon
	return out


## What the fitted camera is looking past, in words — plans/2026-08-26-propulsion-room-design.md
## §5 P10c's check, in the vocabulary every other check here speaks.
##
## ## THE COMPARISON IS AGAINST THE FRAME, AND THAT IS WHAT MAKES IT SAYABLE
##
## The first version of this reported everything forward of the lens plane — a hard geometric
## boundary needing no field of view, which was the point. It fired on EVERY build with a plate
## frame, because the arms of a standard X sit about 54 deg off centre and are therefore in shot on
## any real 150 deg lens. That is true, and it is noise: it is the same objection that keeps the
## propellers out of `camera_obstruction_points_m()` — four findings nobody can act on bury the one
## they can.
##
## So the thing reported is a FITTED PART THAT IS MORE IN SHOT THAN THE AIRCRAFT ITSELF. The
## frame's own silhouette is the baseline, and it is not a free constant: every build has one, it
## is measured rather than chosen, and it moves with the frame — which is exactly right, because a
## deadcat frame EXISTS to get the arms out of the picture, and against a deadcat's baseline a
## guard has further to go before it is worth mentioning.
##
## Still no field of view anywhere. See `CameraView` for why none exists to test against and why
## inventing one here would be a fabricated spec inside a build warning. The sentence carries the
## angle, and the builder — who knows what lens they own — reads the verdict off it: a part at
## 20 deg is in shot on anything wider than 40. Doubling is arithmetic, not a claim about a camera.
##
## CHARACTERISTIC, never LIMITING, and BuildWarning's own rule is why: there is no boundary in the
## physics being crossed. Ducts in the corners of the picture are what a cinewhoop IS, and telling
## somebody who built one that they have made a mistake is the exact failure that file's header was
## written about.
func camera_view_warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var eye = camera_eye_m()
	if eye == null:
		return out

	var report := CameraView.off_axis_report(eye, camera_boresight(), camera_obstruction_points_m())

	# The frame's own silhouette is the baseline. INF when there is no plate geometry at all — a
	# moulded whoop — which is the right answer rather than a missing one: nothing of the airframe
	# is in the picture to compare against, so anything fitted has nothing to beat.
	var frame_deg := INF
	var fitted: Array = []
	for part_name in report:
		var angle: float = report[part_name]
		if str(part_name).begins_with("Plate"):
			frame_deg = minf(frame_deg, angle)
		else:
			fitted.append({"name": part_name, "deg": angle})

	# Sorted so the sentence names the most intrusive part rather than whichever one the dictionary
	# happened to yield first — the order IS the finding.
	fitted.sort_custom(func(a, b): return a["deg"] < b["deg"])

	var worse: Array = []
	for entry in fitted:
		# Forward of the lens plane AND further into the picture than the aircraft already is.
		if entry["deg"] < 90.0 and entry["deg"] < frame_deg:
			worse.append(entry)
	if worse.is_empty():
		return out

	var closest: Dictionary = worse[0]
	var message := "%s enters the camera's view %.0f° off centre — visible on any lens wider than %.0f°" % [
		closest["name"], closest["deg"], closest["deg"] * 2.0]
	if is_inf(frame_deg):
		message += ", and this frame has no plate silhouette to hide behind."
	else:
		message += ", ahead of the airframe's own %.0f°." % frame_deg
	if worse.size() > 1:
		message += " %d other fitted part%s the same." % [
			worse.size() - 1, " does" if worse.size() == 2 else "s do"]
	message += " No lens angle is published for any camera in the catalog, so this is geometry rather than a verdict."

	out.append(BuildWarning.characteristic(&"camera_obstruction", message, {
		"closest_name": closest["name"],
		"closest_deg": closest["deg"],
		"frame_deg": frame_deg,
		"worse_count": worse.size(),
		"off_axis_deg": report,
	}))
	return out


## The narrowest gap in PLAN VIEW between an arbitrary footprint and any propeller's swept disc, in
## metres. Negative means the footprint is inside a disc.
##
## `footprint` is a rectangle in the airframe's own XZ plane: x across, y along Z, forward being -Z.
##
## The pack's check above and every component's check below are one implementation, because they are
## one question. It was the pack's alone until four more objects grew a place on the aircraft, and
## the alternative — a second copy of this loop for components — is the divergence this file's own
## header was written about, in miniature: two clearance checks that agree until one of them learns
## something the other does not.
func footprint_prop_clearance_m(footprint: Rect2) -> float:
	if propeller_meshes.is_empty():
		return 0.0

	var centre := footprint.get_center()
	var half := footprint.size * 0.5
	var narrowest := INF

	for motor_name in MotorLayout.MOTOR_NAMES:
		var propeller: PropellerMesh = propeller_meshes[motor_name]
		var hub := MotorLayout.motor_position(motor_name, arm_m)
		# Distance from the hub to the nearest point of the rectangle. Zero on each axis the hub is
		# already inside, which is what makes this correct for a footprint the props sit over as
		# well as for one they sit clear of.
		var gap := Vector2(
			maxf(absf(hub.x - centre.x) - half.x, 0.0),
			maxf(absf(hub.z - centre.y) - half.y, 0.0)).length()
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


# ---------------------------------------------------------------------------
# Do the components fit?
# ---------------------------------------------------------------------------

## Where a fitted component's DRAWN silhouette lands in plan view, in the airframe's own XZ plane,
## or a zero rectangle if that category is not fitted.
##
## The mesh's own footprint, offset by where it was seated — so an antenna leaning aft of its box
## and a camera lens past its nose are measured where they actually are. This is the same posture
## battery_overhang_m() takes and for the same reason (labs-and-sim.md §2.2): a figure recomputed
## from the published dimensions would be a second opinion that agrees with the render right up
## until a silhouette stops being a box, which for the antenna it already has.
func component_bounds_m(category: String) -> Rect2:
	if not component_meshes.has(category):
		return Rect2()
	var box := component_aabb_m(category)
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## The same component's whole drawn box, seated where it sits. The plan view above throws the height
## away, which is right for a propeller disc — a rotor is a disc and what matters is the airspace
## under it — and wrong for asking whether two components are in each other's way, because three of
## the four bays are on DIFFERENT FACES of the plate stack.
func component_aabb_m(category: String) -> AABB:
	if not component_meshes.has(category):
		return AABB()
	var mesh: ComponentMesh = component_meshes[category]
	var box := mesh.drawn_aabb_m()
	box.position += mesh.position
	return box


## What is wrong with where the fitted components ended up, in words, measured off the geometry
## drawn above. Empty for a build whose components fit — including the reference build.
##
## The same split as everything else here: Build.warnings() is what the parts DECLARE about each
## other, mount_warnings() is what the mount system says about how each attaches, and this is what
## the assembled geometry DOES. Three conditions, each of which became visible only once the four
## components had a picture, and each of which a builder currently cannot see at all:
##
##   - a component reaching into a propeller disc. The antenna is the case that motivates it: it is
##     the furthest-out mass on the aircraft and it stands up into exactly the airspace a rotor
##     sweeps. Same measurement as the pack's, from footprint_prop_clearance_m().
##   - a component larger than the plate it sits on. A full-size 26 mm camera on a 65 mm whoop
##     whose centre plate is 17.6 mm square is a real thing to try, and nothing is wrong with
##     building it — it should simply be obvious, on screen and in words, that it is absurd.
##   - two components occupying the same air. The camera bay and the VTX bay are opposite edges of
##     one face, which is comfortable at 5" and is the same 17.6 mm of plate at 65 mm.
##
## NOTHING HERE BLOCKS. Every one of these is a warning, in the manner of the whole app: a build
## Lothal will not let you assemble is a question you cannot ask.
func component_fit_warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	for category in Build.OPTIONAL_COMPONENTS:
		if not component_meshes.has(category):
			continue
		var label := _component_label(category)
		var bounds := component_bounds_m(category)

		var clearance := footprint_prop_clearance_m(bounds)
		if clearance < 0.0:
			out.append(BuildWarning.impossible(&"component_in_prop_disc",
				"The %s reaches %.0f mm into the propeller discs — the props would strike it." % [
					label, -clearance * 1000.0],
				{"component": category, "intrusion_mm": -clearance * 1000.0}))

		var bay := mount_point(String(Build.COMPONENT_MOUNTS[category]))
		if bay != null and bay.span_m != Vector2.ZERO:
			# Against the part's own SEAT rather than the drawn silhouette, which is the opposite
			# choice from the clearance above and is deliberate. What is being asked here is "is
			# this object bigger than the plate it sits on" — a question about what rests on the
			# bay — and the antenna's silhouette answers a different one: it stands up and leans a
			# long way aft on purpose, and an antenna standing out past the back of the aircraft is
			# what an antenna does. Reaching into a rotor is a fit failure; reaching into open air
			# aft is a mount. See ComponentMesh.seat_footprint_m().
			var seat: Vector2 = (component_meshes[category] as ComponentMesh).seat_footprint_m()
			var over := maxf(seat.x - bay.span_m.x, seat.y - bay.span_m.y)
			if over > 0.0005:
				out.append(BuildWarning.limiting(&"component_larger_than_plate",
					"The %s is %.0f mm across and %s offers %.0f mm — it is bigger than the plate it sits on." % [
						label, maxf(seat.x, seat.y) * 1000.0, bay.label,
						minf(bay.span_m.x, bay.span_m.y) * 1000.0],
					{"component": category, "over_mm": over * 1000.0}))

	out.append_array(_bay_overlap_warnings())
	return out


## Components whose drawn geometry occupies the same air. Every unordered pair, tested as whole
## boxes — pairwise rather than per-bay, because the pairs that collide are a property of the parts
## and the frame together and not of the bay table: the camera bay and the VTX bay are opposite
## edges of one face, and they touch only when the plate between them has run out.
##
## IN ALL THREE DIMENSIONS, AND THE PLAN-VIEW VERSION OF THIS CHECK WAS WRONG. Plan view is right
## for a propeller disc — a rotor is a disc, and its airspace is the whole column under it — and it
## is wrong here, because MountLayout puts the four bays on three different FACES on purpose: the
## antenna stands on the top plate's upper face and the VTX hangs under the lower one at the same
## rear edge, directly above and below each other by design. Projected into plan they overlap
## completely, so the plan-view test reported three collisions on the reference build, which is a
## build that fits. What makes two components a problem is sharing the same space, and the plate
## stack between them is exactly what stops them.
##
## Limiting rather than impossible: a real builder solves this with a shim, a bracket and a zip tie.
func _bay_overlap_warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var fitted: Array = []
	for category in Build.OPTIONAL_COMPONENTS:
		if component_meshes.has(category):
			fitted.append(category)

	for i in fitted.size():
		for j in range(i + 1, fitted.size()):
			var first := component_aabb_m(String(fitted[i]))
			var second := component_aabb_m(String(fitted[j]))
			var overlap := first.intersection(second)
			if overlap.size.x <= 0.0005 or overlap.size.y <= 0.0005 or overlap.size.z <= 0.0005:
				continue
			out.append(BuildWarning.limiting(&"components_overlap",
				"The %s and the %s occupy the same %.0f x %.0f mm of the airframe — they will not both fit where they are meant to go." % [
					_component_label(String(fitted[i])), _component_label(String(fitted[j])),
					overlap.size.x * 1000.0, overlap.size.z * 1000.0],
				{"first": fitted[i], "second": fitted[j],
					"overlap_mm3": overlap.size.x * overlap.size.y * overlap.size.z * 1e9}))
	return out


## What a builder calls each of the four. Here rather than in the catalog entry's name because the
## warning reads better as "the camera" than as "the Foxeer Razer Micro", and the part is already
## named in the rail the builder just chose it from.
static func _component_label(category: String) -> String:
	match category:
		"vtx": return "video transmitter"
		"receiver": return "receiver"
		"antenna": return "antenna"
		_: return "camera"
