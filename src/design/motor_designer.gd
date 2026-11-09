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

## The motor designer asks to open the pack designer; the screen that hosts it opens one and, when
## a pack is saved, calls `select_pack` with the new id.
signal design_pack_requested

const LEFT_W := 300.0
const RIGHT_W := 440.0
const REVEAL_S := 3.0
const BENCH_TABS := {"sweep": "Throttle sweep", "soak": "Hover soak", "punch": "Punch-out"}
const DRONE_PACK := "this_drone"
const DESIGN_PACK_ITEM := "design_a_pack"
const BENCH_NOTE := "ideal / model"
## The compare motor's line: a lighter ink than the chosen motor's.
const COMPARE_INK := Color(0.62, 0.64, 0.68)
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
## The "Details" toggle under the warnings: only the two most severe show until it is open.
var warn_details_button: Button
var warn_details_open := false
const WARNINGS_SHOWN := 2
var pack_option: OptionButton
var prop_option: OptionButton
## "Compare with…": another motor on the same pack and prop, a second line on the throttle sweep.
var compare_option: OptionButton
var compare_row: HBoxContainer
var compare_id := ""
var _compare: Dictionary = {}
var limited_label: Label
## The sweep shows ONE chart: thrust, or (behind the two small toggles) current or g/W.
const SWEEP_VIEWS := ["thrust", "current", "efficiency"]
var sweep_view := "thrust"
var _view_buttons := {}
## "x4 = ... in total", small, under the per-motor result line.
var bench_total_label: Label
var save_text_button: Button
var _specs_dialog: FileDialog
var _drone_parts: Dictionary = {}
var _limited: Dictionary = {}
var _bench_tabs := {}
var _bench: Dictionary = {}
var _bench_tween: Tween


func _init(p_cfg: MotorConfigs = null, p_catalog: PartsCatalog = null, p_store: CustomMotors = null) -> void:
	cfg = p_cfg if p_cfg != null else MotorConfigs.load_default()
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	store = p_store if p_store != null else CustomMotors.new()
	_init_shell("MotorDesigner")
	theme = mono_theme()
	design = MotorDesign.default_design(cfg)
	_build_shell(_build_top_bar(), _build_left(), _build_middle(), _build_right())
	_fill_pickers()
	_rederive()


# ---------------------------------------------------------------------------
# Palette: monochrome like the rest of the Design Space; amber only for warnings
# ---------------------------------------------------------------------------

## The app theme with its blue accent turned into the Design Space's ink (selected tab, chip,
## focus ring, menu highlight): same alphas, no hue. Amber is left to warnings.
static func mono_theme() -> Theme:
	var t := LothalTheme.get_theme().duplicate() as Theme
	var accent := LothalTheme.ACCENT
	for cls in t.get_type_list():
		for sb_name in t.get_stylebox_list(cls):
			var sb := t.get_stylebox(sb_name, cls)
			if sb is StyleBoxFlat:
				var flat := sb.duplicate() as StyleBoxFlat
				flat.bg_color = _ink_for(flat.bg_color, accent)
				flat.border_color = _ink_for(flat.border_color, accent)
				t.set_stylebox(sb_name, cls, flat)
		for c_name in t.get_color_list(cls):
			t.set_color(c_name, cls, _ink_for(t.get_color(c_name, cls), accent))
	return t


static func _ink_for(c: Color, accent: Color) -> Color:
	if absf(c.r - accent.r) < 0.01 and absf(c.g - accent.g) < 0.01 and absf(c.b - accent.b) < 0.01:
		return Color(DesignSpace.INK, c.a)
	return c


## A chart line: ink, or the one amber accent when this line is what a warning is about.
static func line_colour(warn: bool) -> Color:
	return LothalTheme.WARNING if warn else DesignSpace.SELECT_INK


# ---------------------------------------------------------------------------
# Opening, saving, deleting (the pack designer's path: CustomParts.put_record)
# ---------------------------------------------------------------------------

## A fresh default motor (2207 at 1960 KV).
func open_new() -> void:
	design = MotorDesign.default_design(cfg)
	part_id = ""
	_rederive()


