extends SceneTree
## Dev tool, not a test (R2.1): boots the real main scene in a WINDOW (never --headless: the dummy driver has no framebuffer),
## writes four PNGs of the field and measures frame time at 1280x720.
##
##   godot --path . --script res://tests/capture_field_look.gd -- <out_dir> [wind_mps]
##
## Shots: fpv_low (a drone's-eye view just over the grass), chase (the scene's own chase camera), overview (high, from the
## side) and into_sun (looking toward the sun, which is the light's own direction reversed, so it is read, not guessed).
## Then the fps run: vsync off, 300 frames with the chase camera, average and worst frame time from the engine's own clock.

const W := 1280
const H := 720


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://r21"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(W, H)

	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	print("[r21] renderer %s, tufts %d, trees %d" % [RenderingServer.get_video_adapter_name(),
		scene.field_look.tuft_count if scene.field_look != null else -1,
		scene.field_look.tree_count if scene.field_look != null else -1])

	var sun := scene.get_node("DirectionalLight3D") as DirectionalLight3D
	# A DirectionalLight3D shines along its -Z, so the sun itself is along +Z.
	var toward_sun := sun.global_transform.basis.z.normalized()
	var home: Vector3 = scene.drone.global_position

	# 1. FPV low over the grass.
	await _shot(scene, out_dir + "/fpv_low.png", home + Vector3(0.0, 0.55, 3.0), home + Vector3(0.0, 0.9, -40.0), 70.0, 40)
	# 2. Chase: the scene's own camera.
	await _shot(scene, out_dir + "/chase.png", Vector3.ZERO, Vector3.ZERO, 0.0, 40)
	# 3. High overview.
	await _shot(scene, out_dir + "/overview.png", home + Vector3(0.0, 55.0, 75.0), home + Vector3(0.0, 0.0, -10.0), 60.0, 40)
	# 4. Into the sun, from 1.6 m, aimed 16 degrees above the horizon along the sun's own azimuth.
	var az := Vector3(toward_sun.x, 0.0, toward_sun.z).normalized()
	var aim := (az * cos(deg_to_rad(16.0)) + Vector3.UP * sin(deg_to_rad(16.0)))
	await _shot(scene, out_dir + "/into_sun.png", home + Vector3(0.0, 1.6, 0.0), home + Vector3(0.0, 1.6, 0.0) + aim * 50.0, 70.0, 120)

	# Frame time, chase camera, vsync off.
	_use_scene_camera(scene)
	for i in 60:
		await process_frame
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	var sum := 0.0
	var worst := 0.0
	for t in times:
		sum += t
		worst = maxf(worst, t)
	var avg := sum / times.size()
	print("[r21] frame time avg %.2f ms (%.1f fps), worst %.2f ms, over %d frames at %dx%d, vsync off" % [avg, 1000.0 / avg, worst, times.size(), W, H])
	print("[r21] draw calls %d, primitives %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	quit()


var _observer: Camera3D


func _use_scene_camera(scene: Node) -> void:
	if _observer != null:
		_observer.queue_free()
		_observer = null
	(scene.get_node("Camera3D") as Camera3D).make_current()


func _shot(scene: Node, path: String, from: Vector3, to: Vector3, fov: float, settle: int) -> void:
	if fov <= 0.0:
		_use_scene_camera(scene)
	else:
		if _observer == null:
			_observer = Camera3D.new()
			_observer.near = 0.05
			_observer.far = 800.0
			scene.add_child(_observer)
		_observer.fov = fov
		_observer.global_position = from
		_observer.look_at(to, Vector3.UP)
		_observer.make_current()
	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("[r21] wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
