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

	# -----------------------------------------------------------------------
	# P10a — as_part_mass, the AirframeProperties wiring
	# -----------------------------------------------------------------------
	# plans/2026-08-26-propulsion-room-design.md §3.3–§3.5: the guard enters the aircraft's
	# mass tensor as a PartMass at the MOTOR'S plan position, with Vector3.ZERO for its local
	# inertia diagonal — so the R² roll-inertia bite arrives via parallel-axis in
	# AirframeProperties exactly once. The four checks below assert both halves of that,
	# because the alternative — handing the scalar `roll_inertia_contribution_kg_m2` to the
	# local diagonal — would double-count on any build where a guard sits at the arm tip, and
	# the doubling would be a silent finding-shaped bug: every mass number correct, every
	# roll-inertia number wrong by 2x.
	var motor_pos := Vector3(0.096, 0.0, 0.0)   # a 5" arm's tip in the airframe frame
	var pm := PropGuard.as_part_mass({
			"kind": PropGuard.KIND_BUMPER,
			"outer_radius_mm": 68.0, "wall_mm": 3.0, "height_mm": 12.0,
			"density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
		}, motor_pos)
	results.append(TestResult.new(
		"as_part_mass returns a PartMass — not null — for a well-formed bumper spec",
		pm != null,
		"pm is %s" % ("null" if pm == null else "PartMass(mass=%.3f g)" % (pm.mass_kg * 1000.0))))

	results.append(TestResult.new(
		"as_part_mass mass_kg equals PropGuard.mass_kg — the physics is the ONE source",
		absf(pm.mass_kg - PropGuard.mass_kg({
			"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 68.0, "wall_mm": 3.0,
			"height_mm": 12.0, "density_kg_m3": 1050.0, "mount_radius_mm": 96.0})) < 1e-9,
		"as_part_mass=%.9f kg, mass_kg=%.9f kg" % [pm.mass_kg,
			PropGuard.mass_kg({"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 68.0,
				"wall_mm": 3.0, "height_mm": 12.0, "density_kg_m3": 1050.0,
				"mount_radius_mm": 96.0})]))

	# The position is the MOTOR's, to the bit — not the motor's shifted by mount_radius_mm, and
	# not the ring's centroid in world coordinates. A mutation that offset the guard by
	# mount_radius_mm (a length pretending to be a position) fails this check by 96 mm on X.
	results.append(TestResult.new(
		"as_part_mass position is the motor's, exactly — mount_radius_mm is a length, not a position",
		pm.position_m == motor_pos,
		"pm.position=%s, motor_pos=%s" % [pm.position_m, motor_pos]))

	# The load-bearing line, and the reason the P9 row's own paragraph warned about it: the
	# scalar `roll_inertia_contribution_kg_m2` is already m·R_guard² — handing it to the local
	# diagonal would let parallel-axis in AirframeProperties add ANOTHER m·d² on top. For this
	# ring that scalar is 4.25e-4 kg·m² (m = 15.794 g at R_guard = mount + outer = 164 mm), and
	# this check is deliberately AXIS-BLIND: it demands the whole vector be zero, so a stub that
	# wired the scalar to X (pitch) is caught here even though the roll-inertia check in
	# test_airframe_properties.gd — which reads I_ZZ — would not see it. The consequence half of
	# the pair, where the mutation is inserted and its effect on the tensor asserted, is that
	# file's check 5.
	results.append(TestResult.new(
		"as_part_mass local_inertia_diag is Vector3.ZERO — the R² bite arrives once, via parallel-axis",
		pm.local_inertia_diag == Vector3.ZERO,
		"pm.local_inertia_diag=%s (must be ZERO)" % pm.local_inertia_diag))

	# Refused specs return null rather than a zero-mass PartMass. A zero-mass entry would still
	# appear as "prop_guard: 0.000 g" in the frame bench's contributions list, which is a wrong
	# caption for a real absence. Same posture soft_mount.gd's mount_mass_kg took for bad
	# grommet specs.
	var pm_missing := PropGuard.as_part_mass({}, motor_pos)
	results.append(TestResult.new(
		"as_part_mass returns null for a spec with no kind — no zero-mass caption in the frame bench",
		pm_missing == null,
		"pm_missing is %s" % ("null" if pm_missing == null else "PartMass"))
	)

	var pm_bad_wall := PropGuard.as_part_mass({
			"kind": PropGuard.KIND_BUMPER, "outer_radius_mm": 68.0, "wall_mm": -3.0,
			"height_mm": 12.0, "density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
		}, motor_pos)
	results.append(TestResult.new(
		"as_part_mass returns null for a spec compute() refuses — no fallback to a class-typical part",
		pm_bad_wall == null,
		"pm_bad_wall is %s" % ("null" if pm_bad_wall == null else "PartMass")))

	# Duct kind is admissible too — as_part_mass reads the mass, and mass does not read `kind`.
	# The tip_loss_closure and clearance branches are separate: this helper is exclusively
	# about how much the ring weighs and where it rides.
	var pm_duct := PropGuard.as_part_mass({
			"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 68.0, "wall_mm": 3.0,
			"height_mm": 12.0, "density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
			"tip_gap_mm": 1.5,
		}, motor_pos)
	results.append(TestResult.new(
		"as_part_mass on a duct returns the SAME mass as the equivalent bumper — mass does not read kind",
		pm_duct != null and absf(pm_duct.mass_kg - pm.mass_kg) < 1e-12,
		"duct pm.mass=%.9f, bumper pm.mass=%.9f" % [pm_duct.mass_kg if pm_duct else 0.0, pm.mass_kg]))

	# -----------------------------------------------------------------------
	# [P10b] The Build wiring — a fitted guard reaching mass, thrust, torque and the surface
	# -----------------------------------------------------------------------
	results.append_array(_the_reference_build_fits_no_guard())
	results.append_array(_a_fitted_guard_rides_at_every_motor())
	results.append_array(_a_bumper_moves_mass_and_no_thrust_number())
	results.append_array(_a_duct_saves_current_rather_than_costing_it())
	results.append_array(_the_length_scale_is_the_blade_s_own_tip_chord())
	results.append_array(_changing_the_guard_invalidates_the_cached_surface())
	results.append_array(_the_air_twin_carries_the_guard())
	results.append_array(_an_unreadable_guard_fits_nothing())

	return results


