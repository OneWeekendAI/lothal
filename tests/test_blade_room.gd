class_name TestBladeRoom
extends RefCounted
## The two views the Propulsion room gained: `BladeView3D`'s camera and `BladeAeroPanel`'s mapping.
##
## ## What can be checked here and what cannot
##
## Neither view can be BUILT in this runner. `BladeView3D` fills its SubViewport in `_ready`,
## because a SubViewport has no World3D until it enters a tree, and `tests/run_tests.gd` processes
## no frames — the same constraint `test_glass_shell.gd` states about the shell and
## `test_thrust_overlay.gd` about the overlays. So what is asserted here is everything that is
## arithmetic: where the camera sits for a named view, where a curve lands in the plot, which
## stretches get shaded. That the viewport renders is left to the capture tooling, and this
## paragraph exists so that limit is stated rather than implied.
##
## ## What has to be true
##
## 1. **The named views are the views they are named after.** "Top" must look down the shaft and
##    "front" must lie in the disc plane, or the buttons are decoration and two blades cannot be
##    compared from the same angle.
## 2. **The camera frames the blade at any size.** A 2" whoop blade and a 9" cinelifter blade must
##    fill the frame equally, which is what makes the view a comparison rather than a picture.
## 3. **The plot maps the solve onto the canvas.** Points inside the axes land inside the plot
##    rectangle, and the r/R axis runs the same way as the planform editor above it.
## 4. **The panel refuses when the model refuses.** A refusal must produce no curve at all rather
##    than a flat line at zero incidence.

## A whoop blade and a cinelifter blade, in metres of radius — the extremes the framing check runs
## across. Chosen at the ends of what the catalog holds, because a framing rule that only works at
## 5" is a rule that fails the moment somebody opens the room on anything else.
const SMALL_RADIUS_M := 0.0195
const LARGE_RADIUS_M := 0.1143

const TEST_RPM := 18000.0


static func run() -> Array:
	var results: Array = []
	results.append(_test_top_looks_down_the_shaft())
	results.append(_test_front_and_side_lie_in_the_disc_plane())
	results.append(_test_the_camera_frames_every_blade_the_same())
	results.append(_test_the_camera_never_loses_its_up_vector())
	results.append(_test_the_camera_points_at_the_blade())
	results.append(_test_the_alpha_curve_lands_inside_the_plot())
	results.append(_test_the_radius_axis_runs_the_same_way_as_the_planform())
	results.append(_test_a_refusal_draws_no_curve())
	results.append(_test_the_shaded_bands_match_the_stalled_radii())
	return results


static func _panel(verdict: Dictionary, radius_m: float) -> BladeAeroPanel:
	var panel := BladeAeroPanel.new()
	panel.size = Vector2(300, 220)
	panel.show_verdict(verdict, radius_m)
	return panel


static func _reference_verdict() -> Dictionary:
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	return BladeAero.analyse(doc, TEST_RPM)


# ---------------------------------------------------------------------------
# 1. The named views
# ---------------------------------------------------------------------------

## "Top" puts the camera on the shaft axis, above the disc: its horizontal offset must be a
## vanishing fraction of its height.
##
## Not asserted as exactly zero, because the pose stops a fifth of a degree short of the pole on
## purpose — at exactly ±π/2 the up vector is parallel to the view direction and `looking_at` has
## no basis to build. The tolerance is that deliberate gap and no more.
##
## MUTATION that turns this red: swap the y and z terms in `camera_position`. Every view still
## produces a valid transform at a correct distance, and "top" quietly becomes a side view — which
## on a symmetric blade at a glance looks like a rendering difference rather than a wrong camera.
static func _test_top_looks_down_the_shaft() -> TestResult:
	var eye := BladeView3D.camera_position(
		BladeView3D.VIEWS["top"].x, BladeView3D.VIEWS["top"].y, 1.0)
	var horizontal := Vector2(eye.x, eye.z).length()
	return TestResult.new(
		"the top view looks down the shaft",
		eye.y > 0.99 and horizontal < 0.02,
		"eye %s, horizontal offset %.4f" % [str(eye), horizontal])


## "Front" and "side" lie in the disc plane — zero height — and are a quarter turn apart, which is
## what makes them two views rather than one.
static func _test_front_and_side_lie_in_the_disc_plane() -> TestResult:
	var front := BladeView3D.camera_position(
		BladeView3D.VIEWS["front"].x, BladeView3D.VIEWS["front"].y, 1.0)
	var side := BladeView3D.camera_position(
		BladeView3D.VIEWS["side"].x, BladeView3D.VIEWS["side"].y, 1.0)
	var flat: bool = absf(front.y) < 1e-6 and absf(side.y) < 1e-6
	var quarter_turn: bool = absf(front.normalized().dot(side.normalized())) < 1e-3
	return TestResult.new(
		"front and side lie in the disc plane, a quarter turn apart",
		flat and quarter_turn,
		"front %s, side %s" % [str(front), str(side)])


