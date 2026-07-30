class_name TestBatteryMesh
extends RefCounted
## The pack as generated geometry. Same rule as FrameModel, MotorMesh and PropellerMesh — read
## FrameModel's header for why nothing in this project is a fixed asset — with one difference that
## is the whole reason this slice exists.
##
## The other three generators are the ONLY answer to their part's size. This one is not: the mass
## model has had an opinion about how big the pack is since day 2, because the inertia tensor needs
## a box. So the assertion that matters most here is not "the block is 75 mm long", it is "the block
## is the same 75 mm the physics is integrating" — tested by comparing against
## Build.battery_size_of() rather than against a literal. A BatteryMesh that drew the right size
## from its own copy of the catalog would pass every dimension check in this file and still be the
## second source of truth the slice was written to prevent.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_the_block_is_the_size_the_catalog_publishes(catalog))
	results.append(_the_drawn_size_is_the_size_the_physics_uses(catalog))
	results.append(_a_different_pack_is_a_different_block(catalog))
	results.append(_the_cell_division_is_the_pack_s_cell_count(catalog))
	results.append(_chemistry_changes_what_the_cells_are(catalog))
	results.append(_leads_come_out_of_one_end(catalog))
	results.append(_a_pack_with_no_dimensions_still_draws_something(catalog))
	results.append(_lab_reports_the_fit_of_the_pack_it_just_fitted(catalog))

	return results


## The measurement reaches the screen. Everything above proves AirframeModel can measure an
## overhang; this proves Lab shows the one belonging to the build on screen, through the same
## single handler that redraws the geometry — so a panel that described the previous pack would
## fail here rather than in front of a builder.
##
## Driven through the rails, not by calling render() with a hand-made argument: the rail is how a
## pack is really chosen, and the wiring between the two is the only thing left to get wrong.
static func _lab_reports_the_fit_of_the_pack_it_just_fitted(catalog: PartsCatalog) -> TestResult:
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	# The reference build fits, and says so with no warning at all.
	var reference_warning: bool = lab.assembly_panel.fit_warning_text() != ""
	var reference_lateral: String = lab.assembly_panel.fit_row_text("lateral")

	lab.picker.select_id("frame_3in_toothpick")
	lab.propeller_picker.select_id("prop_3x3x3")
	lab.battery_picker.select_id("battery_6s_4000_liion")
	var absurd_warning: String = lab.assembly_panel.fit_warning_text()
	var absurd_lateral: String = lab.assembly_panel.fit_row_text("lateral")

	lab.free()

	return TestResult.new(
		"Lab reports the fit of the pack it has just fitted, and warns when it does not fit",
		not reference_warning and reference_lateral.contains("clear")
			and absurd_warning.contains("propeller") and absurd_lateral.contains("over"),
		"reference build: lateral \"%s\", no warning: %s; 6S 4000 Li-ion on a 3\" toothpick: lateral \"%s\", warning \"%s\"" % [
			reference_lateral, not reference_warning, absurd_lateral,
			absurd_warning.replace("\n", " / ")]
	)


## Length along the aircraft's forward axis (Z, nose = -Z), width across it, height up. Measured
## off the generated geometry's own bounds rather than off the reported field, so a mesh that
## reports one size and draws another is caught here rather than on screen.
static func _the_block_is_the_size_the_catalog_publishes(catalog: PartsCatalog) -> TestResult:
	var pack := catalog.get_part("battery_4s_1500")
	var mesh := BatteryMesh.new()
	mesh.rebuild(pack)

	# 75 x 35 x 37 mm, from data/parts/batteries.json.
	var expected := Vector3(0.035, 0.037, 0.075)
	var drawn := _drawn_extent(mesh)
	var reported := mesh.size_m
	mesh.free()

	return TestResult.new(
		"the 4S 1500's block is its published 75 x 35 x 37 mm, drawn and reported",
		reported.distance_to(expected) < EPS and drawn.distance_to(expected) < EPS,
		"reports %s, draws %s, catalog says %s (metres, x=width y=height z=length)" % [
			reported, drawn, expected]
	)


