class_name TestR17Realism
extends RefCounted
## R1.7: a hands-off hover stays put in calm air; the default weather is calm; the weather and the world are editable from the
## flight and reach the live wind and air; the choice persists; the wind meanders in direction and speed (seeded OU); and the
## aircraft cannot leave the world. One TestResult per case. The mutation each was proven against is stated in its comment.

const MAIN := preload("res://src/scenes/main.gd")
const SCRATCH_COND := "user://r17_conditions.json"
const SCRATCH_SITES := "user://r17_sites.json"
## B1: 30 s hands-off angle-mode hover in calm air, per seed. The bound is DERIVED (calm_drift_bound_m), not measured:
## angle mode levels to the attitude the estimator BELIEVES is level, so what is left of the power-up calibration is a
## standing tilt error eps, which accelerates the craft at g*eps against the rotor drag mu; it reaches v = g*eps/mu.
##  - Residue: Betaflight averages still samples at power-up (gyro_calibration_duration 1.25 s; accel calibration on the
##    bench). A LABELLED ESTIMATE of its accuracy is the sensor's own white noise over the sample count, sigma/sqrt(N),
##    per axis (Gyro/Accelerometer.CALIBRATION_SAMPLES). The tilt it leaves: a gyro rate residue b is balanced by the
##    estimator's accel correction at b/kp (AttitudeEstimator.DEFAULT_KP); an accel residue a reads as a tilt a/g.
##  - Two horizontal axes, independent: a 95th-percentile magnitude is 2.45 sigma (Rayleigh).
##  - Distance: the tilt builds with the estimator's 1/kp and the speed with 1/mu, so over T the craft covers about
##    v (T - 1/kp - 1/mu).
##  - Plus the start transient: Betaflight starts the I terms at zero on arm, so the rate loops settle the hover trim from
##    zero. MEASURED sensor-free (tools/dbg_drift.gd opts=high,nogb,noab,nonoise): CALM_DRIFT_TRANSIENT_M.
## Bound = DRIFT_MARGIN x (transient + residue drift); margin 1.5. Mu is the BET + flapping hover value from Build.
const CALM_DRIFT_TRANSIENT_M := 0.66
const DRIFT_MARGIN := 1.5
const DRIFT_SECONDS := 30.0
const DRIFT_SEEDS := [0, 1, 2]
## Lifted for the 30 s drift hover so a horizontal number is never an aircraft sliding on grass: hands-off at a fixed throttle
## the pack drains and the windings warm (thrust falls ~1.9 percent in 30 s), and a calm hover sinks ~4.4 m in 30 s. That is
## physics with no altitude hold, so the drift case starts high enough to stay airborne and asserts it did.
const DRIFT_LIFT_M := 10.0
## B1 (review P2): hands-off for 10 s from the real spawn. MEASURED 0.6 m, of which ~0.5 m is the pack drain and winding heat
## at fixed throttle (thrust falls 0.07 percent/s against a descent damping of ~0.36 N per m/s). Build's static hover solve,
## which predates the R1.4 ESC model, sinks 1.4 m.
const SPAWN_SINK_BOUND_M := 1.0
## B1: hovering, the body-x accelerometer reads -mu * v (Martin & Salauen 2010). Mu is DERIVED, not pinned: Build's own
## rotor H-force (BET profile + induced + flapping) plus the body's side drag at that speed, over the mass, and the
## sensor must read it within MU_TOLERANCE (the core flies the dynamic hover throttle, Build the level-trim thrust).
const MU_TOLERANCE := 0.06
## B1 power bucket: leans flown (hover, cruise, fast), settle and averaging times, the mu band the cruise point must lie
## in, and the minimum dip below hover. The dip bound 5 percent is half the momentum-theory saving for this disc
## loading less the profile rise, and well clear of the 1.7 percent the shaft-frame (double-counted) model gave.
const BUCKET_LEANS_DEG := [0.0, 20.0, 40.0]
const BUCKET_SETTLE_S := 22.0
const BUCKET_AVERAGE_S := 3.0
const BUCKET_MU_BAND := Vector2(0.10, 0.25)
const BUCKET_MIN_DIP := 0.05
## B1 terminal-speed flight: the sim must settle within the 2 percent the drag calibration is quoted to (Build.top_speed_kmh
## and the flown balance use the same H-force law; the residue is the rear-rotor wake loss and the pack sag in the sim).
const TOP_SPEED_TOLERANCE := 0.02
const TOP_SPEED_FLIGHT_S := 25.0


