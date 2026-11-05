class_name PropExport
## A designed prop as a printable solid (spec, goal 10): one closed hub with a through bore, and one
## closed shell per blade. Geometry comes from `PropellerDocument.section_corners_mm`, the section the
## picture and the mass law read, so the file is a flat-section blade and the sheet says so.
##
## Each blade runs into the hub as its own closed shell, and `StlWriter.check_bodies` checks each body
## alone. A slicer unions them, as it does a motor stack. A flat root section meets a round hub on one
## line only, so the root is carried inward by a stub; the stub overlaps the hub and is not extra plastic,
## which is why `solid_mm3` leaves it out while the file's own summed volume keeps it.

## Thinnest section a 0.4 mm nozzle lays as one line. A stated guess at the process, not a measurement.
const MIN_SECTION_MM := 0.4
## Hub wall around the bore: two lines of the same nozzle.
const MIN_WALL_MM := 0.8
const HUB_SEGMENTS := 64
## Largest gap between stations, as a fraction of radius. Chord knots are always stations as well.
const MAX_STATION_STEP := 0.025
## How far past the point where its corners enter the hub the root stub reaches, mm.
const STUB_OVERLAP_MM := 0.5


## Everything about the solid. `ok` false means no file may be written, and `reason` is one line.
## {ok, reason, bodies, bore_mm, hub_radius_mm, hub_height_mm, solid_mm3, thinnest_mm, thinnest_r_frac}
static func build(doc: PropellerDocument, bore_mm: float) -> Dictionary:
	var out := {"ok": false, "reason": "", "bodies": [], "bore_mm": bore_mm, "hub_radius_mm": 0.0,
		"hub_height_mm": 0.0, "solid_mm3": 0.0, "thinnest_mm": 0.0, "thinnest_r_frac": 0.0}
	var radius := doc.radius_mm()
	if radius <= 0.0 or doc.blades < 1 or doc.chord.size() < 4:
		out.reason = "This prop has no blade to export."
		return out
	if bore_mm <= 0.0:
		out.reason = "This motor names no shaft, so the prop has no bore."
		return out
	var fracs := station_fracs(doc)
	var thinnest := INF
	var thinnest_at := 0.0
	for f: float in fracs:
		var t := doc.chord_at(f) * doc.thickness_ratio
		if t < thinnest:
			thinnest = t
			thinnest_at = f
	out.thinnest_mm = thinnest
	out.thinnest_r_frac = thinnest_at
	var hub_r := radius * PropellerDocument.HUB_RADIUS_TO_RADIUS
	out.hub_radius_mm = hub_r
	if thinnest < MIN_SECTION_MM:
		out.reason = "Too thin to make: %.2f mm at %d %% of radius, needs %.2f mm. Widen the chord there or raise thickness." % [
			thinnest, roundi(thinnest_at * 100.0), MIN_SECTION_MM]
		return out
	var bore_r := bore_mm * 0.5
	if hub_r - bore_r < MIN_WALL_MM:
		out.reason = "The %.1f mm bore leaves under %.1f mm of hub wall on a prop this size." % [bore_mm, MIN_WALL_MM]
		return out
	var root_corners := doc.section_corners_mm(fracs[0])
	var half_width := 0.0
	for c: Vector2 in root_corners:
		half_width = maxf(half_width, absf(c.x))
	var inner := bore_r + MIN_WALL_MM
	if half_width * half_width + inner * inner >= hub_r * hub_r:
		out.reason = "The blade root is wider than the hub can hold. Narrow the chord at the root."
		return out
	var stub_x := maxf(inner, sqrt(hub_r * hub_r - half_width * half_width) - STUB_OVERLAP_MM)

	var reach := 0.0
	for f: float in fracs:
		for c: Vector2 in doc.section_corners_mm(f):
			reach = maxf(reach, absf(c.y))
	# The rule the drawn hub keeps (PropellerMesh): deep enough to bury the root it carries.
	var height := maxf(radius * PropellerMesh.HUB_HEIGHT_TO_RADIUS, reach * 2.0)
	out.hub_height_mm = height

	var bodies: Array = [hub_triangles(hub_r, bore_r, height)]
	var blade := blade_triangles(doc, fracs, stub_x)
	var solid := float(StlWriter.check_manifold(bodies[0]).volume_mm3)
	var blade_alone := float(StlWriter.check_manifold(blade).volume_mm3)
	var section_area := doc.chord_at(fracs[0]) * doc.chord_at(fracs[0]) * doc.thickness_ratio
	solid += doc.blades * (blade_alone - section_area * (fracs[0] * radius - stub_x))
	for k in doc.blades:
		bodies.append(_placed(blade, TAU * float(k) / float(doc.blades), height * 0.5))
	out.bodies = bodies
	out.solid_mm3 = solid
	var report := StlWriter.check_bodies(bodies)
	if not bool(report.ok):
		out.reason = "This solid would not print: %s" % String(report.reasons[0])
		return out
	out.ok = true
	return out


