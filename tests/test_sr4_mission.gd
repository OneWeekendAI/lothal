class_name TestSr4Mission
extends RefCounted
## SR4 mission runner (src/autopilot/mission.gd, mission_runner.gd, mission_result.gd). ONE TestResult per case,
## written out, never looped. Every flight is headless, seeded, dt = 1/500 s, and uses capacity_scale 0.3 (a pack
## rating cut to 30 %, the same aircraft): 0.1-0.2 leaves almost nothing after the 25 % reserve, climb and landing,
## and 0.3 still keeps a whole run to a few seconds of wall time. Survey tests use a 70 x 50 m field (default
## polygon is per class and big; the swap case uses 100 x 60 m). Flights are cached by params inside one run.
## Set the environment variable SR4_ONLY=key1,key2 to run only the cases whose key is listed (used for fail-proofs).
##
## WHICH CLASS RUNS WHICH CASE
##   all three of five_inch, seven_lr, cinelifter: the 18 completion cases (6 missions x 3), RTH at reserve (3),
##     reserve 95 percent (3), survey coverage within 2 percent (3).
##   five_inch only: seed difference, skip-line miss + hole warning, forward-overlap hole, battery swap, JSON round trip.
##   five_inch + cinelifter: determinism (cruise loop / follow path, both with gusts).
##   mavic_3m (plan only, not flown): the 400 x 300 m worked example.
##
## 2 PERCENT AREA TOLERANCE: the 0.5 m raster quantises the area by about 0.3 percent, plus the edge/overrun margin
## (the planner flies half a footprint past each end so the ends are covered; the 0.5 m cell centres at the border
## add under 0.5 percent), plus cross-track error under 1 m on 13-30 m line spacing (no effect on coverage while the
## footprint overlaps its neighbour). Measured here: area flown = polygon area to the cell on all three classes
## (swath exceeds the field edge), so 2 percent is generous; it stays at the plan's number.
## RTH BAND: reserve 25 percent -> the pack left at touchdown must be AT OR ABOVE 25 and under 30 (2026-11-09: measured 26.8 / 26.1 / 26.4
## on five_inch / seven_lr / cinelifter; the estimate before the fix landed at 24.0 / 23.0 / 22.6 and this check failed on all three);
## home error <= 2 m
## (measured about 0.01 m: the landing is a position hold at home).
##
## FAIL-PROOFS (each case was run with its fix removed by a temporary edit of the runner / Mission / MissionResult, then
## restored; observed values). SR4_ONLY selects the cases. A hang at 0 % CPU is a GDScript compile error (warnings are
## errors): such edits were redone in another form and are not listed.
##   P1 Wind/Gyro seeded from randi() instead of the seed: determinism five_inch and cinelifter both FAIL (equal=false).
##   P2 seed ignored (rig seed always 1): seed case FAILS (energy 2.16975 Wh both, distance 625.54 m both).
##   P3 RTH check disabled (reserve rule never trips): RTH five_inch / seven_lr / cinelifter all FAIL (ended_by
##        battery_empty_in_flight, pack left 0.0 %) and the five_inch cruise completion FAILS (cutoff in flight).
##   P4 preflight 'not flown' check removed: reserve 95 % x3 FAIL (flies 16 s, ends landed_at_reserve, sorties 1).
##   P5 survey forced to skip line 1 (every survey): skip case FAILS (intact miss 46 %, both equal), but the three 65 %-overlap
##        coverage cases still PASS (a neighbour line covers the skipped one) - which is why the skip proof uses 10 % overlap.
##   P5b skip option ignored: skip case FAILS (miss 0.00 % both) and hole case FAILS (no hole warning).
##   P12 hole threshold 1e9 m2: hole case FAILS (only the DEBUG warning, no 'coverage hole').
##   P13 polygon scan intervals shortened by 3 cells: coverage five_inch and seven_lr FAIL (miss 2.14 %; coverage_fraction
##        stays 1.000, which is why the check is on area flown / polygon area and not on the fraction alone).
##   P6 planner warnings not copied into the result: forward case FAILS (warnings 0). P6b planner holes not copied: FAILS (holes []).
##   P7 max_sorties forced to 1: swap case FAILS (sorties 1, ended landed_at_reserve, miss 18.4 %).
##   P8 pack runs the cruise mission three times: pack case FAILS (parts cruise, cruise, cruise).
##   P9 mavic_3m side overlap default 0.60: worked example FAILS (9 lines, spacing 36.0, path 4592.39, time 611.75).
##   P10 param tag blanked: JSON round trip FAILS.
##   P11a survey path never issued: five_inch survey completion FAILS (ended no_progress, area 0).
##   P11b cruise loop speed 0 (never leaves home): five_inch cruise completion FAILS (out 0 m, distance 40 m).
##   Not individually proven: unknown-class case, the hover completion case (hold within 2 m), range test, follow path
##   and the survey-suite wrapper; the nav suite is not wrapped (run it with run_suites only="sr4 nav").

