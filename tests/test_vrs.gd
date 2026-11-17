class_name TestVrs
extends RefCounted
## R1.5 — vortex ring state and windmill braking (rust/src/bemt_ratios.rs, "R1.5" block).
##
## Every check names the edit that turns it red; each was run red before it was kept.
##
## Descent x is in hover inflows (descent speed / vh). The band is 0.25 to 1.5 vh, the peak 1.0, the windmill
## branch starts at 2.0. The deficit (15 percent) and the fluctuation (10 percent RMS) are ESTIMATES by owner
## decision; these tests check their SHAPE (zero at the edges, present inside), not that the numbers are true.

const RPM := 9000.0
const EDGES := [0.25, 1.5, 2.0]


static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var ratios := build.forward_ratios()
	results.append_array(_continuous_at_every_edge(ratios))
	results.append_array(_deficit_and_fluctuation_live_only_in_the_band(build, ratios))
	results.append(_forward_speed_exits_vrs(ratios))
	results.append_array(_sim_descent_washes_out(build))
	results.append(_fast_descent_is_stable_on_the_windmill_branch(build))
	return results


# ---- helpers ------------------------------------------------------------------------------------------------

static func _thrust_at(ratios: BemtRatios, x: float) -> float:
	return ratios.thrust_ratio(RPM, -x * ratios.hover_inflow_mps(RPM), 0.0)


static func _power_at(ratios: BemtRatios, x: float) -> float:
	return ratios.power_ratio(RPM, -x * ratios.hover_inflow_mps(RPM), 0.0)


## One 2 s descent at `x` hover inflows with `forward_mps` of body-forward speed. The aircraft is primed at its true
## hover throttle and flown closed-loop on attitude only (angle mode, sticks centred, throttle held), so what survives is
## what the flight controller could not absorb, which is what "washes out" means to a pilot. Returns
## {wobble_deg: RMS of the tilt about its own mean after 0.3 s, rate: peak angular rate rad/s, alt_err_m: peak departure
## from a constant-rate descent, tilt_deg: peak tilt}. Wobble, not mean tilt, because a drifting aircraft leans into
## its own drag with the sticks centred, and that lean is not a washout.
static func fly_descent(build: Build, x: float, forward_mps: float, fluct_on: bool = true) -> Dictionary:
	var core := build.build_drone_core({"off": true})
	var thr := build.hover_throttle_for(core.powertrain.battery)
	core.prime_motors(thr)
	core.powertrain.vrs_fluctuation_on = fluct_on
	var vh: float = build.forward_ratios().hover_inflow_mps(float(core.powertrain.motor_rpm[0]))
	var d := x * vh
	var y0 := 500.0
	core.rigid_body.position_m = Vector3(0, y0, 0)
	core.rigid_body.velocity_mps = Vector3(0, -d, -forward_mps)
	core.rigid_body.orientation = Quaternion.IDENTITY
	var fc := FlightController.new()
	fc.rate_loop.adopt_tune(PidTunes.new().tune_for(build))
	fc.rate_loop.config = build.config
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": thr}
	var dt := 0.002
	var tilts: Array = []
	var vys: Array = []
	var alt := 0.0
	var peak_tilt := 0.0
	var rate := 0.0
	var late_rate := 0.0
	for i in 1000:
		var cmds := fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, rc, dt)
		# B1: the forward speed is HELD (the pilot's job). Level and hands-off, the rotor H-force (mu 0.345 /s) bleeds
		# 3 m/s to ~1.5 m/s in these 2 s, under the 0.5 vh that clears the ring, and the craft re-enters VRS: real
		# physics, but not the claim here, which is what forward speed does. Only the horizontal velocity is pinned.
		if forward_mps > 0.0:
			core.rigid_body.velocity_mps = Vector3(0.0, core.rigid_body.velocity_mps.y, -forward_mps)
		core.step(cmds, dt)
		var up: Vector3 = core.rigid_body.orientation * Vector3.UP
		var tilt := rad_to_deg(up.angle_to(Vector3.UP))
		peak_tilt = maxf(peak_tilt, tilt)
		if i >= 150:
			tilts.append(tilt)
			vys.append(core.rigid_body.velocity_mps.y)
			rate = maxf(rate, core.rigid_body.angular_velocity_rad_s.length())
		if i >= 750:
			late_rate = maxf(late_rate, core.rigid_body.angular_velocity_rad_s.length())
		alt = maxf(alt, absf(core.rigid_body.position_m.y - (y0 - d * float(i + 1) * dt)))
	var mean := 0.0
	for t in tilts:
		mean += t
	mean /= tilts.size()
	var ss := 0.0
	for t in tilts:
		ss += (t - mean) * (t - mean)
	# Vertical-speed wobble: residual of vy against its own straight-line trend, which removes the smooth drag and
	# mean-thrust drift (both scale with descent speed, not with the vortex ring) and keeps what is erratic.
	var n := float(vys.size())
	var mt := (n - 1.0) * 0.5
	var mv := 0.0
	for v in vys:
		mv += v
	mv /= n
	var sxy := 0.0
	var sxx := 0.0
	for k in vys.size():
		sxy += (float(k) - mt) * (vys[k] - mv)
		sxx += (float(k) - mt) * (float(k) - mt)
	var slope := sxy / sxx
	var rs := 0.0
	for k in vys.size():
		var r: float = vys[k] - (mv + slope * (float(k) - mt))
		rs += r * r
	return {"wobble_deg": sqrt(ss / tilts.size()), "rate": rate, "alt_err_m": alt, "tilt_deg": peak_tilt, "late_rate": late_rate,
		"vy_wobble": sqrt(rs / n)}


