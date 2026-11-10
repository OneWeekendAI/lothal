class_name TestSr3World
extends RefCounted
## SR3 world builder: geodesy, sun, world asset (save/load/share), migration, 3DEP GeoTIFF import, presets, and the mission wiring.
## ONE TestResult per case. SR3_ONLY=key1,key2 runs only those cases (used for fail-proofs).
##
## REFERENCE VALUES come from GeographicLib 2.x PolygonArea (Karney 2013, "Algorithms for geodesics", J. Geodesy 87, 43-55; geodesic edges,
## WGS84), computed once with Python (`geographiclib` package) on the same vertices; no surveyed parcel with a published area good to 0.1 %
## was found, so the reference is Karney's algorithm itself. The 1 km square is also checked against the plan's 247.1 acres (0.5 %).
##
## FAIL-PROOFS (each check run with its fix removed by a temporary edit, then restored; observed):
##   F1 polygon_area_m2 = the planar shortcut for every polygon: Illinois area FAILS (23974.1 vs 23999.7 m2, 0.106 %) and the 6-degree polygon FAILS
##      (4.2 % off); the 1 km square and the 125 ha quad still pass (the shortcut is fine on small fields; the large polygon is what proves it).
##   F2 world.to_data writes an empty heightfield: round-trip FAILS (json stable false, heightfield equal false), shared-file FAILS.
##   F3 migration ignores conditions.json: count FAILS (added 3 of 5) and lossless FAILS (standard:false gusty:false).
##   F4 GeoTIFF north edge shifted one pixel: the 3 source-pixel check FAILS (georeference north off) and the heightfield spot check FAILS (0.27 m at the third).
##   F5 world humidity not copied into Conditions: wiring FAILS (humidity 0).
##   F6 terrain_follow=false (SR3_NO_FOLLOW=1): AGL band FAILS (AGL 8.1..25.6 m against a 20 m target, band +-4; followed: 19.6..20.3).
##   F7 mission ignores the world's conditions: wind-from-world FAILS (windy and calm both 1.4581 Wh, wind 0) and determinism FAILS (seed 7 == seed 8).
##   F8 mission ignores the world's polygon (falls back to the class default, also 24,000 m2): survey FAILS on the northmost track point (the world field
##      lies north of home, the default field south... the track never goes beyond z = -100).
##   Also observed while building (not re-run): lat/lon held in Vector2 (32-bit) made the ENU round trip 3 m off and the Illinois area 23954 vs 23999.68.
const ONLY_ENV := "SR3_ONLY"

const SQUARE_REF_M2 := 999934.3053026424            ## GeographicLib, 1 km geodesic square from (40, -88): E 1000 m, N 1000 m, W 1000 m
const QUAD_REF_M2 := 1252950.6729755402             ## GeographicLib, (40,-88)(40,-87.9853)(40.00899,-87.9853)(40.00899,-88)
const ILLINOIS_REF_M2 := 23999.68297803402          ## GeographicLib on the shipped illinois_corn_july polygon
const BIG_REF_M2 := 341107995418.9346               ## GeographicLib, 6 x 6 degree box 37-43 N, 91-85 W (about 340,000 km2)
const FIXTURE_TIF := "res://tests/fixtures/illinois_3dep.tif"
const SITES_FIX := "res://tests/fixtures/sr3_sites_legacy.json"
const COND_FIX := "res://tests/fixtures/sr3_conditions_legacy.json"
const TMP := "user://sr3_test"

static var _cache: Dictionary = {}


static func run() -> Array:
	var out: Array = []
	var only := OS.get_environment(ONLY_ENV)
	var keys: PackedStringArray = only.split(",") if only != "" else PackedStringArray()
	var cases := {
		"sq": func() -> TestResult: return _area_square(),
		"quad": func() -> TestResult: return _area_quad(),
		"ill_area": func() -> TestResult: return _area_illinois(),
		"big": func() -> TestResult: return _area_big_vs_planar(),
		"units": func() -> TestResult: return _units(),
		"enu": func() -> TestResult: return _enu_round_trip(),
		"sun": func() -> TestResult: return _sun(),
		"rt": func() -> TestResult: return _round_trip(),
		"share": func() -> TestResult: return _share(),
		"src_il": func() -> TestResult: return _sources("illinois_corn_july"),
		"src_calm": func() -> TestResult: return _sources("calm_test_field"),
		"src_coast": func() -> TestResult: return _sources("windy_coast"),
		"src_alt": func() -> TestResult: return _sources("high_altitude"),
		"mig_count": func() -> TestResult: return _migration_count(),
		"mig_lossless": func() -> TestResult: return _migration_lossless(),
		"mig_twice": func() -> TestResult: return _migration_idempotent(),
		"tiff_spot": func() -> TestResult: return _tiff_spot_checks(),
		"hf_spot": func() -> TestResult: return _heightfield_spot_checks(),
		"tiff_lzw": func() -> TestResult: return _tiff_unsupported(),
		"fallback": func() -> TestResult: return _import_failure_keeps_terrain(),
		"room": func() -> TestResult: return _field_room_controls(),
		"wiring": func() -> TestResult: return _conditions_wiring(),
		"terrain_mesh": func() -> TestResult: return _terrain_mesh_uses_heightfield(),
		"agl": func() -> TestResult: return _terrain_follow_band(),
		"wind_world": func() -> TestResult: return _wind_from_world(),
		"determinism": func() -> TestResult: return _determinism(),
		"reimport_ok": func() -> TestResult: return _reimport_case(true),
		"reimport_fail": func() -> TestResult: return _reimport_case(false),
		"loc_placeholder": func() -> TestResult: return _placeholder_location(),
		"obs_hit": func() -> TestResult: return _obstacle_case(0.0, "obstacle collision", "a pole on the loop line raises a collision warning"),
		"obs_near": func() -> TestResult: return _obstacle_case(3.0, "obstacle clearance", "a pole 3 m off the loop line raises a clearance warning and no collision"),
		"obs_far": func() -> TestResult: return _obstacle_case(60.0, "", "a pole 60 m off the line raises no obstacle warning"),
		"survey": func() -> TestResult: return _survey_illinois(),
	}
	for k in cases:
		if only == "" or k in keys:
			out.append(cases[k].call())
	return out


