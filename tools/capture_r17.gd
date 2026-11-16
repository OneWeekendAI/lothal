extends SceneTree
## Dev tool: windowed capture of the in-flight World & weather panel with a changed wind on the HUD.
##   godot --path . --script tools/capture_r17.gd -- <out.png>
## Run under a scratch HOME (.test_runs/gd.sh with SCRATCH_HOME): it writes conditions.json and sites.json.

func _init() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(1440, 900))
	root.size = Vector2i(1440, 900)
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 20:
		await process_frame
	m.toggle_conditions_panel()
	var panel: DsSimConditions = m.conditions_panel
	panel.wind_speed_field.value = 7.0
	panel.wind_from_field.value = 90.0
	panel.gust_field.value = 1.0
	panel.temperature_field.value = 35.0
	panel.elevation_field.value = 1500.0
	panel.apply_button.pressed.emit()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	# Close the panel and fly a little, so the HUD wind readout is the live, wandering one.
	m.toggle_conditions_panel()
	for i in 240:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path.replace(".png", "_hud.png"))
	print("wrote ", out_path)
	quit()
