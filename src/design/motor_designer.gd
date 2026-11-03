class_name MotorDesigner
extends DesignerShell
## The motor designer: a pop-up over the Design Space, opened from the "Design your own" tile at
## the end of the Motor shelf. The pack designer's shell (DesignerShell), with three columns.
## Left: 1 Stator (a size on the standard grid), 2 KV (only the options sold for that size),
## 3 Poles & bell (pole config, magnet grade, shaft, mount). Middle: the motor in 3D, drawn from
## its stator and bell dimensions, with a class-typical prop on it. Right: the derived figures,
## then the bench (a placeholder until the bench runs exist).
##
## DERIVED, NOT TYPED. Every figure comes from MotorDesign.derive() (the grid laws in
## MotorConfigs); nothing in the figures column is editable. Every setter ends in _rederive(), so
## any change shows at once.

## A motor was saved to the shelf (custom_parts.json) under this id.
signal saved(part_id: String)

const LEFT_W := 300.0
const RIGHT_W := 440.0
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
	_refresh()


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

	# The bench (throttle sweep, hover soak, punch-out) arrives in its own piece; this keeps its place.
	bench_box = PanelContainer.new()
	bench_box.name = "BenchPlaceholder"
	bench_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(1, 1, 1, 0.02)
	edge.border_color = Color(1, 1, 1, 0.10)
	edge.set_border_width_all(1)
	edge.set_corner_radius_all(LothalTheme.RADIUS_PANEL)
	edge.set_content_margin_all(LothalTheme.SPACE_3)
	bench_box.add_theme_stylebox_override("panel", edge)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	inner.add_child(_section("Bench"))
	inner.add_child(_faint("Thrust, current and heat need a prop and a pack. The throttle sweep, hover soak and punch-out runs will sit here."))
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
	save_as_button.visible = part_id != ""
	save_button.text = "Save changes" if part_id != "" else "Save to shelf"
	_syncing = false
	_refresh_view()


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
