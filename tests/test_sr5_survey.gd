class_name TestSr5Survey
extends RefCounted
## SR5 survey truth. SR5.1 camera presets (data/cameras/*.json, src/autopilot/camera_params.gd): every value tagged
## (measured / published / estimated) with a source; footprint and GSD checked against HAND CALCULATIONS from the published
## field of view / the pixel pitch and focal length (numbers written here, not read back from the code).
## One TestResult per case.
##
## Hand figures at 60 m: Mavic 3M (published FOV 61.2 x 48.1 deg, 2592 x 1944): width 2 x 60 x tan(30.6 deg) = 71.0 m, GSD
## 71.0 / 2592 = 2.739 cm, along-track footprint 2 x 60 x tan(24.05 deg) = 53.6 m. RedEdge-P (pitch 3.45 um, focal 5.5 mm, 1456 x 1088):
## GSD 60 x 3.45e-6 / 5.5e-3 = 3.764 cm.
## The RedEdge-P numbers are tagged ESTIMATED: the vendor pages returned HTTP 403 when the preset was written (2026-11-10), so they
## are from memory and unchecked. Re-check them at the source before using them as published.
##
## FAIL-PROOFS (observed, fix removed by a temporary edit, then restored): see the bottom of this header, filled when run.
## F1 focal taken as the published 25 mm 35-mm EQUIVALENT instead of derived from the FOV: Mavic GSD FAILS (0.528 cm vs 2.739) and footprint FAILS (13.7 x 10.3 m).
## F2 one JSON field tag blanked (RedEdge px_w): its tag case FAILS.

const MAVIC := "mavic_3m_multispectral"
const REDEDGE := "micasense_rededge_p"


static func run() -> Array:
	return [
		_presets_listed(),
		_all_tagged(MAVIC),
		_all_tagged(REDEDGE),
		_published_have_urls(MAVIC),
		_mavic_published_values(),
		_gsd_mavic(),
		_footprint_along_mavic(),
		_gsd_rededge(),
		_unknown_preset(),
		_footprint_level(),
		_footprint_roll(),
		_footprint_hill(),
		_footprint_horizon(),
		_footprint_heightfield(),
		_cov_grid_area(),
		_cov_grid_overlap2(),
		_cov_skipped_line(),
		_cov_count_at_cell(),
		_cov_units(),
		_trk_stride(),
		_trk_tilt_in_cruise(),
		_trk_roll_gusty(),
		_trig_spacing(),
		_gsd_range_flown(),
		_overlap_calm(),
		_overlap_gusty_lower(),
		_mapped_calm(),
		_mapped_skipped_line(),
		_blur_fast_shutter_quiet(),
		_blur_slow_shutter_flags(),
		_blur_warning_in_result(),
		_gimbal_wired(),
		_photos_block_tagged(),
		_photos_deterministic(),
	]


static func _presets_listed() -> TestResult:
	var ids := CameraParams.preset_ids()
	return TestResult.new("sr5 camera presets: both Mavic 3M multispectral and MicaSense RedEdge-P are listed",
		MAVIC in ids and REDEDGE in ids, str(ids))


static func _all_tagged(id: String) -> TestResult:
	var c := CameraParams.from_preset(id)
	var bad: Array = []
	if c == null:
		bad.append("not loaded")
	else:
		for k in ["px_w", "px_h", "pixel_pitch_um", "focal_mm", "shutter_min_s", "exposure_s", "trigger_min_interval_s"]:
			if not c.field_tags.has(k):
				bad.append("missing " + k)
		for k in c.field_tags:
			var e: Dictionary = c.field_tags[k]
			if not (String(e.get("tag", "")) in CameraParams.TAGS) or String(e.get("source", "")) == "":
				bad.append(k)
	return TestResult.new("sr5 camera %s: every field (px, pitch, focal, shutter, exposure, trigger rate) has a tag and a source" % id, bad.is_empty(), str(bad))


static func _published_have_urls(id: String) -> TestResult:
	var c := CameraParams.from_preset(id)
	var bad: Array = []
	for k in c.field_tags:
		var e: Dictionary = c.field_tags[k]
		if String(e["tag"]) == "published" and not String(e["source"]).contains("https://"):
			bad.append(k)
	return TestResult.new("sr5 camera %s: every published field names a source URL" % id, bad.is_empty(), str(bad))


