class_name PartCaption
extends RefCounted
## The ONE key spec shown under a part's picture on the shelf, as a pure function of the catalog
## part and its category: "4S 1500 mAh", "2207 1950KV", "5.1 in 3-blade". No window, no theme.


static func key_spec(part: Dictionary, category: String) -> String:
	if part.is_empty():
		return ""
	var s: Dictionary = part.get("specs", {})
	match category:
		"battery":
			return "%dS %d mAh" % [int(s.get("cells", 0)), int(round(float(s.get("mah", 0))))]
		"motor":
			return "%02d%02d %dKV" % [int(round(float(s.get("stator_diameter_mm", 0)))),
				int(round(float(s.get("stator_height_mm", 0)))), int(round(float(s.get("kv", 0))))]
		"propeller":
			return "%s in %d-blade" % [_trim(float(s.get("diameter_inches", 0))), int(s.get("blades", 0))]
		"esc":
			return "%d A %d-ch" % [int(round(float(s.get("continuous_a", 0)))), int(s.get("channels", 0))]
		"flight_controller":
			var pat := String(part.get("mounting", {}).get("pattern", ""))
			return "%s mm" % pat if pat != "" else ""
		"guard":
			var kind := String(s.get("kind", "")).replace("_", " ")
			var od := float(s.get("outer_radius_mm", 0)) * 2.0
			return "%s %s mm" % [kind, _trim(od)] if od > 0.0 else kind
	if s.has("length_mm"):
		return "%s x %s mm" % [_trim(float(s["length_mm"])), _trim(float(s.get("width_mm", 0)))]
	return ""


static func _trim(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")
