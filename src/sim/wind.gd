class_name Wind
extends RefCounted
## The air itself moves. A steady offset plus a seeded gust process, both authored by the
## builder's own `Conditions` (design §4.3) — `Wind` reads that set, it never writes one:
## `Sim authors nothing` (design §6) is a global constraint of this plan and `Wind` is where it
## first has anything to write, so this class is the guard for it.
##
## The steady half is a constant vector for the object's lifetime — `Conditions` is a snapshot the
## builder picked before flying, not something Sim watches for edits mid-flight. The gust half is a
## first-order stochastic process, shaped exactly like `src/sim/gyro.gd`'s sensor noise: white
## noise through a one-pole filter. Built the same way for the same reason gyro.gd states — an
## unseeded global RNG would make every test in this repo that touches the flight loop
## irreproducible, which is a worse defect than having no noise at all.

## AN ALIAS, NOT A NUMBER. The settling time is a field of the weather the builder authors, so it
## lives on `Conditions` beside `gustiness_mps` and is re-exported here under the name every
## caller already spells. Sim authors nothing, and that includes the constants it flies at.
##
## It is still a labelled guess with an editable field (`Conditions.DEFAULT_GUST_TAU_S` says why
## and what it is). Nothing else here is free: the gust amplitude is the builder's own figure.
##
## `p_gust_tau_s` below stays a DEFAULTED ARGUMENT because the test suite drives this process at
## chosen time constants — but a production caller must pass `p_conditions.gust_tau_s`, and the
## one that matters does, through `Main.make_wind()`. A bare `Wind.new(conditions)` flies at the
## default whatever the builder typed, which is the defect that made the Field room's "Gust
## settle" field a dial with no wire.
## ---------------------------------------------------------------------------
## SR2: THE WIND NOW HAS A PROFILE, A SPECTRUM AND A SHAPE IN SPACE
## ---------------------------------------------------------------------------
##
## Model DRYDEN (default) replaces the isotropic first-order gust; FIRST_ORDER is kept as the legacy
## fallback (the plan's "first-order gust stays as a fallback") and is bit-identical to the old class.
##
## 1. MEAN WIND vs HEIGHT, log law (neutral surface layer):  U(z) = U_ref * ln(z/z0) / ln(z_ref/z0).
##    `Conditions.wind_speed_mps` is the wind at `wind_ref_height_m` (10 m by default: the
##    height weather reports quote). z0 is the surface roughness length, per `Roughness` below. The
##    law is valid from a few z0 up to roughly 100-200 m; z is clamped to [2 z0, 200 m].
##    Source: Stull, Meteorology for Scientists and Engineers (2000) ch. 9 / Wieringa (1992) for z0.
##
## 2. TURBULENCE, Dryden, MIL-F-8785C Sec. 3.7.3 / MIL-HDBK-1797 (low-altitude form, h in feet,
##    10 ft < h < 1000 ft, clamped to that range):
##        Lw = h,   Lu = Lv = h / (0.177 + 0.000823 h)^1.2
##        sigma_u = sigma_v = sigma_w / (0.177 + 0.000823 h)^0.4,   sigma_w = 0.1 * W20
##    (W20 = mean wind at 20 ft). Spectra:  Hu = su sqrt(2 Lu/(pi V)) / (1 + Lu s / V),
##    Hv,w = s sqrt(L/(pi V)) (1 + sqrt3 L s / V) / (1 + L s / V)^2.
##    MIL uses the aircraft's airspeed for V. A hovering multirotor has no airspeed, so V here is the
##    speed the frozen field is carried past a fixed point: the mean wind at that height (Taylor),
##    floored at V_MIN_MPS (ESTIMATED, 1 m/s: keeps a dead-calm gusty day finite).
##    `Conditions.gustiness_mps` is the builder's figure for sigma_u AT THE REFERENCE HEIGHT; sigma_w
##    follows from the MIL ratio, so the three axes are anisotropic (sigma_w about half of sigma_u at 10 m).
##    `Wind.mil_gustiness_mps()` gives the MIL value tied to wind speed (0.1 * W20).
##    `gust_tau_s` (the old settle time) now scales every length scale by gust_tau_s / 2.5.
##
## 3. SPACE, frozen turbulence (Taylor): the field is carried downwind at the local mean speed U.
##    Two seeded streams (A, B) are generated; a point at along-wind coordinate xi reads them
##    xi / U seconds in the past, and a point at crosswind coordinate eta mixes them by the angle
##    theta = 1.19 eta / Lu, so the correlation between two crosswind points is cos(delta theta), 0.37 at one Lu.
##    Four height bins (3, 10, 30, 100 m) are filtered once and interpolated in log height, so the
##    whole field costs 40 filter states at 100 Hz, not per query point.
##
## ---------------------------------------------------------------------------
## R1.6: DISCRETE 1-COSINE GUST AND OBSTACLE WAKE
## ---------------------------------------------------------------------------
##
## DISCRETE GUST (MIL-HDBK-1797 / MIL-F-8785C "1-cosine"): v(s) = A/2 (1 - cos(pi s / d)) for 0 <= s <= 2d, where s is the
## distance behind the gust front and d the gust length (the ramp). The front is carried downwind at the local mean speed
## (frozen turbulence, Taylor), so a point at along-wind coordinate xi sees s = U (t - t0) - xi. The gust adds to the wind
## velocity along the downwind, crosswind or vertical axis. `add_discrete_gust()`; none by default.
##
## OBSTACLE WAKE / SHADOW (`set_obstacles()`, off when the list is empty). In the lee of an obstacle of height H the mean wind
## is reduced and the turbulence raised, fading linearly to nothing at WAKE_LENGTH_HEIGHTS * H downwind of the lee face.
## The numbers are LABELLED ESTIMATES in the spirit of wind-engineering wake surveys (typical cavity/wake lengths 5-10 H),
## not a CFD result: WAKE_LENGTH_HEIGHTS = 7.5 (mid of 5-10), WAKE_DEFICIT = 0.7 of the free mean at the lee face,
## WAKE_TI = 0.3 (wake turbulence sigma as a fraction of the free mean wind at the lee face), lateral spread 0.1 per unit
## downwind distance either side of the obstacle's own width, vertical extent H + 0.1 x, edges tapering over 0.5 H.
## Shape: s = (1 - x/L) times the lateral and vertical tapers; mean x (1 - deficit s); sigma_wake = TI s U_free, taken from
## the same frozen Dryden unit field (so it is seeded, advected and spatially correlated like the rest of the turbulence).
## The obstacle's footprint is its axis-aligned box (`Obstacle.aabb()`), so a yawed obstacle shadows its bounding box.
##
## Everything is a function of the seed (own RandomNumberGenerator); `reset()` re-seeds.

