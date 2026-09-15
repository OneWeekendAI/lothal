class_name StlWriter
## Getting a printable part OUT of Lothal, and refusing to write one that would fail on the bed —
## track.md slice W1P.1, landed here because P10f's guard export is the first part that needs it.
##
## ## Why a writer and not another `to_stl`
##
## `FrameExport.to_stl` already emits a frame as a solid, and it is correct for what it does: a
## plate is an extruded polygon, its caps come from the triangulator `PlateMesh` uses, and the
## walls are stitched in one loop that cannot be wound two ways. Nothing about that generalises.
## A guard is an annulus with a hole through it, a mount stack is several closed shells that
## overlap, and both are assembled from geometry a Node3D generated for the screen — where the
## material says `CULL_DISABLED` and winding therefore costs nothing to get wrong. On a printer
## it costs six hours: a slicer reading an inside-out or open shell produces either a hollow
## shell, a part with the outside missing, or a solid brick where the hole was.
##
## So this class is the boundary, and it has three jobs and no fourth:
##
##   1. **The mm conversion, in exactly one place** (`from_metres`). Every part in this app is
##      modelled in metres and every slicer on earth reads STL as millimetres. A factor of 1000
##      applied twice is a part ten times too big, and a factor applied nowhere is a part the
##      size of a grain of rice — both of which look plausible in a preview window.
##   2. **The manifold check** (`check_manifold`), which is what makes an export a claim rather
##      than a file.
##   3. **The refusal** (`write`), which names the part in the reason. A part that fails does not
##      write a file at all: a bad STL on disk next to a warning in a log is a part somebody
##      prints.
##
## ## What "manifold" is checked as, and why THIS is the test
##
## The check is on directed edges. Every triangle contributes three of them (a→b, b→c, c→a), and
## a closed, consistently wound surface has the property that **every directed edge appears
## exactly once, and its reverse appears exactly once**. That single property carries both of the
## first two failures the slice cares about:
##
##   - An edge whose reverse is missing means a boundary — a hole in the surface.
##   - An edge that appears TWICE in the same direction means two triangles wound the same way
##     across a shared edge, which is the inside-out neighbour. It is the failure the airframe
##     room already met from a different direction (a sign flip inside a shared section function
##     flipped both readers together and every view still looked right), and it is invisible in
##     any picture drawn with culling off.
##
## Neither is catchable by looking at normals: a shell wound entirely inside out is perfectly
## consistent, and every normal in it is a unit vector pointing the wrong way. What catches THAT
## is the third check — the signed volume, by the divergence theorem, must be POSITIVE. A shell
## turned inside out has the same volume with the opposite sign, exactly.
##
## And a fourth, which is not a manifold property but is a print failure: a surface enclosing no
## volume. Two coincident triangles wound opposite ways are closed, consistent and sum to zero.
##
## ## Multiple shells are allowed, deliberately
##
## A motor stack is a base, a bell, an adapter, a shaft and a nut — five closed cylinders that
## interpenetrate. Every one of them is individually closed and outward, so the union passes all
## four checks, and every slicer resolves overlapping shells by union. Requiring ONE shell would
## refuse a correct part; boolean-unioning the shells here would be re-implementing a slicer, and
## Godot's CSG is explicitly not slicer-grade (track.md W1P.3 says so about holes).
##
## ## ASCII, on the project's standing rule
##
## Same argument `FrameExport.to_stl` makes: a text file is one a human can open, diff and check
## the first facet of, and a binary a pull request cannot review is a binary this project does not
## write.

## Millimetres per metre. THE conversion, and the only place it appears — `from_metres` is what
## every producer of printable geometry calls, so a part cannot be scaled in two files.
const MM_PER_M := 1000.0

## Below this a triangle has no area worth emitting, in mm². A degenerate facet is not a print
## failure by itself, but it is an edge pair that cannot be reasoned about — its two "edges" are
## the same segment — so it fails the check by name rather than being silently dropped.
const MIN_TRIANGLE_AREA_MM2 := 1.0e-9

## Below this the solid encloses nothing, in mm³. A cube 0.01 mm on a side is 1e-6 mm³, which is
## already far beneath anything a printer resolves, so the threshold refuses only shapes that are
## not parts.
const MIN_VOLUME_MM3 := 1.0e-6


## Metres to millimetres, for one point. The ONE place the factor lives.
##
## Takes a Vector3 rather than a float because every caller has points and not lengths, and a
## scalar version would be the second door through which a length could arrive unconverted.
##
## **`Vector3` is single precision, so this conversion is not exact and cannot be made so here.**
## A 63.5 mm tip radius modelled as 0.0635 m comes back as 63.500004 mm — 6e-8 relative, four
## orders beneath anything a printer resolves and irrelevant to a part, but it is the reason
## every assertion about converted geometry in this app is bounded relatively rather than to the
## bit. The same float32 floor `PropellerMountProfile` is pinned against for the same reason.
static func from_metres(point_m: Vector3) -> Vector3:
	return point_m * MM_PER_M


