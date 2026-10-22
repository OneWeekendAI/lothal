class_name TestDiskChanges
extends RefCounted
## A drone's file changed by something that is not this app — a second Lothal, a script, an agent,
## a sync tool — while this app has the drone open.
##
## WHY THIS SUITE EXISTS. Autosave wrote the in-memory project over `user://builds/<id>.lothal`
## without looking at what was there. Twice on 2026-10-22 the parts block was edited from outside
## while the app was open, and the next autosave put the old parts back without a word. The
## container now remembers the file as it last read or wrote it, and the save step compares before
## it writes.
##
## Run the app's way: a shell in a tree, so `_ready` has wired the rails and a reload drives them
## exactly as opening a drone does — the rails' `_sync_project` firing mid-apply is the path that
## would quietly put this app's parts back into the document it just read. The autosave timer is
## stopped, and every check drives the tick (or the focus notification) itself, so nothing writes
## between the external change and the step under test.
##
## Each check was run with its fix taken out, and failed (6 of 6 mutations red):
## - `_save_container` not comparing the file: no-edits and local-edits both red (the Lab kept the
##   old battery; no copy appeared — `write` refused, so nothing was overwritten either);
## - the conflict copy failing to write: local-edits red (no reload, no copy);
## - `changed_on_disk` always true: the unchanged-file check red too (the edit never reached disk);
## - the focus handler ignoring NOTIFICATION_APPLICATION_FOCUS_IN: focus-in red;
## - `changed_on_disk` true for a file that is not there: missing-file red (nothing written);
## - `apply_project` handing `apply_selection` `project.parts` itself rather than a copy:
##   no-edits, local-edits and focus-in red — the reload read the file and showed the old battery.

