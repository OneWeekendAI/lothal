class_name TestProjectWiring
extends RefCounted
## The container wired to the chip: New, Open, Duplicate, autosave and the recent list.
##
## ---------------------------------------------------------------------------
## WHERE THESE TESTS RUN, AND WHY IT IS NOT THE SHELL
## ---------------------------------------------------------------------------
##
## GlassShell wires itself in `_ready()`, which needs a tree and a rendered frame, and
## tests/run_tests.gd processes no frames by design (see TestGlassShell for what happened the last
## time a suite ignored that). So the checks below drive the two halves the shell only composes:
## LabScreen.apply_selection, which is the direction that makes opening a drone possible, and
## ProjectLibrary, which decides what a new one contains and where it goes.
##
## The one thing this cannot check is that the shell calls them, and that is honest rather than
## hidden: it is covered by tests/capture_glass_shell.gd, which boots the real thing.
##
## ---------------------------------------------------------------------------
## THE CHECKS THAT COULD HAVE PASSED WHILE PROVING NOTHING
## ---------------------------------------------------------------------------
##
## **1. "Opening a drone fits its parts."** Asserting that the rails hold the right ids after
## apply_selection passes if the rails ALREADY held them — and a fresh LabScreen opens on the
## reference build, which is exactly what a test would naturally save. So the project written here
## deliberately differs from the rails' opening state in every category, and the check asserts the
## ids moved.
##
## **2. "A missing part is reported."** Passes trivially against an apply that reports everything.
## So the same call carries five good ids and one dead one, and the check asserts the five landed.
##
## **3. "Duplicate copies the decisions."** Passes against a duplicate that copies the whole object,
## including its identity — which would give two drones one id and one file. The check asserts the
## id and the file path DIFFER while the parts match.

const TEST_DIR := "user://test_wiring"

static func run() -> Array:
	var results: Array = []
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_a_new_drone_is_a_real_starting_build(catalog))
	results.append_array(_test_opening_a_drone_moves_the_rails(catalog))
	results.append_array(_test_a_part_that_has_gone_is_named_and_the_rest_still_fit(catalog))
	results.append_array(_test_a_filter_cannot_hide_a_saved_drones_parts(catalog))
	results.append_array(_test_duplicate_is_a_different_drone())
	results.append_array(_test_autosave_writes_only_what_changed())
	results.append_array(_test_recent_remembers_without_claiming_files_exist())

	results.append_array(_test_recent_reads_the_drones_name())
	results.append_array(_test_delete_moves_to_trash())
	results.append_array(_test_new_drones_get_distinct_default_names())
	results.append_array(_test_delete_leaves_no_project())

	_clean()
	return results


## THE RECENT LIST NAMES DRONES, NOT FILES.
##
## The file is named after the project ID — a drone may be called "5 inch" or carry a slash, so the
## id is the part that is safe in a path. A label built from the filename therefore reads
## `01m0ajmppre0j35fytky0gtczr`, and that is exactly what the menu showed until read_name existed.
## Found by looking at a screenshot of the shipping app, not by a test.
##
## The check that would have proved nothing: writing a project whose name happens to equal its id,
## or asserting the label is non-empty. So the name below is deliberately unlike any id — spaces,
## a quote mark and a case pattern no generated id has — and the assertion is that the id does NOT
## appear in the label.
static func _test_recent_reads_the_drones_name() -> Array:
	var results: Array = []
	var project := ProjectLibrary.starting_project("Ritwik's 7\" long range")
	var container := ProjectContainer.make(project)
	var path := "%s/%s.%s" % [TEST_DIR, project.project_id, ProjectContainer.EXTENSION]
	container.write(path)

	results.append(TestResult.new(
		"a remembered drone is listed by its name, not by the id its file is called",
		ProjectContainer.read_name(path) == project.name
			and not ProjectContainer.read_name(path).contains(project.project_id),
		"reads back as '%s' (file is %s)" % [
			ProjectContainer.read_name(path), path.get_file()]))

	# A file that will not open is still a file the builder can point at. A blank row would be the
	# one entry they cannot describe when asking what happened to it.
	var broken := "%s/not-a-container.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	var handle := FileAccess.open(broken, FileAccess.WRITE)
	handle.store_string("this is not a zip")
	handle.close()
	results.append(TestResult.new(
		"and a file that will not open still gets a label rather than a blank row",
		ProjectContainer.read_name(broken) == "not-a-container",
		"reads back as '%s'" % ProjectContainer.read_name(broken)))

	return results


