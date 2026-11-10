class_name MissionRunner
extends RefCounted
## SR4 mission runner. MissionRunner.run(params) flies one ready-made mission headless (no window, no input) through
## FlightRig -> NavPilot -> the real FlightController and returns the result dictionary (see MissionResult).
## Deterministic: the seed drives Wind and Gyro through FlightRig; nothing else is random and no wall clock is read
## into the result. Same params twice => byte-identical MissionResult.to_json.
##
## params: class_id (DroneClass id or references.json id), mission, seed, wind_speed_mps, wind_from_deg, gust_mps,
## fields {height_m, speed_mps, front_overlap, side_overlap, reserve_pct}, polygon, path, capacity_scale (default 1),
## max_sorties, camera (CameraParams), dt (default 1/500), camera_on (non-survey), hover_s, laps, range_heading_deg,
## end ("land"|"rth", follow_path), max_sim_min (default 120), debug_skip_line (survey, test only).
##
## FLIGHT: take-off at 2.5 m/s to the mission height (start = home = origin, on the ground), fly the mission, return to
## home at the mission height and descend at 1.5 m/s. Phases: takeoff -> mission -> rth -> descend -> landed.
##
## RESERVE RULE (reserve_pct > 0; 0 switches RTH off):
##   remaining_Wh <= reserve_pct/100 * pack_Wh + energy_to_home
## remaining_Wh = remaining fraction * pack_Wh (an ESTIMATE of the pack's usable energy). pack_Wh starts as capacity * nominal V
## and, once 3 % of the pack is used, becomes the MEASURED energy per used fraction (nominal V x capacity over-states what
## the pack delivers: sag and Peukert; the first run flew flat at the nominal figure),
## energy_to_home = (measured J/m over the last 20 s of motion x distance home + hover power x (height / descent rate + 3 s landing))
##   x 1.2 safety x sag factor (marginal vs average Wh per pack fraction) + 1.5 percent of the pack. See _e_home_wh. The pack lands AT OR
##   ABOVE the stated reserve (before this estimate it landed up to ~3 points under).
## Tested at 5 Hz. When it trips: warning 'RTH at reserve', fly home at height, descend, touch down.
## Survey adds a LOOKAHEAD at each line boundary: if the next line plus the way home from its end does not fit above
## the reserve, return NOW (warning 'RTH: next line does not fit'), swap the pack (max_sorties) and resume at the first
## unflown line. Swap time is not flight time.
## NOT FLOWN: if remaining_Wh - reserve is less than hover power * (climb + descent + 30 s) * 1.1, nothing is flown.
##
## COVERAGE: area_flown_m2 is rasterised from the TRACK (never field area / swath): the camera footprint at each
## camera-on 5 Hz sample (size from CameraParams at the actual height, rotated by the heading) is swept on a 0.5 m
## grid; cells whose centres lie inside the polygon are counted. Holes = connected uncovered cell clusters of at least
## HOLE_MIN_M2. Without a polygon (non-survey) area_flown_m2 is the swept footprint area (0 when the camera is off).
## The camera is modelled as continuous (a footprint at every sample); the shot-interval limit is reported by the
## planner as a 'forward' hole, not by thinning the footprints.

const FAST_HZ := 50.0
const SLOW_HZ := 5.0
const TRACK_STRIDE := 7              # x, z, y, heading, camera_on, roll, pitch (roll / pitch in rad, Euler YXZ of the true body attitude; +roll = right wing up about the forward axis)
const BLUR_LIMIT_PX := SurveyPhotos.BLUR_LIMIT_PX
const GRID_M := 0.5
const HOLE_MIN_M2 := 25.0
const TILT_LIMIT_DEG := 75.0
const RESERVE_SAFETY := 1.2        # margin on the return + landing estimate: before it, the measured estimate ran up to 15 percent short (seven_lr)
const RESERVE_PACK_MARGIN := 0.015  # fixed 1.5 percent of the pack: the 5 Hz trip test and fraction-vs-Wh conversion error (estimated)
const LANDING_SETTLE_S := 3.0       # flare and touch-down at hover power after the descent (estimated)
const MIN_MISSION_S := 30.0
const WINDOW_N := 100              # 20 s of 5 Hz power samples
const CUTOFF_HOLD_S := 0.5         # as tests/sim_reality/sim_reality_harness.gd
const ACCEPT_M := 2.0
const NORMAL_ENDINGS: Array[String] = ["completed", "landed_at_reserve", "battery_cutoff"]

static var _catalog: PartsCatalog

# ---- configuration
var class_id := ""
var mission := ""
var seed_value := 1
var dt := 1.0 / 500.0
var params_in: Dictionary = {}
var p: Dictionary = {}                # resolved fields by name
var extras: Dictionary = {}
var camera: CameraParams
var polygon := PackedVector2Array()
var cruise_mps := 10.0                # the class cruise speed (return speed of a survey)
var rth_mps := 10.0
var max_sorties := 1
var hover_s := 0.0
var laps := 0
var loop_side := 100.0
var camera_on_always := false
var max_sim_s := 7200.0
var land_at_end := true
var skip_line := -1
var world: World = null               # SR3: where/when; its polygon, wind, air and terrain replace the plain params
var terrain_fn := Callable()          # ground height above home at (x, z); valid only with a world and terrain_follow
var agl_fn := Callable()               # same ground, used to MEASURE AGL even when terrain_follow is off (the fail-proof)
var agl_min := INF                    # AGL over the mission phase (terrain follow evidence)
var agl_max := -INF
var agl_n := 0
var rth_wind_aware := true            # false = the pre-SR3 return estimate (no headwind correction); the fail-proof switch

# ---- state
var rig: FlightRig
var bat: BatteryModel
var phase := "takeoff"
var t := 0.0
var t_phase := 0.0
var energy_ws := 0.0
var last_ws := 0.0
var distance_m := 0.0
var max_home := 0.0
var sorties := 0
var warnings: Array[String] = []
var ended_by := ""
var mission_done := false
var alt_goal := 0.0
var alt_cmd := 0.0
var cam_on := false
var track := PackedFloat64Array()     # TRACK_STRIDE floats per 5 Hz sample: x, z, y, heading, camera_on, roll, pitch
var photos: Array = []                # one entry per camera trigger: {t, pos, q, vg}  (SR5.4)
var next_trigger_t := 0.0
var trigger_interval_s := 0.0
var gimbal_stabilised := false        # false = camera fixed to the airframe (tilts with it); true = ideal 3-axis gimbal (nadir, yaw follows the body)
var required_photos := 2
var blur_limit_px := BLUR_LIMIT_PX
var pw := PackedFloat64Array()
var pv := PackedFloat64Array()
var pn := 0
var low_for := 0.0
var pack_wh := 1.0                    # effective Wh per full pack: nominal at first, then measured (see _slow)
var nominal_pack_wh := 1.0
var pack_e0_ws := 0.0
var sortie_reports: Array = []
var sortie_t0 := 0.0
var hover_est_w := 100.0
var rth_reason := ""
var land_xz := Vector2.ZERO
var last_reserve_left := 100.0
var pa := PackedFloat64Array()        # airspeed ring (|ground velocity - mean wind at that height|), same slots as pw
var rf := PackedFloat64Array()        # remaining-fraction ring, same slots as pw
var slow_dt_s := 0.2
var rth_pred_wh := -1.0              # return energy predicted at the moment RTH began (telemetry for the reserve test)
var rth_e0_ws := 0.0
var home_error := 0.0
# survey
var plan: Dictionary = {}
var chunks: Array = []                # each {pts:[Vector2], kinds:[String], line_b:int(local), len_s:float, len_t:float, end:Vector2}
var next_chunk := 0
var path_kinds: Array = []
var path_cam: Array = []              # per leg: camera on
var path_first: Array = []            # per chunk (queue order): first path index
var path_line_b: Array = []           # per chunk: path index of the second 'line' waypoint
var sortie_first_chunk := 0
var evaluated_chunk := -1
var path_chunk0 := 0
var hover_t0 := 0.0
var lap_path_made := false
var mission_started_t := 0.0
# stepping state (SR4.3)
var _final: Dictionary = {}
var _flying := false
var _ctx: Dictionary = {}
var _ticks := 0
var _slow_every := 1
var _fast_every := 1
var _fast_dt := 0.0


