class_name Tolerances
extends RefCounted
## SR8.1: how far each input we do not know exactly may sit from the value the sim uses. A tolerance is a half-width: capacity_pct 5
## means the pack holds anywhere from 95 to 105 percent of its rating. The Monte Carlo runner (SR8.2) draws each tolerance uniformly
## over its span (a stated, conservative choice: nothing is known about the shape) and flies the mission with the drawn values.
##
## Every field carries a tag (measured / published / estimated), a source line and an `edited` flag. NONE of the defaults is measured:
## they are ESTIMATED spans, set so the ranges mean something before real data exists. Edit one and its tag becomes "user" (default_tag
## keeps the original), as Mission fields do. A guess gets a label and an editable field (precision rule P5).
##
## Fields (name: half-width unit):
##   capacity_pct   % of rated capacity (the CropMerge worked example states +-5)
##   mass_pct       % of take-off mass (mass and inertia scale together)
##   temperature_c  degrees C either side of the 25 C reference pack temperature
##   drag_pct       % of the body Cd*A (the streamlined body's 0.4 is itself an estimate, see L6)
##   esc_loss_pct   % of the ESC resistance and switching loss
##   wind_seeds     COUNT of different wind seeds drawn (the gust history; 1 = always the base seed)
##   wind_speed_mps m/s either side of the mission's mean wind (0 = off; the CropMerge example sets it from 10-20 mph)

const NAMES: Array[String] = ["capacity_pct", "mass_pct", "temperature_c", "drag_pct", "esc_loss_pct", "wind_seeds", "wind_speed_mps"]
const TAGS: Array[String] = ["measured", "published", "estimated"]

var fields: Dictionary = {}


static func defaults() -> Tolerances:
	var t := Tolerances.new()
	t._add("capacity_pct", 5.0, "%", "owner's CropMerge worked example (+-5 percent); not measured")
	t._add("mass_pct", 3.0, "%", "estimated: part-mass and wiring spread, no weighed sample")
	t._add("temperature_c", 10.0, "C", "estimated: field pack temperature spread around 25 C")
	t._add("drag_pct", 20.0, "%", "estimated: the body Cd*A has no wind-tunnel or coast-down figure (L6)")
	t._add("esc_loss_pct", 20.0, "%", "estimated: ESC loss model fitted to few points")
	t._add("wind_seeds", 5.0, "seeds", "estimated: how many gust histories to try")
	t._add("wind_speed_mps", 0.0, "m/s", "off by default; a scenario range such as 10-20 mph is set by the caller")
	return t


func _add(name: String, half: float, unit: String, source: String) -> void:
	fields[name] = {"half": half, "default": half, "unit": unit, "tag": "estimated", "default_tag": "estimated", "source": source, "edited": false}


## A copy with one half-width changed. The field becomes edited, tag "user".
func with_half(name: String, half: float) -> Tolerances:
	var t := Tolerances.new()
	t.fields = fields.duplicate(true)
	if t.fields.has(name):
		t.fields[name]["half"] = half
		t.fields[name]["edited"] = not is_equal_approx(half, float(t.fields[name]["default"]))
		t.fields[name]["tag"] = "user" if bool(t.fields[name]["edited"]) else String(t.fields[name]["default_tag"])
	return t


## A copy with every half-width zero (nothing varies): the control for "the range is flat when nothing is wired".
func zeroed() -> Tolerances:
	var t := Tolerances.new()
	t.fields = fields.duplicate(true)
	for k in t.fields:
		t.fields[k]["half"] = 0.0 if k != "wind_seeds" else 1.0
		t.fields[k]["edited"] = true
		t.fields[k]["tag"] = "user"
	return t


func half_width(name: String) -> float:
	return float(fields[name]["half"])


## Problems with the table: [] when every field is whole and tagged.
func problems() -> Array[String]:
	var out: Array[String] = []
	for n in NAMES:
		if not fields.has(n):
			out.append("missing " + n)
			continue
		var f: Dictionary = fields[n]
		if String(f["default_tag"]) not in TAGS:
			out.append("%s: default_tag '%s' is not measured / published / estimated" % [n, f["default_tag"]])
		if String(f["source"]) == "":
			out.append("%s: no source line" % n)
		if float(f["half"]) < 0.0:
			out.append("%s: negative half-width" % n)
	return out


## The run parameters for one draw: u is a Dictionary name -> number in [-1, 1] (wind_seeds: the seed offset index 0..count-1 as a plain number).
## Returns additions for MissionRunner params: capacity_scale factor, mass_scale, drag_scale, esc_loss_scale, pack_temp_c, seed offset,
## wind_delta_mps.
func draw_to_params(u: Dictionary) -> Dictionary:
	return {
		"capacity_factor": 1.0 + half_width("capacity_pct") / 100.0 * float(u.get("capacity_pct", 0.0)),
		"mass_scale": 1.0 + half_width("mass_pct") / 100.0 * float(u.get("mass_pct", 0.0)),
		"pack_temp_c": 25.0 + half_width("temperature_c") * float(u.get("temperature_c", 0.0)),
		"drag_scale": 1.0 + half_width("drag_pct") / 100.0 * float(u.get("drag_pct", 0.0)),
		"esc_loss_scale": 1.0 + half_width("esc_loss_pct") / 100.0 * float(u.get("esc_loss_pct", 0.0)),
		"seed_offset": int(u.get("wind_seeds", 0.0)),
		"wind_delta_mps": half_width("wind_speed_mps") * float(u.get("wind_speed_mps", 0.0)),
	}
