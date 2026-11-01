class_name PartSwap
extends RefCounted
## Click to swap (PLAN Section 3, §4.1): which catalog parts can replace the one under the pointer,
## what each would do to the five readouts, and whether it is refused. Pure: no Node, no drawing,
## nothing kept between calls.
##
## A swap changes ONE id of the session's selection and builds the result through the session's own
## path (`DesignSession.build`, i.e. `Project.to_build`), so the preview, the applied swap and a
## direct `Build.from_ids` of the same selection are the same aircraft by construction.
##
## REFUSED ONLY FOR A HARD MISFIT (§4.1): bolt holes that do not line up (motor to arm pad, either
## board to the stack), props that strike the frame, or a part of the wrong category. Everything
## else (a pack that cannot hover the build, an ESC under the motors' peak) is applied and its
## warnings are shown, because "what happens if" is the point of a builder. The reason is the first
## sentence of the blocking warning, word for word; no new prose is invented for it.

## Pick slot (PickRegistry `part/<slot>`) -> the catalog categories its picker lists, in order.
## The receiver has no drawn mesh of its own and lives beside the stack; a guard wraps the props.
const SLOTS := {
	"battery": ["battery"],
	"motor": ["motor"],
	"prop": ["propeller", "guard"],
	"stack": ["flight_controller", "esc", "receiver"],
	"camera": ["camera"],
	"antennas": ["vtx", "antenna"],
}
const CATEGORY_NAMES := {"battery": "Battery", "motor": "Motors", "propeller": "Props",
	"guard": "Prop guards", "flight_controller": "Flight controller", "esc": "ESC",
	"receiver": "Receiver", "camera": "Camera", "vtx": "Video transmitter", "antenna": "Antenna"}
## The IMPOSSIBLE warnings that make a build not a build. Any other warning is shown, not refused.
const HARD_IDS := [&"motor_mount", &"prop_clearance", &"stack_mount", &"fc_stack_mount"]
const READOUT_KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


## The pick slot an address belongs to ("part/motor/FL" -> "motor"), or "" if it has no picker.
static func slot_of(address: String) -> String:
	var p := address.split("/")
	if p.size() < 2 or p[0] != "part":
		return ""
	return p[1] if SLOTS.has(p[1]) else ""


## May this category be left empty? Optional components can be "not fitted"; required ones cannot.
static func can_be_empty(category: String) -> bool:
	return ProjectSchema.OPTIONAL_CATEGORIES.has(category)


## The verdict on fitting `part_id` as `category`: {ok, reason, readouts, warnings}. `readouts` is
## what the session would show after the swap ({} when refused or unbuildable); `warnings` are the
## first sentences of the build's impossible and limiting warnings, for showing beside it.
## `with_readouts` false skips the readouts (the slow half): the picker's list needs only the verdict.
static func judge(session: DesignSession, catalog: PartsCatalog, category: String,
		part_id: String, with_readouts := true) -> Dictionary:
	var out := {"ok": false, "reason": "", "readouts": {}, "warnings": []}
	if not session.selection.has(category):
		out["reason"] = "%s is not a part of this drone." % category
		return out
	if part_id == "":
		if not can_be_empty(category):
			out["reason"] = "A drone cannot fly without its %s." % CATEGORY_NAMES.get(category, category).to_lower()
			return out
	else:
		var part := catalog.get_part(part_id)
		if part.is_empty():
			out["reason"] = "%s is not in the catalog." % part_id
			return out
		var actual := String(part.get("category", ""))
		if actual != category:
			out["reason"] = "%s is a %s part, not a %s." % [part.get("name", part_id), actual, category]
			return out
	var trial := DesignSession.from_selection(session, category, part_id)
	var b := trial.build(catalog)
	if b == null:
		out["reason"] = "That selection does not build."
		return out
	var warnings := BuildWarning.by_severity(b.warnings())
	for w in warnings:
		if w.severity == BuildWarning.Severity.IMPOSSIBLE and HARD_IDS.has(w.id):
			out["reason"] = first_sentence(w.message)
			return out
	out["ok"] = true
	if with_readouts:
		out["readouts"] = DesignSession.readouts_of(b)
	var shown: Array = []
	for w in warnings:
		if w.severity != BuildWarning.Severity.CHARACTERISTIC:
			shown.append(first_sentence(w.message))
	out["warnings"] = shown
	return out