static func run(params: Dictionary) -> Dictionary:
	var runner := MissionRunner.new()
	if runner.begin(params):
		runner.advance(0x7fffffff)
	return runner.finish()


## SR4.3 stepping API. `run()` above and a watched flight (src/scenes/main.gd `watch_mission`) both go through
## begin / advance / finish, and advance(n) is n times the SAME single-tick body, so any chunking (one render frame
## = several ticks) gives the same result as a headless run with the same params and seed.
## begin(): true when a flight is ready to step; false when the result is already final (error, not flown, test_pack,
## which runs its parts as separate flights and is not watchable).
func begin(params: Dictionary) -> bool:
	_final = _run(params)
	return _flying


func advance(ticks: int) -> void:
	var n := 0
	while _flying and ended_by == "" and n < ticks:
		_tick_once()
		n += 1


func is_done() -> bool:
	return not _flying or ended_by != ""


func finish() -> Dictionary:
	if not _flying:
		return _final
	t = _ticks * dt
	_flying = false
	return _result(_ctx["field_out"], _ctx["build"], _ctx["scale"], _ctx["cond"])


static func _catalog_shared() -> PartsCatalog:
	if _catalog == null:
		_catalog = PartsCatalog.load_default()
	return _catalog


static func make_build(cls: String, capacity_scale: float) -> Build:
	var ref := SimRealityHarness.find_reference(cls)
	if not ref.is_empty():
		return SimRealityHarness.build_for(ref, capacity_scale)
	return DesignSession.default_for_class(cls).build(_catalog_shared())


func _error(msg: String) -> Dictionary:
	var r := {"schema_version": MissionResult.SCHEMA_VERSION, "mission": String(params_in.get("mission", "")),
		"class_id": String(params_in.get("class_id", "")), "seed": int(params_in.get("seed", 1)),
		"versions": {"model": MissionResult.MODEL_VERSION}, "ended_by": "error", "completed": false,
		"error": msg, "warnings": [msg], "flight_time_s": 0.0, "distance_m": 0.0, "energy_wh": 0.0,
		"area_flown_m2": 0.0, "sorties": 0, "track_samples": 0, "params": {}, "conditions": {}, "build_fingerprint": ""}
	MissionResult.add_figures(r)
	return r


func _run(params: Dictionary) -> Dictionary:
	params_in = params
	class_id = String(params.get("class_id", ""))
	mission = String(params.get("mission", ""))
	seed_value = int(params.get("seed", 1))
	dt = float(params.get("dt", 1.0 / 500.0))
	var scale := float(params.get("capacity_scale", 1.0))
	var base := Mission.defaults_for(class_id, mission)
	if not bool(base["ok"]):
		return _error(String(base["error"]))
	var build := make_build(class_id, scale)
	world = params.get("world") as World
	if world != null:
		build.air = world.to_air()
	if not Mission.TABLE.has(class_id):
		base = Mission.defaults_for(class_id, mission, build)
	if mission == Mission.TEST_PACK:
		return _run_pack(params, base)
	# ---- resolve fields
	var over: Dictionary = params.get("fields", {})
	extras = base["extras"]
	var field_out := Mission.resolve_fields(base, over)
	for k in Mission.FIELDS:
		p[k] = float(field_out[k]["value"])
	cruise_mps = float(Mission.defaults_for(class_id, Mission.CRUISE_LOOP, build)["fields"]["speed_mps"]["value"])
	rth_mps = float(p["speed_mps"]) if mission != Mission.SURVEY else cruise_mps
	camera = params.get("camera", CameraParams.generic_1inch())
	trigger_interval_s = float(params.get("trigger_interval_s", camera.min_shot_interval_s))
	gimbal_stabilised = bool(params.get("gimbal_stabilised", false))
	required_photos = int(params.get("required_photos", 2))
	blur_limit_px = float(params.get("blur_limit_px", BLUR_LIMIT_PX))
	max_sorties = int(params.get("max_sorties", int(extras["max_sorties"]["value"])))
	hover_s = float(params.get("hover_s", 0.0))
	laps = int(params.get("laps", 0))
	loop_side = float(extras["loop_side_m"]["value"])
	camera_on_always = bool(params.get("camera_on", false)) and mission != Mission.SURVEY
	max_sim_s = float(params.get("max_sim_min", 120.0)) * 60.0
	land_at_end = String(params.get("end", "land")) == "land"
	skip_line = int(params.get("debug_skip_line", -1))
	rth_wind_aware = bool(params.get("rth_wind_correction", true))
	var field: Vector2 = extras["survey_field_m"]
	polygon = PackedVector2Array(params.get("polygon", PackedVector2Array([Vector2(30, 0), Vector2(30 + field.x, 0), Vector2(30 + field.x, field.y), Vector2(30, field.y)])))
	# ---- rig
	var cond := FlightRig.conditions_with_wind(float(params.get("wind_speed_mps", 0.0)), float(params.get("wind_from_deg", 0.0)), float(params.get("gust_mps", 0.0)))
	if world != null:
		cond = world.to_conditions()
		if not params.has("polygon") and world.polygon.size() >= 6:
			polygon = world.polygon_sim()
		agl_fn = world.ground_fn()
		if bool(params.get("terrain_follow", true)):
			terrain_fn = agl_fn
	rig = FlightRig.new(build, cond, seed_value, Vector3.ZERO, dt)
	bat = rig.core.powertrain.battery
	if SimRealityHarness.find_reference(class_id).is_empty():
		bat.capacity_mah = bat.capacity_mah * scale
	rig.nav.heading_mode = NavPilot.HeadingMode.CRAB
	nominal_pack_wh = bat.capacity_mah / 1000.0 * bat.nominal_v
	pack_wh = nominal_pack_wh
	hover_est_w = build.hover_power_w(bat)
	alt_goal = float(p["height_m"])
	if mission == Mission.SURVEY:
		_prepare_survey()
	# ---- preflight
	var h := float(p["height_m"])
	var reserve_wh := float(p["reserve_pct"]) / 100.0 * pack_wh
	var need_wh := hover_est_w * (h / Mission.CLIMB_RATE_MPS + h / Mission.DESCENT_RATE_MPS + MIN_MISSION_S) * RESERVE_SAFETY / 3600.0
	if _remaining_wh() - reserve_wh < need_wh:
		warnings.append("reserve exceeds usable energy; mission not flown")
		ended_by = "not_flown"
		return _result(field_out, build, scale, cond)
	_ctx = {"field_out": field_out, "build": build, "scale": scale, "cond": cond}
	_prepare_fly()
	_flying = true
	return {}


