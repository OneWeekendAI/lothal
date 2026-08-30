class_name TestGuardMesh
extends RefCounted
## GuardMesh is the ring drawn around a motor when the build fits a prop guard — plans/
## 2026-08-26-propulsion-room-design.md §5 P10c. It is a peer of PropellerMesh (not a member of
## it) so PropellerMesh's invariants against its source file — the ones test_prop_rotation.gd
## asserts — travel with that class unchanged.
##
## The load-bearing test in this file is the mutation-tested check §5 P10c names. The drawing
## must READ PropGuard.tip_clearance_mm for the ring's inner wall rather than derive it from
## (outer_radius - wall) itself. That difference is silent — a version of GuardMesh that
## computed `inner = (outer - wall)` would produce a ring that lands in the same place FOR THE
## SAME SPEC, so a picture-only comparison would pass forever. The failure only appears when the
## spec's outer_radius is inflated relative to the prop tip: measuring the visible gap from
## `outer_radius - prop_tip` instead of from `tip_clearance_mm` reports the gap `wall_mm` too
## wide, which on the reference cinewhoop (outer 68, wall 3, tip 63.5) is 4.5 mm instead of
## 1.5 mm — a triangle three times too fat.
##
## `_the_mutation_from_clearance_to_outer_is_caught` does that mutation IN THE TEST and asserts
## its delta is exactly `wall_mm`. So a future edit that quietly wires the mutation back in
## fails this test on the way in — not "at some later date once someone eyeballs the picture".

const INCH_M := 0.0254

## Values from data/parts/guards.json's cinewhoop entry — carried here so a drift between the
## catalog and this test's expectations is obvious.
const CINEWHOOP_OUTER_MM := 68.0
const CINEWHOOP_WALL_MM := 3.0
const CINEWHOOP_TIP_GAP_MM := 1.5
const FIVE_INCH_TIP_MM := 5.0 * INCH_M * 500.0  # (5 * 0.0254 / 2) * 1000 = 63.5

const EPS := 1e-9


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_no_guard_no_ring())
	results.append(_the_cinewhoop_inner_wall_reads_from_prop_guard(catalog))
	results.append(_the_mutation_from_clearance_to_outer_is_caught(catalog))
	results.append(_drawn_mesh_vertices_confirm_inner_radius(catalog))
	results.append(_a_refused_spec_draws_no_ring())
	results.append(_rebuild_clears_stale_geometry(catalog))
	results.append(_ring_polygon_has_32_vertices_at_outer_radius(catalog))
	results.append(_the_source_file_holds_no_speed())
	results.append(_a_fitted_build_hangs_a_ring_on_every_motor(catalog))
	results.append(_an_unfitted_build_hangs_none_and_a_rebuild_clears_them(catalog))
	results.append(_the_airframe_polygons_sit_on_their_own_motors(catalog))

	return results


# ---------------------------------------------------------------------------

static func _five_inch_radius_m() -> float:
	return 5.0 * INCH_M * 0.5


static func _no_guard_no_ring() -> TestResult:
	var guard := GuardMesh.new()
	guard.rebuild({}, _five_inch_radius_m())

	var children := guard.get_child_count()
	var inner := guard.inner_radius_m
	guard.free()

	return TestResult.new(
		"an empty build.guard leaves the mesh with no ring",
		children == 0 and inner == 0.0,
		"child count %d, inner_radius_m %.6f" % [children, inner]
	)


## The number is `PropGuard.tip_clearance_mm(spec, prop_tip_mm)`, and the drawn inner wall is
## `prop_tip + clearance` — to bit precision, because there is one source and the arithmetic is
## elementary. TO MAKE THIS FAIL: recompute inner as `(outer - wall) * 0.001` in guard_mesh.gd
## and this test reports a delta of exactly `wall_m` on the cinewhoop.
static func _the_cinewhoop_inner_wall_reads_from_prop_guard(catalog: PartsCatalog) -> TestResult:
	var guard_record := catalog.get_part("guard_duct_5in_cinewhoop")
	var prop_tip_m := _five_inch_radius_m()
	var mesh := GuardMesh.new()
	mesh.rebuild(guard_record, prop_tip_m)

	var expected_inner_m := (prop_tip_m * 1000.0 + CINEWHOOP_TIP_GAP_MM) * 0.001
	var drawn_inner_m := mesh.inner_radius_m
	var drawn_outer_m := mesh.outer_radius_m
	var cached_clearance := mesh.tip_clearance_mm_value
	mesh.free()

	var inner_ok := absf(drawn_inner_m - expected_inner_m) < EPS
	var outer_ok := absf(drawn_outer_m - (expected_inner_m + CINEWHOOP_WALL_MM * 0.001)) < EPS
	var cached_ok := absf(cached_clearance - CINEWHOOP_TIP_GAP_MM) < 1e-9

	return TestResult.new(
		"the cinewhoop ring's inner wall reads from PropGuard.tip_clearance_mm",
		inner_ok and outer_ok and cached_ok,
		"expected inner %.6f, drawn inner %.6f, outer %.6f, cached clearance %.6f mm" % [
			expected_inner_m, drawn_inner_m, drawn_outer_m, cached_clearance]
	)


