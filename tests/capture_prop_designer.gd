extends SceneTree
## Dev tool, not a test: photographs the prop designer over the real Design Space, reached the way a
## builder reaches it: GlassShell, New drone, open the prop shelf, press the "+" tile.
##
##   godot --script res://tests/capture_prop_designer.gd -- <out.png> [WxH] [state]
##
## state: "" (the default) | "shelf" (no pop-up: the shelf and its tile) | "edited" (a 7 in two-blade
## on PA6+CF with a pad) | "blade" (drawn chord and twist, pitch offer) | "blade_low" (left column scrolled);
## "tunnel", "tunnel_power", "tunnel_eff", "tunnel_mid", "tunnel_edge", "tunnel_refused", "tunnel_measured", "tunnel_mach";
## "stand", "stand_current", "stand_pack", "structure", "structure_details", "structure_mach".
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://prop_designer.png"
	if args.size() > 1 and args[1] != "":
		var p := args[1].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var state: String = args[2] if args.size() > 2 else ""
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var ds: DesignSpace = shell.design_space
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("propeller")
	for i in 10:
		await process_frame
	ds.shelf.scroll.scroll_vertical = 100000
	for i in 10:
		await process_frame
	if state != "shelf":
		(ds.shelf.find_child("AddProp", true, false) as Button).pressed.emit()
		for i in 6:
			await process_frame
		var d: PropDesigner = ds.prop_designer
		if state == "edited":
			d.step_diameter(2.0)
			d.set_blades(2)
			d.set_blade_material("carbon_filled_nylon")
			d.set_pad_mm(2.0)
			d.name_field.text = "Long ranger"
			d.set_prop_name("Long ranger")
		if state.begins_with("tunnel"):
			d.show_tab("tunnel")
			d.tunnel.set_look_j(0.5)
		if state == "tunnel_power":
			d.tunnel.set_metric("power")
		if state == "tunnel_eff":
			d.tunnel.set_metric("efficiency")
		if state == "tunnel_mid":
			d.tunnel.set_angle(45.0)
		if state == "tunnel_edge":
			d.tunnel.set_angle(90.0)
		if state == "tunnel_refused":
			d.tunnel.set_angle(120.0)
		if state == "tunnel_measured":
			d.doc.diameter_mm = 4.2 * PropellerDocument.INCH_TO_MM
			d.doc.pitch_mm = 4.0 * PropellerDocument.INCH_TO_MM
			d.set_blades(2)
			d.step_rpm(8067.0 - d.rpm)
		if state == "tunnel_mach":
			d.step_rpm(60000.0)
		if state.begins_with("stand"):
			d.show_tab("stand")
		if state == "stand_current":
			d.stand.set_view("current")
		if state == "stand_pack":
			d.stand.pick_pack(d.stand.pack_ids()[1])
		if state.begins_with("structure"):
			d.show_tab("structure")
		if state == "structure_details":
			d.structure.set_details(true)
		if state == "structure_mach":
			d.step_rpm(60000.0)
		if state == "blade":
			d.twist_editor.drag_station_to(5, d.twist_editor.to_pixels(0.6, 27.0))
			d.chord_editor.drag_station_to(24, d.chord_editor.to_pixels(0.6, 15.0))
			d.step_pitch(0.5)
			d.set_caret(0.45)
			d.set_thickness(0.14)
		if state == "blade_low":
			d.twist_editor.drag_station_to(5, d.twist_editor.to_pixels(0.6, 30.0))
			(d.find_child("LeftScroll", true, false) as ScrollContainer).scroll_vertical = 100000
		for i in 40:
			await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
