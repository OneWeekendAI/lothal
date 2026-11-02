class_name PartColour
extends RefCounted
## The colour inside a part's shelf icon: ONE property per category, as a colour or a fill, as a pure
## function of the catalog part and the catalogue's own range for that property (no window, no theme).
## The icons are the only place colour lives in the Design Space (the drone, the panels and the text
## stay monochrome, with amber for warnings); the palette is calm and desaturated on purpose.
##
## The mapping, per category (property -> how it shows):
##   battery            capacity (mAh)               fill level, green, left to right
##   motor              KV (log scale)               body hue, cool (low KV) to warm (high KV)
##   propeller          pitch (inches)               blade hue, cool (low pitch) to warm (high pitch)
##   esc                continuous current (A)       fill level, blue
##   flight_controller  gyro sample rate (Hz)        fill level, violet
##   guard              mass (g)                     fill level, sand
##   receiver, camera, vtx, antenna   mass (g)       fill level, teal
## "Fill level" is the part's value as a share of the catalogue's range for the category (the least
## part is empty, the greatest full); "hue" is the same share along the cool-to-warm ramp.

const GREEN := Color(0.45, 0.70, 0.50)
const BLUE := Color(0.48, 0.62, 0.80)
const VIOLET := Color(0.62, 0.55, 0.80)
const SAND := Color(0.76, 0.66, 0.46)
const TEAL := Color(0.45, 0.70, 0.70)
## The cool-to-warm ramp, three stops: low, middle, high.
const COOL := Color(0.50, 0.64, 0.78)
const MID := Color(0.82, 0.82, 0.78)
const WARM := Color(0.82, 0.60, 0.48)


## The property each category shows: {key: where to read it, kind: "fill" | "hue", log: bool,
## label: what it is called, colour: the fill colour (fills only)}.
static func spec_of(category: String) -> Dictionary:
	match category:
		"battery":
			return {"key": "mah", "kind": "fill", "log": false, "label": "capacity", "colour": GREEN}
		"motor":
			return {"key": "kv", "kind": "hue", "log": true, "label": "KV"}
		"propeller":
			return {"key": "pitch_inches", "kind": "hue", "log": false, "label": "pitch"}
		"esc":
			return {"key": "continuous_a", "kind": "fill", "log": false, "label": "current", "colour": BLUE}
		"flight_controller":
			return {"key": "gyro_sample_rate_hz", "kind": "fill", "log": false, "label": "gyro rate", "colour": VIOLET}
		"guard":
			return {"key": "", "kind": "fill", "log": false, "label": "mass", "colour": SAND}
	return {"key": "", "kind": "fill", "log": false, "label": "mass", "colour": TEAL}


## The raw number the category shows for `part` (the mass for a key of ""); NAN when it has none.
static func value_of(part: Dictionary, category: String) -> float:
	if part.is_empty():
		return NAN
	var key := String(spec_of(category)["key"])
	if key == "":
		return float(part["mass_g"]) if part.has("mass_g") else NAN
	var s: Dictionary = part.get("specs", {})
	return float(s[key]) if s.has(key) else NAN


## The least and greatest `category` value among `parts` (the catalogue's range): Vector2(lo, hi);
## Vector2(NAN, NAN) when no part has the value.
static func range_of(parts: Array, category: String) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in parts:
		var v := value_of(p, category)
		if is_nan(v):
			continue
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(NAN, NAN) if lo > hi else Vector2(lo, hi)


## `value` as a share (0..1) of [lo, hi], on a log scale if `use_log`. A one-value range, or a value
## the part does not have, is 0.5 (the middle: no claim); outside the range it is held to 0 or 1.
static func unit(value: float, lo: float, hi: float, use_log := false) -> float:
	if is_nan(value) or is_nan(lo) or is_nan(hi) or hi <= lo:
		return 0.5
	if use_log:
		if lo <= 0.0 or value <= 0.0:
			return 0.5
		return clampf((log(value) - log(lo)) / (log(hi) - log(lo)), 0.0, 1.0)
	return clampf((value - lo) / (hi - lo), 0.0, 1.0)


## The cool-to-warm ramp at `t` (0 cool, 0.5 middle, 1 warm).
static func ramp(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	return COOL.lerp(MID, t * 2.0) if t < 0.5 else MID.lerp(WARM, (t - 0.5) * 2.0)


## What the icon shows for `part`, given the catalogue's `value_range` for its category:
## {property, kind, t, colour, value}. `t` is the share (fill level, or the place on the ramp);
## `colour` is the fill colour, or the ramp's colour at `t` for a hue. {} for no part.
static func encode(part: Dictionary, category: String, value_range: Vector2) -> Dictionary:
	if part.is_empty():
		return {}
	var spec := spec_of(category)
	var v := value_of(part, category)
	var t := unit(v, value_range.x, value_range.y, bool(spec["log"]))
	var colour: Color = ramp(t) if String(spec["kind"]) == "hue" else spec["colour"]
	return {"property": String(spec["label"]), "kind": String(spec["kind"]), "t": t, "colour": colour, "value": v}