## A new design shaped like `motor` (a catalog record): nearest grid size, KV and bolt pattern.
## An empty record leaves the default design. Not a saved motor: it has no id until it is saved.
func start_like(motor: Dictionary) -> void:
	if motor.is_empty():
		return
	design = MotorDesign.like(motor, cfg)
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
	_drone_parts = {}
	if b != null:
		_drone_parts = {"frame": String(b.frame.get("part_id", "")),
			"propeller": String(b.propeller.get("part_id", "")),
			"battery": String(b.battery.get("part_id", ""))}
	bench_parts = _drone_parts.duplicate()
	_fill_pickers()
	_rederive()


## Runs the bench on another pack: a catalog id, or DRONE_PACK for the one on this drone. Reruns
## the bench and every figure at once.
func set_pack(id: String) -> void:
	if id == DRONE_PACK or id == "":
		bench_parts["battery"] = _drone_parts.get("battery", ReferenceBuild.BATTERY_ID)
	else:
		bench_parts["battery"] = id
	_select_in(pack_option, DRONE_PACK if id == "" else id, bench_parts["battery"])
	_rederive()


## Runs the bench on another prop (a catalog id: shelf or blade generator). Reruns at once.
func set_prop(id: String) -> void:
	bench_parts["propeller"] = id
	_select_in(prop_option, id, id)
	_rederive()


## Compares the sweep with another catalog motor ("" = none), flown with its exact record values
## (Kv, Rm, Io, mass), on the same pack and prop. Reruns at once.
func set_compare(id: String) -> void:
	compare_id = id if id == "" or not catalog.get_part(id).is_empty() else ""
	_select_in(compare_option, compare_id, "")
	_rederive()


## Which chart the sweep shows: "thrust" (default), "current" or "efficiency". Pressing the view
## already showing goes back to thrust.
func set_sweep_view(view: String) -> void:
	sweep_view = view if SWEEP_VIEWS.has(view) else "thrust"
	_refresh_bench()


## The sweep of the compare motor, {} when none is chosen or it cannot be flown.
func compare_result() -> Dictionary:
	return _compare


func compare_name() -> String:
	return String(catalog.get_part(compare_id).get("name", "")) if compare_id != "" else ""


## "Design a pack…": asks the host to open the pack designer.
func design_pack() -> void:
	design_pack_requested.emit()
	_select_in(pack_option, _pack_pick_id(), "")


## Back from the pack designer: the host hands over its fresh catalog and the new pack's id; the
## list is rebuilt and the new pack is the one the bench runs on.
func select_pack(id: String, fresh_catalog: PartsCatalog = null) -> void:
	if fresh_catalog != null:
		catalog = fresh_catalog
	_fill_pickers()
	set_pack(id)


## The pack the bench runs on now (a catalog id).
func pack_id() -> String:
	return String(bench_parts.get("battery", _drone_parts.get("battery", ReferenceBuild.BATTERY_ID)))


func prop_pick_id() -> String:
	return String(bench_parts.get("propeller", _drone_parts.get("propeller", ReferenceBuild.PROPELLER_ID)))


## The sentence under the bench: which of pack current / motor heat / prop load gives out first.
func limited_by_text() -> String:
	return String(_limited.get("text", ""))


func limited_by_key() -> String:
	return String(_limited.get("key", ""))


func _pack_pick_id() -> String:
	return DRONE_PACK if pack_id() == String(_drone_parts.get("battery", ReferenceBuild.BATTERY_ID)) else pack_id()


func _select_in(opt: OptionButton, id: String, fallback_id: String) -> void:
	if opt == null:
		return
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == id:
			opt.select(i)
			return
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == fallback_id:
			opt.select(i)
			return


