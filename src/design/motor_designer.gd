class_name MotorDesigner
extends DesignerShell
## The motor designer: a pop-up over the Design Space, opened from the "Design your own" tile at
## the end of the Motor shelf. The pack designer's shell (DesignerShell), with three columns.
## Left: 1 Stator (a size on the standard grid), 2 KV (only the options sold for that size),
## 3 Poles & bell (pole config, magnet grade, shaft, mount). Middle: the motor in 3D, drawn from
## its stator and bell dimensions, with a class-typical prop on it. Right: the derived figures,
## then the bench (Throttle sweep, Hover soak, Punch-out: one run at a time, drawn in over about
## three seconds by the pack designer's chart widget, PackCharts, and then left standing).
##
## DERIVED, NOT TYPED. Every figure comes from MotorDesign.derive() (the grid laws in
## MotorConfigs); nothing in the figures column is editable. Every setter ends in _rederive(), so
## any change shows at once.

## A motor was saved to the shelf (custom_parts.json) under this id.
signal saved(part_id: String)

const LEFT_W := 300.0
const RIGHT_W := 440.0
const REVEAL_S := 3.0
const BENCH_TABS := {"sweep": "Throttle sweep", "soak": "Hover soak", "punch": "Punch-out"}
const BENCH_NOTE := "ideal / model. Current reads high until the prop chapter."
const FIGURE_ROWS := ["kv", "kt", "rm_ohm", "io_a", "mass_g", "max_current_a", "max_power_w", "magnet_max_c"]

var cfg: MotorConfigs
var catalog: PartsCatalog
var design: MotorDesign
var derive_count := 0
var prop_id := ""
## Where saved motors live (the shelf reloads from the same file).
var store: CustomMotors
var store_path: String = CustomParts.SAVE_PATH
## The saved motor being edited; "" for a new design (Save then makes a new one).
var part_id := ""
## The id armed for deletion by a first request (empty when none).
var pending_delete := ""

var _figs: Dictionary = {}
var _figure_values := {}

# Controls.
var copy_button: Button
var save_button: Button
var save_as_button: Button
var size_label: Label
var size_note: Label
var kv_row: HFlowContainer
var kv_note: Label
var poles_row: HFlowContainer
var magnet_row: HFlowContainer
var shaft_option: OptionButton
var mount_option: OptionButton
var motor_view: MotorView3D
var summary_label: Label
var figures_box: GridContainer
var bench_box: PanelContainer
## The bench: which run is showing, the prop and pack it runs on ({frame, propeller, battery} ids;
## missing keys are the reference build's), and the last run.
var bench_kind := "sweep"
var bench_parts: Dictionary = {}
var charts: PackCharts
var bench_result_label: Label
var bench_warning_label: Label
var _bench_tabs := {}
var _bench: Dictionary = {}
var _bench_tween: Tween


func _init(p_cfg: MotorConfigs = null, p_catalog: PartsCatalog = null, p_store: CustomMotors = null) -> void:
	cfg = p_cfg if p_cfg != null else MotorConfigs.load_default()
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	store = p_store if p_store != null else CustomMotors.new()
	_init_shell("MotorDesigner")
	design = MotorDesign.default_design(cfg)
	_build_shell(_build_top_bar(), _build_left(), _build_middle(), _build_right())
	_rederive()


# ---------------------------------------------------------------------------
# Opening, saving, deleting (the pack designer's path: CustomParts.put_record)
# ---------------------------------------------------------------------------

## A fresh default motor (2207 at 1960 KV).
func open_new() -> void:
	design = MotorDesign.default_design(cfg)
	part_id = ""
	_rederive()


## A saved motor, to edit. A designed one reopens under its id; a migrated hand-typed one opens on
## the nearest grid point as a NEW design, so saving never overwrites the figures that were typed.
func open_motor(p_part_id: String) -> void:
	var rec := store.get_record(p_part_id)
	if rec.is_empty():
		open_new()
		return
	design = MotorDesign.from_record(rec, cfg)
	part_id = "" if CustomMotors.is_legacy(rec) else p_part_id
	_rederive()


## Saves under the current id (a new motor gets one). "" when refused.
func save() -> String:
	var typed := name_field.text.strip_edges()
	if typed != "":
		design.name = typed
	var id := store.save_design(design, cfg, catalog, part_id)
	if id == "":
		return ""
	part_id = id
	saved.emit(id)
	_refresh()
	return id


