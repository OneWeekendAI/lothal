class_name TestPlateMesh
extends RefCounted
## Extruding a plate into the solid you see — airframe.md §7.2.
##
## ## Why a mesh gets a test suite at all
##
## Because the failure mode is invisible geometry, and "invisible" is not a shade of wrong that
## anybody notices in a diff. The first version of this extruder produced meshes with correct
## vertices, correct triangle counts and correct bounding boxes — and every face wound backwards, so
## Godot culled all of them and the aircraft rendered as four motors floating in mid-air with no
## frame between them. Nothing about the data was wrong; only the ORDER of three vertices was, and
## no assertion about sizes or counts can see that.
##
## So the assertion here is the one that matters: every face is wound the way Godot needs it to be
## in order to survive back-face culling — which, since Godot winds front faces CLOCKWISE, means the
## cross product of its own two stored edges points opposite to the normal beside it. A face that
## passes this test is a face you can see.
##
## ## MUTATION NOTES
##
##   - `_test_every_face_points_the_way_it_says_it_does` fails if `_add_face` stops checking the
##     cross product and picks a winding by reasoning about axes instead. That is exactly the bug it
##     was written for.
##   - `_test_both_windings_produce_a_solid` fails if the rim's outward direction stops being taken
##     from the signed area. A builder can draw a plate clockwise simply by going round the other
##     way, and half their frame would then be see-through.
##   - `_test_the_mesh_matches_the_outline_it_came_from` fails if the extruder ever starts
##     simplifying, insetting or "tidying" an outline: the picture would stop being the polygon the
##     mass integral reads, which is the one guarantee §0 asks of this file.


static func run() -> Array:
	var results: Array = []
	results.append(_test_every_face_points_the_way_it_says_it_does())
	results.append(_test_both_windings_produce_a_solid())
	results.append(_test_the_mesh_matches_the_outline_it_came_from())
	results.append(_test_a_degenerate_outline_makes_no_mesh())
	return results


## Counter-clockwise, the winding everything in `FrameEdits` produces.
static func _rectangle() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-30.0, -10.0), Vector2(30.0, -10.0), Vector2(30.0, 10.0), Vector2(-30.0, 10.0)])


static func _reversed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		out.append(points[i])
	return out


## The invisible-geometry test. Walks every triangle the mesh actually holds and checks its winding
## against the normal stored with it.
static func _test_every_face_points_the_way_it_says_it_does() -> TestResult:
	var report := _winding_report(_rectangle())
	return TestResult.new(
		"every face of an extruded plate is wound to face the way its normal says",
		report["backwards"] == 0 and report["faces"] >= 12,
		"%d faces, %d wound backwards" % [report["faces"], report["backwards"]])


## The same plate drawn the other way round. A polygon's winding is a choice a builder makes without
## knowing they made it, and both choices have to come out solid.
static func _test_both_windings_produce_a_solid() -> TestResult:
	var report := _winding_report(_reversed(_rectangle()))
	return TestResult.new(
		"a clockwise outline extrudes just as solidly as a counter-clockwise one",
		report["backwards"] == 0 and report["faces"] >= 12,
		"%d faces, %d wound backwards" % [report["faces"], report["backwards"]])


## The mesh is the outline. Asserted through the bounding box, in the world axes
## `AirframeDocument.world_m` maps onto: u → X, v → Z, thickness → Y.
##
## The Y check is the one with teeth. `extrude` centres the plate on its own origin and leaves the
## height to the node, so a 4 mm plate must span −2 mm to +2 mm and NOT 0 to 4 mm — the version that
## baked the height in made every node's position read zero, and two plates 20 mm apart measured as
## touching.
static func _test_the_mesh_matches_the_outline_it_came_from() -> TestResult:
	var mesh := PlateMesh.extrude(_rectangle(), 4.0)
	if mesh == null:
		return TestResult.new("an extruded plate has the outline's own dimensions", false, "no mesh")
	var box := mesh.get_aabb()
	# 60 mm across u, 20 mm across v, 4 mm of stock, in metres.
	var right := absf(box.size.x - 0.060) < 1.0e-6
	var deep := absf(box.size.z - 0.020) < 1.0e-6
	var thick := absf(box.size.y - 0.004) < 1.0e-6
	var centred := absf(box.position.y + 0.002) < 1.0e-6
	return TestResult.new(
		"an extruded plate has the outline's own dimensions and is centred on its own origin",
		right and deep and thick and centred,
		"size %s, bottom at %.5f m" % [box.size, box.position.y])


## An outline that is not a polygon, and a plate with no stock. Both are states a builder can reach
## mid-edit, and both must produce nothing rather than a malformed surface.
static func _test_a_degenerate_outline_makes_no_mesh() -> TestResult:
	var two_points := PlateMesh.extrude(
		PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0)]), 2.0)
	var no_thickness := PlateMesh.extrude(_rectangle(), 0.0)
	return TestResult.new(
		"a degenerate outline or a zero thickness makes no mesh at all",
		two_points == null and no_thickness == null,
		"two points -> %s, zero thickness -> %s" % [two_points, no_thickness])


## Walks a mesh's triangles and counts how many are wound against their own stored normal.
static func _winding_report(outline: PackedVector2Array) -> Dictionary:
	var mesh := PlateMesh.extrude(outline, 4.0)
	if mesh == null:
		return {"faces": 0, "backwards": 1}
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var faces := int(vertices.size() / 3.0)
	var backwards := 0
	for face in faces:
		var a := vertices[face * 3]
		var b := vertices[face * 3 + 1]
		var c := vertices[face * 3 + 2]
		var geometric := (b - a).cross(c - a)
		# Zero-area triangles are not "backwards", they are nothing — and a triangulator is entitled
		# to emit one on a collinear run of points. Counting them would make this suite fail for a
		# reason that has nothing to do with which way anything faces.
		if geometric.length() <= 1.0e-12:
			continue
		# Compared against Godot's own convention, not the textbook one: front faces are wound
		# CLOCKWISE, so the surviving triangle is the one whose right-hand-rule normal points into
		# the solid. `PlateMesh._add_face` explains why this is asserted rather than reasoned about.
		if geometric.normalized().dot(normals[face * 3]) > -0.5:
			backwards += 1
	return {"faces": faces, "backwards": backwards}