## Pack list: this drone's pack, the shelf packs, the builder's designed packs, then "Design a
## pack…". Prop list: shelf props, then blade-generator props.
func _fill_pickers() -> void:
	if pack_option == null:
		return
	var drone_pack := String(_drone_parts.get("battery", ReferenceBuild.BATTERY_ID))
	pack_option.clear()
	pack_option.add_item("This drone's pack")
	pack_option.set_item_metadata(0, DRONE_PACK)
	for custom in [false, true]:
		for rec in catalog.list_category("battery"):
			var id := String(rec.get("part_id", ""))
			if PartsCatalog.is_custom(id) != custom or id == drone_pack:
				continue
			pack_option.add_item(String(rec.get("name", id)))
			pack_option.set_item_metadata(pack_option.item_count - 1, id)
	compare_option.clear()
	compare_option.add_item("None")
	compare_option.set_item_metadata(0, "")
	for custom in [false, true]:
		for rec in catalog.list_category("motor"):
			var id3 := String(rec.get("part_id", ""))
			if PartsCatalog.is_custom(id3) != custom:
				continue
			compare_option.add_item(String(rec.get("name", id3)))
			compare_option.set_item_metadata(compare_option.item_count - 1, id3)
	_select_in(compare_option, compare_id, "")
	pack_option.add_item("Design a pack…")
	pack_option.set_item_metadata(pack_option.item_count - 1, DESIGN_PACK_ITEM)
	prop_option.clear()
	for custom in [false, true]:
		for rec in catalog.list_category("propeller"):
			var id2 := String(rec.get("part_id", ""))
			if PartsCatalog.is_custom(id2) != custom:
				continue
			prop_option.add_item(String(rec.get("name", id2)))
			prop_option.set_item_metadata(prop_option.item_count - 1, id2)
	_select_in(pack_option, _pack_pick_id(), "")
	_select_in(prop_option, prop_pick_id(), "")


func _on_pack_picked(index: int) -> void:
	var id := String(pack_option.get_item_metadata(index))
	if id == DESIGN_PACK_ITEM:
		design_pack()
	else:
		set_pack(id)


func _on_prop_picked(index: int) -> void:
	set_prop(String(prop_option.get_item_metadata(index)))


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


## The buy-and-build sheet for this motor on the chosen prop and pack (MotorSheet), put on the
## clipboard. Returns the text.
func copy_specs() -> String:
	var text := specs_text()
	DisplayServer.clipboard_set(text)
	return text


func specs_text() -> String:
	return MotorSheet.to_text(design, cfg, bench_parts, catalog)


