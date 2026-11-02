extends SceneTree
## Dev tool, not a test: photographs the Design Space the way a builder reaches it - real
## GlassShell, New drone, pick a class, Choose.
##
##   godot --script res://tests/capture_design_space.gd -- <out.png> <class id> [WxH] [close-up mesh name]
##       [selected address] [hovered address] [swap cat=id,...] [preview cat=id] [frame op]
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
		print("preview %s" % ds.hover_card(kv[0], kv[1]))
	# A frame op (Section 4) on arm FL, 91 mm out along its axis (tests/test_frame_edits_ui.gd's
	# point): "drill" drills a 3 mm hole there through the tool's own click path; "refuse" drills on
	# the arm's first lightening hole, so the refusal line shows; "select" only selects the arm.
	var frame_op: String = args[8] if args.size() > 8 else ""
	if frame_op != "":
		ds.select("frame/arm/FL")
		var doc := ds.session.frame_document()
		var fl := ds.session.plate_of_mesh("frame_arm_FL")
		var plate: Dictionary = doc.plates[fl]
		var top := AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate)
		var aim := AirframeDocument.point_of(plate["tip_point"]).normalized() * 91.0
		if frame_op == "refuse":
			var k := FrameTools.hole_names(plate).find("pick_hole_arm_FL_1")
			aim = FrameTools.centre_of(AirframeDocument.plate_holes(plate)[k])
		if frame_op in ["drill", "refuse"]:
			ds.set_frame_tool("drill")
			ds.drill_d_mm = 3.0
			print("frame op %s -> %s" % [frame_op, ds.drill_at(ds.rig.project(FrameView.space_point(aim, top, ds.doc_xf())))])
		print("change: %s" % ds.frame_change_text())
		# Close on the drill point (30 mm across), so a 3 mm hole is visible.
		var c := FrameView.space_point(aim, top, ds.doc_xf())
		ds.rig.frame(AABB(c - Vector3(0.015, 0.004, 0.015), Vector3(0.03, 0.008, 0.03)))
		# From nearly overhead: the pack and the props stand between the home view and this arm.
		ds.rig.goal_pitch = deg_to_rad(78.0)
	# "shelf:battery,motor" opens the parts shelf with those categories expanded.
	var shelf_arg: String = args[9] if args.size() > 9 else ""
	if shelf_arg.begins_with("shelf"):
		ds.shelf.set_open(true)
		for cat in shelf_arg.trim_prefix("shelf").trim_prefix(":").split(",", false):
			ds.shelf.toggle_category(cat)
	# Arg 10, "motor:kv:kv_mid,..." presses those shelf chips (category:group:option).
	var chip_arg: String = args[10] if args.size() > 10 else ""
	for spec in chip_arg.split(",", false):
		var bits := spec.split(":")
		ds.shelf.set_filter(bits[0], bits[1], bits[2])
	# Arg 12 "labels_off" presses the eye: every label, callout and warning pin hidden.
	if args.size() > 12 and args[12] == "labels_off":
		ds.toggle_labels()
	for i in 60:
		await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
