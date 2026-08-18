class_name ProjectChip
extends PanelContainer
## The top-left cluster: the drone's name, whether it is saved, and the menu that drops out of it.
##
## §5: **"Projects: the project name IS the menu."** So there is no File button, no toolbar and no
## title — the name is the control. That is the entire chrome cost of projects in this shell, and
## it is why the chip is worth building before the thing it names can be saved.
##
## ---------------------------------------------------------------------------
## WHAT IS TRUE HERE TODAY
## ---------------------------------------------------------------------------
##
## New, Open, Duplicate, Rename and Reveal all work; the two exports wait on things that are not
## built. The chip reports where the drone is written and when it was last written.
##
## The state line is the part most likely to become a lie, so it is derived from ONE fact: whether
## `saved_path` is set. There is no "saved" boolean that could disagree with the file system, and
## while nothing has been written the "saved" wording cannot be produced at all.

signal project_renamed(new_name: String)
## Forwarded from the menu so the shell does not have to know the menu exists.
signal action_chosen(action_id: String)
signal recent_chosen(path: String)

## Where this project is written. Empty until the container exists, and the state line reads off
## exactly this.
var saved_path: String = ""
var project: Project

var _name_label: Label
var _state_label: Label
var _dot: Label
var _menu: ProjectMenu
var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _rename_problem: Label


func _init(p_project: Project = null) -> void:
	project = p_project if p_project != null else Project.create()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	add_child(row)

	_name_label = Label.new()
	_name_label.theme_type_variation = "TitleLabel"
	_name_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
	row.add_child(_name_label)

	_dot = Label.new()
	_dot.text = "•"
	_dot.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(_dot)

	_state_label = Label.new()
	_state_label.theme_type_variation = "SmallLabel"
	row.add_child(_state_label)

	var caret := Label.new()
	caret.text = "▾"
	caret.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	row.add_child(caret)

	_menu = ProjectMenu.new()
	_menu.action_chosen.connect(_on_action_chosen)
	_menu.recent_chosen.connect(func(p: String) -> void: recent_chosen.emit(p))
	add_child(_menu)

	_build_rename_dialog()
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()


## Adopts a project and redraws. Used by New and Open when they exist; used by the suite now.
func set_project(p_project: Project, p_saved_path: String = "") -> void:
	project = p_project
	saved_path = p_saved_path
	refresh()


func refresh() -> void:
	_name_label.text = project.name if project != null else "Untitled build"
	_state_label.text = state_text()
	_state_label.tooltip_text = (
		"This drone has a name and an id, and nothing to write them to yet — the project "
		+ "container is the next slice." if saved_path == "" else saved_path)
	_dot.add_theme_color_override("font_color",
		LothalTheme.TEXT_MUTED if saved_path == "" else LothalTheme.SUCCESS)


## The state line. Derived from whether there is a path, so the "saved" wording is unreachable
## while nothing is written — which is the point (see the class comment).
func state_text() -> String:
	if saved_path == "":
		return "not saved anywhere yet"
	return "saved %s" % relative_time(
		int(Time.get_unix_time_from_system()) - _updated_unix())


## "4s ago", "3m ago", "yesterday". Written now, though only the unsaved branch above can reach it
## yet, because the RECENT list and the autosave line both need it and a second copy would drift.
##
## Thresholds are the ordinary ones. `just now` exists because a chip that says "0s ago" reads as
## broken, and the second after a save is when a builder is most likely to be looking at it.
static func relative_time(seconds: int) -> String:
	if seconds < 2:
		return "just now"
	if seconds < 60:
		return "%ds ago" % seconds
	if seconds < 3600:
		return "%dm ago" % int(seconds / 60.0)
	if seconds < 86400:
		return "%dh ago" % int(seconds / 3600.0)
	if seconds < 172800:
		return "yesterday"
	if seconds < 604800:
		return "%d days ago" % int(seconds / 86400.0)
	return "last week" if seconds < 1209600 else "%d weeks ago" % int(seconds / 604800.0)


func _updated_unix() -> int:
	if project == null or project.updated_at == "":
		return int(Time.get_unix_time_from_system())
	return int(Time.get_unix_time_from_datetime_string(project.updated_at))


# ---------------------------------------------------------------------------
# Opening the menu
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		open_menu()


## Drops the menu from the chip's bottom-left corner, so the name and the menu line up — the
## design's whole claim is that they are one control.
func open_menu() -> void:
	_menu.position = Vector2i(global_position) + Vector2i(0, int(size.y) + LothalTheme.SPACE_1)
	_menu.popup()


func menu() -> ProjectMenu:
	return _menu


## Fills RECENT from remembered paths. The label is the file's own name plus how long ago it was
## touched, which is what the design's mockup shows — and it comes from the FILE's modified time
## rather than from the document inside, so listing the menu never opens eight containers.
func set_recent_paths(paths: Array) -> void:
	var entries: Array = []
	var now := int(Time.get_unix_time_from_system())
	for path in paths:
		var file_path := String(path)
		if file_path == saved_path:
			continue
		var modified := int(FileAccess.get_modified_time(file_path))
		entries.append({
			"path": file_path,
			"label": "%s      %s" % [file_path.get_file().get_basename(),
				relative_time(now - modified)],
		})
	_menu.set_recent(entries)


# ---------------------------------------------------------------------------
# Rename — the one entry that works
# ---------------------------------------------------------------------------

func _build_rename_dialog() -> void:
	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename drone"
	_rename_dialog.theme = LothalTheme.get_theme()

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	_rename_field = LineEdit.new()
	_rename_field.custom_minimum_size = Vector2(320, 0)
	column.add_child(_rename_field)
	_rename_problem = Label.new()
	_rename_problem.add_theme_color_override("font_color", LothalTheme.DANGER)
	_rename_problem.visible = false
	column.add_child(_rename_problem)
	_rename_dialog.add_child(column)

	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)


func begin_rename() -> void:
	_rename_field.text = project.name
	_rename_problem.visible = false
	_rename_dialog.popup_centered()
	_rename_field.grab_focus()
	_rename_field.select_all()


## Applies a rename, or refuses it and says why. Returns "" when it went through.
##
## A blank name is refused rather than accepted-and-defaulted. "Untitled build" appearing where a
## builder typed spaces looks like the app lost the name they typed.
func submit_rename(new_name: String) -> String:
	var trimmed := new_name.strip_edges()
	if trimmed == "":
		return "A drone needs a name."
	project.name = trimmed
	project.touch()
	refresh()
	project_renamed.emit(trimmed)
	return ""


## AcceptDialog hides itself the instant OK is pressed, before `confirmed` reaches us, and there is
## no hook that prevents it — `_ok_pressed` is a C++ callable bound to the button. So a refused
## rename puts the dialog straight back up inside the same handler: the window never repaints in
## between and the builder sees a form that simply did not go away. Same shape as every custom-part
## dialog in this app, and the same bug avoided.
func _on_rename_confirmed() -> void:
	var problem := submit_rename(_rename_field.text)
	if problem == "":
		return
	_rename_problem.text = problem
	_rename_problem.visible = true
	_rename_dialog.show()


func _on_action_chosen(action_id: String) -> void:
	if action_id == "rename":
		begin_rename()
	action_chosen.emit(action_id)
