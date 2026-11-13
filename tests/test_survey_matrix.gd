class_name TestSurveyMatrix
extends RefCounted
## Survey matrix runner (cross-check phase A): one run spec in, one runs.csv row out, with the electrical and camera figures taken from
## the real mission result (never back-computed). Cases use a small 300 x 200 m field so the suite stays quick.
## FAIL-PROOF: with src/autopilot/survey_matrix.gd absent every case FAILS (class missing); with the telemetry block removed from
## MissionRunner._result the electrical case FAILS (cells empty).

const COLUMNS_N := 53


static func run() -> Array:
	var out: Array = []
	var row := SurveyMatrix.run_spec({"run_id": "t1", "group": "repro", "sensor": "rededge_p", "pack_ah": 15, "field": "300x200", "farm_acres": 500})
	out.append(_columns())
	out.append(_identity(row))
	out.append(_electrical(row))
	out.append(_camera(row))
	out.append(_csv())
	out.append(_wind_dir())
	out.append(_bad_sensor())
	out.append(_mavic_blank())
	out.append(_effective(row))
	out.append(_completed_not_endurance(row))
	out.append(_kit_effective(row))
	out.append_array(_line_boundary())
	out.append(_wall_cap())
	out.append(_remote_id_and_cap(row))
	out.append(_farm_swaps())
	return out


static func _columns() -> TestResult:
	var c: Array = SurveyMatrix.COLUMNS
	var ok: bool = c.size() == COLUMNS_N and c[0] == "run_id" and c[c.size() - 1] == "warnings" and c.has("peak_current_a") and c.has("required_fps")
	return TestResult.new("survey matrix: the CSV has the tracker's %d columns, run_id first, warnings last" % COLUMNS_N, ok, "n=%d" % c.size())


static func _identity(row: Dictionary) -> TestResult:
	var ok := String(row["run_id"]) == "t1" and String(row["group"]) == "repro" and absf(float(row["mass_kg"]) - 1.911) < 0.002 and float(row["pack_wh"]) > 215.0 and float(row["pack_wh"]) < 217.0 \
		and float(row["mapped_acres"]) > 0.0 and float(row["flight_min"]) > 1.0 and float(row["packs500"]) > 0.0 and String(row["speed_source"]) == "auto_1s"
	return TestResult.new("survey matrix: a RedEdge-P 15 Ah run reports mass 1.911 kg, 216 Wh, mapped acres, packs per 500 acres and the auto speed source", ok, str(row))


static func _electrical(row: Dictionary) -> TestResult:
	var pk = row["peak_current_a"]
	var v = row["min_voltage_v"]
	var ok: bool = typeof(pk) == TYPE_FLOAT and float(pk) > 10.0 and float(pk) < 200.0 and typeof(v) == TYPE_FLOAT and float(v) > 8.0 and float(v) < 17.0 \
		and float(row["hover_power_w"]) > 50.0 and float(row["cruise_power_w"]) > 50.0 and absf(float(row["pack_limit_a"]) - 75.0) < 0.01
	return TestResult.new("survey matrix: peak current, minimum pack voltage, hover and cruise power come from the sim, pack limit is the catalog 75 A", ok,
		"peak %s A, min %s V, hover %s W, cruise %s W, limit %s" % [str(pk), str(v), str(row["hover_power_w"]), str(row["cruise_power_w"]), str(row["pack_limit_a"])])


static func _camera(row: Dictionary) -> TestResult:
	var ok := float(row["gsd_cm"]) > 3.0 and float(row["gsd_cm"]) < 5.0 and float(row["trigger_interval_s"]) > 0.0 \
		and absf(float(row["required_fps"]) * float(row["trigger_interval_s"]) - 1.0) < 0.01 and float(row["camera_max_fps"]) > 0.0 and String(row["trigger_ok"]) in ["true", "false"]
	return TestResult.new("survey matrix: GSD, trigger interval, required fps (= 1 / interval) and camera max fps are filled", ok,
		"gsd %s interval %s req %s max %s" % [str(row["gsd_cm"]), str(row["trigger_interval_s"]), str(row["required_fps"]), str(row["camera_max_fps"])])


static func _csv() -> TestResult:
	var line := SurveyMatrix.csv_line({"run_id": "a,b", "warnings": "say \"hi\"", "mass_kg": 1.5, "twr": null})
	var cells := line.split(",")
	var ok := line.begins_with("\"a,b\",") and line.contains("\"say \"\"hi\"\"\"") and line.contains(",1.5,") and cells.size() >= SurveyMatrix.COLUMNS.size()
	return TestResult.new("survey matrix: csv_line quotes commas and quotes, leaves unknown cells empty and orders by COLUMNS", ok, line.left(120))