## Writes the same sheet to `path` as plain text. True when the file was written.
func save_specs(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(specs_text())
	f.close()
	return true


func _ask_specs_path() -> void:
	if _specs_dialog == null:
		_specs_dialog = FileDialog.new()
		_specs_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_specs_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_specs_dialog.use_native_dialog = true
		_specs_dialog.filters = PackedStringArray(["*.txt ; Text file"])
		_specs_dialog.file_selected.connect(func(path: String): save_specs(path))
		add_child(_specs_dialog)
	_specs_dialog.current_file = "%s.txt" % design.display_name().to_snake_case()
	_specs_dialog.popup_centered_ratio(0.6)


func _rederive() -> void:
	_figs = design.derive(cfg)
	derive_count += 1
	_run_bench()
	_refresh()
	_play_reveal()


func _run_bench() -> void:
	_bench = MotorBench.run(bench_kind, design, cfg, bench_parts, {}, catalog)
	_limited = MotorBench.limited_by(design, cfg, bench_parts, {}, catalog)
	_compare = {}
	if compare_id != "":
		# The record exactly as it stands: a shelf motor keeps its own Kv, Rm, Io and mass instead
		# of the nearest grid design's.
		_compare = MotorBench.sweep_of_record(catalog.get_part(compare_id), bench_parts, {}, catalog)


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
		"Copy a buy-and-build sheet for this motor")
	bar.add_child(copy_button)
	save_text_button = _bar_button("SaveSpecs", "Save as .txt", _ask_specs_path,
		"Save the same sheet as a text file")
	bar.add_child(save_text_button)
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
	var pickers := HBoxContainer.new()
	pickers.name = "Pickers"
	pickers.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	pack_option = _picker("PackPicker", "Pack", "The pack the bench runs on", pickers)
	pack_option.item_selected.connect(_on_pack_picked)
	prop_option = _picker("PropPicker", "Prop", "The prop the bench runs on", pickers)
	prop_option.item_selected.connect(_on_prop_picked)
	inner.add_child(pickers)
	# The compare picker is the sweep's, so it sits on its own row that shows only on that tab.
	compare_row = HBoxContainer.new()
	compare_row.name = "CompareRow"
	compare_option = _picker("ComparePicker", "Compare with…", "Another motor on the same pack and prop", compare_row)
	compare_option.item_selected.connect(func(i: int): set_compare(String(compare_option.get_item_metadata(i))))
	for view in ["current", "efficiency"]:
		var vb := Button.new()
		vb.name = "View_" + view
		vb.text = "Current" if view == "current" else "Efficiency"
		vb.toggle_mode = true
		vb.focus_mode = Control.FOCUS_NONE
		vb.tooltip_text = "Swap the thrust chart for this one"
		vb.pressed.connect(func(): set_sweep_view("thrust" if sweep_view == view else view))
		compare_row.add_child(vb)
		_view_buttons[view] = vb
	inner.add_child(compare_row)
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
	bench_total_label = Label.new()
	bench_total_label.name = "ResultTotal"
	bench_total_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	bench_total_label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	inner.add_child(bench_total_label)
	charts = PackCharts.new()
	# Warnings and the limited-by line stack under the chart; a short chart keeps the window on screen at 720.
	charts.custom_minimum_size = Vector2(0, 80)
	inner.add_child(charts)
	bench_warning_label = Label.new()
	bench_warning_label.name = "Warnings"
	bench_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bench_warning_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	bench_warning_label.add_theme_color_override("font_color", LothalTheme.WARNING)
	inner.add_child(bench_warning_label)
	warn_details_button = Button.new()
	warn_details_button.name = "WarningDetails"
	warn_details_button.flat = true
	warn_details_button.focus_mode = Control.FOCUS_NONE
	warn_details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	warn_details_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	warn_details_button.pressed.connect(toggle_warning_details)
	inner.add_child(warn_details_button)
	limited_label = Label.new()
	limited_label.name = "LimitedBy"
	limited_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limited_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	limited_label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	inner.add_child(limited_label)
	var note := _faint(BENCH_NOTE)
	note.name = "BenchNote"
	inner.add_child(note)
	bench_box.add_child(inner)
	col.add_child(bench_box)
	return col


