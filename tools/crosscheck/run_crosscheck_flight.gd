extends SceneTree
## Golden cross-check for NATIVE CORE 2, TIER 1 (sim + fc): the Rust `FlightLaw` kernels, as
## called through the rewired GDScript classes, against the GDScript originals they replaced.
## Run it:
##   godot --headless --path . --script res://tools/crosscheck/run_crosscheck_flight.gd
##
## The ref_*.gd beside this file ARE the oracle and must never be edited to match the Rust. They
## are byte-verbatim copies of src/fc/{pid_controller,angle_mode_controller,rate_tune}.gd and
## src/sim/{motor_mixer,vibration_model,gyro,wind}.gd at b70140b (the commit before the port),
## with only the leading `class_name` line removed.
##
## EXACT equality, not a tolerance. Every port in this tier repeats the original's f64/f32
## boundaries and operation order, so a faithful port is bit-identical, and anything looser would
## let a closed-loop sim drift away from its oracles a ulp at a time. NaN == NaN and the same
## infinity count as agreement.
##
## Lives under tools/ because tools/* is export-excluded; build_macos.sh gates on the sentinel.

const RPid = preload("res://tools/crosscheck/ref_pid_controller.gd")
const RMix = preload("res://tools/crosscheck/ref_motor_mixer.gd")
const RAngle = preload("res://tools/crosscheck/ref_angle_mode_controller.gd")
const RVib = preload("res://tools/crosscheck/ref_vibration_model.gd")
const RGyro = preload("res://tools/crosscheck/ref_gyro.gd")
const RWind = preload("res://tools/crosscheck/ref_wind.gd")
const RTune = preload("res://tools/crosscheck/ref_rate_tune.gd")

const SENTINEL := "FLIGHT LAW CROSSCHECK OK"

var stats := {}
var total := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = 0x7A11
	_check_pid()
	_check_mixer()
	_check_angle()
	_check_vibration_statics()
	_check_vibration_and_gyro()
	_check_wind()
	_check_rate_tune()
	_report(Time.get_ticks_msec() - t0)


# ---------------------------------------------------------------------------

func _same(a: float, b: float) -> bool:
	if a == b:
		return true
	return is_nan(a) and is_nan(b)


func _cmp(fn: String, rust_v: Variant, ref_v: Variant, desc: String) -> void:
	total += 1
	if not stats.has(fn):
		stats[fn] = {"n": 0, "fails": 0, "first": ""}
	var s: Dictionary = stats[fn]
	s["n"] = int(s["n"]) + 1
	var ok := true
	if rust_v is Vector3:
		var a: Vector3 = rust_v
		var b: Vector3 = ref_v
		ok = _same(a.x, b.x) and _same(a.y, b.y) and _same(a.z, b.z)
	elif rust_v is bool:
		ok = rust_v == ref_v
	else:
		ok = _same(float(rust_v), float(ref_v))
	if not ok:
		s["fails"] = int(s["fails"]) + 1
		if String(s["first"]) == "":
			s["first"] = "%s  rust=%s ref=%s" % [desc, str(rust_v), str(ref_v)]


func _grid(values: Array) -> Array:
	return values


# ---------------------------------------------------------------------------
# PIDController: single steps over a dense grid, then long random sequences.
# ---------------------------------------------------------------------------

func _check_pid() -> void:
	var gains := [Vector3(2.3, 0.15, 0.042), Vector3(6.0, 0.39, 0.0), Vector3(0.0, 0.0, 0.0),
		Vector3(40.0, 5.0, 0.3), Vector3(-1.0, 0.2, 0.01)]
	var limits := [Vector2(1.0, 1.0), Vector2(0.2, 0.5), Vector2(0.0, 1.0), Vector2(5.0, 0.0)]
	var values := [-2.0, -1.0, -0.3, -1.0e-9, 0.0, 1.0e-9, 0.25, 0.9999, 1.0, 1.7, NAN]
	var dts := [0.001, 1.0 / 120.0, 0.0, -0.01]
	for g in gains:
		for lim in limits:
			for integral in [-1.2, -0.4, 0.0, 0.5, 1.0]:
				for has_last in [false, true]:
					for target in values:
						for measured in values:
							for dt in dts:
								var a := PIDController.new(g.x, g.y, g.z, lim.x, lim.y)
								var b = RPid.new(g.x, g.y, g.z, lim.x, lim.y)
								a._integral = integral
								b._integral = integral
								a._last_measured = 0.3
								b._last_measured = 0.3
								a._has_last = has_last
								b._has_last = has_last
								var d := "g=%s lim=%s i=%s hl=%s t=%s m=%s dt=%s" % [g, lim,
									integral, has_last, target, measured, dt]
								_cmp("pid.update", a.update(target, measured, dt),
									b.update(target, measured, dt), d)
								_cmp("pid._integral", a._integral, b._integral, d)
								_cmp("pid._last_measured", a._last_measured, b._last_measured, d)
	for seq in 200:
		var g: Vector3 = gains[seq % gains.size()]
		var lim: Vector2 = limits[seq % limits.size()]
		var a := PIDController.new(g.x, g.y, g.z, lim.x, lim.y)
		var b = RPid.new(g.x, g.y, g.z, lim.x, lim.y)
		for i in 500:
			var target := rng.randf_range(-1.5, 1.5)
			var measured := rng.randf_range(-1.5, 1.5)
			if i == 250:
				a.reset()
				b.reset()
			_cmp("pid.sequence", a.update(target, measured, 0.001), b.update(target, measured, 0.001),
				"seq=%d i=%d" % [seq, i])


