class_name TestPolygonProps
extends RefCounted
## PolygonProps is the layer every later airframe number is built on — mass, CG, the
## inertia tensor, arm stiffness, resonance. A wrong integral here would not look wrong
## anywhere; it would produce plausible frames that fly wrong in the sim, which is the
## failure mode airframe.md §3.1 calls out by name.
##
## So every test below checks against a CLOSED-FORM answer derived independently of the
## code — textbook formulae for the rectangle, circle, annulus and triangle, and hand
## arithmetic written into the comments for the L-section. None of them re-derive an
## expectation by calling the thing under test.
##
## The 30°-rotated case is the load-bearing one. Every axis-aligned shape has Ixy == 0, and
## so does an implementation that has dropped the Ixy term entirely; only a rotated shape
## tells those two apart. It is checked against the analytic rotated-axis transform rather
## than against a stored number, so it also fails if Ixx and Iyy are silently swapped.

## Relative tolerance for the exact-arithmetic shapes (rectangle, triangle, L-section).
## It is 1e-6 and not machine epsilon for one reason worth knowing: PackedVector2Array
## stores SINGLE-precision floats, so a vertex at x = 18.571428... is already wrong in the
## eighth digit before any integral runs. The arithmetic inside PolygonProps is double, and
## the residual here is purely that input quantisation. 1e-6 is ~10x that floor and still
## four orders tighter than any wrong-coefficient bug.
const REL_EPS := 1e-6

## Point-position tolerance in millimetres, same single-precision story. A micron is far
## below any feature this kernel will ever be asked about.
const POS_EPS_MM := 1e-3

## The rotated case needs its own, looser bound, and the reason is worth recording rather
## than hiding: that shape sits at (123, −47), so its moments about the ORIGIN are ~55e6
## and its centroidal Iyy is ~0.97e6. Subtracting the parallel-axis term is a catastrophic
## cancellation of two numbers 56x larger than the answer, and the single-precision vertex
## storage puts ~1e-5 mm of noise into each coordinate before that subtraction happens.
## 2e-5 relative is the resulting floor. Moving the shape to the origin would tighten it
## and would also stop testing the parallel-axis shift, which is the point of the offset.
const ROTATED_REL_EPS := 2e-5

## Tessellated shapes carry real, INTENDED error: the polygon is inscribed in the circle,
## so it genuinely has less area. For a chord tolerance `tol` on radius `r` the area
## deficit is about (4/3)(tol/r) — at 0.1 mm on r = 50 mm that is ~2.7e-3, and the second
## moments run about twice that. So the honest bound is a few parts in a thousand. It is
## loose, and it is still 100x tighter than any wrong-coefficient bug (a 1/12 written as
## 1/6 misses by 100%), which is the only thing a tolerance has to buy.
const TESS_REL_EPS := 1e-2


static func run() -> Array:
	var results: Array = []
	results.append(_test_rectangle())
	results.append(_test_circle())
	results.append(_test_annulus_by_winding())
	results.append(_test_triangle())
	results.append(_test_l_section())
	results.append(_test_rotated_30_degrees())
	results.append(_test_winding_independence())
	results.append(_test_degenerate_inputs())
	results.append(_test_chord_tolerance_is_honoured())
	results.append(_test_distance_to_boundary_is_the_nearest_edge())
	return results


static func _rect(b: float, h: float) -> PackedVector2Array:
	# Counter-clockwise, centred on the origin, so the centroidal moments ARE the origin
	# moments and a parallel-axis bug cannot hide behind a coincidence.
	return PackedVector2Array([
		Vector2(-b * 0.5, -h * 0.5),
		Vector2(b * 0.5, -h * 0.5),
		Vector2(b * 0.5, h * 0.5),
		Vector2(-b * 0.5, h * 0.5),
	])


static func _close(actual: float, expected: float, rel_eps: float) -> bool:
	var scale := maxf(absf(expected), 1.0)
	return absf(actual - expected) <= rel_eps * scale


