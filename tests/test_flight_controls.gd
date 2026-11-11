class_name TestFlightControls
## S5 (UI_REDESIGN_TRACKER): the Sim's on-screen flight controls. Each button must make the same state
## change as its key. The key path is the handler named in DsFlightControls.ACTIONS (the table
## Main._physics_process reads), so a button left unconnected shows as no change.

static func _boot() -> Node:
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	m.notification(Node.NOTIFICATION_READY)
	return m


## What each action changes, as one comparable value.
static func _state(m: Node, id: String) -> Variant:
	match id:
		"pause": return m.flight_paused
		"reset", "respawn": return m.core.rigid_body.position_m
		"view": return [m.fpv_view.visible, m.fpv_view.is_fpv_main()]
		"mode": return m.fc.is_rate_mode()
		"listener": return m.drone_audio.listener_mode
		"record": return m._recorder != null
	return null


static func _prepare(m: Node) -> void:
	# Away from the start, so reset and respawn have somewhere to come back from.
	m.core.rigid_body.position_m = m.core.rigid_body.position_m + Vector3(7.0, 5.0, 3.0)


static func run() -> Array:
	var results: Array = []
	var probe := _boot()
	var strip: DsFlightControls = probe.flight_controls
	results.append(TestResult.new("the Sim builds a flight controls strip", strip != null, ""))
	if strip == null:
		probe.free()
		return results
	var ids: Array = []
	var keys: Array = []
	for a in DsFlightControls.ACTIONS:
		ids.append(a[0])
		keys.append(a[3])
	probe.free()
	results.append(TestResult.new("the strip covers pause, reset, respawn, view, mode, listener, record",
		ids == ["pause", "reset", "respawn", "view", "mode", "listener", "record"], str(ids)))
	results.append(TestResult.new("the old keys stay on their actions (C view, L listener, R record, Space mode)",
		_key_of("view") == KEY_C and _key_of("listener") == KEY_L and _key_of("record") == KEY_R
			and _key_of("mode") == KEY_SPACE, ""))
	var distinct := {}
	for k in keys:
		distinct[k] = true
	results.append(TestResult.new("no two actions share a key", distinct.size() == keys.size(), ""))

	for a in DsFlightControls.ACTIONS:
		var id: String = a[0]
		var by_button := _boot()
		_prepare(by_button)
		var before = _state(by_button, id)
		(by_button.flight_controls.buttons[id] as Button).pressed.emit()
		var after_button = _state(by_button, id)
		by_button.free()

		var by_key := _boot()
		_prepare(by_key)
		by_key.call(a[4])
		var after_key = _state(by_key, id)
		by_key.free()

		results.append(TestResult.new("button '%s' changes state" % id, after_button != before,
			"before %s after %s" % [before, after_button]))
		results.append(TestResult.new("button '%s' makes the same change as its key" % id,
			after_button == after_key, "button %s key %s" % [after_button, after_key]))
	return results


static func _key_of(id: String) -> int:
	for a in DsFlightControls.ACTIONS:
		if a[0] == id:
			return a[3]
	return -1