# ---------------------------------------------------------------------------
# [P10b] The Build wiring — plans/2026-08-26-propulsion-room-design.md §3.4 and §4.0
# ---------------------------------------------------------------------------
#
# P10a shipped `guards.json`, `PropGuard.as_part_mass` and the physics, and proved the
# `AirframeProperties` boundary with fixtures that hand `PartMass` entries in directly. It did
# NOT ship the wiring: `as_part_mass` had no caller outside `tests/`, so no aircraft in the app
# could fit a guard and P10b's closure had nothing to read. That wiring is what this section
# tests — a fitted guard reaching mass, inertia, thrust, torque, current and the ratio surface,
# each by its own route and each with its own way to be missed.

## `guards.json`'s cinewhoop shroud, the entry §3.1 built for exactly this: `tip_gap_mm = 1.5`
## against the reference prop's 1.92 mm tip chord.
const DUCT_ID := "guard_duct_5in_cinewhoop"
## And the freestyle ring, which is a bumper and must therefore move mass and NOTHING else.
const BUMPER_ID := "guard_bumper_5in_abs"


static func _build_with_guard(guard_id: String) -> Build:
	return Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, null, guard_id)


## The reference build fits NO guard, and every oracle it anchors is bit-identical with the new
## parameter present. This is §7's first named failure mode: a `guard_id` default of `""` that
## the parts loader still enumerates, or a closure short circuit that returns 0.99999 instead of
## exactly 1.0, and 496 g / 11.69:1 / 29.6% quietly stop being the numbers the paper says.
##
## Asserted against `ReferenceBuild.build()`, which does NOT pass a guard_id at all, so this also
## pins that the new trailing default argument did not change what the default build is.
##
## TO MAKE THIS FAIL: default `guard_id` to any catalog id, or move the `guard_closure > 0.0`
## short circuit in `_recompute` to `>= 0.0`.
static func _the_reference_build_fits_no_guard() -> Array:
	var plain := ReferenceBuild.build()
	var explicit := _build_with_guard("")
	return [
		TestResult.new(
			"[P10b] a build with guard_id \"\" is the reference build, bit-identical in mass and thrust",
			plain.mass_properties.total_mass_kg == explicit.mass_properties.total_mass_kg
				and plain.k_t == explicit.k_t and plain.k_q == explicit.k_q
				and plain.effective_max_amps == explicit.effective_max_amps,
			"mass %.17f / %.17f, k_t %.17f / %.17f" % [
				plain.mass_properties.total_mass_kg, explicit.mass_properties.total_mass_kg,
				plain.k_t, explicit.k_t]),
		TestResult.new(
			"[P10b] and the 507.5 g / 11.43:1 / 29.9% oracles are where they were",
			absf(explicit.mass_properties.total_mass_kg - 0.5074807) < 1.0e-6
				and absf(explicit.thrust_to_weight() - 11.4290) < 1.0e-3
				and absf(explicit.hover_throttle() - 0.29919) < 1.0e-4
				and explicit.guard_closure == 0.0,
			"%.1f g, %.4f:1, %.5f hover, closure %.1f" % [
				explicit.mass_properties.total_mass_kg * 1000.0, explicit.thrust_to_weight(),
				explicit.hover_throttle(), explicit.guard_closure]),
	]