## A new motor from this design, never touching the one it was opened from. With the name unchanged
## it is saved as "<name> copy".
func save_as() -> String:
	var copy_name := name_field.text.strip_edges()
	if part_id != "" and (copy_name == "" or copy_name == String(store.get_record(part_id).get("name", ""))):
		copy_name = "%s copy" % (design.display_name() if copy_name == "" else copy_name)
	if copy_name != "":
		design.name = copy_name
	var id := store.save_as(design, cfg, catalog)
	if id == "":
		return ""
	part_id = id
	saved.emit(id)
	_refresh()
	return id


## Deletes a saved motor. The first call for an id only arms it (false); the second deletes it.
## Shelf presets are never deletable.
func request_delete(id: String) -> bool:
	if id == "" or not PartsCatalog.is_custom(id):
		pending_delete = ""
		return false
	if pending_delete != id:
		pending_delete = id
		return false
	pending_delete = ""
	if not store.delete(id):
		return false
	if part_id == id:
		part_id = ""
	return true


# ---------------------------------------------------------------------------
# Choices (each re-derives at once)
# ---------------------------------------------------------------------------

func set_motor_name(p_name: String) -> void:
	design.name = p_name.strip_edges()
	_rederive()


func set_stator(stator: String) -> bool:
	var ok := design.set_size(cfg, stator)
	if ok:
		_rederive()
	return ok


func step_size(dir: int) -> bool:
	var ok := design.step_size(cfg, dir)
	if ok:
		_rederive()
	return ok


func set_kv(kv: float) -> bool:
	var ok := design.set_kv(cfg, kv)
	_rederive()
	return ok


func set_poles(poles: int) -> bool:
	var ok := design.set_poles(poles)
	_rederive()
	return ok


func set_magnet(grade: String) -> bool:
	var ok := design.set_magnet(cfg, grade)
	_rederive()
	return ok


func set_shaft(mm: float) -> bool:
	var ok := design.set_shaft(cfg, mm)
	_rederive()
	return ok


func set_mount(pattern: String) -> bool:
	var ok := design.set_mount(cfg, pattern)
	_rederive()
	return ok


func figures() -> Dictionary:
	return _figs


## Shows one of the three bench runs ("sweep", "soak", "punch") and plays it.
func set_bench(kind: String) -> void:
	bench_kind = kind if MotorBench.KINDS.has(kind) else "sweep"
	_run_bench()
	_refresh_bench()
	_play_reveal()


## The prop and pack the bench runs on: the fitted build's frame, prop and pack, if there is one.
func set_bench_build(b: Build) -> void:
	bench_parts = {}
	if b != null:
		bench_parts = {"frame": String(b.frame.get("part_id", "")),
			"propeller": String(b.propeller.get("part_id", "")),
			"battery": String(b.battery.get("part_id", ""))}
	_rederive()


## The last bench run (see MotorBench.run), {} if the motor cannot be flown.
func bench_result() -> Dictionary:
	return _bench


## The warning lines under the chart now, one per problem.
func bench_warnings() -> Array:
	return _bench.get("warnings", [])


## The text the figures column shows for `key` (what a builder reads).
func figure_text(key: String) -> String:
	var l: Label = _figure_values.get(key)
	return l.text if l != null else ""


## The KV values offered on screen right now, read from the chips (not from the model).
func kv_on_screen() -> Array:
	var out: Array = []
	for b in kv_row.get_children():
		out.append(float(b.get_meta("option")))
	return out


## A short plain-text spec list, put on the clipboard. The full buy-and-build sheet comes later.
func copy_specs() -> String:
	var lines := PackedStringArray()
	lines.append(design.display_name())
	lines.append("%s stator, %d KV, %s, %s magnets, %.1f mm shaft, mount %s" % [design.size,
		int(design.kv), design.config(), design.magnet, design.shaft_mm, design.mount])
	for key in FIGURE_ROWS:
		lines.append("%s: %s (%s)" % [_figure_name(key), _format(key), MotorDesign.figure_tags()[key]])
	lines.append("All figures %s." % MotorDesign.BASIS)
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	return text


func _rederive() -> void:
	_figs = design.derive(cfg)
	derive_count += 1
	_run_bench()
	_refresh()
	_play_reveal()


func _run_bench() -> void:
	_bench = MotorBench.run(bench_kind, design, cfg, bench_parts, {}, catalog)


