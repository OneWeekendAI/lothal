class_name TestCourseWarnings
extends RefCounted
## What Lothal is entitled to say about a course you laid out.
##
## The vocabulary is build_warning.gd's, unchanged: impossible where there is a boundary in the
## geometry to point at, limiting where something binds, characteristic where the honest thing is
## to describe the course rather than judge it. The test that matters most is the last one — a
## deliberately tight course must produce NO warning above characteristic, because a tight course
## is a valid thing to build and "too tight" would be the 2.0:1 thrust-to-weight threshold's
## mistake in a new place (labs-and-sim.md §2.3).

static func run() -> Array:
	var results: Array = []
	results.append_array(_impossible())
	results.append_array(_limiting())
	results.append_array(_characteristic())
	results.append_array(_no_taste())
	return results


static func _reference() -> Build:
	return ReferenceBuild.build()


static func _long_range() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), "frame_10in_long_range",
		ReferenceBuild.MOTOR_ID, "prop_10x5x2", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID)


static func _find(list: Array[BuildWarning], id: StringName) -> BuildWarning:
	for entry in list:
		if entry.id == id:
			return entry
	return null


static func _ids(list: Array[BuildWarning]) -> Array[String]:
	var out: Array[String] = []
	for entry in list:
		out.append(String(entry.id))
	return out


static func _course(gates: Array[Dictionary]) -> GateCourse:
	return GateCourse.new(gates, "under_test", "Under test")


static func _impossible() -> Array:
	var results: Array = []
	var build := _reference()

	var default_course := GateCourse.new()
	var clean := CourseWarnings.evaluate(default_course, build)
	var worst := BuildWarning.Severity.CHARACTERISTIC
	for entry in clean:
		worst = mini(worst, entry.severity) as BuildWarning.Severity
	results.append(TestResult.new(
		"the default circuit is laid out cleanly — nothing above characteristic",
		worst == BuildWarning.Severity.CHARACTERISTIC,
		"default circuit says: %s" % ", ".join(_ids(clean))
	))

	# A ring whose bottom edge is under the ground plane. There is a boundary to point at, and
	# it is the ground.
	var sunk := _course([
		GateCourse.make_gate(Vector3(0.0, 1.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 3.0, 20.0), 0.0, 1.5),
	])
	var sunk_warning := _find(CourseWarnings.evaluate(sunk, build), CourseWarnings.GATE_BELOW_GROUND)
	results.append(TestResult.new(
		"a ring that reaches below the ground plane is impossible",
		sunk_warning != null and sunk_warning.severity == BuildWarning.Severity.IMPOSSIBLE,
		"gate 1 centre 1.0 m up through a 1.5 m ring -> %s" % [
			"nothing" if sunk_warning == null else sunk_warning.message]
	))

	# A ring smaller than the aircraft that has to fly through it. Both dimensions are known —
	# the ring's radius and the build's own span — so this needs no threshold.
	var narrow := _course([
		GateCourse.make_gate(Vector3(0.0, 4.0, 0.0), 0.0, 0.25),
		GateCourse.make_gate(Vector3(0.0, 4.0, 20.0), 0.0, 0.25),
	])
	var big := _long_range()
	var narrow_warning := _find(
		CourseWarnings.evaluate(narrow, big), CourseWarnings.RING_SMALLER_THAN_AIRCRAFT)
	results.append(TestResult.new(
		"a ring smaller than the aircraft flying through it is impossible",
		narrow_warning != null and narrow_warning.severity == BuildWarning.Severity.IMPOSSIBLE
			and absf(float(narrow_warning.values.get("span_m", 0.0)) - big.airframe_span_m()) < 1.0e-9,
		"a %.2f m aircraft through a %.2f m ring -> %s" % [
			big.airframe_span_m(), 0.5,
			"nothing" if narrow_warning == null else narrow_warning.message]
	))

	# The same ring is fine for a 65 mm whoop, which is what makes this a measurement rather
	# than a policy about small gates.
	var whoop := Build.from_ids(PartsCatalog.load_default(), "frame_65mm_whoop",
		"motor_0802_19000kv", "prop_16x12x4", "battery_1s_550", ReferenceBuild.ESC_ID)
	results.append(TestResult.new(
		"the same ring says nothing about a whoop — it is a measurement, not a policy",
		_find(CourseWarnings.evaluate(narrow, whoop), CourseWarnings.RING_SMALLER_THAN_AIRCRAFT) == null,
		"whoop spans %.3f m through the same 0.50 m ring" % whoop.airframe_span_m()
	))

	return results


static func _limiting() -> Array:
	var results: Array = []
	var build := _reference()

	# Two rings close enough that the hoops themselves intersect. It works — you can fly it —
	# but the second gate's ring is partly behind the first one's structure.
	var overlapping := _course([
		GateCourse.make_gate(Vector3(0.0, 4.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.9, 4.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 4.0, 30.0), PI, 1.5),
	])
	var intersect := _find(
		CourseWarnings.evaluate(overlapping, build), CourseWarnings.RINGS_INTERSECT)
	results.append(TestResult.new(
		"rings that intersect each other are limiting",
		intersect != null and intersect.severity == BuildWarning.Severity.LIMITING,
		"two coplanar 1.5 m rings 0.9 m apart -> %s" % [
			"nothing" if intersect == null else intersect.message]
	))

	# A route that has to pass through one gate to reach the next: gate 3 sits squarely on the
	# leg from gate 1 to gate 2, so the pilot flies through it out of order on the way.
	var blocked := _course([
		GateCourse.make_gate(Vector3(0.0, 4.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 4.0, -40.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 4.0, -20.0), 0.0, 1.5),
	])
	var through := _find(
		CourseWarnings.evaluate(blocked, build), CourseWarnings.ROUTE_THROUGH_GATE)
	results.append(TestResult.new(
		"a route that runs through a gate to reach the next one is limiting",
		through != null and through.severity == BuildWarning.Severity.LIMITING,
		"gate 3 sits on the leg from 1 to 2 -> %s" % [
			"nothing" if through == null else through.message]
	))

	results.append(TestResult.new(
		"a course whose legs pass nothing on the way says nothing about the route",
		_find(CourseWarnings.evaluate(GateCourse.new(), build), CourseWarnings.ROUTE_THROUGH_GATE) == null,
		"the default circuit's legs are clear"
	))

	return results


