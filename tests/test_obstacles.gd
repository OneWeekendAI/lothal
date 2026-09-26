class_name TestObstacles
extends RefCounted
## F6: the obstacle vocabulary — box / pole / wall, placed on the terrain, drawn and collidable,
## and round-tripped without inventing a kind for one it cannot read.
##
## The three new COURSE WARNINGS (GATE_INTERSECTS_OBSTACLE, ROUTE_THROUGH_OBSTACLE,
## OUTSIDE_SITE_EXTENT) are tested in `test_course_warnings.gd`, alongside the rest of that
## vocabulary — this suite is `Obstacle` itself: placement (check 7), collision (check 8), and
## round-tripping (check 9).

const TOL := 1.0e-6


static func run() -> Array:
	var results: Array = []
	var sections := {
		"an obstacle sits on the terrain, not at y = 0": _sits_on_the_terrain(),
		"obstacles are collidable, not drawn-only": _collidable(),
		"round-tripping": _round_tripping(),
		"intersects_sphere and intersects_segment are exact, not a proximity bubble": _distance_geometry(),
		# F6 fix round 2: nothing checked obstacle geometry's winding before this — F5's own
		# winding check only ever exercises TerrainMesh.build_mesh(terrain) with no obstacles.
		"winding": _winding(),
	}
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 7. Placement: the base is height_at, not y = 0
# ---------------------------------------------------------------------------

static func _sits_on_the_terrain() -> Array:
	var results: Array = []

	# A 10 m hill: a slope that rises 10 m across its own span, so the far end is comfortably at
	# 10 m — pinned by asking `height_at` directly (the ONE formula this room has), not by
	# reasoning about the slope shape ourselves.
	var hill := Terrain.shaped(Terrain.SLOPE, 40.0, 40.0, {"rise_m": 10.0, "direction_deg": 0.0})
	var x := 20.0
	var z := 0.0
	var expected_ground := hill.height_at(x, z)
	results.append(TestResult.new(
		"the fixture's far edge really is 10 m up (sanity on height_at itself)",
		absf(expected_ground - 10.0) < TOL, "height_at(20, 0) = %.4f m" % expected_ground))

	var pole := Obstacle.place(Obstacle.POLE, x, z, {"radius": 0.1, "height": 3.0}, hill)
	results.append(TestResult.new(
		"a pole's base sits at the ground under it, not at y = 0",
		absf(pole.position.y - expected_ground) < TOL,
		"pole base y = %.4f m, ground there = %.4f m" % [pole.position.y, expected_ground]))

	var top_y := pole.aabb().position.y + pole.aabb().size.y
	results.append(TestResult.new(
		"its top is base + height (10 + 3), not height alone",
		absf(top_y - (expected_ground + 3.0)) < TOL,
		"top y = %.4f m, expected %.4f m" % [top_y, expected_ground + 3.0]))

	var flat_pole := Obstacle.place(Obstacle.POLE, 0.0, 0.0, {"radius": 0.1, "height": 3.0}, null)
	results.append(TestResult.new(
		"no terrain (null) reads flat at zero, the same rule height_at itself uses",
		absf(flat_pole.position.y) < TOL, "base y = %.4f m" % flat_pole.position.y))

	return results


# ---------------------------------------------------------------------------
# 8. Collidable: the collider contains the obstacle's own triangles
# ---------------------------------------------------------------------------