## A fitted guard rides at every motor, and its mass and its inertia bite both arrive.
##
## MASS IS ASSERTED EXACTLY: four rings, one per motor, `4 x PropGuard.mass_kg(spec)` and not a
## milligram else. A wiring that fitted one guard for the whole aircraft, or that appended the
## guard to `extra_parts` twice, moves this number and cannot hide.
##
## THE INERTIA BITE IS ASSERTED AGAINST ITS POINT-MASS FLOOR. Each motor sits at
## `(±arm/√2, 0, ±arm/√2)`, so a ring at the motor's own position contributes `m·(x² + y²) =
## m·arm²/2` to roll (I_ZZ) and the four of them contribute `2·m·arm²` — 4.05e-4 kg·m² for the
## bumper's 16.74 g on a 110 mm arm. The MEASURED delta is 4.14e-4: 2% higher, because 63 g
## arriving at y = 0 also pulls the whole aircraft's centre of mass toward the motor plane and
## every other part's parallel-axis distance moves with it. So the check is a band around the
## closed form rather than an equality — wide enough for the CoM shift, far too tight for the
## double-count P10a's row warns about, which lands at 3.9x.
##
## TO MAKE THIS FAIL: place the guard at `Vector3.ZERO` (the delta collapses to the CoM shift
## alone), fit one guard instead of four, or hand `PartMass` the scalar
## `roll_inertia_contribution_kg_m2` as its local diagonal on the Z axis.
static func _a_fitted_guard_rides_at_every_motor() -> Array:
	var catalog := PartsCatalog.load_default()
	var spec: Dictionary = catalog.get_part(BUMPER_ID)["specs"]
	var ring_kg := PropGuard.mass_kg(spec)
	var plain := ReferenceBuild.build()
	var guarded := _build_with_guard(BUMPER_ID)

	var mass_delta := guarded.mass_properties.total_mass_kg - plain.mass_properties.total_mass_kg
	var roll_delta := guarded.mass_properties.inertia.z.z - plain.mass_properties.inertia.z.z
	var point_mass_floor := 2.0 * ring_kg * guarded.arm_m * guarded.arm_m

	return [
		TestResult.new(
			"[P10b] a fitted guard adds exactly four rings of mass — one per motor, not one per build",
			absf(mass_delta - 4.0 * ring_kg) < 1.0e-12,
			"delta %.9f kg against 4 x %.9f = %.9f" % [
				mass_delta, ring_kg, 4.0 * ring_kg]),
		TestResult.new(
			"[P10b] and the roll-inertia bite lands on its point-mass floor, not at zero and not doubled",
			roll_delta > point_mass_floor
				and roll_delta < 1.05 * point_mass_floor,
			"roll delta %.9f kg·m² against the 2·m·arm² floor %.9f (ratio %.4f)" % [
				roll_delta, point_mass_floor, roll_delta / point_mass_floor]),
	]