static func _test_a_new_drone_is_a_real_starting_build(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var project := ProjectLibrary.starting_project("Fresh")
	var build := project.to_build(catalog)

	# §5: a blank canvas is the worst possible first screen. A new drone is a whole aircraft.
	results.append(TestResult.new(
		"a new drone is a complete, known-good aircraft rather than an empty canvas",
		build != null and absf(build.all_up_weight_g() - 507.48) < 0.05,
		"%.2f g" % (0.0 if build == null else build.all_up_weight_g())
	))
	results.append(TestResult.new(
		"and it is named after its id on disk, so renaming can never move the file",
		ProjectLibrary.path_for(project).ends_with(
			"%s.%s" % [project.project_id, ProjectContainer.EXTENSION]),
		ProjectLibrary.path_for(project)
	))
	return results


static func _test_opening_a_drone_moves_the_rails(catalog: PartsCatalog) -> Array:
	var lab := LabScreen.new(catalog)
	var opening := lab.selection()

	# A drone that differs from the rails' opening state in every category, so nothing below can
	# pass by accident.
	var wanted := {
		"frame": "frame_3in_toothpick",
		"motor": "motor_1404_3800kv",
		"propeller": "prop_3x3x3",
		"battery": "battery_3s_650",
		"esc": "esc_4in1_20a_20x20",
		"flight_controller": "fc_f405_20x20",
	}
	var different := true
	for category in wanted:
		if String(opening.get(category, "")) == String(wanted[category]):
			different = false

	var failed := lab.apply_selection(wanted)
	var after := lab.selection()
	var landed := true
	for category in wanted:
		if String(after.get(category, "")) != String(wanted[category]):
			landed = false

	var results: Array = [TestResult.new(
		"opening a drone fits every one of its parts on the rails",
		different and failed.is_empty() and landed,
		"differed from the opening state: %s · failed: %s" % [different, failed]
	)]

	# And the aircraft that comes out the other side is the one that was asked for, not the one the
	# rails happened to be showing.
	var build := Build.from_ids(catalog, wanted["frame"], wanted["motor"], wanted["propeller"],
		wanted["battery"], wanted["esc"], wanted["flight_controller"])
	results.append(TestResult.new(
		"and the aircraft on screen is the one in the file",
		build != null and absf(build.all_up_weight_g()
			- lab.current_build().all_up_weight_g()) < 0.05,
		"%.2f g on the rails vs %.2f g from the ids" % [
			lab.current_build().all_up_weight_g(), build.all_up_weight_g()]
	))
	lab.free()
	return results


static func _test_a_part_that_has_gone_is_named_and_the_rest_still_fit(
		catalog: PartsCatalog) -> Array:
	var lab := LabScreen.new(catalog)
	var wanted := {
		"frame": "frame_3in_toothpick",
		"motor": "motor_deleted_last_year",
		"propeller": "prop_3x3x3",
		"battery": "battery_3s_650",
		"esc": "esc_4in1_20a_20x20",
		"flight_controller": "fc_f405_20x20",
	}
	var failed := lab.apply_selection(wanted)
	var after := lab.selection()

	var results: Array = [TestResult.new(
		"a part that has left the catalog is reported by name",
		failed.size() == 1
			and String((failed[0] as Dictionary)["category"]) == "motor"
			and String((failed[0] as Dictionary)["part_id"]) == "motor_deleted_last_year",
		"failed: %s" % [failed]
	)]
	results.append(TestResult.new(
		"and every other part of that drone still fits",
		String(after["frame"]) == "frame_3in_toothpick"
			and String(after["propeller"]) == "prop_3x3x3"
			and String(after["battery"]) == "battery_3s_650"
			and String(after["esc"]) == "esc_4in1_20a_20x20"
			and String(after["flight_controller"]) == "fc_f405_20x20",
		"after: %s" % [after]
	))
	results.append(TestResult.new(
		"and the rail it could not fit was left where it was, not defaulted",
		String(after["motor"]) != "motor_deleted_last_year",
		"motor rail holds %s" % after["motor"]
	))
	lab.free()
	return results


## The bug this direction shipped with, found by writing the test above.
##
## `select_id` searched only the VISIBLE parts, which is right for its original caller — a click on
## the list the builder is looking at — and silently wrong for this one. A builder who left the
## size filter on 5" and opened their 3" toothpick would have had three parts fail to fit, no
## message, and an aircraft on screen that is not the one in the file. The worst kind of bug this
## feature could have: quiet, and about the numbers.
static func _test_a_filter_cannot_hide_a_saved_drones_parts(catalog: PartsCatalog) -> Array:
	var lab := LabScreen.new(catalog)

	# The builder was browsing 5" frames. Their saved drone is a 3" toothpick.
	lab.picker.set_filter("size_class", "5\"")
	var hidden := true
	for part in lab.picker.visible_parts():
		if String(part["part_id"]) == "frame_3in_toothpick":
			hidden = false

	var failed := lab.apply_selection({"frame": "frame_3in_toothpick"})
	var results: Array = [TestResult.new(
		"a filter the builder left on cannot stop a saved drone's part from being fitted",
		hidden and failed.is_empty()
			and String(lab.selection()["frame"]) == "frame_3in_toothpick",
		"hidden by the filter first: %s · frame now %s" % [hidden, lab.selection()["frame"]]
	)]

	# And an id that genuinely is not in the catalog must still fail — otherwise the fix above
	# would have turned "report it by name" into "clear the filters and select something".
	results.append(TestResult.new(
		"and an id that is not in the catalog at all is still refused",
		not lab.picker.select_id("frame_that_never_existed"),
		"select_id returned %s" % lab.picker.select_id("frame_that_never_existed")
	))
	lab.free()
	return results


static func _test_duplicate_is_a_different_drone() -> Array:
	var results: Array = []
	var source := ProjectLibrary.starting_project("Weekend 5")
	source.assembly["plate_gap_mm"] = 9.0
	source.add_version("before the swap")

	var copy := ProjectLibrary.duplicate_of(source)
	results.append(TestResult.new(
		"a duplicate carries the decisions and takes a new identity",
		copy.project_id != source.project_id
			and copy.parts == source.parts
			and is_equal_approx(float(copy.assembly["plate_gap_mm"]), 9.0)
			and ProjectLibrary.path_for(copy) != ProjectLibrary.path_for(source),
		"'%s' vs '%s'" % [copy.name, source.name]
	))
	results.append(TestResult.new(
		"and starts its own history rather than inheriting the original's versions",
		copy.versions.is_empty() and source.versions.size() == 1,
		"copy has %d versions, source has %d" % [copy.versions.size(), source.versions.size()]
	))
	results.append(TestResult.new(
		"and the copies sort next to what they came from",
		copy.name == "Weekend 5 copy"
			and ProjectLibrary.duplicate_of(copy).name == "Weekend 5 copy 2"
			and ProjectLibrary.duplicate_of(ProjectLibrary.duplicate_of(copy)).name
				== "Weekend 5 copy 3",
		"'%s' then '%s'" % [copy.name, ProjectLibrary.duplicate_of(copy).name]
	))
	return results


static func _test_autosave_writes_only_what_changed() -> Array:
	var results: Array = []
	var path := "%s/auto.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	var container := ProjectContainer.make(ProjectLibrary.starting_project("Autosaved"))
	container.write(path)

	results.append(TestResult.new(
		"an idle drone gives autosave nothing to do",
		not container.has_unsaved_changes(),
		"has_unsaved_changes=%s" % container.has_unsaved_changes()
	))

	# A tweak, the way sliding the pack would arrive.
	container.project.assembly["battery_offset_mm"] = -8.0
	var ticked := container.has_unsaved_changes()
	container.write()

	var reopened := ProjectContainer.open(path)
	results.append(TestResult.new(
		"and one that moved is on disk a tick later, tweak and all",
		ticked and reopened != null
			and is_equal_approx(float(reopened.project.assembly["battery_offset_mm"]), -8.0),
		"offset on disk: %s" % (reopened.project.assembly.get("battery_offset_mm")
			if reopened != null else "(unopened)")
	))
	return results


static func _test_recent_remembers_without_claiming_files_exist() -> Array:
	var results: Array = []
	var settings_path := TEST_DIR + "/settings.json"
	var real := "%s/auto.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	var gone := "%s/deleted.%s" % [TEST_DIR, ProjectContainer.EXTENSION]

	var settings := AppSettings.new()
	settings.remember_project(gone)
	settings.remember_project(real)
	settings.remember_project(gone)
	results.append(TestResult.new(
		"a drone opened twice appears once, at the front",
		settings.recent_projects == [gone, real],
		"%s" % [settings.recent_projects]
	))

	settings.save(settings_path)
	var reloaded := AppSettings.load_from(settings_path)
	results.append(TestResult.new(
		"the list survives a restart",
		reloaded.recent_projects == [gone, real],
		"%s" % [reloaded.recent_projects]
	))
	results.append(TestResult.new(
		"and a drone deleted outside Lothal simply stops being offered",
		reloaded.existing_recent_projects() == [real],
		"%s" % [reloaded.existing_recent_projects()]
	))

	# The in-app half: a drone Lothal itself deleted is forgotten, not merely filtered out of the
	# menu. The file-gone filter above is for paths that vanish OUTSIDE the app, where Lothal cannot
	# know; here it knows it moved the file, so knowing is different from tolerating.
	settings.forget_project(gone)
	results.append(TestResult.new(
		"and one Lothal deletes is removed from the list, not just hidden",
		settings.recent_projects == [real],
		"%s" % [settings.recent_projects]
	))

	# The cap, checked at the boundary rather than trusted.
	var many := AppSettings.new()
	for i in AppSettings.RECENT_LIMIT + 5:
		many.remember_project("%s/d%d.lothal" % [TEST_DIR, i])
	results.append(TestResult.new(
		"and the list does not grow into something nobody reads",
		many.recent_projects.size() == AppSettings.RECENT_LIMIT
			and String(many.recent_projects[0]).ends_with("d12.lothal"),
		"%d entries, newest %s" % [many.recent_projects.size(), many.recent_projects[0]]
	))
	return results


## The delete feature (§10 of the projects design): a rename into the app's trash, never an
## unlink. The easy version — unlink with a confirmation — makes losing a month of design one
## misplaced click, and the trash is the design's answer to that.
##
## The check that would have proved nothing: asserting the original path is gone. That passes
## against an unlink. So the same call also asserts the file EXISTS in `user://builds/trash/`
## and opens as a valid container — which only a move can satisfy.
static func _test_delete_moves_to_trash() -> Array:
	var results: Array = []
	var project := ProjectLibrary.starting_project("Doomed")
	var container := ProjectContainer.make(project)
	var path := "%s/%s.%s" % [TEST_DIR, project.project_id, ProjectContainer.EXTENSION]
	container.write(path)

	ProjectLibrary.delete(path)

	var trash := "%s/trash/%s.%s" % [ProjectLibrary.DIR, project.project_id,
		ProjectContainer.EXTENSION]
	results.append(TestResult.new(
		"a deleted drone is gone from where it lived",
		not FileAccess.file_exists(path),
		"%s removed" % path
	))
	results.append(TestResult.new(
		"and sits in the app's trash, still openable",
		FileAccess.file_exists(trash) and ProjectContainer.open(trash) != null,
		"trash holds %s" % trash
	))
	# The trash is real app-owned storage; take the file back out so the suite leaves it clean.
	if FileAccess.file_exists(trash):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(trash))
	return results


