class_name TestTerrain
extends RefCounted
## The terrain shape vocabulary, and the arithmetic every later slice will trust without checking.
##
## Nothing here draws anything. That is the point: F4 makes `height_at(x, z)` the ground authority
## and F5 builds the mesh from the same call, so a defect in this file does not look like a defect.
## It looks like a gate that is fine, or a hill that is slightly the wrong hill.
##
## The four things that could go wrong quietly, and where each is nailed down:
##
## **1. A shape could ignore one of its own dims.** A slope that ignores `direction_deg` runs the
## right way on the default 0° field and the wrong way on every other. §2 checks the slope at 37°
## and at 90°, because a fixture at 0° hides exactly this — `sin(0)` is 0 and a cross-axis leak
## multiplied by it disappears.
##
## **2. Outside the field could answer 0.** A gate two metres past the edge of a hillside is still
## on a hillside, and 0 there makes the below-ground warning lie in the one place the design says
## it must not. §6 checks it on a slope centred AWAY FROM THE ORIGIN, so a `height_at` that forgot
## the site has a centre cannot pass by coincidence.
##
## **3. `is_flat_at_zero()` could get clever.** F9 appends a terrain term to the best-lap
## fingerprint only when this is false. §7 enumerates all five shapes BY NAME and includes a slope
## of zero rise and a bowl of zero depth — the two the plausible "optimisation" would claim.
##
## **4. The file could be rewritten.** §8 round-trips a block of every shape through `from_data`
## and `to_data` and compares the JSON BYTES, including a flat block carrying a shape-specific key
## and a shape name from a build that does not exist yet.
##
## No fixture in this file is built by the function it is checking, and no golden number is pasted
## out of the implementation's output: the slope's total rise is the `rise_m` that was typed, the
## bowl's floor is the `depth_m` that was typed, and the round-trip fixtures are written by hand.

const TOL := 1.0e-6


static func run() -> Array:
	var results: Array = []
	var sections := {
		"flat": _flat(),
		"slope": _slope(),
		"bowl": _bowl(),
		"banked": _banked(),
		"enclosure": _enclosure(),
		"outside the extent": _outside_the_extent(),
		"is_flat_at_zero": _is_flat_at_zero(),
		"round trip": _round_trip(),
		"fingerprint term": _fingerprint_term(),
		"purity": _purity(),
		"the site": _the_site(),
		"one rule, one number": _one_rule_one_number(),
	}
	# A runtime error partway through a section aborts only that section and its append never runs,
	# so the suite would pass with its best checks silently deleted. Asserting each section produced
	# something is what makes the count trustworthy.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 1. Flat is zero, everywhere, including off-origin
# ---------------------------------------------------------------------------

static func _flat() -> Array:
	var results: Array = []
	var ground := Terrain.flat(80.0, 60.0, 25.0, -40.0)

	# CHECK 1. 200 sampled points, on a field whose centre is NOT the origin, plus its four corners
	# — a flat field is y = 0 by construction and that is what makes F9's conditional safe.
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var samples := _lattice(ground, 14, 14)
	samples.append_array(_corners(ground))
	for point in samples:
		var height: float = ground.height_at(point.x, point.y)
		if absf(height) > absf(worst):
			worst = height
			worst_at = point
	results.append(TestResult.new(
		"flat: height_at is 0.0 at every one of %d sampled points, corners included" % samples.size(),
		absf(worst) < TOL,
		"worst %.6f m at (%.1f, %.1f)" % [worst, worst_at.x, worst_at.y]))
	return results


# ---------------------------------------------------------------------------
# 2. The slope: linear along, constant across, and the direction is READ
# ---------------------------------------------------------------------------