static func _wind_dir() -> TestResult:
	var a := SurveyMatrix.wind_from_deg("along")
	var x := SurveyMatrix.wind_from_deg("across")
	var q := SurveyMatrix.wind_from_deg("quartering")
	var ok := absf(a - 90.0) < 0.01 and absf(x - 0.0) < 0.01 and absf(q - 45.0) < 0.01
	return TestResult.new("survey matrix: wind dir names map to from-degrees for east-west lines (along 90, across 0, quartering 45)", ok, "%s %s %s" % [a, x, q])


static func _bad_sensor() -> TestResult:
	var row := SurveyMatrix.run_spec({"run_id": "bad", "sensor": "nope", "field": "300x200"})
	var ok := String(row["run_id"]) == "bad" and String(row["warnings"]).contains("error") and str(row["flight_min"]) == ""
	return TestResult.new("survey matrix: an unknown sensor yields an error row with no invented numbers, not a crash", ok, str(row["warnings"]))


static func _mavic_blank() -> TestResult:
	var row := SurveyMatrix.run_spec({"run_id": "m", "sensor": "mavic", "field": "300x200", "pack_ah": 0})
	var ok := float(row["flight_min"]) > 1.0 and str(row["pack_limit_a"]) == "" and float(row["peak_current_a"]) > 0.0
	return TestResult.new("survey matrix: the Mavic reference leaves the pack current limit empty (no catalog entry) but still reports sim peak current", ok,
		"limit '%s' peak %s" % [str(row["pack_limit_a"]), str(row["peak_current_a"])])


static func _effective(row: Dictionary) -> TestResult:
	## A spec that omits height/overlap/reserve/wind/gust/seed must still report the values the run used.
	var ok := float(row["height_m"]) == 60.0 and float(row["front"]) == 0.75 and float(row["side"]) == 0.65 and float(row["reserve_pct"]) == 25.0 \
		and float(row["wind_mph"]) == 0.0 and float(row["gust_frac"]) == 0.0 and int(row["seed"]) == 1 and String(row["wind_dir"]) == "calm" \
		and absf(float(row["field_acres"]) - 300.0 * 200.0 / 4046.856) < 0.06
	return TestResult.new("survey matrix: omitted spec fields are reported as the effective defaults used, with the field area in acres", ok,
		"h %s f %s s %s res %s wind %s gust %s seed %s acres %s" % [str(row["height_m"]), str(row["front"]), str(row["side"]), str(row["reserve_pct"]), str(row["wind_mph"]), str(row["gust_frac"]), str(row["seed"]), str(row.get("field_acres", "MISSING"))])


## A run that finishes the field before reaching the reserve has a flight_min that is MISSION time, not endurance, so it cannot
## judge the 30 min ask. FAIL-PROOF: without the completed-row rule meets_30min reads "false" here (a 300 x 200 m field takes minutes).
static func _completed_not_endurance(row: Dictionary) -> TestResult:
	var ok := String(row["ended_by"]) == "completed" and str(row["meets_30min"]) == "" and String(row["warnings"]).contains("not endurance")
	return TestResult.new("survey matrix: a run that completes the field leaves meets_30min blank and says flight_min is not endurance", ok, "%s %s / %s" % [row["ended_by"], row["meets_30min"], row["flight_min"]])


## Phase C: rgb_addon / rtk / pack_ah / remote_id carry the EFFECTIVE value even when the spec omits them (runs.csv was patched for this).
## FAIL-PROOF (seen red 2026-11-13): before the fix these four cells were blank on a default spec.
static func _kit_effective(row: Dictionary) -> TestResult:
	var ok := str(row["rgb_addon"]) == "false" and str(row["rtk"]) == "true" and str(row["remote_id"]) == "false" and float(str(row["pack_ah"]) if str(row["pack_ah"]) != "" else "0") == 15.0 and str(row["pack_s"]) == "4"
	return TestResult.new("survey matrix: a default spec reports rgb_addon false, rtk true, remote_id false, pack 15 Ah 4S (effective, not blank)", ok,
		"rgb '%s' rtk '%s' rid '%s' pack '%s' s '%s'" % [str(row["rgb_addon"]), str(row["rtk"]), str(row["remote_id"]), str(row["pack_ah"]), str(row["pack_s"])])


