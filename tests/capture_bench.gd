extends SceneTree
## Dev tool, not a test: boots the real app shell, walks through to the Bench tab with a chosen
## motor and propeller on the stand, runs the powertrain up to a throttle, and writes a PNG.
## The companion to capture_lab.gd and capture_frame.gd.
##
## This exists for the reason those two do: the headless suite can prove the bench settles on
## the right RPM and still not notice that the stand renders as a black smear, that the boom
## passes through the disc, or that the instruments column has collapsed to nothing.
##
##   godot --script res://tests/capture_bench.gd -- <out.png> [throttle] [motor_id] [prop_id]
##                                                  [settle_frames]
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not
## have, so a headless run HANGS silently rather than failing.
##
## The throttle is applied and then the bench is left to settle for real frames rather than
## being stepped by hand, because what is being photographed is the screen doing its own job —
## a stepped-by-hand bench would prove the physics and not the wiring.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://bench.png"
	var throttle: float = float(args[1]) if args.size() > 1 else 0.5
	var motor_id: String = args[2] if args.size() > 2 else ""
	var prop_id: String = args[3] if args.size() > 3 else ""
	var settle: int = int(args[4]) if args.size() > 4 else 40

	# The rooms without a shell around them. This used to load root.tscn, which was the eight-tab
	# AppShell; root.tscn is the Glass Bench shell now, and a room screenshot wants neither shell's
	# chrome in the frame. RoomHost is exactly the rooms — unchanged by the swap, which is the
	# point of it existing.
	var shell := RoomHost.new()
	root.add_child(shell)

	if motor_id != "" and not shell.lab.motor_picker.select_id(motor_id):
		print("no such motor in the visible list: %s" % motor_id)
		quit(1)
		return
	if prop_id != "" and not shell.lab.propeller_picker.select_id(prop_id):
		print("no such propeller in the visible list: %s" % prop_id)
		quit(1)
		return

	shell.show_bench()
	shell.bench.set_throttle(throttle)

	for _i in settle:
		await process_frame

	var readings: Dictionary = shell.bench.readings()
	print("bench: %.0f g, %.0f RPM, %.1f A, %.2f V, %.2f g/W at %.0f%% throttle" % [
		readings["thrust_g"], readings["rpm"], readings["current_a"],
		readings["voltage_v"], readings["efficiency_g_per_w"], throttle * 100.0])
	print("validation: %s" % ThrustValidation.summary_for(
		shell.lab.catalog, shell.bench.current_build().motor).replace("\n", " / "))

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
