extends SceneTree
## Golden cross-check for NATIVE CORE 2, TIER 2a: ArmBeam's structural arithmetic (Rust
## `FrameLaw`) against the verbatim GDScript it replaced. Run it:
##   godot --headless --path . --script res://tools/crosscheck/run_crosscheck_frame.gd
##
## ref_arm_beam.gd is byte-verbatim src/airframe/arm_beam.gd at 4486f05 minus its `class_name`
## line, and must never be edited to match the port. Its static make()/uniform() build a
## NEW-class ArmBeam (the `ArmBeam.new()` inside is verbatim), so this never calls them: every ref
## beam is a genuine RBeam.new() with its fields set by hand, or the comparison would be the port
## against itself.
##
## EXACT equality: the port repeats the original's f64 operation order, so it is bit-identical.
## Lives under tools/ (export-excluded); build_macos.sh gates on the sentinel.

const RBeam = preload("res://tools/crosscheck/ref_arm_beam.gd")
const SENTINEL := "FRAME LAW CROSSCHECK OK"

var stats := {}
var total := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = 0xBEA7
	var materials := FrameMaterials.load_default()
	var ids: Array = materials.ids()
	ids.append("no_such_material")
	for n in 6000:
		var pair := _random_pair(materials, ids, n)
		_compare(pair[0], pair[1], "beam %d" % n)
	# Every profile the Airframe room actually makes: ArmProfile's own builder, via the real
	# catalog-like shapes (uniform, tapered, kinked, degenerate stations).
	for n in 400:
		var a := ArmBeam.uniform(rng.randf_range(0.01, 0.3), rng.randf_range(0.003, 0.03),
			rng.randf_range(0.001, 0.008), ids[n % ids.size()], materials, rng.randf_range(0.0, 0.08))
		var b = _ref_like(a)
		_compare(a, b, "uniform %d" % n)
	_report(Time.get_ticks_msec() - t0)


func _random_pair(materials: FrameMaterials, ids: Array, n: int) -> Array:
	var length := rng.randf_range(0.005, 0.35)
	if n % 97 == 0:
		length = 0.0
	var count := 1 + rng.randi_range(0, 16)
	var s := PackedFloat64Array()
	var b := PackedFloat64Array()
	var x := 0.0 if n % 5 else -0.01
	for i in count:
		s.append(x)
		b.append(rng.randf_range(0.002, 0.035) if n % 53 else rng.randf_range(-0.005, 0.02))
		# repeated stations (span 0) and stations past the tip both occur in edited profiles
		x += 0.0 if (i % 7 == 3) else rng.randf_range(0.0, length / float(count) * 1.4)
	if n % 31 == 0:
		s = PackedFloat64Array()
		b = PackedFloat64Array()
	var thickness := rng.randf_range(0.0008, 0.008) if n % 41 else 0.0
	var a := ArmBeam.make(length, s, b, thickness, ids[n % ids.size()], materials,
		rng.randf_range(0.0, 0.1))
	a.cut_angle_deg = rng.randf_range(0.0, 90.0) if n % 3 == 0 else 0.0
	a.unibody = n % 4 == 0
	return [a, _ref_like(a)]


func _ref_like(a: ArmBeam) -> Variant:
	var r = RBeam.new()
	for f in ["length_m", "profile_s_m", "profile_b_m", "thickness_m", "tip_mass_kg",
			"material_id", "materials", "cut_angle_deg", "unibody"]:
		r.set(f, a.get(f))
	r.validate()
	return r


