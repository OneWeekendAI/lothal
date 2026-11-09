class_name TestSr2Wind
extends RefCounted
## SR2 atmosphere and wind: humidity in density, log-law shear, Dryden turbulence (MIL-F-8785C), frozen-field
## spatial variation (src/sim/wind.gd, src/course/air_density.gd). One TestResult per case, never looped.
## FAIL-PROOFS are recorded in the plan (sim-reality-plan, SR2) with the observed values.

const SEED := 11
const H := 10.0   # sampled height AGL, m (a bin height, so V is the 10 m mean speed)


static func _cond(speed: float, gust: float, z0: float = 0.1, tau: float = 2.5) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed
	c.wind_from_deg = 270.0     # from the west, air moves toward +X
	c.gustiness_mps = gust
	c.roughness_z0_m = z0
	c.gust_tau_s = tau
	return c


## Runs `seconds` at dt 0.01 at `pos`, returns the turbulence vector series projected on (along, cross, vertical).
static func _series(w: Wind, seconds: float, pos: Vector3 = Vector3(0, H, 0)) -> Array:
	var u := PackedFloat64Array()
	var v := PackedFloat64Array()
	var z := PackedFloat64Array()
	for _i in int(seconds / 0.01):
		w.update_at(0.01, pos, pos.y)
		var t := w.turbulence_mps()
		u.append(t.dot(w._dir))
		v.append(t.dot(w._cross))
		z.append(t.y)
	return [u, v, z]


static func _std(a: PackedFloat64Array) -> float:
	var m := 0.0
	for x in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x in a:
		s += (x - m) * (x - m)
	return sqrt(s / a.size())


static func _acf(a: PackedFloat64Array, lag: int) -> float:
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


static func run() -> Array:
	var out: Array = []
	out.append(_seed_same())
	out.append(_seed_different())
	out.append(_shear_law())
	out.append(_shear_numbers())
	out.append(_humidity_less_dense())
	out.append(_humidity_matches_partial_pressures())
	out.append(_humidity_zero_is_dry())
	out.append(_worked_example())
	var s := _series(Wind.new(_cond(6.705, Wind.mil_gustiness_mps(6.705, 0.1)), 2.5, SEED), 1500.0)
	out.append(_intensity("u", s[0], 0))
	out.append(_intensity("v", s[1], 1))
	out.append(_intensity("w", s[2], 2))
	out.append(_anisotropy(s))
	out.append(_spectrum_u(s[0]))
	out.append(_spectrum_w(s[2]))
	out.append(_frozen_advection())
	out.append(_two_points_differ())
	out.append(_crosswind_decorrelates())
	out.append(_tau_scales_length())
	out.append(_calm_has_no_turbulence())
	out.append(_legacy_fallback_unchanged())
	out.append(_conditions_roundtrip())
	out.append(_hold_in_20_mph())
	return out


static func _seq(seed_value: int) -> PackedVector3Array:
	var w := Wind.new(_cond(6.0, 1.0), 2.5, seed_value)
	var o := PackedVector3Array()
	for _i in 500:
		o.append(w.update_at(0.01, Vector3(3, 10, 4), 10.0))
	return o


static func _seed_same() -> TestResult:
	var a := _seq(5)
	var b := _seq(5)
	return TestResult.new("sr2 seed: the same seed gives identical samples over 500 steps", a == b,
		"first %s vs %s" % [a[0], b[0]])


static func _seed_different() -> TestResult:
	var a := _seq(5)
	var b := _seq(6)
	var diff := 0.0
	for i in a.size():
		diff = maxf(diff, (a[i] - b[i]).length())
	return TestResult.new("sr2 seed: a different seed gives different samples (max difference over 500 steps > 0.1 m/s)", diff > 0.1, "max diff %.3f m/s" % diff)


static func _shear_law() -> TestResult:
	var w := Wind.new(_cond(6.705, 0.0), 2.5, SEED)
	var r := w.mean_speed_at(60.0) / w.mean_speed_at(2.0)
	var law := log(60.0 / 0.1) / log(2.0 / 0.1)
	return TestResult.new("sr2 shear: mean wind at 60 m exceeds 2 m by the log law ratio ln(60/z0)/ln(2/z0) = %.3f (z0 0.1 m), within 0.1%%" % law,
		w.mean_speed_at(60.0) > w.mean_speed_at(2.0) and absf(r / law - 1.0) < 0.001, "measured ratio %.4f" % r)


