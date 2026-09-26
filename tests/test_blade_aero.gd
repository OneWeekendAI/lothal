class_name TestBladeAero
extends RefCounted
## `BladeAero` — the Propulsion room's verdict on the blade being drawn.
##
## ## What has to be true for this verdict to be worth showing a builder
##
## 1. **The stations are the solve's own working state.** `station_distribution` taps `alpha`,
##    `C_l` and `C_d` from inside the converged block that makes each annulus's dT. The check that
##    this is a TAP and not a formula written twice is that the tap reproduces the solve's thrust
##    when it is fed back through the blade-element relation — see the reconstruction test.
##
## 2. **The two taps walk the same grid.** `thrust_distribution` and `station_distribution` must
##    return annulus for annulus in the same order, or the stall shading lands beside the loading
##    it is supposed to explain. Asserted with `==` on the radii: they come from the same loop
##    variable, so anything less than equality would pass a second grid that agreed to nine digits.
##
## 3. **The figure of merit is measured against momentum theory, not against itself.** The one
##    formula this layer owns is pinned to `BemtModel.uniform_inflow_momentum` — a separate
##    integrator in Rust for the same ideal — rather than to a restatement of the same line.
##
## 4. **The lift cap responds to the blade.** A coarse-pitch blade must be capped further out than
##    a fine-pitch one, or the shading is decoration. NOT "a fine blade is uncapped": it is not, and
##    finding that out is what `BladeAero`'s FINDING records — every catalog propeller runs some of
##    its root at the cap, because β = atan(P/2πr) grows without bound toward the axis.
##
## 5. **A refusal stays a refusal.** The solve declines some rotors; a verdict panel that renders
##    that as 0.0 g/W has invented an answer.
##
## ## What is deliberately NOT checked here
##
## Anything needing a tree. `BladeAero` is pure by construction so that the numbers are provable
## headless; the panel and the 3D view that consume it are checked in `test_blade_room.gd`, and
## what neither can check (that the SubViewport renders) is stated there rather than implied.

## The RPM every test runs at unless it is about RPM. 18000 is the operating point
## `test_thrust_overlay.gd` uses for the same catalog prop, so numbers here are comparable to it.
const TEST_RPM := 18000.0

## How coarse the stalling blade's pitch is, in mm. 12 inch of pitch on a 5 inch prop is not a
## propeller anybody would print — which is the point: the test is that stall APPEARS when the
## geometry demands it, and a marginal pitch would leave the check passing on a blade that never
## reached the cap at all.
const COARSE_PITCH_MM := 300.0

## The fine-pitch comparison. 30 mm on a 5" disc is as shallow as a propeller gets — and its root
## STILL reaches the cap, which is the point of the pair rather than an inconvenience.
const FINE_PITCH_MM := 30.0

## How far out the coarse blade's cap must reach before the check believes the pitch moved it. 0.9 R
## is nearly the whole blade, and the fine blade's own extent is asserted below it rather than
## against a constant, so the two clauses cannot both be satisfied by a metric stuck at either end.
const COARSE_CAPPED_FLOOR := 0.9


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_station_tap_reconstructs_the_solves_thrust())
	results.append(_test_both_taps_walk_the_same_annuli())
	results.append(_test_the_figure_of_merit_matches_momentum_theory())
	results.append(_test_the_figure_of_merit_is_below_one_on_a_real_blade())
	results.append(_test_pitch_moves_how_far_out_the_lift_cap_reaches())
	results.append(_test_every_catalog_propeller_caps_some_of_its_root())
	results.append(_test_stall_bands_cover_the_stalled_annuli_and_no_others())
	results.append(_test_stall_fraction_ignores_the_hub())
	results.append(_test_a_refused_rotor_is_refused_rather_than_zero())
	results.append(_test_grams_per_watt_falls_as_the_blade_is_driven_harder())
	results.append(_test_the_caret_finds_its_own_station())
	return results


static func _reference_doc() -> PropellerDocument:
	return PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))


# ---------------------------------------------------------------------------
# 1. The tap is the solve's working state
# ---------------------------------------------------------------------------