const SCALE := 0.3
const SEED := 11
const TOL_AREA := 0.02
const NORMAL: Array[String] = ["completed", "landed_at_reserve", "battery_cutoff"]
const CLASSES: Array[String] = ["five_inch", "seven_lr", "cinelifter"]

static var _cache: Dictionary = {}


static func run() -> Array:
	var out: Array = []
	var only := OS.get_environment("SR4_ONLY")
	var cases := {
		"det_five": func() -> TestResult: return _determinism("five_inch", Mission.CRUISE_LOOP),
		"det_cine": func() -> TestResult: return _determinism("cinelifter", Mission.FOLLOW_PATH),
		"seed": func() -> TestResult: return _seed_differs(),
		"done_five_hover": func() -> TestResult: return _completes("five_inch", Mission.HOVER_ENDURANCE),
		"done_five_cruise": func() -> TestResult: return _completes("five_inch", Mission.CRUISE_LOOP),
		"done_five_range": func() -> TestResult: return _completes("five_inch", Mission.RANGE_TEST),
		"done_five_survey": func() -> TestResult: return _completes("five_inch", Mission.SURVEY),
		"done_five_follow": func() -> TestResult: return _completes("five_inch", Mission.FOLLOW_PATH),
		"done_five_pack": func() -> TestResult: return _completes("five_inch", Mission.TEST_PACK),
		"done_seven_hover": func() -> TestResult: return _completes("seven_lr", Mission.HOVER_ENDURANCE),
		"done_seven_cruise": func() -> TestResult: return _completes("seven_lr", Mission.CRUISE_LOOP),
		"done_seven_range": func() -> TestResult: return _completes("seven_lr", Mission.RANGE_TEST),
		"done_seven_survey": func() -> TestResult: return _completes("seven_lr", Mission.SURVEY),
		"done_seven_follow": func() -> TestResult: return _completes("seven_lr", Mission.FOLLOW_PATH),
		"done_seven_pack": func() -> TestResult: return _completes("seven_lr", Mission.TEST_PACK),
		"done_cine_hover": func() -> TestResult: return _completes("cinelifter", Mission.HOVER_ENDURANCE),
		"done_cine_cruise": func() -> TestResult: return _completes("cinelifter", Mission.CRUISE_LOOP),
		"done_cine_range": func() -> TestResult: return _completes("cinelifter", Mission.RANGE_TEST),
		"done_cine_survey": func() -> TestResult: return _completes("cinelifter", Mission.SURVEY),
		"done_cine_follow": func() -> TestResult: return _completes("cinelifter", Mission.FOLLOW_PATH),
		"done_cine_pack": func() -> TestResult: return _completes("cinelifter", Mission.TEST_PACK),
		"rth_five": func() -> TestResult: return _rth_at_reserve("five_inch"),
		"rth_seven": func() -> TestResult: return _rth_at_reserve("seven_lr"),
		"rth_cine": func() -> TestResult: return _rth_at_reserve("cinelifter"),
		"rthw_seven_225": func() -> TestResult: return _rth_in_wind("seven_lr", 225.0, 45.0),
		"rthw_seven_90": func() -> TestResult: return _rth_in_wind("seven_lr", 90.0, 33.0),
		"res95_five": func() -> TestResult: return _reserve_too_high("five_inch"),
		"res95_seven": func() -> TestResult: return _reserve_too_high("seven_lr"),
		"res95_cine": func() -> TestResult: return _reserve_too_high("cinelifter"),
		"cov_five": func() -> TestResult: return _coverage("five_inch"),
		"cov_seven": func() -> TestResult: return _coverage("seven_lr"),
		"cov_cine": func() -> TestResult: return _coverage("cinelifter"),
		"cov_skip": func() -> TestResult: return _coverage_skip(),
		"cov_hole": func() -> TestResult: return _hole_warning(),
		"forward": func() -> TestResult: return _forward_hole(),
		"swap": func() -> TestResult: return _battery_swap(),
		"swap_full": func() -> TestResult: return _battery_swap_full_pack(),
		"pack": func() -> TestResult: return _pack_parts(),
		"worked": func() -> TestResult: return _worked_example(),
		"json": func() -> TestResult: return _json_round_trip(),
		"survey_suite": func() -> TestResult: return _survey_suite_still_passes(),
		"unknown": func() -> TestResult: return _unknown_class(),
	}
	var keys: PackedStringArray = only.split(",") if only != "" else PackedStringArray()
	for k in cases:
		if only == "" or k in keys:
			out.append(cases[k].call())
	return out