static func _test_rectangle() -> TestResult:
	var b := 40.0
	var h := 90.0
	var poly := _rect(b, h)

	# Textbook: A = bh, Ixx = bh^3/12, Iyy = hb^3/12, Ixy = 0 about the centroid.
	var expect_a := b * h
	var expect_ixx := b * h * h * h / 12.0
	var expect_iyy := h * b * b * b / 12.0

	var a := PolygonProps.area(poly)
	var c := PolygonProps.centroid(poly)
	var m := PolygonProps.second_moments_centroidal(poly)

	var ok := (
		_close(a, expect_a, REL_EPS)
		and c.length() < POS_EPS_MM
		and _close(float(m["ixx"]), expect_ixx, REL_EPS)
		and _close(float(m["iyy"]), expect_iyy, REL_EPS)
		and absf(float(m["ixy"])) < REL_EPS * expect_ixx
	)

	return TestResult.new(
		"rectangle matches A=bh, Ixx=bh^3/12, Iyy=hb^3/12, Ixy=0",
		ok,
		"A=%.6f (want %.6f), centroid=%s, Ixx=%.4f (want %.4f), Iyy=%.4f (want %.4f), Ixy=%.9f" % [
			a, expect_a, c, float(m["ixx"]), expect_ixx, float(m["iyy"]), expect_iyy, float(m["ixy"])
		]
	)


static func _test_circle() -> TestResult:
	var r := 50.0
	var poly := PolygonProps.tessellate_circle(Vector2.ZERO, r)

	# Textbook: A = pi r^2, Ixx = Iyy = pi r^4 / 4, Ixy = 0.
	var expect_a := PI * r * r
	var expect_i := PI * pow(r, 4.0) / 4.0

	var a := PolygonProps.area(poly)
	var m := PolygonProps.second_moments_centroidal(poly)

	var ok := (
		_close(a, expect_a, TESS_REL_EPS)
		# Inscribed, so the polygon must be SMALLER than the circle. A tessellator that
		# somehow overshot would still pass the tolerance check but would be wrong.
		and a < expect_a
		and _close(float(m["ixx"]), expect_i, TESS_REL_EPS)
		and _close(float(m["iyy"]), expect_i, TESS_REL_EPS)
		and absf(float(m["ixy"])) < TESS_REL_EPS * expect_i
	)

	return TestResult.new(
		"tessellated circle matches A=pi r^2 and Ixx=Iyy=pi r^4/4 within tessellation tolerance",
		ok,
		"%d verts, A=%.6f (want %.6f), Ixx=%.3f Iyy=%.3f (want %.3f), Ixy=%.9f" % [
			poly.size(), a, expect_a, float(m["ixx"]), float(m["iyy"]), expect_i, float(m["ixy"])
		]
	)


static func _test_annulus_by_winding() -> TestResult:
	# The whole hole design in one test: no boolean geometry, just a reversed winding added
	# to the sum. If holes did not come out negative this fails by more than a factor of two.
	#
	# The annulus is deliberately NOT at the origin. Centred, its composite centroid is
	# (0,0), the parallel-axis shift inside region_properties() is identically zero, and a
	# version that dropped the shift entirely would pass — mutation-tested and confirmed.
	# Off-origin, that shift is ~7x the answer, so the test now covers it.
	var centre := Vector2(40.0, -25.0)
	var r_outer := 60.0
	var r_inner := 25.0
	var outline := PolygonProps.tessellate_circle(centre, r_outer)
	var hole := PolygonProps.tessellate_circle(centre, r_inner, PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true)

	var expect_a := PI * (r_outer * r_outer - r_inner * r_inner)
	var expect_i := PI * (pow(r_outer, 4.0) - pow(r_inner, 4.0)) / 4.0

	var hole_area := PolygonProps.area(hole)
	var region := PolygonProps.region_properties(outline, [hole])
	var a := float(region["area"])

	var ok := (
		hole_area < 0.0
		and _close(a, expect_a, TESS_REL_EPS)
		and _close(float(region["ixx_c"]), expect_i, TESS_REL_EPS)
		and _close(float(region["iyy_c"]), expect_i, TESS_REL_EPS)
		and (region["centroid"] as Vector2).distance_to(centre) < POS_EPS_MM
		# A concentric annulus is fully symmetric, so its product of inertia must vanish
		# even though it sits well away from the origin — which only holds if the shift is
		# actually applied.
		and absf(float(region["ixy_c"])) < TESS_REL_EPS * expect_i
	)

	return TestResult.new(
		"off-origin annulus by reversed-wound hole: area and Ixx are outline minus hole",
		ok,
		"hole area=%.4f (must be negative), A=%.6f (want %.6f), Ixx=%.3f Iyy=%.3f (want %.3f), centroid=%s (want %s), Ixy=%.3f" % [
			hole_area, a, expect_a, float(region["ixx_c"]), float(region["iyy_c"]), expect_i,
			region["centroid"], centre, float(region["ixy_c"])
		]
	)


