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

	return results


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