# ---------------------------------------------------------------- helpers
static func _field(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(30, 0), Vector2(30 + w, 0), Vector2(30 + w, h), Vector2(30, h)])


static func _params(cls: String, mission: String) -> Dictionary:
	var d := {"class_id": cls, "mission": mission, "seed": SEED, "capacity_scale": SCALE}
	if mission == Mission.SURVEY or mission == Mission.TEST_PACK:
		d["polygon"] = _field(70, 50)
	if mission == Mission.TEST_PACK:
		d["hover_s"] = 20.0
		d["laps"] = 1
	return d


static func _fly(params: Dictionary) -> Dictionary:
	var key := var_to_str(params)
	if not _cache.has(key):
		_cache[key] = MissionRunner.run(params)
	return _cache[key]


static func _has(r: Dictionary, text: String) -> bool:
	for w in r["warnings"]:
		if String(w).contains(text):
			return true
	return false


# ---------------------------------------------------------------- (1)(2) determinism and seeds
static func _determinism(cls: String, mission: String) -> TestResult:
	var p := _params(cls, mission)
	p["capacity_scale"] = 0.15
	p["gust_mps"] = 1.5
	p["wind_speed_mps"] = 3.0
	p["wind_from_deg"] = 60.0
	var a := MissionResult.to_json(MissionRunner.run(p))
	var b := MissionResult.to_json(MissionRunner.run(p))
	return TestResult.new("sr4 mission determinism %s %s: same params twice (3 m/s wind, 1.5 m/s gusts) give byte-identical JSON" % [cls, mission],
		a == b and a.length() > 500, "%d bytes, equal=%s" % [a.length(), str(a == b)])


static func _seed_differs() -> TestResult:
	var p := _params("five_inch", Mission.CRUISE_LOOP)
	p["capacity_scale"] = 0.15
	p["gust_mps"] = 1.5
	p["wind_speed_mps"] = 3.0
	var a := MissionRunner.run(p)
	p["seed"] = SEED + 1
	var b := MissionRunner.run(p)
	var ja := MissionResult.to_json(a)
	var jb := MissionResult.to_json(b)
	return TestResult.new("sr4 mission seed: another seed with 1.5 m/s gusts gives a different result (five_inch cruise loop)",
		ja != jb and absf(float(a["energy_wh"]) - float(b["energy_wh"])) > 1e-6,
		"energy %.5f vs %.5f Wh, distance %.2f vs %.2f m" % [a["energy_wh"], b["energy_wh"], a["distance_m"], b["distance_m"]])


