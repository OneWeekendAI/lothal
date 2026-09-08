class_name TestPropDiscOverlay
extends RefCounted
## The prop-disc overlay — P10e's fifth, see plans/2026-09-02-analysis-overlays-design.md §5.
##
## ## What has to be true for this overlay to be worth drawing
##
## §5.2's argument is that both facts here are ALREADY checked — `PropGuard.clearance_check`
## exists, `AirframeModel.footprint_prop_clearance_m` exists — and that geometry is the one domain
## where a picture beats the sentence those checks produce. That makes the bar unusually clear: it
## must be the same geometry. A plan view drawn from its own idea of where a motor sits would be
## a picture disagreeing with the warning printed beside it, and the picture would win.
##
## 1. **The discs are the model's discs.** Centres from `MotorLayout.motor_position`, which is the
##    table the physics reads and `footprint_prop_clearance_m` measures against; radius from the
##    fitted propeller's own diameter.
##
## 2. **A plan view must not shade a 2D overlap as a 3D collision.** §5.3, and it is the one thing
##    §7 says whoever builds this must not get wrong. Props on a stretched-X sit at different
##    heights; discs that overlap on this canvas may not overlap in space. The overlay may say the
##    discs overlap in plan. It may not say the props hit.
##
## 3. **A guard the model refuses is a refusal, not an absent guard.** `PropGuard.tip_clearance_mm`
##    returns NAN for a spec `compute()` declined, and NAN drawn as "no guard fitted" would
##    attribute to a builder a choice they did not make — the failure `VibrationOverlay` found on
##    the pad, in the same shape one part over.

## The propeller the overlap fixture fits: a 7" blade on a frame laid out for 5". The overlap is
## then 22 mm of interference between adjacent discs rather than a rounding-width touch, so the
## check is about the sign of a real number and not about a tie-break.
const OVERSIZED_PROP_ID := "prop_7x4x3"

## The guard the reference frame is authored for. Its bore is `outer − wall` = 69 mm against a
## 63.5 mm tip: the 5.5 mm the catalog entry's own `source` line quotes.
const REFERENCE_GUARD_ID := "guard_bumper_5in_abs"

## What that guard's bore leaves around the tip, in millimetres. Not a new number — it is
## `PropGuard.tip_clearance_mm`'s answer, pinned here so a change to either the ring or the prop
## has to be acknowledged rather than absorbed.
const REFERENCE_TIP_CLEARANCE_MM := 5.5


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_discs_are_the_layouts_discs())
	results.append(_test_the_gap_is_the_one_the_clearance_check_measures())
	results.append(_test_an_oversized_prop_overlaps_and_the_reference_build_does_not())
	results.append(_test_a_plan_overlap_is_never_reported_as_a_collision())
	results.append(_test_a_fitted_guard_draws_its_bore_at_the_clearance_the_model_states())
	results.append(_test_a_refused_guard_is_a_refusal_rather_than_no_guard())
	results.append(_test_no_drone_is_a_refusal_rather_than_an_empty_plan())
	results.append(_test_the_plan_maps_onto_the_canvas())
	return results


# ---------------------------------------------------------------------------
# 1. The discs are the model's discs
# ---------------------------------------------------------------------------

## Four centres, each bit-identical to `MotorLayout.motor_position(name, arm_m)` projected into
## XZ, and a radius that is the fitted prop's own.
##
## `==` rather than a tolerance for `ThrustOverlay.total_n`'s reason: the overlay applies no
## arithmetic to a motor position, so anything but bit-identity means a second definition of where
## a motor sits has appeared — the defect `AirframeModel.guard_ring_polygons_m` was corrected for
## during P10c, where four rings all came back on the aircraft's centre and the test could not see
## it because it measured against the same wrong frame.
##
## MUTATION that turns this red: build the centres from `arm_m * cos(PI/4)` inline instead of
## calling `MotorLayout.motor_position` — the same arithmetic, restated, which is exactly the copy
## this clause exists to forbid. Verified by flipping the Z sign in that copy: 4 centres wrong,
## and it is the front/rear mirror that a symmetric X-quad's picture cannot show.
static func _test_the_discs_are_the_layouts_discs() -> TestResult:
	var build := ReferenceBuild.build()
	var overlay := PropDiscOverlay.new()
	overlay.adopt(build)

	var all_exact := true
	var checked := 0
	for motor_name in MotorLayout.MOTOR_NAMES:
		var hub := MotorLayout.motor_position(motor_name, build.arm_m)
		var drawn: Vector2 = overlay.disc_centres_m.get(motor_name, Vector2.INF)
		if drawn.x != hub.x or drawn.y != hub.z:
			all_exact = false
		checked += 1
	var radius_right: bool = overlay.radius_m == float(build.prop_geometry().diameter_m) * 0.5
	var radius := overlay.radius_m
	overlay.free()
	return TestResult.new(
		"the four discs sit on MotorLayout's own hubs, at the fitted prop's own radius",
		all_exact and radius_right and checked == 4,
		"%d centres, all exact %s, radius %.4f m" % [checked, str(all_exact), radius])


