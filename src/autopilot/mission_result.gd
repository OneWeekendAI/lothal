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
const MODEL_VERSION := "sr4-1"
const FLOAT_DECIMALS := 6.0


static func figure(value: float, unit: String, tag: String = "estimated") -> Dictionary:
	return {"value": value, "low": value, "high": value, "tag": tag, "unit": unit, "range": "pending SR8"}


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
	r["figures"] = f


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