# ---------------------------------------------------------------- (3) each mission completes
static func _completes(cls: String, mission: String) -> TestResult:
	var r := _fly(_params(cls, mission))
	var ended := String(r["ended_by"])
	var ok: bool = bool(r["completed"]) and ended in NORMAL and not ended.contains("wait") and float(r["flight_time_s"]) > 15.0
	var why := ""
	match mission:
		Mission.HOVER_ENDURANCE:
			ok = ok and ended == "battery_cutoff" and float(r["max_distance_from_home_m"]) < 2.0
			why = "hover holds within 2 m of home to cutoff"
		Mission.CRUISE_LOOP:
			ok = ok and float(r["max_distance_from_home_m"]) > 60.0 and float(r["distance_m"]) > 200.0 and float(r["home_error_m"]) < 3.0
			why = "flew a loop (>60 m out, >200 m), landed within 3 m of home"
		Mission.RANGE_TEST:
			ok = ok and float(r["distance_out_m"]) > 150.0 and float(r["home_error_m"]) < 3.0
			why = "went >150 m out and came home"
		Mission.FOLLOW_PATH:
			ok = ok and ended == "completed" and float(r["max_distance_from_home_m"]) > 20.0
			why = "path finished (ended completed)"
		Mission.SURVEY:
			ok = ok and ended == "completed" and float(r["area_flown_m2"]) > 1000.0 and int(r["sorties"]) >= 1
			why = "all lines flown (ended completed)"
		Mission.TEST_PACK:
			ok = ok and ended == "completed" and (r["parts"] as Array).size() == 3
			why = "three parts completed"
	return TestResult.new("sr4 mission completes %s %s with no input (%s)" % [cls, mission, why], ok,
		"ended_by %s, %.0f s, %.0f m, out %.0f m, area %.0f m2, sorties %d, warnings %d" % [ended, r["flight_time_s"], r["distance_m"], r["max_distance_from_home_m"], r["area_flown_m2"], r["sorties"], (r["warnings"] as Array).size()])


# ---------------------------------------------------------------- (4)(5) reserve
static func _rth_at_reserve(cls: String) -> TestResult:
	var p := _params(cls, Mission.CRUISE_LOOP)
	p["fields"] = {"reserve_pct": 25.0}       # seven_lr defaults to 20, so the 25 is set explicitly for all three
	var r := _fly(p)
	var left := float(r["reserve_left_pct"])
	var ok: bool = _has(r, "RTH at reserve") and left >= 25.0 and left <= 30.0 and float(r["home_error_m"]) <= 2.0 \
		and String(r["ended_by"]) == "landed_at_reserve"
	return TestResult.new("sr4 mission RTH at reserve %s: reserve 25 %% -> warning, pack left AT OR ABOVE the 25 %% reserve (and under 30), touchdown within 2 m of home" % cls, ok,
		"ended_by %s, left %.1f %%, home error %.2f m, warnings %s" % [r["ended_by"], left, r["home_error_m"], str(r["warnings"])])


## SR3 pre-task (RTH reserve in wind). 20 mph (8.94 m/s at the 10 m reference) plus 0.5 m/s gusts from `from_deg`: the cruise loop with a 25 %
## reserve must land AT OR ABOVE the reserve, and not absurdly early (`max_left`). The return energy is priced at the airspeed on the way home
## (headwind component), not at the average of the last 20 s of loop.
## FAIL-PROOF (params rth_wind_correction=false, i.e. the estimate before the fix; env SR4_OLD=1 sets it here): seven_lr from 225 deg left 24.3 %
## (BELOW the reserve, FAIL), seven_lr from 90 deg ended with 52.3 % left (way above 33, FAIL). Fixed: 39.7 and 28.0. Also measured, 8 directions
## x 3 classes: no class lands under 25 % after the fix; five_inch/seven_lr/cinelifter lowest 27.7 / 27.1 / 27.4.
static func _rth_in_wind(cls: String, from_deg: float, max_left: float) -> TestResult:
	var p := _params(cls, Mission.CRUISE_LOOP)
	p["fields"] = {"reserve_pct": 25.0}
	p["wind_speed_mps"] = 20.0 * 0.44704
	p["wind_from_deg"] = from_deg
	p["gust_mps"] = 0.5
	if OS.get_environment("SR4_OLD") != "":
		p["rth_wind_correction"] = false
	var r := _fly(p)
	var left := float(r["reserve_left_pct"])
	var ok: bool = _has(r, "RTH at reserve") and left >= 25.0 and left <= max_left and float(r["home_error_m"]) <= 2.0 \
		and String(r["ended_by"]) == "landed_at_reserve"
	return TestResult.new("sr4 mission RTH in 20 mph wind %s from %d deg: reserve 25 %% -> lands at or above the reserve (and under %.0f)" % [cls, int(from_deg), max_left], ok,
		"ended_by %s, left %.1f %%, home error %.2f m" % [r["ended_by"], left, r["home_error_m"]])