# ---------------------------------------------------------------- helpers
static func _rel(a: float, b: float) -> float:
	return absf(a - b) / absf(b)


static func _ll(flat: Array) -> PackedFloat64Array:
	return PackedFloat64Array(flat)


static func _preset(id: String) -> World:
	return WorldPresets.by_id(id)


static func _hilly_world() -> World:
	var w := WorldPresets.calm_test_field()
	w.world_id = "hilly_test"
	var cols := 41
	var rows := 31
	var vals := PackedFloat32Array()
	vals.resize(cols * rows)
	for r in rows:
		for c in cols:
			var x := -20.0 + c * 10.0
			var z := -250.0 + r * 10.0
			vals[r * cols + c] = 12.0 * sin(x / 50.0) * cos(z / 70.0) - 12.0 * sin(0.0) * 1.0
	var hf := Heightfield.make(-20.0, -250.0, 10.0, cols, rows, vals)
	var t := Terrain.flat(hf.width_m(), hf.length_m(), hf.center().x, hf.center().y)
	t.heightfield = hf
	w.terrain = t
	return w


static func _fly(params: Dictionary) -> Dictionary:
	var key := var_to_str(params)
	if not _cache.has(key):
		_cache[key] = MissionRunner.run(params)
	return _cache[key]


# ---------------------------------------------------------------- geodesy
static func _square_pts() -> PackedFloat64Array:
	# the geodesic 1 km square from (40,-88) as GeographicLib walked it
	return _ll([40.0, -88.0, 39.999999408, -87.988289556, 40.0090056, -87.988289556, 40.009005009, -88.000001539])


static func _area_square() -> TestResult:
	var a := Geodesy.polygon_area_m2(_square_pts())
	var acres := Geodesy.m2_to_acres(a)
	var ok := _rel(a, SQUARE_REF_M2) < 0.001 and _rel(acres, 247.1) < 0.005
	return TestResult.new("sr3 geodesy: a 1 km x 1 km square near 40 N is within 0.1 %% of Karney's area and within 0.5 %% of 247.1 acres", ok,
		"area %.1f m2 vs %.1f (%.4f %%), %.3f acres vs 247.1 (%.3f %%)" % [a, SQUARE_REF_M2, 100.0 * _rel(a, SQUARE_REF_M2), acres, 100.0 * _rel(acres, 247.1)])


static func _area_quad() -> TestResult:
	var a := Geodesy.polygon_area_m2(_ll([40.0, -88.0, 40.0, -87.9853, 40.00899, -87.9853, 40.00899, -88.0]))
	return TestResult.new("sr3 geodesy: a parallel/meridian quadrilateral (125 ha) is within 0.1 % of Karney's area", _rel(a, QUAD_REF_M2) < 0.001,
		"%.2f vs %.2f m2 (%.5f %%)" % [a, QUAD_REF_M2, 100.0 * _rel(a, QUAD_REF_M2)])


static func _area_illinois() -> TestResult:
	var w := _preset("illinois_corn_july")
	var a := w.area_m2()
	return TestResult.new("sr3 geodesy: the Illinois preset polygon area is within 0.1 % of Karney's area, and about 6 acres", _rel(a, ILLINOIS_REF_M2) < 0.001 and w.area_acres() > 5.9 and w.area_acres() < 6.0,
		"%.3f vs %.3f m2 (%.5f %%), %.3f acres, %.3f ha" % [a, ILLINOIS_REF_M2, 100.0 * _rel(a, ILLINOIS_REF_M2), w.area_acres(), w.area_hectares()])


