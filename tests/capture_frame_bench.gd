extends SceneTree
## Dev tool, not a test: boots the real app shell, walks through to the frame bench with a chosen
## frame carrying chosen parts, runs the step, and writes a PNG. The companion to
## capture_esc_bench.gd, capture_battery_bench.gd, capture_bench.gd and capture_lab.gd.
##
##   godot --script res://tests/capture_frame_bench.gd -- <out.png> [frame_id] [axis] [motor_id] [prop_id] [pack_offset_mm]
##
## `axis` is "roll", "pitch" or "yaw", defaulting to roll — the axis the arm-length result lives on.
##
## `pack_offset_mm` slides the pack fore (positive) or aft on its mount, clamped to whatever travel
## the frame and pack leave. It exists so THE PAIR that proves the mass model can be shot: the same
## build with the pack centred and with it slid to its stop, where the only thing that differs is
## the centre-of-mass row and the inertia under it. Before the mount offsets reached the mass model
## that pair would have been two identical panels.
##
##   ... -- /tmp/com_centred.png frame_5in_freestyle roll "" "" 0
##   ... -- /tmp/com_slid.png    frame_5in_freestyle roll "" "" 999
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

## THE TUNING MODE, which is the same tool answering a second question.
##
##   godot --script res://tests/capture_frame_bench.gd -- <out.png> tune
##
## The bench above shows what ONE airframe does open-loop. This shows what three of them do with a
## flight controller in the path, on the fixed gains and on the derived ones, on identical axes —
## which is the whole argument of rate_tune.gd in one picture.
##
## It reuses BandTrace, the chart the bench itself draws its step response on, one per frame with
## the fixed-gain response as the upper series and the derived one as the lower. Three panels rather
## than six lines on one, because the frames differ by 30x in yaw plant and stacking them would draw
## the whoop's response as a spike against the 10"s: the axes have to be identical for the
## comparison to mean anything, and identical axes on one chart means two of the six lines are flat.
##
## Yaw, not roll. Roll is the axis the frame bench itself is about; yaw is where the fixed gains
## were worst by a distance, and where the picture has something to say.
const TUNE_FRAMES := ["frame_65mm_whoop", "frame_5in_freestyle", "frame_10in_long_range"]
const TUNE_STEP_DEG_S := 50.0
const TUNE_DURATION_S := 0.45
const TUNE_DT := 0.001
const TUNE_AXIS := 2   # yaw


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and args[1] == "tune":
		_capture_tune_chart(args[0])
		return
	var out_path: String = args[0] if args.size() > 0 else "user://frame_bench.png"
	var frame_id: String = args[1] if args.size() > 1 else ""
	var axis_name: String = args[2] if args.size() > 2 else "roll"
	var motor_id: String = args[3] if args.size() > 3 else ""
	var prop_id: String = args[4] if args.size() > 4 else ""
	var pack_offset_mm: float = float(args[5]) if args.size() > 5 else NAN

	# The rooms without a shell around them. This used to load root.tscn, which was the eight-tab
	# AppShell; root.tscn is the Glass Bench shell now, and a room screenshot wants neither shell's
	# chrome in the frame. RoomHost is exactly the rooms — unchanged by the swap, which is the
	# point of it existing.
	var shell := RoomHost.new()
	root.add_child(shell)

	for pair in [[frame_id, shell.lab.picker], [motor_id, shell.lab.motor_picker],
			[prop_id, shell.lab.propeller_picker]]:
		var part_id: String = pair[0]
		var rail: PartPicker = pair[1]
		if part_id != "" and not rail.select_id(part_id):
			print("no such part in the visible list: %s" % part_id)
			quit(1)
			return

	# Slid through Lab's OWN tweaks object, not a fresh one, because that is the object AppShell
	# hands the bench — a second one here would move the picture and leave the bench measuring the
	# aircraft nobody asked for, which is the exact divergence this slice closed.
	if is_finite(pack_offset_mm):
		var travel := AssemblyTweaks.battery_travel_mm(shell.lab.current_build())
		shell.lab.tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET,
			clampf(pack_offset_mm, -travel, travel))

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
	print("  centre of mass %.2f mm off centre" % reading["com_offset_mm"])

	# Two frames, because the trace only queues a redraw — the first processes the layout and the
	# second is the one that has the polylines in it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()