## "Pack  [dropdown]" in one row cell; the dropdown fills what is left.
func _picker(node_name: String, label: String, tip: String, row: HBoxContainer) -> OptionButton:
	var cell := HBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	cell.add_child(l)
	var o := OptionButton.new()
	o.name = node_name
	o.tooltip_text = tip
	o.fit_to_longest_item = false
	o.clip_text = true
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size.x = 60.0
	o.focus_mode = Control.FOCUS_NONE
	cell.add_child(o)
	row.add_child(cell)
	return o


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
	compare_row.visible = bench_kind == "sweep"
	for view in _view_buttons:
		(_view_buttons[view] as Button).set_pressed_no_signal(view == sweep_view)
	var r := _bench
	if r.is_empty():
		limited_label.text = ""
		bench_result_label.text = ""
		bench_total_label.text = ""
		bench_warning_label.text = ""
		warn_details_button.visible = false
		charts.set_charts([])
		return
	bench_result_label.text = String(r.result)
	bench_total_label.text = String(r.get("total_text", ""))
	limited_label.text = limited_by_text()
	_refresh_warnings()
	var x: PackedFloat64Array = r.x
	match String(r.kind):
		"soak":
			var ta := _temp_axis(r)
			charts.set_charts([{"title": "Winding temperature", "x": x, "y": r.temp_c,
				"y_min": ta.x, "y_max": ta.y, "unit": " °C", "color": line_colour(_over_heat(r)),
				"x_max": MotorBench.SOAK_S}])
		"punch":
			var ta2 := _temp_axis(r)
			var floor_v := floorf(float(r.low_v) - 1.0)
			charts.set_charts([
				{"title": "Winding temperature", "x": x, "y": r.temp_c, "y_min": ta2.x, "y_max": ta2.y,
					"unit": " °C", "color": line_colour(_over_heat(r)), "x_max": MotorBench.PUNCH_S},
				{"title": "Pack voltage", "x": x, "y": r.v_live, "y_min": floor_v,
					"y_max": ceilf(float(r.start_v) + 0.5), "unit": " V", "color": line_colour(false),
					"x_max": MotorBench.PUNCH_S}])
		_:
			var o := _compare
			var two := not o.is_empty()
			var legend := [{"name": design.display_name(), "color": line_colour(false)},
				{"name": compare_name(), "color": COMPARE_INK}] if two else []
			# Charts are PER MOTOR, like the result line above them (the run holds the whole aircraft).
			var c_thrust := {"title": "Thrust per motor", "x": x, "y": _per_motor(r, "thrust_g"), "y_min": 0.0,
				"y_max": _ceil_nice(maxf(float(r.motor_thrust_g), float(o.get("motor_thrust_g", 0.0)))), "unit": " g",
				"color": line_colour(false), "x_max": 100.0, "x_end_text": "100 %"}
			var c_amps := {"title": "Current per motor", "x": x, "y": _per_motor(r, "current_a"), "y_min": 0.0,
				"y_max": _ceil_nice(maxf(float(r.motor_current_a), float(o.get("motor_current_a", 0.0)))), "unit": " A",
				"color": line_colour(not two and float(r.peak_winding_a) > float(_figs.max_current_a)),
				"x_max": 100.0, "x_end_text": "100 %"}
			var c_gpw := {"title": "g per watt", "x": r.gpw_x, "y": r.gpw.slice(int(r.gpw_from)), "y_min": 0.0,
				"y_max": _ceil_nice(maxf(_max_of(r.gpw), _max_of(o.get("gpw", PackedFloat64Array())))), "unit": " g/W",
				"color": line_colour(false), "x_max": 100.0, "x_end_text": "100 %"}
			if two:
				c_thrust["y2"] = _per_motor(o, "thrust_g")
				c_amps["y2"] = _per_motor(o, "current_a")
				c_gpw["y2"] = (o.gpw as PackedFloat64Array).slice(int(o.gpw_from))
				for cc in [c_thrust, c_amps, c_gpw]:
					cc["color2"] = COMPARE_INK
				c_thrust["legend"] = legend
			var shown: Dictionary = {"current": c_amps, "efficiency": c_gpw}.get(sweep_view, c_thrust)
			if two:
				shown["legend"] = legend
			charts.set_charts([shown])


## The warnings on screen: the two most severe (the bench returns them most severe first), or all
## of them once Details is open.
func shown_warnings() -> Array:
	var all := bench_warnings()
	return all if warn_details_open else all.slice(0, WARNINGS_SHOWN)


func toggle_warning_details() -> void:
	warn_details_open = not warn_details_open
	_refresh_warnings()


func _refresh_warnings() -> void:
	var all := bench_warnings()
	var extra := all.size() - WARNINGS_SHOWN
	if extra <= 0:
		warn_details_open = false
	bench_warning_label.text = "\n".join(shown_warnings())
	bench_warning_label.visible = not all.is_empty()
	warn_details_button.visible = extra > 0
	warn_details_button.text = "Hide details" if warn_details_open else "Details (%d more)" % extra


## One motor's share of a whole-aircraft series of a sweep.
static func _per_motor(r: Dictionary, key: String) -> PackedFloat64Array:
	var a: PackedFloat64Array = r[key]
	var n := float(maxi(int(r.get("motors", 1)), 1))
	var out := PackedFloat64Array()
	for v in a:
		out.append(v / n)
	return out


func _over_heat(r: Dictionary) -> bool:
	# The magnets sit in the bell (read the bell against their limit); the winding against its enamel.
	return float(r.get("peak_bell_c", 0.0)) > float(_figs.magnet_max_c) or float(r.get("burn_s", -1.0)) >= 0.0


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
	# The picture follows the Prop picker; a class-typical shelf prop only when the pick is unknown.
	var prop: Dictionary = catalog.by_id.get(prop_pick_id(), {})
	if prop.is_empty():
		prop = _usual_prop(float(cfg.get_size(design.size).stator_diameter_mm))
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