# ---- continuity -----------------------------------------------------------------------------------------------

## TO MAKE THIS FAIL: change the 1.5-to-2 blend in `descent_inflow` to a hard switch at 2.0, or drop the `off *
## smooth01` easing term below 0.25 (a 0.087 step in vi/vh at 0.25). Red observed for both.
static func _continuous_at_every_edge(ratios: BemtRatios) -> Array:
	var worst_inflow := 0.0
	var worst_thrust := 0.0
	var worst_power := 0.0
	var eps := 1e-9
	for e in EDGES:
		worst_inflow = maxf(worst_inflow, absf(BemtRatios.descent_inflow_ratio(e + eps) - BemtRatios.descent_inflow_ratio(e - eps)))
		worst_thrust = maxf(worst_thrust, absf(_thrust_at(ratios, e + eps) - _thrust_at(ratios, e - eps)))
		worst_power = maxf(worst_power, absf(_power_at(ratios, e + eps) - _power_at(ratios, e - eps)))
	# And across zero: hover reads exactly the static 1.0, and a creep of 1 mm/s is not a step.
	var creep := absf(_thrust_at(ratios, 0.0001) - 1.0)
	return [
		TestResult.new("inflow vi/vh is continuous at 0.25, 1.5 and 2.0 vh (jump under 1e-4 across +-1e-9; the windmill root has an infinite slope at 2.0, so the step must be tiny)",
			worst_inflow < 1e-4, "worst jump %s" % str(worst_inflow)),
		TestResult.new("thrust ratio is continuous at every band edge and at the windmill start",
			worst_thrust < 1e-3, "worst jump %s" % str(worst_thrust)),
		TestResult.new("power ratio is continuous at every band edge and at the windmill start",
			worst_power < 1e-3, "worst jump %s" % str(worst_power)),
		TestResult.new("a 0.0001 vh creep reads within 1e-3 of the static 1.0",
			creep < 1e-3, "thrust ratio departs by %s" % str(creep)),
	]


# ---- the deficit and the fluctuation ------------------------------------------------------------------------

