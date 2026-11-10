extends SceneTree
## SR4 CLI: see tools/run_mission.sh. Exit 0 = mission completed, 1 = failed / aborted, 2 = usage error.

const USAGE := "usage: tools/run_mission.sh --class=<id> --mission=<hover_endurance|cruise_loop|range_test|survey|follow_path|test_pack> [--seed=N --height=M --speed=M/S --front=0.75 --side=0.65 --reserve=PCT --wind=MPS --wind-from=DEG --gust=MPS --capacity-scale=X --rate-hz=500 --out=path.json --record=record.json --csv=out.csv] | tools/run_mission.sh --class=.. --mission=.. --mc=N [--master-seed=S --metric=flight_time_s --tol-capacity_pct=5 ... --dominant=1] | tools/run_mission.sh --replay=record.json [--allow-version-mismatch=1]"


func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg:
			print("bad argument '%s'\n%s" % [arg, USAGE])
			quit(2)
			return
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var known := ["class", "mission", "seed", "height", "speed", "front", "side", "reserve", "wind", "wind-from", "gust", "capacity-scale", "rate-hz", "out", "record", "csv", "replay", "allow-version-mismatch", "mc", "master-seed", "metric", "dominant"]
	for k in a:
		if not k in known and not (String(k).begins_with("tol-") and String(k).substr(4) in Tolerances.NAMES):
			print("unknown option --%s\n%s" % [k, USAGE])
			quit(2)
			return
	if a.has("replay"):
		_replay(String(a["replay"]), String(a.get("allow-version-mismatch", "0")) == "1")
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
		"gust_mps": float(a.get("gust", "0")), "capacity_scale": float(a.get("capacity-scale", "1")),
		"dt": 1.0 / float(a.get("rate-hz", "500"))}
	if a.has("mc") or a.has("dominant"):
		_uncertainty(params, a)
		return
	var t0 := Time.get_ticks_msec()
	var r := MissionRunner.run(params)
	var out_path: String = a.get("out", "/tmp/lothal_missions/%s_%s_%d.json" % [params["class_id"], params["mission"], params["seed"]])
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(MissionResult.to_json(r))
		f.close()
	var rec_made := {}
	if a.has("record") or a.has("csv"):
		rec_made = RunRecord.make(params, r)
	if a.has("record") and not RunRecord.save_json(rec_made, String(a["record"])):
		print("cannot write the record to %s" % a["record"])
	if a.has("csv") and not RunRecord.save_csv(rec_made, String(a["csv"])):
		print("cannot write the csv to %s" % a["csv"])
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
	if a.has("record"):
		print("  record        %s" % a["record"])
	if a.has("csv"):
		print("  csv           %s" % a["csv"])
	quit(0 if bool(r["completed"]) else 1)


## SR7.2: --replay=record.json. Exit 0 identical, 1 differs, 3 refused (nothing flown), 2 unreadable file.
func _replay(path: String, allow: bool) -> void:
	var text := FileAccess.get_file_as_string(path)
	var rec := RunRecord.from_json(text)
	if rec.is_empty():
		print("cannot read a run record from '%s'" % path)
		quit(2)
		return
	var rp := RunReplay.replay(rec, allow)
	print("")
	print("REPLAY %s  status %s" % [path, String(rp["status"]).to_upper()])
	for m in rp["reasons"]:
		print("  refused: %s" % m)
	for m in rp["flags"]:
		print("  flag: %s" % m)
	for d in rp["diffs"]:
		print("  differs: %s" % str(d))
	quit(0 if rp["status"] == "identical" else (3 if rp["status"] == "refused" else 1))


## SR8.2 / SR8.3: --mc=N (Monte Carlo range of --metric over the tolerances) and/or --dominant=1 (one-at-a-time ranking). Tolerances are the
## defaults (all ESTIMATED) unless --tol-<name>=<half-width> edits one. Exit 0.
func _uncertainty(params: Dictionary, a: Dictionary) -> void:
	var tol := Tolerances.defaults()
	for k in a:
		if String(k).begins_with("tol-"):
			tol = tol.with_half(String(k).substr(4), float(a[k]))
	var metric := String(a.get("metric", "flight_time_s"))
	print("")
	print("UNCERTAINTY  class %s  mission %s  metric %s  (tolerances ESTIMATED unless edited)" % [params["class_id"], params["mission"], metric])
	for n in Tolerances.NAMES:
		var f: Dictionary = tol.fields[n]
		print("  tolerance %-15s +-%g %s  [%s%s]" % [n, f["half"], f["unit"], f["tag"], ", edited" if bool(f["edited"]) else ""])
	if a.has("mc"):
		var mc := MonteCarlo.run(params, tol, int(a["mc"]), int(a.get("master-seed", "1")), metric)
		print("  range  low %.4f   mid %.4f   high %.4f   (min %.4f, max %.4f)" % [mc["low"], mc["mid"], mc["high"], mc["min"], mc["max"]])
		print("  %s" % mc["range"])
	if a.has("dominant"):
		var d := Sensitivity.one_at_a_time(params, tol, metric)
		print("  nominal %.4f; dominant input: %s" % [d["nominal"], d["dominant"] if d["dominant"] != "" else "none (nothing varies)"])
		for e in d["entries"]:
			print("    %-15s spread %.4f  share %.0f %%  (%d flights)" % [e["input"], e["spread"], e["share"] * 100.0, e["flights"]])
	quit(0)
