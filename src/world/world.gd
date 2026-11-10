class_name World
extends RefCounted
## SR3: one saved, shareable asset that says where and when a flight happens. Versioned JSON (`FORMAT`, `VERSION`).
##
##   origin       the HOME point: sim (0,0), the take-off spot. lat/lon (WGS84) and its elevation above sea level.
##   polygon      the field boundary as lat/lon vertices (the survey area). Geodesic area comes from `Geodesy`.
##   terrain      a `Terrain`: a procedural shape, or real ground (`Heightfield`, heights above home) imported from USGS 3DEP.
##   obstacles    simple boxes / poles / walls (`Obstacle`), sim metres.
##   surface      name + roughness length z0 (m) - what the wind log-law sees.
##   wind         speed at the reference height (10 m), reference height, direction it blows FROM, turbulence (Dryden sigma_u) and tau.
##   air          temperature, relative humidity, optional station pressure (hPa; blank = standard atmosphere at the elevation).
##   time         a UTC stamp; with the origin it gives the sun's elevation (SunPosition).
##   sources      for every field above: {tag: measured|published|estimated, note}. A field with no source is reported by
##                `missing_sources()`; the presets must have none.
##   legacy       a migrated sites.json / conditions.json record, kept verbatim so nothing is lost.
## Unknown top-level keys are preserved on save.

const FORMAT := "lothal.world"
const VERSION := 1
const TAGS: Array[String] = ["measured", "published", "estimated"]
## Every field a world must carry a source for.
const SOURCE_KEYS: Array[String] = ["origin", "field.polygon", "terrain", "surface.z0", "wind.speed", "wind.from", "wind.gust",
	"air.temperature", "air.humidity", "air.pressure", "time"]

var world_id := "world"
var world_name := "World"
var description := ""
var origin_lat := 40.0
## True when lat/lon is NOT a real place (a migrated old Site / weather set has none). Written to the file only
## when true, so every real-location world serialises exactly as before.
var location_placeholder := false
var origin_lon := -88.0
var origin_elevation_m := 0.0
var polygon := PackedFloat64Array()                ## flat lat0, lon0, lat1, lon1, ... (degrees, 64-bit; Vector2 is only 32-bit)
var terrain: Terrain = Terrain.flat(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)
var obstacles: Array[Obstacle] = []
var surface_name := "short grass"
var z0_m := 0.03
var wind_speed_mps := 0.0                           ## at wind_ref_height_m
var wind_ref_height_m := 10.0
var wind_from_deg := 0.0
var gustiness_mps := 0.0
var gust_tau_s := Conditions.DEFAULT_GUST_TAU_S
var temperature_c := 15.0
var humidity_pct := 0.0
var pressure_hpa := 0.0                             ## 0 = standard atmosphere at the elevation
var utc := "2026-07-15T18:00:00Z"
var sources: Dictionary = {}
var legacy: Dictionary = {}
var _unknown: Dictionary = {}


## Source tag of the location (measured / published / estimated); "" when unlabelled.
func location_tag() -> String:
	var s: Variant = sources.get("origin")
	return String((s as Dictionary).get("tag", "")) if s is Dictionary else ""


## Warnings the world itself raises, carried into every mission result that flies it.
func world_warnings() -> Array[String]:
	var out: Array[String] = []
	if location_placeholder:
		out.append("placeholder location: this world has no real latitude/longitude (migrated from the old Field room), so sun position and date-dependent figures use a stand-in place (tag %s)" % location_tag())
	return out


func set_source(key: String, tag: String, note: String) -> void:
	sources[key] = {"tag": tag, "note": note}


## Source keys with no valid tag.
func missing_sources() -> Array[String]:
	var out: Array[String] = []
	for k in SOURCE_KEYS:
		var s: Variant = sources.get(k)
		if not (s is Dictionary) or not (String((s as Dictionary).get("tag", "")) in TAGS) or String((s as Dictionary).get("note", "")) == "":
			out.append(k)
	return out


