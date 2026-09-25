extends SceneTree
## TEMPORARY: times opening the Field system in the real shell.  -- --parts : cold per-part timing
var shell: Node
var frames := 0
var t0 := 0
var phase := 0
var parts := false
func _initialize() -> void:
	parts = "--parts" in OS.get_cmdline_user_args()
	shell = (load("res://src/scenes/root.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	process_frame.connect(_on_frame)
func _on_frame() -> void:
	frames += 1
	if phase == 0 and frames == 90:
		phase = 1
		var f = shell.field_room()
		if parts:
			f.build = shell.rooms.lab.current_build()
			for m in ["_fill_lists", "_refresh_world", "_refresh_panels", "_render_controls"]:
				var s := Time.get_ticks_usec(); f.call(m)
				print("PART %-18s %7.1f ms" % [m, (Time.get_ticks_usec() - s) / 1000.0])
		var a := Time.get_ticks_usec()
		shell.select_system_by_name("Field")
		print("OPEN select_system_by_name  %7.1f ms" % ((Time.get_ticks_usec() - a) / 1000.0))
		t0 = Time.get_ticks_usec(); frames = 0
	elif phase == 1:
		var now := Time.get_ticks_usec()
		if frames <= 6: print("OPEN frame %d               %7.1f ms" % [frames, (now - t0) / 1000.0])
		t0 = now
		if frames == 6:
			phase = 2; frames = 0
			shell.select_system_by_name("Frame")
	elif phase == 2 and frames == 30:
		phase = 3; frames = 0
		var a := Time.get_ticks_usec()
		shell.select_system_by_name("Field")
		print("REOPEN select               %7.1f ms" % ((Time.get_ticks_usec() - a) / 1000.0))
		t0 = Time.get_ticks_usec()
	elif phase == 3:
		var now := Time.get_ticks_usec()
		if frames <= 3: print("REOPEN frame %d             %7.1f ms" % [frames, (now - t0) / 1000.0])
		t0 = now
		if frames == 3: quit()
