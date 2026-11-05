class_name TestPropTunnel
extends RefCounted
## PD3: the tunnel reports the shipped forward solve and nothing else, and refuses what that solve
## cannot answer. Each direct figure here is a separate `BemtModel` call, never a `PropTunnel` one.
##
## TO MAKE THESE FAIL: return the static answer on descent (`PropTunnel.point`'s sentinel check);
## solve one J step ahead of the J reported (`_axial_point`); stop one row early in `stations`; move
## or drop MACH_FLAG; let `axial_sweep` keep points past zero thrust.

const RPM := 12000.0


static func run() -> Array:
	var results: Array = []
	results.append(_axial_figures_equal_the_direct_solve())
	results.append(_a_table_reaches_the_tunnel())
	results.append(_efficiency_is_the_definition())
	results.append(_descent_is_a_refusal_with_no_figures())
	results.append(_flow_past_ninety_is_descent())
	results.append(_curve_ends_at_thrust_zero())
	results.append(_a_flat_blade_is_refused())
	results.append(_flow_angle_figures_equal_the_direct_solve())
	results.append(_edgewise_carries_thrust_and_power_only())
	results.append(_a_fast_axial_flow_starts_the_angle_curve_late())
	results.append(_stations_sum_to_the_totals())
	results.append(_stations_at_hover_sum_to_the_hover_total())
	results.append(_station_angle_is_blade_minus_inflow())
	results.append(_mach_flag_falls_at_the_line())
	results.append(_edge_flag_needs_fast_edgewise())
	results.append(_bad_rpm_is_refused())
	return results


static func _geometry() -> Dictionary:
	var catalog := PartsCatalog.load_default()
	return PropTunnel.geometry_of(PropellerDocument.from_catalog_prop(catalog.get_part(ReferenceBuild.PROPELLER_ID)))


static func _direct(g: Dictionary, rpm: float, v_ax: float, v_ed: float) -> PackedFloat64Array:
	var polar := BemtModel.global_polar()
	return BemtModel.solve_forward_with_guard(g.rho, g.diameter_m, g.pitch_m, g.blades, rpm, g.chord,
		polar[0], polar[1], polar[2], polar[3], v_ax, v_ed, 0.0, g.twist)


static func _axial_figures_equal_the_direct_solve() -> TestResult:
	var g := _geometry()
	var sweep := PropTunnel.axial_sweep(g, RPM)
	var n: float = RPM / 60.0
	var d: float = g.diameter_m
	var bad := ""
	for i in sweep.points.size() - 1:
		var p: Dictionary = sweep.points[i]
		var j: float = i * PropTunnel.J_STEP
		var r := _direct(g, RPM, j * n * d, 0.0)
		var ct: float = r[0] / (g.rho * n * n * pow(d, 4.0))
		var cp: float = r[1] * TAU * n / (g.rho * pow(n, 3.0) * pow(d, 5.0))
		if p.j != j or p.thrust_n != r[0] or p.torque_nm != r[1] \
				or absf(p.ct - ct) > 1e-12 or absf(p.cp - cp) > 1e-12:
			bad += " J%.2f" % j
	return TestResult.new("tunnel: every swept J equals a direct solve_forward at that J",
		bad == "" and sweep.points.size() > 5, "%d points, wrong at:%s" % [sweep.points.size(), bad])


