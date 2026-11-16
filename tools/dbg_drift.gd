extends SceneTree
# usage: godot --headless --script tools/dbg_drift.gd -- mode=file|calm|ten secs=30
const MAIN := preload("res://src/scenes/main.gd")
func _init() -> void:
	var mode := "file"
	var secs := 30.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="): mode = a.substr(5)
		if a.begins_with("secs="): secs = float(a.substr(5))
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	if mode == "calm":
		var c := Conditions.new()
		m.wind = MAIN.make_wind(c)
		m.core.wind = m.wind
	elif mode == "ten":
		var c := Conditions.new()
		c.wind_speed_mps = 10.0
		m.wind = MAIN.make_wind(c)
		m.core.wind = m.wind
	var opts := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("opts="): opts = a.substr(5).split(",")
	for a in opts:
		if a == "nogb": m.core.gyro.bias_rad_s = Vector3.ZERO
		if a == "noab": m.core.accel.bias_mps2 = Vector3.ZERO
		if a == "nonoise":
			m.core.accel.noise_mps2 = 0.0
			m.core.gyro.noise_rad_s = 0.0
		if a == "novib": m.core.gyro.vibration = null
	print("mode=", mode, " wind=", m.wind.speed_mps, " from=", m.wind.from_deg, " gust=", m.wind.gustiness_mps, " cond=", m.conditions_name, " rate_mode=", m.fc.is_rate_mode())
	var p0: Vector3 = m.core.rigid_body.position_m
	print("start ", p0)
	var dt := 1.0 / 120.0
	var n := int(secs / dt)
	for i in n:
		m._physics_process(dt)
		if "fast" in opts and i < 40:
			var up_t2: Vector3 = m.core.rigid_body.orientation * Vector3.UP
			print("f%d tilt=%.4f deg w=%s rpm=%s cmd... " % [i, rad_to_deg(up_t2.angle_to(Vector3.UP)), m.core.rigid_body.angular_velocity_rad_s, m.core.observables.rpm])
		if "trace" in opts and i % 60 == 0 and i < 1200:
			var up_t: Vector3 = m.core.rigid_body.orientation * Vector3.UP
			var up_e: Vector3 = m.fc.estimator.attitude * Vector3.UP
			print("t=%.2f tilt_true=%.3f deg est_up_in_body... est_tilt=%.3f deg vel=%s thr=%.3f hover=%.3f" % [i * dt, rad_to_deg(up_t.angle_to(Vector3.UP)), rad_to_deg(up_e.angle_to(Vector3.UP)), m.core.rigid_body.velocity_mps, m.rc.throttle, m._hover_throttle])
		if i % 1200 == 0:
			var p: Vector3 = m.core.rigid_body.position_m
			print("t=%.1f d=%s v=%s crashed=%s" % [i * dt, p - p0, m.core.rigid_body.velocity_mps, m.core.crashed])
	var p1: Vector3 = m.core.rigid_body.position_m
	print("END drift=", p1 - p0, " horiz=", Vector2(p1.x - p0.x, p1.z - p0.z).length(), " m  rate=", Vector2(p1.x - p0.x, p1.z - p0.z).length() / secs, " m/s")
	quit()
