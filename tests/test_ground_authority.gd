class_name TestGroundAuthority
extends RefCounted
## F4: the terrain, and not y = 0, is what "below ground" and "you crashed" mean.
##
## ---------------------------------------------------------------------------
## §1 IS THE REGRESSION NET, AND ITS NUMBERS DID NOT COME FROM THIS CODE
## ---------------------------------------------------------------------------
##
## Every literal in §1 was printed by the SHIPPED code before a line of F4 was written — a
## throwaway script run at e731f37, its output pasted here, the script deleted. A golden value
## read out of the implementation it guards is a test that cannot fail, and this is the one
## section whose whole job is to fail if F4 moved anything on flat ground. A flat-at-zero site is
## what every course in the wild is, so "flat is bit-identical" is the promise that keeps the
## `p_site = null` / `p_terrain = null` defaults honest rather than merely convenient.
##
## ---------------------------------------------------------------------------
## WHY THE HILL IS A SLOPE AND NOT A "HILL"
## ---------------------------------------------------------------------------
##
## Terrain has no dome. A slope of `rise_m` 20 reads 10.0 at its own centre and 0 / 20 at the two
## ends, which gives all three things these checks need from one shape: a known 10 m ground under
## a gate, and two points at the SAME authored height sitting over different ground. The site is
## deliberately centred at x = 100 rather than at the origin, because `height_at` resolves world
## coordinates against the site's own centre and a fixture centred at (0, 0) cannot tell a
## correct implementation from one that forgot the origin exists.
##
## ---------------------------------------------------------------------------
## THE CRASH TEST IS CALLED, NOT READ
## ---------------------------------------------------------------------------
##
## §3 calls `main.gd`'s `_check_crash` directly — it is static and pure for exactly that reason —
## and §6 then reads the same function's SOURCE to prove it is still arithmetic. Neither alone is
## enough: the call cannot see a raycast that agrees with the arithmetic today, and the scan
## cannot see a sign error. The scan also asserts the things it expects to FIND, so deleting or
## renaming the function reddens it instead of making it vacuously true.

const MAIN_SCRIPT := preload("res://src/scenes/main.gd")
const MAIN_PATH := "res://src/scenes/main.gd"

# --- Captured from the shipped code at e731f37, BEFORE F4 was written. -------------------------
const PRE_F4_START := Vector3(18.0, 2.5, -7.0)
const PRE_F4_RESPAWN_NOTHING_CLEARED := Vector3(18.0, 2.5, -7.0)
const PRE_F4_RESPAWN_AFTER_GATE_1 := Vector3(18.0, 2.5, 1.0)
const PRE_F4_SUNK_MESSAGE := "Gate 1 reaches 0.50 m below the ground. Raise it above 1.50 m."
const PRE_F4_SUNK_VALUES := {"gate": 1, "lower_edge_m": -0.5, "radius_m": 1.5}
const PRE_F4_DEFAULT_WARNINGS := ["course_route_length/2", "course_tightest_turn/2"]
const PRE_F4_CRASH_ALTITUDE_M := 0.02
# ----------------------------------------------------------------------------------------------

## The slope fixture's numbers, worked out by hand from `_slope_height` rather than by calling it:
## height = rise_m * (along / (2 * half_span) + 0.5), so a 20 m rise across a 120 m field reads
## 0 at the low edge, 10 at the centre and 20 at the high edge.
const HILL_RISE_M := 20.0
const FIELD_M := 120.0
const HILL_CENTRE_X_M := 100.0
const GROUND_AT_CENTRE_M := 10.0
const GROUND_AT_HIGH_EDGE_M := 20.0
const GATE_RADIUS_M := 1.5

const EPS := 1.0e-6

## How close a PLACED point has to be to the clearance it was placed at. Wider than EPS because
## `GateCourse.PLACEMENT_MARGIN` deliberately overshoots — a point stored at exactly the crash
## threshold comes back below it through a 32-bit Vector3 and respawn-loops, which is what the
## first run of this section found. Ten microns at 10 m, and five orders of magnitude tighter than
## the 1.17 m the gate-versus-setback mutation moves the answer by, so it cannot hide one.
const PLACEMENT_TOL := 1.0e-4


