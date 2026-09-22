class_name TestTerrainMesh
extends RefCounted
## F5: the ground you SEE and the ground `height_at` answers, built from one call.
##
## The rule this slice exists to enforce: `TerrainMesh.vertices()` calls `Terrain.height_at` for
## every point it draws rather than carrying a second copy of the slope/bowl/bank arithmetic. A
## mesh built from its own expression would let a hill exist on screen that the physics does not
## have, and nothing would look wrong until someone flew into the gap. §1 is the direct check of
## that rule, across all five shapes; every other section either guards a structural property of
## the mesh (extent, winding, vertex count) or the wiring that keeps it rebuilt.
##
## No fixture here is built by the function it is checking: §1's expectation IS `height_at`, read
## because that is literally the promise ("drawn = queried"), not because it was convenient; the
## flat AABB and vertex count pinned in §4 are computed from `GRID_STEP_M` and
## `Terrain.DEFAULT_WIDTH_M`/`DEFAULT_LENGTH_M` by hand, not read back from `TerrainMesh` itself.

const TOL := 1.0e-6
const MAIN_PATH := "res://src/scenes/main.gd"
const MAIN_SCRIPT := preload("res://src/scenes/main.gd")


static func run() -> Array:
	var results: Array = []
	var sections := {
		"drawn = queried": _drawn_equals_queried(),
		"collider matches mesh": _collider_matches_mesh(),
		"mesh spans the site's extent": _mesh_spans_the_extent(),
		"flat is planar and pinned": _flat_is_planar_and_pinned(),
		"winding": _winding(),
		"enclosure walls and pillars": _enclosure_walls_and_pillars(),
		"vertex count follows width, not rise": _vertex_count_follows_width_not_rise(),
		"one entry point": _one_entry_point(),
		# F6 fix round 1: obstacles are collidable IN SIM, not just at the TerrainMesh API.
		"obstacles reach the sim scene's collider": _obstacles_reach_the_sim_scene(),
	}
	# A runtime error partway through a section aborts only that section and its append never
	# runs, so the suite would pass with its best checks silently deleted. Asserting each section
	# produced something is what makes the count trustworthy.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 1. Drawn = queried, across all five shapes
# ---------------------------------------------------------------------------

static func _drawn_equals_queried() -> Array:
	var results: Array = []
	var terrains := {
		"flat": Terrain.flat(80.0, 60.0, 12.0, -8.0),
		"slope": Terrain.shaped(Terrain.SLOPE, 100.0, 60.0,
			{"rise_m": 4.0, "direction_deg": 37.0}, 5.0, -3.0),
		"bowl": Terrain.shaped(Terrain.BOWL, 90.0, 90.0, {"depth_m": 3.0}, 0.0, 20.0),
		"banked": Terrain.shaped(Terrain.BANKED, 70.0, 50.0,
			{"bank_height_m": 2.5, "bank_width_m": 12.0, "bank_edge": "east"}, -10.0, 0.0),
		"enclosure": Terrain.shaped(Terrain.ENCLOSURE, 60.0, 60.0,
			{"wall_height_m": 4.0, "roofed": true, "pillar_spacing_m": 8.0}, 0.0, 0.0),
	}
	for label in terrains:
		var terrain: Terrain = terrains[label]
		var verts := TerrainMesh.vertices(terrain)
		var worst := 0.0
		for v in verts:
			var expected: float = terrain.height_at(v.x, v.z)
			worst = maxf(worst, absf(v.y - expected))
		results.append(TestResult.new(
			"%s: every drawn vertex's y equals height_at(x, z)" % label,
			worst < TOL,
			"worst mismatch %.9f m over %d vertices" % [worst, verts.size()]))
	return results


# ---------------------------------------------------------------------------
# 2. The collider is the mesh's own triangles, not a second draw at a different step
# ---------------------------------------------------------------------------

