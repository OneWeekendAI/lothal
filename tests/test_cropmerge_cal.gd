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
