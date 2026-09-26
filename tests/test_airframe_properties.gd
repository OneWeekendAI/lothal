class_name TestAirframeProperties
extends RefCounted
## airframe.md §3.2–§3.4: mass from ρ·t·A, the CG from a first-moment sum, and the full 3×3 tensor
## with the thin-plate closed form and the tensor parallel-axis shift.
##
## Two of these tests exist because of failures that DO NOT SHOW UP as wrong-looking numbers:
##
##   - the coordinate transposition (§3.4's callout). A symmetric X frame has roll == pitch, so
##     every fixture anyone writes first passes with the mapping backwards. `_test_a_stretched
##     _frame_rolls_harder_than_it_pitches` is the only test here that can catch it, and it asserts
##     a DIRECTION and a RATIO rather than mere inequality — "roll ≠ pitch" is satisfied by the
##     transposed model too.
##   - the composite-shift bug (§3.1). Holes concentric with their outline give the right answer
##     even when the shift is done per-part, so the hole fixture below puts its holes OFF-CENTRE.
##
## The mass check is the one §3.2 nominates as falsifiable, and it is run as a falsification rather
## than as a demonstration: the generator that produces the presets never reads `mass_g`, so
## nothing in the pipeline can have been fitted to the answer.

const CARBON := "carbon_3k_twill_0_90"
## §3.2's bound. Written here once, before the numbers, and never moved — a bound adjusted to fit
## the data is not a bound (the project's standing rule, and validation.md's).
const MASS_TOLERANCE := 0.10

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var materials := FrameMaterials.load_default()

	results.append(_test_a_flat_plate_matches_the_box_formula(materials))
	results.append(_test_a_stretched_frame_rolls_harder_than_it_pitches(materials))
	results.append(_test_a_rotated_plate_has_the_right_product_of_inertia(materials))
	results.append(_test_off_centre_holes_remove_the_right_mass_and_inertia(materials))
	results.append(_test_parallel_axis_computed_two_ways(materials))
	results.append(_test_the_tensor_does_not_care_where_the_origin_is(materials))
	results.append(_test_cg_rises_with_a_raised_plate(materials))
	results.append(_test_preset_masses_land_within_ten_percent(catalog, materials))
	results.append(_test_against_the_existing_mass_model(catalog, materials))
	results.append_array(_test_prop_guard_enters_via_extra_parts(materials))
	return results


# ---------------------------------------------------------------------------
# P10a — the prop-guard wiring (plans/2026-08-26-propulsion-room-design.md §3)
# ---------------------------------------------------------------------------

