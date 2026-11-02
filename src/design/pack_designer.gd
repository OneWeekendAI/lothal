class_name PackDesigner
extends Control
## The pack designer: a pop-up over the Design Space (opened only from the "+" tile at the end of
## the battery list). Three columns. Left: 1 Cell, 2 Layout, 3 Wiring. Middle: the pack in 3D.
## Right: the pack's figures, then the bench (Discharge and Recharge).
##
## It opens on a valid default pack (a 4S1P of 1500 mAh LiPo cells) with its bench result already
## showing, so a first-time visitor sees a working pack before they touch anything.
##
## DERIVED, NOT TYPED. Every figure comes from cell x layout x wiring (PackDesign.derive); the only
## typed numbers are the wiring, the bench settings and, for a custom cell, the cell's own fields.
## The figures column holds labels only. A pack that arrived as typed figures ("legacy") or a shelf
## preset is locked until "Rebuild from cells" / "Start from this".
##
## Every setter ends in _rederive(): derive, run the bench, refresh the screen, replay the reveal.
## The reveal is a ~3 s draw-in that ends on static charts; with no scene tree (tests) it is skipped.

signal saved(part_id: String)
signal closed

const REVEAL_S := 3.0
const BACKDROP := Color(0.0, 0.0, 0.0, 0.58)
const MARGIN_X := 36
const MARGIN_Y := 24
const LEFT_W := 300.0
const RIGHT_W := 440.0
const CHEMISTRIES := ["LiPo", "LiPo HV", "Li-ion", "LiFePO4"]
const STEADY_DEFAULT_A := 10.0
## The custom-cell fields a builder may type (and so the only typed numbers that reach the figures).
const CUSTOM_FIELDS := [
	["mah", "Capacity", "mAh", 50.0, 20000.0, 50.0],
	["max_cont_a", "Steady current", "A", 1.0, 400.0, 1.0],
	["max_burst_a", "Burst current", "A", 1.0, 800.0, 1.0],
	["r_mohm", "Resistance", "mΩ", 1.0, 200.0, 0.5],
	["mass_g", "Mass", "g", 1.0, 200.0, 0.5],
	["length_mm", "Length", "mm", 5.0, 150.0, 0.5],
	["width_mm", "Width", "mm", 5.0, 100.0, 0.5],
	["thickness_mm", "Thickness", "mm", 2.0, 40.0, 0.1],
	["diameter_mm", "Diameter", "mm", 5.0, 40.0, 0.1],
]
const FIGURE_ROWS := ["voltage", "capacity", "mass_g", "size", "current", "resistance"]

var catalog: PartsCatalog
var lib: CellLibrary
var store: DesignedPacks
var charge: PackCharge
var build: Build
## Where the shelf reloads the saved packs from, and where the charge state is written.
## The id armed for deletion by a first press (empty when none).
var pending_delete := ""
var store_path: String = CustomParts.SAVE_PATH
var charge_path: String = PackCharge.SAVE_PATH

var design: PackDesign
var part_id := ""
var read_only := false
var derive_count := 0
var chemistry_filter := ""
var discharge_mode := "constant"
var discharge_amps := STEADY_DEFAULT_A
var charge_c := 1.0
var tab := "discharge"

var _figs: Dictionary = {}
var _run: Dictionary = {}
var _recharge: Dictionary = {}
var _warns: Array[String] = []
var _tween: Tween
var _recharge_pending := false
var _charged_now := false
var _charge_from_frac := 0.0
var _syncing := false
var _test_drained := false

# Controls.
var window: PanelContainer
var name_field: LineEdit
var badge_label: Label
var rebuild_button: Button
var start_from_button: Button
var my_packs_button: Button
var save_as_button: Button
var copy_button: Button
var save_text_button: Button
var _specs_dialog: FileDialog
var save_button: Button
var back_button: Button
var my_packs_panel: PanelContainer
var my_packs_list: VBoxContainer
var chip_row: HFlowContainer
var cell_list: ItemList
var custom_button: Button
var custom_box: VBoxContainer
var series_label: Label
var parallel_label: Label
var connector_option: OptionButton
var awg_option: OptionButton
var length_spin: SpinBox
var pack_view: PackView3D
var summary_label: Label
var figures_box: GridContainer
var figures_header: Label
var _figure_values := {}
var _figure_tags := {}
var tab_discharge: Button
var tab_recharge: Button
var steady_button: Button
var drone_button: Button
var amps_spin: SpinBox
var run_button: Button
var charge_spin: SpinBox
var charge_button: Button
var discharge_row: HBoxContainer
var recharge_row: HBoxContainer
var charge_line: Label
var charge_bar: ProgressBar
var result_label: Label
var warning_label: Label
## "This test used the pack's charge": shown after a Discharge run drained a stored pack.
var test_note: Label
var charts: PackCharts
var _custom_spins := {}
var _cell_ids: Array = []


func _init(p_catalog: PartsCatalog = null, p_lib: CellLibrary = null, p_store: DesignedPacks = null,
		p_charge: PackCharge = null, p_build: Build = null) -> void:
	catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	lib = p_lib if p_lib != null else CellLibrary.load_default()
	store = p_store if p_store != null else DesignedPacks.new()
	charge = p_charge if p_charge != null else PackCharge.new()
	build = p_build
	name = "PackDesigner"
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	design = PackDesign.default_design(lib)
	# The load a pack is judged on is the drone it would fly in, when there is one.
	discharge_mode = "this_drone" if build != null else "constant"
	_build_ui()


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

## A fresh default pack (4S1P of 1500 mAh LiPo cells).
func open_new() -> void:
	design = PackDesign.default_design(lib)
	part_id = ""
	read_only = false
	chemistry_filter = ""
	_after_open()