## The two fixes for the delete-that-looked-like-nothing bug.
##
## **1. Distinct default names.** Every New drone was named "Untitled build", so a wall of
## identical projects accumulated and deleting one was indistinguishable from having done nothing —
## the replacement was named the same as the thing deleted. A new drone's default name now comes
## from what is already on disk, so consecutive drones are distinct.
##
## **2. Delete leaves nothing open.** Delete used to adopt a fresh starting project in the same
## second, which is the second half of why delete looked inert. Delete now closes the drone and
## creates nothing; the chip says so, and the builds folder does not grow.
static func _test_new_drones_get_distinct_default_names() -> Array:
	var results: Array = []
	var first := ProjectLibrary.starting_project()
	# A new drone is only on disk once New adopts it, and the NEXT default name is derived from what
	# is on disk — so the write between the two calls is the flow, not test scaffolding.
	ProjectContainer.make(first).write(ProjectLibrary.path_for(first))
	var second := ProjectLibrary.starting_project()
	results.append(TestResult.new(
		"two new drones get different default names",
		first.name != second.name
			and ProjectLibrary._untitled_number(second.name)
				> ProjectLibrary._untitled_number(first.name),
		"'%s' then '%s'" % [first.name, second.name]
	))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.path_for(first)))
	return results


static func _test_delete_leaves_no_project() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	var project := ProjectLibrary.starting_project("Doomed shell")
	var builds := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	var before := DirAccess.get_files_at(builds)
	shell.adopt(project)
	var gone := shell.container.path

	shell._on_project_action("delete")

	var after := DirAccess.get_files_at(builds)
	results.append(TestResult.new(
		"delete closes the drone and opens nothing",
		shell.container == null and shell.chip.project == null,
		"container=%s chip-project=%s" % [shell.container, shell.chip.project]
	))
	results.append(TestResult.new(
		"and writes no replacement drone",
		after.size() == before.size()
			and not after.has(gone.get_file())
			and not FileAccess.file_exists(gone),
		"%d files after (before was %d), gone=%s" % [after.size(), before.size(),
			not FileAccess.file_exists(gone)]
	))
	results.append(TestResult.new(
		"and the chip says there is no drone",
		shell.chip.state_text() == "no drone open",
		"'%s'" % shell.chip.state_text()
	))
	# The move lands in the app's trash; take it back out so the suite leaves the app clean.
	var trash_file := "%s/trash/%s.%s" % [ProjectLibrary.DIR,
		project.project_id, ProjectContainer.EXTENSION]
	if FileAccess.file_exists(trash_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(trash_file))
	shell.free()
	return results


static func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