static func _collider_matches_mesh() -> Array:
	var results: Array = []
	var terrain := Terrain.shaped(Terrain.SLOPE, 84.0, 56.0, {"rise_m": 5.0, "direction_deg": 20.0})

	var mesh_points := _mesh_triangle_points(TerrainMesh.build_mesh(terrain))
	var collider_points := TerrainMesh.build_collider(terrain).get_faces()

	results.append(TestResult.new(
		"collider carries the same number of triangle vertices as the drawn mesh",
		mesh_points.size() == collider_points.size(),
		"mesh %d points, collider %d points" % [mesh_points.size(), collider_points.size()]))

	var sorted_mesh := _sorted_points(mesh_points)
	var sorted_collider := _sorted_points(collider_points)
	var worst := 0.0
	var n := mini(sorted_mesh.size(), sorted_collider.size())
	for i in n:
		worst = maxf(worst, (sorted_mesh[i] - sorted_collider[i]).length())
	results.append(TestResult.new(
		"sorted, the collider's points are the mesh's points",
		n > 0 and n == sorted_mesh.size() and n == sorted_collider.size() and worst < TOL,
		"worst pairwise distance %.9f m over %d matched points" % [worst, n]))
	return results


# ---------------------------------------------------------------------------
# 3. The mesh's bounding box is the site's extent, not a fixed pad
# ---------------------------------------------------------------------------

static func _mesh_spans_the_extent() -> Array:
	var results: Array = []
	var terrain := Terrain.shaped(Terrain.BOWL, 76.0, 34.0, {"depth_m": 2.0}, 3.0, -5.0)
	var verts := TerrainMesh.vertices(terrain)

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)

	results.append(TestResult.new(
		"the mesh's x-span equals width_m exactly",
		absf((max_x - min_x) - terrain.width_m) < TOL,
		"span %.6f m, width_m %.6f m" % [max_x - min_x, terrain.width_m]))
	results.append(TestResult.new(
		"the mesh's z-span equals length_m exactly",
		absf((max_z - min_z) - terrain.length_m) < TOL,
		"span %.6f m, length_m %.6f m" % [max_z - min_z, terrain.length_m]))
	results.append(TestResult.new(
		"the mesh is NOT a fixed 400 m pad",
		absf((max_x - min_x) - 400.0) > TOL,
		"span %.3f m" % (max_x - min_x)))
	return results


# ---------------------------------------------------------------------------
# 4. Flat is planar at y = 0, and the default site's grid is a pinned shape
# ---------------------------------------------------------------------------

static func _flat_is_planar_and_pinned() -> Array:
	var results: Array = []
	var terrain := Terrain.flat(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)
	var verts := TerrainMesh.vertices(terrain)

	var worst_y := 0.0
	for v in verts:
		worst_y = maxf(worst_y, absf(v.y))
	results.append(TestResult.new(
		"a flat site's mesh is planar at y = 0",
		worst_y < TOL, "worst |y| %.9f m over %d vertices" % [worst_y, verts.size()]))

	# Pinned by hand from GRID_STEP_M and Terrain.DEFAULT_WIDTH_M/LENGTH_M — 120 m / 2.0 m step =
	# 60 cells, 61 vertices per side. NOT read back from TerrainMesh: a golden value taken from the
	# implementation it guards is a test that cannot fail.
	var expected_side := int(Terrain.DEFAULT_WIDTH_M / TerrainMesh.GRID_STEP_M) + 1
	var expected_count := expected_side * expected_side
	results.append(TestResult.new(
		"the default site's floor grid has the vertex count GRID_STEP_M implies (120 m -> 61x61)",
		verts.size() == expected_count,
		"got %d, expected %d (%dx%d)" % [verts.size(), expected_count, expected_side, expected_side]))

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)
	results.append(TestResult.new(
		"the default site's AABB is the SITE's 120x120 extent, not the old 400 m plane",
		absf((max_x - min_x) - Terrain.DEFAULT_WIDTH_M) < TOL
			and absf((max_z - min_z) - Terrain.DEFAULT_LENGTH_M) < TOL,
		"span %.3f x %.3f m" % [max_x - min_x, max_z - min_z]))
	return results


# ---------------------------------------------------------------------------
# 5. Winding: every triangle's normal points up
# ---------------------------------------------------------------------------

