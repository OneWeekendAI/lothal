class_name TestSr8Range
extends RefCounted
## SR8 uncertainty. SR8.1 tolerance fields (src/autopilot/tolerances.gd) and the runner hooks they drive (mass_scale, drag_scale,
## esc_loss_scale, pack_temp_c in MissionRunner). SR8.2 / SR8.3 (Monte Carlo, dominant input) follow in this file. One TestResult per case.
## Flights: five_inch, capacity_scale 0.15, seed 11, 3 m/s wind with 1.5 m/s gusts; hover_endurance (and a 1-lap cruise_loop for drag).
## Hand figures: hover power goes as mass^1.5, so +10 percent mass shortens a hover by 1 - 1.1^-1.5 = 13.3 percent (band 9-16 percent: the pack
## sags and the motors leave the ideal line). Direction-and-order checks for temperature (cold pack: -20 C), ESC loss (x2) and drag (x2, cruise).
## FAIL-PROOFS (observed 2026-11-10): TL1 a default tag blanked: the tag and defaults cases FAIL. TL2 edit leaves the default tag: the edit case FAILS.
## TL3 mass hook removed: the mass case FAILS (126.3 s -> 126.3 s). TL4 pack temperature hook removed: the temperature case FAILS. TL5 ESC hook removed: the ESC case FAILS.
## TL6 drag hook removed: the drag case FAILS.

static var _cache: Dictionary = {}


static func _fly(extra: Dictionary = {}, mission: String = Mission.HOVER_ENDURANCE) -> Dictionary:
	var key := var_to_str([extra, mission])
	if not _cache.has(key):
		var p := {"class_id": "five_inch", "mission": mission, "seed": 11, "capacity_scale": 0.15, "wind_speed_mps": 3.0, "wind_from_deg": 60.0, "gust_mps": 1.5}
		if mission == Mission.CRUISE_LOOP:
			p["laps"] = 1
		for k in extra:
			p[k] = extra[k]
		_cache[key] = MissionRunner.run(p)
	return _cache[key]


static func run() -> Array:
	return [
		_every_tolerance_tagged(),
		_defaults_load(),
		_edit_marks_user(),
		_edit_back_to_default(),
		_edit_does_not_mutate(),
		_problem_detector_can_fail(),
		_hook_defaults_identical(),
		_hook_mass(),
		_hook_temperature(),
		_hook_esc(),
		_hook_drag(),
	]


static func _every_tolerance_tagged() -> TestResult:
	var t := Tolerances.defaults()
	var bad: Array[String] = []
	for n in Tolerances.NAMES:
		if String(t.fields[n]["tag"]) not in Tolerances.TAGS or String(t.fields[n]["source"]) == "":
			bad.append(n)
	return TestResult.new("sr8 tolerances: every default has a tag in {measured, published, estimated} and a source line", bad.is_empty() and t.problems().is_empty(), str(bad) + str(t.problems()))


static func _defaults_load() -> TestResult:
	var t := Tolerances.defaults()
	var ok: bool = t.fields.size() == Tolerances.NAMES.size() and t.half_width("capacity_pct") == 5.0 and t.half_width("wind_seeds") == 5.0 and t.half_width("wind_speed_mps") == 0.0
	for n in Tolerances.NAMES:
		ok = ok and not bool(t.fields[n]["edited"]) and String(t.fields[n]["tag"]) == "estimated"
	return TestResult.new("sr8 tolerances: the seven defaults load (capacity +-5, 5 wind seeds, wind speed off), all estimated and unedited", ok, str(t.fields.keys()))


static func _edit_marks_user() -> TestResult:
	var t := Tolerances.defaults().with_half("mass_pct", 10.0)
	var f: Dictionary = t.fields["mass_pct"]
	return TestResult.new("sr8 tolerances: editing mass to +-10 percent marks it edited, tag user, default tag kept", bool(f["edited"]) and f["tag"] == "user" and f["default_tag"] == "estimated" and f["half"] == 10.0, str(f))


static func _edit_back_to_default() -> TestResult:
	var t := Tolerances.defaults().with_half("mass_pct", 10.0).with_half("mass_pct", 3.0)
	var f: Dictionary = t.fields["mass_pct"]
	return TestResult.new("sr8 tolerances: setting a field back to its default clears 'edited' and restores its tag", not bool(f["edited"]) and f["tag"] == "estimated", str(f))


static func _edit_does_not_mutate() -> TestResult:
	var a := Tolerances.defaults()
	var b := a.with_half("drag_pct", 50.0)
	return TestResult.new("sr8 tolerances: with_half returns a copy, the original keeps 20 percent drag", a.half_width("drag_pct") == 20.0 and b.half_width("drag_pct") == 50.0, "%s / %s" % [a.half_width("drag_pct"), b.half_width("drag_pct")])


static func _problem_detector_can_fail() -> TestResult:
	var t := Tolerances.defaults()
	t.fields["drag_pct"]["default_tag"] = "guess"
	t.fields["mass_pct"]["source"] = ""
	return TestResult.new("sr8 tolerances: the checker reports a bad tag and a missing source (it can fail)", t.problems().size() == 2, str(t.problems()))


static func _hook_defaults_identical() -> TestResult:
	var a := _fly()
	var b := _fly({"mass_scale": 1.0, "drag_scale": 1.0, "esc_loss_scale": 1.0, "pack_temp_c": 25.0})
	return TestResult.new("sr8 hooks: mass / drag / ESC scales of 1 and 25 C give the same flight as leaving them out (bit for bit in the figures)",
		float(a["flight_time_s"]) == float(b["flight_time_s"]) and float(a["energy_wh"]) == float(b["energy_wh"]), "%s vs %s s" % [a["flight_time_s"], b["flight_time_s"]])


static func _hook_mass() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"mass_scale": 1.1})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: +10 percent mass shortens the hover by 9-16 percent (hand 13.3 percent from mass^1.5)", change < -0.09 and change > -0.16, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_temperature() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"pack_temp_c": 5.0})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: a 5 C pack (20 C colder) shortens the hover by 5-20 percent", change < -0.05 and change > -0.20, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_esc() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"esc_loss_scale": 2.0})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: doubling the ESC loss shortens the hover by 0.5-5 percent", change < -0.005 and change > -0.05, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_drag() -> TestResult:
	var a := _fly({}, Mission.CRUISE_LOOP)
	var b := _fly({"drag_scale": 2.0}, Mission.CRUISE_LOOP)
	var wa := float(a["wh_per_min"])
	var wb := float(b["wh_per_min"])
	return TestResult.new("sr8 hooks: doubling body drag raises a cruise's Wh per minute by 5-25 percent", wb / wa - 1.0 > 0.05 and wb / wa - 1.0 < 0.25, "%.4f -> %.4f Wh/min (%.1f percent)" % [wa, wb, (wb / wa - 1.0) * 100.0])
