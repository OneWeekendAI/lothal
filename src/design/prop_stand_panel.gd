class_name PropStandPanel
extends VBoxContainer
## The Thrust stand tab (PD9). No second solver: `MotorBench` runs this prop on the chosen motor and
## pack through a real Build, the same law the drone flies by.

const BENCH_PROP_ID := "bench_designed_prop"
const DRONE := "this_drone"
const VIEWS := ["thrust", "current", "efficiency"]
const VIEW_LABELS := ["Thrust", "Current", "g per watt"]
const NO_RUN := "This motor and pack cannot be run."

var shell: PropDesigner
var cfg: MotorConfigs
var view := "thrust"
var motor_pick := DRONE
var pack_pick := DRONE
var result: Dictionary = {}
var limited: Dictionary = {}
var run_count := 0

var motor_option: OptionButton
var pack_option: OptionButton
var view_row: HFlowContainer
var charts: PackCharts
var result_label: Label
var limited_label: Label


func _init(p_shell: PropDesigner) -> void:
	shell = p_shell
	cfg = MotorConfigs.load_default()
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	motor_option = _picker("StandMotor", "Motor", "motor", "This drone's motor", pick_motor)
	pack_option = _picker("StandPack", "Pack", "battery", "This drone's pack", pick_pack)
	view_row = shell._chip_row("StandView", "View_")
	shell._set_chips(view_row, VIEWS, VIEW_LABELS, set_view)
	add_child(view_row)
	charts = PackCharts.new()
	charts.name = "StandChart"
	charts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charts.custom_minimum_size = Vector2(0, 170)
	charts.reveal = 1.0
	add_child(charts)
	result_label = shell._faint("")
	result_label.name = "StandResult"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(result_label)
	limited_label = shell._faint("")
	limited_label.name = "StandLimited"
	limited_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(limited_label)


func _picker(node_name: String, title: String, category: String, first: String, on_pick: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var l := shell._faint(title)
	l.custom_minimum_size = Vector2(48, 0)
	row.add_child(l)
	var opt := OptionButton.new()
	opt.name = node_name
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.clip_text = true
	opt.add_item(first)
	opt.set_item_metadata(0, DRONE)
	for rec in shell.catalog.list_category(category):
		opt.add_item(String(rec.get("name", rec.get("part_id", ""))))
		opt.set_item_metadata(opt.item_count - 1, String(rec.get("part_id", "")))
	opt.item_selected.connect(func(i: int): on_pick.call(String(opt.get_item_metadata(i))))
	row.add_child(opt)
	add_child(row)
	return opt


func pack_ids() -> Array:
	var ids: Array = []
	for i in pack_option.item_count:
		ids.append(String(pack_option.get_item_metadata(i)))
	return ids


func pick_motor(id: String) -> void:
	motor_pick = id
	_show_pick(motor_option, id)
	shell._rederive()


func pick_pack(id: String) -> void:
	pack_pick = id
	_show_pick(pack_option, id)
	shell._rederive()


func _show_pick(opt: OptionButton, id: String) -> void:
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == id:
			opt.select(i)
			return


func set_view(v: Variant) -> void:
	view = String(v)
	shell._rederive()


func motor_record() -> Dictionary:
	return shell.motor if motor_pick == DRONE else shell.catalog.get_part(motor_pick)


## {frame, propeller, battery} ids the run uses. The propeller is this prop, in `bench_catalog`.
func parts() -> Dictionary:
	var battery: String = shell.drone_parts.get("battery", "") if pack_pick == DRONE else pack_pick
	return {"frame": shell.drone_parts.get("frame", ""), "battery": battery, "propeller": BENCH_PROP_ID}


## The shelf with this prop added, on a copy: the drawn blade never reaches the real catalog.
func bench_catalog() -> PartsCatalog:
	var c := PartsCatalog.new()
	c.by_id = shell.catalog.by_id.duplicate()
	c.by_category = shell.catalog.by_category.duplicate()
	c.by_id[BENCH_PROP_ID] = shell.flyable_record(BENCH_PROP_ID)
	return c


func refresh() -> void:
	run_count += 1
	shell._mark_chips(view_row, VIEWS, view)
	var c := bench_catalog()
	result = MotorBench.sweep_of_record(motor_record(), parts(), {}, c)
	if result.is_empty():
		limited = {}
		result_label.text = NO_RUN
		limited_label.text = ""
		charts.set_charts([])
		return
	limited = MotorBench.limited_of_record(motor_record(), cfg, parts(), {}, c)
	result_label.text = String(result.result)
	limited_label.text = String(limited.get("text", ""))
	charts.set_charts([_chart()])


func _per_motor(key: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v: float in result[key]:
		out.append(v / float(result.motors))
	return out


func _chart() -> Dictionary:
	var ink := DesignSpace.INK
	match view:
		"current":
			return {"title": "Current per motor", "x": result.x, "y": _per_motor("current_a"), "y_min": 0.0,
				"y_max": ceilf(float(result.motor_current_a) * 1.1), "unit": " A", "color": ink,
				"x_max": 100.0, "x_end_text": "100 %"}
		"efficiency":
			var y: PackedFloat64Array = (result.gpw as PackedFloat64Array).slice(int(result.gpw_from))
			var top := 0.0
			for v in y:
				top = maxf(top, v)
			return {"title": "g per watt", "x": result.gpw_x, "y": y, "y_min": 0.0, "y_max": ceilf(top * 1.1),
				"unit": " g/W", "color": ink, "x_max": 100.0, "x_end_text": "100 %"}
	return {"title": "Thrust per motor", "x": result.x, "y": _per_motor("thrust_g"), "y_min": 0.0,
		"y_max": ceilf(float(result.motor_thrust_g) * 1.1), "unit": " g", "color": ink,
		"x_max": 100.0, "x_end_text": "100 %"}
