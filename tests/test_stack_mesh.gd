class_name TestStackMesh
extends RefCounted
## The FC/ESC stack: a real board in the standoff stack, at real scale — and, more importantly,
## an unchanged aircraft on the scales.
##
## THE ORACLE HAZARD THIS SUITE EXISTS FOR. Build has carried ELECTRONICS_MASS_G := 55 g since day
## 2: a lump at the origin standing in for the FC, the ESC, the camera, the VTX, the antenna and
## the receiver. The reference build's 496 g, 11.7:1 and 29% hover were all computed WITH that lump
## included. Giving one of those six components physical form is a VISUAL change, so if it also
## made the aircraft heavier then every build in Lothal would have gained weight for nothing and
## two of the project's three fixed points would have moved.
##
## So the rule is subtraction, not addition: what is drawn comes OUT of the 55 g. These tests hold
## that budget shut from both ends — the two electronics masses must sum to exactly the lump, and
## neither may be zero, because "we drew it and gave it no mass" and "we drew it and added mass"
## are both ways of getting the accounting wrong.

const EPS := 0.0005
## Grams. Tighter than a gram, so "unchanged to the gram" is asserted rather than approximated.
const MASS_EPS_G := 0.001

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_the_board_is_the_pattern_it_is_drilled_for())
	results.append(_test_the_stack_is_drawn_at_the_size_it_reports())
	results.append(_test_the_stack_sits_in_the_standoff_stack(catalog))
	results.append(_test_the_electronics_budget_still_totals_the_lump(catalog))
	results.append(_test_the_reference_oracles_did_not_move())
	results.append(_test_no_mount_position_reaches_the_mass_model(catalog))

	return results


## Board size follows the bolt pattern, because the difference between a 30.5 board and a 20x20
## board is the strip of PCB outside the bolt circle and that strip is the same width on both.
## 36.5 mm and 26 mm, worked out on paper.
static func _test_the_board_is_the_pattern_it_is_drilled_for() -> TestResult:
	var full := StackMesh.size_m("30.5x30.5")
	var small := StackMesh.size_m("20x20")

	var passed := absf(full.x - 0.0365) < EPS and absf(full.z - 0.0365) < EPS \
		and absf(small.x - 0.026) < EPS and absf(small.z - 0.026) < EPS

	return TestResult.new(
		"the board's footprint follows the pattern it is drilled for",
		passed,
		"30.5x30.5 -> %.1f mm board, 20x20 -> %.1f mm board" % [full.x * 1000.0, small.x * 1000.0])


## What is on screen is what size_m() reports, measured off the generated meshes rather than
## recomputed from the constants. The clearance check reads size_m() and the builder reads the
## picture, and labs-and-sim.md §2.2 is that those are one thing.
static func _test_the_stack_is_drawn_at_the_size_it_reports() -> TestResult:
	var stack := StackMesh.new()
	stack.rebuild(Build.STACK_MOUNT_PATTERN)
	var reported := StackMesh.size_m(Build.STACK_MOUNT_PATTERN)

	var widest := 0.0
	var lowest := INF
	var highest := -INF
	var boards := 0
	for child in stack.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var box := mesh_instance.mesh as BoxMesh
		if box == null:
			continue
		if String(mesh_instance.name).begins_with("Board"):
			boards += 1
			widest = maxf(widest, box.size.x)
			lowest = minf(lowest, mesh_instance.position.y - box.size.y * 0.5)
			highest = maxf(highest, mesh_instance.position.y + box.size.y * 0.5)

	var passed := boards == 2 \
		and absf(widest - reported.x) < EPS \
		and absf((highest - lowest) - reported.y) < EPS \
		and absf(lowest) < EPS

	stack.free()
	return TestResult.new(
		"the stack is drawn at the size it reports, seated on y = 0",
		passed,
		"%d boards, widest %.4f m (reports %.4f), height %.4f m (reports %.4f), base at %.4f m" % [
			boards, widest, reported.x, highest - lowest, reported.y, lowest])