## The single-source assertion, and the point of the slice. Every pack in the catalog, so a mesh
## that happens to agree about the reference build and disagrees about the 6S Li-ion brick fails.
static func _the_drawn_size_is_the_size_the_physics_uses(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	for pack in catalog.list_category("battery"):
		checked += 1
		var mesh := BatteryMesh.new()
		mesh.rebuild(pack)
		var physics := Build.battery_size_of(pack)
		if mesh.size_m.distance_to(physics) > 1e-9:
			problems.append("%s: drawn %s vs physics %s" % [pack["part_id"], mesh.size_m, physics])
		mesh.free()

	return TestResult.new(
		"every pack is drawn at exactly the size its inertia tensor is built from",
		problems.is_empty(),
		"%d packs checked, %s" % [checked, "all agree" if problems.is_empty() else str(problems)]
	)


## A 2S 450 and a 6S 4000 Li-ion are not the same object scaled — they differ on all three axes,
## and the Li-ion is nearly as wide as it is long while the 2S is four times as long as it is wide.
static func _a_different_pack_is_a_different_block(catalog: PartsCatalog) -> TestResult:
	var mesh := BatteryMesh.new()

	mesh.rebuild(catalog.get_part("battery_2s_450"))
	var small := _drawn_extent(mesh)
	mesh.rebuild(catalog.get_part("battery_6s_4000_liion"))
	var large := _drawn_extent(mesh)
	mesh.free()

	var grew_on_every_axis := large.x > small.x and large.y > small.y and large.z > small.z
	var changed_shape := absf(large.z / large.x - small.z / small.x) > 1.0

	return TestResult.new(
		"swapping a 2S 450 for a 6S 4000 Li-ion changes the block on all three axes and its shape",
		grew_on_every_axis and changed_shape,
		"%s (length:width %.2f) -> %s (length:width %.2f)" % [
			small, small.z / small.x, large, large.z / large.x]
	)


## A 4S pack is four cells and a 1S pack is one, and you can see it. Not decoration: the cell count
## is what sets the pack voltage, which sets the RPM ceiling, and it is the single biggest reason a
## 4S->6S swap feels like a different aircraft. Drawing it means the rail's most consequential
## choice is legible on the airframe rather than only in a spec row.
static func _the_cell_division_is_the_pack_s_cell_count(catalog: PartsCatalog) -> TestResult:
	var mesh := BatteryMesh.new()
	var counts: Dictionary = {}
	var problems: Array[String] = []

	for part_id in ["battery_1s_300", "battery_2s_450", "battery_4s_1500", "battery_6s_1300"]:
		var pack := catalog.get_part(part_id)
		mesh.rebuild(pack)
		var drawn := _count_named(mesh, "Cell_")
		counts[part_id] = drawn
		var expected := int(pack["specs"]["cells"])
		if drawn != expected:
			problems.append("%s draws %d cells, is %d" % [part_id, drawn, expected])
	mesh.free()

	return TestResult.new(
		"the pack draws as many cells as it has",
		problems.is_empty(),
		"%s%s" % [counts, "" if problems.is_empty() else " -- " + str(problems)]
	)


## Chemistry is already physics-bearing (it selects the discharge curve). It is also the most
## visible thing about a pack: a LiPo is a brick of stacked pouches and a Li-ion is a bundle of
## barrels, and telling them apart at a glance is most of what makes a long-range build look like
## a long-range build.
##
## The Li-ion arrangement is DERIVED, not authored: the cell grid comes from the cell count and the
## pack's own width-to-height ratio, which lands on 2x2 for a 4S 18650 pack and 3x2 for a 6S 21700
## one — the way both are really built.
static func _chemistry_changes_what_the_cells_are(catalog: PartsCatalog) -> TestResult:
	var mesh := BatteryMesh.new()

	mesh.rebuild(catalog.get_part("battery_4s_1500"))
	var lipo_round := _count_cells_of_type(mesh, true)
	var lipo_flat := _count_cells_of_type(mesh, false)

	mesh.rebuild(catalog.get_part("battery_6s_4000_liion"))
	var liion_round := _count_cells_of_type(mesh, true)
	var liion_flat := _count_cells_of_type(mesh, false)
	mesh.free()

	return TestResult.new(
		"a LiPo draws as stacked pouches and a Li-ion as cylindrical cells",
		lipo_flat == 4 and lipo_round == 0 and liion_round == 6 and liion_flat == 0,
		"4S 1500 LiPo: %d pouches, %d barrels; 6S 4000 Li-ion: %d pouches, %d barrels" % [
			lipo_flat, lipo_round, liion_flat, liion_round]
	)


## Leads leave the pack from ONE end — the rear, since nose is -Z — rather than from the middle or
## from both. A pack drawn without them reads as a block of resin.
static func _leads_come_out_of_one_end(catalog: PartsCatalog) -> TestResult:
	var mesh := BatteryMesh.new()
	mesh.rebuild(catalog.get_part("battery_4s_1500"))

	var leads := _count_named(mesh, "Lead_")
	var body_rear: float = mesh.size_m.z * 0.5
	var all_behind := leads > 0
	for child in mesh.get_children():
		if String(child.name).begins_with("Lead_"):
			if (child as Node3D).position.z <= body_rear:
				all_behind = false
	var straps := _count_named(mesh, "Strap_")
	mesh.free()

	return TestResult.new(
		"leads emerge from the rear of the pack, and a strap holds it down",
		leads == 2 and all_behind and straps >= 1,
		"%d leads, all aft of z=%.4f: %s; %d straps" % [leads, body_rear, all_behind, straps]
	)


## Same posture as MotorMesh's fallback stator and FrameModel's fallback pad: an incomplete
## contribution should look wrong, not disappear. The size it falls back to is Build's, so even the
## fallback has one source rather than two.
static func _a_pack_with_no_dimensions_still_draws_something(catalog: PartsCatalog) -> TestResult:
	var pack: Dictionary = catalog.get_part("battery_4s_1500").duplicate(true)
	for key in ["length_mm", "width_mm", "height_mm"]:
		(pack["specs"] as Dictionary).erase(key)

	var mesh := BatteryMesh.new()
	mesh.rebuild(pack)
	var drawn := _drawn_extent(mesh)
	var expected := Build.battery_size_of(pack)
	mesh.free()

	return TestResult.new(
		"a pack with no published dimensions still draws, at the size the physics falls back to",
		drawn.distance_to(expected) < EPS and drawn.length() > 0.0,
		"drew %s against the fallback's %s" % [drawn, expected]
	)


# ---------------------------------------------------------------------------
# Measuring the generated geometry
# ---------------------------------------------------------------------------

## The bounding box of everything drawn EXCEPT the leads and straps, which are hardware hanging off
## the pack rather than the pack. Composed from each mesh's own AABB through its own transform, so
## this measures what is on screen and not what any field claims.
static func _drawn_extent(mesh: BatteryMesh) -> Vector3:
	var bounds: AABB = AABB()
	var started := false
	for child in mesh.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var child_name := String(child.name)
		if child_name.begins_with("Lead_") or child_name.begins_with("Strap_"):
			continue
		var box := instance.transform * instance.mesh.get_aabb()
		bounds = box if not started else bounds.merge(box)
		started = true
	return bounds.size if started else Vector3.ZERO


static func _count_named(mesh: BatteryMesh, prefix: String) -> int:
	var count := 0
	for child in mesh.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count


## Cells, split by what they are made of: a cylinder is a Li-ion barrel, a box is a LiPo pouch.
static func _count_cells_of_type(mesh: BatteryMesh, cylindrical: bool) -> int:
	var count := 0
	for child in mesh.get_children():
		if not String(child.name).begins_with("Cell_"):
			continue
		var is_cylinder := (child as MeshInstance3D).mesh is CylinderMesh
		if is_cylinder == cylindrical:
			count += 1
	return count