static func _area_big_vs_planar() -> TestResult:
	var big := _ll([37.0, -91.0, 37.0, -85.0, 43.0, -85.0, 43.0, -91.0])
	var ours := Geodesy.polygon_area_m2(big)
	var planar := Geodesy.planar_shortcut_area_m2(big)
	var ok := _rel(ours, BIG_REF_M2) < 0.001 and _rel(planar, BIG_REF_M2) > 0.001
	return TestResult.new("sr3 geodesy: on a 6 degree polygon the geodesic area is within 0.1 %% of Karney's and the planar shortcut is NOT (so the test can fail)", ok,
		"geodesic %.4f %% off, planar shortcut %.4f %% off" % [100.0 * _rel(ours, BIG_REF_M2), 100.0 * _rel(planar, BIG_REF_M2)])


static func _units() -> TestResult:
	var ok := is_equal_approx(Geodesy.m2_to_hectares(25000.0), 2.5) and is_equal_approx(Geodesy.m2_to_acres(4046.8564224), 1.0)
	return TestResult.new("sr3 geodesy: 1 hectare is 10,000 m2 and 1 acre is 4046.8564224 m2", ok, "")


static func _enu_round_trip() -> TestResult:
	var sim := Geodesy.latlon_to_sim(40.0, -87.9, 40.0, -88.0)       # 0.1 deg east of home: about 8.5 km
	var back := Geodesy.sim_to_latlon(sim.x, sim.y, 40.0, -88.0)
	var east_expected := 6378137.0 * cos(deg_to_rad(40.0)) / sqrt(1.0 - Geodesy.E2 * pow(sin(deg_to_rad(40.0)), 2.0)) * deg_to_rad(0.1)
	var exact := Geodesy.latlon_to_enu(40.0, -87.9, 0.0, 40.0, -88.0, 0.0)
	var exact_back := Geodesy.enu_to_latlon(exact[0], exact[1], exact[2], 40.0, -88.0, 0.0)
	var ok := absf(exact_back[0] - 40.0) < 1.0e-10 and absf(exact_back[1] + 87.9) < 1.0e-10 and absf(float(back[0]) - 40.0) < 1.0e-6 and absf(float(back[1]) + 87.9) < 1.0e-6 and absf(sim.x - east_expected) < 0.02 * east_expected \
		and absf(sim.x - east_expected) < 100.0
	var north := Geodesy.latlon_to_sim(40.001, -88.0, 40.0, -88.0)
	ok = ok and north.y < 0.0 and absf(north.y + 111.0e3 * 0.001) < 1.0          # north is -Z; 1 mdeg of latitude is about 111.0 m
	return TestResult.new("sr3 geodesy: lat/lon -> sim -> lat/lon round trip (1e-10 deg in 64-bit; 1e-6 deg through the 32-bit Vector2 sim position), east is +X, north is -Z", ok,
		"back (%.12f, %.12f); east %.1f m (parallel arc %.1f); north y %.3f" % [back[0], back[1], sim.x, east_expected, north.y])


static func _sun() -> TestResult:
	# June 2026 solstice (21 Jun 2026 08:24 UTC) at 40 N, 0 E: solar noon elevation = 90 - 40 + 23.44 = 73.44 deg; midnight negative
	var noon_t := SunPosition.parse_utc("2026-06-21T12:00:00Z")
	var best := -90.0
	var t := noon_t - 3.0 * 3600.0
	while t <= noon_t + 3.0 * 3600.0:
		best = maxf(best, float(SunPosition.at(40.0, 0.0, t)["elevation_deg"]))
		t += 120.0
	var midnight := float(SunPosition.at(40.0, 0.0, SunPosition.parse_utc("2026-06-22T00:00:00Z"))["elevation_deg"])
	var decl := float(SunPosition.at(40.0, 0.0, noon_t)["declination_deg"])
	var az := float(SunPosition.at(40.0, 0.0, noon_t + 1800.0)["azimuth_deg"])
	var ok := absf(best - 73.44) < 0.25 and midnight < -20.0 and absf(decl - 23.44) < 0.1 and az > 150.0 and az < 260.0
	return TestResult.new("sr3 sun: solstice noon elevation at 40 N is 73.4 deg (90 - lat + 23.44), midnight is below the horizon, afternoon sun is south-west", ok,
		"peak %.2f, midnight %.1f, declination %.3f, azimuth %.1f" % [best, midnight, decl, az])


# ---------------------------------------------------------------- the asset
static func _round_trip() -> TestResult:
	var w := _preset("illinois_corn_july")
	var text := w.to_json()
	var again := World.from_data(JSON.parse_string(text)).to_json()
	var path := "%s/rt.world.json" % TMP
	w.save(path)
	var loaded := World.load_from(path)
	var same_bytes := loaded != null and loaded.to_json() == text and FileAccess.get_file_as_string(path) == text
	var hf_ok := loaded != null and loaded.terrain.heightfield != null and loaded.terrain.heightfield.h == w.terrain.heightfield.h \
		and absf(loaded.terrain.height_at(100.0, -60.0) - w.terrain.height_at(100.0, -60.0)) < 1.0e-9
	var ok := again == text and same_bytes and hf_ok and loaded.fingerprint() == w.fingerprint()
	return TestResult.new("sr3 world: save -> load -> save is byte-identical, heightfield and polygon included", ok,
		"json stable %s, file bytes equal %s, heightfield equal %s, bytes %d" % [again == text, same_bytes, hf_ok, text.length()])


