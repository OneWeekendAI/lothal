class_name TestAirframeModel
extends RefCounted
## The assembled airframe: one Build in, one complete aircraft of generated geometry out.
##
## The assertion that matters most is that the motors hang off FrameModel's arm_tips pads
## rather than being placed by a second copy of the arm-tip arithmetic. Two copies of that
## sum would agree for a long time and then diverge the first time anything about the mount
## changes, and the symptom would be motors floating a few millimetres off the arms — the
## kind of thing nobody notices in a screenshot and no numeric test looks for. So the check
## is structural (is the motor a descendant of the pad?) as well as positional.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_motors_hang_off_the_arm_tips(catalog))
	results.append(_test_a_frame_change_takes_its_motors_with_it(catalog))
	results.append(_test_motor_choice_changes_motor_size(catalog))
	results.append(_test_props_sit_on_the_motor_shafts(catalog))
	results.append(_test_prop_choice_changes_the_props(catalog))
	results.append(_test_an_oversized_prop_overlaps_the_airframe(catalog))

	return results


## A propeller belongs to its motor, not to the frame. Parented that way, a taller motor lifts
## its own prop and nothing at the call site has to know how tall a 2807 is.
static func _test_props_sit_on_the_motor_shafts(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3")
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	var problems: Array[String] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		var motor: MotorMesh = airframe.motor_meshes[motor_name]
		var prop: PropellerMesh = airframe.propeller_meshes[motor_name]
		if prop.get_parent() != motor:
			problems.append("%s's prop is not on its motor" % motor_name)
		var bell := motor.get_node("Bell") as MeshInstance3D
		var bell_top: float = bell.position.y + (bell.mesh as CylinderMesh).height * 0.5
		if prop.position.y <= bell_top:
			problems.append("%s's prop at y=%.4f is inside the bell (top %.4f)" % [
				motor_name, prop.position.y, bell_top])

	# A taller motor must carry its prop higher — the check that the height is asked for rather
	# than assumed.
	var tall := AirframeModel.new()
	tall.rebuild(_build(catalog, "frame_5in_freestyle", "motor_2807_1300kv", "prop_5x43x3"))
	var short_y: float = (airframe.propeller_meshes["M1"] as Node3D).position.y
	var tall_y: float = (tall.propeller_meshes["M1"] as Node3D).position.y
	if tall_y <= short_y:
		problems.append("a 2807 does not raise its prop above a 2207's (%.4f vs %.4f)" % [tall_y, short_y])

	airframe.free()
	tall.free()

	return TestResult.new(
		"every propeller sits on its own motor's shaft, clear of the bell",
		problems.is_empty(),
		"prop height 2207 %.4f m -> 2807 %.4f m, %s" % [
			short_y, tall_y, "all seated" if problems.is_empty() else str(problems)]
	)


## Frame and motor held still, so anything that moves came from the prop selection. This is the
## acceptance criterion — a 3-blade 5" swapped for a 2-blade 7" changes diameter AND count —
## asserted on the assembled airframe rather than on a prop on its own.
static func _test_prop_choice_changes_the_props(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_7in_long_range", "motor_2807_1300kv", "prop_5x43x3"))
	var five: PropellerMesh = airframe.propeller_meshes["M1"]
	var five_radius := five.radius_m
	var five_blades := five.blade_count

	airframe.rebuild(_build(catalog, "frame_7in_long_range", "motor_2807_1300kv", "prop_7x35x2"))
	var seven: PropellerMesh = airframe.propeller_meshes["M1"]
	var seven_radius := seven.radius_m
	var seven_blades := seven.blade_count

	var count := airframe.propeller_meshes.size()
	airframe.free()

	return TestResult.new(
		"swapping a 3-blade 5\" for a 2-blade 7\" changes all four props",
		count == 4 and seven_radius > five_radius * 1.3 and five_blades == 3 and seven_blades == 2,
		"%d props: %d-blade r=%.4f m -> %d-blade r=%.4f m" % [
			count, five_blades, five_radius, seven_blades, seven_radius]
	)


## Incompatibility has to be visible in the geometry, not only in a warnings panel
## (labs-and-sim.md §2.2: "the render is the engineering check"). A 7" prop on a 3" frame must
## produce discs that actually intersect — and the text warning must still fire, because warn-
## never-block means the build stays selectable and the consequence is the lesson.
static func _test_an_oversized_prop_overlaps_the_airframe(catalog: PartsCatalog) -> TestResult:
	var legal := _build(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3")
	var oversized := _build(catalog, "frame_3in_toothpick", "motor_2207_1960kv", "prop_7x4x3")

	var airframe := AirframeModel.new()
	airframe.rebuild(legal)
	var legal_gap := airframe.adjacent_prop_gap_m()
	airframe.rebuild(oversized)
	var oversized_gap := airframe.adjacent_prop_gap_m()
	airframe.free()

	var warned := false
	for warning in oversized.warnings():
		if warning.contains("strike the frame"):
			warned = true

	return TestResult.new(
		"an oversized prop intersects the airframe on screen, and still says so in words",
		legal_gap > 0.0 and oversized_gap < 0.0 and warned,
		"5\" prop on a 5\" frame: %+.4f m clearance; 7\" prop on a 3\" frame: %+.4f m; warning fired: %s" % [
			legal_gap, oversized_gap, warned]
	)


static func _build(catalog: PartsCatalog, frame_id: String, motor_id: String, prop_id: String) -> Build:
	return Build.from_ids(catalog, frame_id, motor_id, prop_id, ReferenceBuild.BATTERY_ID)


static func _test_motors_hang_off_the_arm_tips(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, "frame_7in_long_range", "motor_2807_1300kv", "prop_7x4x3")
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	var problems: Array[String] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		var pad: Node3D = airframe.frame_model.arm_tips[motor_name]
		var motor: Node3D = airframe.motor_meshes[motor_name]

		# Structural: the motor must be UNDER the pad, so a frame rebuild cannot orphan it.
		if not airframe.frame_model.is_ancestor_of(motor) or motor.get_parent() != pad:
			problems.append("%s is not parented on its pad" % motor_name)

		# Positional, measured through the actual transform chain rather than read off a field:
		# horizontally the motor must land exactly on the layout position, and vertically it
		# must sit above the pad rather than inside the arm.
		var world: Transform3D = airframe.transform * _chain_to(airframe, motor)
		var expected := MotorLayout.motor_position(motor_name, build.arm_m)
		if absf(world.origin.x - expected.x) > EPS or absf(world.origin.z - expected.z) > EPS:
			problems.append("%s at %s, expected x/z of %s" % [motor_name, world.origin, expected])
		if world.origin.y <= expected.y:
			problems.append("%s sits at or below the arm (y=%.4f)" % [motor_name, world.origin.y])

	var motor_count := airframe.motor_meshes.size()
	airframe.free()

	return TestResult.new(
		"all four motors hang off the frame's own arm-tip pads",
		problems.is_empty() and motor_count == 4,
		"%d motors, %s" % [motor_count, "all mounted" if problems.is_empty() else str(problems)]
	)


## Rebuilding with a different frame must move the motors with the arms and leave nothing of
## the old build behind — the failure being four motors at the 5" positions and four more at
## the 7" positions, which reads as a crowded airframe rather than as a bug.
static func _test_a_frame_change_takes_its_motors_with_it(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_3in_toothpick", "motor_1404_3800kv", "prop_3x3x3"))
	var old_motor: Node3D = airframe.motor_meshes["M1"]
	var small_reach := _furthest_motor(airframe)

	var large := _build(catalog, "frame_7in_long_range", "motor_1404_3800kv", "prop_3x3x3")
	airframe.rebuild(large)
	var large_reach := _furthest_motor(airframe)
	# Detachment, not is_instance_valid(): FrameModel releases the pads with queue_free(), so
	# the old nodes are reclaimed at the end of the frame rather than inside this call. What
	# has to be true the moment rebuild() returns is that nothing from the previous build is
	# still IN the airframe — that is what would render, and what a stale-geometry bug looks
	# like on screen.
	var old_still_inside := airframe.is_ancestor_of(old_motor)
	var count := airframe.motor_meshes.size()

	airframe.free()

	var passed := count == 4 and large_reach > small_reach + 0.05 and not old_still_inside

	return TestResult.new(
		"a frame change moves the motors and detaches the old ones",
		passed,
		"motor reach %.4f -> %.4f m, %d motors, old M1 still in the airframe: %s" % [
			small_reach, large_reach, count, old_still_inside]
	)


## Only the motor changes. The frame is held still, so any change in the airframe's geometry
## has to have come from the motor selection.
static func _test_motor_choice_changes_motor_size(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_freestyle", "motor_1404_3800kv", "prop_5x43x3"))
	var small: float = (airframe.motor_meshes["M1"] as MotorMesh).bell_radius_m
	var small_height: float = (airframe.motor_meshes["M1"] as MotorMesh).total_height_m

	airframe.rebuild(_build(catalog, "frame_5in_freestyle", "motor_2807_1300kv", "prop_5x43x3"))
	var large: float = (airframe.motor_meshes["M1"] as MotorMesh).bell_radius_m
	var large_height: float = (airframe.motor_meshes["M1"] as MotorMesh).total_height_m

	airframe.free()

	return TestResult.new(
		"swapping a 1404 for a 2807 changes the motors on the same frame",
		large > small * 1.5 and large_height > small_height,
		"bell radius %.4f -> %.4f m, motor height %.4f -> %.4f m" % [
			small, large, small_height, large_height]
	)


static func _furthest_motor(airframe: AirframeModel) -> float:
	var furthest := 0.0
	for motor_name in airframe.motor_meshes:
		var motor: Node3D = airframe.motor_meshes[motor_name]
		var origin: Vector3 = _chain_to(airframe, motor).origin
		furthest = maxf(furthest, Vector2(origin.x, origin.z).length())
	return furthest


## Composes a descendant's transform up to `root`, since these nodes are never in a real tree
## in the headless suite and global_transform would be meaningless.
static func _chain_to(root: Node, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var walker: Node = node
	while walker != null and walker != root:
		var spatial := walker as Node3D
		if spatial != null:
			transform = spatial.transform * transform
		walker = walker.get_parent()
	return transform
