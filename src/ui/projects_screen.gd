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
## A row was deleted (moved to the trash); the shell forgets it from its recents.
signal project_deleted(path: String)
## A row was renamed in place. The file (and so every recents path) is unchanged.
signal project_renamed(path: String, new_name: String)

const ROW_HEIGHT := 32
const LEFT_WIDTH := 264
const SORT_EDITED := 0
const SORT_NAME := 1
## The row's own "⋯" column, at the right end of every row and of the header: wide enough for a
## 28px+ hit area, and never shared with the EDITED text.
const MORE_WIDTH := 32
## The longest strings `ProjectChip.relative_time` can produce (weeks have no ceiling, three
## digits is two years); the EDITED column is sized to the widest of them in the real mono font.
const EDITED_LONGEST := ["just now", "59m ago", "23h ago", "yesterday", "6 days ago", "last week", "999 weeks ago"]
const MENU_RENAME := 0
const MENU_REVEAL := 1
const MENU_DELETE := 2

## The Design Space's monochrome ink and stage (design_space.gd); the accent colour is reserved
## for warnings, so nothing on this page is blue.
const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const STAGE_BG := Color(0.035, 0.035, 0.038)
const HAIRLINE := Color(1, 1, 1, 0.08)

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
var _confirm: ConfirmationDialog
var _pending_path := ""
var _menu: PopupMenu
var _menu_path := ""
var _menu_name := ""
var _rename: AcceptDialog
var _rename_field: LineEdit
var _rename_problem: Label
var _rename_path := ""
## What the OS is called; tests set it to check the per-OS label and command.
var os_name := OS.get_name()
## Where the rename reads custom parts from when it rewrites the file; tests point it at scratch.
var custom_parts_path: String = CustomParts.SAVE_PATH
## Receives the command dictionary from `reveal_command`. Tests replace it so no window opens.
var opener: Callable = _open_in_os


func _init(p_catalog: PartsCatalog = null) -> void:
	_catalog = p_catalog
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = STAGE_BG
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
	panel.add_theme_stylebox_override("panel", _plain_box(Color(0, 0, 0, 0), 0, true))
	panel.custom_minimum_size = Vector2(0, 48)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", LothalTheme.SPACE_4)
	margin.add_theme_constant_override("margin_right", LothalTheme.SPACE_4)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	margin.add_child(row)

	var mark := LogoMark.new()
	row.add_child(mark)
	var brand := Label.new()
	brand.text = "LOTHAL"
	DsUi.title(brand)
	brand.add_theme_color_override("font_color", INK)
	row.add_child(brand)
	var crumb := Label.new()
	crumb.text = "/ projects"
	crumb.add_theme_color_override("font_color", INK_FAINT)
	crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(crumb)

	var version := Label.new()
	version.text = "v%s" % LothalVersion.CURRENT
	DsUi.quiet(version)
	version.add_theme_color_override("font_color", INK_FAINT)
	row.add_child(version)
	return panel


