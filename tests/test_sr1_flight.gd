class_name TestSr1Flight
extends RefCounted
## SR1 steady-flight physics: directional drag, the cruise power bucket, ground effect.
## One test per case. Each states what would make it fail; the "mutation" notes in the SR1 section of the
## plan record that the test was run against the unfixed code and went red.
##
## The worked example the plan asks for: a 1.2 kg mapper on a 20 Ah Li-ion pack, built from the Mavic
## harness parts with the pack swapped (ESTIMATED: pack mass 520 g is lighter than 20 Ah of real cells
## would be; the example is about the power curve's SHAPE, not a purchasable aircraft).

static func run() -> Array:
	var out: Array = []
	out.append_array(_drag_defaults_are_labelled())
	out.append_array(_drag_field_replaces_default())
	out.append_array(_head_on_vs_side_on())
	out.append_array(_body_angle_changes_drag_in_the_sim())
	out.append_array(_power_bucket())
	out.append_array(_bucket_depth_terms())
	out.append_array(_ground_effect_curve())
	out.append_array(_ground_effect_in_the_sim())
	out.append_array(_top_speed_top_area())
	return out


static func mapper_build(frame_g: float = 1200.0) -> Build:
	var ref: Dictionary = SimRealityHarness.find_reference("mavic_3m").duplicate(true)
	for part in ref["parts"]:
		if part["category"] == "battery":
			part["part_id"] = "ref_mapper_20ah"
			part["mass_g"] = 520.0
			part["specs"]["mah"] = 20000.0
			part["specs"]["nominal_v"] = 14.4
			part["specs"]["chemistry"] = "Li-ion"
			part["specs"]["c_rating"] = 3.0
			part["specs"]["internal_r_ohm"] = 0.05
			part["specs"]["length_mm"] = 150
			part["specs"]["width_mm"] = 70
			part["specs"]["height_mm"] = 60
	ref["build"]["battery"] = "ref_mapper_20ah"
	ref["solve_frame_mass_to_g"] = frame_g
	ref["id"] = "mapper_1p2kg"
	return SimRealityHarness.build_for(ref)


static func power_w(b: Build, v: float, side_on: bool = false) -> float:
	return b.flight_current_at_a(v, 1.0, 1.0, Build.AT_NOMINAL, side_on) * float(b.battery["specs"]["nominal_v"])


static func _drag_defaults_are_labelled() -> Array:
	var fpv := ReferenceBuild.build()
	var mavic := SimRealityHarness.build_for(SimRealityHarness.find_reference("mavic_3m"))
	var f: Vector3 = fpv.drag_cda_m2
	var m: Vector3 = mavic.drag_cda_m2
	return [TestResult.new("drag default per class (ESTIMATED): an open FPV frame keeps the legacy frontal Cd*A, a shelled body has the stated fraction of the same scaling, and the side and top areas differ from the frontal (not one scalar)",
		fpv.drag_class() == "open frame" and mavic.drag_class() == "streamlined"
		and absf(f.z - Build.REFERENCE_DRAG_AREA_M2 * pow(fpv.arm_m / Build.REFERENCE_ARM_M, 2.0)) < 1e-6
		and absf(m.z - Build.REFERENCE_DRAG_AREA_M2 * pow(mavic.arm_m / Build.REFERENCE_ARM_M, 2.0) * Build.DRAG_STREAMLINED_FRONT) < 1e-6
		and absf(f.x - f.z) > 0.02 * f.z and absf(f.y - f.z) > 0.1 * f.z and absf(m.y - m.z) > 0.1 * m.z,
		"FPV Cd*A side/top/front %.4f/%.4f/%.4f (%s), Mavic %.4f/%.4f/%.4f (%s)" % [f.x, f.y, f.z, fpv.drag_class(), m.x, m.y, m.z, mavic.drag_class()])]


