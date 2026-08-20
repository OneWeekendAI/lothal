class_name TestPropellerMesh
extends RefCounted
## PropellerMesh generates blades from diameter, pitch and blade count. It is the one piece of
## geometry in this slice with real shape in it, and therefore the one where "looks about
## right" is least trustworthy — which is what these tests are for.
##
## The central check reads the TWIST back out of the generated vertices and turns it into a
## pitch, at every radial station independently. Pitch is the distance a propeller would
## advance in one revolution if it did not slip, so the blade angle at radius r must satisfy
## tan(beta) = pitch / (2*pi*r) — a steeply feathered root easing to a shallow tip. A prop
## whose blade angle does not vary that way is not a propeller, it is a fan, and a flat disc
## or a uniformly-angled paddle would sail through any check that only looked at diameter and
## blade count.
##
## Since slice P3 the twist is not re-derived at all — the mesh DRAWS the document's beta(r).
## PropellerDocument.beta_rad is the one definition (propulsion.md §3.2), and the two tests at
## the bottom assert the angle read back from the drawn blade equals that beta, at every station,
## including for an authored twist table.
##
## Reading the angle back out is done with a principal-axis fit over each station's vertices.
## The blade has thickness, so a station is four corners of a thin rectangle; the major axis
## of that rectangle IS the chord line, exactly, because the thickness spreads symmetrically
## either side of it. Anything cruder (say, the Y extent over the Z extent) is polluted by the
## thickness and would force a tolerance loose enough to hide a real error.

const INCH_M := 0.0254

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_twist_follows_pitch(catalog))
	results.append(_test_higher_pitch_is_more_twisted(catalog))
	results.append(_test_blade_count_and_spacing(catalog))
	results.append(_test_diameter_sets_the_sweep(catalog))
	results.append(_test_a_3_blade_5in_is_not_a_2_blade_7in(catalog))
	results.append(_test_rebuild_no_stale_blades(catalog))
	results.append(_test_mesh_twist_is_the_documents_beta(catalog))
	results.append(_test_authored_twist_is_drawn(catalog))

	return results


# ---------------------------------------------------------------------------
# Reading the generated blade back
# ---------------------------------------------------------------------------

## One blade's vertices, in blade-local space, where +X is the radial direction. Taken from
## the mesh itself rather than from anything the class chose to remember about what it drew.
static func _blade_vertices(mesh: PropellerMesh) -> PackedVector3Array:
	var blade := mesh.get_node("Blade_0") as MeshInstance3D
	var arrays: Array = (blade.mesh as ArrayMesh).surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


## Groups a blade's vertices into radial stations. Every corner of one station shares that
## station's radius exactly, so the grouping key is the X coordinate.
static func _stations(vertices: PackedVector3Array) -> Array:
	var by_radius: Dictionary = {}
	for v in vertices:
		var key := "%.6f" % v.x
		if not by_radius.has(key):
			by_radius[key] = {"radius": v.x, "points": []}
		by_radius[key]["points"].append(Vector2(v.z, v.y))

	var out: Array = []
	for key in by_radius:
		out.append(by_radius[key])
	out.sort_custom(func(a, b): return a["radius"] < b["radius"])
	return out


## The blade angle at one station: the direction of the major principal axis of that station's
## points in the (chordwise, vertical) plane. Closed-form 2x2 eigenvector, which for the four
## corners of a thin rectangle returns the chord line exactly.
static func _twist_rad(points: Array) -> float:
	var mean := Vector2.ZERO
	for p in points:
		mean += p
	mean /= float(points.size())

	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in points:
		var d: Vector2 = p - mean
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y

	# Major-axis direction of the 2x2 covariance [[sxx, sxy], [sxy, syy]].
	var theta := 0.5 * atan2(2.0 * sxy, sxx - syy)
	return absf(theta)


## Pitch implied by the blade angle at a given radius: pitch = 2*pi*r*tan(beta).
static func _implied_pitch_m(radius_m: float, twist_rad: float) -> float:
	return TAU * radius_m * tan(twist_rad)


# ---------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------

