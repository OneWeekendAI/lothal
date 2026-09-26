class_name TestFieldPage
extends RefCounted
## The Field item pages (lab dock design §3, §4): Site, Course and Conditions, headless.
##
## What this suite guards: each row's line 2 names the chosen site, course or conditions and its
## line 3 is the deciding figure computed from the typed facts (elevation and the air there; gate
## count and lap; temperature and wind) — and the row, its page's two numbers and the course's own
## warnings read ONE computation (`FieldFigures`). With no object to compute from, the line is
## empty rather than a stand-in.
##
## One test per case.


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()

	# --- the shared figures
	out.append(_route_length_of_a_right_triangle())
	out.append(_tightest_turn_of_a_right_triangle())
	out.append(_no_turn_with_two_gates())
	out.append(_course_warning_states_the_figures_route_length())
	out.append(_site_text_at_920_m())
	out.append(_course_text_of_the_default_circuit())
	out.append(_course_text_with_no_gates())
	out.append(_conditions_text_calm())
	out.append(_conditions_text_steady_wind())
	out.append(_conditions_text_gusts_only())

	# --- the rows
	out.append(_site_row(build))
	out.append(_course_row(build))
	out.append(_conditions_row(build))
	out.append(_rows_without_objects_leave_line_3_empty(build))
	out.append(_course_row_owns_the_course_leaving_the_site(build))
	out.append(_course_row_goes_red_for_a_gate_below_ground(build))
	out.append(_course_row_does_not_repeat_its_page_numbers_as_warnings(build))

	# --- the page numbers
	out.append(_site_page_numbers())
	out.append(_course_page_numbers())
	out.append(_conditions_page_numbers_warm())
	out.append(_conditions_page_numbers_cold())

	# --- the pages
	out.append(_page_definitions_name_their_sheets())
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Three gates at the corners of a 30-40-50 right triangle, 2 m up: a 120 m lap whose corners are
## 90° (gate 2), ~143° (gate 3) and ~127° (gate 1).
static func _triangle() -> GateCourse:
	var gates: Array[Dictionary] = [
		GateCourse.make_gate(Vector3(0, 2, 0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(30, 2, 0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(30, 2, 40), 0.0, 1.5),
	]
	return GateCourse.new(gates, "tri", "Triangle")


static func _site(elevation_m: float) -> Site:
	var site := Site.new()
	site.site_name = "Hill"
	site.elevation_m = elevation_m
	return site


static func _conditions(temperature_c: float, wind_mps := 0.0, from_deg := 0.0,
		gusts_mps := 0.0) -> Conditions:
	var c := Conditions.new()
	c.conditions_name = "Day"
	c.temperature_c = temperature_c
	c.wind_speed_mps = wind_mps
	c.wind_from_deg = from_deg
	c.gustiness_mps = gusts_mps
	return c


static func _context(site: Site, course: GateCourse, conditions: Conditions) -> Dictionary:
	return {"site": site.site_name if site != null else "",
		"course": course.course_name if course != null else "",
		"conditions": conditions.conditions_name if conditions != null else "",
		"field_site": site, "field_course": course, "field_conditions": conditions}


static func _row(build: Build, id: StringName, context: Dictionary) -> Dictionary:
	for row in SectionRows.rows("Field", build, build.warnings(), context):
		if row["id"] == id:
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "choice '%s' · line3 '%s' · status %s · %d warning(s)" % [row.get("choice"),
		row.get("line3"), row.get("status"), (row.get("warnings", []) as Array).size()]


# ---------------------------------------------------------------------------
# The shared figures
# ---------------------------------------------------------------------------

static func _route_length_of_a_right_triangle() -> TestResult:
	var got := FieldFigures.route_length_m(_triangle())
	return TestResult.new("field figures: a 30-40-50 triangle of gates is a 120 m lap",
		is_equal_approx(got, 120.0), "%.3f m" % got)


static func _tightest_turn_of_a_right_triangle() -> TestResult:
	var turn := FieldFigures.tightest_turn(_triangle())
	# At gate 3 the route turns from +z onto the hypotenuse back to gate 1: 180° − atan(30/40).
	var want := 180.0 - rad_to_deg(atan2(30.0, 40.0))
	return TestResult.new("field figures: the triangle's tightest corner is ~143° at gate 3",
		not turn.is_empty() and absf(float(turn["deg"]) - want) < 0.01 and int(turn["gate"]) == 3,
		str(turn))


static func _no_turn_with_two_gates() -> TestResult:
	var gates: Array[Dictionary] = [GateCourse.make_gate(Vector3(0, 2, 0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(20, 2, 0), 0.0, 1.5)]
	var turn := FieldFigures.tightest_turn(GateCourse.new(gates, "two", "Two"))
	return TestResult.new("field figures: two gates have no corner to name", turn.is_empty(), str(turn))


static func _course_warning_states_the_figures_route_length() -> TestResult:
	var course := _triangle()
	var stated := -1.0
	for w in CourseWarnings.evaluate(course, null):
		if w.id == CourseWarnings.ROUTE_LENGTH:
			stated = float(w.values.get("route_length_m", -1.0))
	return TestResult.new("field figures: the course's route-length line quotes FieldFigures' lap",
		stated == FieldFigures.route_length_m(course) and stated > 0.0, "%.3f" % stated)


static func _site_text_at_920_m() -> TestResult:
	var got := FieldFigures.site_text(_site(920.0), _conditions(15.0))
	return TestResult.new("field figures: a 920 m site at 15 °C reads its elevation and ~1.10 kg/m³",
		got == "920 m · ~1.10 kg/m³", got)


static func _course_text_of_the_default_circuit() -> TestResult:
	var got := FieldFigures.course_text(GateCourse.new())
	# Eight rings on an 18 m circle, alternating 2.5 m and 4.0 m: chords of ~13.86 m.
	return TestResult.new("field figures: the default circuit reads 8 gates and its 111 m lap",
		got == "8 gates · 111 m gate to gate", got)


static func _course_text_with_no_gates() -> TestResult:
	# An empty list to the constructor means "the default circuit", so the gates are removed after.
	var course := GateCourse.new()
	course.gates.clear()
	var got := FieldFigures.course_text(course)
	return TestResult.new("field figures: a course with no gates says so", got == "no gates", got)


static func _conditions_text_calm() -> TestResult:
	var got := FieldFigures.conditions_text(_conditions(15.0))
	return TestResult.new("field figures: a still 15 °C day reads '15 °C · calm'", got == "15 °C · calm", got)


static func _conditions_text_steady_wind() -> TestResult:
	var got := FieldFigures.conditions_text(_conditions(22.0, 4.0, 270.0))
	return TestResult.new("field figures: a windy day names the speed and the bearing it comes from",
		got == "22 °C · wind 4.0 m/s from 270°", got)


static func _conditions_text_gusts_only() -> TestResult:
	var got := FieldFigures.conditions_text(_conditions(15.0, 0.0, 0.0, 2.0))
	return TestResult.new("field figures: gusts with no steady wind are not called calm",
		got == "15 °C · gusts 2.0 m/s", got)


# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

static func _site_row(build: Build) -> TestResult:
	var row := _row(build, &"site", _context(_site(920.0), _triangle(), _conditions(15.0)))
	return TestResult.new("field rows: Site names the site and reads its elevation and air",
		row.get("choice") == "Hill" and row.get("line3") == "920 m · ~1.10 kg/m³"
			and row.get("status") == SectionRows.OK, _show(row))


static func _course_row(build: Build) -> TestResult:
	var row := _row(build, &"course", _context(_site(0.0), _triangle(), _conditions(15.0)))
	return TestResult.new("field rows: Course names the course and reads its gates and lap",
		row.get("choice") == "Triangle" and row.get("line3") == "3 gates · 120 m gate to gate"
			and row.get("status") == SectionRows.OK, _show(row))


static func _conditions_row(build: Build) -> TestResult:
	var row := _row(build, &"conditions", _context(_site(0.0), _triangle(), _conditions(22.0, 4.0, 270.0)))
	return TestResult.new("field rows: Conditions names the set and reads temperature and wind",
		row.get("choice") == "Day" and row.get("line3") == "22 °C · wind 4.0 m/s from 270°", _show(row))


static func _rows_without_objects_leave_line_3_empty(build: Build) -> TestResult:
	var names_only := {"site": "Hill", "course": "Triangle", "conditions": "Day"}
	var bad: Array = []
	for id in [&"site", &"course", &"conditions"]:
		var row := _row(build, id, names_only)
		if str(row.get("line3", "?")) != "":
			bad.append("%s: '%s'" % [id, row.get("line3")])
	return TestResult.new("field rows: with only names, no line 3 is guessed", bad.is_empty(), str(bad))


## The site shrunk to 5 m square: every leg of the 50 m triangle leaves it — a limiting warning the
## Course row owns, amber, its short on line 3.
static func _course_row_owns_the_course_leaving_the_site(build: Build) -> TestResult:
	var site := _site(0.0)
	site.terrain = Site.flat_terrain(5.0, 5.0)
	var row := _row(build, &"course", _context(site, _triangle(), _conditions(15.0)))
	return TestResult.new("field rows: a course that leaves its site turns the Course row amber",
		row.get("status") == SectionRows.WARN and row.get("line3") == "⚠ course leaves the site",
		_show(row))


static func _course_row_goes_red_for_a_gate_below_ground(build: Build) -> TestResult:
	var course := _triangle()
	course.gates[1]["position"] = Vector3(30, -3, 0)
	var row := _row(build, &"course", _context(_site(0.0), course, _conditions(15.0)))
	return TestResult.new("field rows: a gate below the ground turns the Course row red",
		row.get("status") == SectionRows.BAD and str(row.get("line3")).begins_with("⚠ "), _show(row))


static func _course_row_does_not_repeat_its_page_numbers_as_warnings(build: Build) -> TestResult:
	var row := _row(build, &"course", _context(_site(0.0), _triangle(), _conditions(15.0)))
	var ids: Array = []
	for w in row.get("warnings", []):
		ids.append((w as BuildWarning).id)
	return TestResult.new("field rows: the lap and the tightest corner are page numbers, not warnings",
		not ids.has(CourseWarnings.ROUTE_LENGTH) and not ids.has(CourseWarnings.TIGHTEST_TURN)
			and row.has("warnings"), str(ids))


# ---------------------------------------------------------------------------
# The page numbers
# ---------------------------------------------------------------------------

static func _site_page_numbers() -> TestResult:
	var got := SectionRows.page_numbers(&"site", null,
		_context(_site(920.0), _triangle(), _conditions(15.0)))
	return TestResult.new("field pages: Site shows the air density and how much thinner than sea level",
		got == [["Air density", "~1.10 kg/m³"], ["Vs sea-level air", "~10% thinner"]], str(got))


static func _course_page_numbers() -> TestResult:
	var got := SectionRows.page_numbers(&"course", null,
		_context(_site(0.0), _triangle(), _conditions(15.0)))
	return TestResult.new("field pages: Course shows the lap and its tightest corner",
		got == [["Lap, gate to gate", "120 m"], ["Tightest corner", "143° at gate 3"]], str(got))


static func _conditions_page_numbers_warm() -> TestResult:
	var got := SectionRows.page_numbers(&"conditions", null,
		_context(_site(0.0), _triangle(), _conditions(30.0, 4.0, 270.0)))
	# 288.15 K / 303.15 K: the same place at 30 °C holds ~4.9% less air than at 15 °C.
	return TestResult.new("field pages: a 30 °C day is ~5% thinner than 15 °C, and its wind",
		got == [["Air vs 15 °C", "~5% thinner"], ["Wind", "4.0 m/s from 270°"]], str(got))


static func _conditions_page_numbers_cold() -> TestResult:
	var got := SectionRows.page_numbers(&"conditions", null,
		_context(_site(0.0), _triangle(), _conditions(0.0)))
	return TestResult.new("field pages: a 0 °C day is ~5% denser than 15 °C, and calm",
		got == [["Air vs 15 °C", "~5% denser"], ["Wind", "calm"]], str(got))


# ---------------------------------------------------------------------------
# The pages
# ---------------------------------------------------------------------------

static func _page_definitions_name_their_sheets() -> TestResult:
	var sheets := {}
	for definition in SectionRows.DEFINITIONS["Field"]:
		var page: Dictionary = definition["page"]
		sheets[definition["id"]] = "%s/%s" % [page.get("room"), page.get("sheet")]
	return TestResult.new("field pages: each row opens the Field room on its own sheet",
		sheets == {&"site": "field/site", &"course": "field/course", &"conditions": "field/conditions"},
		str(sheets))