## Four checks in one, because the wiring's correctness has four faces and one bad shape can
## satisfy any subset. §3.5 of the design doc: nothing in AirframeProperties changes — the
## extra_parts slot is already the right shape. So this test asserts BEHAVIOUR (the numbers
## AirframeProperties produces) rather than INTERFACE (which needs no new checks).
##
## The fixture is a symmetric X — a single square plate at the origin, so the plate's own tensor
## is diagonal in body axes, and guards at four symmetric arm positions add only a diagonal
## roll+pitch+yaw contribution the arithmetic can be pinned to. Every number below is elementary
## and nothing is fitted.
static func _test_prop_guard_enters_via_extra_parts(materials: FrameMaterials) -> Array:
	var results: Array = []

	# A 200x200 mm carbon plate at the origin. Its own tensor is symmetric about all three axes
	# and is the SAME with or without guards, so the delta is exclusively the guards.
	var plate_side_mm := 200.0
	var doc := _document_of([AirframeDocument.make_plate(
		_rectangle(plate_side_mm, plate_side_mm), [], 2.0, 0.0, "centre_plate")])

	# The reference cinewhoop ring, from the P9 finding: outer 68 mm, wall 3 mm, height 12 mm,
	# ABS ρ = 1050. Mount radius 96 mm — a real 5" arm length from frames.json. The four motors
	# sit at the corners of a square, at x = ±arm and z = ±arm in the plate's plane (their radial
	# distance from the centre is arm·√2, which is deliberate and does not enter the arithmetic
	# below: roll is I_ZZ = Σ m(x² + y²), and with y = 0 only the x-offset contributes).
	var arm_m := 0.096
	var guard_spec := {
		"kind": PropGuard.KIND_BUMPER,
		"outer_radius_mm": 68.0, "wall_mm": 3.0, "height_mm": 12.0,
		"density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
	}
	# One PartMass per motor position, at the four corners of the ±arm square.
	var motor_positions := [
		Vector3(arm_m, 0.0, arm_m),
		Vector3(-arm_m, 0.0, arm_m),
		Vector3(arm_m, 0.0, -arm_m),
		Vector3(-arm_m, 0.0, -arm_m),
	]
	var guards_extra: Array = []
	for pos in motor_positions:
		var pm: PartMass = PropGuard.as_part_mass(guard_spec, pos)
		if pm != null:
			guards_extra.append(pm)

	# ---- Check 1: without guards, the tensor has NO CONTRIBUTION from prop_guard ----------
	# A default extra_parts = [] fixture must produce a tensor that contains no guard mass.
	# This is the guard against a load-time regression that would enumerate guards.json even
	# when a build fits none — the reference-build oracle depends on this being true.
	var props_without := AirframeProperties.compute(doc, materials)
	var guard_labels_without := 0
	for c in props_without.contributions:
		if String(c["label"]) == "prop_guard":
			guard_labels_without += 1
	results.append(TestResult.new(
		"a document with no guards fitted produces zero 'prop_guard' contributions — the reference-build oracle stands",
		guard_labels_without == 0,
		"contributions contain %d prop_guard labels (must be 0)" % guard_labels_without))

	# ---- Check 2: with four guards, mass increases by 4 × PropGuard.mass_kg -------------
	# Every number here is elementary: four rings, each PropGuard.mass_kg(spec), added to the
	# plate mass. A guard that failed to add mass would fail this by 4× the ring mass.
	var props_with := AirframeProperties.compute(doc, materials, guards_extra)
	var expected_ring_mass_kg := PropGuard.mass_kg(guard_spec)
	var expected_delta_kg := 4.0 * expected_ring_mass_kg
	var actual_delta_kg := props_with.total_mass_kg - props_without.total_mass_kg
	results.append(TestResult.new(
		"four guards add 4 × ring_mass to the total — mass enters through extra_parts unchanged",
		absf(actual_delta_kg - expected_delta_kg) < 1.0e-9,
		"delta=%.6f g, expected=%.6f g (ring=%.6f g)" % [actual_delta_kg * 1000.0,
			expected_delta_kg * 1000.0, expected_ring_mass_kg * 1000.0]))

	# ---- Check 3: the roll-inertia delta matches 4 × m × arm², NOT twice that -----------
	# The load-bearing check, and the reason P10a exists. Four rings at ±arm on X and ±arm on
	# Z contribute, about the roll axis (Z), a parallel-axis term of m·d² where d² = x² + y².
	# For rings at (±arm, 0, ±arm), the x-component contributes m·arm² each (four times) so the
	# roll-inertia delta is exactly 4·m·arm². If a stub wired the scalar
	# roll_inertia_contribution_kg_m2 into the ROLL component of local_inertia_diag, this check
	# would fail by EXACTLY 4·m·R_guard² extra — the double-count the P9 row's own paragraph
	# warned about, and check 5 below inserts that mutation and asserts it does fail.
	#
	# Which component is the roll one matters and is easy to get backwards: AirframeProperties
	# names roll = I_ZZ (rotation about the fore/aft axis), so the double-count lands on the Z
	# component of local_inertia_diag and NOT on the X one. A stub that wired the scalar to X
	# would land in PITCH inertia and slip past this check entirely — which is why the
	# `local_inertia_diag == Vector3.ZERO` assertion in test_prop_guard.gd is the axis-blind
	# half of the pair and this one is the consequence-showing half.
	#
	# Numbers, so a mutation is caught by name rather than by tolerance:
	#   m = PropGuard.mass_kg(spec) ≈ 0.01579 kg (5" cinewhoop ring)
	#   arm² = 0.096² = 0.009216 m²
	#   4·m·arm² = 4 × 0.01579 × 0.009216 = 5.82e-4 kg·m²
	# A double-count would add ANOTHER 4·m·R_guard², with R_guard = mount_radius + outer_radius =
	# 164 mm: 4 × 0.01579 × 0.164² = 1.70e-3 kg·m² of spurious extra inertia, taking the delta to
	# 2.28e-3 — 3.9× the truth, which the tolerance below rejects by four orders of magnitude.
	var actual_roll_delta := props_with.roll_inertia_kg_m2() - props_without.roll_inertia_kg_m2()
	var expected_roll_delta := 4.0 * expected_ring_mass_kg * arm_m * arm_m
	results.append(TestResult.new(
		"roll-inertia delta is 4·m·arm² — parallel-axis supplies the R² bite ONCE, no double-count",
		absf(actual_roll_delta - expected_roll_delta) / absf(expected_roll_delta) < 1.0e-5,
		"actual=%f, expected=%f (m=%.3f g, arm=%.3f m)" % [actual_roll_delta,
			expected_roll_delta, expected_ring_mass_kg * 1000.0, arm_m]))

	# ---- Check 4: a refused spec adds no mass — no class-typical fallback --------------
	# A guard whose spec PropGuard.compute() refuses returns null from as_part_mass. A build
	# that filters those out (the pattern the design doc recommends) contributes exactly the
	# base mass, and nothing labelled prop_guard sneaks in.
	var bad_guards: Array = []
	var bad_pm := PropGuard.as_part_mass({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 68.0, "wall_mm": -3.0, "height_mm": 12.0,
			"density_kg_m3": 1050.0, "mount_radius_mm": 96.0}, motor_positions[0])
	if bad_pm != null:
		bad_guards.append(bad_pm)
	var props_bad := AirframeProperties.compute(doc, materials, bad_guards)
	results.append(TestResult.new(
		"a spec compute() refuses contributes no mass — no fallback to a class-typical ring",
		absf(props_bad.total_mass_kg - props_without.total_mass_kg) < 1.0e-12,
		"delta_kg=%.9f (must be 0)" % (props_bad.total_mass_kg - props_without.total_mass_kg)))

	# ---- Check 5: the double-count, INSERTED and caught -------------------------------
	# Design doc §3.6's last bullet, and the one check here that is written as a positive
	# assertion about a mutation rather than as a pin on the correct answer. Check 3 would fail
	# if as_part_mass regressed, but "check 3 would fail" is a claim about a test, and the whole
	# point of the P9 row's warning is that the double-count is invisible in every mass number
	# and shows up only in the tensor. So: build the mutant by hand — the same four guards, but
	# each carrying compute()'s scalar `roll_inertia_contribution_kg_m2` on the ROLL (Z) axis of
	# its local diagonal, which is exactly what a well-meaning wiring of "the guard's roll
	# inertia contribution" looks like — and assert the roll inertia it produces is WRONG, by
	# the specific 4·m·R_guard² the parallel-axis shift has already supplied.
	#
	# Without as_part_mass's Vector3.ZERO this test's subject and check 3's subject are the same
	# object, and check 3 goes red. That is the point: the mutation has nowhere to hide.
	var scalar_roll_kg_m2 := float(PropGuard.compute(guard_spec)["roll_inertia_contribution_kg_m2"])
	var mutant_extra: Array = []
	for pos in motor_positions:
		mutant_extra.append(PartMass.new(expected_ring_mass_kg, pos,
			Vector3(0.0, 0.0, scalar_roll_kg_m2), "prop_guard"))
	var props_mutant := AirframeProperties.compute(doc, materials, mutant_extra)
	var mutant_roll_delta := props_mutant.roll_inertia_kg_m2() - props_without.roll_inertia_kg_m2()
	var spurious := 4.0 * scalar_roll_kg_m2
	results.append(TestResult.new(
		"the double-count mutation DOES fail: the scalar on the local roll axis adds 4·m·R_guard² of inertia the parallel-axis shift already supplied",
		absf(mutant_roll_delta - (expected_roll_delta + spurious)) / absf(expected_roll_delta) < 1.0e-5
			and mutant_roll_delta > expected_roll_delta * 2.0,
		"mutant delta=%.9f, correct delta=%.9f, spurious term=%.9f (ratio %.2fx)" % [
			mutant_roll_delta, expected_roll_delta, spurious,
			mutant_roll_delta / expected_roll_delta]))

	# And the mass is IDENTICAL under the mutation — which is why a mass-only test suite would
	# have shipped the double-count. Stated as an assertion so the claim above is not rhetoric.
	results.append(TestResult.new(
		"the same mutation moves NO mass number — the double-count is invisible outside the tensor",
		absf(props_mutant.total_mass_kg - props_with.total_mass_kg) < 1.0e-12,
		"mutant total=%.9f kg, correct total=%.9f kg" % [props_mutant.total_mass_kg,
			props_with.total_mass_kg]))

	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A counter-clockwise rectangle, `width_mm` across the plate's u (world X) and `depth_mm` across
