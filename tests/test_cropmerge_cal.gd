class_name TestCropmergeCal
extends RefCounted
## CropMerge calibration cases (2026-11-11). One TestResult per case.
## FAIL-PROOFS (observed): CM1 the in-flight-empty sortie report removed from MissionRunner: the empty-pack case FAILS (acres per battery 0).
## CM3 the horizontal-speed filter removed from MissionRunner._motion_j_per_m: the high-climb case FAILS (no_progress at the first line).
## CM2 Sensitivity.CAMERA_FOR emptied: the two camera cases FAIL (preset generic_1inch).


static func run() -> Array:
	var out: Array = []
	out.append(_empty_pack_has_a_report())
	out.append(_high_climb_not_priced_as_cruise())
	out.append(_cam_mavic())
	out.append(_cam_mapper())
	out.append(_cam_other_stays_generic())
	out.append(_mapper_gust_flight(2))
	out.append(_mapper_gust_flight(3))
	return out


static func _field(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(30, 0), Vector2(30 + w, 0), Vector2(30 + w, h), Vector2(30, h)])


## A survey with reserve 0 on a field too big for the pack runs flat in the air; the pack drawn is then 100 percent, not 0, so acres per battery is real.
static func _empty_pack_has_a_report() -> TestResult:
	var r := MissionRunner.run({"class_id": "five_inch", "mission": Mission.SURVEY, "seed": 1, "capacity_scale": 0.3, "fields": {"reserve_pct": 0.0},
		"polygon": _field(400, 300), "max_sorties": 1})
	var ab: Dictionary = r["acres_per_battery"]
	return TestResult.new("cropmerge cal: a pack that runs flat in the air counts as a full pack drawn, so acres per battery is above 0",
		String(r["ended_by"]) == "battery_empty_in_flight" and float(ab["value"]) > 0.0 and absf(float(ab["pack_fraction_drawn"]) - 1.0) < 0.02,
		"ended %s, value %.2f, drawn %.3f" % [r["ended_by"], ab["value"], ab["pack_fraction_drawn"]])


static func _preset(cls: String) -> String:
	var row: Dictionary = Sensitivity.cropmerge_example(cls, _field(60, 40), 100.0, 1, 1).get("row", {})
	return String(row.get("trail", {}).get("camera_preset", "?"))


static func _cam_mavic() -> TestResult:
	var id := _preset("mavic_3m")
	return TestResult.new("cropmerge cal: the mavic_3m example flies the Mavic 3M multispectral camera, not the generic 1 inch", id == "mavic_3m_multispectral", "preset " + id)


static func _cam_mapper() -> TestResult:
	var id := _preset("mapper")
	return TestResult.new("cropmerge cal: the mapper example flies the RedEdge-P camera preset (estimated)", id == "micasense_rededge_p", "preset " + id)


static func _cam_other_stays_generic() -> TestResult:
	var id := _preset("five_inch")
	return TestResult.new("cropmerge cal: a class with no listed camera keeps the generic camera and says so", id == "generic_1inch", "preset " + id)


## A 120 m climb (48 s at 2.5 m/s) fills the 20 s power window with climbing samples. Counting those as "moving" priced the way home at climb
## power per metre of CLIMB (about 6x the cruise cost), so a pack that easily flies the first line refused it ("no_progress", 0 acres).
static func _high_climb_not_priced_as_cruise() -> TestResult:
	var r := MissionRunner.run({"class_id": "five_inch", "mission": Mission.SURVEY, "seed": 1, "capacity_scale": 0.6, "fields": {"height_m": 120.0, "speed_mps": 12.0},
		"polygon": _field(500, 200), "max_sorties": 1})
	return TestResult.new("cropmerge cal: a 120 m climb is not priced as cruise: the first survey line is flown (not no_progress) and covers more than 30 percent",
		String(r["ended_by"]) != "no_progress" and float(r["coverage_fraction"]) > 0.3,
		"ended %s, coverage %.2f, flight %.0f s" % [r["ended_by"], r["coverage_fraction"], r["flight_time_s"]])


## DIAGNOSED 2026-11-11: the mapper flipped at 20 mph with gusts (seeds 2 and 3). At a line end the velocity loop commanded the full
## 25 degree tilt back to reverse, into a 17 m/s relative wind: the disc then sees axial inflow, the thrust ratio falls to about 0.65,
## the four rotors pin at the rpm ceiling and the attitude loop has no differential left. The nav had no idea of its thrust margin.
## Also fixed first: BemtRatios::read returned the static 1.0 for ANY negative axial velocity, a 45 percent thrust step as the body axial velocity crossed zero in fast flight (test_bemt_ratios).
## Fix: NavPilot fades the tilt limit to zero as the commanded collective rises from THR_SOFT to THR_HARD.
## FAIL-PROOF (observed): with the cap removed both flights end lost_control (tilt above 75 deg at t = 854 s and 700 s).
static func _mapper_gust_flight(seed_value: int) -> TestResult:
	var r := MissionRunner.run({"class_id": "mapper", "mission": Mission.SURVEY, "seed": seed_value, "camera": CameraParams.from_preset("micasense_rededge_p"),
		"fields": {"height_m": 60.0, "front_overlap": 0.75, "side_overlap": 0.65, "reserve_pct": 25.0, "speed_mps": 9.75},
		"polygon": _field(1500, 500), "wind_speed_mps": 8.94, "wind_from_deg": 90.0, "gust_mps": 1.79, "max_sorties": 1})
	return TestResult.new("cropmerge cal: the mapper at 60 m in 20 mph with gusts (seed %d) does not lose control" % seed_value,
		String(r["ended_by"]) != "lost_control" and float(r["flight_time_s"]) > 600.0,
		"ended %s after %.1f min" % [r["ended_by"], float(r["flight_time_s"]) / 60.0])