static func _reserve_too_high(cls: String) -> TestResult:
	var p := _params(cls, Mission.CRUISE_LOOP)
	p["fields"] = {"reserve_pct": 95.0}
	var r := _fly(p)
	var ok: bool = String(r["ended_by"]) == "not_flown" and _has(r, "reserve exceeds usable energy; mission not flown") \
		and float(r["flight_time_s"]) < 1.0 and int(r["sorties"]) == 0 and not bool(r["completed"])
	return TestResult.new("sr4 mission reserve 95 %% %s: ends at once, no take-off, warning 'reserve exceeds usable energy; mission not flown'" % cls, ok,
		"ended_by %s, flight_time %.2f s, sorties %d, warnings %s" % [r["ended_by"], r["flight_time_s"], r["sorties"], str(r["warnings"])])


# ---------------------------------------------------------------- (6)(7)(8) survey
static func _coverage(cls: String) -> TestResult:
	var r := _fly(_params(cls, Mission.SURVEY))
	var poly := float(r["polygon_area_m2"])
	var miss := absf(float(r["area_flown_m2"]) - poly) / poly
	return TestResult.new("sr4 mission survey coverage %s: area flown (from the track) within 2 %% of the polygon area" % cls,
		miss <= TOL_AREA and poly > 0.0 and String(r["ended_by"]) == "completed",
		"flown %.0f m2 vs polygon %.0f m2 (miss %.2f %%), coverage %.3f, holes %d" % [r["area_flown_m2"], poly, miss * 100.0, r["coverage_fraction"], (r["holes"] as Array).size()])


static func _side10(skip: int) -> Dictionary:
	var p := _params("five_inch", Mission.SURVEY)
	p["fields"] = {"side_overlap": 0.10}
	if skip >= 0:
		p["debug_skip_line"] = skip
	return _fly(p)


static func _coverage_skip() -> TestResult:
	var base := _side10(-1)
	var skipped := _side10(1)
	var poly := float(base["polygon_area_m2"])
	var miss_base := absf(float(base["area_flown_m2"]) - poly) / poly
	var miss_skip := absf(float(skipped["area_flown_m2"]) - poly) / poly
	return TestResult.new("sr4 mission skip a line: with 10 % side overlap the intact survey is within 2 % and the one with a line skipped misses it",
		miss_base <= TOL_AREA and miss_skip > TOL_AREA,
		"intact miss %.2f %%, skipped miss %.2f %%" % [miss_base * 100.0, miss_skip * 100.0])


static func _hole_warning() -> TestResult:
	var base := _side10(-1)
	var skipped := _side10(1)
	var ok: bool = _has(skipped, "coverage hole") and (skipped["holes"] as Array).size() > 0 and not _has(base, "coverage hole")
	return TestResult.new("sr4 mission hole flagged: a skipped line gives a 'coverage hole' warning with count and area, the intact survey none", ok,
		"skipped warnings %s; intact has hole warning: %s" % [str(skipped["warnings"]), str(_has(base, "coverage hole"))])