static func _clean() -> void:
	for path in [SCRATCH_COND, SCRATCH_SITES, "user://r17_stale.json", "user://r17_stale.json.v1.bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _booted() -> Node:
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	m.conditions_path = SCRATCH_COND
	m.sites_path = SCRATCH_SITES
	m.conditions_library = ConditionsLibrary.with_default()
	m.notification(Node.NOTIFICATION_READY)
	return m


static func _hover(m: Node, seconds: float) -> Dictionary:
	var p0: Vector3 = m.core.rigid_body.position_m
	var floor_y: float = m.core.ground_y_m + m.core.rest_height_m
	var min_clear := INF
	var bearings: Array = []
	var dt := 1.0 / 120.0
	for i in int(seconds / dt):
		m._physics_process(dt)
		min_clear = minf(min_clear, m.core.rigid_body.position_m.y - floor_y)
		if i % 120 == 0 and m.wind.velocity_mps().length() > 0.5:
			var v: Vector3 = m.wind.velocity_mps()
			bearings.append(rad_to_deg(atan2(v.x, v.z)))
	var d: Vector3 = m.core.rigid_body.position_m - p0
	return {"horizontal_m": Vector2(d.x, d.z).length(), "vertical_m": d.y, "min_clearance_m": min_clear, "bearings": bearings}


## The sensors re-seeded (a different noise stream and calibration residue per seed), then recalibrated as at power-up.
static func _reseed(m: Node, seed_n: int) -> void:
	m.core.gyro._seed = 0x9100 + seed_n
	m.core.accel._seed = 0xACC00 + seed_n
	m.core.gyro.reset()
	m.core.accel.reset()
	m.core.gyro.calibrate()
	m.core.accel.calibrate()


## The true body specific force of a level, hover-trimmed in-flight core moving at `v_world` through `wind_conditions` air.
static func _specific_force_at(v_world: Vector3, wind_conditions: Conditions) -> Dictionary:
	var b := ReferenceBuild.build()
	var core: DroneCore = b.build_drone_core(MAIN.FREE_FLIGHT_PHYSICS)
	var thr: float = MAIN.dynamic_hover_throttle(b, b.hover_throttle())
	core.prime_motors(thr)
	core.rigid_body.position_m = Vector3(0.0, 20.0, 0.0)
	if wind_conditions != null:
		core.wind = Wind.new(wind_conditions, wind_conditions.gust_tau_s, Wind.DEFAULT_SEED, Wind.Model.DRYDEN, false)
	core.rigid_body.velocity_mps = v_world
	core.step({"M1": thr, "M2": thr, "M3": thr, "M4": thr}, 0.001)
	var air: Vector3 = v_world - (core.wind.velocity_mps() if core.wind != null else Vector3.ZERO)
	return {"sf": core.observables.accel_body_mps2, "air": air}


## Expected linear drag (1/s) a level hover sees at `speed` sideways: (rotor H + body side drag) / (m v).
static func _expected_mu(speed: float) -> float:
	var b := ReferenceBuild.build()
	var w := b.weight_n()
	var body := b.drag_axes.x * speed * speed
	return (b.rotor_h_force_n(speed, 0.0, w) + body) / (b.mass_properties.total_mass_kg * speed)


## The calm-drift bound, derived as described at CALM_DRIFT_TRANSIENT_M.
static func calm_drift_bound_m() -> Dictionary:
	var mu := _expected_mu(0.5)
	var g := AttitudeEstimator.GRAVITY_MPS2
	var gyro_res := Gyro.DEFAULT_NOISE_RAD_S / sqrt(float(Gyro.CALIBRATION_SAMPLES))
	var accel_res := Accelerometer.DEFAULT_NOISE_MPS2 / sqrt(float(Accelerometer.CALIBRATION_SAMPLES))
	var kp := AttitudeEstimator.DEFAULT_KP
	var tilt_sigma := sqrt(pow(gyro_res / kp, 2.0) + pow(accel_res / g, 2.0))
	var v := g * 2.45 * tilt_sigma / mu
	var residue_m := v * maxf(DRIFT_SECONDS - 1.0 / kp - 1.0 / mu, 0.0)
	return {"bound_m": DRIFT_MARGIN * (CALM_DRIFT_TRANSIENT_M + residue_m), "mu": mu, "residue_m": residue_m}


## The reference core flown level at a held `lean_deg`, nose down, with an altitude-hold throttle, to terminal speed (km/h).
## Attitude and body rates are pinned each tick: this measures the drag balance, not the attitude loop.
static func fly_terminal_kmh(lean_deg: float) -> float:
	var b := ReferenceBuild.build()
	var core: DroneCore = b.build_drone_core(MAIN.FREE_FLIGHT_PHYSICS)
	var thr: float = b.hover_throttle()
	core.prime_motors(thr)
	core.rigid_body.position_m = Vector3(0.0, 200.0, 0.0)
	var att := Basis(Vector3.RIGHT, -deg_to_rad(lean_deg))
	var dt := 1.0 / 500.0
	var speed := 0.0
	for i in int(TOP_SPEED_FLIGHT_S / dt):
		core.rigid_body.orientation = att
		core.rigid_body.angular_velocity_rad_s = Vector3.ZERO
		thr = clampf(thr - 0.5 * core.rigid_body.velocity_mps.y * dt - 0.02 * (core.rigid_body.position_m.y - 200.0) * dt, 0.0, 1.0)
		core.step({"M1": thr, "M2": thr, "M3": thr, "M4": thr}, dt)
		var v: Vector3 = core.rigid_body.velocity_mps
		speed = Vector2(v.x, v.z).length()
	return speed * 3.6


## B1 power bucket: the reference core flown level at a held `lean_deg` with an altitude-hold throttle (PI on climb rate
## and height, settled for BUCKET_SETTLE_S), returning the mean pack current over the last BUCKET_AVERAGE_S, the speed
## and the advance ratio mu = V / (Omega R). `tpp` false ablates the tip-path-plane power flow (DroneCore.flap_tpp_enabled).
static func fly_level_power(lean_deg: float, tpp: bool = true) -> Dictionary:
	var b := ReferenceBuild.build()
	var core: DroneCore = b.build_drone_core(MAIN.FREE_FLIGHT_PHYSICS)
	core.flap_tpp_enabled = tpp
	var thr: float = b.hover_throttle()
	var ti := thr
	core.prime_motors(thr)
	core.rigid_body.position_m = Vector3(0.0, 200.0, 0.0)
	var att := Basis(Vector3.RIGHT, -deg_to_rad(lean_deg))
	var dt := 1.0 / 500.0
	var cur := 0.0
	var n := 0
	for i in int((BUCKET_SETTLE_S + BUCKET_AVERAGE_S) / dt):
		core.rigid_body.orientation = att
		core.rigid_body.angular_velocity_rad_s = Vector3.ZERO
		var ey: float = core.rigid_body.position_m.y - 200.0
		var vy: float = core.rigid_body.velocity_mps.y
		ti -= 0.05 * (vy + 0.3 * ey) * dt
		thr = clampf(ti - 0.06 * vy - 0.02 * ey, 0.0, 1.0)
		core.step({"M1": thr, "M2": thr, "M3": thr, "M4": thr}, dt)
		if float(i) * dt >= BUCKET_SETTLE_S:
			cur += float(core.observables.current_total_a)
			n += 1
	var v: Vector3 = core.rigid_body.velocity_mps
	var speed := Vector2(v.x, v.z).length()
	var rpm := 0.0
	for r in core.powertrain.motor_rpm:
		rpm += float(r) / 4.0
	return {"a": cur / maxf(float(n), 1.0), "v": speed, "mu": speed / maxf(rpm * TAU / 60.0 * core.prop_radius_m, 1.0)}


static func _spread(a: Array) -> float:
	if a.is_empty():
		return 0.0
	return float(a.max()) - float(a.min())


static func _wind_of(speed: float, from_deg := 270.0) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed
	c.wind_from_deg = from_deg
	return c


static func run() -> Array:
	var r: Array = []
	_clean()

	# --- the default weather is calm -----------------------------------------------------------------
	# Mutation: Conditions.wind_speed_mps default 10.0 -> both cases fail.
	var fresh := ConditionsLibrary.load_from("user://r17_does_not_exist.json")
	r.append(TestResult.new("R17 a fresh install's selected weather is calm, 0 m/s",
		fresh.selected().is_calm() and fresh.selected().wind_speed_mps == 0.0 and fresh.selected().gustiness_mps == 0.0,
		"%.2f m/s, gust %.2f" % [fresh.selected().wind_speed_mps, fresh.selected().gustiness_mps]))
	var m0 := _booted()
	r.append(TestResult.new("R17 the booted flight scene has a calm wind and no meander",
		m0.wind.speed_mps == 0.0 and not m0.wind.meander_enabled, "wind %.2f meander %s" % [m0.wind.speed_mps, m0.wind.meander_enabled]))

	# --- a stale file that selects a windy set is migrated, nothing deleted ----------------------------
	# Mutation: delete the migration block in ConditionsLibrary.load_from -> selected stays "windy".
	var windy := ConditionsLibrary.with_default()
	var w10 := windy.create("Windy")
	w10.wind_speed_mps = 10.0
	windy.select(w10.conditions_id)
	windy.save("user://r17_stale.json")
	# Rewrite it as schema 1, the way an old build left it.
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://r17_stale.json"))
	doc["schema"] = 1
	var f := FileAccess.open("user://r17_stale.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var migrated := ConditionsLibrary.load_from("user://r17_stale.json")
	r.append(TestResult.new("R17 a v1 file with a windy set selected opens calm; both sets kept; a .v1.bak copy is written",
		migrated.selected().is_calm() and migrated.ids().size() == 2 and migrated.has(w10.conditions_id)
		and migrated.migrated_selection_from == w10.conditions_id and FileAccess.file_exists("user://r17_stale.json.v1.bak"),
		"selected %s, %d sets, from %s" % [migrated.selected_id, migrated.ids().size(), migrated.migrated_selection_from]))

	# --- the choice persists across a reload ---------------------------------------------------------
	# Mutation: select() not followed by save() in Main.select_conditions -> the reload still says "standard".
	var m1 := _booted()
	var lib1: ConditionsLibrary = m1.conditions_library
	var made: Conditions = lib1.create("Hot day")
	made.temperature_c = 40.0
	m1.select_conditions(made.conditions_id)
	var reloaded := ConditionsLibrary.load_from(SCRATCH_COND)
	r.append(TestResult.new("R17 selecting a weather set from the flight persists across a reload",
		reloaded.selected_id == made.conditions_id and absf(reloaded.selected().temperature_c - 40.0) < 1e-9
		and absf(m1.build.air.temperature_c - 40.0) < 1e-9,
		"reloaded selected %s, %.1f C; live air %.1f C" % [reloaded.selected_id, reloaded.selected().temperature_c, m1.build.air.temperature_c]))
	m1.free()

	# --- a UI edit reaches the live wind and air density, the HUD, and the file ------------------------
	# Mutation: drop `wind = make_wind(c)` from Main._apply_weather -> the wind check fails; drop the build.air line -> the air check fails.
	var m2 := _booted()
	var hover_before: float = m2._hover_throttle
	var rho_before: float = m2.build.air.kgm3()
	m2.toggle_conditions_panel()
	var panel: DsSimConditions = m2.conditions_panel
	panel.wind_speed_field.value = 7.0
	panel.wind_from_field.value = 90.0
	panel.temperature_field.value = 35.0
	panel.elevation_field.value = 1500.0
	panel.apply_button.pressed.emit()
	m2.toggle_conditions_panel()   # close; flight resumes
	m2._physics_process(1.0 / 120.0)
	var saved := ConditionsLibrary.load_from(SCRATCH_COND)
	r.append(TestResult.new("R17 the in-flight panel edit changes the live Wind object (speed and bearing)",
		absf(m2.wind.speed_mps - 7.0) < 1e-9 and absf(m2.wind.from_deg - 90.0) < 1e-9 and m2.core.wind == m2.wind,
		"wind %.1f m/s from %.0f, core wired %s" % [m2.wind.speed_mps, m2.wind.from_deg, m2.core.wind == m2.wind]))
	r.append(TestResult.new("R17 the edit changes the live air density (hotter and higher is thinner) and the hover throttle follows",
		m2.build.air.kgm3() < rho_before - 0.05 and absf(m2.build.air.temperature_c - 35.0) < 1e-9
		and m2._hover_throttle > hover_before,
		"rho %.3f -> %.3f, hover %.3f -> %.3f" % [rho_before, m2.build.air.kgm3(), hover_before, m2._hover_throttle]))
	r.append(TestResult.new("R17 the HUD shows the changed wind",
		m2.hud._wind_label.text.contains("Wind") and not m2.hud._wind_label.text.contains("0.0 m/s"),
		m2.hud._wind_label.text))
	r.append(TestResult.new("R17 the edit forks Standard into a set of its own and persists it",
		saved.selected_id != Conditions.STANDARD_ID and absf(saved.selected().wind_speed_mps - 7.0) < 1e-9
		and saved.has(Conditions.STANDARD_ID) and saved.conditions(Conditions.STANDARD_ID).is_calm(),
		"saved selected %s at %.1f m/s; Standard still calm %s" % [saved.selected_id, saved.selected().wind_speed_mps,
			saved.has(Conditions.STANDARD_ID) and saved.conditions(Conditions.STANDARD_ID).is_calm()]))

	# --- a world can be switched from the flight -------------------------------------------------------
	# Mutation: apply_world not calling _apply_weather -> the live wind stays 7 m/s.
	var worlds := WorldLibrary.load_dir("user://r17_worlds")
	worlds.ensure_presets()
	m2.worlds_dir = "user://r17_worlds"
	var ok: bool = m2.apply_world("windy_coast")
	r.append(TestResult.new("R17 choosing a world loads its wind into the live Wind and a set of its own",
		ok and absf(m2.wind.speed_mps - worlds.world("windy_coast").wind_speed_mps) < 1e-6
		and m2.conditions_library.selected_id == "world_windy_coast",
		"live %.2f m/s, selected %s" % [m2.wind.speed_mps, m2.conditions_library.selected_id]))
	m2.free()
	m0.free()

	# --- the new fields round-trip, and leave an old file's bytes alone ---------------------------------
	var plain := Conditions.new().to_data()
	var tuned := Conditions.new()
	tuned.dir_sigma_deg = 20.0
	tuned.speed_sigma_frac = 0.1
	var back := Conditions.from_data(tuned.to_data())
	r.append(TestResult.new("R17 meander fields are written only when changed, and round-trip",
		not plain.has("dir_sigma_deg") and not plain.has("speed_tau_s") and back.dir_sigma_deg == 20.0 and back.speed_sigma_frac == 0.1,
		"%s" % [plain.keys()]))

	# --- the meander: direction std, speed std, and the time scale -------------------------------------
	# Mutation: _step_meander computing the noise without sqrt(1 - a*a) -> std off by a large factor; a = 0 -> autocorrelation 0.
	var c5 := _wind_of(5.0)
	var w := Wind.new(c5, 2.5, 7, Wind.Model.DRYDEN, true)
	var thetas := PackedFloat64Array()
	var speeds := PackedFloat64Array()
	for _i in 60000:
		w.update_at(1.0, Vector3.ZERO, 10.0)
		thetas.append(w.meander_theta_deg())
		speeds.append(w.meander_speed_fraction())
	var target := c5.effective_dir_sigma_deg()
	var sd := _std(thetas)
	r.append(TestResult.new("R17 the direction wander's std over a long run matches the labelled estimate clamp(57.3/U, 8, 45)",
		absf(target - clampf(57.3 / 5.0, 8.0, 45.0)) < 1e-9 and absf(sd - target) / target < 0.12,
		"U 5 m/s: target %.2f deg, measured %.2f deg" % [target, sd]))
	var sds := _std(speeds)
	r.append(TestResult.new("R17 the speed variability std is 15 percent of U",
		absf(sds - 0.15) / 0.15 < 0.12, "measured %.3f" % sds))
	var rho := _autocorr(thetas, int(w.meander_dir_tau_s))
	r.append(TestResult.new("R17 the direction wander's autocorrelation at one time scale is 1/e (time scale 60 s)",
		absf(rho - exp(-1.0)) < 0.08, "rho(60 s) = %.3f, expected %.3f" % [rho, exp(-1.0)]))
	r.append(TestResult.new("R17 the auto sigma is larger in light wind than strong, clamped to [8, 45] degrees",
		_wind_of(2.0).effective_dir_sigma_deg() > _wind_of(10.0).effective_dir_sigma_deg()
		and _wind_of(10.0).effective_dir_sigma_deg() == 8.0 and _wind_of(0.5).effective_dir_sigma_deg() == 45.0,
		"2 m/s %.1f, 10 m/s %.1f, 0.5 m/s %.1f" % [_wind_of(2.0).effective_dir_sigma_deg(),
			_wind_of(10.0).effective_dir_sigma_deg(), _wind_of(0.5).effective_dir_sigma_deg()]))
	var calm_w := Wind.new(Conditions.new(), 2.5, 7, Wind.Model.DRYDEN, true)
	var calm_max := 0.0
	for _i in 2000:
		calm_max = maxf(calm_max, calm_w.update_at(0.1, Vector3.ZERO, 10.0).length())
	r.append(TestResult.new("R17 calm stays calm: no meander, no wind, ever", not calm_w.meander_enabled and calm_max == 0.0,
		"max |wind| %.4f" % calm_max))
	var inst := Wind.new(_wind_of(5.0, 0.0), 2.5, 7, Wind.Model.DRYDEN, true)
	inst.update_at(30.0, Vector3.ZERO, 10.0)
	var v := inst.meandered_steady()
	var bearing := fposmod(rad_to_deg(atan2(-v.x, v.z)), 360.0)
	r.append(TestResult.new("R17 the HUD's instantaneous bearing is the bearing the wind vector actually comes from",
		absf(angle_difference(deg_to_rad(bearing), deg_to_rad(inst.inst_from_deg()))) < 1e-4
		and absf(v.length() - inst.inst_speed_mps()) < 1e-4,
		"vector bearing %.3f, HUD %.3f; |v| %.3f HUD %.3f" % [bearing, inst.inst_from_deg(), v.length(), inst.inst_speed_mps()]))

	# --- the range limit and the ground beyond the field ----------------------------------------------
	# Mutation: delete the out_of_range branch in Main._physics_process -> the aircraft is still 400 m out.
	var m3 := _booted()
	var start: Vector3 = m3.core.rigid_body.position_m
	r.append(TestResult.new("R17 the start is in range, a point 1 km away is not",
		not MAIN.out_of_range(start, m3.terrain) and MAIN.out_of_range(Vector3(1000, 5, 0), m3.terrain), ""))
	m3.core.rigid_body.position_m = Vector3(400.0, 20.0, 0.0)
	m3._physics_process(1.0 / 120.0)
	var back_at: Vector3 = m3.core.rigid_body.position_m
	r.append(TestResult.new("R17 an aircraft that leaves the flying area is brought back to the course",
		not MAIN.out_of_range(back_at, m3.terrain) and back_at.distance_to(start) < 200.0,
		"after one frame at %s" % [back_at]))
	var world := CollisionWorld.new(m3.terrain, m3.obstacles, m3.course.gates)
	var far_ground := world.contact(Vector3(2000.0, -0.5, -2000.0), 0.05)
	r.append(TestResult.new("R17 the ground still exists, and is collidable, far beyond the drawn field (nothing to fall into)",
		not far_ground.is_empty() and String(far_ground.get("surface", "")) == "ground", str(far_ground.get("surface", "none"))))
	m3.free()

	# --- a hands-off hover stays put in calm air (B1) ----------------------------------------------------
	# Mutations: Gyro.still_average returns 0.6 x its mean -> 3.4-3.7 m, all three fail; rotor_h_force_enabled = false -> 8-29 m.
	var drift_bound := calm_drift_bound_m()
	var calm_bound: float = drift_bound["bound_m"]
	for seed_n in DRIFT_SEEDS:
		var m4 := _booted()
		_reseed(m4, seed_n)
		m4.core.rigid_body.position_m.y += DRIFT_LIFT_M
		var calm := _hover(m4, DRIFT_SECONDS)
		r.append(TestResult.new("R17 hands-off angle-mode hover for 30 s in calm air drifts less than %.2f m, airborne throughout (seed %d)" % [calm_bound, seed_n],
			float(calm["horizontal_m"]) < calm_bound and float(calm["min_clearance_m"]) > 0.0,
			"drift %.2f m (bound: mu %.3f /s, residue %.2f m), sink %.2f m, lowest %.2f m above the ground" % [calm["horizontal_m"], drift_bound["mu"], drift_bound["residue_m"], -float(calm["vertical_m"]), calm["min_clearance_m"]]))
		m4.free()

	# --- hands off from the real spawn, the aircraft holds its height (B1, review P2) -------------------
	# Mutation: Main._rebuild uses build.hover_throttle_for(...) without dynamic_hover_throttle -> sinks 1.4 m.
	var m6 := _booted()
	var spawn := _hover(m6, 10.0)
	r.append(TestResult.new("R17 hands off for 10 s from the spawn, the aircraft sinks less than %.1f m and never touches the ground" % SPAWN_SINK_BOUND_M,
		absf(float(spawn["vertical_m"])) < SPAWN_SINK_BOUND_M and float(spawn["min_clearance_m"]) > 0.0,
		"dy %.2f m, lowest %.2f m above the ground" % [spawn["vertical_m"], spawn["min_clearance_m"]]))
	m6.free()

	# --- the accelerometer sees airspeed through rotor drag (B1, review P1/T2) ---------------------------
	# Mutations: rotor_h_force_enabled = false -> mu reads 0.005-0.016 /s, all fail; rotor drag fed rigid_body.velocity_mps instead
	# of the air-relative velocity -> the wind case reads ~0.
	for speed in [1.0, 3.0]:
		var side := _specific_force_at(Vector3(speed, 0.0, 0.0), null)
		var mu_read: float = -float(side["sf"].x) / speed
		var mu_want := _expected_mu(speed)
		r.append(TestResult.new("R17 level at %.0f m/s sideways the body-x accelerometer reads -mu*v, mu within %.0f percent of Build's rotor H + body drag (%.3f /s)" % [speed, 100.0 * MU_TOLERANCE, mu_want],
			absf(mu_read - mu_want) < MU_TOLERANCE * mu_want, "mu %.3f /s (sf %s)" % [mu_read, side["sf"]]))
	var breeze := Conditions.new()
	breeze.wind_speed_mps = 3.0
	breeze.wind_from_deg = 90.0
	var held := _specific_force_at(Vector3.ZERO, breeze)
	var air_x := float(held["air"].x)
	var mu_wind: float = -float(held["sf"].x) / air_x if absf(air_x) > 0.5 else 0.0
	var mu_wind_want := _expected_mu(absf(air_x))
	r.append(TestResult.new("R17 held still in a 3 m/s side wind the accelerometer reads the same -mu*airspeed (%.3f /s): wind acts through rotor drag" % mu_wind_want,
		absf(mu_wind - mu_wind_want) < MU_TOLERANCE * mu_wind_want, "air x %.2f m/s, mu %.3f /s (sf %s)" % [air_x, mu_wind, held["sf"]]))

	# --- flown to terminal speed at the calibration lean, the sim agrees with Build.top_speed_kmh (B1) ---
	# Mutations: Build.TOP_SPEED_LEAN_DEG held at 45 for the flight (lean_deg arg) -> 77 km/h, fails; the rotor H-force
	# replaced by the old K law (2.5 T v / (Omega R)) -> 152 km/h, fails.
	var flown := fly_terminal_kmh(Build.TOP_SPEED_LEAN_DEG)
	var analytic := ReferenceBuild.build().top_speed_kmh()
	r.append(TestResult.new("R17 the sim flown level at a %.0f deg lean settles within %.0f percent of Build.top_speed_kmh (%.1f km/h)" % [Build.TOP_SPEED_LEAN_DEG, 100.0 * TOP_SPEED_TOLERANCE, analytic],
		absf(flown - analytic) < TOP_SPEED_TOLERANCE * analytic, "flown %.2f km/h" % flown))

	# --- the forward-flight power bucket (B1): flown, level, power dips below hover and climbs again --------
	# Classical rotor power P = P_i(mu) + P_0 (1 + K mu^2) + P_par (Leishman ch. 5): induced power falls with speed
	# (Glauert), parasite rises with V^3, so the minimum sits at moderate mu below hover. The flown reference build at
	# BUCKET_LEANS_DEG: hover 4.76 A, 9.5 m/s (mu 0.16; tip speed only ~59 m/s on a 5" prop) 4.34 A, 19 m/s 7.0 A. Mutation: DroneCore.flap_tpp_enabled false
	# (the flapping tilt read at the shaft, charged as H_flap x V of climb power) -> 9.6 m/s draws 5.14 A, above hover; fails.
	var p_hover := fly_level_power(BUCKET_LEANS_DEG[0])
	var p_cruise := fly_level_power(BUCKET_LEANS_DEG[1])
	var p_fast := fly_level_power(BUCKET_LEANS_DEG[2])
	r.append(TestResult.new("R17 flown level, the power at mu %.2f-%.2f is at least %.0f percent below hover, and climbs again at speed (the bucket)" % [BUCKET_MU_BAND.x, BUCKET_MU_BAND.y, 100.0 * BUCKET_MIN_DIP],
		p_cruise["mu"] >= BUCKET_MU_BAND.x and p_cruise["mu"] <= BUCKET_MU_BAND.y
			and p_cruise["a"] < (1.0 - BUCKET_MIN_DIP) * p_hover["a"] and p_fast["a"] > p_cruise["a"],
		"hover %.3f A; %.1f m/s mu %.3f: %.3f A; %.1f m/s: %.3f A" % [p_hover["a"], p_cruise["v"], p_cruise["mu"], p_cruise["a"], p_fast["v"], p_fast["a"]]))

	# --- in a 10 m/s wind the wind's direction is not constant -----------------------------------------
	# Mutation: pass p_meander = false in Main.make_wind -> the bearing spread is exactly 0.
	var m5 := _booted()
	var gale := _wind_of(10.0, 270.0)
	m5.wind = MAIN.make_wind(gale)
	m5.core.wind = m5.wind
	var windy_run := _hover(m5, 30.0)
	var spread := _spread(windy_run["bearings"])
	r.append(TestResult.new("R17 in a 10 m/s wind the wind bearing seen over a 30 s hover is not constant (spread > 1 deg)",
		spread > 1.0 and float(windy_run["horizontal_m"]) > 30.0, "spread %.2f deg, drift %.0f m" % [spread, windy_run["horizontal_m"]]))
	m5.free()
	return r


static func _std(a: PackedFloat64Array) -> float:
	var m := 0.0
	for x in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x in a:
		s += (x - m) * (x - m)
	return sqrt(s / a.size())


static func _autocorr(a: PackedFloat64Array, lag: int) -> float:
	var m := 0.0
	for x in a:
		m += x
	m /= a.size()
	var num := 0.0
	var den := 0.0
	for i in a.size():
		den += (a[i] - m) * (a[i] - m)
		if i + lag < a.size():
			num += (a[i] - m) * (a[i + lag] - m)
	return num / den