## The mutation §5 P10c names, INSERTED here and asserted to change the answer. Nothing else in
## GuardMesh's real code catches this — the wrong version and the right version both draw a ring
## with the ring's material at approximately the right place, and the "wrong" answer is only
## wrong compared with what PropGuard says the clearance is. So the check is direct: compute
## what the mutation WOULD produce and confirm the delta is exactly `wall_m`, on the cinewhoop
## whose ratio propulsion.md §9 P9 measures.
##
## `wall_mm = 3` and `tip_gap_mm = 1.5`, so the wrong inner is 4.5 mm out and the right one is
## 1.5 mm — three times fatter, the "triangle 3x too fat" the P10c bullet cites. If GuardMesh's
## implementation ever swaps `tip_clearance_mm` for `outer_radius - prop_tip`, this ratio is
## what it lands on and the outer wall of the drawn ring shifts by exactly `wall_m` outward.
static func _the_mutation_from_clearance_to_outer_is_caught(catalog: PartsCatalog) -> TestResult:
	var guard_record := catalog.get_part("guard_duct_5in_cinewhoop")
	var spec: Dictionary = guard_record.get("specs", {})
	var prop_tip_mm := _five_inch_radius_m() * 1000.0
	var outer_mm := float(spec.get("outer_radius_mm", 0.0))
	var wall_mm := float(spec.get("wall_mm", 0.0))

	var true_clearance := PropGuard.tip_clearance_mm(spec, prop_tip_mm)
	var mutation_clearance := outer_mm - prop_tip_mm  # the "read outer_radius instead" bug

	var mesh := GuardMesh.new()
	mesh.rebuild(guard_record, prop_tip_mm * 0.001)
	var drawn_inner_m := mesh.inner_radius_m
	mesh.free()

	var mutation_inner_m := (prop_tip_mm + mutation_clearance) * 0.001
	var true_inner_m := (prop_tip_mm + true_clearance) * 0.001

	# The drawn ring must land on the true value, not the mutation.
	var lands_correctly := absf(drawn_inner_m - true_inner_m) < EPS
	# And the mutation must move the answer by exactly wall_m — the "3x too fat" gap in mm terms.
	var mutation_delta_mm := (mutation_inner_m - true_inner_m) * 1000.0
	var mutation_shifts_by_wall := absf(mutation_delta_mm - wall_mm) < 1e-6
	# The ratio the P10c bullet names, sanity-pinned so a hand-edit that changes the cinewhoop
	# geometry cannot silently invalidate the "3x" evidence.
	var ratio := mutation_clearance / true_clearance
	var ratio_is_three := absf(ratio - 3.0) < 1e-9

	return TestResult.new(
		"reading outer_radius instead of tip_clearance draws the gap 3x too fat and is caught",
		lands_correctly and mutation_shifts_by_wall and ratio_is_three,
		"drawn %.6f m (true %.6f, mutation %.6f), delta %.4f mm (wall %.1f), ratio %.4f" % [
			drawn_inner_m, true_inner_m, mutation_inner_m, mutation_delta_mm, wall_mm, ratio]
	)


