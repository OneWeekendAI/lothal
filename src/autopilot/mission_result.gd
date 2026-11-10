class_name MissionResult
extends RefCounted
## SR4 mission result: the dictionary schema (schema_version 1) and its JSON text. Open for SR7, which extends
## it: add keys, never rename. Keys starting with '_' (the raw track) are NOT written to JSON.
##
## figures: each {value, low, high, tag, unit, range}. low = high = value for now; 'range' says why
## ('pending SR8': the uncertainty phase turns the point into a range). tag 'estimated': a sim prediction with
## no validation behind it (the SR0 published bands are optimistic context, not a calibration).
##
## to_json: sorted keys, floats snapped to 6 decimals (so the text compares byte for byte), NaN / INF -> null.

const SCHEMA_VERSION := 1
const MODEL_VERSION := "sr5-1"
const FLOAT_DECIMALS := 6.0


static func figure(value: float, unit: String, tag: String = "estimated") -> Dictionary:
	return {"value": value, "low": value, "high": value, "tag": tag, "unit": unit, "range": "pending SR8"}


## A figure whose low / high are a real spread (not a pending SR8 range).
static func range_figure(value: float, low: float, high: float, unit: String, tag: String, why: String) -> Dictionary:
	return {"value": value, "low": low, "high": high, "tag": tag, "unit": unit, "range": why}


static func param(value: float, default: Dictionary, edited: bool) -> Dictionary:
	return {"value": value, "default": float(default["value"]), "edited": edited,
		"tag": "user" if edited else String(default["tag"]), "default_tag": String(default["tag"]), "note": String(default.get("note", ""))}


## Adds the standard `figures` block from the scalar fields already on `r`.
static func add_figures(r: Dictionary) -> void:
	var f := {}
	var units := {"flight_time_s": "s", "distance_m": "m", "area_flown_m2": "m2", "polygon_area_m2": "m2",
		"polygon_area_geodesic_m2": "m2", "coverage_fraction": "fraction", "energy_wh": "Wh", "wh_per_min": "Wh/min", "reserve_left_pct": "%",
		"home_error_m": "m", "max_distance_from_home_m": "m"}
	if r.has("distance_out_m"):
		units["distance_out_m"] = "m"
	for k in units:
		if r.has(k):
			f[k] = figure(float(r[k]), units[k])
	if r.has("photos") and int((r["photos"] as Dictionary).get("images", 0)) > 0:
		var ph: Dictionary = r["photos"]
		var g: Dictionary = ph["gsd_cm"]
		f["gsd_cm"] = range_figure(float(g["mean"]), float(g["min"]), float(g["max"]), "cm/px", String(g["tag"]), "min / max over the photos flown")
		f["mapped_m2"] = figure(float(ph["mapped_m2"]), "m2")
		f["blur_px"] = range_figure(float(ph["blur"]["mean_px"]), 0.0, float(ph["blur"]["max_px"]), "px", "estimated", "mean / worst photo")
	r["figures"] = f


## SR5.5. How much one battery maps, from the photo-mapped area (precision rule P1: never field / swath).
##   batteries used = sum over sorties of (pack fraction drawn) / (1 - reserve/100): one "battery" is the usable part of a pack under the
##   reserve convention. The range is that convention: value at the stated reserve, low at stated + 10 points, high at 0 percent (fly to empty).
##   `extrapolated` is true when the run drew less than one usable battery, so the figure scales a partial pack linearly (take-off and
##   return overhead do not scale; this over-states). Tolerances (capacity, wind) are still pending SR8 and are NOT in this range.
## batteries_per_farm = farm acres / acres_per_battery (farm_acres param, default this field), range inverted.
## cross_check_swath: what a field / swath formula would claim for the same plan (planned line length x line spacing). A cross-check
## only, labelled as such: it never feeds a headline figure.
const RESERVE_RANGE_PTS := 10.0