# ---------------------------------------------------------------- the flight loop
func _prepare_fly() -> void:
	_slow_every = int(round(1.0 / (SLOW_HZ * dt)))
	_fast_every = int(round(1.0 / (FAST_HZ * dt)))
	_fast_dt = _fast_every * dt
	_ticks = 0
	_begin_sortie()


## One tick of the flight loop (the body the headless run and a watched run both use).
func _tick_once() -> void:
	var o := rig.core.observables
	rig.step()
	energy_ws += o.voltage_live_v * o.current_total_a * dt
	_ticks += 1
	if _ticks % _fast_every == 0:
		_fast(_fast_dt)
		if ended_by != "":
			return
	if _ticks % _slow_every == 0:
		t_phase += _slow_every * dt
		_slow(_slow_every * dt)


func _begin_sortie() -> void:
	sorties += 1
	phase = "takeoff"
	sortie_t0 = _now()
	alt_goal = float(p["height_m"])
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(alt_cmd)
	cam_on = false
	low_for = 0.0
	evaluated_chunk = -1
	sortie_first_chunk = next_chunk


func _now() -> float:
	return rig.time_s


func _fast(fast_dt: float) -> void:
	var rb := rig.core.rigid_body
	var o := rig.core.observables
	if (rb.orientation * Vector3.UP).y < cos(deg_to_rad(TILT_LIMIT_DEG)):
		ended_by = "lost_control"
		warnings.append("loss of control: tilt above %.0f deg at t=%.1f s" % [TILT_LIMIT_DEG, _now()])
		return
	var y := rb.position_m.y - (float(terrain_fn.call(rb.position_m.x, rb.position_m.z)) if terrain_fn.is_valid() else 0.0)
	if y < -10.0 or y > float(p["height_m"]) + 60.0:
		ended_by = "lost_control"
		warnings.append("loss of control: height anomaly (y=%.1f m) at t=%.1f s" % [y, _now()])
		return
	distance_m += rb.velocity_mps.length() * fast_dt
	alt_cmd = move_toward(alt_cmd, alt_goal, (Mission.CLIMB_RATE_MPS if alt_goal > alt_cmd else Mission.DESCENT_RATE_MPS) * fast_dt)
	if terrain_fn.is_valid():
		rig.nav.set_altitude_agl(alt_cmd, terrain_fn)
	else:
		rig.nav.set_altitude_msl(alt_cmd)
	if bat.below_cutoff(o.current_total_a) and bat.remaining_fraction() > 0.0:
		low_for += fast_dt
	else:
		low_for = 0.0
	if low_for >= CUTOFF_HOLD_S or bat.used_mah >= bat.capacity_mah:
		var hover_hold := mission == Mission.HOVER_ENDURANCE and phase == "mission"
		ended_by = "battery_cutoff" if hover_hold else "battery_empty_in_flight"
		if not hover_hold:
			warnings.append("battery cutoff before landing (phase %s, pack %.0f %% left, loaded %.2f V/cell)" % [phase, bat.remaining_fraction() * 100.0, o.voltage_live_v / float(bat.cells)])
		return
	if _now() >= max_sim_s:
		ended_by = "time_cap"
		warnings.append("simulated-time cap of %.0f min reached" % (max_sim_s / 60.0))


func _remaining_wh() -> float:
	return bat.remaining_fraction() * pack_wh


func _mean_power(motion: bool) -> float:
	var s := 0.0
	var n := 0
	for i in mini(pn, WINDOW_N):
		var moving := pv[i] >= 2.0
		if motion and moving or (not motion and pv[i] < 1.0):
			s += pw[i]
			n += 1
	return s / n if n > 0 else -1.0


func _power_motion_or_hover() -> float:
	var m := _mean_power(true)
	if m > 0.0:
		return m
	var hv := _mean_power(false)
	return hv if hv > 0.0 else hover_est_w


## Energy to fly home and land, from what this aircraft has MEASURED over the last 20 s (never a catalogue number):
##   cruise  = measured joules per metre in motion (sum of power over sum of speed on the moving samples, so it carries
##             the wind the aircraft is flying in now) x distance home;
##   landing = hover power (the larger of the measured hover samples and the powertrain's own hover_power_w, because the
##             descent holds near hover thrust with the avionics load on) x (height / descent rate + LANDING_SETTLE_S);
## then RESERVE_SAFETY on the sum. The older estimate priced the whole way home at mean in-motion power and left the
## landing to that same figure; it ran short and the aircraft touched down up to ~3 points under the stated reserve.
func _e_home_wh(dist_m: float, height: float, from_xz: Vector2 = Vector2.INF) -> float:
	var j_per_m := _motion_j_per_m()
	var cruise_wh := 0.0
	if j_per_m > 0.0:
		cruise_wh = j_per_m * dist_m * _return_wind_factor(height, from_xz) / 3600.0
	else:
		cruise_wh = hover_est_w * dist_m / maxf(rth_mps, 0.5) / 3600.0
	var hover_w := maxf(_mean_power(false), hover_est_w)
	var land_wh := hover_w * (maxf(height, 0.0) / Mission.DESCENT_RATE_MPS + LANDING_SETTLE_S) / 3600.0
	return (cruise_wh + land_wh) * RESERVE_SAFETY * _sag_factor() + RESERVE_PACK_MARGIN * pack_wh


## Mean wind vector (world frame) at the aircraft's height above ground, from the SR2 wind. Zero without a wind model.
func _wind_at(pos: Vector3) -> Vector3:
	var w = rig.core.wind
	if w == null:
		return Vector3.ZERO
	return w.mean_at(maxf(pos.y - rig.core.ground_y_m, 0.0))


## Wind correction of the way home (SR3 pre-task; the reserve used to price the return at the power of the last 20 s,
## which is flown on every heading of the loop, so a headwind home was priced as the loop average).
## Power against airspeed is modelled as P(Va) = P_hover + k Va^3 (parasite-type growth with airspeed), with k fixed by the
## window itself: k Va_win^3 = (mean moving power - hover power), at least 20 percent of hover power (ESTIMATED floor, so a
## window at near-hover power still reacts to the wind). The factor is P(Va on the way home) / P(window mean): the airspeed
## home is |rth_mps along the home heading - mean wind at flight height|, i.e. it carries the headwind component. 1.0 without
## a position (the survey line lookahead passes the line end) or without moving samples. In near-calm air also times the window's mean ground speed over the speed flown home (energy per metre = power / speed). Clamped 0.3..2.5 (ESTIMATED).
func _return_wind_factor(height: float, from_xz: Vector2) -> float:
	if not rth_wind_aware or from_xz == Vector2.INF or from_xz.length() < 1.0:
		return 1.0
	var p_mot := _mean_power(true)
	if p_mot <= 0.0:
		return 1.0
	var p_h := maxf(_mean_power(false), hover_est_w)
	var va3 := 0.0
	var vg := 0.0
	var n := 0
	for i in mini(pn, WINDOW_N):
		if pv[i] >= 2.0:
			va3 += pa[i] * pa[i]
			vg += pv[i]
			n += 1
	if n == 0 or va3 <= 0.0:
		return 1.0
	va3 /= n
	vg /= n
	var k := maxf(p_mot - p_h, 0.2 * p_h) / va3
	var heading := (-from_xz).normalized() * rth_mps
	var air := Vector3(heading.x, 0.0, heading.y) - _wind_at(Vector3(from_xz.x, height + rig.core.ground_y_m, from_xz.y))
	var p_win := p_h + maxf(p_mot - p_h, 0.2 * p_h)
	# power ratio at the airspeed home, times the time-per-metre ratio (the window's mean ground speed over the speed flown home)
	# In wind the window's ground speed is dragged around by the head/tail legs and the ratio under-priced the return (seven_lr from 225 deg landed
	# at 24.8 %), so the speed ratio is applied only in near-calm air, where it fixes the survey (slow lines, fast return) case.
	var speed_ratio := vg / maxf(rth_mps, 1.0) if _wind_at(Vector3(from_xz.x, height + rig.core.ground_y_m, from_xz.y)).length() < 1.0 else 1.0
	return clampf((p_h + k * air.length_squared()) / p_win * speed_ratio, 0.3, 2.5)


