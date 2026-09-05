class_name TestVibrationOverlay
extends RefCounted
## The vibration-path overlay — P10e's third, see
## .superpowers/sdd/2026-09-02-analysis-overlays-design/task-1-brief.md §3.
##
## ## What has to be true for this overlay to be worth drawing
##
## 1. **The two ways of having no pad do not render the same.** `SoftMount.f_n_hz` returns INF for
##    a mount that is not fitted AND for one whose spec the model declined to read, so both draw a
##    flat line at exactly 1.0. Only the words tell a builder which. This is §3.3's rule and it is
##    the first check in the file because it is the one the overlay exists to get right.
##
## 2. **The curve is the model's, sample for sample.** An overlay that wrote out the isolator
##    formula again would be the P10d defect in a new file, and the second copy would be free to
##    drift the moment either changed. Asserted with `==`, not with a tolerance, for
##    `ThrustOverlay`'s reason: if it ever stops being exact the overlay has stopped drawing the
##    model, and the answer is to find out why rather than to loosen the check.
##
## 3. **The pad is not a free win.** Below its own frequency it passes MORE through than no pad at
##    all. A chart that only ever showed attenuation would be an advertisement.
##
## 4. **The hump's height is a band.** It is set by a damping ratio nobody publishes, on the part
##    of the curve an eye goes to first.
##
## 5. **The vertical lines are this aircraft's, at the RPM it is turning.** Rated RPM is the wrong
##    operating point and the difference is a factor a builder cannot see from the picture.
##
## ## What is deliberately NOT checked here
##
## Anything needing the shell in a tree — `tests/run_tests.gd` processes no frames. So the mapping
## is checked through the public pure functions, as `test_campbell_overlay.gd` does, and that the
## toggle shows the Control is left to capture.

## A fitted pad, in metres of compressed thickness. The same 2 mm `tests/test_soft_mount.gd` and
## `tests/test_vibration.gd` use, so three files are arguing about one mount.
const FITTED_MOUNT_M := 0.002

## How close two floats have to be before this file calls them the same frequency.
const HZ_EPSILON := 1e-9


static func run() -> Array:
	var results: Array = []
	results.append(_test_no_pad_and_an_unreadable_pad_do_not_render_alike())
	results.append(_test_the_curve_is_the_models_own_samples())
	results.append(_test_the_pad_amplifies_below_its_own_frequency())
	results.append(_test_the_hump_height_is_drawn_as_a_damping_band())
	results.append(_test_the_lines_are_this_aircraft_at_its_operating_rpm())
	results.append(_test_the_curve_maps_onto_the_canvas())
	results.append(_test_a_build_that_turns_nothing_is_refused())
	return results


# ---------------------------------------------------------------------------
# 1. THE §3.3 RULE
# ---------------------------------------------------------------------------

## A build with no mount and a build whose mount the model declined to read both draw T = 1.0
## everywhere, and are captioned differently — the declined one saying a mount IS fitted and naming
## the reason.
##
## Four clauses, and the shape of them matters. The two "flat at 1.0" clauses assert that the
## physics really is identical, which is what makes the caption the ONLY thing separating the two
## cases and therefore worth a check of its own. The "different" clause alone would be satisfied by
## two arbitrary strings, so the declined caption is also asked to contain the model's own reason
## and to say the mount is fitted — an overlay that captioned it "no soft mount, spec unreadable"
## would pass a difference test while still telling the builder they have a bare frame.
##
## MUTATION that turns this red: make `VibrationOverlay.caption_for_tier` fall through — delete the
## `insufficient_data:` branch so an unreadable pad gets the "no soft mount fitted" caption. That is
## exactly the collapse §3.3 was written about, and it is a one-line simplification that looks like
## tidying.
static func _test_no_pad_and_an_unreadable_pad_do_not_render_alike() -> TestResult:
	var bare := VibrationOverlay.new()
	bare.adopt(ReferenceBuild.build())
	var declined := VibrationOverlay.new()
	declined.adopt(_build_with_unreadable_mount())

	var tiers_ok: bool = bare.tier == "no_mount" \
		and declined.tier.begins_with("insufficient_data:")
	var both_flat: bool = _is_flat_at_unity(bare.transmissibility) \
		and _is_flat_at_unity(declined.transmissibility) \
		and bare.transmissibility.size() > 1 and declined.transmissibility.size() > 1
	var bare_caption := VibrationOverlay.caption_for_tier(bare.tier, bare.mount_f_n_hz)
	var declined_caption := VibrationOverlay.caption_for_tier(
		declined.tier, declined.mount_f_n_hz)
	var different: bool = bare_caption != declined_caption \
		and bare_caption != "" and declined_caption != ""
	var honest: bool = declined_caption.contains("fitted") \
		and declined_caption.contains(declined.tier.trim_prefix("insufficient_data:")) \
		and not declined_caption.begins_with("No soft mount")
	bare.free()
	declined.free()
	return TestResult.new(
		"no pad and a pad the model declined to read are both T = 1 and are captioned differently",
		tiers_ok and both_flat and different and honest,
		"tiers %s (%s), both flat at 1.0 %s, captions differ %s, declined one names the reason %s"
			% [str(tiers_ok), declined_caption, str(both_flat), str(different), str(honest)])