## The first sentence of a warning: up to the first ". " (so "5.0\"" and "30.5x30.5" survive).
static func first_sentence(message: String) -> String:
	var cut := message.find(". ")
	return message if cut < 0 else message.substr(0, cut + 1)


## The picker's rows for one category: every catalog part of it (and "not fitted" for an optional
## one), each {category, id, name, numbers, fitted, ok, reason, warnings}. No readouts: a row's
## deltas are worked out when it is hovered (DesignSpace.preview), so opening a picker builds each
## alternative once for its verdict and nothing more.
##
## `memo` (optional, kept by the caller for one catalog) remembers verdicts by the exact selection
## they judged, so reopening a picker after a swap in the same category builds nothing again: its
## rows' trial selections are the same ones as before.
static func options(session: DesignSession, catalog: PartsCatalog, category: String,
		memo: Variant = null) -> Array:
	# Null, not {}: a default dictionary could be one shared instance, keyed without the catalog.
	var m: Dictionary = memo if memo != null else {}
	var fitted := String(session.selection.get(category, ""))
	var ids: Array = []
	if can_be_empty(category):
		ids.append("")
	for part in catalog.list_category(category):
		ids.append(String((part as Dictionary).get("part_id", "")))
	var out: Array = []
	for id in ids:
		var trial: Dictionary = session.selection.duplicate()
		trial[category] = id
		var key := "%s|%s" % [category, var_to_str(trial)]
		if not m.has(key):
			if m.size() > 4000:
				m.clear()
			m[key] = judge(session, catalog, category, id, false)
		var v: Dictionary = m[key]
		var part := catalog.get_part(id) if id != "" else {}
		out.append({"category": category, "id": id,
			"name": String(part.get("name", "Not fitted")) if id != "" else "Not fitted",
			"numbers": deciding_numbers(part, category), "fitted": id == fitted,
			"ok": v["ok"], "reason": v["reason"], "warnings": v["warnings"]})
	return out


## Two or three numbers that decide between parts of a category, as display strings.
static func deciding_numbers(part: Dictionary, category: String) -> Array:
	if part.is_empty():
		return []
	var s: Dictionary = part.get("specs", {})
	var g := "%.0f g" % float(part.get("mass_g", 0.0)) if float(part.get("mass_g", 0.0)) >= 10.0 \
		else "%.1f g" % float(part.get("mass_g", 0.0))
	match category:
		"battery":
			return ["%dS" % int(s.get("cells", 0)), "%d mAh" % int(s.get("mah", 0)), g,
				"%dC" % int(s.get("c_rating", 0))]
		"motor":
			return ["%02d%02d" % [int(round(float(s.get("stator_diameter_mm", 0)))),
				int(round(float(s.get("stator_height_mm", 0))))], "%d KV" % int(s.get("kv", 0)), g]
		"propeller":
			return ["%s x %s x %d" % [_trim(float(s.get("diameter_inches", 0))),
				_trim(float(s.get("pitch_inches", 0))), int(s.get("blades", 0))], g]
		"esc":
			return ["%d A" % int(s.get("continuous_a", 0)), "%d ch" % int(s.get("channels", 0)),
				String(part.get("mounting", {}).get("pattern", "")), g]
		"flight_controller":
			return [String(part.get("mounting", {}).get("pattern", "")), g]
		"guard":
			return [String(s.get("kind", "")).replace("_", " "), g]
	if s.has("length_mm"):
		return ["%s x %s x %s mm" % [_trim(float(s["length_mm"])), _trim(float(s.get("width_mm", 0))),
			_trim(float(s.get("height_mm", 0)))], g]
	return [g]


static func _trim(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")
