class_name TestWatchCard
## S6 (UI_REDESIGN_TRACKER): the watched mission's card in the sim. A short watched mission is stepped frame by frame; the
## progress the card shows never goes back, the Mission picker's Watch is busy (and Run held) while it flies and free
## after, and the result card at the end shows exactly `watch_result`. Back to design leaves the sim.

static func run() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_watchcard_%d" % OS.get_process_id()
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	shell.open_mission_picker()
	var picker := shell.mission_picker
	var opts := {"mission": "cruise_loop", "seed": 11, "capacity_scale": 0.15, "gust_mps": 1.5,
		"wind_speed_mps": 3.0, "wind_from_deg": 60.0}
	results.append(TestResult.new("before Watch: both buttons are free", not picker.watch_button.disabled and not picker.headless_button.disabled, ""))
	picker.watch_requested.emit(opts)
	var sim = shell.rooms.sim
	var card: DsWatchCard = sim.watch_card if sim != null else null
	results.append(TestResult.new("Watch shows the card with the mission's name",
		card != null and card.visible and card.mission_label.text == "Cruise loop", str(card)))
	results.append(TestResult.new("while the flight runs Watch is busy and Run is held",
		picker.watching and picker.watch_button.disabled and picker.watch_button.text == "Watching..." and picker.headless_button.disabled, picker.watch_button.text))
	var last := 0.0
	var monotone := true
	var moved := false
	var shown_ok := true
	var frames := 0
	while sim != null and sim.watch_runner != null and frames < 200000:
		sim._watch_frame(1.0 / 60.0)
		frames += 1
		var p: float = card.progress
		if p < last:
			monotone = false
		if p > 0.0 and p < 1.0:
			moved = true
		if absf(card.bar.value - p * 100.0) > 0.01 or (sim.watch_runner != null and card.results.visible):
			shown_ok = false
		last = p
	results.append(TestResult.new("progress never goes back and passes through the middle", monotone and moved, "%d frames, last %.3f" % [frames, last]))
	results.append(TestResult.new("the bar shows what the card holds, and no result card until the end", shown_ok, ""))
	results.append(TestResult.new("the bar is full at the end", is_equal_approx(card.progress, 1.0) and card.done and not card.running, ""))
	results.append(TestResult.new("the result card IS watch_result (same dictionary, same JSON)",
		not sim.watch_result.is_empty() and card.results.visible and card.results.result == sim.watch_result
		and MissionResult.to_json(card.results.result) == MissionResult.to_json(sim.watch_result), ""))
	results.append(TestResult.new("the result card shows the flown figures",
		card.results.text().contains("Endurance") and card.results.text().contains(ResultsPanel.figure_name("flight_time_s")), card.results.text().left(80)))
	results.append(TestResult.new("after the flight Watch and Run are free again",
		not picker.watching and not picker.watch_button.disabled and not picker.headless_button.disabled and picker.watch_button.text == "Watch it", picker.watch_button.text))
	results.append(TestResult.new("Back to design is offered after, and not before", card.back_button.visible, ""))
	results.append(TestResult.new("the card's Back is wired to the sim's back_to_design_requested", card.back_requested.get_connections().size() > 0
		and sim.back_to_design_requested.is_connected(shell.back_to_drone_from_room), ""))
	shell.back_to_drone_from_room()   # what that signal calls, a frame after the press (it frees the sim, so it cannot run inside it)
	results.append(TestResult.new("Back to design leaves the sim for the Design Space",
		not shell.away_from_design() and shell.design_space.visible, ""))
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results