## Writes the file, or refuses and writes nothing. {ok, reason}.
static func write(doc: PropellerDocument, bore_mm: float, path: String) -> Dictionary:
	var solid := build(doc, bore_mm)
	if not bool(solid.ok):
		return {"ok": false, "reason": String(solid.reason)}
	var name_of := doc.name if doc.name.strip_edges() != "" else "prop"
	var done := StlWriter.write_bodies(name_of, solid.bodies, path)
	return {"ok": bool(done.ok), "reason": String(done.reason)}


## Radius fractions from the first chord station to the tip: every chord knot, and more where they are far apart.
static func station_fracs(doc: PropellerDocument) -> PackedFloat64Array:
	var hub := PropellerDocument.HUB_RADIUS_TO_RADIUS
	var knots: Array[float] = [hub, 1.0]
	var i := 0
	while i < doc.chord.size():
		if doc.chord[i] > hub and doc.chord[i] < 1.0:
			knots.append(doc.chord[i])
		i += 2
	knots.sort()
	var out := PackedFloat64Array()
	for j in knots.size() - 1:
		var gap := knots[j + 1] - knots[j]
		if gap <= 1e-9:
			continue
		var steps := maxi(1, ceili(gap / MAX_STATION_STEP))
		for s in steps:
			out.append(knots[j] + gap * float(s) / float(steps))
	out.append(1.0)
	return out


## One blade along +X, shaft on Z, centred on z = 0. The first ring is the root section moved in to `stub_x`.
static func blade_triangles(doc: PropellerDocument, fracs: PackedFloat64Array, stub_x: float) -> Array:
	var radius := doc.radius_mm()
	var rings: Array = [_ring(doc.section_corners_mm(fracs[0]), stub_x)]
	for f: float in fracs:
		rings.append(_ring(doc.section_corners_mm(f), f * radius))
	var out: Array = []
	for i in rings.size() - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		for f in 4:
			var g := (f + 1) % 4
			# A twisted face is not flat, and any one diagonal bulges it: all alike is 2.6 % too much
			# plastic on an 8 inch prop, alternating leaves ribs. Fanning from the middle does neither.
			var mid := (a[f] + a[g] + b[f] + b[g]) * 0.25
			out.append(PackedVector3Array([a[f], a[g], mid]))
			out.append(PackedVector3Array([a[g], b[g], mid]))
			out.append(PackedVector3Array([b[g], b[f], mid]))
			out.append(PackedVector3Array([b[f], a[f], mid]))
	var root: PackedVector3Array = rings[0]
	var tip: PackedVector3Array = rings[rings.size() - 1]
	out.append(PackedVector3Array([root[0], root[2], root[1]]))
	out.append(PackedVector3Array([root[0], root[3], root[2]]))
	out.append(PackedVector3Array([tip[0], tip[1], tip[2]]))
	out.append(PackedVector3Array([tip[0], tip[2], tip[3]]))
	return out


## Mesh axes (radial, axial, tangential) to STL axes (x, y, z) = (radial, -tangential, axial): a pure
## rotation, so the prop keeps the hand it has on screen.
static func _ring(corners: PackedVector2Array, x_mm: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c: Vector2 in corners:
		out.append(Vector3(x_mm, -c.x, c.y))
	return out


static func _placed(triangles: Array, angle: float, lift: float) -> Array:
	var out: Array = []
	for t in triangles:
		var moved := PackedVector3Array()
		for p: Vector3 in t:
			moved.append(p.rotated(Vector3(0, 0, 1), angle) + Vector3(0, 0, lift))
		out.append(moved)
	return out


## The hub: a tube on Z from z = 0 to `height`, wound so the bore wall faces the axis.
static func hub_triangles(outer_r: float, bore_r: float, height: float) -> Array:
	var out: Array = []
	for i in HUB_SEGMENTS:
		var a := TAU * float(i) / float(HUB_SEGMENTS)
		var b := TAU * float((i + 1) % HUB_SEGMENTS) / float(HUB_SEGMENTS)
		var oa := Vector3(cos(a), sin(a), 0) * outer_r
		var ob := Vector3(cos(b), sin(b), 0) * outer_r
		var ia := Vector3(cos(a), sin(a), 0) * bore_r
		var ib := Vector3(cos(b), sin(b), 0) * bore_r
		var up := Vector3(0, 0, height)
		_quad(out, oa, ob, ob + up, oa + up)
		_quad(out, ib, ia, ia + up, ib + up)
		_quad(out, ia + up, oa + up, ob + up, ib + up)
		_quad(out, ib, ob, oa, ia)
	return out


static func _quad(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	out.append(PackedVector3Array([a, b, c]))
	out.append(PackedVector3Array([a, c, d]))
