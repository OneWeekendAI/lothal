extends SceneTree
## SR4 CLI: see tools/run_mission.sh. Exit 0 = mission completed, 1 = failed / aborted, 2 = usage error.

const USAGE := "usage: tools/run_mission.sh --class=<id> --mission=<hover_endurance|cruise_loop|range_test|survey|follow_path|test_pack> [--seed=N --height=M --speed=M/S --front=0.75 --side=0.65 --reserve=PCT --wind=MPS --wind-from=DEG --gust=MPS --capacity-scale=X --out=path.json]"


func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg:
			print("bad argument '%s'\n%s" % [arg, USAGE])
			quit(2)
			return
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var known := ["class", "mission", "seed", "height", "speed", "front", "side", "reserve", "wind", "wind-from", "gust", "capacity-scale", "out"]
	for k in a:
		if not k in known:
			print("unknown option --%s\n%s" % [k, USAGE])
			quit(2)
			return
	if not a.has("class") or not a.has("mission"):
		print("--class and --mission are required\n" + USAGE)
		quit(2)
		return
	if not Mission.is_mission(a["mission"]):
		print("unknown mission '%s' (known: %s)" % [a["mission"], ", ".join(Mission.IDS)])
		quit(2)
		return
	if not Mission.is_known_class(a["class"]):
		print("unknown class '%s'" % a["class"])
		quit(2)
		return
	var fields := {}
	for pair in [["height", "height_m"], ["speed", "speed_mps"], ["front", "front_overlap"], ["side", "side_overlap"], ["reserve", "reserve_pct"]]:
		if a.has(pair[0]):
			fields[pair[1]] = float(a[pair[0]])
	var params := {"class_id": a["class"], "mission": a["mission"], "seed": int(a.get("seed", "1")), "fields": fields,
		"wind_speed_mps": float(a.get("wind", "0")), "wind_from_deg": float(a.get("wind-from", "0")),
		"gust_mps": float(a.get("gust", "0")), "capacity_scale": float(a.get("capacity-scale", "1"))}
	var t0 := Time.get_ticks_msec()
	var r := MissionRunner.run(params)
	var out_path: String = a.get("out", "/tmp/lothal_missions/%s_%s_%d.json" % [params["class_id"], params["mission"], params["seed"]])
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(MissionResult.to_json(r))
		f.close()
	print("")
	print("MISSION %s  class %s  seed %d  capacity_scale %.2f  (model %s)" % [r["mission"], r["class_id"], r["seed"], params["capacity_scale"], MissionResult.MODEL_VERSION])
	print("  ended by      %s%s" % [r["ended_by"], "" if r["completed"] else "   (NOT COMPLETED)"])
	print("  flight time   %.1f s (%.2f min), %d sortie(s)" % [r["flight_time_s"], r["flight_time_s"] / 60.0, r["sorties"]])
	print("  distance      %.0f m, max from home %.0f m" % [r["distance_m"], r["max_distance_from_home_m"]])
	print("  energy        %.2f Wh (%.2f Wh/min)" % [r["energy_wh"], r["wh_per_min"]])
	print("  reserve left  %.1f %%, home error %.2f m" % [r["reserve_left_pct"], r["home_error_m"]])
	if r["polygon_area_m2"] > 0.0 or r["area_flown_m2"] > 0.0:
		print("  area flown    %.0f m2 (polygon %.0f m2, coverage %.1f %%)" % [r["area_flown_m2"], r["polygon_area_m2"], r["coverage_fraction"] * 100.0])
	for w in r["warnings"]:
		print("  warning: %s" % w)
	print("  wall time     %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("  json          %s" % out_path)
	quit(0 if bool(r["completed"]) else 1)