static func _shear_numbers() -> TestResult:
	var w := Wind.new(_cond(6.705, 0.0), 2.5, SEED)
	var at_ref := w.mean_speed_at(10.0)
	# the same value must reach the flown wind vector: update_at at 60 m and 2 m, no turbulence
	var v60 := w.update_at(0.01, Vector3(0, 60, 0), 60.0).length()
	var v2 := w.update_at(0.01, Vector3(0, 2, 0), 2.0).length()
	return TestResult.new("sr2 shear: the wind vector the drone is flown in follows the profile (10 m = typed speed; 60 m and 2 m match the law)",
		absf(at_ref - 6.705) < 1e-9 and absf(v60 - w.mean_speed_at(60.0)) < 1e-4 and absf(v2 - w.mean_speed_at(2.0)) < 1e-4,
		"10 m %.3f, 60 m flown %.3f, 2 m flown %.3f" % [at_ref, v60, v2])


static func _humidity_less_dense() -> TestResult:
	var dry := AirDensity.new(0.0, 30.0, 0.0).kgm3()
	var wet := AirDensity.new(0.0, 30.0, 80.0).kgm3()
	var drop := 1.0 - wet / dry
	return TestResult.new("sr2 humidity: air at 30 C and 80 percent RH is less dense than dry air at 30 C, by 0.5 to 2 percent",
		wet < dry and drop > 0.005 and drop < 0.02, "dry %.4f, humid %.4f kg/m3, drop %.2f%%" % [dry, wet, drop * 100.0])


## Independent route: partial pressures. rho = (p - e)/(Rd T) + e/(Rv T), Rv = 461.5 J/(kg K).
static func _humidity_matches_partial_pressures() -> TestResult:
	var a := AirDensity.new(920.0, 35.0, 60.0)
	var t := 35.0 + 273.15
	var e := a.vapour_pressure_pa()
	var p := a.pressure_pa()
	var rho := (p - e) / (287.058 * t) + e / (461.5 * t)
	return TestResult.new("sr2 humidity: the virtual-temperature density matches the partial-pressure sum (Dalton) within 0.1 percent at 920 m, 35 C, 60 percent RH",
		absf(a.kgm3() / rho - 1.0) < 0.001, "virtual-T %.5f vs Dalton %.5f kg/m3" % [a.kgm3(), rho])


static func _humidity_zero_is_dry() -> TestResult:
	var a := AirDensity.new(920.0, 35.0)
	var raw := a.pressure_pa() / (287.058 * (35.0 + 273.15))
	return TestResult.new("sr2 humidity: 0 percent RH reproduces the old dry density exactly (no golden moves)", a.kgm3() == raw, "%.9f vs %.9f" % [a.kgm3(), raw])


static func _worked_example() -> TestResult:
	var w := Wind.new(_cond(15.0 * 0.44704, 0.0, 0.10), 2.5, SEED)
	var s2 := w.mean_speed_at(2.0)
	var s30 := w.mean_speed_at(30.0)
	var s60 := w.mean_speed_at(60.0)
	print("  SR2 worked example: 15 mph (6.705 m/s) at 10 m over short crops (z0 0.10 m), log law U(z)=U10 ln(z/z0)/ln(10/z0): 2 m %.2f m/s (%.1f mph), 10 m %.2f, 30 m %.2f m/s (%.1f mph), 60 m %.2f m/s (%.1f mph)" % [
		s2, s2 / 0.44704, w.mean_speed_at(10.0), s30, s30 / 0.44704, s60, s60 / 0.44704])
	return TestResult.new("sr2 worked example: 15 mph at 10 m over short crops gives 4.36 / 8.31 / 9.31 m/s at 2 / 30 / 60 m (by hand from the log law)",
		absf(s2 - 4.362) < 0.01 and absf(s30 - 8.305) < 0.01 and absf(s60 - 9.314) < 0.01, "%.3f %.3f %.3f" % [s2, s30, s60])


## Target: sigma_u,v at 10 m = typed gustiness (= MIL value for this wind), sigma_w = sigma_w_ref.
static func _intensity(axis: String, a: PackedFloat64Array, ax: int) -> TestResult:
	var w := Wind.new(_cond(6.705, Wind.mil_gustiness_mps(6.705, 0.1)), 2.5, SEED)
	var sc: Array = w.dryden_scales(H)
	var target: float = sc[2] if ax < 2 else sc[3]
	var got := _std(a)
	return TestResult.new("sr2 turbulence: measured sigma_%s over 1500 s at 10 m is within 15%% of the Dryden target (%.3f m/s)" % [axis, target],
		absf(got / target - 1.0) < 0.15, "measured %.3f m/s (%.1f%% off)" % [got, (got / target - 1.0) * 100.0])


static func _anisotropy(s: Array) -> TestResult:
	var su := _std(s[0])
	var sw := _std(s[2])
	var d := 0.177 + 0.000823 * (H / 0.3048)
	var want := pow(d, 0.4)   # sigma_w / sigma_u = (0.177 + 0.000823 h)^0.4
	return TestResult.new("sr2 turbulence: the axes are anisotropic, sigma_w/sigma_u = (0.177+0.000823 h)^0.4 = %.2f at 10 m (within 15%%)" % want,
		absf(sw / su / want - 1.0) < 0.15 and sw < 0.8 * su, "measured ratio %.3f" % (sw / su))