## How many pack-average watt-hours one more watt-hour costs NOW (>= 1). pack_wh is the average energy per used fraction
## since take-off, but the same fraction yields fewer watt-hours late in the discharge (lower terminal voltage, Peukert), so a
## return priced at the average lands short. Measured over the same 20 s window: energy drawn / pack fraction used in it.
## Needs 0.3 percent of the pack used in the window to be meaningful; otherwise 1.
func _sag_factor() -> float:
	var n := mini(pn, WINDOW_N)
	if n < 10 or pack_wh <= 0.0:
		return 1.0
	var newest := (pn - 1) % WINDOW_N
	var oldest := (pn - n) % WINDOW_N
	var d_frac := rf[oldest] - rf[newest]
	if d_frac < 0.003:
		return 1.0
	var e_wh := 0.0
	for i in n:
		e_wh += pw[i]
	e_wh *= slow_dt_s / 3600.0
	return clampf(pack_wh / (e_wh / d_frac), 1.0, 1.5)


## Joules per metre over the moving samples of the window (-1 when there are none).
func _motion_j_per_m() -> float:
	var e := 0.0
	var d := 0.0
	for i in mini(pn, WINDOW_N):
		if pv[i] >= 2.0:
			e += pw[i]
			d += pv[i]
	return e / d if d > 0.0 else -1.0


func _slow(slow_dt: float) -> void:
	var rb := rig.core.rigid_body
	var pos := rb.position_m
	var vel := rb.velocity_mps
	var sp_h := Vector2(vel.x, vel.z).length()
	# power sample (ring)
	var pw_now := (energy_ws - last_ws) / slow_dt
	last_ws = energy_ws
	var slot := pn % WINDOW_N
	if pw.size() < WINDOW_N:
		pw.resize(WINDOW_N)
		pv.resize(WINDOW_N)
		pa.resize(WINDOW_N)
	if rf.size() < WINDOW_N:
		rf.resize(WINDOW_N)
	slow_dt_s = slow_dt
	pw[slot] = pw_now
	pv[slot] = vel.length()
	pa[slot] = (vel - _wind_at(pos)).length()
	rf[slot] = bat.remaining_fraction()
	pn += 1
	# Effective Wh per full pack: nominal V x capacity over-states what the pack delivers (voltage sags under load,
	# Peukert), so once 3 percent is used it becomes the MEASURED energy per used fraction of this pack. Estimate.
	var used_f := 1.0 - bat.remaining_fraction()
	if used_f >= 0.03:
		pack_wh = (energy_ws - pack_e0_ws) / 3600.0 / used_f
	var home_d := Vector2(pos.x, pos.z).length()
	max_home = maxf(max_home, home_d)
	# track sample (camera flag is the one decided by the previous tick's state)
	var yaw: float = rig.nav.estimate()["yaw"]
	var eul := Basis(rb.orientation).get_euler(EULER_ORDER_YXZ)     # x pitch, y yaw, z roll
	track.append_array(PackedFloat64Array([pos.x, pos.z, pos.y, yaw, 1.0 if cam_on else 0.0, eul.z, eul.x]))
	if cam_on and _now() >= next_trigger_t - 0.01:
		_trigger(rb, eul)
	match phase:
		"takeoff":
			if _reserve_tripped(pos, home_d):
				return
			if pos.y >= float(p["height_m"]) - 0.5:
				_start_mission(pos)
		"mission":
			if agl_fn.is_valid() and t_phase > 5.0:
				var agl := pos.y - float(agl_fn.call(pos.x, pos.z))
				agl_min = minf(agl_min, agl)
				agl_max = maxf(agl_max, agl)
				agl_n += 1
			if _reserve_tripped(pos, home_d):
				return
			_mission_tick(pos)
		"rth":
			cam_on = false
			if home_d < 1.5 and sp_h < 1.0:
				_begin_descend(Vector2.ZERO)
		"descend":
			cam_on = false
			if alt_cmd <= 0.0 and pos.y < 0.3:
				_touchdown(pos)


func _reserve_tripped(pos: Vector3, home_d: float) -> bool:
	var rp := float(p["reserve_pct"])
	if rp <= 0.0:
		return false
	var need := rp / 100.0 * pack_wh + _e_home_wh(home_d, pos.y, Vector2(pos.x, pos.z))
	if _remaining_wh() <= need:
		warnings.append("RTH at reserve (t=%.0f s, pack %.0f %% left, %.0f m from home)" % [_now(), bat.remaining_fraction() * 100.0, home_d])
		rth_reason = "reserve"
		_begin_rth(pos)
		return true
	return false


func _begin_rth(pos: Vector3) -> void:
	rth_pred_wh = _e_home_wh(Vector2(pos.x, pos.z).length(), pos.y, Vector2(pos.x, pos.z))
	rth_e0_ws = energy_ws
	cam_on = false
	alt_goal = float(p["height_m"])
	if Vector2(pos.x, pos.z).length() <= 2.0:
		_begin_descend(Vector2.ZERO)
		return
	phase = "rth"
	t_phase = 0.0
	rig.nav.set_hold(Vector2(pos.x, pos.z))      # clears any path (set_track alone would let the old path take over again)
	rig.nav.set_track(Vector2(pos.x, pos.z), Vector2.ZERO, rth_mps, 0.0)


func _begin_descend(at_xz: Vector2) -> void:
	phase = "descend"
	t_phase = 0.0
	land_xz = at_xz
	alt_goal = 0.0
	rig.nav.set_hold(at_xz)


func _touchdown(pos: Vector3) -> void:
	var rec := bat.remaining_fraction() * 100.0
	last_reserve_left = rec
	home_error = Vector2(pos.x, pos.z).length()
	sortie_reports.append({"sortie": sorties, "flight_time_s": _now() - sortie_t0, "reserve_left_pct": rec,
		"pack_used_pct": 100.0 - rec, "home_error_m": home_error, "rth_predicted_wh": rth_pred_wh, "rth_actual_wh": (energy_ws - rth_e0_ws) / 3600.0, "ended": "completed" if mission_done else ("landed_at_reserve" if rth_reason != "" else "landed")})
	phase = "landed"
	# battery swap for a survey with lines left?
	if not mission_done and mission == Mission.SURVEY and next_chunk < chunks.size():
		if next_chunk == sortie_first_chunk:
			ended_by = "no_progress"
			warnings.append("no progress: the pack cannot fly even one line plus the way home; stopped")
			return
		if sorties < max_sorties:
			bat.used_mah = 0.0
			pack_e0_ws = energy_ws
			warnings.append("battery swapped before sortie %d (swap time not counted)" % (sorties + 1))
			rth_reason = ""
			_begin_sortie()
			return
		warnings.append("mission incomplete: %d of %d survey lines unflown after %d sorties" % [chunks.size() - next_chunk, chunks.size(), sorties])
		ended_by = "landed_at_reserve"
		return
	ended_by = "completed" if mission_done else ("landed_at_reserve" if rth_reason != "" else "completed")


