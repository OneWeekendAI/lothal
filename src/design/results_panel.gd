class_name ResultsPanel
extends PanelContainer
## L1.6 the result of a flown mission, shown. set_result(result) keeps the SAME dictionary (no copy); render() writes the text
## from it every time, so the panel can never show a value the result does not hold. Per figure: name, value, range text, tag.
## Then the endurance line, the inputs trail line and the notes on edited fields. Text only, monochrome like the other panels.

const INK := Color(0.93, 0.93, 0.93)

var result: Dictionary = {}
var label: Label


func _init() -> void:
	name = "ResultsPanel"
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", INK)
	add_child(label)


func set_result(r: Dictionary) -> void:
	result = r
	render()


func render() -> void:
	label.text = text_for(result)


func text() -> String:
	return label.text


static func _n(v: float) -> String:
	return "%.2f" % v


static func text_for(r: Dictionary) -> String:
	if r.is_empty():
		return "No flight yet."
	var lines: Array[String] = []
	var figs: Dictionary = r.get("figures", {})
	for k in figs:
		var f: Dictionary = figs[k]
		var rng := ""
		if not is_equal_approx(float(f["low"]), float(f["high"])):
			rng = " (range %s to %s)" % [_n(float(f["low"])), _n(float(f["high"]))]
		else:
			rng = " (%s)" % String(f.get("range", ""))
		lines.append("%s %s %s%s [%s]" % [k, _n(float(f["value"])), f["unit"], rng, f["tag"]])
	lines.append("Endurance: " + String(MissionFlow.endurance_check(r)["line"]))
	var t: Dictionary = r.get("inputs_trail", {})
	if not t.is_empty():
		var w: Variant = t.get("world")
		lines.append("Flown: build %s, class %s, world %s, seed %s, model %s" % [String(t["build_fingerprint"]).left(10), t["class_id"],
			(String((w as Dictionary)["id"]) if w != null else "class default"), t["seed"], t["versions"]["model"]])
	for n in MissionFlow.figure_notes(r):
		lines.append(n)
	return "\n".join(lines)