## Feeding the tapped α, C_l and C_d back through the blade-element relation reproduces the
## per-annulus thrust the OTHER tap reports, to the solve's convergence residual.
##
##     dT = ½ρU²·N_b·c·(C_l·cosφ − C_d·sinφ)·dr
##
## The inflow angle is recovered as φ = β − α from the document's own β, so this check crosses
## three definitions that are written in three different places (the polar in Rust, β on
## `PropellerDocument`, the thrust tap) and would fail if any drifted from the others.
##
## MUTATION that turns this red: in `bemt.rs`, push `beta` instead of `alpha` into the station
## tap. Both are angles of the same order at the same annulus, both make a plausible-looking
## curve, and only reconstructing the thrust from them tells the two apart.
static func _test_the_station_tap_reconstructs_the_solves_thrust() -> TestResult:
	var doc := _reference_doc()
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var radius := d_m * 0.5
	var rho := BladeAero.RHO_DEFAULT
	var omega := TEST_RPM * TAU / 60.0
	var pairs: PackedFloat64Array = BemtModel.thrust_distribution(
		rho, d_m, p_m, float(doc.blades), TEST_RPM, doc.chord, 0.0)
	var stations: PackedFloat64Array = BemtModel.station_distribution(
		rho, d_m, p_m, float(doc.blades), TEST_RPM, doc.chord, 0.0)

	var count := BladeAero.station_count(stations)
	var dr: float = absf(pairs[2] - pairs[0])
	var worst := 0.0
	var checked := 0
	for i in count:
		var at := i * BladeAero.STATION_STRIDE
		var r: float = stations[at]
		var alpha: float = stations[at + 1]
		var c_l: float = stations[at + 2]
		var c_d: float = stations[at + 3]
		var chord_m := doc.chord_at(r / radius) * 0.001
		if chord_m <= 0.0 or c_l <= 0.0:
			continue
		var beta := doc.beta_rad(r / radius)
		var phi := beta - alpha
		# U² = v_i² + (Ωr)², and v_i = Ωr·tan(φ) is the solve's own definition of φ.
		var v_i := omega * r * tan(phi)
		var u2 := v_i * v_i + pow(omega * r, 2.0)
		var d_t := 0.5 * rho * u2 * float(doc.blades) * chord_m \
			* (c_l * cos(phi) - c_d * sin(phi)) * dr
		var reported: float = pairs[i * 2 + 1]
		if reported > 0.0:
			worst = maxf(worst, absf(d_t - reported) / reported)
			checked += 1
	return TestResult.new(
		"the station tap reconstructs the thrust tap's own dT through the blade-element relation",
		checked > 10 and worst < 1e-9,
		"%d annuli, worst relative gap %s" % [checked, str(worst)])


## The two taps are the same annuli in the same order, radius for radius, exactly.
##
## MUTATION that turns this red: move the station push in `bemt.rs` above the `chord_m <= 0.0`
## early-out's own push, so the zero-chord annuli appear in one tap and not the other. The arrays
## then differ only in LENGTH and in where they align — every station still carries a correct
## radius, so a test comparing only counts, or only the first few entries, passes.
static func _test_both_taps_walk_the_same_annuli() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var checked := 0
	var all_aligned := true
	var worst_name := ""
	for prop in catalog.by_category["propeller"]:
		var doc := PropellerDocument.from_catalog_prop(prop)
		var d_m := doc.diameter_mm * 0.001
		var p_m := doc.pitch_mm * 0.001
		var pairs: PackedFloat64Array = BemtModel.thrust_distribution(
			BladeAero.RHO_DEFAULT, d_m, p_m, float(doc.blades), TEST_RPM, doc.chord, 0.0)
		var stations: PackedFloat64Array = BemtModel.station_distribution(
			BladeAero.RHO_DEFAULT, d_m, p_m, float(doc.blades), TEST_RPM, doc.chord, 0.0)
		checked += 1
		var n_pairs := int(pairs.size() / 2.0)
		var n_stations := BladeAero.station_count(stations)
		var aligned := n_pairs == n_stations and n_pairs > 0
		if aligned:
			for i in n_pairs:
				if pairs[i * 2] != stations[i * BladeAero.STATION_STRIDE]:
					aligned = false
					break
		if not aligned:
			all_aligned = false
			worst_name = str(prop.get("part_id", "?"))
	return TestResult.new(
		"both taps return the same annuli in the same order on every catalog prop",
		all_aligned and checked > 0,
		"%d props%s" % [checked, "" if all_aligned else " (misaligned at %s)" % worst_name])


