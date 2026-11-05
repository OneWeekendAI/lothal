class_name TestPropRepoint
extends RefCounted
## PD14: every Lab entry follows through to the prop designer, and none reaches the old room. The old
## room's own tests still drive `set_blade_room_open`, which stays in code until the owner's sign-off.

const OTHER_PROP := "prop_7x35x2"


static func run() -> Array:
	return [
		_test_rail_door_opens_designer(),
		_test_inspector_button_opens_designer_on_shown_prop(),
		_test_rail_new_action_opens_designer(),
		_test_rail_new_action_survives_a_catalog_reload(),
		_test_finder_new_action_opens_designer(),
		_test_no_source_opens_the_old_room(),
		_test_second_open_is_the_same_designer(),
		_test_close_clears_the_designer(),
		_test_keys_stay_out_of_the_lab_while_up(),
		_test_saved_and_fitted_reach_the_lab(),
		_test_session_is_the_labs_drone_as_it_stands(),
		_test_shelf_prop_starts_a_new_prop(),
		_test_saved_prop_reopens_under_its_id(),
	]


static func _shell() -> GlassShell:
	return GlassShell.new()


static func _went_to_designer(shell: GlassShell) -> bool:
	return shell.prop_designer != null and not shell.blade_room().visible and not shell.page_open()


static func _system(name: String) -> int:
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == name:
			return i
	return -1


static func _new_button(rail: Control) -> Button:
	for b in rail.find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("New custom propeller"):
			return b
	return null


static func _test_rail_door_opens_designer() -> TestResult:
	var shell := _shell()
	shell._focused_index = _system("Propulsion")
	shell._on_room_door_pressed()
	var ok := _went_to_designer(shell)
	shell.free()
	return TestResult.new("[PD14] the rail's Design blade door opens the designer, not the room", ok, "")


static func _test_inspector_button_opens_designer_on_shown_prop() -> TestResult:
	var shell := _shell()
	var panel := shell.lab.propeller_details
	var shown := shell.lab.catalog.get_part(OTHER_PROP)
	panel.render(shown, shell.lab.current_build())
	var pressed := 0
	for b in panel.find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("Design"):
			(b as Button).pressed.emit()
			pressed += 1
	var ok := pressed == 1 and _went_to_designer(shell)
	var source := shell.prop_designer.source_name if shell.prop_designer != null else ""
	shell.free()
	return TestResult.new("[PD14] Design this blade opens the designer on the prop shown",
		ok and source == str(shown["name"]), "%d pressed, source %s" % [pressed, source])


static func _test_rail_new_action_opens_designer() -> TestResult:
	var shell := _shell()
	var windows_before := shell.lab.propeller_picker.find_children("*", "Window", true, false).size()
	_new_button(shell.lab.propeller_picker).pressed.emit()
	var windows := shell.lab.propeller_picker.find_children("*", "Window", true, false).size()
	var ok := _went_to_designer(shell) and windows == windows_before
	shell.free()
	return TestResult.new("[PD14] New custom propeller opens the designer, not the old form", ok,
		"%d dialogs before, %d after" % [windows_before, windows])


## The rail is rebuilt by a reload, so a connection made once by hand would silently be gone.
static func _test_rail_new_action_survives_a_catalog_reload() -> TestResult:
	var shell := _shell()
	shell.lab.reload_catalog()
	_new_button(shell.lab.propeller_picker).pressed.emit()
	var ok := _went_to_designer(shell)
	shell.free()
	return TestResult.new("[PD14] the rail's New action still opens the designer after a reload", ok, "")


static func _test_finder_new_action_opens_designer() -> TestResult:
	var shell := _shell()
	var index := _system("Propulsion")
	var slot := -1
	var titles: Array = GlassShell.SYSTEMS[index]["rails"]
	for i in titles.size():
		if shell._rail_for_system(index, i) == shell.lab.propeller_picker:
			slot = i
	shell._on_finder_authoring(index, slot, 0)
	var ok := slot >= 0 and _went_to_designer(shell)
	shell.free()
	return TestResult.new("[PD14] the finder's New action opens the designer", ok, "slot %d" % slot)


## A new door would not press any button above, so the source is asked as well.
static func _test_no_source_opens_the_old_room() -> TestResult:
	var bad: Array = []
	var dirs := ["res://src/ui", "res://src/lab", "res://src/design"]
	for dir in dirs:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string("%s/%s" % [dir, file])
			if text.contains("set_blade_room_open(true)") or text.contains("_blade_room.open_preset") \
				or text.contains("{\"room\": \"blade\""):
				bad.append(file)
	return TestResult.new("[PD14] nothing in the app's source opens the old blade room", bad.is_empty(), str(bad))


