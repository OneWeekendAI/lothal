class_name ResultsPanel
extends VBoxContainer
## L1.6 the result of a flown mission, shown in the Design Space's own widgets. set_result(result) keeps the SAME dictionary
## (no copy); render() rebuilds the rows from it every time, so the panel can never show a value the result does not hold.
## One row per figure: name, value with unit, its source tag as the subtle tag chip, and the range under it. Then the
## endurance line (amber when it fails), what was flown and the settings that were used. text() is every shown line.

var result: Dictionary = {}
var _shown: Array[String] = []


func _init() -> void:
	name = "ResultsPanel"
	add_theme_constant_override("separation", 6)


func set_result(r: Dictionary) -> void:
	result = r
	render()


func text() -> String:
	return "\n".join(_shown)


static func _n(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.0f" % v
	return "%.1f" % v if absf(v) >= 10.0 else "%.2f" % v


## "flight_time_s" -> "Flight time".
static func figure_name(k: String) -> String:
	var parts := k.split("_")
	if parts.size() > 1 and parts[parts.size() - 1] in ["s", "m", "m2", "cm", "px", "pct", "wh"]:
		parts.remove_at(parts.size() - 1)
	var s := " ".join(parts)
	return s.left(1).to_upper() + s.substr(1)


static func unit_text(u: String) -> String:
	return String(u).replace("m2", "m²")


func _line(s: String, ink := DsUi.INK_MUTED) -> Label:
	var l := DsUi.label(s, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1, 0)
	_shown.append(s)
	return l


func render() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_shown = []
	add_child(DsUi.rule())
	add_child(DsUi.section("Result"))
	if result.is_empty():
		add_child(_line("No flight yet."))
		return
	var figs: Dictionary = result.get("figures", {})
	for k in figs:
		var f: Dictionary = figs[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var nm := String(figure_name(k))
		var val := "%s %s" % [_n(float(f["value"])), unit_text(f["unit"])]
		var n := DsUi.label(nm, DsUi.INK_MUTED)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(DsUi.label(val, DsUi.INK))
		row.add_child(DsUi.tag(String(f["tag"]))[0])
		add_child(row)
		_shown.append("%s %s [%s]" % [nm, val, f["tag"]])
		var rng := ""
		if not is_equal_approx(float(f["low"]), float(f["high"])):
			rng = "range %s to %s" % [_n(float(f["low"])), _n(float(f["high"]))]
		elif String(f.get("range", "")) != "" and not String(f["range"]).begins_with("pending"):
			rng = String(f["range"])
		if rng != "":
			add_child(_line(rng, DsUi.INK_FAINT))
	var e := MissionFlow.endurance_check(result)
	add_child(_line("Endurance: " + String(e["line"]), DsUi.INK if e["passes"] else DsUi.WARN))
	var t: Dictionary = result.get("inputs_trail", {})
	if not t.is_empty():
		var w: Variant = t.get("world")
		add_child(_line("Flown: build %s, class %s, world %s, seed %s, model %s" % [String(t["build_fingerprint"]).left(10), t["class_id"],
			(String((w as Dictionary)["id"]) if w != null else "class default"), t["seed"], t["versions"]["model"]], DsUi.INK_FAINT))
	var fields: Dictionary = result.get("params", {}).get("fields", {})
	if not fields.is_empty():
		add_child(DsUi.section("Settings flown"))
		for k in fields:
			var f: Dictionary = fields[k]
			var ui: Array = MissionPicker.FIELD_UI.get(k, [String(k), "", 0, 0, 0, 1])
			var pct: bool = k in MissionPicker.FRACTION_FIELDS
			var u := String(ui[1])
			var x := float(f["value"]) * (100.0 if pct else 1.0)
			var line := "%s %s%s" % [ui[0], MissionFlow._n(x), u]
			if bool(f.get("edited", false)):
				var dflt := float(f["default"]) * (100.0 if pct else 1.0)
				line += ", edited by user (default %s%s, %s)" % [MissionFlow._n(dflt), u, f["default_tag"]]
			else:
				line += ", default (%s)" % f["tag"]
			add_child(_line(line))
