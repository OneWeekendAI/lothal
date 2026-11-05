class_name PropTunnel
extends RefCounted
## The wind tunnel's numbers (PD3), no UI. Every figure is one `BemtModel` forward solve at the stated
## condition: nothing is interpolated, extrapolated or fitted here.
##
## A result is `{ok: true, ...}` or `{ok: false, reason: "one line"}`, and a refusal has no figures in
## it, so it cannot render as a result. Descent is refused from the solve's own sentinel (residual
## -1, returned beside the STATIC answer), so there is one definition of descent. Thrust below zero
## ends a curve. Above Mach 0.7, or edgewise past the fast surface's reach, points stay on the curve
## and carry `flag`, because the model still answers but no longer deserves a solid line.
##
## Edgewise figures are thrust and power only: the closure is axisymmetric, so there is no
## advancing/retreating asymmetry, H-force or flapping moment to report (spec, "Tunnel: edgewise").
##
## TO MAKE THESE FAIL: see tests/test_prop_tunnel.gd.

const RHO_SEA_LEVEL := 1.225
## ISA sea level, m/s.
const SPEED_OF_SOUND_MPS := 340.3
const MACH_FLAG := 0.7
## Edge of `bemt_ratios.rs`'s surface (`MU_MAX`): V_edge / (Omega R). Past it flight is clamped.
const MU_EDGE_FLAG := 0.6
const J_STEP := 0.05
const J_LIMIT := 3.0
const ANGLE_STEP_DEG := 5.0
## Bisection steps for a curve's thrust-zero end, about 1e-6 of a step in J or angle.
const CROSSING_STEPS := 20
const STATION_STRIDE := 8

const REASON_DESCENT := "Descent: this model has no answer once air comes from below the disc."
const REASON_BLADE := "This blade cannot be solved: check diameter, blades and chord."
const REASON_RPM := "Set an rpm above zero."
const REASON_NO_THRUST := "This blade makes no thrust at this condition."
const FLAG_MACH := "Above Mach 0.7: the model ignores compressibility here."
const FLAG_EDGE := "Fast edgewise flow: this model has no blade asymmetry, so read a trend only."
const END_ZERO_THRUST := "Curve ends here: thrust reaches zero."
const END_J_LIMIT := "Curve stops at the sweep's limit, still making thrust."


## The solve's inputs, in SI, from a blade document. The document's own flown table, so a helix blade
## passes no table and takes the old path.
static func geometry_of(doc: PropellerDocument) -> Dictionary:
	return {
		"diameter_m": doc.diameter_mm * 0.001,
		"pitch_m": doc.pitch_mm * 0.001,
		"blades": float(doc.blades),
		"chord": doc.chord,
		"twist": doc.flown_twist(),
		"rho": RHO_SEA_LEVEL,
	}


## One condition. `{ok, thrust_n, torque_nm, power_w, tip_mach, mu_edge, flag}`.
static func point(g: Dictionary, rpm: float, v_axial: float, v_edge := 0.0) -> Dictionary:
	if rpm <= 0.0:
		return _refuse(REASON_RPM)
	var polar := BemtModel.global_polar()
	var r := BemtModel.solve_forward_with_guard(float(g.rho), float(g.diameter_m), float(g.pitch_m),
		float(g.blades), rpm, g.chord, polar[0], polar[1], polar[2], polar[3], v_axial, v_edge, 0.0, g.twist)
	if r[4] < 0.0:
		return _refuse(REASON_DESCENT)
	# The solve's degenerate return. A negative torque alone is a real windmilling answer, not this.
	if r[0] == 0.0 and r[1] == 0.0:
		return _refuse(REASON_BLADE)
	var omega_r: float = rpm * TAU / 60.0 * float(g.diameter_m) * 0.5
	var mach: float = tip_mach(float(g.diameter_m), rpm, v_axial, v_edge)
	var mu_edge: float = absf(v_edge) / omega_r
	var flag := ""
	if mach > MACH_FLAG:
		flag = FLAG_MACH
	elif mu_edge > MU_EDGE_FLAG:
		flag = FLAG_EDGE
	return {
		"ok": true, "thrust_n": r[0], "torque_nm": r[1], "power_w": r[1] * rpm * TAU / 60.0,
		"tip_mach": mach, "mu_edge": mu_edge, "flag": flag,
	}


## The advancing tip, the fastest air on the disc. Axially this is the helical tip speed. `sound_mps`
## is there for one reason: APC's files use 1100 ft/s (335.28 m/s), and this tunnel uses the 15 C
## air its density already is, so APC's column is only reproducible by naming its constant.
static func tip_mach(diameter_m: float, rpm: float, v_axial := 0.0, v_edge := 0.0,
		sound_mps := SPEED_OF_SOUND_MPS) -> float:
	var tangential: float = rpm * TAU / 60.0 * diameter_m * 0.5 + absf(v_edge)
	return sqrt(tangential * tangential + v_axial * v_axial) / sound_mps


