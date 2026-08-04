class_name TestCourseLibrary
extends RefCounted
## The field, once it stopped being constants: named courses that are authored, saved, chosen and
## flown (labs-and-sim.md §2.4).
##
## Two checks here carry the whole slice.
##
## The first is that THE DEFAULT COURSE DID NOT MOVE. Every gate position, normal and radius, and
## the start line, identical to the arithmetic that used to be the world. A fresh install has to
## fly exactly what it flew before, or this is a rewrite wearing a refactor's clothes.
##
## The second is a course that is NOT a circle and NOT eight gates, taken all the way through —
## placed, saved, loaded, flown, scored and lapped. That is the check that proves the constants
## are really gone; a circle of a different radius would pass against an implementation that had
## merely made COURSE_RADIUS_M a variable.

const LIBRARY_PATH := "user://test_courses.json"
const LAP_PATH := "user://test_course_best_laps.json"

static func run() -> Array:
	var results: Array = []
	results.append_array(_default_course_is_unchanged())
	results.append_array(_arbitrary_layouts())
	results.append_array(_persistence())
	results.append_array(_named_courses())
	results.append_array(_best_laps_are_per_course())
	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A course through a list of points, each gate facing the next one. Not a circle, and the caller
## chooses how many points there are — which is the whole point of these tests.
static func _course_through(points: Array, radii: Array, id: String, name: String) -> GateCourse:
	var gates: Array[Dictionary] = []
	for i in points.size():
		var here: Vector3 = points[i]
		var next: Vector3 = points[(i + 1) % points.size()]
		var to_next := next - here
		gates.append(GateCourse.make_gate(here, atan2(to_next.x, -to_next.z), float(radii[i])))
	return GateCourse.new(gates, id, name)


## The S-bend used throughout: five gates, none of them on a common circle, three different ring
## sizes, and nowhere near the origin.
static func _s_bend() -> GateCourse:
	return _course_through(
		[Vector3(100.0, 3.0, 0.0), Vector3(112.0, 2.2, 6.0), Vector3(120.0, 5.0, 20.0),
			Vector3(108.0, 3.4, 30.0), Vector3(96.0, 4.0, 18.0)],
		[1.5, 1.2, 2.0, 1.2, 1.5],
		"s_bend", "S-bend")


## Flies the whole course in order, straight through the middle of every ring. Returns how many
## gates scored and how many laps completed.
static func _fly_a_lap(course: GateCourse, timer: LapTimer, seconds_per_gate: float) -> Dictionary:
	var passes := 0
	var laps := 0
	for i in course.gates.size():
		var gate: Dictionary = course.gates[i]
		timer.tick(seconds_per_gate)
		if course.advance(gate["position"] - gate["normal"] * 0.5, gate["position"] + gate["normal"] * 0.5):
			passes += 1
			var completed := course.just_completed_lap()
			timer.on_gate_passed(completed)
			if completed:
				laps += 1
	return {"passes": passes, "laps": laps}


# ---------------------------------------------------------------------------
# The default course did not move
# ---------------------------------------------------------------------------