## TO MAKE THESE FAIL: set VRS_MEAN_DEFICIT to 0.0 (the mean check goes red: the fit alone gains thrust), or make
## `vrs_band` return 1.0 outside the edges (the zero-outside check goes red), or remove the `thrust *=
## self.vrs_fluctuation(...)` line in powertrain.rs step_in_flight (the fluctuation check goes red).
static func _deficit_and_fluctuation_live_only_in_the_band(build: Build, ratios: BemtRatios) -> Array:
	var results: Array = []
	# The inflow alone GAINS thrust at fixed rpm (the stated reason a deficit is needed at all).
	var gain := BemtRatios.descent_thrust_ratio_inflow_only(1.0)
	var net := _thrust_at(ratios, 1.0)
	results.append(TestResult.new("the inflow fit alone predicts a thrust gain at 1.0 vh; with the deficit the net is a 15 percent loss",
		gain > 1.05 and absf(net - (1.0 - BemtRatios.vrs_mean_deficit())) < 1e-6,
		"fit-only %.4f, net %.4f" % [gain, net]))
	# Deficit = inflow-only minus net, and band weight; zero outside the band, positive inside, at several points.
	var inside_ok := true
	var outside_ok := true
	var detail := ""
	for x in [0.4, 0.7, 1.0, 1.3]:
		var def: float = BemtRatios.descent_thrust_ratio_inflow_only(x) - _thrust_at(ratios, x)
		if def <= 0.01 or BemtRatios.vrs_band_weight(x) <= 0.0:
			inside_ok = false
			detail += " in@%.1f:%.4f" % [x, def]
	for x in [0.0, 0.1, 0.25, 1.5, 1.8, 2.5, 4.0]:
		var def: float = BemtRatios.descent_thrust_ratio_inflow_only(x) - _thrust_at(ratios, x)
		var w: float = ratios.vrs_weight(RPM, -x * ratios.hover_inflow_mps(RPM), 0.0)
		if absf(def) > 1e-6 or w > 1e-6 or BemtRatios.vrs_band_weight(x) > 1e-6:
			outside_ok = false
			detail += " out@%.2f:%s" % [x, str(def)]
	results.append(TestResult.new("the thrust deficit exists inside 0.25 to 1.5 vh and is exactly zero at the edges and outside",
		inside_ok and outside_ok, "bad points:%s" % detail))
	# Fluctuation: run one rotor's thrust through the powertrain at a fixed rpm, count the spread.
	var spread_in := _thrust_spread(build, 1.0, 0.0, true)
	var spread_off := _thrust_spread(build, 1.0, 0.0, false)
	var spread_out := _thrust_spread(build, 0.1, 0.0, true)
	var spread_fast := _thrust_spread(build, 3.0, 0.0, true)
	var spread_edge := _thrust_spread(build, 0.25, 0.0, true)
	results.append(TestResult.new("the fluctuation: about 10 percent RMS at the peak, none with the flag off, none outside the band or on the windmill branch or at the band edge",
		spread_in > 0.06 and spread_in < 0.14 and spread_off < 2e-3 and spread_out < 2e-3 and spread_fast < 2e-3 and spread_edge < 2e-3,
		"peak %.4f, off %s, 0.1 vh %s, 3 vh %s, 0.25 vh %s" % [spread_in, str(spread_off), str(spread_out), str(spread_fast), str(spread_edge)]))
	# Independent per rotor.
	var core := build.build_drone_core({"off": true})
	core.prime_motors(build.hover_throttle())
	var vh: float = build.forward_ratios().hover_inflow_mps(float(core.powertrain.motor_rpm[0]))
	var cmds := PackedFloat64Array([build.hover_throttle(), build.hover_throttle(), build.hover_throttle(), build.hover_throttle()])
	var same := 0
	for _i in 600:
		core.powertrain.step_in_flight(cmds, 0.002, Vector3(0, -vh, 0))
		var t: PackedFloat32Array = core.powertrain.observables.thrust_n
		if absf(t[0] - t[1]) < 1e-9 and absf(t[1] - t[2]) < 1e-9:
			same += 1
	results.append(TestResult.new("the four rotors draw independent fluctuations (they are not equal on almost every tick)",
		same < 10, "%d of 600 ticks with three equal thrusts" % same))
	return results