func _complete(pos: Vector3) -> void:
	mission_done = true
	_begin_rth(pos)


# ---------------------------------------------------------------- missions
func _loop_points(n_laps: int) -> Array:
	var l := loop_side
	var pts: Array = [Vector2.ZERO]
	for _i in n_laps:
		pts.append(Vector2(0, -l))
		pts.append(Vector2(l, -l))
		pts.append(Vector2(l, 0))
		pts.append(Vector2.ZERO)
	return pts


func _start_mission(pos: Vector3) -> void:
	phase = "mission"
	t_phase = 0.0
	mission_started_t = _now()
	var here := Vector2(pos.x, pos.z)
	match mission:
		Mission.HOVER_ENDURANCE:
			rig.nav.set_hold(Vector2.ZERO)
		Mission.CRUISE_LOOP:
			var pts := _loop_points(laps if laps > 0 else 40)
			pts[0] = here
			rig.nav.set_path(pts, float(p["speed_mps"]), ACCEPT_M)
		Mission.RANGE_TEST:
			var hd := deg_to_rad(float(params_in.get("range_heading_deg", 0.0)))
			var far := here + Vector2(sin(hd), -cos(hd)) * 1.0e6
			rig.nav.set_track(here, far, float(p["speed_mps"]), float(p["speed_mps"]))
		Mission.FOLLOW_PATH:
			var pts2: Array = [here]
			var given: Variant = params_in.get("path", null)
			if given == null:
				var l := loop_side * 0.5
				given = [Vector2(0, -l), Vector2(l, -l), Vector2(l, 0), Vector2(0, 0)]
			for q in given:
				pts2.append(Vector2(q))
			rig.nav.set_path(pts2, float(p["speed_mps"]), ACCEPT_M)
		Mission.SURVEY:
			if not _survey_fit(pos, true):
				return
			_issue_survey_path(here)


func _mission_tick(pos: Vector3) -> void:
	match mission:
		Mission.HOVER_ENDURANCE:
			if hover_s > 0.0 and _now() - mission_started_t >= hover_s:
				_complete(pos)
		Mission.CRUISE_LOOP:
			if rig.nav.path_done():
				if laps > 0:
					_complete(pos)
				else:
					var pts := _loop_points(40)
					pts[0] = Vector2(pos.x, pos.z)
					rig.nav.set_path(pts, float(p["speed_mps"]), ACCEPT_M)
			cam_on = camera_on_always
		Mission.RANGE_TEST:
			cam_on = camera_on_always
		Mission.FOLLOW_PATH:
			cam_on = camera_on_always
			if rig.nav.path_done():
				mission_done = true
				if land_at_end:
					_begin_descend(Vector2(pos.x, pos.z))
				else:
					_begin_rth(pos)
		Mission.SURVEY:
			_survey_tick(pos)


## SR5.4: one camera trigger. Records the pose; the footprint is projected at the end of the run (see SurveyPhotos). The trigger
## clock is the 5 Hz tick, so a shot lands up to 0.2 s (1.6 m at 8 m/s) away from its ideal instant (ESTIMATED effect, stated).
func _trigger(rb: RigidBodyState, eul: Vector3) -> void:
	var q := rb.orientation
	if gimbal_stabilised:
		q = Quaternion(Basis.from_euler(Vector3(0.0, eul.y, 0.0), EULER_ORDER_YXZ))
	photos.append({"t": _now(), "pos": rb.position_m, "q": q, "vg": Vector2(rb.velocity_mps.x, rb.velocity_mps.z).length()})
	next_trigger_t = _now() + maxf(trigger_interval_s, 0.0)
	if next_trigger_t <= _now():
		next_trigger_t = _now() + 1.0 / SLOW_HZ


# ---------------------------------------------------------------- survey
func _prepare_survey() -> void:
	plan = SurveyPlanner.plan(polygon, camera, float(p["height_m"]), float(p["front_overlap"]),
		float(p["side_overlap"]), float(p["speed_mps"]))
	for w in plan["warnings"]:
		warnings.append("planner: " + String(w))
	if bool(plan["error"]):
		ended_by = "error"
		return
	if not params_in.has("trigger_interval_s"):
		trigger_interval_s = maxf(float(plan["shot_interval_s"]), camera.min_shot_interval_s)
	var wps: Array = plan["waypoints"]
	var cur: Array = []
	var lines_seen := 0
	var chunk_prev_end := Vector2.ZERO
	var i := 0
	var first := true
	while i < wps.size():
		var w: Dictionary = wps[i]
		cur.append(w)
		var closes := false
		if String(w["kind"]) == "line":
			lines_seen += 1
			if lines_seen % 2 == 0:
				if i + 1 < wps.size() and String(wps[i + 1]["kind"]) == "overrun":
					cur.append(wps[i + 1])
					i += 1
				closes = true
		i += 1
		if closes:
			var pts: Array = []
			var kinds: Array = []
			var lb := -1
			var seen := 0
			var len_line := 0.0
			var len_turn := 0.0
			var pp := chunk_prev_end if not first else Vector2.ZERO
			var past_first := false
			for c in cur:
				var q: Vector2 = c["p"]
				var kd := String(c["kind"])
				pts.append(q)
				kinds.append(kd)
				if kd == "line":
					seen += 1
					if seen == 2:
						lb = pts.size() - 1
				var dd := pp.distance_to(q)
				# the connector (turn arc or transit from the previous line's end) runs up to the first non-turn point
				if not past_first:
					len_turn += dd
				else:
					len_line += dd
				if kd != "turn":
					past_first = true
				pp = q
			chunk_prev_end = pp
			chunks.append({"pts": pts, "kinds": kinds, "line_b": lb, "len_line": len_line, "len_turn": len_turn, "end": pp})
			cur = []
			first = false
	if skip_line >= 0 and skip_line < chunks.size():
		chunks.remove_at(skip_line)
		warnings.append("DEBUG: survey line %d skipped" % skip_line)


## True when the next chunk (plus the way home from its end) fits above the reserve. On false: begins RTH.
func _survey_fit(pos: Vector3, at_start: bool) -> bool:
	if next_chunk >= chunks.size():
		return true
	var rp := float(p["reserve_pct"])
	if rp <= 0.0:
		return true
	var c: Dictionary = chunks[next_chunk]
	var spd := float(p["speed_mps"])
	var pwr: float = _mean_power(true)
	if pwr <= 0.0:
		pwr = _power_motion_or_hover() * 1.15
	var transit := 0.0
	if at_start:
		transit = Vector2(pos.x, pos.z).distance_to(Vector2(c["pts"][0]))
	var e_line := _sag_factor() * pwr * ((float(c["len_line"]) + transit) / spd + float(c["len_turn"]) / (spd * SurveyPlanner.TURN_SPEED_FACTOR)) / 3600.0
	var end: Vector2 = c["end"]
	var need := rp / 100.0 * pack_wh + e_line + _e_home_wh(end.length(), pos.y)
	if _remaining_wh() >= need:
		return true
	warnings.append("RTH: next line does not fit")
	rth_reason = "lookahead"
	_begin_rth(pos)
	return false


