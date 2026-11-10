class_name NavPilot
extends RefCounted
## SR4 navigation core. It sits ABOVE the real FlightController (ANGLE mode): every tick it turns a
## position / altitude / heading goal into an `rc` dict {roll, pitch, yaw, throttle} and returns
## `fc.update(orientation, gyro, rc, dt)`. It never writes a motor command itself and never bypasses
## the flight law.
##
## ESTIMATE = SIM TRUTH FOR NOW (SR4 placeholder; a real estimator comes later). `estimate()` is the
## ONE place the pilot reads the world: position, velocity and heading from core.rigid_body, the steady
## wind from core.wind (steady part only, no gust). Replace that method and nothing else changes.
## Battery state for the hover feed-forward is read from core.powertrain.battery (also truth).
##
## Frames: Y up, forward at yaw 0 is -Z, north = -Z, east = +X (src/sim/wind.gd). Yaw is rotation about +Y.
##
## CASCADE (all gains are TIME CONSTANTS, none is tuned per class)
##  1. position -> velocity target: v = P*(pos error), P = 1/POS_TAU_S, capped by the speed limit.
##  2. velocity -> horizontal acceleration: a = (v err)/VEL_TAU_S + I. The I term is the "wind correction"
##     (a world-frame acceleration that learns the steady drag); `wind_correction` off removes it AND the crab.
##  3. acceleration -> tilt = atan(a/g), clamped to `tilt_limit_deg` (default 25), mapped to the roll / pitch
##     stick through the angle-mode scale (MAX_ANGLE 30 deg at full stick).
##  The attitude loop under it closes in about 0.1-0.15 s on every class (RateTune holds the inner tau constant,
##  see angle_mode_controller.gd), so VEL_TAU_S (0.4) is about three times that and POS_TAU_S (1.2) three times VEL_TAU_S:
##  each outer loop is several times slower than the one beneath it (0.6 / 1.8 left a 3 m corner overshoot on the 100 m square).
##  ALTITUDE: height error -> vertical-speed target (1/ALT_TAU_S, capped) -> throttle = hover_ff / cos(tilt)
##  + hover_ff * (a_z)/(2 g) with a_z = P+I on vertical-speed error (thrust ~ throttle^2, so dT/T = 2 dthr/thr).
##  HEADING: yaw stick is a RATE command (rc.yaw x 800 deg/s); rate = P*(yaw error), capped at MAX_YAW_RATE.
##
## PATH TURN RULE (set_path): the commanded ground speed along a leg is
##   v = min(speed, sqrt(turn_speed^2 + 2*a_brake*d))   with d the distance left to the next waypoint,
## i.e. a bounded constant deceleration a_brake down to `turn_speed` AT the corner, then the next leg starts
## at once (when within accept_radius, or past it along the leg) and accelerates away. The last waypoint
## uses end speed 0 and the pilot then holds it. The corner is cut by at most about accept_radius.

enum HeadingMode { FIXED, COURSE, CRAB }

const G := 9.81
const MAX_ANGLE_RAD := 0.5235988        # flight_law.rs MAX_ANGLE_RAD, 30 deg at full stick
const MAX_RATE_RAD_S := 13.962634       # RateModeController.MAX_RATE_RAD_S, yaw stick scale
const POS_TAU_S := 1.2
const VEL_TAU_S := 0.4
const VEL_I_TAU_S := 3.0                # integral time of the velocity loop (wind correction)
const ALT_TAU_S := 1.2
const VZ_TAU_S := 0.33                  # vertical-speed loop: a_z = verr / VZ_TAU_S
const VZ_I_TAU_S := 1.5
const YAW_TAU_S := 0.5
const MAX_YAW_RATE_RAD_S := 2.0
const FF_REFRESH_S := 1.0
## Thrust-margin tilt cap (ESTIMATED shape): above THR_SOFT of the commanded collective the allowed tilt fades linearly to zero at
## THR_HARD, so attitude control keeps differential headroom. The mapper flipped in 20 mph gusts: at a line-end run-out it leaned
## 25 degrees into a 17 m/s headwind, the rotors unloaded, the aircraft sank, the altitude loop pushed the collective to the stops
## and the pitch loop lost its differential (CropMerge, 2026-11-11). Never binds below 0.55, which no ordinary flight reaches.
const THR_SOFT := 0.55
const THR_HARD := 0.85
const CRAB_MIN_AIRSPEED := 1.0
const XTRACK_TAU_S := 1.2               # cross-track error -> lateral velocity, same as POS_TAU_S

