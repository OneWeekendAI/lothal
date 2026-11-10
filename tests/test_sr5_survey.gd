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