static func _mavic_published_values() -> TestResult:
	var c := CameraParams.from_preset(MAVIC)
	var ft := c.field_tags
	var ok: bool = c.px_w == 2592 and c.px_h == 1944 and is_equal_approx(float(ft["fov_h_deg"]["value"]), 61.2) \
		and is_equal_approx(float(ft["fov_v_deg"]["value"]), 48.1) and is_equal_approx(c.min_shot_interval_s, 2.0) \
		and String(ft["px_w"]["tag"]) == "published" and String(ft["pixel_pitch_um"]["tag"]) == "estimated"
	return TestResult.new("sr5 camera Mavic 3M: published 2592x1944, FOV 61.2 x 48.1, 2 s minimum interval kept as published; pixel pitch labelled estimated", ok,
		"%dx%d interval %.1f" % [c.px_w, c.px_h, c.min_shot_interval_s])


static func _gsd_mavic() -> TestResult:
	var c := CameraParams.from_preset(MAVIC)
	var g := c.gsd_cm(60.0)
	return TestResult.new("sr5 camera Mavic 3M: GSD at 60 m within 2 percent of the hand calculation 2.739 cm", absf(g / 2.739 - 1.0) < 0.02, "%.4f cm" % g)


static func _footprint_along_mavic() -> TestResult:
	var c := CameraParams.from_preset(MAVIC)
	var fp := c.footprint_m(60.0)
	return TestResult.new("sr5 camera Mavic 3M: footprint at 60 m is 71.0 m across and 53.6 m along (within 2 percent)",
		absf(fp.x / 71.0 - 1.0) < 0.02 and absf(fp.y / 53.6 - 1.0) < 0.02, "%.2f x %.2f m" % [fp.x, fp.y])


static func _gsd_rededge() -> TestResult:
	var c := CameraParams.from_preset(REDEDGE)
	var g := c.gsd_cm(60.0)
	return TestResult.new("sr5 camera RedEdge-P: GSD at 60 m within 2 percent of 60 x 3.45 um / 5.5 mm = 3.764 cm (estimated inputs)", absf(g / 3.764 - 1.0) < 0.02, "%.4f cm" % g)


static func _unknown_preset() -> TestResult:
	return TestResult.new("sr5 camera: an unknown preset id gives null, not a default camera", CameraParams.from_preset("no_such_camera") == null, "")


# ---------------------------------------------------------------- SR5.2 footprint projection
## Hand figures, Mavic 3M camera at 60 m, tan(hx) = 0.5914 (published 61.2 deg), tan(hy) = 0.4435 (1944/2592 of hx, the sensor's own aspect;
## the published 48.1 deg gives 0.4463, 0.6 percent more). Using the published vertical angle:
##   level flat:        4 x 0.5914 x 0.4463 x 60^2 = 3800.5 m2 (the code's own 0.4435 gives 3777, 0.6 percent less)
##   10 deg roll, flat: ground x +51.43 / -22.55 m, half-lengths 30.35 / 24.62 m, trapezoid 73.98 x 54.98 = 4067 m2
##   level over a 20 percent slope rising to +X: t = h / (1 +- 0.2 tx), corners x +31.73 / -40.24 m, half-lengths 23.94 / 30.37 m, 3909 m2
## Tolerance 1.5 percent on all three (the vertical-angle difference above is inside it).
## FAIL-PROOFS: FP1 ground treated as flat (ground callable ignored): the hill case FAILS (3777 vs 3909, -3.4 percent) and the heightfield case FAILS.
## FP2 roll ignored (orientation replaced by identity): the roll case FAILS (3777 vs 4067).

static func _cam() -> CameraParams:
	return CameraParams.from_preset(MAVIC)


static func _footprint_level() -> TestResult:
	var r := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion.IDENTITY)
	var c: PackedVector2Array = r["corners"]
	var sym: bool = r["ok"] and absf(c[0].x + c[2].x) < 0.01 and absf(c[0].y + c[2].y) < 0.01
	return TestResult.new("sr5 footprint level over flat ground at 60 m: area within 1.5 percent of the hand calculation 3800 m2 and centred under the camera",
		sym and absf(float(r["area_m2"]) / 3800.5 - 1.0) < 0.015, "area %.1f m2, corners %s" % [r["area_m2"], str(c)])