var fc: FlightController
var core: DroneCore
var build: Build

var tilt_limit_deg := 25.0
var speed_limit_mps := 15.0
var climb_limit_mps := 3.0
## Master switch for the wind correction: the velocity-loop integrator and the crab heading.
var wind_correction := true
## Terrain feed-forward (AGL mode): add the ground's rate of rise along the velocity to the climb target.
var terrain_feed_forward := true
## Throttle trim integrator of the altitude loop (off = P-only on vertical speed, hover feed-forward only).
var altitude_integrator := true
## Calibration of the build's hover-throttle model (1.0 = trust it). A labelled, editable guess; the integrator trims the rest.
var hover_ff_scale := 1.0
## Braking used by the speed profile of tracks and paths, m/s^2. Default derived in _init from the tilt limit.
var a_brake_mps2 := 1.5
var turn_speed_mps := 3.0

var heading_mode: int = HeadingMode.FIXED
var heading_target := 0.0               # FIXED mode yaw, rad

# horizontal goal
var _mode := "hold"                     # hold | track
var _hold := Vector2.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _dir := Vector2(0, -1)
var _len := 0.0
var _speed := 5.0
var _end_speed := 0.0
var _vel_i := Vector2.ZERO              # world-frame (x, z) acceleration learned against the wind, m/s^2

# vertical goal
var _alt_agl := false
var _alt_msl := 0.0
var _agl_h := 0.0
var _terrain: Callable
var _thr_ff := 0.4
var _ff_age := 0.0
var _thr_trim := 0.0                    # integrator of the vertical-speed loop, in throttle units
var _target_alt := 0.0                  # the height currently being chased (read-out)

# path
var _path: Array = []
var _path_i := 0
var _path_speed := 5.0
var _accept := 2.0

var last_rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
var _arrived_flag := false


func _init(p_build: Build, p_core: DroneCore, p_fc: FlightController) -> void:
	build = p_build
	core = p_core
	fc = p_fc
	_thr_ff = build.hover_throttle_for(core.powertrain.battery) * hover_ff_scale
	a_brake_mps2 = 0.4 * G * tan(deg_to_rad(tilt_limit_deg))
	var e := estimate()
	_hold = Vector2(e["pos"].x, e["pos"].z)
	_alt_msl = e["pos"].y
	heading_target = e["yaw"]


## ESTIMATE = SIM TRUTH FOR NOW (SR4 placeholder; a real estimator comes later).
func estimate() -> Dictionary:
	var rb := core.rigid_body
	var f := rb.orientation * Vector3(0, 0, -1)
	return {
		"pos": rb.position_m, "vel": rb.velocity_mps,
		"yaw": atan2(-f.x, -f.z),
		"wind": core.wind.mean_at(maxf(rb.position_m.y - core.ground_y_m, 0.0)) if core.wind != null else Vector3.ZERO,
		"source": "sim_truth",
	}


# ---------------------------------------------------------------- goals
func set_hold(pos_xz: Vector2, reset_wind_estimate: bool = false) -> void:
	_mode = "hold"
	_hold = pos_xz
	_path.clear()
	_arrived_flag = false
	if reset_wind_estimate:
		_vel_i = Vector2.ZERO


func set_altitude_msl(y: float) -> void:
	_alt_agl = false
	_alt_msl = y


func set_altitude_agl(h: float, terrain_fn: Callable) -> void:
	_alt_agl = true
	_agl_h = h
	_terrain = terrain_fn


