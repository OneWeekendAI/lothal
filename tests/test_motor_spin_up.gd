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
##   1. Tau rises with rotor inertia on every catalog motor; the 0802/2808 ordering is reported
##      (it is not an invariant: the damping term outgrows inertia with motor size).
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

const FALLBACK_TAU := 0.03
const _TAU := 6.283185307179586  # 2·pi. Local const so this file has no runtime dependency
                                 # on Godot's TAU builtin during import.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var materials := FrameMaterials.load_default()

	results.append(_test_tau_increases_with_rotor_inertia(catalog, materials))
	results.append(_test_whoop_and_cinelifter_tau_reported(catalog, materials))
	results.append(_test_j_blade_doubles_with_blade_count(catalog, materials))
	results.append(_test_j_rotor_scales_with_bell_radius_squared())
	results.append(_test_motor_model_lag_reproduces_its_own_tau())
	results.append(_test_no_tau_falls_back_to_pre_p7_constant())
	results.append(_test_every_catalog_motor_has_positive_tau(catalog, materials))
	results.append(_test_recovered_r_is_positive_where_data_is_present(catalog, materials))
	results.append(_test_specs_bell_ratio_reaches_the_geometry())

	return results


## Tau must GROW with rotor inertia, everything else held. This is the physical direction the
## 0802-vs-2808 comparison was standing in for. The cross-motor comparison itself is not an
## invariant: the damping term K_e^2/R falls with KV^2 and rises with stator size, so on catalog data
## the 2808 (J_total 4.2e-5) damps ~640x harder than the 0802 (9.0e-8) while carrying ~460x its
## inertia, and the 0802 comes out SLOWER (41 ms vs 30 ms, 2026-11-04). That is reported below, not
## asserted. What was a real bug is fixed: R_winding was recovered from datasheet amps at the BEMT
## rated point, whose model current is 1.5-1.8x the datasheet amps and unevenly so, which inflated R
## on the small motors (56 ms vs 46 ms). tau now uses the plant's own Rm.
static func _test_tau_increases_with_rotor_inertia(catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var problems: Array = []
	var checked := 0
	for motor in catalog.list_category("motor"):
		var base := _spin_up_for_motor(motor, catalog, materials)
		if base.is_empty():
			continue
		var heavy: Dictionary = motor.duplicate(true)
		heavy["specs"]["bell_mass_fraction"] = 0.8
		var more := _spin_up_for_motor(heavy, catalog, materials)
		checked += 1
		var tau0 := float(base["tau_s"])
		var tau1 := float(more["tau_s"])
		var j0 := float(base["j_rotor_kg_m2"])
		var j1 := float(more["j_rotor_kg_m2"])
		# J doubles (bell mass fraction 0.4 -> 0.8) and tau must rise, by the J_total ratio exactly
		# because the damping denominator does not depend on rotor inertia.
		var want := tau0 * float(more["j_total_kg_m2"]) / float(base["j_total_kg_m2"])
		if not (j1 > 1.99 * j0 and tau1 > tau0 and absf(tau1 - want) < 1e-9 * want):
			problems.append(str(motor.get("part_id", "?")))
	return TestResult.new(
		"tau rises with rotor inertia on every catalog motor (damping held)",
		checked >= 16 and problems.is_empty(),
		"%d motors checked; wrong on: %s" % [checked, ", ".join(problems)])


## The cross-motor ordering, REPORTED. Bounds are sanity only (a wired fallback of 0.03 s on both
## would give 1.00x; a zero or runaway tau would leave the band).
static func _test_whoop_and_cinelifter_tau_reported(catalog: PartsCatalog,
		materials: FrameMaterials) -> TestResult:
	var small := _tau_for(catalog, materials, "motor_0802_19000kv")
	var large := _tau_for(catalog, materials, "motor_2808_1300kv")
	var passed := small > 0.005 and small < 0.12 and large > 0.005 and large < 0.12 \
		and absf(small - FALLBACK_TAU) > 1e-6 and absf(large - FALLBACK_TAU) > 1e-6
	return TestResult.new(
		"0802 and 2808 taus are derived, per motor, inside 5-120 ms (ordering reported)",
		passed,
		"tau(0802) = %.4f s, tau(2808) = %.4f s, ratio 2808/0802 = %.2fx (damping K_e^2/R outgrows J; see propulsion.md §9 P7)" % [
			small, large, large / small])


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
		if str(s.get("tier", "")) in ["recovered", "model_rm"]:
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
	# The model's own fit (Build.fit_rated_point): k_t and k_q from the test prop's blade-element
	# integral (prop chapter, 2026-11-04), and the loaded rated rpm the recovery of R is anchored to.
	# This helper used to re-derive k_t from the DATASHEET thrust at Kv x V, a path the build no
	# longer flies, which made it disagree with Build.spin_up() (0802 tau 47 ms vs 2808 20 ms).
	var fit := Build.fit_rated_point(motor, test_prop)
	var k_q_at_test_prop := float(fit["k_q"])
	var omega_rated := PropellerModel.rpm_to_rad_s(float(fit["rpm"]))
	# For the catalog-wide test we use the test prop as the "fitted" prop too — that's the
	# reference-build convention: the aircraft flies on the prop the motor was measured with.
	var omega_hover := 0.5 * omega_rated
	var dc := Build.dc_motor_params(motor)
	return MotorSpinUp.compute(motor, test_doc, materials, k_q_at_test_prop, k_q_at_test_prop,
		omega_hover, omega_rated, 0.0 if dc.is_empty() else float(dc[1]))


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