static func _drag_field_replaces_default() -> Array:
	var b := ReferenceBuild.build()
	var before := b.drag_cda_m2
	b.drag_field_m2 = Vector3(0.0, 0.05, 0.0)
	b._recompute()
	var after := b.drag_cda_m2
	return [TestResult.new("drag field: a positive component replaces the derived Cd*A on that axis only, and the build's drag_axes follows (a field that is read by nothing leaves y unchanged)",
		absf(after.y - 0.05) < 1e-6 and absf(after.x - before.x) < 1e-6 and absf(after.z - before.z) < 1e-6
		and absf(b.drag_axes.y - 0.5 * b.air.kgm3() * 0.05) < 1e-6,
		"y %.4f -> %.4f, x %.4f -> %.4f" % [before.y, after.y, before.x, after.x])]


static func _head_on_vs_side_on() -> Array:
	var results: Array = []
	var b := SimRealityHarness.build_for(SimRealityHarness.find_reference("mavic_3m"))
	var head := power_w(b, 12.0, false)
	var side := power_w(b, 12.0, true)
	var diff: float = absf(side - head) / head
	results.append(TestResult.new("directional drag: the same build at 12 m/s needs different power head-on and side-on (more than 3 percent apart)",
		diff > 0.03, "head-on %.1f W, side-on %.1f W (%.1f%% apart; side Cd*A %.4f vs front %.4f m2)" % [head, side, diff * 100.0, b.drag_cda_m2.x, b.drag_cda_m2.z]))
	# Fail-proof inside the test: one scalar for every axis (what the code did before) gives no difference.
	var iso := SimRealityHarness.build_for(SimRealityHarness.find_reference("mavic_3m"))
	var a: float = iso.drag_cda_m2.z
	iso.drag_field_m2 = Vector3(a, a, a)
	iso._recompute()
	var h2 := power_w(iso, 12.0, false)
	var s2 := power_w(iso, 12.0, true)
	results.append(TestResult.new("directional drag, counterfactual: with one Cd*A on every axis head-on and side-on are identical (so the check above can fail)",
		absf(s2 - h2) / h2 < 0.001, "head-on %.2f W, side-on %.2f W" % [h2, s2]))
	return results


static func _decel(core: DroneCore, orientation: Quaternion) -> float:
	core.rigid_body.orientation = orientation
	core.rigid_body.velocity_mps = Vector3(0, 0, -12.0)
	core.step({"M1": 0.0, "M2": 0.0, "M3": 0.0, "M4": 0.0}, 0.01)
	return core.rigid_body.velocity_mps.z + 12.0   # speed lost along the track (positive: -Z is forward)


static func _body_angle_changes_drag_in_the_sim() -> Array:
	var b := SimRealityHarness.build_for(SimRealityHarness.find_reference("mavic_3m"))
	var level := _decel(b.build_drone_core({"off": true}), Quaternion.IDENTITY)
	var edge_on := _decel(b.build_drone_core({"off": true}), Quaternion(Vector3.RIGHT, -PI * 0.5))
	var legacy_core := b.build_drone_core({"off": true})
	legacy_core.drag_axes = Vector3(-1, -1, -1)
	var l0 := _decel(legacy_core, Quaternion.IDENTITY)
	var legacy_core2 := b.build_drone_core({"off": true})
	legacy_core2.drag_axes = Vector3(-1, -1, -1)
	var l1 := _decel(legacy_core2, Quaternion(Vector3.RIGHT, -PI * 0.5))
	var ratio: float = edge_on / level
	var want: float = b.drag_axes.y / b.drag_axes.z
	return [
		TestResult.new("body angle: the same 12 m/s flow slows the aircraft by its TOP area when the rotor axis points into the wind and by its FRONTAL area when level (decel ratio equals the area ratio within 10%)",
			absf(ratio / want - 1.0) < 0.10, "decel level %.5f, rotor-axis-on %.5f m/s per step; ratio %.2f, areas top/front %.2f" % [level, edge_on, ratio, want]),
		TestResult.new("body angle, counterfactual: the old scalar drag decelerates identically at both angles (so the check above can fail)",
			absf(l1 - l0) / l0 < 0.01, "level %.5f, rotated %.5f" % [l0, l1]),
	]