func _build_new_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plain_box(Color(1, 1, 1, 0.03), LothalTheme.RADIUS_PANEL))
	panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	panel.add_child(box)

	var title := Label.new()
	title.text = "NEW DRONE"
	DsUi.quiet(title)
	title.add_theme_color_override("font_color", INK_MUTED)
	box.add_child(title)

	var new_button := Button.new()
	new_button.name = "NewDrone"
	new_button.text = "+ New drone"
	_style_button(new_button, true)
	new_button.custom_minimum_size = Vector2(0, 44)
	new_button.pressed.connect(func() -> void: new_requested.emit())
	box.add_child(new_button)

	var hint := Label.new()
	hint.text = "Starts from a known-good 5\" freestyle build. Change any part from there."
	DsUi.quiet(hint)
	hint.add_theme_color_override("font_color", INK_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var open_button := Button.new()
	open_button.name = "OpenFile"
	open_button.text = "Open file…"
	_style_button(open_button, false)
	open_button.custom_minimum_size = Vector2(0, 36)
	open_button.pressed.connect(func() -> void: open_requested.emit())
	box.add_child(open_button)
	return panel


func _build_table() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plain_box(Color(1, 1, 1, 0.03), LothalTheme.RADIUS_PANEL))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	panel.add_child(box)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	box.add_child(bar)
	var title := Label.new()
	title.text = "ALL PROJECTS"
	DsUi.quiet(title)
	title.add_theme_color_override("font_color", INK_MUTED)
	bar.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search drones…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_field(_search)
	_search.text_changed.connect(func(_t: String) -> void: _page = 0; _render())
	bar.add_child(_search)
	_sort = OptionButton.new()
	_style_button(_sort, false)
	_sort.add_item("Sort: last edited", SORT_EDITED)
	_sort.add_item("Sort: name", SORT_NAME)
	_sort.item_selected.connect(func(_i: int) -> void: _page = 0; _render())
	bar.add_child(_sort)

	var head_inset := MarginContainer.new()
	head_inset.add_theme_constant_override("margin_left", LothalTheme.SPACE_2)
	head_inset.add_theme_constant_override("margin_right", LothalTheme.SPACE_2)
	head_inset.add_child(_row_box(["NAME", "PROP", "DRY", "AUW", "EDITED", ""], true))
	box.add_child(head_inset)
	var rule := ColorRect.new()
	rule.color = HAIRLINE
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)

	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.clip_contents = true
	_rows.add_theme_constant_override("separation", 0)
	_rows.resized.connect(_on_rows_resized)
	box.add_child(_rows)

	_empty_label = Label.new()
	_empty_label.text = "No saved drones yet. New drone starts one."
	_empty_label.add_theme_color_override("font_color", INK_FAINT)
	_empty_label.visible = false
	_rows.add_child(_empty_label)

	var foot := HBoxContainer.new()
	box.add_child(foot)
	_range_label = Label.new()
	DsUi.quiet(_range_label)
	_range_label.add_theme_color_override("font_color", INK_FAINT)
	_range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_range_label)
	_prev = Button.new()
	_prev.text = "‹"
	_style_button(_prev, false)
	_prev.pressed.connect(func() -> void: _page -= 1; _render())
	foot.add_child(_prev)
	_next = Button.new()
	_next.text = "›"
	_style_button(_next, false)
	_next.pressed.connect(func() -> void: _page += 1; _render())
	foot.add_child(_next)

	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Delete"
	_confirm.cancel_button_text = "Cancel"
	_confirm.confirmed.connect(_on_delete_confirmed)
	_confirm.canceled.connect(func() -> void: _pending_path = "")
	_style_dialog(_confirm, "Delete drone")
	add_child(_confirm)

	_rename = AcceptDialog.new()
	_rename.ok_button_text = "Rename"
	var rename_box := VBoxContainer.new()
	rename_box.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	_rename_field = LineEdit.new()
	_rename_field.custom_minimum_size = Vector2(320, 0)
	_style_field(_rename_field)
	_rename_field.text_submitted.connect(func(_t: String) -> void:
		_rename.hide()
		_on_rename_confirmed())
	rename_box.add_child(_rename_field)
	_rename_problem = Label.new()
	_rename_problem.add_theme_color_override("font_color", LothalTheme.DANGER)
	_rename_problem.visible = false
	rename_box.add_child(_rename_problem)
	_rename.confirmed.connect(_on_rename_confirmed)
	_style_dialog(_rename, "Rename drone", rename_box)
	add_child(_rename)

	_menu = PopupMenu.new()
	_style_menu(_menu)
	_menu.add_item("Rename", MENU_RENAME)
	_menu.add_item(reveal_label(os_name), MENU_REVEAL)
	_menu.add_separator()
	_menu.add_item("Delete", MENU_DELETE)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	return panel


