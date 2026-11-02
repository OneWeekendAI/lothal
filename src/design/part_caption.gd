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
			# Its name already says cells, capacity and C ("4S 1300mAh 95C"): the caption is the mass.
			return mass_text(part)
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


## The caption for a card named `part_name`: the key spec, unless the name already says it (a motor
## is named "2207 1950KV"), then the part's mass; "" only when neither adds anything. Spaces and
## case do not count, so "4S 1300 mAh" is said by "4S 1300mAh 95C".
static func for_card(part: Dictionary, category: String, part_name: String) -> String:
	var spec := key_spec(part, category)
	if spec != "" and not _said_by(part_name, spec):
		return spec
	var m := mass_text(part)
	return m if m != "" and not _said_by(part_name, m) else ""


static func mass_text(part: Dictionary) -> String:
	var g := float(part.get("mass_g", 0.0))
	if g <= 0.0:
		return ""
	return "%.0f g" % g if g >= 10.0 else "%.1f g" % g


static func _said_by(part_name: String, text: String) -> bool:
	return _squash(part_name).contains(_squash(text))


static func _squash(t: String) -> String:
	return t.to_lower().replace(" ", "")


static func _trim(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")