# ---------------------------------------------------------------------------
# 2. The gap is the clearance check's gap
# ---------------------------------------------------------------------------

## `narrowest_disc_gap_m` against the same measurement `AirframeModel.footprint_prop_clearance_m`
## makes — hub separation minus two radii, over every unordered pair.
##
## The narrowest pair on an X-quad is an ADJACENT one, not a diagonal, and that is worth pinning
## because a loop written over `MOTOR_NAMES` in order visits M1-M2 first and could stop there. So
## the check asserts the value AND that the diagonal is the looser of the two, which no
## single-pair implementation satisfies.
##
## MUTATION that turns this red: subtract one radius instead of two. Verified: 0.0286 m becomes
## 0.0921 m, and the reference build's adjacent props would be reported clear by three times the
## gap they have.
static func _test_the_gap_is_the_one_the_clearance_check_measures() -> TestResult:
	var build := ReferenceBuild.build()
	var overlay := PropDiscOverlay.new()
	overlay.adopt(build)

	var a := MotorLayout.motor_position("M1", build.arm_m)
	var b := MotorLayout.motor_position("M2", build.arm_m)
	var d := MotorLayout.motor_position("M4", build.arm_m)
	var radius: float = float(build.prop_geometry().diameter_m) * 0.5
	var adjacent: float = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) - radius * 2.0
	var diagonal: float = Vector2(a.x, a.z).distance_to(Vector2(d.x, d.z)) - radius * 2.0

	var narrowest := overlay.narrowest_disc_gap_m()
	var matches: bool = is_equal_approx(narrowest, adjacent)
	var adjacent_is_tighter: bool = adjacent < diagonal
	overlay.free()
	return TestResult.new(
		"the narrowest disc gap is the adjacent pair's, hub separation less two radii",
		matches and adjacent_is_tighter,
		"narrowest %.4f m, adjacent %.4f m, diagonal %.4f m" % [narrowest, adjacent, diagonal])


# ---------------------------------------------------------------------------
# 3. An overlap is found, and a build that does not overlap is not
# ---------------------------------------------------------------------------

## §5.2's whole example: "a builder who fits a 5.1" prop on a frame laid out for 5" gets a
## sentence today and would get two visibly overlapping circles here".
##
## Both directions, because either alone is satisfiable by a constant. An implementation that
## always reports overlap passes the first clause; one that never does passes the second.
##
## MUTATION that turns this red: `return gap < -1.0` instead of `gap < 0.0` — a "tolerance" on an
## overlap, which reads as prudence and means a 7" prop on a 5" frame is drawn as clear.
static func _test_an_oversized_prop_overlaps_and_the_reference_build_does_not() -> TestResult:
	var clear := PropDiscOverlay.new()
	clear.adopt(ReferenceBuild.build())
	var reference_clear: bool = clear.overlapping_pairs().is_empty()
	var reference_gap := clear.narrowest_disc_gap_m()
	clear.free()

	var fouled := PropDiscOverlay.new()
	fouled.adopt(_build_with_prop(OVERSIZED_PROP_ID))
	var pairs: Array = fouled.overlapping_pairs()
	var fouled_gap := fouled.narrowest_disc_gap_m()
	# All four adjacent pairs foul on a symmetric quad; the diagonals stay clear.
	var four_pairs: bool = pairs.size() == 4
	fouled.free()

	return TestResult.new(
		"a 7\" prop on a 5\" layout overlaps on all four adjacent pairs, and the 5\" one does not",
		reference_clear and four_pairs and fouled_gap < 0.0,
		"reference gap %.4f m (clear %s), oversized gap %.4f m, pairs %s" % [
			reference_gap, str(reference_clear), fouled_gap, str(pairs)])


# ---------------------------------------------------------------------------
# 4. The honesty rule
# ---------------------------------------------------------------------------

