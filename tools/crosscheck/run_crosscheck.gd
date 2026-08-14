extends SceneTree
const RMotor = preload("res://tools/crosscheck/ref_motor_model.gd")
const RBatt = preload("res://tools/crosscheck/ref_battery_model.gd")
const RProp = preload("res://tools/crosscheck/ref_propeller_model.gd")
const RPt = preload("res://tools/crosscheck/ref_powertrain.gd")
## Golden cross-check for TIER 1 (design check 3): the Rust GDExtension classes against the
## GDScript originals they replaced, recovered verbatim from git history and renamed Ref* to
## avoid a class_name collision. Run it:
##   godot --headless --path . --script res://tools/crosscheck/run_crosscheck.gd
##
## The ref_*.gd files ARE the oracle, so they must never be edited to match the Rust — that
## would make this compare the port against itself. They are byte-verbatim from the commits
## that deleted them (e6376d3^, 4a63753^, d7359e0^, 8b8aeaf^) apart from the class_name
## removal and the Ref* renaming. Tier 2's crosscheck (tests/rust_crosscheck_tier2.gd)
## transcribes its references by hand instead, and that is the weaker method: a transcription
## can absorb the very change it is meant to detect, which is exactly what happened to
## _ref_current_at_rpm there.
##
## This lives under tools/ because tools/* is export-excluded — these files are verbatim
## copies of the physics the port exists to hide, and shipping them in the pck would undo it.
## build_macos.sh runs this as a gate; it is deliberately not in run_tests.gd's SUITES
## because a full catalog sweep is far slower than a unit suite.

const REL_TOL := 1.0e-12
const NEAR_ZERO := 1.0e-300

const INCH_M := 0.0254

## Full-length powertrain runs are O(combos * steps); the whole catalog gets a short run and a
## representative stride gets the long one. Both counts are reported.
const PT_SHORT_STEPS := 40
const PT_LONG_STEPS := 2000
const PT_LONG_STRIDE := 140   # every Nth combo gets the 2000-step run

var stats := {}          # fn name -> {worst=float, desc=String, n=int, fails=int}
var total_comparisons := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var catalog := PartsCatalog.load_default()
	if not catalog.load_errors.is_empty():
		print("CATALOG LOAD ERRORS: ", catalog.load_errors)
		quit(2)
		return

	var motors: Array = catalog.by_category["motor"]
	var props: Array = catalog.by_category["propeller"]
	var packs: Array = catalog.by_category["battery"]
	print("catalog: %d motors x %d propellers x %d packs = %d combos"
		% [motors.size(), props.size(), packs.size(), motors.size() * props.size() * packs.size()])

	_check_propeller(motors, props, catalog)
	_check_motor(motors, packs)
	_check_battery(packs)
	_check_powertrain(motors, props, packs, catalog)

	_report(Time.get_ticks_msec() - t0)


# ---------------------------------------------------------------------------
# comparison core
# ---------------------------------------------------------------------------

func _rel(a: float, b: float) -> float:
	if a == b:
		return 0.0
	# Both sides NaN, or both the SAME infinity, is agreement: a faithful port reproduces the
	# original's overflow in the same place. Only NaN-or-Inf against a finite number diverges.
	if is_nan(a) and is_nan(b):
		return 0.0
	if is_nan(a) or is_nan(b):
		return INF
	if is_inf(a) or is_inf(b):
		return 0.0 if (is_inf(a) and is_inf(b) and signf(a) == signf(b)) else INF
	var scale: float = maxf(absf(a), absf(b))
	if scale <= NEAR_ZERO:
		return absf(a - b)
	return absf(a - b) / scale


func _cmp(fn: String, rust_v: float, ref_v: float, desc: String) -> void:
	total_comparisons += 1
	if not stats.has(fn):
		stats[fn] = {"worst": 0.0, "desc": "(exact on every sample)", "n": 0, "fails": 0, "nan": 0}
	var s: Dictionary = stats[fn]
	s["n"] = int(s["n"]) + 1
	if (is_nan(rust_v) and is_nan(ref_v)) or (is_inf(rust_v) and is_inf(ref_v)):
		s["nan"] = int(s["nan"]) + 1
	var r := _rel(rust_v, ref_v)
	if r > float(s["worst"]):
		s["worst"] = r
		s["desc"] = "%s  rust=%s ref=%s" % [desc,
			String.num_scientific(rust_v), String.num_scientific(ref_v)]
	if r > REL_TOL:
		s["fails"] = int(s["fails"]) + 1


