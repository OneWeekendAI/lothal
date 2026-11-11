class_name TestOpenProjects
extends RefCounted
## M14 (MERGE_TRACKER): the Open dialog lists the drones on disk (Projects), with sort and delete, and choosing
## one swaps the whole project in. Replaces the Projects room of the "..." menu.
##   - the Projects section lists every saved drone, newest first, and the sort button flips it to by-name;
##   - choosing a row reports the drone's path (DesignSpace re-emits it, the shell opens it);
##   - Delete is two presses (the first only asks), then MOVES the file to the trash and redraws;
##   - the drone open now cannot be deleted;
##   - end to end: through a DesignApp, picking another drone (another class) in the dialog opens it.
##
## MUTATION: removing the delete's second-press branch (delete on first press) fails "the first press only asks";
## making `sorted` ignore its mode fails the sort check; dropping the project_open_requested connection fails the
## end-to-end swap.

const SCRATCH := "user://test_open_projects"


static func _make(name: String, drone_class: String, age_s: int) -> String:
	var p := DroneClass.starting_project(drone_class, name)
	var stamp := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - age_s) + "Z"
	p.created_at = stamp
	p.updated_at = stamp
	var path := ProjectLibrary.path_for(p)
	ProjectContainer.make(p).write(path, SCRATCH + "/parts.json")
	return path


static func _names(bar: DesignFileBar) -> Array:
	var out: Array = []
	for r in bar.project_rows:
		var b := (r as Node).get_node_or_null("Open")
		if b != null:
			out.append((b as Button).text)
	return out


static func _clean() -> void:
	for sub in ["", "/trash"]:
		var dir := ProjectSettings.globalize_path(SCRATCH + sub)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH + "/trash"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	var held := RealFiles.hold([AppSettings.SAVE_PATH, AssemblyTweaks.SAVE_PATH])
	var saved_root := ProjectLibrary.root
	ProjectLibrary.root = SCRATCH
	_clean()
	ProjectLibrary.ensure_dir()
	var old_path := _make("Alpha", "five_inch", 7200)
	var new_path := _make("Zulu", "five_inch", 60)
	var mid_path := _make("Mike", "seven_lr", 3600)

	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), PartsCatalog.load_default())
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	await tree.process_frame
	ds.current_project = func() -> String: return new_path
	var opened: Array = []
	var deleted: Array = []
	ds.project_open_requested.connect(func(p: String): opened.append(p))
	ds.project_deleted.connect(func(p: String): deleted.append(p))
	ds.open_open_dialog()
	var bar := ds.file_bar

	var listed := _names(bar)
	listed.sort()
	out.append(TestResult.new("the Open dialog lists the drones on disk", listed == ["Alpha", "Mike", "Zulu"], str(listed)))
	# A container's write stamps "now", so the three files share a second: the order is checked on entries with
	# distinct edit times (the same shape ProjectRows.list returns).
	var entries := ProjectRows.list(null)
	var age := {"Zulu": 60, "Mike": 3600, "Alpha": 7200}
	for e in entries:
		e["updated_unix"] = int(Time.get_unix_time_from_system()) - int(age[String(e["name"])])
	bar.refresh_projects(entries)
	out.append(TestResult.new("the list is last edited first", _names(bar) == ["Zulu", "Mike", "Alpha"], str(_names(bar))))
	bar.project_sort_button.pressed.emit()
	out.append(TestResult.new("the sort button flips the list to by name",
		_names(bar) == ["Alpha", "Mike", "Zulu"], str(_names(bar))))
	bar.project_sort_button.pressed.emit()
	out.append(TestResult.new("and back to last edited", _names(bar) == ["Zulu", "Mike", "Alpha"], str(_names(bar))))

	var alpha := _row(bar, "Alpha")
	var zulu := _row(bar, "Zulu")
	(alpha.get_node("Open") as Button).pressed.emit()
	out.append(TestResult.new("choosing a row asks the shell to open that drone", opened == [old_path], str(opened)))
	out.append(TestResult.new("the drone open now has Delete disabled", (zulu.get_node("Delete") as Button).disabled, ""))
	out.append(TestResult.new("and delete_project refuses it", not ds.delete_project(new_path) and FileAccess.file_exists(new_path), ""))

	(alpha.get_node("Delete") as Button).pressed.emit()
	out.append(TestResult.new("the first Delete press only asks: the file stays and the button reads Delete?",
		FileAccess.file_exists(old_path) and deleted.is_empty()
			and (_row(bar, "Alpha").get_node("Delete") as Button).text == "Delete?", ""))
	(_row(bar, "Alpha").get_node("Delete") as Button).pressed.emit()
	var trash := "%s/trash/%s" % [SCRATCH, old_path.get_file()]
	out.append(TestResult.new("the second press moves the file to the trash (never an unlink) and tells the shell",
		not FileAccess.file_exists(old_path) and FileAccess.file_exists(trash) and deleted == [old_path], str(deleted)))
	var left := _names(bar)
	left.sort()
	out.append(TestResult.new("the section redraws without it", left == ["Mike", "Zulu"], str(left)))
	ds.queue_free()
	await tree.process_frame

	# End to end through the shell: a drone of another class swaps in.
	var frame := SubViewport.new()
	frame.size = Vector2i(1280, 720)
	tree.root.add_child(frame)
	var app := DesignApp.new()
	frame.add_child(app)
	for i in 3:
		await tree.process_frame
	app.interactive = true
	app.open_project(new_path)
	for i in 8:
		await tree.process_frame
	var first_class := app.design_space.session.drone_class
	app.design_space.open_open_dialog()
	var mike := _row(app.design_space.file_bar, "Mike")
	(mike.get_node("Open") as Button).pressed.emit()
	for i in 8:
		await tree.process_frame
	out.append(TestResult.new("end to end: picking another drone in the Open dialog opens it (name and class swap)",
		app.container.path == mid_path and app.design_space.session.drone_class == "seven_lr" and first_class == "five_inch",
		"path=%s class=%s was %s" % [app.container.path, app.design_space.session.drone_class, first_class]))
	frame.queue_free()
	await tree.process_frame
	_clean()
	ProjectLibrary.root = saved_root
	held.restore()
	return out


static func _row(bar: DesignFileBar, name: String) -> Node:
	for r in bar.project_rows:
		var b := (r as Node).get_node_or_null("Open")
		if b != null and (b as Button).text == name:
			return r
	return null
