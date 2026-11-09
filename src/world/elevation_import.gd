class_name ElevationImport
extends RefCounted
## SR3 terrain import from USGS 3DEP (The National Map). Source: 3DEPElevation ImageServer `exportImage` returning a GeoTIFF
## (float32 metres, EPSG:4326, bilinear), and the Elevation Point Query Service (EPQS) for single points.
##   https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer
##   https://epqs.nationalmap.gov/v1/json?x=<lon>&y=<lat>&wkid=4326&units=Meters
## Downloads are cached under user://elevation_cache/ keyed by the request URL, so a flight over the same field never hits the
## network twice and works offline afterwards. If the network or the tile fails, `import_world` returns ok=false and leaves the
## world's terrain as it was, with the error in the result - the caller keeps a flat or procedural ground and notes the elevation.

const SERVICE := "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage"
const EPQS := "https://epqs.nationalmap.gov/v1/json"
const CACHE_DIR := "user://elevation_cache"
const DEFAULT_STEP_M := 10.0           ## 3DEP's common 1/3 arc-second grid is about 10 m
const DEFAULT_PAD_M := 40.0
const MAX_PIXELS := 2000


## Sim-metre rectangle holding the polygon and the home point, padded.
static func sim_rect(w: World, pad_m: float) -> Rect2:
	var pts := w.polygon_sim()
	pts.append(Vector2.ZERO)
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo - Vector2(pad_m, pad_m), (hi - lo) + Vector2(2.0 * pad_m, 2.0 * pad_m))


## lat/lon bounding box {west, south, east, north} of a sim rectangle, with a margin so bilinear edges stay inside the tile.
static func latlon_bbox(w: World, rect: Rect2, margin_m: float) -> Dictionary:
	var lo_lat := INF
	var hi_lat := -INF
	var lo_lon := INF
	var hi_lon := -INF
	var m := margin_m
	for c in [rect.position + Vector2(-m, -m), rect.position + Vector2(rect.size.x + m, -m),
			rect.position + Vector2(-m, rect.size.y + m), rect.position + rect.size + Vector2(m, m)]:
		var ll := Geodesy.sim_to_latlon(c.x, c.y, w.origin_lat, w.origin_lon)
		lo_lat = minf(lo_lat, ll[0])
		hi_lat = maxf(hi_lat, ll[0])
		lo_lon = minf(lo_lon, ll[1])
		hi_lon = maxf(hi_lon, ll[1])
	return {"west": lo_lon, "south": lo_lat, "east": hi_lon, "north": hi_lat}


static func tile_url(bbox: Dictionary, cols: int, rows: int) -> String:
	return "%s?bbox=%.7f,%.7f,%.7f,%.7f&bboxSR=4326&size=%d,%d&imageSR=4326&format=tiff&pixelType=F32&noData=-9999&interpolation=RSP_BilinearInterpolation&f=image" % [
		SERVICE, bbox["west"], bbox["south"], bbox["east"], bbox["north"], cols, rows]


static func point_url(lat: float, lon: float) -> String:
	return "%s?x=%.7f&y=%.7f&wkid=4326&units=Meters&includeDate=false" % [EPQS, lon, lat]


## The elevation (m) in an EPQS JSON reply, or NAN.
static func parse_point(body: String) -> float:
	var j: Variant = JSON.parse_string(body)
	if j is Dictionary and (j as Dictionary).has("value"):
		var v := String((j as Dictionary)["value"])
		if v.is_valid_float():
			return float(v)
	return NAN


static func cache_path(url: String) -> String:
	return "%s/%s.bin" % [CACHE_DIR, url.md5_text()]


static func read_cache(url: String) -> PackedByteArray:
	var p := cache_path(url)
	return FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()


static func write_cache(url: String, bytes: PackedByteArray) -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(cache_path(url), FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


## Coroutine: `await ElevationImport.fetch(host_node, url)`. Cache first, then the network (HTTPRequest added under `host`).
static func fetch(host: Node, url: String) -> Dictionary:
	var cached := read_cache(url)
	if not cached.is_empty():
		return {"ok": true, "bytes": cached, "from_cache": true, "error": "", "url": url}
	var req := HTTPRequest.new()
	req.timeout = 30.0
	host.add_child(req)
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return {"ok": false, "bytes": PackedByteArray(), "from_cache": false, "error": "request failed to start (%d)" % err, "url": url}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {"ok": false, "bytes": PackedByteArray(), "from_cache": false, "error": "network result %d, HTTP %d" % [int(res[0]), int(res[1])], "url": url}
	var body: PackedByteArray = res[3]
	if body.size() < 8:
		return {"ok": false, "bytes": PackedByteArray(), "from_cache": false, "error": "empty reply", "url": url}
	write_cache(url, body)
	return {"ok": true, "bytes": body, "from_cache": false, "error": "", "url": url}


## Builds the world's heightfield from GeoTIFF bytes (no network). On success sets the terrain, the origin elevation and the
## terrain source tag; on failure changes nothing. `note` goes into the source note (e.g. the retrieval date).
static func apply_bytes(w: World, bytes: PackedByteArray, step_m: float, pad_m: float, note: String) -> Dictionary:
	var parsed := GeoTiff.parse(bytes)
	if not bool(parsed["ok"]):
		return {"ok": false, "error": String(parsed["error"])}
	var rect := sim_rect(w, pad_m)
	var built := Heightfield.from_raster(parsed["raster"], w.origin_lat, w.origin_lon, rect.size.x * 0.5, rect.size.y * 0.5, step_m, rect.get_center())
	if not bool(built["ok"]):
		return {"ok": false, "error": String(built["error"])}
	var hf: Heightfield = built["field"]
	var t := Terrain.flat(hf.width_m(), hf.length_m(), hf.center().x, hf.center().y)
	t.heightfield = hf
	w.terrain = t
	w.origin_elevation_m = Heightfield.quantise(float(built["home_elevation_m"]))
	w.set_source("terrain", "published", "USGS 3DEP elevation, %.0f m grid, bilinear; %s" % [step_m, note])
	return {"ok": true, "error": "", "missing_nodes": int(built["missing"]), "home_elevation_m": w.origin_elevation_m}


## Coroutine: fetch (cache or network) then apply. Failure leaves the terrain untouched and says why.
static func import_world(host: Node, w: World, step_m: float = DEFAULT_STEP_M, pad_m: float = DEFAULT_PAD_M, note: String = "") -> Dictionary:
	var rect := sim_rect(w, pad_m)
	var bbox := latlon_bbox(w, rect, 2.0 * step_m)
	var cols := clampi(int(ceil(rect.size.x / step_m)) + 6, 8, MAX_PIXELS)
	var rows := clampi(int(ceil(rect.size.y / step_m)) + 6, 8, MAX_PIXELS)
	var got: Dictionary = await fetch(host, tile_url(bbox, cols, rows))
	if not bool(got["ok"]):
		return {"ok": false, "error": String(got["error"]), "from_cache": false}
	var out := apply_bytes(w, got["bytes"], step_m, pad_m, note)
	out["from_cache"] = got["from_cache"]
	out["bytes"] = got["bytes"]
	return out