## its v (world Z), centred on `centre_mm`.
static func _rectangle(width_mm: float, depth_mm: float, centre_mm := Vector2.ZERO) -> PackedVector2Array:
	var w := width_mm * 0.5
	var d := depth_mm * 0.5
	return PackedVector2Array([
		centre_mm + Vector2(-w, -d), centre_mm + Vector2(w, -d),
		centre_mm + Vector2(w, d), centre_mm + Vector2(-w, d),
	])


## The same rectangle wound clockwise, which is what makes it a hole (§3.1).
static func _rectangular_hole(side_mm: float, centre_mm: Vector2) -> PackedVector2Array:
	return PolygonProps.reversed(_rectangle(side_mm, side_mm, centre_mm))


static func _document_of(plates: Array) -> AirframeDocument:
	var doc := AirframeDocument.new()
	doc.material_id = CARBON
	doc.plates = plates
	return doc


static func _relative(actual: float, expected: float) -> float:
	if absf(expected) < 1e-15:
		return absf(actual)
	return absf(actual - expected) / absf(expected)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

static func _test_a_flat_plate_matches_the_box_formula(materials: FrameMaterials) -> TestResult:
	# One rectangular plate is a solid cuboid, whose tensor is the textbook m(a²+b²)/12 on every
	# axis. That makes this the anchor test: the polygon integral, the ρ·t·A mass, the m·t²/12
	# through-thickness terms and the axis mapping all have to be right together to reproduce it,
	# and there is no fitted constant anywhere in the comparison.
	var width := 200.0    # along u -> world X
	var depth := 80.0     # along v -> world Z
	var thickness := 6.0  # thick on purpose: this is where m·t²/12 stops being negligible
	var doc := _document_of([AirframeDocument.make_plate(
		_rectangle(width, depth), [], thickness, 0.0, AirframeDocument.ROLE_BOTTOM)])
	var props := AirframeProperties.compute(doc, materials)

	var rho := materials.density(CARBON)
	var w := width / 1000.0
	var d := depth / 1000.0
	var t := thickness / 1000.0
	var expected_mass := rho * w * d * t
	var expected_pitch := expected_mass * (d * d + t * t) / 12.0   # about X
	var expected_roll := expected_mass * (w * w + t * t) / 12.0    # about Z
	var expected_yaw := expected_mass * (w * w + d * d) / 12.0     # about Y

	var errors := {
		"mass": _relative(props.total_mass_kg, expected_mass),
		"pitch": _relative(props.pitch_inertia_kg_m2(), expected_pitch),
		"roll": _relative(props.roll_inertia_kg_m2(), expected_roll),
		"yaw": _relative(props.yaw_inertia_kg_m2(), expected_yaw),
	}
	var worst := 0.0
	for key in errors:
		worst = maxf(worst, errors[key])
	# The products of inertia of an axis-aligned plate are exactly zero, and a wrong Ixy sign
	# convention would still leave them zero here — which is why the rotated case lives in
	# test_polygon_props.gd and this one only asserts the diagonal.
	var products_zero := absf(props.i_xz) < 1e-12 and absf(props.i_xy) < 1e-12

	return TestResult.new(
		"a 200x80x6 mm plate reproduces the solid-cuboid tensor exactly",
		worst < 1e-6 and products_zero,
		"worst relative error %s (mass %.4f kg, roll %s, pitch %s, yaw %s kg m^2); products %s" % [
			worst, props.total_mass_kg, props.roll_inertia_kg_m2(),
			props.pitch_inertia_kg_m2(), props.yaw_inertia_kg_m2(), props.i_xz])


