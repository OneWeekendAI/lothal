class_name TestMotorMesh
extends RefCounted
## MotorMesh is procedural geometry generated from a motor part's real stator dimensions,
## for the same reason FrameModel is (read its header): a 1404 and a 2207 must come out
## visibly different sizes because 14x4 and 22x7 are different numbers, not because two
## assets were authored or one asset was scaled.
##
## The test that earns its place here is the 2207-versus-2306 one. A fixed mesh under a
## uniform scale factor passes every "bigger motor is bigger" check ever written. It cannot
## pass a check that asks for a WIDER bell and a SHORTER one at the same time, which is
## exactly what those two real motors are — 22x7 against 23x6.

const EPS := 0.0001

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_bell_derives_from_stator_diameter(catalog))
	results.append(_test_diameter_and_height_move_independently(catalog))
	results.append(_test_shaft_stands_above_the_bell(catalog))
	results.append(_test_rebuild_no_stale_children(catalog))
	results.append(_test_missing_specs_do_not_crash())

	return results


## Measured off the generated mesh, never re-read from the JSON — re-reading stator_diameter_mm
## and comparing it to itself is the test that cannot fail.
static func _bell_radius(mesh: MotorMesh) -> float:
	var bell := mesh.get_node("Bell") as MeshInstance3D
	return (bell.mesh as CylinderMesh).top_radius


static func _generated_height(mesh: MotorMesh) -> float:
	# The whole motor's extent, walked out of the children rather than trusted from a field.
	var top := -INF
	var bottom := INF
	for child in mesh.get_children():
		var instance := child as MeshInstance3D
		if instance == null:
			continue
		var aabb := instance.mesh.get_aabb()
		top = maxf(top, instance.position.y + aabb.end.y)
		bottom = minf(bottom, instance.position.y + aabb.position.y)
	return top - bottom


static func _test_bell_derives_from_stator_diameter(catalog: PartsCatalog) -> TestResult:
	var small := MotorMesh.new()
	small.rebuild(catalog.get_part("motor_1404_3800kv"))
	var large := MotorMesh.new()
	large.rebuild(catalog.get_part("motor_2207_1960kv"))

	var small_radius := _bell_radius(small)
	var large_radius := _bell_radius(large)
	var small_height := _generated_height(small)
	var large_height := _generated_height(large)

	small.free()
	large.free()

	# 14 mm vs 22 mm of stator is a 1.57x step; require most of it to actually reach the mesh,
	# rather than a token difference that would let a nearly-fixed size through.
	var radius_ratio := large_radius / small_radius
	var passed := radius_ratio > 1.4 and large_height > small_height + 0.002

	return TestResult.new(
		"a 2207's generated bell is visibly larger than a 1404's",
		passed,
		"bell radius %.4f -> %.4f m (ratio %.2f), overall height %.4f -> %.4f m" % [
			small_radius, large_radius, radius_ratio, small_height, large_height]
	)


## The one a scaled stand-in cannot pass. The 2207 is 22 mm wide and 7 mm tall; the 2306 is
## 23 mm wide and 6 mm tall. Wider AND shorter is not reachable by any uniform scale of a
## single authored mesh, so this pins the geometry to the two specs separately.
static func _test_diameter_and_height_move_independently(catalog: PartsCatalog) -> TestResult:
	var tall := MotorMesh.new()
	tall.rebuild(catalog.get_part("motor_2207_1960kv"))
	var wide := MotorMesh.new()
	wide.rebuild(catalog.get_part("motor_2306_2450kv"))

	var tall_radius := _bell_radius(tall)
	var wide_radius := _bell_radius(wide)
	var tall_height := _generated_height(tall)
	var wide_height := _generated_height(wide)

	tall.free()
	wide.free()

	var passed := wide_radius > tall_radius + EPS and wide_height < tall_height - EPS

	return TestResult.new(
		"bell diameter and bell height follow their own specs, not one scale factor",
		passed,
		"2207 (22x7): r=%.4f h=%.4f   2306 (23x6): r=%.4f h=%.4f" % [
			tall_radius, tall_height, wide_radius, wide_height]
	)


## The prop bolts to the shaft, above the bell. If the shaft did not clear the bell there
## would be nowhere to put a propeller that was not inside the motor.
static func _test_shaft_stands_above_the_bell(catalog: PartsCatalog) -> TestResult:
	var mesh := MotorMesh.new()
	mesh.rebuild(catalog.get_part("motor_2207_1960kv"))

	var bell := mesh.get_node("Bell") as MeshInstance3D
	var shaft := mesh.get_node("Shaft") as MeshInstance3D
	var bell_top: float = bell.position.y + (bell.mesh as CylinderMesh).height * 0.5
	var shaft_top: float = shaft.position.y + (shaft.mesh as CylinderMesh).height * 0.5
	var shaft_radius: float = (shaft.mesh as CylinderMesh).top_radius
	var bell_radius: float = (bell.mesh as CylinderMesh).top_radius
	var mount := mesh.prop_mount_height_m

	mesh.free()

	var passed := shaft_top > bell_top + EPS \
		and shaft_radius < bell_radius * 0.3 \
		and mount >= bell_top and mount <= shaft_top

	return TestResult.new(
		"a visible shaft stands above the bell, and the prop mount sits on it",
		passed,
		"bell top %.4f m, shaft top %.4f m, shaft/bell radius %.2f, prop mount %.4f m" % [
			bell_top, shaft_top, shaft_radius / bell_radius, mount]
	)


static func _test_rebuild_no_stale_children(catalog: PartsCatalog) -> TestResult:
	var mesh := MotorMesh.new()
	mesh.rebuild(catalog.get_part("motor_1404_3800kv"))
	var first_count := mesh.get_child_count()
	var old_bell := mesh.get_node("Bell") as MeshInstance3D
	var small_radius := _bell_radius(mesh)

	mesh.rebuild(catalog.get_part("motor_2807_1300kv"))
	var second_count := mesh.get_child_count()
	var old_still_parented := old_bell.get_parent() == mesh
	var new_radius := _bell_radius(mesh)

	mesh.free()

	var passed := first_count == second_count and not old_still_parented \
		and new_radius > small_radius + EPS

	return TestResult.new(
		"rebuilding a motor leaves no geometry from the previous one",
		passed,
		"child count %d -> %d, old bell still parented: %s, bell radius %.4f -> %.4f m" % [
			first_count, second_count, old_still_parented, small_radius, new_radius]
	)


## A contributor's half-finished motor must render as a motor rather than crash Lab. Same
## precedent as FrameModel's missing-catalog-block case.
static func _test_missing_specs_do_not_crash() -> TestResult:
	var mesh := MotorMesh.new()
	mesh.rebuild({"part_id": "motor_test_bare", "name": "Bare", "category": "motor", "mass_g": 20.0})

	var height := _generated_height(mesh)
	var children := mesh.get_child_count()
	mesh.free()

	return TestResult.new(
		"a motor with no specs still produces geometry instead of crashing",
		children >= 3 and height > 0.0,
		"%d children, %.4f m tall" % [children, height]
	)
