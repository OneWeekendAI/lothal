extends SceneTree
## CropMerge calibration CLI: one survey on a rectangular field, printed as one line of key numbers.
## usage: godot --headless --script res://tools/run_survey_cal.gd -- --class=mavic_3m --camera=mavic_3m_multispectral --height=217 --speed=15
##   --front=0.7 --side=0.6 --reserve=0 --field=2000x1500 --wind=0 --gust=0 --wind-from=90 --seed=1 --sorties=1 [--generic=1]

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var fs := String(a.get("field", "2000x1500")).split("x")
	var fw := float(fs[0])
	var fh := float(fs[1])
	var poly := PackedVector2Array([Vector2(30, 0), Vector2(30 + fw, 0), Vector2(30 + fw, fh), Vector2(30, fh)])
	var fields := {}
	for pair in [["height", "height_m"], ["speed", "speed_mps"], ["front", "front_overlap"], ["side", "side_overlap"], ["reserve", "reserve_pct"]]:
		if a.has(pair[0]):
			fields[pair[1]] = float(a[pair[0]])
	var params := {"class_id": a.get("class", "mavic_3m"), "mission": Mission.SURVEY, "seed": int(a.get("seed", "1")), "fields": fields, "polygon": poly,
		"wind_speed_mps": float(a.get("wind", "0")), "wind_from_deg": float(a.get("wind-from", "90")), "gust_mps": float(a.get("gust", "0")),
		"max_sorties": int(a.get("sorties", "1")), "farm_acres": float(fw * fh / 4046.856)}
	if a.has("camera"):
		params["camera"] = CameraParams.from_preset(String(a["camera"]))
	if not fields.has("speed_mps") and params.has("camera"):
		# the default survey speed assumes the generic camera; with a real one use 0.95 x its own camera-interval cap, capped at 15 m/s
		var cam: CameraParams = params["camera"]
		var h := float(fields.get("height_m", 60.0))
		fields["speed_mps"] = Mission.fp_survey_speed(cam, h, float(fields.get("front_overlap", 0.75)), 15.0)
	var t0 := Time.get_ticks_msec()
	var r := MissionRunner.run(params)
	var ab: Dictionary = r.get("acres_per_battery", {})
	var ph: Dictionary = r.get("photos", {})
	print("CAL args=%s speed=%.2f" % [str(a), float(fields.get("speed_mps", -1))])
	print("CAL ended=%s completed=%s time_min=%.2f sorties=%d dist_km=%.1f energy_wh=%.1f" % [r["ended_by"], r["completed"], r["flight_time_s"] / 60.0, r["sorties"], r["distance_m"] / 1000.0, r["energy_wh"]])
	print("CAL mapped_acres=%.1f polygon_acres=%.1f cover=%.2f  acres_per_batt value=%.1f low=%.1f high=%.1f drawn=%.3f extrap=%s" % [float(ph.get("mapped_acres", 0)), r["polygon_area_m2"] / 4046.856, r["coverage_fraction"], float(ab.get("value", 0)), float(ab.get("low", 0)), float(ab.get("high", 0)), float(ab.get("pack_fraction_drawn", 0)), str(ab.get("extrapolated"))])
	for w in r["warnings"]:
		print("CAL warn: %s" % w)
	print("CAL reserve_left=%.1f wall_s=%.0f" % [r["reserve_left_pct"], (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
