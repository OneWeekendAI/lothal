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
