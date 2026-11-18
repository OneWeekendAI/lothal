extends SceneTree
## B4 dev probe (windowed, never --headless): chase-view frame time at 1280x720, vsync off, under render variants, to find
## where the frame goes.   godot --path . --script res://tests/probe_fps_variants.gd
const W := 1280
const H := 720


func _measure(label: String, frames := 240) -> float:
	for i in 30:
		await process_frame
	var rid := root.get_viewport_rid()
	var gpu := 0.0
	var cpu := 0.0
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	gpu /= frames
	cpu /= frames
	var avg := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	# Uncapped render throughput: drawn without presenting (no display-link wait), so an occluded window's 60 Hz cap
	# cannot hide the cost. The sync at the end waits for the GPU to finish the batch.
	var t1 := Time.get_ticks_usec()
	for i in frames:
		RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_sync()
	var forced := float(Time.get_ticks_usec() - t1) / 1000.0 / frames
	print("[b4fps] %-28s forced-draw %.2f ms/frame (%.1f fps uncapped)" % [label, forced, 1000.0 / forced])
	print("[b4fps] %-28s gpu %.2f ms  rcpu %.2f ms  frame %.2f ms  %.1f fps  draws %d  prims %d" % [label, gpu, cpu, avg, 1000.0 / avg,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	return avg


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(W, H)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	(scene.get_node("Camera3D") as Camera3D).make_current()
	var sun := scene.get_node("DirectionalLight3D") as DirectionalLight3D
	var fl: Node = scene.field_look
	await _measure("baseline")
	var trees: Array = []
	var grass: Array = []
	for c in fl.get_children():
		if String(c.name).begins_with("Trees"):
			trees.append(c)
		elif String(c.name).begins_with("Grass"):
			grass.append(c)
	for t in trees:
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _measure("trees no shadow")
	for t in trees:
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		t.visible = false
	await _measure("trees hidden")
	for t in trees:
		t.visible = true
	for g in grass:
		g.visible = false
	await _measure("grass hidden")
	for g in grass:
		g.visible = true
	sun.shadow_enabled = false
	await _measure("no sun shadow")
	sun.shadow_enabled = true
	scene.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	await _measure("msaa off")
	scene.get_viewport().msaa_3d = Viewport.MSAA_4X
	await _measure("baseline again")
	quit()