## Airspeed sweep straight into the disc at a set rpm: Ct, Cp and efficiency against J, from J = 0
## to the J where thrust reaches zero. `{ok, points, j0, end, end_reason}`; `j0` is -1 if the sweep
## stopped first.
static func axial_sweep(g: Dictionary, rpm: float) -> Dictionary:
	var first := _axial_point(g, rpm, 0.0)
	if not first.ok:
		return first
	if float(first.thrust_n) <= 0.0:
		return _refuse(REASON_NO_THRUST)
	var points: Array = [first]
	var steps := roundi(J_LIMIT / J_STEP)
	for i in range(1, steps + 1):
		var j: float = i * J_STEP
		var p := _axial_point(g, rpm, j)
		if not p.ok:
			return p
		if float(p.thrust_n) > 0.0:
			points.append(p)
			continue
		var lo: float = (i - 1) * J_STEP
		var hi: float = j
		for _s in CROSSING_STEPS:
			var mid: float = 0.5 * (lo + hi)
			if float(_axial_point(g, rpm, mid).thrust_n) > 0.0:
				lo = mid
			else:
				hi = mid
		var last := _axial_point(g, rpm, lo)
		points.append(last)
		return {"ok": true, "points": points, "j0": lo, "end": "zero_thrust", "end_reason": END_ZERO_THRUST}
	return {"ok": true, "points": points, "j0": -1.0, "end": "j_limit", "end_reason": END_J_LIMIT}


## Flow angle sweep at a set rpm and airspeed, 0 = straight into the disc, 90 = edgewise. Thrust and
## power only. Where the axial part unloads the rotor the curve STARTS at the angle thrust returns.
## `{ok, points, start_angle_deg, start_reason}`, each point also carrying its angle and two speeds.
static func flow_angle_sweep(g: Dictionary, rpm: float, airspeed: float) -> Dictionary:
	if airspeed < 0.0:
		return _refuse(REASON_DESCENT)
	var points: Array = []
	var start_reason := ""
	var prev := -1.0
	for i in range(0, roundi(90.0 / ANGLE_STEP_DEG) + 1):
		var angle: float = i * ANGLE_STEP_DEG
		var p := _angle_point(g, rpm, airspeed, angle)
		if not p.ok:
			return p
		if float(p.thrust_n) <= 0.0:
			prev = angle
			continue
		if points.is_empty() and prev >= 0.0:
			var lo := prev
			var hi := angle
			for _s in CROSSING_STEPS:
				var mid: float = 0.5 * (lo + hi)
				if float(_angle_point(g, rpm, airspeed, mid).thrust_n) > 0.0:
					hi = mid
				else:
					lo = mid
			points.append(_angle_point(g, rpm, airspeed, hi))
			start_reason = "No thrust at shallower angles at this airspeed."
		points.append(p)
	if points.is_empty():
		return _refuse(REASON_NO_THRUST)
	return {"ok": true, "points": points, "start_angle_deg": points[0].angle_deg, "start_reason": start_reason}


## One flow angle. Past 90 the axial part is negative, which `point` refuses as descent.
static func flow_angle_point(g: Dictionary, rpm: float, airspeed: float, angle_deg: float) -> Dictionary:
	return _angle_point(g, rpm, airspeed, angle_deg)


## What each station is doing at one condition, hub to tip: `{ok, stations, thrust_n, torque_nm}`, a
## station being `{r_m, r_frac, alpha_rad, phi_rad, cl, cd, thrust_n, torque_nm, u_mps}`. `thrust_n`
## is the sum over the stations returned.
static func stations(g: Dictionary, rpm: float, v_axial: float, v_edge := 0.0) -> Dictionary:
	var check := point(g, rpm, v_axial, v_edge)
	if not check.ok:
		return check
	var rows := BemtModel.forward_stations(float(g.rho), float(g.diameter_m), float(g.pitch_m),
		float(g.blades), rpm, g.chord, v_axial, v_edge, 0.0, g.twist)
	var out: Array = []
	var thrust := 0.0
	var torque := 0.0
	var radius: float = float(g.diameter_m) * 0.5
	for i in range(0, rows.size(), STATION_STRIDE):
		out.append({
			"r_m": rows[i], "r_frac": rows[i] / radius, "alpha_rad": rows[i + 1], "phi_rad": rows[i + 2],
			"cl": rows[i + 3], "cd": rows[i + 4], "thrust_n": rows[i + 5], "torque_nm": rows[i + 6],
			"u_mps": rows[i + 7],
		})
		thrust += rows[i + 5]
		torque += rows[i + 6]
	return {"ok": true, "stations": out, "thrust_n": thrust, "torque_nm": torque}


static func _axial_point(g: Dictionary, rpm: float, j: float) -> Dictionary:
	var n: float = rpm / 60.0
	var d: float = float(g.diameter_m)
	var p := point(g, rpm, j * n * d)
	if not p.ok:
		return p
	var rho: float = float(g.rho)
	p["j"] = j
	p["v_mps"] = j * n * d
	p["ct"] = float(p.thrust_n) / (rho * n * n * pow(d, 4.0))
	p["cp"] = float(p.power_w) / (rho * pow(n, 3.0) * pow(d, 5.0))
	p["eta"] = float(p.thrust_n) * float(p.v_mps) / float(p.power_w) if float(p.power_w) > 0.0 else 0.0
	return p


static func _angle_point(g: Dictionary, rpm: float, airspeed: float, angle_deg: float) -> Dictionary:
	var rad := deg_to_rad(angle_deg)
	# Exact at the ends: cos(90 deg) is 6e-17 in floats, which would be a real axial component.
	var v_axial: float = 0.0 if angle_deg == 90.0 else airspeed * cos(rad)
	var v_edge: float = airspeed * sin(rad)
	var p := point(g, rpm, v_axial, v_edge)
	if not p.ok:
		return p
	p["angle_deg"] = angle_deg
	p["v_axial_mps"] = v_axial
	p["v_edge_mps"] = v_edge
	return p


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