enum Model { DRYDEN, FIRST_ORDER }

## Surface roughness length z0, metres. Davenport-Wieringa classification, Wieringa (1992), "Updating the
## Davenport roughness classification", J. Wind Eng. Ind. Aerodyn. 41-44: class 1 sea 0.0002, class 2 smooth
## (mud flats, snow, beaches) 0.005, class 3 open (flat, grass, few obstacles) 0.03, class 4 roughly open (low
## crops) 0.10, class 5 rough (high crops, scattered obstacles) 0.25, class 6 very rough (parkland, bushes,
## orchards) 0.5. RE-VERIFIED 2026-11-10 (SR2.1) against the table reproduced at
## https://en.wikipedia.org/wiki/Roughness_length (values unchanged; an earlier version of this comment had the
## class NUMBERS shifted by one, the values were right). Values are published CLASS values; a real field sits
## somewhere in a class, so the field is editable (`Conditions.roughness_z0_m`). Tag: published.
const ROUGHNESS := {
	"sea": 0.0002, "bare": 0.005, "grass": 0.03, "short_crops": 0.10,
	"tall_crops": 0.25, "scattered_trees": 0.5,
}
const DEFAULT_Z0_M := 0.03
const DEFAULT_REF_HEIGHT_M := 10.0
const MIN_HEIGHT_M := 3.048        # 10 ft, lower bound of the MIL low-altitude form
const MAX_HEIGHT_M := 304.8        # 1000 ft, upper bound
const MAX_PROFILE_HEIGHT_M := 200.0
const V_MIN_MPS := 1.0             # ESTIMATED floor on the advection speed
const V_MAX_MPS := 40.0
const FT := 0.3048
const DT_S := 0.01                 # turbulence field step, 100 Hz
const HISTORY_S := 60.0            # how far upstream/downstream a point may be, +-30 s of travel
const BIN_HEIGHTS_M := [3.048, 10.0, 30.0, 100.0]
const REFERENCE_LENGTH_TAU_S := 2.5

