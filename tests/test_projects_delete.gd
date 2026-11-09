class_name TestProjectsDelete
extends RefCounted
## The "⋯" row menu on the Projects table (src/ui/projects_screen.gd): Delete, Rename, Reveal.
##
## Everything runs against a temporary library: `ProjectLibrary.root` is pointed at a scratch folder
## and restored after, so the builder's real `user://builds` is never read, moved or written.
##
## The checks that matter are the ones a plausible wrong version passes:
## - the click ASKS (a version that deletes straight away passes "Delete removes it");
## - Cancel leaves the file on disk, not merely the row on screen;
## - the delete is a MOVE to trash, so the file must exist there afterwards;
## - the ⋯ button does not also open the project (it sits inside the row's button).
## The dialog assertions read `visible`: AcceptDialog closes itself on OK, so a dialog that is
## "confirmed" is gone by the time the handler looks, and an unasserted `visible` proves nothing.

const SCRATCH := "user://test_projects_delete"


static func run() -> Array:
	var results: Array = []
	var saved_root := ProjectLibrary.root
	ProjectLibrary.root = SCRATCH
	_clean()
	ProjectLibrary.ensure_dir()

	var keep := Project.create("Keeper")
	var doomed := Project.create("Doomed")
	for p in [keep, doomed]:
		ProjectContainer.make(p).write(ProjectLibrary.path_for(p), SCRATCH + "/parts.json")
	var doomed_path := ProjectLibrary.path_for(doomed)
	var keep_path := ProjectLibrary.path_for(keep)

	var screen := ProjectsScreen.new(null)
	screen.refresh()
	var chosen: Array = []
	screen.project_chosen.connect(func(p: String) -> void: chosen.append(p))

	screen.custom_parts_path = SCRATCH + "/parts.json"
	var opened: Array = []
	screen.opener = func(c: Dictionary) -> void: opened.append(c)
	screen.os_name = "macOS"

	var more := _more_for(screen, "Doomed")
	results.append(TestResult.new("every row has a ⋯ button",
		more != null and _more_for(screen, "Keeper") != null, "more=%s" % more))
	if more == null:
		screen.free()
		_clean()
		ProjectLibrary.root = saved_root
		return results

	# --- the menu itself -------------------------------------------------------------------
	more.pressed.emit()
	results.append(TestResult.new("pressing ⋯ opens the menu and does not open the project",
		screen._menu.visible and chosen.is_empty(), "visible=%s chosen=%s" % [screen._menu.visible, chosen]))
	results.append(TestResult.new("the menu has Rename, a file-manager item and Delete",
		screen._menu.get_item_text(0) == "Rename" and screen._menu.get_item_text(1) == "Show in Finder"
		and screen._menu.get_item_text(3) == "Delete",
		"%s / %s / %s" % [screen._menu.get_item_text(0), screen._menu.get_item_text(1), screen._menu.get_item_text(3)]))
	for pair in [["macOS", "Show in Finder"], ["Windows", "Show in Explorer"], ["Linux", "Show in file manager"],
			["FreeBSD", "Show in file manager"]]:
		screen.os_name = pair[0]
		screen.open_menu(doomed_path, "Doomed")
		results.append(TestResult.new("on %s the item reads '%s'" % pair,
			screen._menu.get_item_text(1) == pair[1], "got '%s'" % screen._menu.get_item_text(1)))

	# --- Reveal ----------------------------------------------------------------------------
	var absolute := ProjectSettings.globalize_path(doomed_path)
	screen.os_name = "macOS"
	screen.open_menu(doomed_path, "Doomed")
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_REVEAL)
	results.append(TestResult.new("macOS reveal runs `open -R <file>` on the build file",
		opened.size() == 1 and opened[0] == {"kind": "execute", "program": "open", "args": ["-R", absolute]},
		"opened=%s" % [opened]))
	opened.clear()
	screen.os_name = "Windows"
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_REVEAL)
	results.append(TestResult.new("Windows reveal runs `explorer /select,<file>` with backslashes",
		opened.size() == 1 and opened[0]["program"] == "explorer"
		and opened[0]["args"] == ["/select," + absolute.replace("/", "\\")],
		"opened=%s" % [opened]))
	opened.clear()
	screen.os_name = "Linux"
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_REVEAL)
	results.append(TestResult.new("Linux reveal opens the file's folder",
		opened.size() == 1 and opened[0] == {"kind": "shell_open", "path": absolute.get_base_dir()},
		"opened=%s" % [opened]))
	results.append(TestResult.new("revealing never opens the project",
		chosen.is_empty(), "chosen=%s" % [chosen]))

	# --- Rename ----------------------------------------------------------------------------
	var renamed: Array = []
	screen.project_renamed.connect(func(p: String, n: String) -> void: renamed.append([p, n]))
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_RENAME)
	results.append(TestResult.new("Rename shows a dialog prefilled with the current name",
		screen._rename.visible and screen._rename_field.text == "Doomed",
		"visible=%s text='%s'" % [screen._rename.visible, screen._rename_field.text]))

	screen._rename_field.text = "   "
	screen._rename.hide()  # AcceptDialog closes itself on OK before `confirmed` fires
	screen._rename.confirmed.emit()
	results.append(TestResult.new("an empty name is refused and the dialog stays visible",
		screen._rename.visible and screen._rename_problem.visible
		and screen._rename_problem.text != "" and renamed.is_empty()
		and ProjectContainer.read_name(doomed_path) == "Doomed",
		"visible=%s problem='%s' renamed=%s name='%s'" % [screen._rename.visible,
			screen._rename_problem.text, renamed, ProjectContainer.read_name(doomed_path)]))

	screen._rename_field.text = "  Phoenix  "
	screen._rename.hide()
	screen._rename.confirmed.emit()
	results.append(TestResult.new("a valid name is written to the file, trimmed",
		ProjectContainer.read_name(doomed_path) == "Phoenix" and renamed == [[doomed_path, "Phoenix"]],
		"name='%s' renamed=%s" % [ProjectContainer.read_name(doomed_path), renamed]))
	results.append(TestResult.new("the dialog goes away after a good rename",
		not screen._rename.visible, "visible=%s" % screen._rename.visible))
	results.append(TestResult.new("the list refreshes: new name shown, old name gone",
		_more_for(screen, "Phoenix") != null and _more_for(screen, "Doomed") == null
		and screen.entries.size() == 2, "entries=%d" % screen.entries.size()))
	results.append(TestResult.new("the file keeps its path, so a recents entry still points at it",
		FileAccess.file_exists(doomed_path), "exists=%s" % FileAccess.file_exists(doomed_path)))
	results.append(TestResult.new("renaming never opens the project", chosen.is_empty(), "chosen=%s" % [chosen]))

	# --- Delete, through the menu ----------------------------------------------------------
	more = _more_for(screen, "Phoenix")
	more.pressed.emit()
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_DELETE)
	results.append(TestResult.new("menu Delete asks \"Delete 'Phoenix'?\" and touches nothing yet",
		screen._confirm.visible and screen._confirm.dialog_text == "Delete 'Phoenix'?"
		and FileAccess.file_exists(doomed_path),
		"visible=%s text='%s' exists=%s" % [screen._confirm.visible,
			screen._confirm.dialog_text, FileAccess.file_exists(doomed_path)]))

	screen._confirm.canceled.emit()
	results.append(TestResult.new("Cancel keeps the project, on disk and in the list",
		FileAccess.file_exists(doomed_path) and screen.entries.size() == 2,
		"exists=%s entries=%d" % [FileAccess.file_exists(doomed_path), screen.entries.size()]))
	screen._on_delete_confirmed()  # a stray confirm after Cancel must do nothing
	results.append(TestResult.new("a confirm after Cancel deletes nothing",
		FileAccess.file_exists(doomed_path), "exists=%s" % FileAccess.file_exists(doomed_path)))

	more = _more_for(screen, "Phoenix")
	more.pressed.emit()
	screen._menu.id_pressed.emit(ProjectsScreen.MENU_DELETE)
	var gone: Array = []
	screen.project_deleted.connect(func(p: String) -> void: gone.append(p))
	screen._confirm.confirmed.emit()
	var trash := "%s/%s/%s" % [SCRATCH, ProjectLibrary.TRASH_SUBDIR, doomed_path.get_file()]
	results.append(TestResult.new("Delete moves it to the trash folder, not an unlink",
		not FileAccess.file_exists(doomed_path) and FileAccess.file_exists(trash)
		and FileAccess.file_exists(keep_path),
		"original=%s trash=%s keeper=%s" % [FileAccess.file_exists(doomed_path),
			FileAccess.file_exists(trash), FileAccess.file_exists(keep_path)]))
	results.append(TestResult.new("after Delete the list, the count and the pager refresh",
		screen.entries.size() == 1 and _more_for(screen, "Phoenix") == null
		and screen._range_label.text == "1–1 of 1" and gone == [doomed_path],
		"entries=%d range='%s' gone=%s" % [screen.entries.size(), screen._range_label.text, gone]))
	results.append(TestResult.new("the project is never opened by deleting it",
		chosen.is_empty(), "chosen=%s" % [chosen]))

	var mark := screen.find_child("LogoMark", true, false)
	results.append(TestResult.new("the header carries the drawn Lothal mark, square, not the old text glyph",
		mark != null and mark.custom_minimum_size.x == mark.custom_minimum_size.y
		and screen.find_children("*", "Label", true, false).all(func(l: Label) -> bool: return not l.text.contains("◇")),
		"mark=%s" % mark))

	# --- look: the dialogs carry their title inside the panel, no native title bar ---------
	for d in [screen._rename, screen._confirm]:
		results.append(TestResult.new("dialog has an in-panel title and a collapsed native title bar",
			d.get_meta("heading") is Label and (d.get_meta("heading") as Label).text != ""
			and d.get_theme_constant("title_height") == 0,
			"title_height=%d" % d.get_theme_constant("title_height")))

	screen.free()
	_clean()
	ProjectLibrary.root = saved_root
	return results


static func _more_for(screen: ProjectsScreen, drone_name: String) -> Button:
	for row in screen._rows.get_children():
		if row is Button and row.has_node("More") \
				and row.get_node("More").tooltip_text == "More actions for '%s'" % drone_name:
			return row.get_node("More")
	return null


static func _clean() -> void:
	_rm(ProjectSettings.globalize_path(SCRATCH))


static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)