static func _power_bucket() -> Array:
	var results: Array = []
	var b := mapper_build()
	var hover := power_w(b, 0.0)
	var best_v := 0.0
	var best_p := INF
	var v := 0.5
	while v <= 24.0:
		var p := power_w(b, v)
		if p < best_p:
			best_p = p
			best_v = v
		v += 0.5
	var fast := power_w(b, 22.0)
	var curve := ""
	for s in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 22.0]:
		curve += " %d m/s %.0f W;" % [int(s), power_w(b, s)]
	results.append(TestResult.new("power bucket (1.2 kg mapper, 20 Ah Li-ion): best-cruise power is at least 15 percent below hover, at a speed between 5 and 18 m/s",
		best_p < 0.85 * hover and best_v >= 5.0 and best_v <= 18.0,
		"AUW %.0f g, hover %.1f W, best %.1f W at %.1f m/s (%.0f%% of hover);%s" % [b.all_up_weight_g(), hover, best_p, best_v, 100.0 * best_p / hover, curve]))
	var depth: float = 1.0 - best_p / hover
	results.append(TestResult.new("power bucket depth (1.2 kg mapper) is inside the literature band 14 to 30 percent: 14 = DJI Mavic 3 published 37 vs 43 min (marketing-optimistic), 30 = momentum-theory ideal (about 34) less the published induced, profile and interference losses",
		depth >= 0.14 and depth <= 0.30, "depth %.1f%% (hover %.1f W, best %.1f W)" % [depth * 100.0, hover, best_p]))
	results.append(TestResult.new("power bucket (1.2 kg mapper): power rises again at high speed, 22 m/s costs more than the best cruise by over 25 percent",
		fast > 1.25 * best_p, "22 m/s %.1f W against best %.1f W" % [fast, best_p]))
	return results


static func _ground_effect_curve() -> Array:
	var r := 0.12
	var g_r := DroneCore.ground_effect_gain(r, r)
	var g_half := DroneCore.ground_effect_gain(0.5 * r, r)
	var g_2r := DroneCore.ground_effect_gain(2.0 * r, r)
	var g_far := DroneCore.ground_effect_gain(10.0 * r, r)
	var mono := true
	var prev := 99.0
	for i in 60:
		var z := (0.4 + 0.04 * i) * r
		var g := DroneCore.ground_effect_gain(z, r)
		if g > prev + 1e-12:
			mono = false
		prev = g
	return [TestResult.new("ground effect (Cheeseman-Bennett): gain is 1/(1-(R/4z)^2) at z = R (1.0667), 1.333 at the R/2 floor, exactly 1 from 2R up, and never rises with height",
		absf(g_r - 1.0 / (1.0 - 1.0 / 16.0)) < 1e-9 and absf(g_half - 4.0 / 3.0) < 1e-9 and g_2r == 1.0 and g_far == 1.0 and mono,
		"gain at R %.4f, R/2 %.4f, 2R %.4f, 10R %.4f, monotone %s" % [g_r, g_half, g_2r, g_far, mono])]


static func _ground_effect_in_the_sim() -> Array:
	var results: Array = []
	var gains := {}
	for enabled in [true, false]:
		var b := ReferenceBuild.build()
		var core := b.build_drone_core({"off": true, "ground_effect": enabled})
		core.ground_effect_enabled = enabled
		var r: float = core.prop_radius_m
		var thr := b.hover_throttle()
		var cmds := {"M1": thr, "M2": thr, "M3": thr, "M4": thr}
		var acc := []
		for height in [0.6 * r, 3.0 * r]:
			core.prime_motors(thr)
			core.rigid_body.position_m = Vector3(0, height, 0)
			core.rigid_body.velocity_mps = Vector3.ZERO
			core.rigid_body.orientation = Quaternion.IDENTITY
			core.step(cmds, 0.002)
			acc.append(core.rigid_body.velocity_mps.y)
		gains[enabled] = acc[0] - acc[1]
	results.append(TestResult.new("ground effect in the sim: with it on, the same throttle lifts harder 0.6R above the ground than 3R above it; with it off the two are equal (so the check can fail)",
		gains[true] > 1e-4 and absf(gains[false]) < 1e-6,
		"vertical speed gained after one step, near minus far: on %.6f, off %s m/s" % [gains[true], str(gains[false])])
	)
	return results