# ---------------------------------------------------------------------------
# 2. One transmissibility, not two
# ---------------------------------------------------------------------------

## Every plotted sample is bit-identical to `VibrationModel.mount_transmissibility` at that
## frequency, on the model `for_build` settles.
##
## `==` rather than a tolerance, deliberately: any difference at all means the overlay is drawing
## something other than the model, and there is no size of difference that is acceptable.
##
## MUTATION that turns this red: scale one line of `VibrationOverlay._sample` —
## `transmissibility.append(model.mount_transmissibility(hz) * 1.0000001)`, the shape of a "nudge
## it so the peak reads nicer" edit that no tolerance-based check would ever catch.
static func _test_the_curve_is_the_models_own_samples() -> TestResult:
	var build := _build_with_mount(FITTED_MOUNT_M)
	var overlay := VibrationOverlay.new()
	overlay.adopt(build)
	var model := VibrationModel.for_build(build)

	var sampled: bool = overlay.freq_hz.size() == VibrationOverlay.SAMPLE_COUNT + 1 \
		and overlay.transmissibility.size() == overlay.freq_hz.size()
	var exact := true
	var worst := 0.0
	for i in overlay.freq_hz.size():
		var expected := model.mount_transmissibility(overlay.freq_hz[i])
		if overlay.transmissibility[i] != expected:
			exact = false
			worst = maxf(worst, absf(overlay.transmissibility[i] - expected))
	# And the axis is not a fixed hertz span: it reaches every excitation line the build has.
	var reaches: bool = true
	for order_name in overlay.excitations:
		reaches = reaches and float(overlay.excitations[order_name]) <= overlay.top_hz() + 1e-9
	var sample_count: int = overlay.freq_hz.size()
	overlay.free()
	return TestResult.new(
		"every plotted sample is the vibration model's own transmissibility, exactly",
		sampled and exact and reaches,
		"%d samples (%s), bit-identical %s (worst gap %s), axis contains every line %s"
			% [sample_count, str(sampled), str(exact), str(worst), str(reaches)])


# ---------------------------------------------------------------------------
# 3. The pad is not a free win
# ---------------------------------------------------------------------------

## Below the mount's own frequency the curve sits ABOVE unity, and well above it the curve sits
## below — and `region_at` names both.
##
## Both directions, because a chart showing only the isolation half would be the sales pitch the
## §3.2 finding exists to contradict. The classification is asked of `region_at` rather than
## re-derived from sqrt(2)·f_n here, so the check is about the function the drawing actually uses.
##
## MUTATION that turns this red: move `region_at`'s threshold to `t > 2.0` — the "a 30% amplification
## isn't worth flagging" edit, which keeps the mode itself amplified and quietly reclassifies the
## shoulder below it as isolation. Observed: this check alone reddens.
##
## The stronger mutation, `return "isolated"` unconditionally, does not compile: `project.godot`
## makes warnings errors and an unused parameter is one. Worth writing down, because a mutation
## that will not build proves nothing about the check.
static func _test_the_pad_amplifies_below_its_own_frequency() -> TestResult:
	var build := _build_with_mount(FITTED_MOUNT_M)
	var overlay := VibrationOverlay.new()
	overlay.adopt(build)
	var model := VibrationModel.for_build(build)
	var f_n := overlay.mount_f_n_hz

	var fitted: bool = is_finite(f_n) and f_n > 0.0 and overlay.tier == "computed"
	var at_mode := model.mount_transmissibility(f_n)
	var below := model.mount_transmissibility(f_n * 0.5)
	var far_above := model.mount_transmissibility(f_n * 4.0)
	var amplifies: bool = at_mode > 1.0 and below > 1.0 \
		and VibrationOverlay.region_at(at_mode) == "amplified" \
		and VibrationOverlay.region_at(below) == "amplified"
	var isolates: bool = far_above < 1.0 \
		and VibrationOverlay.region_at(far_above) == "isolated"
	overlay.free()
	return TestResult.new(
		"the pad amplifies below its own frequency and isolates well above it, and both are named",
		fitted and amplifies and isolates,
		"f_n %.1f Hz (%s): T = %.2f at half, %.2f on the mode, %.3f at 4x — amplifies %s, isolates %s"
			% [f_n, str(fitted), below, at_mode, far_above, str(amplifies), str(isolates)])