static func add_survey_economics(r: Dictionary, plan: Dictionary, farm_acres: float) -> void:
	var ph: Dictionary = r.get("photos", {})
	var acres := float(ph.get("mapped_acres", 0.0))
	var reserve := 0.0
	if r.get("params", {}).get("fields", {}).has("reserve_pct"):
		reserve = float(r["params"]["fields"]["reserve_pct"]["value"])
	var drawn := 0.0
	for s in r.get("sortie_reports", []):
		drawn += float(s["pack_used_pct"]) / 100.0
	var why := "landing-reserve convention: low = stated reserve + %.0f points, high = 0 percent; capacity and wind tolerances pending SR8" % RESERVE_RANGE_PTS
	var ab := _per_battery(acres, drawn, reserve, why)
	r["acres_per_battery"] = ab
	var farm := farm_acres if farm_acres > 0.0 else Geodesy.m2_to_acres(float(r.get("polygon_area_m2", 0.0)))
	var v := farm / float(ab["value"]) if float(ab["value"]) > 0.0 else NAN
	var lo := farm / float(ab["high"]) if float(ab["high"]) > 0.0 else NAN
	var hi := farm / float(ab["low"]) if float(ab["low"]) > 0.0 else NAN
	r["batteries_per_farm"] = {"value": v, "low": lo, "high": hi, "tag": "estimated", "unit": "batteries", "farm_acres": farm,
		"farm_acres_source": "farm_acres param" if farm_acres > 0.0 else "this field's polygon", "range": why,
		"whole_batteries": (int(ceil(v)) if not is_nan(v) else -1)}
	var line_len := float(plan.get("path_length_m", 0.0)) - float(plan.get("turn_length_m", 0.0))
	var swath_m2 := line_len * float(plan.get("spacing_m", 0.0))
	var swath_acres := Geodesy.m2_to_acres(swath_m2)
	var cross_ab := swath_acres / (drawn / (1.0 - reserve / 100.0)) if drawn > 0.0 and reserve < 100.0 else 0.0
	r["cross_check_swath"] = {"label": "CROSS-CHECK ONLY: what a field / swath formula claims for the planned lines; not the result", "area_m2": swath_m2,
		"acres": swath_acres, "acres_per_battery": cross_ab, "line_length_m": line_len, "line_spacing_m": float(plan.get("spacing_m", 0.0)),
		"headline_acres": acres, "differs_from_headline_pct": (swath_acres / acres - 1.0) * 100.0 if acres > 0.0 else NAN, "tag": "estimated"}


static func _per_battery(acres: float, drawn: float, reserve: float, why: String) -> Dictionary:
	var at := func(res: float) -> float:
		var usable := 1.0 - minf(res, 99.0) / 100.0
		return acres / (drawn / usable) if drawn > 0.0 else 0.0
	var usable_now := 1.0 - minf(reserve, 99.0) / 100.0
	return {"value": at.call(reserve), "low": at.call(reserve + RESERVE_RANGE_PTS), "high": at.call(0.0), "tag": "estimated", "unit": "acres/battery",
		"range": why, "batteries_used": drawn / usable_now, "pack_fraction_drawn": drawn, "reserve_pct": reserve,
		"extrapolated": drawn < usable_now, "source": "photo-mapped acres (CoverageMap) / batteries used"}


static func to_json(r: Dictionary) -> String:
	return JSON.stringify(_clean(r), "  ", true)


static func _clean(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v):
				return null
			return snappedf(v, pow(10.0, -FLOAT_DECIMALS))
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				if String(k).begins_with("_"):
					continue
				d[String(k)] = _clean(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_clean(x))
			return a
		TYPE_VECTOR2:
			return [_clean(v.x), _clean(v.y)]
		TYPE_VECTOR3:
			return [_clean(v.x), _clean(v.y), _clean(v.z)]
		TYPE_PACKED_VECTOR2_ARRAY:
			var a2 := []
			for x in v:
				a2.append(_clean(x))
			return a2
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			return null
	return v
