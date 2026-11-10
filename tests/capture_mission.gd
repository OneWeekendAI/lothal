extends SceneTree
## Dev tool, not a test: photographs the Design Space top bar and Mission drawer the way a builder reaches them.
##
##   godot --script res://tests/capture_mission.gd -- <out dir> [WxH]
##
## Writes bar.png (closed), menu.png (the dots menu open), mission.png (drawer), result.png (after Run) and world.png
## (the world editor). Needs a real window; run with HOME pointed at a scratch directory.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://"
	var wh := (args[1] if args.size() > 1 else "1280x720").split("x")
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	root.size = Vector2i(int(wh[0]), int(wh[1]))
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class("seven_lr")
	shell.class_picker.choose()
	for i in 90:
		await process_frame
	await _shot(dir + "/bar.png")
	var fb: DesignFileBar = shell.design_space.file_bar
	fb.menu_button.pressed.emit()
	for i in 6:
		await process_frame
	await _shot(dir + "/menu.png")
	fb.mission_button.pressed.emit()
	for i in 20:
		await process_frame
	await _shot(dir + "/mission.png")
	var p: MissionPicker = shell.mission_picker
	(p.field_boxes["speed_mps"] as DsSlider).value = 9.0
	p._update_tags()
	p.env_option.select(1)
	p._update_env_hint()
	p.extra_opts = {"capacity_scale": 0.3}
	p.run_headless()
	for i in 20:
		await process_frame
	await _shot(dir + "/result.png")
	p.hide()
	shell.open_field_from_design()
	for i in 30:
		await process_frame
	var field := shell.field_room()
	await _shot(dir + "/field.png")
	var ids: Array[String] = field.worlds.ids()
	field.edit_world_requested.emit(ids[0])
	shell.world_editor.add_obstacle_button.pressed.emit()
	for i in 20:
		await process_frame
	await _shot(dir + "/world.png")
	quit()


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