static func run() -> Array:
	var results: Array = []
	var sections := {
		"flat is bit-identical": _flat_is_bit_identical(),
		"below ground is below terrain": _below_ground_is_below_terrain(),
		"crash is above terrain": _crash_is_above_terrain(),
		"spawn sits on the terrain": _spawn_sits_on_the_terrain(),
		"the default is flat": _the_default_is_flat(),
		"the crash test is arithmetic": _the_crash_test_is_arithmetic(),
		"a library with no sites": _a_library_with_no_sites(),
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
# Fixtures
# ---------------------------------------------------------------------------

## A slope running along +x, centred 100 m east of the world origin. Its centre reads 10.0 m, its
## west edge (world x = 40) reads 0.0 and its east edge (world x = 160) reads 20.0.
static func _hill_site() -> Site:
	var where := Site.new()
	where.terrain = Terrain.shaped(Terrain.SLOPE, FIELD_M, FIELD_M,
		{"rise_m": HILL_RISE_M, "direction_deg": 0.0}, HILL_CENTRE_X_M, 0.0)
	return where


## A slope running along +z through the world origin, for the spawn checks: the default circuit's
## gate 1 and its start line sit at different z, so the two read different ground.
static func _slope_along_z() -> Terrain:
	return Terrain.shaped(Terrain.SLOPE, FIELD_M, FIELD_M,
		{"rise_m": HILL_RISE_M, "direction_deg": 90.0}, 0.0, 0.0)


## The height `_slope_along_z()` must read at a given z, computed here from the published formula
## rather than by asking the terrain — an expectation taken from the function under observation
## would agree with it however wrong both were.
static func _expected_slope_z(z: float) -> float:
	return HILL_RISE_M * (z / FIELD_M + 0.5)


static func _bowl_site() -> Site:
	var where := Site.new()
	where.terrain = Terrain.shaped(Terrain.BOWL, FIELD_M, FIELD_M, {"depth_m": 10.0})
	return where


static func _course(gates: Array[Dictionary]) -> GateCourse:
	return GateCourse.new(gates, "under_test", "Under test")


static func _find(list: Array[BuildWarning], id: StringName) -> BuildWarning:
	for entry in list:
		if entry.id == id:
			return entry
	return null


static func _tags(list: Array[BuildWarning]) -> Array[String]:
	var out: Array[String] = []
	for entry in list:
		out.append("%s/%d" % [entry.id, entry.severity])
	return out


static func _same(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < EPS and absf(a.y - b.y) < EPS and absf(a.z - b.z) < EPS


# ---------------------------------------------------------------------------
# §1 — Check 1: flat at zero is exactly what shipped
# ---------------------------------------------------------------------------

static func _flat_is_bit_identical() -> Array:
	var results: Array = []
	var flat_site := Site.new()
	var flat := flat_site.terrain
	var build := ReferenceBuild.build()

	var course := GateCourse.new()
	results.append(TestResult.new(
		"[F4] the start line is where it was before F4, with no terrain and with a flat one",
		_same(course.start_position(), PRE_F4_START)
			and _same(course.start_position(flat), PRE_F4_START),
		"pinned %v; no arg %v; flat %v" % [
			PRE_F4_START, course.start_position(), course.start_position(flat)]
	))

	results.append(TestResult.new(
		"[F4] nothing cleared yet still respawns on the start line, unmoved",
		_same(course.respawn_position(), PRE_F4_RESPAWN_NOTHING_CLEARED)
			and _same(course.respawn_position(flat), PRE_F4_RESPAWN_NOTHING_CLEARED),
		"pinned %v; no arg %v; flat %v" % [
			PRE_F4_RESPAWN_NOTHING_CLEARED, course.respawn_position(),
			course.respawn_position(flat)]
	))

	var gate1: Dictionary = course.gates[0]
	course.advance(gate1["position"] - gate1["normal"] * 0.5,
		gate1["position"] + gate1["normal"] * 0.5)
	results.append(TestResult.new(
		"[F4] and the respawn past gate 1 is unmoved too",
		_same(course.respawn_position(), PRE_F4_RESPAWN_AFTER_GATE_1)
			and _same(course.respawn_position(flat), PRE_F4_RESPAWN_AFTER_GATE_1),
		"pinned %v; no arg %v; flat %v" % [
			PRE_F4_RESPAWN_AFTER_GATE_1, course.respawn_position(),
			course.respawn_position(flat)]
	))

	var sunk := _course([
		GateCourse.make_gate(Vector3(0.0, 1.0, 0.0), 0.0, GATE_RADIUS_M),
		GateCourse.make_gate(Vector3(0.0, 3.0, 20.0), 0.0, GATE_RADIUS_M),
	])
	var sunk_warning := _find(CourseWarnings.evaluate(sunk, build, flat_site),
		CourseWarnings.GATE_BELOW_GROUND)
	results.append(TestResult.new(
		"[F4] a gate sunk below a FLAT site reports the message and values it always did",
		sunk_warning != null and sunk_warning.message == PRE_F4_SUNK_MESSAGE
			and sunk_warning.values == PRE_F4_SUNK_VALUES,
		"pinned \"%s\" %s; got \"%s\" %s" % [
			PRE_F4_SUNK_MESSAGE, PRE_F4_SUNK_VALUES,
			"nothing" if sunk_warning == null else sunk_warning.message,
			{} if sunk_warning == null else sunk_warning.values]
	))

	results.append(TestResult.new(
		"[F4] the default circuit on a flat site says exactly what it said before F4",
		_tags(CourseWarnings.evaluate(GateCourse.new(), build, flat_site))
			== PRE_F4_DEFAULT_WARNINGS,
		"pinned %s; got %s" % [PRE_F4_DEFAULT_WARNINGS,
			_tags(CourseWarnings.evaluate(GateCourse.new(), build, flat_site))]
	))

	results.append(TestResult.new(
		"[F4] the crash altitude is the number it was, and the flat crash test brackets it",
		absf(MAIN_SCRIPT.CRASH_ALTITUDE_M - PRE_F4_CRASH_ALTITUDE_M) < 1.0e-12
			and MAIN_SCRIPT._check_crash(Vector3(0.0, 0.019, 0.0), null)
			and not MAIN_SCRIPT._check_crash(Vector3(0.0, 0.021, 0.0), null)
			and MAIN_SCRIPT._check_crash(Vector3(0.0, 0.019, 0.0), flat)
			and not MAIN_SCRIPT._check_crash(Vector3(0.0, 0.021, 0.0), flat),
		"CRASH_ALTITUDE_M %.10f (pinned %.10f); 0.019 crashed %s/%s; 0.021 crashed %s/%s" % [
			MAIN_SCRIPT.CRASH_ALTITUDE_M, PRE_F4_CRASH_ALTITUDE_M,
			MAIN_SCRIPT._check_crash(Vector3(0.0, 0.019, 0.0), null),
			MAIN_SCRIPT._check_crash(Vector3(0.0, 0.019, 0.0), flat),
			MAIN_SCRIPT._check_crash(Vector3(0.0, 0.021, 0.0), null),
			MAIN_SCRIPT._check_crash(Vector3(0.0, 0.021, 0.0), flat)]
	))

	return results


# ---------------------------------------------------------------------------
# §2 — Checks 2, 3, 4, 9: the below-ground warning asks the terrain
# ---------------------------------------------------------------------------

static func _below_ground_is_below_terrain() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var hill := _hill_site()

	# Check 2. Lower edge 3 m clear of a 10 m hill: centre = 10 + 1.5 + 3.
	var clear := _course([
		GateCourse.make_gate(
			Vector3(HILL_CENTRE_X_M, GROUND_AT_CENTRE_M + GATE_RADIUS_M + 3.0, 0.0),
			0.0, GATE_RADIUS_M),
		GateCourse.make_gate(
			Vector3(HILL_CENTRE_X_M, GROUND_AT_CENTRE_M + GATE_RADIUS_M + 3.0, 20.0),
			0.0, GATE_RADIUS_M),
	])
	results.append(TestResult.new(
		"[F4] a gate 3 m above a 10 m hill is not below the ground",
		_find(CourseWarnings.evaluate(clear, build, hill),
			CourseWarnings.GATE_BELOW_GROUND) == null,
		"gate centre %.1f m over ground %.1f m" % [
			GROUND_AT_CENTRE_M + GATE_RADIUS_M + 3.0, GROUND_AT_CENTRE_M]
	))

	# Check 3. Three metres above the DATUM, and eight and a half metres inside the hill.
	var buried := _course([
		GateCourse.make_gate(Vector3(HILL_CENTRE_X_M, 3.0, 0.0), 0.0, GATE_RADIUS_M),
		GateCourse.make_gate(Vector3(HILL_CENTRE_X_M, 3.0, 20.0), 0.0, GATE_RADIUS_M),
	])
	var buried_warning := _find(CourseWarnings.evaluate(buried, build, hill),
		CourseWarnings.GATE_BELOW_GROUND)
	var depth_m := GROUND_AT_CENTRE_M - (3.0 - GATE_RADIUS_M)
	results.append(TestResult.new(
		"[F4] a gate 3 m above the datum but inside a 10 m hill IS below the ground",
		buried_warning != null,
		"3 m up, ground %.1f m -> %s" % [GROUND_AT_CENTRE_M,
			"nothing" if buried_warning == null else buried_warning.message]
	))
	results.append(TestResult.new(
		"[F4] and it quotes the depth below the TERRAIN (%.2f m), not below zero" % depth_m,
		buried_warning != null
			and buried_warning.message.contains("%.2f m below the ground" % depth_m)
			and absf(float(buried_warning.values.get("lower_edge_m", 0.0)) + depth_m) < EPS,
		"expected %.2f m; message \"%s\"; lower_edge_m %s" % [depth_m,
			"nothing" if buried_warning == null else buried_warning.message,
			"nothing" if buried_warning == null else str(buried_warning.values.get("lower_edge_m"))]
	))

	# Check 9. The id and the severity are the ones the garage already speaks.
	results.append(TestResult.new(
		"[F4] the warning is still course_gate_below_ground, and still impossible",
		buried_warning != null and String(buried_warning.id) == "course_gate_below_ground"
			and buried_warning.severity == BuildWarning.Severity.IMPOSSIBLE,
		"id %s severity %s" % [
			"nothing" if buried_warning == null else String(buried_warning.id),
			"nothing" if buried_warning == null else str(buried_warning.severity)]
	))

	# Check 4. Two gates at the SAME authored height, at opposite ends of the slope. The site is
	# centred at x = 100, so these are world x = 40 (ground 0) and world x = 160 (ground 20) —
	# and a warning computed at the site origin, or at the world origin, cannot tell them apart.
	var low_x := HILL_CENTRE_X_M - FIELD_M * 0.5
	var high_x := HILL_CENTRE_X_M + FIELD_M * 0.5
	var ends := _course([
		GateCourse.make_gate(Vector3(low_x, 3.0, 0.0), 0.0, GATE_RADIUS_M),
		GateCourse.make_gate(Vector3(high_x, 3.0, 0.0), 0.0, GATE_RADIUS_M),
	])
	var ends_warnings := CourseWarnings.evaluate(ends, build, hill)
	var ends_below: Array[int] = []
	for entry in ends_warnings:
		if entry.id == CourseWarnings.GATE_BELOW_GROUND:
			ends_below.append(int(entry.values.get("gate", 0)))
	results.append(TestResult.new(
		"[F4] the terrain is asked at each gate's own x/z: the uphill gate is buried, the downhill one is not",
		ends_below == [2],
		"gates warned: %s (world x %.0f ground 0.0, world x %.0f ground %.0f)" % [
			ends_below, low_x, high_x, GROUND_AT_HIGH_EDGE_M]
	))

	return results


# ---------------------------------------------------------------------------
# §3 — Checks 5, 6: crashing is hitting the terrain
# ---------------------------------------------------------------------------

static func _crash_is_above_terrain() -> Array:
	var results: Array = []
	var hill := _hill_site().terrain
	var flat := Site.new().terrain

	# Check 5. Four metres up is flying over flat ground and six metres underground on the hill.
	var over_hill := Vector3(HILL_CENTRE_X_M, 4.0, 0.0)
	results.append(TestResult.new(
		"[F4] y = 4 over a 10 m hill is a crash; the same height over flat ground is flying",
		MAIN_SCRIPT._check_crash(over_hill, hill)
			and not MAIN_SCRIPT._check_crash(Vector3(0.0, 4.0, 0.0), flat),
		"hill (ground %.1f m) crashed %s; flat crashed %s" % [GROUND_AT_CENTRE_M,
			MAIN_SCRIPT._check_crash(over_hill, hill),
			MAIN_SCRIPT._check_crash(Vector3(0.0, 4.0, 0.0), flat)]
	))

	# Check 6. A bowl's floor is BELOW the datum, and negative is not the same as deep.
	var bowl := _bowl_site().terrain
	results.append(TestResult.new(
		"[F4] y = -4 inside a 10 m bowl is flying, not crashed — the floor is at -10",
		not MAIN_SCRIPT._check_crash(Vector3(0.0, -4.0, 0.0), bowl)
			and MAIN_SCRIPT._check_crash(Vector3(0.0, -10.5, 0.0), bowl),
		"bowl floor %.2f m; -4 crashed %s; -10.5 crashed %s" % [
			bowl.height_at(0.0, 0.0),
			MAIN_SCRIPT._check_crash(Vector3(0.0, -4.0, 0.0), bowl),
			MAIN_SCRIPT._check_crash(Vector3(0.0, -10.5, 0.0), bowl)]
	))

	return results


# ---------------------------------------------------------------------------
# §4 — Checks 7, 8: the start line and the respawn sit on the ground
# ---------------------------------------------------------------------------

static func _spawn_sits_on_the_terrain() -> Array:
	var results: Array = []
	var slope := _slope_along_z()
	var course := GateCourse.new()

	# Check 7. Gate 1 of the default circuit sits at z = 0 and the start line 7 m behind it at
	# z = -7, so the ground under the gate and the ground under the start line differ by 1.17 m.
	# Both are far above the gate's authored 2.5 m, so the terrain is what decides.
	var start := course.start_position(slope)
	var expected_start_y := _expected_slope_z(-GateCourse.START_SETBACK_M) \
		+ GateCourse.GROUND_CLEARANCE_M
	var at_the_gate_y := _expected_slope_z(0.0) + GateCourse.GROUND_CLEARANCE_M
	results.append(TestResult.new(
		"[F4] the start line sits the ground clearance above the terrain UNDER THE START LINE",
		start.y >= expected_start_y and start.y - expected_start_y < PLACEMENT_TOL
			and absf(start.x - PRE_F4_START.x) < EPS
			and absf(start.z - PRE_F4_START.z) < EPS,
		"start %v; expected y %.6f (at the gate it would be %.6f)" % [
			start, expected_start_y, at_the_gate_y]
	))
	results.append(TestResult.new(
		"[F4] and the fixture really distinguishes the two — the slope is not level along z",
		absf(expected_start_y - at_the_gate_y) > 1.0,
		"start ground %.4f m vs gate ground %.4f m" % [
			expected_start_y - GateCourse.GROUND_CLEARANCE_M,
			at_the_gate_y - GateCourse.GROUND_CLEARANCE_M]
	))

	# Check 8, the fallback branch: nothing cleared yet respawns on the start line, and the start
	# line is on the terrain.
	results.append(TestResult.new(
		"[F4] with nothing cleared yet, the respawn is the start line — terrain and all",
		_same(course.respawn_position(slope), start),
		"respawn %v vs start %v" % [course.respawn_position(slope), start]
	))

	# Check 8, the ordinary branch: one metre past gate 1, which sits at z = +1.
	var gate1: Dictionary = course.gates[0]
	course.advance(gate1["position"] - gate1["normal"] * 0.5,
		gate1["position"] + gate1["normal"] * 0.5)
	var respawn := course.respawn_position(slope)
	var expected_respawn_y := _expected_slope_z(1.0) + GateCourse.GROUND_CLEARANCE_M
	results.append(TestResult.new(
		"[F4] the respawn past gate 1 sits above the terrain at the respawn point",
		respawn.y >= expected_respawn_y and respawn.y - expected_respawn_y < PLACEMENT_TOL
			and absf(respawn.z - PRE_F4_RESPAWN_AFTER_GATE_1.z) < EPS,
		"respawn %v; expected y %.6f" % [respawn, expected_respawn_y]
	))

	# And the number that makes both of the above meaningful: the clearance the spawn uses is the
	# clearance the crash test rejects, and there is one of it. Two copies would let a course
	# spawn the aircraft below the altitude at which it is declared crashed.
	results.append(TestResult.new(
		"[F4] the spawn clearance IS the crash altitude, and a spawn survives being stored",

		absf(MAIN_SCRIPT.CRASH_ALTITUDE_M - GateCourse.GROUND_CLEARANCE_M) < 1.0e-12
			and not MAIN_SCRIPT._check_crash(respawn, slope),
		"CRASH_ALTITUDE_M %.10f vs GROUND_CLEARANCE_M %.10f; respawn crashed %s" % [
			MAIN_SCRIPT.CRASH_ALTITUDE_M, GateCourse.GROUND_CLEARANCE_M,
			MAIN_SCRIPT._check_crash(respawn, slope)]
	))

	return results


# ---------------------------------------------------------------------------
# §5 — Check 10: no site means flat, not "some site"
# ---------------------------------------------------------------------------

static func _the_default_is_flat() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var flat_site := Site.new()

	# A course with something to say in every severity, so the comparison is over a real list
	# rather than over two empty ones.
	var busy := _course([
		GateCourse.make_gate(Vector3(0.0, 1.0, 0.0), 0.0, GATE_RADIUS_M),
		GateCourse.make_gate(Vector3(0.0, 3.0, 1.5), 0.0, GATE_RADIUS_M),
		GateCourse.make_gate(Vector3(0.0, 3.0, 20.0), 0.0, GATE_RADIUS_M),
	])

	var without := CourseWarnings.evaluate(busy, build)
	var with_flat := CourseWarnings.evaluate(busy, build, flat_site)
	var same := without.size() == with_flat.size()
	if same:
		for i in without.size():
			if without[i].id != with_flat[i].id or without[i].message != with_flat[i].message \
					or without[i].severity != with_flat[i].severity \
					or without[i].values != with_flat[i].values:
				same = false
				break
	results.append(TestResult.new(
		"[F4] evaluate() with no site is evaluate() with a flat-at-zero site, warning for warning",
		same,
		"no site: %s; flat site: %s" % [_tags(without), _tags(with_flat)]
	))
	results.append(TestResult.new(
		"[F4] and the fixture is not two empty lists — it really has warnings to compare",
		without.size() >= 3 and _find(without, CourseWarnings.GATE_BELOW_GROUND) != null,
		"%d warnings: %s" % [without.size(), _tags(without)]
	))

	# The same promise on the other two defaults.
	var course := GateCourse.new()
	results.append(TestResult.new(
		"[F4] and start_position()/respawn_position() with no terrain are the flat answers too",
		_same(course.start_position(), course.start_position(Site.new().terrain))
			and _same(course.respawn_position(), course.respawn_position(Site.new().terrain)),
		"start %v / %v" % [course.start_position(), course.start_position(Site.new().terrain)]
	))

	return results


# ---------------------------------------------------------------------------
# §6 — Check 11: the crash test is still an altitude comparison
# ---------------------------------------------------------------------------

## The tokens a physics query would have to spell. `main.gd:52`'s recorded decision is that ground
## contact is arithmetic — `height_at` is arithmetic too, so F4 does not disturb it — and this is
## what stops a future hand reaching for the space state because the ground got a shape.
const QUERY_TOKENS := ["intersect_ray", "PhysicsRayQueryParameters", "RayCast3D",
	"direct_space_state", "intersect_shape", "PhysicsShapeQueryParameters", "cast_motion"]

static func _the_crash_test_is_arithmetic() -> Array:
	var results: Array = []
	var file := FileAccess.open(MAIN_PATH, FileAccess.READ)
	if file == null:
		results.append(TestResult.new(
			"[F4] main.gd can be read for the crash-test scan", false,
			"could not open %s" % MAIN_PATH))
		return results
	var source := file.get_as_text()
	file.close()

	var start := source.find("static func _check_crash(")
	var body := ""
	if start >= 0:
		var after := source.find("\nfunc ", start)
		var after_static := source.find("\nstatic func ", start + 1)
		if after_static >= 0 and (after < 0 or after_static < after):
			after = after_static
		body = source.substr(start, source.length() - start if after < 0 else after - start)

	results.append(TestResult.new(
		"[F4] _check_crash exists in main.gd and is the arithmetic it claims to be",
		start >= 0 and body.contains("height_at(") and body.contains("CRASH_ALTITUDE_M"),
		"found at %d, %d chars, names height_at: %s" % [
			start, body.length(), body.contains("height_at(")]
	))

	var found: Array[String] = []
	for token in QUERY_TOKENS:
		if body.contains(token):
			found.append(token)
	results.append(TestResult.new(
		"[F4] and it contains no physics query — the ground got a shape, not a collider",
		found.is_empty(),
		"scanned %d chars for %d tokens; found %s" % [
			body.length(), QUERY_TOKENS.size(), found]
	))

	# The scan is only worth anything if it can see a token. Proven here rather than asserted:
	# the same predicate over a line that DOES spell one must come back positive.
	var decoy := "\tvar hit := space.direct_space_state.intersect_ray(query)\n"
	var decoy_found := false
	for token in QUERY_TOKENS:
		if decoy.contains(token):
			decoy_found = true
	results.append(TestResult.new(
		"[F4] and the scan can actually see a query — it finds one in a decoy line",
		decoy_found,
		"decoy: %s" % decoy.strip_edges()
	))

	return results


# ---------------------------------------------------------------------------
# §7 — Review round 1: the room still draws when there is nowhere to fly
# ---------------------------------------------------------------------------

## Where the empty-library fixture is written. Its own path, so nothing here can tread on the
## builder's sites or on another suite's.
const EMPTY_SITES_PATH := "user://test_f4_empty_sites.json"
const EMPTY_COURSES_PATH := "user://test_f4_empty_courses.json"

## Where the start marker is parked before the room is asked to re-render. Nowhere a course could
## put it, so "it arrived" cannot be true by accident.
const NOWHERE := Vector3(-999.0, -999.0, -999.0)


## The Field editor's render path reads `site().terrain`, and `site()` can answer null — which is a
## runtime error inside `_render_panel()`, so the room stops drawing rather than opening somewhere
## flyable. `scenes/main.gd` guards exactly this; this is the check that makes the other caller
## agree.
##
## IT ALSO RECORDS WHICH ROUTE IS ACTUALLY OPEN, because the route named in review is not. A
## `sites.json` carrying `"sites": []` parses and then falls through to `with_default()` — the file
## path is closed, and asserting it here is what stops a later slice removing that fallback in the
## belief nothing depends on it. The open route is a library built IN CODE: `SiteLibrary.new()` has
## no ids, `selected()` reads one out of an empty dictionary, and `p_sites` takes whatever it is
## handed.
static func _a_library_with_no_sites() -> Array:
	var results: Array = []

	var file := FileAccess.open(EMPTY_SITES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "selected": "", "sites": []}))
		file.close()
	var from_file := SiteLibrary.load_from(EMPTY_SITES_PATH)
	results.append(TestResult.new(
		"[F4] a sites.json carrying an empty list still loads a field — that route is closed",
		from_file.selected() != null and from_file.ids().size() == 1,
		"loaded %d site(s); selected %s" % [from_file.ids().size(),
			"nothing" if from_file.selected() == null else from_file.selected().site_id]
	))

	var empty := SiteLibrary.new()
	results.append(TestResult.new(
		"[F4] and the route that IS open is a library built in code — selected() is null there",
		empty.selected() == null and empty.ids().is_empty(),
		"%d site(s); selected %s" % [empty.ids().size(),
			"nothing" if empty.selected() == null else empty.selected().site_id]
	))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(EMPTY_COURSES_PATH))
	# RE-POINTED IN F11 FROM `FieldEditorScreen` TO `FieldSystem`, not weakened. The old field
	# editor is retired and the authoring lives in the Field room; the dangerous state and every
	# claim about it are the same, asked of the room that now has to survive it.
	var room := FieldSystem.new(
		empty, CourseLibrary.load_from(EMPTY_COURSES_PATH), ConditionsLibrary.with_default(),
		ReferenceBuild.build(), EMPTY_COURSES_PATH)
	results.append(TestResult.new(
		"[F4] the Field room really is in the dangerous state — its site() answers null",
		room.site() == null,
		"site() -> %s" % ["null" if room.site() == null else room.site().site_id]
	))

	results.append(TestResult.new(
		"[F4] and the ground it reads there is null — flat at zero, not a dereference",
		room.site_terrain() == null,
		"site_terrain() -> %s" % [
			"null" if room.site_terrain() == null else String(room.site_terrain().shape)]
	))

	# THE RENDER PATH FOR REAL, and it has to be, for a reason that took a green mutation to find.
	# A bad dereference aborts THE FUNCTION IT IS IN and hands the caller the return type's default
	# — measured. So `site().terrain` inside a helper aborts the helper, returns null, and is
	# indistinguishable from the guard; the same dereference written INLINE in the refresh aborts
	# THE REFRESH, and every line after it silently does not happen. That is the actual defect, and
	# the only way to see it is to look at something the refresh does AFTER that line.
	#
	# THE PROBE MOVED WITH THE ROOM. The old screen's start marker is gone; what stands at
	# `start_position()` here is the aircraft's own footprint (F10, §11 Q1) — the same derived
	# fact in the same place, placed by the same refresh, after the terrain is read.
	var placed := false
	if room.silhouette() != null:
		room.silhouette().position = NOWHERE
		room.select_gate(0)
		placed = _same(room.silhouette().position, PRE_F4_START)
	results.append(TestResult.new(
		"[F4] the refresh runs to the end and the start footprint arrives, with no site at all",
		room.silhouette() != null and placed,
		"footprint %s -> %v (pinned %v)" % [
			"absent" if room.silhouette() == null else "moved to %v" % NOWHERE,
			Vector3.ZERO if room.silhouette() == null else room.silhouette().position,
			PRE_F4_START]
	))

	# The other caller on the same path, which `_terrain_of` already made safe. Asserted rather
	# than assumed, because "already safe" is a claim about a null reaching a different function.
	results.append(TestResult.new(
		"[F4] and the warnings list survives the same state — evaluate() takes a null site",
		room.warnings() != null,
		"%d warning(s) with no site to speak of" % room.warnings().size()
	))

	# RULING 19'S TWO GUARDS. Installed in F4; the F11 port into `FieldSystem` re-pointed the tests
	# and left the guards behind. They need two DIFFERENT kinds of check, and the reason is worth
	# writing down because the first attempt at this got it wrong and a mutation caught it.
	#
	# `courses_of_selected_site()` HAS NO BEHAVIOURAL SIGNATURE AT ALL, and no check can give it
	# one. A GDScript abort returns the function's return-type default to the caller — `[]` for
	# `Array[String]` — which is exactly what the guarded version returns. Caller resumes either
	# way, same value, same everything after it. A behavioural check here is guaranteed to be a
	# check that cannot fail, and the first version of this WAS one: it planted a row in
	# `course_list`, ran the fill and asserted the row was gone — which it is whether the call
	# aborted or not, because `course_list.clear()` runs before the call. Its mutation scored 0.
	#
	# So this one is a SOURCE SCAN of that function's own body, with its blind spot stated: it
	# reads text, so it cannot see whether the guard is correct — only that it is there and that
	# it comes before every dereference in that function. That is strictly more than nothing and
	# it is honestly all this defect admits of. The SCRIPT ERROR the unguarded version prints is
	# the other half of the evidence, and `tests/test_real_files.gd`'s header is where this repo
	# records which of those are expected.
	var room_source := ""
	var room_file := FileAccess.open("res://src/ui/field_system.gd", FileAccess.READ)
	if room_file != null:
		room_source = room_file.get_as_text()
		room_file.close()
	# SCANNED IN THE FUNCTION'S OWN BODY, not in the file. The first version of this matched the
	# guard text ANYWHERE in an 1800-line file that already holds a second
	# `var selected_site := sites.selected()` at `:1210`, and it was falsified: leave the guard
	# byte-for-byte intact, insert a SECOND unguarded `sites.selected().site_id` above it, and the
	# function aborts on a null site exactly as it did before the fix while the suite stays green
	# — 3186 results, 0 FAIL, with two live `site_id on Nil` errors in the log. So the slice below
	# cuts from this function's `func` line to the next one, drops its comment lines (the guard's
	# own comment says ".site_id" in prose), and asserts the guard comes BEFORE any dereference
	# in what is left.
	var guard_body := ""
	var body_start := room_source.find("func courses_of_selected_site()")
	if body_start >= 0:
		var body_end := room_source.find("\nfunc ", body_start + 1)
		if body_end < 0:
			body_end = room_source.length()
		for body_line in room_source.substr(body_start, body_end - body_start).split("\n"):
			if body_line.strip_edges().begins_with("#"):
				continue
			guard_body += body_line + "\n"
	var guard_at := guard_body.find(
		"var selected_site := sites.selected()\n\tif selected_site == null:\n\t\treturn out")
	var first_deref := guard_body.find(".site_id")
	results.append(TestResult.new(
		"[F4] courses_of_selected_site() GUARDS the null selection rather than dereferencing it " +
			"(source scan of THAT FUNCTION'S BODY — an aborted call and a guarded one return " +
			"the same [] to the same caller, so there is nothing behavioural to assert)",
		body_start >= 0 and guard_at >= 0 and first_deref >= 0 and guard_at < first_deref,
		("the function was %s, the guard text was %s, and the first .site_id in its body is at " +
			"%d against the guard at %d") % [
			"found" if body_start >= 0 else "NOT found",
			"found" if guard_at >= 0 else "NOT found", first_deref, guard_at]))
	# THE BLIND SPOT THAT IS LEFT, stated: this still reads text. It sees that the guard precedes
	# every dereference in this function, not that the guard is CORRECT — a guard testing the
	# wrong thing, or a dereference moved into a helper this function calls, both pass here. What
	# it no longer misses is an unguarded deref added to this function, or the guard drifting into
	# some other function of the same file.

	# The Site panel's own guard, which DOES have a signature: `render_rows` runs after the
	# dereference, so whether the title was rewritten says whether the function got past it.
	# `row_text` two lines below `show_site` has guarded this same null all along, so the line
	# above it was dereferencing something the very next function handles.
	var site_panel: SpecPanel = room.panel("Site")
	if site_panel == null:
		results.append(TestResult.new(
			"[F4] the Site panel exists to be asked about a null site", false, "panel(\"Site\") -> null"))
	else:
		site_panel._title.text = "STALE"
		site_panel.show_site(null)
		results.append(TestResult.new(
			"[F4] and show_site(null) GUARDS rather than aborting — render_rows ran, so the " +
				"title was rewritten instead of left stale",
			site_panel._title.text != "STALE" and site_panel._title.text.contains("SITE"),
			"the Site panel's title reads \"%s\"" % site_panel._title.text))

	# THE RAIL IS STILL ALIVE, and this is the claim the check above CANNOT make. `_fill_lists()`
	# sets `_filling` and `courses_of_selected_site()` runs between the two halves of it. When
	# that function dereferenced a null `selected()`, the abort killed the fill BEFORE the latch
	# was cleared — so `_filling` stayed `true` for the life of the room and `choose_site` /
	# `choose_course` early-returned on every click for ever. The rail stopped responding, and
	# "the refresh runs to the end" above went green anyway, because a GDScript abort is local and
	# `refresh()` resumed. The assertion was true and the property it implied was false.
	results.append(TestResult.new(
		"[F4] the fill latch is not stuck after a refresh in the dangerous state — the rail can " +
			"still be clicked",
		not room._filling,
		"_filling = %s after refresh() with no site at all" % room._filling))

	# AND IT IS NOT STUCK AFTER A FILL THAT GENUINELY ABORTS, which is the half with teeth.
	# Guarding the two null dereferences removes the aborts we know about; this asserts the
	# CONSEQUENCE is gone for the ones we do not. `_fill_lists()` sets the latch, calls
	# `_fill_lists_body()` and clears it, and the abort is local to the body — so the latch
	# clears. Move `_filling = false` back inside the body and this goes red.
	#
	# THE ABORT IS REAL AND NOT SIMULATED. `_fill_lists_body()`'s very first statement is
	# `site_list.clear()`, so taking the list away is a genuine null dereference inside the body —
	# the same kind of abort the null site used to cause, raised somewhere a guard cannot be
	# written for every case. It is driven on a throwaway room, never on one under test elsewhere.
	# `SCRIPT ERROR: ... 'clear()' ... on a base object of type 'null instance'` in a green run of
	# this suite is THIS check, and its absence means the check stopped testing anything.
	var doomed := FieldSystem.new(
		SiteLibrary.with_default(), CourseLibrary.load_from(EMPTY_COURSES_PATH),
		ConditionsLibrary.with_default(), ReferenceBuild.build(), EMPTY_COURSES_PATH)
	var had_list: bool = doomed.site_list != null
	doomed.site_list = null
	doomed._filling = false
	doomed._fill_lists()
	results.append(TestResult.new(
		"[F4] the aborting-fill fixture is a room that really did have a list to lose",
		had_list,
		"site_list before the fixture took it away: %s" % ["built" if had_list else "null"]))
	results.append(TestResult.new(
		"[F4] and the latch is clear after a fill that ABORTED: an aborted fill cannot leave " +
			"the rail dead",
		not doomed._filling,
		"_filling = %s after an aborted _fill_lists()" % doomed._filling))
	doomed.free()

	room.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EMPTY_SITES_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EMPTY_COURSES_PATH))
	return results
