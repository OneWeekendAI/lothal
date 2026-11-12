class_name TestSurveyKitParts
extends RefCounted
## Survey-kit catalog parts and delivery builds (2026-11-12). Masses are the published figures named in each part's source.
## FAIL-PROOF (observed, see the results file): with the five part entries and the Sentera preset removed from data/, every part,
## pack, preset and build case FAILS; with SurveyKitBuilds.make's payload line removed the payload-load case FAILS; with the
## round-up removed from batteries_per_farm the packs case FAILS.

const PARTS := {"cam_micasense_rededge_p_kit": [315.0, "camera"], "cam_sentera_6x_multispectral": [290.0, "camera"], "cam_sony_rx0_ii": [132.0, "camera"],
	"gps_here3plus_rtk": [51.8, "gps"], "mapper_battery_4s3p_15000_liion": [870.0, "battery"]}


static func run() -> Array:
	var out: Array = []
	var cat := PartsCatalog.load_default()
	for id in PARTS:
		out.append(_part(cat, id))
	out.append(_pack(cat))
	out.append(_presets())
	out.append_array(_builds(cat))
	out.append_array(_farm())
	return out


static func _part(cat: PartsCatalog, id: String) -> TestResult:
	var p: Dictionary = cat.get_part(id)
	var want: Array = PARTS[id]
	var src := String(p.get("source", ""))
	var ok := not p.is_empty() and absf(float(p.get("mass_g", 0.0)) - float(want[0])) < 1e-6 and String(p.get("category", "")) == String(want[1])
	ok = ok and src.contains("https://") and (src.contains("PUBLISHED") or src.contains("ESTIMATED")) and not src.to_lower().contains("price")
	return TestResult.new("survey kit parts: %s is in the catalog at %s g with a URL and a PUBLISHED/ESTIMATED tag in its source" % [id, str(want[0])], ok, "mass %s" % str(p.get("mass_g")))


static func _pack(cat: PartsCatalog) -> TestResult:
	var p: Dictionary = cat.get_part("mapper_battery_4s3p_15000_liion")
	if p.is_empty():
		return TestResult.new("survey kit parts: the 4S3P 15 Ah pack is 216 Wh, in the Li-ion density band, 75 A", false, "missing")
	var s: Dictionary = p["specs"]
	var wh := float(s["nominal_v"]) * float(s["mah"]) / 1000.0
	var why := TestBatteryDensity.check(String(s["chemistry"]), float(s["nominal_v"]), float(s["mah"]), float(p["mass_g"]))
	return TestResult.new("survey kit parts: the 4S3P 15 Ah pack is 216 Wh, in the Li-ion density band, 75 A (5C), 4 series cells",
		absf(wh - 216.0) < 0.5 and why == "" and absf(float(s["c_rating"]) * float(s["mah"]) / 1000.0 - 75.0) < 0.5 and int(s["cells"]) == 4, "%.0f Wh %s" % [wh, why])


static func _presets() -> TestResult:
	var s := CameraParams.from_preset("sentera_6x_multispectral")
	var r := CameraParams.from_preset("micasense_rededge_p")
	if s == null or r == null:
		return TestResult.new("survey kit parts: Sentera 6X preset loads and its footprint at 60 m is the published 47 deg HFOV", false, "preset missing")
	var width := 2.0 * 60.0 * tan(deg_to_rad(23.5))
	var fp := s.sensor_w_mm / s.focal_mm * 60.0
	return TestResult.new("survey kit parts: Sentera 6X preset (2048 px, 47 deg HFOV, 0.2 s) and RedEdge-P pixel/focal fields tagged published",
		s.px_w == 2048 and absf(fp - width) < 0.05 and absf(s.min_shot_interval_s - 0.2) < 1e-6
		and String(r.field_tags["focal_mm"]["tag"]) == "published" and String(r.field_tags["px_w"]["tag"]) == "published",
		"footprint %.2f vs %.2f, interval %.2f" % [fp, width, s.min_shot_interval_s])


static func _builds(cat: PartsCatalog) -> Array:
	var out: Array = []
	var m := SurveyKitBuilds.make({"sensor": "rededge_p", "pack": "15"}, cat)
	var bad := SurveyKitBuilds.make({"sensor": "nope"}, cat)
	out.append(TestResult.new("survey kit builds: an unknown sensor is refused with an error, not a build", String(bad.get("error", "")) != "" and not bad.has("build"), str(bad.get("error"))))
	if String(m.get("error", "x")) != "":
		out.append(TestResult.new("survey kit builds: the RedEdge-P 15 Ah build carries the kit, Here3+ and 12 W", false, str(m)))
		return out
	var b: Build = m["build"]
	out.append(TestResult.new("survey kit builds: the RedEdge-P 15 Ah build carries 12 W of payload load (10 W sensor peak + 2 W RTK) and the RedEdge-P camera preset",
		absf(b.payload_w - 12.0) < 1e-6 and (m["camera"] as CameraParams).preset_id == "micasense_rededge_p", "payload_w %.1f" % b.payload_w))
	var small := SurveyKitBuilds.make({"sensor": "rededge_p", "pack": "10"}, cat)["build"] as Build
	var dm := (b.mass_properties.total_mass_kg - small.mass_properties.total_mass_kg) * 1000.0
	out.append(TestResult.new("survey kit builds: the 15 Ah pack adds exactly the pack mass difference (870 - 580 g)", absf(dm - 290.0) < 1.0, "dm %.1f g" % dm))
	var no_rtk := SurveyKitBuilds.make({"sensor": "rededge_p", "pack": "15", "rtk": false}, cat)["build"] as Build
	out.append(TestResult.new("survey kit builds: RTK on adds the Here3+ 51.8 g over the stand-in 30 g and 2 W", absf((b.mass_properties.total_mass_kg - no_rtk.mass_properties.total_mass_kg) * 1000.0 - 21.8) < 0.5 and absf(b.payload_w - no_rtk.payload_w - 2.0) < 1e-6, ""))
	var rgb := SurveyKitBuilds.make({"sensor": "rededge_p", "pack": "15", "rgb_addon": true}, cat)["build"] as Build
	out.append(TestResult.new("survey kit builds: the RGB add-on adds 132 g and 2 W", absf((rgb.mass_properties.total_mass_kg - b.mass_properties.total_mass_kg) * 1000.0 - 132.0) < 1.0 and absf(rgb.payload_w - b.payload_w - 2.0) < 1e-6, ""))
	return out


static func _farm() -> Array:
	var out: Array = []
	var r := SurveyKitBuilds.batteries_per_farm(300.0, 100.0, 80.0, 125.0)
	out.append(TestResult.new("survey kit farm: 300 acres at 100 (80-125) acres per battery is 3.0 (2.4-3.75) batteries, 3 to 4 whole packs",
		absf(r["value"] - 3.0) < 1e-9 and absf(r["low"] - 2.4) < 1e-9 and absf(r["high"] - 3.75) < 1e-9 and r["packs_low"] == 3 and r["packs_high"] == 4 and r["packs_value"] == 3, str(r)))
	var z := SurveyKitBuilds.batteries_per_farm(300.0, 0.0, 0.0, 0.0)
	out.append(TestResult.new("survey kit farm: a zero acres-per-battery figure reports unknown (-1), not infinity", z["value"] == -1.0 and z["packs_value"] == -1, str(z)))
	return out
