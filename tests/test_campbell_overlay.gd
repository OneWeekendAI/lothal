class_name TestCampbellOverlay
extends RefCounted
## The Campbell overlay — P10e's second, see plans/2026-09-02-analysis-overlays-design.md §2.
##
## ## What has to be true for this overlay to be worth drawing
##
## 1. **The motor line is per POLE PAIR.** A 14-pole motor at 10,000 rpm forces at 1166.67 Hz.
##    Not 2333.33 (poles instead of pole pairs), not 583.33 (a stray half the other way). This is
##    the one number in the overlay that is wrong in a way nobody can see, because all three draw a
##    plausible straight line through the origin, so the check names all three and rejects two by
##    number.
##
##    §2.2 of the design names the per-pole wrong answer as **1400**, and that is an arithmetic
##    slip in the design rather than a third candidate: 14 × 10,000/60 is 2333.33, and 1400 is the
##    per-pole answer at 6,000 rpm. The correct number and the halved-twice one are both right for
##    10,000 rpm, so only the middle one moved. Rejected here at the value the formula actually
##    produces, because a check written against 1400 would have rejected a number no implementation
##    of this can return, and passed the one it exists to catch.
##
## 2. **The orders come from the aircraft.** Swapping a 3-blade prop for a 2-blade one moves the
##    blade-passing line and NOTHING else. That relationship is the overlay's whole claim on §0's
##    bar: it shows a builder which of their choices moved the crossing.
##
## 3. **The resonance is a band, not a hairline.** `VibrationModel.REFERENCE_RESONANCE_HZ` is a
##    guess that this project has twice failed to measure (LTHL-18, LTHL-49). A crisp line at it
##    would claim a precision no part of the model has.
##
## 4. **A crossing the aircraft cannot reach is not marked.** The axis runs to rated RPM; the
##    aircraft stops at whichever of the motor, pack and ESC limits binds first.
##
## ## What is deliberately NOT checked here
##
## Anything needing the shell in a tree — `tests/run_tests.gd` processes no frames, the constraint
## `tests/test_glass_shell.gd` states. So the mapping is checked through the public pure functions,
## as `test_thrust_overlay.gd` does, and that the toggle shows the Control is left to capture.

## The fixture motor for the pole-pair check: 14 poles at 10,000 rpm, the exact case §2.2 of the
## design names. Written here rather than taken from the catalog so the arithmetic is checked
## against a number a reader can do in their head, and so a catalog edit cannot move the oracle.
const FIXTURE_POLES := 14.0
const FIXTURE_RPM := 10000.0

## The right answer, and the two wrong ones. 1166.67 = 7 pole pairs × 10,000/60.
const CORRECT_ELECTRICAL_HZ := 1166.6666666666667
const WRONG_PER_POLE_HZ := 2333.3333333333335
const WRONG_HALVED_TWICE_HZ := 583.3333333333334

## How far apart two frequencies must be before this file will call them different. Tight, because
## every candidate it is separating differs by a factor of two.
const HZ_EPSILON := 1e-9


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_motor_line_is_per_pole_pair())
	results.append(_test_the_orders_come_from_the_aircraft())
	results.append(_test_the_resonance_is_a_band_not_a_hairline())
	results.append(_test_an_unreachable_crossing_is_not_marked())
	results.append(_test_the_diagram_maps_onto_the_canvas())
	results.append(_test_a_build_with_no_rpm_range_is_refused())
	return results


# ---------------------------------------------------------------------------
# 1. The number nobody can see is wrong
# ---------------------------------------------------------------------------

