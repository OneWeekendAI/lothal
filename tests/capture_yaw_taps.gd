extends SceneTree
## Dev tool: the reported bug, driven through the real scene as MOTION rather than as a
## number. Taps yaw one way, then the other for a DIFFERENT duration, then releases every
## key and keeps filming while the aircraft does whatever it does next.
##
## Deliberately unequal taps. Equal ones cancel even on a broken open loop, which is exactly
## why "tap A then D" was reported as a bug and not caught by anything: the durations a human
## produces never match. What the tail of this clip shows is whether releasing the stick
## means "stop rotating" or merely "stop pushing".
##
## Not a test — nothing here asserts anything. tests/test_stick_release.gd is the assertion;
## this is what the assertion looks like.
##
##   godot --script res://tests/capture_yaw_taps.gd -- <out_dir> [frames]

const TAP_A_FRAMES := 24    # ~0.2 s at 120 Hz
const TAP_B_FRAMES := 42    # ~0.35 s — deliberately NOT the same

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://yaw_frames"
	var frames: int = int(args[1]) if args.size() > 1 else 150

	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame

	for i in frames:
		# A is -yaw, D is +yaw (main.gd's keyboard map).
		if i == 0:
			_hold(KEY_A, true)
		elif i == TAP_A_FRAMES:
			_hold(KEY_A, false)
			_hold(KEY_D, true)
		elif i == TAP_A_FRAMES + TAP_B_FRAMES:
			# Hands off. Nothing below touches a key.
			_hold(KEY_D, false)

		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/frame_%03d.png" % [out_dir, i])

	_hold(KEY_A, false)
	_hold(KEY_D, false)
	print("wrote %d frames to %s (tap A %d frames, tap D %d frames, then hands off)"
		% [frames, out_dir, TAP_A_FRAMES, TAP_B_FRAMES])
	quit()

func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
