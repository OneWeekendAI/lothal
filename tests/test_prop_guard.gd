class_name TestPropGuard
extends RefCounted
## Prop guards as parts (propulsion.md §6, slice P9). The `kind` discriminator decides whether a
## thrust model applies at all — a bumper claims no thrust change, a duct claims tip-loss
## suppression only — and the bumper's own geometry produces a mass and an inertia bite that a
## real cinewhoop feels harder than a heavy motor does.
##
## Every check below fails without the physics: a stub that returned zero mass would fail the
## arithmetic pin; a stub that returned `1.0` for anything called "guard" would fail the silent
## failure guard; a stub that keyed off mass alone would fail the cinewhoop ratio because that
## finding is R² geometry, not mass; and a clearance that measured from the outer radius rather
## than the inner wall would fail by a factor of three on the reference cinewhoop ring.
##
## §6.1 grants a bumper three claims — mass, inertia AND clearance — and the clearance block is
## also where the discriminator stops being an honour system: a ring's own gap, measured in tip
## chords, says what it is, and `kind_disagrees` fires in both of the directions §6.1 names.


static func run() -> Array:
	var results: Array = []

	# -----------------------------------------------------------------------
	# The kind discriminator — §6.1's "before any geometry"
	# -----------------------------------------------------------------------
	# Unknown kind refuses. Missing kind field refuses. A guard with no kind is a guard whose
	# thrust model has not been decided, and the physics must not pick one for it.
	var no_kind := PropGuard.compute({"outer_radius_mm": 40.0, "wall_mm": 2.0,
			"height_mm": 8.0, "density_kg_m3": 1150.0})
	results.append(TestResult.new(
		"a guard with no kind field refuses — tier reports unknown_kind, all figures zero",
		no_kind["tier"] == "unknown_kind" and float(no_kind["mass_kg"]) == 0.0
			and float(no_kind["roll_inertia_contribution_kg_m2"]) == 0.0,
		"tier %s, mass %.4f g, I %.6f kg·m²" % [no_kind["tier"],
			float(no_kind["mass_kg"]) * 1000.0, float(no_kind["roll_inertia_contribution_kg_m2"])]))

	var wrong_kind := PropGuard.compute({"kind": "cage", "outer_radius_mm": 40.0,
			"wall_mm": 2.0, "height_mm": 8.0, "density_kg_m3": 1150.0})
	results.append(TestResult.new(
		"a guard with an unrecognised kind refuses — no fallback to a class-typical model",
		wrong_kind["tier"] == "unknown_kind" and float(wrong_kind["mass_kg"]) == 0.0,
		"tier %s (kind 'cage')" % wrong_kind["tier"]))

	# -----------------------------------------------------------------------
	# Bumper mass — the airframe.md §3.1 kernel form
	# -----------------------------------------------------------------------
	# m = rho · V(outline, height, wall). For a circular ring V = 2π · R_mean · height · wall,
	# with R_mean = outer - wall/2 so a thick wall does not over-count the corner. Pinned by
	# hand: outer = 40 mm, wall = 2 mm, height = 8 mm, ρ = 1150 kg/m³ (nylon), R_mean = 39 mm.
	#   V = 2π · 0.039 · 0.008 · 0.002 = 3.9207e-6 m³
	#   m = 1150 · 3.9207e-6 = 4.5088e-3 kg = 4.5088 g
	# Tolerance is five parts in a hundred thousand — the whole computation is elementary and
	# nothing here is fitted, so a loose band would just absorb an edit that changed physics.
	var ring_spec := {"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 40.0,
			"wall_mm": 2.0, "height_mm": 8.0, "density_kg_m3": 1150.0}
	var ring := PropGuard.compute(ring_spec)
	var mass_predicted := 1150.0 * TAU * 0.039 * 0.008 * 0.002
	results.append(TestResult.new(
		"bumper mass is rho · 2π · R_mean · height · wall — pinned to the arithmetic",
		absf(float(ring["mass_kg"]) - mass_predicted) / mass_predicted < 1.0e-5,
		"%.5f g against %.5f g predicted (rho=1150, R_mean=39 mm, h=8 mm, w=2 mm)"
			% [float(ring["mass_kg"]) * 1000.0, mass_predicted * 1000.0]))

	# Mass scales linearly with density, height and wall thickness on independent axes so a bug
	# that conflated any two would fail one of them.
	var double_density := PropGuard.mass_kg({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 40.0, "wall_mm": 2.0, "height_mm": 8.0, "density_kg_m3": 2300.0})
	results.append(TestResult.new(
		"doubling density doubles mass",
		absf(double_density / float(ring["mass_kg"]) - 2.0) < 1.0e-9,
		"rho=1150: %.4f g   rho=2300: %.4f g   ratio %.6f"
			% [float(ring["mass_kg"]) * 1000.0, double_density * 1000.0,
				double_density / float(ring["mass_kg"])]))

	var double_height := PropGuard.mass_kg({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 40.0, "wall_mm": 2.0, "height_mm": 16.0, "density_kg_m3": 1150.0})
	results.append(TestResult.new(
		"doubling height doubles mass",
		absf(double_height / float(ring["mass_kg"]) - 2.0) < 1.0e-9,
		"h=8mm: %.4f g   h=16mm: %.4f g   ratio %.6f"
			% [float(ring["mass_kg"]) * 1000.0, double_height * 1000.0,
				double_height / float(ring["mass_kg"])]))

	# -----------------------------------------------------------------------
	# Bumper inertia — §6.2's `I += m · R_guard^2`
	# -----------------------------------------------------------------------
	# R_guard = mount_radius + outer_radius. Without a mount_radius the ring's centre is at the
	# aircraft roll axis and R_guard = outer_radius. Same 4.5088 g ring at R_guard = 40 mm:
	#   I = 4.5088e-3 · (0.040)² = 7.2141e-6 kg·m²
	var i_predicted := mass_predicted * 0.040 * 0.040
	results.append(TestResult.new(
		"roll inertia contribution is m · R_guard² — pinned to the arithmetic",
		absf(float(ring["roll_inertia_contribution_kg_m2"]) - i_predicted) / i_predicted < 1.0e-5,
		"%.6f kg·m² against %.6f predicted (m=4.5088 g, R_guard=40 mm)"
			% [float(ring["roll_inertia_contribution_kg_m2"]), i_predicted]))

	# Doubling R_guard quadruples the inertia contribution at fixed mass — the R² law that
	# makes this slice worth building.
	var mount_80 := PropGuard.compute({"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 40.0,
			"wall_mm": 2.0, "height_mm": 8.0, "density_kg_m3": 1150.0, "mount_radius_mm": 40.0})
	# mount + outer = 80 mm, four times the R² at the same mass.
	results.append(TestResult.new(
		"doubling R_guard (via mount_radius) quadruples the inertia contribution at fixed mass",
		absf(float(mount_80["roll_inertia_contribution_kg_m2"])
				/ float(ring["roll_inertia_contribution_kg_m2"]) - 4.0) < 1.0e-9,
		"R_guard=40mm: %.6f   R_guard=80mm: %.6f   ratio %.6f"
			% [float(ring["roll_inertia_contribution_kg_m2"]),
				float(mount_80["roll_inertia_contribution_kg_m2"]),
				float(mount_80["roll_inertia_contribution_kg_m2"])
					/ float(ring["roll_inertia_contribution_kg_m2"])]))

	# -----------------------------------------------------------------------
	# The finding — a guard beats a motor on a real cinewhoop
	# -----------------------------------------------------------------------
	# propulsion.md §6.2: "a 12 g guard ring can cost more roll inertia than a 32 g motor.
	# That is an arithmetic claim this model can make and should, because it is exactly the
	# sort of thing that surprises people, and it is the answer to why does my cinewhoop feel
	# so lazy."
	#
	# The reference cinewhoop: a 5" Cinewhoop from data/parts/frames.json — arm_mm = 96 mm.
	# A representative moulded ABS/nylon guard hoop surrounds each 5" propeller (tip radius
	# 63.5 mm). Its geometry: outer_radius 68 mm, wall 3.0 mm, height 12 mm — one of two
	# published cinewhoop ring shapes a bench-scale caliper reading would land on. Density
	# 1050 kg/m³ (ABS).
	#
	# Its `kind` is DUCT, and that is not cosmetic. The inner wall sits at 68 - 3 = 65 mm
	# against a 63.5 mm tip: a 1.5 mm annular gap, a fifth of a tip chord. A ring that close is
	# a shroud, and calling it a bumper is precisely §6.1's second silent failure — "a
	# cinewhoop treated as a bumper reports a hover throttle that will not fly the aircraft".
	# The clearance checks below assert the geometry, and `kind_disagrees` fires if this spec
	# is ever relabelled. Mass and inertia do not read `kind`, so the finding is unchanged.
	#
	#   V   = 2π · (0.068 - 0.0015) · 0.012 · 0.003 = 1.5029e-5 m³
	#   m   = 1050 · 1.5029e-5           = 15.78 g
	#   R_guard = 96 + 68                = 164 mm
	#   I   = 0.01578 · (0.164)²         = 4.244e-4 kg·m²
	#
	# The motor is a real catalog entry (data/parts/motors.json) sized for the class: a
	# 32 g 2306-class motor at the same arm.
	#   I_motor = 0.032 · (0.096)²        = 2.949e-4 kg·m²
	#
	# Ratio: 4.244e-4 / 2.949e-4 ≈ 1.44. The guard is 51 % LIGHTER (16 g against 32 g) and
	# still contributes about 44 % more roll inertia — because R_guard/R_motor = 1.71 and
	# inertia goes as R².
	var cinewhoop_spec := {
		"kind": PropGuard.KIND_DUCT,
		"outer_radius_mm": 68.0,
		"wall_mm": 3.0,
		"height_mm": 12.0,
		"density_kg_m3": 1050.0,
		"mount_radius_mm": 96.0,
	}
	var cinewhoop_guard := PropGuard.compute(cinewhoop_spec)
	var motor_mass_kg := 0.032
	var motor_arm_m := 0.096
	var motor_inertia := motor_mass_kg * motor_arm_m * motor_arm_m
	var guard_inertia := float(cinewhoop_guard["roll_inertia_contribution_kg_m2"])
	results.append(TestResult.new(
		"a 16 g guard on a 5in cinewhoop out-contributes a 32 g motor to roll inertia — the finding",
		guard_inertia > motor_inertia,
		"guard %.3f g at R=164 mm: I=%.6f kg·m²   motor 32.0 g at R=96 mm: I=%.6f kg·m²   ratio %.3f"
			% [float(cinewhoop_guard["mass_kg"]) * 1000.0, guard_inertia,
				motor_inertia, guard_inertia / motor_inertia]))

	# The finding pinned to its published band. The doc's example (12 g / 32 g) sits at ratio
	# 1.04; this file's slightly heavier ring is 1.44. Both illustrate the R² effect and
	# neither is fitted — a band from 1.0 (the doc's floor) up to 2.0 keeps the assertion
	# meaningful without forcing the number.
	results.append(TestResult.new(
		"the cinewhoop ratio lies in [1.0, 2.0] — the band §6.2's example places it in",
		guard_inertia / motor_inertia >= 1.0 and guard_inertia / motor_inertia <= 2.0,
		"ratio %.3f (guard 15.78 g at R_guard=164 mm, motor 32 g at R_motor=96 mm)"
			% (guard_inertia / motor_inertia)))

	# -----------------------------------------------------------------------
	# Blade tip clearance — §6.2's exact check, and §6.1's mislabelling made visible
	# -----------------------------------------------------------------------
	# clearance = (outer - wall) - prop_tip_radius. Pinned by hand on the cinewhoop ring above:
	# (68 - 3) - 63.5 = 1.5 mm. Exact arithmetic, nothing fitted — §8 files tip clearance under
	# Exact, and a band here would absorb the very edit it exists to catch.
	var tip_r_5in := 63.5
	var whoop_clearance := PropGuard.tip_clearance_mm(cinewhoop_spec, tip_r_5in)
	results.append(TestResult.new(
		"tip clearance is (outer - wall) - tip_radius — pinned to 1.5 mm on the cinewhoop ring",
		absf(whoop_clearance - 1.5) < 1.0e-9,
		"outer 68 mm, wall 3 mm, inner 65 mm against a 63.5 mm tip: %.4f mm" % whoop_clearance))

	# Clearance reads the WALL, not just the outer radius. A model that returned
	# outer - tip_radius would answer 4.5 mm here and be wrong by three times the real gap —
	# the exact slip this test was written after finding.
	results.append(TestResult.new(
		"clearance measures from the INNER wall — a model ignoring wall_mm would say 4.5 mm",
		absf(whoop_clearance - (68.0 - 63.5)) > 2.9,
		"inner-wall answer %.3f mm against the outer-radius answer 4.500 mm" % whoop_clearance))

	# A negative clearance is the ANSWER, not a refusal: the ring passes through the disc.
	var interfering := {"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 62.0,
			"wall_mm": 3.0, "height_mm": 12.0, "density_kg_m3": 1050.0}
	var interference := PropGuard.tip_clearance_mm(interfering, tip_r_5in)
	results.append(TestResult.new(
		"a guard whose inner wall is inside the disc reports NEGATIVE clearance, not zero and not a refusal",
		interference < 0.0 and absf(interference - (59.0 - 63.5)) < 1.0e-9,
		"inner 59 mm against a 63.5 mm tip: %.4f mm (must be -4.5)" % interference))

	# Refusals return NAN, never 0.0 — because 0.0 is a real clearance (a shroud flush with
	# the tip) and must not double as the "cannot answer" value.
	var flush := PropGuard.tip_clearance_mm({"kind": PropGuard.KIND_DUCT,
			"outer_radius_mm": 66.5, "wall_mm": 3.0, "height_mm": 12.0,
			"density_kg_m3": 1050.0}, tip_r_5in)
	results.append(TestResult.new(
		"a shroud flush with the tip reports clearance exactly 0.0 — a real answer, not a refusal",
		flush == 0.0 and not is_nan(flush),
		"inner 63.5 mm against a 63.5 mm tip: %.6f mm" % flush))

	var no_prop := PropGuard.tip_clearance_mm(cinewhoop_spec, 0.0)
	var bad_spec_clearance := PropGuard.tip_clearance_mm({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 40.0, "wall_mm": -1.0, "height_mm": 8.0,
			"density_kg_m3": 1150.0}, tip_r_5in)
	results.append(TestResult.new(
		"clearance against no prop, or on a spec compute() refuses, is NAN rather than 0.0",
		is_nan(no_prop) and is_nan(bad_spec_clearance),
		"tip_radius=0: %s   negative wall: %s" % [no_prop, bad_spec_clearance]))

	# The mislabelling detector. The split sits at gap = one tip chord — the point where
	# tip_loss_closure passes 1/2 — so it introduces no constant of its own. The cinewhoop ring
	# at 1.5 mm against an 8 mm tip chord is geometrically a duct, and IS declared one.
	var whoop_check := PropGuard.clearance_check(cinewhoop_spec, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"the cinewhoop ring is geometrically a duct and declares itself one — no disagreement",
		whoop_check["geometric_kind"] == PropGuard.KIND_DUCT
			and whoop_check["kind_disagrees"] == false,
		"clearance %.2f mm = %.3f tip chords -> geometric %s, declared %s, disagrees %s"
			% [float(whoop_check["clearance_mm"]), float(whoop_check["gap_ratio"]),
				whoop_check["geometric_kind"], whoop_check["declared_kind"],
				whoop_check["kind_disagrees"]]))

	# The same ring relabelled is §6.1's second silent failure, and it FIRES. This is the check
	# that the showcase spec above cannot be quietly switched back to `bumper`.
	var mislabelled := cinewhoop_spec.duplicate()
	mislabelled["kind"] = PropGuard.KIND_BUMPER
	var mislabel_check := PropGuard.clearance_check(mislabelled, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"a 1.5 mm shroud declared a bumper is flagged — §6.1's cinewhoop-as-bumper, made visible",
		mislabel_check["kind_disagrees"] == true
			and mislabel_check["geometric_kind"] == PropGuard.KIND_DUCT,
		"declared bumper at %.3f tip chords of gap -> geometric %s, disagrees %s"
			% [float(mislabel_check["gap_ratio"]), mislabel_check["geometric_kind"],
				mislabel_check["kind_disagrees"]]))

	# And it fires in the other direction too — §6.1's "either direction". A wide open ring
	# declared a duct is a free lunch waiting to happen.
	var wide_ring_as_duct := {"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 90.0,
			"wall_mm": 3.0, "height_mm": 8.0, "density_kg_m3": 1050.0}
	var wide_check := PropGuard.clearance_check(wide_ring_as_duct, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"a 23.5 mm open ring declared a duct is flagged too — the free lunch, in the other direction",
		wide_check["kind_disagrees"] == true
			and wide_check["geometric_kind"] == PropGuard.KIND_BUMPER,
		"declared duct at %.3f tip chords of gap -> geometric %s, disagrees %s"
			% [float(wide_check["gap_ratio"]), wide_check["geometric_kind"],
				wide_check["kind_disagrees"]]))

	# A genuine bumper, well clear, agrees with its own label — so the detector is not a
	# stub that always says "disagrees".
	var honest_bumper := PropGuard.clearance_check({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 90.0, "wall_mm": 3.0, "height_mm": 8.0,
			"density_kg_m3": 1050.0}, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"a genuinely open bumper agrees with its label — the detector is not stuck at 'disagrees'",
		honest_bumper["kind_disagrees"] == false
			and honest_bumper["geometric_kind"] == PropGuard.KIND_BUMPER,
		"declared bumper at %.3f tip chords of gap -> geometric %s, disagrees %s"
			% [float(honest_bumper["gap_ratio"]), honest_bumper["geometric_kind"],
				honest_bumper["kind_disagrees"]]))

	# Interference disagrees with EVERY declared kind — no guard should intersect its own disc.
	var interference_check := PropGuard.clearance_check(interfering, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"a guard intersecting its own disc classifies as interference and disagrees with any kind",
		interference_check["geometric_kind"] == "interference"
			and interference_check["kind_disagrees"] == true,
		"clearance %.2f mm -> geometric %s, disagrees %s"
			% [float(interference_check["clearance_mm"]),
				interference_check["geometric_kind"], interference_check["kind_disagrees"]]))

	# Without a tip chord there is no length scale, so the CLASSIFICATION is withheld while the
	# clearance itself still stands — the same refusal tip_loss_closure makes, and the clearance
	# is pure geometry that needs no scale.
	var no_chord_check := PropGuard.clearance_check(cinewhoop_spec, tip_r_5in, 0.0)
	results.append(TestResult.new(
		"with no tip chord the kind classification is withheld, but the exact clearance still stands",
		no_chord_check["geometric_kind"] == "unknown"
			and no_chord_check["kind_disagrees"] == false
			and absf(float(no_chord_check["clearance_mm"]) - 1.5) < 1.0e-9,
		"chord=0: geometric %s, disagrees %s, clearance %.4f mm"
			% [no_chord_check["geometric_kind"], no_chord_check["kind_disagrees"],
				float(no_chord_check["clearance_mm"])]))

	# The classification split is the closure form's own half-way point and not a new constant:
	# at gap exactly equal to the tip chord, tip_loss_closure is exactly 1/2.
	var at_split := {"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 74.5, "wall_mm": 3.0,
			"height_mm": 12.0, "density_kg_m3": 1050.0, "tip_gap_mm": 8.0}
	var split_check := PropGuard.clearance_check(at_split, tip_r_5in, 8.0)
	results.append(TestResult.new(
		"the bumper/duct split sits where tip_loss_closure = 1/2 exactly — no threshold of its own",
		absf(float(split_check["gap_ratio"]) - 1.0) < 1.0e-9
			and PropGuard.tip_loss_closure(at_split, 8.0) == 0.5,
		"gap %.3f mm = %.4f tip chords, closure there = %.6f"
			% [float(split_check["clearance_mm"]), float(split_check["gap_ratio"]),
				PropGuard.tip_loss_closure(at_split, 8.0)]))

	# -----------------------------------------------------------------------
	# The silent-failure guard — §6.1's real error, tested at the point it matters
	# -----------------------------------------------------------------------
	# A bumper claims no thrust change EVEN when the spec is shaped like a duct's. This is the
	# check that fails on a stub that keyed off `tip_gap_mm` alone: a mislabelled bumper would
	# quietly claim duct thrust augmentation, and §6.1's "getting this backwards is a real
	# error" says a test must exist that fails when it does.
	var bumper_shaped_like_duct := {
		"kind": PropGuard.KIND_BUMPER,
		"outer_radius_mm": 32.0, "wall_mm": 2.0, "height_mm": 8.0,
		"density_kg_m3": 1150.0, "tip_gap_mm": 0.5,
	}
	var bumper_closure := PropGuard.tip_loss_closure(bumper_shaped_like_duct, 8.0)
	results.append(TestResult.new(
		"a bumper carrying a tip_gap_mm spec still returns closure 0.0 — the silent failure §6.1 exists to prevent",
		bumper_closure == 0.0,
		"kind=bumper, tip_gap_mm=0.5, chord=8 mm: closure = %.6f (must be exactly 0.0)"
			% bumper_closure))

	# And its String claim: a bumper's thrust change is "unchanged", full stop. A panel legend
	# reads this rather than a number, so the honesty tier survives §7's overlays.
	results.append(TestResult.new(
		"bumper.thrust_change_claim == 'unchanged' — the hard NO §8 requires",
		PropGuard.thrust_change_claim(bumper_shaped_like_duct) == "unchanged",
		"claim: %s" % PropGuard.thrust_change_claim(bumper_shaped_like_duct)))

	# -----------------------------------------------------------------------
	# Duct — the tip-loss closure fraction, §6.3
	# -----------------------------------------------------------------------
	# closure(gap=0) = 1 exactly. The shroud is flush with the tip; the leak is fully closed.
	var duct_flush := {"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 64.0,
			"wall_mm": 3.0, "height_mm": 20.0, "density_kg_m3": 1150.0, "tip_gap_mm": 0.0}
	var closure_flush := PropGuard.tip_loss_closure(duct_flush, 8.0)
	results.append(TestResult.new(
		"duct with tip_gap = 0 gives closure = 1 exactly — F → 1, the leak fully closes",
		closure_flush == 1.0,
		"gap=0 mm, chord=8 mm: closure = %.6f (must be exactly 1.0)" % closure_flush))

	# closure → 0 as gap → ∞. A duct with a large gap is a bumper in disguise, and the
	# augmentation vanishes rather than saturating on a constant.
	var duct_huge := {"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 64.0,
			"wall_mm": 3.0, "height_mm": 20.0, "density_kg_m3": 1150.0, "tip_gap_mm": 1000.0}
	var closure_huge := PropGuard.tip_loss_closure(duct_huge, 8.0)
	results.append(TestResult.new(
		"duct with an enormous tip gap gives closure ≈ 0 — the shroud that isn't there",
		closure_huge < 0.01 and closure_huge > 0.0,
		"gap=1000 mm, chord=8 mm: closure = %.6f" % closure_huge))

	# Monotone in gap at fixed chord, on independent points so a non-monotone edit fails somewhere.
	var monotone := true
	var prev := 2.0  # any value > 1 works as the initial sentinel
	for gap_mm in [0.0, 0.5, 1.0, 2.0, 4.0, 8.0]:
		var spec := {"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 64.0,
				"wall_mm": 3.0, "height_mm": 20.0, "density_kg_m3": 1150.0,
				"tip_gap_mm": gap_mm}
		var c := PropGuard.tip_loss_closure(spec, 8.0)
		if c > prev:
			monotone = false
			break
		prev = c
	results.append(TestResult.new(
		"duct closure falls monotonically as tip_gap grows — the physics's direction",
		monotone,
		"scanned gap ∈ {0, 0.5, 1, 2, 4, 8} mm at chord 8 mm — %s"
			% ("monotone" if monotone else "REVERSED at some step")))

	# The rational form pinned to arithmetic. gap = 1 mm, chord = 8 mm → 1/(1 + 1/8) = 8/9.
	var closure_pin := PropGuard.tip_loss_closure({"kind": PropGuard.KIND_DUCT,
			"outer_radius_mm": 64.0, "wall_mm": 3.0, "height_mm": 20.0,
			"density_kg_m3": 1150.0, "tip_gap_mm": 1.0}, 8.0)
	results.append(TestResult.new(
		"duct closure is 1/(1 + gap/chord) — pinned at gap=1 mm, chord=8 mm to 8/9",
		absf(closure_pin - 8.0 / 9.0) < 1.0e-12,
		"closure = %.9f against 8/9 = %.9f" % [closure_pin, 8.0 / 9.0]))

	# -----------------------------------------------------------------------
	# Duct refusals — §6.3's "not fitted against the one build we happen to check"
	# -----------------------------------------------------------------------
	# Missing tip_gap: closure = 0. No spec, no claim.
	var duct_no_gap := PropGuard.tip_loss_closure({"kind": PropGuard.KIND_DUCT,
			"outer_radius_mm": 64.0, "wall_mm": 3.0, "height_mm": 20.0,
			"density_kg_m3": 1150.0}, 8.0)
	results.append(TestResult.new(
		"duct with no tip_gap_mm spec returns closure 0.0 — no claim without a measured gap",
		duct_no_gap == 0.0,
		"missing tip_gap_mm: closure = %.6f (must be 0.0)" % duct_no_gap))

	# Missing/non-positive chord_at_tip: closure = 0. The length scale must come from the
	# physics, not from a constant in this file.
	var duct_no_chord := PropGuard.tip_loss_closure({"kind": PropGuard.KIND_DUCT,
			"outer_radius_mm": 64.0, "wall_mm": 3.0, "height_mm": 20.0,
			"density_kg_m3": 1150.0, "tip_gap_mm": 1.0}, 0.0)
	results.append(TestResult.new(
		"duct with chord_at_tip = 0 returns closure 0.0 — no constant length scale, per §0",
		duct_no_chord == 0.0,
		"chord=0: closure = %.6f (must be 0.0)" % duct_no_chord))

	# Duct's thrust-change claim is "characteristic". §8: no error bar, ever, until something
	# is measured — and a panel legend reads THIS instead of a number the model cannot back.
	results.append(TestResult.new(
		"duct.thrust_change_claim == 'characteristic' — §8's honesty tier",
		PropGuard.thrust_change_claim({"kind": PropGuard.KIND_DUCT}) == "characteristic",
		"claim: %s" % PropGuard.thrust_change_claim({"kind": PropGuard.KIND_DUCT})))

	# -----------------------------------------------------------------------
	# Geometry refusals — the SoftMount posture, translated
	# -----------------------------------------------------------------------
	# Non-positive geometry: refuse rather than silently return zero-through-arithmetic. A
	# corrupt catalog row (wall_mm = -1) would otherwise produce a NEGATIVE mass and a green
	# test.
	var bad_wall := PropGuard.compute({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 40.0, "wall_mm": -1.0, "height_mm": 8.0, "density_kg_m3": 1150.0})
	results.append(TestResult.new(
		"a negative wall_mm refuses via insufficient_data, not via a negative mass",
		String(bad_wall["tier"]).begins_with("insufficient_data")
			and float(bad_wall["mass_kg"]) == 0.0,
		"tier %s, mass %.4f g" % [bad_wall["tier"], float(bad_wall["mass_kg"]) * 1000.0]))

	# A wall thicker than the ring collapses the mean radius — refuse rather than compute a
	# negative circumference.
	var over_wall := PropGuard.compute({"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 5.0, "wall_mm": 12.0, "height_mm": 8.0, "density_kg_m3": 1150.0})
	results.append(TestResult.new(
		"a wall thicker than the ring's outer radius refuses — no negative circumference",
		String(over_wall["tier"]).begins_with("insufficient_data"),
		"tier %s (outer=5 mm, wall=12 mm)" % over_wall["tier"]))

	return results
