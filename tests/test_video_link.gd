class_name TestVideoLink
extends RefCounted
## R2.4: the FPV feed's video system follows the camera part (analog or digital), and the link budget drives it:
## analog noise rises with distance and with line-of-sight blockers; digital shows the lens `latency` old.

static func run() -> Array:
	var r: Array = []
	var cams := _cameras()
	var analog := VideoLink.new(cams.get("cam_micro_analog", {}))
	var digital := VideoLink.new(cams.get("cam_dji_o4_pro", {}))

	# 1. Noise is monotonic in distance, and spans clean-near to lost-far.
	var prev := -1.0
	var mono := true
	var strict := 0
	for i in 120:
		var d := 5.0 + 5.0 * i
		analog.evaluate(d, 0)
		var n := analog.noise()
		if n < prev - 1e-12:
			mono = false
		if n > prev + 1e-9:
			strict += 1
		prev = n
	analog.evaluate(10.0, 0)
	var near := analog.noise()
	analog.evaluate(600.0, 0)
	var far := analog.noise()
	r.append(TestResult.new("r2.4: analog noise never falls as the drone flies away (5..600 m), and rises over the range",
		mono and strict > 10 and near < 0.05 and far > 0.95, "near %.3f far %.3f rising steps %d" % [near, far, strict]))
	digital.evaluate(10.0, 0)
	var q_near := digital.quality
	digital.evaluate(400.0, 0)
	r.append(TestResult.new("r2.4: digital spends a weak link on bitrate, never static (noise 0, bitrate falls)",
		digital.noise() == 0.0 and digital.quality < q_near and digital.bitrate_mbps() < float(digital.cfg["max_mbps"]),
		"q %.2f -> %.2f, %.1f Mbps" % [q_near, digital.quality, digital.bitrate_mbps()]))

	# 2. Line-of-sight blocking raises the noise, through the R1.1 collision world.
	var terrain := Terrain.flat(400.0, 400.0)
	var wall := Obstacle.place(Obstacle.BOX, 40.0, 0.0, {"w": 4.0, "h": 10.0, "d": 20.0, "yaw_deg": 0.0}, terrain)
	var obstacles: Array[Obstacle] = [wall]
	var world := CollisionWorld.new(terrain, obstacles, [])
	var pilot := Vector3(0.0, 1.6, 0.0)
	var behind := Vector3(80.0, 2.0, 0.0)
	var beside := Vector3(0.0, 2.0, 80.0)
	var b_behind := world.blockers_between(pilot, behind)
	var b_beside := world.blockers_between(pilot, beside)
	var b_ground := world.blockers_between(pilot, Vector3(0.0, -3.0, 60.0))
	analog.evaluate(pilot.distance_to(beside), b_beside)
	var clear_n := analog.noise()
	analog.evaluate(pilot.distance_to(behind), b_behind)
	var blocked_n := analog.noise()
	r.append(TestResult.new("r2.4: a wall between pilot and drone blocks line of sight and raises the analog noise",
		b_behind == 1 and b_beside == 0 and b_ground == 1 and blocked_n > clear_n + 0.2,
		"blockers %d/%d/%d, noise clear %.3f blocked %.3f" % [b_beside, b_behind, b_ground, clear_n, blocked_n]))

	# 3. Digital latency equals the configured frame delay.
	for hz: float in [60.0, 120.0]:
		var dl := VideoLink.new(cams.get("cam_dji_o4_pro", {}))
		dl.evaluate(10.0, 0)
		var frames := dl.delay_frames(hz)
		var ok := true
		var seen := -1
		for k in 40:
			var shown := dl.shown_pose(k / hz, Transform3D(Basis(), Vector3(k, 0, 0)))
			seen = int(shown.origin.x)
			if k >= frames and seen != k - frames:
				ok = false
		r.append(TestResult.new("r2.4: at %.0f Hz the digital feed shows the frame %d back (%.0f ms configured)" % [hz, frames, dl.latency_s() * 1000.0],
			ok and frames >= 2 and is_equal_approx(dl.latency_s(), float(cams["cam_dji_o4_pro"]["video"]["latency_ms"]) / 1000.0)
			and frames == ceili(dl.latency_s() * hz - 1e-9), "last shown %d of 39" % seen))
	var al := VideoLink.new(cams.get("cam_micro_analog", {}))
	var live := Transform3D(Basis(), Vector3(7, 0, 0))
	r.append(TestResult.new("r2.4: analog shows the live lens (no frame delay)",
		al.shown_pose(0.0, live) == live and al.delay_frames(60.0) == 0, ""))
	# At the edge digital freezes: the shown pose stops following the lens.
	var fz := VideoLink.new(cams.get("cam_dji_o4_pro", {}))
	fz.evaluate(10.0, 0)
	fz.shown_pose(0.0, Transform3D(Basis(), Vector3(1, 0, 0)))
	fz.evaluate(5000.0, 0)
	var held := fz.shown_pose(1.0, Transform3D(Basis(), Vector3(2, 0, 0)))
	r.append(TestResult.new("r2.4: a digital link at the edge freezes the picture instead of showing static",
		fz.is_frozen() and held.origin.x == 1.0 and fz.noise() == 0.0, "held %s" % held.origin))

	# 4. The analog/digital choice follows the part, through the FPV view the sim draws.
	var view := FpvView.new()
	var follows := true
	var detail := ""
	for id in cams:
		var part: Dictionary = cams[id]
		var sig := str(part.get("catalog", {}).get("signal", ""))
		view.set_camera_part(part)
		var want := sig if sig in ["analog", "digital"] else "none"
		var vsys: int = view.link.shader_params(0.0, 0)["vsys"]
		if view.link.system != want or vsys != {"analog": 1, "digital": 2}.get(want, 0):
			follows = false
			detail += "%s:%s/%d " % [id, view.link.system, vsys]
	# A custom part with no `video` block falls back on what its catalog says.
	for sig in ["analog", "digital"]:
		view.set_camera_part({"name": "custom", "catalog": {"signal": sig}})
		if view.link.system != sig:
			follows = false
			detail += "custom %s -> %s " % [sig, view.link.system]
	view.free()
	r.append(TestResult.new("r2.4: every camera part's video system picks the feed's post-process (analog 1, digital 2, none 0)",
		follows and cams.size() >= 5, detail))
	return r


static func _cameras() -> Dictionary:
	var out := {}
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts/cameras.json"))
	for c in d["parts"]:
		out[str(c["part_id"])] = c
	return out
