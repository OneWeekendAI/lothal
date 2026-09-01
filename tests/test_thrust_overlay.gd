class_name TestThrustOverlay
extends RefCounted
## The thrust-distribution overlay — P10e's first, see
## plans/2026-09-02-analysis-overlays-design.md.
##
## ## What has to be true for this overlay to be worth drawing
##
## 1. **It draws the solve, not a second copy of it.** `BemtModel.thrust_distribution` taps the
##    per-annulus addends inside `solve_impl`'s own loop, so their sum is `solve(...)[0]`
##    BIT-IDENTICALLY. Asserted with `==`, not with a tolerance: the claim is that these are the
##    same additions, and any tolerance at all would pass a GDScript reimplementation of the
##    quadrature that happened to agree to nine digits — which is the exact defect P10d spent a
##    slice removing from `PropellerMesh` and the thing §8 of the authored-blade design warned
##    whoever wrote this file about.
##
## 2. **It draws the grid the solve chose.** The overlay never derives an annulus position from
##    the diameter; it reads the radii back. So the returned r values must be the midpoint rule
##    the solver runs — uniformly spaced, first one half a width above the hub, last one half a
##    width below the tip.
##
## 3. **It responds to the blade in the editor next to it.** This is §8's whole argument for
##    shipping this overlay first. A tip-unloaded planform and the catalog arch of the same
##    diameter must put the peak of dT/dr in visibly different places.
##
## 4. **A refusal is a refusal.** The solve declines some rotors. Rendering that as a flat line
##    at zero would be the overlay inventing an answer the model would not give.
##
## ## What is deliberately NOT checked here
##
## Anything needing the shell in a tree. `GlassShell` wires itself in `_init` and `_ready`, needs a
## rendered frame for its reparent, and tests/run_tests.gd processes no frames — the constraint
## tests/test_glass_shell.gd already states from the other side, and the reason its own suite tests
## a static function rather than a shell. So the mapping functions below are public and pure and
## are checked directly; that the toggle shows the Control is left to the capture tooling, and
## said here rather than implied.

## The reference build's blade, tapered toward the tip by this much at r/R = 1 relative to the
## root. 0.45 rather than something gentler because the check is about a peak MOVING, and a taper
## the solve barely notices would leave the check passing on a distribution that does not respond
## to the planform at all — the failure this file exists to make impossible.
const TIP_TAPER := 0.45

## How far inboard the tip-unloaded blade must move its peak, as a fraction of radius. 0.02 is a
## floor rather than a prediction: the assertion is "the planform moved the answer", and the
## measured move is reported in the detail so a shrinking one is visible before it reaches zero.
const PEAK_MOVE_FLOOR := 0.02


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_sum_is_the_solves_thrust_bit_for_bit())
	results.append(_test_the_radii_are_the_solvers_own_grid())
	results.append(_test_a_tip_unloaded_blade_moves_the_peak_inboard())
	results.append(_test_a_refused_rotor_is_refused_rather_than_flat())
	results.append(_test_the_operating_point_is_the_spin_ups())
	results.append(_test_the_curve_maps_onto_the_canvas())
	return results


# ---------------------------------------------------------------------------
# 1. The overlay draws the solve
# ---------------------------------------------------------------------------

