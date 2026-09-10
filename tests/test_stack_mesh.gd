class_name TestStackMesh
extends RefCounted
## The FC/ESC stack: a real board in the standoff stack, at real scale — and, more importantly,
## an unchanged aircraft on the scales.
##
## THE ORACLE HAZARD THIS SUITE EXISTS FOR. Build has carried ELECTRONICS_BUDGET_G := 55 g since day
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
	results.append(_test_the_mount_position_reaches_the_mass_model(catalog))

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


## The electronics, held shut from both ends. Everything on the aircraft that is not frame, pack or
## motor-and-prop must sum to the six carved shares PLUS the harness, and neither the stack nor the
## harness may be zero — drawing a component and giving it no mass is the other way to get this
## wrong, and it would leave the picture and the scales disagreeing.
##
## IT USED TO BE `ELECTRONICS_BUDGET_G` ON THE RIGHT-HAND SIDE, flat, on every build. PW2 weighed
## the harness instead of leaving it as the budget's remainder, so the sum is now the shares plus a
## real harness and this check follows the model rather than holding it to a retired constant.
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

	var expected_g := Build.carved_total_g() + build.harness_mass_g()
	var passed := absf(electronics_g - expected_g) < MASS_EPS_G \
		and Build.STACK_MASS_G > 0.0 \
		and build.harness_mass_g() > 0.0 \
		and Build.STACK_MASS_G < expected_g

	return TestResult.new(
		"the electronics weigh the carved shares plus the harness, and nothing is drawn weightless",
		passed,
		"%.4f g of electronics against %.1f carved + %.4f harness: %.1f g given form as the stack, %.1f g as the four LTHL-11 unbundled" % [
			electronics_g, Build.carved_total_g(), build.harness_mass_g(), Build.STACK_MASS_G,
			Build.carved_total_g() - Build.STACK_MASS_G])


## The three fixed points, restated here rather than only in test_validation.gd, because this is
## the slice that could move them and a failure should say so next to the change that caused it.
## 507.5 g, 11.43:1 and 30% are parts.md's reference build after PW2 re-baselined it (the harness
## stopped being a flat 14 g lump); it was 496 g / 11.7 : 1 / 29% before that.
static func _test_the_reference_oracles_did_not_move() -> TestResult:
	var build := ReferenceBuild.build()
	var weight_g := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()

	var passed := absf(weight_g - 507.48) < 0.5 \
		and absf(twr - 11.43) < 0.1 \
		and absf(hover - 0.30) < 0.01

	return TestResult.new(
		"mounting the stack moved neither the weight, the thrust-to-weight, nor the hover throttle",
		passed,
		"%.1f g (want 507.5), %.2f:1 (want 11.43), %.1f%% hover (want 29.9)" % [
			weight_g, twr, hover * 100.0])


## THE INVERSE OF WHAT THIS TEST USED TO ASSERT, and deliberately so.
##
## It read "the stack's mount position stays out of the mass model": the stack was drawn between
## the plates and the mass model had not heard about it, because assembly was geometry-bearing and
## not physics-bearing (labs-and-sim.md §2.5). That was the right decision while the mass model had
## no centre-of-gravity term to put it in, and assembly_tweaks.gd named the day it would change.
##
## That day is this slice. So the assertion is now that the two agree: the boards weigh in at the
## height they are drawn at, from the same seat and the same two board offsets. Inverting it rather
## than deleting it keeps the check that matters — that the picture and the physics cannot drift —
## pointing the other way.
static func _test_the_mount_position_reaches_the_mass_model(_catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()

	# Where the boards are DRAWN: the stack node's own position, plus each board's height within it.
	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var drawn := airframe.stack_mesh.position if airframe.stack_mesh != null else Vector3.ZERO
	var drawn_off_origin: bool = airframe.stack_mesh != null and absf(drawn.y) > EPS
	airframe.free()

	var drawn_fc := drawn + Vector3(0.0, StackMesh.fc_centre_height_m(), 0.0)
	var drawn_esc := drawn + Vector3(0.0, StackMesh.esc_centre_height_m(), 0.0)

	# Where they are WEIGHED.
	var weighed_fc := Vector3.ZERO
	var weighed_esc := Vector3.ZERO
	for part in build.mass_parts():
		if (part as PartMass).label == "Flight controller":
			weighed_fc = (part as PartMass).position_m
		elif (part as PartMass).label == "ESC":
			weighed_esc = (part as PartMass).position_m

	var agrees: bool = (weighed_fc - drawn_fc).length() < 1e-9 \
		and (weighed_esc - drawn_esc).length() < 1e-9
	# And the thing that would make the check vacuous: the stack really is drawn off the origin, so
	# "they agree" is not two zeroes agreeing.
	return TestResult.new(
		"the stack is weighed at the height it is drawn",
		agrees and drawn_off_origin and weighed_fc != weighed_esc,
		"FC drawn %s weighed %s; ESC drawn %s weighed %s; stack drawn off the origin: %s" % [
			drawn_fc, weighed_fc, drawn_esc, weighed_esc, drawn_off_origin])
