class_name WorldEditor
extends DsDrawer
## L2.4 the world editor: controls bound to a WorldEditModel, built in code like MissionPicker. Every control only calls a model
## op and then re-reads the model (no second copy of the data); a tag label beside each field shows model.field_tag(path), so a
## field reads "user" once edited. `changed(world)` carries model.result() after each edit. Vertices and obstacles are chosen in a
## list; the fields below edit the selected one. Vertex lat/lon pass through the model's Vector2 (32-bit, about a metre).
## Vertex "add" puts the new vertex a small guessed offset (VERTEX_NUDGE_DEG) from the last one: it is a placeholder to edit.

signal changed(world: World)

const VERTEX_NUDGE_DEG := 0.0001
const NEW_DIMS := {
	"box": {"w": 2.0, "h": 2.0, "d": 2.0, "yaw_deg": 0.0},
	"pole": {"radius": 0.1, "height": 3.0},
	"wall": {"length": 4.0, "height": 2.0, "thickness": 0.2, "yaw_deg": 0.0},
}

var model: WorldEditModel
var preset_option: DsList
var sun_time: LineEdit
var sun_lat: DsStepper
var sun_lon: DsStepper
var wind_speed: DsStepper
var wind_from: DsStepper
var wind_gust: DsStepper
var vertex_list: DsList
var vertex_lat: DsStepper
var vertex_lon: DsStepper
var add_vertex_button: Button
var delete_vertex_button: Button
var obstacle_list: DsList
var obstacle_kind: DsList
var add_obstacle_button: Button
var remove_obstacle_button: Button
var obstacle_fields := {}     ## key -> DsStepper for the selected obstacle
var tag_labels := {}          ## path -> Label (every field)
var _obstacle_box: VBoxContainer
var _busy := false


func _init(p_model: WorldEditModel) -> void:
	super("World")
	name = "WorldEditor"
	# The Field room keeps its list down the left edge; the editor sits just right of it, over the map.
	offset_left = 364.0
	offset_right = 364.0 + WIDTH
	offset_top = 84.0
	offset_bottom = 84.0
	model = p_model
	var v := content
	v.add_child(DsUi.section("Starting point"))
	preset_option = DsList.new(true)
	for id in WorldPresets.IDS:
		preset_option.add_item(String(id).replace("_", " ").capitalize())
	preset_option.select(-1)
	preset_option.item_selected.connect(_on_preset)
	v.add_child(preset_option)
	v.add_child(DsUi.section("Sun"))
	sun_time = LineEdit.new()
	DsUi.style_field(sun_time)
	sun_time.text_submitted.connect(func(_t: String) -> void: _on_sun())
	v.add_child(_row("Time (UTC)", sun_time, "sun.time"))
	sun_lat = _spin(-90.0, 90.0, 0.0001)
	sun_lon = _spin(-180.0, 180.0, 0.0001)
	v.add_child(_row("Latitude", sun_lat, "sun.origin"))
	v.add_child(_row("Longitude", sun_lon, ""))
	v.add_child(DsUi.section("Wind"))
	wind_speed = _spin(0.0, 60.0, 0.001)
	wind_from = _spin(0.0, 360.0, 0.001)
	wind_gust = _spin(0.0, 30.0, 0.001)
	v.add_child(_row("Speed (m/s)", wind_speed, "wind.speed"))
	v.add_child(_row("From (deg)", wind_from, "wind.from"))
	v.add_child(_row("Gust (m/s)", wind_gust, "wind.gust"))
	for sb in [sun_lat, sun_lon]:
		sb.value_changed.connect(func(_x: float) -> void: _on_sun())
	for sb in [wind_speed, wind_from, wind_gust]:
		sb.value_changed.connect(func(_x: float) -> void: _on_wind())
	v.add_child(DsUi.section("Field outline"))
	vertex_list = DsList.new(true)
	vertex_list.item_selected.connect(func(_i: int) -> void: _refresh_vertex_fields())
	v.add_child(vertex_list)
	vertex_lat = _spin(-90.0, 90.0, 0.00001)
	vertex_lon = _spin(-180.0, 180.0, 0.00001)
	vertex_lat.value_changed.connect(func(_x: float) -> void: _on_vertex())
	vertex_lon.value_changed.connect(func(_x: float) -> void: _on_vertex())
	v.add_child(_row("Latitude", vertex_lat, "field.polygon"))
	v.add_child(_row("Longitude", vertex_lon, ""))
	var vb := HBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_vertex_button = DsUi.button("Add vertex")
	add_vertex_button.pressed.connect(_on_add_vertex)
	vb.add_child(add_vertex_button)
	delete_vertex_button = DsUi.button("Delete vertex")
	delete_vertex_button.pressed.connect(_on_delete_vertex)
	vb.add_child(delete_vertex_button)
	v.add_child(vb)
	v.add_child(DsUi.section("Obstacles"))
	obstacle_list = DsList.new(true)
	obstacle_list.item_selected.connect(func(_i: int) -> void: _rebuild_obstacle_fields())
	v.add_child(obstacle_list)
	_obstacle_box = VBoxContainer.new()
	_obstacle_box.add_theme_constant_override("separation", 6)
	v.add_child(_obstacle_box)
	v.add_child(DsUi.label("New obstacle", DsUi.INK_FAINT))
	obstacle_kind = DsList.new(true)
	for k in NEW_DIMS:
		obstacle_kind.add_item(k)
	obstacle_kind.select(0)
	v.add_child(obstacle_kind)
	var ob := HBoxContainer.new()
	ob.add_theme_constant_override("separation", 6)
	add_obstacle_button = DsUi.button("Add obstacle")
	add_obstacle_button.pressed.connect(_on_add_obstacle)
	ob.add_child(add_obstacle_button)
	remove_obstacle_button = DsUi.button("Remove obstacle")
	remove_obstacle_button.pressed.connect(_on_remove_obstacle)
	ob.add_child(remove_obstacle_button)
	v.add_child(ob)
	refresh()