static func _collidable() -> Array:
	var results: Array = []
	var terrain := Terrain.flat(40.0, 40.0)
	var box: Array[Obstacle] = [Obstacle.place(Obstacle.BOX, 0.0, 0.0, {"w": 2.0, "h": 3.0, "d": 2.0, "yaw_deg": 0.0}, terrain)]

	var floor_only_mesh := TerrainMesh.build_mesh(terrain)
	var floor_only_points: int = floor_only_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()

	var with_box_mesh := TerrainMesh.build_mesh(terrain, box)
	var with_box_points: int = with_box_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	results.append(TestResult.new(
		"passing an obstacle to build_mesh draws MORE triangles than the floor alone",
		with_box_points > floor_only_points,
		"floor alone: %d points, with a box: %d points" % [floor_only_points, with_box_points]))

	var with_box_collider := TerrainMesh.build_collider(terrain, box)
	var collider_points := with_box_collider.get_faces()
	results.append(TestResult.new(
		"the collider carries exactly as many points as the mesh drew, obstacle included",
		collider_points.size() == with_box_points,
		"mesh %d points, collider %d points" % [with_box_points, collider_points.size()]))

	var max_y := -INF
	for p in collider_points:
		max_y = maxf(max_y, p.y)
	results.append(TestResult.new(
		"the collider reaches the top of the box (3.0 m), so it is really collidable up there",
		absf(max_y - 3.0) < TOL, "max collider y %.6f m" % max_y))
	return results


# ---------------------------------------------------------------------------
# 9. Round-tripping: byte-identical dims per kind, an unknown kind dropped
# ---------------------------------------------------------------------------

static func _round_tripping() -> Array:
	var results: Array = []
	var terrain := Terrain.flat(60.0, 60.0)

	var fixtures := {
		"box": {"kind": "box", "x": 4.0, "z": -2.0, "dims": {"w": 1.5, "h": 2.0, "d": 0.8, "yaw_deg": 30.0}},
		"pole": {"kind": "pole", "x": -6.0, "z": 3.0, "dims": {"radius": 0.15, "height": 2.5}},
		"wall": {"kind": "wall", "x": 0.0, "z": 10.0, "dims": {"length": 5.0, "height": 1.8, "thickness": 0.3, "yaw_deg": 90.0}},
	}
	for label in fixtures:
		var record: Dictionary = fixtures[label]
		var one := Obstacle.from_data(record, terrain)
		results.append(TestResult.new(
			"%s: from_data reads a real obstacle" % label, one != null, "got %s" % one))
		if one == null:
			continue
		var back := one.to_data()
		results.append(TestResult.new(
			"%s: kind round-trips" % label, back.get("kind") == record["kind"],
			"wrote %s, read back %s" % [record["kind"], back.get("kind")]))
		results.append(TestResult.new(
			"%s: x/z round-trip" % label,
			absf(float(back.get("x", NAN)) - float(record["x"])) < TOL
				and absf(float(back.get("z", NAN)) - float(record["z"])) < TOL,
			"wrote (%.3f, %.3f), read back (%.3f, %.3f)" % [
				record["x"], record["z"], back.get("x", NAN), back.get("z", NAN)]))
		var dims_back: Dictionary = back.get("dims", {})
		var dims_written: Dictionary = record["dims"]
		var dims_match := dims_back.size() == dims_written.size()
		for key in dims_written:
			if not dims_back.has(key) or absf(float(dims_back[key]) - float(dims_written[key])) > TOL:
				dims_match = false
		results.append(TestResult.new(
			"%s: dims round-trip byte-identically (its own keys, nothing invented or lost)" % label,
			dims_match,
			"wrote %s, read back %s" % [dims_written, dims_back]))

	# An unknown kind is DROPPED, not defaulted to a box.
	var unknown := Obstacle.from_data({"kind": "spire", "x": 1.0, "z": 1.0, "dims": {"h": 9.0}}, terrain)
	results.append(TestResult.new(
		"a kind this version does not recognise is dropped, not defaulted to a box",
		unknown == null, "got %s" % unknown))

	# The same, through Site's own list — a record with one good obstacle and one unrecognised
	# one keeps only the good one, rather than the unrecognised one silently becoming a box.
	var site := Site.from_data({
		"id": "s", "name": "S", "elevation_m": 0.0,
		"obstacles": [
			{"kind": "pole", "x": 0.0, "z": 0.0, "dims": {"radius": 0.1, "height": 2.0}},
			{"kind": "spire", "x": 5.0, "z": 5.0, "dims": {}},
		],
	})
	results.append(TestResult.new(
		"Site.from_data keeps the recognised obstacle and drops the unrecognised one",
		site.obstacles.size() == 1 and site.obstacles[0].kind == Obstacle.POLE,
		"got %d obstacle(s): %s" % [site.obstacles.size(),
			site.obstacles.map(func(o: Obstacle) -> String: return String(o.kind))]))
	return results


