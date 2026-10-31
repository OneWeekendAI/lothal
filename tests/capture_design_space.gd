extends SceneTree
## Dev tool, not a test: photographs the Design Space the way a builder reaches it - real
## GlassShell, New drone, pick a class, Choose.
##
##   godot --script res://tests/capture_design_space.gd -- <out.png> <class id> [WxH] [close-up mesh name]
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://design_space.png"
	var class_id: String = args[1] if args.size() > 1 else "five_inch"
	if args.size() > 2 and args[2] != "":
		var p := args[2].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var closeup: String = args[3] if args.size() > 3 else ""
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class(class_id)
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var ds: DesignSpace = shell.design_space
	if closeup != "":
		for entry in ds.mesh_boxes():
			if String(entry["name"]).begins_with(closeup):
				ds.rig.frame(entry["box"])
				break
	for i in 120:
		await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