## The motor's electrical excitation is `pole_pairs × rpm/60`, and the two plausible wrong answers
## are named and rejected rather than merely not-asserted.
##
## Three clauses on purpose. "Equals 1166.67" alone would be satisfied by a file that hardcoded
## 1166.67; the two rejections are what make it an assertion about the FORMULA. And the order is
## taken from `Build.excitation_orders()` on a real build rather than from `poles × 0.5` written
## again here — a check that recomputed the halving would pass whatever the build does, which is
## the §1.2 defect wearing a test's clothes.
##
## MUTATION that turns this red: drop the `* 0.5` from `Build.pole_pairs()` — the "poles, surely"
## slip the method's own comment exists to prevent. Predicted: the correct clause and the
## per-pole-rejection clause go red together, the halved-twice rejection stays green.
static func _test_the_motor_line_is_per_pole_pair() -> TestResult:
	var build := _build_with_poles(FIXTURE_POLES)
	var order: float = float(build.excitation_orders()["motor electrical"])
	var hz := CampbellOverlay.excitation_hz(order, FIXTURE_RPM)

	var right: bool = absf(hz - CORRECT_ELECTRICAL_HZ) < HZ_EPSILON
	var not_per_pole: bool = absf(hz - WRONG_PER_POLE_HZ) > HZ_EPSILON
	var not_halved_twice: bool = absf(hz - WRONG_HALVED_TWICE_HZ) > HZ_EPSILON
	return TestResult.new(
		"the motor line is pole PAIRS: 14 poles at 10,000 rpm forces at 1166.67 Hz",
		right and not_per_pole and not_halved_twice,
		"%s Hz (order %s) — right %s, not the per-pole %s %s, not the halved-twice %s %s"
			% [str(hz), str(order), str(right), str(WRONG_PER_POLE_HZ), str(not_per_pole),
				str(WRONG_HALVED_TWICE_HZ), str(not_halved_twice)])


# ---------------------------------------------------------------------------
# 2. The orders are the aircraft's
# ---------------------------------------------------------------------------

## Fitting a 2-blade prop in place of the 3-blade one moves the blade-passing line and leaves the
## other two exactly where they were.
##
## The "leaves the other two" clause is not padding. It is what separates "the orders respond to
## the build" from "everything responds to the build" — an overlay that recomputed all three from
## whatever changed would pass a check that only looked at the line it expected to move.
##
## MUTATION that turns this red: hardcode `"blade passing": 3.0` in `Build.excitation_orders()`,
## the entirely reasonable-looking "quads are tri-blade" simplification, which is right for the
## reference build and wrong for the prop beside it in the catalog.
static func _test_the_orders_come_from_the_aircraft() -> TestResult:
	var three := ReferenceBuild.build()
	var two := _build_with_blades(2)
	var a := three.excitation_orders()
	var b := two.excitation_orders()

	var blades_three: float = float(three.prop_geometry().blades)
	var blades_two: float = float(two.prop_geometry().blades)
	var fixture_ok: bool = blades_three == 3.0 and blades_two == 2.0
	var blade_moved: bool = float(a["blade passing"]) == 3.0 and float(b["blade passing"]) == 2.0
	var others_still: bool = float(a["1x rotation"]) == float(b["1x rotation"]) \
		and float(a["motor electrical"]) == float(b["motor electrical"])
	return TestResult.new(
		"changing the prop moves the blade-passing order and only that one",
		fixture_ok and blade_moved and others_still,
		"blades %s→%s (fixture %s), blade order %s→%s (%s), 1x and electrical unchanged %s"
			% [str(blades_three), str(blades_two), str(fixture_ok),
				str(a["blade passing"]), str(b["blade passing"]), str(blade_moved),
				str(others_still)])


# ---------------------------------------------------------------------------
# 3. The band — the thing §8 said was the most likely way this overlay ships worse than nothing
# ---------------------------------------------------------------------------

## The arm mode renders as a STRIP that brackets the model's number, with a half-width of at least
## 15% of it, and the strip scales with the frequency rather than being a fixed hertz.
##
## The 15% floor is below the 20% the overlay actually uses on purpose: the assertion is "this is
## a band, and a wide one", and a floor equal to the value would turn any future re-derivation of
## the width into a test failure rather than a review. A width shrinking toward a hairline is
## visible in the detail before it reaches the floor.
##
## The scaling clause is the one with teeth. A band written as a fixed ±36 Hz would bracket the
## reference frame and pass everything above; on a 7" build whose mode sits far lower it would be
## a proportionally enormous band, and on a whoop's stubby arms a hairline again. Checking two
## frames whose modes differ says the width is a FRACTION.
##
## MUTATION that turns this red: set `RESONANCE_BAND_FRAC := 0.0` — the hairline §2.4 calls the
## most dangerous drawing in the document, and the shape this ships as if nobody checks.
static func _test_the_resonance_is_a_band_not_a_hairline() -> TestResult:
	var build := ReferenceBuild.build()
	var model := VibrationModel.for_build(build)
	var res := model.resonance_hz
	var band := CampbellOverlay.band_hz(res)

	var brackets: bool = band.size() == 2 and band[0] < res and band[1] > res
	var half_width: float = 0.0 if band.size() != 2 else (band[1] - band[0]) * 0.5
	var wide_enough: bool = half_width >= res * 0.15

	# A second frame, whose mode is somewhere else entirely, to show the width is a fraction.
	var other_res := VibrationModel.resonance_hz_for(0.180, 0.045)
	var other := CampbellOverlay.band_hz(other_res)
	var other_half: float = 0.0 if other.size() != 2 else (other[1] - other[0]) * 0.5
	var proportional: bool = absf(other_half / other_res - half_width / res) < 1e-12 \
		and absf(other_res - res) > 1.0

	# And the wording is not left to a reader's inference.
	var overlay := CampbellOverlay.new()
	overlay.adopt(build)
	var derived_said: bool = overlay.resonance_hz == res
	overlay.free()
	return TestResult.new(
		"the arm mode is drawn as a band around the derived number, not as a hairline on it",
		brackets and wide_enough and proportional and derived_said,
		"%.1f Hz → %.1f-%.1f (half-width %.1f Hz, %.1f%%), brackets %s, wide enough %s, "
			% [res, band[0], band[1], half_width, half_width / res * 100.0,
				str(brackets), str(wide_enough)]
			+ "proportional on a %.1f Hz frame %s, overlay carries it %s"
			% [other_res, str(proportional), str(derived_said)])


