extends SceneTree
## Dev tool, not a test: photographs the flight sim with a payload hung under the drone, resting on the ground.
##
##   godot --script res://tests/capture_payload_sim.gd -- <out.png> [class id] [payload kind] [mass_g] [WxH]
##
## Goes in as a builder does (New drone, class, set payload, Fly it) and waits for the camera to settle.
## Needs a real window; run with HOME pointed at a scratch directory.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://payload_sim.png"
	var class_id: String = args[1] if args.size() > 1 else "five_inch"
	var kind: String = args[2] if args.size() > 2 else "payload_gimbal_camera"
	var mass_g: float = float(args[3]) if args.size() > 3 and args[3] != "" else -1.0
	if args.size() > 4 and args[4] != "":
		var p := args[4].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var shell := DesignApp.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class(class_id)
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var saved := {"kind": kind}
	if mass_g >= 0.0:
		saved["mass_g"] = mass_g
	shell.design_space.session.set_payload(saved)
	shell.design_space.file_bar.fly_button.pressed.emit()
	for i in 240:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("saved %s %s" % [out_path, img.get_size()])
	quit()