const WAKE_LENGTH_HEIGHTS := 7.5   # ESTIMATE, 5-10 obstacle heights
const WAKE_DEFICIT := 0.7          # ESTIMATE, fraction of the free mean removed at the lee face
const WAKE_TI := 0.3               # ESTIMATE, wake sigma / free mean at the lee face
const WAKE_SPREAD := 0.1           # ESTIMATE, lateral half-width growth per metre downwind
const WAKE_EDGE_HEIGHTS := 0.5     # ESTIMATE, taper width in obstacle heights
enum GustAxis { ALONG, ACROSS, VERTICAL }

const DEFAULT_GUST_TAU_S := Conditions.DEFAULT_GUST_TAU_S
const DEFAULT_SEED := 0x10FA2   # distinct from Gyro's, so the two streams never correlate

## The mean wind AT THE REFERENCE HEIGHT, m/s, world frame (what the builder typed).
var steady_mps: Vector3
var gust_tau_s: float

## Kept for display (the HUD line, check 13).
var speed_mps: float
var from_deg: float

## sigma_u at the reference height, m/s (`conditions.gustiness_mps`). Zero means no turbulence at all.
var gustiness_mps: float
var model: int = Model.DRYDEN
var z0_m := DEFAULT_Z0_M
var ref_height_m := DEFAULT_REF_HEIGHT_M

var _rng := RandomNumberGenerator.new()
var _seed: int

## R1.7 MEANDER (see `Conditions.dir_sigma_deg`): two seeded Ornstein-Uhlenbeck processes on the MEAN wind,
## a direction offset (degrees) and a speed fraction (dimensionless), on their own RNG so they never
## perturb the Dryden stream. Off unless `p_meander` is passed; the flight scene turns it on.
var meander_enabled := false
var meander_dir_sigma_deg := 0.0
var meander_dir_tau_s := Conditions.DEFAULT_DIR_TAU_S
var meander_speed_sigma := 0.0
var meander_speed_tau_s := Conditions.DEFAULT_SPEED_TAU_S
var _m_theta_deg := 0.0
var _m_speed := 0.0
var _m_rng := RandomNumberGenerator.new()
## Legacy first-order gust state.
var _gust := Vector3.ZERO
## Last returned total wind (mean at the last query height plus turbulence).
var _last := Vector3.ZERO
var _turb := Vector3.ZERO

# --- Dryden field state ---
var _dir := Vector3(0, 0, 1)        # unit horizontal vector the air moves TOWARD
var _cross := Vector3(1, 0, 0)
# B2/P3: the instantaneous basis. The meander rotates the mean wind, so the frozen-field advection axis, the wake
# axis and the gust/turbulence output axes rotate with it. Equals _dir/_cross when the meander is off.
var _idir := Vector3(0, 0, 1)
var _icross := Vector3(1, 0, 0)
var _sigma_w_ref := 0.0
var _len_k := 1.0
var _bin_v: Array[float] = []       # advection speed per bin
var _a_u: Array[float] = []         # exp(-dt V/L) per bin, u
var _tau_vw: Array[float] = []      # L/V per bin, v and w
var _x: PackedFloat64Array          # states, [stream][bin][5] = u, v1, v2, w1, w2
var _hist: PackedFloat32Array       # ring: slot * (4 bins * 6) + bin * 6 + stream*3 + axis (unscaled unit variance)
var _slots := 0
var _head := 0                      # slot written last
var _acc := 0.0
var _t := 0.0                       # time since reset, s (discrete gusts)
var _gusts: Array = []              # {t0, amp, len, axis}
var _obstacles: Array = []          # Obstacle