## Every station must imply the SAME pitch — the prop's own published pitch. This is what
## makes the blade a helical surface rather than a bent plate, and it is checked station by
## station so a blade that happens to be right in the middle and wrong at both ends fails.
static func _test_twist_follows_pitch(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var checked := 0
	var worst_error := 0.0
	var worst_where := ""
	var monotonic := true

	for prop_id in ["prop_5x43x3", "prop_7x35x2", "prop_3x3x3", "prop_10x5x2"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		var expected_pitch_m: float = float(prop["specs"]["pitch_inches"]) * INCH_M

		var mesh := PropellerMesh.new()
		mesh.rebuild(prop)
		var stations := _stations(_blade_vertices(mesh))
		mesh.free()

		var previous_twist := INF
		for station in stations:
			var radius: float = station["radius"]
			if radius <= 0.0:
				continue
			var twist := _twist_rad(station["points"])
			var implied := _implied_pitch_m(radius, twist)
			var error: float = absf(implied - expected_pitch_m) / expected_pitch_m
			checked += 1
			if error > worst_error:
				worst_error = error
				worst_where = "%s at r=%.4f m (implied %.1f\" vs %.1f\")" % [
					prop_id, radius, implied / INCH_M, expected_pitch_m / INCH_M]
			# A helical blade unwinds as it goes out: beta falls as r rises, STRICTLY. Written as
			# >= rather than > on purpose — a flat blade has the same angle everywhere and would
			# satisfy a non-strict version at every station.
			if twist >= previous_twist:
				monotonic = false
			previous_twist = twist

	results.append(TestResult.new(
		"the blade angle at every radius is the one the prop's pitch implies",
		worst_error < 0.02 and checked >= 40,
		"%d stations across 4 props, worst pitch error %.1f%% — %s" % [
			checked, worst_error * 100.0, worst_where if worst_where != "" else "none"]
	))
	results.append(TestResult.new(
		"the blade unwinds from a steep root to a shallow tip",
		monotonic,
		"blade angle falls monotonically with radius across all %d stations" % checked
	))
	return results


## Same diameter, same blade count, more pitch. Nothing but the pitch number differs, so the
## blade must be visibly more feathered at every station or pitch is not reaching the mesh.
static func _test_higher_pitch_is_more_twisted(catalog: PartsCatalog) -> TestResult:
	var low := PropellerMesh.new()
	low.rebuild(catalog.get_part("prop_5x43x3"))
	var high := PropellerMesh.new()
	high.rebuild(catalog.get_part("prop_5x48x3"))

	var low_stations := _stations(_blade_vertices(low))
	var high_stations := _stations(_blade_vertices(high))

	var all_steeper := low_stations.size() == high_stations.size() and low_stations.size() > 0
	var sample := ""
	for i in mini(low_stations.size(), high_stations.size()):
		var low_twist := _twist_rad(low_stations[i]["points"])
		var high_twist := _twist_rad(high_stations[i]["points"])
		if high_twist <= low_twist:
			all_steeper = false
		# The middle station, by index. Integer division on purpose: an odd count has no exact
		# middle and either neighbour of it is the sample worth quoting.
		@warning_ignore("integer_division")
		var middle := low_stations.size() / 2
		if i == middle:
			sample = "mid-blade %.1f deg -> %.1f deg" % [rad_to_deg(low_twist), rad_to_deg(high_twist)]

	low.free()
	high.free()

	return TestResult.new(
		"a 4.8\" pitch blade is more feathered than a 4.3\" one at the same diameter",
		all_steeper,
		sample
	)


static func _test_blade_count_and_spacing(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	for prop_id in ["prop_5x43x2", "prop_5x43x3", "prop_16x12x4"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		var expected := int(prop["specs"]["blades"])

		var mesh := PropellerMesh.new()
		mesh.rebuild(prop)

		var blades: Array[Node] = []
		for child in mesh.get_children():
			if String(child.name).begins_with("Blade_"):
				blades.append(child)
		if blades.size() != expected:
			problems.append("%s: %d blades drawn, %d in the spec" % [prop_id, blades.size(), expected])
		else:
			# Evenly spaced around the hub, or the prop is unbalanced on screen.
			var step := TAU / float(expected)
			for i in blades.size():
				var yaw: float = (blades[i] as Node3D).rotation.y
				if absf(fposmod(yaw, TAU) - fposmod(step * i, TAU)) > 0.001:
					problems.append("%s: blade %d at %.1f deg, expected %.1f" % [
						prop_id, i, rad_to_deg(yaw), rad_to_deg(step * i)])
		mesh.free()

	return TestResult.new(
		"blade count comes from the spec, and the blades are evenly spaced",
		problems.is_empty(),
		"2, 3 and 4-blade props checked, %s" % ("all correct" if problems.is_empty() else str(problems))
	)


## The sweep the prop actually occupies must be its published diameter — this is the number
## that decides whether a prop clears the arms, so it is not allowed to be approximate.
static func _test_diameter_sets_the_sweep(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	for prop_id in ["prop_3x3x3", "prop_5x43x3", "prop_7x4x3", "prop_10x5x2"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		var expected_radius: float = float(prop["specs"]["diameter_inches"]) * INCH_M * 0.5

		var mesh := PropellerMesh.new()
		mesh.rebuild(prop)
		var reach := 0.0
		for v in _blade_vertices(mesh):
			reach = maxf(reach, v.x)
		var reported := mesh.radius_m
		mesh.free()

		if absf(reach - expected_radius) > 0.0005:
			problems.append("%s: blades reach %.4f m, diameter implies %.4f m" % [
				prop_id, reach, expected_radius])
		if absf(reported - expected_radius) > 0.0005:
			problems.append("%s: reports radius %.4f m, diameter implies %.4f m" % [
				prop_id, reported, expected_radius])

	return TestResult.new(
		"the blades sweep exactly the published diameter",
		problems.is_empty(),
		"4 diameters checked, %s" % ("all exact" if problems.is_empty() else str(problems))
	)


## The acceptance criterion, as a test: these two must be unmistakably different objects.
static func _test_a_3_blade_5in_is_not_a_2_blade_7in(catalog: PartsCatalog) -> TestResult:
	var five := PropellerMesh.new()
	five.rebuild(catalog.get_part("prop_5x43x3"))
	var seven := PropellerMesh.new()
	seven.rebuild(catalog.get_part("prop_7x35x2"))

	var five_blades := 0
	var seven_blades := 0
	for child in five.get_children():
		if String(child.name).begins_with("Blade_"):
			five_blades += 1
	for child in seven.get_children():
		if String(child.name).begins_with("Blade_"):
			seven_blades += 1

	var five_radius := five.radius_m
	var seven_radius := seven.radius_m
	# Different meshes, not the same mesh at two scales: the 7" is a bi-blade and its blades
	# are proportionally wider, so its chord must not be a fixed multiple of the 5"'s.
	var five_chord := _chord_at_mid(_blade_vertices(five))
	var seven_chord := _chord_at_mid(_blade_vertices(seven))

	five.free()
	seven.free()

	var passed := five_blades == 3 and seven_blades == 2 \
		and seven_radius > five_radius * 1.3 and seven_chord > five_chord

	return TestResult.new(
		"a 3-blade 5\" and a 2-blade 7\" are unmistakably different props",
		passed,
		"5\": %d blades r=%.4f chord=%.4f   7\": %d blades r=%.4f chord=%.4f" % [
			five_blades, five_radius, five_chord, seven_blades, seven_radius, seven_chord]
	)


static func _chord_at_mid(vertices: PackedVector3Array) -> float:
	var stations := _stations(vertices)
	if stations.is_empty():
		return 0.0
	# As above: the middle station by index, truncating deliberately.
	@warning_ignore("integer_division")
	var middle := stations.size() / 2
	var mid: Array = stations[middle]["points"]
	var widest := 0.0
	for a in mid:
		for b in mid:
			widest = maxf(widest, (a as Vector2).distance_to(b as Vector2))
	return widest


static func _test_rebuild_no_stale_blades(catalog: PartsCatalog) -> TestResult:
	var mesh := PropellerMesh.new()
	mesh.rebuild(catalog.get_part("prop_16x12x4"))
	var four_blade_children := mesh.get_child_count()
	var old_blade := mesh.get_node("Blade_0") as Node3D

	mesh.rebuild(catalog.get_part("prop_5x43x2"))
	var two_blade_children := mesh.get_child_count()
	var old_still_inside := mesh.is_ancestor_of(old_blade)
	var radius := mesh.radius_m

	mesh.free()

	# A 4-blade replaced by a 2-blade must LOSE children. This is the one direction in which a
	# missed clear-out is invisible: leftover blades on a bigger prop just look like a bigger
	# prop, and a 2-blade showing four blades is the same bug read the other way.
	var passed := two_blade_children < four_blade_children and not old_still_inside \
		and absf(radius - 5.0 * INCH_M * 0.5) < 0.0005

	return TestResult.new(
		"rebuilding a 4-blade as a 2-blade drops the extra blades",
		passed,
		"%d children -> %d, old blade still inside: %s, radius now %.4f m" % [
			four_blade_children, two_blade_children, old_still_inside, radius]
	)


# ---------------------------------------------------------------------------
# P3 — the mesh draws the document's beta(r), not a copy of it
# ---------------------------------------------------------------------------

## P3'S PROOF, and the whole point of the slice: the angle the mesh draws and the angle the
## document's beta(r) says are ONE NUMBER, asserted at every station. The mesh reads
## PropellerDocument.beta_rad — that is the change — and this checks the vertex construction
## (station -> rotated section -> mesh) encodes that angle honestly, with no sign error, no
## offset and no second copy. For geometric presets the mesh and the document are the same helix,
## so this also pins the two together the way test_propeller_document pins the chord: if either
## ever drifts, the read-back stops matching the document.
static func _test_mesh_twist_is_the_documents_beta(catalog: PartsCatalog) -> TestResult:
	var checked := 0
	var worst_error := 0.0
	var worst_where := ""

	for prop_id in ["prop_5x43x3", "prop_7x35x2", "prop_3x3x3", "prop_10x5x2"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		var doc := PropellerDocument.from_catalog_prop(prop)
		var mesh := PropellerMesh.new()
		mesh.rebuild(prop)
		var stations := _stations(_blade_vertices(mesh))
		var radius_m := mesh.radius_m
		mesh.free()

		for station in stations:
			var radius: float = station["radius"]
			if radius <= 0.0:
				continue
			var read_back := _twist_rad(station["points"])
			var expected := doc.beta_rad(radius / radius_m)
			var error := absf(read_back - expected)
			checked += 1
			if error > worst_error:
				worst_error = error
				worst_where = "%s at r/R=%.3f (drawn %.3f°, doc %.3f°)" % [
					prop_id, radius / radius_m, rad_to_deg(read_back), rad_to_deg(expected)]

	return TestResult.new(
		"the blade angle drawn equals the document's beta(r), one number at every station",
		checked >= 40 and worst_error < 0.001,
		"%d stations, worst deviation %.5f rad — %s" % [checked, worst_error, worst_where])


## THE CASE ONLY READING THE DOCUMENT CAN GET RIGHT. A blade whose builder authored a twist table
## (twist_mode: authored, §3.2 — the tip-unloaded shape good blades use) must be DRAWN with that
## table, not with the constant-pitch helix. Before slice P3 the mesh held its own geometric
## formula and would draw the helix; the physics (the document) would read the authored table, and
## the picture and the physics would disagree by exactly the unload. This test fails on that state
## and passes once the mesh reads beta_rad.
static func _test_authored_twist_is_drawn(catalog: PartsCatalog) -> TestResult:
	var prop: Dictionary = catalog.get_part("prop_5x43x3")
	var doc := PropellerDocument.from_catalog_prop(prop)
	# An unloaded tip: the root as the helix demands, the geometric middle, and a tip four degrees
	# shallower — less twist at the tip, which is what "most good props unload the tip" means.
	# The root/mid/tip are read while the document is still GEOMETRIC; switching mode first would
	# make beta_rad read the still-empty authored table and every station would come back 0.
	var root := doc.beta_rad(0.1)
	var mid := doc.beta_rad(0.5)
	var tip := doc.beta_rad(1.0)
	doc.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED
	doc.twist = [0.1, root, 0.5, mid, 1.0, tip - deg_to_rad(4.0)]

	var mesh := PropellerMesh.new()
	mesh.rebuild(prop, doc)
	var stations := _stations(_blade_vertices(mesh))
	var radius_m := mesh.radius_m
	mesh.free()

	var checked := 0
	var worst_error := 0.0
	var worst_where := ""
	for station in stations:
		var radius: float = station["radius"]
		if radius <= 0.0:
			continue
		var r_frac := radius / radius_m
		var read_back := _twist_rad(station["points"])
		var expected := doc.beta_rad(r_frac)
		var error := absf(read_back - expected)
		checked += 1
		if error > worst_error:
			worst_error = error
			worst_where = "r/R=%.3f (drawn %.3f°, doc %.3f°)" % [
				r_frac, rad_to_deg(read_back), rad_to_deg(expected)]

	# And the unload must be REAL, checked against the helix the same prop would draw without the
	# authored table — an independent oracle, so the test is not comparing the mesh to itself.
	var tip_read := _tip_twist_rad(stations)
	var helix_tip := atan(doc.pitch_mm / (TAU * radius_m * 1000.0))
	var unloaded := absf(tip_read - (helix_tip - deg_to_rad(4.0))) < 0.001

	return TestResult.new(
		"an authored twist table is drawn as authored, not as the constant-pitch helix",
		checked >= 10 and worst_error < 0.001 and unloaded,
		"%d stations, worst deviation %.5f rad — %s; tip drawn %.2f°, helix tip %.2f°" % [
			checked, worst_error, worst_where, rad_to_deg(tip_read), rad_to_deg(helix_tip)])


## The blade angle at the outermost station — the tip, where beta is smallest and an unload shows.
static func _tip_twist_rad(stations: Array) -> float:
	if stations.is_empty():
		return 0.0
	return _twist_rad(stations[stations.size() - 1]["points"])