# ---------------------------------------------------------------------------
# Exactness of the distance geometry the warnings are built from
# ---------------------------------------------------------------------------

static func _distance_geometry() -> Array:
	var results: Array = []
	var terrain := Terrain.flat(40.0, 40.0)
	var box := Obstacle.place(Obstacle.BOX, 0.0, 0.0, {"w": 2.0, "h": 2.0, "d": 2.0, "yaw_deg": 0.0}, terrain)

	results.append(TestResult.new(
		"a point at the box's own centre is inside it (distance 0)",
		box.intersects_sphere(Vector3(0.0, 1.0, 0.0), 0.0), ""))
	results.append(TestResult.new(
		"a point 2 m clear of the box on every axis does not intersect it, even with a fat sphere",
		not box.intersects_sphere(Vector3(3.0, 1.0, 0.0), 0.5),
		"box half-extent 1.0 m on x, point at x=3.0, sphere radius 0.5"))
	results.append(TestResult.new(
		"a point exactly `radius` from the box's face does intersect (boundary inclusive)",
		box.intersects_sphere(Vector3(1.5, 1.0, 0.0), 0.5),
		"box face at x=1.0, point at x=1.5, sphere radius 0.5 -> distance 0.5"))

	# A segment that passes straight through the box is caught; one that detours around it is not
	# — proof that the WHOLE segment is walked and not just its endpoints.
	results.append(TestResult.new(
		"a segment straight through the box intersects it",
		box.intersects_segment(Vector3(-5.0, 1.0, 0.0), Vector3(5.0, 1.0, 0.0)), ""))
	results.append(TestResult.new(
		"a segment that detours around the box (both ends clear) does not intersect it",
		not box.intersects_segment(Vector3(-5.0, 1.0, 5.0), Vector3(5.0, 1.0, 5.0)), ""))
	return results


# ---------------------------------------------------------------------------
# Winding: every drawn face points outward, not merely "not degenerate"
# ---------------------------------------------------------------------------
##
## Godot's front faces are clockwise, and this repo has already paid for getting that backwards
## once (see terrain_mesh.gd's own header, and F5's `_winding` check on the floor grid). F5's check
## never exercises an obstacle — it only ever calls `TerrainMesh.build_mesh(terrain)` with an empty
## obstacle list — so nothing verified `_box_triangles`/`_cylinder_triangles` until this section.
##
## THE HONEST FORMULATION IS A DOT PRODUCT AGAINST THE SOLID'S OWN CENTRE, not `normal.y > 0` —
## that is the ground-plane rule from F5, and it is wrong here: a vertical wall's side faces point
## sideways, and a pole's cap normals point straight up/down while its side normals point outward
## in every horizontal direction. A triangle's normal must point AWAY from the solid it belongs to,
## whatever direction that happens to be — `(b-a).cross(c-a)` dotted with `centroid - solid_centre`,
## which is positive exactly when the face is wound outward.
##
## The cylinder's caps and sides are checked SEPARATELY because they are different code
## (`_cylinder_triangles`'s side-quad loop vs its two triangle-fans), and a copied winding
## convention flips most often exactly at a seam like that.