static func _footprint_roll() -> TestResult:
	var r := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion(Vector3(0, 0, 1), deg_to_rad(10.0)))
	var level := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion.IDENTITY)
	return TestResult.new("sr5 footprint 10 deg roll over flat ground: area within 1.5 percent of the hand calculation 4067 m2 and over 5 percent larger than level",
		absf(float(r["area_m2"]) / 4067.1 - 1.0) < 0.015 and float(r["area_m2"]) > 1.05 * float(level["area_m2"]),
		"area %.1f m2 vs level %.1f m2" % [r["area_m2"], level["area_m2"]])


static func _footprint_hill() -> TestResult:
	var slope := func(x: float, _z: float) -> float: return 0.2 * x
	var r := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion.IDENTITY, slope)
	return TestResult.new("sr5 footprint level over a 20 percent slope: area within 1.5 percent of the hand calculation 3909 m2 (a flat-ground-only projection gives 3777)",
		absf(float(r["area_m2"]) / 3909.2 - 1.0) < 0.015, "area %.1f m2, ground y %.1f..%.1f m" % [r["area_m2"], r["ground_y_min"], r["ground_y_max"]])


static func _footprint_horizon() -> TestResult:
	var r := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion(Vector3(0, 0, 1), deg_to_rad(75.0)))
	return TestResult.new("sr5 footprint with the camera rolled 75 deg (horizon in frame): not ok, no area reported", not bool(r["ok"]) and float(r["area_m2"]) == 0.0, str(r["note"]))


static func _footprint_heightfield() -> TestResult:
	# 41 x 41 posts, 10 m, plane y = 0.2 x - the same slope through a real Heightfield and its ground_of() adaptor.
	var heights := PackedFloat32Array()
	for row in 41:
		for col in 41:
			heights.append(0.2 * (-200.0 + col * 10.0))
	var hf := Heightfield.make(-200.0, -200.0, 10.0, 41, 41, heights)
	var r := Footprint.project(_cam(), Vector3(0, 60, 0), Quaternion.IDENTITY, Footprint.ground_of(hf))
	return TestResult.new("sr5 footprint through a Heightfield (20 percent plane): same 3909 m2 within 1.5 percent",
		hf.is_valid() and absf(float(r["area_m2"]) / 3909.2 - 1.0) < 0.015, "valid %s, area %.1f m2" % [str(hf.is_valid()), r["area_m2"]])


# ---------------------------------------------------------------- SR5.3 coverage raster
## Grid helpers: lines run along +Z, spaced `side` x footprint width apart in X; shots every 0.25 x footprint length along Z (75 percent
## front overlap). Footprints come from Footprint.project (level, Mavic 3M camera, 60 m), never from a swath formula.
## FAIL-PROOFS (observed): CV1 add_footprint marking only the cell under the first corner: grid area FAILS (a few cells instead of 100 percent),
## the 5-photo case FAILS. CV2 skipped line not skipped (grid built with all lines): the skipped-line case FAILS (hole 0 m2 vs 5649). CV3 acres factor
## 4046.8564224 -> 4000: the units case FAILS.
const CELL := 1.0

static func _shots(lines: Array, side_gap: float, z_end: float) -> CoverageMap:
	var cam := _cam()
	var fp := cam.footprint_m(60.0)
	var map := CoverageMap.covering(Rect2(-20.0, -40.0, fp.x * 8.0, z_end + 80.0), CELL)
	for k in lines:
		var x: float = fp.x * 0.5 + float(k) * fp.x * (1.0 - side_gap)
		var z := 0.0
		while z <= z_end + fp.y * 0.5:
			var r := Footprint.project(cam, Vector3(x, 60.0, z), Quaternion.IDENTITY)
			map.add_footprint(r["corners"])
			z += fp.y * 0.25
	return map


static func _field(side_gap: float, n_lines: int, z_end: float) -> PackedVector2Array:
	var fp := _cam().footprint_m(60.0)
	var w := fp.x + float(n_lines - 1) * fp.x * (1.0 - side_gap)
	return PackedVector2Array([Vector2(0.3, 0.3), Vector2(w - 0.4, 0.3), Vector2(w - 0.4, z_end - 0.2), Vector2(0.3, z_end - 0.2)])


static func _cov_grid_area() -> TestResult:
	var poly := _field(0.35, 5, 100.0)
	var map := _shots([0, 1, 2, 3, 4], 0.35, 100.0)
	var area := float(map.mapped_area(1, poly)["m2"])
	var truth := _poly_area(poly)
	return TestResult.new("sr5 coverage perfect grid over a flat field: mapped area within 1 percent of the polygon area",
		absf(area / truth - 1.0) < 0.01, "mapped %.1f m2, polygon %.1f m2, images %d" % [area, truth, map.images])