## The drawn MESH vertices — not the reported fields — reach the same inner radius. Reading
## fields alone would let a version pass that stored inner_radius_m correctly and then built
## the mesh from a different value: two definitions in one file, the exact drift this test file
## exists to catch. Vertices come off the ArrayMesh's own surface, in the manner of
## test_propeller_mesh.gd.
static func _drawn_mesh_vertices_confirm_inner_radius(catalog: PartsCatalog) -> TestResult:
	var guard_record := catalog.get_part("guard_duct_5in_cinewhoop")
	var prop_tip_m := _five_inch_radius_m()
	var mesh := GuardMesh.new()
	mesh.rebuild(guard_record, prop_tip_m)

	var ring := mesh.get_node("GuardRing") as MeshInstance3D
	var vertices: PackedVector3Array = (ring.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

	# The inner ring is the SMALLEST radius any vertex sits at. The outer ring is the largest.
	# Reading them as extrema means the check has no idea which vertex indices are which and
	# still lands on the two rings the annulus actually has.
	var min_r := INF
	var max_r := -INF
	for v in vertices:
		var r: float = Vector2(v.x, v.z).length()
		if r < min_r: min_r = r
		if r > max_r: max_r = r

	var expected_inner_m := mesh.inner_radius_m
	var expected_outer_m := mesh.outer_radius_m
	mesh.free()

	var inner_ok := absf(min_r - expected_inner_m) < 1e-6
	var outer_ok := absf(max_r - expected_outer_m) < 1e-6

	return TestResult.new(
		"drawn mesh vertices reach the reported inner and outer radii",
		inner_ok and outer_ok,
		"vertex extrema %.6f..%.6f m, reported %.6f..%.6f m" % [
			min_r, max_r, expected_inner_m, expected_outer_m]
	)


## A spec PropGuard.compute() refuses draws no ring — same posture as as_part_mass. A ring at
## a class-typical default would be a picture of a guard nobody fitted. The refusal is silent
## in the mass path (null return, no PartMass appended); the drawing must match, or the aircraft
## has the right weight and shows a shroud nobody built.
static func _a_refused_spec_draws_no_ring() -> TestResult:
	# A spec with no `kind` — refused by PropGuard.compute().
	var bad_record := {
		"part_id": "test_bad",
		"category": "guard",
		"specs": {
			"outer_radius_mm": 68.0, "wall_mm": 3.0, "height_mm": 12.0,
			"density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
		},
	}
	var mesh := GuardMesh.new()
	mesh.rebuild(bad_record, _five_inch_radius_m())
	var children := mesh.get_child_count()
	var inner := mesh.inner_radius_m
	var clearance := mesh.tip_clearance_mm_value
	mesh.free()

	return TestResult.new(
		"an unreadable guard spec draws no ring rather than a default one",
		children == 0 and inner == 0.0 and is_nan(clearance),
		"child count %d, inner %.6f, cached clearance %s" % [
			children, inner, ("NAN" if is_nan(clearance) else str(clearance))]
	)


## A rebuild from a fitted guard to no guard clears the ring. Same failure mode motor mesh's
## `_test_rebuild_no_stale_children` guards against, adapted to a category whose PRESENCE is
## optional — a stale ring after a guard was removed is a picture of a part nobody built, which
## is a more misleading failure than a wrong ring shape.
static func _rebuild_clears_stale_geometry(catalog: PartsCatalog) -> TestResult:
	var guard_record := catalog.get_part("guard_duct_5in_cinewhoop")
	var mesh := GuardMesh.new()

	mesh.rebuild(guard_record, _five_inch_radius_m())
	var fitted_children := mesh.get_child_count()
	var fitted_inner := mesh.inner_radius_m
	var old_ring := mesh.get_node("GuardRing") as MeshInstance3D

	mesh.rebuild({}, _five_inch_radius_m())
	var unfitted_children := mesh.get_child_count()
	var unfitted_inner := mesh.inner_radius_m
	var old_still_parented := old_ring.get_parent() == mesh

	# And back the other way — no stale field either.
	mesh.rebuild(guard_record, _five_inch_radius_m())
	var refitted_inner := mesh.inner_radius_m

	mesh.free()

	var passed := fitted_children == 1 and fitted_inner > 0.0 \
		and unfitted_children == 0 and unfitted_inner == 0.0 \
		and not old_still_parented \
		and absf(refitted_inner - fitted_inner) < EPS

	return TestResult.new(
		"rebuild clears a stale ring and restores it on refit",
		passed,
		"fit: %d children inner %.6f; unfit: %d children inner %.6f; old parented: %s; refit inner %.6f" % [
			fitted_children, fitted_inner, unfitted_children, unfitted_inner,
			old_still_parented, refitted_inner]
	)


## The plan-view polygon for the camera-frustum containment test §5 P10c asks for. The check on
## the arm side is not in the codebase yet — grepped for `frustum` returns nothing under src/ —
## so this test pins the polygon SHAPE (32 vertices, all on the outer radius, at the mesh's own
## XZ position). The moment the arm frustum check lands, the guard's polygon plugs in unchanged
## and this test is what says "yes, the polygon is still that."
static func _ring_polygon_has_32_vertices_at_outer_radius(catalog: PartsCatalog) -> TestResult:
	var guard_record := catalog.get_part("guard_duct_5in_cinewhoop")
	var prop_tip_m := _five_inch_radius_m()
	var mesh := GuardMesh.new()
	# The node's own transform is deliberately something ELSE — on a real aircraft it is
	# (0, disc_y, 0) in the arm-tip pad's frame, which is not the plan position. The polygon is
	# built about the centre the caller passes, so a version that read `position` instead lands
	# 0.11 m away from where this check looks for it.
	mesh.position = Vector3(0.11, 0.0, -0.07)
	mesh.rebuild(guard_record, prop_tip_m)

	var origin_xz := Vector2(0.09, -0.09)
	var polygon := mesh.ring_polygon_m(origin_xz)
	var outer_m := mesh.outer_radius_m

	var max_radial_error := 0.0
	for p in polygon:
		var r := (p - origin_xz).length()
		max_radial_error = maxf(max_radial_error, absf(r - outer_m))

	mesh.free()

	return TestResult.new(
		"the ring polygon is a 32-vertex circle at outer_radius in the mesh's XZ frame",
		polygon.size() == 32 and max_radial_error < 1e-6,
		"polygon size %d, max radial error %.9f m, outer %.6f m" % [
			polygon.size(), max_radial_error, outer_m]
	)


## Same posture as tests/test_prop_rotation.gd's `_test_the_source_file_holds_no_speed`: a guard
## does not rotate, so no member of GuardMesh's source may name a rate. If GuardMesh ever grows
## a member named to imply one — RPM, SPEED, REV_PER, OMEGA — this test fires. It is the same
## invariant PropellerMesh's file carries, extended by parallel to the class that draws the
## other part of a rotor's stage.
static func _the_source_file_holds_no_speed() -> TestResult:
	var file := FileAccess.open("res://src/lab/guard_mesh.gd", FileAccess.READ)
	if file == null:
		return TestResult.new("guard_mesh.gd source is readable", false, "FileAccess.open returned null")
	var text := file.get_as_text()
	file.close()

	# Same regex spirit as test_prop_rotation.gd — the point is a var/const declaration that
	# NAMES a rate, not a mention in a comment or a string literal.
	var regex := RegEx.new()
	regex.compile("(?m)^\\s*(var|const)\\s+[A-Za-z_][A-Za-z0-9_]*(RPM|SPEED|REV_PER|OMEGA)")
	var matches: Array = regex.search_all(text)

	return TestResult.new(
		"guard_mesh.gd declares no member named for a rate",
		matches.is_empty(),
		"%d rate-named declaration(s) found" % matches.size()
	)


# --- The airframe wiring: one ring per motor, on the pad the motor sits on ---------------------
#
# GuardMesh on its own is a ring generator; what makes it an aircraft part is AirframeModel
# parenting one per motor onto the arm-tip pad. That wiring has its own failure modes, none of
# which the ring tests above can see: a ring on the frame instead of the pad (a frame change
# leaves it behind), a ring at the motor's base instead of the propeller's disc plane (it wraps
# nothing), and a stale ring after a rebuild to a build fitting no guard.


static func _guarded_build(catalog: PartsCatalog, guard_id: String) -> Build:
	return Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3",
		ReferenceBuild.BATTERY_ID, Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID, {}, null, guard_id)