static func _default_course_is_unchanged() -> Array:
	var results: Array = []
	_forget(LIBRARY_PATH)

	var library := CourseLibrary.load_from(LIBRARY_PATH)
	var course := library.selected()

	results.append(TestResult.new(
		"a fresh install opens on the default circuit",
		course != null and course.course_id == GateCourse.DEFAULT_ID and course.gates.size() == 8,
		"selected \"%s\" with %d gates" % [
			"none" if course == null else course.course_id,
			0 if course == null else course.gates.size()]
	))
	if course == null:
		return results

	# Against the factory's own output, field by field. The arithmetic is what a fresh install
	# flies, and this is the assertion that it is untouched.
	var expected := GateCourse.build_gates()
	var worst_position := 0.0
	var worst_normal := 0.0
	var worst_radius := 0.0
	for i in mini(expected.size(), course.gates.size()):
		worst_position = maxf(worst_position,
			float(course.gates[i]["position"].distance_to(expected[i]["position"])))
		worst_normal = maxf(worst_normal,
			float(course.gates[i]["normal"].distance_to(expected[i]["normal"])))
		worst_radius = maxf(worst_radius,
			absf(float(course.gates[i]["radius"]) - float(expected[i]["radius"])))

	results.append(TestResult.new(
		"the default course's gates are exactly what build_gates() produces",
		worst_position < 1.0e-9 and worst_normal < 1.0e-9 and worst_radius < 1.0e-9,
		"worst gate differs by %.12f m, normal %.12f, radius %.12f m" % [
			worst_position, worst_normal, worst_radius]
	))

	# The start line was derived from a fixed 7 m setback and is now capped by the room behind
	# gate 1. On the default circuit the cap must not bind, or every existing lap time is on a
	# different course from the one that set it.
	var untouched := GateCourse.new()
	results.append(TestResult.new(
		"the default start line is unmoved (the setback cap does not bind on the circuit)",
		course.start_position().distance_to(untouched.gates[0]["position"]
			- untouched.gates[0]["normal"] * GateCourse.START_SETBACK_M) < 1.0e-9
			and absf(course.start_setback_m() - GateCourse.START_SETBACK_M) < 1.0e-9,
		"setback %.3f m (nominal %.1f)" % [course.start_setback_m(), GateCourse.START_SETBACK_M]
	))

	return results


# ---------------------------------------------------------------------------
# Nothing may assume eight gates in a circle
# ---------------------------------------------------------------------------

static func _arbitrary_layouts() -> Array:
	var results: Array = []

	# Gate 1 nowhere near the origin's east, and the course running the other way round.
	var course := _s_bend()

	var start := course.start_position()
	var gate1: Dictionary = course.gates[0]
	var straight_ahead := start + course.start_forward() * (course.start_setback_m() + 4.0)
	results.append(TestResult.new(
		"the start line is derived from gate 1 wherever gate 1 is",
		GateCourse.segment_passes_gate(start, straight_ahead, gate1)
			and start.distance_to(gate1["position"]) > 1.0,
		"start %v, %.1f m short of a gate at %v" % [
			start, start.distance_to(gate1["position"]), gate1["position"]]
	))

	# The cap has to bind somewhere, or it is untested scaffolding. Two gates 4 m apart cannot
	# afford a 7 m setback: it would put the start line on the far side of the gate behind.
	var tight := _course_through(
		[Vector3(0.0, 2.5, 0.0), Vector3(4.0, 2.5, 0.0)], [1.5, 1.5], "tight", "Tight")
	results.append(TestResult.new(
		"a start line cannot back up past the gate behind it",
		tight.start_setback_m() < 4.0
			and tight.start_position().distance_to(tight.gates[1]["position"]) > 0.5,
		"setback %.2f m on gates 4.0 m apart" % tight.start_setback_m()
	))

	# Respawn before any gate is cleared used to be the centre of the default circle, which is an
	# arbitrary patch of empty field for a course laid out 100 m away.
	var respawn := course.respawn_position()
	results.append(TestResult.new(
		"an un-started course respawns at its own start line, not at the world origin",
		respawn.distance_to(course.start_position()) < 1.0e-6 and respawn.distance_to(Vector3.ZERO) > 50.0,
		"respawn %v, %.0f m from the origin" % [respawn, respawn.length()]
	))

	# Five gates must wrap on five. The old modulo was GATE_COUNT, which is 8.
	var timer := LapTimer.new(course.fingerprint(), LAP_PATH)
	_forget(LAP_PATH)
	var flight := _fly_a_lap(course, timer, 1.0)
	results.append(TestResult.new(
		"a five-gate course completes a lap on the fifth gate, not the eighth",
		flight["passes"] == 5 and flight["laps"] == 1 and course.next_gate_index == 0,
		"%d gates, %d lap(s), re-armed at gate %d" % [
			flight["passes"], flight["laps"], course.next_gate_index + 1]
	))

	# Respawn after a mid-course clip, on a layout with no circular symmetry to hide behind.
	course.reset()
	var gate2: Dictionary = course.gates[1]
	course.advance(course.gates[0]["position"] - course.gates[0]["normal"] * 0.5,
		course.gates[0]["position"] + course.gates[0]["normal"] * 0.5)
	course.advance(gate2["position"] - gate2["normal"] * 0.5, gate2["position"] + gate2["normal"] * 0.5)
	var mid_respawn := course.respawn_position()
	results.append(TestResult.new(
		"a crash respawns just past the last gate cleared, on any layout",
		mid_respawn.distance_to(gate2["position"]) < 1.5
			and not GateCourse.segment_passes_gate(
				mid_respawn, mid_respawn + gate2["normal"] * 0.1, course.gates[2]),
		"respawn %.2f m from gate 2, and gate 3 is the one now due" % mid_respawn.distance_to(gate2["position"])
	))

	return results