## §6.1's SILENT FAILURE, now testable through a whole aircraft: a bumper claims mass, inertia
## and clearance ONLY. Fitting one must move the mass numbers and leave every thrust number
## bit-identical — not close, identical, because `tip_loss_closure` returns 0.0 for a bumper and
## `_recompute`'s short circuit then never touches `k_t`.
##
## The reason this is worth a whole-build test after `test_prop_guard.gd` already checks
## `tip_loss_closure` on a bumper: the closure is computed in `Build._recompute` from a spec dug
## out of a catalog record, and a wiring that read `guard["specs"]["tip_gap_mm"]` directly
## instead of going through `PropGuard` would pass every unit check in this file and hand the
## freestyle ring a duct's thrust anyway. `guards.json`'s bumper carries no `tip_gap_mm`, so the
## sharper version of the same trap — a wiring that treats a missing gap as zero, i.e. as a
## PERFECT seal — is what the `k_t` identity actually catches.
##
## TO MAKE THIS FAIL: drop the `kind` check from `tip_loss_closure`, or default a missing
## `tip_gap_mm` to 0.0 anywhere on the path.
static func _a_bumper_moves_mass_and_no_thrust_number() -> Array:
	var plain := ReferenceBuild.build()
	var bumped := _build_with_guard(BUMPER_ID)
	return [
		TestResult.new(
			"[P10b] a fitted BUMPER leaves k_t, k_q and the current limit bit-identical",
			bumped.guard_closure == 0.0 and bumped.k_t == plain.k_t
				and bumped.k_q == plain.k_q
				and bumped.effective_max_amps == plain.effective_max_amps,
			"closure %.1f, k_t %.17f / %.17f" % [bumped.guard_closure, bumped.k_t, plain.k_t]),
		TestResult.new(
			"[P10b] while its mass and inertia genuinely moved, so the check above is not vacuous",
			bumped.mass_properties.total_mass_kg > plain.mass_properties.total_mass_kg
				and bumped.mass_properties.inertia.z.z > plain.mass_properties.inertia.z.z,
			"%.1f g against %.1f g, I_ZZ %.8f against %.8f" % [
				bumped.mass_properties.total_mass_kg * 1000.0,
				plain.mass_properties.total_mass_kg * 1000.0,
				bumped.mass_properties.inertia.z.z, plain.mass_properties.inertia.z.z]),
	]


## THE DEFECT THIS TEST EXISTS TO PIN, and it shipped in the first cut of P10b.
##
## `Build` fits `k_q` from `k_t` — `PropellerModel.fit_k_q` is a fixed multiple of it — so the
## obvious wiring, "scale `k_t` by the closure's thrust factor and let `k_q` follow", moves
## torque in the SAME direction as thrust. The BEMT solve says the opposite: closing the tip leak
## enlarges the annulus that accepts momentum, the induced velocity falls, and induced drag falls
## with it. Measured on the reference build with the cinewhoop duct (closure 0.5615):
##
##     static thrust   x 1.00999
##     static torque   x 0.99472
##
## The first cut reported `k_q` UP 1.0% where the model says it is DOWN 0.53%, and
## `effective_max_amps` — which is a ratio of two `k_q` values — carried the same error the same
## wrong way. A duct's entire point is that it is an efficiency part; the number a builder fits
## one for is the current, and the current was the number that went backwards.
##
## So `k_q` is now fit from the OPEN-ROTOR `k_t` and multiplied by the closure's own TORQUE
## factor, from `BemtModel.static_closure_factors`'s second element. This test asserts the
## direction, which is what the shortcut cannot satisfy: no scalar multiple of a `k_t` that went
## UP produces a `k_q` that went DOWN.
##
## TO MAKE THIS FAIL: write `k_q = PropellerModel.fit_k_q(k_t, D)` after the `k_t *=` line —
## the exact one-line shortcut this replaced.
static func _a_duct_saves_current_rather_than_costing_it() -> Array:
	var plain := ReferenceBuild.build()
	var ducted := _build_with_guard(DUCT_ID)
	return [
		TestResult.new(
			"[P10b] a fitted duct raises k_t — the thrust the closed tip leak earns, +1.0%",
			ducted.k_t > plain.k_t
				and absf(ducted.k_t / plain.k_t - 1.00999) < 5.0e-5,
			"k_t ratio %.8f" % (ducted.k_t / plain.k_t)),
		TestResult.new(
			"[P10b] and LOWERS k_q, which no multiple of a raised k_t can do — the shortcut is dead",
			ducted.k_q < plain.k_q
				and absf(ducted.k_q / plain.k_q - 0.99472) < 5.0e-5,
			"k_q ratio %.8f (the k_t-derived shortcut would give %.8f)" % [
				ducted.k_q / plain.k_q, ducted.k_t / plain.k_t]),
		TestResult.new(
			"[P10b] and the current limit follows the torque, not the thrust",
			ducted.effective_max_amps < plain.effective_max_amps,
			"%.4f A against %.4f A" % [
				ducted.effective_max_amps, plain.effective_max_amps]),
	]


