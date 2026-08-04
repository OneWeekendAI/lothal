extends SceneTree
## Dev tool, not a test: boots the real app shell (root.tscn), optionally selects a named
## frame, and writes a PNG of the framebuffer. The companion to capture_frame.gd, which does
## the same for Sim.
##
## This exists because the headless suite can prove the arm-tip coordinates are right and
## still not notice that the airframe renders as a black smear or that the rail covers the
## viewport. The last round of bugs on this project were ones the tests could not see.
##
##   godot --script res://tests/capture_lab.gd -- <out.png> [settle_frames] [frame_part_id]
##                                                 [azimuth_deg] [elevation_deg]
##                                                 [motor_part_id] [prop_part_id]
##                                                 ["sim" | <panel name>] [battery_part_id]
##                                                 [resolution_WxH] [esc_part_id]
##
## The pack argument comes last rather than next to the motor and prop, so that every invocation
## written before it existed still means what it meant. Pass "" for the sim/panel slot to reach it
## while staying in Lab.
##
## A trailing "sim" makes the selections in Lab and then walks out through the Sim tab before
## shooting, which is how the project's central claim gets photographed: the airframe in the
## field is the one chosen in the garage.
##
## The motor and prop arguments are what let a specific BUILD be photographed rather than a
## specific frame — needed the moment prop clearance became something to look at, since "a 7"
## prop on a 3" frame" is a combination and not a part.
##
## The orbit angles are applied AFTER settling, because the idle orbit is still turning during
## those frames and would otherwise carry the view off the angle asked for. A negative
## elevation looks up at the underside — which is the view a battery tray or a payload mount
## has to be checked from, and the one a yaw-only turntable can never reach.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://lab.png"
	var settle: int = int(args[1]) if args.size() > 1 else 30
	var part_id: String = args[2] if args.size() > 2 else ""

	if args.size() > 9 and args[9] != "":
		var res_parts := args[9].split("x")
		if res_parts.size() == 2:
			var w := int(res_parts[0])
			var h := int(res_parts[1])
			DisplayServer.window_set_size(Vector2i(w, h))
			root.size = Vector2i(w, h)

	var shell: AppShell = load("res://src/scenes/root.tscn").instantiate()
	root.add_child(shell)

	if part_id == "sim":
		# Shoots Sim as reached through its tab, rather than main.tscn loaded directly the way
		# capture_frame.gd does it — the point being that the door works, not that the field does.
		shell.show_sim()
	elif part_id != "":
		var frames: Array = shell.lab.picker.visible_frames()
		var index := -1
		for i in frames.size():
			if frames[i]["part_id"] == part_id:
				index = i
		if index < 0:
			print("no such frame in the visible list: %s" % part_id)
			quit(1)
			return
		shell.lab.picker.select_index(index)

	if args.size() > 5 and args[5] != "":
		if not shell.lab.motor_picker.select_id(args[5]):
			print("no such motor in the visible list: %s" % args[5])
			quit(1)
			return
	if args.size() > 6 and args[6] != "":
		if not shell.lab.propeller_picker.select_id(args[6]):
			print("no such propeller in the visible list: %s" % args[6])
			quit(1)
			return

	# The pack, last so every existing invocation keeps working. It is selected BEFORE the sim/panel
	# branch below, because walking out to the field with the wrong pack fitted would photograph
	# precisely the claim this argument exists to check.
	if args.size() > 8 and args[8] != "":
		if not shell.lab.battery_picker.select_id(args[8]):
			print("no such pack in the visible list: %s" % args[8])
			quit(1)
			return

	# The board, last again and for the same reason. It matters to a photograph of the BUILD panel
	# because the board is often what binds: shooting a cinelifter through a 45 A stack would
	# photograph a current limit that the build being illustrated does not have.
	if args.size() > 10 and args[10] != "":
		if not shell.lab.esc_picker.select_id(args[10]):
			print("no such ESC in the visible list: %s" % args[10])
			quit(1)
			return

	if args.size() > 7 and args[7] == "sim":
		shell.show_sim()
	elif args.size() > 7 and args[7] != "":
		# Anything else names a right-hand panel to bring to the front ("Fit"), since a panel that
		# is behind a tab cannot otherwise be photographed.
		if not shell.lab.show_panel(args[7]):
			print("no such panel: %s" % args[7])
			quit(1)
			return

	for i in settle:
		await process_frame

	if args.size() > 4:
		# Stop the idle orbit first, or it overwrites the angle on the next frame.
		shell.lab.auto_orbit = false
		shell.lab.set_orbit(deg_to_rad(float(args[3])), deg_to_rad(float(args[4])))
		for i in 2:
			await process_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