# ---------------------------------------------------------------------------
# 3. The figure of merit is measured, not restated
# ---------------------------------------------------------------------------

## `BladeAero.ideal_power_w` agrees with Rust's momentum integrator run at the induced velocity the
## closed form implies: v_i = sqrt(T / (2ρA)) must produce that same T and a power of T·v_i.
##
## This is the cross-check that the FM denominator is momentum theory rather than a number that
## happens to have the right units — the two are computed by different code in different languages
## and agree only if the closed form is the integral's.
##
## MUTATION that turns this red: drop the factor 2 in `ideal_power_w`'s `sqrt(2·ρ·A)`. FM stays
## dimensionally correct, stays monotone in everything, and lands at 1.41x its true value — which
## no self-consistency check can see, because every other number in this file would move with it.
static func _test_the_figure_of_merit_matches_momentum_theory() -> TestResult:
	var rho := BladeAero.RHO_DEFAULT
	var d_m := 0.127
	var area := PI * pow(d_m * 0.5, 2.0)
	var thrust := 8.0
	var v_i := sqrt(thrust / (2.0 * rho * area))
	var momentum: PackedFloat64Array = BemtModel.uniform_inflow_momentum(rho, d_m, v_i, 4000)
	var ideal := BladeAero.ideal_power_w(thrust, rho, area)
	var thrust_gap: float = absf(momentum[0] - thrust) / thrust
	var power_gap: float = absf(momentum[1] - ideal) / ideal
	return TestResult.new(
		"the FM denominator is Rust's momentum integral, not a lookalike closed form",
		thrust_gap < 1e-6 and power_gap < 1e-6,
		"thrust %s, power %s (relative)" % [str(thrust_gap), str(power_gap)])


## A real blade's figure of merit sits strictly between 0 and 1: momentum theory is a FLOOR on
## power, so no rotor may beat it, and a rotor with profile drag may not equal it either.
##
## The band is the check. A verdict that could report FM above 1 would be telling a builder their
## printed blade beats the physical limit, which is the single most damaging thing this panel
## could say.
static func _test_the_figure_of_merit_is_below_one_on_a_real_blade() -> TestResult:
	var verdict := BladeAero.analyse(_reference_doc(), TEST_RPM)
	var fm: float = verdict["figure_of_merit"]
	return TestResult.new(
		"the reference blade's figure of merit lies strictly inside (0, 1)",
		not verdict["refused"] and fm > 0.0 and fm < 1.0,
		"FM %.3f at %.1f N, %.1f W" % [fm, verdict["thrust_n"], verdict["power_w"]])


# ---------------------------------------------------------------------------
# 4. Stall responds to the blade
# ---------------------------------------------------------------------------

## Pitching the blade up moves the lift cap OUTBOARD, and the fine blade is capped only near its
## root.
##
## The original form of this check — "a coarse blade caps and a fine one does not" — was written
## before the model was asked, and the model disagreed: at 30 mm of pitch on a 5" disc, 30% of the
## blade is still at the cap. That is not a bug in either, and the finding is now recorded in
## `BladeAero`'s header. What survives as a check is the DIFFERENCE, which is what the room is for.
##
## Both clauses are asserted, and that is the substance: a metric pinned at 1.0 R satisfies the
## first alone, and one pinned at the hub satisfies the second alone.
##
## MUTATION that turns this red: `>` instead of `>=` in `BladeAero.is_stalled`. The polar clamps
## C_l to exactly C_l_max, so every capped station reports C_l == cap and a strict comparison finds
## nothing capped on ANY blade, at any pitch — both extents collapse to 0.0.
static func _test_pitch_moves_how_far_out_the_lift_cap_reaches() -> TestResult:
	var coarse := _reference_doc()
	coarse.pitch_mm = COARSE_PITCH_MM
	var fine := _reference_doc()
	fine.pitch_mm = FINE_PITCH_MM
	var coarse_extent: float = BladeAero.analyse(coarse, TEST_RPM)["capped_to_r_frac"]
	var fine_extent: float = BladeAero.analyse(fine, TEST_RPM)["capped_to_r_frac"]
	return TestResult.new(
		"pitching the blade up pushes the lift cap outboard, and a fine blade is capped near the root",
		coarse_extent >= COARSE_CAPPED_FLOOR and fine_extent < coarse_extent * 0.75,
		"coarse capped to %.2f R, fine to %.2f R" % [coarse_extent, fine_extent])