func _geom(prop: Dictionary) -> Dictionary:
	return {
		"diameter_m": float(prop["specs"]["diameter_inches"]) * INCH_M,
		"pitch_m": float(prop["specs"]["pitch_inches"]) * INCH_M,
		"blades": float(prop["specs"]["blades"]),
	}


# ---------------------------------------------------------------------------
# PropellerModel
# ---------------------------------------------------------------------------

func _check_propeller(motors: Array, props: Array, catalog: PartsCatalog) -> void:
	var rpm_sweep := [0.0, 1.0, 1000.0, 5000.0, 15000.0, 30000.0, 60000.0]

	for rpm in rpm_sweep:
		_cmp("PropellerModel.rpm_to_rad_s",
			PropellerModel.rpm_to_rad_s(rpm), RProp.rpm_to_rad_s(rpm),
			"rpm=%s" % rpm)

	# fit_k_t against every motor's own published thrust test.
	var k_ts: Array = []
	for m in motors:
		var tv := float(m["thrust_test"]["voltage_v"])
		var max_rpm := float(m["specs"]["kv"]) * tv
		var g := float(m["specs"]["max_thrust_g"])
		var a := PropellerModel.fit_k_t(g, max_rpm)
		var b := RProp.fit_k_t(g, max_rpm)
		_cmp("PropellerModel.fit_k_t", a, b, "%s g=%s max_rpm=%s" % [m["part_id"], g, max_rpm])
		k_ts.append({"id": m["part_id"], "k_t": b, "test_prop": m["thrust_test"]["prop_id"]})

	# fit_k_q for every (fitted k_t x every prop diameter).
	for e in k_ts:
		for p in props:
			var d: float = _geom(p)["diameter_m"]
			_cmp("PropellerModel.fit_k_q",
				PropellerModel.fit_k_q(e["k_t"], d), RProp.fit_k_q(e["k_t"], d),
				"%s -> %s d=%s k_t=%s" % [e["id"], p["part_id"], d, e["k_t"]])

	# scale_k_t_to_prop across EVERY ordered prop pair, for each motor's fitted k_t.
	for e in k_ts:
		var from_p: Dictionary = catalog.get_part(e["test_prop"])
		var fg := _geom(from_p)
		for to_p in props:
			var tg := _geom(to_p)
			var a := PropellerModel.scale_k_t_to_prop(e["k_t"],
				fg["diameter_m"], fg["pitch_m"], fg["blades"],
				tg["diameter_m"], tg["pitch_m"], tg["blades"])
			var b := RProp.scale_k_t_to_prop(e["k_t"], fg, tg)
			_cmp("PropellerModel.scale_k_t_to_prop", a, b,
				"%s: %s -> %s" % [e["id"], from_p["part_id"], to_p["part_id"]])

	# Every ordered prop pair independent of any motor, at a unit k_t.
	for from_p in props:
		var fg := _geom(from_p)
		for to_p in props:
			var tg := _geom(to_p)
			var a := PropellerModel.scale_k_t_to_prop(1.0e-8,
				fg["diameter_m"], fg["pitch_m"], fg["blades"],
				tg["diameter_m"], tg["pitch_m"], tg["blades"])
			var b := RProp.scale_k_t_to_prop(1.0e-8, fg, tg)
			_cmp("PropellerModel.scale_k_t_to_prop", a, b,
				"unit k_t: %s -> %s" % [from_p["part_id"], to_p["part_id"]])

	# thrust_n / reaction_torque_n_m over the RPM sweep, for every motor x prop k_t.
	for e in k_ts:
		var from_p: Dictionary = catalog.get_part(e["test_prop"])
		var fg := _geom(from_p)
		for to_p in props:
			var tg := _geom(to_p)
			var k_t := RProp.scale_k_t_to_prop(e["k_t"], fg, tg)
			var k_q := RProp.fit_k_q(k_t, tg["diameter_m"])
			for rpm in rpm_sweep:
				_cmp("PropellerModel.thrust_n",
					PropellerModel.thrust_n(k_t, rpm), RProp.thrust_n(k_t, rpm),
					"%s/%s rpm=%s k_t=%s" % [e["id"], to_p["part_id"], rpm, k_t])
				_cmp("PropellerModel.reaction_torque_n_m",
					PropellerModel.reaction_torque_n_m(k_q, rpm),
					RProp.reaction_torque_n_m(k_q, rpm),
					"%s/%s rpm=%s k_q=%s" % [e["id"], to_p["part_id"], rpm, k_q])