# ---- geography
func polygon_sim() -> PackedVector2Array:
	return Geodesy.polygon_to_sim(polygon, origin_lat, origin_lon)


func area_m2() -> float:
	return Geodesy.polygon_area_m2(polygon)


func area_acres() -> float:
	return Geodesy.m2_to_acres(area_m2())


func area_hectares() -> float:
	return Geodesy.m2_to_hectares(area_m2())


## Sun elevation / azimuth at the origin at the world's time (empty-of-meaning -1 stamp returns elevation NAN).
func sun() -> Dictionary:
	var t := SunPosition.parse_utc(utc)
	if t < 0.0:
		return {"elevation_deg": NAN, "azimuth_deg": NAN}
	return SunPosition.at(origin_lat, origin_lon, t)


# ---- the existing sim types
## Ground height above the home point at (x, z), zero at the home itself.
func ground_fn() -> Callable:
	var t := terrain
	var h0 := t.height_at(0.0, 0.0)
	return func(x: float, z: float) -> float: return t.height_at(x, z) - h0


func to_site() -> Site:
	var s := Site.new()
	s.site_id = "world_%s" % world_id
	s.site_name = world_name
	s.elevation_m = origin_elevation_m
	s.terrain = terrain
	s.obstacles = obstacles
	return s


func to_conditions() -> Conditions:
	var c := Conditions.new()
	c.conditions_id = "world_%s" % world_id
	c.conditions_name = world_name
	c.wind_speed_mps = wind_speed_mps
	c.wind_from_deg = wind_from_deg
	c.gustiness_mps = gustiness_mps
	c.gust_tau_s = gust_tau_s
	c.temperature_c = temperature_c
	c.humidity_pct = humidity_pct
	c.roughness_z0_m = z0_m
	c.wind_ref_height_m = wind_ref_height_m
	return c


func to_air() -> AirDensity:
	var a := AirDensity.new(origin_elevation_m, temperature_c, humidity_pct)
	if pressure_hpa > 0.0:
		a.pressure_override_pa = pressure_hpa * 100.0
	return a


# ---- serialisation
func to_data() -> Dictionary:
	var rec := _unknown.duplicate(true)
	rec["format"] = FORMAT
	rec["version"] = VERSION
	rec["id"] = world_id
	rec["name"] = world_name
	rec["description"] = description
	rec["origin"] = {"lat": origin_lat, "lon": origin_lon, "elevation_m": origin_elevation_m}
	if location_placeholder:
		rec["origin"]["placeholder"] = true
	var poly: Array = []
	for i in floori(polygon.size() * 0.5):
		poly.append([polygon[2 * i], polygon[2 * i + 1]])
	rec["field"] = {"polygon": poly}
	var tb := terrain.to_data()
	if terrain.heightfield != null:
		tb["heightfield"] = terrain.heightfield.to_data()
	rec["terrain"] = tb
	var obs: Array = []
	for o in obstacles:
		obs.append(o.to_data())
	rec["obstacles"] = obs
	rec["surface"] = {"name": surface_name, "z0_m": z0_m}
	rec["wind"] = {"speed_mps": wind_speed_mps, "ref_height_m": wind_ref_height_m, "from_deg": wind_from_deg,
		"gustiness_mps": gustiness_mps, "gust_tau_s": gust_tau_s}
	rec["air"] = {"temperature_c": temperature_c, "humidity_pct": humidity_pct, "pressure_hpa": pressure_hpa}
	rec["time"] = {"utc": utc}
	rec["sources"] = sources.duplicate(true)
	if not legacy.is_empty():
		rec["legacy"] = legacy.duplicate(true)
	return rec


const KNOWN_KEYS := ["format", "version", "id", "name", "description", "origin", "field", "terrain", "obstacles", "surface",
	"wind", "air", "time", "sources", "legacy"]