## Σ dT over the returned annuli == `solve(...)[0]`, exactly, on every propeller in the catalog.
##
## The whole catalog rather than one prop because the property is about the code path, and a
## single prop would pass for an implementation that happened to hit the same rounding on one
## planform. Equality is `==` on doubles and that is deliberate — see the header.
##
## MUTATION that turns this red: in `bemt.rs`, push `d_t_mom` instead of `d_t` into the tap. Both
## are per-annulus thrusts at the same annulus and they agree to the solve's convergence residual
## (~1e-4 relative), so every tolerance anyone would reasonably write passes the mutation and only
## bit-equality catches it.
static func _test_the_sum_is_the_solves_thrust_bit_for_bit() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var polar: PackedFloat64Array = BemtModel.global_polar()
	var checked := 0
	var worst_name := ""
	var worst_gap := 0.0
	var all_exact := true
	for prop in catalog.by_category["propeller"]:
		var doc := PropellerDocument.from_catalog_prop(prop)
		var d_m := doc.diameter_mm * 0.001
		var p_m := doc.pitch_mm * 0.001
		var blades := float(doc.blades)
		var pairs: PackedFloat64Array = BemtModel.thrust_distribution(
			1.225, d_m, p_m, blades, 18000.0, doc.chord, 0.0)
		var solved: PackedFloat64Array = BemtModel.solve(
			1.225, d_m, p_m, blades, 18000.0, doc.chord,
			polar[0], polar[1], polar[2], polar[3])
		var summed := ThrustOverlay.total_n(pairs)
		checked += 1
		if summed != solved[0]:
			all_exact = false
			var gap: float = absf(summed - solved[0])
			if gap > worst_gap:
				worst_gap = gap
				worst_name = str(prop.get("part_id", "?"))
	return TestResult.new(
		"the overlay's total IS the solve's thrust, bit for bit, on every catalog prop",
		all_exact and checked > 0,
		"%d props, all exact %s%s" % [checked, str(all_exact),
			"" if all_exact else " (worst %s at %s N)" % [worst_name, str(worst_gap)]])


## The radii come back from the solver's own midpoint grid, and the overlay never rebuilds it.
##
## Three clauses, and they are three because each alone is satisfiable by a wrong grid: uniform
## spacing says nothing about where the grid starts, the hub offset says nothing about the tip,
## and the count says nothing about either. Together they pin the midpoint rule `solve_impl` runs.
##
## MUTATION that turns this red: in `bemt.rs`, push `r_frac` instead of `r` into the tap — a
## dimensionless radius where a metric one belongs, which is exactly the slip a caller dividing by
## `radius_m` afterwards would not notice on the SHAPE of the curve at all.
static func _test_the_radii_are_the_solvers_own_grid() -> TestResult:
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var radius := doc.diameter_mm * 0.001 * 0.5
	var pairs: PackedFloat64Array = BemtModel.thrust_distribution(
		1.225, doc.diameter_mm * 0.001, doc.pitch_mm * 0.001, float(doc.blades),
		18000.0, doc.chord, 0.0)
	var width := ThrustOverlay.annulus_width_m(pairs)
	var count: int = int(pairs.size() / 2.0)

	var worst_step := 0.0
	for i in range(1, count):
		worst_step = maxf(worst_step, absf((pairs[i * 2] - pairs[(i - 1) * 2]) - width))
	var hub_m: float = doc.chord[0] * radius
	var first_ok: bool = absf(pairs[0] - (hub_m + width * 0.5)) < 1e-12
	var last_ok: bool = absf(pairs[(count - 1) * 2] - (radius - width * 0.5)) < 1e-12
	var uniform_ok: bool = count > 2 and worst_step < 1e-12
	return TestResult.new(
		"the annuli come back on the solver's own midpoint grid, not one rebuilt from the diameter",
		uniform_ok and first_ok and last_ok,
		"%d annuli, uniform %s, starts half a width above the hub %s, ends half a width below R %s"
			% [count, str(uniform_ok), str(first_ok), str(last_ok)])


# ---------------------------------------------------------------------------
# 3. It responds to the blade in the editor next to it — §8's argument
# ---------------------------------------------------------------------------