## A shelf pack: a saved one (editable), or a preset (read-only: recharge, or start from it).
func open_pack(p_part_id: String) -> void:
	var rec := store.get_record(p_part_id)
	if not rec.is_empty():
		design = PackDesign.from_record(rec, lib)
		part_id = p_part_id
		read_only = false
		_after_open()
		return
	var preset := catalog.get_part(p_part_id)
	if preset.is_empty():
		open_new()
		return
	design = PackDesign.from_record(DesignedPacks.migrate_v1_record(preset), lib)
	design.part_id = p_part_id
	design.name = String(preset.get("name", p_part_id))
	part_id = p_part_id
	read_only = true
	_after_open()


## An editable copy of the pack that is open (a preset, or any other), under a new name.
func start_from_this() -> void:
	design.rebuild_from_cells()
	design.name = "%s copy" % design.name
	design.part_id = ""
	part_id = ""
	read_only = false
	_after_open()


## A legacy (typed-figures) pack becomes a derived one. Its figures may change from here on.
func rebuild_from_cells() -> void:
	if not is_legacy_open():
		return
	design.rebuild_from_cells()
	_sync_widgets()
	_rederive()


func is_legacy_open() -> bool:
	return design.is_legacy() and not read_only


func _after_open() -> void:
	tab = "discharge"
	chemistry_filter = ""
	my_packs_panel.visible = false
	_sync_widgets()
	_rederive()


## A17: delete a saved pack. The first call for an id only arms it (returns false); the second call
## for the same id deletes it and returns true. Shelf presets are never deletable.
func request_delete(id: String) -> bool:
	if id == "" or not PartsCatalog.is_custom(id):
		pending_delete = ""
		return false
	if pending_delete != id:
		pending_delete = id
		return false
	pending_delete = ""
	if not store.remove(id):
		return false
	store.save(store_path)
	if part_id == id:
		open_new()
	if my_packs_panel.visible:
		_fill_my_packs()
	return true


## Every pack on the shelf, presets included: [{id, name, kind: preset | saved | legacy}].
func my_packs() -> Array:
	var out: Array = []
	for rec in catalog.list_category("battery"):
		var id := String(rec.get("part_id", ""))
		if PartsCatalog.is_custom(id):
			continue
		out.append({"id": id, "name": String(rec.get("name", id)), "kind": "preset"})
	for rec in store.records():
		var block: Dictionary = rec.get("design", {})
		out.append({"id": String(rec.get("part_id", "")), "name": String(rec.get("name", "")),
			"kind": "legacy" if bool(block.get("legacy", false)) else "saved"})
	return out


# ---------------------------------------------------------------------------
# Setters: each one re-derives and reruns the bench
# ---------------------------------------------------------------------------

func _locked() -> bool:
	return read_only or design.is_legacy()


func set_pack_name(p_name: String) -> void:
	if read_only:
		return
	design.name = p_name
	if name_field != null and name_field.text != p_name:
		name_field.text = p_name


func set_chemistry_filter(c: String) -> void:
	if _locked():
		return
	chemistry_filter = c
	if c != "" and design.chemistry() != c:
		if String(design.cell.get("basis", "")) == "custom":
			_retype_custom(c)
		else:
			var group := lib.by_chemistry(c)
			if not group.is_empty():
				design.cell = group[0]
	_sync_widgets()
	_rederive()


func set_cell(cell_id: String) -> void:
	if _locked():
		return
	if cell_id == "custom_cell":
		if String(design.cell.get("basis", "")) != "custom":
			var cs: Dictionary = design.cell.get("specs", {})
			var chem := design.chemistry()
			var cyl := chem == "Li-ion"
			var cyl_form := String(design.cell.get("form", "pouch")) == "cylindrical"
			var dims := Vector3(float(cs.get("length_mm", 60.0)), float(cs.get("width_mm", 28.0)),
				float(cs.get("thickness_mm", 7.0)))
			if cyl:
				dims = Vector3(float(cs.get("diameter_mm", 21.7)), float(cs.get("length_mm", 70.0)), 0.0)
			elif cyl_form:
				dims = Vector3(float(cs.get("length_mm", 60.0)), 28.0, 7.0)
			design.cell = CellLibrary.custom_cell("Custom cell", chem, float(cs.get("mah", 1500.0)),
				float(cs.get("max_cont_a", 50.0)), float(cs.get("max_burst_a", 100.0)),
				float(cs.get("r_mohm", 5.0)), float(cs.get("mass_g", 30.0)), dims,
				"cylindrical" if cyl else "pouch")
	else:
		var cell := lib.get_cell(cell_id)
		if cell.is_empty():
			return
		design.cell = cell
	_sync_widgets()
	_rederive()


## A custom cell's own field (key in CUSTOM_FIELDS). The only typed figure that reaches the pack.
func set_custom_field(field: String, value: float) -> void:
	if _locked() or String(design.cell.get("basis", "")) != "custom":
		return
	var specs: Dictionary = (design.cell["specs"] as Dictionary).duplicate()
	specs[field] = value
	var cell := design.cell.duplicate(true)
	cell["specs"] = specs
	design.cell = cell
	_rederive()


func _retype_custom(chem: String) -> void:
	var cs: Dictionary = design.cell.get("specs", {})
	var cyl := chem == "Li-ion"
	var dims := Vector3(float(cs.get("length_mm", 60.0)), float(cs.get("width_mm", 28.0)),
		float(cs.get("thickness_mm", 7.0)))
	if cyl:
		dims = Vector3(float(cs.get("diameter_mm", 21.7)), float(cs.get("length_mm", 70.0)), 0.0)
	design.cell = CellLibrary.custom_cell(String(design.cell.get("name", "Custom cell")), chem,
		float(cs.get("mah", 1500.0)), float(cs.get("max_cont_a", 50.0)),
		float(cs.get("max_burst_a", 100.0)), float(cs.get("r_mohm", 5.0)),
		float(cs.get("mass_g", 30.0)), dims, "cylindrical" if cyl else "pouch")