# ---------------------------------------------------------------------------
# 4. The height of the hump is a guess, and is drawn as one
# ---------------------------------------------------------------------------

## The band brackets the drawn curve at the peak, its width comes from the published damping range,
## and it INVERTS above the crossover.
##
## The inversion clause is the one with teeth. A band drawn as "the curve, ±some fraction" would
## bracket the peak and pass a bracketing check, while saying something false about the isolation
## region: more damping makes the hump SHORTER and the isolation WORSE, so the two curves must
## swap sides somewhere. That crossover is where the band pinches, and the pinch is the honest part
## of the picture — it is the one feature of the curve the damping guess does not move.
##
## MUTATION that turns this red: set `SoftMount.DAMPING_RATIO_LOW := SoftMount.DEFAULT_DAMPING_RATIO`
## (0.10), collapsing the band to a line on one side — the "the default is fine, one curve is
## simpler" edit. Observed: this check alone reddens; the inversion clause survives on the other
## half of the band, which is what makes the bracketing clause the one doing the work here.
static func _test_the_hump_height_is_drawn_as_a_damping_band() -> TestResult:
	var overlay := VibrationOverlay.new()
	overlay.adopt(_build_with_mount(FITTED_MOUNT_M))

	var peak_index := 0
	for i in overlay.transmissibility.size():
		if overlay.transmissibility[i] > overlay.transmissibility[peak_index]:
			peak_index = i
	var sized: bool = overlay.t_low_damping.size() == overlay.transmissibility.size() \
		and overlay.t_high_damping.size() == overlay.transmissibility.size() \
		and overlay.transmissibility.size() > 2
	var brackets: bool = sized \
		and overlay.t_low_damping[peak_index] > overlay.transmissibility[peak_index] \
		and overlay.t_high_damping[peak_index] < overlay.transmissibility[peak_index]

	# Above the crossover the order reverses: the softly damped pad is the better isolator.
	var last: int = overlay.transmissibility.size() - 1
	var inverts: bool = sized and overlay.t_low_damping[last] < overlay.t_high_damping[last]

	# And the band is the PUBLISHED range, not a width this file invented.
	var model := VibrationModel.for_build(_build_with_mount(FITTED_MOUNT_M))
	var from_range: bool = sized \
		and overlay.t_low_damping[peak_index] == model.mount_transmissibility_at(
			overlay.freq_hz[peak_index], SoftMount.DAMPING_RATIO_LOW) \
		and SoftMount.DAMPING_RATIO_LOW < SoftMount.DEFAULT_DAMPING_RATIO \
		and SoftMount.DAMPING_RATIO_HIGH > SoftMount.DEFAULT_DAMPING_RATIO
	var peak_nominal: float = overlay.transmissibility[peak_index] if sized else 0.0
	var peak_low: float = overlay.t_low_damping[peak_index] if sized else 0.0
	var peak_high: float = overlay.t_high_damping[peak_index] if sized else 0.0
	overlay.free()
	return TestResult.new(
		"the hump's height is a band across the published damping range, and it inverts above the crossover",
		sized and brackets and inverts and from_range,
		"peak %.2f inside [%.2f, %.2f] (%s), inverted at the top of the axis %s, from the range %s"
			% [peak_nominal, peak_high, peak_low,
				str(brackets), str(inverts), str(from_range)])


# ---------------------------------------------------------------------------
# 5. The lines are this aircraft's, at the throttle it is at
# ---------------------------------------------------------------------------

