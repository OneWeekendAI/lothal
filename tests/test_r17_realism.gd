class_name TestR17Realism
extends RefCounted
## R1.7: a hands-off hover stays put in calm air; the default weather is calm; the weather and the world are editable from the
## flight and reach the live wind and air; the choice persists; the wind meanders in direction and speed (seeded OU); and the
## aircraft cannot leave the world. One TestResult per case. The mutation each was proven against is stated in its comment.

const MAIN := preload("res://src/scenes/main.gd")
const SCRATCH_COND := "user://r17_conditions.json"
const SCRATCH_SITES := "user://r17_sites.json"
const CALM_DRIFT_BOUND_M := 25.0     # 30 s hands-off angle-mode hover in calm air; was 68 m before the IMU calibration (R1.7)


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
	var bearings: Array = []
	var dt := 1.0 / 120.0
	for i in int(seconds / dt):
		m._physics_process(dt)
		if i % 120 == 0 and m.wind.velocity_mps().length() > 0.5:
			var v: Vector3 = m.wind.velocity_mps()
			bearings.append(rad_to_deg(atan2(v.x, v.z)))
	var d: Vector3 = m.core.rigid_body.position_m - p0
	return {"horizontal_m": Vector2(d.x, d.z).length(), "bearings": bearings}


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

	# --- a hands-off hover stays put in calm air -----------------------------------------------------
	# Mutation: remove the two calibrate() calls in Main._reset_to -> drift is ~68 m and the bound fails.
	var m4 := _booted()
	var calm := _hover(m4, 30.0)
	r.append(TestResult.new("R17 hands-off angle-mode hover for 30 s in calm air drifts less than %.0f m" % CALM_DRIFT_BOUND_M,
		float(calm["horizontal_m"]) < CALM_DRIFT_BOUND_M, "drift %.1f m (%.2f m/s)" % [calm["horizontal_m"], float(calm["horizontal_m"]) / 30.0]))
	m4.free()

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
