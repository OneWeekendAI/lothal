class_name WorldEditor
extends Control
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
var preset_option: OptionButton
var sun_time: LineEdit
var sun_lat: SpinBox
var sun_lon: SpinBox
var wind_speed: SpinBox
var wind_from: SpinBox
var wind_gust: SpinBox
var vertex_list: ItemList
var vertex_lat: SpinBox
var vertex_lon: SpinBox
var add_vertex_button: Button
var delete_vertex_button: Button
var obstacle_list: ItemList
var obstacle_kind: OptionButton
var add_obstacle_button: Button
var remove_obstacle_button: Button
var obstacle_fields := {}     ## key -> SpinBox for the selected obstacle
var tag_labels := {}          ## path -> Label (every field)
var _obstacle_box: VBoxContainer
var _busy := false


func _init(p_model: WorldEditModel) -> void:
	name = "WorldEditor"
	model = p_model
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	preset_option = OptionButton.new()
	for id in WorldPresets.IDS:
		preset_option.add_item(id.replace("_", " "))
	preset_option.select(-1)
	preset_option.item_selected.connect(_on_preset)
	v.add_child(preset_option)
	sun_time = LineEdit.new()
	sun_time.text_submitted.connect(func(_t: String) -> void: _on_sun())
	v.add_child(_row("sun time (UTC)", sun_time, "sun.time"))
	sun_lat = _spin(-90.0, 90.0, 0.0001)
	sun_lon = _spin(-180.0, 180.0, 0.0001)
	v.add_child(_row("sun lat", sun_lat, "sun.origin"))
	v.add_child(_row("sun lon", sun_lon, ""))
	wind_speed = _spin(0.0, 60.0, 0.001)
	wind_from = _spin(0.0, 360.0, 0.001)
	wind_gust = _spin(0.0, 30.0, 0.001)
	v.add_child(_row("wind m/s", wind_speed, "wind.speed"))
	v.add_child(_row("wind from deg", wind_from, "wind.from"))
	v.add_child(_row("gust m/s", wind_gust, "wind.gust"))
	for sb in [sun_lat, sun_lon]:
		sb.value_changed.connect(func(_x: float) -> void: _on_sun())
	for sb in [wind_speed, wind_from, wind_gust]:
		sb.value_changed.connect(func(_x: float) -> void: _on_wind())
	vertex_list = ItemList.new()
	vertex_list.custom_minimum_size = Vector2(0, 80)
	vertex_list.item_selected.connect(func(_i: int) -> void: _refresh_vertex_fields())
	v.add_child(vertex_list)
	vertex_lat = _spin(-90.0, 90.0, 0.00001)
	vertex_lon = _spin(-180.0, 180.0, 0.00001)
	vertex_lat.value_changed.connect(func(_x: float) -> void: _on_vertex())
	vertex_lon.value_changed.connect(func(_x: float) -> void: _on_vertex())
	v.add_child(_row("vertex lat", vertex_lat, "field.polygon"))
	v.add_child(_row("vertex lon", vertex_lon, ""))
	var vb := HBoxContainer.new()
	add_vertex_button = Button.new()
	add_vertex_button.text = "Add vertex"
	add_vertex_button.pressed.connect(_on_add_vertex)
	vb.add_child(add_vertex_button)
	delete_vertex_button = Button.new()
	delete_vertex_button.text = "Delete vertex"
	delete_vertex_button.pressed.connect(_on_delete_vertex)
	vb.add_child(delete_vertex_button)
	v.add_child(vb)
	obstacle_list = ItemList.new()
	obstacle_list.custom_minimum_size = Vector2(0, 80)
	obstacle_list.item_selected.connect(func(_i: int) -> void: _rebuild_obstacle_fields())
	v.add_child(obstacle_list)
	_obstacle_box = VBoxContainer.new()
	v.add_child(_obstacle_box)
	var ob := HBoxContainer.new()
	obstacle_kind = OptionButton.new()
	for k in NEW_DIMS:
		obstacle_kind.add_item(k)
	ob.add_child(obstacle_kind)
	add_obstacle_button = Button.new()
	add_obstacle_button.text = "Add obstacle"
	add_obstacle_button.pressed.connect(_on_add_obstacle)
	ob.add_child(add_obstacle_button)
	remove_obstacle_button = Button.new()
	remove_obstacle_button.text = "Remove obstacle"
	remove_obstacle_button.pressed.connect(_on_remove_obstacle)
	ob.add_child(remove_obstacle_button)
	v.add_child(ob)
	refresh()


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.allow_greater = true
	sb.allow_lesser = true
	return sb


## One labelled row; `path` ("" = no tag label of its own) names the tag shown beside the control.
func _row(label: String, control: Control, path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	row.add_child(control)
	if path != "":
		var t := Label.new()
		t.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		row.add_child(t)
		tag_labels[path] = t
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
		vertex_list.add_item("%d: %.5f, %.5f" % [i, w.polygon[2 * i], w.polygon[2 * i + 1]])
	if model.vertex_count() > 0:
		vertex_list.select(clampi(keep, 0, model.vertex_count() - 1))
	var keep_o := _selected(obstacle_list)
	obstacle_list.clear()
	for i in w.obstacles.size():
		obstacle_list.add_item("%d: %s" % [i, String(w.obstacles[i].kind)])
	if w.obstacles.size() > 0:
		obstacle_list.select(clampi(keep_o, 0, w.obstacles.size() - 1))
	_busy = false
	_refresh_vertex_fields()
	_rebuild_obstacle_fields()


func _selected(list: ItemList) -> int:
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
			sb.set_value_no_signal(o.position.x if k == "x" else (o.position.z if k == "z" else float(o.dims[k])))
			var key: String = k
			sb.value_changed.connect(func(x: float) -> void: _on_obstacle_field(key, x))
			obstacle_fields[key] = sb
			_obstacle_box.add_child(_row("obstacle " + key, sb, "obstacle.%d.%s" % [i, key]))
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
		vertex_list.set_item_text(i, "%d: %.5f, %.5f" % [i, vertex_lat.value, vertex_lon.value])
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
	var kind := obstacle_kind.get_item_text(maxi(obstacle_kind.selected, 0))
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