static func _test_triangle() -> TestResult:
	# Right triangle, legs b along +x and h along +y from the origin.
	#   A       = bh/2                       = 30*80/2        = 1200
	#   centroid= (b/3, h/3)                 = (10, 26.666...)
	#   Ixx_c   = b h^3 / 36                 = 30*512000/36   = 426666.666...
	#   Iyy_c   = h b^3 / 36                 = 80*27000/36    =  60000
	#   Ixy_c   = -b^2 h^2 / 72              = -(900*6400)/72 = -80000
	# The Ixy sign is negative for this orientation because the bulk of the area sits below
	# the centroidal line y = x*(h/b) on the +x side. Getting it positive is a real bug.
	var b := 30.0
	var h := 80.0
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(b, 0), Vector2(0, h)])

	var expect_a := b * h / 2.0
	var expect_cx := b / 3.0
	var expect_cy := h / 3.0
	var expect_ixx := b * h * h * h / 36.0
	var expect_iyy := h * b * b * b / 36.0
	var expect_ixy := -(b * b) * (h * h) / 72.0

	var a := PolygonProps.area(poly)
	var c := PolygonProps.centroid(poly)
	var m := PolygonProps.second_moments_centroidal(poly)

	var ok := (
		_close(a, expect_a, REL_EPS)
		and absf(c.x - expect_cx) < POS_EPS_MM
		and absf(c.y - expect_cy) < POS_EPS_MM
		and _close(float(m["ixx"]), expect_ixx, REL_EPS)
		and _close(float(m["iyy"]), expect_iyy, REL_EPS)
		and _close(float(m["ixy"]), expect_ixy, REL_EPS)
	)

	return TestResult.new(
		"right triangle matches bh/2, (b/3,h/3), bh^3/36, hb^3/36, -b^2h^2/72",
		ok,
		"A=%.4f (want %.4f), c=%s (want %s), Ixx=%.4f (want %.4f), Iyy=%.4f (want %.4f), Ixy=%.4f (want %.4f)" % [
			a, expect_a, c, Vector2(expect_cx, expect_cy), float(m["ixx"]), expect_ixx,
			float(m["iyy"]), expect_iyy, float(m["ixy"]), expect_ixy
		]
	)