func set_series(n: int) -> void:
	if _locked():
		return
	design.series = clampi(n, PackDesign.S_RANGE.x, PackDesign.S_RANGE.y)
	_rederive()


func set_parallel(n: int) -> void:
	if _locked():
		return
	design.parallel = clampi(n, PackDesign.P_RANGE.x, PackDesign.P_RANGE.y)
	_rederive()


func set_wiring(connector_family: String, awg: int, length_mm: float) -> void:
	if _locked():
		return
	design.connector_family = connector_family
	design.lead_awg = awg
	design.lead_length_mm = clampf(length_mm, 20.0, 400.0)
	_rederive()


func set_discharge_mode(mode: String, amps: float = NAN) -> void:
	discharge_mode = mode if mode == "this_drone" and build != null else "constant"
	if not is_nan(amps):
		discharge_amps = maxf(amps, 0.1)
	_rederive()


func set_charge_c(c: float) -> void:
	charge_c = clampf(c, 0.1, 10.0)
	_rederive()


func set_tab(which: String) -> void:
	tab = which if which == "recharge" else "discharge"
	_rederive()


# ---------------------------------------------------------------------------
# Derive, bench, refresh
# ---------------------------------------------------------------------------

func figures() -> Dictionary:
	return _figs


func warnings() -> Array[String]:
	return _warns


func bench_result() -> Dictionary:
	return _run


func recharge_result() -> Dictionary:
	return _recharge


## What a figure is: "ideal / datasheet", except the wrap allowance in the mass, an estimate.
func figure_tags() -> Dictionary:
	return _figure_tags


## The names of every number a builder can type here (tests: none of them is a derived figure).
func typed_fields() -> Array:
	var out: Array = ["name", "series", "parallel", "connector", "awg", "length_mm",
		"discharge_amps", "charge_c"]
	if String(design.cell.get("basis", "")) == "custom":
		for f in CUSTOM_FIELDS:
			out.append("custom_" + String(f[0]).trim_suffix("_a").trim_suffix("_g").trim_suffix("_mm").trim_suffix("_mohm"))
	return out


func _rederive() -> void:
	derive_count += 1
	_test_drained = false
	if not _recharge_pending:
		_charged_now = false
	_figs = design.derive()
	_run = _run_discharge()
	_recharge = _run_recharge_preview()
	_warns = PackBench.warnings(design, _run, build if discharge_mode == "this_drone" else null,
		charge_c if tab == "recharge" else NAN)
	_refresh()
	_play_reveal()


## The Discharge run, pressed: runs the bench and, for a pack that has an id (saved, or on the
## shelf), leaves its stored used_mah at the run's end. A new unsaved design has nothing stored, so
## it is untouched. Only this press drains; editing, reopening or the automatic first run never do.
func run_discharge_test() -> void:
	_rederive()
	if part_id == "":
		return
	var used: PackedFloat64Array = _run.get("used_mah", PackedFloat64Array())
	if used.is_empty():
		return
	charge.set_used_mah(part_id, float(used[used.size() - 1]))
	charge.save(charge_path)
	_test_drained = true
	_refresh()


func _discharge_current() -> float:
	if discharge_mode == "this_drone" and build != null:
		return maxf(PackBench.this_drone_current_a(build), 0.1)
	return discharge_amps


func _run_discharge() -> Dictionary:
	var amps := _discharge_current()
	var est_s := float(_figs.get("mah", 1000.0)) / 1000.0 / maxf(amps, 0.1) * 3600.0
	return PackBench.discharge(design, amps, maxf(1.0, ceilf(est_s / 600.0)))


## The recharge from where the pack stands now (from empty when it is full, as a preview).
func _recharge_start_mah() -> float:
	var used := charge.used_mah(part_id) if part_id != "" else 0.0
	return used if used > 0.0 else float(_figs.get("mah", 0.0))


func _run_recharge_preview() -> Dictionary:
	var est_s := float(_figs.get("mah", 1000.0)) / 1000.0 / maxf(charge_c, 0.1) * 3600.0 * 1.4
	return PackBench.recharge(design, _recharge_start_mah(), charge_c, maxf(1.0, ceilf(est_s / 600.0)))


## Charges the pack: plays the recharge, and when it completes the stored state is back to full.
func run_recharge() -> void:
	tab = "recharge"
	_charge_from_frac = charge_fraction()
	_recharge_pending = true
	_rederive()
	if not is_inside_tree():
		_finish_recharge()


func _finish_recharge() -> void:
	if not _recharge_pending:
		return
	_recharge_pending = false
	_charged_now = true
	if part_id != "":
		charge.set_used_mah(part_id, 0.0)
		charge.save(charge_path)
	_recharge = _run_recharge_preview()
	_refresh()


## The stored charge of this pack as a fraction of its capacity (1.0 for a pack not yet saved).
func charge_fraction() -> float:
	var mah := float(_figs.get("mah", 0.0))
	if part_id == "" or mah <= 0.0:
		return 1.0
	return charge.remaining_fraction(part_id, mah)


## "Charge: 38% (930 of 1500 mAh used)", then "Charging 74%" during the reveal, then
## "Charged to 100% ✓".
func charge_line_text() -> String:
	var mah := float(_figs.get("mah", 0.0))
	if _recharge_pending and is_inside_tree():
		return "Charging %d%%" % roundi(_charge_shown() * 100.0)
	if _charged_now:
		return "Charged to 100% \u2713"
	var used := charge.used_mah(part_id) if part_id != "" else 0.0
	var pct := 100 if used <= 0.0 else clampi(roundi(charge_fraction() * 100.0), 0, 99)
	return "Charge: %d%% (%d of %d mAh used)" % [pct, roundi(used), roundi(mah)]