## One closed-loop yaw step, as [[t, deg/s], ...]. `tune` null means the fixed gains, which is the
## behaviour this chart exists to show being replaced.
static func _tune_trace(build: Build, tune: RateTune) -> Array:
	var core := build.build_drone_core()
	core.powertrain.battery.set_to_nominal_datum()
	var controller := RateModeController.new()
	controller.adopt_tune(tune)
	var throttle := build.hover_throttle()
	var setpoint := Vector3.ZERO
	setpoint[TUNE_AXIS] = deg_to_rad(TUNE_STEP_DEG_S) / RateModeController.MAX_RATE_RAD_S

	var out: Array = []
	for i in int(TUNE_DURATION_S / TUNE_DT):
		core.step(controller.update(setpoint, core.gyro.rate_rad_s, throttle, TUNE_DT), TUNE_DT)
		out.append([(i + 1) * TUNE_DT,
			rad_to_deg(Gyro.contract_rates(core.rigid_body.angular_velocity_rad_s)[TUNE_AXIS])])
	return out


func _capture_tune_chart(out_path: String) -> void:
	# Taller than the app's own window: three stacked charts with their captions do not fit in
	# 720, and a proof image with its third panel cut off is not a proof of anything.
	DisplayServer.window_set_size(Vector2i(1280, 900))

	var theme := LothalTheme.get_theme()
	var backdrop := PanelContainer.new()
	backdrop.theme = theme
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	backdrop.add_child(column)

	var heading := Label.new()
	heading.text = "%.0f deg/s YAW STEP — FIXED GAINS vs DERIVED, IDENTICAL AXES" % TUNE_STEP_DEG_S
	heading.theme_type_variation = &"TitleLabel"
	column.add_child(heading)

	var legend := Label.new()
	legend.text = "red: one gain set for every build (kp 6.0 throughout)      blue: derived from each airframe's own yaw acceleration"
	legend.theme_type_variation = &"MutedLabel"
	column.add_child(legend)

	var catalog := PartsCatalog.load_default()
	for frame_id in TUNE_FRAMES:
		var build := Build.from_ids(catalog, frame_id, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID)
		var tune := RateTune.derive(build)
		var fixed := _tune_trace(build, null)
		var derived := _tune_trace(build, tune)

		var caption := Label.new()
		caption.text = "%s — yaw plant %.0f rad/s%s, %.2fx the reference.   fixed kp %.1f  ->  derived kp %.2f" % [
			build.frame["name"], tune.plant_alpha.z, "\u00b2", tune.scale.z,
			RateModeController.REFERENCE_KP.z, tune.kp.z]
		caption.theme_type_variation = &"MutedLabel"
		column.add_child(caption)

		var chart := BandTrace.new()
		chart.x_axis = BandTrace.XAxis.TIME_FINE
		chart.x_max = TUNE_DURATION_S
		# Every sample kept: the whole event is 450 ms and the chart's default interval would draw
		# it as a handful of points.
		chart.base_interval = 0.0
		chart.y_unit = "deg/s"
		chart.y_step = 20.0
		chart.upper_colour = LothalTheme.DANGER      # the fixed gains
		chart.lower_colour = LothalTheme.ACCENT      # the derived tune
		chart.reference_label = "%.0f deg/s demanded" % TUNE_STEP_DEG_S
		chart.custom_minimum_size = Vector2(860, 210)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(chart)
		# clear() rather than only setting base_interval: the running interval is seeded at
		# construction, so a chart told to keep every sample after it was built keeps one every
		# 50 ms anyway and draws a 450 ms event as nine points.
		chart.clear()
		# IDENTICAL on all three, and that is the point of the picture: the y range is not fitted to
		# each frame, so the whoop ringing to 82 deg/s and the 10" crawling up to 50 are drawn
		# against the same ruler.
		chart.configure(0.0, 90.0, TUNE_STEP_DEG_S)
		for i in fixed.size():
			chart.sample(fixed[i][0], fixed[i][1], derived[i][1])

		print("%s: fixed peak %.1f deg/s, derived peak %.1f deg/s" % [frame_id,
			_peak(fixed), _peak(derived)])

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()


static func _peak(trace: Array) -> float:
	var peak := 0.0
	for row in trace:
		peak = maxf(peak, row[1])
	return peak