# ---------------------------------------------------------------------------
# MotorMixer
# ---------------------------------------------------------------------------

func _check_mixer() -> void:
	var configs := [{}, {"motor_spin": "props_in"}, {"motor_spin": {"M1": -1, "M3": 1.0}}]
	var cmds := [-1.5, -1.0, -0.6, -0.1, 0.0, 0.05, 0.3, 0.77, 1.0, 1.4]
	var throttles := [-0.2, 0.0, 0.05, 0.29, 0.5, 0.95, 1.0, 1.3]
	for config in configs:
		for th in throttles:
			for r in cmds:
				for p in cmds:
					for y in cmds:
						var a := MotorMixer.mix(th, r, p, y, config)
						var b: Dictionary = RMix.mix(th, r, p, y, config)
						for name in MotorLayout.MOTOR_NAMES:
							_cmp("MotorMixer.mix", a[name], b[name],
								"%s th=%s r=%s p=%s y=%s %s" % [config, th, r, p, y, name])
	# The scale step never fires at MIX_GAIN = 0.2 on in-range commands; drive it directly.
	for i in 20000:
		var th := rng.randf_range(-0.5, 1.5)
		var r := rng.randf_range(-6.0, 6.0)
		var p := rng.randf_range(-6.0, 6.0)
		var y := rng.randf_range(-6.0, 6.0)
		var a := MotorMixer.mix(th, r, p, y)
		var b: Dictionary = RMix.mix(th, r, p, y)
		for name in MotorLayout.MOTOR_NAMES:
			_cmp("MotorMixer.mix(random, incl. scale step)", a[name], b[name],
				"th=%s r=%s p=%s y=%s %s" % [th, r, p, y, name])


# ---------------------------------------------------------------------------
# AngleModeController
# ---------------------------------------------------------------------------

func _check_angle() -> void:
	for i in 60000:
		var q := Quaternion(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1),
			rng.randf_range(-1, 1)).normalized()
		if i % 7 == 0:
			q = Quaternion.from_euler(Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6)))
		var rc := {"roll": rng.randf_range(-1.2, 1.2), "pitch": rng.randf_range(-1.2, 1.2),
			"yaw": rng.randf_range(-1.2, 1.2), "throttle": 0.3}
		if i % 11 == 0:
			rc = {"roll": 0, "pitch": 1, "yaw": -1, "throttle": 0}   # int sticks
		_cmp("AngleModeController.rate_setpoint", AngleModeController.rate_setpoint(q, rc),
			RAngle.rate_setpoint(q, rc), "q=%s rc=%s" % [q, rc])


# ---------------------------------------------------------------------------
# VibrationModel statics
# ---------------------------------------------------------------------------

func _check_vibration_statics() -> void:
	var arms := [-0.1, 0.0, 0.02, 0.0325, 0.08, 0.110, 0.135, 0.2, 0.3]
	var tips := [-0.001, 0.0, 0.002, 0.012, 0.0365, 0.06, 0.12]
	for arm in arms:
		for tip in tips:
			_cmp("VibrationModel.resonance_hz_for", VibrationModel.resonance_hz_for(arm, tip),
				RVib.resonance_hz_for(arm, tip), "arm=%s tip=%s" % [arm, tip])
	for i in 50000:
		var hz := rng.randf_range(0.0, 3000.0)
		var res := rng.randf_range(-10.0, 900.0)
		var zeta := rng.randf_range(0.0, 0.5)
		if i % 13 == 0:
			hz = res   # exactly on resonance
		_cmp("VibrationModel.modal_gain", VibrationModel.modal_gain(hz, res, zeta),
			RVib.modal_gain(hz, res, zeta), "hz=%s res=%s zeta=%s" % [hz, res, zeta])
	# Transmissibility through real mounts: every soft-mount thickness x tip load x spec.
	var specs := [{}, {"shore_a": 40}, {"shore_a": 70, "damping_ratio": 0.2}]
	for mount_m in [0.0, 0.0005, 0.001, 0.002, 0.004]:
		for tip in [0.01, 0.0365, 0.08]:
			for spec in specs:
				var a := VibrationModel.new()
				var b = RVib.new()
				for m in [a, b]:
					m.soft_mount_m = mount_m
					m.tip_load_kg = tip
					m.soft_mount_spec = spec
				for hz in [0.0, 1.0, 50.0, 120.0, 180.0, 300.0, 700.0, 2500.0]:
					for zeta in [NAN, 0.0, 0.05, 0.3]:
						_cmp("VibrationModel.mount_transmissibility", a.mount_transmissibility(hz, zeta),
							b.mount_transmissibility(hz, zeta),
							"mount=%s tip=%s spec=%s hz=%s zeta=%s" % [mount_m, tip, spec, hz, zeta])