# ---------------------------------------------------------------------------
# MotorModel
# ---------------------------------------------------------------------------

func _check_motor(motors: Array, packs: Array) -> void:
	var throttles := [0.0, 0.25, 0.5, 0.87, 1.0, 1.5, -0.3]
	var max_throttles := [1.0, 0.62, 0.35]
	var dts := [1.0 / 120.0, 1.0 / 1000.0]
	var start_rpms := [0.0, 1200.0, 45000.0]

	# voltage sweep from every pack's nominal, plus a synthetic ladder
	var voltages: Array = [0.0, 1.0, 3.7, 11.1, 14.8, 22.2, 25.2]
	for p in packs:
		voltages.append(float(p["specs"]["nominal_v"]))

	for m in motors:
		var kv := float(m["specs"]["kv"])
		for mt in max_throttles:
			var rust: MotorModel = MotorModel.create(kv, mt)
			var ref_m: RMotor = RMotor.new(kv, mt)
			_cmp("MotorModel.max_throttle(clamp)", rust.max_throttle, ref_m.max_throttle,
				"%s mt=%s" % [m["part_id"], mt])

			for v in voltages:
				_cmp("MotorModel.max_rpm", rust.max_rpm(v), ref_m.max_rpm(v),
					"%s kv=%s v=%s" % [m["part_id"], kv, v])

			for dt in dts:
				for r0 in start_rpms:
					for th in throttles:
						var a: float = r0
						var b: float = r0
						var v: float = float(m["thrust_test"]["voltage_v"]) * 4.0
						for i in 200:
							a = rust.step(a, th, v, dt)
							b = ref_m.step(b, th, v, dt)
							_cmp("MotorModel.step", a, b,
								"%s mt=%s dt=%s r0=%s thr=%s iter=%d"
								% [m["part_id"], mt, dt, r0, th, i])


# ---------------------------------------------------------------------------
# BatteryModel  (highest risk)
# ---------------------------------------------------------------------------