func _issue_survey_path(here: Vector2) -> void:
	var pts: Array = [here]
	path_kinds = ["start"]
	path_first = []
	path_line_b = []
	path_chunk0 = next_chunk
	for ci in range(next_chunk, chunks.size()):
		var c: Dictionary = chunks[ci]
		path_first.append(pts.size())
		for k in c["pts"].size():
			pts.append(c["pts"][k])
			path_kinds.append(c["kinds"][k])
		path_line_b.append(path_first[-1] + int(c["line_b"]))
	if pts.size() < 2:
		mission_done = true
		return
	evaluated_chunk = path_chunk0
	rig.nav.set_path(pts, float(p["speed_mps"]), ACCEPT_M)


func _survey_tick(pos: Vector3) -> void:
	if next_chunk >= chunks.size() and phase == "mission":
		pass
	var leg: int = rig.nav.leg_index()
	cam_on = false
	if next_chunk < chunks.size():
		var li: int = next_chunk - path_chunk0
		if li >= 0 and li < path_line_b.size():
			if leg >= path_line_b[li]:
				next_chunk += 1
				li += 1
			if li < path_first.size() and next_chunk > evaluated_chunk and leg >= path_first[li] and li > 0:
				evaluated_chunk = next_chunk
				if not _survey_fit(pos, false):
					return
	if leg + 1 < path_kinds.size() and path_kinds[leg] == "line" and path_kinds[leg + 1] == "line" and not rig.nav.path_done():
		cam_on = true
	if rig.nav.path_done():
		next_chunk = chunks.size()
		_complete(pos)


# ---------------------------------------------------------------- coverage
## Rasterises the swept camera footprint. track = TRACK_STRIDE floats per sample (x, z, y, heading, camera_on, roll, pitch).
## Returns {area_flown_m2, polygon_cells_m2, coverage_fraction, holes:[{area_m2, x, z}], hole_total_m2}.
static func coverage(trk: PackedFloat64Array, cam: CameraParams, poly: PackedVector2Array) -> Dictionary:
	var g := GRID_M
	var n := int(trk.size() / float(TRACK_STRIDE))
	var rects: Array = []
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	if poly.size() >= 3:
		for q in poly:
			bmin = Vector2(minf(bmin.x, q.x), minf(bmin.y, q.y))
			bmax = Vector2(maxf(bmax.x, q.x), maxf(bmax.y, q.y))
	var any_cam := false
	for i in n:
		if trk[i * TRACK_STRIDE + 4] < 0.5:
			continue
		any_cam = true
		var c := Vector2(trk[i * TRACK_STRIDE], trk[i * TRACK_STRIDE + 1])
		var h := trk[i * TRACK_STRIDE + 3]
		var fp := cam.footprint_m(trk[i * TRACK_STRIDE + 2])
		var fwd := Vector2(-sin(h), -cos(h)) * (fp.y * 0.5)
		var rgt := Vector2(cos(h), -sin(h)) * (fp.x * 0.5)
		var cs := [c - rgt - fwd, c + rgt - fwd, c + rgt + fwd, c - rgt + fwd]
		rects.append(cs)
		if poly.size() < 3:
			for q in cs:
				bmin = Vector2(minf(bmin.x, q.x), minf(bmin.y, q.y))
				bmax = Vector2(maxf(bmax.x, q.x), maxf(bmax.y, q.y))
	var out := {"area_flown_m2": 0.0, "polygon_cells_m2": 0.0, "coverage_fraction": 0.0, "holes": [], "hole_total_m2": 0.0}
	if poly.size() < 3 and not any_cam:
		return out
	var rows := int(ceil((bmax.y - bmin.y) / g)) + 1
	var open_lo := PackedFloat64Array()
	var open_hi := PackedFloat64Array()
	open_lo.resize(rows)
	open_hi.resize(rows)
	open_lo.fill(INF)
	open_hi.fill(-INF)
	var done: Array = []
	for _r in rows:
		done.append(PackedFloat64Array())
	for cs in rects:
		var ymin := INF
		var ymax := -INF
		for q in cs:
			ymin = minf(ymin, q.y)
			ymax = maxf(ymax, q.y)
		var j0 := maxi(0, int(ceil((ymin - bmin.y) / g - 0.5)))
		var j1 := mini(rows - 1, int(floor((ymax - bmin.y) / g - 0.5)))
		for j in range(j0, j1 + 1):
			var y := bmin.y + (j + 0.5) * g
			var lo := INF
			var hi := -INF
			for e in 4:
				var a: Vector2 = cs[e]
				var b: Vector2 = cs[(e + 1) % 4]
				if (a.y <= y) != (b.y <= y):
					var x := a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
					lo = minf(lo, x)
					hi = maxf(hi, x)
			if hi < lo:
				continue
			if lo <= open_hi[j] and hi >= open_lo[j]:
				open_lo[j] = minf(open_lo[j], lo)
				open_hi[j] = maxf(open_hi[j], hi)
			else:
				if open_hi[j] >= open_lo[j]:
					done[j].append(open_lo[j])
					done[j].append(open_hi[j])
				open_lo[j] = lo
				open_hi[j] = hi
	# integer cell ranges per row
	var covered_cells := 0
	var poly_cells := 0
	var nodes: Array = []                # {row, k0, k1}
	var row_nodes: Array = []
	for j in rows:
		var y := bmin.y + (j + 0.5) * g
		var iv: Array = []
		var d: PackedFloat64Array = done[j]
		for k in range(0, d.size(), 2):
			iv.append(Vector2(d[k], d[k + 1]))
		if open_hi[j] >= open_lo[j]:
			iv.append(Vector2(open_lo[j], open_hi[j]))
		iv.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cov: Array = []                 # int ranges Vector2i
		for v in iv:
			var k0 := int(ceil((v.x - bmin.x) / g - 0.5))
			var k1 := int(floor((v.y - bmin.x) / g - 0.5))
			if k1 < k0:
				continue
			if not cov.is_empty() and k0 <= cov[-1].y + 1:
				cov[-1] = Vector2i(cov[-1].x, maxi(cov[-1].y, k1))
			else:
				cov.append(Vector2i(k0, k1))
		var prs: Array = []
		if poly.size() >= 3:
			var xs: Array = []
			for e in poly.size():
				var a: Vector2 = poly[e]
				var b: Vector2 = poly[(e + 1) % poly.size()]
				if (a.y <= y) != (b.y <= y):
					xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			var m := 0
			while m + 1 < xs.size():
				var k0 := int(ceil((xs[m] - bmin.x) / g - 0.5))
				var k1 := int(floor((xs[m + 1] - bmin.x) / g - 0.5))
				if k1 >= k0:
					prs.append(Vector2i(k0, k1))
				m += 2
		var unc_here: Array = []
		var rn: Array = []
		if poly.size() >= 3:
			for pr in prs:
				poly_cells += pr.y - pr.x + 1
				var cursor: int = pr.x
				for cr in cov:
					if cr.y < cursor or cr.x > pr.y:
						continue
					var a0 := maxi(cr.x, pr.x)
					var a1 := mini(cr.y, pr.y)
					covered_cells += a1 - a0 + 1
					if a0 > cursor:
						unc_here.append(Vector2i(cursor, a0 - 1))
					cursor = a1 + 1
				if cursor <= pr.y:
					unc_here.append(Vector2i(cursor, pr.y))
		else:
			for cr in cov:
				covered_cells += cr.y - cr.x + 1
		for u in unc_here:
			nodes.append({"row": j, "k0": u.x, "k1": u.y})
			rn.append(nodes.size() - 1)
		row_nodes.append(rn)
	out["area_flown_m2"] = covered_cells * g * g
	out["polygon_cells_m2"] = poly_cells * g * g
	out["coverage_fraction"] = float(covered_cells) / float(poly_cells) if poly_cells > 0 else 0.0
	# holes: union-find over uncovered runs of adjacent rows
	var parent: Array = []
	for i in nodes.size():
		parent.append(i)
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for j in range(1, rows):
		for a in row_nodes[j]:
			for b in row_nodes[j - 1]:
				if nodes[a]["k0"] <= nodes[b]["k1"] and nodes[b]["k0"] <= nodes[a]["k1"]:
					var ra: int = find.call(a)
					var rb: int = find.call(b)
					if ra != rb:
						parent[ra] = rb
	var sums := {}
	for i in nodes.size():
		var r: int = find.call(i)
		var nd: Dictionary = nodes[i]
		var cnt: int = nd["k1"] - nd["k0"] + 1
		if not sums.has(r):
			sums[r] = {"cells": 0, "sx": 0.0, "sz": 0.0}
		sums[r]["cells"] += cnt
		sums[r]["sx"] += (bmin.x + ((nd["k0"] + nd["k1"]) * 0.5 + 0.5) * g) * cnt
		sums[r]["sz"] += (bmin.y + (nd["row"] + 0.5) * g) * cnt
	var holes: Array = []
	var total := 0.0
	for r in sums:
		var s: Dictionary = sums[r]
		var area: float = s["cells"] * g * g
		if area >= HOLE_MIN_M2:
			holes.append({"area_m2": area, "x": s["sx"] / s["cells"], "z": s["sz"] / s["cells"]})
			total += area
	holes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area_m2"] > b["area_m2"] or (a["area_m2"] == b["area_m2"] and a["x"] < b["x"]))
	out["holes"] = holes
	out["hole_total_m2"] = total
	return out