static func _slope() -> Array:
	var results: Array = []
	var rise := 3.0
	# 37°, NOT 0°. A cross-axis term that leaks into the height scaled by sin(direction) is exactly
	# zero on a 0° fixture, which is how this defect ships.
	var ground := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0,
		{"rise_m": rise, "direction_deg": 37.0})
	var radians := deg_to_rad(37.0)
	var along_axis := Vector2(cos(radians), sin(radians))
	var across_axis := Vector2(-sin(radians), cos(radians))

	# CHECK 2a. Constant ACROSS the slope's axis. Points that share an along-coordinate and differ
	# only in their across-coordinate must be at the same height.
	var spread := 0.0
	for step in range(-6, 7):
		var base := along_axis * (float(step) * 3.0)
		var lowest := INF
		var highest := -INF
		for offset in range(-8, 9):
			var point := base + across_axis * (float(offset) * 1.5)
			var height: float = ground.height_at(point.x, point.y)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
		spread = maxf(spread, highest - lowest)
	results.append(TestResult.new(
		"slope at 37°: height is constant across the slope's axis",
		spread < TOL, "worst spread %.6f m over 17 points on 13 lines" % spread))

	# CHECK 2b. LINEAR along it — equal steps give equal rises, so the second difference is zero.
	var worst_bend := 0.0
	var previous_delta := INF
	var last := ground.height_at(-along_axis.x * 18.0, -along_axis.y * 18.0)
	for step in range(-17, 19):
		var point := along_axis * float(step)
		var height: float = ground.height_at(point.x, point.y)
		var delta := height - last
		if previous_delta < INF:
			worst_bend = maxf(worst_bend, absf(delta - previous_delta))
		previous_delta = delta
		last = height
	results.append(TestResult.new(
		"slope at 37°: height rises linearly along the slope's axis",
		worst_bend < TOL, "worst second difference %.9f m" % worst_bend))

	# CHECK 2c. The total rise across the field is the rise_m that was TYPED — 3.0 here, not a
	# number read back out of the implementation.
	var lowest_corner := INF
	var highest_corner := -INF
	for point in _lattice(ground, 30, 30) + _corners(ground):
		var height: float = ground.height_at(point.x, point.y)
		lowest_corner = minf(lowest_corner, height)
		highest_corner = maxf(highest_corner, height)
	results.append(TestResult.new(
		"slope at 37°: the total rise across the field is the 3.0 m that was typed",
		absf((highest_corner - lowest_corner) - rise) < 1.0e-4
			and absf(lowest_corner) < 1.0e-4 and absf(highest_corner - rise) < 1.0e-4,
		"%.4f m, from %.4f to %.4f" % [highest_corner - lowest_corner, lowest_corner, highest_corner]))

	# CHECK 3. The direction is read, not ignored: at 90° the slope runs along z, and a point at
	# +x is at the SAME height as one at −x while +z is higher than −z. A hard-coded 0° reverses
	# both of those statements.
	var ninety := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0,
		{"rise_m": rise, "direction_deg": 90.0})
	var east: float = ninety.height_at(40.0, 0.0)
	var west: float = ninety.height_at(-40.0, 0.0)
	var north: float = ninety.height_at(0.0, -25.0)
	var south: float = ninety.height_at(0.0, 25.0)
	results.append(TestResult.new(
		"slope at 90°: rises along z and is flat along x (direction_deg is read, not ignored)",
		absf(east - west) < TOL and south - north > 1.0,
		"x: %.4f vs %.4f; z: %.4f vs %.4f" % [east, west, north, south]))
	return results


# ---------------------------------------------------------------------------
# 3. The bowl: a pit, and a smooth one
# ---------------------------------------------------------------------------

static func _bowl() -> Array:
	var results: Array = []
	var depth := 2.5
	var ground := Terrain.shaped(Terrain.BOWL, 90.0, 50.0, {"depth_m": depth})

	# CHECK 4. The centre is at −depth_m, the rim is at 0, and nothing is above 0. The sign is the
	# whole check: a bowl that is really a hill passes every "it varies" test there is.
	var highest := -INF
	var highest_at := Vector2.ZERO
	for point in _lattice(ground, 20, 20) + _corners(ground):
		var height: float = ground.height_at(point.x, point.y)
		if height > highest:
			highest = height
			highest_at = point
	var rim_error := 0.0
	for turn in range(0, 24):
		var theta := TAU * float(turn) / 24.0
		var rim := Vector2(45.0 * cos(theta), 25.0 * sin(theta))
		rim_error = maxf(rim_error, absf(ground.height_at(rim.x, rim.y)))
	results.append(TestResult.new(
		"bowl: the centre is at −2.5 m, the rim is at 0, and no sampled point is above 0",
		absf(ground.height_at(0.0, 0.0) + depth) < TOL
			and rim_error < 1.0e-4 and highest <= TOL,
		"centre %.4f, worst rim %.6f, highest %.6f at (%.1f, %.1f)"
			% [ground.height_at(0.0, 0.0), rim_error, highest, highest_at.x, highest_at.y]))

	# CHECK 5. Monotonic from the centre out to the rim along four radii — including the two
	# diagonals, where a bowl built out of the ABSOLUTE VALUE of a linear term goes flat (and, on
	# one of them, never leaves the floor at all).
	var worst_radius := ""
	var worst_step := 0.0
	for turn in range(0, 4):
		var theta := deg_to_rad(45.0 + 90.0 * float(turn))
		var previous := ground.height_at(0.0, 0.0)
		for step in range(1, 41):
			var r := float(step) / 40.0
			var point := Vector2(45.0 * r * cos(theta), 25.0 * r * sin(theta))
			var height: float = ground.height_at(point.x, point.y)
			var gain := height - previous
			if gain <= 1.0e-9 and (worst_radius == "" or gain < worst_step):
				worst_radius = "%.0f°" % rad_to_deg(theta)
				worst_step = gain
			previous = height
	results.append(TestResult.new(
		"bowl: rises strictly from the centre to the rim along all four diagonal radii",
		worst_radius == "",
		"all four strictly rising" if worst_radius == ""
			else "flat or falling on the %s radius (%.9f m)" % [worst_radius, worst_step]))
	return results


# ---------------------------------------------------------------------------
# 4. The bank: one edge, and the named one
# ---------------------------------------------------------------------------

