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
const PACKS := {"15": "mapper_battery_4s3p_15000_liion", "10": "mapper_battery_4s_10000_liion",
	"20": "mapper_battery_4s4p_20000_liion", "25": "mapper_battery_4s5p_25000_liion",
	"6s10": "mapper_battery_6s2p_10000_liion", "6s15": "mapper_battery_6s3p_15000_liion"}
const RTK_PART := "gps_here3plus_rtk"
const RGB_ADDON_PART := "cam_sony_rx0_ii"
const RGB_ADDON_W := 2.0   # ESTIMATED
## Broadcast Remote ID: Dronetag Beacon, 16 g PUBLISHED. It runs on its own cell; the build still charges 0.37 W to the pack
## (100 mA peak x 3.7 V, computed from the published figures, an upper bound) so the option is never free.
const REMOTE_ID_PART := "rid_dronetag_beacon"
const REMOTE_ID_W := 0.37


## {"build": Build, "camera": CameraParams, "error": String}. `v`: sensor ("rededge_p" | "sentera_6x"), pack ("15" | "10"),
## rtk (bool, default true), rgb_addon (bool, default false: adds the RX0 II mass and load as payload), remote_id (bool, default
## false: adds the Dronetag Beacon as payload), swaps ({category: part_id}, optional: any further DesignSession swap, e.g. motor or
## propeller; a refused swap is an error). The result also carries "payload_items": [{role, part_id, name, mass_g, w, tag}], the
## add-ons that make up the build's single payload mass (for the BOM; they sum to payload_mass_g and payload_w).
static func make(v: Dictionary, catalog: PartsCatalog = null) -> Dictionary:
	var cat := catalog if catalog != null else PartsCatalog.load_default()
	var sensor: Dictionary = SENSORS.get(String(v.get("sensor", "rededge_p")), {})
	var pack: String = PACKS.get(String(v.get("pack", "15")), "")
	if sensor.is_empty() or pack == "":
		return {"error": "unknown sensor or pack"}
	var ds := DesignSession.default_for_class("mapper")
	var rtk := bool(v.get("rtk", true))
	var pairs: Array = [["camera", sensor["camera"]], ["gps", RTK_PART if rtk else "mapper_gps_rtk"], ["battery", pack]]
	var sw: Dictionary = v.get("swaps", {})
	for k in sw:
		pairs.append([String(k), String(sw[k])])
	for pair in pairs:
		var res := ds.swap(cat, String(pair[0]), String(pair[1]))
		if not bool(res.get("ok", true)):
			return {"error": "swap refused: %s" % str(res)}
	var b := ds.build(cat)
	if b == null:
		return {"error": "build failed"}
	var w := float(sensor["w"]) + (RTK_W if rtk else 0.0)
	var items: Array = [{"role": "sensor power", "part_id": String(sensor["camera"]), "name": "sensor electrical load (mass is the camera part)", "mass_g": 0.0, "w": float(sensor["w"]), "tag": "published"}]
	if rtk:
		items.append({"role": "RTK power", "part_id": RTK_PART, "name": "RTK electrical load (mass is the gps part)", "mass_g": 0.0, "w": RTK_W, "tag": "estimated"})
	for add in [["rgb_addon", RGB_ADDON_PART, RGB_ADDON_W, "estimated"], ["remote_id", REMOTE_ID_PART, REMOTE_ID_W, "computed from published"]]:
		if bool(v.get(String(add[0]), false)):
			var part: Dictionary = cat.get_part(String(add[1]))
			if part.is_empty():
				return {"error": "part missing: %s" % add[1]}
			items.append({"role": "RGB add-on" if add[0] == "rgb_addon" else "Remote ID", "part_id": String(add[1]), "name": String(part["name"]),
				"mass_g": float(part["mass_g"]), "w": float(add[2]), "tag": String(add[3])})
	var extra_g := 0.0
	w = 0.0
	for it in items:
		extra_g += float(it["mass_g"])
		w += float(it["w"])
	b.apply_class_payload({"w": w, "mass_g": extra_g, "tag": "estimated", "note": "survey kit"})
	return {"build": b, "camera": CameraParams.from_preset(String(sensor["preset"])), "error": "", "payload_items": items}


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
