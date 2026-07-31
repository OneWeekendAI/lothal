extends SceneTree
## Dev tool, not a test: boots the real app shell, walks through to the ESC bench with a chosen
## board under the chosen motors, runs the sweep, and writes a PNG. The companion to
## capture_battery_bench.gd, capture_bench.gd, capture_lab.gd and capture_frame.gd.
##
##   godot --script res://tests/capture_esc_bench.gd -- <out.png> [esc_id] [motor_id] [prop_id]
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not
## have, so a headless run HANGS silently rather than failing.
##
## The sweep is driven by hand with the bench's own _process turned off, the way
## capture_battery_bench.gd drives the discharge — not to compress time here (six seconds is not
## long) but because with both driving it every step would be counted twice, the ramp would reach
## the top in three seconds, and the picture would look entirely plausible.
##
## The pair worth shooting is the same motors under two different boards, which is the whole
## argument of the bench in two frames:
##
##   ... -- /tmp/esc_ample.png      esc_4in1_60a_30x30
##   ... -- /tmp/esc_undersized.png esc_4in1_20a_20x20

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://esc_bench.png"
	var esc_id: String = args[1] if args.size() > 1 else ""
	var motor_id: String = args[2] if args.size() > 2 else ""
	var prop_id: String = args[3] if args.size() > 3 else ""

	var shell: AppShell = load("res://src/scenes/root.tscn").instantiate()
	root.add_child(shell)

	for pair in [[esc_id, shell.lab.esc_picker], [motor_id, shell.lab.motor_picker],
			[prop_id, shell.lab.propeller_picker]]:
		var part_id: String = pair[0]
		var rail: PartPicker = pair[1]
		if part_id != "" and not rail.select_id(part_id):
			print("no such part in the visible list: %s" % part_id)
			quit(1)
			return

	shell.show_esc_bench()
	var bench: EscBenchScreen = shell.esc_bench

	# See the header: the bench must not be advanced by its own _process and by this loop at once.
	bench.set_process(false)
	bench.start_sweep()
	var guard := 0
	while bench.running and guard < 100000:
		bench.advance(1.0 / 60.0)
		guard += 1

	var reading: Dictionary = bench.readings()
	print("%s under four %s: %.0f A a channel rated, %.1f A drawn, headroom %+.1f A (%s)" % [
		bench.current_build().esc["name"], bench.current_build().motor["name"],
		reading["rating_a"], reading["draw_per_channel_a"], reading["headroom_a"],
		"ample" if reading["has_headroom"] else "UNDERSIZED"])
	print("crossing: %s;  runs out first: %s;  %d samples out to %.0f%% throttle" % [
		"never" if reading["crossing_throttle"] < 0.0
			else "%.0f%% throttle" % (reading["crossing_throttle"] * 100.0),
		reading["binding_component"], bench.trace.sample_count(), bench.trace.span() * 100.0])

	# Two frames, because the trace only queues a redraw — the first processes the layout and the
	# second is the one that has the polyline in it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