static func _banked() -> Array:
	var results: Array = []
	var bank_height := 3.0
	var bank_width := 12.0
	var ground := Terrain.shaped(Terrain.BANKED, 100.0, 80.0, {
		"bank_height_m": bank_height, "bank_width_m": bank_width,
		"bank_edge": Terrain.NORTH})

	# CHECK 6. The bank rises only within bank_width_m of the named edge; everywhere else is flat
	# at 0; the peak is bank_height_m. The "everywhere else" half is what fails when a bank is
	# applied to all four edges — and it fails on the OTHER three edges, not in the middle.
	var peak: float = ground.height_at(0.0, -40.0)
	var elsewhere := 0.0
	var elsewhere_at := Vector2.ZERO
	for point in _lattice(ground, 24, 24) + _corners(ground):
		# Inside the bank's own strip, which runs from the north edge (z = −40) inwards.
		if point.y < -40.0 + bank_width:
			continue
		var height: float = ground.height_at(point.x, point.y)
		if absf(height) > absf(elsewhere):
			elsewhere = height
			elsewhere_at = point
	results.append(TestResult.new(
		"banked: the peak is the 3.0 m typed, and the field outside the 12 m strip is flat at 0",
		absf(peak - bank_height) < TOL and absf(elsewhere) < TOL,
		"peak %.4f m; worst outside %.6f m at (%.1f, %.1f)"
			% [peak, elsewhere, elsewhere_at.x, elsewhere_at.y]))

	# CHECK 7. bank_edge is read: banking the south edge gives the north field mirrored in z.
	var south := Terrain.shaped(Terrain.BANKED, 100.0, 80.0, {
		"bank_height_m": bank_height, "bank_width_m": bank_width,
		"bank_edge": Terrain.SOUTH})
	var mirror_error := 0.0
	var same_count := 0
	var compared := 0
	for point in _lattice(ground, 18, 18):
		var here: float = ground.height_at(point.x, point.y)
		var there: float = south.height_at(point.x, -point.y)
		mirror_error = maxf(mirror_error, absf(here - there))
		compared += 1
		if absf(here - south.height_at(point.x, point.y)) < TOL:
			same_count += 1
	results.append(TestResult.new(
		"banked: north and south are mirror images in z, and are not the same field",
		mirror_error < TOL and same_count < compared,
		"mirror error %.6f m; %d/%d points identical unmirrored"
			% [mirror_error, same_count, compared]))
	return results


# ---------------------------------------------------------------------------
# 5. The enclosure floor is flat at zero
# ---------------------------------------------------------------------------

static func _enclosure() -> Array:
	var results: Array = []
	# CHECK 8. Walls, roof and pillars are geometry for F5 and obstacles for F6. They are NOT
	# ground: an enclosure whose floor sits at the wall height puts the aircraft on the roof.
	var ground := Terrain.shaped(Terrain.ENCLOSURE, 40.0, 30.0,
		{"wall_height_m": 5.0, "roofed": true, "pillar_spacing_m": 8.0})
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var samples := _lattice(ground, 16, 16)
	samples.append_array(_corners(ground))
	for point in samples:
		var height: float = ground.height_at(point.x, point.y)
		if absf(height) > absf(worst):
			worst = height
			worst_at = point
	results.append(TestResult.new(
		"enclosure: the floor is flat at 0 at all %d sampled points, wall_height_m notwithstanding"
			% samples.size(),
		absf(worst) < TOL,
		"worst %.6f m at (%.1f, %.1f)" % [worst, worst_at.x, worst_at.y]))
	return results


# ---------------------------------------------------------------------------
# 6. Outside the extent is the nearest boundary point
# ---------------------------------------------------------------------------

static func _outside_the_extent() -> Array:
	var results: Array = []
	# CENTRED AWAY FROM THE ORIGIN. A height_at that assumes the field is centred on (0, 0) answers
	# plausibly on every fixture that is, and F4's ground authority is built on this being right.
	var ground := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0,
		{"rise_m": 4.0, "direction_deg": 20.0}, 30.0, -10.0)

	# CHECK 9. Outside, the answer is the height at the nearest point on the boundary — and on this
	# slope that value is nowhere near 0, so "returns 0.0 outside" is visibly wrong.
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var nearest_is_zero := 0
	var checked := 0
	var offsets := [Vector2(9.0, 0.0), Vector2(-9.0, 0.0), Vector2(0.0, 7.0), Vector2(0.0, -7.0),
		Vector2(25.0, 25.0), Vector2(-25.0, 18.0)]
	for point in _lattice(ground, 9, 9) + _corners(ground):
		for offset in offsets:
			var outside: Vector2 = point + offset
			if ground.contains(outside.x, outside.y):
				continue
			var nearest := Vector2(
				clampf(outside.x, 30.0 - 50.0, 30.0 + 50.0),
				clampf(outside.y, -10.0 - 30.0, -10.0 + 30.0))
			var error: float = absf(ground.height_at(outside.x, outside.y)
				- ground.height_at(nearest.x, nearest.y))
			checked += 1
			if absf(ground.height_at(outside.x, outside.y)) < TOL:
				nearest_is_zero += 1
			if error > worst:
				worst = error
				worst_at = outside
	results.append(TestResult.new(
		"outside the extent: height_at equals the height at the nearest boundary point",
		checked > 0 and worst < TOL,
		"%d points outside, worst error %.6f m at (%.1f, %.1f)"
			% [checked, worst, worst_at.x, worst_at.y]))
	# And the check above would be satisfied by a boundary that happened to be 0 everywhere, which
	# on this slope it is not — stated separately so the first check cannot pass vacuously.
	results.append(TestResult.new(
		"outside the extent: and that boundary height is not 0 (so returning 0 would be visible)",
		checked > 0 and nearest_is_zero * 8 < checked,
		"%d of %d outside points read 0.0" % [nearest_is_zero, checked]))
	return results


