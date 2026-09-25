extends SceneTree
## Times entering the field the way room_host.show_sim does. TEMPORARY measurement tool.
var t0 := 0
var frames := 0
var sim: Node
func _initialize() -> void:
	t0 = Time.get_ticks_usec()
	var packed := load("res://src/scenes/main.tscn")
	_p("load(main.tscn)")
	sim = packed.instantiate()
	_p("instantiate")
	sim.adopt_selected_course()
	_p("adopt_selected_course")
	root.add_child(sim)
	_p("add_child (_ready total)")
	process_frame.connect(_on_frame)
func _on_frame() -> void:
	frames += 1
	if frames <= 8 or frames % 30 == 0:
		_p("frame %d" % frames)
	if frames >= 120:
		quit()
func _p(label: String) -> void:
	var now := Time.get_ticks_usec()
	print("STEP %-28s %8.1f ms" % [label, (now - t0) / 1000.0])
	t0 = now