static func _test_a_stretched_frame_rolls_harder_than_it_pitches(materials: FrameMaterials) -> TestResult:
	# THE MANDATORY ASYMMETRIC FIXTURE (§3.4). A frame stretched SIDEWAYS — wide across, short
	# nose-to-tail — has its mass further from the fore/aft axis than from the lateral one, so it
	# must be harder to ROLL than to PITCH. Transpose the mapping and the model says the opposite
	# while every mass, every CG and every order of magnitude stays perfectly plausible.
	#
	# Two independent halves, because the transposition can hide in either path and each half is
	# blind to the other's:
	#   (a) IN-PLANE, one wide plate. Exercises polygon ixx/iyy -> world X/Z.
	#   (b) PARALLEL AXIS, four motor pads out at (±120, ±60) mm. Exercises the d⊗d shift, which
	#       could be transposed on its own even with (a) right.
	var problems: Array = []
	var rho := materials.density(CARBON)

	# (a) one plate, 240 mm across the airframe and 60 mm fore-aft.
	var wide := AirframeProperties.compute(_document_of([AirframeDocument.make_plate(
		_rectangle(240.0, 60.0), [], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM)]), materials)
	var plate_ratio := wide.roll_inertia_kg_m2() / wide.pitch_inertia_kg_m2()
	# (0.240² + 0.002²) / (0.060² + 0.002²) — the cuboid ratio, worked out in full.
	var expected_plate_ratio := (0.240 * 0.240 + 0.002 * 0.002) / (0.060 * 0.060 + 0.002 * 0.002)
	if wide.roll_inertia_kg_m2() <= wide.pitch_inertia_kg_m2():
		problems.append("in-plane: roll %s is not greater than pitch %s" % [
			wide.roll_inertia_kg_m2(), wide.pitch_inertia_kg_m2()])
	if _relative(plate_ratio, expected_plate_ratio) > 1e-6:
		problems.append("in-plane ratio %.4f, expected %.4f" % [plate_ratio, expected_plate_ratio])

	# (b) four 20 mm pads at (±120, ±60) mm — a stretched X, motors wide and close-coupled.
	var pads: Array = []
	for x in [-120.0, 120.0]:
		for z in [-60.0, 60.0]:
			pads.append(AirframeDocument.make_plate(
				_rectangle(20.0, 20.0, Vector2(x, z)), [], 2.0, 0.0, AirframeDocument.ROLE_ARM))
	var stretched := AirframeProperties.compute(_document_of(pads), materials)

	var pad_mass := rho * 0.020 * 0.020 * 0.002
	var own := pad_mass * (0.020 * 0.020 + 0.002 * 0.002) / 12.0
	var expected_roll := 4.0 * (own + pad_mass * 0.120 * 0.120)
	var expected_pitch := 4.0 * (own + pad_mass * 0.060 * 0.060)
	if stretched.roll_inertia_kg_m2() <= stretched.pitch_inertia_kg_m2():
		problems.append("parallel-axis: roll %s is not greater than pitch %s" % [
			stretched.roll_inertia_kg_m2(), stretched.pitch_inertia_kg_m2()])
	if _relative(stretched.roll_inertia_kg_m2(), expected_roll) > 1e-6:
		problems.append("parallel-axis roll %s, expected %s" % [
			stretched.roll_inertia_kg_m2(), expected_roll])
	if _relative(stretched.pitch_inertia_kg_m2(), expected_pitch) > 1e-6:
		problems.append("parallel-axis pitch %s, expected %s" % [
			stretched.pitch_inertia_kg_m2(), expected_pitch])
	# Yaw is the perpendicular-axis sum for flat plates, whichever way round the other two are.
	# It is asserted here because a mapping that swapped roll and pitch AND rebuilt yaw out of the
	# swapped pair would still satisfy the two checks above.
	if _relative(stretched.yaw_inertia_kg_m2(),
			stretched.roll_inertia_kg_m2() + stretched.pitch_inertia_kg_m2()
				- 8.0 * pad_mass * 0.002 * 0.002 / 12.0) > 1e-6:
		problems.append("yaw is not the perpendicular-axis sum")

	return TestResult.new(
		"a laterally stretched frame is harder to roll than to pitch, by the right ratio",
		problems.is_empty(),
		"in-plane roll/pitch %.3f (expected %.3f); stretched-X roll %s vs pitch %s (ratio %.3f)" % [
			plate_ratio, expected_plate_ratio, stretched.roll_inertia_kg_m2(),
			stretched.pitch_inertia_kg_m2(),
			stretched.roll_inertia_kg_m2() / stretched.pitch_inertia_kg_m2()]
			if problems.is_empty() else "; ".join(problems))


static func _test_a_rotated_plate_has_the_right_product_of_inertia(materials: FrameMaterials) -> TestResult:
	# The ONLY test here that can see the sign of I_xz, and it exists because every other fixture
	# in this file is axis-aligned and an axis-aligned plate has I_xz == 0 whatever the convention.
	# §3.1 says the same thing about its own `ixy` and carries a 30° case for it; this is that case
	# carried one level up, into the MASS tensor, where a second sign flip lives (`I_xz = −ρ·t·Ixy`,
	# the opposite of PolygonProps' `+∫xy dA`). Getting it backwards makes a deadcat yaw the wrong
	# way when it rolls — §3.4's stated reason for computing products of inertia at all.
	#
	# Rotate a 200 x 80 plate by +30° in its own plane. With the unrotated plate's principal
	# moments A (pitch, about X) and C (roll, about Z), the rotated tensor is exactly:
	#     I_XX(θ) = A·cos²θ + C·sin²θ
	#     I_ZZ(θ) = A·sin²θ + C·cos²θ
	#     I_XZ(θ) = (A − C)·sinθ·cosθ
	# and since C > A for a plate that is wider than it is deep, I_XZ must come out NEGATIVE at
	# +30°. The sign is asserted on its own line, separately from the magnitude, because a
	# magnitude check written as absf() would pass with the convention inverted.
	var theta := deg_to_rad(30.0)
	var flat := _rectangle(200.0, 80.0)
	var turned := PackedVector2Array()
	for point in flat:
		turned.append(point.rotated(theta))

	var straight := AirframeProperties.compute(_document_of([AirframeDocument.make_plate(
		flat, [], 3.0, 0.0, AirframeDocument.ROLE_BOTTOM)]), materials)
	var rotated := AirframeProperties.compute(_document_of([AirframeDocument.make_plate(
		turned, [], 3.0, 0.0, AirframeDocument.ROLE_BOTTOM)]), materials)

	var a := straight.pitch_inertia_kg_m2()
	var c := straight.roll_inertia_kg_m2()
	var expected_pitch := a * cos(theta) * cos(theta) + c * sin(theta) * sin(theta)
	var expected_roll := a * sin(theta) * sin(theta) + c * cos(theta) * cos(theta)
	var expected_xz := (a - c) * sin(theta) * cos(theta)

	var problems: Array = []
	if _relative(rotated.pitch_inertia_kg_m2(), expected_pitch) > 1e-6:
		problems.append("pitch %s, expected %s" % [rotated.pitch_inertia_kg_m2(), expected_pitch])
	if _relative(rotated.roll_inertia_kg_m2(), expected_roll) > 1e-6:
		problems.append("roll %s, expected %s" % [rotated.roll_inertia_kg_m2(), expected_roll])
	if _relative(rotated.i_xz, expected_xz) > 1e-5:
		problems.append("i_xz %s, expected %s" % [rotated.i_xz, expected_xz])
	if rotated.i_xz >= 0.0:
		problems.append("i_xz came out non-negative (%s) — the sign convention is inverted" % rotated.i_xz)
	# Rotating in plane cannot change the mass or the yaw inertia; if either moved, the fixture is
	# measuring something other than a rotation.
	if _relative(rotated.total_mass_kg, straight.total_mass_kg) > 1e-6 \
			or _relative(rotated.yaw_inertia_kg_m2(), straight.yaw_inertia_kg_m2()) > 1e-6:
		problems.append("rotating the plate changed its mass or its yaw inertia")

	return TestResult.new(
		"a 30-degree rotated plate has the right product of inertia, sign included",
		problems.is_empty(),
		"i_xz %s (expected %s, negative as it must be); pitch and roll match the rotation formula" % [
			rotated.i_xz, expected_xz] if problems.is_empty() else "; ".join(problems))


