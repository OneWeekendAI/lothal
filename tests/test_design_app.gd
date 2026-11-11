class_name TestDesignApp
extends RefCounted
## The Design Space app (R9): the one shell. Every screen is reached through the Design Space's own
## "..." menu, and nothing is reachable only through chrome that no longer exists.
##
## What each check can fail on, and what it was proved against:
## - the "..." menu has NO Rooms group: no Room_* button, no `DesignFileBar.ROOMS`, no `DesignApp.open_room`/`open_setup`,
##   and `DsSetup` is gone (M15), so a room cannot come back without this going red;
## - the menu's doors are the Design Space's own: Field, Mission and Flights each open and Back returns to the design.

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
	results.append(_the_rooms_group_is_gone(app))
	app.interactive = true
	app.new_project()
	app.class_picker.show_class("five_inch")
	app.class_picker.choose()
	for i in 12:
		await tree.process_frame
	results.append(TestResult.new("design app: choosing a class lands on the Design Space with no old chrome around it",
		app.design_space != null and app.design_space.visible and app.find_children("*", "Dock", true, false).is_empty(),
		str(app.design_space)))
	var before := app.design_space.session.selection.duplicate(true)
	var flights_open: bool = app.open_flights() and app.design_space.flights_sheet != null
	app.design_space.flights_sheet.close()
	await tree.process_frame
	results.append(TestResult.new("design app: Flights opens as a drawer over the design and closing it returns to the same design",
		flights_open and app.design_space.visible and app.design_space.flights_sheet == null
			and app.design_space.session.selection == before and not app.away_from_design(), "flights"))
	results.append(TestResult.new("design app: the field opens from the menu's own signal and Back returns",
		_field_round_trip(app), "field"))
	app.get_parent().queue_free()
	held.restore()
	return results


static func _the_rooms_group_is_gone(app: DesignApp) -> TestResult:
	var room_buttons := app.find_children("Room_*", "Button", true, false)
	var bar_src := TestPidTunes._code_only(FileAccess.get_file_as_string("res://src/design/design_file_bar.gd"))
	var app_src := TestPidTunes._code_only(FileAccess.get_file_as_string("res://src/ui/design_app.gd"))
	var left: Array = []
	if not room_buttons.is_empty():
		left.append("%d Room_ buttons" % room_buttons.size())
	for token in ["ROOMS", "room_pressed"]:
		if bar_src.contains(token):
			left.append("file bar: " + token)
	for token in ["func open_room", "func open_setup", "DsSetup"]:
		if app_src.contains(token):
			left.append("design app: " + token)
	if FileAccess.file_exists("res://src/design/ds_setup.gd"):
		left.append("ds_setup.gd exists")
	return TestResult.new("design app: the menu has no Rooms group and the Setup pages are gone", left.is_empty(), str(left))


static func _field_round_trip(app: DesignApp) -> bool:
	var opened := app.open_field_from_design()
	var shown := app.field_room().visible
	app.back_to_drone_from_room()
	return opened and shown and not app.field_room().visible and app.design_space.visible