## The three vertical lines are `Build.excitation_orders()` evaluated at `Build.operating_rpm()`,
## and fitting a 2-blade prop changes the blade line's order in the fan and no other order.
##
## The operating-point clause is separate from the orders clause on purpose. An overlay drawing the
## right ORDERS at rated RPM would put every line at the same wrong place, in the same proportion,
## and the picture would look entirely correct — the three lines would keep their spacing and only
## their position against the hump, which is the whole question, would be wrong. So the check names
## the rated-RPM answer and rejects it by number.
##
## MUTATION that turns this red: `adopt` reading `build.rated_rpm()` instead of
## `build.operating_rpm()` — the "full throttle is the worst case, draw that" edit, which on the
## reference build moves every line by a factor of about three.
static func _test_the_lines_are_this_aircraft_at_its_operating_rpm() -> TestResult:
	var build := _build_with_mount(FITTED_MOUNT_M)
	var overlay := VibrationOverlay.new()
	overlay.adopt(build)

	var orders := build.excitation_orders()
	var expected := CampbellOverlay.excitation_hz(
		float(orders["blade passing"]), build.operating_rpm())
	var at_rated := CampbellOverlay.excitation_hz(
		float(orders["blade passing"]), build.rated_rpm())
	var named: bool = overlay.excitations.size() == orders.size()
	var at_operating: bool = named \
		and absf(float(overlay.excitations["blade passing"]) - expected) < HZ_EPSILON
	var not_rated: bool = absf(expected - at_rated) > 1.0 \
		and absf(float(overlay.excitations["blade passing"]) - at_rated) > 1.0

	# The blade count changes the SPACING of the fan, and only the blade line's share of it.
	#
	# Compared as ratios rather than as frequencies, and the reason is a finding: a 2-blade prop
	# makes different thrust, so the aircraft hovers at a different RPM and ALL THREE lines move.
	# A check asserting the 1x line stayed put would have been asserting that the operating point
	# is fixed, which is the very thing this overlay must not do. What is invariant is the fan's
	# shape — blade passing is `blades` times the 1x line, and the electrical line is pole pairs
	# times it, on any build at any throttle.
	var two := VibrationOverlay.new()
	two.adopt(_build_with_blades(2))
	var three_ratio: float = float(overlay.excitations["blade passing"]) \
		/ float(overlay.excitations["1x rotation"])
	var two_ratio: float = float(two.excitations["blade passing"]) \
		/ float(two.excitations["1x rotation"])
	var blade_moved: bool = absf(three_ratio - 3.0) < 1e-9 and absf(two_ratio - 2.0) < 1e-9
	var others_still: bool = absf(
		float(two.excitations["motor electrical"]) / float(two.excitations["1x rotation"])
		- float(overlay.excitations["motor electrical"])
			/ float(overlay.excitations["1x rotation"])) < 1e-9
	overlay.free()
	two.free()
	return TestResult.new(
		"the excitation lines are the build's orders at its operating RPM, not at rated",
		named and at_operating and not_rated and blade_moved and others_still,
		"blade passing %.1f Hz at %.0f rpm (rated would be %.1f Hz) — at operating %s, not rated %s, "
			% [expected, build.operating_rpm(), at_rated, str(at_operating), str(not_rated)]
			+ "blade order 3->2 in the fan %s, electrical order unchanged %s"
				% [str(blade_moved), str(others_still)])


# ---------------------------------------------------------------------------
# 6. The mapping onto the canvas
# ---------------------------------------------------------------------------

## Where the curve LANDS, without a window — `ThrustOverlay`'s posture.
##
## The unity line is the clause that matters: this chart is defined by which side of T = 1 a
## harmonic falls on, so unity must be a real y INSIDE the plot rather than clamped to the bottom
## edge. `peak_t()`'s floor of 1.0 is what guarantees that, and a bare frame — whose curve is flat
## at exactly 1.0 — is the case that would clamp without it.
##
## MUTATION that turns this red: drop the `* AXIS_HEADROOM` from `peak_t()` so the axis ends exactly
## at the tallest sample. Predicted, and observed: the bare-frame clause reddens — unity lands ON
## the top edge, where the line the whole chart is read against is indistinguishable from the frame
## — while the fitted-build clauses stay green.
static func _test_the_curve_maps_onto_the_canvas() -> TestResult:
	var overlay := VibrationOverlay.new()
	overlay.adopt(_build_with_mount(FITTED_MOUNT_M))
	overlay.size = Vector2(360, 210)
	var inner_left := VibrationOverlay.MARGIN_PX
	var inner_right: float = 360.0 - VibrationOverlay.MARGIN_PX
	var inner_top := VibrationOverlay.MARGIN_PX
	var inner_bottom: float = 210.0 - VibrationOverlay.MARGIN_PX

	var points := overlay.curve_points(overlay.transmissibility)
	var spans: bool = points.size() == overlay.transmissibility.size() \
		and absf(points[0].x - inner_left) < 1e-9 \
		and absf(points[points.size() - 1].x - inner_right) < 1e-9
	var inside := true
	for p in points:
		inside = inside and p.y >= inner_top - 1e-9 and p.y <= inner_bottom + 1e-9

	var unity_y := overlay.to_pixels(0.0, 1.0).y
	var unity_inside: bool = unity_y > inner_top + 1e-9 and unity_y < inner_bottom - 1e-9

	# A bare frame is flat at exactly 1.0, and unity still has to be a line on the chart rather
	# than the top edge of it.
	var bare := VibrationOverlay.new()
	bare.adopt(ReferenceBuild.build())
	bare.size = Vector2(360, 210)
	var bare_unity := bare.to_pixels(0.0, 1.0).y
	var bare_ok: bool = bare_unity > inner_top + 1e-9 and bare_unity < inner_bottom - 1e-9
	overlay.free()
	bare.free()
	return TestResult.new(
		"the curve spans the axis, stays on the canvas, and unity is a line inside it",
		spans and inside and unity_inside and bare_ok,
		"spans %s, on canvas %s, unity at %.1f px inside %s, flat bare curve's unity at %.1f px %s"
			% [str(spans), str(inside), unity_y, str(unity_inside), bare_unity, str(bare_ok)])