## §5.3, and §7's "the one thing whoever builds it must not get wrong": **it must not shade an
## overlap as a collision.**
##
## Two clauses, and they are two because they fail differently. The first is POSITIVE — the
## verdict for an overlap has to name the limitation, so a builder reading it knows what has and
## has not been checked. The second is a prohibition on the words that would make it a claim about
## three dimensions: this overlay compares no heights, so it cannot say the props meet.
##
## The prohibition is a word test and that is the honest form for it. The failure §5.3 describes
## is not an arithmetic error — the arithmetic is right, the plan gap really is negative — it is
## the SENTENCE printed over it. There is nothing else to assert.
##
## MUTATION that turns this red: return "the propellers collide" for a negative gap. Verified:
## both clauses go red, since it also drops the qualification.
static func _test_a_plan_overlap_is_never_reported_as_a_collision() -> TestResult:
	var overlap := PropDiscOverlay.verdict_for(-0.0222)
	var clear := PropDiscOverlay.verdict_for(0.0286)
	var qualified: bool = overlap.to_lower().contains("plan") and overlap.to_lower().contains("height")
	var forbidden := ["collide", "collision", "strike", "hit", "will touch"]
	var claims_contact := false
	for word in forbidden:
		if overlap.to_lower().contains(word) or clear.to_lower().contains(word):
			claims_contact = true
	var distinct: bool = overlap != clear
	return TestResult.new(
		"a plan-view overlap is qualified as one, and never called a collision",
		qualified and not claims_contact and distinct,
		"overlap \"%s\", clear \"%s\"" % [overlap, clear])


# ---------------------------------------------------------------------------
# 5. The guard's bore
# ---------------------------------------------------------------------------

## The ring around each disc is `PropGuard.tip_clearance_mm`'s own answer, and the bore radius it
## is drawn at is the tip radius plus that clearance.
##
## Read back through the clearance rather than through `outer − wall` deliberately: that is the
## sum P10c's `GuardMesh` was corrected to take, after a test measured the ring against the same
## wrong expression it drew it with. One definition of where the bore is, here as there.
##
## MUTATION that turns this red: draw the bore at `outer_radius_mm` — the ring's OUTSIDE, the
## exact slip P10c found, which on this guard puts the bore 3 mm out and reports 8.5 mm of tip
## clearance where the model states 5.5.
static func _test_a_fitted_guard_draws_its_bore_at_the_clearance_the_model_states() -> TestResult:
	var build := _build_with_guard(REFERENCE_GUARD_ID)
	var overlay := PropDiscOverlay.new()
	overlay.adopt(build)

	var stated: float = PropGuard.tip_clearance_mm(build.guard["specs"], overlay.radius_m * 1000.0)
	var drawn_mm := overlay.tip_to_guard_mm()
	var matches_model: bool = drawn_mm == stated
	var matches_catalog: bool = is_equal_approx(drawn_mm, REFERENCE_TIP_CLEARANCE_MM)
	var bore_follows: bool = is_equal_approx(overlay.guard_bore_radius_m,
		overlay.radius_m + stated * 0.001)
	var state := overlay.guard_state
	var bore := overlay.guard_bore_radius_m
	overlay.free()
	return TestResult.new(
		"a fitted guard's bore is the tip plus the clearance PropGuard states",
		state == PropDiscOverlay.GUARD_FITTED and matches_model and matches_catalog and bore_follows,
		"state %s, clearance %.4f mm (catalog 5.5), bore %.4f m vs tip %.4f m" % [
			state, drawn_mm, bore, bore - stated * 0.001])


# ---------------------------------------------------------------------------
# 6. A refused guard is not an absent guard
# ---------------------------------------------------------------------------

## §5.3's second paragraph. `PropGuard.compute` declines a spec it cannot read and
## `tip_clearance_mm` returns NAN; drawing NAN as "no ring" says the builder fitted nothing, when
## what happened is that they fitted something Lothal could not read.
##
## Three states, and the check needs all three, because the bug is that two of them collapse into
## one. A build with no guard and a build with an unreadable guard both have no ring to draw; only
## the state says why.
##
## MUTATION that turns this red: `guard_state = GUARD_NONE` whenever the clearance is NAN — the
## natural one-liner, and the whole defect.
static func _test_a_refused_guard_is_a_refusal_rather_than_no_guard() -> TestResult:
	var none := PropDiscOverlay.new()
	none.adopt(ReferenceBuild.build())
	var none_state: String = none.guard_state
	var none_bore := none.guard_bore_radius_m
	none.free()

	var fitted := PropDiscOverlay.new()
	fitted.adopt(_build_with_guard(REFERENCE_GUARD_ID))
	var fitted_state: String = fitted.guard_state
	fitted.free()

	var refused := PropDiscOverlay.new()
	refused.adopt(_build_with_unreadable_guard())
	var refused_state: String = refused.guard_state
	var refused_bore := refused.guard_bore_radius_m
	var reason: String = refused.guard_reason
	refused.free()

	var three_states: bool = none_state == PropDiscOverlay.GUARD_NONE \
		and fitted_state == PropDiscOverlay.GUARD_FITTED \
		and refused_state == PropDiscOverlay.GUARD_REFUSED
	# Both have nothing to draw, which is what makes the state the only thing telling them apart.
	var both_boreless: bool = is_nan(none_bore) and is_nan(refused_bore)
	return TestResult.new(
		"a guard the model cannot read is a refusal, not an absent guard",
		three_states and both_boreless and reason != "",
		"none %s, fitted %s, refused %s (\"%s\"), both boreless %s" % [
			none_state, fitted_state, refused_state, reason, str(both_boreless)])