static func _plain_box(fill: Color, radius: int, bottom_rule := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	if bottom_rule:
		sb.border_color = HAIRLINE
		sb.border_width_bottom = 1
	else:
		sb.set_border_width_all(1)
		sb.border_color = HAIRLINE
	sb.set_content_margin_all(LothalTheme.SPACE_4)
	return sb


## The Design Space's ghost button (design_file_bar.gd); primary is the same shape, inverted.
static func _style_button(b: Button, primary: bool) -> void:
	DsUi.style_button(b, false, primary)


## A dialog in the page's monochrome: dark panel with a hairline, no blue outline, and the title
## drawn INSIDE the panel (the native title bar and its close box are collapsed to nothing).
static func _style_dialog(d: AcceptDialog, title_text: String, body: Control = null) -> void:
	# The border is drawn by `embedded_border` (square: a rounded one leaves grey window corners)
	# with no content margin, because Window offsets its content by that stylebox's margins; the
	# breathing room and the in-panel title space come from the plain `panel` fill inside it.
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.075, 0.075, 0.08)
	border.border_color = Color(1, 1, 1, 0.16)
	border.set_border_width_all(1)
	border.set_content_margin_all(0)
	var panel := border.duplicate() as StyleBoxFlat
	panel.set_content_margin_all(LothalTheme.SPACE_4)
	d.add_theme_stylebox_override("panel", panel)
	d.add_theme_stylebox_override("embedded_border", border)
	d.add_theme_stylebox_override("embedded_unfocused_border", border)
	d.add_theme_constant_override("title_height", 0)
	d.add_theme_color_override("title_color", Color(0, 0, 0, 0))
	d.add_theme_color_override("title_outline_modulate", Color(0, 0, 0, 0))
	var blank := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	d.add_theme_icon_override("close", blank)
	d.add_theme_icon_override("close_pressed", blank)
	# The title is the first row of the dialog's own content: AcceptDialog re-lays out every Control
	# child to fill the content rect, so a title placed by hand ends up on top of the body.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = title_text
	DsUi.quiet(heading)
	heading.add_theme_color_override("font_color", INK_MUTED)
	column.add_child(heading)
	d.set_meta("heading", heading)
	if body != null:
		column.add_child(body)
	else:
		# The built-in message label stays (it holds `dialog_text`) but is hidden; this one shows it.
		d.get_label().visible = false
		var message := Label.new()
		message.add_theme_color_override("font_color", INK)
		column.add_child(message)
		d.set_meta("message", message)
	d.add_child(column)
	var buttons: Array = [d.get_ok_button()]
	if d is ConfirmationDialog:
		buttons.append((d as ConfirmationDialog).get_cancel_button())
	for b in buttons:
		_style_button(b, b == d.get_ok_button())
		var ring := b.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
		ring.border_color = Color(1, 1, 1, 0.45)
		b.add_theme_stylebox_override("focus", ring)


static func _style_menu(m: PopupMenu) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.085, 0.085, 0.09)
	panel.border_color = Color(1, 1, 1, 0.14)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	panel.set_content_margin_all(4)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	m.add_theme_stylebox_override("panel", panel)
	m.add_theme_stylebox_override("hover", hover)
	m.add_theme_stylebox_override("focus", hover)
	var rule := StyleBoxLine.new()
	rule.color = HAIRLINE
	m.add_theme_stylebox_override("separator", rule)
	m.add_theme_color_override("font_color", INK_MUTED)
	m.add_theme_color_override("font_hover_color", INK)
	m.add_theme_constant_override("v_separation", 6)


static func _style_field(f: LineEdit) -> void:
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.04)
	field.border_color = Color(1, 1, 1, 0.12)
	field.set_border_width_all(1)
	field.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	field.content_margin_left = LothalTheme.SPACE_3
	field.content_margin_right = LothalTheme.SPACE_3
	field.content_margin_top = LothalTheme.SPACE_2
	field.content_margin_bottom = LothalTheme.SPACE_2
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = Color(1, 1, 1, 0.4)
	f.add_theme_stylebox_override("normal", field)
	f.add_theme_stylebox_override("focus", focus)
	f.add_theme_color_override("font_color", INK)
	f.add_theme_color_override("font_placeholder_color", INK_FAINT)
	f.add_theme_color_override("caret_color", INK)
	f.add_theme_color_override("selection_color", Color(1, 1, 1, 0.22))
	f.add_theme_color_override("font_selected_color", INK)


## A table row: no fill, a hairline beneath, a faint lift on hover.
static func _style_row(b: Button) -> void:
	var plain := StyleBoxFlat.new()
	plain.bg_color = Color(0, 0, 0, 0)
	plain.border_color = Color(1, 1, 1, 0.05)
	plain.border_width_bottom = 1
	var hover := plain.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("normal", plain)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)