## A blade tapered toward the tip moves the peak of dT/dr INBOARD of where the catalog arch puts
## it. This is the check that would have been impossible to write honestly before the authored-
## blade slice: on that code both builds carried the generated arch and the two peaks landed on
## the same annulus.
##
## Both clauses matter. "The peaks differ" alone would pass if the tapered blade moved the peak
## OUTBOARD, which is not what unloading a tip does and would mean the taper had been applied to
## the wrong end of the blade — a sign error a shape-only check cannot see.
##
## MUTATION that turns this red: have `Build.thrust_distribution` pass
## `PropellerDocument.from_catalog_prop(propeller).chord`'s GENERATED arch — that is,
## `PropellerDocument.generate_chord(...)` — instead of `blade_chord()`. It is the pre-slice
## behaviour, it looks entirely reasonable at the call site, and it is the defect §8 said an
## overlay shipped before the resolver would have had.
static func _test_a_tip_unloaded_blade_moves_the_peak_inboard() -> TestResult:
	var plain := ReferenceBuild.build()
	var tapered := _build_with_document(_tip_unloaded_document())

	var plain_pairs := plain.thrust_distribution()
	var tapered_pairs := tapered.thrust_distribution()
	var plain_radius: float = float(plain.prop_geometry().diameter_m) * 0.5
	var tapered_radius: float = float(tapered.prop_geometry().diameter_m) * 0.5

	var plain_peak := ThrustOverlay.r_frac_at(
		plain_pairs, ThrustOverlay.peak_index(plain_pairs), plain_radius)
	var tapered_peak := ThrustOverlay.r_frac_at(
		tapered_pairs, ThrustOverlay.peak_index(tapered_pairs), tapered_radius)

	var moved: bool = plain_peak - tapered_peak >= PEAK_MOVE_FLOOR
	var same_disc: bool = absf(plain_radius - tapered_radius) < 1e-12
	return TestResult.new(
		"unloading the tip moves the peak of dT/dr inboard, on the same disc",
		moved and same_disc,
		"catalog arch peaks at %.3f R, tip-unloaded at %.3f R (moved %.3f R, same disc %s)"
			% [plain_peak, tapered_peak, plain_peak - tapered_peak, str(same_disc)])


# ---------------------------------------------------------------------------
# 4. A refusal is a refusal
# ---------------------------------------------------------------------------

## The solve declines a rotor with no blades, no diameter, no RPM, or a chord table too short to
## be a planform. The distribution must come back EMPTY for each, and the overlay must render that
## as words rather than as a curve at zero.
##
## The last clause is the one with teeth: a healthy rotor must not report a refusal, or the check
## would pass for an overlay that refuses everything.
##
## The refusal rule is asked for by name (`ThrustOverlay.refusal_for`) rather than restated here.
## A test that re-derived "empty means declined" would pass whatever the overlay does with an empty
## distribution, which is the shape of check this project treats as a defect.
##
## MUTATION that turns this red: weaken `refusal_for`'s floor to `pairs.size() >= 0` — the
## plausible "the caption already says 0.00 N, the words are redundant" simplification. All four
## declined rotors then draw an empty axis pair captioned as a total, and the healthy clause stays
## green. (Deleting the condition outright instead leaves `pairs` unused, and an unused parameter
## is a warning, and `project.godot` makes warnings errors — so that version of the mutation hangs
## the runner rather than reddening anything. Noted because it cost ten minutes.)
static func _test_a_refused_rotor_is_refused_rather_than_flat() -> TestResult:
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var d_m := doc.diameter_mm * 0.001
	var p_m := doc.pitch_mm * 0.001
	var cases := {
		"no blades": BemtModel.thrust_distribution(1.225, d_m, p_m, 0.0, 18000.0, doc.chord, 0.0),
		"no disc": BemtModel.thrust_distribution(1.225, 0.0, p_m, 3.0, 18000.0, doc.chord, 0.0),
		"stopped": BemtModel.thrust_distribution(1.225, d_m, p_m, 3.0, 0.0, doc.chord, 0.0),
		"no planform": BemtModel.thrust_distribution(
			1.225, d_m, p_m, 3.0, 18000.0, PackedFloat64Array([0.1, 5.0]), 0.0),
	}
	var refused: Array[String] = []
	var all_empty := true
	for label in cases:
		var pairs: PackedFloat64Array = cases[label]
		if not pairs.is_empty():
			all_empty = false
		if ThrustOverlay.refusal_for(pairs) != "":
			refused.append(str(label))

	var healthy := ThrustOverlay.new()
	healthy.adopt(ReferenceBuild.build())
	var healthy_ok: bool = healthy.refusal == "" and healthy.distribution.size() >= 4
	healthy.free()
	return TestResult.new(
		"a rotor the model declines is reported as declined, and a real one is not",
		all_empty and refused.size() == cases.size() and healthy_ok,
		"declined %d/%d (%s), all empty %s, reference build drawn %s"
			% [refused.size(), cases.size(), ", ".join(refused), str(all_empty), str(healthy_ok)])