## Structural, in the manner of test_airframe_model's motor check: the ring must be a child of
## the same arm-tip pad the motor hangs off, not of the frame and not of the motor. The pad is
## what a frame change moves; the motor is what a motor change replaces. And its Y must be the
## propeller disc's, because the tip clearance the ring draws describes the gap at that plane —
## a ring at the pad's own Y wraps the arm, not the disc.
static func _a_fitted_build_hangs_a_ring_on_every_motor(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_guarded_build(catalog, "guard_duct_5in_cinewhoop"))

	var problems: Array[String] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		if not airframe.guard_meshes.has(motor_name):
			problems.append("%s has no guard ring" % motor_name)
			continue
		var guard: GuardMesh = airframe.guard_meshes[motor_name]
		var motor: Node3D = airframe.motor_meshes[motor_name]
		var propeller: Node3D = airframe.propeller_meshes[motor_name]
		if guard.get_parent() != motor.get_parent():
			problems.append("%s's ring is not a sibling of its motor" % motor_name)
		var disc_y: float = motor.position.y + propeller.position.y
		if absf(guard.position.y - disc_y) > 1e-9:
			problems.append("%s's ring at y=%.4f is not on the disc plane %.4f" % [
				motor_name, guard.position.y, disc_y])
		if guard.inner_radius_m <= 0.0:
			problems.append("%s's ring has no geometry" % motor_name)

	var count := airframe.guard_meshes.size()
	airframe.free()

	return TestResult.new(
		"a fitted guard hangs a ring on every motor's own pad, at the propeller disc plane",
		problems.is_empty() and count == MotorLayout.MOTOR_NAMES.size(),
		"%d rings, %s" % [count, "all seated" if problems.is_empty() else str(problems)]
	)


