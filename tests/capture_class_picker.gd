extends SceneTree
## Dev tool, not a test: photographs the "Choose your drone class" screen the way a builder reaches
## it — a real DesignApp, then New drone — so the picture is of the production path.
##
##   godot --script res://tests/capture_class_picker.gd -- <out.png> [settle] [WxH] [class id]
##
## Needs a real window (no --headless: the dummy driver has no framebuffer). Run it with HOME
## pointed at a scratch directory (as tools/run_tests_safe.sh does): New drone writes a project.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://class_picker.png"
	var settle: int = int(args[1]) if args.size() > 1 else 90
	if args.size() > 2 and args[2] != "":
		var res_parts := args[2].split("x")
		if res_parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(res_parts[0]), int(res_parts[1])))
			root.size = Vector2i(int(res_parts[0]), int(res_parts[1]))
	var shown: String = args[3] if args.size() > 3 else ""

	var shell := DesignApp.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	if shown != "" and shell.class_picker != null:
		shell.class_picker.show_class(shown)
	for i in settle:
		await process_frame

	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