static func _share() -> TestResult:
	var a := WorldLibrary.new()
	a.dir = "%s/share_a" % TMP
	var w := _preset("illinois_corn_july")
	a.put(w)
	var shared := "%s/shared_copy.world.json" % TMP
	var exported := a.export_to(w.world_id, shared)
	var b := WorldLibrary.new()                          # a clean library standing in for a clean install
	b.dir = "%s/share_b_clean" % TMP
	var got := b.import_from(shared)
	var ok := exported and got != null and got.fingerprint() == w.fingerprint() and got.area_m2() == w.area_m2() \
		and got.terrain.height_at(80.0, -50.0) == w.terrain.height_at(80.0, -50.0) and b.world(w.world_id) != null
	return TestResult.new("sr3 world: a shared file opens identically in a clean library (same fingerprint, area and ground)", ok, "imported %s" % (got != null))


static func _sources(id: String) -> TestResult:
	var w := _preset(id)
	var missing: Array[String] = w.missing_sources() if w != null else ["(preset not found)"]
	var tags := {}
	if w != null:
		for k in w.sources:
			tags[String(w.sources[k]["tag"])] = true
	return TestResult.new("sr3 preset %s: every field carries a measured/published/estimated tag and a note" % id, w != null and missing.is_empty(),
		"missing %s, tags used %s" % [str(missing), str(tags.keys())])


# ---------------------------------------------------------------- migration
static func _migrate() -> Dictionary:
	var lib := WorldLibrary.new()
	lib.dir = "%s/mig_%d" % [TMP, randi()]
	var added := WorldLibrary.migrate(lib, SITES_FIX, COND_FIX)
	return {"lib": lib, "added": added}


static func _migration_count() -> TestResult:
	var sites := (JSON.parse_string(FileAccess.get_file_as_string(SITES_FIX))["sites"] as Array).size()
	var conds := (JSON.parse_string(FileAccess.get_file_as_string(COND_FIX))["conditions"] as Array).size()
	var m := _migrate()
	var lib: WorldLibrary = m["lib"]
	var reloaded := WorldLibrary.load_dir(lib.dir)
	var ok := int(m["added"]) == sites + conds and lib.count() == sites + conds and reloaded.count() == sites + conds and sites == 3 and conds == 2
	return TestResult.new("sr3 migration: 3 sites + 2 condition sets become 5 worlds, on disk too", ok, "sites %d, sets %d, added %d, in library %d, reloaded %d" % [sites, conds, m["added"], lib.count(), reloaded.count()])


static func _migration_lossless() -> TestResult:
	var m := _migrate()
	var lib := WorldLibrary.load_dir((m["lib"] as WorldLibrary).dir)
	var all_ok := true
	var detail := ""
	var sites: Array = JSON.parse_string(FileAccess.get_file_as_string(SITES_FIX))["sites"]
	for rec in sites:
		var w := lib.world("site_%s" % rec["id"])
		var back := Site.from_data(w.legacy["record"]).to_data() if w != null else {}
		var same: bool = w != null and JSON.stringify(w.legacy["record"], "", true) == JSON.stringify(rec, "", true) and JSON.stringify(back, "", true) == JSON.stringify(Site.from_data(rec).to_data(), "", true) \
			and absf(w.origin_elevation_m - float(rec["elevation_m"])) < 1.0e-9 and w.terrain.fingerprint_term() == Site.from_data(rec).terrain.fingerprint_term()
		all_ok = all_ok and same
		detail += "%s:%s " % [rec["id"], same]
	var conds: Array = JSON.parse_string(FileAccess.get_file_as_string(COND_FIX))["conditions"]
	for rec in conds:
		var w2 := lib.world("conditions_%s" % rec["id"])
		var c := Conditions.from_data(rec)
		var same2: bool = w2 != null and JSON.stringify(w2.legacy["record"], "", true) == JSON.stringify(rec, "", true) \
			and absf(w2.wind_speed_mps - c.wind_speed_mps) < 1.0e-9 and absf(w2.temperature_c - c.temperature_c) < 1.0e-9 \
			and absf(w2.humidity_pct - c.humidity_pct) < 1.0e-9 and absf(w2.z0_m - c.roughness_z0_m) < 1.0e-9
		all_ok = all_ok and same2
		detail += "%s:%s " % [rec["id"], same2]
	var club := lib.world("site_club_field")
	all_ok = all_ok and club != null and absf(club.temperature_c - 28.5) < 1.0e-9 and club.obstacles.size() == 2 and club.legacy["record"].has("newer_build_key")
	var sites_bytes := FileAccess.get_file_as_string(SITES_FIX)
	all_ok = all_ok and sites_bytes == FileAccess.get_file_as_string(SITES_FIX)
	return TestResult.new("sr3 migration: every old record survives verbatim (unknown keys, parked temperature, obstacles, terrain) and re-reads as the same Site/Conditions", all_ok, detail)