## SPECTRUM CHECK (time-domain equivalent of the Dryden PSD, a Fourier pair): at the 10 m bin V = U(10 m).
## Longitudinal autocorrelation is exp(-xi/Lu): 0.368 at xi = Lu and 0.135 at 2 Lu.
static func _spectrum_u(u: PackedFloat64Array) -> TestResult:
	var w := Wind.new(_cond(6.705, 1.0), 2.5, SEED)
	var sc: Array = w.dryden_scales(H)
	var lag := int(sc[0] / w.mean_speed_at(H) / 0.01)
	var r1 := _acf(u, lag)
	var r2 := _acf(u, 2 * lag)
	return TestResult.new("sr2 spectrum: u autocorrelation follows Dryden exp(-xi/Lu): 0.37 +-0.08 at xi=Lu and 0.14 +-0.06 at 2 Lu",
		absf(r1 - 0.368) < 0.08 and absf(r2 - 0.135) < 0.06, "r(Lu)=%.3f r(2Lu)=%.3f (lag %d samples)" % [r1, r2, lag])


## Transverse (w) autocorrelation is (1 - xi/2L) exp(-xi/L): 0.18 at L, ZERO at 2L (u would still be 0.135).
static func _spectrum_w(wv: PackedFloat64Array) -> TestResult:
	var w := Wind.new(_cond(6.705, 1.0), 2.5, SEED)
	var sc: Array = w.dryden_scales(H)
	var lag := int(sc[1] / w.mean_speed_at(H) / 0.01)
	var r1 := _acf(wv, lag)
	var r2 := _acf(wv, 2 * lag)
	return TestResult.new("sr2 spectrum: w autocorrelation follows the Dryden transverse form (1-xi/2L)exp(-xi/L): 0.18 +-0.08 at xi=Lw, 0.00 +-0.07 at 2 Lw",
		absf(r1 - 0.184) < 0.08 and absf(r2) < 0.07, "r(Lw)=%.3f r(2Lw)=%.3f (lag %d samples)" % [r1, r2, lag])


## Taylor: a point downwind by U*5 s sees at time t what the origin saw at t-5 s.
static func _frozen_advection() -> TestResult:
	var w := Wind.new(_cond(6.705, 1.0), 2.5, SEED)
	var origin := Vector3(0, H, 0)
	var hist: Array[Vector3] = []
	for _i in 3000:
		w.update_at(0.01, origin, H)
		hist.append(w.turbulence_mps())
	var u_loc := w.mean_speed_at(H)
	var downwind := w._dir * (u_loc * 5.0) + Vector3(0, H, 0)
	w.update_at(0.0, downwind, H)
	var there := w.turbulence_mps()
	var then := hist[hist.size() - 1 - 500]
	var err := (there - then).length()
	return TestResult.new("sr2 space: a point U*5 s downwind feels at time t the gust the origin felt at t-5 s (frozen turbulence), within 0.05 m/s",
		err < 0.05 and then.length() > 0.1, "difference %.4f m/s, gust size %.3f m/s" % [err, then.length()])


static func _two_points_differ() -> TestResult:
	var w := Wind.new(_cond(6.705, 1.0), 2.5, SEED)
	var maxd := 0.0
	for _i in 3000:
		w.update_at(0.01, Vector3.ZERO, H)
		var a := w.turbulence_mps()
		w.update_at(0.0, w._dir * 200.0 + Vector3(0, H, 0), H)
		var b := w.turbulence_mps()
		maxd = maxf(maxd, (a - b).length())
	return TestResult.new("sr2 space: two points 200 m apart along the wind feel different gusts at the same instant (max difference over 30 s above 0.5 m/s)",
		maxd > 0.5, "max difference %.3f m/s" % maxd)


static func _crosswind_decorrelates() -> TestResult:
	var w := Wind.new(_cond(6.705, 1.0), 2.5, SEED)
	var a := PackedFloat64Array()
	var b := PackedFloat64Array()
	var near := PackedFloat64Array()
	for _i in 60000:
		w.update_at(0.01, Vector3(0, H, 0), H)
		a.append(w.turbulence_mps().dot(w._dir))
		w.update_at(0.0, w._cross * 2.0 + Vector3(0, H, 0), H)
		near.append(w.turbulence_mps().dot(w._dir))
		w.update_at(0.0, w._cross * 100.0 + Vector3(0, H, 0), H)
		b.append(w.turbulence_mps().dot(w._dir))
	var rn := _corr(a, near)
	var rf := _corr(a, b)
	return TestResult.new("sr2 space: gusts 2 m apart crosswind correlate (> 0.9), 100 m apart barely (< 0.3)", rn > 0.9 and rf < 0.3,
		"corr(2 m) %.3f, corr(100 m) %.3f" % [rn, rf])