static func _forward_hole() -> TestResult:
	var p := _params("five_inch", Mission.SURVEY)
	p["fields"] = {"speed_mps": 8.0}
	var r := _fly(p)
	var kinds: Array = []
	for h in r["holes"]:
		kinds.append(String(h.get("kind", "area")))
	var ok: bool = _has(r, "forward overlap impossible") and "forward" in kinds
	return TestResult.new("sr4 mission forward overlap: 8 m/s at 25 m is too fast for the camera's 2 s minimum interval -> warning and a 'forward' hole in the result", ok,
		"hole kinds %s, warnings %d" % [str(kinds), (r["warnings"] as Array).size()])


static func _battery_swap() -> TestResult:
	var p := _params("five_inch", Mission.SURVEY)
	p["polygon"] = _field(100, 60)
	var r := _fly(p)
	var poly := float(r["polygon_area_m2"])
	var miss := absf(float(r["area_flown_m2"]) - poly) / poly
	var ok: bool = int(r["sorties"]) >= 2 and miss <= TOL_AREA and String(r["ended_by"]) == "completed" and _has(r, "battery swapped")
	return TestResult.new("sr4 mission battery swap: a 100 x 60 m survey too big for one 30 % pack completes in 2 or more sorties within 2 % of the area", ok,
		"sorties %d, miss %.2f %%, ended_by %s, flight %.0f s" % [r["sorties"], miss * 100.0, r["ended_by"], r["flight_time_s"]])


## The swap on a FULL-size pack (capacity scale 1, class defaults), not the 30 % pack the case above uses: a 200 x 120 m
## (24,000 m2) survey, 2.5 times the 5 inch's default 9,600 m2 field, which one 4S pack cannot cover above its 25 % reserve.
## FAIL-PROOF (max_sorties forced to 1 in the params): 1 sortie, ended landed_at_reserve, 'mission incomplete' warning, area short.
static func _battery_swap_full_pack() -> TestResult:
	var p := {"class_id": "five_inch", "mission": Mission.SURVEY, "seed": SEED, "capacity_scale": 1.0, "polygon": _field(200, 120)}
	var r := _fly(p)
	var poly := float(r["polygon_area_m2"])
	var miss := absf(float(r["area_flown_m2"]) - poly) / poly
	var landed_ok := true
	for sr in r["sortie_reports"]:
		landed_ok = landed_ok and float(sr["reserve_left_pct"]) >= 25.0
	var ok: bool = int(r["sorties"]) >= 2 and miss <= TOL_AREA and String(r["ended_by"]) == "completed" and _has(r, "battery swapped") and landed_ok
	return TestResult.new("sr4 mission battery swap, full-size pack: a 200 x 120 m survey (2.5x the default field) needs 2 or more full packs, completes within 2 % of the area, every sortie lands at or above the 25 % reserve", ok,
		"sorties %d, %.0f of %.0f m2 (miss %.2f %%), ended_by %s, flight %.0f s, landed at reserve every sortie %s" % [r["sorties"], r["area_flown_m2"], poly, miss * 100.0, r["ended_by"], r["flight_time_s"], landed_ok])


# ---------------------------------------------------------------- (9)-(11)
static func _pack_parts() -> TestResult:
	var r := _fly(_params("five_inch", Mission.TEST_PACK))
	var parts: Array = r["parts"]
	var names: Array = []
	var all_fig := parts.size() == 3
	for pt in parts:
		names.append(String(pt["mission"]))
		all_fig = all_fig and (pt["figures"] as Dictionary).has("flight_time_s") and float(pt["flight_time_s"]) > 5.0 and float(pt["energy_wh"]) > 0.0
	var ok: bool = all_fig and names == [Mission.HOVER_ENDURANCE, Mission.CRUISE_LOOP, Mission.SURVEY] \
		and float(parts[2]["area_flown_m2"]) > 1000.0 and float(parts[0]["flight_time_s"]) < float(parts[1]["flight_time_s"]) + 200.0
	return TestResult.new("sr4 mission standard pack: one result with three parts (hover, cruise, survey), each with its own figures", ok,
		"parts %s, times %s" % [str(names), str(parts.map(func(x: Dictionary) -> float: return snappedf(x["flight_time_s"], 0.1)))])


