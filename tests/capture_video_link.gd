extends SceneTree
## Dev tool, not a test (R2.4). Boots the real main scene in a WINDOW and writes the FPV feed, full screen, for an
## analog and a digital camera part at three link states: near (20 m, clear), far (the distance where the link is at
## 20% quality, clear), and behind an obstacle (60 m, one blocker). The flight is paused and the link is evaluated
## at those geometries directly (VideoLink.evaluate), so the three shots share one scene. Then forced-draw frame time.
##   godot --path . --script res://tests/capture_video_link.gd -- <out_dir>

const W := 1280
const H := 720


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://r24"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(W, H)
	Engine.max_fps = 0
	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	var view: FpvView = scene.fpv_view
	view.toggle_main()
	scene.flight_paused = true
	var cams := TestVideoLink._cameras()
	for id in ["cam_micro_analog", "cam_dji_o4_pro"]:
		view.set_camera_part(cams[id])
		var far := 20.0
		while far < 5000.0:
			view.update_link(far, 0)
			if view.link.quality <= 0.2:
				break
			far += 5.0
		for shot in [["near", 20.0, 0], ["far", far, 0], ["obstacle", 60.0, 1]]:
			view.update_link(float(shot[1]), int(shot[2]))
			scene.hud.set_link(view.link.hud_text(), view.link.quality)
			for i in 8:
				await process_frame
			print("[r24] %s %s: %s" % [view.link.system, shot[0], view.link.hud_text()])
			await _shot("%s/%s_%s.png" % [out_dir, view.link.system, shot[0]])
	view.set_camera_part(cams["cam_micro_analog"])
	view.update_link(150.0, 0)
	for i in 30:
		await process_frame
	var t1 := Time.get_ticks_usec()
	for i in 240:
		RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_sync()
	var forced := float(Time.get_ticks_usec() - t1) / 1000.0 / 240.0
	print("[r24] FPV main analog %dx%d: forced-draw %.2f ms (%.1f fps)" % [W, H, forced, 1000.0 / forced])
	quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
