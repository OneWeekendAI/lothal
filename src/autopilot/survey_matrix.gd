class_name SurveyMatrix
extends RefCounted
## Survey matrix runner core (cross-check phase A): one run spec in, one runs.csv row out. Every figure is read from the mission
## result (MissionRunner.run, incl. its "telemetry" block); nothing is back-computed. A figure the sim cannot give is left "" (empty).
## Spec keys: run_id, group, sensor (rededge_p|sentera_6x|mavic), pack_ah (15|10), rgb_addon, rtk, remote_id (echoed, not modelled),
## height_m, front, side, speed_mps (omit = camera-interval auto), fps_cap (true = camera trigger floor set to the PUBLISHED max fps),
## reserve_pct, field "WxH", wind_mph, wind_dir (calm|along|across|quartering; lines run east-west), gust_frac, seed, farm_acres.

const COLUMNS := ["run_id", "group", "sensor", "pack_ah", "pack_wh", "rgb_addon", "rtk", "remote_id", "height_m", "front", "side",
	"speed_mps", "speed_source", "reserve_pct", "field", "field_acres", "wind_mph", "wind_dir", "gust_frac", "seed", "mass_kg", "twr", "flight_min",
	"left_pct", "ended_by", "energy_wh", "acres_batt", "acres_low", "acres_high", "mapped_acres", "packs500", "packs500_low",
	"packs500_high", "gsd_cm", "trigger_interval_s", "required_fps", "camera_max_fps", "trigger_ok", "peak_current_a", "pack_limit_a",
	"min_voltage_v", "hover_power_w", "cruise_power_w", "meets_30min", "meets_4to5_packs", "meets_100_125_acres",
	"pack_s", "speed_cap_mps", "sorties", "packs_used", "farm_complete", "acres_per_sortie", "warnings"]
## Published maximum capture rates (sheets / camera presets): RedEdge-P 3 per s, Sentera 6X 5 per s, Mavic 3M 2 s interval.
const CAMERA_MAX_FPS := {"rededge_p": 3.0, "sentera_6x": 5.0, "mavic": 0.5}
const MPH := 0.44704


static func wind_from_deg(name: String) -> float:
	match name:
		"along": return 90.0
		"quartering": return 45.0
		_: return 0.0


static func _empty_row() -> Dictionary:
	var r := {}
	for c in COLUMNS:
		r[c] = ""
	return r