## §4.0's FIRST LINK: where the length scale comes from. `PropGuard.tip_loss_closure` takes
## `chord_at_tip_mm` from its caller because P9 refused to keep it as a constant, and the caller
## is `PropellerDocument.chord_at(1.0)`. The failure this guards is a tip-chord constant
## reappearing in `build.gd` — which would pass every check in this file that only looks at the
## closure's VALUE, because a constant near 1.9 mm gives nearly the right answer on the reference
## prop and the wrong answer on every other propeller in the catalog.
##
## So it is asserted on TWO propellers with different tip chords, against the document's own
## `chord_at(1.0)` each time. A constant cannot satisfy both.
##
## TO MAKE THIS FAIL: replace `guarded_prop_doc.chord_at(1.0)` with any literal.
static func _the_length_scale_is_the_blade_s_own_tip_chord() -> Array:
	var catalog := PartsCatalog.load_default()
	var spec: Dictionary = catalog.get_part(DUCT_ID)["specs"]
	var results: Array = []
	var tip_chords: Array = []
	for prop_id in [ReferenceBuild.PROPELLER_ID, "prop_8x45x3"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		if prop.is_empty():
			continue
		var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			prop_id, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID,
			{}, null, DUCT_ID)
		var tip_chord_mm := PropellerDocument.from_catalog_prop(prop).chord_at(1.0)
		tip_chords.append(tip_chord_mm)
		results.append(TestResult.new(
			"[P10b] the closure on %s reads that blade's OWN tip chord, not a constant" % prop_id,
			absf(build.guard_closure - PropGuard.tip_loss_closure(spec, tip_chord_mm)) < 1.0e-15,
			"closure %.12f from tip chord %.5f mm" % [build.guard_closure, tip_chord_mm]))
	results.append(TestResult.new(
		"[P10b] and the two propellers really do have different tip chords, so a constant fails",
		tip_chords.size() == 2 and absf(float(tip_chords[0]) - float(tip_chords[1])) > 0.1,
		"tip chords %s mm" % str(tip_chords)))
	return results


## §4.0's SECOND LINK, and the one it calls "the most likely to be missed, because everything
## looks right and the aircraft flies the old surface". `Build` caches `_forward_ratios` because
## the first solve costs ~150 ms. Extending the Rust cache key is necessary and NOT sufficient: a
## build that already holds a surface keeps flying the pre-guard one until something clears the
## handle.
##
## Asserted by fitting a guard on a build that has ALREADY built its open-rotor surface, then
## checking the new surface both is a different object and reports the new closure. Object
## identity alone is too weak — a wiring that reset the handle to `null` and then rebuilt from a
## stale `guard_closure` would pass it — and the closure alone is too weak, because a surface
## built from the right closure but never re-fetched is the exact bug. Both, or neither.
##
## TO MAKE THIS FAIL: delete the `_forward_ratios = null` line from `_recompute`.
static func _changing_the_guard_invalidates_the_cached_surface() -> Array:
	var catalog := PartsCatalog.load_default()
	var build := ReferenceBuild.build()
	var open_surface := build.forward_ratios()
	var open_closure := open_surface.guard_closure()

	build.guard = catalog.get_part(DUCT_ID)
	build._recompute()
	var ducted_surface := build.forward_ratios()
	# Snapshotted HERE, not read at the end: the `return [...]` below is built after the guard
	# has been taken off again, so a `build.guard_closure` in the assertion would read 0.0 and
	# fail a check about a state the build is no longer in.
	var ducted_closure := build.guard_closure

	# And back off again — a guard REMOVED must invalidate just as a guard fitted does.
	build.guard = {}
	build._recompute()
	var reopened_surface := build.forward_ratios()

	return [
		TestResult.new(
			"[P10b] fitting a guard replaces the cached ratio surface — object AND closure both move",
			ducted_surface.get_instance_id() != open_surface.get_instance_id()
				and open_closure == 0.0
				and absf(ducted_surface.guard_closure() - ducted_closure) < 1.0e-15
				and ducted_surface.guard_closure() > 0.5,
			"open closure %.4f, ducted surface closure %.17f, build closure %.17f" % [
				open_closure, ducted_surface.guard_closure(), ducted_closure]),
		TestResult.new(
			"[P10b] and removing it invalidates the surface again, back to the open rotor",
			reopened_surface.get_instance_id() != ducted_surface.get_instance_id()
				and reopened_surface.guard_closure() == 0.0
				and build.guard_closure == 0.0,
			"reopened surface closure %.4f" % reopened_surface.guard_closure()),
	]


