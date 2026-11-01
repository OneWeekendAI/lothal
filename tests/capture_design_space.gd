extends SceneTree
## Dev tool, not a test: photographs the Design Space the way a builder reaches it - real
## GlassShell, New drone, pick a class, Choose.
##
##   godot --script res://tests/capture_design_space.gd -- <out.png> <class id> [WxH] [close-up mesh name]
##       [selected address] [hovered address] [swap cat=id,...] [preview cat=id]
##
## Swaps go through `DesignSpace.choose` (the picker's own path) after the selection; a preview
## hovers that row of the open picker, so the readout deltas show.
##
## A selected address is clicked through `click_at` at a point on its own surface (clicking again
## until it is selected, as a builder would); a hovered one goes through `hover_at` at its box centre.
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://design_space.png"
	var class_id: String = args[1] if args.size() > 1 else "five_inch"
	if args.size() > 2 and args[2] != "":
		var p := args[2].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var closeup: String = args[3] if args.size() > 3 else ""
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class(class_id)
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var ds: DesignSpace = shell.design_space
	if closeup != "":
		for entry in ds.mesh_boxes():
			if String(entry["name"]).begins_with(closeup):
				ds.rig.frame(entry["box"])
				break
	var select_address: String = args[4] if args.size() > 4 else ""
	var hover_address: String = args[5] if args.size() > 5 else ""
	for i in 60:
		await process_frame
	if select_address != "":
		var c := ds.picks.box_of(select_address).get_center()
		var ndc := ds.rig.project(c)
		for i in 8:
			if ds.click_at(ndc) == select_address:
				break
		print("selected %s" % ds.selected)
	if hover_address != "":
		var hc := ds.picks.box_of(hover_address).get_center()
		var hn := ds.rig.project(hc)
		var px := Vector2((hn.x + 1.0) * 0.5 * ds.size.x, (1.0 - hn.y) * 0.5 * ds.size.y)
		print("hovered %s" % ds.hover_at(hn, px))
	var swaps: String = args[6] if args.size() > 6 else ""
	for pair in swaps.split(",", false):
		var kv := pair.split("=")
		print("swap %s -> %s" % [pair, ds.choose(kv[0], kv[1])["ok"]])
	var preview: String = args[7] if args.size() > 7 else ""
	if preview != "":
		var kv := preview.split("=")
		for i in ds.picker_rows().size():
			var row: Dictionary = ds.picker_rows()[i]
			if String(row["category"]) == kv[0] and String(row["id"]) == kv[1]:
				print("preview %s" % ds.hover_row(i))
	for i in 60:
		await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
