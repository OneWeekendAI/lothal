extends SceneTree
## CropMerge mapper build search: one survey of a mapper-class variant, printed as one CAL line.
## usage: godot --headless --script res://tools/run_build_search.gd -- --motor=motor_2808_1300kv --prop=prop_10x5x2 --battery=mapper_battery_4s_10000_liion
##   [--mah=15000 --pack_mass=870 --pack_r=0.035 --cells=4]  (custom pack: a copy of the mapper pack with these specs, ESTIMATED)
##   [--field=1500x500 --wind=8.94 --gust=1.79 --wind-from=90 --seed=1 --reserve=25 --height=60 --speed=9.75] [--info=1] (build facts only)

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var cat := PartsCatalog.load_default()
	if a.has("mah"):
		var src: Dictionary = cat.get_part(String(a.get("battery", "mapper_battery_4s_10000_liion"))).duplicate(true)
		src["part_id"] = "search_pack"
		src["mass_g"] = float(a.get("pack_mass", src["mass_g"]))
		var sp: Dictionary = src["specs"]
		sp["mah"] = float(a["mah"])
		if a.has("pack_r"):
			sp["internal_r_ohm"] = float(a["pack_r"])
		if a.has("cells"):
			sp["cells"] = int(a["cells"])
			sp["nominal_v"] = 3.6 * int(a["cells"])
		cat.by_id["search_pack"] = src
		cat.by_category["battery"].append(src)
		a["battery"] = "search_pack"
	var ds := DesignSession.default_for_class("mapper")
	for pair in [["frame", "frame"], ["motor", "motor"], ["prop", "propeller"], ["battery", "battery"], ["esc", "esc"]]:
		if a.has(pair[0]):
			var res := ds.swap(cat, pair[1], String(a[pair[0]]))
			if not bool(res.get("ok", true)):
				print("CAL swap refused: %s" % str(res))
	var b := ds.build(cat)
	var pm := b.mass_properties.total_mass_kg
	print("CAL build mass_kg=%.3f twr=%.2f hover_thr=%.2f motor=%s prop=%s battery=%s" % [pm, b.thrust_to_weight(), b.hover_throttle_for(b.build_drone_core().powertrain.battery), a.get("motor", "default"), a.get("prop", "default"), a.get("battery", "default")])
	if a.has("info"):
		quit(0)
		return
	var fw := float(String(a.get("field", "1500x500")).split("x")[0])
	var fh := float(String(a.get("field", "1500x500")).split("x")[1])
	var poly := PackedVector2Array([Vector2(30, 0), Vector2(30 + fw, 0), Vector2(30 + fw, fh), Vector2(30, fh)])
	var cam := CameraParams.from_preset("micasense_rededge_p")
	var h := float(a.get("height", "60"))
	var fields := {"height_m": h, "front_overlap": 0.75, "side_overlap": 0.65, "reserve_pct": float(a.get("reserve", "25"))}
	fields["speed_mps"] = float(a["speed"]) if a.has("speed") else Mission.fp_survey_speed(cam, h, 0.75, 15.0)
	var params := {"class_id": "mapper", "build": b, "mission": Mission.SURVEY, "seed": int(a.get("seed", "1")), "fields": fields, "polygon": poly, "camera": cam,
		"wind_speed_mps": float(a.get("wind", "0")), "wind_from_deg": float(a.get("wind-from", "90")), "gust_mps": float(a.get("gust", "0")),
		"max_sorties": 1, "farm_acres": float(fw * fh / 4046.856)}
	var r := MissionRunner.run(params)
	var ab: Dictionary = r.get("acres_per_battery", {})
	var left := float(r["reserve_left_pct"])
	print("CAL speed=%.2f ended=%s time_min=%.1f landed_left_pct=%.1f acres_batt=%.1f (%.1f-%.1f) mapped=%.1f energy_wh=%.1f seed=%s wind=%s" % [fields["speed_mps"], r["ended_by"], r["flight_time_s"] / 60.0, left, float(ab.get("value", 0)), float(ab.get("low", 0)), float(ab.get("high", 0)), float((r.get("photos", {}) as Dictionary).get("mapped_acres", 0)), r["energy_wh"], a.get("seed", "1"), a.get("wind", "0")])
	quit(0)