static func from_data(data: Variant) -> World:
	var w := World.new()
	if not (data is Dictionary):
		return w
	var d: Dictionary = data
	w.world_id = String(d.get("id", w.world_id))
	w.world_name = String(d.get("name", w.world_id))
	w.description = String(d.get("description", ""))
	var o: Dictionary = d.get("origin", {}) if d.get("origin") is Dictionary else {}
	w.origin_lat = float(o.get("lat", w.origin_lat))
	w.origin_lon = float(o.get("lon", w.origin_lon))
	w.origin_elevation_m = float(o.get("elevation_m", 0.0))
	w.location_placeholder = bool(o.get("placeholder", false))
	var f: Dictionary = d.get("field", {}) if d.get("field") is Dictionary else {}
	var pts: Variant = f.get("polygon", [])
	if pts is Array:
		for p in (pts as Array):
			if p is Array and (p as Array).size() >= 2:
				w.polygon.append(float(p[0]))
				w.polygon.append(float(p[1]))
	if d.get("terrain") is Dictionary:
		var tb: Dictionary = (d["terrain"] as Dictionary).duplicate(true)
		var hf: Variant = tb.get("heightfield")
		tb.erase("heightfield")
		w.terrain = Terrain.from_data(tb)
		if hf is Dictionary:
			var field := Heightfield.from_data(hf)
			if field != null and field.is_valid():
				w.terrain.heightfield = field
	var obs: Variant = d.get("obstacles", [])
	if obs is Array:
		for e in (obs as Array):
			var ob := Obstacle.from_data(e, null)
			if ob != null:
				w.obstacles.append(ob)
	var s: Dictionary = d.get("surface", {}) if d.get("surface") is Dictionary else {}
	w.surface_name = String(s.get("name", w.surface_name))
	w.z0_m = float(s.get("z0_m", w.z0_m))
	var wi: Dictionary = d.get("wind", {}) if d.get("wind") is Dictionary else {}
	w.wind_speed_mps = float(wi.get("speed_mps", 0.0))
	w.wind_ref_height_m = float(wi.get("ref_height_m", 10.0))
	w.wind_from_deg = float(wi.get("from_deg", 0.0))
	w.gustiness_mps = float(wi.get("gustiness_mps", 0.0))
	w.gust_tau_s = float(wi.get("gust_tau_s", Conditions.DEFAULT_GUST_TAU_S))
	var a: Dictionary = d.get("air", {}) if d.get("air") is Dictionary else {}
	w.temperature_c = float(a.get("temperature_c", 15.0))
	w.humidity_pct = float(a.get("humidity_pct", 0.0))
	w.pressure_hpa = float(a.get("pressure_hpa", 0.0))
	var t: Dictionary = d.get("time", {}) if d.get("time") is Dictionary else {}
	w.utc = String(t.get("utc", w.utc))
	if d.get("sources") is Dictionary:
		w.sources = (d["sources"] as Dictionary).duplicate(true)
	if d.get("legacy") is Dictionary:
		w.legacy = (d["legacy"] as Dictionary).duplicate(true)
	w._unknown = JsonStore.unknown_fields(d, KNOWN_KEYS)
	return w


## Canonical text: keys sorted, so the same world is the same bytes on any machine.
func to_json() -> String:
	return JSON.stringify(to_data(), "\t", true)


func save(path: String) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	f.close()
	return true


static func load_from(path: String) -> World:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or String((parsed as Dictionary).get("format", "")) != FORMAT:
		return null
	if int((parsed as Dictionary).get("version", 0)) > VERSION:
		push_warning("%s: world version %d is newer than this build (%d); opening what is recognised" % [path, int((parsed as Dictionary)["version"]), VERSION])
	return from_data(parsed)


## Short stable fingerprint of everything that decides a flight: the input trail for a result.
func fingerprint() -> String:
	return str(hash(to_json()))
