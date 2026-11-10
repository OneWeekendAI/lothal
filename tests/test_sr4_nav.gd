class_name TestSr4Nav
extends RefCounted
## SR4 navigation core (src/autopilot/nav_pilot.gd) flown through the real FlightController by
## src/autopilot/flight_rig.gd. One TestResult per case, never looped. Estimate = sim truth (placeholder).
## Every flight is seeded (rig seed drives the gust process and the gyro noise), dt = 1/500 s.
##
## FAIL-PROOFS (each case was run with its fix removed by a temporary edit, then restored; observed value):
##   M1 wind_correction default false (no integrator, no crab):
##        hold five_inch  FAILS: mean offset 0.186 m (limit 0.1), max radius 0.364 m; seven_lr 0.247 m, cinelifter 0.162 m.
##   M2 crab disabled (CRAB treated as COURSE even with correction on):
##        crosswind corrected FAILS: heading-track 0.2 deg (needs > 3; fixed code 41.2 deg).
##   M3 terrain_feed_forward default false:
##        terrain-follow FAILS: AGL range 9.03..9.06 m (limit 9.7; fixed code 10.00..10.06).
##   M4 altitude_integrator default false (hover feed-forward 15 percent low, as the case sets):
##        altitude step FAILS: final error 1.390 m (limit 0.1; fixed code 0.003).
##   M5 cross-track correction removed (xt / 1e9):
##        waypoint square FAILS: per-leg max xt 0.59 2.03 2.15 2.49 m (limit 1.2; fixed code max 0.71);
##        crosswind corrected FAILS: max xt 1.355 m (limit 0.3).
##   M6 wind_correction ignored (integrator and crab always on, so "off" changes nothing):
##        crosswind OFF case FAILS: off xt 0.088 m, heading-track 41.24 deg (fixed code: 0.654 m, 0.19 deg).
##   Measured with the fixed code (bands are these, rounded up): hold max radius 0.145 / 0.191 / 0.127 m
##   (five_inch / seven_lr / cinelifter), square per-leg xt 0.13 0.36 0.44 0.71 m, crosswind on 0.088 m vs off
##   0.654 m, heading-track 41.2 deg, terrain AGL 10.00..10.06 m, altitude step error 0.003 m.
##
## M8 (SR4.1, 2026-11-10) five-minute hold in 15 mph + 1 m/s turbulence: fixed code max radius 0.204 m, last-60 s mean offset 0.005 m.
##        wind_correction default false: hold-5-min FAILS: max radius 0.701 m (limit 0.4), mean offset 0.323 m (limit 0.1).
##   The other SR4.1 gaps (square per leg, crab on/off, 10 percent slope AGL, reserve 95 percent not flown) already existed
##   (nav square/crosswind/terrain; mission res95 x3); no new case needed.
##
## M7 (hover model, added with SR4 follow-up 2026-11-09): hover_throttle_for matched the flown hover to 0.2-1 percent
##   already; the 8-20 percent error was the hover POWER the mission runner derived from it (hover_current_a(thr) priced at
##   the nominal voltage, no avionics load): flown 79 W against 49 W modelled on the 5 inch (-38 percent).
##        hover model five_inch FAILS with the old estimate (hover_current_a(thr) * nominal_v): -37.8 percent;
##        hover model cinelifter at 70 percent used FAILS with hover_throttle_for replaced by hover_throttle() (nominal datum):
##        throttle -12 percent.
##
## Bands are what was measured, rounded up generously (stated in each check name).

const SEED := 7
const START_Y := 10.0


static func run() -> Array:
	var out: Array = []
	out.append(_hold("five_inch"))
	out.append(_hold("seven_lr"))
	out.append(_hold("cinelifter"))
	out.append(_hold_five_minutes())
	out.append(_square())
	out.append(_crosswind_corrected())
	out.append(_crosswind_uncorrected())
	out.append(_terrain_follow())
	out.append(_altitude_step())
	out.append(_hover_model("five_inch", 0.0))
	out.append(_hover_model("cinelifter", 0.7))
	return out


static func _rig(cls: String, wind_mps: float, from_deg: float, gust: float, start := Vector3(0, START_Y, 0)) -> FlightRig:
	return FlightRig.from_class(cls, FlightRig.conditions_with_wind(wind_mps, from_deg, gust), SEED, start)


