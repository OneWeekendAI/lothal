class_name Sensitivity
extends RefCounted
## SR8.3: which uncertain input moves a number the most. One at a time: every tolerance is flown at its -1 and +1 corner (everything else at
## nominal) and the spread of the metric between the two corners is that input's effect; the input with the largest spread is DOMINANT.
## wind_seeds has no corners: its effect is the spread over the first `count` seeds. A zero tolerance is listed with spread 0 and not flown.
## share = the input's spread / the sum of the spreads (the shares add to 1 when anything moves). One at a time ignores interactions, which is
## why Monte Carlo (MonteCarlo) gives the joint range and this gives the reading order. Tag estimated: it is only as good as the tolerances.
##
## cropmerge_example: the owner's worked example: pack capacity +-5 percent, wind 10-20 mph (15 mph +- 5), every other tolerance off, on a
## survey mission, metric acres per battery. The class is whatever the caller passes; the intended one is "mapper" (L4: estimated parts, a real class). Any other class is a STAND-IN and the
## label says so. Batteries per farm = farm acres / acres per battery, range inverted.

const MPH := 0.44704
const WIND_MIN_MPH := 10.0
const WIND_MAX_MPH := 20.0
## L5: the vendor's claim for the Mavic 3M, kept beside the simulated range as context only. Optimistic by nature (a datasheet-style claim, no stated field, wind or reserve).
const PUBLISHED_ACRES_PER_BATTERY_LOW := 100.0
const PUBLISHED_ACRES_PER_BATTERY_HIGH := 125.0
## CropMerge calibration: the survey camera a class carries. The runner's own default is the generic 1 inch camera, which is NOT what the
## Mavic 3M or a RedEdge mapper carries (generic footprint 1.5 h x 1.0 h, 3M multispectral 1.18 h x 0.89 h), so an example flown with the default
## camera mis-sized swath, line count and camera-interval speed cap. Classes not listed keep the generic camera.
const CAMERA_FOR := {"mavic_3m": "mavic_3m_multispectral", "mapper": "micasense_rededge_p"}
const AREA_BASIS := "photo-mapped track: acres covered by photos the flown track actually took (CoverageMap/SurveyPhotos), not field area and not line length x swath"


static func one_at_a_time(base: Dictionary, tol: Tolerances, metric: String) -> Dictionary:
	var nominal := MonteCarlo.value_at(MissionRunner.run(base), metric)
	var entries: Array = []
	for name in Tolerances.NAMES:
		var half := tol.half_width(name)
		var e := {"input": name, "half_width": half, "unit": tol.fields[name]["unit"], "flights": 0, "low_value": nominal, "high_value": nominal, "spread": 0.0}
		if name == "wind_seeds":
			if int(half) >= 2:
				var vals: Array[float] = []
				for k in int(half):
					vals.append(MonteCarlo.value_at(MissionRunner.run(MonteCarlo.params_for(base, tol, {"wind_seeds": float(k)})), metric))
				e["flights"] = vals.size()
				e["low_value"] = vals.min()
				e["high_value"] = vals.max()
		elif half > 0.0:
			e["low_value"] = MonteCarlo.value_at(MissionRunner.run(MonteCarlo.params_for(base, tol, {name: -1.0})), metric)
			e["high_value"] = MonteCarlo.value_at(MissionRunner.run(MonteCarlo.params_for(base, tol, {name: 1.0})), metric)
			e["flights"] = 2
		e["spread"] = absf(float(e["high_value"]) - float(e["low_value"]))
		entries.append(e)
	var total := 0.0
	for e in entries:
		total += float(e["spread"])
	for e in entries:
		e["share"] = float(e["spread"]) / total if total > 0.0 else 0.0
		e["spread_pct_of_nominal"] = float(e["spread"]) / absf(nominal) * 100.0 if nominal != 0.0 else NAN
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["spread"]) > float(b["spread"]))
	return {"metric": metric, "nominal": nominal, "entries": entries, "dominant": String(entries[0]["input"]) if total > 0.0 else "", "total_spread": total,
		"tag": "estimated", "method": "one at a time: each tolerance at its -1 and +1 corner, the others at nominal; wind_seeds over its first `count` seeds"}