static func _test_l_section() -> TestResult:
	# L-section, counter-clockwise: (0,0) (60,0) (60,20) (20,20) (20,100) (0,100).
	# Hand-derived as two rectangles, R1 = 60x20 at the foot, R2 = 20x80 up the leg:
	#   A   = 1200 + 1600 = 2800
	#   x_  = (1200*30 + 1600*10) / 2800 = 52000/2800 = 18.571428571...
	#   y_  = (1200*10 + 1600*60) / 2800 = 108000/2800 = 38.571428571...
	# About the ORIGIN, using int(x1..x2, y1..y2): Ixx = w(y2^3-y1^3)/3 etc:
	#   Ixx = 60*20^3/3 + 20*(100^3-20^3)/3 = 160000 + 6613333.333... = 6773333.333...
	#   Iyy = 20*60^3/3 + 80*20^3/3        = 1440000 +  213333.333... = 1653333.333...
	#   Ixy = (x2^2-x1^2)(y2^2-y1^2)/4 per rect = 360000 + 960000     = 1320000
	# Shifted to the centroid:
	#   Ixx_c = 6773333.333 - 2800*y_^2 = 2607619.0476...
	#   Iyy_c = 1653333.333 - 2800*x_^2 =  687619.0476...
	#   Ixy_c = 1320000     - 2800*x_*y_ = -685714.2857...
	# Ixy_c is negative, which is the interesting part: the L leans into the second quadrant
	# relative to its own centroid, so this shape also catches an Ixy sign error.
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(60, 0), Vector2(60, 20),
		Vector2(20, 20), Vector2(20, 100), Vector2(0, 100),
	])

	var expect_a := 2800.0
	# Kept as doubles, NOT as a Vector2: rounding the hand-derived centroid to float32
	# before using it in the parallel-axis shift would quietly move the expectation onto
	# the same error the implementation makes, and the test would agree with a bug.
	var expect_cx := 52000.0 / 2800.0
	var expect_cy := 108000.0 / 2800.0
	var expect_origin_ixx := 160000.0 + 20.0 * (1000000.0 - 8000.0) / 3.0
	var expect_origin_iyy := 1440000.0 + 80.0 * 8000.0 / 3.0
	var expect_origin_ixy := 1320000.0
	var expect_ixx := expect_origin_ixx - expect_a * expect_cy * expect_cy
	var expect_iyy := expect_origin_iyy - expect_a * expect_cx * expect_cx
	var expect_ixy := expect_origin_ixy - expect_a * expect_cx * expect_cy

	var a := PolygonProps.area(poly)
	var c := PolygonProps.centroid(poly)
	var origin := PolygonProps.second_moments(poly)
	var m := PolygonProps.second_moments_centroidal(poly)

	var ok := (
		_close(a, expect_a, REL_EPS)
		and absf(c.x - expect_cx) < POS_EPS_MM
		and absf(c.y - expect_cy) < POS_EPS_MM
		and _close(float(origin["ixx"]), expect_origin_ixx, REL_EPS)
		and _close(float(origin["iyy"]), expect_origin_iyy, REL_EPS)
		and _close(float(origin["ixy"]), expect_origin_ixy, REL_EPS)
		and _close(float(m["ixx"]), expect_ixx, REL_EPS)
		and _close(float(m["iyy"]), expect_iyy, REL_EPS)
		and _close(float(m["ixy"]), expect_ixy, REL_EPS)
		and float(m["ixy"]) < 0.0
	)

	return TestResult.new(
		"L-section matches hand-derived area, centroid, origin moments and centroidal moments",
		ok,
		"A=%.4f (want %.1f), c=%s, origin Ixx=%.3f/%.3f Iyy=%.3f/%.3f Ixy=%.3f/%.3f, centroidal Ixx=%.3f/%.3f Iyy=%.3f/%.3f Ixy=%.3f/%.3f" % [
			a, expect_a, c,
			float(origin["ixx"]), expect_origin_ixx, float(origin["iyy"]), expect_origin_iyy,
			float(origin["ixy"]), expect_origin_ixy,
			float(m["ixx"]), expect_ixx, float(m["iyy"]), expect_iyy, float(m["ixy"]), expect_ixy
		]
	)