func _init(p_conditions: Conditions, p_gust_tau_s := DEFAULT_GUST_TAU_S,
		p_seed := DEFAULT_SEED, p_model: int = Model.DRYDEN, p_meander := false) -> void:
	speed_mps = p_conditions.wind_speed_mps
	from_deg = p_conditions.wind_from_deg
	gustiness_mps = p_conditions.gustiness_mps
	gust_tau_s = p_gust_tau_s
	model = p_model
	z0_m = maxf(p_conditions.roughness_z0_m, 1.0e-4)
	ref_height_m = maxf(p_conditions.wind_ref_height_m, 1.0)
	steady_mps = steady_vector(speed_mps, from_deg)
	_last = steady_mps
	_seed = p_seed
	_rng.seed = _seed
	if p_meander and p_conditions.has_steady_wind():
		meander_enabled = true
		meander_dir_sigma_deg = p_conditions.effective_dir_sigma_deg()
		meander_dir_tau_s = maxf(p_conditions.dir_tau_s, 0.1)
		meander_speed_sigma = maxf(p_conditions.speed_sigma_frac, 0.0)
		meander_speed_tau_s = maxf(p_conditions.speed_tau_s, 0.1)
		_reset_meander()
	if model == Model.DRYDEN:
		_setup_dryden()

## `from_deg` is the bearing the wind comes FROM (0 = north, clockwise — the meteorological
## convention `conditions.gd` names). The air itself moves the OPPOSITE way, so this inverts it at
## this one point — cheaper than inverting every user's intuition. North (`from_deg = 0`) is -Z in
## this codebase's own convention (`main.gd`: "+Z, per the coordinate contract's -Z-is-forward" —
## the camera's forward, -Z, is the direction a builder facing the field calls "ahead"/"north"), so
## a north wind blows the air toward +Z ("south").
##
## THIS IS NOT A GUESS PINNED HERE FOR THE FIRST TIME — `Terrain._banked_height()` (terrain.gd)
## already fixes both axes this way, and independently agrees on both: its NORTH case is
## `distance = half_z + dz`, zero at `dz = -half_z`, so the NORTH edge sits at -Z; its EAST case is
## `distance = half_x - dx`, zero at `dx = +half_x`, so the EAST edge sits at +X. `steady_vector`'s
## own four cardinal cases (see `tests/test_wind.gd`'s `_cardinal_bearings()`) land on exactly
## those axes. Named here so a future reader checks that mapping before "fixing" this one to
## disagree with it.
##
## Nothing here normalises `from_deg` first — `conditions.gd`'s header is explicit that a 370 stays
## 370 — and `sin`/`cos` do not need it normalised either, so none happens here.
static func steady_vector(p_speed_mps: float, p_from_deg: float) -> Vector3:
	return FlightLaw.wind_steady_vector(p_speed_mps, p_from_deg)

## Mean wind speed (m/s) at `height_m` above ground, log law from the reference height.
func mean_speed_at(height_m: float) -> float:
	return speed_mps * profile_factor(height_m)


## Mean wind vector (world frame) at `height_m` above ground. FIRST_ORDER keeps the old uniform wind.
func mean_at(height_m: float) -> Vector3:
	if model == Model.FIRST_ORDER:
		return steady_mps
	return meandered_steady() * profile_factor(height_m)


## The reference-height mean wind with the meander applied: rotated by the direction offset and scaled
## by the speed fraction. Equals `steady_mps` exactly when the meander is off.
func meandered_steady() -> Vector3:
	if not meander_enabled:
		return steady_mps
	return steady_vector(speed_mps * maxf(1.0 + _m_speed, 0.0), from_deg + _m_theta_deg)


## The instantaneous mean speed (reference height) and the bearing it comes FROM, for the HUD.
func inst_speed_mps() -> float:
	return speed_mps * maxf(1.0 + _m_speed, 0.0) if meander_enabled else speed_mps