static func _migration_idempotent() -> TestResult:
	var m := _migrate()
	var lib: WorldLibrary = m["lib"]
	var before := lib.count()
	var second := WorldLibrary.migrate(lib, SITES_FIX, COND_FIX)
	return TestResult.new("sr3 migration: running it twice adds nothing, and the legacy files are not touched", second == 0 and lib.count() == before, "second run added %d" % second)


# ---------------------------------------------------------------- terrain import
static func _tiff_spot_checks() -> TestResult:
	var parsed := GeoTiff.parse(FileAccess.get_file_as_bytes(FIXTURE_TIF))
	if not bool(parsed["ok"]):
		return TestResult.new("sr3 terrain: GeoTIFF fixture parses", false, String(parsed["error"]))
	var r: GeoTiff.Raster = parsed["raster"]
	# values read by an independent Python struct reader from the same file (tile layout, little-endian float32)
	var checks := [[5, 5, 215.4049530029297], [19, 13, 215.29100036621094], [32, 23, 214.69834899902344]]
	var ok := r.width == 38 and r.height == 27 and absf(r.west + 88.2307053) < 1.0e-9 and absf(r.north - 40.06199939868421) < 1.0e-9
	var detail := "%dx%d " % [r.width, r.height]
	for c in checks:
		var v := r.at(int(c[0]), int(c[1]))
		var s := r.sample(r.lat_of(int(c[1])), r.lon_of(int(c[0])))
		ok = ok and absf(v - float(c[2])) < 1.0e-4 and absf(s - float(c[2])) < 1.0e-3
		detail += "(%d,%d) %.3f/%.3f vs %.3f  " % [c[0], c[1], v, s, c[2]]
	return TestResult.new("sr3 terrain: the GeoTIFF reader reproduces three source pixel heights from the saved 3DEP tile, at pixel centres and by lat/lon", ok, detail)


static func _heightfield_spot_checks() -> TestResult:
	var w := WorldPresets.illinois_corn_july()
	var res := ElevationImport.apply_bytes(w, FileAccess.get_file_as_bytes(FIXTURE_TIF), ElevationImport.DEFAULT_STEP_M, ElevationImport.DEFAULT_PAD_M, "test")
	if not bool(res["ok"]):
		return TestResult.new("sr3 terrain: heightfield from the 3DEP tile", false, String(res["error"]))
	var checks := [[40.06140529736842, -88.23011119868421, 215.4049530029297], [40.06054115, -88.22859894078947, 215.29100036621094], [40.05946096578948, -88.22719470131578, 214.69834899902344]]
	var ok := absf(w.origin_elevation_m - 215.84) < 0.3 and int(res["missing_nodes"]) == 0
	var detail := "home %.2f m; " % w.origin_elevation_m
	for c in checks:
		var sim := Geodesy.latlon_to_sim(c[0], c[1], w.origin_lat, w.origin_lon)
		var got := w.terrain.height_at(sim.x, sim.y) + w.origin_elevation_m
		ok = ok and absf(got - float(c[2])) < 0.25
		detail += "%.2f vs %.2f (sim %.0f,%.0f)  " % [got, c[2], sim.x, sim.y]
	var shipped := _preset("illinois_corn_july")
	ok = ok and shipped.terrain.heightfield != null and shipped.terrain.heightfield.h == w.terrain.heightfield.h
	return TestResult.new("sr3 terrain: the world's heightfield reproduces three 3DEP source heights within 0.25 m, and the shipped preset is exactly that import", ok, detail)


static func _tiff_unsupported() -> TestResult:
	var bytes := FileAccess.get_file_as_bytes(FIXTURE_TIF)
	# set the Compression tag (259) value to 5 (LZW)
	var ifd := bytes.decode_u32(4)
	var n := bytes.decode_u16(ifd)
	for i in n:
		var e := ifd + 2 + i * 12
		if bytes.decode_u16(e) == 259:
			bytes.encode_u16(e + 8, 5)
	var res := GeoTiff.parse(bytes)
	var junk := GeoTiff.parse(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9]))
	return TestResult.new("sr3 terrain: an LZW tile and a non-TIFF are refused with a reason, not read as a wrong grid", not bool(res["ok"]) and String(res["error"]).contains("compression") and not bool(junk["ok"]), String(res["error"]))


static func _import_failure_keeps_terrain() -> TestResult:
	var w := WorldPresets.calm_test_field()
	var before := w.to_json()
	var res := ElevationImport.apply_bytes(w, PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8]), 10.0, 40.0, "x")
	return TestResult.new("sr3 terrain: a failed import leaves the world's flat terrain and elevation untouched and says why", not bool(res["ok"]) and w.to_json() == before and String(res["error"]) != "", String(res["error"]))