static func _test_off_centre_holes_remove_the_right_mass_and_inertia(materials: FrameMaterials) -> TestResult:
	# Two square holes at ±40 mm along u. Off-centre on purpose: §3.1 says a per-part centroidal
	# shift gives the RIGHT answer for a concentric hole, so a concentric fixture proves nothing.
	# Square rather than round, so every expectation below is exact arithmetic with no tessellation
	# deficit to allow for — the circle's ~1.3% inscribed-area bias would otherwise have to be
	# folded into a tolerance, and a tolerance that absorbs a real bug is how this test dies.
	var width := 200.0
	var depth := 100.0
	var thickness := 3.0
	var hole_side := 20.0
	var offset := 40.0

	var solid := AirframeProperties.compute(_document_of([AirframeDocument.make_plate(
		_rectangle(width, depth), [], thickness, 0.0, AirframeDocument.ROLE_BOTTOM)]), materials)
	var drilled := AirframeProperties.compute(_document_of([AirframeDocument.make_plate(
		_rectangle(width, depth),
		[_rectangular_hole(hole_side, Vector2(-offset, 0.0)),
			_rectangular_hole(hole_side, Vector2(offset, 0.0))],
		thickness, 0.0, AirframeDocument.ROLE_BOTTOM)]), materials)

	var rho := materials.density(CARBON)
	var t := thickness / 1000.0
	var s := hole_side / 1000.0
	var e := offset / 1000.0
	var hole_mass := rho * t * s * s

	# Mass removed: two squares of material.
	var expected_mass := solid.total_mass_kg - 2.0 * hole_mass
	# Roll (about Z, built from u²): each hole removes its own moment PLUS its m·e² — the term a
	# per-part centroidal shift drops, and the entire reason this fixture is off-centre.
	var expected_roll := solid.roll_inertia_kg_m2() \
		- 2.0 * (hole_mass * (s * s + t * t) / 12.0 + hole_mass * e * e)
	# Pitch (about X, built from v²): the holes are on the v = 0 line, so only their own moment goes.
	var expected_pitch := solid.pitch_inertia_kg_m2() - 2.0 * hole_mass * (s * s + t * t) / 12.0

	var problems: Array = []
	if drilled.total_mass_kg >= solid.total_mass_kg:
		problems.append("drilling did not remove mass")
	if _relative(drilled.total_mass_kg, expected_mass) > 1e-9:
		problems.append("mass %.6f kg, expected %.6f" % [drilled.total_mass_kg, expected_mass])
	if _relative(drilled.roll_inertia_kg_m2(), expected_roll) > 1e-9:
		problems.append("roll %s, expected %s" % [drilled.roll_inertia_kg_m2(), expected_roll])
	if _relative(drilled.pitch_inertia_kg_m2(), expected_pitch) > 1e-9:
		problems.append("pitch %s, expected %s" % [drilled.pitch_inertia_kg_m2(), expected_pitch])
	# The symmetric pair leaves the centroid where it was; a composite shift done wrongly would
	# move it, so this is a second, cheaper witness on the same bug.
	if drilled.cg_m.length() > 1e-12:
		problems.append("CG moved to %s" % drilled.cg_m)

	return TestResult.new(
		"two off-centre holes remove exactly their mass and their m*e^2 of roll inertia",
		problems.is_empty(),
		"%.3f g removed, roll %s -> %s (expected %s)" % [
			(solid.total_mass_kg - drilled.total_mass_kg) * 1000.0,
			solid.roll_inertia_kg_m2(), drilled.roll_inertia_kg_m2(), expected_roll]
			if problems.is_empty() else "; ".join(problems))


static func _test_parallel_axis_computed_two_ways(materials: FrameMaterials) -> TestResult:
	# The same aircraft, twice: once by handing the plate and an off-centre lump to compute()
	# together, and once by asking compute() for each ALONE and shifting the two answers onto the
	# combined CG by hand. The theorem is what makes those equal, so the two disagreeing means the
	# tensor shift is wrong — and it is a real check rather than a restatement, because the hand
	# path never touches AirframeProperties' shifting code.
	var plate := AirframeDocument.make_plate(
		_rectangle(120.0, 90.0), [], 2.5, 0.0, AirframeDocument.ROLE_BOTTOM)
	var lump := PartMass.new(0.180, Vector3(0.030, 0.020, -0.045), Vector3(1e-5, 2e-5, 3e-5), "pack")

	var together := AirframeProperties.compute(_document_of([plate]), materials, [lump])
	var plate_only := AirframeProperties.compute(_document_of([plate]), materials)

	# The combined CG, by hand.
	var m1 := plate_only.total_mass_kg
	var m2 := lump.mass_kg
	var c1 := plate_only.cg_m
	var c2 := lump.position_m
	var cg := (c1 * m1 + c2 * m2) / (m1 + m2)

	var d1 := c1 - cg
	var d2 := c2 - cg
	var expected_roll := plate_only.i_zz + m1 * (d1.x * d1.x + d1.y * d1.y) \
		+ lump.local_inertia_diag.z + m2 * (d2.x * d2.x + d2.y * d2.y)
	var expected_pitch := plate_only.i_xx + m1 * (d1.y * d1.y + d1.z * d1.z) \
		+ lump.local_inertia_diag.x + m2 * (d2.y * d2.y + d2.z * d2.z)
	var expected_xz := plate_only.i_xz - m1 * d1.x * d1.z - m2 * d2.x * d2.z

	var problems: Array = []
	# 1e-9 metres would be below the floor: `cg_m` is a Vector3 and therefore single precision, so
	# a 24 mm coordinate carries ~3e-9 m of representation error before anything is compared. The
	# tolerance is that floor, not a number chosen to make this go green — the double-precision
	# components (i_xx…) are compared at 1e-7 below, where the floor does not apply.
	if (together.cg_m - cg).length() > 1e-7:
		problems.append("CG %s vs hand %s" % [together.cg_m, cg])
	if _relative(together.roll_inertia_kg_m2(), expected_roll) > 1e-7:
		problems.append("roll %s vs hand %s" % [together.roll_inertia_kg_m2(), expected_roll])
	if _relative(together.pitch_inertia_kg_m2(), expected_pitch) > 1e-7:
		problems.append("pitch %s vs hand %s" % [together.pitch_inertia_kg_m2(), expected_pitch])
	if _relative(together.i_xz, expected_xz) > 1e-7:
		problems.append("i_xz %s vs hand %s" % [together.i_xz, expected_xz])
	# And the off-centre lump must actually have produced a product of inertia, or the check above
	# is comparing two zeros. This is the line that stops the whole test being vacuous.
	if absf(together.i_xz) < 1e-9:
		problems.append("fixture produced no product of inertia to check")

	return TestResult.new(
		"an off-centre mass obeys the tensor parallel-axis theorem, checked two ways",
		problems.is_empty(),
		"roll %s, pitch %s, i_xz %s all match the hand shift" % [
			together.roll_inertia_kg_m2(), together.pitch_inertia_kg_m2(), together.i_xz]
			if problems.is_empty() else "; ".join(problems))