# ---------------------------------------------------------------------------
# 5. One operating point, not two
# ---------------------------------------------------------------------------

## `Build.operating_rpm()` is the SAME operating point the spin-up linearisation uses. The overlay
## needs "the RPM this drone sits at", and so does `_omega_hover_rad_s`; two definitions of it
## would let the overlay draw a blade loading nobody flies, with both numbers plausible and
## neither labelled.
##
## Checked through the observable both share — `MotorSpinUp`'s τ, which is a function of
## `_omega_hover_rad_s` — rather than by reading a private method, and on a build that hovers AND
## one that does not, because the two arms of that function are exactly where they could diverge.
##
## MUTATION that turns this red: make `operating_rpm` return `rated_rpm()` unconditionally, which
## is the plausible simplification (it is what the method returns for anything that cannot hover)
## and moves the hovering build's operating point by a factor of about three.
static func _test_the_operating_point_is_the_spin_ups() -> TestResult:
	var flying := ReferenceBuild.build()
	var hovers := flying.can_hover()
	var rpm := flying.operating_rpm()
	var expected: float = flying.rated_rpm() * flying.hover_throttle()
	var hover_ok: bool = hovers and absf(rpm - expected) < 1e-12

	# The other arm: a build carrying a pack far too heavy to lift falls back to rated.
	var heavy := _overloaded_build()
	var heavy_rpm := heavy.operating_rpm()
	var heavy_ok: bool = not heavy.can_hover() and heavy_rpm == heavy.rated_rpm()

	# And the distribution really is taken at it — same RPM in, same numbers out.
	var geometry := flying.prop_geometry()
	var direct: PackedFloat64Array = BemtModel.thrust_distribution(
		flying.air.kgm3(), geometry.diameter_m, geometry.pitch_m, geometry.blades,
		rpm, flying.blade_chord(), flying.guard_closure)
	var same: bool = direct == flying.thrust_distribution()
	return TestResult.new(
		"the overlay is drawn at the operating point the spin-up linearises at",
		hover_ok and heavy_ok and same,
		"hovering %.1f rpm (%s), overloaded falls back to rated %.1f (%s), drawn there %s"
			% [rpm, str(hover_ok), heavy_rpm, str(heavy_ok), str(same)])


# ---------------------------------------------------------------------------
# 6. The mapping onto the canvas
# ---------------------------------------------------------------------------

