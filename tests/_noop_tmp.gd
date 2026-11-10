extends SceneTree
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var ref := SimRealityHarness.find_reference("mavic_3m")
	SimRealityHarness.step_dt = 0.08
	var r := SimRealityHarness.fly(ref, "hover", 1.0)
	print("FLY ms ", Time.get_ticks_msec() - t0, " t ", r["time_min"], " ", r["ended_by"], " tilt ", r["max_tilt_deg"])
	quit(0)