const TEST_DIR := "user://test_disk_changes"
const SETTLE_FRAMES := 3
const WINDOW := Vector2i(1280, 720)


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var previous_settings: Variant = _read(AppSettings.SAVE_PATH)
	ProjectLibrary.ensure_dir()
	var builds_before := _lothal_files()
	_clean(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

	var frame := SubViewport.new()
	frame.size = WINDOW
	tree.root.add_child(frame)
	var shell := GlassShell.new()
	frame.add_child(shell)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	shell._autosave.stop()
	var other := _other_battery(shell)

	results.append(await _external_change_no_edits_reloads(tree, shell, other))
	results.append(await _external_change_with_edits_keeps_both(tree, shell, other))
	results.append(await _unchanged_file_saves(tree, shell))
	results.append(await _focus_in_reloads(tree, shell, other))
	results.append(await _missing_file_is_written(tree, shell))

	frame.queue_free()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	_clean(TEST_DIR)
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	for file in _lothal_files():
		if not builds_before.has(file):
			DirAccess.remove_absolute(absolute.path_join(file))
	_restore(AppSettings.SAVE_PATH, previous_settings)
	return results


# ---------------------------------------------------------------------------

static func _external_change_no_edits_reloads(tree: SceneTree, shell: GlassShell,
		other: String) -> TestResult:
	var path := await _opened(tree, shell, "no_edits")
	_change_outside(path, other)
	var disk := FileAccess.get_file_as_bytes(path)
	shell._on_autosave_tick()
	await _settle(tree)
	var fitted := str(shell.lab.selection()["battery"])
	var untouched := FileAccess.get_file_as_bytes(path) == disk
	return TestResult.new(
		"disk changes: an outside edit with nothing unsaved here is reloaded, not overwritten",
		fitted == other and untouched and _conflict_copies().is_empty(),
		"Lab battery %s (disk %s), file untouched %s, copies %d" % [fitted, other, untouched,
			_conflict_copies().size()])


static func _external_change_with_edits_keeps_both(tree: SceneTree, shell: GlassShell,
		other: String) -> TestResult:
	var path := await _opened(tree, shell, "with_edits")
	shell.container.project.name = "Edited here"
	_change_outside(path, other)
	var disk := FileAccess.get_file_as_bytes(path)
	shell._on_autosave_tick()
	await _settle(tree)
	var untouched := FileAccess.get_file_as_bytes(path) == disk
	var copies := _conflict_copies()
	var kept := ""
	if copies.size() == 1:
		var copy := ProjectContainer.open(String(copies[0]))
		kept = copy.project.name if copy != null else "(unreadable)"
	var fitted := str(shell.lab.selection()["battery"])
	var notice := shell.status_text()
	return TestResult.new(
		"disk changes: an outside edit with unsaved edits here keeps the disk and copies this app's",
		untouched and copies.size() == 1 and kept.begins_with("Edited here") and fitted == other
			and notice.contains("copy"),
		"file untouched %s, copies %d, copy named '%s', Lab battery %s, status '%s'" % [
			untouched, copies.size(), kept, fitted, notice])


static func _unchanged_file_saves(tree: SceneTree, shell: GlassShell) -> TestResult:
	var path := await _opened(tree, shell, "unchanged")
	shell.container.project.name = "Saved normally"
	shell._on_autosave_tick()
	var saved := ProjectContainer.open(path)
	var name := saved.project.name if saved != null else "(unreadable)"
	return TestResult.new(
		"disk changes: a file nobody else touched is saved as before",
		name == "Saved normally" and _conflict_copies().is_empty(),
		"file name '%s', copies %d" % [name, _conflict_copies().size()])


static func _focus_in_reloads(tree: SceneTree, shell: GlassShell, other: String) -> TestResult:
	var path := await _opened(tree, shell, "focus")
	_change_outside(path, other)
	var disk := FileAccess.get_file_as_bytes(path)
	shell.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _settle(tree)
	var fitted := str(shell.lab.selection()["battery"])
	var untouched := FileAccess.get_file_as_bytes(path) == disk
	return TestResult.new(
		"disk changes: coming back to the window shows an outside edit without a restart",
		fitted == other and untouched,
		"Lab battery %s (disk %s), file untouched %s" % [fitted, other, untouched])


static func _missing_file_is_written(tree: SceneTree, shell: GlassShell) -> TestResult:
	var path := await _opened(tree, shell, "missing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	shell.container.project.name = "Written again"
	shell._on_autosave_tick()
	var saved := ProjectContainer.open(path)
	var name := saved.project.name if saved != null else "(not there)"
	return TestResult.new(
		"disk changes: a file deleted from under the app is written again on the next save",
		name == "Written again",
		"file name '%s'" % name)


# ---------------------------------------------------------------------------

## A fresh drone on the reference battery, written to its own file and opened in the shell. Every
## check starts from one, with the test folder emptied, so no check can read another's file or copy.
static func _opened(tree: SceneTree, shell: GlassShell, stem: String) -> String:
	_clean(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var path := "%s/%s.%s" % [TEST_DIR, stem, ProjectContainer.EXTENSION]
	ProjectContainer.make(ProjectLibrary.starting_project("Disk %s" % stem)).write(path)
	shell.open_project(path)
	await _settle(tree)
	# Whatever the open normalised is saved now, so the check starts with nothing unsaved.
	shell._on_autosave_tick()
	return path


## What the outside writer does: read the file, change the parts block, write it back — through a
## container of its own, so it shares nothing with the shell's.
static func _change_outside(path: String, battery: String) -> void:
	var outside := ProjectContainer.open(path)
	outside.project.parts["battery"] = battery
	outside.write(path)


static func _other_battery(shell: GlassShell) -> String:
	var fitted := str(shell.lab.selection()["battery"])
	for part in PartsCatalog.load_default().list_category("battery"):
		var id := str((part as Dictionary)["part_id"])
		if id != fitted and id != ReferenceBuild.BATTERY_ID:
			return id
	return ""


static func _conflict_copies() -> Array:
	var out: Array = []
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return out
	for file in DirAccess.get_files_at(absolute):
		if file.contains(".conflict-") and file.ends_with("." + ProjectContainer.EXTENSION):
			out.append("%s/%s" % [TEST_DIR, file])
	return out


static func _settle(tree: SceneTree) -> void:
	for i in SETTLE_FRAMES:
		await tree.process_frame


static func _lothal_files() -> Array:
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return []
	return Array(DirAccess.get_files_at(absolute))


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_string(path)


static func _restore(path: String, previous: Variant) -> void:
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(String(previous))
	handle.close()


static func _clean(dir: String) -> void:
	var absolute := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