static func _worked_example() -> TestResult:
	var d := Mission.defaults_for("mavic_3m", Mission.SURVEY)
	var f: Dictionary = d["fields"]
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 300), Vector2(0, 300)])
	var pl := SurveyPlanner.plan(poly, CameraParams.generic_1inch(), float(f["height_m"]["value"]), float(f["front_overlap"]["value"]), float(f["side_overlap"]["value"]), 8.0)
	# hand check (tests/test_sr4_survey.gd): 10 lines, spacing 31.5 m, path 5045.32 m, time 667.78 s at 8 m/s
	var ok: bool = int(pl["line_count"]) == 10 and absf(float(pl["spacing_m"]) - 31.5) < 1e-6 \
		and absf(float(pl["path_length_m"]) - 5045.32) < 0.05 and absf(float(pl["expected_time_s"]) - 667.78) < 0.05
	print("    worked example (mavic_3m defaults %.0f m, front %.2f, side %.2f; 400 x 300 m, 8 m/s): %d lines, spacing %.2f m, path %.2f m, time %.2f s (hand: 10, 31.5, 5045.32, 667.78)" % [
		f["height_m"]["value"], f["front_overlap"]["value"], f["side_overlap"]["value"], pl["line_count"], pl["spacing_m"], pl["path_length_m"], pl["expected_time_s"]])
	return TestResult.new("sr4 mission worked example: 400 x 300 m at the mavic_3m defaults (60 m, 75/65) plans 10 lines, 31.5 m, 5045.32 m, 667.78 s (hand check)", ok,
		"%d lines, spacing %.3f, path %.2f, time %.2f" % [pl["line_count"], pl["spacing_m"], pl["path_length_m"], pl["expected_time_s"]])


static func _json_round_trip() -> TestResult:
	var r := _fly(_params("five_inch", Mission.CRUISE_LOOP))
	var text := MissionResult.to_json(r)
	var back = JSON.parse_string(text)
	var ok: bool = back is Dictionary
	var detail := ""
	if ok:
		var d: Dictionary = back
		ok = int(d["seed"]) == SEED and int(d["schema_version"]) == 1 and String(d["versions"]["model"]) == "sr4-1" \
			and String(d["build_fingerprint"]) != "" and not d.has("_track")
		var fields: Dictionary = d["params"]["fields"]
		for k in Mission.FIELDS:
			var e: Dictionary = fields[k]
			ok = ok and e.has("value") and e.has("default") and e.has("edited") and ["estimated", "published", "measured", "user"].has(String(e["tag"]))
		for k in d["figures"]:
			var fg: Dictionary = d["figures"][k]
			ok = ok and fg.has("value") and fg.has("low") and fg.has("high") and fg.has("unit") and fg.has("tag") and fg["range"] == "pending SR8"
		ok = ok and (d["figures"] as Dictionary).has("energy_wh") and (d["figures"] as Dictionary).has("flight_time_s")
		ok = ok and MissionResult.to_json(r) == text
		detail = "%d bytes, %d figures" % [text.length(), (d["figures"] as Dictionary).size()]
	return TestResult.new("sr4 mission JSON round trip: parses, carries seed, params (value/default/edited/tag), conditions, versions and tagged figures", ok, detail)


static func _survey_suite_still_passes() -> TestResult:
	var bad := 0
	for t in TestSr4Survey.run():
		if not t.passed:
			bad += 1
	return TestResult.new("sr4 mission: the existing sr4 survey suite still passes (sr4 nav is run by its own suite entry)", bad == 0, "%d failing" % bad)


static func _unknown_class() -> TestResult:
	var d := Mission.defaults_for("no_such_class", Mission.SURVEY)
	var r := MissionRunner.run({"class_id": "no_such_class", "mission": Mission.SURVEY})
	var ok: bool = not bool(d["ok"]) and String(d["error"]).contains("unknown class") and String(r["ended_by"]) == "error" and not bool(r["completed"])
	return TestResult.new("sr4 mission unknown class: a clear error from defaults_for and from the runner, no flight", ok, String(d["error"]))
