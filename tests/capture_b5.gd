extends SceneTree
## Dev tool, not a test (B5: R2.3 + R2.5). Boots the real main scene in a WINDOW (never --headless) and writes:
## the FPV feed at full throttle (soft-mount shake, printed in rad and px), a slow-rpm damaged prop close-up, a fast
## damaged (chipped) disc close-up, and a 7 m/s ground hit with its debris. Then forced-draw frame time at 1280x720.
##
##   godot --path . --script res://tests/capture_b5.gd -- <out_dir>

const W := 1280
const H := 720


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://b5"
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

	# 1. FPV full screen, full throttle: climbing out at 100%.
	view.toggle_main()
	scene._hover_throttle = 1.0  # the keyboard path centres the stick here; 1.0 = full throttle
	var peak := 0.0
	for i in 40:
		scene._hover_throttle = 1.0  # the keyboard path centres the stick here; 1.0 = full throttle
		await physics_frame
		peak = maxf(peak, scene.camera_mount.offset(scene.core.gyro.vibration).length())
	var rpm: PackedFloat32Array = scene.core.observables.rpm
	var px_per_rad := float(W) / deg_to_rad(view.lens_data().get("hfov_deg", 120.0)) if view.lens_data() is Dictionary else 600.0
	print("[b5] full throttle rpm %s: mount offset peak %s rad = %.4f px (vib %s, rel %s)" % [rpm, peak, peak * px_per_rad,
		scene.camera_mount.vibration_offset(scene.core.gyro.vibration).length(), scene.camera_mount.rel_angle.length()])
	await _shot(out_dir + "/fpv_full_throttle.png")
	var hard := FpvMount.new("hard")
	print("[b5] same instant, hard mount: %s rad" % hard.vibration_offset(scene.core.gyro.vibration).length())
	view.toggle_main()

	# 2. Slow-rpm prop close-up, with one damaged prop (M2 at 0.25 lost thrust).
	scene.flight_paused = true
	var cam := Camera3D.new()
	cam.fov = 40.0
	scene.add_child(cam)
	cam.make_current()
	var model: SimDroneModel = scene.airframe
	model.set_damage(PackedFloat64Array([0.0, 0.25, 0.0, 0.0]))
	model.set_all_rates_rpm(400.0)
	var prop := model.prop_nodes["M2"] as Node3D
	for i in 6:
		_aim(cam, prop)
		await process_frame
	await _shot(out_dir + "/prop_slow_400rpm_damaged.png")
	# 3. The same prop and its neighbour at 15,000 rpm: the swept discs, M2's chipped and off-axis.
	model.set_all_rates_rpm(15000.0)
	for i in 6:
		_aim(cam, prop)
		await process_frame
	await _shot(out_dir + "/prop_fast_15000rpm_chipped.png")
	model.set_damage(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))

	# 4. A 7 m/s ground hit (R1.1 damage, below the 8 m/s crash): the debris it sheds, 6 frames later.
	scene.flight_paused = false
	var p: Vector3 = scene.core.rigid_body.position_m
	var gy: float = scene.terrain.height_at(p.x, p.z)
	scene.core.rigid_body.position_m = Vector3(p.x, gy + 0.3, p.z)
	scene.core.rigid_body.velocity_mps = Vector3(2.0, -7.0, 0.0)
	scene.rc.throttle = 0.0
	var hit := Vector3(p.x, gy, p.z)
	for i in 8:
		await physics_frame
		cam.global_position = hit + Vector3(1.2, 0.6, 1.2)
		cam.look_at(hit, Vector3.UP)
	var n: int = scene.crash_debris.fragments.size() if scene.crash_debris != null else 0
	print("[b5] crash: impact %.2f m/s, damage %s, %d fragments" % [scene.last_frame_impact_mps, scene.core.prop_damage, n])
	await _shot(out_dir + "/crash_debris.png")
	for i in 60:
		await process_frame
	await _shot(out_dir + "/crash_debris_settled.png")

	# Frame time, FPV main, forced draw (presented rate is capped by the display link).
	cam.queue_free()
	view.toggle_main()
	for i in 30:
		await process_frame
	var t1 := Time.get_ticks_usec()
	for i in 240:
		RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_sync()
	var forced := float(Time.get_ticks_usec() - t1) / 1000.0 / 240.0
	var t0 := Time.get_ticks_usec()
	for i in 240:
		await process_frame
	var presented := float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0
	print("[b5] FPV main %dx%d: forced-draw %.2f ms (%.1f fps uncapped); presented %.2f ms (%.1f fps)" % [W, H, forced, 1000.0 / forced, presented, 1000.0 / presented])
	quit()


func _aim(cam: Camera3D, target: Node3D) -> void:
	var at := target.global_position
	cam.global_position = at + Vector3(0.12, 0.10, 0.12)
	cam.look_at(at, Vector3.UP)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("[b5] wrote %s" % path)