static func _cov_grid_overlap2() -> TestResult:
	# Front overlap 75 percent puts every cell in 4 photos of ONE line; a cell in the side-overlap strip is in 8. Requiring 5 photos keeps only the
	# overlap strips: 4 strips of 0.35 w in a field 3.6 w wide, so 1.4 / 3.6 = 0.389 of the field (hand calculation).
	var poly := _field(0.35, 5, 100.0)
	var map := _shots([0, 1, 2, 3, 4], 0.35, 100.0)
	var one := float(map.mapped_area(1, poly)["m2"])
	var five := float(map.mapped_area(5, poly)["m2"])
	return TestResult.new("sr5 coverage same grid, 5 photos required: only the side-overlap strips remain, 1.4 / 3.6 = 39 percent of the field (35-43 percent)",
		five / one > 0.35 and five / one < 0.43, "required 1: %.1f m2, required 5: %.1f m2, ratio %.3f" % [one, five, five / one])


static func _cov_skipped_line() -> TestResult:
	# 10 percent side overlap, so a skipped line leaves a real gap: 2s - w = 0.8 w wide (w = footprint width), 100 m long.
	var gap := 0.10
	var poly := _field(gap, 5, 100.0)
	var map := _shots([0, 1, 3, 4], gap, 100.0)
	var fp := _cam().footprint_m(60.0)
	var expect := (2.0 * (1.0 - gap) - 1.0) * fp.x * (100.0 - 0.5)
	var hole := float(map.hole_area(1, poly)["m2"])
	return TestResult.new("sr5 coverage skipped middle line (10 percent side overlap): the hole is 0.8 footprint widths x field length, within one cell row (one column of 100 m)",
		absf(hole - expect) <= 100.0 * CELL, "hole %.1f m2, expected %.1f m2" % [hole, expect])


static func _cov_count_at_cell() -> TestResult:
	var map := _shots([0, 1], 0.35, 100.0)
	var fp := _cam().footprint_m(60.0)
	# A point under the overlap of line 0 and line 1 (side overlap 35 percent) and between shots (75 percent front overlap: 4 photos at a time).
	var x := fp.x * 0.5 + 0.5 * fp.x * 0.65
	var n := map.overlap_at(x, 50.0)
	return TestResult.new("sr5 coverage: a cell in the side-overlap strip is seen by about 8 photos (2 lines x 4 shots at 75 percent front overlap)",
		n >= 7 and n <= 9, "count %d" % n)


static func _cov_units() -> TestResult:
	var map := CoverageMap.covering(Rect2(0, 0, 100, 100), 1.0)
	map.add_footprint(PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]))
	var a := map.mapped_area(1)
	return TestResult.new("sr5 coverage units: 100 x 100 m is 10000 m2, 1 ha and 2.4711 acres",
		is_equal_approx(float(a["m2"]), 10000.0) and is_equal_approx(float(a["hectares"]), 1.0) and absf(float(a["acres"]) - 2.47105) < 0.0001, str(a))


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


# ---------------------------------------------------------------- SR5.4 triggers wired into the MissionRunner
## Flights: five_inch survey of a 70 x 50 m field at 40 m with the Mavic 3M camera, side overlap 30 percent, seed 11, pack rating x0.5.
## Hand figures: GSD at 40 m = 2.739 cm x 40 / 60 = 1.826 cm (the SR5.1 hand figure scaled by height). Planned front overlap 75 percent.
## The camera is FIXED to the airframe (tilts with it) unless the run says gimbal_stabilised; blur = ground speed x exposure / GSD.
## FAIL-PROOFS (observed 2026-11-10, fix removed by a temporary edit, then restored):
## TR1 roll / pitch not written to the track (zeros): the nose-down and gusty-roll cases FAIL (mean pitch 0.000, roll 0.000).
## TR2 attitude replaced by identity at the trigger: 4 FAIL (calm overlap 0.813 vs 0.749 planned: the tilt matters; gusty min overlap; skipped line; gimbal fixed worst 0 deg).
## TR3 trigger fires every 0.2 s tick (no interval): spacing FAILS (0.20 s vs 3.01 s) and calm overlap FAILS (0.983).
## TR4 blur term dropped (0): 3 FAIL (fast-shutter hand figure, slow-shutter flags 0 of 16, warning absent).
## TR5 gimbal flag ignored: the gimbal case FAILS (stabilised worst 3.69 deg).
## TR6 coverage map not fed (nothing added): the two mapped cases FAIL (0 m2 mapped).
const SEED54 := 11
static var _cache54: Dictionary = {}


