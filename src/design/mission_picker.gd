class_name MissionPicker
extends DsDrawer
## L1.5 pick a mission, edit its five settings, pick an environment, then Watch it or Run it headless. A Design Space side
## drawer (DsDrawer) built from the room's own widgets. Settings start at Mission.defaults_for, each with its source tag
## ("estimated" until you change it, then "edited"). Run flies MissionFlow.run for the design given to set_session and shows
## the result in a ResultsPanel under the buttons; Watch only emits watch_requested(opts), the main scene is not wired here.
## The opts carry every setting as shown, so an edit always reaches the flight.

signal watch_requested(opts: Dictionary)
signal run_finished(result: Dictionary)

## key -> [caption, unit, slider min, slider max, slider step, display scale]. Values are kept in the mission's own units
## (an overlap is a fraction); the slider shows it as a percent.
const FIELD_UI := {
	"height_m": ["Height", " m", 5.0, 200.0, 1.0, 1.0],
	"speed_mps": ["Speed", " m/s", 1.0, 30.0, 0.5, 1.0],
	"front_overlap": ["Front overlap", "%", 30.0, 95.0, 1.0, 1.0],
	"side_overlap": ["Side overlap", "%", 30.0, 95.0, 1.0, 1.0],
	"reserve_pct": ["Reserve", "%", 0.0, 60.0, 1.0, 1.0],
}
const FRACTION_FIELDS := ["front_overlap", "side_overlap"]

var session: DesignSession
var extra_opts: Dictionary = {}    ## passed through to MissionRunner unchanged (e.g. capacity_scale)
var mission_list: DsList
var mission_ids: Array[String] = []
var field_boxes := {}              ## key -> DsSlider
var tag_labels := {}               ## key -> Label inside the tag chip
var env_option: DsList
var watch_button: Button
var headless_button: Button
var results: ResultsPanel
var last: Dictionary = {}
var _envs: Array = []
var _env_hint: Label


static func mission_name(id: String) -> String:
	var s := id.replace("_", " ")
	return s.left(1).to_upper() + s.substr(1)


func _init() -> void:
	super("Mission")
	name = "MissionPicker"
	var v := content
	mission_list = DsList.new(true)
	for id in Mission.IDS:
		if id != Mission.TEST_PACK:
			mission_ids.append(id)
			mission_list.add_item(mission_name(id))
	mission_list.item_selected.connect(func(_i: int): refresh_defaults())
	v.add_child(mission_list)
	v.add_child(DsUi.section("Settings"))
	for k in Mission.FIELDS:
		var ui: Array = FIELD_UI[k]
		var scl := 100.0 if k in FRACTION_FIELDS else 1.0
		var sl := DsSlider.new(ui[0], ui[1], float(ui[2]) / scl, float(ui[3]) / scl, float(ui[4]) / scl, scl)
		field_boxes[k] = sl
		tag_labels[k] = sl.tag_label
		sl.value_changed.connect(func(_x: float): _update_tags())
		v.add_child(sl)
	v.add_child(DsUi.section("Environment"))
	_envs = MissionFlow.environments()
	env_option = DsList.new(true, true)
	for e in _envs:
		env_option.add_item(String(e["name"]).replace("_", " ").capitalize())
		env_option.button_at(env_option.item_count - 1).tooltip_text = String(e["tag"])
	env_option.select(-1)
	env_option.item_selected.connect(func(_i: int): _update_env_hint())
	v.add_child(env_option)
	_env_hint = DsUi.label("", DsUi.INK_FAINT)
	v.add_child(_env_hint)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	watch_button = DsUi.button("Watch it", false, true)
	watch_button.tooltip_text = "Fly this mission in the simulator, in view"
	watch_button.pressed.connect(func(): watch_requested.emit(options()))
	br.add_child(watch_button)
	headless_button = DsUi.button("Run")
	headless_button.tooltip_text = "Fly it without drawing it and show the result below"
	headless_button.pressed.connect(run_headless)
	br.add_child(headless_button)
	footer.add_child(br)
	results = ResultsPanel.new()
	results.visible = false
	v.add_child(results)
	mission_list.select(0)
	refresh_defaults()
	_update_env_hint()


func _update_env_hint() -> void:
	_env_hint.text = "Nothing picked: the class's own world" if env_option.selected < 0 else "Location source: %s" % _envs[env_option.selected]["tag"]


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


## Reset every setting to the default of the chosen mission and class.
func refresh_defaults() -> void:
	var d := _defaults()
	if not d["ok"]:
		return
	for k in Mission.FIELDS:
		(field_boxes[k] as DsSlider).value = float(d["fields"][k]["value"])
	_update_tags()


func _shown(k: String, v: float) -> String:
	var ui: Array = FIELD_UI[k]
	var x := v * (100.0 if k in FRACTION_FIELDS else 1.0)
	return ("%d" % int(round(x)) if is_equal_approx(x, round(x)) else "%.1f" % x) + String(ui[1])


func _update_tags() -> void:
	var d := _defaults()
	if not d["ok"]:
		return
	for k in Mission.FIELDS:
		var f: Dictionary = d["fields"][k]
		var box := field_boxes[k] as DsSlider
		var edited := not is_equal_approx(box.value, float(f["value"]))
		(tag_labels[k] as Label).text = "edited, was %s" % _shown(k, float(f["value"])) if edited else String(f["tag"])


func options() -> Dictionary:
	var fields := {}
	for k in Mission.FIELDS:
		fields[k] = (field_boxes[k] as DsSlider).value
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
	results.visible = true
	results.set_result(last["result"])
	run_finished.emit(last["result"])
	_show_result.call_deferred()
	return last


func _show_result() -> void:
	if is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
		scroll.ensure_control_visible(results)
		scroll.scroll_vertical = int(results.position.y - 4.0)