static func _winding() -> Array:
	var results: Array = []
	var terrain := Terrain.shaped(Terrain.SLOPE, 40.0, 30.0, {"rise_m": 3.0, "direction_deg": 15.0})
	var points := _mesh_triangle_points(TerrainMesh.build_mesh(terrain))

	var worst_y := INF
	var checked := 0
	var i := 0
	while i + 2 < points.size():
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var c: Vector3 = points[i + 2]
		var normal := (b - a).cross(c - a)
		if normal.length() > 1.0e-9:
			worst_y = minf(worst_y, normal.normalized().y)
			checked += 1
		i += 3
	results.append(TestResult.new(
		"every triangle's normal has y > 0 (Godot's front faces are clockwise)",
		checked > 0 and worst_y > 0.0,
		"worst normal.y %.6f over %d triangles" % [worst_y if checked > 0 else 0.0, checked]))
	return results


# ---------------------------------------------------------------------------
# 6. An enclosure's walls and pillars are drawn AND collidable; the floor stays flat
# ---------------------------------------------------------------------------

static func _enclosure_walls_and_pillars() -> Array:
	var results: Array = []
	var terrain := Terrain.shaped(Terrain.ENCLOSURE, 40.0, 40.0,
		{"wall_height_m": 3.0, "roofed": true, "pillar_spacing_m": 10.0})

	var floor_verts := TerrainMesh.vertices(terrain)
	var worst_floor_y := 0.0
	for v in floor_verts:
		worst_floor_y = maxf(worst_floor_y, absf(v.y))
	results.append(TestResult.new(
		"an enclosure's floor is still flat at y = 0",
		worst_floor_y < TOL, "worst |y| %.9f m" % worst_floor_y))

	var side := TerrainMesh._grid_dims(terrain)
	var floor_triangle_points: int = side.x * side.y * 2 * 3

	var mesh_points := _mesh_triangle_points(TerrainMesh.build_mesh(terrain))
	var collider_points := TerrainMesh.build_collider(terrain).get_faces()

	results.append(TestResult.new(
		"walls, pillars (and roof) add geometry beyond the floor grid",
		mesh_points.size() > floor_triangle_points,
		"mesh has %d triangle-points, floor alone is %d" % [mesh_points.size(), floor_triangle_points]))
	results.append(TestResult.new(
		"the extra geometry is collidable, not drawn-only: collider matches the mesh exactly",
		mesh_points.size() == collider_points.size(),
		"mesh %d points, collider %d points" % [mesh_points.size(), collider_points.size()]))

	# A point above wall height, just inside a wall's plane, must be found INSIDE some collider
	# triangle's bounding prism if walls were really added — checked here by a coarser proxy: the
	# maximum y among all collider points must reach wall_height_m (the floor alone never does).
	var max_y := -INF
	for p in collider_points:
		max_y = maxf(max_y, p.y)
	results.append(TestResult.new(
		"the collider reaches wall_height_m, so a wall really is collidable up there",
		absf(max_y - 3.0) < TOL, "max collider y %.6f m (wall_height_m 3.0)" % max_y))
	return results


# ---------------------------------------------------------------------------
# 7. width_m changes the grid; rise_m changes heights, not the grid
# ---------------------------------------------------------------------------

