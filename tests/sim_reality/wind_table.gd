extends SceneTree
## SR2 mission table in wind: godot --headless --script res://tests/sim_reality/wind_table.gd -- [mission=survey,cruise_loop] [cls=five_inch,seven_lr,cinelifter] [mph=0,15,20] [z0 not exposed: 0.03]
## Wind is quoted at 10 m; turbulence is the MIL value for that wind (Wind.mil_gustiness_mps).
func _init() -> void:
	var missions := ["survey", "cruise_loop"]
	var classes := ["five_inch", "seven_lr", "cinelifter"]
	var mphs := [0.0, 15.0, 20.0]
	for a in OS.get_cmdline_user_args():
		var k: String = a.get_slice("=", 0)
		var v: PackedStringArray = a.get_slice("=", 1).split(",")
		match k:
			"mission": missions = Array(v)
			"cls": classes = Array(v)
			"mph":
				mphs = []
				for s in v:
					mphs.append(float(s))
	print("class       mission       mph  time_min  area_m2  energy_Wh  dist_m  sorties  alt_err_max_m  ended_by")
	for cls in classes:
		for m in missions:
			for mph in mphs:
				var spd: float = mph * 0.44704
				var p := {"class_id": cls, "mission": m, "seed": 1, "wind_speed_mps": spd, "wind_from_deg": 90.0,
					"gust_mps": Wind.mil_gustiness_mps(spd) if spd > 0.0 else 0.0}
				var r := MissionRunner.run(p)
				var alt: float = float(r["params"]["fields"]["height_m"]["value"])
				var trk: PackedFloat64Array = r["_track"]
				var worst := 0.0
				for i in int(trk.size() / 5.0):
					var y := trk[i * 5 + 2]
					if y > 0.9 * alt:
						worst = maxf(worst, absf(y - alt))
				print("%-11s %-12s %4.0f  %8.2f %8.0f %10.2f %7.0f %8d %13.2f  %s" % [cls, m, mph, float(r["flight_time_s"]) / 60.0,
					float(r["area_flown_m2"]), float(r["energy_wh"]), float(r["distance_m"]), int(r["sorties"]), worst, r["ended_by"]])
	quit()