# ---------------------------------------------------------------------------
# 4. The flight envelope
# ---------------------------------------------------------------------------

## A crossing beyond what the aircraft can actually turn is NOT marked, and one inside it is.
##
## Both clauses, because a check that only asserted the refusal would pass an overlay that marked
## nothing at all — which is the failure mode this project keeps writing down: a stuck-at-no
## refusal that satisfies every test about refusing.
##
## Driven through the pure function with explicit frequencies rather than through a build, because
## the reference build's own crossings all sit comfortably inside its envelope and a fixture built
## to put one outside would be testing the fixture. The envelope itself is asserted separately
## below: `reachable_rpm` must be a real RPM at or under rated.
##
## MUTATION that turns this red: delete the `at > p_reachable_rpm` clause from
## `CampbellOverlay.markable_crossing_rpm`, which is the "the axis already stops at rated, this is
## belt and braces" simplification. Predicted: the unreachable clause reddens, the reachable one
## and the envelope clause stay green.
static func _test_an_unreachable_crossing_is_not_marked() -> TestResult:
	var build := ReferenceBuild.build()
	var reach := build.reachable_rpm()
	var envelope_ok: bool = reach > 0.0 and reach <= build.rated_rpm()

	# 1x rotation crosses a mode at exactly that mode's frequency in rev/s: 60 Hz → 3600 rpm.
	var inside := CampbellOverlay.markable_crossing_rpm(1.0, 60.0, 3600.0)
	var outside := CampbellOverlay.markable_crossing_rpm(1.0, 60.0, 3599.0)
	var inside_ok: bool = absf(inside - 3600.0) < 1e-9
	var outside_ok: bool = outside < 0.0

	# And the no-pad case: a resonance at INF is never crossed, at any throttle.
	var no_pad := CampbellOverlay.markable_crossing_rpm(1.0, INF, 3600.0)
	var no_pad_ok: bool = no_pad < 0.0
	return TestResult.new(
		"a crossing the aircraft cannot reach is not marked, and one it can is",
		envelope_ok and inside_ok and outside_ok and no_pad_ok,
		"envelope %.0f of %.0f rated (%s), crossing at 3600 marked %s, "
			% [reach, build.rated_rpm(), str(envelope_ok), str(inside_ok)]
			+ "the same crossing past a 3599 rpm limit dropped %s, no pad dropped %s"
			% [str(outside_ok), str(no_pad_ok)])


# ---------------------------------------------------------------------------
# 5. The mapping onto the canvas
# ---------------------------------------------------------------------------