## A twin at a different air must be the SAME AIRCRAFT. `at_air` rebuilds through `from_ids`, so
## a guard that did not travel would make "would this fly at sea level" an answer about a
## different drone — lighter by 63 g and with the tip leak open again.
##
## The closure is re-derived at the new density rather than copied, which is the honest way round:
## it IS density-invariant, but a copied scalar and a re-derived one are the same number only
## while that stays true, and stating the invariance in two places is how they drift apart.
##
## TO MAKE THIS FAIL: drop the trailing `g_id` argument from `at_air`'s `from_ids` call.
static func _the_air_twin_carries_the_guard() -> Array:
	var ducted := _build_with_guard(DUCT_ID)
	var twin := ducted.at_air(AirDensity.new(3500.0, 5.0))
	return [
		TestResult.new(
			"[P10b] a build re-flown at another air keeps its guard, its mass and its closure",
			str(twin.guard.get("part_id", "")) == DUCT_ID
				and twin.guard_closure == ducted.guard_closure
				and absf(twin.mass_properties.total_mass_kg
					- ducted.mass_properties.total_mass_kg) < 1.0e-12,
			"twin guard %s, closure %.12f, mass %.4f g" % [
				str(twin.guard.get("part_id", "")), twin.guard_closure,
				twin.mass_properties.total_mass_kg * 1000.0]),
		TestResult.new(
			"[P10b] and the thin air still moved its k_t, so the twin is genuinely a twin at 3500 m",
			twin.k_t < ducted.k_t,
			"k_t %.12f at 3500 m against %.12f at sea level" % [twin.k_t, ducted.k_t]),
	]


## An unreadable guard fits NOTHING — not a zero-mass ghost, not a class-typical ring. Same
## posture `as_part_mass` takes with its `null` return, asserted one level up where a builder
## could actually hit it: a custom part with a mistyped `wall_mm`.
##
## Both halves matter. The mass must be bit-identical to the unguarded build (a zero-mass
## `PartMass` would pass a lenient check while adding a phantom entry to `contributions`), and
## the closure must be 0.0 (a duct whose geometry `compute()` refuses must not still claim the
## tip-loss suppression its `tip_gap_mm` would earn).
##
## TO MAKE THIS FAIL: drop the `pm != null` guard in `mass_parts()`, or read `tip_gap_mm` without
## first asking `compute()` whether the ring is readable at all.
static func _an_unreadable_guard_fits_nothing() -> Array:
	var plain := ReferenceBuild.build()
	var build := ReferenceBuild.build()
	build.guard = {
		"part_id": "guard_broken_fixture",
		"category": "guard",
		"specs": {
			"kind": PropGuard.KIND_DUCT, "outer_radius_mm": 68.0, "wall_mm": -3.0,
			"height_mm": 12.0, "density_kg_m3": 1050.0, "mount_radius_mm": 96.0,
			"tip_gap_mm": 1.5,
		},
	}
	build._recompute()
	return [
		TestResult.new(
			"[P10b] a guard whose geometry compute() refuses adds no mass — bit-identical, not close",
			build.mass_properties.total_mass_kg == plain.mass_properties.total_mass_kg
				and build.mass_properties.inertia.z.z == plain.mass_properties.inertia.z.z,
			"%.17f kg against %.17f kg" % [
				build.mass_properties.total_mass_kg, plain.mass_properties.total_mass_kg]),
		TestResult.new(
			"[P10b] and claims no tip-loss suppression either, though its tip_gap_mm is readable",
			build.guard_closure == 0.0 and build.k_t == plain.k_t and build.k_q == plain.k_q,
			"closure %.1f, k_t %.17f / %.17f" % [build.guard_closure, build.k_t, plain.k_t]),
	]