static func _survey54(wind: float, gust: float, extra: Dictionary = {}) -> Dictionary:
	var cam := _cam()
	if extra.has("exposure_s"):
		cam.exposure_s = float(extra["exposure_s"])
	var fields := {"height_m": 40.0, "side_overlap": 0.3}
	for k in extra.get("fields", {}):
		fields[k] = extra["fields"][k]
	var p := {"class_id": "five_inch", "mission": "survey", "seed": SEED54, "capacity_scale": 0.5, "camera": cam,
		"polygon": PackedVector2Array([Vector2(30, 0), Vector2(100, 0), Vector2(100, 50), Vector2(30, 50)]),
		"wind_speed_mps": wind, "gust_mps": gust, "fields": fields}
	for k in ["debug_skip_line", "gimbal_stabilised"]:
		if extra.has(k):
			p[k] = extra[k]
	var key := var_to_str([wind, gust, extra])
	if not _cache54.has(key):
		_cache54[key] = MissionRunner.run(p)
	return _cache54[key]


static func _max_tilt_deg(r: Dictionary, col: int, only_camera_on: bool) -> float:
	var trk: PackedFloat64Array = r["_track"]
	var m := 0.0
	for i in int(trk.size() / float(MissionRunner.TRACK_STRIDE)):
		if only_camera_on and trk[i * MissionRunner.TRACK_STRIDE + 4] < 0.5:
			continue
		m = maxf(m, absf(rad_to_deg(trk[i * MissionRunner.TRACK_STRIDE + col])))
	return m


static func _trk_stride() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var trk: PackedFloat64Array = r["_track"]
	var ok := MissionRunner.TRACK_STRIDE == 7 and trk.size() == int(r["track_samples"]) * 7 and trk.size() > 0
	return TestResult.new("sr5 track: 7 floats per sample (x, z, y, heading, camera_on, roll, pitch), size = samples x 7", ok,
		"stride %d, floats %d, samples %d" % [MissionRunner.TRACK_STRIDE, trk.size(), r["track_samples"]])


static func _trk_tilt_in_cruise() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var trk: PackedFloat64Array = r["_track"]
	var sum := 0.0
	var n := 0
	for i in int(trk.size() / 7.0):
		if trk[i * 7 + 4] > 0.5:
			sum += trk[i * 7 + 6]
			n += 1
	var mean_deg := rad_to_deg(sum / maxf(n, 1.0))
	return TestResult.new("sr5 track: cruising the survey lines at 2.95 m/s the nose is down (mean pitch between -2 and -0.1 deg; measured -0.55)",
		n > 100 and mean_deg < -0.1 and mean_deg > -2.0, "%d camera-on samples, mean pitch %.3f deg" % [n, mean_deg])


static func _trk_roll_gusty() -> TestResult:
	var calm := _max_tilt_deg(_survey54(0.0, 0.0), 5, true)
	var gust := _max_tilt_deg(_survey54(4.5, 2.0), 5, true)
	return TestResult.new("sr5 track: roll in 4.5 m/s wind with 2 m/s gusts exceeds 1 deg and five times the calm run's",
		gust > 1.0 and gust > 5.0 * calm, "calm max roll %.3f deg, gusty %.3f deg" % [calm, gust])


static func _trig_spacing() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var ph: Array = r["_photos"]
	var want := float(r["survey"]["shot_interval_s"])
	var worst_lo := INF
	var worst_hi := 0.0
	var same_line := 0
	for i in range(1, ph.size()):
		var dt := float(ph[i]["t"]) - float(ph[i - 1]["t"])
		if dt < want + 0.5:
			same_line += 1
			worst_lo = minf(worst_lo, dt)
			worst_hi = maxf(worst_hi, dt)
	return TestResult.new("sr5 triggers: shots on a line are one planned interval apart (within the 0.2 s tick)",
		ph.size() >= 8 and same_line >= 6 and worst_lo >= want - 0.25 and worst_hi <= want + 0.25,
		"%d photos, planned interval %.2f s, observed %.2f-%.2f s over %d pairs" % [ph.size(), want, worst_lo, worst_hi, same_line])


