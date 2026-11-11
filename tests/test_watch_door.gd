class_name TestWatchDoor
## B2 (UI_REDESIGN_TRACKER): the Mission picker's Watch it reaches the sim. The shell enters the sim
## through the one door, starts `Main.watch_mission` with MissionFlow's own params, and puts the
## Mission drawer away. The watched result equals the headless MissionFlow.run, field by field.

static func run() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_watchdoor_%d" % OS.get_process_id()
	var shell := DesignApp.new()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	var session := shell.design_space.session
	shell.open_mission_picker()
	var opts := {"mission": "cruise_loop", "seed": 11, "capacity_scale": 0.15, "gust_mps": 1.5,
		"wind_speed_mps": 3.0, "wind_from_deg": 60.0}
	results.append(TestResult.new("the drawer is open before Watch", shell.mission_picker.visible, ""))
	shell.mission_picker.watch_requested.emit(opts)
	var sim = shell.rooms.sim
	results.append(TestResult.new("Watch it enters the sim, Design Space hidden",
		sim != null and shell.away_from_design() and not shell.design_space.visible, str(sim)))
	results.append(TestResult.new("Watch it starts a watched flight (watch_runner set)",
		sim != null and sim.watch_runner != null, ""))
	results.append(TestResult.new("the Mission drawer is not left over the sim", not shell.mission_picker.visible, ""))
	var frames := 0
	if sim != null:
		while sim.watch_runner != null and frames < 200000:
			sim._watch_frame(1.0 / 60.0)
			frames += 1
	var head: Dictionary = MissionFlow.run(session, opts)["result"].duplicate(true)
	head.erase("inputs_trail")
	var watched: Dictionary = sim.watch_result if sim != null else {}
	results.append(TestResult.new("the watched result equals the headless MissionFlow.run result (JSON)",
		not watched.is_empty() and MissionResult.to_json(watched) == MissionResult.to_json(head),
		"%d frames, %d vs %d bytes" % [frames, MissionResult.to_json(watched).length(), MissionResult.to_json(head).length()]))
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results
