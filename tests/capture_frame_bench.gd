extends SceneTree
## Dev tool, not a test: boots the real app shell, walks through to the frame bench with a chosen
## frame carrying chosen parts, runs the step, and writes a PNG. The companion to
## capture_esc_bench.gd, capture_battery_bench.gd, capture_bench.gd and capture_lab.gd.
##
##   godot --script res://tests/capture_frame_bench.gd -- <out.png> [frame_id] [axis] [motor_id] [prop_id]
##
## `axis` is "roll", "pitch" or "yaw", defaulting to roll — the axis the arm-length result lives on.
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not have,
## so a headless run HANGS silently rather than failing.
##
## The step is driven by hand with the bench's own _process turned off, the way capture_esc_bench.gd
## drives its sweep. With both driving it every substep would be counted twice, the response would
## arrive in half the time, and the picture would look entirely plausible.
##
## THE PAIR WORTH SHOOTING is the same parts on a short frame and a long one, which is the whole
## argument of the bench in two frames — and the camera distance is fixed across the catalog, so the
## 7" is visibly the bigger aircraft as well as the slower one:
##
##   ... -- /tmp/framebench_3in.png frame_3in_toothpick
##   ... -- /tmp/framebench_7in.png frame_7in_long_range

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://frame_bench.png"
	var frame_id: String = args[1] if args.size() > 1 else ""
	var axis_name: String = args[2] if args.size() > 2 else "roll"
	var motor_id: String = args[3] if args.size() > 3 else ""
	var prop_id: String = args[4] if args.size() > 4 else ""

	var shell: AppShell = load("res://src/scenes/root.tscn").instantiate()
	root.add_child(shell)

	for pair in [[frame_id, shell.lab.picker], [motor_id, shell.lab.motor_picker],
			[prop_id, shell.lab.propeller_picker]]:
		var part_id: String = pair[0]
		var rail: PartPicker = pair[1]
		if part_id != "" and not rail.select_id(part_id):
			print("no such part in the visible list: %s" % part_id)
			quit(1)
			return

	shell.show_frame_bench()
	var bench: FrameBenchScreen = shell.frame_bench

	var axis := FrameBench.AXIS_NAMES.find(axis_name)
	if axis < 0:
		print("no such axis: %s (want one of %s)" % [axis_name, ", ".join(FrameBench.AXIS_NAMES)])
		quit(1)
		return
	bench.set_axis(axis)

	# See the header: the bench must not be advanced by its own _process and by this loop at once.
	bench.set_process(false)
	bench.start_run()
	var guard := 0
	while bench.running and guard < 100000:
		bench.advance(1.0 / 240.0)
		guard += 1

	var reading: Dictionary = bench.readings()
	print("%s on %.0f mm arms, %.0f g all up — %s step" % [
		bench.current_build().frame["name"], reading["arm_mm"], reading["all_up_weight_g"],
		reading["axis_name"]])
	print("  inertia: roll %.0f  pitch %.0f  yaw %.0f g*cm^2" % [
		reading["inertia_roll_kg_m2"] * 1.0e7, reading["inertia_pitch_kg_m2"] * 1.0e7,
		reading["inertia_yaw_kg_m2"] * 1.0e7])
	print("  peak torque %.3f N*m over %.0f g*cm^2 -> %.0f rad/s^2; %s to %.0f deg/s" % [
		reading["peak_torque_n_m"], reading["inertia_kg_m2"] * 1.0e7,
		reading["peak_alpha_rad_s2"],
		"never" if reading["time_to_rate_s"] < 0.0
			else "%.0f ms" % (reading["time_to_rate_s"] * 1000.0),
		reading["target_rate_deg_s"]])
	print("  the 5\" reference took %s on %.0f g*cm^2" % [
		"never" if reading["yardstick_time_to_rate_s"] < 0.0
			else "%.0f ms" % (reading["yardstick_time_to_rate_s"] * 1000.0),
		reading["yardstick_inertia_kg_m2"] * 1.0e7])
	print("  prop clearance %+.1f mm;  %d samples a series" % [
		reading["prop_gap_mm"], bench.trace.sample_count()])

	# Two frames, because the trace only queues a redraw — the first processes the layout and the
	# second is the one that has the polylines in it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