func _check_battery(packs: Array) -> void:
	var chemistries := ["LiPo", "Li-ion", "NiMH-typo"]
	var soc_steps := 400

	# Pure per-chemistry statics over the FULL SoC range, plus out-of-range clamping.
	for chem in chemistries:
		_cmp("BatteryModel.nominal_cell_v",
			BatteryModel.nominal_cell_v(chem), RBatt.nominal_cell_v(chem), "chem=%s" % chem)
		_cmp("BatteryModel.soc_at_nominal",
			BatteryModel.soc_at_nominal(chem), RBatt.soc_at_nominal(chem), "chem=%s" % chem)
		for i in range(-3, soc_steps + 4):
			var soc := float(i) / float(soc_steps)
			_cmp("BatteryModel.cell_open_circuit_v",
				BatteryModel.cell_open_circuit_v(soc, chem),
				RBatt.cell_open_circuit_v(soc, chem),
				"chem=%s soc=%s" % [chem, soc])

	var currents := [0.0, 0.5, 5.0, 30.0, 120.0, 400.0]

	for p in packs:
		var sp: Dictionary = p["specs"]
		var nv := float(sp["nominal_v"])
		var r := float(sp["internal_r_ohm"])
		var mah := float(sp["mah"])
		var cells := int(sp["cells"])
		var catalog_chem := String(sp["chemistry"])

		# cells<=0 exercises the "infer the cell count from nominal_v" ctor branch, which the
		# catalog's own figure (always >0) never reaches. Without these two the
		# BatteryModel.cells(ctor) row is a check that cannot fail — mutation-tested.
		for zero_cells in [0, -3]:
			var rz: BatteryModel = BatteryModel.create(nv, r, mah, zero_cells, catalog_chem)
			var gz: RBatt = RBatt.new(nv, r, mah, zero_cells, catalog_chem)
			_cmp("BatteryModel.cells(ctor)", float(rz.cells), float(gz.cells),
				"%s p_cells=%d nominal_v=%s" % [p["part_id"], zero_cells, nv])
			_cmp("BatteryModel.resting_voltage_v", rz.resting_voltage_v(), gz.resting_voltage_v(),
				"%s p_cells=%d" % [p["part_id"], zero_cells])
			_cmp("BatteryModel.resting_cell_v", rz.resting_cell_v(), gz.resting_cell_v(),
				"%s p_cells=%d" % [p["part_id"], zero_cells])

		for chem in [catalog_chem, "LiPo", "Li-ion", "NiMH-typo"]:
			var rust: BatteryModel = BatteryModel.create(nv, r, mah, cells, chem)
			var ref_b: RBatt = RBatt.new(nv, r, mah, cells, chem)
			_cmp("BatteryModel.cells(ctor)", float(rust.cells), float(ref_b.cells),
				"%s chem=%s" % [p["part_id"], chem])
			_cmp("BatteryModel.chemistry(ctor fallback)",
				1.0 if String(rust.chemistry) == String(ref_b.chemistry) else 0.0, 1.0,
				"%s chem=%s rust=%s ref=%s" % [p["part_id"], chem, rust.chemistry, ref_b.chemistry])

			# Full SoC sweep by setting used_mah directly.
			for i in soc_steps + 1:
				var soc := float(i) / float(soc_steps)
				var used := mah * (1.0 - soc)
				rust.used_mah = used
				ref_b.used_mah = used
				var tag := "%s chem=%s soc=%s" % [p["part_id"], chem, soc]
				_cmp("BatteryModel.remaining_fraction",
					rust.remaining_fraction(), ref_b.remaining_fraction(), tag)
				_cmp("BatteryModel.soc_offset_v", rust.soc_offset_v(), ref_b.soc_offset_v(), tag)
				_cmp("BatteryModel.resting_voltage_v",
					rust.resting_voltage_v(), ref_b.resting_voltage_v(), tag)
				_cmp("BatteryModel.resting_cell_v",
					rust.resting_cell_v(), ref_b.resting_cell_v(), tag)
				for c in currents:
					_cmp("BatteryModel.voltage_live",
						rust.voltage_live(c), ref_b.voltage_live(c), "%s I=%s" % [tag, c])

			# set_to_nominal_datum
			rust.set_to_nominal_datum()
			ref_b.set_to_nominal_datum()
			_cmp("BatteryModel.set_to_nominal_datum(used_mah)",
				rust.used_mah, ref_b.used_mah, "%s chem=%s" % [p["part_id"], chem])
			_cmp("BatteryModel.set_to_nominal_datum(resting_v)",
				rust.resting_voltage_v(), ref_b.resting_voltage_v(),
				"%s chem=%s" % [p["part_id"], chem])

			# Accumulated drain divergence: 3000 steps at a realistic-ish current.
			rust.used_mah = 0.0
			ref_b.used_mah = 0.0
			var dt := 1.0 / 120.0
			for i in 3000:
				var cur := 8.0 + 6.0 * sin(float(i) * 0.017)
				rust.drain(cur, dt)
				ref_b.drain(cur, dt)
				if i % 25 == 0 or i > 2990:
					var tag2 := "%s chem=%s drain_iter=%d" % [p["part_id"], chem, i]
					_cmp("BatteryModel.drain(used_mah)", rust.used_mah, ref_b.used_mah, tag2)
					_cmp("BatteryModel.drain->resting_voltage_v",
						rust.resting_voltage_v(), ref_b.resting_voltage_v(), tag2)
					_cmp("BatteryModel.drain->voltage_live",
						rust.voltage_live(12.0), ref_b.voltage_live(12.0), tag2)


# ---------------------------------------------------------------------------
# Powertrain
# ---------------------------------------------------------------------------

