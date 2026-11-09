class_name Heightfield
extends RefCounted
## Real ground for the sim: a regular grid of heights over the sim's x/z plane, bilinear in between. Heights are metres ABOVE
## THE HOME POINT (sim y = 0 is where the drone stands at take-off), quantised to 1 cm so that a saved world re-saves byte
## for byte. Built from a GeoTIFF raster (USGS 3DEP) by `from_raster`, or by hand for tests.

const QUANT := 100.0           ## 1 cm

var x0 := 0.0                  ## sim x of column 0
var z0 := 0.0                  ## sim z of row 0
var step := 10.0               ## metres between nodes, both axes
var cols := 0
var rows := 0
var h := PackedFloat32Array()  ## row-major, row = z


static func quantise(v: float) -> float:
	var q := roundf(v * QUANT) / QUANT
	return 0.0 if q == 0.0 else q       # no negative zero: it would break == on the packed array after a save/load


static func make(p_x0: float, p_z0: float, p_step: float, p_cols: int, p_rows: int, heights: PackedFloat32Array) -> Heightfield:
	var out := Heightfield.new()
	out.x0 = p_x0
	out.z0 = p_z0
	out.step = p_step
	out.cols = p_cols
	out.rows = p_rows
	out.h = PackedFloat32Array()
	out.h.resize(p_cols * p_rows)
	for i in mini(heights.size(), out.h.size()):
		out.h[i] = quantise(heights[i])
	return out


func is_valid() -> bool:
	return cols >= 2 and rows >= 2 and h.size() == cols * rows and step > 0.0


func width_m() -> float:
	return float(cols - 1) * step


func length_m() -> float:
	return float(rows - 1) * step


func center() -> Vector2:
	return Vector2(x0 + width_m() * 0.5, z0 + length_m() * 0.5)


func height_at(x: float, z: float) -> float:
	if not is_valid():
		return 0.0
	var fx := clampf((x - x0) / step, 0.0, float(cols - 1))
	var fz := clampf((z - z0) / step, 0.0, float(rows - 1))
	var c0 := mini(int(floor(fx)), cols - 2)
	var r0 := mini(int(floor(fz)), rows - 2)
	var tx := fx - float(c0)
	var tz := fz - float(r0)
	var a := h[r0 * cols + c0]
	var b := h[r0 * cols + c0 + 1]
	var c := h[(r0 + 1) * cols + c0]
	var d := h[(r0 + 1) * cols + c0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func min_max() -> Vector2:
	var lo := INF
	var hi := -INF
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(lo, hi)


## Samples `raster` at every node of the grid (sim frame about the home lat/lon) and subtracts the raster height at home.
## Returns {ok, error, field, home_elevation_m, missing} - `missing` counts nodes outside the raster or on nodata (they take
## the home height so the ground stays continuous, and the count is reported rather than hidden).
static func from_raster(raster: GeoTiff.Raster, home_lat: float, home_lon: float, half_w_m: float, half_l_m: float, p_step: float,
		centre := Vector2.ZERO) -> Dictionary:
	var home := raster.sample(home_lat, home_lon)
	if is_nan(home):
		return {"ok": false, "error": "the elevation tile does not cover the home point", "field": null, "home_elevation_m": NAN, "missing": 0}
	var n_c := maxi(2, int(ceil(2.0 * half_w_m / p_step)) + 1)
	var n_r := maxi(2, int(ceil(2.0 * half_l_m / p_step)) + 1)
	var vals := PackedFloat32Array()
	vals.resize(n_c * n_r)
	var gx0 := centre.x - half_w_m
	var gz0 := centre.y - half_l_m
	var missing := 0
	for r in n_r:
		for c in n_c:
			var ll := Geodesy.sim_to_latlon(gx0 + c * p_step, gz0 + r * p_step, home_lat, home_lon)
			var e := raster.sample(ll[0], ll[1])
			if is_nan(e):
				missing += 1
				e = home
			vals[r * n_c + c] = e - home
	return {"ok": true, "error": "", "field": Heightfield.make(gx0, gz0, p_step, n_c, n_r, vals), "home_elevation_m": home, "missing": missing}


func to_data() -> Dictionary:
	var ints: Array = []
	ints.resize(h.size())
	for i in h.size():
		ints[i] = int(roundf(h[i] * QUANT))
	return {"x0": x0, "z0": z0, "step_m": step, "cols": cols, "rows": rows, "heights_cm": ints}


static func from_data(data: Variant) -> Heightfield:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	var out := Heightfield.new()
	out.x0 = float(d.get("x0", 0.0))
	out.z0 = float(d.get("z0", 0.0))
	out.step = float(d.get("step_m", 10.0))
	out.cols = int(d.get("cols", 0))
	out.rows = int(d.get("rows", 0))
	var ints: Variant = d.get("heights_cm", [])
	out.h.resize(out.cols * out.rows)
	if ints is Array and (ints as Array).size() == out.h.size():
		for i in out.h.size():
			out.h[i] = float(ints[i]) / QUANT
	else:
		out.cols = 0
		out.rows = 0
		out.h = PackedFloat32Array()
	return out


func fingerprint_term() -> String:
	return "hf|%d|%d|%.2f|%.2f|%.2f|%d" % [cols, rows, step, x0, z0, hash(h)]
