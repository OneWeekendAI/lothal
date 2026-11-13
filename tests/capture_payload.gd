extends SceneTree
## Dev tool, not a test: photographs the Design Space with a payload hung under the drone.
##
##   godot --script res://tests/capture_payload.gd -- <out.png> <class id> <payload kind> [mass_g] [WxH]
##       [yaw_deg] [pitch_deg] [zoom]
##
## Goes in the way a builder does (DesignApp, New drone, pick a class, Choose), then sets the payload through the
## session. Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://payload.png"
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
	var ds: DesignSpace = shell.design_space
	var saved := {"kind": kind}
	if mass_g >= 0.0:
		saved["mass_g"] = mass_g
	ds.session.set_payload(saved)
	if args.size() > 5 and args[5] != "":
		ds.rig.goal_yaw = deg_to_rad(float(args[5]))
	if args.size() > 6 and args[6] != "":
		ds.rig.goal_pitch = deg_to_rad(float(args[6]))
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