## On the aircraft, in the frame's own stack mount — between the plates, sitting on the bottom
## plate's upper face, and low enough to close inside the standoffs on the reference build.
static func _test_the_stack_sits_in_the_standoff_stack(catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	var mount: MountPoint = null
	for point in airframe.frame_model.mount_points:
		if point.id == "stack":
			mount = point

	var detail := ""
	var passed := true
	if airframe.stack_mesh == null or mount == null:
		passed = false
		detail = "no stack mesh or no stack mount"
	else:
		var base: float = airframe.stack_mesh.position.y
		var height: float = StackMesh.size_m(Build.STACK_MOUNT_PATTERN).y
		if absf(base - mount.position.y) > EPS:
			passed = false
			detail += "base at y=%.4f, mount seat at y=%.4f; " % [base, mount.position.y]
		if base + height > airframe.frame_model.plate_top_face_m():
			passed = false
			detail += "the stack stands proud of the top plate; "
		if catalog.get_part("frame_5in_freestyle")["specs"]["stack_mount"] != mount.pattern:
			passed = false
			detail += "the mount is not the frame's declared pattern; "
		if passed:
			detail = "seated on the bottom plate at y=%.4f, %.1f mm tall, inside a %.1f mm stack" % [
				base, height * 1000.0,
				(airframe.frame_model.plate_top_face_m() - base) * 1000.0]

	airframe.free()
	return TestResult.new("the stack is mounted in the standoff stack", passed, detail)


## The budget, held shut from both ends. The two electronics contributions must sum to exactly
## ELECTRONICS_MASS_G, and neither may be zero — drawing a component and giving it no mass is the
## other way to get this wrong, and it would leave the picture and the scales disagreeing.
static func _test_the_electronics_budget_still_totals_the_lump(_catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()

	# Everything not accounted for by the frame, the pack and the four motor/prop pairs IS the
	# electronics, however many entries it has been split into. Measured as a remainder rather
	# than by counting entries, so adding a third electronics mass cannot slip past this.
	var total_g := 0.0
	for part in build.mass_parts():
		total_g += (part as PartMass).mass_kg * 1000.0

	var motor_prop_g := (float(build.motor["mass_g"]) + float(build.propeller["mass_g"])) * 4.0
	var accounted_g := motor_prop_g + float(build.frame["mass_g"]) + float(build.battery["mass_g"])
	var electronics_g := total_g - accounted_g

	var passed := absf(electronics_g - Build.ELECTRONICS_MASS_G) < MASS_EPS_G \
		and Build.STACK_MASS_G > 0.0 \
		and Build.STACK_MASS_G < Build.ELECTRONICS_MASS_G

	return TestResult.new(
		"the electronics still weigh exactly what the lump always did",
		passed,
		"%.4f g of electronics (budget %.1f g): %.1f g given form as the stack, %.1f g still lumped" % [
			electronics_g, Build.ELECTRONICS_MASS_G, Build.STACK_MASS_G,
			Build.ELECTRONICS_MASS_G - Build.STACK_MASS_G])


## The three fixed points, restated here rather than only in test_validation.gd, because this is
## the slice that could move them and a failure should say so next to the change that caused it.
## 496 g, 11.7:1 and 29% are parts.md's hand-verified reference build.
static func _test_the_reference_oracles_did_not_move() -> TestResult:
	var build := ReferenceBuild.build()
	var weight_g := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()

	var passed := absf(weight_g - 496.0) < 0.5 \
		and absf(twr - 11.7) < 0.1 \
		and absf(hover - 0.29) < 0.01

	return TestResult.new(
		"mounting the stack moved neither the weight, the thrust-to-weight, nor the hover throttle",
		passed,
		"%.1f g (want 496), %.2f:1 (want 11.7), %.1f%% hover (want 29)" % [
			weight_g, twr, hover * 100.0])


## Geometry-bearing, not physics-bearing (labs-and-sim.md §2.5). The stack is drawn well below the
## origin, between the plates — and the mass model must not have heard about it. Every mass in the
## model still sits either at the centre or at a motor position, and there is no third place.
static func _test_no_mount_position_reaches_the_mass_model(_catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()
	var allowed: Array[Vector3] = [Vector3.ZERO]
	for motor_name in MotorLayout.MOTOR_NAMES:
		allowed.append(MotorLayout.motor_position(motor_name, build.arm_m))

	var stray: Array = []
	for part in build.mass_parts():
		var position: Vector3 = (part as PartMass).position_m
		var known := false
		for candidate in allowed:
			if (position - candidate).length() < 1e-9:
				known = true
		if not known:
			stray.append(position)

	# And the thing that would make the check vacuous: the stack really is drawn off the origin.
	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var drawn_off_origin: bool = airframe.stack_mesh != null \
		and absf(airframe.stack_mesh.position.y) > EPS
	airframe.free()

	return TestResult.new(
		"the stack's mount position stays out of the mass model",
		stray.is_empty() and drawn_off_origin,
		"%d masses off the centre or an arm tip %s; stack drawn off the origin: %s" % [
			stray.size(), stray, drawn_off_origin])
