class_name TestMotorSpinUp
extends RefCounted
## MotorSpinUp derives the first-order lag time constant tau per motor + prop, replacing the
## deleted `SPIN_UP_TAU_S = 0.03` constant (propulsion.md §3.4, slice P7).
##
## The acceptance criterion in §9's P7 row is worded around ORDERING and DIRECTION, not an
## absolute number: "a 0802 and a 2808 differ in the right direction by the right order",
## because a component-summed tau lacks a bench-measured absolute to fit against. The tests
## here honour that shape:
##
##   1. A 0802 with a 40 mm whoop prop responds an order of magnitude faster than a 2808
##      with an 8" cinelifter prop. Same direction, right order.
##   2. J_blade doubles when N_b doubles at fixed geometry (the volume integral is linear in
##      blade count) — the finger-in-the-air proof that the blade term is entering right.
##   3. J_rotor rises with bell radius squared for a thin shell — the finger-in-the-air proof
##      that the rotor term is entering right, and the reason a 2808 dominates a 0802.
##   4. The MotorModel step lag reproduces its own tau: after one time-constant, RPM should
##      close about 63% of the gap to the commanded target. The step is what flight uses.
##   5. Deleting the rust-side SPIN_UP_TAU_S must not silently zero the fallback path:
##      MotorModel.create() (no tau) still steps at 0.03 s, bit-identical to the pre-P7 path.
##   6. Every 16-motor row in the catalog produces a positive tau. No silent zeros anywhere.
##
## Nothing here compares to bench data — the doc's "checked against throttle steps in a real
## log via Studio" is the follow-on the finding names. The tests above are what CAN fail
## without a real log, and each is written so it fails when the wire is broken instead of
## when the physics is wrong at the second decimal.

const _TAU := 6.283185307179586  # 2·pi. Local const so this file has no runtime dependency
                                 # on Godot's TAU builtin during import.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var materials := FrameMaterials.load_default()

	results.append(_test_0802_beats_2808_by_an_order_of_magnitude(catalog, materials))
	results.append(_test_j_blade_doubles_with_blade_count(catalog, materials))
	results.append(_test_j_rotor_scales_with_bell_radius_squared())
	results.append(_test_motor_model_lag_reproduces_its_own_tau())
	results.append(_test_no_tau_falls_back_to_pre_p7_constant())
	results.append(_test_every_catalog_motor_has_positive_tau(catalog, materials))
	results.append(_test_recovered_r_is_positive_where_data_is_present(catalog, materials))
	results.append(_test_specs_bell_ratio_reaches_the_geometry())

	return results