## Authored twist has to arrive, or a designer's twist edit moves nothing on the chart.
static func _a_table_reaches_the_tunnel() -> TestResult:
	var p: Dictionary = PropGap.props()["apcff_4.2x4"]
	var doc := PropellerDocument.new()
	doc.diameter_mm = float(p["diameter_in"]) * 25.4
	doc.pitch_mm = float(p["pitch_in"]) * 25.4
	doc.blades = int(p["blades"])
	doc.chord = PropGap.chord_of(p)
	var helix := PropTunnel.axial_sweep(PropTunnel.geometry_of(doc), float(p["run_rpm"]))
	doc.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED
	doc.twist = PropGap.twist_of(p)
	var authored := PropTunnel.axial_sweep(PropTunnel.geometry_of(doc), float(p["run_rpm"]))
	var want := PropGap.model_figures(p, PropGap.twist_of(p))
	# PropGap scans J0 in steps of its own J_STEP, so it agrees to within one.
	return TestResult.new("tunnel: an authored table moves J0, to the figure the gap report gets",
		absf(float(authored.j0) - float(want.j0)) <= PropGap.J_STEP and float(authored.j0) - float(helix.j0) >= 0.05,
		"helix %.3f, authored %.3f, gap report %.3f" % [helix.j0, authored.j0, want.j0])


static func _efficiency_is_the_definition() -> TestResult:
	var sweep := PropTunnel.axial_sweep(_geometry(), RPM)
	var bad := 0
	var peak := 0.0
	for p: Dictionary in sweep.points:
		if absf(float(p.eta) - float(p.j) * float(p.ct) / float(p.cp)) > 1e-12:
			bad += 1
		peak = maxf(peak, p.eta)
	return TestResult.new("tunnel: efficiency is J Ct / Cp, zero at rest, below 1 at its peak",
		bad == 0 and sweep.points[0].eta == 0.0 and peak > 0.2 and peak < 1.0, "peak %.3f, %d wrong" % [peak, bad])


static func _is_bare_refusal(r: Dictionary) -> bool:
	return not r.ok and String(r.reason) != "" and r.size() == 2


static func _descent_is_a_refusal_with_no_figures() -> TestResult:
	var g := _geometry()
	var p := PropTunnel.point(g, RPM, -1.0)
	var s := PropTunnel.stations(g, RPM, -1.0)
	var rows := BemtModel.forward_stations(g.rho, g.diameter_m, g.pitch_m, g.blades, RPM, g.chord, -1.0, 0.0, 0.0, g.twist)
	return TestResult.new("tunnel: descent is a refusal with no figures, at point, stations and the tap",
		_is_bare_refusal(p) and p.reason == PropTunnel.REASON_DESCENT and _is_bare_refusal(s) and rows.is_empty(),
		"point %s, stations %s, tap rows %d" % [p, s.keys(), rows.size()])


static func _flow_past_ninety_is_descent() -> TestResult:
	var g := _geometry()
	var over := PropTunnel.flow_angle_point(g, RPM, 10.0, 120.0)
	var at := PropTunnel.flow_angle_point(g, RPM, 10.0, 90.0)
	return TestResult.new("tunnel: flow from below the disc refuses, exactly edgewise does not",
		_is_bare_refusal(over) and at.ok and at.v_axial_mps == 0.0, "120: %s, 90: %s" % [over, at])


static func _curve_ends_at_thrust_zero() -> TestResult:
	var g := _geometry()
	var sweep := PropTunnel.axial_sweep(g, RPM)
	var last: Dictionary = sweep.points[-1]
	var static_t: float = sweep.points[0].thrust_n
	var n: float = RPM / 60.0
	var beyond := _direct(g, RPM, (float(sweep.j0) + 0.001) * n * float(g.diameter_m), 0.0)
	var none_negative := true
	for p: Dictionary in sweep.points:
		none_negative = none_negative and float(p.thrust_n) > 0.0
	return TestResult.new("tunnel: the curve's last point is the thrust-zero crossing, none past it",
		sweep.end == "zero_thrust" and last.j == sweep.j0 and float(last.thrust_n) < 1e-3 * static_t
			and none_negative and beyond[0] <= 0.0 and String(sweep.end_reason) != "",
		"J0 %.4f, last T %.6f of static %.2f, T just past %.4f" % [sweep.j0, last.thrust_n, static_t, beyond[0]])


