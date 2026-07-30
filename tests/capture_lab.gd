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
