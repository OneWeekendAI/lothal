class_name FieldFigures
extends RefCounted
## The Field section's numbers, computed once (lab dock design §3, §4): the Site, Course and
## Conditions rows, their pages' two numbers and the course warnings that state the same figures
## all read these functions, so the list, the page and the warning cannot come to disagree.
##
## Every figure is arithmetic on what the builder typed or placed — the site's elevation, the
## conditions' temperature and wind, the gates' positions. Nothing here is a threshold.
##
## `~` marks the air figures: `AirDensity` is the standard-atmosphere model on two typed facts (dry
## air, the standard lapse rate), so the density is an estimate of the real air, not a reading.

## Below this many gates there is no corner: a turn needs a gate before and a gate after.
const MIN_GATES_FOR_A_TURN := 3


## The lap measured gate centre to gate centre in straight lines, back to the first gate — the
## shortest line through the rings, so a flown lap is at least this long.
static func route_length_m(course: GateCourse) -> float:
	if course == null or course.gates.is_empty():
		return 0.0
	var gates := course.gates
	var total := 0.0
	for i in gates.size():
		total += float((gates[i]["position"] as Vector3).distance_to(
			gates[(i + 1) % gates.size()]["position"]))
	return total


## The sharpest change of heading the route demands, in the horizontal plane:
## `{deg, gate}` (gate 1-based), or `{}` with fewer than three gates.
static func tightest_turn(course: GateCourse) -> Dictionary:
	if course == null or course.gates.size() < MIN_GATES_FOR_A_TURN:
		return {}
	var gates := course.gates
	var tightest_deg := 0.0
	var tightest_gate := 1
	for i in gates.size():
		var previous: Vector3 = gates[(i - 1 + gates.size()) % gates.size()]["position"]
		var here: Vector3 = gates[i]["position"]
		var next: Vector3 = gates[(i + 1) % gates.size()]["position"]
		var incoming := Vector3(here.x - previous.x, 0.0, here.z - previous.z)
		var outgoing := Vector3(next.x - here.x, 0.0, next.z - here.z)
		if incoming.length() < 0.001 or outgoing.length() < 0.001:
			continue
		var turn_deg := rad_to_deg(incoming.angle_to(outgoing))
		if turn_deg > tightest_deg:
			tightest_deg = turn_deg
			tightest_gate = i + 1
	return {"deg": tightest_deg, "gate": tightest_gate}


## The air at the site on the selected day — `AirDensity.compose`, the one function the Field room
## and `RoomHost` ask, so the row and the garage's air are the same computation.
static func air(p_site: Site, p_conditions: Conditions) -> AirDensity:
	return AirDensity.compose(p_site, p_conditions)


## "~9% thinner" / "~3% denser" / "same" for a fraction below a reference (positive = thinner).
static func thinner_text(fraction: float) -> String:
	var pct := roundi(absf(fraction) * 100.0)
	if pct == 0:
		return "same"
	return "~%d%% %s" % [pct, "thinner" if fraction > 0.0 else "denser"]


static func density_text(p_air: AirDensity) -> String:
	return "~%.2f kg/m³" % p_air.kgm3()


# ---------------------------------------------------------------------------
# Row line 3
# ---------------------------------------------------------------------------

## Site: its elevation and the air there, e.g. "920 m · ~1.12 kg/m³". Empty with no site.
static func site_text(p_site: Site, p_conditions: Conditions) -> String:
	if p_site == null:
		return ""
	return "%d m · %s" % [roundi(p_site.elevation_m), density_text(air(p_site, p_conditions))]


## Course: "8 gates · 111 m gate to gate". "no gates" for an empty course; empty with none.
static func course_text(course: GateCourse) -> String:
	if course == null:
		return ""
	var n := course.gates.size()
	if n == 0:
		return "no gates"
	return "%d %s · %d m gate to gate" % [n, "gate" if n == 1 else "gates",
		roundi(route_length_m(course))]


## Conditions: temperature and wind, e.g. "15 °C · calm", "22 °C · wind 4.0 m/s from 270°",
## "15 °C · gusts 2.0 m/s". Empty with no conditions.
static func conditions_text(p_conditions: Conditions) -> String:
	if p_conditions == null:
		return ""
	var wind := wind_text(p_conditions)
	return "%d °C · %s%s" % [roundi(p_conditions.temperature_c),
		"wind " if p_conditions.has_steady_wind() else "", wind]


## The wind in one phrase: "4.0 m/s from 270°" (the bearing it comes FROM), "gusts 2.0 m/s" with no
## steady wind, or "calm".
static func wind_text(p_conditions: Conditions) -> String:
	if p_conditions.has_steady_wind():
		return "%.1f m/s from %d°" % [p_conditions.wind_speed_mps,
			roundi(p_conditions.wind_from_deg)]
	if not p_conditions.is_calm():
		return "gusts %.1f m/s" % p_conditions.gustiness_mps
	return "calm"


# ---------------------------------------------------------------------------
# Page numbers
# ---------------------------------------------------------------------------

## How much the day's temperature alone thins the air at this site, against the same site at the
## standard 15 °C. Positive = thinner.
static func temperature_effect(p_site: Site, p_conditions: Conditions) -> float:
	var today := air(p_site, p_conditions)
	var standard_day := AirDensity.new(today.elevation_m, AirDensity.STANDARD_TEMPERATURE_C)
	return 1.0 - today.kgm3() / standard_day.kgm3()


## `[[label, value], [label, value]]` for a Field row's page, or `[]` when the object it reads is
## not there (never a stand-in).
static func page_numbers(id: StringName, p_site: Site, p_course: GateCourse,
		p_conditions: Conditions) -> Array:
	match id:
		&"site":
			if p_site == null:
				return []
			var here := air(p_site, p_conditions)
			return [["Air density", density_text(here)],
				["Vs sea-level air", thinner_text(here.fraction_below_standard())]]
		&"course":
			if p_course == null:
				return []
			var turn := tightest_turn(p_course)
			return [["Lap, gate to gate", "%d m" % roundi(route_length_m(p_course))
					if not p_course.gates.is_empty() else "no gates"],
				["Tightest corner", "%d° at gate %d" % [roundi(float(turn["deg"])), int(turn["gate"])]
					if not turn.is_empty() else "needs 3 gates"]]
		&"conditions":
			if p_conditions == null:
				return []
			return [["Air vs 15 °C", thinner_text(temperature_effect(p_site, p_conditions))],
				["Wind", wind_text(p_conditions)]]
	return []