## Phase C: a sortie that lands at a line boundary with far more than the reserve left (> reserve + 10 points) measured a
## line-quantised time, not endurance: the RUNNER blanks a failing meets_30min and says why (200 rows were patched by hand).
## FAIL-PROOF (seen red 2026-11-13): without the rule the 22.6 min / 53 % row read meets_30min "false".
static func _line_boundary() -> Array:
	var out: Array = []
	var cases := [[22.6, 53.0, "landed_at_reserve", "", true], [22.6, 30.0, "landed_at_reserve", "false", false], [31.0, 53.0, "landed_at_reserve", "true", false]]
	for c in cases:
		var row := {"flight_min": c[0], "left_pct": c[1], "ended_by": c[2], "reserve_pct": 25.0, "meets_30min": ""}
		var w := PackedStringArray()
		SurveyMatrix.endurance_verdict(row, w)
		var said := " ".join(w).contains("line boundary")
		out.append(TestResult.new("survey matrix: %.1f min with %.0f %% left (reserve 25) -> meets_30min '%s', line-boundary warning %s" % [c[0], c[1], c[3], str(c[4])],
			str(row["meets_30min"]) == c[3] and said == c[4], "got '%s' warns %s" % [str(row["meets_30min"]), str(w)]))
	return out


## Phase C: a run past its wall-time budget stops and yields an ERROR row (no figures), never a hang.
## FAIL-PROOF (seen red 2026-11-13): before the guard max_wall_s was ignored and the run produced a normal row.
static func _wall_cap() -> TestResult:
	var row := SurveyMatrix.run_spec({"run_id": "w", "sensor": "rededge_p", "field": "300x200", "max_wall_s": 0.01})
	var ok := String(row["ended_by"]) == "wall_cap" and String(row["warnings"]).begins_with("error") and str(row["flight_min"]) == "" and str(row["acres_batt"]) == "" and String(row["run_id"]) == "w"
	return TestResult.new("survey matrix: a run past max_wall_s ends 'wall_cap' as an error row with no figures", ok, "%s / %s / %s" % [row["ended_by"], row["flight_min"], str(row["warnings"]).left(80)])


## Phase C: the remote_id key flies the Beacon's 16 g; speed_cap_mps replaces the fixed 15 m/s auto-speed ceiling and is reported.
## FAIL-PROOF (seen red 2026-11-13): before run_spec passed remote_id the mass delta was 0; before the key the cap cell was blank and
## the Sentera 6X at 120 m sat at 15 m/s.
static func _remote_id_and_cap(base: Dictionary) -> TestResult:
	var rid := SurveyMatrix.run_spec({"run_id": "rid", "sensor": "rededge_p", "field": "300x200", "remote_id": true})
	var cap := SurveyMatrix.run_spec({"run_id": "cap", "sensor": "sentera_6x", "field": "300x200", "height_m": 120, "speed_cap_mps": 20})
	var dm := (float(rid["mass_kg"]) - float(base["mass_kg"])) * 1000.0
	var ok := absf(dm - 16.0) < 1.01 and String(rid["remote_id"]) == "true" and float(str(cap["speed_cap_mps"]) if str(cap["speed_cap_mps"]) != "" else "0") == 20.0 \
		and float(cap["speed_mps"]) > 15.0 and float(str(base["speed_cap_mps"]) if str(base["speed_cap_mps"]) != "" else "0") == 15.0
	return TestResult.new("survey matrix: remote_id adds 16 g to mass_kg; speed_cap_mps 20 lets the Sentera at 120 m pass 15 m/s and is reported (default 15)", ok,
		"dm %.1f g, cap %s speed %s, base cap %s" % [dm, str(cap["speed_cap_mps"]), str(cap["speed_mps"]), str(base["speed_cap_mps"])])


## Phase C: max_sorties > 1 swaps packs until the field is done: sorties, packs_used (sum of pack fractions drawn), farm_complete and
## acres_per_sortie come from the run's own sortie reports. FAIL-PROOF (seen red 2026-11-13): before the key the runner forced
## max_sorties 1, so this 10 Ah run stopped after one sortie with farm_complete blank.
static func _farm_swaps() -> TestResult:
	var r := SurveyMatrix.run_spec({"run_id": "farm", "sensor": "rededge_p", "pack_ah": 10, "field": "1000x500", "max_sorties": 6, "max_sim_min": 300})
	var ok := String(r["ended_by"]) == "completed" and int(r["sorties"]) >= 2 and String(r["farm_complete"]) == "true" \
		and float(r["packs_used"]) > 0.5 and float(r["packs_used"]) <= float(r["sorties"]) \
		and absf(float(r["acres_per_sortie"]) * int(r["sorties"]) - float(r["mapped_acres"])) < 0.2 * int(r["sorties"])
	return TestResult.new("survey matrix: a 10 Ah run over 1000 x 500 m with max_sorties 6 swaps packs and completes; sorties, packs_used, acres per sortie reported", ok,
		"%s sorties %s packs %s complete %s aps %s mapped %s" % [r["ended_by"], str(r["sorties"]), str(r["packs_used"]), str(r["farm_complete"]), str(r["acres_per_sortie"]), str(r["mapped_acres"])])