func _charge_shown() -> float:
	if _recharge_pending and is_inside_tree():
		return lerpf(_charge_from_frac, 1.0, charts.reveal)
	return 1.0 if _charged_now else charge_fraction()


func _process(_delta: float) -> void:
	if _recharge_pending and charge_line != null:
		charge_line.text = charge_line_text()
		charge_bar.value = _charge_shown() * 100.0


func _play_reveal() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		charts.reveal = 1.0
		return
	charts.reveal = 0.0
	_tween = create_tween()
	_tween.tween_property(charts, "reveal", 1.0, REVEAL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(_finish_recharge)


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------

## Saves under the current id (a new pack gets one). "" when refused or read-only.
func save() -> String:
	if read_only:
		return ""
	design.name = name_field.text.strip_edges() if name_field.text.strip_edges() != "" else design.name
	var id := store.save_design(design, charge, part_id)
	if id == "":
		return ""
	part_id = id
	design.part_id = id
	charge.save(charge_path)
	saved.emit(id)
	_refresh()
	return id


## A new pack from this design at full charge, never touching the one it was opened from.
func save_as() -> String:
	if read_only:
		return ""
	var copy_name := name_field.text.strip_edges()
	if part_id != "" and (copy_name == "" or copy_name == String(store.get_record(part_id).get("name", ""))):
		copy_name = "%s copy" % (design.name if copy_name == "" else copy_name)
	design.name = copy_name if copy_name != "" else design.name
	var id := store.save_as(design, charge)
	if id == "":
		return ""
	part_id = id
	design.part_id = id
	charge.save(charge_path)
	set_pack_name(design.name)
	saved.emit(id)
	_refresh()
	return id


## The buy-and-build sheet for this pack (PackSheet), put on the clipboard. Returns the text.
func copy_specs() -> String:
	var text := PackSheet.to_text(design)
	DisplayServer.clipboard_set(text)
	return text


## Writes the same sheet to `path` as plain text. True when the file was written.
func save_specs(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(PackSheet.to_text(design))
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
	_specs_dialog.current_file = "%s.txt" % String(design.name).to_snake_case()
	_specs_dialog.popup_centered_ratio(0.6)


func close() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	closed.emit()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Screen
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.color = BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	window = PanelContainer.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = MARGIN_X
	window.offset_right = -MARGIN_X
	window.offset_top = MARGIN_Y
	window.offset_bottom = -MARGIN_Y
	var box := LothalTheme.glass_box(Color(0.075, 0.083, 0.105, 0.98), LothalTheme.RADIUS_PANEL)
	box.content_margin_left = LothalTheme.SPACE_4
	box.content_margin_right = LothalTheme.SPACE_4
	box.content_margin_top = LothalTheme.SPACE_3
	box.content_margin_bottom = LothalTheme.SPACE_4
	window.add_theme_stylebox_override("panel", box)
	add_child(window)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	window.add_child(root)
	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", LothalTheme.SPACE_4)
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_middle())
	body.add_child(_build_right())

	_build_my_packs_panel()


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "‹  Back"
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(close)
	bar.add_child(back_button)
	name_field = LineEdit.new()
	name_field.name = "NameField"
	name_field.placeholder_text = "Pack name"
	name_field.custom_minimum_size = Vector2(240, 0)
	name_field.max_length = 40
	name_field.text_changed.connect(func(t: String): if not _syncing: set_pack_name(t))
	bar.add_child(name_field)
	badge_label = Label.new()
	badge_label.name = "Badge"
	badge_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	badge_label.add_theme_color_override("font_color", LothalTheme.WARNING)
	badge_label.visible = false
	bar.add_child(badge_label)
	rebuild_button = Button.new()
	rebuild_button.name = "RebuildFromCells"
	rebuild_button.text = "Rebuild from cells"
	rebuild_button.visible = false
	rebuild_button.pressed.connect(rebuild_from_cells)
	bar.add_child(rebuild_button)
	start_from_button = Button.new()
	start_from_button.name = "StartFromThis"
	start_from_button.text = "Start from this"
	start_from_button.visible = false
	start_from_button.pressed.connect(start_from_this)
	bar.add_child(start_from_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	my_packs_button = Button.new()
	my_packs_button.name = "MyPacks"
	my_packs_button.text = "My packs"
	my_packs_button.pressed.connect(_toggle_my_packs)
	bar.add_child(my_packs_button)
	copy_button = Button.new()
	copy_button.name = "CopySpecs"
	copy_button.text = "Copy specs"
	copy_button.tooltip_text = "Copy a buy-and-build sheet for this pack"
	copy_button.pressed.connect(func(): copy_specs())
	bar.add_child(copy_button)
	save_text_button = Button.new()
	save_text_button.name = "SaveSpecs"
	save_text_button.text = "Save as text…"
	save_text_button.pressed.connect(_ask_specs_path)
	bar.add_child(save_text_button)
	save_as_button = Button.new()
	save_as_button.name = "SaveAs"
	save_as_button.text = "Save as new"
	save_as_button.pressed.connect(func(): save_as())
	bar.add_child(save_as_button)
	save_button = Button.new()
	save_button.name = "Save"
	save_button.text = "Save to shelf"
	save_button.pressed.connect(func(): save())
	bar.add_child(save_button)
	return bar


func _section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	return l


func _faint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
	return l


func _build_left() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "LeftScroll"
	scroll.custom_minimum_size = Vector2(LEFT_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	scroll.add_child(col)

	col.add_child(_section("1 · Cell"))
	chip_row = HFlowContainer.new()
	chip_row.name = "Chemistry"
	chip_row.add_theme_constant_override("h_separation", 4)
	chip_row.add_theme_constant_override("v_separation", 4)
	for c in CHEMISTRIES:
		var b := Button.new()
		b.name = "Chem_" + String(c).replace(" ", "")
		b.text = String(c)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_chemistry_filter("" if chemistry_filter == c else c))
		chip_row.add_child(b)
	col.add_child(chip_row)
	cell_list = ItemList.new()
	cell_list.name = "Cells"
	cell_list.custom_minimum_size = Vector2(0, 132)
	cell_list.select_mode = ItemList.SELECT_SINGLE
	cell_list.item_selected.connect(_on_cell_picked)
	col.add_child(cell_list)
	custom_button = Button.new()
	custom_button.name = "CustomCell"
	custom_button.text = "Custom cell…"
	custom_button.toggle_mode = true
	custom_button.pressed.connect(_toggle_custom)
	col.add_child(custom_button)
	custom_box = VBoxContainer.new()
	custom_box.name = "CustomFields"
	custom_box.add_theme_constant_override("separation", 2)
	col.add_child(custom_box)

	col.add_child(_spacer(LothalTheme.SPACE_1))
	col.add_child(_section("2 · Layout"))
	series_label = _add_stepper(col, "Series", "cells in a row: sets the voltage",
		func(): set_series(design.series - 1), func(): set_series(design.series + 1))
	parallel_label = _add_stepper(col, "Parallel", "side by side: sets the capacity",
		func(): set_parallel(design.parallel - 1), func(): set_parallel(design.parallel + 1))

	col.add_child(_spacer(LothalTheme.SPACE_1))
	col.add_child(_section("3 · Wiring"))
	connector_option = OptionButton.new()
	connector_option.name = "Connector"
	for row in catalog.list_category("connector"):
		var fam := String((row.get("catalog", {}) as Dictionary).get("family", ""))
		if fam != "" and _connector_index(fam) < 0:
			connector_option.add_item(fam)
	connector_option.item_selected.connect(func(_i: int): if not _syncing: _wiring_changed())
	col.add_child(_labelled("Plug", connector_option))
	awg_option = OptionButton.new()
	awg_option.name = "WireGauge"
	for g in WireGauge.gauges():
		awg_option.add_item("%d AWG" % int(g), int(g))
	awg_option.item_selected.connect(func(_i: int): if not _syncing: _wiring_changed())
	col.add_child(_labelled("Wire", awg_option))
	length_spin = SpinBox.new()
	length_spin.name = "LeadLength"
	length_spin.min_value = 20.0
	length_spin.max_value = 400.0
	length_spin.step = 5.0
	length_spin.suffix = "mm"
	length_spin.value_changed.connect(func(_v: float): if not _syncing: _wiring_changed())
	col.add_child(_labelled("Lead length", length_spin))
	col.add_child(_faint("The plug's contact resistance is counted in the Power harness, not here."))
	return scroll


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _labelled(text: String, ctl: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(88, 0)
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctl)
	return row


func _add_stepper(parent: Control, title: String, hint: String, on_minus: Callable, on_plus: Callable) -> Label:
	var row := HBoxContainer.new()
	row.name = "Stepper_" + title
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var l := Label.new()
	l.text = "%s  (%s)" % [title, "voltage" if title == "Series" else "capacity"]
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(l)
	var minus := Button.new()
	minus.name = "%sMinus" % title
	minus.text = "−"
	minus.custom_minimum_size = Vector2(32, 0)
	minus.pressed.connect(on_minus)
	row.add_child(minus)
	var v := Label.new()
	v.name = "%sValue" % title
	v.custom_minimum_size = Vector2(44, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(v)
	var plus := Button.new()
	plus.name = "%sPlus" % title
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 0)
	plus.pressed.connect(on_plus)
	row.add_child(plus)
	l.tooltip_text = hint
	parent.add_child(row)
	return v


func _build_middle() -> Control:
	var col := VBoxContainer.new()
	col.name = "Middle"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	pack_view = PackView3D.new()
	col.add_child(pack_view)
	summary_label = Label.new()
	summary_label.name = "Summary"
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
	summary_label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(summary_label)
	return col


func _build_right() -> Control:
	var col := VBoxContainer.new()
	col.name = "Right"
	col.custom_minimum_size = Vector2(RIGHT_W, 0)
	col.add_theme_constant_override("separation", LothalTheme.SPACE_2)

	figures_header = Label.new()
	figures_header.name = "FiguresHeader"
	figures_header.text = "Pack figures   ·   %s" % PackDesign.BASIS
	figures_header.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	figures_header.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(figures_header)
	figures_box = GridContainer.new()
	figures_box.name = "Figures"
	figures_box.columns = 3
	figures_box.add_theme_constant_override("h_separation", LothalTheme.SPACE_3)
	figures_box.add_theme_constant_override("v_separation", 2)
	for key in FIGURE_ROWS:
		var n := Label.new()
		n.text = _figure_name(key)
		n.custom_minimum_size = Vector2(88, 0)
		n.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		n.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
		figures_box.add_child(n)
		var v := Label.new()
		v.name = "Fig_" + key
		v.custom_minimum_size = Vector2(214, 0)
		v.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
		v.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
		figures_box.add_child(v)
		_figure_values[key] = v
		var t := Label.new()
		t.name = "Tag_" + key
		t.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL - 1)
		t.add_theme_color_override("font_color", LothalTheme.TEXT_FAINT)
		figures_box.add_child(t)
		_figure_values[key + "_tag"] = t
	col.add_child(figures_box)

	col.add_child(_spacer(LothalTheme.SPACE_1))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	tab_discharge = _tab_button("Discharge", "discharge")
	tab_recharge = _tab_button("Recharge", "recharge")
	tabs.add_child(tab_discharge)
	tabs.add_child(tab_recharge)
	col.add_child(tabs)

	discharge_row = HBoxContainer.new()
	discharge_row.name = "DischargeRow"
	discharge_row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	steady_button = Button.new()
	steady_button.name = "Steady"
	steady_button.text = "Steady load"
	steady_button.toggle_mode = true
	steady_button.pressed.connect(func(): set_discharge_mode("constant"))
	discharge_row.add_child(steady_button)
	drone_button = Button.new()
	drone_button.name = "ThisDrone"
	drone_button.text = "This drone"
	drone_button.toggle_mode = true
	drone_button.disabled = build == null
	drone_button.pressed.connect(func(): set_discharge_mode("this_drone"))
	discharge_row.add_child(drone_button)
	amps_spin = SpinBox.new()
	amps_spin.name = "DischargeAmps"
	amps_spin.min_value = 0.5
	amps_spin.max_value = 400.0
	amps_spin.step = 0.5
	amps_spin.suffix = "A"
	amps_spin.value_changed.connect(func(v: float): if not _syncing: set_discharge_mode("constant", v))
	discharge_row.add_child(amps_spin)
	run_button = Button.new()
	run_button.name = "RunAgain"
	run_button.text = "Run again"
	run_button.pressed.connect(run_discharge_test)
	discharge_row.add_child(run_button)
	col.add_child(discharge_row)

	recharge_row = HBoxContainer.new()
	recharge_row.name = "RechargeRow"
	recharge_row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var rate := Label.new()
	rate.text = "Charge rate"
	rate.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	rate.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	recharge_row.add_child(rate)
	charge_spin = SpinBox.new()
	charge_spin.name = "ChargeC"
	charge_spin.min_value = 0.1
	charge_spin.max_value = 10.0
	charge_spin.step = 0.1
	charge_spin.suffix = "C"
	charge_spin.value_changed.connect(func(v: float): if not _syncing: set_charge_c(v))
	recharge_row.add_child(charge_spin)
	charge_button = Button.new()
	charge_button.name = "ChargeNow"
	charge_button.text = "Charge now"
	charge_button.pressed.connect(run_recharge)
	recharge_row.add_child(charge_button)
	col.add_child(recharge_row)

	charge_line = Label.new()
	charge_line.name = "ChargeLine"
	charge_line.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	charge_line.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(charge_line)
	charge_bar = ProgressBar.new()
	charge_bar.name = "ChargeBar"
	charge_bar.show_percentage = false
	charge_bar.min_value = 0.0
	charge_bar.max_value = 100.0
	charge_bar.custom_minimum_size = Vector2(0, 6)
	col.add_child(charge_bar)

	result_label = Label.new()
	result_label.name = "Result"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	result_label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	col.add_child(result_label)
	test_note = Label.new()
	test_note.name = "TestNote"
	test_note.visible = false
	test_note.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	test_note.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	col.add_child(test_note)
	charts = PackCharts.new()
	col.add_child(charts)
	warning_label = Label.new()
	warning_label.name = "Warnings"
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	warning_label.add_theme_color_override("font_color", LothalTheme.WARNING)
	col.add_child(warning_label)
	return col


func _tab_button(text: String, which: String) -> Button:
	var b := Button.new()
	b.name = "Tab_" + which
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): set_tab(which))
	return b