func inst_from_deg() -> float:
	if not meander_enabled:
		return from_deg
	return fposmod(from_deg + _m_theta_deg, 360.0)


func meander_theta_deg() -> float:
	return _m_theta_deg


func meander_speed_fraction() -> float:
	return _m_speed


## Exact OU step: x' = a x + sigma sqrt(1 - a^2) n, a = exp(-dt / tau). Stationary variance sigma^2.
func _step_meander(dt: float) -> void:
	if not meander_enabled or dt <= 0.0:
		return
	var a := exp(-dt / meander_dir_tau_s)
	_m_theta_deg = a * _m_theta_deg + meander_dir_sigma_deg * sqrt(1.0 - a * a) * _m_rng.randfn()
	var b := exp(-dt / meander_speed_tau_s)
	_m_speed = b * _m_speed + meander_speed_sigma * sqrt(1.0 - b * b) * _m_rng.randfn()
	_update_basis()


## B2/P3: rotate the downwind/crosswind basis by the meander angle (same bearing convention as steady_vector).
func _update_basis() -> void:
	if not meander_enabled:
		_idir = _dir
		_icross = _cross
		return
	var r := deg_to_rad(from_deg + _m_theta_deg)
	_idir = Vector3(-sin(r), 0, cos(r))
	_icross = Vector3(-_idir.z, 0, _idir.x)


func _reset_meander() -> void:
	_m_rng.seed = _seed ^ 0x3EA4D3
	# Drawn from the stationary distribution, so the wind is already wandering at t = 0.
	_m_theta_deg = meander_dir_sigma_deg * _m_rng.randfn()
	_m_speed = meander_speed_sigma * _m_rng.randfn()
	_update_basis()


## ln(z/z0) / ln(z_ref/z0), with z clamped to [2 z0, 200 m].
func profile_factor(height_m: float) -> float:
	var z := clampf(height_m, 2.0 * z0_m, MAX_PROFILE_HEIGHT_M)
	var zr := maxf(ref_height_m, 2.0 * z0_m * 1.0001)
	return log(z / z0_m) / log(zr / z0_m)


## Wind speed that MIL-F-8785C ties turbulence to: sigma_w = 0.1 * W20 (W20 = mean wind at 20 ft
## = 6.096 m). Returns the matching sigma_u at the reference height, i.e. the figure to type into
## `Conditions.gustiness_mps` for "the MIL turbulence for this wind".
static func mil_gustiness_mps(p_speed_ref_mps: float, p_z0_m := DEFAULT_Z0_M,
		p_ref_height_m := DEFAULT_REF_HEIGHT_M) -> float:
	var z := clampf(20.0 * FT, 2.0 * p_z0_m, MAX_PROFILE_HEIGHT_M)
	var w20 := p_speed_ref_mps * log(z / p_z0_m) / log(p_ref_height_m / p_z0_m)
	return 0.1 * w20 / pow(0.177 + 0.000823 * (p_ref_height_m / FT), 0.4)


## Dryden scales at a height. Returns [Lu(=Lv), Lw, sigma_u(=sigma_v), sigma_w], metres and m/s,
## before the gust_tau_s length scaling.
func dryden_scales(height_m: float) -> Array:
	var h_ft := clampf(height_m, MIN_HEIGHT_M, MAX_HEIGHT_M) / FT
	var d := 0.177 + 0.000823 * h_ft
	return [h_ft / pow(d, 1.2) * FT, h_ft * FT, _sigma_w_ref / pow(d, 0.4), _sigma_w_ref]