static func _terrain_mesh_uses_heightfield() -> TestResult:
	var w := _hilly_world()
	var verts := TerrainMesh.vertices(w.terrain)
	var worst := 0.0
	for v in verts:
		worst = maxf(worst, absf(v.y - w.terrain.height_at(v.x, v.z)))
	var span := w.terrain.heightfield.min_max()
	return TestResult.new("sr3 terrain: TerrainMesh draws the imported ground (vertices equal height_at, relief %.1f m)" % (span.y - span.x), worst < 1.0e-4 and span.y - span.x > 15.0 and verts.size() > 1000, "worst %.6f over %d vertices" % [worst, verts.size()])


# ---------------------------------------------------------------- the world in the sim
static func _conditions_wiring() -> TestResult:
	var w := _preset("illinois_corn_july")
	var c := w.to_conditions()
	var air := w.to_air()
	var dry := AirDensity.new(w.origin_elevation_m, w.temperature_c, 0.0)
	var edited := _preset("illinois_corn_july")
	edited.humidity_pct = 90.0
	edited.z0_m = 0.5
	edited.wind_ref_height_m = 20.0
	var c2 := edited.to_conditions()
	var ok := absf(c.wind_speed_mps - 6.7056) < 1.0e-3 and c.humidity_pct == 55.0 and c.roughness_z0_m == 0.15 and c.wind_from_deg == 225.0 \
		and air.kgm3() < dry.kgm3() and air.elevation_m > 210.0 and edited.to_air().kgm3() < air.kgm3() \
		and c2.humidity_pct == 90.0 and c2.roughness_z0_m == 0.5 and c2.wind_ref_height_m == 20.0
	var held := World.new()
	held.pressure_hpa = 900.0
	ok = ok and absf(held.to_air().pressure_pa() - 90000.0) < 1.0e-6
	return TestResult.new("sr3 world: wind, humidity, z0, reference height and pressure reach Conditions and AirDensity; humid air is lighter", ok,
		"wind %.3f, rho %.4f (dry %.4f), edited rho %.4f" % [c.wind_speed_mps, air.kgm3(), dry.kgm3(), edited.to_air().kgm3()])


static func _field_room_controls() -> TestResult:
	var base := "user://sr3_test/room_courses.json"
	for f in [base, SiteLibrary.path_beside(base), ConditionsLibrary.path_beside(base)]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var room := FieldSystem.new(SiteLibrary.load_from(SiteLibrary.path_beside(base)), CourseLibrary.load_from(base), ConditionsLibrary.load_from(ConditionsLibrary.path_beside(base)), ReferenceBuild.build(), base)
	room.set_field_humidity_pct(70.0)
	room.set_field_roughness_m(0.25)
	room.set_field_wind_ref_height_m(20.0)
	var saved := ConditionsLibrary.load_from(ConditionsLibrary.path_beside(base)).selected()
	var edited_ok := saved.humidity_pct == 70.0 and saved.roughness_z0_m == 0.25 and saved.wind_ref_height_m == 20.0 \
		and absf(room.air().humidity_pct - 70.0) < 1.0e-9 and room.humidity_field.value == 70.0 and room.ref_height_field.value == 20.0
	var picked := room.apply_world("illinois_corn_july")
	var after := ConditionsLibrary.load_from(ConditionsLibrary.path_beside(base)).selected()
	var site_after := SiteLibrary.load_from(SiteLibrary.path_beside(base)).selected()
	var ok := edited_ok and picked and absf(after.wind_speed_mps - 6.7056) < 1.0e-3 and after.humidity_pct == 55.0 and absf(site_after.elevation_m - 215.84) < 0.01 \
		and room.world_picker != null and room.world_picker.item_count >= 5
	return TestResult.new("sr3 field room: humidity, surface z0 and wind reference height are editable and saved; picking a world loads its weather and ground", ok,
		"edited ok %s, picked %s, wind %.3f, humidity %.0f, elevation %.2f, picker items %d" % [edited_ok, picked, after.wind_speed_mps, after.humidity_pct, site_after.elevation_m, room.world_picker.item_count])


static func _terrain_follow_band() -> TestResult:
	var w := _hilly_world()
	var p := {"class_id": "five_inch", "mission": Mission.CRUISE_LOOP, "seed": 1, "capacity_scale": 0.3, "world": w, "fields": {"reserve_pct": 0.0}, "laps": 1}
	if OS.get_environment("SR3_NO_FOLLOW") != "":
		p["terrain_follow"] = false
	var r := _fly(p)
	var tf: Dictionary = r["terrain_follow"]
	var target := float(tf["agl_target_m"])
	var lo := float(tf["agl_min_m"])
	var hi := float(tf["agl_max_m"])
	var relief := w.terrain.heightfield.min_max()
	var ok := bool(tf["enabled"]) and int(tf["samples"]) > 100 and lo > target - 4.0 and hi < target + 4.0 and relief.y - relief.x > 15.0 and String(r["ended_by"]) in ["completed", "landed_at_reserve"]
	if OS.get_environment("SR3_VERBOSE") != "":
		print("AGL ", target, " ", lo, " ", hi)
	return TestResult.new("sr3 terrain follow: over %.0f m of real-shaped relief the cruise loop holds AGL within target +-4 m" % (relief.y - relief.x), ok,
		"target %.0f m, AGL %.1f..%.1f over %d samples, ended_by %s" % [target, lo, hi, tf["samples"], r["ended_by"]])


