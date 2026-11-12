class_name SurveyKitBuilds
extends RefCounted
## Survey kit builds (2026-11-12): the mapper airframe carrying a named sensor kit, RTK GNSS and pack, with the
## payload counted in full (mass from the catalog parts, electrical load from the sensor's published power plus RTK).
## SENSORS maps a short name to {camera part, camera preset, power W, tag}. Powers: RedEdge-P 10 W peak [published, MicaSense guide];
## Sentera 6X 15 W [published, reseller listing]; RTK 2 W [estimated].
## Numbers are tagged in the part files; this class only assembles.

const RTK_W := 2.0
const SENSORS := {
	"rededge_p": {"camera": "cam_micasense_rededge_p_kit", "preset": "micasense_rededge_p", "w": 10.0},
	"sentera_6x": {"camera": "cam_sentera_6x_multispectral", "preset": "sentera_6x_multispectral", "w": 15.0},
}
const PACKS := {"15": "mapper_battery_4s3p_15000_liion", "10": "mapper_battery_4s_10000_liion"}
const RTK_PART := "gps_here3plus_rtk"
const RGB_ADDON_PART := "cam_sony_rx0_ii"
const RGB_ADDON_W := 2.0   # ESTIMATED


## {"build": Build, "camera": CameraParams, "error": String}. `v`: sensor ("rededge_p" | "sentera_6x"), pack ("15" | "10"),
## rtk (bool, default true), rgb_addon (bool, default false: adds the RX0 II mass and load as payload).
static func make(v: Dictionary, catalog: PartsCatalog = null) -> Dictionary:
	var cat := catalog if catalog != null else PartsCatalog.load_default()
	var sensor: Dictionary = SENSORS.get(String(v.get("sensor", "rededge_p")), {})
	var pack: String = PACKS.get(String(v.get("pack", "15")), "")
	if sensor.is_empty() or pack == "":
		return {"error": "unknown sensor or pack"}
	var ds := DesignSession.default_for_class("mapper")
	var rtk := bool(v.get("rtk", true))
	for pair in [["camera", sensor["camera"]], ["gps", RTK_PART if rtk else "mapper_gps_rtk"], ["battery", pack]]:
		var res := ds.swap(cat, String(pair[0]), String(pair[1]))
		if not bool(res.get("ok", true)):
			return {"error": "swap refused: %s" % str(res)}
	var b := ds.build(cat)
	if b == null:
		return {"error": "build failed"}
	var w := float(sensor["w"]) + (RTK_W if rtk else 0.0)
	var extra_g := 0.0
	if bool(v.get("rgb_addon", false)):
		extra_g = float(cat.get_part(RGB_ADDON_PART)["mass_g"])
		w += RGB_ADDON_W
	b.apply_class_payload({"w": w, "mass_g": extra_g, "tag": "estimated", "note": "survey kit"})
	return {"build": b, "camera": CameraParams.from_preset(String(sensor["preset"])), "error": ""}


## Batteries (packs) a farm needs from acres per battery: {"value","low","high"} = farm / mid, farm / high, farm / low (more acres per
## battery means fewer batteries), each rounded UP to whole packs under "packs_*". A zero or negative figure returns -1 (unknown).
static func batteries_per_farm(farm_acres: float, apb_mid: float, apb_low: float, apb_high: float) -> Dictionary:
	if apb_mid <= 0.0 or apb_low <= 0.0 or apb_high <= 0.0:
		return {"value": -1.0, "low": -1.0, "high": -1.0, "packs_value": -1, "packs_low": -1, "packs_high": -1}
	var out := {"value": farm_acres / apb_mid, "low": farm_acres / apb_high, "high": farm_acres / apb_low}
	out["packs_value"] = int(ceil(out["value"] - 1e-9))
	out["packs_low"] = int(ceil(out["low"] - 1e-9))
	out["packs_high"] = int(ceil(out["high"] - 1e-9))
	return out