static func run_spec(spec: Dictionary) -> Dictionary:
	var row := _empty_row()
	for k in ["run_id", "group", "sensor", "pack_ah", "rgb_addon", "rtk", "remote_id", "height_m", "front", "side", "reserve_pct", "field", "wind_mph", "wind_dir", "gust_frac", "seed"]:
		if spec.has(k):
			row[k] = spec[k]
	var sensor := String(spec.get("sensor", "rededge_p"))
	row["sensor"] = sensor
	# every row carries the EFFECTIVE value used, never a blank for "default"
	row["height_m"] = float(spec.get("height_m", 60.0))
	row["front"] = float(spec.get("front", 0.75))
	row["side"] = float(spec.get("side", 0.65))
	row["reserve_pct"] = float(spec.get("reserve_pct", 25.0))
	row["wind_mph"] = float(spec.get("wind_mph", 0.0))
	row["wind_dir"] = String(spec.get("wind_dir", "calm")) if float(spec.get("wind_mph", 0.0)) > 0.0 else "calm"
	row["gust_frac"] = float(spec.get("gust_frac", 0.0))
	row["seed"] = int(spec.get("seed", 1))
	if sensor != "mavic":
		row["rgb_addon"] = "true" if bool(spec.get("rgb_addon", false)) else "false"
		row["rtk"] = "true" if bool(spec.get("rtk", true)) else "false"
		row["remote_id"] = "true" if bool(spec.get("remote_id", false)) else "false"
	row["field"] = String(spec.get("field", "1000x500"))
	var fs := String(spec.get("field", "1000x500")).split("x")
	var fw := float(fs[0])
	var fh := float(fs[1]) if fs.size() > 1 else 500.0
	row["field_acres"] = snappedf(fw * fh / 4046.856, 0.1)
	var poly := PackedVector2Array([Vector2(30, 0), Vector2(30 + fw, 0), Vector2(30 + fw, fh), Vector2(30, fh)])
	var h := float(spec.get("height_m", 60.0))
	var front := float(spec.get("front", 0.75))
	var fields := {"height_m": h, "front_overlap": front, "side_overlap": float(spec.get("side", 0.65)), "reserve_pct": float(spec.get("reserve_pct", 25.0))}
	var wind := float(spec.get("wind_mph", 0.0)) * MPH
	var params := {"mission": Mission.SURVEY, "seed": int(spec.get("seed", 1)), "fields": fields, "polygon": poly,
		"wind_speed_mps": wind, "wind_from_deg": wind_from_deg(String(spec.get("wind_dir", "calm"))), "gust_mps": wind * float(spec.get("gust_frac", 0.0)),
		"max_sorties": 1, "farm_acres": float(spec.get("farm_acres", 500.0)),
		"max_wall_s": float(spec.get("max_wall_s", 900.0)), "max_sim_min": float(spec.get("max_sim_min", 120.0))}
	var build: Build
	var pack_id := ""
	if sensor == "mavic":
		params["class_id"] = "mavic_3m"
		params["camera"] = CameraParams.from_preset("mavic_3m_multispectral")
		build = MissionRunner.make_build("mavic_3m", 1.0)
		params["build"] = build
	else:
		var pack_key := String(spec.get("pack", str(int(spec.get("pack_ah", 15)))))
		var made := SurveyKitBuilds.make({"sensor": sensor, "pack": pack_key, "rtk": bool(spec.get("rtk", true)), "rgb_addon": bool(spec.get("rgb_addon", false))})
		if String(made.get("error", "")) != "":
			row["warnings"] = "error: " + String(made["error"])
			return row
		build = made["build"]
		params["class_id"] = "mapper"
		params["build"] = build
		params["camera"] = made["camera"]
		pack_id = String(SurveyKitBuilds.PACKS.get(pack_key, ""))
		var bs: Dictionary = build.battery.get("specs", {})
		row["pack_ah"] = snappedf(float(bs.get("mah", 0.0)) / 1000.0, 0.1)
		row["pack_s"] = int(bs.get("cells", 0))
	var cam: CameraParams = params["camera"]
	var max_fps := float(CAMERA_MAX_FPS.get(sensor, 0.0))
	if bool(spec.get("fps_cap", false)) and max_fps > 0.0:
		cam.min_shot_interval_s = 1.0 / max_fps
	if spec.has("speed_mps") and str(spec["speed_mps"]) != "":
		fields["speed_mps"] = float(spec["speed_mps"])
		row["speed_source"] = "manual"
	else:
		fields["speed_mps"] = Mission.fp_survey_speed(cam, h, front, 15.0)
		row["speed_source"] = "auto_1s" if sensor == "rededge_p" and not bool(spec.get("fps_cap", false)) else "auto_camera_fps"
	row["speed_mps"] = snappedf(float(fields["speed_mps"]), 0.01)
	row["mass_kg"] = snappedf(build.mass_properties.total_mass_kg, 0.001)
	row["twr"] = snappedf(build.thrust_to_weight(), 0.01)
	var r := MissionRunner.run(params)
	if String(r.get("ended_by", "")) == "wall_cap":
		row["ended_by"] = "wall_cap"
		row["warnings"] = "error: " + " | ".join(PackedStringArray(r.get("warnings", [])))
		return row
	var ab: Dictionary = r.get("acres_per_battery", {})
	var bf: Dictionary = r.get("batteries_per_farm", {})
	var ph: Dictionary = r.get("photos", {})
	var tel: Dictionary = r.get("telemetry", {})
	row["pack_wh"] = snappedf(float(r.get("params", {}).get("nominal_pack_wh", 0.0)), 0.1)
	row["flight_min"] = snappedf(float(r["flight_time_s"]) / 60.0, 0.1)
	row["left_pct"] = snappedf(float(r["reserve_left_pct"]), 0.1)
	row["ended_by"] = String(r["ended_by"])
	row["energy_wh"] = snappedf(float(r["energy_wh"]), 0.1)
	row["acres_batt"] = snappedf(float(ab.get("value", 0.0)), 0.1)
	row["acres_low"] = snappedf(float(ab.get("low", 0.0)), 0.1)
	row["acres_high"] = snappedf(float(ab.get("high", 0.0)), 0.1)
	row["mapped_acres"] = snappedf(float(ph.get("mapped_acres", 0.0)), 0.1)
	if float(ab.get("value", 0.0)) > 0.0:
		row["packs500"] = snappedf(float(bf.get("value", 0.0)), 0.01)
		row["packs500_low"] = snappedf(float(bf.get("low", 0.0)), 0.01)
		row["packs500_high"] = snappedf(float(bf.get("high", 0.0)), 0.01)
	if float(ph.get("images", 0)) > 0:
		row["gsd_cm"] = snappedf(float(ph["gsd_cm"]["mean"]), 0.01)
	var ti := float(tel.get("trigger_interval_s", 0.0))
	if ti > 0.0:
		row["trigger_interval_s"] = snappedf(ti, 0.001)
		row["required_fps"] = snappedf(1.0 / ti, 0.001)
		if max_fps > 0.0:
			row["camera_max_fps"] = max_fps
			row["trigger_ok"] = "true" if 1.0 / ti <= max_fps + 1e-6 else "false"
	for pair in [["peak_current_a", "peak_current_a", 0.1], ["min_voltage_v", "min_voltage_v", 0.01], ["hover_power_w", "hover_power_w", 0.1], ["cruise_power_w", "cruise_power_w", 0.1]]:
		var v := float(tel.get(pair[1], -1.0))
		if v > 0.0:
			row[pair[0]] = snappedf(v, float(pair[2]))
	if pack_id != "":
		var part: Dictionary = PartsCatalog.load_default().get_part(pack_id)
		if not part.is_empty():
			row["pack_limit_a"] = snappedf(float(part["specs"]["c_rating"]) * float(part["specs"]["mah"]) / 1000.0, 0.1)
	var warns := PackedStringArray(r["warnings"])
	endurance_verdict(row, warns)
	if str(row["packs500"]) != "":
		row["meets_4to5_packs"] = "true" if float(row["packs500"]) <= 5.0 else "false"
		row["meets_100_125_acres"] = "true" if float(row["acres_batt"]) >= 100.0 else "false"
	row["warnings"] = " | ".join(warns)
	return row