# ---------------------------------------------------------------- result
## SR3.1: the world's obstacles against the FLOWN track. Two thresholds, both ESTIMATED and in the result's
## warnings (not hidden): the aircraft counts as touching an obstacle inside COLLISION_RADIUS_M of its solid
## (a body of about a 5 inch quad plus prop), and as "close" inside CLEARANCE_M (a common 5 m visual-line rule of
## thumb, not a regulation). One warning per obstacle per kind, with the closest sample's position.
const COLLISION_RADIUS_M := 0.3
const CLEARANCE_M := 5.0

func _obstacle_warnings() -> void:
	if world != null:
		for m in world.world_warnings():
			warnings.append(m)
	if world == null or world.obstacles.is_empty() or track.size() < TRACK_STRIDE:
		return
	var n := int(track.size() / float(TRACK_STRIDE))
	var oi := 0
	for ob in world.obstacles:
		var hit_at := -1
		var near_at := -1
		for i in n:
			var c := Vector3(track[i * TRACK_STRIDE], track[i * TRACK_STRIDE + 2], track[i * TRACK_STRIDE + 1])   # track is x, z, y, yaw, cam
			if hit_at < 0 and ob.intersects_sphere(c, COLLISION_RADIUS_M):
				hit_at = i
				break
			if near_at < 0 and ob.intersects_sphere(c, CLEARANCE_M):
				near_at = i
		if hit_at >= 0:
			warnings.append("obstacle collision: the flown path comes within %.1f m of obstacle %d (%s) at (%.0f, %.0f), height %.0f m (thresholds ESTIMATED)" % [COLLISION_RADIUS_M, oi, String(ob.kind), track[hit_at * TRACK_STRIDE], track[hit_at * TRACK_STRIDE + 1], track[hit_at * TRACK_STRIDE + 2]])
		elif near_at >= 0:
			warnings.append("obstacle clearance: the flown path comes within %.0f m of obstacle %d (%s) at (%.0f, %.0f), height %.0f m (threshold ESTIMATED)" % [CLEARANCE_M, oi, String(ob.kind), track[near_at * TRACK_STRIDE], track[near_at * TRACK_STRIDE + 1], track[near_at * TRACK_STRIDE + 2]])
		oi += 1