# ---------------------------------------------------------------------------
# Persistence, under AssemblyTweaks' rules
# ---------------------------------------------------------------------------

static func _persistence() -> Array:
	var results: Array = []
	_forget(LIBRARY_PATH)

	var library := CourseLibrary.load_from(LIBRARY_PATH)
	var authored := _s_bend()
	library.put(authored)
	library.select(authored.course_id)
	library.save(LIBRARY_PATH)

	var reloaded := CourseLibrary.load_from(LIBRARY_PATH)
	var round_tripped := reloaded.course("s_bend")

	var intact := round_tripped != null and round_tripped.gates.size() == authored.gates.size()
	if intact:
		for i in authored.gates.size():
			intact = intact \
				and round_tripped.gates[i]["position"].distance_to(authored.gates[i]["position"]) < 1.0e-6 \
				and round_tripped.gates[i]["normal"].distance_to(authored.gates[i]["normal"]) < 1.0e-6 \
				and absf(float(round_tripped.gates[i]["radius"]) - float(authored.gates[i]["radius"])) < 1.0e-6
	results.append(TestResult.new(
		"an authored course round-trips through the file with its geometry intact",
		intact and round_tripped.course_name == "S-bend",
		"reloaded \"%s\" with %d gates" % [
			"none" if round_tripped == null else round_tripped.course_name,
			0 if round_tripped == null else round_tripped.gates.size()]
	))

	results.append(TestResult.new(
		"which course was chosen survives a restart",
		reloaded.selected_id == "s_bend" and reloaded.selected() != null
			and reloaded.selected().course_id == "s_bend",
		"reopened on \"%s\"" % reloaded.selected_id
	))

	# A course flown after a save/load has to score, or persistence has quietly rounded the world
	# into something unflyable.
	_forget(LAP_PATH)
	var timer := LapTimer.new(round_tripped.fingerprint(), LAP_PATH)
	var flight := _fly_a_lap(round_tripped, timer, 2.0)
	results.append(TestResult.new(
		"a course that has been through the file is still flyable, scorable and lappable",
		flight["passes"] == 5 and flight["laps"] == 1 and absf(timer.last_lap_s - 8.0) < 0.001,
		"%d gates, %d lap(s), lap = %.2f s" % [flight["passes"], flight["laps"], timer.last_lap_s]
	))

	# Unknown fields, top level and inside a course, both written by a later version of Lothal.
	_forget(LIBRARY_PATH)
	JsonStore.write_document(LIBRARY_PATH, {
		"schema": 1,
		"selected": GateCourse.DEFAULT_ID,
		"weather": {"wind_mps": 4.0},
		"courses": [{
			"id": "future", "name": "Future", "surface": "grass",
			"gates": GateCourse.gates_to_data(_s_bend().gates),
		}],
	})
	CourseLibrary.load_from(LIBRARY_PATH).save(LIBRARY_PATH)
	var raw := JsonStore.read_document(LIBRARY_PATH)
	var kept_course: Dictionary = {}
	for entry in (raw.get("courses", []) as Array):
		if (entry as Dictionary).get("id", "") == "future":
			kept_course = entry
	results.append(TestResult.new(
		"fields a later version wrote are preserved, at the top level and inside a course",
		raw.has("weather") and kept_course.get("surface", "") == "grass",
		"kept top-level %s, and the course's surface = \"%s\"" % [
			"weather" if raw.has("weather") else "nothing", kept_course.get("surface", "")]
	))

	# A corrupt file loads as defaults, exactly as a corrupt tweaks file does.
	_forget(LIBRARY_PATH)
	var handle := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	handle.store_string("{\"courses\": [ this is not json")
	handle.close()
	var recovered := CourseLibrary.load_from(LIBRARY_PATH)
	results.append(TestResult.new(
		"a corrupt file opens the default circuit instead of stopping the app",
		recovered.selected() != null and recovered.selected().course_id == GateCourse.DEFAULT_ID
			and recovered.selected().gates.size() == 8,
		"recovered \"%s\"" % (
			"nothing" if recovered.selected() == null else recovered.selected().course_id)
	))

	return results


