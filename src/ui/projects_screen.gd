class_name ProjectsScreen
extends Control
## The Projects screen: every saved drone in one table, and the two ways to start one.
##
## Built from lothal-mockups/screens/projects, minus what the mockup had twice or had not got:
##
## - **No "Recent" cards.** Sorted by last edited, the four cards were exactly the table's first
##   four rows. The table is the list; a second copy of its head is noise.
## - **No preset list.** One known-good starting build exists (ProjectLibrary.starting_project);
##   four presets would be three invented drones, which §9 forbids.
## - **No "Import BF dump", no avatar, no Settings.** None of them does anything yet, and a screen
##   whose job is "pick a drone" does not need to advertise features it is not.
##
## The table pages rather than scrolls — the same clip-and-page rule the rest of the shell follows —
## and the page size is whatever fits, so a taller window shows more rows instead of more gap.

signal new_requested
signal open_requested
signal project_chosen(path: String)

const ROW_HEIGHT := 32
const LEFT_WIDTH := 264
const SORT_EDITED := 0
const SORT_NAME := 1

## Every drone on disk, as `[{path, name, updated_unix, size, dry_g, auw_g}]`. Filled by `refresh`.
var entries: Array = []
var _catalog: PartsCatalog
var _page := 0
var _rows_per_page := 10

var _search: LineEdit
var _sort: OptionButton
var _rows: VBoxContainer
var _range_label: Label
var _prev: Button
var _next: Button
var _empty_label: Label


func _init(p_catalog: PartsCatalog = null) -> void:
	_catalog = p_catalog
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = LothalTheme.SURFACE_BASE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	outer.add_child(_build_header())

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		body.add_theme_constant_override("margin_" + side, LothalTheme.SPACE_4)
	outer.add_child(body)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", LothalTheme.SPACE_4)
	body.add_child(split)
	split.add_child(_build_new_panel())
	split.add_child(_build_table())


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "FlushPanel"
	panel.custom_minimum_size = Vector2(0, 48)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", LothalTheme.SPACE_4)
	margin.add_theme_constant_override("margin_right", LothalTheme.SPACE_4)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	margin.add_child(row)

	var brand := Label.new()
	brand.text = "◇ LOTHAL"
	brand.theme_type_variation = "TitleLabel"
	brand.add_theme_color_override("font_color", LothalTheme.ACCENT)
	row.add_child(brand)
	var crumb := Label.new()
	crumb.text = "/ projects"
	crumb.theme_type_variation = "MutedLabel"
	crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(crumb)

	var version := Label.new()
	version.text = "v%s" % LothalVersion.CURRENT
	version.theme_type_variation = "SmallLabel"
	row.add_child(version)
	return panel


func _build_new_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	panel.add_child(box)

	var title := Label.new()
	title.text = "NEW DRONE"
	title.theme_type_variation = "SmallLabel"
	title.add_theme_color_override("font_color", LothalTheme.ACCENT)
	box.add_child(title)

	var new_button := Button.new()
	new_button.name = "NewDrone"
	new_button.text = "+ New drone"
	new_button.theme_type_variation = "PrimaryButton"
	new_button.custom_minimum_size = Vector2(0, 44)
	new_button.pressed.connect(func() -> void: new_requested.emit())
	box.add_child(new_button)

	var hint := Label.new()
	hint.text = "Starts from a known-good 5\" freestyle build. Change any part from there."
	hint.theme_type_variation = "SmallLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var open_button := Button.new()
	open_button.name = "OpenFile"
	open_button.text = "Open file…"
	open_button.pressed.connect(func() -> void: open_requested.emit())
	box.add_child(open_button)
	return panel


func _build_table() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	panel.add_child(box)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	box.add_child(bar)
	var title := Label.new()
	title.text = "ALL PROJECTS"
	title.theme_type_variation = "SmallLabel"
	title.add_theme_color_override("font_color", LothalTheme.ACCENT)
	bar.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search drones…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _page = 0; _render())
	bar.add_child(_search)
	_sort = OptionButton.new()
	_sort.add_item("Sort: last edited", SORT_EDITED)
	_sort.add_item("Sort: name", SORT_NAME)
	_sort.item_selected.connect(func(_i: int) -> void: _page = 0; _render())
	bar.add_child(_sort)

	box.add_child(_row_box(["NAME", "PROP", "DRY", "AUW", "EDITED"], true))
	box.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.clip_contents = true
	_rows.add_theme_constant_override("separation", 0)
	_rows.resized.connect(_on_rows_resized)
	box.add_child(_rows)

	_empty_label = Label.new()
	_empty_label.text = "No saved drones yet. New drone starts one."
	_empty_label.theme_type_variation = "MutedLabel"
	_empty_label.visible = false
	_rows.add_child(_empty_label)

	var foot := HBoxContainer.new()
	box.add_child(foot)
	_range_label = Label.new()
	_range_label.theme_type_variation = "SmallLabel"
	_range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_range_label)
	_prev = Button.new()
	_prev.text = "‹"
	_prev.flat = true
	_prev.pressed.connect(func() -> void: _page -= 1; _render())
	foot.add_child(_prev)
	_next = Button.new()
	_next.text = "›"
	_next.flat = true
	_next.pressed.connect(func() -> void: _page += 1; _render())
	foot.add_child(_next)
	return panel


