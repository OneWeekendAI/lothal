class_name TestB4LiveWeather
extends RefCounted
## B4/E2 (REALISM_REVIEW.md): a weather edit applies LIVE. The wind and the air density are rebuilt, the aircraft keeps its
## pose, motion and pack, and the new wind crossfades in, so the edit is no step impulse. A world switch still respawns.
##
## The edit is a steady 8 m/s (no gusts, no meander), so any frame-to-frame step is the apply's own, not turbulence.
## FORCE_STEP_LIMIT: the largest frame-to-frame change in the body's true specific force (m/s^2, one 120 Hz frame) that an
## apply may cause. Measured: 0.002 for the same flight with no apply, 0.039 through the blend; an un-blended air density
## (thrust and hover throttle stepping at once) gave 0.89, and an instant 0 -> 8 m/s wind more. 0.2 sits between them.
## WIND_STEP_LIMIT: the same for the wind the core feels (m/s per frame); the 1.5 s smoothstep of 8 m/s peaks at 0.07.

const SCRATCH_COND := "user://b4_conditions.json"
const SCRATCH_SITES := "user://b4_sites.json"
const FORCE_STEP_LIMIT := 0.2
const WIND_STEP_LIMIT := 0.5
const DT := 1.0 / 120.0


static func _booted() -> Node:
	for path in [SCRATCH_COND, SCRATCH_SITES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	m.conditions_path = SCRATCH_COND
	m.sites_path = SCRATCH_SITES
	m.conditions_library = ConditionsLibrary.with_default()
	m.notification(Node.NOTIFICATION_READY)
	return m


static func run() -> Array:
	var r: Array = []
	var m := _booted()
	# Fly a little first so there is real state to keep: a lean and some speed.
	for i in 60:
		m._physics_process(DT)
	m.core.rigid_body.velocity_mps += Vector3(2.0, 0.0, 1.0)
	for i in 30:
		m._physics_process(DT)
	var ctrl_prev: Vector3 = m.core.observables.accel_body_mps2
	var ctrl_worst := 0.0
	for i in 90:   # the control: the same flight's own frame-to-frame steps, no apply
		m._physics_process(DT)
		ctrl_worst = maxf(ctrl_worst, (m.core.observables.accel_body_mps2 - ctrl_prev).length())
		ctrl_prev = m.core.observables.accel_body_mps2
	for i in 0:
		m._physics_process(DT)
	var old_core: DroneCore = m.core
	var old_wind: Wind = m.wind
	var rho0: float = m.core.powertrain.air_density_kgm3
	var p0: Vector3 = old_core.rigid_body.position_m
	var v0: Vector3 = old_core.rigid_body.velocity_mps
	var q0: Quaternion = old_core.rigid_body.orientation
	var w0: Vector3 = old_core.rigid_body.angular_velocity_rad_s
	var used0: float = old_core.powertrain.battery.used_mah
	var rpm0: PackedFloat64Array = old_core.powertrain.motor_rpm.duplicate()
	var f_prev: Vector3 = old_core.observables.accel_body_mps2
	var wind_prev: Vector3 = old_wind.velocity_mps()

	m.toggle_conditions_panel()   # open, as a pilot does (K); flight pauses
	# Mutation: `_apply_weather(..., live)` taking the respawn branch -> position resets to the start; dropping
	# `_carry_flight_state` -> pose and pack reset; dropping `wind = make_wind(c)` -> the wind check fails.
	m.apply_conditions_edit({"wind_speed_mps": 8.0, "wind_from_deg": 90.0, "temperature_c": 35.0, "elevation_m": 1500.0,
		"gustiness_mps": 0.0, "dir_sigma_deg": 0.0, "speed_sigma_frac": 0.0})
	var c: DroneCore = m.core
	r.append(TestResult.new("b4 e2: live apply rebuilds the Wind (8 m/s from 90) and the core flies it",
		m.wind != old_wind and absf(m.wind.speed_mps - 8.0) < 1e-9 and absf(m.wind.from_deg - 90.0) < 1e-9 and c.wind == m.wind,
		"wind %.1f from %.0f, new object %s" % [m.wind.speed_mps, m.wind.from_deg, m.wind != old_wind]))
	r.append(TestResult.new("b4 e2: live apply keeps position, velocity, attitude and body rates exactly",
		c.rigid_body.position_m == p0 and c.rigid_body.velocity_mps == v0 and c.rigid_body.orientation == q0
		and c.rigid_body.angular_velocity_rad_s == w0 and v0.length() > 0.3,
		"p %s -> %s, |v| %.2f -> %.2f" % [p0, c.rigid_body.position_m, v0.length(), c.rigid_body.velocity_mps.length()]))
	r.append(TestResult.new("b4 e2: live apply keeps the pack and the rotor speeds",
		absf(c.powertrain.battery.used_mah - used0) < 1e-12 and used0 > 0.0 and c.powertrain.motor_rpm == rpm0,
		"used %.4f -> %.4f mAh, rpm0 %.0f -> %.0f" % [used0, c.powertrain.battery.used_mah, rpm0[0], c.powertrain.motor_rpm[0]]))
	var status: String = m.conditions_panel.status_label.text if m.conditions_panel != null else ""
	r.append(TestResult.new("b4 e2: the apply is labelled live with its blend time",
		m.wind.crossfade_fraction() == 0.0 and status.contains("live") and status.contains("1.5 s"), status))

	# Mutation: drop `wind.crossfade_from(old_wind)` -> the first frame meets an 8 m/s wall: both steps blow their limits.
	m.toggle_conditions_panel()   # close; flight resumes
	var worst_f := 0.0
	var worst_w := 0.0
	for i in 240:
		m._physics_process(DT)
		var f: Vector3 = m.core.observables.accel_body_mps2
		var wv: Vector3 = m.wind.velocity_mps()
		worst_f = maxf(worst_f, (f - f_prev).length())
		worst_w = maxf(worst_w, (wv - wind_prev).length())
		f_prev = f
		wind_prev = wv
	r.append(TestResult.new("b4 e2: live apply rebuilds the air density (35 C at 1500 m is thinner); the core reaches it after the blend",
		m.build.air.kgm3() < rho0 - 0.1 and absf(m.build.air.kgm3() - m.core.powertrain.air_density_kgm3) < 1e-9
		and absf(m.build.air.kgm3() - m.core.air_density_kgm3) < 1e-9 and m._air_blend.is_empty(),
		"rho %.4f -> build %.4f, core %.4f" % [rho0, m.build.air.kgm3(), m.core.powertrain.air_density_kgm3]))
	r.append(TestResult.new("b4 e2: no force step on apply (specific force <= %.1f m/s^2, wind <= %.1f m/s per frame)" % [FORCE_STEP_LIMIT, WIND_STEP_LIMIT],
		worst_f <= FORCE_STEP_LIMIT and worst_w <= WIND_STEP_LIMIT and m.wind.crossfade_fraction() == -1.0
		and m.wind.velocity_mps().length() > 4.0,
		"control %.3f; worst force step %.3f m/s^2, wind step %.3f m/s, wind now %.1f m/s" % [ctrl_worst, worst_f, worst_w, m.wind.velocity_mps().length()]))

	# A world changes the ground under the aircraft: that one still respawns at the start, and says so.
	var worlds := WorldLibrary.load_dir("user://b4_worlds")
	worlds.ensure_presets()
	m.worlds_dir = "user://b4_worlds"
	m.apply_world("windy_coast")
	var start: Vector3 = m.course.start_position(m.terrain)
	var status2: String = m.conditions_panel.status_label.text if m.conditions_panel != null else ""
	r.append(TestResult.new("b4 e2: a world switch respawns at the start and the status says so",
		m.core.rigid_body.position_m.distance_to(start) < 1e-6 and status2.contains("respawned"),
		"%s vs start %s; '%s'" % [m.core.rigid_body.position_m, start, status2]))
	m.free()

	# --- Q1 render: the grass pick bands are culled only where the shader had already collapsed every tuft in them -----
	# Mutation: drop the half diagonal from FieldLook.band_range_m -> a tuft at the chunk's near corner is still kept.
	var worst_keep_over := -INF
	for b in range(1, FieldLook.PICK_BANDS):
		var lo := float(b) / FieldLook.PICK_BANDS
		var nearest := FieldLook.band_range_m(lo) - FieldLook.CHUNK_M * sqrt(2.0) * 0.5
		var keep := 1.0 - smoothstep(FieldLook.FADE_START_M, FieldLook.FADE_END_M, nearest)
		worst_keep_over = maxf(worst_keep_over, keep - lo)
	r.append(TestResult.new("b4 q1: a grass band is culled only past where its every tuft is already faded out",
		FieldLook.PICK_BANDS > 1 and worst_keep_over <= 0.0, "worst keep - pick_lo %.4f over %d bands" % [worst_keep_over, FieldLook.PICK_BANDS]))
	# The picks themselves live in MultiMesh custom data, which the headless dummy renderer does not store, so the pick ->
	# band mapping is read off FieldLook.tuft_pick and the picture is checked windowed (tests/probe_fps_variants.gd +
	# capture_field_look.gd, before/after PNGs). Mutation: banding off (PICK_BANDS 1) -> the first check above fails.
	var fl := FieldLook.new()
	fl.rebuild(Terrain.new())
	var tufts := 0
	var misplaced := 0
	var counts := {}
	for i in fl.tuft_count:
		var band := mini(int(FieldLook.tuft_pick(i) * FieldLook.PICK_BANDS), FieldLook.PICK_BANDS - 1)
		counts[band] = int(counts.get(band, 0)) + 1
	for child in fl.get_children():
		var name := String(child.name)
		if name.begins_with("Grass_"):
			tufts += child.multimesh.instance_count
			var band := int(name.get_slice("_b", 1))
			counts[band] = int(counts.get(band, 0)) - child.multimesh.instance_count
	for k in counts:
		if counts[k] != 0:
			misplaced += absi(counts[k])
	r.append(TestResult.new("b4 q1: every tuft is drawn once, in the band its pick names",
		tufts == fl.tuft_count and tufts > 1000 and misplaced == 0, "%d tufts of %d, %d misplaced" % [tufts, fl.tuft_count, misplaced]))
	fl.free()
	for path in [SCRATCH_COND, SCRATCH_SITES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	return r