func _setup_dryden() -> void:
	var d_ref := 0.177 + 0.000823 * (clampf(ref_height_m, MIN_HEIGHT_M, MAX_HEIGHT_M) / FT)
	_sigma_w_ref = gustiness_mps * pow(d_ref, 0.4)
	_len_k = maxf(gust_tau_s, 0.05) / REFERENCE_LENGTH_TAU_S
	var h2 := Vector2(steady_mps.x, steady_mps.z)
	if h2.length() < 1.0e-6:
		# Calm: the direction the (non-existent) wind blows towards, from the bearing.
		h2 = Vector2(-sin(deg_to_rad(from_deg)), cos(deg_to_rad(from_deg)))
	h2 = h2.normalized()
	_dir = Vector3(h2.x, 0, h2.y)
	_cross = Vector3(-_dir.z, 0, _dir.x)
	_update_basis()
	_bin_v.clear()
	_a_u.clear()
	_tau_vw.clear()
	for h in BIN_HEIGHTS_M:
		var v: float = clampf(mean_speed_at(h), V_MIN_MPS, V_MAX_MPS)
		var sc: Array = dryden_scales(h)
		_bin_v.append(v)
		_a_u.append(exp(-DT_S * v / (sc[0] * _len_k)))
		_tau_vw.append(sc[1] * _len_k / v)
	_slots = int(HISTORY_S / DT_S) + 2
	_reset_field()


func _reset_field() -> void:
	_x = PackedFloat64Array()
	_x.resize(2 * 4 * 5)
	_hist = PackedFloat32Array()
	_hist.resize(_slots * 24)
	_head = 0
	_acc = 0.0
	if not _field_needed():
		return
	# Burn in over the whole history so the field is stationary and every delay is filled.
	for _k in _slots:
		_step_field()


func _step_field() -> void:
	_head = (_head + 1) % _slots
	var base := _head * 24
	for st in 2:
		var nu := _rng.randfn()
		var nv := _rng.randfn()
		var nw := _rng.randfn()
		for b in 4:
			var o := (st * 4 + b) * 5
			var au: float = _a_u[b]
			_x[o] = au * _x[o] + sqrt(1.0 - au * au) * nu
			var tau: float = _tau_vw[b]
			var q := sqrt(tau / DT_S)
			var k := DT_S / tau
			# v: x1' = (-x1 + n)/tau, x2' = (-x2 + x1)/tau, y = (1-sqrt3) x2 + sqrt3 x1 (unit variance, see header)
			_x[o + 1] += k * (-_x[o + 1] + q * nv)
			_x[o + 2] += k * (-_x[o + 2] + _x[o + 1])
			_x[o + 3] += k * (-_x[o + 3] + q * nw)
			_x[o + 4] += k * (-_x[o + 4] + _x[o + 3])
			var s3 := 1.7320508
			_hist[base + b * 6 + st * 3] = _x[o]
			_hist[base + b * 6 + st * 3 + 1] = (1.0 - s3) * _x[o + 2] + s3 * _x[o + 1]
			_hist[base + b * 6 + st * 3 + 2] = (1.0 - s3) * _x[o + 4] + s3 * _x[o + 3]


func _field_needed() -> bool:
	return gustiness_mps > 0.0 or not _obstacles.is_empty()


## Obstacles whose lee is sheltered (R1.6). Pass an empty list to remove the wake.
func set_obstacles(list: Array) -> void:
	if list.is_empty() and _obstacles.is_empty():
		return
	_obstacles = list.duplicate()
	if model == Model.DRYDEN:
		_rng.seed = _seed
		_reset_field()


## A discrete 1-cosine gust: `amplitude_mps` peak (signed), `length_m` = ramp length d (total 2d), front reaching the
## origin at `start_s` seconds after reset, along `axis` (GustAxis).
func add_discrete_gust(amplitude_mps: float, length_m: float, start_s := 0.0, axis: int = GustAxis.ALONG) -> void:
	_gusts.append({"t0": start_s, "amp": amplitude_mps, "len": maxf(length_m, 0.01), "axis": axis})


## The 1-cosine profile at distance `s` behind the front.
static func one_minus_cosine(amp: float, length_m: float, s: float) -> float:
	if s <= 0.0 or s >= 2.0 * length_m:
		return 0.0
	return 0.5 * amp * (1.0 - cos(PI * s / length_m))


func _gust_at(height_m: float, along: float) -> Vector3:
	var out := Vector3.ZERO
	if _gusts.is_empty():
		return out
	var u := clampf(mean_speed_at(height_m), V_MIN_MPS, V_MAX_MPS)
	for g in _gusts:
		var v := one_minus_cosine(g["amp"], g["len"], u * (_t - g["t0"]) - along)
		match int(g["axis"]):
			GustAxis.ALONG: out += _idir * v
			GustAxis.ACROSS: out += _icross * v
			_: out += Vector3(0, v, 0)
	return out