## Where the curve LANDS, without a window — `PropellerPlanformEditor`'s posture.
##
## Four clauses. The root sits on the left inner edge and the tip on the right; the peak annulus
## touches the top of the inner rect, because the vertical scale is fitted to this blade's own
## peak; and x is strictly increasing, which is what makes the polyline a function of radius
## rather than a shape that doubles back.
##
## MUTATION that turns this red: in `curve_points`, divide by `_peak_density()` before calling
## `to_pixels` (double-normalising). Measured: it reddens the PEAK clause alone and leaves
## ascending and spans green — the prediction here was the other way round, and it was wrong for a
## reason worth keeping. Double-normalising is a monotone squash of the y axis; it moves every
## point down and reorders none, so an x-only clause cannot see it at all. The three clauses are
## not three views of one defect, they are three different defects, which is why they are three.
static func _test_the_curve_maps_onto_the_canvas() -> TestResult:
	var overlay := ThrustOverlay.new()
	overlay.adopt(ReferenceBuild.build())
	overlay.size = Vector2(360, 210)
	var points := overlay.curve_points()
	var inner_left := ThrustOverlay.MARGIN_PX
	var inner_right: float = 360.0 - ThrustOverlay.MARGIN_PX
	var inner_top := ThrustOverlay.MARGIN_PX

	var enough: bool = points.size() >= 8
	var ascending := enough
	for i in range(1, points.size()):
		if points[i].x <= points[i - 1].x:
			ascending = false
	# The first annulus sits half a width above the hub and the last half a width below the tip,
	# so neither reaches its edge — the bound is "inside, in order", not "on the edge".
	var spans: bool = enough and points[0].x > inner_left \
		and points[points.size() - 1].x < inner_right \
		and points[points.size() - 1].x > inner_left + (inner_right - inner_left) * 0.8
	var peak := ThrustOverlay.peak_index(overlay.distribution)
	var peak_at_top: bool = peak >= 0 and absf(points[peak].y - inner_top) < 1e-9
	overlay.free()
	return TestResult.new(
		"the curve maps onto the canvas: in order, inside the axes, peak at the top",
		enough and ascending and spans and peak_at_top,
		"%d points, ascending %s, spans %s, peak (annulus %d) at the top %s"
			% [points.size(), str(ascending), str(spans), peak, str(peak_at_top)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The reference blade with its chord scaled down toward the tip — a planform a builder can draw
## in the room next door, and one the catalog does not contain.
##
## The taper is applied to the CHORD only; scaling the radii would author a different blade rather
## than a tapered one (`test_authored_blade.gd`'s `_scaled_document` makes the same point).
static func _tip_unloaded_document() -> PropellerDocument:
	var catalog := PartsCatalog.load_default()
	var doc := PropellerDocument.from_catalog_prop(catalog.get_part(ReferenceBuild.PROPELLER_ID))
	var shaped := doc.chord.duplicate()
	for i in range(0, shaped.size(), 2):
		var r_frac: float = shaped[i]
		shaped[i + 1] = shaped[i + 1] * lerpf(1.0, TIP_TAPER, clampf(r_frac, 0.0, 1.0))
	doc.chord = shaped
	doc.chord_is_assumed = false
	return doc


## The reference aircraft flying a custom propeller record carrying `doc` inline — the path a
## published blade actually takes (`test_authored_blade.gd`'s `_build_with_scaled_blade`).
static func _build_with_document(doc: PropellerDocument) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	record["part_id"] = "custom_propeller_tip_unloaded_fixture"
	record["name"] = "Tip-unloaded fixture blade"
	record[PropellerDocument.AUTHORED_BLADE_KEY] = doc.to_dictionary()
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		record["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)


## A build that cannot lift itself: the reference aircraft with the heaviest pack in the catalog
## on the smallest motor. Found by search rather than hardcoded, so a catalog edit cannot silently
## turn this fixture into one that hovers and leave the second arm of the operating-point check
## testing the first arm twice.
static func _overloaded_build() -> Build:
	var catalog := PartsCatalog.load_default()
	var heaviest := ""
	var heaviest_g := -1.0
	for pack in catalog.by_category["battery"]:
		# Cells x capacity, because a battery record carries no mass — `BatteryModel` derives it.
		# This is a fixture-picking heuristic, not a mass model, and the check asserts the aircraft
		# really cannot hover rather than trusting it.
		var energy := float(pack["specs"]["cells"]) * float(pack["specs"]["mah"])
		if energy > heaviest_g:
			heaviest_g = energy
			heaviest = str(pack["part_id"])
	var weakest := ""
	var weakest_thrust := INF
	for spec in catalog.by_category["motor"]:
		var lift := float(spec["specs"]["max_thrust_g"])
		if lift < weakest_thrust:
			weakest_thrust = lift
			weakest = str(spec["part_id"])
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, weakest,
		ReferenceBuild.PROPELLER_ID, heaviest, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