# ---------------------------------------------------------------------------
# VibrationModel.angular_rate_at and Gyro, run together as the aircraft runs them: a gyro with
# the vibration attached, stepped by uneven dts, over every frame in the catalog.
# ---------------------------------------------------------------------------

func _pair_for(build: Build, mount_m: float, spec: Dictionary) -> Array:
	var a := VibrationModel.for_build(build)
	var b = RVib.new(build.arm_m)
	a.soft_mount_m = mount_m
	a.soft_mount_spec = spec
	for f in ["blades", "prop_radius_m", "tip_load_kg", "resonance_hz", "imbalance_kg",
			"blade_pass_kg", "damping_ratio", "soft_mount_m", "soft_mount_spec"]:
		b.set(f, a.get(f))
	return [a, b]


func _check_vibration_and_gyro() -> void:
	var builds := _frame_builds(false)
	var fcs := PartsCatalog.load_default().list_category("flight_controller")
	var spec_cycle := [{}, {"shore_a": 50}]
	var mounts := [0.0, 0.0015]
	for bi in builds.size():
		var build: Build = builds[bi]
		for mi in mounts.size():
			var pair := _pair_for(build, mounts[mi], spec_cycle[mi])
			var va: VibrationModel = pair[0]
			var vb = pair[1]
			# Straight angular_rate_at over a changing rpm set, including stopped motors.
			var t := 0.0
			for i in 3000:
				if i % 500 == 0:
					var rpms := PackedFloat64Array()
					for k in 4:
						rpms.append(0.0 if (floori(float(i) / 500.0) + k) % 5 == 0 else rng.randf_range(2000.0, 40000.0))
					va.set_rpm(rpms)
					vb.set_rpm(rpms)
				t += rng.randf_range(0.0002, 0.004)
				_cmp("VibrationModel.angular_rate_at", va.angular_rate_at(t), vb.angular_rate_at(t),
					"%s mount=%s i=%d" % [build.frame.get("part_id"), mounts[mi], i])
			va.reset()
			vb.reset()
			# Gyro with that vibration attached, from the catalog FC's own specs.
			var fc: Dictionary = fcs[bi % fcs.size()]
			var ga := Gyro.from_part(fc)
			var gb = RGyro.new(ga.sample_rate_hz, ga.cutoff_hz, ga.noise_rad_s, ga.bias_rad_s)
			ga.vibration = va
			gb.vibration = vb
			for i in 4000:
				var w := Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9))
				var dt := 0.001 if i % 3 else rng.randf_range(0.0001, 0.01)
				if i == 2000:
					ga.reset()
					gb.reset()
				_cmp("Gyro.update(+vibration)", ga.update(w, dt), gb.update(w, dt),
					"%s fc=%s i=%d" % [build.frame.get("part_id"), fc.get("part_id"), i])
			_cmp("Gyro.sample_step_noise_rad_s", ga.sample_step_noise_rad_s(),
				gb.sample_step_noise_rad_s(), str(fc.get("part_id")))
	for sr in [100.0, 1000.0, 3200.0, 8000.0]:
		for cut in [20.0, 90.0, 150.0, 500.0, 4000.0]:
			for noise in [0.0, 0.0028, 0.03]:
				var ga := Gyro.new(sr, cut, noise)
				var gb = RGyro.new(sr, cut, noise)
				_cmp("Gyro.sample_step_noise_rad_s(grid)", ga.sample_step_noise_rad_s(),
					gb.sample_step_noise_rad_s(), "sr=%s cut=%s n=%s" % [sr, cut, noise])
				for i in 300:
					var w := Vector3(rng.randf_range(-5, 5), 0.0, rng.randf_range(-5, 5))
					_cmp("Gyro.update(grid)", ga.update(w, 0.001), gb.update(w, 0.001),
						"sr=%s cut=%s i=%d" % [sr, cut, i])


# ---------------------------------------------------------------------------
# Wind
# ---------------------------------------------------------------------------