## Wind 5 m/s steady from the east plus 1 m/s gusts, 60 s, horizontal radius from the hold point.
static func _hold(cls: String) -> TestResult:
	var rig := _rig(cls, 5.0, 90.0, 1.0)
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(START_Y)
	var worst := 0.0
	var sum := Vector2.ZERO
	var n := 0
	for k in 60 * 500:
		rig.step()
		var p := rig.position()
		var r := Vector2(p.x, p.z)
		worst = maxf(worst, r.length())
		if k >= 40 * 500:
			sum += r
			n += 1
	var mean_off := (sum / float(n)).length()
	return TestResult.new("sr4 hold %s: 60 s in 5 m/s wind + 1 m/s gust stays within 0.5 m and the last-20 s mean offset is under 0.1 m" % cls,
		worst < 0.5 and mean_off < 0.1, "max radius %.3f m, mean offset (40-60 s) %.3f m" % [worst, mean_off])


## SR4.1: five minutes at one point in 15 mph (6.7 m/s, from the east) with turbulence (Dryden, sigma 1.0 m/s, which is
## above the MIL-F-8785C 0.1 x W20 = 0.7 m/s: a stated harsh case). Stated radius: the drone stays within 0.4 m of the point for
## the whole 300 s, and the last-60 s mean offset stays under 0.1 m (no integrator windup or slow drift).
static func _hold_five_minutes() -> TestResult:
	var rig := _rig("five_inch", 15.0 * 0.44704, 90.0, 1.0)
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(START_Y)
	var worst := 0.0
	var sum := Vector2.ZERO
	var n := 0
	for k in 300 * 500:
		rig.step()
		var p := rig.position()
		var r := Vector2(p.x, p.z)
		worst = maxf(worst, r.length())
		if k >= 240 * 500:
			sum += r
			n += 1
	var mean_off := (sum / float(n)).length()
	return TestResult.new("sr4 hold five_inch 5 min in 15 mph (6.7 m/s) wind + 1 m/s turbulence: stays within 0.4 m and the last-60 s mean offset is under 0.1 m",
		worst < 0.4 and mean_off < 0.1, "max radius %.3f m, mean offset (240-300 s) %.3f m, t %.0f s" % [worst, mean_off, rig.time_s])


## 100 m square at 8 m/s, 3 m/s wind from 45 deg, course heading. Cross-track error is read on each leg between
## 15 m after its start and 15 m before its end (the corner transient is the turn rule, not the line following).
static func _square() -> TestResult:
	var rig := _rig("five_inch", 3.0, 45.0, 0.5)
	rig.nav.set_altitude_msl(START_Y)
	rig.nav.set_heading_mode(NavPilot.HeadingMode.COURSE)
	rig.nav.set_path([Vector2(0, 0), Vector2(0, -100), Vector2(100, -100), Vector2(100, 0), Vector2(0, 0)], 8.0, 2.0)
	var worst := [0.0, 0.0, 0.0, 0.0]
	var worst_all := 0.0
	var steps := 0
	while not rig.nav.path_done() and steps < 120 * 500:
		rig.step()
		steps += 1
		var leg := rig.nav.leg_index()
		var along := rig.nav.along_track_distance()
		var xt := absf(rig.nav.cross_track_error())
		worst_all = maxf(worst_all, xt)
		if along > 15.0 and along < 85.0 and leg < 4:
			worst[leg] = maxf(worst[leg], xt)
	var m := maxf(maxf(worst[0], worst[1]), maxf(worst[2], worst[3]))
	return TestResult.new("sr4 waypoint square 100 m at 8 m/s: cross-track error on each leg's middle 70 m is under 1.2 m",
		rig.nav.path_done() and m < 1.2,
		"done %s in %.1f s; per-leg max xt %.2f %.2f %.2f %.2f m; worst anywhere (incl corners) %.2f m" % [
			rig.nav.path_done(), rig.time_s, worst[0], worst[1], worst[2], worst[3], worst_all])


## Flies north (-Z) along a 400 m line at 8 m/s with 7 m/s wind from the east (90 deg to the track).
## Returns {xt: max |cross-track| after 15 s, heading_vs_track_deg: mean over the same span}.
static func _crosswind_flight(correction: bool) -> Dictionary:
	var rig := _rig("five_inch", 7.0, 90.0, 0.5)
	rig.nav.wind_correction = correction
	rig.nav.set_altitude_msl(START_Y)
	rig.nav.set_heading_mode(NavPilot.HeadingMode.CRAB)
	rig.nav.set_track(Vector2(0, 0), Vector2(0, -400), 8.0)
	var worst := 0.0
	var diff_sum := 0.0
	var n := 0
	for k in 40 * 500:
		rig.step()
		if k >= 15 * 500:
			worst = maxf(worst, absf(rig.nav.cross_track_error()))
			var e := rig.nav.estimate()
			var v: Vector3 = e["vel"]
			var track := atan2(-v.x, -v.z)
			diff_sum += absf(rad_to_deg(wrapf(e["yaw"] - track, -PI, PI)))
			n += 1
	return {"xt": worst, "diff_deg": diff_sum / float(n)}