static func _characteristic() -> Array:
	var results: Array = []
	var build := _reference()

	var course := GateCourse.new()
	var warnings := CourseWarnings.evaluate(course, build)

	# The route the pilot actually flies: gate to gate, all the way round and back to the first.
	var expected_length := 0.0
	for i in course.gates.size():
		expected_length += float(course.gates[i]["position"].distance_to(
			course.gates[(i + 1) % course.gates.size()]["position"]))

	var length := _find(warnings, CourseWarnings.ROUTE_LENGTH)
	results.append(TestResult.new(
		"the route's length is reported, and it is the sum of the legs",
		length != null and length.severity == BuildWarning.Severity.CHARACTERISTIC
			and absf(float(length.values.get("route_length_m", 0.0)) - expected_length) < 0.001,
		"%.1f m expected, reported %s" % [expected_length,
			"nothing" if length == null else "%.1f m" % float(length.values.get("route_length_m", 0.0))]
	))

	# On an eight-gate circle every corner is the same 45 deg, which is a good oracle precisely
	# because there is nothing to pick out.
	var turn := _find(warnings, CourseWarnings.TIGHTEST_TURN)
	results.append(TestResult.new(
		"the tightest turn the course demands is reported",
		turn != null and turn.severity == BuildWarning.Severity.CHARACTERISTIC
			and absf(float(turn.values.get("turn_deg", 0.0)) - 45.0) < 0.5,
		"a regular octagon turns %s at every corner" % [
			"nothing" if turn == null else "%.1f deg" % float(turn.values.get("turn_deg", 0.0))]
	))

	# And a course with one hairpin in it reports the hairpin, not the average.
	var hairpin := GateCourse.new([
		GateCourse.make_gate(Vector3(0.0, 4.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(0.0, 4.0, 30.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(2.0, 4.0, 30.0), PI, 1.5),
	], "hairpin", "Hairpin")
	var hairpin_turn := _find(CourseWarnings.evaluate(hairpin, build), CourseWarnings.TIGHTEST_TURN)
	results.append(TestResult.new(
		"a course with one hairpin reports the hairpin rather than an average",
		hairpin_turn != null and float(hairpin_turn.values.get("turn_deg", 0.0)) > 150.0,
		"tightest turn %s" % [
			"nothing" if hairpin_turn == null else "%.0f deg" % float(hairpin_turn.values.get("turn_deg", 0.0))]
	))

	return results


static func _no_taste() -> Array:
	var results: Array = []

	# A deliberately tight little course for a 65 mm whoop: 6 m across, 0.6 m rings, sharp
	# corners. Every ring still clears the ground and still clears the aircraft, and nothing
	# intersects — so Lothal has nothing to warn about, and must not invent something.
	var whoop := Build.from_ids(PartsCatalog.load_default(), "frame_65mm_whoop",
		"motor_0802_19000kv", "prop_16x12x4", "battery_1s_550", ReferenceBuild.ESC_ID)
	var tight := GateCourse.new([
		GateCourse.make_gate(Vector3(0.0, 1.0, 0.0), 0.0, 0.6),
		GateCourse.make_gate(Vector3(0.0, 1.4, 6.0), 0.0, 0.6),
		GateCourse.make_gate(Vector3(6.0, 1.0, 6.0), PI * 0.5, 0.6),
		GateCourse.make_gate(Vector3(6.0, 1.4, 0.0), PI, 0.6),
	], "whoop_box", "Whoop box")

	var warnings := CourseWarnings.evaluate(tight, whoop)
	var judgements: Array[String] = []
	for entry in warnings:
		if entry.severity != BuildWarning.Severity.CHARACTERISTIC:
			judgements.append(String(entry.id))

	results.append(TestResult.new(
		"a tight course is a valid course — nothing above characteristic is said about it",
		judgements.is_empty(),
		"6 m box with 0.6 m rings for a %.3f m whoop -> %s" % [
			whoop.airframe_span_m(),
			"nothing said" if judgements.is_empty() else ", ".join(judgements)]
	))

	results.append(TestResult.new(
		"and it is still described rather than passed over in silence",
		_find(warnings, CourseWarnings.ROUTE_LENGTH) != null
			and _find(warnings, CourseWarnings.TIGHTEST_TURN) != null,
		"says: %s" % ", ".join(_ids(warnings))
	))

	# There is no difficulty score, and there must not be one. Asserted by id so that adding one
	# fails here rather than passing review.
	var scored := false
	for entry in warnings:
		if String(entry.id).contains("difficulty"):
			scored = true
	results.append(TestResult.new(
		"no course is given a difficulty score — that would be taste in physics clothing",
		not scored,
		"warning ids: %s" % ", ".join(_ids(warnings))
	))

	return results