## Raw (term-free) forward power ratio for the mapper's prop at one (V_axial, V_edge, rpm), built from the
## unmodified solves, to compare production against. The three SR1 bucket terms are each tested as the
## difference between production and this.
static func _raw_and_prod(b: Build, rpm: float, vax: float, ved: float) -> Dictionary:
	var g = b.prop_geometry()
	var ch := b.blade_chord()
	var tw := b.blade_twist()
	var pol := BemtModel.global_polar()
	var rho: float = b.air.kgm3()
	var st := BemtModel.solve_with_guard(rho, g.diameter_m, g.pitch_m, g.blades, rpm, ch, pol[0], pol[1], pol[2], pol[3], b.guard_closure, tw)
	var fl := BemtModel.solve_forward_with_guard(rho, g.diameter_m, g.pitch_m, g.blades, rpm, ch, pol[0], pol[1], pol[2], pol[3], vax, ved, b.guard_closure, tw)
	var prod := BemtModel.power_ratio_forward_with_guard(rho, g.diameter_m, g.pitch_m, g.blades, rpm, ch, vax, ved, b.guard_closure, tw)
	var area := PI * pow(g.diameter_m * 0.5, 2.0)
	var ideal: float = st[0] * sqrt(st[0] / (2.0 * rho * area))
	var omega_r: float = rpm * TAU / 60.0 * g.diameter_m * 0.5
	var mu: float = ved / omega_r
	var climb: float = fl[0] * vax
	var v_i: float = (fl[2] - climb) / fl[0]
	return {"static_p": st[2] + st[3], "ind": fl[2], "prof": fl[3], "climb": climb, "kappa_hover": st[2] / ideal,
		"mu": mu, "skew_sin": ved / sqrt(pow(vax + v_i, 2.0) + ved * ved), "prod": prod}


static func _bucket_depth_terms() -> Array:
	var results: Array = []
	var b := mapper_build()
	var rpm := 4400.0
	var vax := 0.8
	var ved := 11.4
	var d := _raw_and_prod(b, rpm, vax, ved)
	var sp: float = d["static_p"]
	var raw: float = (d["ind"] + d["prof"]) / sp
	var pf: float = (1.0 + 4.65 * d["mu"] * d["mu"]) / (1.0 + 2.0 * d["mu"] * d["mu"])
	var excess: float = 1.15 / 1.15 - 1.0   # kappa hover = kappa forward = 1.15 (owner decision 2026-11-09), ratio 1
	# 1. induced-power factor
	var with_kappa: float = (d["climb"] + (d["ind"] - d["climb"]) * (1.0 + excess * d["skew_sin"]) + d["prof"] * pf) / sp
	var no_kappa: float = (d["ind"] + d["prof"] * pf) / sp
	results.append(TestResult.new("bucket term 1, induced-power factor (kappa 1.15 in hover AND forward flight, so the forward/hover ratio is exactly 1): production equals the formula with no extra forward penalty, and the old 1.15/1.10 ratio would have raised the ratio by at least 1.5 percent",
		absf(d["prod"] - with_kappa) < 1e-6 and absf(with_kappa - no_kappa) < 1e-12 and (d["climb"] + (d["ind"] - d["climb"]) * (1.0 + (1.15 / 1.10 - 1.0) * d["skew_sin"]) + d["prof"] * pf) / sp / no_kappa > 1.015,
		"production %.4f, with %.4f, without %.4f (kappa_hover %.3f, excess %.3f, skew sin %.3f)" % [d["prod"], with_kappa, no_kappa, d["kappa_hover"], excess, d["skew_sin"]]))
	# 2. profile power growth
	var no_prof: float = (d["climb"] + (d["ind"] - d["climb"]) * (1.0 + excess * d["skew_sin"]) + d["prof"]) / sp
	results.append(TestResult.new("bucket term 2, profile-power growth (1 + 4.65 mu^2 against the BEMT's implicit 1 + 2 mu^2): production includes it, and without it the ratio would be at least 2 percent lower",
		absf(d["prod"] - with_kappa) < 1e-6 and (with_kappa - no_prof) / no_prof > 0.02,
		"mu %.3f, factor %.3f, production %.4f, without %.4f, raw %.4f" % [d["mu"], pf, d["prod"], no_prof, raw]))
	# 3. rotor-rotor interference: whole-build power, default against the field set to 0
	var p_on := power_w(b, 11.5)
	var b2 := mapper_build()
	b2.rotor_interference_loss = 0.0
	var p_off := power_w(b2, 11.5)
	var h_on := power_w(b, 0.0)
	var h_off := power_w(b2, 0.0)
	var f25 := BemtRatios.interference_power_factor(0.11, 0.0, 25.0, 4430.0, 0.119)
	var f10 := BemtRatios.interference_power_factor(0.11, 0.5, 10.0, 4430.0, 0.119)
	var f_breeze := BemtRatios.interference_power_factor(0.11, 0.0, 3.0, 25000.0, 0.0635)
	results.append(TestResult.new("bucket term 3, rotor-rotor interference (11 percent rear-rotor thrust loss, 5-15 m/s only): at 11.5 m/s the build draws at least 5 percent more than with the field at 0; hover identical; factor exactly 1 at 25 m/s on the mapper; and a 5 inch quad in a 3 m/s breeze takes under 1 percent",
		(p_on - p_off) / p_off > 0.05 and absf(h_on - h_off) < 1e-9 and f25 == 1.0 and f10 > 1.05 and f_breeze < 1.01,
		"11.5 m/s %.1f W on vs %.1f W off; hover %.2f vs %.2f; factor at 10 m/s %.4f, at 25 m/s %.4f, 5in 3 m/s %.4f" % [p_on, p_off, h_on, h_off, f10, f25, f_breeze]))
	return results