# ---------------------------------------------------------------------------
# 7. is_flat_at_zero() is shape == FLAT and nothing else
# ---------------------------------------------------------------------------

static func _is_flat_at_zero() -> Array:
	var results: Array = []
	# CHECK 10. Enumerated BY NAME, and including the two shapes a plausible "optimisation" would
	# claim: a slope whose rise is 0 and a bowl whose depth is 0. F9 appends a terrain term only
	# when this is false, so the day it starts reasoning about dims, a build that reads a zero-rise
	# slope differently re-hashes and orphans every best lap set on one.
	results.append(TestResult.new(
		"is_flat_at_zero: true for flat", Terrain.flat(50.0, 50.0).is_flat_at_zero(), "flat"))
	var degenerate := {
		Terrain.SLOPE: {"rise_m": 0.0, "direction_deg": 0.0},
		Terrain.BOWL: {"depth_m": 0.0},
		Terrain.BANKED: {"bank_height_m": 0.0, "bank_width_m": 0.0, "bank_edge": Terrain.NORTH},
		Terrain.ENCLOSURE: {"wall_height_m": 0.0, "roofed": false, "pillar_spacing_m": 0.0},
	}
	for named in [Terrain.SLOPE, Terrain.BOWL, Terrain.BANKED, Terrain.ENCLOSURE]:
		var ordinary := Terrain.shaped(named, 50.0, 50.0)
		var zeroed := Terrain.shaped(named, 50.0, 50.0, degenerate[named])
		results.append(TestResult.new(
			"is_flat_at_zero: false for %s, and still false when its dims are all zero" % named,
			not ordinary.is_flat_at_zero() and not zeroed.is_flat_at_zero(),
			"%s / %s" % [ordinary.is_flat_at_zero(), zeroed.is_flat_at_zero()]))
	results.append(TestResult.new(
		"is_flat_at_zero: exactly one of the five shapes in SHAPES claims it",
		Terrain.SHAPES.size() == 5
			and _flat_claimers(Terrain.SHAPES) == 1,
		"%d of %d" % [_flat_claimers(Terrain.SHAPES), Terrain.SHAPES.size()]))
	return results


static func _flat_claimers(shapes: Array) -> int:
	var count := 0
	for named in shapes:
		if Terrain.shaped(named, 50.0, 50.0).is_flat_at_zero():
			count += 1
	return count


# ---------------------------------------------------------------------------
# 8. Every shape reaches from_data, and the file comes back byte-identical
# ---------------------------------------------------------------------------

## Blocks written BY HAND, one per shape, in the key order the app's own writer produces —
## `JsonStore` calls `JSON.stringify` and that sorts keys, so this IS what is on disk. Not produced
## by `to_data()`: a fixture built by the writer it is checking is a round trip of the code with
## itself, and cannot fail.
const FIXTURES := {
	"flat": '{"center_x_m":0.0,"center_z_m":0.0,"length_m":120.0,"rise_m":1.5,"shape":"flat","width_m":120.0}',
	"slope": '{"center_x_m":12.5,"center_z_m":-3.0,"direction_deg":65.0,"length_m":70.0,"rise_m":4.25,"shape":"slope","width_m":90.0}',
	"bowl": '{"center_x_m":0.0,"center_z_m":0.0,"depth_m":3.5,"length_m":80.0,"shape":"bowl","width_m":80.0}',
	"banked": '{"bank_edge":"east","bank_height_m":2.75,"bank_width_m":9.0,"center_x_m":0.0,"center_z_m":0.0,"length_m":60.0,"shape":"banked","width_m":100.0}',
	"enclosure": '{"center_x_m":-8.0,"center_z_m":0.0,"length_m":45.0,"pillar_spacing_m":6.0,"roofed":true,"shape":"enclosure","wall_height_m":4.5,"width_m":30.0}',
}