## Where the lines LAND, without a window — `ThrustOverlay`'s posture.
##
## Every excitation line starts at the origin corner; the STEEPEST one — the motor's, on any real
## build — reaches the top-right corner exactly, because the frequency axis is fitted to the
## diagram's own tallest line; and a shallower order lands below it at the same x. The last clause
## is what makes the fan a fan: three lines that all reached the top would be three lines
## normalised individually, each drawn on its own axis, which is the way this kind of chart most
## commonly lies.
##
## MUTATION that turns this red: make `peak_hz()` fit to the 1× order instead of the maximum
## (`top = maxf(top, excitation_hz(1.0, rated_rpm))`). Predicted: the corner clause reddens
## because the electrical line clamps to the top long before the right-hand edge, and the ordering
## clause reddens with it because all three lines clamp to the same y.
static func _test_the_diagram_maps_onto_the_canvas() -> TestResult:
	var overlay := CampbellOverlay.new()
	overlay.adopt(ReferenceBuild.build())
	overlay.size = Vector2(360, 210)
	var inner_left := CampbellOverlay.MARGIN_PX
	var inner_right: float = 360.0 - CampbellOverlay.MARGIN_PX
	var inner_top := CampbellOverlay.MARGIN_PX
	var inner_bottom: float = 210.0 - CampbellOverlay.MARGIN_PX

	var steepest := 0.0
	for order_name in overlay.orders:
		steepest = maxf(steepest, float(overlay.orders[order_name]))
	var steep_points := overlay.line_points(steepest)
	var slow_points := overlay.line_points(1.0)

	var from_origin: bool = steep_points.size() == 2 and slow_points.size() == 2 \
		and absf(steep_points[0].x - inner_left) < 1e-9 \
		and absf(steep_points[0].y - inner_bottom) < 1e-9
	var corner: bool = steep_points.size() == 2 \
		and absf(steep_points[1].x - inner_right) < 1e-9 \
		and absf(steep_points[1].y - inner_top) < 1e-9
	var ordered: bool = steep_points.size() == 2 and slow_points.size() == 2 \
		and slow_points[1].y > steep_points[1].y + 1.0

	# The hover line has to sit inside the axis it is drawn on, or it is a claim about an RPM the
	# diagram does not show.
	var hover_x := overlay.to_pixels(overlay.hover_rpm, 0.0).x
	var hover_ok: bool = hover_x > inner_left and hover_x < inner_right
	overlay.free()
	return TestResult.new(
		"the fan maps onto the canvas: from the origin, steepest into the corner, in order",
		from_origin and corner and ordered and hover_ok,
		"steepest order %s, from origin %s, reaches the corner %s, 1x below it %s, hover at %.1f px %s"
			% [str(steepest), str(from_origin), str(corner), str(ordered), hover_x, str(hover_ok)])


# ---------------------------------------------------------------------------
# 6. A refusal is a refusal
# ---------------------------------------------------------------------------

## A build with no RPM range gets words, not empty axes with a hover line on them.
##
## The healthy clause is the one with teeth, as in `test_thrust_overlay.gd`: without it the check
## passes for an overlay that refuses everything. The rule is asked for by name rather than
## restated, so a change to what counts as unplottable is checked where it lives.
##
## MUTATION that turns this red: weaken the guard to `p_rated_rpm < 0.0`, the plausible "rpm is
## never negative anyway" tightening, which lets a stopped build draw a diagram whose every line
## is a point at the origin.
static func _test_a_build_with_no_rpm_range_is_refused() -> TestResult:
	var orders := ReferenceBuild.build().excitation_orders()
	var stopped: bool = CampbellOverlay.refusal_for(orders, 0.0) != ""
	var no_orders: bool = CampbellOverlay.refusal_for({}, 29000.0) != ""

	var overlay := CampbellOverlay.new()
	overlay.adopt(null)
	var empty_ok: bool = overlay.refusal != "" and overlay.orders.is_empty()
	overlay.adopt(ReferenceBuild.build())
	var healthy_ok: bool = overlay.refusal == "" and overlay.orders.size() == 3 \
		and overlay.rated_rpm > 0.0
	overlay.free()
	return TestResult.new(
		"a build with nothing to sweep is refused in words, and a real one is not",
		stopped and no_orders and empty_ok and healthy_ok,
		"stopped refused %s, orderless refused %s, no drone refused %s, reference build drawn %s"
			% [str(stopped), str(no_orders), str(empty_ok), str(healthy_ok)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The reference aircraft with a motor record carrying `poles` poles — the 14-pole case §2.2
## names. A copied record rather than a catalog search, so the oracle is 14 whatever the catalog
## happens to stock.
static func _build_with_poles(poles: float) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.MOTOR_ID).duplicate(true)
	record["part_id"] = "custom_motor_pole_fixture"
	record["name"] = "Pole-count fixture motor"
	record["specs"]["poles"] = poles
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["motor"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, record["part_id"],
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)


## The reference aircraft with a propeller record of `blades` blades, everything else identical.
## Same disc, same pitch — so the only thing that can move an order is the blade count.
static func _build_with_blades(blades: int) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	record["part_id"] = "custom_propeller_blade_count_fixture"
	record["name"] = "Blade-count fixture prop"
	record["specs"]["blades"] = blades
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		record["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