static func _a_flat_blade_is_refused() -> TestResult:
	var g := _geometry()
	g.pitch_m = 0.0
	var flat := PropTunnel.axial_sweep(g, RPM)
	var none := _geometry()
	none.chord = PackedFloat64Array()
	var blank := PropTunnel.axial_sweep(none, RPM)
	return TestResult.new("tunnel: no pitch and no chord refuse rather than chart zeros",
		_is_bare_refusal(flat) and _is_bare_refusal(blank) and blank.reason == PropTunnel.REASON_BLADE,
		"%s / %s" % [flat, blank])


static func _flow_angle_figures_equal_the_direct_solve() -> TestResult:
	var g := _geometry()
	var sweep := PropTunnel.flow_angle_sweep(g, RPM, 15.0)
	var bad := ""
	for i in sweep.points.size():
		var p: Dictionary = sweep.points[i]
		var angle: float = i * PropTunnel.ANGLE_STEP_DEG
		var ax: float = 0.0 if angle == 90.0 else 15.0 * cos(deg_to_rad(angle))
		var r := _direct(g, RPM, ax, 15.0 * sin(deg_to_rad(angle)))
		if p.angle_deg != angle or p.thrust_n != r[0] or p.power_w != r[1] * RPM * TAU / 60.0:
			bad += " %.0f" % angle
	return TestResult.new("tunnel: every flow angle equals a direct solve_forward, 0 to 90 degrees",
		bad == "" and sweep.points.size() == 19, "%d points, wrong at:%s" % [sweep.points.size(), bad])


static func _edgewise_carries_thrust_and_power_only() -> TestResult:
	var sweep := PropTunnel.flow_angle_sweep(_geometry(), RPM, 15.0)
	var stray := 0
	for p: Dictionary in sweep.points:
		for key in ["ct", "cp", "eta", "j"]:
			stray += 1 if p.has(key) else 0
	return TestResult.new("tunnel: flow-angle points have no Ct, Cp, efficiency or J to misread",
		stray == 0 and sweep.points[-1].has("thrust_n") and sweep.points[-1].has("power_w"), "%d stray" % stray)


## Past J0 straight-on, thrust only returns as the flow leans over. No point may chart below zero.
static func _a_fast_axial_flow_starts_the_angle_curve_late() -> TestResult:
	var g := _geometry()
	var airspeed: float = 1.5 * RPM / 60.0 * float(g.diameter_m)
	var sweep := PropTunnel.flow_angle_sweep(g, RPM, airspeed)
	var first: Dictionary = sweep.points[0]
	var static_t: float = PropTunnel.point(g, RPM, 0.0).thrust_n
	var none_negative := true
	for p: Dictionary in sweep.points:
		none_negative = none_negative and float(p.thrust_n) > 0.0
	return TestResult.new("tunnel: a flow-angle curve starts at the angle thrust returns, and says why",
		sweep.start_angle_deg > 0.0 and float(first.thrust_n) < 1e-3 * static_t and none_negative
			and String(sweep.start_reason) != "" and sweep.points[-1].angle_deg == 90.0,
		"starts %.3f deg at T %.6f" % [sweep.start_angle_deg, first.thrust_n])


static func _stations_sum_to_the_totals() -> TestResult:
	var g := _geometry()
	var bad := ""
	for v: Vector2 in [Vector2(10.0, 0.0), Vector2(5.0, 12.0), Vector2(0.0, 15.0)]:
		var s := PropTunnel.stations(g, RPM, v.x, v.y)
		var r := _direct(g, RPM, v.x, v.y)
		var t := 0.0
		for row: Dictionary in s.stations:
			t += float(row.thrust_n)
		if t != r[0] or s.thrust_n != r[0] or s.torque_nm != r[1] or s.stations.size() != 40:
			bad += " %s (%d rows, %.9f vs %.9f)" % [v, s.stations.size(), t, r[0]]
	return TestResult.new("tunnel: stations sum to the solve's total thrust and torque, bit-exact", bad == "", bad)