static func _round_trip() -> Array:
	var results: Array = []

	# CHECK 11. Every shape in SHAPES is reachable from a file, and every one of them writes back
	# the bytes it was read from — INCLUDING the flat block, which here carries a shape-specific
	# key. Dropping dims "because flat has none" is how a builder's number disappears on first save.
	var unreached: Array[String] = []
	var rewritten: Array[String] = []
	for named in Terrain.SHAPES:
		var text: String = FIXTURES[String(named)]
		var block: Variant = JSON.parse_string(text)
		var ground := Terrain.from_data(block)
		if ground.shape != named:
			unreached.append(String(named))
		var back := JSON.stringify(ground.to_data())
		if back != text:
			rewritten.append("%s -> %s" % [named, back])
	results.append(TestResult.new(
		"round trip: all %d shapes reach from_data and write back byte-identically"
			% Terrain.SHAPES.size(),
		unreached.is_empty() and rewritten.is_empty(),
		"unreached: %s; rewritten: %s" % [
			"none" if unreached.is_empty() else ", ".join(unreached),
			"none" if rewritten.is_empty() else "; ".join(rewritten)]))

	# The dims actually arrived, rather than the block round-tripping through `_raw` with nothing
	# read out of it — stated by value, per shape, so the check above cannot pass on a class that
	# parsed nothing.
	var read_back := Terrain.from_data(JSON.parse_string(FIXTURES["banked"]))
	results.append(TestResult.new(
		"round trip: the dims are READ, not merely carried (banked, by value)",
		absf(float(read_back.dims.get("bank_height_m", 0.0)) - 2.75) < TOL
			and String(read_back.dims.get("bank_edge", "")) == Terrain.EAST
			and absf(read_back.height_at(50.0, 0.0) - 2.75) < TOL,
		"%.2f m at the %s edge; height %.3f"
			% [float(read_back.dims.get("bank_height_m", 0.0)),
				read_back.dims.get("bank_edge", "?"), read_back.height_at(50.0, 0.0)]))

	# A FILE THIS CLASS WROTE ITSELF, not one it was handed. The check above passes on a `to_data()`
	# that writes nothing of its own and lets the record it was read from carry every dim through —
	# measured, on this slice, on 2026-09-22: the "drops dims for flat" mutation did not redden it.
	# A terrain built in code has no record behind it, which is the path F5's editor takes the
	# moment a builder types a rise and saves.
	var authored := {
		Terrain.FLAT: {"rise_m": 1.5},
		Terrain.SLOPE: {"rise_m": 4.25, "direction_deg": 65.0},
		Terrain.BOWL: {"depth_m": 3.5},
		Terrain.BANKED: {"bank_height_m": 2.75, "bank_width_m": 9.0, "bank_edge": Terrain.EAST},
		Terrain.ENCLOSURE: {"wall_height_m": 4.5, "roofed": true, "pillar_spacing_m": 6.0},
	}
	var lost: Array[String] = []
	for named in Terrain.SHAPES:
		var dims: Dictionary = authored[named]
		var built := Terrain.shaped(named, 90.0, 70.0, dims, 5.0, -5.0)
		var written: Dictionary = built.to_data()
		for key in dims:
			if not written.has(key) or written[key] != dims[key]:
				lost.append("%s.%s" % [named, key])
		var reopened := Terrain.from_data(written)
		if reopened.fingerprint_term() != built.fingerprint_term():
			lost.append("%s (term)" % named)
	results.append(TestResult.new(
		"round trip: a terrain built in code writes its own dims — flat's included",
		lost.is_empty(),
		"nothing lost" if lost.is_empty() else "lost: " + ", ".join(lost)))

	# THE KEY THAT WAS NEVER THERE. F1's own byte-identity fixture carries a block with no centre in
	# it, and a writer that adds one "because the class has one" grows every hand-written file by
	# two keys. It stays absent while it is still the default, and appears the moment it is not.
	var centreless := '{"length_m":150.0,"shape":"flat","width_m":200.0}'
	var kept := Terrain.from_data(JSON.parse_string(centreless))
	var moved := Terrain.from_data(JSON.parse_string(centreless))
	moved.center_x_m = 40.0
	results.append(TestResult.new(
		"round trip: a block with no centre does not grow one — until the centre is moved",
		JSON.stringify(kept.to_data()) == centreless
			and moved.to_data().has("center_x_m")
			and absf(float(moved.to_data().get("center_x_m", 0.0)) - 40.0) < TOL
			and not moved.to_data().has("center_z_m"),
		"%s then %s" % [JSON.stringify(kept.to_data()), JSON.stringify(moved.to_data())]))

	# CHECK 12. A shape name from a build that does not exist yet. It reads as flat, the file opens,
	# and the name is written back — an older build flattening a field somebody sculpted would be
	# the quiet-rewrite failure arriving through the reader instead of the writer.
	var future := '{"center_x_m":0.0,"center_z_m":0.0,"crater_m":9.0,"length_m":70.0,"shape":"volcano","width_m":70.0}'
	var opened := Terrain.from_data(JSON.parse_string(future))
	results.append(TestResult.new(
		"round trip: an unknown shape reads as flat, opens, and keeps its name in the file",
		opened != null and opened.shape == Terrain.FLAT
			and absf(opened.height_at(10.0, -20.0)) < TOL
			and JSON.stringify(opened.to_data()) == future,
		"shape %s, height %.3f, bytes %s" % [
			"null" if opened == null else String(opened.shape),
			0.0 if opened == null else opened.height_at(10.0, -20.0),
			"identical" if opened != null and JSON.stringify(opened.to_data()) == future
				else "REWRITTEN"]))

	# AND THE BUILDER WHO DELIBERATELY CHOOSES FLAT. Keeping the unknown name is right only while
	# nobody has touched the shape; re-emitting it unconditionally makes flat the one shape that
	# cannot be selected on a file a newer build wrote. There is no error and no way to tell from
	# the screen — the editor says flat and the file says volcano.
	var chosen := Terrain.from_data(JSON.parse_string(future))
	chosen.shape = Terrain.FLAT
	var also := Terrain.from_data(JSON.parse_string(future))
	also.shape = Terrain.BOWL
	results.append(TestResult.new(
		"round trip: choosing a shape clears the unknown name — flat is selectable again",
		String(chosen.to_data().get("shape", "")) == String(Terrain.FLAT)
			and String(also.to_data().get("shape", "")) == String(Terrain.BOWL),
		"chose flat -> %s; chose bowl -> %s" % [
			chosen.to_data().get("shape", "?"), also.to_data().get("shape", "?")]))

	# And the two other ways a file arrives damaged, on JsonStore's rule that a bad file is not a
	# fatal error: a block that is not a dictionary at all, and one with nothing in it.
	var nonsense := Terrain.from_data("not a terrain")
	var empty := Terrain.from_data({})
	results.append(TestResult.new(
		"round trip: a block that is not a dictionary, and an empty one, both open as flat defaults",
		nonsense != null and nonsense.shape == Terrain.FLAT
			and absf(nonsense.extent().x - Terrain.DEFAULT_WIDTH_M) < TOL
			and empty != null and empty.shape == Terrain.FLAT,
		"%s / %s" % [
			"null" if nonsense == null else String(nonsense.shape),
			"null" if empty == null else String(empty.shape)]))
	return results