static func _test_the_tensor_does_not_care_where_the_origin_is(materials: FrameMaterials) -> TestResult:
	# Translate the entire document — plates, holes and z — a long way from the origin. The CG must
	# move by exactly that, and the tensor ABOUT THE CG must not move at all. A shift referenced to
	# the origin instead of the CG passes at the origin and fails here, which is the mistake
	# motor_layout.gd's header describes from the torque side.
	var here := _document_of([
		AirframeDocument.make_plate(_rectangle(140.0, 70.0),
			[_rectangular_hole(15.0, Vector2(30.0, 10.0))], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM),
		AirframeDocument.make_plate(_rectangle(60.0, 60.0), [], 2.0, 25.0, AirframeDocument.ROLE_TOP),
	])
	var offset := Vector2(123.0, -47.0)   # §3.1's own catastrophic-cancellation fixture, in mm
	var lift := 40.0
	var there := _document_of([
		AirframeDocument.make_plate(_rectangle(140.0, 70.0, offset),
			[_rectangular_hole(15.0, offset + Vector2(30.0, 10.0))], 2.0, lift,
			AirframeDocument.ROLE_BOTTOM),
		AirframeDocument.make_plate(_rectangle(60.0, 60.0, offset), [], 2.0, 25.0 + lift,
			AirframeDocument.ROLE_TOP),
	])

	var a := AirframeProperties.compute(here, materials)
	var b := AirframeProperties.compute(there, materials)
	var expected_cg := a.cg_m + Vector3(offset.x, lift, offset.y) / 1000.0

	# Each component is compared against the TENSOR'S SCALE, not against itself. That is not a
	# softened bound, it is the only metric that means anything for `i_xz`: on this fixture i_xz is
	# 2.1e-7 against a 6.7e-5 diagonal, three orders down, because it is a difference of terms that
	# very nearly cancel. Its own-relative error is 4.6e-5 while its ABSOLUTE error is 1e-11, and a
	# tensor whose largest entry is wrong by 1e-11 is not a tensor with a problem. Dividing by the
	# scale says exactly that, and still fails the moment a shift is genuinely mis-applied, because
	# a mis-applied shift moves a term by a fraction of the SCALE and not by a fraction of a
	# near-zero. (Measured while writing this: the three diagonal terms come back at 4e-7 of scale,
	# comfortably better than §3.1's stated ~7e-6 floor; the product term is the one that needs the
	# distinction.)
	var scale := maxf(maxf(absf(a.i_xx), absf(a.i_yy)), absf(a.i_zz))
	var worst := 0.0
	for pair in [[a.i_xx, b.i_xx], [a.i_yy, b.i_yy], [a.i_zz, b.i_zz], [a.i_xz, b.i_xz]]:
		worst = maxf(worst, absf(pair[1] - pair[0]) / scale)

	var problems: Array = []
	# Single-precision Vector3 floor again, and this fixture sits at 123 mm, so it is larger here.
	if (b.cg_m - expected_cg).length() > 1e-6:
		problems.append("CG %s, expected %s" % [b.cg_m, expected_cg])
	if worst > 1e-5:
		problems.append("tensor moved by %s of its own scale" % worst)
	if absf(a.i_xz) < 1e-12:
		problems.append("fixture has no product of inertia, so the check is vacuous")

	return TestResult.new(
		"translating the whole document moves the CG and leaves the CG-referenced tensor alone",
		problems.is_empty(),
		"moved by (%.0f, %.0f, %.0f) mm; tensor changed by %s of its scale (i_xz alone %s of itself)" % [
			offset.x, lift, offset.y, worst, absf(b.i_xz - a.i_xz) / absf(a.i_xz)] if problems.is_empty() else "; ".join(problems))


