extends SceneTree
## Survey variant: one survey of a delivery build, printed as one SV line.
## usage: godot --headless --path . --script res://tools/run_survey_variant.gd -- --sensor=rededge_p|sentera_6x|mavic --pack=15|10 [--rgb=1] [--rtk=0]
##   [--height=60 --front=0.75 --side=0.65 --speed=<m/s> --reserve=25 --field=1000x500 --wind=0 --gust=0 --wind-from=90 --seed=1 --farm=500]
## --speed omitted: 0.95 x the camera-interval cap at 15 m/s max (Mission.fp_survey_speed).

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var sensor := String(a.get("sensor", "rededge_p"))
	var fs := String(a.get("field", "1000x500")).split("x")
	var fw := float(fs[0])
	var fh := float(fs[1])
	var poly := PackedVector2Array([Vector2(30, 0), Vector2(30 + fw, 0), Vector2(30 + fw, fh), Vector2(30, fh)])
	var h := float(a.get("height", "60"))
	var front := float(a.get("front", "0.75"))
	var fields := {"height_m": h, "front_overlap": front, "side_overlap": float(a.get("side", "0.65")), "reserve_pct": float(a.get("reserve", "25"))}
	var params := {"mission": Mission.SURVEY, "seed": int(a.get("seed", "1")), "fields": fields, "polygon": poly,
		"wind_speed_mps": float(a.get("wind", "0")), "wind_from_deg": float(a.get("wind-from", "90")), "gust_mps": float(a.get("gust", "0")),
		"max_sorties": 1, "farm_acres": fw * fh / 4046.856}
	var mass_kg := 0.0
	if sensor == "mavic":
		params["class_id"] = "mavic_3m"
		params["camera"] = CameraParams.from_preset("mavic_3m_multispectral")
		var ref := MissionRunner.make_build("mavic_3m", 1.0)
		params["build"] = ref
		mass_kg = ref.mass_properties.total_mass_kg
		print("SV build mass_kg=%.3f payload_g=%.0f payload_w=%.1f" % [mass_kg, ref.payload_mass_g, ref.payload_w])
	else:
		var made := SurveyKitBuilds.make({"sensor": sensor, "pack": a.get("pack", "15"), "rtk": String(a.get("rtk", "1")) != "0", "rgb_addon": String(a.get("rgb", "0")) == "1"})
		if String(made["error"]) != "":
			print("SV error %s" % made["error"])
			quit(1)
			return
		var b: Build = made["build"]
		params["class_id"] = "mapper"
		params["build"] = b
		params["camera"] = made["camera"]
		mass_kg = b.mass_properties.total_mass_kg
		print("SV build mass_kg=%.3f payload_g=%.0f payload_w=%.1f twr=%.2f" % [mass_kg, b.payload_mass_g, b.payload_w, b.thrust_to_weight()])
	fields["speed_mps"] = float(a["speed"]) if a.has("speed") else Mission.fp_survey_speed(params["camera"], h, front, 15.0)
	var r := MissionRunner.run(params)
	var ab: Dictionary = r.get("acres_per_battery", {})
	var bf := SurveyKitBuilds.batteries_per_farm(float(a.get("farm", "100")), float(ab.get("value", 0)), float(ab.get("low", 0)), float(ab.get("high", 0)))
	print("SV args=%s speed=%.2f ended=%s time_min=%.1f left_pct=%.1f acres_batt=%.1f low=%.1f high=%.1f mapped=%.1f energy_wh=%.1f batt500=%.2f (%.2f-%.2f) packs=%d-%d extrap=%s" % [str(a), float(fields["speed_mps"]),
		r["ended_by"], r["flight_time_s"] / 60.0, float(r["reserve_left_pct"]), float(ab.get("value", 0)), float(ab.get("low", 0)), float(ab.get("high", 0)),
		float((r.get("photos", {}) as Dictionary).get("mapped_acres", 0)), r["energy_wh"], bf["value"], bf["low"], bf["high"], bf["packs_low"], bf["packs_high"], str(ab.get("extrapolated"))])
	for w in r["warnings"]:
		print("SV warn: %s" % w)
	quit(0)
