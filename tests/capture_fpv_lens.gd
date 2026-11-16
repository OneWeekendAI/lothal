extends SceneTree
## Dev tool, not a test (R2.2): boots the real main scene in a WINDOW (never --headless) and writes the FPV feed through the
## lens: full-screen FPV flying level over the field (nose down by the camera's uptilt so the lens looks at the horizon),
## the hover pose (looks into the sky), the inset, a second camera part, and the frame time with the FPV pass on.
##
##   godot --path . --script res://tests/capture_fpv_lens.gd -- <out_dir>

const W := 1280
const H := 720


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://r22"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(W, H)

	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	var view: FpvView = scene.fpv_view
	var home: Vector3 = scene.drone.global_position
	var catalog := PartsCatalog.load_default()
	print("[r22] fitted %s, lens %s" % [view.is_fitted(), view.lens_data()])

	# Freeze the physics so the pose we set is the pose drawn.
	scene.flight_paused = true
	var tilt := view.tilt_deg()

	# 1. Inset (the default mode), hover pose.
	await _pose(scene, home, 0.0, 6)
	await _shot(out_dir + "/fpv_inset_hover.png")

	view.toggle_main()
	# 2. Full screen, hover pose: the lens looks `tilt` degrees above the horizon.
	await _pose(scene, home, 0.0, 6)
	await _shot(out_dir + "/fpv_main_hover_uptilt.png")
	# 3. Full screen, flying level: nose down by the uptilt so the lens is on the horizon.
	await _pose(scene, home + Vector3(0.0, 2.0, 0.0), -tilt, 6)
	await _shot(out_dir + "/fpv_main_level_field.png")
	# 4. Low and fast: 30 deg nose down, close to the grass.
	await _pose(scene, home + Vector3(0.0, 0.8, 0.0), -tilt - 10.0, 6)
	await _shot(out_dir + "/fpv_main_low.png")
	# 5. A different camera part: the full-size analog (Brown-Conrady, narrower).
	view.set_camera_part(catalog.get_part("cam_fullsize_analog"))
	await _pose(scene, home + Vector3(0.0, 2.0, 0.0), -tilt, 6)
	await _shot(out_dir + "/fpv_main_level_fullsize.png")
	# Back to the reference camera for the frame-time run.
	view.set_camera_part(catalog.get_part("cam_micro_analog"))
	await _pose(scene, home + Vector3(0.0, 2.0, 0.0), -tilt, 6)

	# Frame time, FPV main, vsync off.
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in 360:
		await process_frame
		if i >= 60:
			var now := Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
		last = Time.get_ticks_usec()
	var sum := 0.0
	var worst := 0.0
	for t in times:
		sum += t
		worst = maxf(worst, t)
	var avg := sum / times.size()
	print("[r22] FPV main: frame time avg %.2f ms (%.1f fps), worst %.2f ms, %d frames at %dx%d, vsync off" % [avg, 1000.0 / avg, worst, times.size(), W, H])
	quit()


## Places the drone at `at` with `pitch_deg` of pitch (negative = nose down), then lets frames render.
func _pose(scene: Node, at: Vector3, pitch_deg: float, settle: int) -> void:
	for i in settle:
		scene._snap_visual(at, Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)).get_rotation_quaternion())
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("[r22] wrote %s" % path)