static func _gsd_range_flown() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var g: Dictionary = r["photos"]["gsd_cm"]
	var fig: Dictionary = r["figures"]["gsd_cm"]
	var ok := absf(float(g["mean"]) / 1.826 - 1.0) < 0.02 and float(g["min"]) <= float(g["mean"]) and float(g["mean"]) <= float(g["max"]) \
		and float(g["max"]) > float(g["min"]) and float(fig["low"]) == float(g["min"]) and float(fig["high"]) == float(g["max"]) and String(fig["tag"]) == _cam().tag
	return TestResult.new("sr5 GSD range from the flown poses: mean 1.826 cm/px at 40 m within 2 percent, a min-max range in the figure, tagged like the camera (estimated: pixel pitch)",
		ok, "min %.4f mean %.4f max %.4f cm/px; figure tag %s" % [g["min"], g["mean"], g["max"], fig["tag"]])


static func _overlap_calm() -> TestResult:
	var o: Dictionary = _survey54(0.0, 0.0)["photos"]["front_overlap"]
	return TestResult.new("sr5 overlap measured from the footprints (calm): mean front overlap within 0.03 of the planned 0.75",
		int(o["pairs"]) >= 6 and absf(float(o["mean"]) - 0.75) < 0.03, "min %.3f mean %.3f max %.3f over %d pairs" % [o["min"], o["mean"], o["max"], o["pairs"]])


static func _overlap_gusty_lower() -> TestResult:
	var calm: Dictionary = _survey54(0.0, 0.0)["photos"]["front_overlap"]
	var gust: Dictionary = _survey54(4.5, 2.0)["photos"]["front_overlap"]
	return TestResult.new("sr5 overlap: the same seed in 4.5 m/s wind with 2 m/s gusts has a lower worst-case front overlap than calm (by more than 0.02)",
		float(gust["min"]) < float(calm["min"]) - 0.02, "calm min %.3f (mean %.3f), gusty min %.3f (mean %.3f)" % [calm["min"], calm["mean"], gust["min"], gust["mean"]])


static func _mapped_calm() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var ph: Dictionary = r["photos"]
	var poly := float(r["polygon_area_m2"])
	return TestResult.new("sr5 mapped area (2+ photos per cell, from the flown triggers): within 5 percent of the field and 95 percent mapped",
		absf(float(ph["mapped_m2"]) / poly - 1.0) < 0.05 and float(ph["mapped_fraction"]) > 0.95 and absf(float(ph["mapped_acres"]) - float(ph["mapped_m2"]) / 4046.8564224) < 1e-6,
		"mapped %.0f m2 of %.0f (%.3f), %.4f acres, %d images" % [ph["mapped_m2"], poly, ph["mapped_fraction"], ph["mapped_acres"], ph["images"]])


static func _mapped_skipped_line() -> TestResult:
	var calm := _survey54(0.0, 0.0, {"fields": {"side_overlap": 0.1}})
	var skip := _survey54(0.0, 0.0, {"fields": {"side_overlap": 0.1}, "debug_skip_line": 1})
	var c: Dictionary = calm["photos"]
	var k: Dictionary = skip["photos"]
	return TestResult.new("sr5 mapped area: skipping a line (10 percent side overlap) maps at least 20 percent less area and leaves 500+ m2 unmapped inside the field",
		float(k["mapped_m2"]) < 0.8 * float(c["mapped_m2"]) and float(k["unmapped_in_polygon_m2"]) > 500.0 and float(c["unmapped_in_polygon_m2"]) < 250.0,
		"intact %.0f m2 mapped, %.0f m2 unmapped; skipped %.0f mapped, %.0f unmapped" % [c["mapped_m2"], c["unmapped_in_polygon_m2"], k["mapped_m2"], k["unmapped_in_polygon_m2"]])


static func _blur_fast_shutter_quiet() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var b: Dictionary = r["photos"]["blur"]
	var v := float(r["params"]["fields"]["speed_mps"]["value"])
	var gsd_m := float(r["photos"]["gsd_cm"]["mean"]) / 100.0
	var hand := v * _cam().exposure_s / gsd_m
	return TestResult.new("sr5 blur at the Mavic's own exposure: nothing flagged, worst photo within 25 percent of speed x exposure / GSD by hand",
		int(b["flagged"]) == 0 and float(b["max_px"]) < 0.5 and absf(float(b["max_px"]) / hand - 1.0) < 0.25,
		"exposure %.5f s, speed field %.1f m/s, hand %.3f px, worst %.3f px, flagged %d" % [_cam().exposure_s, v, hand, b["max_px"], b["flagged"]])


