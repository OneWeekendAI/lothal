extends SceneTree
## Dev tool, not a test: builds a scratch log directory, constructs StudioScreen over it directly
## (no AppShell — the closest precedent, capture_field_editor.gd, boots the shell because a course
## has to cross the door into Sim; a log never crosses anywhere), and writes two PNGs so a human can
## look at the redesigned room. The companion to capture_lab.gd and capture_field_editor.gd.
##
##   godot --script res://tests/capture_studio.gd -- <gap.png> <explore.png> [resolution_WxH]
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not
## have, so a headless run HANGS silently rather than failing.
##
## resolution_WxH matches capture_lab.gd's argument of the same name and exists for the same
## reason: a capture at one convenient window size is how the report pane getting pushed off a
## NARROW window went unnoticed. Take one shot near the project's declared minimum
## (window/size/min_size in project.godot, currently 1024x600) alongside the default/wide one —
## the report pane's right edge is the thing to check in the narrow shot.
##
## The two logs are written through FlightRecorder, the same way tests/test_studio.gd's
## _write_log helper does it, so the header on screen is a real one rather than a hand-written
## approximation. Never user://logs — a SCRATCH directory, removed at the end, so a capture run
## does not leave fake flights in a builder's real history.
const SCRATCH_DIR := "user://capture_studio_logs"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var gap_path: String = args[0] if args.size() > 0 else "user://studio_gap.png"
	var explore_path: String = args[1] if args.size() > 1 else "user://studio_explore.png"

	if args.size() > 2 and args[2] != "":
		var res_parts := args[2].split("x")
		if res_parts.size() == 2:
			var w := int(res_parts[0])
			var h := int(res_parts[1])
			DisplayServer.window_set_size(Vector2i(w, h))
			root.size = Vector2i(w, h)

	_fresh_dir()
	var newer_id := _write_log("flight-20260816-140000.csv", 3000, 2)
	_write_log("flight-20260816-090000.csv", 3000)

	var library := FlightLogLibrary.load_from(SCRATCH_DIR)
	var studio := StudioScreen.new(library)
	root.add_child(studio)
	studio.select(newer_id)

	# ---- Shot 1: the gap view, declared block collapsed (its default — nothing to do).
	studio.set_view_mode(StudioScreen.ViewMode.GAP)
	studio.set_declared_expanded(false)
	await _settle()
	_shoot(gap_path)

	# ---- Shot 2: the explorer, three channels of three different units so all three lanes draw.
	studio.set_view_mode(StudioScreen.ViewMode.EXPLORE)
	_select_channels(studio, ["gyro_x_rad_s", "m1_rpm", "m1_thrust_n"])
	await _settle()
	_shoot(explore_path)

	studio.free()
	_clean()
	quit()


## Two frames, because the trace and the report pane only queue a redraw — the first processes the
## layout and the second is the one with content on it. Matches capture_field_editor.gd's shape.
func _settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _shoot(out_path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])


## Selects the given channel names in the picker by name rather than by index, so the fixture
## reads the same regardless of the header's column order. Selected on the UNFILTERED list and in
## one pass — set_channel_filter() rebuilds the ItemList from scratch on every call (see
## _rebuild_channel_list), which drops whatever was selected under a previous filter, so filtering
## once per name and re-selecting as we go loses everything but the last name picked.
func _select_channels(studio: StudioScreen, names: Array) -> void:
	studio.set_channel_filter("")
	var list: ItemList = studio._channel_list
	list.deselect_all()
	for name in names:
		for i in list.item_count:
			if list.get_item_text(i).begins_with(name):
				list.select(i, false)
				break
	studio._load_selected_channels()


## Writes a real log through the real recorder, the same approach as tests/test_studio.gd's
## _write_log — so the header is genuine rather than a hand-written approximation.
func _write_log(name: String, rows: int, jumps: int = 0) -> String:
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	var throttle := ReferenceBuild.hover_throttle()
	core.prime_motors(throttle)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	var recorder := FlightRecorder.new(build, 1, null, core.gyro)
	recorder.discontinuities = jumps

	for _i in rows:
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, 0.001)
		core.step(cmds, 0.001)
		recorder.capture(core.observables)

	var path := "%s/%s" % [SCRATCH_DIR, name]
	recorder.save(path)
	return name


func _fresh_dir() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH_DIR))


func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(SCRATCH_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for name in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [SCRATCH_DIR, name]))
	DirAccess.remove_absolute(absolute)