func _result(field_out: Dictionary, build: Build, scale: float, cond: Conditions) -> Dictionary:
	_obstacle_warnings()
	var n := int(track.size() / float(TRACK_STRIDE))
	var cov := coverage(track, camera, polygon if mission == Mission.SURVEY else PackedVector2Array())
	var flight_t := _now() if ended_by != "not_flown" else 0.0
	var holes_out: Array = []
	if mission == Mission.SURVEY:
		for h in cov["holes"]:
			holes_out.append(h)
		if not (cov["holes"] as Array).is_empty():
			var ph: Array = cov["holes"]
			warnings.append("coverage hole: %d uncovered cluster(s) of at least %.0f m2, total %.0f m2, largest %.0f m2 near (%.0f, %.0f)" % [ph.size(), HOLE_MIN_M2, cov["hole_total_m2"], ph[0]["area_m2"], ph[0]["x"], ph[0]["z"]])
		for h in plan.get("holes", []):
			holes_out.append(h)
	var shots_rep := SurveyPhotos.report(photos, camera, polygon if mission == Mission.SURVEY else PackedVector2Array(), agl_fn, required_photos, blur_limit_px, maxf(trigger_interval_s, 0.2))
	var blur: Dictionary = shots_rep["blur"]
	if int(blur["flagged"]) > 0:
		warnings.append("motion blur: %d of %d photos blur by more than %.2f px (worst %.2f px at %.2f s exposure; limit ESTIMATED, model ignores rotation)" % [blur["flagged"], shots_rep["images"], blur["limit_px"], blur["max_px"], blur["exposure_s"]])
	if mission == Mission.SURVEY:
		for h in shots_rep["holes"]:
			holes_out.append(h)
		if not (shots_rep["holes"] as Array).is_empty():
			var sh: Array = shots_rep["holes"]
			warnings.append("photo gaps: %d cluster(s) of at least %.0f m2 seen by fewer than %d photos, largest %.0f m2 near (%.0f, %.0f)" % [sh.size(), HOLE_MIN_M2, required_photos, sh[0]["area_m2"], sh[0]["x"], sh[0]["z"]])
	var energy_wh := energy_ws / 3600.0
	var ok: bool = ended_by in NORMAL_ENDINGS and not (mission == Mission.SURVEY and next_chunk < chunks.size())
	var polygon_area := SurveyPlanner.polygon_area(polygon) if mission == Mission.SURVEY else 0.0
	var params_out := {"fields": field_out, "capacity_scale": scale, "max_sorties": max_sorties,
		"hover_s": hover_s, "laps": laps, "loop_side_m": loop_side, "camera_on": camera_on_always,
		"rth_speed_mps": rth_mps, "nominal_pack_wh": nominal_pack_wh, "effective_pack_wh": pack_wh, "climb_rate_mps": Mission.CLIMB_RATE_MPS, "descent_rate_mps": Mission.DESCENT_RATE_MPS,
		"reserve_rule": "remaining_Wh <= reserve_pct/100*pack_Wh + energy_to_home (x1.1); reserve_pct 0 = no RTH",
		"camera": {"sensor_w_mm": camera.sensor_w_mm, "sensor_h_mm": camera.sensor_h_mm, "focal_mm": camera.focal_mm, "tag": camera.tag}}
	var r := {
		"schema_version": MissionResult.SCHEMA_VERSION, "mission": mission, "class_id": class_id,
		"build_fingerprint": build.fingerprint(), "seed": seed_value,
		"params": params_out,
		"conditions": {"wind_speed_mps": cond.wind_speed_mps, "wind_from_deg": cond.wind_from_deg, "gust_mps": cond.gustiness_mps,
			"capacity_scale": scale, "dt": dt},
		"versions": {"model": MissionResult.MODEL_VERSION},
		"flight_time_s": flight_t, "distance_m": distance_m if flight_t > 0.0 else 0.0,
		"area_flown_m2": cov["area_flown_m2"], "polygon_area_m2": polygon_area,
		"coverage_fraction": cov["coverage_fraction"] if mission == Mission.SURVEY else 0.0,
		"energy_wh": energy_wh, "wh_per_min": energy_wh / (flight_t / 60.0) if flight_t > 0.0 else 0.0,
		"reserve_left_pct": last_reserve_left if ended_by in ["completed", "landed_at_reserve"] else bat.remaining_fraction() * 100.0,
		"home_error_m": home_error, "max_distance_from_home_m": max_home,
		"sorties": sorties if ended_by != "not_flown" else 0,
		"warnings": warnings, "ended_by": ended_by, "completed": ok, "track_samples": n,
		"holes": holes_out, "sortie_reports": sortie_reports, "photos": shots_rep,
		"_track": track, "_photos": photos,
	}
	if mission == Mission.RANGE_TEST:
		r["distance_out_m"] = max_home
	if world != null:
		r["world"] = {"id": world.world_id, "name": world.world_name, "version": World.VERSION, "fingerprint": world.fingerprint(),
			"origin_lat": world.origin_lat, "origin_lon": world.origin_lon, "elevation_m": world.origin_elevation_m,
			"sun_elevation_deg": world.sun().get("elevation_deg"), "ground": "heightfield" if world.terrain.heightfield != null else String(world.terrain.shape)}
		r["terrain_follow"] = {"enabled": terrain_fn.is_valid(), "agl_target_m": float(p["height_m"]), "agl_min_m": agl_min if agl_n > 0 else NAN,
			"agl_max_m": agl_max if agl_n > 0 else NAN, "samples": agl_n}
		if mission == Mission.SURVEY and world.polygon.size() >= 6 and not params_in.has("polygon"):
			r["polygon_area_geodesic_m2"] = world.area_m2()
	if mission == Mission.SURVEY and not plan.is_empty():
		r["survey"] = {"line_count": plan["line_count"], "lines_in_queue": chunks.size(), "lines_flown": mini(next_chunk, chunks.size()),
			"spacing_m": plan["spacing_m"], "planned_path_m": plan["path_length_m"], "planned_time_s": plan["expected_time_s"],
			"shot_interval_s": plan["shot_interval_s"], "line_angle_deg": plan["line_angle_deg"]}
	MissionResult.add_figures(r)
	if mission == Mission.SURVEY:
		MissionResult.add_survey_economics(r, plan, float(params_in.get("farm_acres", 0.0)))
	return r


# ---------------------------------------------------------------- standard test pack
func _run_pack(params: Dictionary, base: Dictionary) -> Dictionary:
	var parts: Array = []
	var specs := [[Mission.HOVER_ENDURANCE, "hover"], [Mission.CRUISE_LOOP, "cruise"], [Mission.SURVEY, "survey"]]
	var tot_t := 0.0
	var tot_d := 0.0
	var tot_e := 0.0
	var area := 0.0
	var poly_area := 0.0
	var cov_fr := 0.0
	var all_ok := true
	var warn: Array = []
	var sorts := 0
	var maxh := 0.0
	var over: Dictionary = params.get("fields", {})
	for s in specs:
		var sub := params.duplicate(true)
		sub["mission"] = s[0]
		sub["fields"] = over.duplicate()
		if s[0] == Mission.HOVER_ENDURANCE:
			sub["hover_s"] = float(params.get("hover_s", Mission.DEFAULT_HOVER_S))
			sub["fields"]["reserve_pct"] = float(over.get("reserve_pct", base["fields"]["reserve_pct"]["value"]))
		elif s[0] == Mission.CRUISE_LOOP:
			sub["laps"] = int(params.get("laps", Mission.DEFAULT_LAPS))
		else:
			if params.has("survey_height_m"):
				sub["fields"]["height_m"] = float(params["survey_height_m"])
			if params.has("survey_speed_mps"):
				sub["fields"]["speed_mps"] = float(params["survey_speed_mps"])
		var rr := MissionRunner.run(sub)
		var part := rr.duplicate()
		part["part"] = String(s[1])
		parts.append(part)
		tot_t += float(rr["flight_time_s"])
		tot_d += float(rr["distance_m"])
		tot_e += float(rr["energy_wh"])
		sorts += int(rr["sorties"])
		maxh = maxf(maxh, float(rr["max_distance_from_home_m"]))
		all_ok = all_ok and bool(rr["completed"])
		for w in rr["warnings"]:
			warn.append("%s: %s" % [s[1], w])
		if s[0] == Mission.SURVEY:
			area = rr["area_flown_m2"]
			poly_area = rr["polygon_area_m2"]
			cov_fr = rr["coverage_fraction"]
	var r := {
		"schema_version": MissionResult.SCHEMA_VERSION, "mission": Mission.TEST_PACK, "class_id": class_id,
		"build_fingerprint": parts[0]["build_fingerprint"], "seed": seed_value,
		"params": {"note": "each part flies on a fresh pack (swapped between parts, swap time not counted); totals are sums; height/speed edits apply to hover and cruise, survey_height_m / survey_speed_mps to the survey",
			"parts_params": [parts[0]["params"], parts[1]["params"], parts[2]["params"]]},
		"conditions": parts[0]["conditions"], "versions": {"model": MissionResult.MODEL_VERSION},
		"flight_time_s": tot_t, "distance_m": tot_d, "area_flown_m2": area, "polygon_area_m2": poly_area,
		"coverage_fraction": cov_fr, "energy_wh": tot_e, "wh_per_min": tot_e / (tot_t / 60.0) if tot_t > 0.0 else 0.0,
		"reserve_left_pct": parts[2]["reserve_left_pct"], "home_error_m": parts[2]["home_error_m"],
		"max_distance_from_home_m": maxh, "sorties": sorts, "warnings": warn,
		"ended_by": "completed" if all_ok else "failed_part", "completed": all_ok, "track_samples": 0, "parts": parts,
	}
	var tsum := 0
	for pt in parts:
		tsum += int(pt["track_samples"])
	r["track_samples"] = tsum
	MissionResult.add_figures(r)
	return r