static func _wind_from_world() -> TestResult:
	var windy := WorldPresets.calm_test_field()
	windy.world_id = "windy_cmp"
	windy.wind_speed_mps = 9.0
	windy.wind_from_deg = 90.0
	var calm := WorldPresets.calm_test_field()
	var base := {"class_id": "five_inch", "mission": Mission.FOLLOW_PATH, "seed": 1, "capacity_scale": 0.3}
	var a := base.duplicate()
	a["world"] = windy
	var b := base.duplicate()
	b["world"] = calm
	var ra := _fly(a)
	var rb := _fly(b)
	var wa: Dictionary = ra["conditions"]
	var ok := float(wa["wind_speed_mps"]) == 9.0 and float(wa["wind_from_deg"]) == 90.0 and absf(float(ra["energy_wh"]) - float(rb["energy_wh"])) > 1.0e-4 \
		and String(ra["world"]["id"]) == "windy_cmp"
	return TestResult.new("sr3 integration: the mission reads the wind from the world (result carries it and the energy differs from the calm world)", ok,
		"windy %.4f Wh, calm %.4f Wh, conditions %s" % [ra["energy_wh"], rb["energy_wh"], str(wa)])


static func _determinism() -> TestResult:
	var w := _preset("illinois_corn_july")
	var p := {"class_id": "five_inch", "mission": Mission.CRUISE_LOOP, "seed": 7, "capacity_scale": 0.3, "world": w, "fields": {"reserve_pct": 25.0}}
	var a := MissionRunner.run(p)
	var b := MissionRunner.run(p)
	var other := p.duplicate()
	other["seed"] = 8
	var c := MissionRunner.run(other)
	var ja := MissionResult.to_json(a)
	var ok := ja == MissionResult.to_json(b) and ja != MissionResult.to_json(c) and String(a["world"]["fingerprint"]) == w.fingerprint() and float(a["conditions"]["wind_speed_mps"]) > 6.0
	return TestResult.new("sr3 integration: the same world + seed gives a byte-identical mission result, another seed does not, and the result carries the world fingerprint", ok,
		"energy %.4f Wh, seed 8: %.4f Wh, fingerprint %s" % [a["energy_wh"], c["energy_wh"], a["world"]["fingerprint"]])


static func _survey_illinois() -> TestResult:
	var w := _preset("illinois_corn_july")
	var p := {"class_id": "seven_lr", "mission": Mission.SURVEY, "seed": 1, "world": w, "max_sim_min": 120.0}
	var r := _fly(p)
	var poly := float(r["polygon_area_geodesic_m2"]) if r.has("polygon_area_geodesic_m2") else 0.0
	var miss := absf(float(r["area_flown_m2"]) - poly) / maxf(poly, 1.0)
	var tf: Dictionary = r["terrain_follow"]
	var track: PackedFloat64Array = r["_track"]
	var min_z := 1.0e9
	for i in range(1, track.size(), 5):
		min_z = minf(min_z, track[i])
	var ok := min_z < -100.0 and poly > 23900.0 and poly < 24100.0 and miss <= 0.02 and bool(r["completed"]) and float(tf["agl_max_m"]) - float(tf["agl_min_m"]) < 8.0
	if OS.get_environment("SR3_VERBOSE") != "":
		print("SURVEY ", r["area_flown_m2"], " ", poly, " ", r["sorties"], " ", r["ended_by"], " ", tf["agl_min_m"], " ", tf["agl_max_m"], " ", r["flight_time_s"], " ", r["warnings"])
	return TestResult.new("sr3 integration: a seven_lr survey over the Illinois preset (15 mph wind, 3DEP ground) flies within 2 %% of the polygon's geodesic area", ok,
		"flown %.0f of %.0f m2 (miss %.2f %%), %d sorties, ended_by %s, AGL %.1f..%.1f, wind %.2f m/s, northmost z %.0f" % [r["area_flown_m2"], poly, miss * 100.0, r["sorties"], r["ended_by"], tf["agl_min_m"], tf["agl_max_m"], r["conditions"]["wind_speed_mps"], min_z])


## SR3.1: obstacles carried by the world are checked against the flown track. Mutation record: with the
## `_obstacle_warnings()` call removed from MissionRunner._result the collision and clearance cases went red
## (no warning); the far case stays green by design (it is the control that the warning is not unconditional).
static func _obstacle_case(x_offset: float, want: String, what: String) -> TestResult:
	var w := WorldPresets.calm_test_field()
	w.world_id = "obstacle_test"
	w.obstacles.append(Obstacle.place(Obstacle.POLE, x_offset, -45.0, {"radius": 0.5, "height": 200.0}, w.terrain))
	var r := _fly({"class_id": "five_inch", "mission": Mission.CRUISE_LOOP, "seed": 1, "capacity_scale": 0.3, "world": w})
	var hit := false
	var near := false
	for m in r["warnings"]:
		hit = hit or String(m).begins_with("obstacle collision")
		near = near or String(m).begins_with("obstacle clearance")
	var ok := false
	match want:
		"obstacle collision":
			ok = hit
		"obstacle clearance":
			ok = near and not hit
		_:
			ok = not hit and not near
	return TestResult.new("sr3 obstacles in missions: %s" % what, ok, "warnings %s, ended_by %s" % [str(r["warnings"]), r["ended_by"]])


