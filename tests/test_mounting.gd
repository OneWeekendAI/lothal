class_name TestMounting
extends RefCounted
## How a propeller is actually bolted to a motor: the shaft standing above the bell, the
## adapter it seats on, the prop, and the nut on top.
##
## The bug these tests exist to catch is one no numeric test in the project could see and no
## screenshot at Lab's fixed camera distance could either: the propeller was drawn at a height
## the motor reported, but that height was small enough that the blade ROOTS — which dip well
## below the hub's centreline, because a root is steeply feathered and the blade has chord —
## sat down inside the bell. The prop and the motor read as one merged object, which is exactly
## the opposite of what Lab is for: if the picture is the engineering check (labs-and-sim.md
## §2.2), then hardware that cannot physically fit must not appear to fit.
##
## So these checks measure the real thing: the lowest point of a blade's generated vertices,
## in the motor's own space, against the top face of the bell. Not the prop's origin — the
## origin is a point in the middle of the hub and it can clear the bell by a millimetre while
## the blade behind it is buried.
##
## Every motor in the catalog is checked, each against the propeller its OWN thrust_test names,
## which is the catalog's own statement about what this motor is flown on. That covers the range
## from a 0802 on a 1.6" quad-blade to a 2807 on a 7" — a two-order-of-magnitude spread in which
## a single hand-tuned mounting constant cannot possibly be right everywhere, which is the
## reason the height is derived rather than authored.

## A gap smaller than this would not be visible on screen at any camera distance Lab uses, and
## "visible daylight" is the acceptance criterion.
const MIN_VISIBLE_GAP_M := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_daylight_above_every_bell(catalog))
	results.append(_test_the_seat_is_derived_from_the_motor(catalog))
	results.append(_test_the_adapter_hardware_is_there(catalog))
	results.append(_test_a_nut_sits_above_the_hub(catalog))
	results.append(_test_the_shaft_reaches_the_nut(catalog))

	return results


# ---------------------------------------------------------------------------
# Reading the assembled mount back
# ---------------------------------------------------------------------------

## Top face of the bell, in the motor's own space.
static func _bell_top_m(motor: MotorMesh) -> float:
	var bell := motor.get_node("Bell") as MeshInstance3D
	return bell.position.y + (bell.mesh as CylinderMesh).height * 0.5


## The lowest point of any blade, in the MOTOR's space. Blades are yawed about the vertical
## about the hub, and a yaw leaves Y alone, so a blade mesh's own AABB gives the vertical
## extent regardless of which blade it is.
static func _lowest_blade_point_m(motor: MotorMesh, prop: PropellerMesh) -> float:
	var lowest := INF
	for child in prop.get_children():
		if not String(child.name).begins_with("Blade_"):
			continue
		var blade := child as MeshInstance3D
		lowest = minf(lowest, prop.position.y + blade.mesh.get_aabb().position.y)
	return lowest


static func _highest_prop_point_m(prop: PropellerMesh) -> float:
	var highest := -INF
	for child in prop.get_children():
		var mesh_child := child as MeshInstance3D
		if mesh_child == null or mesh_child.mesh == null:
			continue
		var aabb: AABB = mesh_child.mesh.get_aabb()
		highest = maxf(highest, prop.position.y + aabb.position.y + aabb.size.y)
	return highest


## Every motor paired with the prop its own thrust_test was measured on.
static func _catalog_pairs(catalog: PartsCatalog) -> Array:
	var pairs: Array = []
	for motor in catalog.list_category("motor"):
		pairs.append([motor, catalog.get_part(String(motor["thrust_test"]["prop_id"]))])
	return pairs


static func _assembled(catalog: PartsCatalog, motor_id: String, prop_id: String) -> AirframeModel:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(
		catalog, ReferenceBuild.FRAME_ID, motor_id, prop_id, ReferenceBuild.BATTERY_ID))
	return airframe


# ---------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------