## Wake of every obstacle at a point: [mean_factor (1 = free), sigma_fraction (wake sigma / free mean)].
func wake_at(pos: Vector3, height_m: float) -> Array:
	var factor := 1.0
	var ti := 0.0
	for o in _obstacles:
		var box: AABB = o.aabb()
		var hgt := box.size.y
		if hgt <= 0.0:
			continue
		var c := box.get_center()
		var rel := pos - c
		var ext_along := 0.5 * (absf(_idir.x) * box.size.x + absf(_idir.z) * box.size.z)
		var ext_icross := 0.5 * (absf(_icross.x) * box.size.x + absf(_icross.z) * box.size.z)
		var x := rel.dot(_idir) - ext_along
		var y := absf(rel.dot(_icross))
		var length := WAKE_LENGTH_HEIGHTS * hgt
		if x <= 0.0 or x >= length:
			continue
		var edge := WAKE_EDGE_HEIGHTS * hgt
		var half_w := ext_icross + WAKE_SPREAD * x
		var top := hgt + WAKE_SPREAD * x
		var sh := (1.0 - x / length) * clampf(1.0 - (y - half_w) / edge, 0.0, 1.0) \
			* clampf(1.0 - (height_m - top) / edge, 0.0, 1.0)
		factor *= 1.0 - WAKE_DEFICIT * sh
		ti += WAKE_TI * sh
	return [factor, ti]


## Turbulence vector (world frame) at a point, from the stored field. `unit` returns unit variance on every axis.
## `along` and `across` are the point's coordinates along the downwind and crosswind axes.
func _turbulence_at(height_m: float, along: float, across: float, unit := false) -> Vector3:
	var h := clampf(height_m, MIN_HEIGHT_M, MAX_HEIGHT_M)
	var fb := (log(h) - log(BIN_HEIGHTS_M[0])) / (log(BIN_HEIGHTS_M[1]) - log(BIN_HEIGHTS_M[0]))
	var b0 := 0
	if h >= BIN_HEIGHTS_M[1]:
		b0 = 1
		fb = (log(h) - log(BIN_HEIGHTS_M[1])) / (log(BIN_HEIGHTS_M[2]) - log(BIN_HEIGHTS_M[1]))
	if h >= BIN_HEIGHTS_M[2]:
		b0 = 2
		fb = clampf((log(h) - log(BIN_HEIGHTS_M[2])) / (log(BIN_HEIGHTS_M[3]) - log(BIN_HEIGHTS_M[2])), 0.0, 1.0)
	var u_local := clampf(mean_speed_at(h), V_MIN_MPS, V_MAX_MPS)
	var delay := clampf(0.5 * HISTORY_S + along / u_local, 0.0, HISTORY_S)
	var pos := delay / DT_S
	var i0 := int(pos)
	var fr := pos - float(i0)
	var s0 := ((_head - i0) % _slots + _slots) % _slots
	var s1 := ((_head - i0 - 1) % _slots + _slots) % _slots
	var sc: Array = dryden_scales(h)
	var theta: float = 1.19 * across / (sc[0] * _len_k)
	var ct: float = cos(theta)
	var st: float = sin(theta)
	var out := Vector3.ZERO
	for bi in 2:
		var b := b0 + bi
		var w := (1.0 - fb) if bi == 0 else fb
		if w <= 0.0:
			continue
		var sb: Array = dryden_scales(BIN_HEIGHTS_M[b])
		var r := Vector3.ZERO
		for ax in 3:
			var ia := b * 6 + ax
			var ib := b * 6 + 3 + ax
			var va := lerpf(_hist[s0 * 24 + ia], _hist[s1 * 24 + ia], fr)
			var vb := lerpf(_hist[s0 * 24 + ib], _hist[s1 * 24 + ib], fr)
			r[ax] = ct * va + st * vb
		if unit:
			out += w * r
		else:
			out += w * Vector3(r.x * sb[2], r.y * sb[2], r.z * sb[3])
	return _idir * out.x + _icross * out.y + Vector3(0, out.z, 0)