func _check_powertrain(motors: Array, props: Array, packs: Array, catalog: PartsCatalog) -> void:
	var combo := 0
	var long_runs := 0
	for m in motors:
		var kv := float(m["specs"]["kv"])
		var tv := float(m["thrust_test"]["voltage_v"])
		var rated_rpm := kv * tv
		var k_t_test := RProp.fit_k_t(float(m["specs"]["max_thrust_g"]), rated_rpm)
		var test_prop: Dictionary = catalog.get_part(m["thrust_test"]["prop_id"])
		var fg := _geom(test_prop)
		var max_amps := float(m["specs"]["max_amps"])
		var poles := float(m["specs"].get("poles", 14))

		for p in props:
			var tg := _geom(p)
			var k_t := RProp.scale_k_t_to_prop(k_t_test, fg, tg)
			var k_q := RProp.fit_k_q(k_t, tg["diameter_m"])

			for bp in packs:
				var sp: Dictionary = bp["specs"]
				var steps := PT_SHORT_STEPS
				if combo % PT_LONG_STRIDE == 0:
					steps = PT_LONG_STEPS
					long_runs += 1
				combo += 1
				_run_powertrain_pair(
					"%s|%s|%s" % [m["part_id"], p["part_id"], bp["part_id"]],
					kv, k_t, k_q, max_amps, rated_rpm, poles * 0.5, tg["blades"],
					tg["diameter_m"] * 0.5, tg["pitch_m"], sp, steps)

	print("powertrain: %d combos (%d at %d steps, rest at %d)"
		% [combo, long_runs, PT_LONG_STEPS, PT_SHORT_STEPS])


func _run_powertrain_pair(tag: String, kv: float, k_t: float, k_q: float, max_amps: float,
		rated_rpm: float, pole_pairs: float, blades: float, prop_radius_m: float,
		prop_pitch_m: float, sp: Dictionary, steps: int) -> void:
	var nv := float(sp["nominal_v"])
	var r := float(sp["internal_r_ohm"])
	var mah := float(sp["mah"])
	var cells := int(sp["cells"])
	var chem := String(sp["chemistry"])

	var r_motor: MotorModel = MotorModel.create(kv, 1.0)
	var r_batt: BatteryModel = BatteryModel.create(nv, r, mah, cells, chem)
	# STANDARD AIR, and it has to be: the GDScript twin below is the pre-port implementation, which
	# was written when there was one atmosphere and hardcodes 1.225. Handing Rust a field's air here
	# would make the two sides disagree for a correct reason and report it as a port defect.
	#
	# Build.AIR_DENSITY_KGM3 rather than AirDensity.standard_kgm3(), deliberately: the twin's literal
	# is 1.225, and the derivation is 1.2249781. Nothing in this cross-check reads rho today — the
	# body velocity is zero throughout, so power_factor short-circuits to 1.0 — so the two are
	# indistinguishable here, which is exactly why the choice should be made on principle now rather
	# than discovered later. A golden cross-check must be handed the constant its ORACLE holds.
	var rust: Powertrain = Powertrain.create(r_motor, k_t, k_q, r_batt, max_amps, rated_rpm,
		pole_pairs, blades, prop_radius_m, prop_pitch_m, Build.AIR_DENSITY_KGM3)

	var g_motor: RMotor = RMotor.new(kv, 1.0)
	var g_batt: RBatt = RBatt.new(nv, r, mah, cells, chem)
	var ref_pt: RPt = RPt.new(g_motor, k_t, k_q, g_batt, max_amps, rated_rpm,
		pole_pairs, blades, prop_radius_m)

	# construction-time publish
	_cmp_pt(tag + " @ctor", rust, ref_pt)

	# current_at_rpm across a sweep
	for rpm in [0.0, 1.0, 900.0, rated_rpm * 0.5, rated_rpm, rated_rpm * 1.7]:
		_cmp("Powertrain.current_at_rpm", rust.current_at_rpm(rpm), ref_pt.current_at_rpm(rpm),
			"%s rpm=%s" % [tag, rpm])

	# prime()
	for th in [0.0, 0.3, 0.71, 1.0]:
		rust.prime(th)
		ref_pt.prime(th)
		_cmp_pt("%s @prime(%s)" % [tag, th], rust, ref_pt)

	# step() with a varying per-motor throttle array
	var dt := 1.0 / 120.0
	for i in steps:
		var f := float(i)
		var cmds := PackedFloat64Array([
			clampf(0.5 + 0.45 * sin(f * 0.031), 0.0, 1.2),
			clampf(0.5 + 0.45 * cos(f * 0.023), 0.0, 1.2),
			clampf(0.9 - 0.5 * sin(f * 0.011), 0.0, 1.2),
			clampf(0.2 + 0.8 * absf(sin(f * 0.007)), 0.0, 1.2),
		])
		var dict := {"M1": cmds[0], "M2": cmds[1], "M3": cmds[2], "M4": cmds[3]}
		rust.step(cmds, dt)
		ref_pt.step(dict, dt)
		_cmp_pt("%s @step%d" % [tag, i], rust, ref_pt)