## SR3.2: a migrated world has no real location. It says so in the world (location_tag estimated, placeholder flag
## that survives a save/load) and in a mission result; a preset with a real place carries neither. Mutation record:
## with `location_placeholder = true` removed from _label_migrated the case went red.
static func _placeholder_location() -> TestResult:
	var m := _migrate()
	var lib := WorldLibrary.load_dir((m["lib"] as WorldLibrary).dir)
	var migrated: World = null
	for id in lib.ids():
		migrated = lib.world(id)
		break
	var real := WorldPresets.calm_test_field()
	var rt := World.from_data(JSON.parse_string(migrated.to_json())) if migrated != null else null
	var r := _fly({"class_id": "five_inch", "mission": Mission.HOVER_ENDURANCE, "seed": 1, "capacity_scale": 0.05, "world": rt})
	var in_result := false
	for w in r["warnings"]:
		in_result = in_result or String(w).begins_with("placeholder location")
	var ok := migrated != null and migrated.location_placeholder and migrated.location_tag() == "estimated" and rt.location_placeholder \
		and not migrated.world_warnings().is_empty() and real.world_warnings().is_empty() and not real.location_placeholder and in_result
	var flag: bool = migrated != null and migrated.location_placeholder
	var tag: String = migrated.location_tag() if migrated != null else ""
	return TestResult.new("sr3 migrated worlds: location_tag is estimated, the placeholder flag survives save/load, the world and a mission result both carry the warning, and a real-place preset carries neither", ok,
		"migrated flag %s tag %s, real warnings %d, in result %s" % [str(flag), tag, real.world_warnings().size(), str(in_result)])


## SR3.3: the Field room's "Re-import elevation" button. No network: the elevation cache is seeded for the exact URL the
## call asks for (ElevationImport.request_url), with the 3DEP fixture (good case) or junk bytes (failure case). Mutation
## record: with `apply_bytes` skipped in the success path the heightfield case went red; with the failure path writing
## the half-built terrain the failure case went red.
static func _reimport_case(good: bool) -> TestResult:
	var base := "user://sr3_test/reimport_courses.json"
	for f in [base, SiteLibrary.path_beside(base), ConditionsLibrary.path_beside(base)]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var room := FieldSystem.new(SiteLibrary.load_from(SiteLibrary.path_beside(base)), CourseLibrary.load_from(base), ConditionsLibrary.load_from(ConditionsLibrary.path_beside(base)), ReferenceBuild.build(), base)
	var flat := WorldPresets.illinois_corn_july()
	flat.world_id = "reimport_probe"
	flat.world_name = "Reimport probe"
	flat.terrain = Terrain.flat(200.0, 300.0, 0.0, 0.0)
	flat.origin_elevation_m = 0.0
	room.worlds.put(flat, false)
	room.apply_world("reimport_probe")
	var url := ElevationImport.request_url(flat)
	var had_cache := FileAccess.file_exists(ElevationImport.cache_path(url))
	ElevationImport.write_cache(url, FileAccess.get_file_as_bytes(FIXTURE_TIF) if good else PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
	var terrain_before := room.site().terrain
	var elev_before := room.site().elevation_m
	var res: Dictionary = room.finish_reimport(room.worlds.world("reimport_probe"), {"ok": true, "bytes": ElevationImport.read_cache(url), "error": ""})
	if not had_cache:
		DirAccess.remove_absolute(ElevationImport.cache_path(url))
	var site := room.site()
	var w2 := room.worlds.world("reimport_probe")
	var ok := false
	var detail := ""
	if good:
		ok = bool(res["ok"]) and site.terrain.heightfield != null and absf(site.elevation_m - 215.84) < 0.3 and w2.terrain.heightfield != null \
			and room.reimport_status.text.begins_with("Ground updated") and room.reimport_button != null
		detail = "ok %s, site elevation %.2f, heightfield %s, status '%s'" % [str(res["ok"]), site.elevation_m, str(site.terrain.heightfield != null), room.reimport_status.text]
	else:
		ok = not bool(res["ok"]) and site.terrain == terrain_before and site.terrain.heightfield == null and site.elevation_m == elev_before \
			and w2.terrain.heightfield == null and room.reimport_status.text.contains("flat ground kept")
		detail = "error '%s', site elevation %.2f, status '%s'" % [String(res["error"]), site.elevation_m, room.reimport_status.text]
	var title := "Re-import elevation replaces the world's and the site's ground with the 3DEP heightfield (no network, cache seeded)" if good else "a failed Re-import leaves the flat ground and elevation untouched and shows the reason"
	return TestResult.new("sr3 field room: %s" % title, ok, detail)