static func _corr(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var ma := 0.0
	var mb := 0.0
	for i in a.size():
		ma += a[i]
		mb += b[i]
	ma /= a.size()
	mb /= a.size()
	var n := 0.0
	var da := 0.0
	var db := 0.0
	for i in a.size():
		n += (a[i] - ma) * (b[i] - mb)
		da += (a[i] - ma) * (a[i] - ma)
		db += (b[i] - mb) * (b[i] - mb)
	return n / sqrt(da * db)


## The old "Gust settle" field keeps a wire: it scales every length scale by tau / 2.5.
static func _tau_scales_length() -> TestResult:
	var fast := _series(Wind.new(_cond(6.705, 1.0, 0.1, 2.5), 2.5, SEED), 600.0)
	var slow := _series(Wind.new(_cond(6.705, 1.0, 0.1, 5.0), 5.0, SEED), 600.0)
	var ts := _integral_time(slow[0])
	var tf := _integral_time(fast[0])
	return TestResult.new("sr2 mapping: doubling the old gust_tau_s doubles the turbulence length scale (integral time ratio 2 +-0.5)",
		absf(ts / tf - 2.0) < 0.5, "integral times %.2f s vs %.2f s (ratio %.2f)" % [tf, ts, ts / tf])


static func _integral_time(a: PackedFloat64Array) -> float:
	var t := 0.0
	for k in range(1, 3000, 10):
		var r := _acf(a, k)
		if r <= 0.0:
			break
		t += r * 0.1
	return t


static func _calm_has_no_turbulence() -> TestResult:
	var w := Wind.new(_cond(5.0, 0.0), 2.5, SEED)
	var worst := 0.0
	for _i in 200:
		worst = maxf(worst, (w.update_at(0.01, Vector3.ZERO, 10.0) - w.mean_at(10.0)).length())
	return TestResult.new("sr2 mapping: gustiness 0 gives exactly the mean wind (no turbulence)", worst == 0.0, "max deviation %.6f" % worst)


static func _legacy_fallback_unchanged() -> TestResult:
	var a := Wind.new(_cond(5.0, 1.0), 2.5, SEED, Wind.Model.FIRST_ORDER)
	var b := Wind.new(_cond(5.0, 1.0), 2.5, SEED, Wind.Model.FIRST_ORDER)
	var va := a.update_at(0.01, Vector3(0, 60, 0), 60.0)
	var vb := b.update(0.01)
	return TestResult.new("sr2 mapping: the FIRST_ORDER fallback is height-blind and equals the legacy update()", va == vb and absf(va.y) < 1.0 and absf(a.steady_mps.length() - 5.0) < 1e-9,
		"%s vs %s" % [va, vb])


static func _conditions_roundtrip() -> TestResult:
	var c := _cond(5.0, 1.0)
	c.humidity_pct = 65.0
	c.wind_ref_height_m = 8.0
	var d := Conditions.from_data(c.to_data())
	var old := Conditions.from_data({"id": "x", "name": "x", "wind_speed_mps": 3.0})
	return TestResult.new("sr2 conditions: humidity, z0 and reference height round-trip; a pre-SR2 file reads as dry, open grass, 10 m",
		d.humidity_pct == 65.0 and d.roughness_z0_m == 0.1 and d.wind_ref_height_m == 8.0
		and old.humidity_pct == 0.0 and old.roughness_z0_m == 0.03 and old.wind_ref_height_m == 10.0, "ok")


## 7 inch long range holds height and position in 20 mph (8.94 m/s at 10 m) with MIL turbulence (sigma_u 1.5 m/s).
## Measured 2026-11-09: altitude max 0.42 m, radius max 0.33 m over 100 s after a 20 s settle. Limits 1.0 m each.
static func _hold_in_20_mph() -> TestResult:
	var spd := 20.0 * 0.44704
	var c := FlightRig.conditions_with_wind(spd, 90.0, Wind.mil_gustiness_mps(spd, 0.03))
	var rig := FlightRig.from_class("seven_lr", c, 3, Vector3(0, 10, 0))
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(10.0)
	var worst_z := 0.0
	var worst_r := 0.0
	for k in 120 * 500:
		rig.step()
		if k > 20 * 500:
			var p := rig.position()
			worst_z = maxf(worst_z, absf(p.y - 10.0))
			worst_r = maxf(worst_r, Vector2(p.x, p.z).length())
	return TestResult.new("sr2 autopilot: seven_lr holds height within 1.0 m and position within 1.0 m for 100 s in 20 mph wind with MIL turbulence",
		worst_z < 1.0 and worst_r < 1.0, "altitude max %.2f m, radius max %.2f m" % [worst_z, worst_r])