static func _test_rotated_30_degrees() -> TestResult:
	# THE test for Ixy. A 40x90 rectangle rotated 30° about its own centroid must satisfy
	# the rotated-axis transform exactly:
	#   Ixx' = (Ixx+Iyy)/2 + (Ixx-Iyy)/2*cos(2t) - Ixy*sin(2t)
	#   Iyy' = (Ixx+Iyy)/2 - (Ixx-Iyy)/2*cos(2t) + Ixy*sin(2t)
	#   Ixy' = (Ixx-Iyy)/2*sin(2t) + Ixy*cos(2t)
	# with Ixx, Iyy, Ixy the unrotated values (Ixy = 0 here). Because the unrotated Ixy is
	# zero, Ixy' = (Ixx-Iyy)/2*sin(60°) is large and nonzero — an implementation that
	# returns 0 for Ixy passes every other shape in this file and fails only here.
	#
	# SIGN CONVENTION, and it is the trap in this test rather than in the code: that
	# transform rotates the AXES by +t about a fixed shape. Here the SHAPE is rotated by
	# +30° about fixed axes, which is the same thing as rotating the axes by −30°. So the
	# transform is evaluated at −t. Get this backwards and Ixy' comes out with the right
	# magnitude and the wrong sign — indistinguishable, at a glance, from the very bug the
	# test exists to catch.
	var b := 40.0
	var h := 90.0
	var t := deg_to_rad(30.0)

	var ixx0 := b * h * h * h / 12.0
	var iyy0 := h * b * b * b / 12.0
	var ixy0 := 0.0

	var axis_t := -t  # see the sign-convention note above
	var half_sum := (ixx0 + iyy0) * 0.5
	var half_diff := (ixx0 - iyy0) * 0.5
	var expect_ixx := half_sum + half_diff * cos(2.0 * axis_t) - ixy0 * sin(2.0 * axis_t)
	var expect_iyy := half_sum - half_diff * cos(2.0 * axis_t) + ixy0 * sin(2.0 * axis_t)
	var expect_ixy := half_diff * sin(2.0 * axis_t) + ixy0 * cos(2.0 * axis_t)

	# Rotate about the centroid AND translate off the origin, so the parallel-axis shift is
	# doing real work and cannot cancel out against a centred shape.
	var offset := Vector2(123.0, -47.0)
	var rotated := PackedVector2Array()
	for p in _rect(b, h):
		rotated.append(p.rotated(t) + offset)

	var a := PolygonProps.area(rotated)
	var c := PolygonProps.centroid(rotated)
	var m := PolygonProps.second_moments_centroidal(rotated)

	var ok := (
		_close(a, b * h, ROTATED_REL_EPS)
		and c.distance_to(offset) < POS_EPS_MM
		and _close(float(m["ixx"]), expect_ixx, ROTATED_REL_EPS)
		and _close(float(m["iyy"]), expect_iyy, ROTATED_REL_EPS)
		and _close(float(m["ixy"]), expect_ixy, ROTATED_REL_EPS)
		# Sign, checked separately from magnitude, because `_close` on a number this large
		# would pass on a sign flip only if the tolerance were absurd — but stating it
		# makes the intent unmissable to whoever edits this next.
		and signf(float(m["ixy"])) == signf(expect_ixy)
		and absf(expect_ixy) > 1.0
	)

	return TestResult.new(
		"rectangle rotated 30 deg matches the analytic rotated-axis transform (catches a wrong Ixy)",
		ok,
		"A=%.4f, c=%s (want %s), Ixx=%.4f (want %.4f), Iyy=%.4f (want %.4f), Ixy=%.4f (want %.4f)" % [
			a, c, offset, float(m["ixx"]), expect_ixx, float(m["iyy"]), expect_iyy,
			float(m["ixy"]), expect_ixy
		]
	)


static func _test_winding_independence() -> TestResult:
	# Reversing an outline must flip the sign of area exactly and move the centroid not at
	# all — the property that lets a hole be "the same polygon, wound the other way" and
	# still contribute its moments about the right place.
	var poly := PackedVector2Array([
		Vector2(10, 5), Vector2(70, 5), Vector2(70, 35), Vector2(40, 60), Vector2(10, 35),
	])
	var rev := PolygonProps.reversed(poly)

	var a := PolygonProps.area(poly)
	var a_rev := PolygonProps.area(rev)
	var c := PolygonProps.centroid(poly)
	var c_rev := PolygonProps.centroid(rev)
	var m := PolygonProps.second_moments_centroidal(poly)
	var m_rev := PolygonProps.second_moments_centroidal(rev)

	var ok := (
		a > 0.0
		and a_rev < 0.0
		and _close(a_rev, -a, REL_EPS)
		and c.distance_to(c_rev) < POS_EPS_MM
		and _close(float(m_rev["ixx"]), -float(m["ixx"]), REL_EPS)
		and _close(float(m_rev["iyy"]), -float(m["iyy"]), REL_EPS)
		and _close(float(m_rev["ixy"]), -float(m["ixy"]), REL_EPS)
	)

	return TestResult.new(
		"reversing the winding negates area and moments but leaves the centroid alone",
		ok,
		"A=%.6f vs reversed %.6f, centroid %s vs %s, Ixx %.4f vs %.4f" % [
			a, a_rev, c, c_rev, float(m["ixx"]), float(m_rev["ixx"])
		]
	)


