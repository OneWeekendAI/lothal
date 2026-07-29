extends SceneTree
## Dev tool, not a test: boots the real main scene in a window, lets it settle, and writes a
## PNG of the framebuffer. This is how the UI gets looked at on a machine where the shell has
## no screen-recording permission — Godot captures its own viewport, so the OS is not involved.
##
##   godot --script res://tests/capture_frame.gd -- <out.png> [settle_frames] [overview]
##
## Passing "overview" detaches the chase cam and shoots the whole circuit from above, which
## is the only way to check the course as a shape rather than one gate at a time.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://frame.png"
	var settle: int = int(args[1]) if args.size() > 1 else 30
	var overview: bool = args.size() > 2 and args[2] == "overview"

	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)

	for i in settle:
		await process_frame

	if overview:
		# A second camera, made current, so the scene's own chase cam keeps running
		# untouched — the point is to observe the course, not to change it.
		var observer := Camera3D.new()
		observer.far = 800.0
		scene.add_child(observer)
		observer.global_position = Vector3(0.0, 34.0, 34.0)
		observer.look_at(Vector3(0, 2, 0), Vector3.UP)
		observer.make_current()
		for i in 4:
			await process_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
