extends SceneTree
## Dev tool, not a test: boots the real app shell, walks through to the battery bench with a chosen
## pack under a chosen load, runs the discharge forward, and writes a PNG of the trace. The
## companion to capture_bench.gd, capture_lab.gd and capture_frame.gd.
##
##   godot --script res://tests/capture_battery_bench.gd -- <out.png> [battery_id]
##                                                          [hover|punch] [seconds] [motor_id] [prop_id]
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not
## have, so a headless run HANGS silently rather than failing.
##
## ---------------------------------------------------------------------------
## WHY THIS ONE FAST-FORWARDS AND THE THRUST STAND'S DOES NOT
## ---------------------------------------------------------------------------
##
## The thrust stand settles in about thirty milliseconds, so capture_bench.gd can let real frames
## do the work and photograph the screen doing its own job. A pack takes MINUTES to flatten, at
## 1:1, deliberately (labs-and-sim.md §5) — and the knee, which is the thing worth photographing,
## only arrives at the very end.
##
## So this tool turns the bench's own _process off and drives advance() by hand in quarter-second
## steps. That is not a different simulation: BatteryBenchScreen.MAX_SUBSTEPS is set high enough
## that a quarter-second step still runs the powertrain at the full 1 kHz, so the run is exactly
## the one that would have happened over the wall-clock minutes. Turning _process off rather than
## leaving it on is the load-bearing part — with both driving it, every step would be counted
## twice and the pack would drain at double rate while looking entirely plausible.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://battery_bench.png"
	var battery_id: String = args[1] if args.size() > 1 else ""
	var load_name: String = args[2] if args.size() > 2 else "punch"
	var seconds: float = float(args[3]) if args.size() > 3 else 90.0
	var motor_id: String = args[4] if args.size() > 4 else ""
	var prop_id: String = args[5] if args.size() > 5 else ""

	var shell: AppShell = load("res://src/scenes/root.tscn").instantiate()
	root.add_child(shell)

	for pair in [[battery_id, shell.lab.battery_picker], [motor_id, shell.lab.motor_picker],
			[prop_id, shell.lab.propeller_picker]]:
		var part_id: String = pair[0]
		var rail: PartPicker = pair[1]
		if part_id != "" and not rail.select_id(part_id):
			print("no such part in the visible list: %s" % part_id)
			quit(1)
			return

	shell.show_battery_bench()
	var bench: BatteryBenchScreen = shell.battery_bench
	bench.set_load_mode(
		BatteryBenchScreen.Load.PUNCH if load_name == "punch" else BatteryBenchScreen.Load.HOVER)

	# See the header: the bench must not be advanced by its own _process and by this loop at once.
	bench.set_process(false)
	bench.set_running(true)
	var step := 0.25
	var elapsed := 0.0
	while bench.running and elapsed < seconds:
		bench.advance(step)
		elapsed += step

	var reading: Dictionary = bench.readings()
	print("%s under %s: sag %.2f V, %.1f A, %.2f V live (rest %.2f V), %.0f%% left, %.0f g, holds %.0f s more" % [
		bench.current_build().battery["name"], bench.load_name(), reading["sag_v"],
		reading["current_a"], reading["live_v"], reading["resting_v"],
		reading["remaining_fraction"] * 100.0, reading["thrust_g"], reading["hold_up_s"]])
	print("trace: %d samples over %.0f s, deepest sag %.2f V%s" % [
		bench.trace.sample_count(), bench.trace.span(), bench.trace.widest_gap(),
		", pack flat" if not bench.running else ""])

	# Two frames, because the trace only queues a redraw — the first frame processes the layout
	# and the second is the one that has the polyline in it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