# ---------------------------------------------------------------------------
# 9. The fingerprint term tells two different terrains apart
# ---------------------------------------------------------------------------

static func _fingerprint_term() -> Array:
	var results: Array = []
	# F9 hashes this into the best-lap fingerprint. The shape's NAME is not enough: a lap set on a
	# 1 m rise must not be presented as the best on a 6 m one, and both are "slope".
	var one := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0, {"rise_m": 1.0, "direction_deg": 30.0})
	var six := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0, {"rise_m": 6.0, "direction_deg": 30.0})
	var turned := Terrain.shaped(Terrain.SLOPE, 100.0, 60.0, {"rise_m": 1.0, "direction_deg": 31.0})
	var wider := Terrain.shaped(Terrain.SLOPE, 101.0, 60.0, {"rise_m": 1.0, "direction_deg": 30.0})
	results.append(TestResult.new(
		"fingerprint term: two slopes differing only in rise_m produce different terms",
		one.fingerprint_term() != six.fingerprint_term(),
		"%s vs %s" % [one.fingerprint_term(), six.fingerprint_term()]))
	results.append(TestResult.new(
		"fingerprint term: and differing only in direction_deg, or only in width, does too",
		one.fingerprint_term() != turned.fingerprint_term()
			and one.fingerprint_term() != wider.fingerprint_term(),
		"%s | %s | %s" % [one.fingerprint_term(), turned.fingerprint_term(),
			wider.fingerprint_term()]))
	results.append(TestResult.new(
		"fingerprint term: names its shape, and every shape's term is distinct",
		one.fingerprint_term().begins_with(String(Terrain.SLOPE))
			and _distinct_terms(Terrain.SHAPES) == Terrain.SHAPES.size(),
		"%d distinct of %d" % [_distinct_terms(Terrain.SHAPES), Terrain.SHAPES.size()]))
	# Stable: the same terrain read twice gives the same term, or every best lap re-hashes on load.
	var written := Terrain.from_data(JSON.parse_string(FIXTURES["bowl"]))
	var reread := Terrain.from_data(JSON.parse_string(JSON.stringify(written.to_data())))
	results.append(TestResult.new(
		"fingerprint term: survives a save and a reload unchanged",
		written.fingerprint_term() == reread.fingerprint_term(),
		"%s vs %s" % [written.fingerprint_term(), reread.fingerprint_term()]))
	return results


static func _distinct_terms(shapes: Array) -> int:
	var seen := {}
	for named in shapes:
		seen[Terrain.shaped(named, 50.0, 50.0).fingerprint_term()] = true
	return seen.size()


# ---------------------------------------------------------------------------
# 10. height_at is pure
# ---------------------------------------------------------------------------