## Relative RMS of one rotor's published thrust over 4 s at a held state.
static func _thrust_spread(build: Build, x: float, forward_mps: float, fluct_on: bool) -> float:
	var core := build.build_drone_core({"off": true})
	var thr := build.hover_throttle()
	core.prime_motors(thr)
	core.powertrain.vrs_fluctuation_on = fluct_on
	var vh: float = build.forward_ratios().hover_inflow_mps(float(core.powertrain.motor_rpm[0]))
	var cmds := PackedFloat64Array([thr, thr, thr, thr])
	var vals: Array = []
	for i in 2000:
		core.powertrain.step_in_flight(cmds, 0.002, Vector3(0, -x * vh, -forward_mps))
		if i >= 250:
			vals.append(float(core.powertrain.observables.thrust_n[0]))
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var ss := 0.0
	for v in vals:
		ss += (v - mean) * (v - mean)
	return sqrt(ss / vals.size()) / maxf(mean, 1e-9)


# ---- forward speed exits VRS --------------------------------------------------------------------------------

## TO MAKE THIS FAIL: make `vrs_forward_clear` return 1.0 regardless of the in-plane speed.
static func _forward_speed_exits_vrs(ratios: BemtRatios) -> TestResult:
	var vh := ratios.hover_inflow_mps(RPM)
	var pure := ratios.vrs_weight(RPM, -vh, 0.0)
	var drift := ratios.vrs_weight(RPM, -vh, 0.5 * vh)
	var fast := ratios.vrs_weight(RPM, -vh, 2.0 * vh)
	var t_pure := ratios.thrust_ratio(RPM, -vh, 0.0)
	var t_fwd := ratios.thrust_ratio(RPM, -vh, 2.0 * vh)
	return TestResult.new("forward speed clears VRS: full weight and a 15 percent loss in pure descent, none at 0.5 vh of drift, and the 2 vh edgewise thrust is no VRS loss",
		pure == 1.0 and drift == 0.0 and fast == 0.0 and t_pure < 0.9 and t_fwd > t_pure + 0.1,
		"weight pure %.3f, drift %.3f, fast %.3f; thrust pure %.3f, forward %.3f" % [pure, drift, fast, t_pure, t_fwd])


# ---- the full sim -------------------------------------------------------------------------------------------

## TO MAKE THESE FAIL: delete the `thrust *= self.vrs_fluctuation(...)` line AND set VRS_MEAN_DEFICIT to 0 (the 1 vh
## descent then behaves like the 0.2 vh one and the washout checks go red); make `vrs_forward_clear` always 1.0 (the
## forward-speed check goes red).
static func _sim_descent_washes_out(build: Build) -> Array:
	var vrs := fly_descent(build, 1.0, 0.0)
	var slow := fly_descent(build, 0.2, 0.0)
	var drift := fly_descent(build, 1.0, 3.0)
	var drift_slow := fly_descent(build, 0.2, 3.0)
	var line := "attitude wobble deg / peak rate rad/s / vertical-speed wobble m/s: 1 vh %.3f / %.3f / %.4f; 0.2 vh %.3f / %.3f / %.4f; 1 vh + 3 m/s %.3f / %.3f / %.4f; 0.2 vh + 3 m/s %.3f / %.3f / %.4f" % [
		vrs["wobble_deg"], vrs["rate"], vrs["vy_wobble"], slow["wobble_deg"], slow["rate"], slow["vy_wobble"],
		drift["wobble_deg"], drift["rate"], drift["vy_wobble"], drift_slow["wobble_deg"], drift_slow["rate"], drift_slow["vy_wobble"]]
	return [
		TestResult.new("a vertical descent at 1 vh washes out: more than twice the attitude wobble of the same descent at 0.2 vh",
			vrs["wobble_deg"] > 2.0 * slow["wobble_deg"] and vrs["rate"] > 5.0 * slow["rate"], line),
		TestResult.new("a vertical descent at 1 vh washes out: more than twice the altitude-rate wobble (altitude error) of the same descent at 0.2 vh",
			vrs["vy_wobble"] > 2.0 * slow["vy_wobble"], line),
		TestResult.new("the same 1 vh descent with 3 m/s forward speed does not wash out: its attitude wobble, rate and altitude-rate wobble stay near the 0.2 vh drift run",
			drift["wobble_deg"] < 1.5 * drift_slow["wobble_deg"] + 0.1 and drift["rate"] < 3.0 * drift_slow["rate"] + 0.02
			and drift["vy_wobble"] < 1.5 * drift_slow["vy_wobble"] + 0.02, line),
	]