## The camera's distance is the same multiple of radius for a whoop blade and a cinelifter blade,
## so both fill the frame identically.
##
## MUTATION that turns this red: make `DISTANCE_TO_RADIUS` a distance in metres instead of a
## multiple. The 5" reference blade still frames perfectly — it is what such a constant would be
## tuned on — and a 1.5" whoop blade becomes a dot while a 9" blade overflows the viewport.
static func _test_the_camera_frames_every_blade_the_same() -> TestResult:
	var small := BladeView3D.camera_transform(0.5, 0.4, SMALL_RADIUS_M)
	var large := BladeView3D.camera_transform(0.5, 0.4, LARGE_RADIUS_M)
	var small_ratio := small.origin.length() / SMALL_RADIUS_M
	var large_ratio := large.origin.length() / LARGE_RADIUS_M
	return TestResult.new(
		"a whoop blade and a cinelifter blade are framed at the same multiple of radius",
		absf(small_ratio - large_ratio) < 1e-6
			and absf(small_ratio - BladeView3D.DISTANCE_TO_RADIUS) < 1e-6,
		"%.3f R and %.3f R" % [small_ratio, large_ratio])


## Every reachable pitch produces a transform with an orthonormal basis — including the poles,
## which is where `looking_at` degenerates.
##
## The sweep runs PAST the clamp on both sides, because the clamp is the thing under test: an
## unclamped pitch reaching exactly ±π/2 produces a basis with a zero determinant, and Godot
## reports that as an error and hands back an identity transform — a camera at the origin, inside
## the hub, which renders as a black frame with nothing to say why.
##
## MUTATION that turns this red: drop the clamp in `camera_position`. Only the poles fail, and only
## the two view buttons that reach them, so any check sampling a handful of ordinary angles passes.
static func _test_the_camera_never_loses_its_up_vector() -> TestResult:
	var worst := 0.0
	var samples := 0
	for i in range(-30, 31):
		var pitch := (float(i) / 30.0) * (PI * 0.5 + 0.2)
		var xform := BladeView3D.camera_transform(0.3, pitch, 0.0645)
		var basis := xform.basis
		worst = maxf(worst, absf(basis.determinant() - 1.0))
		samples += 1
	return TestResult.new(
		"every reachable pitch, including past the poles, keeps an orthonormal camera basis",
		samples == 61 and worst < 1e-5,
		"%d poses, worst determinant error %s" % [samples, str(worst)])


## The camera LOOKS at the hub, from wherever it sits.
##
## Godot's camera looks down its own -Z, so the check is that -Z, at every pose, points from the
## camera's position back toward the origin.
##
## This test exists because its absence shipped a blank viewport. The suite already asserted that
## the camera sat in the right place with an orthonormal basis, and
## `looking_at(target, up, use_model_front = true)` — which aims +Z at the target instead of -Z —
## satisfies both of those perfectly while pointing the camera at the empty space behind it. Where
## a camera sits and where it looks are two facts, and only one of them was being checked.
##
## MUTATION that turns this red: restore the `true` third argument to `looking_at`. Nothing else in
## this file moves.
static func _test_the_camera_points_at_the_blade() -> TestResult:
	var worst := 0.0
	var samples := 0
	for view_id in BladeView3D.VIEWS.keys():
		var pose: Vector2 = BladeView3D.VIEWS[view_id]
		var xform := BladeView3D.camera_transform(pose.x, pose.y, 0.0645)
		var forward := -xform.basis.z.normalized()
		var to_hub := (Vector3.ZERO - xform.origin).normalized()
		worst = maxf(worst, forward.distance_to(to_hub))
		samples += 1
	return TestResult.new(
		"every named view points the camera at the hub, not away from it",
		samples == BladeView3D.VIEWS.size() and worst < 1e-5,
		"%d views, worst forward-vector error %s" % [samples, str(worst)])


# ---------------------------------------------------------------------------
# 3. The panel's mapping
# ---------------------------------------------------------------------------