## The FINDING itself, pinned: every propeller in the shipped catalog runs part of its root at the
## polar's lift cap at a plausible operating point.
##
## This is here so the claim in `BladeAero`'s header is a measurement rather than a remark, and so
## that a future change to the polar or to β that made root capping disappear FAILS rather than
## quietly turning the panel's fourth figure into a constant 0.00 R nobody would look at twice.
##
## The band is asserted at both ends: nothing may be uncapped, and nothing outside the catalog's
## measured spread may pass unnoticed either.
static func _test_every_catalog_propeller_caps_some_of_its_root() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var lowest := INF
	var highest := 0.0
	var checked := 0
	var uncapped := ""
	for prop in catalog.by_category["propeller"]:
		var doc := PropellerDocument.from_catalog_prop(prop)
		var verdict := BladeAero.analyse(doc, TEST_RPM)
		if verdict["refused"]:
			continue
		checked += 1
		var extent: float = verdict["capped_to_r_frac"]
		lowest = minf(lowest, extent)
		highest = maxf(highest, extent)
		if extent <= 0.0:
			uncapped = str(prop.get("part_id", "?"))
	return TestResult.new(
		"every catalog propeller runs part of its root at the polar's lift cap",
		checked > 10 and uncapped == "" and lowest > 0.2 and highest <= 1.0,
		"%d props, capped to between %.2f R and %.2f R%s"
			% [checked, lowest, highest, "" if uncapped == "" else " (uncapped: %s)" % uncapped])


## The shaded bands cover exactly the stalled annuli: every stalled station falls inside a band,
## and every unstalled one falls outside every band except within half an annulus of a stalled
## neighbour (the half-width the bands deliberately extend by).
##
## MUTATION that turns this red: in `stall_bands`, close the open run only inside the loop and
## drop the tail append after it. A blade stalled all the way to the tip — the common case, and
## the one a builder most needs to see — then produces NO band at all, while every partially
## stalled blade still bands correctly.
static func _test_stall_bands_cover_the_stalled_annuli_and_no_others() -> TestResult:
	var doc := _reference_doc()
	doc.pitch_mm = COARSE_PITCH_MM
	var verdict := BladeAero.analyse(doc, TEST_RPM)
	var stations: PackedFloat64Array = verdict["stations"]
	var radius := doc.radius_mm() * 0.001
	var c_l_max: float = BemtModel.global_polar()[3]
	var bands := BladeAero.stall_bands(stations, c_l_max, radius)

	var count := BladeAero.station_count(stations)
	var half := absf(stations[BladeAero.STATION_STRIDE] - stations[0]) * 0.5 / radius
	var missed := 0
	var spurious := 0
	for i in count:
		var r_frac: float = stations[i * BladeAero.STATION_STRIDE] / radius
		var inside := false
		var j := 0
		while j + 1 < bands.size():
			if r_frac >= bands[j] - 1e-12 and r_frac <= bands[j + 1] + 1e-12:
				inside = true
			j += 2
		var stalled := BladeAero.is_stalled(stations, i, c_l_max)
		if stalled and not inside:
			missed += 1
		# An unstalled station may legitimately sit inside the half-width overhang of a stalled
		# neighbour; deeper than that is a band covering blade that is flying.
		if not stalled and inside:
			var nearest_stalled := INF
			for k in count:
				if BladeAero.is_stalled(stations, k, c_l_max):
					nearest_stalled = minf(nearest_stalled,
						absf(stations[k * BladeAero.STATION_STRIDE] / radius - r_frac))
			if nearest_stalled > half * 2.0 + 1e-9:
				spurious += 1
	return TestResult.new(
		"the shaded bands cover every stalled annulus and no blade that is flying",
		bands.size() > 0 and missed == 0 and spurious == 0,
		"%d bands, %d stalled stations uncovered, %d flying stations shaded"
			% [int(bands.size() / 2.0), missed, spurious])


