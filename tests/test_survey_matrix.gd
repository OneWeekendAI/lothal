class_name TestSurveyMatrix
extends RefCounted
## Survey matrix runner (cross-check phase A): one run spec in, one runs.csv row out, with the electrical and camera figures taken from
## the real mission result (never back-computed). Cases use a small 300 x 200 m field so the suite stays quick.
## FAIL-PROOF: with src/autopilot/survey_matrix.gd absent every case FAILS (class missing); with the telemetry block removed from
## MissionRunner._result the electrical case FAILS (cells empty).

const COLUMNS_N := 46


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