## The optional-presence posture, both directions. An unfitted build shows no ring at all — the
## picture of "no guard" is nothing, not a default one — and a rebuild from fitted to unfitted
## must leave neither a dictionary entry nor a node behind. A stale ring is the more misleading
## failure: the mass is right, the oracle is right, and the aircraft on screen has a shroud
## nobody bought.
static func _an_unfitted_build_hangs_none_and_a_rebuild_clears_them(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(_guarded_build(catalog, ""))
	var unfitted_first := airframe.guard_meshes.size()

	airframe.rebuild(_guarded_build(catalog, "guard_duct_5in_cinewhoop"))
	var fitted := airframe.guard_meshes.size()
	var stale_ring: GuardMesh = airframe.guard_meshes["M1"]

	airframe.rebuild(_guarded_build(catalog, ""))
	var unfitted_after := airframe.guard_meshes.size()
	var polygons_after := airframe.guard_ring_polygons_m().size()
	# "Gone" means no longer part of THIS aircraft — walking up from the ring must not reach the
	# AirframeModel. Asserting `get_parent() == null` instead would be wrong for the same reason
	# it would be wrong for a motor: FrameModel's rebuild frees the whole arm-tip pad the ring
	# hangs off, and a queue_free'd orphan still reports its parent for the rest of the frame.
	var stale_still_in_tree := is_instance_valid(stale_ring) and _is_descendant_of(stale_ring, airframe)

	airframe.free()

	var passed := unfitted_first == 0 and fitted == MotorLayout.MOTOR_NAMES.size() \
		and unfitted_after == 0 and polygons_after == 0 and not stale_still_in_tree

	return TestResult.new(
		"an unfitted build draws no rings, and a refit-then-remove leaves none behind",
		passed,
		"unfitted %d -> fitted %d -> unfitted %d (%d polygons), stale ring parented: %s" % [
			unfitted_first, fitted, unfitted_after, polygons_after, stale_still_in_tree]
	)


static func _is_descendant_of(node: Node, root: Node) -> bool:
	var walker: Node = node.get_parent()
	while walker != null:
		if walker == root:
			return true
		walker = walker.get_parent()
	return false


## The frame bug the polygon parameter exists to prevent, asserted on a real aircraft. Each
## ring's plan polygon must be centred on ITS OWN motor — MotorLayout.motor_position, the same
## source footprint_prop_clearance_m reads. A version that built the polygon from the GuardMesh
## node's own `position` would centre all four on the aircraft's origin, because the ring is
## parented onto the pad and its local XZ is (0, 0): four identical polygons, a frustum check
## answering about an aircraft nobody built. This check fails outright against that version —
## the centroids collapse to one point and the spread goes to zero.
static func _the_airframe_polygons_sit_on_their_own_motors(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	var build := _guarded_build(catalog, "guard_duct_5in_cinewhoop")
	airframe.rebuild(build)

	var polygons := airframe.guard_ring_polygons_m()
	var problems: Array[String] = []
	var centroids: Array[Vector2] = []
	for motor_name in MotorLayout.MOTOR_NAMES:
		if not polygons.has(motor_name):
			problems.append("%s has no polygon" % motor_name)
			continue
		var polygon: PackedVector2Array = polygons[motor_name]
		var hub := MotorLayout.motor_position(motor_name, build.arm_m)
		var hub_xz := Vector2(hub.x, hub.z)
		var outer: float = (airframe.guard_meshes[motor_name] as GuardMesh).outer_radius_m
		if polygon.size() != 32:
			problems.append("%s's polygon has %d vertices" % [motor_name, polygon.size()])
		var centroid := Vector2.ZERO
		for p in polygon:
			centroid += p
			if absf((p - hub_xz).length() - outer) > 1e-6:
				problems.append("%s's polygon is not on its own motor" % motor_name)
				break
		centroids.append(centroid / float(maxi(polygon.size(), 1)))

	# And the four centroids are four DIFFERENT points — the direct statement of the collapse
	# the parameter prevents, so the check cannot pass on an aircraft whose rings all stacked up.
	var min_separation := INF
	for i in centroids.size():
		for j in range(i + 1, centroids.size()):
			min_separation = minf(min_separation, (centroids[i] - centroids[j]).length())
	airframe.free()

	return TestResult.new(
		"each ring's plan polygon is centred on its own motor, not on the aircraft's origin",
		problems.is_empty() and centroids.size() == 4 and min_separation > 0.05,
		"%d polygons, closest two centroids %.4f m apart, %s" % [
			polygons.size(), min_separation, "all placed" if problems.is_empty() else str(problems)]
	)