## Follow the line from -> to at `speed`, ending at `end_speed` at `to`.
func set_track(from_xz: Vector2, to_xz: Vector2, speed: float, end_speed: float = 0.0) -> void:
	_mode = "track"
	_from = from_xz
	_to = to_xz
	_len = from_xz.distance_to(to_xz)
	_dir = (to_xz - from_xz) / maxf(_len, 1e-6)
	_speed = speed
	_end_speed = end_speed
	_arrived_flag = false


## Constant-speed path through the points, starting from `waypoints[0]` -> [1] etc. See the turn rule above.
func set_path(waypoints: Array, speed: float, accept_radius: float = 2.0) -> void:
	_path = waypoints.duplicate()
	_path_speed = speed
	_accept = accept_radius
	_path_i = 0
	_start_leg(0)


func _start_leg(i: int) -> void:
	_path_i = i
	var last := i >= _path.size() - 2
	set_track(_path[i], _path[i + 1], _path_speed, 0.0 if last else turn_speed_mps)
	_arrived_flag = false


func set_heading_mode(mode: int, fixed_yaw_rad: float = NAN) -> void:
	heading_mode = mode
	if not is_nan(fixed_yaw_rad):
		heading_target = fixed_yaw_rad


# ---------------------------------------------------------------- read-outs
## Signed distance to the right of the current track (right of travel positive), m.
func cross_track_error() -> float:
	if _mode != "track":
		return 0.0
	var p := _xz(estimate()["pos"]) - _from
	return p.x * -_dir.y + p.y * _dir.x


func along_track_distance() -> float:
	if _mode != "track":
		return 0.0
	return (_xz(estimate()["pos"]) - _from).dot(_dir)


func track_length() -> float:
	return _len


func leg_index() -> int:
	return _path_i


func target_altitude() -> float:
	return _target_alt


func arrived(radius: float = 2.0) -> bool:
	var e := estimate()
	var goal := _hold if _mode == "hold" else _to
	if _path.size() > 0 and _path_i < _path.size() - 2:
		return false
	return _xz(e["pos"]).distance_to(goal) <= radius