## One table row's cells. Name takes the slack; the numbers get fixed columns so they line up.
static func _row_box(cells: Array, header := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widths := [0, 64, 72, 72, 96]
	for i in cells.size():
		var label := Label.new()
		label.text = str(cells[i])
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if header:
			label.theme_type_variation = "SmallLabel"
		elif i > 0:
			label.theme_type_variation = "ReadoutLabel"
		if widths[i] == 0:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			label.custom_minimum_size = Vector2(widths[i], 0)
		row.add_child(label)
	return row


## Re-reads `user://builds`. Each drone is opened once here and its numbers kept, so paging and
## searching never touch the disk.
func refresh() -> void:
	entries = list_builds(_catalog)
	_render()


## Every drone in the builds folder (not the trash), with the numbers the table shows. A file that
## will not open is left out rather than shown as a row that cannot be opened.
static func list_builds(catalog: PartsCatalog) -> Array:
	ProjectLibrary.ensure_dir()
	var out: Array = []
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	for file in DirAccess.get_files_at(absolute):
		if not file.ends_with(".%s" % ProjectContainer.EXTENSION):
			continue
		var path := "%s/%s" % [ProjectLibrary.DIR, file]
		var opened := ProjectContainer.open(path)
		if opened == null:
			continue
		var project := opened.project
		var entry := {
			"path": path,
			"name": project.name,
			"updated_unix": _unix_of(project.updated_at),
			"size": "—", "dry_g": -1.0, "auw_g": -1.0,
		}
		var build: Build = project.to_build(catalog) if catalog != null else null
		if build != null:
			entry["auw_g"] = build.all_up_weight_g()
			entry["dry_g"] = build.all_up_weight_g() - float(build.battery.get("mass_g", 0.0))
			var specs: Dictionary = build.propeller.get("specs", {})
			if specs.has("diameter_inches"):
				entry["size"] = "%s\"" % _trim(float(specs["diameter_inches"]))
		out.append(entry)
	return out


## The rows the current search and sort leave, before paging.
func visible_entries() -> Array:
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var out: Array = []
	for entry in entries:
		if query == "" or str(entry["name"]).to_lower().contains(query):
			out.append(entry)
	if _sort != null and _sort.get_selected_id() == SORT_NAME:
		out.sort_custom(func(a, b) -> bool:
			return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	else:
		out.sort_custom(func(a, b) -> bool: return int(a["updated_unix"]) > int(b["updated_unix"]))
	return out


func _on_rows_resized() -> void:
	var fits := maxi(1, int(_rows.size.y / ROW_HEIGHT))
	if fits != _rows_per_page:
		_rows_per_page = fits
		_render()


func _render() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		if child != _empty_label:
			child.queue_free()
			_rows.remove_child(child)

	var shown := visible_entries()
	var pages := maxi(1, ceili(float(shown.size()) / _rows_per_page))
	_page = clampi(_page, 0, pages - 1)
	var first := _page * _rows_per_page
	var last := mini(first + _rows_per_page, shown.size())

	_empty_label.visible = shown.is_empty()
	if shown.is_empty() and not entries.is_empty():
		_empty_label.text = "No drone matches \"%s\"." % _search.text.strip_edges()
	elif entries.is_empty():
		_empty_label.text = "No saved drones yet. New drone starts one."

	var now := int(Time.get_unix_time_from_system())
	for i in range(first, last):
		var entry: Dictionary = shown[i]
		var button := Button.new()
		button.flat = true
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.tooltip_text = str(entry["path"])
		var path := str(entry["path"])
		button.pressed.connect(func() -> void: project_chosen.emit(path))
		var cells := _row_box([entry["name"], entry["size"], _grams(float(entry["dry_g"])),
			_grams(float(entry["auw_g"])), _edited(int(entry["updated_unix"]), now)])
		cells.set_anchors_preset(Control.PRESET_FULL_RECT)
		cells.offset_left = LothalTheme.SPACE_2
		cells.offset_right = -LothalTheme.SPACE_2
		button.add_child(cells)
		_rows.add_child(button)

	_range_label.text = "%d–%d of %d" % [first + 1, last, shown.size()] if not shown.is_empty() \
		else "0 of %d" % entries.size()
	_prev.disabled = _page == 0
	_next.disabled = _page >= pages - 1


static func _grams(g: float) -> String:
	if g < 0.0:
		return "—"
	return "%s kg" % _trim(g / 1000.0) if g >= 1000.0 else "%d g" % roundi(g)


static func _edited(unix: int, now: int) -> String:
	if unix <= 0:
		return "—"
	return ProjectChip.relative_time(maxi(0, now - unix))


static func _trim(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


static func _unix_of(iso: String) -> int:
	if iso == "":
		return 0
	return int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))
