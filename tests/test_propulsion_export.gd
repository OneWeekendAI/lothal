class_name TestPropulsionExport
extends RefCounted
## Guards and mount stacks out to STL — the P10f row's own proof obligation, which is stated in
## plans/2026-08-26-propulsion-room-design.md §1 as "`StlWriter.check_manifold` passes on every
## catalog guard."
##
## ## Why "every catalog guard" and not one fixture
##
## The three entries in `data/parts/guards.json` are not three of the same thing. Two are ducts and
## one is a bumper; one is a 3" TPU shroud with a 2 mm wall and one is a 5" ABS ring with a 3 mm
## one; and the ring's inner wall is derived per-guard from `PropGuard.tip_clearance_mm` against
## the propeller it wraps, so the annulus is a different shape for each. A single fixture would
## prove the writer works on the geometry somebody happened to test it with. The loop is written
## with an explicit `checked == 3` so that a renamed catalog category cannot empty it and pass
## silently — the vacuity guard `test_parts_system.gd`'s own guard checks already carry.
##
## ## The check that would have passed while proving nothing
##
## `check_manifold` returning `ok` on a ring is not, by itself, evidence that the RING is right:
## an implementation that emitted a cube would pass it too. So the volume is asserted against the
## annulus's own closed form, `π(R_o² − R_i²)·h`, computed from the radii `GuardMesh` derived —
## which ties the exported solid to the drawn one through a number neither file contains.
##
## And the winding is proved by mutation rather than by assertion: `_a_ring_wound_the_other_way_is
## _refused` reverses every triangle of a real catalog guard and requires the writer to refuse it.
## Without that, "the guard exports" is a claim about a file existing.

const INCH_M := 0.0254


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_every_catalog_guard_is_printable(catalog))
	results.append(_the_ring_encloses_the_annulus_it_draws(catalog))
	results.append(_a_ring_wound_the_other_way_is_refused(catalog))
	results.append(_no_guard_exports_nothing_rather_than_an_empty_solid())
	results.append(_a_refused_spec_exports_nothing(catalog))
	results.append(_the_mount_stack_is_printable())
	results.append(_the_mount_stack_is_the_stack_that_was_drawn())
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The tip radius the guard is fitted around, from its own `prop_class` ("5\"" → 63.5 mm). Read
## from the catalog entry rather than pinned, so a fourth guard in a fourth size is covered by the
## same loop the day it is added.
static func _tip_radius_m(guard: Dictionary) -> float:
	var prop_class := String(guard.get("catalog", {}).get("prop_class", ""))
	var inches := prop_class.replace("\"", "").strip_edges().to_float()
	return inches * INCH_M * 0.5


static func _reversed(triangles: Array) -> Array:
	var out: Array = []
	for triangle in triangles:
		out.append(PackedVector3Array([triangle[2], triangle[1], triangle[0]]))
	return out


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