static func _test_cg_rises_with_a_raised_plate(materials: FrameMaterials) -> TestResult:
	# §3.3's point, in miniature: a mass at a height has a height. The existing model cannot express
	# this at all — every frame mass in it sits at the origin — and it is the term that becomes
	# §4.6's CG-above-thrust-plane.
	var low := _document_of([
		AirframeDocument.make_plate(_rectangle(80.0, 80.0), [], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM),
		AirframeDocument.make_plate(_rectangle(80.0, 80.0), [], 2.0, 0.0, AirframeDocument.ROLE_TOP),
	])
	var tall := _document_of([
		AirframeDocument.make_plate(_rectangle(80.0, 80.0), [], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM),
		AirframeDocument.make_plate(_rectangle(80.0, 80.0), [], 2.0, 30.0, AirframeDocument.ROLE_TOP),
	])

	var a := AirframeProperties.compute(low, materials)
	var b := AirframeProperties.compute(tall, materials)

	# Two identical plates, one lifted 30 mm: the CG is at half of that, and both plates gain
	# m·(15 mm)² of roll and pitch. Exact, and neither term is a fitted one.
	var half := 0.015
	var expected_gain := a.total_mass_kg * half * half
	var problems: Array = []
	if _relative(b.cg_m.y, half) > 1e-6:   # single-precision Vector3 floor
		problems.append("CG height %.6f m, expected %.6f" % [b.cg_m.y, half])
	if _relative(b.roll_inertia_kg_m2() - a.roll_inertia_kg_m2(), expected_gain) > 1e-6:
		problems.append("roll gained %s, expected %s" % [
			b.roll_inertia_kg_m2() - a.roll_inertia_kg_m2(), expected_gain])
	# Yaw is about the vertical axis, so raising a plate along it changes nothing.
	if _relative(b.yaw_inertia_kg_m2(), a.yaw_inertia_kg_m2()) > 1e-9:
		problems.append("yaw changed when a plate was raised along the yaw axis")
	if absf(b.total_mass_kg - a.total_mass_kg) > 1e-12:
		problems.append("raising a plate changed the mass")

	return TestResult.new(
		"a raised plate lifts the CG and adds m*d^2 to roll and pitch, but not to yaw",
		problems.is_empty(),
		"CG rose to %.1f mm; roll +%s kg m^2, yaw unchanged" % [
			b.cg_m.y * 1000.0, b.roll_inertia_kg_m2() - a.roll_inertia_kg_m2()]
			if problems.is_empty() else "; ".join(problems))


static func _test_preset_masses_land_within_ten_percent(
	catalog: PartsCatalog, materials: FrameMaterials
) -> TestResult:
	# §3.2'S FALSIFIABLE CLAIM, run as a falsification. The preset generator reads arm_mm,
	# motor_mount, stack_mount and the material string, and never reads mass_g, so this comparison
	# is against a number the pipeline has not seen.
	#
	# WHICH FRAMES THE CLAIM COVERS, decided by §0 and not by the results: "the one thing this
	# shape cannot describe is a 3D-printed part — ducts, camera pods, TPU bumpers". A frame whose
	# published construction is moulded ducts is not a plate assembly and the plate model owes it
	# nothing; its error is reported below and not asserted on. Every frame that IS a plate
	# assembly is held to the ±10%.
	var errors: Array = []
	var failures: Array = []
	var excluded: Array = []
	var asserted := 0

	for frame in catalog.list_category("frame"):
		var doc := AirframeDocument.from_catalog_frame(frame)
		var props := AirframeProperties.compute(doc, materials)
		var published := float(frame["mass_g"])
		var error := (props.total_mass_g() - published) / published
		var description := str(frame.get("catalog", {}).get("material", ""))
		var is_plate_assembly := not (description.to_lower().contains("duct")
			or description.to_lower().contains("moulded")
			or description.to_lower().contains("hybrid"))

		errors.append("%s %.0fg->%.0fg %+.0f%%%s" % [
			str(frame["part_id"]).replace("frame_", ""), published, props.total_mass_g(),
			error * 100.0, "" if is_plate_assembly else "*"])
		if not is_plate_assembly:
			excluded.append(str(frame["part_id"]))
			continue
		asserted += 1
		if absf(error) > MASS_TOLERANCE:
			failures.append("%s %+.1f%%" % [str(frame["part_id"]).replace("frame_", ""), error * 100.0])

	# WHY THIS STILL REPORTS RATHER THAN GATES — RE-DECIDED 2026-08-19, AFTER A2b, and written down
	# so nobody "fixes" it by tuning the generator.
	#
	# §3.2's +/-10% claim is about the MASS MODEL: mass = rho*t*A. That claim is gated, exactly, by
	# _test_a_flat_plate_matches_the_box_formula and by _test_against_the_existing_mass_model. It is
	# not what this test measures.
	#
	# A2b removed the excuse that was standing here: frames.json NOW carries plate_thickness_mm and
	# arm_thickness_mm, sourced from vendor spec sheets and product surveys, for every frame that is
	# a plate assembly at all. The generator reads them. THE GATE STILL CANNOT BE TURNED ON, and the
	# tolerance does not move to meet it (MASS_TOLERANCE stays 0.10). What real geometry bought is a
	# sharper diagnosis, not a pass:
	#
	#   - The three NAMED PRODUCTS are still 29-48% LIGHT, on their own published thicknesses. That
	#     is now a clean result: with the vendor's own numbers in the model, "centre plate + four
	#     arms" cannot reach the vendor's own mass, because side plates, canopies, camera plates and
	#     stack cages are simply not in the topology. The Evoque V2 publishes FIVE plate thicknesses
	#     and this document models two of them.
	#   - The GENERIC frames went the other way and got HEAVIER, not lighter (10" +32%, 3" +29%,
	#     cinelifter +26%). Real arms are thicker than the old 4.5%-of-length assumption, so the
	#     generator's square centre plates and full-length arms now carry more carbon. The remaining
	#     error is AREA, not thickness: four full-length arms overlapping a square centre plate is
	#     more plate than any real frame has, and no thickness figure can fix an outline.
	#
	# So the miss moved from "we do not know the thickness" to "the outline is wrong", which is a
	# statement about A7/A8 (real outlines) rather than about A2b. Trimming the arms or shrinking
	# the plates until the sum lands would be a bound moved to fit its data, which this project does
	# not do. The evidence is printed instead.
	return TestResult.new(
		"FINDING (not a gate): sourced thicknesses do not close the preset mass gap; the outline does",
		true,
		"%d/%d plate frames would pass +/-10%% (%d moulded/ducted excluded by §0, marked *). A2b DONE: thicknesses are now SOURCED, not guessed, and the gap did not close — named products stay light (topology: side/camera/upper plates unmodelled), generics went heavier (real arms are thicker than the old assumption). Remaining error is OUTLINE AREA, not thickness; gate stays off and the tolerance stays at 10%%. OUTSIDE 10%%: %s. ALL: %s" % [
			asserted - failures.size(), asserted, excluded.size(),
			"none" if failures.is_empty() else ", ".join(failures), "; ".join(errors)])