static func _test_degenerate_inputs() -> TestResult:
	# The editor will hand this kernel half-drawn outlines every frame while a point is
	# being dragged. A divide-by-zero here would surface as INF mass and a NaN CG in the
	# 3D view, so the contract is: finite numbers, no crash, no INF.
	var empty := PackedVector2Array()
	var one := PackedVector2Array([Vector2(3, 4)])
	var two := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var collinear := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(5, 0)])

	var cases := [empty, one, two, collinear]
	var all_finite := true
	var detail := ""
	for case in cases:
		var poly: PackedVector2Array = case
		var a := PolygonProps.area(poly)
		var c := PolygonProps.centroid(poly)
		var m := PolygonProps.second_moments(poly)
		var mc := PolygonProps.second_moments_centroidal(poly)
		var region := PolygonProps.region_properties(poly, [])
		var finite := (
			is_finite(a) and is_finite(c.x) and is_finite(c.y)
			and is_finite(float(m["ixx"])) and is_finite(float(m["iyy"])) and is_finite(float(m["ixy"]))
			and is_finite(float(mc["ixx"])) and is_finite(float(mc["iyy"])) and is_finite(float(mc["ixy"]))
			and is_finite(float(region["area"]))
			and is_finite((region["centroid"] as Vector2).x)
			and is_finite(float(region["ixx_c"]))
			and absf(a) < 1e-6
		)
		if not finite:
			all_finite = false
		detail += "n=%d A=%.9f c=%s; " % [poly.size(), a, c]

	return TestResult.new(
		"degenerate polygons (under 3 points, zero area) return finite zeros instead of crashing",
		all_finite,
		detail
	)


static func _test_chord_tolerance_is_honoured() -> TestResult:
	# The tessellation promise is a stated chord tolerance, not a vertex count. Check the
	# actual sagitta of the generated polygon against the requested tolerance, and check
	# that a tighter tolerance really does produce a finer polygon — otherwise "0.1 mm"
	# would be decoration on a fixed segment count.
	var r := 80.0
	var coarse := PolygonProps.tessellate_circle(Vector2.ZERO, r, 1.0)
	var fine := PolygonProps.tessellate_circle(Vector2.ZERO, r, 0.01)

	var worst := 0.0
	for i in fine.size():
		var p := fine[i]
		var q := fine[(i + 1) % fine.size()]
		var mid := (p + q) * 0.5
		worst = maxf(worst, r - mid.length())

	var arc := PolygonProps.tessellate_arc(Vector2(5, 5), 20.0, 0.0, PI * 0.5)
	var arc_ends_on_circle := (
		arc.size() >= 2
		and absf(arc[0].distance_to(Vector2(5, 5)) - 20.0) < 1e-9
		and absf(arc[arc.size() - 1].distance_to(Vector2(5, 5)) - 20.0) < 1e-9
		and arc[arc.size() - 1].distance_to(Vector2(5, 25)) < 1e-6
	)

	var ok := (
		fine.size() > coarse.size()
		and worst <= 0.01 + 1e-9
		and arc_ends_on_circle
	)

	return TestResult.new(
		"tessellation honours the stated chord tolerance and arcs land on their endpoints",
		ok,
		"coarse=%d verts, fine=%d verts, worst sagitta=%.6f mm (limit 0.01), arc endpoints ok=%s" % [
			coarse.size(), fine.size(), worst, arc_ends_on_circle
		]
	)


## The number `HardwareMass.hole_to_edge_warning` has always said belonged here. Asserted against a
## rectangle, where the answer is arithmetic: a point 3 mm in from the long side and 20 mm from the
## nearest short side is 3 mm from the boundary.
##
## MUTATION: measure to the infinite LINE through each edge instead of to the segment, and the
## corner case below reports 0 instead of 5 — a hole safely outside the plate would then pass a
## tear-out check that exists to catch exactly that.
static func _test_distance_to_boundary_is_the_nearest_edge() -> TestResult:
	var rectangle := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 20.0), Vector2(0.0, 20.0)])
	var inside := PolygonProps.distance_to_boundary(rectangle, Vector2(50.0, 3.0))
	var near_end := PolygonProps.distance_to_boundary(rectangle, Vector2(2.0, 10.0))
	# Diagonally off the (0,0) corner: the nearest boundary point is the corner itself, 5 mm away.
	var off_corner := PolygonProps.distance_to_boundary(rectangle, Vector2(-3.0, -4.0))
	return TestResult.new(
		"distance to a polygon boundary measures to the nearest edge, segment-clamped",
		absf(inside - 3.0) < 1.0e-6 and absf(near_end - 2.0) < 1.0e-6
			and absf(off_corner - 5.0) < 1.0e-6,
		"inside %.4f (want 3), near end %.4f (want 2), off corner %.4f (want 5)" % [
			inside, near_end, off_corner])