func _spin(lo: float, hi: float, step: float) -> DsStepper:
	return DsStepper.new(lo, hi, step)


## One labelled row; `path` ("" = no tag chip of its own) names the tag shown beside the control.
func _row(label: String, control: Control, path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := DsUi.label(label, DsUi.INK_MUTED)
	l.custom_minimum_size = Vector2(76, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	var t := DsUi.tag("")
	t[0].custom_minimum_size = Vector2(66, 0)
	t[0].modulate.a = 1.0 if path != "" else 0.0
	if path != "":
		tag_labels[path] = t[1]
	row.add_child(t[0])
	return row


## Re-reads everything from the model (no signal is emitted).
func refresh() -> void:
	_busy = true
	var w := model.result()
	sun_time.text = w.utc
	sun_lat.set_value_no_signal(w.origin_lat)
	sun_lon.set_value_no_signal(w.origin_lon)
	wind_speed.set_value_no_signal(w.wind_speed_mps)
	wind_from.set_value_no_signal(w.wind_from_deg)
	wind_gust.set_value_no_signal(w.gustiness_mps)
	var keep := _selected(vertex_list)
	vertex_list.clear()
	for i in model.vertex_count():
		vertex_list.add_item("%d" % (i + 1))
	if model.vertex_count() > 0:
		vertex_list.select(clampi(keep, 0, model.vertex_count() - 1))
	var keep_o := _selected(obstacle_list)
	obstacle_list.clear()
	for i in w.obstacles.size():
		obstacle_list.add_item("%d  %s" % [i + 1, String(w.obstacles[i].kind)])
	if w.obstacles.size() > 0:
		obstacle_list.select(clampi(keep_o, 0, w.obstacles.size() - 1))
	_busy = false
	_refresh_vertex_fields()
	_rebuild_obstacle_fields()


func _selected(list: DsList) -> int:
	var s := list.get_selected_items()
	return s[0] if s.size() > 0 else 0


func _refresh_vertex_fields() -> void:
	_busy = true
	var w := model.result()
	var i := _selected(vertex_list)
	if i < model.vertex_count():
		vertex_lat.set_value_no_signal(w.polygon[2 * i])
		vertex_lon.set_value_no_signal(w.polygon[2 * i + 1])
	delete_vertex_button.disabled = model.vertex_count() <= 3
	_busy = false
	_update_tags()


func _rebuild_obstacle_fields() -> void:
	for c in _obstacle_box.get_children():
		_obstacle_box.remove_child(c)
		c.free()
	for p in tag_labels.keys():
		if String(p).begins_with("obstacle."):
			tag_labels.erase(p)
	obstacle_fields.clear()
	var w := model.result()
	var i := _selected(obstacle_list)
	remove_obstacle_button.disabled = w.obstacles.is_empty()
	if i < w.obstacles.size():
		var o := w.obstacles[i]
		var keys: Array = ["x", "z"]
		keys.append_array(o.dims.keys())
		for k in keys:
			var sb := _spin(-10000.0, 10000.0, 0.001)
			var unit := " (deg)" if String(k).ends_with("deg") else " (m)"
			sb.set_value_no_signal(o.position.x if k == "x" else (o.position.z if k == "z" else float(o.dims[k])))
			var key: String = k
			sb.value_changed.connect(func(x: float) -> void: _on_obstacle_field(key, x))
			obstacle_fields[key] = sb
			_obstacle_box.add_child(_row(String(key).replace("_deg", "").replace("_", " ").capitalize() + unit, sb, "obstacle.%d.%s" % [i, key]))
	_update_tags()


func _update_tags() -> void:
	for path in tag_labels:
		(tag_labels[path] as Label).text = model.field_tag(path)


func _done() -> void:
	_update_tags()
	changed.emit(model.result())


func _on_preset(index: int) -> void:
	if model.set_preset(WorldPresets.IDS[index]):
		refresh()
		changed.emit(model.result())


func _on_sun() -> void:
	if _busy:
		return
	model.set_sun(sun_time.text, sun_lat.value, sun_lon.value)
	_done()


func _on_wind() -> void:
	if _busy:
		return
	model.set_wind(wind_speed.value, wind_from.value, wind_gust.value)
	_done()


func _on_vertex() -> void:
	if _busy:
		return
	var i := _selected(vertex_list)
	if model.move_vertex(i, Vector2(vertex_lat.value, vertex_lon.value)):
		_busy = true
		pass
		_busy = false
		_done()


func _on_add_vertex() -> void:
	var w := model.result()
	var n := model.vertex_count()
	var v := Vector2(w.polygon[2 * n - 2] + VERTEX_NUDGE_DEG, w.polygon[2 * n - 1] + VERTEX_NUDGE_DEG)
	if model.add_vertex(n, v):
		refresh()
		vertex_list.select(n)
		_refresh_vertex_fields()
		changed.emit(model.result())


func _on_delete_vertex() -> void:
	if model.delete_vertex(_selected(vertex_list)):
		refresh()
		changed.emit(model.result())


func _on_add_obstacle() -> void:
	var kind: String = NEW_DIMS.keys()[maxi(obstacle_kind.selected, 0)]
	if model.add_obstacle({"kind": kind, "x": 0.0, "z": 0.0, "dims": (NEW_DIMS[kind] as Dictionary).duplicate()}):
		refresh()
		obstacle_list.select(obstacle_list.item_count - 1)
		_rebuild_obstacle_fields()
		changed.emit(model.result())


func _on_remove_obstacle() -> void:
	if model.remove_obstacle(_selected(obstacle_list)):
		refresh()
		changed.emit(model.result())


func _on_obstacle_field(key: String, value: float) -> void:
	if _busy:
		return
	if model.set_obstacle_field(_selected(obstacle_list), key, value):
		_done()