## The chart draws in over REVEAL_S and then stays. Outside the tree there is no animation to play.
func _play_reveal() -> void:
	if _bench_tween != null and _bench_tween.is_valid():
		_bench_tween.kill()
	if charts == null:
		return
	if not is_inside_tree():
		charts.reveal = 1.0
		return
	charts.reveal = 0.0
	_bench_tween = create_tween()
	_bench_tween.tween_property(charts, "reveal", 1.0, REVEAL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Screen
# ---------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := _top_bar_start("Motor name", set_motor_name)
	bar.add_child(_fill())
	copy_button = _bar_button("CopySpecs", "Copy specs", func(): copy_specs(),
		"Copy this motor's choices and figures as text")
	bar.add_child(copy_button)
	# Only while editing a saved motor: a copy under a new name instead of an overwrite.
	save_as_button = _bar_button("SaveAs", "Save as new", func(): save_as(),
		"Save a copy under the name above, leaving the saved motor as it is")
	save_as_button.visible = false
	bar.add_child(save_as_button)
	save_button = _bar_button("Save", "Save to shelf", func(): save(),
		"Save this motor to the Motor shelf under the name above")
	bar.add_child(save_button)
	return bar


func _build_left() -> Control:
	var out := []
	var scroll := _left_column(LEFT_W, out)
	var col: VBoxContainer = out[0]

	col.add_child(_section("1 · Stator"))
	size_label = _add_stepper(col, "Size", "Stator size", "stator diameter and height, in mm",
		func(): step_size(-1), func(): step_size(1), 64.0)
	size_note = _faint("")
	size_note.name = "SizeNote"
	col.add_child(size_note)

	col.add_child(_spacer(LothalTheme.SPACE_1))
	col.add_child(_section("2 · KV"))
	kv_row = _chip_row("KVOptions", "KV_")
	col.add_child(kv_row)
	kv_note = _faint("")
	kv_note.name = "KVNote"
	col.add_child(kv_note)

	col.add_child(_spacer(LothalTheme.SPACE_1))
	col.add_child(_section("3 · Poles & bell"))
	poles_row = _chip_row("Poles", "Poles_")
	var pole_opts := MotorConfigs.POLE_CONFIGS.keys()
	pole_opts.sort()
	var pole_labels := pole_opts.map(func(p): return String(MotorConfigs.POLE_CONFIGS[p]))
	_set_chips(poles_row, pole_opts, pole_labels, func(p): set_poles(int(p)))
	_tag_options(poles_row, pole_opts)
	col.add_child(_labelled("Poles", poles_row))
	magnet_row = _chip_row("Magnet", "Magnet_")
	var grades := cfg.magnets().map(func(m): return String(m.get("grade", "")))
	_set_chips(magnet_row, grades, grades, func(g): set_magnet(String(g)))
	_tag_options(magnet_row, grades)
	col.add_child(_labelled("Magnet", magnet_row))
	shaft_option = OptionButton.new()
	shaft_option.name = "Shaft"
	shaft_option.item_selected.connect(func(i: int):
		if not _syncing: set_shaft(float(shaft_option.get_item_metadata(i))))
	col.add_child(_labelled("Shaft", shaft_option))
	mount_option = OptionButton.new()
	mount_option.name = "Mount"
	mount_option.item_selected.connect(func(i: int):
		if not _syncing: set_mount(mount_option.get_item_text(i)))
	col.add_child(_labelled("Mount", mount_option))
	col.add_child(_faint("The magnet grade sets how hot the motor may run before its magnets weaken."))
	return scroll


func _build_middle() -> Control:
	var col := _middle_column()
	motor_view = MotorView3D.new()
	col.add_child(motor_view)
	summary_label = Label.new()
	summary_label.name = "Summary"
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
	summary_label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(summary_label)
	var prop_note := _faint("")
	prop_note.name = "PropNote"
	prop_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(prop_note)
	return col


func _build_right() -> Control:
	var col := _right_column(RIGHT_W)
	var header := Label.new()
	header.name = "FiguresHeader"
	header.text = "Motor figures   ·   %s" % MotorDesign.BASIS
	header.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	header.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(header)
	figures_box = _figure_grid(FIGURE_ROWS, _figure_name, _figure_values)
	col.add_child(figures_box)
	col.add_child(_spacer(LothalTheme.SPACE_2))

	bench_box = PanelContainer.new()
	bench_box.name = "Bench"
	bench_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(1, 1, 1, 0.02)
	edge.border_color = Color(1, 1, 1, 0.10)
	edge.set_border_width_all(1)
	edge.set_corner_radius_all(LothalTheme.RADIUS_PANEL)
	edge.set_content_margin_all(LothalTheme.SPACE_2)
	bench_box.add_theme_stylebox_override("panel", edge)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	for kind in MotorBench.KINDS:
		var tb := Button.new()
		tb.name = "Tab_" + kind
		tb.text = BENCH_TABS[kind]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func(): set_bench(kind))
		tabs.add_child(tb)
		_bench_tabs[kind] = tb
	inner.add_child(tabs)
	bench_result_label = Label.new()
	bench_result_label.name = "Result"
	bench_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bench_result_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	bench_result_label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	inner.add_child(bench_result_label)
	charts = PackCharts.new()
	inner.add_child(charts)
	bench_warning_label = Label.new()
	bench_warning_label.name = "Warnings"
	bench_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bench_warning_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	bench_warning_label.add_theme_color_override("font_color", LothalTheme.WARNING)
	inner.add_child(bench_warning_label)
	var note := _faint(BENCH_NOTE)
	note.name = "BenchNote"
	inner.add_child(note)
	bench_box.add_child(inner)
	col.add_child(bench_box)
	return col


