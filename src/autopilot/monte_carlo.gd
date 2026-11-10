class_name MonteCarlo
extends RefCounted
## SR8.2: a range for any one number a mission reports, by flying the mission many times with its uncertain inputs drawn from their
## tolerances (Tolerances). Headless, deterministic: the same (params, tolerances, n, master_seed) gives the same draws and the same range.
##
## DRAWS. A random generator seeded with `master_seed` draws, for EVERY run and in a FIXED order, one number per tolerance in
## Tolerances.NAMES (uniform in [-1, 1]; for wind_seeds a whole number 0..count-1), whether or not that tolerance is zero. So widening
## one tolerance changes only that input of every run, never the draws of the others, and the first n draws of a longer run are the draws of
## a shorter one (doubling the runs adds samples, it does not reshuffle).
## RANGE. low = 10th percentile, mid = median, high = 90th percentile of the metric over the runs (linear interpolation), plus min / max / mean.
## A percentile range, not a worst case: the stated reading is "8 draws in 10 land inside low-high". Tag estimated: the tolerances are.
## METRIC. A dotted path into the mission result: "flight_time_s", "energy_wh", "acres_per_battery.value", "photos.mapped_acres".

const LOW_P := 0.10
const HIGH_P := 0.90


static func run(base: Dictionary, tol: Tolerances, n: int, master_seed: int, metric: String = "flight_time_s") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed
	var values: Array[float] = []
	var draws: Array = []
	for i in n:
		var u := {}
		for name in Tolerances.NAMES:
			if name == "wind_seeds":
				u[name] = float(rng.randi_range(0, maxi(int(tol.half_width(name)) - 1, 0)))
			else:
				u[name] = rng.randf_range(-1.0, 1.0)
		var p := params_for(base, tol, u)
		var r := MissionRunner.run(p)
		var v := value_at(r, metric)
		values.append(v)
		draws.append({"run": i, "u": u, "capacity_scale": p["capacity_scale"], "mass_scale": p["mass_scale"], "drag_scale": p["drag_scale"],
			"esc_loss_scale": p["esc_loss_scale"], "pack_temp_c": p["pack_temp_c"], "seed": p["seed"], "wind_speed_mps": p["wind_speed_mps"], "value": v})
	return summarise(values, draws, tol, n, master_seed, metric)


## The mission params for one draw `u` (name -> number; names left out count as 0, the nominal value).
static func params_for(base: Dictionary, tol: Tolerances, u: Dictionary) -> Dictionary:
	var d := tol.draw_to_params(u)
	var p := base.duplicate(true)
	p["capacity_scale"] = float(base.get("capacity_scale", 1.0)) * float(d["capacity_factor"])
	p["mass_scale"] = d["mass_scale"]
	p["drag_scale"] = d["drag_scale"]
	p["esc_loss_scale"] = d["esc_loss_scale"]
	p["pack_temp_c"] = d["pack_temp_c"]
	p["seed"] = int(base.get("seed", 1)) + int(d["seed_offset"])
	p["wind_speed_mps"] = maxf(float(base.get("wind_speed_mps", 0.0)) + float(d["wind_delta_mps"]), 0.0)
	return p


## Dotted path into a result; NAN when it is missing.
static func value_at(r: Dictionary, path: String) -> float:
	var cur: Variant = r
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return NAN
	return float(cur) if (cur is float or cur is int) else NAN


static func summarise(values: Array[float], draws: Array, tol: Tolerances, n: int, master_seed: int, metric: String) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in values:
		mean += v
	mean /= maxf(float(n), 1.0)
	var low := percentile(sorted, LOW_P)
	var mid := percentile(sorted, 0.5)
	var high := percentile(sorted, HIGH_P)
	return {"metric": metric, "n": n, "master_seed": master_seed, "low": low, "mid": mid, "high": high, "min": sorted[0] if n > 0 else NAN,
		"max": sorted[n - 1] if n > 0 else NAN, "mean": mean, "tag": "estimated",
		"range": "10th to 90th percentile of %d draws over the tolerances (uniform), master seed %d; tolerances are ESTIMATED unless edited" % [n, master_seed],
		"tolerances": tol.fields.duplicate(true), "draws": draws}


static func percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return NAN
	var pos := p * float(sorted.size() - 1)
	var i := int(floor(pos))
	var j := mini(i + 1, sorted.size() - 1)
	return float(sorted[i]) + (float(sorted[j]) - float(sorted[i])) * (pos - float(i))


## The range as a result figure ({value, low, high, tag, unit, range}).
static func as_figure(mc: Dictionary, unit: String) -> Dictionary:
	return MissionResult.range_figure(float(mc["mid"]), float(mc["low"]), float(mc["high"]), unit, String(mc["tag"]), String(mc["range"]))