## The CropMerge worked example. `field` is the polygon flown (a small stand-in field keeps the run short); farm_acres the farm the batteries are for.
static func cropmerge_example(class_id: String, field: PackedVector2Array, farm_acres: float, n: int, master_seed: int, run_seed: int = 1, camera_id: String = "") -> Dictionary:
	var mean_mps := 0.5 * (WIND_MIN_MPH + WIND_MAX_MPH) * MPH
	var span_mps := 0.5 * (WIND_MAX_MPH - WIND_MIN_MPH) * MPH
	var tol := Tolerances.defaults().zeroed().with_half("capacity_pct", 5.0).with_half("wind_speed_mps", span_mps)
	var base := {"class_id": class_id, "mission": Mission.SURVEY, "seed": run_seed, "capacity_scale": 1.0, "polygon": field,
		"wind_speed_mps": mean_mps, "wind_from_deg": 90.0, "gust_mps": 0.2 * mean_mps, "farm_acres": farm_acres}
	var cam_id := camera_id if camera_id != "" else String(CAMERA_FOR.get(class_id, ""))
	if cam_id != "":
		var cam := CameraParams.from_preset(cam_id)
		if cam != null:
			base["camera"] = cam
	var mc := MonteCarlo.run(base, tol, n, master_seed, "acres_per_battery.value")
	var dom := one_at_a_time(base, tol, "acres_per_battery.value")
	var batteries := {"value": farm_acres / float(mc["mid"]), "low": farm_acres / float(mc["high"]), "high": farm_acres / float(mc["low"]), "tag": "estimated",
		"unit": "batteries", "farm_acres": farm_acres}
	var nom := MissionRunner.run(base)
	var ab: Dictionary = nom.get("acres_per_battery", {})
	var photos: Dictionary = nom.get("photos", {})
	var nominal := {"mapped_acres": float(photos.get("mapped_acres", 0.0)), "batteries_used": float(ab.get("batteries_used", 0.0)), "flight_time_s": float(nom.get("flight_time_s", 0.0)),
		"completed": bool(nom.get("completed", false)), "ended_by": String(nom.get("ended_by", "")), "sorties": int(nom.get("sorties", 0)),
		"extrapolated": bool(ab.get("extrapolated", false))}
	var row := {"class_id": class_id,
		"acres_per_battery": {"low": float(mc["low"]), "mid": float(mc["mid"]), "high": float(mc["high"]), "tag": "estimated", "unit": "acres/battery", "n": n, "range": String(mc["range"])},
		"published": {"low": PUBLISHED_ACRES_PER_BATTERY_LOW, "high": PUBLISHED_ACRES_PER_BATTERY_HIGH, "tag": "published", "unit": "acres/battery",
			"note": "vendor claim for the Mavic 3M; optimistic, context only, not a result of this simulator"},
		"area": {"mapped_acres": nominal["mapped_acres"], "tag": "estimated", "basis": AREA_BASIS},
		"batteries_used": {"value": nominal["batteries_used"], "tag": "estimated"},
		"flight_time": {"value_s": nominal["flight_time_s"], "tag": "estimated"},
		"trail": {"build_fingerprint": String(nom.get("build_fingerprint", "")), "seed": run_seed, "master_seed": master_seed,
			"model_version": String(nom.get("versions", {}).get("model", "")), "mission": Mission.SURVEY,
			"camera_preset": (base["camera"] as CameraParams).preset_id if base.has("camera") else "generic_1inch"}}
	var cls := "Class 'mapper' is built from ESTIMATED parts (not a sourced aircraft)" if class_id == "mapper" else "Class '%s' is a STAND-IN for the mapper class" % class_id
	return {"label": "CropMerge worked example: capacity +-5 percent, wind 10-20 mph (15 +- 5). %s; a field smaller than the farm is flown, so acres per battery is EXTRAPOLATED from a part pack" % cls,
		"class_id": class_id, "wind_mph": [WIND_MIN_MPH, WIND_MAX_MPH], "capacity_pct": 5.0, "acres_per_battery": mc, "batteries_per_farm": batteries, "dominant": dom,
		"nominal": nominal, "row": row}
