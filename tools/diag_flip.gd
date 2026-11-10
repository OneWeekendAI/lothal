extends SceneTree
## Flip diagnosis: flies a survey with MissionRunner stepping and prints a ring of the last seconds before loss of control.
## usage: godot --headless --script res://tools/diag_flip.gd -- (same args as run_survey_cal.gd) [--tail=4] [--every=25]

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var fs := String(a.get("field", "1500x500")).split("x")
	var fw := float(fs[0])
	var fh := float(fs[1])
	var poly := PackedVector2Array([Vector2(30, 0), Vector2(30 + fw, 0), Vector2(30 + fw, fh), Vector2(30, fh)])
	var fields := {}
	for pair in [["height", "height_m"], ["speed", "speed_mps"], ["front", "front_overlap"], ["side", "side_overlap"], ["reserve", "reserve_pct"]]:
		if a.has(pair[0]):
			fields[pair[1]] = float(a[pair[0]])
	var params := {"class_id": a.get("class", "mapper"), "mission": Mission.SURVEY, "seed": int(a.get("seed", "1")), "fields": fields, "polygon": poly,
		"wind_speed_mps": float(a.get("wind", "0")), "wind_from_deg": float(a.get("wind-from", "90")), "gust_mps": float(a.get("gust", "0")),
		"max_sorties": 1, "farm_acres": float(fw * fh / 4046.856)}
	if a.has("camera"):
		params["camera"] = CameraParams.from_preset(String(a["camera"]))
		var cam: CameraParams = params["camera"]
		if not fields.has("speed_mps"):
			fields["speed_mps"] = Mission.fp_survey_speed(cam, float(fields.get("height_m", 60.0)), float(fields.get("front_overlap", 0.75)), 15.0)
	var every := int(a.get("every", "25"))
	var tail_s := float(a.get("tail", "4"))
	var r := MissionRunner.new()
	if not r.begin(params):
		print("not flying")
		quit(1)
		return
	if a.has("tilt"):
		r.rig.nav.tilt_limit_deg = float(a["tilt"])
		r.rig.nav.a_brake_mps2 = 0.4 * 9.81 * tan(deg_to_rad(float(a["tilt"])))
	var ring: Array = []
	var cap := int(tail_s * 500.0 / every)
	while not r.is_done():
		r.advance(every)
		var rig := r.rig
		var rb := rig.core.rigid_body
		var o := rig.core.observables
		var up := rb.orientation * Vector3.UP
		var tilt := rad_to_deg(acos(clampf(up.y, -1, 1)))
		var wt: Vector3 = rig.core.wind.velocity_mps()
		var va := rb.velocity_mps - wt
		var th := 0.0
		var mx := 0.0
		for i in 4:
			th += o.thrust_n[i]
			mx = maxf(mx, o.thrust_n[i])
		var mn: float = o.thrust_n[0]
		for i in 4:
			mn = minf(mn, o.thrust_n[i])
		var vh := Vector2(va.x, va.z)
		var bv: Vector3 = rig.core.powertrain.last_body_velocity_mps
		var rr: float = o.thrust_n[0] / maxf(PropellerModel.thrust_n(rig.core.powertrain.k_t, o.rpm[0]), 1e-6)
		var row := "bodyV=(%5.1f,%5.1f,%5.1f) trat=%.3f " % [bv.x, bv.y, bv.z, rr] + "t=%6.2f ph=%s pos=(%7.1f,%5.1f,%6.1f) tilt=%5.1f v=(%5.1f,%5.1f,%5.1f) airspd_h=%5.1f air_vert=%5.1f wind_now=(%5.1f,%5.1f,%5.1f) T/W=%4.2f Tmax=%5.2f Tmin=%5.2f rpm=%5.0f/%5.0f/%5.0f/%5.0f I=%5.1fA V=%5.2f yawrate=%5.2f" % [
			rig.time_s, r.phase, rb.position_m.x, rb.position_m.y, rb.position_m.z, tilt, rb.velocity_mps.x, rb.velocity_mps.y, rb.velocity_mps.z, vh.length(), va.y,
			wt.x, wt.y, wt.z, th / maxf(o.weight_n, 0.001), mx, mn, o.rpm[0], o.rpm[1], o.rpm[2], o.rpm[3], o.current_total_a, o.voltage_live_v, rb.angular_velocity_rad_s.y]
		row += " thrff=%.2f trim=%.2f thr=%.2f" % [rig.nav._thr_ff, rig.nav._thr_trim, rig.nav.last_rc["throttle"]]
		var eu := Basis(rb.orientation).get_euler(EULER_ORDER_YXZ)
		row += " rc_p=%.2f rc_r=%.2f pitch=%.1f roll=%.1f q=%.1f p=%.1f" % [rig.nav.last_rc["pitch"], rig.nav.last_rc["roll"], rad_to_deg(eu.x), rad_to_deg(eu.z), rad_to_deg(rb.angular_velocity_rad_s.x), rad_to_deg(rb.angular_velocity_rad_s.z)]
		row += " mode=%s leg=%d dir=(%.2f,%.2f) spd=%.1f endspd=%.1f len=%.0f along=%.0f veli=(%.2f,%.2f) yaw=%.0f" % [rig.nav._mode, rig.nav._path_i, rig.nav._dir.x, rig.nav._dir.y, rig.nav._speed, rig.nav._end_speed, rig.nav._len, (Vector2(rb.position_m.x, rb.position_m.z) - rig.nav._from).dot(rig.nav._dir), rig.nav._vel_i.x, rig.nav._vel_i.y, rad_to_deg(rig.nav.estimate()["yaw"])]
		ring.append(row)
		if ring.size() > cap:
			ring.pop_front()
	for row in ring:
		print(row)
	print("ended=%s weight_n=%.2f" % [r.ended_by, r.rig.core.observables.weight_n])
	quit(0)