static func _figure_name(key: String) -> String:
	match key:
		"kv": return "KV"
		"kt": return "Kt"
		"rm_ohm": return "Resistance"
		"io_a": return "No-load"
		"mass_g": return "Mass"
		"max_current_a": return "Max current"
		"max_power_w": return "Max power"
		"magnet_max_c": return "Heat limit"
	return key


func _format(key: String) -> String:
	if _figs.is_empty():
		return "—"
	var f := _figs
	match key:
		"kv":
			return "%d KV" % int(f.kv)
		"kt":
			return "%.2f mN·m/A" % (float(f.kt) * 1000.0)
		"rm_ohm":
			var r := float(f.rm_ohm)
			return "%.2f Ω" % r if r >= 1.0 else "%.0f mΩ" % (r * 1000.0)
		"io_a":
			return "%.2f A at %s V" % [float(f.io_a), _num(float(f.io_voltage_v))]
		"mass_g":
			return "%.1f g" % float(f.mass_g)
		"max_current_a":
			return "%.1f A continuous" % float(f.max_current_a)
		"max_power_w":
			return "%d W on %dS" % [int(round(float(f.max_power_w))), int(f.max_cells)]
		"magnet_max_c":
			return "%d °C  (%s)" % [int(f.magnet_max_c), String(f.magnet)]
	return ""


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v


func _tag_options(row: HFlowContainer, options: Array) -> void:
	var kids := row.get_children()
	for i in mini(kids.size(), options.size()):
		kids[i].set_meta("option", options[i])


func _refresh() -> void:
	_syncing = true
	if name_field.text != design.name:
		name_field.text = design.name
	name_field.placeholder_text = design.default_name()
	var row := cfg.get_size(design.size)
	size_label.text = design.size
	size_note.text = "%s × %s mm stator  ·  flown up to %dS" % [_num(float(row.stator_diameter_mm)),
		_num(float(row.stator_height_mm)), int(row.max_cells)]

	var kvs := design.kv_choices(cfg)
	if kv_on_screen() != kvs.map(func(k): return float(k)):
		_set_chips(kv_row, kvs, kvs.map(func(k): return str(int(k))), func(k): set_kv(float(k)))
		_tag_options(kv_row, kvs.map(func(k): return float(k)))
	_mark_chips(kv_row, kvs, design.kv)
	kv_note.text = "The KV values sold for a %s." % design.size
	var pole_opts := MotorConfigs.POLE_CONFIGS.keys()
	pole_opts.sort()
	_mark_chips(poles_row, pole_opts, design.poles)
	_mark_chips(magnet_row, cfg.magnets().map(func(m): return String(m.get("grade", ""))), design.magnet)

	shaft_option.clear()
	for mm in cfg.shaft_options(design.size):
		shaft_option.add_item("%s mm" % _num(float(mm)))
		shaft_option.set_item_metadata(shaft_option.item_count - 1, float(mm))
		if is_equal_approx(float(mm), design.shaft_mm):
			shaft_option.select(shaft_option.item_count - 1)
	shaft_option.disabled = shaft_option.item_count < 2
	mount_option.clear()
	for m in cfg.mount_options(design.size):
		mount_option.add_item(String(m))
		if String(m) == design.mount:
			mount_option.select(mount_option.item_count - 1)
	mount_option.disabled = mount_option.item_count < 2

	var tags := MotorDesign.figure_tags()
	for key in FIGURE_ROWS:
		(_figure_values[key] as Label).text = _format(key)
		(_figure_values[key + "_tag"] as Label).text = String(tags.get(key, ""))
	summary_label.text = "%s  ·  %d KV  ·  %s" % [design.size, int(design.kv), design.config()]
	_refresh_bench()
	save_as_button.visible = part_id != ""
	save_button.text = "Save changes" if part_id != "" else "Save to shelf"
	_syncing = false
	_refresh_view()