static func _blur_slow_shutter_flags() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var slow := _cam()
	slow.exposure_s = 0.02
	var rep := SurveyPhotos.report(r["_photos"], slow, PackedVector2Array(), Callable(), 2, 0.5, 2.0)
	var b: Dictionary = rep["blur"]
	return TestResult.new("sr5 blur at 1/50 s: every photo is flagged (speed x 0.02 s is several pixels at 1.8 cm/px)",
		int(b["flagged"]) == int(rep["images"]) and int(rep["images"]) > 0 and float(b["max_px"]) > 2.0,
		"flagged %d of %d, worst %.2f px" % [b["flagged"], rep["images"], b["max_px"]])


static func _blur_warning_in_result() -> TestResult:
	var r := _survey54(0.0, 0.0, {"exposure_s": 0.02})
	var has := false
	for w in r["warnings"]:
		if String(w).contains("motion blur"):
			has = true
	var calm_has := false
	for w in _survey54(0.0, 0.0)["warnings"]:
		if String(w).contains("motion blur"):
			calm_has = true
	return TestResult.new("sr5 blur: a run at 1/50 s warns 'motion blur' with the count and the ESTIMATED limit, the 1/2000 s run does not",
		has and not calm_has and int(r["photos"]["blur"]["flagged"]) > 0, "slow warns %s, normal warns %s" % [str(has), str(calm_has)])


static func _gimbal_wired() -> TestResult:
	var fixed := _survey54(4.5, 2.0)
	var gim := _survey54(4.5, 2.0, {"gimbal_stabilised": true})
	var tilt_fixed := 0.0
	for ph in fixed["_photos"]:
		tilt_fixed = maxf(tilt_fixed, rad_to_deg((ph["q"] * Vector3.DOWN).angle_to(Vector3.DOWN)))
	var tilt_gim := 0.0
	for ph in gim["_photos"]:
		tilt_gim = maxf(tilt_gim, rad_to_deg((ph["q"] * Vector3.DOWN).angle_to(Vector3.DOWN)))
	return TestResult.new("sr5 gimbal: a fixed mount photographs tilted (over 3 deg off nadir somewhere), a stabilised gimbal is nadir (under 0.01 deg)",
		tilt_fixed > 3.0 and tilt_gim < 0.01, "fixed worst %.2f deg, stabilised worst %.4f deg" % [tilt_fixed, tilt_gim])


static func _photos_block_tagged() -> TestResult:
	var r := _survey54(0.0, 0.0)
	var d = JSON.parse_string(MissionResult.to_json(r))
	var ph: Dictionary = d["photos"]
	var ok: bool = String(ph["gsd_cm"]["tag"]) in CameraParams.TAGS and String(ph["blur"]["limit_tag"]) == "estimated" and String(ph["required_photos_tag"]) == "estimated" \
		and String(ph["front_overlap"]["tag"]) == "estimated" and String(ph["source"]).contains("Footprint.project") and not d.has("_photos") \
		and String(d["figures"]["gsd_cm"]["tag"]) in CameraParams.TAGS and String(d["figures"]["mapped_m2"]["tag"]) == "estimated"
	return TestResult.new("sr5 photos block in the result JSON: range figures, every value tagged, a source line, the raw poses not written", ok, str(ph.keys()))


static func _photos_deterministic() -> TestResult:
	var a := _survey54(0.0, 0.0)
	var p2 := {"class_id": "five_inch", "mission": "survey", "seed": SEED54, "capacity_scale": 0.5, "camera": _cam(),
		"polygon": PackedVector2Array([Vector2(30, 0), Vector2(100, 0), Vector2(100, 50), Vector2(30, 50)]),
		"wind_speed_mps": 0.0, "gust_mps": 0.0, "fields": {"height_m": 40.0, "side_overlap": 0.3}}
	var b := MissionRunner.run(p2)
	return TestResult.new("sr5 photos: the same run twice gives byte-identical result text",
		MissionResult.to_json(a) == MissionResult.to_json(b), "photos equal %s" % str(JSON.stringify(a["photos"]) == JSON.stringify(b["photos"])))