static func _vertex_count_follows_width_not_rise() -> Array:
	var results: Array = []
	var narrow := Terrain.shaped(Terrain.SLOPE, 40.0, 40.0, {"rise_m": 1.0, "direction_deg": 0.0})
	var wide := Terrain.shaped(Terrain.SLOPE, 120.0, 40.0, {"rise_m": 1.0, "direction_deg": 0.0})
	results.append(TestResult.new(
		"changing width_m changes the vertex count",
		TerrainMesh.vertices(narrow).size() != TerrainMesh.vertices(wide).size(),
		"40 m wide: %d vertices, 120 m wide: %d vertices" % [
			TerrainMesh.vertices(narrow).size(), TerrainMesh.vertices(wide).size()]))

	var low_rise := Terrain.shaped(Terrain.SLOPE, 60.0, 40.0, {"rise_m": 1.0, "direction_deg": 0.0})
	var high_rise := Terrain.shaped(Terrain.SLOPE, 60.0, 40.0, {"rise_m": 9.0, "direction_deg": 0.0})
	var low_verts := TerrainMesh.vertices(low_rise)
	var high_verts := TerrainMesh.vertices(high_rise)
	results.append(TestResult.new(
		"changing rise_m does NOT change the vertex count",
		low_verts.size() == high_verts.size(),
		"rise 1.0: %d vertices, rise 9.0: %d vertices" % [low_verts.size(), high_verts.size()]))

	var worst_height_diff := 0.0
	var n := mini(low_verts.size(), high_verts.size())
	for i in n:
		worst_height_diff = maxf(worst_height_diff, absf(high_verts[i].y - low_verts[i].y))
	results.append(TestResult.new(
		"...but it DOES change the heights",
		worst_height_diff > 0.5,
		"worst height difference between rise 1.0 and rise 9.0: %.4f m" % worst_height_diff))
	return results


# ---------------------------------------------------------------------------
# 8. The ground is rebuilt through one entry point, unconditionally
# ---------------------------------------------------------------------------

## Source-scanned rather than booted: main.tscn's _ready() builds a full UI (theme, build panel,
## parts catalog) that needs a processed frame to settle (capture_frame.gd's own comment says so),
## which this synchronous runner does not have. What matters here is structural: `_rebuild_ground`
## is called, unconditionally, from both places the ground could go stale — `_ready` (first load)
## and `adopt_selected_course` (site/course switch) — and the mutation this guards against (a
## skip when the shape name did not change) would show up as a conditional guarding the call
## rather than as the call itself vanishing, so both are checked.
static func _one_entry_point() -> Array:
	var results: Array = []
	var file := FileAccess.open(MAIN_PATH, FileAccess.READ)
	if file == null:
		results.append(TestResult.new(
			"main.gd can be read for the ground-rebuild wiring scan", false,
			"could not open %s" % MAIN_PATH))
		return results
	var source := file.get_as_text()
	file.close()

	var ready_body := _function_body(source, "func _ready() -> void:")
	var adopt_body := _function_body(source, "func adopt_selected_course() -> void:")
	var rebuild_body := _function_body(source, "func _rebuild_ground() -> void:")

	results.append(TestResult.new(
		"_ready() calls _rebuild_ground() at its own indent level (unconditionally)",
		_calls_unconditionally(ready_body, "_rebuild_ground()"),
		"found: %s" % (ready_body.find("_rebuild_ground()") >= 0)))
	results.append(TestResult.new(
		"adopt_selected_course() calls _rebuild_ground() at its own indent level (unconditionally)",
		_calls_unconditionally(adopt_body, "_rebuild_ground()"),
		"found: %s" % (adopt_body.find("_rebuild_ground()") >= 0)))
	# F6: build_mesh/build_collider gained an `obstacles` argument so obstacles reach the SAME
	# triangle list the floor does — re-pointed to the new call text rather than loosened to a
	# bare "TerrainMesh.build_mesh" substring, which would stop noticing a rebuild that got
	# wrapped in an `if` (the whole job of this check).
	results.append(TestResult.new(
		"_rebuild_ground() itself builds the mesh and the collider unconditionally, " +
			"not behind a \"shape unchanged\" guard, obstacles included",
		_calls_unconditionally(rebuild_body, "TerrainMesh.build_mesh(terrain, obstacles)")
			and _calls_unconditionally(rebuild_body, "TerrainMesh.build_collider(terrain, obstacles)"),
		"body: %s" % rebuild_body.strip_edges()))
	return results


# ---------------------------------------------------------------------------
# 9. Obstacles reach the SIM SCENE's collider, not just TerrainMesh's own API (F6 fix round 1)
# ---------------------------------------------------------------------------

