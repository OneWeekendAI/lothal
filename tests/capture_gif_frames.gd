extends SceneTree
## Dev tool: drives the real app shell (GlassShell, what root.tscn boots) through a short tour and
## dumps a numbered PNG per captured frame, for assembling the README animation. Not a test —
## nothing here asserts anything. It exists so the repo's headline image is generated from the
## real app rather than staged.
##
##   HOME=<scratch> godot --script res://tests/capture_gif_frames.gd -- <out_dir> [step]
##
## Run it under a scratch HOME: opening pages and flying must not touch the developer's own drone.
## `step` keeps every Nth rendered frame (default 2), so the GIF plays at 30 fps from a 60 fps run.
##
## The tour: the garage turning the reference build, two part pages opened the way a row click
## opens them, then out to the field through the Sim toggle and a scripted run at the first gate.

var _out_dir := ""
var _step := 2
var _rendered := 0
var _written := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "user://frames"
	_step = int(args[1]) if args.size() > 1 else 2
	DirAccess.make_dir_recursive_absolute(_out_dir)

	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 30:
		await process_frame

	# The garage: the idle orbit turns the build.
	await _record(100)

	for pair in [["Propulsion", &"motors"], ["Power", &"battery"]]:
		shell.select_system_by_name(pair[0])
		shell.open_row(pair[1])
		await _record(80)

	# Back to the drone, then out to the field through the same toggle a click drives.
	shell.back_to_drone()
	await _record(20)
	shell.rooms.show_sim()
	for i in 60:
		await process_frame
	# Tab hides the build panel, so the run is the picture.
	_tap(KEY_TAB)

	# Climb to gate height off camera, then nose down to fly forward.
	_hold(KEY_W, true)
	for i in 40:
		await process_frame
	_hold(KEY_W, false)
	_hold(KEY_DOWN, true)
	await _record(150)
	_hold(KEY_DOWN, false)

	print("wrote %d frames to %s" % [_written, _out_dir])
	quit()

func _record(frames: int) -> void:
	for i in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		_rendered += 1
		if _rendered % _step != 0:
			continue
		var image := root.get_texture().get_image()
		image.save_png("%s/frame_%04d.png" % [_out_dir, _written])
		_written += 1

func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap(key: Key) -> void:
	_hold(key, true)
	await process_frame
	_hold(key, false)