## SR1.3: top_speed_kmh() includes the top-area drag term at the trim lean. At the fixed 45 degree cap that
## term cancels exactly (so a lean-capped build is blind to it, by physics, not by omission); it bites where
## thrust binds, so the cases use a deliberately overloaded build (frame mass 2400 g on the mapper parts).
## Mutation record: with top_speed_kmh() restored to the frontal-only, fixed-45-degree form, the "doubling
## top area lowers the thrust-limited top speed" case went red (speeds equal).
static func _thrust_limited() -> Build:
	return mapper_build(2400.0)


static func _top_speed_top_area() -> Array:
	var results: Array = []
	var b := _thrust_limited()
	var capped := ReferenceBuild.build()
	var cap_speed := sqrt(b.weight_n() * tan(Build.TOP_SPEED_LEAN_RAD) / b.drag_coefficient) * 3.6
	var base := b.top_speed_kmh()
	var dbl := _thrust_limited()
	dbl.drag_field_m2 = Vector3(0.0, dbl.drag_cda_m2.y * 2.0, 0.0)
	dbl._recompute()
	var doubled := dbl.top_speed_kmh()
	results.append(TestResult.new("top speed: the overloaded build is thrust-limited (below its 45 degree lean-capped speed), so this regime tests what the plain cap cannot",
		base < cap_speed * 0.98, "top speed %.2f km/h, lean-capped %.2f km/h" % [base, cap_speed]))
	results.append(TestResult.new("top speed: doubling the top-area Cd*A lowers the thrust-limited top speed (the top-area term is in the figure)",
		doubled < base - 0.05, "base %.3f km/h, top area x2 %.3f km/h" % [base, doubled]))
	var c2 := ReferenceBuild.build()
	c2.drag_field_m2 = Vector3(0.0, c2.drag_cda_m2.y * 2.0, 0.0)
	c2._recompute()
	results.append(TestResult.new("top speed: the reference FPV build is lean-capped (its figure equals sqrt(W / front Cd*A halves) within 0.1 percent)",
		absf(capped.top_speed_kmh() - sqrt(capped.weight_n() / capped.drag_coefficient) * 3.6) < 0.001 * capped.top_speed_kmh(),
		"top speed %.3f km/h" % capped.top_speed_kmh()))
	results.append(TestResult.new("top speed: on a lean-capped build the top-area term cancels exactly at 45 degrees (doubling it moves the figure by under 0.1 percent), the physics the note records",
		absf(c2.top_speed_kmh() - capped.top_speed_kmh()) < 0.001 * capped.top_speed_kmh(),
		"lean-capped %.3f km/h, top area x2 %.3f km/h" % [capped.top_speed_kmh(), c2.top_speed_kmh()]))
	return results