## V = 0 is the hover path, whose fixed point differs from the forward one.
static func _stations_at_hover_sum_to_the_hover_total() -> TestResult:
	var g := _geometry()
	var s := PropTunnel.stations(g, RPM, 0.0)
	var r := _direct(g, RPM, 0.0, 0.0)
	return TestResult.new("tunnel: at rest the tap reads the hover path, to the bit",
		s.thrust_n == r[0] and s.torque_nm == r[1] and s.stations.size() == 40, "%.9f vs %.9f" % [s.thrust_n, r[0]])


## Separates a real tap from one that summed right with its columns crossed.
static func _station_angle_is_blade_minus_inflow() -> TestResult:
	var g := _geometry()
	var bad := 0
	var rows: Array = PropTunnel.stations(g, RPM, 10.0).stations
	var omega: float = RPM * TAU / 60.0
	for row: Dictionary in rows:
		var beta: float = atan(float(g.pitch_m) / (TAU * float(row.r_m)))
		var u_min: float = omega * float(row.r_m)
		if absf(float(row.alpha_rad) - (beta - float(row.phi_rad))) > 1e-12 or float(row.u_mps) < u_min:
			bad += 1
	var hub: Dictionary = rows[0]
	var tip: Dictionary = rows[-1]
	return TestResult.new("tunnel: station alpha is beta minus phi, r runs hub to tip, U at least the swirl",
		bad == 0 and hub.r_frac < tip.r_frac and tip.r_frac < 1.0 and tip.r_frac > 0.98, "%d wrong" % bad)


static func _mach_flag_falls_at_the_line() -> TestResult:
	var g := _geometry()
	var radius: float = float(g.diameter_m) * 0.5
	var rpm_at_line: float = PropTunnel.MACH_FLAG * PropTunnel.SPEED_OF_SOUND_MPS / radius * 60.0 / TAU
	var under := PropTunnel.point(g, rpm_at_line * 0.99, 0.0)
	var over := PropTunnel.point(g, rpm_at_line * 1.01, 0.0)
	var expected: float = (rpm_at_line * 1.01) * TAU / 60.0 * radius / 340.3
	var sweep := PropTunnel.axial_sweep(g, rpm_at_line * 1.01)
	return TestResult.new("tunnel: Mach 0.7 flags on the line, keeps the number, and reaches the sweep",
		under.flag == "" and over.flag == PropTunnel.FLAG_MACH and absf(float(over.tip_mach) - expected) < 1e-9
			and over.thrust_n > 0.0 and sweep.points[0].flag == PropTunnel.FLAG_MACH and PropTunnel.MACH_FLAG == 0.7,
		"under '%s', over '%s', M %.4f want %.4f, T %.2f, sweep %s" % [under.flag, over.flag, over.tip_mach, expected, over.thrust_n, sweep.points[0].flag])


static func _edge_flag_needs_fast_edgewise() -> TestResult:
	var g := _geometry()
	var omega_r: float = RPM * TAU / 60.0 * float(g.diameter_m) * 0.5
	var slow := PropTunnel.point(g, RPM, 0.0, 0.59 * omega_r)
	var fast := PropTunnel.point(g, RPM, 0.0, 0.61 * omega_r)
	var axial := PropTunnel.point(g, RPM, 0.61 * omega_r, 0.0)
	return TestResult.new("tunnel: the edgewise flag sits at mu 0.6 and only on edgewise flow",
		slow.flag == "" and fast.flag == PropTunnel.FLAG_EDGE and axial.flag == "",
		"%s / %s / %s" % [slow.flag, fast.flag, axial.flag])


static func _bad_rpm_is_refused() -> TestResult:
	var r := PropTunnel.axial_sweep(_geometry(), 0.0)
	return TestResult.new("tunnel: zero rpm refuses", _is_bare_refusal(r) and r.reason == PropTunnel.REASON_RPM, str(r))
