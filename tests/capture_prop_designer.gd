extends SceneTree
## Dev tool, not a test: photographs the prop designer over the real Design Space, reached the way a
## builder reaches it: GlassShell, New drone, open the prop shelf, press the "+" tile.
##
##   godot --script res://tests/capture_prop_designer.gd -- <out.png> [WxH] [state]
##
## state: "" (the default) | "shelf" (no pop-up: the shelf and its tile) | "edited" (a 7 in two-blade
## on PA6+CF with a pad).
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
		for i in 40:
			await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
