extends SceneTree
## Dev tool, not a test: a strip of every DsUi button state (rest, hover, pressed, disabled, focus, busy) for
## plain, primary and toggle buttons, drawn from the buttons' own styleboxes.
##   godot --script res://tests/capture_button_states.gd -- <out.png> [WxH]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://button_states.png"
	var size := Vector2i(1280, 720)
	if args.size() > 1:
		var p := args[1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.095, 0.105)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.position = Vector2(40, 40)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 18)
	root.add_child(grid)
	var states := ["normal", "hover", "pressed", "disabled", "focus", "busy"]
	grid.add_child(DsUi.label("", DsUi.INK_MUTED))
	for st in states:
		grid.add_child(DsUi.label(st, DsUi.INK_MUTED))
	for kind in ["plain", "primary", "toggle"]:
		grid.add_child(DsUi.label(kind, DsUi.INK_MUTED))
		for st in states:
			var b := DsUi.button("Fly it", kind == "toggle", kind == "primary")
			var box_state: String = st
			if st == "busy":
				DsUi.set_busy(b, true, "Loading...")
				box_state = "disabled"
			var panel := PanelContainer.new()
			panel.add_theme_stylebox_override("panel", b.get_theme_stylebox(box_state))
			var l := DsUi.label(b.text, DsUi.INK if st in ["hover", "pressed", "focus", "normal"] and kind == "primary" or st in ["hover", "pressed", "focus"] else (DsUi.INK_FAINT if st == "disabled" else (DsUi.INK_MUTED)), LothalTheme.FONT_SIZE_SMALL)
			panel.add_child(l)
			grid.add_child(panel)
	for i in 10:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("saved %s" % out_path)
	quit()
