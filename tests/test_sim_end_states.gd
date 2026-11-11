class_name TestSimEndStates
## S7 (UI_REDESIGN_TRACKER): the sim's end states (crash, landing, battery empty, lap finished) speak through
## the Design Space toast (DsToast, owned by DsHud), and the old HUD banner node/path is gone. S6 polish: the race
## panel is hidden when no lap is running, and the flight readouts are hidden while a mission is watched.
##
## FAIL-PROOF (observed): with the old banner restored in ds_hud.gd / main.gd the toast cases and the
## no-banner case FAIL; with the panels always visible the two panel cases FAIL.


const MAIN := preload("res://src/scenes/main.gd")


static func _booted() -> Node:
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	m.notification(Node.NOTIFICATION_READY)
	return m


static func _banner_nodes(n: Node, out: Array) -> void:
	if n.name.to_lower().contains("banner"):
		out.append(str(n.name))
	for c in n.get_children():
		_banner_nodes(c, out)


static func run() -> Array:
	var r: Array = []
	var m := _booted()
	var hud: DsHud = m.hud

	m._respawn_after_crash()
	r.append(TestResult.new("S7 crash: the DS toast says so", hud.toast.visible and hud.toast.message.begins_with("Crashed"),
		"toast \"%s\"" % hud.toast.message))

	hud.toast.clear()
	m._note_battery(true)
	r.append(TestResult.new("S7 battery empty: the DS toast says so", hud.toast.message == "Battery empty.",
		"toast \"%s\"" % hud.toast.message))
	hud.toast.clear()
	m._note_battery(true)
	r.append(TestResult.new("S7 battery empty is said once, not every frame", hud.toast.message == "",
		"toast \"%s\"" % hud.toast.message))
	m._note_battery(false)

	hud.say(MAIN.lap_toast_text(61.5, 0.0))
	r.append(TestResult.new("S7 lap finished (first lap): NEW BEST toast", hud.toast.message.begins_with("NEW BEST"), hud.toast.message))
	r.append(TestResult.new("S7 lap finished (slower than best): LAP toast",
		MAIN.lap_toast_text(70.0, 61.5).begins_with("LAP  "), MAIN.lap_toast_text(70.0, 61.5)))

	var landed := {"ended_by": "completed", "completed": true}
	var empty := {"ended_by": "battery_empty_in_flight", "completed": false}
	var lost := {"ended_by": "lost_control", "completed": false}
	r.append(TestResult.new("S7 landing text", MAIN.watch_end_text(landed).begins_with("Landed")
		and not MAIN.watch_end_is_warning(landed), MAIN.watch_end_text(landed)))
	r.append(TestResult.new("S7 watch ends on an empty pack: Battery empty", MAIN.watch_end_text(empty) == "Battery empty."
		and MAIN.watch_end_is_warning(empty), MAIN.watch_end_text(empty)))
	r.append(TestResult.new("S7 watch ends in a crash: Crashed", MAIN.watch_end_text(lost).begins_with("Crashed"),
		MAIN.watch_end_text(lost)))

	# A real watched mission end puts its toast on the HUD and hides the flight panel while it runs.
	var p := {"class_id": "five_inch", "mission": "hover_endurance", "seed": 11, "capacity_scale": 0.15}
	m.watch_mission(p)
	r.append(TestResult.new("S6 polish: the flight readouts are hidden while a mission is watched",
		not hud._flight_panel.visible and not hud._race_panel.visible, ""))
	var guard := 0
	while m.watch_runner != null and guard < 200000:
		m._watch_frame(1.0 / 60.0)
		guard += 1
	r.append(TestResult.new("S7 a watched mission's end is a DS toast",
		hud.toast.message == MAIN.watch_end_text(m.watch_result) and hud.toast.message != "",
		"toast \"%s\" after %d frames" % [hud.toast.message, guard]))

	var banners: Array = []
	_banner_nodes(m, banners)
	r.append(TestResult.new("S7 no banner node exists in the sim", banners.is_empty(), str(banners)))
	r.append(TestResult.new("S7 the HUD has no show_banner / tick_banner",
		not hud.has_method("show_banner") and not hud.has_method("tick_banner"), ""))
	r.append(TestResult.new("S7 the sim does not call the old banner",
		not FileAccess.get_file_as_string("res://src/scenes/main.gd").contains("show_banner"), ""))

	# Race panel: hidden at the hover start, shown once a lap runs.
	var h2 := DsHud.new()
	r.append(TestResult.new("S6 polish: the race panel starts hidden", not h2._race_panel.visible, ""))
	h2.set_recording(true, 1.0, 10)
	r.append(TestResult.new("race panel shows while recording", h2._race_panel.visible, ""))
	h2.free()
	m.free()
	return r