static func _purity() -> Array:
	var results: Array = []
	# CHECK 13. The same 1000 points, asked in a shuffled order and in a sorted one. The mutation
	# this is written against is a cache keyed on x — so the points deliberately REUSE x values with
	# different z, which is the only arrangement in which such a cache answers wrongly.
	var ground := Terrain.shaped(Terrain.BOWL, 90.0, 70.0, {"depth_m": 3.0})
	var points: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	for index in range(0, 1000):
		# 17 distinct x values across 1000 points: every x recurs, with a different z each time.
		points.append(Vector2(float(index % 17) * 5.0 - 40.0, rng.randf_range(-45.0, 45.0)))

	var shuffled := points.duplicate()
	shuffled.shuffle()
	var first := {}
	for point in shuffled:
		first[point] = ground.height_at(point.x, point.y)
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var disagreements := 0
	var worst := 0.0
	for point in sorted:
		var again: float = ground.height_at(point.x, point.y)
		var before: float = first[point]
		if absf(again - before) > 0.0:
			disagreements += 1
			worst = maxf(worst, absf(again - before))
	results.append(TestResult.new(
		"purity: 1000 heights asked in shuffled order match the same 1000 asked in sorted order",
		first.size() == points.size() and disagreements == 0,
		"%d distinct points, %d disagreements, worst %.6f m"
			% [first.size(), disagreements, worst]))
	return results


# ---------------------------------------------------------------------------
# 11. The site's block did not move
# ---------------------------------------------------------------------------

## A sites.json exactly as F1/F2 write one. Written by hand, here, so that this is a check against
## the FORMAT rather than against whatever this slice's writer happens to produce.
## The one site inside it, as its own bytes — the literal the writer must reproduce. Written out
## rather than taken from `JSON.stringify(record)`, which would compare the reader with itself.
const SITE_BYTES := '{"elevation_m":0.0,"id":"default_site","name":"Field","obstacles":[],"terrain":{"center_x_m":0.0,"center_z_m":0.0,"length_m":120.0,"shape":"flat","width_m":120.0}}'

const SITES_FIXTURE := '{"schema":1,"selected":"default_site","sites":[{"elevation_m":0.0,"id":"default_site","name":"Field","obstacles":[],"terrain":{"center_x_m":0.0,"center_z_m":0.0,"length_m":120.0,"shape":"flat","width_m":120.0}}]}'


static func _the_site() -> Array:
	var results: Array = []
	var file: Variant = JSON.parse_string(SITES_FIXTURE)
	var record: Dictionary = (file as Dictionary)["sites"][0]
	var site := Site.from_data(record)

	# The block is behind a Terrain now and the file did not move: the same record, written back,
	# is the same bytes. This is the F1 finding — Lothal quietly editing every file a builder owns.
	results.append(TestResult.new(
		"the site: an F1-written record round-trips byte-identically through the new Terrain",
		JSON.stringify(site.to_data()) == SITE_BYTES,
		JSON.stringify(site.to_data())))

	# And the three accessors answer exactly what they answered before.
	results.append(TestResult.new(
		"the site: extent(), center() and contains() answer identically to F1's dictionary",
		site.extent() == Vector2(120.0, 120.0) and site.center() == Vector2.ZERO
			and site.contains(Vector3(60.0, 3.0, -60.0))
			and not site.contains(Vector3(60.1, 3.0, 0.0)),
		"%s / %s" % [site.extent(), site.center()]))

	# A record with no terrain block does not GAIN one. The F1 review finding, in the one place
	# this slice could have re-broken it.
	var bare := {"id": "bando", "name": "Bando", "elevation_m": 12.0}
	var reopened := Site.from_data(bare)
	results.append(TestResult.new(
		"the site: a record with no terrain block does not grow one, and still has an extent",
		not reopened.to_data().has("terrain")
			and JSON.stringify(reopened.to_data()) == JSON.stringify(bare)
			and reopened.extent().x > 0.0,
		JSON.stringify(reopened.to_data())))

	# THE BLOCK A BUILDER AUTHORS ON A RECORD THAT NEVER HAD ONE. F3 shipped this as a regression:
	# the "was there a block in the file" flag is set at load and never again, so picking a shape on
	# a hand-edited site and saving erased it — no error, and the bowl is simply gone on reload.
	# Under F1 the predicate was on the value and could not go stale.
	var hand_edited := {"id": "bando", "name": "Bando", "elevation_m": 12.0}
	var authored := Site.from_data(hand_edited)
	authored.terrain = Terrain.shaped(Terrain.BOWL, 120.0, 120.0, {"depth_m": 4.0})
	var saved: Dictionary = authored.to_data()
	var reloaded := Site.from_data(saved)
	results.append(TestResult.new(
		"the site: a terrain authored on a record with no block is written, and survives a reload",
		saved.has("terrain") and reloaded.terrain.shape == Terrain.BOWL
			and absf(reloaded.terrain.height_at(0.0, 0.0) + 4.0) < TOL,
		"%s; reloaded as %s at %.2f m"
			% [JSON.stringify(saved), reloaded.terrain.shape,
				reloaded.terrain.height_at(0.0, 0.0)]))

	# And the silence it must not break: the SAME record, untouched, still does not grow a block.
	var untouched := Site.from_data(hand_edited)
	results.append(TestResult.new(
		"the site: and the same record, left alone, still does not grow one",
		not untouched.to_data().has("terrain")
			and JSON.stringify(untouched.to_data()) == JSON.stringify(hand_edited),
		JSON.stringify(untouched.to_data())))

	# The site's own centre reaches the terrain: a height asked in WORLD coordinates on an off-origin
	# site is the height at that place, not at the same offset from the origin. F4's ground authority
	# is built on this and nothing before F4 would notice it being wrong.
	var away := Site.from_data({"id": "away", "name": "Away", "elevation_m": 0.0,
		"terrain": {"shape": "slope", "width_m": 100.0, "length_m": 100.0,
			"center_x_m": 200.0, "center_z_m": 0.0, "rise_m": 5.0, "direction_deg": 0.0}})
	results.append(TestResult.new(
		"the site: height_at is in WORLD coordinates, resolved against the site's own centre",
		absf(away.terrain.height_at(200.0, 0.0) - 2.5) < TOL
			and absf(away.terrain.height_at(150.0, 0.0)) < TOL
			and absf(away.terrain.height_at(250.0, 0.0) - 5.0) < TOL
			and absf(away.terrain.height_at(0.0, 0.0)) < TOL,
		"centre %.3f, west edge %.3f, east edge %.3f, origin %.3f" % [
			away.terrain.height_at(200.0, 0.0), away.terrain.height_at(150.0, 0.0),
			away.terrain.height_at(250.0, 0.0), away.terrain.height_at(0.0, 0.0)]))
	return results