## Hub annuli — zero chord, no lift — are excluded from the stall fraction's denominator.
##
## Built by extending the reference planform's root inward with zero-chord stations, which adds
## non-lifting annuli WITHOUT changing the blade: the fraction must not move.
##
## MUTATION that turns this red: count every station in the denominator. The metric then improves
## the more hub a planform declares, so a builder could "fix" a stalled blade by moving its root
## inboard and changing nothing about the aerofoil at all.
static func _test_stall_fraction_ignores_the_hub() -> TestResult:
	var doc := _reference_doc()
	doc.pitch_mm = COARSE_PITCH_MM
	var before: float = BladeAero.analyse(doc, TEST_RPM)["stall_fraction"]

	var hubbed := _reference_doc()
	hubbed.pitch_mm = COARSE_PITCH_MM
	var extended := PackedFloat64Array([0.02, 0.0, doc.chord[0] - 0.001, 0.0])
	extended.append_array(doc.chord)
	hubbed.chord = extended
	var after: float = BladeAero.analyse(hubbed, TEST_RPM)["stall_fraction"]
	return TestResult.new(
		"declaring more hub does not improve the stall fraction",
		before > 0.0 and absf(after - before) < 0.06,
		"%.3f before, %.3f after adding %d non-lifting stations"
			% [before, after, 2])


# ---------------------------------------------------------------------------
# 5. Refusals, and the shape of the verdict
# ---------------------------------------------------------------------------

## A rotor the solve declines comes back flagged, not zeroed.
##
## MUTATION that turns this red: return the dictionary with `refused` left false when
## `station_distribution` comes back empty. Every number in it is still 0.0 and every panel still
## draws — as a blade making no thrust at no efficiency, which is a claim about the blade rather
## than about the model's standing to answer.
static func _test_a_refused_rotor_is_refused_rather_than_zero() -> TestResult:
	var doc := _reference_doc()
	var stopped := BladeAero.analyse(doc, 0.0)
	var bladeless := _reference_doc()
	bladeless.blades = 0
	var no_blades := BladeAero.analyse(bladeless, TEST_RPM)
	return TestResult.new(
		"a stopped rotor and a bladeless one are refusals, not zero-efficiency blades",
		stopped["refused"] and no_blades["refused"],
		"stopped refused %s, bladeless refused %s"
			% [str(stopped["refused"]), str(no_blades["refused"])])


## Hover efficiency falls as the same blade is driven harder — disc loading rises with RPM² and
## induced power with T^1.5, so g/W must decrease monotonically across the usable range.
##
## This is the check that the headline number is a real efficiency and not thrust wearing a
## different unit: thrust RISES with RPM, so anything that accidentally reported thrust, or
## reported watts per gram, moves the wrong way here.
static func _test_grams_per_watt_falls_as_the_blade_is_driven_harder() -> TestResult:
	var doc := _reference_doc()
	var last := INF
	var monotone := true
	var trace: Array = []
	for rpm in [8000.0, 14000.0, 20000.0, 26000.0]:
		var verdict := BladeAero.analyse(doc, rpm)
		var g_per_w: float = verdict["grams_per_watt"]
		trace.append("%.0f: %.1f" % [rpm, g_per_w])
		if g_per_w >= last:
			monotone = false
		last = g_per_w
	return TestResult.new(
		"grams per watt falls monotonically as the blade is driven harder",
		monotone,
		"; ".join(PackedStringArray(trace)))


## The caret's r/R lands on the annulus that contains it, and an empty tap has no nearest station.
##
## MUTATION that turns this red: `return 0` instead of `-1` for an empty tap. Every caret then
## reads station zero of an array with no stations, which a panel renders as a plausible 0.0° angle
## of attack at the root of a blade the model refused to solve.
static func _test_the_caret_finds_its_own_station() -> TestResult:
	var doc := _reference_doc()
	var verdict := BladeAero.analyse(doc, TEST_RPM)
	var stations: PackedFloat64Array = verdict["stations"]
	var radius := doc.radius_mm() * 0.001
	var hits := 0
	var count := BladeAero.station_count(stations)
	for i in count:
		var r_frac: float = stations[i * BladeAero.STATION_STRIDE] / radius
		if BladeAero.station_at(stations, r_frac, radius) == i:
			hits += 1
	var empty_is_refused := BladeAero.station_at(PackedFloat64Array(), 0.5, radius) == -1
	return TestResult.new(
		"a caret finds the annulus it sits in, and an empty tap has no nearest station",
		hits == count and count > 0 and empty_is_refused,
		"%d/%d stations self-locate, empty tap returns -1 %s"
			% [hits, count, str(empty_is_refused)])