## Steady plus the last computed turbulence — does not advance anything (the HUD reads this).
func velocity_mps() -> Vector3:
	return _last


## Advances the process by one physics tick at the origin, ground height `ref_height_m`.
func update(dt: float) -> Vector3:
	return update_at(dt, Vector3.ZERO, ref_height_m)


## B4/E2 LIVE APPLY. A weather edit in flight hands the new field the old one; for `seconds` both advance and the air the
## aircraft feels is old -> new on a smoothstep, so an edit is never a step impulse (a real front arrives over seconds,
## not in one millisecond). `crossfade_fraction()` is 0 at the start, 1 once the old field is dropped; -1 when none ran.
const CROSSFADE_S := 1.5
var _fade_from: Wind = null
var _fade_s := 0.0
var _fade_t := 0.0


func crossfade_from(old: Wind, seconds := CROSSFADE_S) -> void:
	if old == null or old == self or seconds <= 0.0:
		return
	# Never chain fades: the old field's own fade is collapsed onto it, so at most two fields ever step.
	old._fade_from = null
	_fade_from = old
	_fade_s = seconds
	_fade_t = 0.0
	_last = old._last


## 0..1 progress of a crossfade in flight, or -1.0 when none is running (the HUD labels this).
func crossfade_fraction() -> float:
	return clampf(_fade_t / _fade_s, 0.0, 1.0) if _fade_from != null else -1.0


## Advances by `dt` and returns the wind at world position `pos` (m) at `height_m` above ground.
## Calls with the same seed and the same sequence of (dt, pos, height) return the same vectors.
func update_at(dt: float, pos: Vector3, height_m: float) -> Vector3:
	if _fade_from == null:
		return _update_at_raw(dt, pos, height_m)
	var old_v := _fade_from.update_at(dt, pos, height_m)
	var new_v := _update_at_raw(dt, pos, height_m)
	_fade_t += dt
	var s := smoothstep(0.0, 1.0, _fade_t / _fade_s)
	if _fade_t >= _fade_s:
		_fade_from = null
	_last = old_v.lerp(new_v, s)
	return _last


func _update_at_raw(dt: float, pos: Vector3, height_m: float) -> Vector3:
	if model == Model.FIRST_ORDER:
		var k := FlightLaw.gust_coefficients(dt, gust_tau_s, gustiness_mps)
		var a: float = k[0]
		var sigma: float = k[1]
		var drive := Vector3(
			_rng.randfn(0.0, sigma),
			_rng.randfn(0.0, sigma),
			_rng.randfn(0.0, sigma))
		_gust += (drive - _gust) * a
		_last = steady_mps + _gust
		return _last
	_step_meander(dt)
	var mean := mean_at(height_m)
	_t += dt
	var turb := Vector3.ZERO
	if _field_needed():
		_acc += dt
		while _acc >= DT_S:
			_acc -= DT_S
			_step_field()
		var along := pos.dot(_idir)
		var across := pos.dot(_icross)
		if gustiness_mps > 0.0:
			turb = _turbulence_at(height_m, along, across)
		if not _obstacles.is_empty() and steady_mps.length() > 0.05:
			var wk := wake_at(pos, height_m)
			mean *= float(wk[0])
			if float(wk[1]) > 0.0:
				turb += _turbulence_at(height_m, along, across, true) * (float(wk[1]) * mean_speed_at(height_m))
	turb += _gust_at(height_m, pos.dot(_idir))
	_turb = turb
	_last = mean + turb
	return _last


## Turbulence part of the last query (for tests and logs).
func turbulence_mps() -> Vector3:
	return _turb


## Re-seeded, so a respawn replays the same wind.
func reset() -> void:
	_gust = Vector3.ZERO
	_turb = Vector3.ZERO
	_last = steady_mps
	_rng.seed = _seed
	_t = 0.0
	if meander_enabled:
		_reset_meander()
	if model == Model.DRYDEN:
		_reset_field()