func _check_wind() -> void:
	for speed in [0.0, 0.5, 3.0, 8.0, 17.5]:
		for from in [-90.0, 0.0, 45.0, 90.0, 180.0, 271.3, 359.9, 720.0]:
			_cmp("Wind.steady_vector", Wind.steady_vector(speed, from), RWind.steady_vector(speed, from),
				"speed=%s from=%s" % [speed, from])
	for gust in [0.0, 0.4, 2.5]:
		for tau in [0.2, Wind.DEFAULT_GUST_TAU_S, 3.0]:
			var c := Conditions.standard()
			c.wind_speed_mps = 4.0
			c.wind_from_deg = 30.0
			c.gustiness_mps = gust
			var a := Wind.new(c, tau)
			var b = RWind.new(c, tau)
			_cmp("Wind.steady_mps", a.steady_mps, b.steady_mps, "")
			for i in 3000:
				var dt := 1.0 / 120.0 if i % 4 else rng.randf_range(0.0005, 0.05)
				if i == 1500:
					a.reset()
					b.reset()
				_cmp("Wind.update", a.update(dt), b.update(dt), "gust=%s tau=%s i=%d" % [gust, tau, i])


# ---------------------------------------------------------------------------
# RateTune: every frame x every flight controller, through the real FrameBench.
# ---------------------------------------------------------------------------

func _check_rate_tune() -> void:
	for noise in [0.0, 0.001, 0.0028, 0.02]:
		for sr in [-1.0, 0.0, 500.0, 1000.0, 8000.0]:
			for kd in [0.0, 0.01, 0.042, 1.0]:
				_cmp("RateTune.noise_fraction_for", RateTune.noise_fraction_for(noise, sr, kd),
					RTune.noise_fraction_for(noise, sr, kd), "n=%s sr=%s kd=%s" % [noise, sr, kd])
	for build in _frame_builds(true):
		var d := "%s/%s" % [build.frame.get("part_id"), build.fc.get("part_id")]
		_cmp("RateTune.kd_ceiling_for", RateTune.kd_ceiling_for(build), RTune.kd_ceiling_for(build), d)
		for kd in [0.0, 0.042, 0.3]:
			_cmp("RateTune.d_noise_fraction", RateTune.d_noise_fraction(build, kd),
				RTune.d_noise_fraction(build, kd), d)
		var a := RateTune.derive(build)
		var b: RateTune = RTune.derive(build)
		for f in ["scale", "plant_alpha", "derived_kp", "derived_ki", "derived_kd", "kp", "ki", "kd"]:
			_cmp("RateTune.derive." + f, a.get(f), b.get(f), d)
		_cmp("RateTune.derive.kd_ceiling", a.kd_ceiling, b.kd_ceiling, d)
		_cmp("RateTune.derive.d_limited", a.d_limited, b.d_limited, d)
		# RTune.derive() builds a NEW-class RateTune (its `RateTune.new()` is verbatim), so its
		# methods are the port's. Instance methods are compared on a genuine ref instance holding
		# the same state — comparing b.time_constant_s() would compare the port with itself.
		var r = RTune.new()
		r.plant_alpha = a.plant_alpha
		r.kp = a.kp
		_cmp("RateTune.time_constant_s", a.time_constant_s(), r.time_constant_s(), d)
		# Through an override, including a zero-gain axis (the INF branch).
		a.set_gains(1, Vector3(0.0, 0.1, 0.01))
		r.kp = a.kp
		_cmp("RateTune.time_constant_s(override)", a.time_constant_s(), r.time_constant_s(), d)


func _frame_builds(every_fc: bool) -> Array:
	var catalog := PartsCatalog.load_default()
	var fcs: Array = [ReferenceBuild.FC_ID]
	if every_fc:
		fcs = []
		for fc in catalog.list_category("flight_controller"):
			fcs.append(fc["part_id"])
	var out: Array = []
	for frame in catalog.list_category("frame"):
		for fc_id in fcs:
			out.append(Build.from_ids(catalog, frame["part_id"], ReferenceBuild.MOTOR_ID,
				ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
				fc_id, Build.no_components()))
	return out


# ---------------------------------------------------------------------------

func _report(ms: int) -> void:
	var fails := 0
	var names := stats.keys()
	names.sort()
	for fn in names:
		var s: Dictionary = stats[fn]
		fails += int(s["fails"])
		var line := "  %-48s n=%-8d fails=%d" % [fn, int(s["n"]), int(s["fails"])]
		if int(s["fails"]) > 0:
			line += "   first: " + String(s["first"])
		print(line)
	print("%d comparisons across %d functions in %d ms, %d divergent" % [total, names.size(), ms, fails])
	if total < 900000:
		print("TOO FEW COMPARISONS — the sweep did not run")
		quit(1)
		return
	if fails == 0:
		print(SENTINEL)
		quit(0)
	else:
		print("FLIGHT LAW CROSSCHECK FAILED")
		quit(1)