# ---------------------------------------------------------------------------
# More than one course, or this is a level editor with one level
# ---------------------------------------------------------------------------

static func _named_courses() -> Array:
	var results: Array = []
	_forget(LIBRARY_PATH)

	var library := CourseLibrary.load_from(LIBRARY_PATH)
	var first := library.create("Whoop box")
	var second := library.create("Long haul")
	library.put(_s_bend())
	library.save(LIBRARY_PATH)

	var reloaded := CourseLibrary.load_from(LIBRARY_PATH)
	results.append(TestResult.new(
		"several named courses live side by side",
		reloaded.ids().size() == 4 and reloaded.names().has("Whoop box")
			and reloaded.names().has("Long haul") and reloaded.names().has("S-bend"),
		"library holds %s" % ", ".join(reloaded.names())
	))

	results.append(TestResult.new(
		"a new course gets an id of its own rather than colliding with the last one",
		first != null and second != null and first.course_id != second.course_id,
		"\"%s\" and \"%s\"" % [
			"" if first == null else first.course_id, "" if second == null else second.course_id]
	))

	results.append(TestResult.new(
		"a new course starts as the default circuit, ready to be edited",
		first != null and first.gates.size() == 8,
		"%d gates on a new course" % (0 if first == null else first.gates.size())
	))

	results.append(TestResult.new(
		"choosing a course that is not there changes nothing",
		not reloaded.select("no_such_course") and reloaded.selected() != null,
		"still on \"%s\"" % reloaded.selected_id
	))

	reloaded.remove("s_bend")
	results.append(TestResult.new(
		"a course can be deleted",
		not reloaded.has("s_bend") and reloaded.ids().size() == 3,
		"%d courses left" % reloaded.ids().size()
	))

	# Deleting the course you are standing on must leave you somewhere, not on nothing.
	reloaded.select(GateCourse.DEFAULT_ID)
	reloaded.remove(GateCourse.DEFAULT_ID)
	results.append(TestResult.new(
		"deleting the selected course selects another rather than leaving none",
		reloaded.selected() != null and reloaded.selected_id != GateCourse.DEFAULT_ID,
		"now on \"%s\"" % reloaded.selected_id
	))

	# And the last one cannot be deleted into an empty field.
	for id in reloaded.ids():
		reloaded.remove(id)
	results.append(TestResult.new(
		"the last course cannot be deleted — there is always somewhere to fly",
		reloaded.ids().size() == 1 and reloaded.selected() != null,
		"%d course(s) left" % reloaded.ids().size()
	))

	return results