# ---------------------------------------------------------------------------
# 7. No drone
# ---------------------------------------------------------------------------

## The empty state, the same door the other four overlays are handed a null through.
##
## MUTATION that turns this red: `refusal = ""` on the null branch.
static func _test_no_drone_is_a_refusal_rather_than_an_empty_plan() -> TestResult:
	var overlay := PropDiscOverlay.new()
	overlay.adopt(null)
	var refused: bool = overlay.refusal != ""
	var no_discs: bool = overlay.disc_centres_m.is_empty()
	var words := overlay.refusal
	overlay.free()
	return TestResult.new(
		"no drone open is a refusal, not a plan view of nothing",
		refused and no_discs,
		"refusal \"%s\", discs empty %s" % [words, str(no_discs)])


# ---------------------------------------------------------------------------
# 8. The mapping
# ---------------------------------------------------------------------------

## The plan is SQUARE on the canvas, and that is the whole check.
##
## Every other overlay in P10e fits its Y axis to its own content, because each plots a quantity
## against a different quantity and the aspect ratio means nothing. This one plots metres against
## metres. A disc drawn on independently fitted axes is an ellipse, and an ellipse is a picture of
## a propeller that does not exist — the one way a geometry overlay can lie without getting a
## number wrong.
##
## Three clauses: the aircraft's centre lands at the canvas centre, a metre across maps to the same
## pixels as a metre along, and the outermost disc edge stays inside the plot.
##
## MUTATION that turns this red: scale x by `inner.size.x / span` and y by `inner.size.y / span`
## — independent fits, which on the 360x210 panel this ships in squashes every disc by 0.49.
static func _test_the_plan_maps_onto_the_canvas() -> TestResult:
	var overlay := PropDiscOverlay.new()
	overlay.adopt(ReferenceBuild.build())
	overlay.size = Vector2(360.0, 210.0)

	var centre := overlay.to_pixels(Vector2.ZERO)
	var one_across := overlay.to_pixels(Vector2(0.05, 0.0)) - centre
	var one_along := overlay.to_pixels(Vector2(0.0, 0.05)) - centre
	var square: bool = is_equal_approx(absf(one_across.x), absf(one_along.y))
	var centred: bool = is_equal_approx(centre.x, 180.0) and is_equal_approx(centre.y, 105.0)

	var inside := true
	for motor_name in overlay.disc_centres_m:
		var at: Vector2 = overlay.to_pixels(overlay.disc_centres_m[motor_name])
		var edge: float = absf(one_across.x) * (overlay.radius_m / 0.05)
		if at.y - edge < PropDiscOverlay.MARGIN_PX - 0.001 \
				or at.y + edge > 210.0 - PropDiscOverlay.MARGIN_PX + 0.001:
			inside = false
	overlay.free()
	return TestResult.new(
		"the plan is square on the canvas and the whole aircraft fits inside the plot",
		square and centred and inside,
		"centre %s, 50 mm across %.4f px, along %.4f px, all discs inside %s" % [
			str(centre), one_across.x, one_along.y, str(inside)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _build_with_prop(prop_id: String) -> Build:
	var catalog := PartsCatalog.load_default()
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		prop_id, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)


static func _build_with_guard(guard_id: String) -> Build:
	var catalog := PartsCatalog.load_default()
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, guard_id)


## The reference guard with its wall removed, which `PropGuard.compute` declines outright
## ("wall_non_positive") rather than treating as a zero-thickness ring. A guard that IS fitted and
## that the model cannot read — the state §5.3 says must not render as no guard.
static func _build_with_unreadable_guard() -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(REFERENCE_GUARD_ID).duplicate(true)
	record["part_id"] = "guard_unreadable_fixture"
	record["name"] = "Guard with no wall (fixture)"
	record["specs"]["wall_mm"] = 0.0
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["guard"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, record["part_id"])