## Every point of the α curve lands inside the plot rectangle.
##
## MUTATION that turns this red: drop the `clampf` on the α term in `to_pixels`. The reference
## blade's root sits far above the 25° top of the axis, so its curve leaves the plot, is drawn over
## the headline figures, and — because a Control does not clip its own `_draw` — over the room
## outside the panel as well.
static func _test_the_alpha_curve_lands_inside_the_plot() -> TestResult:
	var verdict := _reference_verdict()
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var panel := _panel(verdict, doc.radius_mm() * 0.001)
	var rect := panel.plot_rect()
	var curve := panel.alpha_curve_px()
	var outside := 0
	for point in curve:
		if not rect.has_point(point):
			outside += 1
	return TestResult.new(
		"every point of the angle-of-attack curve lands inside the plot",
		curve.size() > 10 and outside == 0,
		"%d points, %d outside %s" % [curve.size(), outside, str(rect)])


## r/R increases to the right, as it does in the planform editor above — the two share an axis and
## a caret, and a reversed one here would put the curve's tip under the editor's root.
static func _test_the_radius_axis_runs_the_same_way_as_the_planform() -> TestResult:
	var panel := _panel(_reference_verdict(), 0.0645)
	var root := panel.to_pixels(0.0, 0.0)
	var tip := panel.to_pixels(1.0, 0.0)
	var rect := panel.plot_rect()
	return TestResult.new(
		"the radius axis runs root-left to tip-right, spanning the plot",
		tip.x > root.x and absf(root.x - rect.position.x) < 1e-6
			and absf(tip.x - rect.end.x) < 1e-6,
		"root at x=%.1f, tip at x=%.1f, plot %s" % [root.x, tip.x, str(rect)])


## A refused solve draws no curve and no shading — not a flat line at zero incidence.
##
## MUTATION that turns this red: have `alpha_curve_px` fall through to the station walk when
## `refused` is true. The stations array is empty on a refusal, so the curve is empty too and the
## check still passes — UNLESS the mutation also drops the emptiness guard, which is the pair of
## slips that actually ships. So the assertion is on both the curve AND the bands, and a panel that
## draws either from a refusal fails here.
static func _test_a_refusal_draws_no_curve() -> TestResult:
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var refused := BladeAero.analyse(doc, 0.0)
	var panel := _panel(refused, doc.radius_mm() * 0.001)
	return TestResult.new(
		"a refused solve draws no curve and no shading",
		refused["refused"] and panel.alpha_curve_px().is_empty()
			and panel.stall_rects_px().is_empty(),
		"curve %d points, %d shaded rects"
			% [panel.alpha_curve_px().size(), panel.stall_rects_px().size()])


## The shaded rectangles sit at the pixel columns of the radii `BladeAero` called capped, and span
## the plot's full height.
##
## MUTATION that turns this red: in `stall_rects_px`, use the band's start for both edges. Every
## band collapses to the 1 px minimum width, which still draws something at the right place — a
## thin line where a region belongs, easy to read as a deliberate marker rather than a bug.
static func _test_the_shaded_bands_match_the_stalled_radii() -> TestResult:
	var doc := PropellerDocument.from_catalog_prop(
		PartsCatalog.load_default().get_part(ReferenceBuild.PROPELLER_ID))
	var radius := doc.radius_mm() * 0.001
	var verdict := BladeAero.analyse(doc, TEST_RPM)
	var panel := _panel(verdict, radius)
	var bands := BladeAero.stall_bands(verdict["stations"], BemtModel.global_polar()[3], radius)
	var rects := panel.stall_rects_px()
	var rect := panel.plot_rect()

	# 0.01 px and not 1e-6: `Rect2` stores single-precision floats, so a pixel computed in a double
	# and stored in a rect comes back a few parts in 10^8 different — which is the type talking, not
	# the mapping. The mutation this guards against collapses every band to the 1 px minimum, so a
	# hundredth of a pixel is still four orders of magnitude tighter than it needs to be.
	var tolerance_px := 0.01
	var matched := 0
	for i in rects.size():
		var expected_x := panel.to_pixels(bands[i * 2], 0.0).x
		var expected_w := panel.to_pixels(bands[i * 2 + 1], 0.0).x - expected_x
		var band_rect: Rect2 = rects[i]
		if absf(band_rect.position.x - expected_x) < tolerance_px \
				and absf(band_rect.size.x - maxf(expected_w, 1.0)) < tolerance_px \
				and absf(band_rect.size.y - rect.size.y) < tolerance_px:
			matched += 1
	return TestResult.new(
		"each shaded band spans the capped radii it stands for, full plot height",
		rects.size() > 0 and matched == rects.size()
			and rects.size() * 2 == bands.size(),
		"%d bands, %d matching" % [rects.size(), matched])


# ---------------------------------------------------------------------------
# 5. Pitch, the room's other editable property
# ---------------------------------------------------------------------------