func _cmp_pt(tag: String, rust: Powertrain, ref_pt: RPt) -> void:
	var ro = rust.observables
	var go = ref_pt.observables
	for i in 4:
		_cmp("Powertrain.motor_rpm", rust.motor_rpm[i],
			ref_pt.motor_rpm[MotorLayout.MOTOR_NAMES[i]], "%s m%d" % [tag, i])
		_cmp("Powertrain.obs.rpm", float(ro.rpm[i]), float(go.rpm[i]), "%s m%d" % [tag, i])
		_cmp("Powertrain.obs.thrust_n", float(ro.thrust_n[i]), float(go.thrust_n[i]),
			"%s m%d" % [tag, i])
		_cmp("Powertrain.obs.current_a", ro.current_a[i], go.current_a[i], "%s m%d" % [tag, i])
		_cmp("Powertrain.obs.reaction_torque_n_m", ro.reaction_torque_n_m[i],
			go.reaction_torque_n_m[i], "%s m%d" % [tag, i])
		_cmp("Powertrain.obs.blade_pass_hz", float(ro.blade_pass_hz[i]), float(go.blade_pass_hz[i]),
			"%s m%d" % [tag, i])
		_cmp("Powertrain.obs.electrical_hz", float(ro.electrical_hz[i]),
			float(go.electrical_hz[i]), "%s m%d" % [tag, i])
		_cmp("Powertrain.obs.tip_speed_mps", float(ro.tip_speed_mps[i]),
			float(go.tip_speed_mps[i]), "%s m%d" % [tag, i])
	_cmp("Powertrain.obs.total_thrust_n", ro.total_thrust_n, go.total_thrust_n, tag)
	_cmp("Powertrain.obs.current_total_a", ro.current_total_a, go.current_total_a, tag)
	_cmp("Powertrain.obs.voltage_live_v", ro.voltage_live_v, go.voltage_live_v, tag)
	_cmp("Powertrain.obs.capacity_used_fraction", ro.capacity_used_fraction,
		go.capacity_used_fraction, tag)
	_cmp("Powertrain.obs.elapsed_s", ro.elapsed_s, go.elapsed_s, tag)
	_cmp("Powertrain.last_voltage_v", rust.last_voltage_v, ref_pt.last_voltage_v, tag)
	_cmp("Powertrain.last_current_total_a", rust.last_current_total_a,
		ref_pt.last_current_total_a, tag)
	_cmp("Powertrain.battery.used_mah", rust.battery.used_mah, ref_pt.battery.used_mah, tag)


# ---------------------------------------------------------------------------

func _report(ms: int) -> void:
	var names := stats.keys()
	names.sort()
	var failing := 0
	print("\n%-42s %-14s %12s  %s" % ["FUNCTION", "SAMPLES", "WORST REL", "STATUS"])
	print("-".repeat(110))
	for n in names:
		var s: Dictionary = stats[n]
		var status := "OK"
		if int(s["fails"]) > 0:
			status = "*** DIVERGES (%d/%d over tol) ***" % [s["fails"], s["n"]]
			failing += 1
		print("%-42s %-12d %-14s %s"
			% [n, int(s["n"]), String.num_scientific(float(s["worst"])), status])
		if int(s["fails"]) > 0 or float(s["worst"]) > 0.0:
			print("      worst case: %s" % s["desc"])
		if int(s["nan"]) > 0:
			print("      (%d/%d samples were nan/inf on BOTH sides — identical overflow, counted as agreement)"
				% [int(s["nan"]), int(s["n"])])
	print("-".repeat(110))
	print("total comparisons: %d   functions: %d   diverging: %d   tol: %s   elapsed: %.1fs"
		% [total_comparisons, names.size(), failing, REL_TOL, float(ms) / 1000.0])
	if failing == 0:
		print("RUST CROSSCHECK OK")
	else:
		print("%d RUST CROSSCHECK FAILURES" % failing)
	quit(1 if failing > 0 else 0)
