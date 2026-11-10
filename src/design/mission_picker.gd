class_name MissionPicker
extends PanelContainer
## L1.5 pick a mission, edit its five fields, pick an environment, then Watch or fly it Headless. Built in code like the other
## Design Space panels. Fields start at Mission.defaults_for (tag shown beside each, "estimated" until you change it). Headless runs
## MissionFlow.run for the design given to set_session and shows the result in a ResultsPanel; Watch only emits watch_requested(opts),
## the main scene is not wired here. The opts carry every field as shown, so an edit always reaches the flight.

signal watch_requested(opts: Dictionary)
signal run_finished(result: Dictionary)

const FIELD_STEP := {"front_overlap": 0.01, "side_overlap": 0.01}

var session: DesignSession
var extra_opts: Dictionary = {}    ## passed through to MissionRunner unchanged (e.g. capacity_scale)
var mission_list: ItemList
var mission_ids: Array[String] = []
var field_boxes := {}
var tag_labels := {}
var env_option: OptionButton
var watch_button: Button
var headless_button: Button
var results: ResultsPanel
var last: Dictionary = {}
var _envs: Array = []


func _init() -> void:
	name = "MissionPicker"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	mission_list = ItemList.new()
	mission_list.custom_minimum_size = Vector2(0, 100)
	for id in Mission.IDS:
		if id != Mission.TEST_PACK:
			mission_ids.append(id)
			mission_list.add_item(id.replace("_", " "))
	mission_list.item_selected.connect(func(_i: int): refresh_defaults())
	v.add_child(mission_list)
	for k in Mission.FIELDS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = k
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = 0.0
		sb.max_value = 10000.0
		sb.step = FIELD_STEP.get(k, 0.5)
		sb.allow_greater = true
		row.add_child(sb)
		var t := Label.new()
		t.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		row.add_child(t)
		field_boxes[k] = sb
		tag_labels[k] = t
		sb.value_changed.connect(func(_x: float): _update_tags())
		v.add_child(row)
	env_option = OptionButton.new()
	_envs = MissionFlow.environments()
	for e in _envs:
		env_option.add_item("%s (%s)" % [e["name"], e["tag"]])
	env_option.select(-1)
	v.add_child(env_option)
	var br := HBoxContainer.new()
	watch_button = Button.new()
	watch_button.text = "Watch"
	watch_button.pressed.connect(func(): watch_requested.emit(options()))
	br.add_child(watch_button)
	headless_button = Button.new()
	headless_button.text = "Headless"
	headless_button.pressed.connect(run_headless)
	br.add_child(headless_button)
	v.add_child(br)
	results = ResultsPanel.new()
	v.add_child(results)
	mission_list.select(0)
	refresh_defaults()


func set_session(s: DesignSession) -> void:
	session = s
	refresh_defaults()


func mission_id() -> String:
	var sel := mission_list.get_selected_items()
	return mission_ids[sel[0]] if not sel.is_empty() else mission_ids[0]


func _class_id() -> String:
	return session.drone_class if session != null else "five_inch"


func _defaults() -> Dictionary:
	return Mission.defaults_for(_class_id(), mission_id())


## Reset every field to the default of the chosen mission and class.
func refresh_defaults() -> void:
	var d := _defaults()
	if not d["ok"]:
		return
	for k in Mission.FIELDS:
		(field_boxes[k] as SpinBox).set_value_no_signal(float(d["fields"][k]["value"]))
	_update_tags()


func _update_tags() -> void:
	var d := _defaults()
	if not d["ok"]:
		return
	for k in Mission.FIELDS:
		var f: Dictionary = d["fields"][k]
		var edited := not is_equal_approx((field_boxes[k] as SpinBox).value, float(f["value"]))
		(tag_labels[k] as Label).text = "user (default %s, %s)" % [f["value"], f["tag"]] if edited else String(f["tag"])


func options() -> Dictionary:
	var fields := {}
	for k in Mission.FIELDS:
		fields[k] = (field_boxes[k] as SpinBox).value
	var o := extra_opts.duplicate()
	o["mission"] = mission_id()
	o["fields"] = fields
	var i := env_option.selected
	if i >= 0:
		o["world"] = WorldPresets.by_id(String(_envs[i]["id"]))
	return o


func run_headless() -> Dictionary:
	if session == null:
		return {}
	last = MissionFlow.run(session, options())
	results.set_result(last["result"])
	run_finished.emit(last["result"])
	return last