## The acceptance criterion, measured: at every motor in the catalog, on its own prop, there is
## daylight between the top of the bell and the underside of the blade roots.
static func _test_daylight_above_every_bell(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	var tightest := INF
	var tightest_where := ""

	for pair in _catalog_pairs(catalog):
		var motor_part: Dictionary = pair[0]
		var prop_part: Dictionary = pair[1]
		var airframe := _assembled(catalog, motor_part["part_id"], prop_part["part_id"])

		for motor_name in MotorLayout.MOTOR_NAMES:
			var motor: MotorMesh = airframe.motor_meshes[motor_name]
			var prop: PropellerMesh = airframe.propeller_meshes[motor_name]
			var gap := _lowest_blade_point_m(motor, prop) - _bell_top_m(motor)
			checked += 1
			if gap < tightest:
				tightest = gap
				tightest_where = "%s on %s" % [motor_part["part_id"], prop_part["part_id"]]
			if gap < MIN_VISIBLE_GAP_M:
				problems.append("%s on %s: %s blade roots are %.4f m above the bell" % [
					motor_part["part_id"], prop_part["part_id"], motor_name, gap])
		airframe.free()

	return TestResult.new(
		"every motor in the catalog carries its prop clear of the bell, blade roots included",
		problems.is_empty() and checked >= 40,
		"%d mounts checked, tightest %.4f m (%s)%s" % [
			checked, tightest, tightest_where,
			"" if problems.is_empty() else " — " + str(problems.slice(0, 3))]
	)


## The seat height has to be a consequence of the motor's published dimensions, not a constant.
## Two motors of the SAME stator diameter and different stator heights must seat their props at
## different heights, and the taller stator must be the higher of the two — that is the whole
## content of "derived from stator_height_mm".
static func _test_the_seat_is_derived_from_the_motor(catalog: PartsCatalog) -> TestResult:
	var short_motor := MotorMesh.new()
	var tall_motor := MotorMesh.new()
	# 2207 and 2306 share nothing but their rough class: 22 mm x 7 mm against 23 mm x 6 mm.
	# 2306 is the WIDER and SHORTER of the two, so a seat height driven by any single scale
	# factor on stator diameter would put the 2306's prop higher. Stator HEIGHT must decide it.
	short_motor.rebuild(catalog.get_part("motor_2306_2450kv"))
	tall_motor.rebuild(catalog.get_part("motor_2207_1960kv"))

	var short_seat := short_motor.prop_mount_height_m
	var tall_seat := tall_motor.prop_mount_height_m
	var short_stator: float = float(catalog.get_part("motor_2306_2450kv")["specs"]["stator_height_mm"])
	var tall_stator: float = float(catalog.get_part("motor_2207_1960kv")["specs"]["stator_height_mm"])

	short_motor.free()
	tall_motor.free()

	return TestResult.new(
		"the prop seat is derived from stator height, so a taller stator seats its prop higher",
		tall_seat > short_seat and short_stator < tall_stator,
		"2306 (%.0f mm stator) seats at %.4f m, 2207 (%.0f mm stator) at %.4f m" % [
			short_stator, short_seat, tall_stator, tall_seat]
	)


## The daylight is not empty space: it is occupied by the adapter the prop actually seats on.
## A gap with nothing in it would be a prop floating above a motor, which is a different lie
## from the one this slice fixes.
static func _test_the_adapter_hardware_is_there(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	for motor_id in ["motor_0802_19000kv", "motor_2207_1960kv", "motor_2807_1300kv"]:
		var motor := MotorMesh.new()
		motor.rebuild(catalog.get_part(motor_id))

		var adapter := motor.get_node_or_null("Adapter") as MeshInstance3D
		if adapter == null:
			problems.append("%s has no adapter above the bell" % motor_id)
			motor.free()
			continue

		var mesh := adapter.mesh as CylinderMesh
		var bell_top := _bell_top_m(motor)
		var adapter_bottom: float = adapter.position.y - mesh.height * 0.5
		# It sits ON the bell, spanning the gap up to the seat, and it is wider than the shaft
		# (an adapter that is only as wide as the shaft is a shaft).
		if absf(adapter_bottom - bell_top) > 0.0001:
			problems.append("%s's adapter starts at %.4f, bell top is %.4f" % [
				motor_id, adapter_bottom, bell_top])
		if absf(adapter.position.y + mesh.height * 0.5 - motor.prop_mount_height_m) > 0.0001:
			problems.append("%s's adapter does not reach the prop seat" % motor_id)
		var shaft_radius: float = ((motor.get_node("Shaft") as MeshInstance3D).mesh as CylinderMesh).top_radius
		if mesh.top_radius <= shaft_radius * 1.2:
			problems.append("%s's adapter is no wider than its shaft" % motor_id)
		motor.free()

	return TestResult.new(
		"the daylight above the bell is occupied by a prop adapter, not empty",
		problems.is_empty(),
		"3 motors checked, %s" % ("all fitted" if problems.is_empty() else str(problems))
	)


## The other half of the acceptance criterion: a nut on top, above everything the prop occupies.
static func _test_a_nut_sits_above_the_hub(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	for pair in _catalog_pairs(catalog):
		var motor_id: String = pair[0]["part_id"]
		var prop_id: String = pair[1]["part_id"]
		var airframe := _assembled(catalog, motor_id, prop_id)
		var motor: MotorMesh = airframe.motor_meshes["M1"]
		var prop: PropellerMesh = airframe.propeller_meshes["M1"]

		var nut := motor.get_node_or_null("Nut") as MeshInstance3D
		if nut == null:
			problems.append("%s: no nut" % motor_id)
			airframe.free()
			continue

		var nut_mesh := nut.mesh as CylinderMesh
		var nut_bottom: float = nut.position.y - nut_mesh.height * 0.5
		var hub_top: float = prop.position.y + prop.topside_m
		if nut_bottom < hub_top - 0.0001:
			problems.append("%s on %s: nut bottom %.4f is below the prop's top %.4f" % [
				motor_id, prop_id, nut_bottom, hub_top])
		var shaft_radius: float = ((motor.get_node("Shaft") as MeshInstance3D).mesh as CylinderMesh).top_radius
		if maxf(nut_mesh.top_radius, nut_mesh.bottom_radius) <= shaft_radius:
			problems.append("%s: nut is no wider than the shaft it threads onto" % motor_id)
		airframe.free()

	return TestResult.new(
		"a prop nut sits above the hub on every motor in the catalog",
		problems.is_empty(),
		"12 motors on their own props, %s" % ("all nutted" if problems.is_empty() else str(problems))
	)


## The shaft has to be long enough for what is stacked on it. A nut floating above the end of
## the thread is the same class of error as a prop inside the bell, and just as invisible at
## Lab's camera distance.
static func _test_the_shaft_reaches_the_nut(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var tightest := INF
	for pair in _catalog_pairs(catalog):
		var motor_id: String = pair[0]["part_id"]
		var prop_id: String = pair[1]["part_id"]
		var airframe := _assembled(catalog, motor_id, prop_id)
		var motor: MotorMesh = airframe.motor_meshes["M1"]
		var prop: PropellerMesh = airframe.propeller_meshes["M1"]

		var shaft := motor.get_node("Shaft") as MeshInstance3D
		var shaft_top: float = shaft.position.y + (shaft.mesh as CylinderMesh).height * 0.5
		var nut := motor.get_node_or_null("Nut") as MeshInstance3D
		var stack_top: float = _highest_prop_point_m(prop)
		if nut != null:
			stack_top = maxf(stack_top, nut.position.y + (nut.mesh as CylinderMesh).height * 0.5)

		var margin := shaft_top - stack_top
		tightest = minf(tightest, margin)
		if margin < -0.0001:
			problems.append("%s on %s: the stack tops out %.4f m above the shaft" % [
				motor_id, prop_id, -margin])
		# And the motor must report that whole extent, or Lab's framing does not know how tall
		# the build is.
		if motor.total_height_m < shaft_top - 0.0001:
			problems.append("%s: total_height_m %.4f is below its own shaft top %.4f" % [
				motor_id, motor.total_height_m, shaft_top])
		airframe.free()

	return TestResult.new(
		"the shaft runs the full height of what is bolted to it",
		problems.is_empty(),
		"12 motors on their own props, tightest shaft margin %.4f m%s" % [
			tightest, "" if problems.is_empty() else " — " + str(problems.slice(0, 3))]
	)