## Metres to millimetres for a whole triangle list, which is how producers that model in metres
## hand their geometry over. Goes through `from_metres` per point rather than scaling the array,
## so there is still one factor.
static func from_metres_triangles(triangles_m: Array) -> Array:
	var out: Array = []
	for triangle in triangles_m:
		out.append(PackedVector3Array([
			from_metres(triangle[0]), from_metres(triangle[1]), from_metres(triangle[2])]))
	return out


## Is this a solid a slicer can print? Returns
## `{"ok": bool, "reasons": Array[String], "volume_mm3": float, "triangle_count": int}`.
##
## `reasons` is a LIST rather than a first failure, because a producer that gets winding wrong
## usually gets it wrong everywhere and the volume sign says so too — reporting one of the two
## would send whoever reads it looking for a hole that is not there.
static func check_manifold(triangles: Array) -> Dictionary:
	var reasons: Array = []

	if triangles.is_empty():
		return {"ok": false, "reasons": ["the solid has no triangles"],
			"volume_mm3": 0.0, "triangle_count": 0}

	var degenerate := 0
	var volume_mm3 := 0.0
	# Directed edge -> how many times it was walked. Keyed on the two endpoints in order, so
	# a→b and b→a are different keys, which is the whole mechanism (see the header).
	var edges: Dictionary = {}

	for triangle in triangles:
		if triangle.size() != 3:
			reasons.append("a facet has %d vertices rather than 3" % triangle.size())
			continue
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]

		if (b - a).cross(c - a).length() * 0.5 < MIN_TRIANGLE_AREA_MM2:
			degenerate += 1
			continue

		# The divergence-theorem volume: the signed tetrahedron each facet makes with the origin.
		# Positive when the surface is wound outwards, and exactly negated when it is not.
		volume_mm3 += a.dot(b.cross(c)) / 6.0

		for pair in [[a, b], [b, c], [c, a]]:
			var key := _edge_key(pair[0], pair[1])
			edges[key] = int(edges.get(key, 0)) + 1

	if degenerate > 0:
		reasons.append("%d facet(s) have no area" % degenerate)

	var unmatched := 0
	var doubled := 0
	for key in edges:
		var count := int(edges[key])
		if count > 1:
			# The same edge walked twice the same way: two triangles wound alike across it.
			doubled += 1
		if not edges.has(_reverse_key(key)):
			unmatched += 1

	if unmatched > 0:
		reasons.append("the surface is not closed — %d edge(s) have no neighbour" % unmatched)
	if doubled > 0:
		reasons.append("the winding is inconsistent — %d edge(s) are shared by two facets that "
			% doubled + "face the same way")

	if absf(volume_mm3) < MIN_VOLUME_MM3:
		reasons.append("the solid encloses no volume (%.9f mm³)" % volume_mm3)
	elif volume_mm3 < 0.0:
		reasons.append("the solid is inside out — its facets enclose %.3f mm³ of outside"
			% -volume_mm3)

	return {
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"volume_mm3": volume_mm3,
		"triangle_count": triangles.size(),
	}


## Is each BODY a solid a slicer can print? Printed-room PR13. Returns check_manifold's shape, with every
## reason prefixed "body N:" (1-based), and the volume and triangle count summed over the bodies.
##
## ## Why bodies, and why the whole-file check could not stay
##
## `check_manifold` counts directed edges across the whole list. That is exactly right inside one closed
## surface, and wrong across two: a catalog frame is six plates, and where neighbouring arms meet their
## plates share IDENTICAL edges running the same way. Each plate is closed and outward on its own; the
## whole-file count sees the shared edge walked twice in one direction and calls it bad winding. Every
## catalog frame was refused for that (PR9). A slicer unions touching bodies exactly as it unions
## interpenetrating ones, which this file already allows.
##
## So the producer says where one body ends — it knows, because it built them one at a time — and each
## body gets the FULL check on its own: closed, consistently wound, outward, enclosing something. Nothing
## about the strictness inside a body is relaxed. A body is still refused for a single flipped facet, and
## an empty body is refused rather than skipped, because a producer that emits one has lost a part.
##
## `check_manifold` and `write` are unchanged: a caller with one list still gets the whole-file check.
static func check_bodies(bodies: Array) -> Dictionary:
	if bodies.is_empty():
		return {"ok": false, "reasons": ["there are no bodies"], "volume_mm3": 0.0, "triangle_count": 0}
	var reasons: Array = []
	var volume := 0.0
	var count := 0
	for index in bodies.size():
		var report := check_manifold(bodies[index])
		volume += float(report["volume_mm3"])
		count += int(report["triangle_count"])
		for reason in report["reasons"]:
			reasons.append("body %d: %s" % [index + 1, String(reason)])
	return {"ok": reasons.is_empty(), "reasons": reasons, "volume_mm3": volume, "triangle_count": count}