# ---------------------------------------------------------------------------
# The hazard: a best lap belongs to the course it was set on
# ---------------------------------------------------------------------------

static func _best_laps_are_per_course() -> Array:
	var results: Array = []
	_forget(LAP_PATH)

	var course_a := _s_bend()
	var course_b := _course_through(
		[Vector3(0.0, 3.0, 0.0), Vector3(30.0, 3.0, 0.0), Vector3(30.0, 3.0, 30.0)],
		[1.5, 1.5, 1.5], "sprint", "Sprint")

	results.append(TestResult.new(
		"two different layouts do not share a fingerprint",
		course_a.fingerprint() != course_b.fingerprint(),
		"A = %s, B = %s" % [course_a.fingerprint(), course_b.fingerprint()]
	))

	# Set a 5 s lap on A.
	var timer_a := LapTimer.new(course_a.fingerprint(), LAP_PATH)
	_fly_a_lap(course_a, timer_a, 1.0)
	results.append(TestResult.new(
		"a lap flown on course A is recorded as A's best",
		absf(timer_a.best_lap_s - 4.0) < 0.001,
		"best on A = %.2f s" % timer_a.best_lap_s
	))

	# THE FAILURE MODE, ASSERTED DIRECTLY: walk to a different course and A's record must not be
	# sitting there as the time to beat.
	var timer_b := LapTimer.new(course_b.fingerprint(), LAP_PATH)
	results.append(TestResult.new(
		"a best lap set on course A is NOT reported as a record on course B",
		timer_b.best_lap_s == 0.0,
		"B opened showing %s" % LapTimer.format(timer_b.best_lap_s)
	))

	# A slower lap on B is still B's record, because B has none — and it must not overwrite A's.
	_fly_a_lap(course_b, timer_b, 4.0)
	var timer_a_again := LapTimer.new(course_a.fingerprint(), LAP_PATH)
	results.append(TestResult.new(
		"recording a slower lap on B leaves A's faster record alone",
		absf(timer_b.best_lap_s - 8.0) < 0.001 and absf(timer_a_again.best_lap_s - 4.0) < 0.001,
		"B = %.2f s, A still %.2f s" % [timer_b.best_lap_s, timer_a_again.best_lap_s]
	))

	# Editing a course is the same problem in miniature: move one gate 2 m and the record does
	# not follow, because the fingerprint is the geometry.
	var edited := _s_bend()
	edited.gates[2]["position"] += Vector3(2.0, 0.0, 0.0)
	var timer_edited := LapTimer.new(edited.fingerprint(), LAP_PATH)
	results.append(TestResult.new(
		"moving a gate retires the record set before it moved",
		timer_edited.best_lap_s == 0.0,
		"the edited course opened showing %s" % LapTimer.format(timer_edited.best_lap_s)
	))

	# ...and putting it back brings the record back, because it is the same track again.
	var restored := _s_bend()
	results.append(TestResult.new(
		"putting the gate back restores the record — it is the same track again",
		absf(LapTimer.new(restored.fingerprint(), LAP_PATH).best_lap_s - 4.0) < 0.001,
		"restored course shows %s" % LapTimer.format(
			LapTimer.new(restored.fingerprint(), LAP_PATH).best_lap_s)
	))

	# A save/load round trip must NOT retire a record. Float coordinates through JSON is exactly
	# the accidental edit this rounding exists to tolerate.
	_forget(LIBRARY_PATH)
	var library := CourseLibrary.load_from(LIBRARY_PATH)
	library.put(_s_bend())
	library.save(LIBRARY_PATH)
	var after_disk := CourseLibrary.load_from(LIBRARY_PATH).course("s_bend")
	results.append(TestResult.new(
		"a course that has been written and read back keeps its record",
		after_disk != null and after_disk.fingerprint() == course_a.fingerprint(),
		"fingerprint %s before disk, %s after" % [
			course_a.fingerprint(), "none" if after_disk == null else after_disk.fingerprint()]
	))

	return results
