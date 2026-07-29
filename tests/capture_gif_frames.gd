extends SceneTree
## Dev tool: flies the course under scripted input and dumps a numbered PNG per frame, for
## assembling the README animation. Not a test — nothing here asserts anything. It exists
## so the repo's headline image is generated from the real simulation rather than staged.
##
##   godot --script res://tests/capture_gif_frames.gd -- <out_dir> [frames]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://frames"
	var frames: int = int(args[1]) if args.size() > 1 else 90

	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame

	# Nose down to fly forward, plus throttle to hold height against the lean.
	_hold(KEY_DOWN, true)
	_hold(KEY_W, true)

	for i in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("%s/frame_%03d.png" % [out_dir, i])

	_hold(KEY_DOWN, false)
	_hold(KEY_W, false)
	print("wrote %d frames to %s" % [frames, out_dir])
	quit()

func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
