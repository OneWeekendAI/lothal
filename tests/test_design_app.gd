class_name TestDesignApp
extends RefCounted
## The Design Space app (R9): the one shell. Every screen is reached through the Design Space's own
## "..." menu, and nothing is reachable only through chrome that no longer exists.
##
## What each check can fail on, and what it was proved against:
## - the setup groups name every sheet of the lab (a sheet added to LabScreen and left out of
##   DsSetup.GROUPS has no door);
## - each Rooms menu entry opens its room AND the away bar's Back returns to the same design;
## - the menu lists every show_* room of RoomHost except the sim (reached by Fly it) and the lab
##   (the model, never shown), so a new room cannot be added without a door.

const SETTLE := 3


static func _app(tree: SceneTree) -> DesignApp:
	var frame := SubViewport.new()
	frame.size = Vector2i(1280, 720)
	tree.root.add_child(frame)
	var app := DesignApp.new()
	frame.add_child(app)
	for i in SETTLE:
		await tree.process_frame
	return app


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var held := RealFiles.hold([AssemblyTweaks.SAVE_PATH])
	var app := await _app(tree)
	results.append(_setup_covers_every_sheet(app))
	results.append(_menu_covers_every_room())
	app.interactive = true
	app.new_project()
	app.class_picker.show_class("five_inch")
	app.class_picker.choose()
	for i in 12:
		await tree.process_frame
	results.append(TestResult.new("design app: choosing a class lands on the Design Space with no old chrome around it",
		app.design_space != null and app.design_space.visible and app.find_children("*", "Dock", true, false).is_empty(),
		str(app.design_space)))
	for room in ["setup", "bench", "esc_bench", "frame_bench", "studio"]:
		var before := app.design_space.session.selection.duplicate(true)
		var opened := app.open_room(room)
		await tree.process_frame
		var away := app.away_from_design() and not app.design_space.visible
		app.back_to_drone_from_room()
		await tree.process_frame
		results.append(TestResult.new("design app: the menu's '%s' opens and Back returns to the same design" % room,
			opened and away and app.design_space != null and app.design_space.visible
				and app.design_space.session.selection == before and not app.away_from_design(),
			"opened=%s away=%s" % [opened, away]))
	results.append(TestResult.new("design app: the field opens from the menu's own signal and Back returns",
		_field_round_trip(app), "field"))
	results.append(TestResult.new("design app: Projects from the menu leaves the design for the Projects screen",
		app.open_room("projects") and app.projects_shown() and app.design_space == null, "projects"))
	app.get_parent().queue_free()
	held.restore()
	return results


static func _setup_covers_every_sheet(app: DesignApp) -> TestResult:
	var titles: Array = []
	for g in DsSetup.GROUPS:
		titles.append_array(g[1])
	var missing: Array = []
	var tabs := app.setup.panels
	for i in tabs.get_tab_count():
		if not titles.has(tabs.get_tab_title(i)):
			missing.append(tabs.get_tab_title(i))
	var stale: Array = []
	for t in titles:
		var found := false
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == t:
				found = true
		if not found:
			stale.append(t)
	return TestResult.new("design app: Setup names every sheet of the lab, and only sheets that exist",
		missing.is_empty() and stale.is_empty(), "no door: %s; no sheet: %s" % [missing, stale])


static func _menu_covers_every_room() -> TestResult:
	var ids: Array = []
	for r in DesignFileBar.ROOMS:
		ids.append(r[0])
	var wanted := {"bench": "show_bench", "esc_bench": "show_esc_bench", "frame_bench": "show_frame_bench",
		"studio": "show_studio"}
	var methods: Array = []
	for m in RoomHost.new().get_method_list():
		var n := String(m["name"])
		if n.begins_with("show_") and n not in ["show_lab", "show_sim"]:
			methods.append(n)
	var missing: Array = []
	for n in methods:
		var ok := false
		for id in wanted:
			if wanted[id] == n and ids.has(id):
				ok = true
		if not ok:
			missing.append(n)
	return TestResult.new("design app: the Rooms menu has a door for every RoomHost room",
		missing.is_empty(), "no door: %s" % [missing])


static func _field_round_trip(app: DesignApp) -> bool:
	var opened := app.open_field_from_design()
	var shown := app.field_room().visible
	app.back_to_drone_from_room()
	return opened and shown and not app.field_room().visible and app.design_space.visible