func path_done() -> bool:
	return _path.size() > 0 and _arrived_flag


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ---------------------------------------------------------------- the tick
func command(dt: float) -> Dictionary:
	var e := estimate()
	var pos: Vector3 = e["pos"]
	var vel: Vector3 = e["vel"]
	var yaw: float = e["yaw"]
	var p2 := _xz(pos)
	var v2 := _xz(vel)

	# --- path bookkeeping: advance to the next leg
	if _path.size() > 0 and _mode == "track":
		var along := (p2 - _from).dot(_dir)
		if p2.distance_to(_to) <= _accept or along >= _len:
			if _path_i < _path.size() - 2:
				_start_leg(_path_i + 1)
			else:
				_arrived_flag = true
				var end: Vector2 = _to
				var keep := _path.duplicate()
				set_hold(end)
				_path = keep
				_arrived_flag = true

	# --- horizontal velocity target
	var v_target := Vector2.ZERO
	if _mode == "hold":
		v_target = (_hold - p2) / POS_TAU_S
	else:
		var rel := p2 - _from
		var along := rel.dot(_dir)
		var xt := rel.x * -_dir.y + rel.y * _dir.x           # right of travel positive
		var left := _len - along
		var v_along := minf(_speed, sqrt(_end_speed * _end_speed + 2.0 * a_brake_mps2 * maxf(left, 0.0)))
		if left <= 0.0:
			v_along = 0.0
		var right_n := Vector2(-_dir.y, _dir.x)
		v_target = _dir * v_along - right_n * (xt / XTRACK_TAU_S)
	if v_target.length() > speed_limit_mps:
		v_target = v_target.normalized() * speed_limit_mps

	# --- velocity loop -> horizontal acceleration
	# Thrust-margin cap on the tilt, from the collective this loop commanded on the previous tick.
	var thr_room := clampf((THR_HARD - float(last_rc["throttle"])) / (THR_HARD - THR_SOFT), 0.0, 1.0)
	var a_max := G * tan(deg_to_rad(tilt_limit_deg) * thr_room)
	var verr := v_target - v2
	if wind_correction:
		var i_max := 0.6 * a_max
		_vel_i += verr * (dt / (VEL_TAU_S * VEL_I_TAU_S))
		if _vel_i.length() > i_max:
			_vel_i = _vel_i.normalized() * i_max
	else:
		_vel_i = Vector2.ZERO
	var a_cmd := verr / VEL_TAU_S + _vel_i
	if a_cmd.length() > a_max:
		a_cmd = a_cmd.normalized() * a_max

	# --- body frame stick mapping. fwd = (-sin y, -cos y), right = (cos y, -sin y)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var a_f := a_cmd.dot(fwd)
	var a_r := a_cmd.dot(right)
	# nose DOWN (negative pitch) accelerates forward; right side down (positive roll) accelerates right
	var rc_pitch := -atan(a_f / G) / MAX_ANGLE_RAD
	var rc_roll := atan(a_r / G) / MAX_ANGLE_RAD
	var tilt := atan(a_cmd.length() / G)

	# --- altitude
	_ff_age += dt
	if _ff_age >= FF_REFRESH_S:
		_ff_age = 0.0
		_thr_ff = build.hover_throttle_for(core.powertrain.battery) * hover_ff_scale
	var vz_ff := 0.0
	var target := _alt_msl
	if _alt_agl:
		var here: float = _terrain.call(pos.x, pos.z)
		target = here + _agl_h
		if terrain_feed_forward:
			var ahead := p2 + v2 * 0.25
			vz_ff = (float(_terrain.call(ahead.x, ahead.y)) - here) / 0.25
	_target_alt = target
	var vz_t := clampf((target - pos.y) / ALT_TAU_S, -climb_limit_mps, climb_limit_mps) + vz_ff
	var vz_err := vz_t - vel.y
	# The feed-forward is the build's own model of hover; the integrator is a throttle TRIM on top of it (the model is
	# a few to 20 percent off the sim, and the pack sags), and the loop gain scales with the throttle actually in use.
	var hover_est := maxf(_thr_ff + _thr_trim, 0.05)
	if altitude_integrator:
		_thr_trim = clampf(_thr_trim + hover_est * vz_err * dt / (2.0 * G * VZ_TAU_S * VZ_I_TAU_S), -0.6 * _thr_ff, 0.6 * _thr_ff)
	var a_z := vz_err / VZ_TAU_S
	var thr := hover_est / cos(minf(tilt, deg_to_rad(40.0))) + hover_est * a_z / (2.0 * G)

	# --- heading
	var want_yaw := _heading_goal(e, v2)
	var yerr := wrapf(want_yaw - yaw, -PI, PI)
	var yrate := clampf(yerr / YAW_TAU_S, -MAX_YAW_RATE_RAD_S, MAX_YAW_RATE_RAD_S)
	var rc_yaw := -yrate / MAX_RATE_RAD_S     # measured: +yaw stick turns CLOCKWISE seen from above (negative yaw about +Y)

	last_rc = {"roll": clampf(rc_roll, -1.0, 1.0), "pitch": clampf(rc_pitch, -1.0, 1.0),
		"yaw": clampf(rc_yaw, -1.0, 1.0), "throttle": clampf(thr, 0.0, 1.0)}
	return fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, last_rc, dt)


var _last_goal := NAN


func _heading_goal(e: Dictionary, v2: Vector2) -> float:
	var mode := heading_mode
	if mode == HeadingMode.CRAB and not wind_correction:
		mode = HeadingMode.COURSE          # no crab without wind correction
	if is_nan(_last_goal):
		_last_goal = e["yaw"]
	match mode:
		HeadingMode.FIXED:
			_last_goal = heading_target
		HeadingMode.COURSE:
			var d := _dir if _mode == "track" else v2
			if d.length() > 0.5:
				_last_goal = atan2(-d.x, -d.y)
		HeadingMode.CRAB:
			var w: Vector3 = e["wind"]
			var air := v2 - Vector2(w.x, w.z)
			if air.length() > CRAB_MIN_AIRSPEED:
				_last_goal = atan2(-air.x, -air.y)
	return _last_goal