## `Main.new()` rather than `main.tscn` instantiated: booting the real scene needs a processed
## frame to settle (see §8's header), which this synchronous runner does not have, and the
## @onready ground nodes would still be null at the point `adopt_selected_course()` runs even if
## it were instantiated, since entering the tree — not construction — is what fires `_ready()`
## (capture_frame.gd's own comment: "adding the scene from a SceneTree script does not run _ready
## synchronously"). So the ground nodes are supplied directly, the same way `RoomHost` supplies
## its own `course_library`/`site_library` before calling `adopt_selected_course()` — this is the
## one entry point the real app uses too, not a shortcut around it.
static func _obstacles_reach_the_sim_scene() -> Array:
	var results: Array = []

	var terrain := Terrain.flat(30.0, 30.0)
	var box := Obstacle.place(Obstacle.BOX, 0.0, 0.0, {"w": 2.0, "h": 3.0, "d": 2.0, "yaw_deg": 0.0}, terrain)

	var site := Site.new()
	site.site_id = "f6_fix_site"
	site.terrain = terrain
	site.obstacles = [box]
	var sites := SiteLibrary.new()
	sites.put(site)

	var course := GateCourse.new([
		GateCourse.make_gate(Vector3(0.0, 4.0, 10.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 4.0, -10.0), 0.0, 1.5),
	], "f6_fix_course", "F6 fix course")
	course.site_id = site.site_id
	var courses := CourseLibrary.new()
	courses.put(course)

	var scene: Node3D = MAIN_SCRIPT.new()
	scene.site_library = sites
	scene.course_library = courses
	scene.ground_mesh = MeshInstance3D.new()
	scene.ground_collision = CollisionShape3D.new()
	scene.adopt_selected_course()

	var collider: Shape3D = scene.ground_collision.shape
	var collider_points: PackedVector3Array = (collider as ConcavePolygonShape3D).get_faces() \
		if collider is ConcavePolygonShape3D else PackedVector3Array()
	var floor_only_points: int = TerrainMesh.build_mesh(terrain).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()

	results.append(TestResult.new(
		"adopt_selected_course() leaves a real collider on the ground, with more points than " +
			"the floor alone — the box reached it, not just the mesh",
		collider_points.size() > floor_only_points,
		"floor alone: %d points, scene's ground_collision: %d points" % [
			floor_only_points, collider_points.size()]))

	var max_y := -INF
	for p in collider_points:
		max_y = maxf(max_y, p.y)
	results.append(TestResult.new(
		"the sim scene's own collider reaches the box's top (3.0 m)",
		absf(max_y - 3.0) < TOL, "max collider y %.6f m" % max_y))

	scene.ground_mesh.free()
	scene.ground_collision.free()
	scene.free()
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Every triangle vertex the mesh actually carries — `ArrayMesh`'s only surface, un-indexed
## (`SurfaceTool.commit()` without `.index()`), so three consecutive points are one triangle.
static func _mesh_triangle_points(mesh: ArrayMesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


static func _sorted_points(points: PackedVector3Array) -> Array:
	var out: Array = []
	for p in points:
		out.append(p)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if absf(a.x - b.x) > TOL: return a.x < b.x
		if absf(a.y - b.y) > TOL: return a.y < b.y
		return a.z < b.z)
	return out


## The text of a function's body, from its own `func` line up to (not including) the next
## top-level `func`/`static func`. Same technique test_ground_authority.gd uses for
## `_the_crash_test_is_arithmetic`.
static func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var after_start := start + signature.length()
	var after := source.find("\nfunc ", after_start)
	var after_static := source.find("\nstatic func ", after_start)
	if after_static >= 0 and (after < 0 or after_static < after):
		after = after_static
	if after < 0:
		after = source.length()
	return source.substr(after_start, after - after_start)


## Whether `needle` appears in `body` on a line indented with exactly one tab more than the
## function body's own statements start at (i.e. at the function's top level), which is what rules
## out a call hidden inside an `if` a mutation could have added.
static func _calls_unconditionally(body: String, needle: String) -> bool:
	if body.find(needle) < 0:
		return false
	for line in body.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.find(needle) >= 0:
			# Exactly one leading tab: not nested inside an `if`/`for`/`while` (two or more tabs).
			var leading_tabs := 0
			while leading_tabs < line.length() and line[leading_tabs] == "\t":
				leading_tabs += 1
			if leading_tabs == 1:
				return true
	return false
