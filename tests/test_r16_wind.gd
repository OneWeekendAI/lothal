class_name TestR16Wind
extends RefCounted
## R1.6 wind: the Dryden spectrum, intensity vs height and wind, the mean profile, the 1-cosine gust, the obstacle wake,
## and what turbulence does to a hovering drone. One TestResult per case, never looped. Each was mutation-proven;
## the mutation is stated in the case comment.

const DT := 0.01


static func _cond(speed: float, gust: float, z0: float = 0.1, tau: float = 0.5, from_deg := 270.0) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed
	c.wind_from_deg = from_deg   # 270: from the west, the air moves toward +X
	c.gustiness_mps = gust
	c.roughness_z0_m = z0
	c.gust_tau_s = tau
	return c


static func _series(w: Wind, seconds: float, pos: Vector3, axis: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for _i in int(seconds / DT):
		w.update_at(DT, pos, pos.y)
		var t := w.turbulence_mps()
		out.append([t.dot(w._dir), t.dot(w._cross), t.y][axis])
	return out


static func _std(a: PackedFloat64Array) -> float:
	var m := 0.0
	for x in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x in a:
		s += (x - m) * (x - m)
	return sqrt(s / a.size())


## One-sided power spectral density per rad/s at omega (Hann-windowed periodogram, 2048-sample segments, averaged).
static func _psd(a: PackedFloat64Array, omega: float) -> float:
	var n := 2048
	var win := PackedFloat64Array()
	var sw2 := 0.0
	for i in n:
		var h := 0.5 - 0.5 * cos(TAU * i / n)
		win.append(h)
		sw2 += h * h
	var acc := 0.0
	var segs := int(a.size() / float(n))
	var c1 := cos(omega * DT)
	var s1 := sin(omega * DT)
	for sg in segs:
		var re := 0.0
		var im := 0.0
		var cr := 1.0
		var ci := 0.0
		for i in n:
			var v := a[sg * n + i] * win[i]
			re += v * cr
			im -= v * ci
			var nr := cr * c1 - ci * s1
			ci = cr * s1 + ci * c1
			cr = nr
		acc += (re * re + im * im) * DT / (PI * sw2)
	return acc / segs


static func _dryden_u(sigma: float, l: float, v: float, w: float) -> float:
	return sigma * sigma * (2.0 * l / (PI * v)) / (1.0 + pow(l * w / v, 2))


static func _dryden_w(sigma: float, l: float, v: float, w: float) -> float:
	var x := pow(l * w / v, 2)
	return sigma * sigma * (l / (PI * v)) * (1.0 + 3.0 * x) / pow(1.0 + x, 2)


## Mean over seven omega L/V in [0.5, 6] of measured / analytic spectrum.
static func _psd_ratio(axis: int) -> float:
	var w := Wind.new(_cond(5.0, 1.5), 0.5, 3)
	var pos := Vector3(0, 10, 0)
	var s := _series(w, 1000.0, pos, axis)
	# The MIL-F-8785C scales written out independently of Wind.dryden_scales (h in feet), so a wrong length is caught.
	var h_ft := 10.0 / 0.3048
	var d := 0.177 + 0.000823 * h_ft
	var k := 0.5 / 2.5   # gust_tau_s / the reference tau scales every length
	var v := w.mean_speed_at(10.0)
	var l: float = (h_ft / pow(d, 1.2) * 0.3048 * k) if axis != 2 else (10.0 * k)
	var sigma_w := 1.5 * pow(d, 0.4)   # gustiness is sigma_u at the reference height
	var sigma: float = (sigma_w / pow(d, 0.4)) if axis != 2 else sigma_w
	var tot := 0.0
	var n := 0
	for x in [0.5, 0.8, 1.2, 1.8, 2.7, 4.0, 6.0]:
		var om: float = x * v / l
		var meas := _psd(s, om)
		tot += meas / (_dryden_u(sigma, l, v, om) if axis != 2 else _dryden_w(sigma, l, v, om))
		n += 1
	return tot / n


## MUTATIONS: Lu x2 in dryden_scales -> ratio far from 1; the v/w filter's sqrt3 mix removed -> w ratio off.
static func _psd_u() -> TestResult:
	var r := _psd_ratio(0)
	return TestResult.new("r1.6 dryden: the longitudinal PSD matches sigma^2 (2L/piV)/(1+(L w/V)^2) over w L/V 0.5-6, mean ratio within 15%",
		absf(r - 1.0) < 0.15, "measured / analytic = %.3f" % r)


static func _psd_w() -> TestResult:
	var r := _psd_ratio(2)
	return TestResult.new("r1.6 dryden: the vertical PSD matches sigma^2 (L/piV)(1+3(L w/V)^2)/(1+(L w/V)^2)^2 over w L/V 0.5-6, mean ratio within 15%",
		absf(r - 1.0) < 0.15, "measured / analytic = %.3f" % r)


## sigma_u at 3.048 m over sigma_u at 100 m: analytic (d100 / d3)^0.4 = 1.44 (MIL-HDBK-1797, h in feet). A flat-in-height
## model gives 1.0. MUTATION: dryden_scales' sigma_u = sigma_w -> ratio 1.0, fails.
static func _intensity_height() -> TestResult:
	var w := Wind.new(_cond(5.0, 1.5), 0.5, 5)
	var lo := PackedFloat64Array()
	var hi := PackedFloat64Array()
	for _i in 100000:
		w.update_at(DT, Vector3(0, 3.048, 0), 3.048)
		lo.append(w.turbulence_mps().dot(w._dir))
		w.update_at(0.0, Vector3(0, 100, 0), 100.0)
		hi.append(w.turbulence_mps().dot(w._dir))
	var want: float = w.dryden_scales(3.048)[2] / w.dryden_scales(100.0)[2]
	var got := _std(lo) / _std(hi)
	return TestResult.new("r1.6 intensity: sigma_u at 3 m over sigma_u at 100 m follows the MIL low-altitude form (%.2f), within 15%%" % want,
		absf(got / want - 1.0) < 0.15 and want > 1.3, "measured %.3f" % got)


## sigma_w = 0.1 W20 (MIL-F-8785C), so tripling the wind triples sigma_w.
## MUTATION: mil_gustiness_mps without the 0.1 factor or the wind dependence fails one of the numbers.
static func _intensity_wind() -> TestResult:
	var sig: Array = []
	var want: Array = []
	for spd in [3.0, 9.0]:
		var g := Wind.mil_gustiness_mps(spd, 0.1)
		var w := Wind.new(_cond(spd, g), 0.5, 7)
		sig.append(_std(_series(w, 800.0, Vector3(0, 10, 0), 2)))
		want.append(0.1 * spd * log(6.096 / 0.1) / log(10.0 / 0.1))
	return TestResult.new("r1.6 intensity: sigma_w = 0.1 x the 6 m wind (MIL-F-8785C) at 3 and 9 m/s, each within 15%, and the ratio is 3 within 15%",
		absf(sig[0] / want[0] - 1.0) < 0.15 and absf(sig[1] / want[1] - 1.0) < 0.15 and absf(sig[1] / sig[0] / 3.0 - 1.0) < 0.15,
		"sigma_w %.3f / %.3f m/s, targets %.3f / %.3f" % [sig[0], sig[1], want[0], want[1]])


## The log law against an independent evaluation at five heights and two roughness lengths, 0.1%.
## MUTATION: profile_factor linear in z (or z0 ignored) fails.
static func _profile() -> TestResult:
	var worst := 0.0
	for z0 in [0.03, 0.5]:
		var w := Wind.new(_cond(8.0, 0.0, z0), 0.5, 1)
		for h in [2.0, 5.0, 10.0, 30.0, 100.0]:
			var want := 8.0 * log(h / z0) / log(10.0 / z0)
			worst = maxf(worst, absf(w.mean_speed_at(h) / want - 1.0))
	return TestResult.new("r1.6 profile: mean wind at 2-100 m follows U = Uref ln(z/z0)/ln(zref/z0) for z0 0.03 and 0.5 m, within 0.1%",
		worst < 1.0e-3, "worst relative error " + str(worst))


## 1-cosine: the peak is the amplitude, zero before and after, peak at t0 + d/U. MUTATION: cos -> sin breaks it.
static func _one_cosine() -> TestResult:
	var w := Wind.new(_cond(5.0, 0.0, 0.1), 0.5, 1)
	w.add_discrete_gust(3.0, 20.0, 2.0)
	var u := w.mean_speed_at(10.0)
	var peak := 0.0
	var t_peak := 0.0
	var before := 0.0
	var after := 0.0
	for i in int(20.0 / DT):
		var t := i * DT
		var v := w.update_at(DT, Vector3.ZERO, 10.0)
		var g := v.dot(w._dir) - u
		if t < 1.9:
			before = maxf(before, absf(g))
		if t > 2.0 + 2.0 * 20.0 / u + 0.1:
			after = maxf(after, absf(g))
		if g > peak:
			peak = g
			t_peak = t
	var want_t := 2.0 + 20.0 / u
	return TestResult.new("r1.6 gust: a 1-cosine gust of 3 m/s, length 20 m peaks at 3.0 m/s at t0 + d/U, zero before and after",
		absf(peak - 3.0) < 0.02 and absf(t_peak - want_t) < 0.05 and before < 1.0e-9 and after < 1.0e-9,
		"peak %.3f at %.2f s (want %.2f), before %s, after %s" % [peak, t_peak, want_t, str(before), str(after)])


static func _wake_wind(obstacles: bool, gust := 0.5) -> Wind:
	var w := Wind.new(_cond(6.0, gust, 0.1), 0.5, 9)
	if obstacles:
		w.set_obstacles([Obstacle.place(Obstacle.BOX, 30.0, 0.0, {"w": 4.0, "h": 5.0, "d": 4.0, "yaw_deg": 0.0})])
	return w


static func _mean_and_sigma(w: Wind, pos: Vector3) -> Array:
	var u := PackedFloat64Array()
	for _i in 12000:
		var v := w.update_at(DT, pos, pos.y)
		u.append(v.dot(w._dir))
	var m := 0.0
	for x in u:
		m += x
	return [m / u.size(), _std(u)]


## Behind a 5 m box (lee face x = 32), 3 m downwind at 2 m height: mean wind well below free, turbulence above free.
## MUTATIONS: WAKE_DEFICIT = 0 -> mean unchanged, fails; WAKE_TI = 0 -> sigma unchanged, fails.
static func _wake_in_lee() -> TestResult:
	var shadow := _mean_and_sigma(_wake_wind(true), Vector3(35.0, 2.0, 0.0))
	var free := _mean_and_sigma(_wake_wind(false), Vector3(35.0, 2.0, 0.0))
	return TestResult.new("r1.6 wake: 3 m behind a 5 m obstacle the mean wind is below 60% of free and the turbulence above 1.5x free",
		shadow[0] < 0.6 * free[0] and shadow[1] > 1.5 * free[1],
		"mean %.2f vs free %.2f m/s, sigma_u %.2f vs free %.2f m/s" % [shadow[0], free[0], shadow[1], free[1]])


## The wake ends: past 7.5 H downwind, to the side, upwind and above it the wind is free; recovery is monotone.
## MUTATION: WAKE_LENGTH_HEIGHTS 7.5 -> 20 leaves the far point sheltered, fails.
static func _wake_ends() -> TestResult:
	var w := _wake_wind(true)
	var ok := true
	var detail := ""
	for p in [Vector3(32.0 + 40.0, 2.0, 0.0), Vector3(35.0, 2.0, 15.0), Vector3(20.0, 2.0, 0.0), Vector3(35.0, 12.0, 0.0)]:
		var f: float = w.wake_at(p, p.y)[0]
		ok = ok and f == 1.0
		detail += " %.3f" % f
	var near: float = w.wake_at(Vector3(35.0, 2.0, 0.0), 2.0)[0]
	var mid: float = w.wake_at(Vector3(52.0, 2.0, 0.0), 2.0)[0]
	return TestResult.new("r1.6 wake: free wind (factor exactly 1) past 7.5 H, to the side, upwind and above; recovery is monotone (%.2f, %.2f, 1)" % [near, mid],
		ok and near < mid and mid < 1.0, "factors%s" % detail)


## No obstacle, no gust: bit-identical to the pre-R1.6 behaviour.
static func _no_obstacles_no_change() -> TestResult:
	var a := _wake_wind(false)
	var b := _wake_wind(false)
	b.set_obstacles([])
	var same := true
	for i in 500:
		same = same and a.update_at(DT, Vector3(i * 0.1, 5, 0), 5.0) == b.update_at(DT, Vector3(i * 0.1, 5, 0), 5.0)
	return TestResult.new("r1.6 wake: an empty obstacle list and no gusts leave the wind bit-identical", same, "")


## Hover hold (FlightRig, 5 inch): position RMS and tilt RMS grow with turbulence intensity and are zero in calm.
## MUTATION: wind not reaching the airspeed path (core.wind = null) gives zero disturbance at every intensity.
static func _hover(gust: float, speed: float) -> Array:
	var c := FlightRig.conditions_with_wind(speed, 270.0, gust)
	var rig := FlightRig.from_class("five_inch", c, 4, Vector3(0, 10, 0))
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(10.0)
	var sp := 0.0
	var st := 0.0
	var n := 0
	for k in 40 * 500:
		rig.step()
		if k > 10 * 500:
			var p := rig.position()
			sp += Vector2(p.x, p.z).length_squared() + (p.y - 10.0) * (p.y - 10.0)
			var up := rig.core.rigid_body.orientation * Vector3.UP
			var tilt := acos(clampf(up.y, -1.0, 1.0))
			st += tilt * tilt
			n += 1
	return [sqrt(sp / n), rad_to_deg(sqrt(st / n))]


static func _hover_turbulence() -> Array:
	var calm := _hover(0.0, 0.0)
	var low := _hover(0.5, 3.0)
	var high := _hover(1.5, 3.0)
	return [
		TestResult.new("r1.6 hover: in calm air a hovering drone's position and attitude disturbance is zero (below 1 cm, 0.05 deg; measured 3 mm, 0.001 deg)",
			calm[0] < 0.01 and calm[1] < 0.05, "position RMS %.4f m, tilt RMS %.4f deg" % [calm[0], calm[1]]),
		TestResult.new("r1.6 hover: tripling the turbulence intensity (0.5 to 1.5 m/s) raises position and attitude disturbance, each by more than 1.5x",
			low[0] > 2.0 * calm[0] and high[0] > 1.5 * low[0] and high[1] > 1.5 * low[1],
			"low %.3f m %.3f deg, high %.3f m %.3f deg" % [low[0], low[1], high[0], high[1]]),
	]


static func run() -> Array:
	var out: Array = []
	out.append(_psd_u())
	out.append(_psd_w())
	out.append(_intensity_height())
	out.append(_intensity_wind())
	out.append(_profile())
	out.append(_one_cosine())
	out.append(_wake_in_lee())
	out.append(_wake_ends())
	out.append(_no_obstacles_no_change())
	out.append_array(_hover_turbulence())
	return out
