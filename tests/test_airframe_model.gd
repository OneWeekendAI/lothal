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
	results.append(_test_the_pack_sits_on_the_top_plate(catalog))
	results.append(_test_a_pack_change_changes_the_block(catalog))
	results.append(_test_a_frame_change_takes_the_pack_with_it(catalog))
	results.append(_test_the_overhang_is_measured_off_the_geometry(catalog))
	results.append(_test_a_pack_that_reaches_the_props_says_so(catalog))

	return results


## The fit check and the picture are the same geometry (labs-and-sim.md §2.2), so the overhang is
## measured off the drawn plate and the drawn pack rather than recomputed from arm_mm and a ratio —
## the same posture as adjacent_prop_gap_m().
##
## Both numbers below were worked out by hand from the two spec sheets before the code was run,
## which is what makes this test able to fail. Asserting the reference build's overhang is merely
## some number, or non-negative, would prove nothing at all:
##
##   a 2S 450 (63 x 15.5 mm) on a 10" frame (215 mm arm -> a 118.25 mm plate)
##     fore/aft (63 - 118.25) / 2 = -27.625 mm      lateral (15.5 - 118.25) / 2 = -51.375 mm
##
##   a 6S 4000 Li-ion (78 x 64 mm) on a 3" toothpick (75 mm arm -> a 41.25 mm plate)
##     fore/aft (78 - 41.25) / 2 = +18.375 mm       lateral (64 - 41.25) / 2 = +11.375 mm
##
## Negative clears, positive hangs over the edge.
static func _test_the_overhang_is_measured_off_the_geometry(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_10in_long_range", "motor_2807_1300kv",
		"prop_5x43x3", "battery_2s_450"))
	var clears := airframe.battery_overhang_m()

	airframe.rebuild(Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion"))
	var hangs := airframe.battery_overhang_m()
	airframe.free()

	var passed := absf(clears["fore_aft"] - -0.027625) < 1e-6 \
		and absf(clears["lateral"] - -0.051375) < 1e-6 \
		and absf(hangs["fore_aft"] - 0.018375) < 1e-6 \
		and absf(hangs["lateral"] - 0.011375) < 1e-6

	return TestResult.new(
		"the pack's overhang past the centre plate is measured, and reads both ways",
		passed,
		"2S 450 on a 10\": %+.1f mm fore/aft, %+.1f mm lateral; 6S 4000 Li-ion on a 3\": %+.1f mm fore/aft, %+.1f mm lateral" % [
			clears["fore_aft"] * 1000.0, clears["lateral"] * 1000.0,
			hangs["fore_aft"] * 1000.0, hangs["lateral"] * 1000.0]
	)


## Warn, never block. A 6S Li-ion on a 3" toothpick is exactly the curiosity this workbench exists
## for — seeing the pack dwarf the airframe IS the answer — so the build stays selectable and the
## consequence is the lesson, the same bargain an oversized prop already strikes.
##
## Hand-computed again, from the plan view. A 3" toothpick puts its motors at 75 * cos45 = 53.03 mm
## on each axis and its 3" props sweep a 38.1 mm radius. The 6S pack's footprint reaches 32 mm
## sideways and 39 mm fore/aft, so the nearest corner of the pack sits sqrt(21.03^2 + 14.03^2) =
## 25.3 mm from the hub — 12.8 mm INSIDE a disc that wants 38.1 mm.
##
## The reference build clears by 9.0 mm on the same arithmetic (77.78 mm arms, a 63.5 mm radius, a
## pack reaching 17.5 x 37.5 mm), and must raise no warning at all: it overhangs its plate by
## 7.25 mm fore and aft, which is what every real 5" build does and is why a fore/aft overhang is
## reported rather than warned about. Only being WIDER than the plate is a warning.
static func _test_a_pack_that_reaches_the_props_says_so(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	var reference_clearance := airframe.battery_prop_clearance_m()
	var reference_warnings := airframe.battery_fit_warnings()

	airframe.rebuild(Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion"))
	var absurd_clearance := airframe.battery_prop_clearance_m()
	var absurd_warnings := airframe.battery_fit_warnings()
	airframe.free()

	var warned_about_props := false
	var warned_about_width := false
	for warning in absurd_warnings:
		if warning.contains("propeller"):
			warned_about_props = true
		if warning.contains("wider"):
			warned_about_width = true

	var passed := absf(reference_clearance - 0.00900) < 5e-5 and reference_warnings.is_empty() \
		and absf(absurd_clearance - -0.01282) < 5e-5 \
		and warned_about_props and warned_about_width

	return TestResult.new(
		"a pack big enough to reach the props says so, and the reference build says nothing",
		passed,
		"reference build clears the discs by %+.1f mm with %d warnings; 6S 4000 Li-ion on a 3\" toothpick is %+.1f mm and says %s" % [
			reference_clearance * 1000.0, reference_warnings.size(),
			absurd_clearance * 1000.0, str(absurd_warnings)]
	)


## With nothing chosen, the pack is where a 5" pack goes: on the top centre plate, lying along the
## aircraft's forward axis. It gets there through the frame's top strap MOUNT POINT rather than
## through a line that names the top plate — see TestBatteryMount for the underside and the
## fore/aft slide — and what is asserted here is the DEFAULT, which has not changed.
##
## The seat is the mount's, not the airframe's: the plate's height is FrameModel's (and the
## standoff tweak moves it), so an airframe that placed the pack at its own computed height would
## be a second copy of the plate stack's arithmetic, and it would drift the first time somebody
## wound the standoffs.
static func _test_the_pack_sits_on_the_top_plate(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3")
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	var pack := airframe.battery_mesh
	var problems: Array[String] = []

	if pack == null or not airframe.frame_model.is_ancestor_of(pack):
		airframe.free()
		return TestResult.new("the pack is mounted on the frame's top centre plate", false,
			"there is no pack on the airframe")

	if airframe.battery_mount == null or airframe.battery_mount.id != "strap_top":
		problems.append("the pack defaulted to %s rather than the top strap mount" % [
			"nothing" if airframe.battery_mount == null else airframe.battery_mount.id])

	# Its underside rests ON the plate's top face, measured through the transform chain rather than
	# read off a field: a pack floating 2 mm above the plate, or sunk into it, is exactly the class
	# of error that looks perfect in a screenshot.
	var pack_y: float = _chain_to(airframe, pack).origin.y
	var underside := pack_y - pack.size_m.y * 0.5
	var plate_face: float = airframe.frame_model.plate_top_face_m()
	if absf(underside - plate_face) > EPS:
		problems.append("the pack's underside is at %.4f, the plate's face at %.4f" % [
			underside, plate_face])

	# Along the aircraft, not across it: nose is -Z, and the published length is the long axis.
	if pack.size_m.z <= pack.size_m.x:
		problems.append("the pack is not lying fore-and-aft (%s)" % pack.size_m)

	airframe.free()

	return TestResult.new(
		"with nothing chosen, the pack is on the top strap mount, lying fore-and-aft",
		problems.is_empty(),
		"underside %.4f m on a plate face at %.4f m, %s" % [
			underside, plate_face, "seated" if problems.is_empty() else str(problems)]
	)


## Change the pack and the block on the aircraft changes size — the acceptance criterion, asserted
## on the assembled airframe rather than on a BatteryMesh on its own. Frame, motor and prop are
## held still, so anything that moved came from the pack rail.
static func _test_a_pack_change_changes_the_block(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_2s_450"))
	var small: Vector3 = airframe.battery_mesh.size_m
	var small_cells: int = airframe.battery_mesh.cell_count
	var small_y: float = _chain_to(airframe, airframe.battery_mesh).origin.y

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_6s_4000_liion"))
	var large: Vector3 = airframe.battery_mesh.size_m
	var large_cells: int = airframe.battery_mesh.cell_count
	var large_y: float = _chain_to(airframe, airframe.battery_mesh).origin.y

	airframe.free()

	# A taller pack has to sit higher, because it is seated on its underside rather than centred:
	# a pack that grew downward would be inside the plate it is strapped to.
	var passed := large.x > small.x and large.y > small.y and large.z > small.z \
		and small_cells == 2 and large_cells == 6 and large_y > small_y

	return TestResult.new(
		"choosing a different pack changes the block on the aircraft, and re-seats it",
		passed,
		"2S 450 %s (%d cells) at y=%.4f -> 6S 4000 Li-ion %s (%d cells) at y=%.4f" % [
			small, small_cells, small_y, large, large_cells, large_y]
	)


## A frame change replaces the plate the pack is strapped to, so it must take the pack with it and
## leave nothing of the old one behind. The failure being two packs on one airframe.
##
## The second half is the one that proves the pack FOLLOWS the plate rather than sitting at a
## height that happens to match. A frame change does not move the plate face — the standoff gap is
## derived from plate thickness, so every frame's top face is at the same 12.5 mm — so a pack
## nailed to a constant would pass a frame swap and fail nobody. Winding the standoffs to their
## limit does move it, by a different amount for each frame, and the pack has to rise by exactly
## that much.
static func _test_a_frame_change_takes_the_pack_with_it(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_3in_toothpick", "motor_1404_3800kv", "prop_3x3x3"))
	var old_pack: Node3D = airframe.battery_mesh
	var small_side: float = airframe.frame_model.plate_side_m

	var large := _build(catalog, "frame_10in_long_range", "motor_2807_1300kv", "prop_5x43x3")
	airframe.rebuild(large)
	var old_still_inside := airframe.is_ancestor_of(old_pack)
	var underside := _pack_underside(airframe)
	var face: float = airframe.frame_model.plate_top_face_m()
	var large_side: float = airframe.frame_model.plate_side_m
	var packs_drawn := 0
	for node in airframe.frame_model.get_children():
		if node is BatteryMesh:
			packs_drawn += 1

	# Same build, standoffs wound to the limit this frame allows.
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.PLATE_GAP, AssemblyTweaks.limits(large)[AssemblyTweaks.PLATE_GAP]["max"])
	airframe.rebuild(large, tweaks)
	var raised_face: float = airframe.frame_model.plate_top_face_m()
	var raised_underside := _pack_underside(airframe)

	airframe.free()

	var followed := absf(raised_underside - raised_face) < EPS and raised_face > face + EPS
	var passed := not old_still_inside and packs_drawn == 1 \
		and absf(underside - face) < EPS and large_side > small_side and followed

	return TestResult.new(
		"a frame change re-seats the pack, and the pack rides the standoffs up with the plate",
		passed,
		"plate side %.4f -> %.4f m, %d packs, old one still inside: %s; standoffs to the limit moved the face %.4f -> %.4f m and the pack's underside %.4f -> %.4f m" % [
			small_side, large_side, packs_drawn, old_still_inside,
			face, raised_face, underside, raised_underside]
	)


static func _pack_underside(airframe: AirframeModel) -> float:
	var pack: BatteryMesh = airframe.battery_mesh
	return _chain_to(airframe, pack).origin.y - pack.size_m.y * 0.5


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