## meets_30min from the row's flight_min, ended_by, left_pct and reserve_pct; appends the reason to `warns` when it has to stay blank.
## A sortie that finished the field, or stopped at a line boundary far above the reserve, measured mission time, not endurance.
static func endurance_verdict(row: Dictionary, warns: PackedStringArray) -> void:
	if not row["flight_min"] is float:
		return
	row["meets_30min"] = "true" if float(row["flight_min"]) >= 30.0 else "false"
	# the line-fit lookahead sent it home with far more than the reserve: the time is line-quantised, so a short one cannot fail the ask
	if String(row["ended_by"]) == "landed_at_reserve" and float(row["flight_min"]) < 30.0 and str(row.get("reserve_pct", "")) != "" \
			and float(row["left_pct"]) > float(row["reserve_pct"]) + 10.0:
		row["meets_30min"] = ""
		warns.append("sortie stopped at a line boundary with %s %% left (reserve %s %%): flight_min understates endurance; meets_30min unknown" % [str(row["left_pct"]), str(row["reserve_pct"])])
	# a sortie that finished the field before the reserve measured mission time, not endurance: it cannot fail the 30 min ask
	if String(row["ended_by"]) == "completed" and float(row["flight_min"]) < 30.0:
		row["meets_30min"] = ""
		warns.append("field completed with %s %% left: flight_min is mission time, not endurance; meets_30min unknown (use a bigger field)" % str(row["left_pct"]))


static func csv_cell(v: Variant) -> String:
	if v == null:
		return ""
	var s := str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


static func csv_header() -> String:
	return ",".join(PackedStringArray(COLUMNS))


static func csv_line(row: Dictionary) -> String:
	var cells := PackedStringArray()
	for c in COLUMNS:
		cells.append(csv_cell(row.get(c, "")))
	return ",".join(cells)