static func _crosswind_corrected() -> TestResult:
	var r := _crosswind_flight(true)
	return TestResult.new("sr4 crosswind 7 m/s at 90 deg: crab heading differs from track by more than 3 deg AND cross-track error stays under 0.3 m",
		r["diff_deg"] > 3.0 and r["xt"] < 0.3, "heading-track %.1f deg, max xt %.3f m" % [r["diff_deg"], r["xt"]])


static func _crosswind_uncorrected() -> TestResult:
	var on := _crosswind_flight(true)
	var off := _crosswind_flight(false)
	return TestResult.new("sr4 crosswind with wind_correction OFF: drift shows, cross-track error over 0.4 m and over 3x the corrected flight, heading ~ track",
		off["xt"] > 0.4 and off["xt"] > 3.0 * on["xt"] and off["diff_deg"] < 3.0,
		"off: xt %.3f m, heading-track %.2f deg; on: xt %.3f m" % [off["xt"], off["diff_deg"], on["xt"]])


## 10 percent slope rising to the north (terrain y = -0.1 z). 10 m AGL at 8 m/s for 25 s.
static func _terrain_follow() -> TestResult:
	var ground := func(_x: float, z: float) -> float: return -0.1 * z
	var rig := _rig("five_inch", 0.0, 0.0, 0.0)
	rig.nav.set_altitude_agl(10.0, ground)
	rig.nav.set_track(Vector2(0, 0), Vector2(0, -400), 8.0)
	var lo := 1e9
	var hi := -1e9
	for k in 25 * 500:
		rig.step()
		if k >= 5 * 500:
			var p := rig.position()
			var agl := p.y - float(ground.call(p.x, p.z))
			lo = minf(lo, agl)
			hi = maxf(hi, agl)
	var rise := rig.position().y - START_Y
	return TestResult.new("sr4 terrain-follow, 10 percent slope at 8 m/s: AGL stays within 10 m +/- 0.3 m after 5 s (and the drone climbed over 10 m)",
		lo > 9.7 and hi < 10.3 and rise > 10.0, "AGL range %.2f..%.2f m, climbed %.1f m" % [lo, hi, rise])


## 5 m climb step at hover with the hover feed-forward 15 percent low: final error under 0.1 m by 12 s, overshoot under 0.5 m.
static func _altitude_step() -> TestResult:
	var rig := _rig("five_inch", 0.0, 0.0, 0.0)
	# The hover model is 15 percent low (feed-forward scale 0.85): only the integrator can find the trim.
	rig.nav.hover_ff_scale = 0.85
	rig.nav.set_altitude_msl(START_Y)
	rig.run_for(3.0)
	rig.nav.set_altitude_msl(START_Y + 5.0)
	var peak := 0.0
	for _k in 12 * 500:
		rig.step()
		peak = maxf(peak, rig.position().y)
	var err := absf(rig.position().y - (START_Y + 5.0))
	var over := peak - (START_Y + 5.0)
	return TestResult.new("sr4 altitude step +5 m: error under 0.1 m after 12 s and overshoot under 0.5 m",
		err < 0.1 and over < 0.5, "final error %.3f m, overshoot %.3f m" % [err, over])


## The build's hover model against the flown hover: throttle (hover_throttle_for, refreshed for the pack's state) within 2
## percent of what the altitude loop settled at (feed-forward + trim), and hover_power_w within 3 percent of the mean
## terminal power over the last 3 s. `used` is the fraction of the pack already drained when the hover starts.
static func _hover_model(cls: String, used: float) -> TestResult:
	var rig := _rig(cls, 0.0, 0.0, 0.0, Vector3(0, 30.0, 0))
	var bat = rig.core.powertrain.battery
	bat.used_mah = bat.capacity_mah * used
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(30.0)
	rig.run_for(12.0)
	var est_w: float = rig.build.hover_power_w(bat)
	var model_thr: float = rig.build.hover_throttle_for(bat)
	var s := 0.0
	var n := 1500
	for _k in n:
		rig.step()
		s += rig.core.observables.voltage_live_v * rig.core.observables.current_total_a
	var flown_w := s / float(n)
	var settled: float = rig.nav._thr_ff + rig.nav._thr_trim
	var thr_err := model_thr / settled - 1.0
	var w_err := est_w / flown_w - 1.0
	return TestResult.new("sr4 hover model %s at %.0f %% used: hover_throttle_for within 2 %% of the flown hover throttle and hover_power_w within 3 %% of the flown hover power" % [cls, used * 100.0],
		absf(thr_err) < 0.02 and absf(w_err) < 0.03,
		"throttle model %.4f flown %.4f (%+.1f %%), power model %.1f W flown %.1f W (%+.1f %%)" % [model_thr, settled, thr_err * 100.0, est_w, flown_w, w_err * 100.0])