## Checks each body, then writes all of them as one file — or refuses by name and writes nothing, as
## `write` does. The file is the bodies' triangles in order, so its text is `to_ascii` of them flattened:
## the same text a print record hashes.
static func write_bodies(solid_name: String, bodies: Array, path: String) -> Dictionary:
	var report := check_bodies(bodies)
	if not bool(report["ok"]):
		return {"ok": false, "volume_mm3": float(report["volume_mm3"]),
			"reason": "%s: %s" % [solid_name, ", ".join(PackedStringArray(report["reasons"]))]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "volume_mm3": float(report["volume_mm3"]),
			"reason": "%s: could not open %s for writing" % [solid_name, path]}
	file.store_string(to_ascii(solid_name, flatten(bodies)))
	file.close()
	return {"ok": true, "reason": "", "volume_mm3": float(report["volume_mm3"])}


## The bodies' triangles in body order, as one list.
static func flatten(bodies: Array) -> Array:
	var out: Array = []
	for body in bodies:
		out.append_array(body)
	return out


## The solid as ASCII STL text, in millimetres. Does NOT check — `write` does, and a caller that
## wants the text of a broken solid to look at is a debugging case rather than an export.
##
## The facet normal is computed from the winding rather than carried alongside it. Most slicers
## ignore the stored normal and recompute from vertex order for exactly the reason this class
## checks winding at all; emitting a normal that disagreed with the winding would put the two
## definitions of "which way is out" in one file.
static func to_ascii(solid_name: String, triangles: Array) -> String:
	var out := PackedStringArray()
	out.append("solid %s" % _sanitise(solid_name))
	for triangle in triangles:
		if triangle.size() != 3:
			continue
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var normal := (b - a).cross(c - a).normalized()
		out.append("facet normal %.6f %.6f %.6f" % [normal.x, normal.y, normal.z])
		out.append("  outer loop")
		for point in [a, b, c]:
			out.append("    vertex %.5f %.5f %.5f" % [point.x, point.y, point.z])
		out.append("  endloop")
		out.append("endfacet")
	out.append("endsolid %s" % _sanitise(solid_name))
	return "\n".join(out) + "\n"


## Checks, then writes — or refuses, BY NAME. Returns
## `{"ok": bool, "reason": String, "volume_mm3": float}`.
##
## Nothing is written when the check fails. That is the whole posture of the slice: an STL on
## disk is a part somebody starts printing, and a file that a warning in a log said was bad is
## still a file next to five good ones in a folder six hours later.
##
## `reason` names the part first — "guard_duct_5in_cinewhoop: the surface is not closed …" — so
## the message is readable in a toast, in a log line and in a test failure without the caller
## having to reassemble it from two fields.
static func write(solid_name: String, triangles: Array, path: String) -> Dictionary:
	var report := check_manifold(triangles)
	if not bool(report["ok"]):
		return {"ok": false, "volume_mm3": float(report["volume_mm3"]),
			"reason": "%s: %s" % [solid_name, ", ".join(PackedStringArray(report["reasons"]))]}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "volume_mm3": float(report["volume_mm3"]),
			"reason": "%s: could not open %s for writing" % [solid_name, path]}
	file.store_string(to_ascii(solid_name, triangles))
	file.close()
	return {"ok": true, "reason": "", "volume_mm3": float(report["volume_mm3"])}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## A directed edge's key. Quantised to the nanometre before being made into a string, because two
## triangles that share a corner arrive at that corner by different arithmetic and float equality
## on a computed vertex is a hole the check would invent. A nanometre is four orders below the
## finest thing a printer does and four orders above float32's noise at part scale.
static func _edge_key(from_point: Vector3, to_point: Vector3) -> String:
	return "%s|%s" % [_point_key(from_point), _point_key(to_point)]


static func _reverse_key(key: String) -> String:
	var halves := key.split("|")
	if halves.size() != 2:
		return key
	return "%s|%s" % [halves[1], halves[0]]


static func _point_key(point: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [point.x, point.y, point.z]


## An STL solid name is a bare token on the header line, so a space in it makes the rest of the
## name look like the start of the geometry to a strict reader.
static func _sanitise(solid_name: String) -> String:
	var trimmed := solid_name.strip_edges().replace(" ", "_")
	return trimmed if trimmed != "" else "part"