func _refresh_bench() -> void:
	if charts == null:
		return
	for kind in _bench_tabs:
		(_bench_tabs[kind] as Button).set_pressed_no_signal(kind == bench_kind)
	var r := _bench
	if r.is_empty():
		bench_result_label.text = ""
		bench_warning_label.text = ""
		charts.set_charts([])
		return
	bench_result_label.text = String(r.result)
	bench_warning_label.text = "\n".join(r.warnings)
	bench_warning_label.visible = not r.warnings.is_empty()
	var x: PackedFloat64Array = r.x
	match String(r.kind):
		"soak":
			var ta := _temp_axis(r)
			charts.set_charts([{"title": "Winding temperature", "x": x, "y": r.temp_c,
				"y_min": ta.x, "y_max": ta.y, "unit": " °C", "color": LothalTheme.WARNING,
				"x_max": MotorBench.SOAK_S}])
		"punch":
			var ta2 := _temp_axis(r)
			var floor_v := floorf(float(r.low_v) - 1.0)
			charts.set_charts([
				{"title": "Winding temperature", "x": x, "y": r.temp_c, "y_min": ta2.x, "y_max": ta2.y,
					"unit": " °C", "color": LothalTheme.WARNING, "x_max": MotorBench.PUNCH_S},
				{"title": "Pack voltage", "x": x, "y": r.v_live, "y_min": floor_v,
					"y_max": ceilf(float(r.start_v) + 0.5), "unit": " V", "color": LothalTheme.ACCENT,
					"x_max": MotorBench.PUNCH_S}])
		_:
			charts.set_charts([
				{"title": "Thrust", "x": x, "y": r.thrust_g, "y_min": 0.0,
					"y_max": _ceil_nice(float(r.max_thrust_g)), "unit": " g", "color": LothalTheme.ACCENT,
					"x_max": 100.0, "x_end_text": "100 %"},
				{"title": "Current", "x": x, "y": r.current_a, "y_min": 0.0,
					"y_max": _ceil_nice(float(r.max_current_a)), "unit": " A", "color": LothalTheme.WARNING,
					"x_max": 100.0, "x_end_text": "100 %"},
				{"title": "g per watt", "x": r.gpw_x, "y": r.gpw.slice(int(r.gpw_from)), "y_min": 0.0,
					"y_max": _ceil_nice(_max_of(r.gpw)), "unit": " g/W", "color": LothalTheme.SUCCESS,
					"x_max": 100.0, "x_end_text": "100 %"}])


## Temperature chart range: ambient up to the run's peak or the magnet limit, with room above.
func _temp_axis(r: Dictionary) -> Vector2:
	var top := maxf(float(r.peak_temp_c), float(_figs.magnet_max_c)) + 5.0
	return Vector2(20.0, ceilf(top / 10.0) * 10.0)


static func _max_of(a: PackedFloat64Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


## Rounds up to 1, 2 or 5 times a power of ten, so axis ends read as plain numbers.
static func _ceil_nice(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var mag := pow(10.0, floorf(log(v) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if v <= m * mag:
			return m * mag
	return 10.0 * mag


func _refresh_view() -> void:
	var prop := _usual_prop(float(cfg.get_size(design.size).stator_diameter_mm))
	prop_id = String(prop.get("part_id", ""))
	motor_view.show_motor(design.to_record(cfg), prop)
	var note := find_child("PropNote", true, false) as Label
	if note != null:
		note.text = ("Shown with a %s prop" % String(prop.get("name", ""))) if not prop.is_empty() else ""


## The shelf prop nearest the size's usual diameter (the picture only; thrust needs the bench).
func _usual_prop(stator_diameter_mm: float) -> Dictionary:
	var want := MotorDesign.usual_prop_inches(stator_diameter_mm)
	var best: Dictionary = {}
	var best_d := INF
	for p in catalog.list_category("propeller"):
		if PartsCatalog.is_custom(String(p.get("part_id", ""))):
			continue
		var d := absf(float((p.get("specs", {}) as Dictionary).get("diameter_inches", 0.0)) - want)
		if d < best_d:
			best_d = d
			best = p
	return best