## One result per guard rather than one looping result: a suite that reports "the guards are
## printable" once cannot say WHICH of the three stopped being so.
static func _every_catalog_guard_is_printable(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var checked := 0
	for guard in catalog.list_category("guard"):
		checked += 1
		var triangles := PropulsionExport.guard_triangles_mm(guard, _tip_radius_m(guard))
		var report := StlWriter.check_manifold(triangles)
		results.append(TestResult.new(
			"%s exports a closed, outward-wound solid" % guard["part_id"],
			bool(report["ok"]),
			"%d facets, %.3f mm³ · %s" % [report["triangle_count"], report["volume_mm3"],
				" / ".join(PackedStringArray(report["reasons"]))]))

	results.append(TestResult.new(
		"and all three catalog guards were actually checked",
		checked == 3,
		"checked %d" % checked))
	return results


## The volume against the annulus's own closed form. `ok` alone would pass on a cube.
static func _the_ring_encloses_the_annulus_it_draws(catalog: PartsCatalog) -> TestResult:
	var guard := catalog.get_part("guard_duct_5in_cinewhoop")
	var tip_m := _tip_radius_m(guard)

	var mesh := GuardMesh.new()
	mesh.rebuild(guard, tip_m)
	var inner_mm := mesh.inner_radius_m * 1000.0
	var outer_mm := mesh.outer_radius_m * 1000.0
	var height_mm := mesh.height_m * 1000.0
	var triangles := mesh.ring_triangles_mm()
	mesh.free()

	var expected := PI * (outer_mm * outer_mm - inner_mm * inner_mm) * height_mm
	var actual := float(StlWriter.check_manifold(triangles)["volume_mm3"])
	# A 32-sided prism is inscribed in the circle it approximates, so it encloses slightly LESS
	# than the true annulus — by the same 0.51% at both radii, since the chord factor depends only
	# on the segment count. Bounded at 1% and asserted as an under-count rather than a magnitude,
	# because a ring drawn from the wrong radii would miss in either direction.
	var ratio := actual / expected
	return TestResult.new(
		"the exported cinewhoop ring encloses its own annulus, not merely some volume",
		ratio > 0.99 and ratio <= 1.0,
		"%.3f mm³ against π(%.2f² − %.2f²)·%.1f = %.3f mm³ (ratio %.5f)" % [
			actual, outer_mm, inner_mm, height_mm, expected, ratio])


## The mutation. Nothing about a ring's shape changes when it is turned inside out, so this is the
## check that says the export is a claim about winding rather than about triangles existing.
static func _a_ring_wound_the_other_way_is_refused(catalog: PartsCatalog) -> TestResult:
	var guard := catalog.get_part("guard_bumper_5in_abs")
	var triangles := PropulsionExport.guard_triangles_mm(guard, _tip_radius_m(guard))
	var report := StlWriter.check_manifold(_reversed(triangles))
	var named := false
	for reason in report["reasons"]:
		if String(reason).contains("inside out"):
			named = true
	return TestResult.new(
		"the same ring wound the other way is refused as inside out",
		not bool(report["ok"]) and named,
		" / ".join(PackedStringArray(report["reasons"])))


static func _no_guard_exports_nothing_rather_than_an_empty_solid() -> TestResult:
	var triangles := PropulsionExport.guard_triangles_mm({}, 0.0635)
	var result := StlWriter.write("nothing", triangles, "user://test_no_guard.stl")
	var wrote := FileAccess.file_exists("user://test_no_guard.stl")
	if wrote:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_no_guard.stl"))
	return TestResult.new(
		"a build that fits no guard exports no triangles, and writes no file",
		triangles.is_empty() and not bool(result["ok"]) and not wrote,
		"%d triangles, wrote=%s" % [triangles.size(), wrote])


## The posture `PropGuard.as_part_mass` and `GuardMesh.rebuild` both hold, now on the export path:
## a geometry the model refuses produces no part, rather than a class-typical one.
static func _a_refused_spec_exports_nothing(catalog: PartsCatalog) -> TestResult:
	var broken := catalog.get_part("guard_duct_5in_cinewhoop").duplicate(true)
	var specs: Dictionary = broken["specs"]
	specs.erase("kind")
	var triangles := PropulsionExport.guard_triangles_mm(broken, 0.0635)
	return TestResult.new(
		"a guard whose spec PropGuard refuses exports nothing rather than a default ring",
		triangles.is_empty(),
		"%d triangles" % triangles.size())


static func _the_mount_stack_is_printable() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var motor := catalog.get_part(ReferenceBuild.MOTOR_ID)
	var mesh := MotorMesh.new()
	mesh.rebuild(motor, 0.006, 0.0, 0.003)
	var triangles := PropulsionExport.mount_stack_triangles_mm(mesh)
	mesh.free()
	var report := StlWriter.check_manifold(triangles)
	return TestResult.new(
		"the motor's mount stack exports as closed, outward-wound shells",
		bool(report["ok"]) and float(report["volume_mm3"]) > 0.0,
		"%d facets, %.1f mm³ · %s" % [report["triangle_count"], report["volume_mm3"],
			" / ".join(PackedStringArray(report["reasons"]))])


## The stack that is exported is the stack that was generated, asserted through its extent: a
## stack built from anything else would have to land on `MotorMesh.total_height_m` by accident.
## Bounded relatively at the float32 floor, because `Node3D.position` is single precision — the
## same bound `PropellerMountProfile`'s own suite is pinned at, for the same reason.
static func _the_mount_stack_is_the_stack_that_was_drawn() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var motor := catalog.get_part(ReferenceBuild.MOTOR_ID)
	var mesh := MotorMesh.new()
	mesh.rebuild(motor, 0.006, 0.0, 0.003)
	var expected_mm := mesh.total_height_m * 1000.0
	var triangles := PropulsionExport.mount_stack_triangles_mm(mesh)
	mesh.free()

	var top_mm := -INF
	var bottom_mm := INF
	for triangle in triangles:
		for point in triangle:
			top_mm = maxf(top_mm, point.z)
			bottom_mm = minf(bottom_mm, point.z)

	return TestResult.new(
		"and it spans exactly the height MotorMesh built, from the pad up",
		absf(top_mm - expected_mm) < 1e-3 and absf(bottom_mm) < 1e-3,
		"%.6f mm to %.6f mm against MotorMesh.total_height_m = %.6f mm" % [
			bottom_mm, top_mm, expected_mm])