static func _test_second_open_is_the_same_designer() -> TestResult:
	var shell := _shell()
	var first := shell.open_prop_designer()
	var second := shell.open_prop_designer()
	var layers := shell.find_children("PropDesignerLayer*", "CanvasLayer", false, false).size()
	var ok := first == second and layers == 1
	shell.free()
	return TestResult.new("[PD14] a second open does not stack a second designer", ok, "%d layers" % layers)


static func _test_close_clears_the_designer() -> TestResult:
	var shell := _shell()
	shell.open_prop_designer().close()
	var gone := shell.prop_designer == null and shell._prop_designer_layer == null
	var again := shell.open_prop_designer() != null
	shell.free()
	return TestResult.new("[PD14] closing clears the designer, and it opens again", gone and again, "")


static func _test_keys_stay_out_of_the_lab_while_up() -> TestResult:
	var shell := _shell()
	shell.set_power_room_open(true)
	var before := shell.page_open()
	shell.open_prop_designer()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	shell._unhandled_key_input(esc)
	var after := shell.page_open()
	shell.free()
	return TestResult.new("[PD14] Escape in the designer does not also close the Lab's page beneath it",
		before and after, "page %s then %s" % [before, after])


static func _test_saved_and_fitted_reach_the_lab() -> TestResult:
	var shell := _shell()
	var d := shell.open_prop_designer()
	d.fitted.emit(OTHER_PROP)
	var fitted := str(shell.lab.selection()["propeller"])
	var old_catalog := shell.lab.catalog
	d.saved.emit("whatever")
	var reloaded := shell.lab.catalog != old_catalog and d.catalog == shell.lab.catalog
	shell.free()
	return TestResult.new("[PD14] a fit moves the Lab's rail and a save re-reads its catalog",
		fitted == OTHER_PROP and reloaded, "fitted %s, reloaded %s" % [fitted, reloaded])


static func _test_session_is_the_labs_drone_as_it_stands() -> TestResult:
	var shell := _shell()
	shell.container = null
	var no_project := shell.open_prop_designer().session == null
	shell.prop_designer.close()
	var project := Project.new()
	shell.container = ProjectContainer.make(project)
	shell.lab.propeller_picker.select_id(OTHER_PROP)
	var session := shell.open_prop_designer().session
	var held := str(session.selection.get("propeller", "")) if session != null else ""
	# A fit reaches the project at once, not at the next autosave.
	shell.prop_designer.fitted.emit(ReferenceBuild.PROPELLER_ID)
	var synced := str(project.parts.get("propeller", "")) == ReferenceBuild.PROPELLER_ID \
		or str(shell.container.project.parts.get("propeller", "")) == ReferenceBuild.PROPELLER_ID
	shell.container = null
	shell.free()
	return TestResult.new("[PD14] the designer's drone is the Lab's now; no project, no session",
		no_project and held == OTHER_PROP and synced, "no project %s, holds %s, synced %s" % [no_project, held, synced])


static func _test_shelf_prop_starts_a_new_prop() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var d := PropDesigner.new(catalog)
	var prop := catalog.get_part(OTHER_PROP)
	d.open_part(prop)
	var ok := d.part_id == "" and d.doc.id == "" and d.doc.published_mass_g == 0.0 \
		and absf(d.doc.diameter_mm - PropellerDocument.from_catalog_prop(prop).diameter_mm) < 0.01
	var dia := d.doc.diameter_mm
	d.free()
	return TestResult.new("[PD14] a shelf prop starts a new prop with its size and no claim on the vendor",
		ok, "%.1f mm" % dia)


static func _test_saved_prop_reopens_under_its_id() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var path := "user://pd14_repoint_parts.json"
	DirAccess.remove_absolute(path)
	var a := PropDesigner.new(catalog)
	a.store_path = path
	a.set_prop_name("PD14 keeper")
	var id := a.save()
	a.free()
	var b := PropDesigner.new(catalog)
	b.store_path = path
	b.open_part({"part_id": id})
	var ok := id != "" and b.part_id == id and b.doc.name == "PD14 keeper"
	var got := b.part_id
	b.free()
	DirAccess.remove_absolute(path)
	return TestResult.new("[PD14] a saved prop reopens under its id, so a save edits it", ok,
		"saved %s, opened %s" % [id, got])