static func _winding() -> Array:
	var results: Array = []
	var terrain := Terrain.flat(30.0, 30.0)

	# --- box: every face's normal must point away from the box's own centre --------------------
	var box := Obstacle.place(Obstacle.BOX, 2.0, -1.0,
		{"w": 2.0, "h": 3.0, "d": 1.5, "yaw_deg": 25.0}, terrain)
	var box_centre := box.position + Vector3(0.0, 1.5, 0.0)  # h / 2
	var box_stat := _worst_outward_dot(box.triangles(), box_centre)
	results.append(TestResult.new(
		"every box triangle's normal points outward, away from the box's own centre",
		box_stat.checked > 0 and box_stat.worst > 0.0,
		"worst outward dot %.6f over %d triangles" % [box_stat.worst, box_stat.checked]))

	# --- wall: same code (_box_triangles) as box, different dims/yaw — proves the shared path ---
	var wall := Obstacle.place(Obstacle.WALL, -3.0, 4.0,
		{"length": 5.0, "height": 2.0, "thickness": 0.4, "yaw_deg": 60.0}, terrain)
	var wall_centre := wall.position + Vector3(0.0, 1.0, 0.0)  # height / 2
	var wall_stat := _worst_outward_dot(wall.triangles(), wall_centre)
	results.append(TestResult.new(
		"every wall triangle's normal points outward, away from the wall's own centre",
		wall_stat.checked > 0 and wall_stat.worst > 0.0,
		"worst outward dot %.6f over %d triangles" % [wall_stat.worst, wall_stat.checked]))

	# --- pole: sides and caps are different code, checked separately ---------------------------
	var pole := Obstacle.place(Obstacle.POLE, 1.0, 1.0, {"radius": 0.4, "height": 2.5}, terrain)
	var pole_centre := pole.position + Vector3(0.0, 1.25, 0.0)  # height / 2
	# _cylinder_triangles() appends, per side segment, 4 triangles in a fixed order: two side
	# triangles (6 points), then the top-cap fan triangle and the base-cap fan triangle (6 points)
	# — see the function itself. Sliced here rather than re-derived, so caps and sides are two
	# genuinely separate populations rather than one guessed apart after the fact.
	var pole_triangles := pole._cylinder_triangles(0.4, 2.5)
	var side_triangles := PackedVector3Array()
	var cap_triangles := PackedVector3Array()
	var i := 0
	while i + 12 <= pole_triangles.size():
		for j in 6:
			side_triangles.append(pole_triangles[i + j])
		for j in range(6, 12):
			cap_triangles.append(pole_triangles[i + j])
		i += 12

	var side_stat := _worst_outward_dot(side_triangles, pole_centre)
	results.append(TestResult.new(
		"every pole SIDE triangle's normal points outward, away from the pole's own centre",
		side_stat.checked > 0 and side_stat.worst > 0.0,
		"worst outward dot %.6f over %d triangles" % [side_stat.worst, side_stat.checked]))

	var cap_stat := _worst_outward_dot(cap_triangles, pole_centre)
	results.append(TestResult.new(
		"every pole CAP triangle's normal points outward, away from the pole's own centre " +
			"(top cap up, base cap down)",
		cap_stat.checked > 0 and cap_stat.worst > 0.0,
		"worst outward dot %.6f over %d triangles" % [cap_stat.worst, cap_stat.checked]))

	return results


## The worst (smallest) normalised dot product between a triangle's own normal and the direction
## from the solid's own centre to that triangle's centroid, over every triangle in `triangles`.
## Positive means outward; the worst value over a whole shape is what a marginal or backwards face
## would show up as, rather than hiding behind a plain pass/fail boolean (the same reporting shape
## F5's `_winding` check uses for its worst `normal.y`).
static func _worst_outward_dot(triangles: PackedVector3Array, solid_centre: Vector3) -> Dictionary:
	var worst := INF
	var checked := 0
	var i := 0
	while i + 2 < triangles.size():
		var a: Vector3 = triangles[i]
		var b: Vector3 = triangles[i + 1]
		var c: Vector3 = triangles[i + 2]
		var normal := (b - a).cross(c - a)
		var centroid := (a + b + c) / 3.0
		var outward := centroid - solid_centre
		if normal.length() > 1.0e-9 and outward.length() > 1.0e-9:
			worst = minf(worst, normal.normalized().dot(outward.normalized()))
			checked += 1
		i += 3
	return {"worst": worst, "checked": checked}