static func _figure_name(key: String) -> String:
	match key:
		"voltage": return "Voltage"
		"capacity": return "Capacity"
		"mass_g": return "Mass"
		"size": return "Size"
		"current": return "Current"
		"resistance": return "Resistance"
	return key


func _build_my_packs_panel() -> void:
	my_packs_panel = PanelContainer.new()
	my_packs_panel.name = "MyPacksPanel"
	my_packs_panel.visible = false
	my_packs_panel.anchor_left = 1.0
	my_packs_panel.anchor_right = 1.0
	my_packs_panel.offset_right = -(MARGIN_X + LothalTheme.SPACE_4)
	my_packs_panel.offset_left = -(MARGIN_X + LothalTheme.SPACE_4 + 320)
	my_packs_panel.offset_top = MARGIN_Y + 56
	my_packs_panel.offset_bottom = MARGIN_Y + 56 + 380
	var panel_box := LothalTheme.glass_box(Color(0.105, 0.115, 0.14, 1.0))
	panel_box.set_content_margin_all(LothalTheme.SPACE_2)
	my_packs_panel.add_theme_stylebox_override("panel", panel_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	my_packs_panel.add_child(scroll)
	my_packs_list = VBoxContainer.new()
	my_packs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_packs_list.add_theme_constant_override("separation", 2)
	scroll.add_child(my_packs_list)
	add_child(my_packs_panel)


func _toggle_my_packs() -> void:
	my_packs_panel.visible = not my_packs_panel.visible
	if my_packs_panel.visible:
		_fill_my_packs()


func _fill_my_packs() -> void:
	for c in my_packs_list.get_children():
		my_packs_list.remove_child(c)
		c.queue_free()
	var last := ""
	for r in my_packs():
		var kind := String(r["kind"])
		var group := "Shelf packs" if kind == "preset" else "My packs"
		if group != last:
			my_packs_list.add_child(_faint(group.to_upper()))
			last = group
		var b := Button.new()
		b.name = "Pack_" + String(r["id"])
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = String(r["name"]) + ("   (typed)" if kind == "legacy" else "")
		b.clip_text = true
		var id := String(r["id"])
		b.pressed.connect(func(): open_pack(id))
		if kind == "preset":
			my_packs_list.add_child(b)
			continue
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_child(b)
		var del := Button.new()
		del.name = "Delete_" + id
		del.flat = true
		del.text = "Sure?" if pending_delete == id else "Delete"
		del.add_theme_color_override("font_color", LothalTheme.DANGER)
		del.pressed.connect(func(): request_delete(id); _fill_my_packs())
		row.add_child(del)
		my_packs_list.add_child(row)


func _toggle_custom() -> void:
	if String(design.cell.get("basis", "")) != "custom":
		set_cell("custom_cell")
	else:
		set_cell(_first_cell_id())


func _first_cell_id() -> String:
	var group := lib.by_chemistry(design.chemistry())
	return String(group[0].get("cell_id", "")) if not group.is_empty() else "cell_lipo_1500"


func _connector_index(family: String) -> int:
	for i in connector_option.item_count:
		if connector_option.get_item_text(i) == family:
			return i
	return -1


func _wiring_changed() -> void:
	var fam := connector_option.get_item_text(connector_option.selected) if connector_option.selected >= 0 else design.connector_family
	set_wiring(fam, awg_option.get_selected_id(), length_spin.value)


func _on_cell_picked(index: int) -> void:
	if _syncing or index < 0 or index >= _cell_ids.size():
		return
	set_cell(String(_cell_ids[index]))


## Puts the widgets where the model is, without echoing back into the setters.
func _sync_widgets() -> void:
	_syncing = true
	name_field.text = design.name
	name_field.editable = not read_only
	for b in chip_row.get_children():
		(b as Button).button_pressed = chemistry_filter == String((b as Button).text)
	_fill_cell_list()
	custom_button.button_pressed = String(design.cell.get("basis", "")) == "custom"
	_fill_custom_fields()
	var i := _connector_index(design.connector_family)
	if i >= 0:
		connector_option.select(i)
	var gi := awg_option.get_item_index(design.lead_awg)
	if gi >= 0:
		awg_option.select(gi)
	length_spin.set_value_no_signal(design.lead_length_mm)
	amps_spin.set_value_no_signal(discharge_amps)
	charge_spin.set_value_no_signal(charge_c)
	_syncing = false


func _fill_cell_list() -> void:
	cell_list.clear()
	_cell_ids = []
	var pool: Array = []
	for chem in CHEMISTRIES:
		if chemistry_filter == "" or chemistry_filter == chem:
			pool.append_array(lib.by_chemistry(chem))
	var current := String(design.cell.get("cell_id", ""))
	var is_custom := String(design.cell.get("basis", "")) == "custom"
	for c in pool:
		var specs: Dictionary = c.get("specs", {})
		cell_list.add_item(String(c.get("name", "")).replace(" (class)", ""))
		_cell_ids.append(String(c.get("cell_id", "")))
		cell_list.set_item_tooltip(cell_list.item_count - 1, "%.0f mAh · %s" % [
			float(specs.get("mah", 0.0)), String(c.get("chemistry", ""))])
		if String(c.get("cell_id", "")) == current and not is_custom:
			cell_list.select(cell_list.item_count - 1)
			cell_list.ensure_current_is_visible()


func _fill_custom_fields() -> void:
	for c in custom_box.get_children():
		custom_box.remove_child(c)
		c.queue_free()
	_custom_spins.clear()
	if String(design.cell.get("basis", "")) != "custom" or _locked():
		return
	var cs: Dictionary = design.cell.get("specs", {})
	var cyl := String(design.cell.get("form", "pouch")) == "cylindrical"
	for f in CUSTOM_FIELDS:
		var key := String(f[0])
		if cyl and (key == "width_mm" or key == "thickness_mm"):
			continue
		if not cyl and key == "diameter_mm":
			continue
		var sp := SpinBox.new()
		sp.name = "Custom" + _camel(key)
		sp.min_value = float(f[3])
		sp.max_value = float(f[4])
		sp.step = float(f[5])
		sp.suffix = String(f[2])
		sp.set_value_no_signal(float(cs.get(key, 0.0)))
		sp.value_changed.connect(func(v: float): if not _syncing: set_custom_field(key, v))
		custom_box.add_child(_labelled(String(f[1]), sp))
		_custom_spins[key] = sp
	custom_box.add_child(_faint("Typed by you: your figures, not a datasheet's."))


static func _camel(key: String) -> String:
	match key:
		"max_cont_a": return "ContA"
		"max_burst_a": return "BurstA"
		"r_mohm": return "Rmohm"
		"mass_g": return "Mass"
		"mah": return "Mah"
		"length_mm": return "Length"
		"width_mm": return "Width"
		"thickness_mm": return "Thickness"
		"diameter_mm": return "Diameter"
	return key


func _refresh() -> void:
	var f := _figs
	var legacy := design.is_legacy()
	var basis := String(f.get("basis", PackDesign.BASIS))
	_figure_tags = {}
	for key in ["nominal_v", "full_v", "empty_v", "mah", "wh", "mass_g", "dims_mm", "cont_a", "burst_a", "internal_r_ohm"]:
		_figure_tags[key] = basis
	if not legacy:
		_figure_tags["mass_g"] = "estimate"
	var dims: Vector3 = f.get("dims_mm", Vector3.ZERO)
	(_figure_values["voltage"] as Label).text = "%.1f V   (%.1f – %.1f)" % [
		float(f.get("nominal_v", 0.0)), float(f.get("empty_v", 0.0)), float(f.get("full_v", 0.0))]
	(_figure_values["capacity"] as Label).text = "%.0f mAh   ·   %.1f Wh" % [float(f.get("mah", 0.0)), float(f.get("wh", 0.0))]
	(_figure_values["mass_g"] as Label).text = "%.0f g" % float(f.get("mass_g", 0.0))
	(_figure_values["size"] as Label).text = "%.0f × %.0f × %.0f mm" % [dims.x, dims.y, dims.z]
	(_figure_values["current"] as Label).text = "%.0f A steady   ·   %.0f A burst%s" % [float(f.get("cont_a", 0.0)), float(f.get("burst_a", 0.0)),
		" (est.)" if bool(f.get("burst_estimated", false)) else ""]
	(_figure_values["resistance"] as Label).text = "%.0f mΩ%s" % [float(f.get("internal_r_ohm", 0.0)) * 1000.0,
		" (est.)" if bool(f.get("resistance_estimated", false)) else ""]
	# The basis is in the header; a row repeats it only where it differs: the mass allowance.
	for key in FIGURE_ROWS:
		(_figure_values[key + "_tag"] as Label).text = ""
	(_figure_values["mass_g_tag"] as Label).text = String(_figure_tags["mass_g"]) if not legacy else ""
	figures_header.text = "Pack figures   ·   %s" % ("as listed on the shelf" if read_only else basis)

	series_label.text = _layout_text().split("S")[0] + "S"
	parallel_label.text = "1P" if legacy else "%dP" % design.parallel
	var locked := _locked()
	for n in ["SeriesMinus", "SeriesPlus", "ParallelMinus", "ParallelPlus"]:
		var btn := find_child(n, true, false) as Button
		if btn != null:
			btn.disabled = locked
	custom_button.disabled = locked
	cell_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	cell_list.modulate = Color(1, 1, 1, 0.45 if locked else 1.0)
	connector_option.disabled = locked
	awg_option.disabled = locked
	length_spin.editable = not locked
	for b in chip_row.get_children():
		(b as Button).disabled = locked

	summary_label.text = "%s   ·   %.1f V   ·   %.0f mAh" % [
		_layout_text(), float(f.get("nominal_v", 0.0)), float(f.get("mah", 0.0))]
	pack_view.show_record(design.to_record())

	badge_label.visible = locked
	badge_label.text = ("shelf pack (typed figures)" if read_only else PackDesign.LEGACY_BASIS) if locked else ""
	rebuild_button.visible = is_legacy_open()
	start_from_button.visible = read_only
	save_button.disabled = read_only
	save_as_button.disabled = read_only

	tab_discharge.button_pressed = tab == "discharge"
	tab_recharge.button_pressed = tab == "recharge"
	discharge_row.visible = tab == "discharge"
	recharge_row.visible = tab == "recharge"
	charge_line.visible = tab == "recharge"
	charge_bar.visible = tab == "recharge"
	charge_line.text = charge_line_text()
	charge_bar.value = _charge_shown() * 100.0
	steady_button.button_pressed = discharge_mode == "constant"
	drone_button.button_pressed = discharge_mode == "this_drone"
	amps_spin.set_value_no_signal(_discharge_current())
	amps_spin.editable = discharge_mode == "constant"
	_refresh_bench()
	warning_label.text = "\n".join(_warns)
	warning_label.visible = not _warns.is_empty()
	test_note.visible = _test_drained and tab == "discharge"
	test_note.text = "This test used the pack's charge" if test_note.visible else ""


func _layout_text() -> String:
	if design.is_legacy():
		return "%dS" % int(design.legacy_specs.get("cells", design.series))
	return "%dS%dP" % [design.series, design.parallel]


func _refresh_bench() -> void:
	if tab == "discharge":
		var t: PackedFloat64Array = _run.get("t", PackedFloat64Array())
		var vaxis := PackBench.voltage_axis(design)
		var taxis := PackBench.temp_axis(design, _run)
		result_label.text = "Runs %s to empty   ·   %.1f Wh   ·   sags %.1f V   ·   %.2f V/cell loaded" % [
			_duration(float(_run.get("run_time_s", 0.0))), float(_run.get("wh_delivered", 0.0)),
			float(_run.get("peak_sag_v", 0.0)), float(_run.get("cell_v_load", 0.0))]
		var mah := maxf(float(_figs.get("mah", 1.0)), 1.0)
		charts.set_charts([
			{"title": "Pack voltage", "x": t, "y": _run.get("v_live", PackedFloat64Array()),
				"y_min": vaxis.x, "y_max": vaxis.y, "unit": " V", "color": LothalTheme.ACCENT},
			{"title": "Cell temperature", "x": t, "y": _run.get("cell_temp_c", PackedFloat64Array()),
				"y_min": taxis.x, "y_max": taxis.y, "unit": " °C",
				"color": LothalTheme.WARNING},
			{"title": "Capacity used", "x": t, "y": _run.get("used_mah", PackedFloat64Array()),
				"y_min": 0.0, "y_max": mah, "unit": " mAh", "color": LothalTheme.TEXT_MUTED,
				"red_above": mah * (1.0 - PackCharts.KNEE_LEFT), "total": mah},
		])
	else:
		var rt: PackedFloat64Array = _recharge.get("t", PackedFloat64Array())
		var from_empty := (charge.used_mah(part_id) if part_id != "" else 0.0) <= 0.0
		var full_s := float(_recharge.get("time_to_full_s", 0.0))
		if _recharge_pending:
			result_label.text = "Charging…"
		elif rt.size() == 0:
			result_label.text = "Already full."
		else:
			result_label.text = "%s in %s at %.1fC" % ["Empty to full" if from_empty else "Full", _duration(full_s), charge_c]
		var vaxis2 := PackBench.voltage_axis(design)
		var imax := maxf(charge_c * float(_figs.get("mah", 1000.0)) / 1000.0, 0.1)
		charts.set_charts([
			{"title": "Pack voltage", "x": rt, "y": _recharge.get("v", PackedFloat64Array()),
				"y_min": vaxis2.x, "y_max": vaxis2.y, "unit": " V", "color": LothalTheme.ACCENT},
			{"title": "Charge current", "x": rt, "y": _recharge.get("i", PackedFloat64Array()),
				"y_min": 0.0, "y_max": imax, "unit": " A", "color": LothalTheme.SUCCESS},
		])


static func _duration(s: float) -> String:
	if s >= 5400.0:
		return "%.1f h" % (s / 3600.0)
	if s >= 90.0:
		return "%.0f min" % (s / 60.0)
	return "%.0f s" % s