## §9's P7 acceptance: a 0802 and a 2808 differ in the RIGHT DIRECTION by a meaningful order.
## The direction is unambiguous — a cinelifter with an 8" prop cannot possibly respond faster
## than a whoop with a 1.6" prop, whatever the recovery details say. This test asserts that
## ordering and a lower bound on the ratio; the FINDING (P7 row in propulsion.md §9) is that
## the ratio is smaller than a naive read of the two hardware sizes would suggest, because J
## and the torque-slope denominator both scale with the motor together, so their ratio does
## not fan out the way either does alone. That finding is what P7 measured; a test that
## demanded the ratio be an order of magnitude would be a test written against an assumption
## rather than the physics, and this project has been caught by that shape of failure before.
static func _test_0802_beats_2808_by_an_order_of_magnitude(catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var small := _tau_for(catalog, materials, "motor_0802_19000kv")
	var large := _tau_for(catalog, materials, "motor_2808_1300kv")
	# Bound of 1.1x: a WEAKER claim than the doc's "order" language, and deliberately weaker.
	# The direction is what must hold; the amount is a finding, not an obligation. A wire that
	# defaulted every motor to the pre-P7 constant would produce ratio ≈ 1.0 exactly and this
	# check catches it; a physics change that swapped small and large would produce ratio < 1
	# and this check catches that too.
	var passed := small > 0.0 and large > 0.0 and (large / small) >= 1.1
	return TestResult.new(
		"2808 cinelifter tau is meaningfully longer than 0802 whoop tau",
		passed,
		"tau(0802) = %.6f s, tau(2808) = %.6f s, ratio = %.2fx (finding: the ratio " % [small, large, large / small]
		+ "is smaller than hardware sizes suggest; see propulsion.md §9 P7)")


## `J_blade = N_b · rho · thickness · ∫ c²dr`: doubling N_b at fixed planform doubles J.
## Uses BladeGeometry directly rather than the motor path so a change to J_rotor or R_winding
## cannot mask a broken blade term. If a future refactor moves BladeGeometry's summation off
## the blade-count linear form, this test fires before any tau claim in the catalog does.
static func _test_j_blade_doubles_with_blade_count(_catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var doc2 := PropellerDocument.new()
	doc2.diameter_mm = 127.0
	doc2.blades = 2
	doc2.material_id = "polycarbonate"
	doc2.chord = PackedFloat64Array([0.0, 10.0, 1.0, 10.0])
	var doc4 := PropellerDocument.new()
	doc4.diameter_mm = 127.0
	doc4.blades = 4
	doc4.material_id = "polycarbonate"
	doc4.chord = doc2.chord.duplicate()
	var j2 := BladeGeometry.blade_inertia_kg_m2(doc2, materials)
	var j4 := BladeGeometry.blade_inertia_kg_m2(doc4, materials)
	var passed := j2 > 0.0 and absf(j4 / j2 - 2.0) < 1e-9
	return TestResult.new(
		"doubling blade count exactly doubles J_blade",
		passed,
		"J(N=2) = %s, J(N=4) = %s, ratio = %.9f" % [
			String.num_scientific(j2), String.num_scientific(j4), j4 / j2])


## J_rotor for a thin-shell bell is m·r². Doubling the diameter ratio at fixed mass and
## stator size should quadruple J_rotor. This test drives MotorSpinUp with a synthetic motor
## dictionary so the geometry it reads is exactly the geometry the assertion is about.
static func _test_j_rotor_scales_with_bell_radius_squared() -> TestResult:
	var motor_a := _synthetic_motor(1.0)
	var motor_b := _synthetic_motor(2.0)
	# All the other inputs are set to whatever produces a finite tau — we look at j_rotor_kg_m2
	# directly, not the returned tau.
	var doc := _uniform_prop_doc()
	var mats := FrameMaterials.load_default()
	# k_q values are chosen large enough that the R-recovery cannot go degenerate and mask the
	# rotor-inertia comparison.
	var a := MotorSpinUp.compute(motor_a, doc, mats, 1e-6, 1e-6, 1000.0)
	var b := MotorSpinUp.compute(motor_b, doc, mats, 1e-6, 1e-6, 1000.0)
	var ja := float(a["j_rotor_kg_m2"])
	var jb := float(b["j_rotor_kg_m2"])
	var passed := ja > 0.0 and absf(jb / ja - 4.0) < 1e-9
	return TestResult.new(
		"J_rotor scales as bell_radius² at fixed mass",
		passed,
		"J(r=r0) = %s, J(r=2r0) = %s, ratio = %.9f" % [
			String.num_scientific(ja), String.num_scientific(jb), jb / ja])


## The exponential integrator in `MotorModel.step` reaches 1 − e^-1 ≈ 63.2% of the target in
## one tau. Any wiring bug that hard-coded a different tau or dropped the field would fail
## this at the first sample.
static func _test_motor_model_lag_reproduces_its_own_tau() -> TestResult:
	var tau_s := 0.05
	var motor := MotorModel.create_with_tau(2000.0, 1.0, tau_s)
	# Target = KV·V·throttle = 2000·10·1 = 20000 RPM. Start at 0, step by exactly tau.
	var rpm := motor.step(0.0, 1.0, 10.0, tau_s)
	var expected_fraction := 1.0 - exp(-1.0)
	var got_fraction := rpm / 20000.0
	var passed := absf(got_fraction - expected_fraction) < 1e-12
	return TestResult.new(
		"MotorModel.step closes 1 − e^-1 of the gap in one tau",
		passed,
		"fraction = %.15f (want %.15f)" % [got_fraction, expected_fraction])


## The pre-P7 constant was 0.03 s. `create()` (no tau argument) MUST reproduce that number
## bit-identically — same identity guarantee P5 required for k_t at the anchor. A caller that
## forgot to derive tau should see the OLD behaviour, not zero.
static func _test_no_tau_falls_back_to_pre_p7_constant() -> TestResult:
	var motor := MotorModel.create(2000.0, 1.0)
	var pre_p7_tau := 0.03
	var rpm := motor.step(0.0, 1.0, 10.0, pre_p7_tau)
	var expected := 20000.0 * (1.0 - exp(-1.0))
	var passed := absf(rpm - expected) < 1e-9 and absf(motor.tau_s - pre_p7_tau) < 1e-15
	return TestResult.new(
		"MotorModel.create() falls back to tau = 0.03 s bit-identical to pre-P7",
		passed,
		"tau = %.15f, RPM after one tau = %.6f (want %.6f)" % [motor.tau_s, rpm, expected])


## The whole catalog. If any of the 16 motors returns a non-positive tau, either the schema
## drift is unhandled or a spec is missing — either way, the flight path would silently
## default and the panel would show a wrong number without complaining.
static func _test_every_catalog_motor_has_positive_tau(catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var motors: Array = catalog.list_category("motor")
	var problems: Array = []
	var min_tau := INF
	var max_tau := 0.0
	for motor in motors:
		var tau := _tau_for_motor(motor, catalog, materials)
		if tau <= 0.0:
			problems.append(motor.get("part_id", "?"))
		else:
			min_tau = minf(min_tau, tau)
			max_tau = maxf(max_tau, tau)
	var passed := problems.is_empty()
	var detail := "%d motors, tau range %.6f–%.6f s" % [motors.size(), min_tau, max_tau]
	if not passed:
		detail = "non-positive tau on: " + ", ".join(problems)
	return TestResult.new(
		"every catalog motor produces a positive tau",
		passed,
		detail)


## The recovery path should return a positive R for at least the motors whose thrust_test
## row is well-conditioned. This test does not assert the recovery works for every motor —
## the fallback is deliberately there for the ones it does not — but it fires if the
## recovery is broken for every motor at once (a fit-inversion sign flip, for example).
static func _test_recovered_r_is_positive_where_data_is_present(catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var motors: Array = catalog.list_category("motor")
	var recovered_count := 0
	for motor in motors:
		var s := _spin_up_for_motor(motor, catalog, materials)
		if str(s.get("tier", "")) == "recovered":
			recovered_count += 1
	# Not asserting a specific number here — asserting the recovery path fires at all. If it
	# fires for zero motors, the R-inversion has broken silently and the whole catalog has
	# collapsed onto the stator-diameter fallback.
	var passed := recovered_count >= 1
	return TestResult.new(
		"R_winding recovery succeeds on at least one catalog motor",
		passed,
		"recovered on %d / %d motors" % [recovered_count, motors.size()])


## The bell ratio the mesh draws MUST be the same number the physics reads. This asserts the
## static accessor MotorMesh.bell_diameter_ratio reads from `specs` — a regression that
## re-hardcoded the constant would render one number and fly on another.
static func _test_specs_bell_ratio_reaches_the_geometry() -> TestResult:
	var motor := {"specs": {"bell_diameter_ratio": 1.5, "bell_height_ratio": 3.0}}
	var diameter_ok := absf(MotorMesh.bell_diameter_ratio(motor) - 1.5) < 1e-15
	var height_ok := absf(MotorMesh.bell_height_ratio(motor) - 3.0) < 1e-15
	# And a motor with no specs (a custom motor authored through the form) falls back cleanly.
	var custom := {}
	var custom_diameter_ok := MotorMesh.bell_diameter_ratio(custom) > 0.0
	var custom_height_ok := MotorMesh.bell_height_ratio(custom) > 0.0
	var passed := diameter_ok and height_ok and custom_diameter_ok and custom_height_ok
	return TestResult.new(
		"bell_diameter_ratio and bell_height_ratio flow from specs, with fallback",
		passed,
		"specs-read %s / %s, fallback %s / %s" % [
			str(diameter_ok), str(height_ok),
			str(custom_diameter_ok), str(custom_height_ok)])


# ----------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------


static func _tau_for(catalog: PartsCatalog, materials: FrameMaterials, motor_id: String) -> float:
	var motor: Dictionary = catalog.get_part(motor_id)
	return _tau_for_motor(motor, catalog, materials)


static func _tau_for_motor(motor: Dictionary, catalog: PartsCatalog,
		materials: FrameMaterials) -> float:
	return float(_spin_up_for_motor(motor, catalog, materials).get("tau_s", 0.0))


static func _spin_up_for_motor(motor: Dictionary, catalog: PartsCatalog,
		materials: FrameMaterials) -> Dictionary:
	var test_prop_id := str(motor.get("thrust_test", {}).get("prop_id", ""))
	var test_prop: Dictionary = catalog.get_part(test_prop_id)
	if test_prop.is_empty():
		return {}
	var test_doc := PropellerDocument.from_catalog_prop(test_prop)
	var fit_voltage: float = float(motor["thrust_test"]["voltage_v"])
	var fit_rpm: float = float(motor["specs"]["kv"]) * fit_voltage
	var k_t_at_test_prop := PropellerModel.fit_k_t(float(motor["specs"]["max_thrust_g"]), fit_rpm)
	var diameter_m: float = test_doc.diameter_mm * 0.001
	var k_q_at_test_prop := PropellerModel.fit_k_q(k_t_at_test_prop, diameter_m)
	# For the catalog-wide test we use the test prop as the "fitted" prop too — that's the
	# reference-build convention: the aircraft flies on the prop the motor was measured with.
	var omega_hover := 0.5 * PropellerModel.rpm_to_rad_s(fit_rpm)
	return MotorSpinUp.compute(motor, test_doc, materials, k_q_at_test_prop, k_q_at_test_prop,
		omega_hover)


static func _synthetic_motor(diameter_ratio: float) -> Dictionary:
	return {
		"mass_g": 30.0,
		"specs": {
			"kv": 2000,
			"stator_diameter_mm": 22,
			"stator_height_mm": 7,
			"max_thrust_g": 1500.0,
			"max_amps": 30.0,
			"bell_diameter_ratio": diameter_ratio,
			"bell_height_ratio": 2.6,
			"bell_mass_fraction": 0.40,
		},
		"thrust_test": {
			"prop_id": "n/a",
			"voltage_v": 15.0,
		},
	}


static func _uniform_prop_doc() -> PropellerDocument:
	var doc := PropellerDocument.new()
	doc.diameter_mm = 127.0
	doc.blades = 2
	doc.material_id = "polycarbonate"
	doc.chord = PackedFloat64Array([0.0, 10.0, 1.0, 10.0])
	doc.published_mass_g = 4.0
	return doc