# ---------------------------------------------------------------------------
# 7. A refusal is a refusal
# ---------------------------------------------------------------------------

## A build turning nothing gets words; a real one gets a curve.
##
## The healthy clause is the one with teeth, as in the other two overlays' files: without it the
## check passes for an overlay that refuses everything, which is the stuck-at-no failure this
## project keeps writing down.
##
## MUTATION that turns this red: weaken the guard to `p_operating_rpm >= 0.0`, the plausible "rpm
## is never negative" tightening, which lets a stopped aircraft draw a pad nothing is shaking.
static func _test_a_build_that_turns_nothing_is_refused() -> TestResult:
	var stopped: bool = VibrationOverlay.refusal_for(0.0) != ""
	var turning: bool = VibrationOverlay.refusal_for(8000.0) == ""

	var overlay := VibrationOverlay.new()
	overlay.adopt(null)
	var empty_ok: bool = overlay.refusal != "" and overlay.excitations.is_empty() \
		and overlay.transmissibility.is_empty()
	overlay.adopt(_build_with_mount(FITTED_MOUNT_M))
	var healthy_ok: bool = overlay.refusal == "" and overlay.excitations.size() == 3 \
		and overlay.transmissibility.size() > 2
	overlay.free()
	return TestResult.new(
		"a build that turns nothing is refused in words, and a real one is not",
		stopped and turning and empty_ok and healthy_ok,
		"stopped refused %s, turning allowed %s, no drone refused %s, reference build drawn %s"
			% [str(stopped), str(turning), str(empty_ok), str(healthy_ok)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## True when every sample is exactly one — what BOTH no-pad cases produce, which is why the caption
## is the only thing that separates them.
static func _is_flat_at_unity(values: PackedFloat64Array) -> bool:
	for value in values:
		if value != 1.0:
			return false
	return true


## The reference aircraft with a soft mount fitted, through the assembly tweak a builder sets in
## Lab rather than by poking the model — so the overlay is read the way the shell reads it.
static func _build_with_mount(thickness_m: float) -> Build:
	var build := ReferenceBuild.build()
	build.set_assembly({"soft_mount_m": thickness_m})
	return build


## A mount fitted onto a tip the model cannot weigh — a motor and a prop whose records carry no
## mass, which is `SoftMount.compute`'s `tip_mass_non_positive` and therefore an INF `f_n` from a
## FITTED pad. The §3.3 case, reached the way it would really be reached: through a catalog record
## that is missing a field rather than by writing the tier in by hand.
static func _build_with_unreadable_mount() -> Build:
	var catalog := PartsCatalog.load_default()
	var motor: Dictionary = catalog.get_part(ReferenceBuild.MOTOR_ID).duplicate(true)
	motor["part_id"] = "custom_motor_massless_fixture"
	motor["name"] = "Massless fixture motor"
	motor["mass_g"] = 0.0
	catalog.by_id[motor["part_id"]] = motor
	catalog.by_category["motor"].append(motor)

	var prop: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	prop["part_id"] = "custom_propeller_massless_fixture"
	prop["name"] = "Massless fixture prop"
	prop["mass_g"] = 0.0
	catalog.by_id[prop["part_id"]] = prop
	catalog.by_category["propeller"].append(prop)

	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor["part_id"],
		prop["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	build.set_assembly({"soft_mount_m": FITTED_MOUNT_M})
	return build


## The reference aircraft with a propeller of `blades` blades and everything else identical —
## `test_campbell_overlay.gd`'s fixture, for the same reason: the only thing that can move an order
## is the blade count.
static func _build_with_blades(blades: int) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	record["part_id"] = "custom_propeller_vibration_blade_fixture"
	record["name"] = "Blade-count fixture prop"
	record["specs"]["blades"] = blades
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		record["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	build.set_assembly({"soft_mount_m": FITTED_MOUNT_M})
	return build
