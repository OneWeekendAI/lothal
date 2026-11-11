extends SceneTree
## Dev tool, not a test: photographs the Sim as a builder reaches it from the Design Space.
##
##   godot --script res://tests/capture_sim_door.gd -- <out.png> <class id> [WxH] [entry] [mission]
##
## entry: "fly" (Fly it, default) or "toggle" (the old Sim toggle). "mission" opens the Mission
## drawer first, to show it does not stay over the sim. Needs a real window and a scratch HOME.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://sim_door.png"
	var class_id: String = args[1] if args.size() > 1 else "five_inch"
	if args.size() > 2 and args[2] != "":
		var p := args[2].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var entry: String = args[3] if args.size() > 3 else "fly"
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class(class_id)
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var catalog := PartsCatalog.load_default()
	for opt in catalog.list_category("battery"):
		var bid := String(opt["part_id"])
		if bid != String(shell.design_space.session.selection["battery"]) and shell.design_space.session.swap(catalog, "battery", bid)["ok"]:
			break
	if entry == "toggle":
		shell._sim_button.pressed.emit()
	else:
		shell.design_space.file_bar.fly_button.pressed.emit()
	for i in 90:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("saved %s %s" % [out_path, img.get_size()])
	quit()