func _compare(a: ArmBeam, b: Variant, d: String) -> void:
	_cmp("ArmBeam.is_valid", a.is_valid(), b.is_valid(), d)
	_cmp("ArmBeam.compliance_integral", a.compliance_integral(), b.compliance_integral(), d)
	_cmp("ArmBeam.plan_area_m2", a.plan_area_m2(), b.plan_area_m2(), d)
	_cmp("ArmBeam.root_fixity", a.root_fixity(), b.root_fixity(), d)
	_cmp("ArmBeam.k_tip_n_per_m", a.k_tip_n_per_m(), b.k_tip_n_per_m(), d)
	_cmp("ArmBeam.arm_mass_kg", a.arm_mass_kg(), b.arm_mass_kg(), d)
	_cmp("ArmBeam.resonance_hz", a.resonance_hz(), b.resonance_hz(), d)
	for force in [0.0, 1.0, 12.5, -4.0]:
		_cmp("ArmBeam.tip_deflection_m", a.tip_deflection_m(force), b.tip_deflection_m(force), d)
		var ta: Dictionary = a.torsion_deg(force * 0.01)
		var tb: Dictionary = b.torsion_deg(force * 0.01)
		for k in ["twist_deg", "torsion_constant_m4", "shear_modulus_pa"]:
			_cmp("ArmBeam.torsion_deg." + k, ta[k], tb[k], d)
		for hole in [0.0, 0.002, 0.0031, 0.05]:
			var ra: Dictionary = a.strength_report(force, hole, 0.0)
			var rb: Dictionary = b.strength_report(force, hole, 0.0)
			for k in ra:
				if ra[k] is float:
					_cmp("ArmBeam.strength_report." + k, ra[k], rb[k], d)
	for i in 40:
		var s := rng.randf_range(-0.05, a.length_m + 0.05) if i > 1 else (0.0 if i == 0 else a.length_m)
		_cmp("ArmBeam.width_at", a.width_at(s), b.width_at(s), "%s s=%s" % [d, s])
		_cmp("ArmBeam.second_moment_at", a.second_moment_at(s), b.second_moment_at(s), "%s s=%s" % [d, s])
		_cmp("ArmBeam.bending_stress_pa", a.bending_stress_pa(9.0, s), b.bending_stress_pa(9.0, s),
			"%s s=%s" % [d, s])
		for hole in [0.0, 0.003, 0.2]:
			_cmp("ArmBeam.net_section_stress_pa", a.net_section_stress_pa(9.0, s, hole),
				b.net_section_stress_pa(9.0, s, hole), "%s s=%s h=%s" % [d, s, hole])
		_cmp("ArmBeam.bearing_stress_pa", a.bearing_stress_pa(9.0, s * 0.1),
			b.bearing_stress_pa(9.0, s * 0.1), "%s s=%s" % [d, s])


func _same(x: float, y: float) -> bool:
	return x == y or (is_nan(x) and is_nan(y))


func _cmp(fn: String, rust_v: Variant, ref_v: Variant, desc: String) -> void:
	total += 1
	if not stats.has(fn):
		stats[fn] = {"n": 0, "fails": 0, "first": ""}
	var s: Dictionary = stats[fn]
	s["n"] = int(s["n"]) + 1
	var ok: bool = (rust_v == ref_v) if rust_v is bool else _same(float(rust_v), float(ref_v))
	if not ok:
		s["fails"] = int(s["fails"]) + 1
		if String(s["first"]) == "":
			s["first"] = "%s  rust=%s ref=%s" % [desc, str(rust_v), str(ref_v)]


func _report(ms: int) -> void:
	var fails := 0
	var names := stats.keys()
	names.sort()
	for fn in names:
		var s: Dictionary = stats[fn]
		fails += int(s["fails"])
		var line := "  %-52s n=%-8d fails=%d" % [fn, int(s["n"]), int(s["fails"])]
		if int(s["fails"]) > 0:
			line += "   first: " + String(s["first"])
		print(line)
	print("%d comparisons across %d functions in %d ms, %d divergent" % [total, names.size(), ms, fails])
	if total < 500000:
		print("TOO FEW COMPARISONS — the sweep did not run")
		quit(1)
		return
	if fails == 0:
		print(SENTINEL)
		quit(0)
	else:
		print("FRAME LAW CROSSCHECK FAILED")
		quit(1)