static func _test_against_the_existing_mass_model(
	catalog: PartsCatalog, materials: FrameMaterials
) -> TestResult:
	# The old model against the new one on the reference build — a symmetric X, which is the only
	# aircraft the old model can describe.
	#
	# THE TWO ARE EXPECTED TO DISAGREE ON INERTIA, and §3.3 says why: the old model is one lumped
	# box at the origin, sized by FRAME_PLATE_TO_ARM_RATIO — a ratio chosen so the m·r² looked
	# right, standing in for carbon that is really out at the arm tips. Reporting that disagreement
	# is the point of this test; asserting a size for it would be inventing a bound. What IS
	# asserted are the two things that must hold whatever the distribution turns out to be:
	#
	#   1. MASS IS AN IDENTITY. Swapping the frame lump for the computed geometry changes the
	#      aircraft's mass by exactly the difference between those two frame masses and by nothing
	#      else. Falsifiable to the microgram, and it catches any double count — a plate weighed
	#      twice, hardware counted in both models, an arm dropped.
	#   2. A SYMMETRIC X IS SYMMETRIC. The generated preset has four identical arms on the
	#      diagonals and square centre plates, so its roll and pitch inertias must be EQUAL. The
	#      old model gets this for free (its frame is one cube); the new one gets it only if the
	#      arms, the holes and the mapping are all right together. Note this is the check the
	#      stretched fixture complements: symmetry alone cannot see a transposition, and a
	#      transposition alone cannot break symmetry.
	#
	# The whole-aircraft comparison uses ReferenceBuild's parts as they are, camera and pack
	# included — those make the aircraft fore/aft asymmetric on purpose (LTHL-11), which is why the
	# symmetry assertion is made on the FRAME and not on the assembled build.
	var build := ReferenceBuild.build()
	var old := build.mass_properties

	# The build's parts, minus the frame lump the geometry replaces.
	var others: Array = []
	var frame_lump_kg := 0.0
	for part in build.mass_parts():
		if part.label == "Frame":
			frame_lump_kg = part.mass_kg
			continue
		others.append(part)

	var doc := AirframeDocument.from_catalog_frame(catalog.get_part(ReferenceBuild.FRAME_ID))
	var frame_only := AirframeProperties.compute(doc, materials)
	var whole := AirframeProperties.compute(doc, materials, others)

	var expected_mass := old.total_mass_kg - frame_lump_kg + frame_only.total_mass_kg
	var old_roll: float = old.inertia.z.z

	var problems: Array = []
	if _relative(whole.total_mass_kg, expected_mass) > 1e-9:
		problems.append("mass %.6f kg, expected %.6f" % [whole.total_mass_kg, expected_mass])
	# WHY THIS IS 1e-6 AND NOT 1e-9 (changed in A2b, and the reason is not "it started failing").
	# The four arm outlines are the SAME polygon rotated to four azimuths, and every vertex of them
	# passes through points_of()'s PackedVector2Array — single precision, whose floor §3.1 measures
	# at ~1e-7 relative on a vertex. Two rotations of one shape therefore cannot be expected to
	# agree below that floor, so 1e-9 was never a claim about symmetry; it was a claim about which
	# arm width happened to round cleanly, and a sourced 12.0 mm root width rounds differently from
	# the derived 13.2 mm it replaced (the observed disagreement is 1.6e-9, i.e. still a hundredfold
	# INSIDE the precision floor). 1e-6 is one order above the floor and still tight enough to catch
	# a real geometric asymmetry: MUTATION-VERIFIED by stretching the centre plate 0.05% fore-aft,
	# which fires at 5.5e-6. Note what does NOT break it, because it is instructive — lengthening
	# one arm, or the front PAIR, leaves roll and pitch equal, since a 45° arm feeds both axes
	# alike. Only an asymmetry between the u and v directions is one this assertion can see, which
	# is exactly why the stretched fixture above and not this check is the transposition test.
	if _relative(frame_only.roll_inertia_kg_m2(), frame_only.pitch_inertia_kg_m2()) > 1e-6:
		problems.append("the symmetric-X preset is not symmetric: roll %s pitch %s" % [
			frame_only.roll_inertia_kg_m2(), frame_only.pitch_inertia_kg_m2()])
	# And it must not be symmetric by being empty, which is the way this check goes vacuous.
	if frame_only.roll_inertia_kg_m2() <= 0.0:
		problems.append("the preset has no roll inertia at all")
	# EVERY mass-bearing item reached the sum. A whole category quietly dropped — the hardware, say —
	# leaves the mass identity above intact (it is an identity about the swap, not about the total)
	# and the symmetry intact, and would otherwise pass unseen. Counting is the cheap witness.
	var expected_items := doc.plates.size() + doc.hardware.size() + doc.pads.size() + doc.straps.size()
	if frame_only.contributions.size() != expected_items:
		problems.append("%d of %d document items reached the mass sum" % [
			frame_only.contributions.size(), expected_items])

	return TestResult.new(
		"the geometry model agrees with MassProperties on mass exactly, and the symmetric-X preset is symmetric",
		problems.is_empty(),
		("frame %.1f g computed vs %.1f g lumped; aircraft %.1f g vs %.1f g. "
			+ "FRAME-ONLY roll/pitch %s (lump gives %s), yaw %s (lump %s). "
			+ "Whole aircraft: roll %s vs old %s (x%.2f), pitch %s vs old %s, yaw %s vs %s (x%.2f); CG y %.2f mm vs %.2f mm") % [
			frame_only.total_mass_g(), frame_lump_kg * 1000.0,
			whole.total_mass_kg * 1000.0, old.total_mass_kg * 1000.0,
			frame_only.roll_inertia_kg_m2(), old_roll, frame_only.yaw_inertia_kg_m2(), old.inertia.y.y,
			whole.roll_inertia_kg_m2(), old_roll, whole.roll_inertia_kg_m2() / old_roll,
			whole.pitch_inertia_kg_m2(), old.inertia.x.x,
			whole.yaw_inertia_kg_m2(), old.inertia.y.y, whole.yaw_inertia_kg_m2() / old.inertia.y.y,
			whole.cg_m.y * 1000.0, old.com_m.y * 1000.0]
			if problems.is_empty() else "; ".join(problems))