## Flies a descent from `x0` hover inflows while it is still on the windmill branch (descent above 2.1 vh) and returns
## the peak tilt, the peak angular rate and how long it stayed there. It is a short window by nature: the windmill brake
## is a strong restoring force, and the aircraft sheds the excess speed in a few tenths of a second and then settles at
## the vortex-ring sink rate near 1.1 vh, which is the physical behaviour and the next regime, not part of this one.
static func fly_windmill(build: Build, x0: float) -> Dictionary:
	var core := build.build_drone_core({"off": true})
	var thr := build.hover_throttle_for(core.powertrain.battery)
	core.prime_motors(thr)
	var vh: float = build.forward_ratios().hover_inflow_mps(float(core.powertrain.motor_rpm[0]))
	core.rigid_body.position_m = Vector3(0, 500, 0)
	core.rigid_body.velocity_mps = Vector3(0, -x0 * vh, 0)
	var fc := FlightController.new()
	fc.rate_loop.adopt_tune(PidTunes.new().tune_for(build))
	fc.rate_loop.config = build.config
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": thr}
	var tilt := 0.0
	var rate := 0.0
	var steps := 0
	var vy0: float = core.rigid_body.velocity_mps.y
	for i in 1000:
		if -core.rigid_body.velocity_mps.y < 2.1 * vh:
			break
		var cmds := fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, rc, 0.002)
		core.step(cmds, 0.002)
		var up: Vector3 = core.rigid_body.orientation * Vector3.UP
		tilt = maxf(tilt, rad_to_deg(up.angle_to(Vector3.UP)))
		rate = maxf(rate, core.rigid_body.angular_velocity_rad_s.length())
		steps += 1
	return {"tilt_deg": tilt, "rate": rate, "steps": steps, "vy0": vy0, "vy1": core.rigid_body.velocity_mps.y}


## TO MAKE THIS FAIL: let `momentum_windmill` return x/2 + sqrt(x^2/4 - 1) (the other root: the thrust ratio then
## collapses, nothing brakes the fall and the aircraft stays beyond 2 vh), or remove the soft ceiling THRUST_GAIN_CAP
## (the gain runs past 5x and the aircraft is thrown upward), or make `descent_power_ratio` skip its floor (a negative
## power ratio charges the pack).
static func _fast_descent_is_stable_on_the_windmill_branch(build: Build) -> TestResult:
	var worst_tilt := 0.0
	var worst_rate := 0.0
	var restoring := true
	var spent := true
	for x in [2.5, 3.0, 4.0]:
		var r := fly_windmill(build, x)
		worst_tilt = maxf(worst_tilt, r["tilt_deg"])
		worst_rate = maxf(worst_rate, r["rate"])
		restoring = restoring and r["vy1"] > r["vy0"] + 1.0
		spent = spent and r["steps"] > 20 and r["steps"] < 1000
	var ratios := build.forward_ratios()
	var t25 := _thrust_at(ratios, 2.5)
	var t4 := _thrust_at(ratios, 4.0)
	var p4 := _power_at(ratios, 4.0)
	return TestResult.new("a fast descent beyond 2 vh is stable on the windmill branch: the aircraft brakes (descent speed falls, thrust ratio above 1 and capped), stays level and calm, and the power ratio stays positive",
		worst_tilt < 3.0 and worst_rate < 0.2 and restoring and spent and t25 > 1.0 and t4 >= t25 and t4 < 2.2 and p4 > 0.0,
		"peak tilt %.3f deg, peak rate %.3f rad/s, braking %s, window ok %s; thrust ratio %.3f at 2.5 vh, %.3f at 4 vh; power ratio %.3f at 4 vh" % [
			worst_tilt, worst_rate, str(restoring), str(spent), t25, t4, p4])