## One table row's cells. Name takes the slack; the numbers get fixed columns so they line up.
static func _row_box(cells: Array, header := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widths := [0, 64, 72, 72, _edited_width(), MORE_WIDTH]
	for i in cells.size():
		if i == 5 and not header:
			var slot := Control.new()
			slot.custom_minimum_size = Vector2(MORE_WIDTH, 0)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.name = "BinSlot"
			row.add_child(slot)
			continue
		var label := Label.new()
		label.text = str(cells[i])
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if header:
			DsUi.quiet(label)
			label.add_theme_color_override("font_color", INK_FAINT)
		elif i > 0:
			DsUi.readout(label)
			label.add_theme_color_override("font_color", INK_MUTED)
		else:
			label.add_theme_color_override("font_color", INK)
		if widths[i] == 0:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			label.custom_minimum_size = Vector2(widths[i], 0)
		row.add_child(label)
	return row


## Width of the EDITED column: the widest relative-time string in the readout font, plus a pixel of
## slack. Measured, not guessed, so a font change moves the column with it.
static func _edited_width() -> int:
	var th := LothalTheme.get_theme()
	var font: Font = th.default_font
	var px: int = LothalTheme.FONT_SIZE_BODY
	var widest := 0.0
	for text in EDITED_LONGEST + ["EDITED"]:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return ceili(widest) + 2


## Re-reads `user://builds`. Each drone is opened once here and its numbers kept, so paging and
## searching never touch the disk.
func refresh() -> void:
	entries = list_builds(_catalog)
	_render()


## Every drone in the builds folder (not the trash), with the numbers the table shows. A file that
## will not open is left out rather than shown as a row that cannot be opened.
static func list_builds(catalog: PartsCatalog) -> Array:
	return ProjectRows.list(catalog)


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
		_style_row(button)
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.tooltip_text = str(entry["path"])
		var path := str(entry["path"])
		button.pressed.connect(func() -> void: project_chosen.emit(path))
		var cells := _row_box([entry["name"], entry["size"], _grams(float(entry["dry_g"])),
			_grams(float(entry["auw_g"])), _edited(int(entry["updated_unix"]), now), ""])
		cells.set_anchors_preset(Control.PRESET_FULL_RECT)
		cells.offset_left = LothalTheme.SPACE_2
		cells.offset_right = -LothalTheme.SPACE_2
		button.add_child(cells)
		var more := _make_more(path, str(entry["name"]))
		button.add_child(more)
		more.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		more.offset_right = -LothalTheme.SPACE_2
		more.offset_left = -LothalTheme.SPACE_2 - MORE_WIDTH
		# Subtle at rest, full strength on row hover or on the button itself (or keyboard focus).
		var dim := func(on: bool) -> void:
			more.modulate.a = 1.0 if on else 0.7
		button.mouse_entered.connect(dim.bind(true))
		button.mouse_exited.connect(func() -> void: dim.call(more.is_hovered() or more.has_focus()))
		more.mouse_entered.connect(dim.bind(true))
		more.focus_entered.connect(dim.bind(true))
		more.focus_exited.connect(dim.bind(false))
		_rows.add_child(button)

	_range_label.text = "%d–%d of %d" % [first + 1, last, shown.size()] if not shown.is_empty() \
		else "0 of %d" % entries.size()
	_prev.disabled = _page == 0
	_next.disabled = _page >= pages - 1


## The row's "⋯" button. It sits on top of the row's own button, so pressing it opens the menu and
## never reaches the row (which would open the project).
func _make_more(path: String, drone_name: String) -> Button:
	var more := Button.new()
	more.name = "More"
	more.text = "⋯"
	more.flat = true
	more.focus_mode = Control.FOCUS_ALL
	more.mouse_filter = Control.MOUSE_FILTER_STOP
	more.tooltip_text = "More actions for '%s'" % drone_name
	more.modulate.a = 0.7
	more.add_theme_font_size_override("font_size", 20)
	more.add_theme_color_override("font_color", INK)
	more.add_theme_color_override("font_hover_color", INK)
	more.add_theme_color_override("font_pressed_color", INK)
	more.add_theme_color_override("font_focus_color", INK)
	var plain := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	for state in ["normal", "disabled"]:
		more.add_theme_stylebox_override(state, plain)
	for state in ["hover", "pressed", "focus"]:
		more.add_theme_stylebox_override(state, hover)
	more.pressed.connect(func() -> void: open_menu(path, drone_name, more))
	return more


## Opens the row menu for one drone, under `anchor` when given.
func open_menu(path: String, drone_name: String, anchor: Control = null) -> void:
	_menu_path = path
	_menu_name = drone_name
	_menu.set_item_text(_menu.get_item_index(MENU_REVEAL), reveal_label(os_name))
	if _menu.is_inside_tree() and anchor != null:
		var origin := Vector2i(anchor.get_screen_position()) + Vector2i(int(anchor.size.x) - 150, int(anchor.size.y))
		_menu.popup(Rect2i(origin, Vector2i(150, 0)))
	else:
		_menu.visible = true


func _on_menu_id(id: int) -> void:
	match id:
		MENU_RENAME: request_rename(_menu_path, _menu_name)
		MENU_REVEAL: reveal(_menu_path)
		MENU_DELETE: request_delete(_menu_path, _menu_name)


## The menu's label for the file-manager item, per OS.
static func reveal_label(p_os_name: String) -> String:
	match p_os_name:
		"macOS": return "Show in Finder"
		"Windows": return "Show in Explorer"
	return "Show in file manager"


## What revealing `absolute_file` means on this OS, as data so a test can read it instead of
## opening a window: `{kind: "execute", program, args}` or `{kind: "shell_open", path}`.
static func reveal_command(p_os_name: String, absolute_file: String) -> Dictionary:
	match p_os_name:
		"macOS":
			return {"kind": "execute", "program": "open", "args": ["-R", absolute_file]}
		"Windows":
			return {"kind": "execute", "program": "explorer",
				"args": ["/select,%s" % absolute_file.replace("/", "\\")]}
	return {"kind": "shell_open", "path": absolute_file.get_base_dir()}


func reveal(path: String) -> void:
	opener.call(reveal_command(os_name, ProjectSettings.globalize_path(path)))


func _open_in_os(command: Dictionary) -> void:
	if command["kind"] == "execute":
		OS.create_process(str(command["program"]), command["args"])
	else:
		OS.shell_open(str(command["path"]))


## Asks for a new name, prefilled with the current one.
func request_rename(path: String, drone_name: String) -> void:
	_rename_path = path
	_rename_field.text = drone_name
	_rename_problem.visible = false
	if _rename.is_inside_tree():
		_rename.popup_centered()
		_rename_field.grab_focus()
		_rename_field.select_all()
	else:
		_rename.visible = true


## Applies the typed name, or refuses and says why. Returns "" on success.
func submit_rename() -> String:
	if _rename_path == "":
		return "No drone chosen."
	var problem := ProjectLibrary.rename(_rename_path, _rename_field.text, custom_parts_path)
	if problem != "":
		return problem
	var path := _rename_path
	_rename_path = ""
	project_renamed.emit(path, _rename_field.text.strip_edges())
	refresh()
	return ""


## AcceptDialog hides itself on OK before `confirmed` reaches us, so a refused name re-shows it.
func _on_rename_confirmed() -> void:
	var problem := submit_rename()
	if problem == "":
		return
	_rename_problem.text = problem
	_rename_problem.visible = true
	_rename.show()


## Asks "Delete '<name>'?". Nothing is touched until the builder confirms.
func request_delete(path: String, drone_name: String) -> void:
	_pending_path = path
	_confirm.dialog_text = "Delete '%s'?" % drone_name
	(_confirm.get_meta("message") as Label).text = _confirm.dialog_text
	if _confirm.is_inside_tree():
		_confirm.popup_centered()
	else:
		_confirm.visible = true


func _on_delete_confirmed() -> void:
	var path := _pending_path
	_pending_path = ""
	if path == "":
		return
	ProjectLibrary.delete(path)  # a move into the trash folder, never an unlink
	project_deleted.emit(path)
	refresh()


## The Lothal mark (icon.svg) without its tile: a top-down quad, redrawn as vectors so it is crisp at
## any size. Monochrome — the icon's cyan front arm is drawn in ink like the rest.
class LogoMark extends Control:
	const HEIGHT := 26.0
	const SRC := Vector2(40, 40)   # the quad occupies 40..200 of the icon's 240 grid
	const SPAN := 160.0

	func _init() -> void:
		name = "LogoMark"
		custom_minimum_size = Vector2(HEIGHT, HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := HEIGHT / SPAN
		var at := func(x: float, y: float) -> Vector2: return (Vector2(x, y) - SRC) * k
		var ring := ProjectsScreen.INK_FAINT
		var ink := ProjectsScreen.INK
		for c in [Vector2(164, 76), Vector2(164, 164), Vector2(76, 164), Vector2(76, 76)]:
			draw_arc(at.call(c.x, c.y), 36 * k, 0, TAU, 40, ring, 5 * k, true)
		var w := 15 * k
		for seg in [[100, 100, 76, 76], [140, 140, 164, 164], [100, 140, 76, 164], [140, 100, 164, 76]]:
			draw_line(at.call(seg[0], seg[1]), at.call(seg[2], seg[3]), ink, w, true)
		draw_rect(Rect2(at.call(99, 97), Vector2(42, 46) * k), ink, false, 13 * k, true)
		for c in [Vector2(76, 76), Vector2(164, 164), Vector2(76, 164), Vector2(164, 76)]:
			draw_circle(at.call(c.x, c.y), 11 * k, ink)


static func _grams(g: float) -> String:
	if g < 0.0:
		return "—"
	return "%s kg" % ProjectRows.trim(g / 1000.0) if g >= 1000.0 else "%d g" % roundi(g)


static func _edited(unix: int, now: int) -> String:
	if unix <= 0:
		return "—"
	return ProjectChip.relative_time(maxi(0, now - unix))