# ---------------------------------------------------------------------------
# 12. One rule for the half-extent, one number for the default
# ---------------------------------------------------------------------------

static func _one_rule_one_number() -> Array:
	var results: Array = []

	# `contains()` halved the width and `height_at()` halved its absolute value: two rules for one
	# question, which answered differently for a field whose width was typed negative — outside
	# every field, and still on a slope. Nothing in F3 needed a negative width; the point is that
	# the two answers must come from the same place or they drift.
	var ground := Terrain.shaped(Terrain.SLOPE, -80.0, 60.0,
		{"rise_m": 4.0, "direction_deg": 0.0})
	var inside := ground.contains(39.0, 0.0)
	var outside := ground.contains(45.0, 0.0)
	var boundary_agrees := absf(ground.height_at(45.0, 0.0) - ground.height_at(40.0, 0.0)) < TOL
	results.append(TestResult.new(
		"one rule: contains() and height_at() halve the extent the same way, negative width and all",
		inside and not outside and boundary_agrees
			and ground.half_extent() == Vector2(40.0, 30.0),
		"inside %s, outside %s, boundary agrees %s, half %s"
			% [inside, outside, boundary_agrees, ground.half_extent()]))

	# ONE NUMBER, NAMED TWICE. `Terrain.to_data()` omits a key still equal to the default the reader
	# supplies, so a second, independent 120 in `Site` means a width authored at Site's new default
	# is written absent and read back as Terrain's old one — an authored value silently changing.
	# Asserted by name, because the two being equal today is exactly what makes the drift invisible.
	results.append(TestResult.new(
		"one number: Site's default extent IS Terrain's, not a second copy of it",
		Site.DEFAULT_WIDTH_M == Terrain.DEFAULT_WIDTH_M
			and Site.DEFAULT_LENGTH_M == Terrain.DEFAULT_LENGTH_M,
		"site %.1f x %.1f, terrain %.1f x %.1f" % [Site.DEFAULT_WIDTH_M, Site.DEFAULT_LENGTH_M,
			Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M]))

	# And the consequence, demonstrated rather than argued: a width equal to the default is written
	# absent, and reading it back gives the same number. The moment the two constants differ, this
	# is the check that goes red with a real value in its detail.
	var authored_at_default := Terrain.from_data(
		JSON.parse_string('{"length_m":150.0,"shape":"flat"}'))
	authored_at_default.width_m = Site.DEFAULT_WIDTH_M
	var written: Dictionary = authored_at_default.to_data()
	results.append(TestResult.new(
		"one number: a width authored at Site's default is written absent and reads back the same",
		not written.has("width_m")
			and absf(Terrain.from_data(written).width_m - Site.DEFAULT_WIDTH_M) < TOL,
		"%s -> %.1f m" % [JSON.stringify(written), Terrain.from_data(written).width_m]))
	return results


# ---------------------------------------------------------------------------
# Sampling helpers. Points are (x, z) packed in a Vector2 — y is not a height here.
# ---------------------------------------------------------------------------

static func _lattice(ground: Terrain, across: int, down: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var middle := ground.center()
	var half := ground.extent() * 0.5
	for i in range(0, across):
		for j in range(0, down):
			points.append(Vector2(
				middle.x - half.x + 2.0 * half.x * float(i) / float(across - 1),
				middle.y - half.y + 2.0 * half.y * float(j) / float(down - 1)))
	return points


static func _corners(ground: Terrain) -> Array[Vector2]:
	var middle := ground.center()
	var half := ground.extent() * 0.5
	return [
		Vector2(middle.x - half.x, middle.y - half.y),
		Vector2(middle.x + half.x, middle.y - half.y),
		Vector2(middle.x - half.x, middle.y + half.y),
		Vector2(middle.x + half.x, middle.y + half.y),
	]
