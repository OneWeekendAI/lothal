class_name TestSr4Survey
extends RefCounted
## SR4 survey planner (src/autopilot/survey_planner.gd, camera_params.gd). Pure geometry, one TestResult per case.
##
## WORKED EXAMPLE, by hand: field 400 x 300 m (x 0..400, y 0..300), height 60 m, generic_1inch
## (13.2 x 8.8 mm, f 8.8 mm), front 75 %, side 65 %, speed 8 m/s.
##   across footprint = 60 * 13.2 / 8.8 = 90 m;  along footprint = 60 * 8.8 / 8.8 = 60 m
##   spacing = 90 * (1 - 0.65) = 31.5 m;  shot spacing = 60 * (1 - 0.75) = 15 m;  shot interval = 15 / 8 = 1.875 s
##   (< camera minimum 2.0 s, so the forward warning FIRES here; max speed = 15 / 2 = 7.5 m/s)
##   longest edge is the 400 m one -> lines run along x; stacked across the 300 m extent
##   lines n = ceil(300 / 31.5) = ceil(9.52) = 10; margin to each edge = (300 - 9 * 31.5) / 2 = 8.25 m (< 45 m reach)
##   overrun = 60 / 2 = 30 m -> each flown line = 400 + 2 * 30 = 460 m;  10 lines = 4600 m
##   turns: 9 semicircles of diameter 31.5 -> 9 * pi * 15.75 = 445.32 m
##   path length = 4600 + 445.32 = 5045.32 m
##   time = 4600 / 8 + 445.32 / (8 * 0.6) = 575 + 92.78 = 667.78 s    (turns at 0.6 x speed)
##   area = 400 * 300 = 120000 m2
##
## FAIL-PROOFS (each case was run with its fix removed by a temporary edit, then restored; observed value):
##   M1 spacing x1.5: worked count FAILS (7 lines, spacing 47.25); path/time FAILS (3665 m); skip-coverage FAILS
##        (full 0.79); alternation FAILS.
##   M2 last scan line dropped (for k in n-1): worked count FAILS (9 lines); path FAILS (4536 m); narrow field FAILS (0 lines).
##   M3 forward test disabled (interval < 0): forward-fires FAILS (no warning, no hole).
##   M15 forward test always true: forward-not-fires FAILS (spurious warning at 7 m/s).
##   M4 side-overlap and spacing<=0 guards removed: side=1 case HANGS (infinite line count; detected by timeout).
##   M5 degenerate guard and no-scan warning removed: both degenerate cases FAIL (lines 0, warnings []).
##        (The polygon guard alone is redundant with the no-scan warning; the cases check the 'degenerate' text.)
##   M6 auto angle = last edge: worked count FAILS (13 lines), auto-angle FAILS, U-shape FAILS, alternation FAILS.
##   M7 concave pairs merged into one segment: U-shape FAILS (max 1 segment per scan line).
##   M8 no direction reversal (always fly left to right): path FAILS (8750 m); alternation FAILS.
##   M9 overrun 0: path FAILS (4445 m vs 5045).
##   M10 turn slowdown factor 1.0: time FAILS (630.7 s vs 667.8).
##   M11 one-line-for-narrow rule removed: narrow field FAILS (2 lines).
##   M12 footprint along from the long sensor side: camera FAILS (90 x 90), worked interval FAILS (2.81 s), forward-fires FAILS.
##   M13 shoelace without 0.5: area FAILS (240000).
##   M14 spacing x3 (94.5 m > 90 m footprint): coverage 400x300 FAILS (0.953), coverage L FAILS (0.869), skip FAILS.
##   Not individually proven: the GSD value alone (camera case also holds footprint; M12 only breaks footprint).
##   Note: at 65 % side overlap one removed line is still covered by its neighbours, so the skip case uses 10 %.
##
## Coverage = share of 1 m cell centres inside the polygon that lie in a swath rectangle (across/2 each side
## of a clipped line, along/2 past each end, i.e. a shot at each clipped end). Edge margin: cells within 1 m
## of the polygon boundary are excluded (rasterisation noise); tolerance 99 % (<= 1 %).

const H := 60.0


static func run() -> Array:
	var out: Array = []
	out.append(_cam_footprint())
	out.append(_worked_count_spacing())
	out.append(_worked_path_time())
	out.append(_area())
	out.append(_coverage_rect())
	out.append(_coverage_l())
	out.append(_coverage_after_skip())
	out.append(_forward_fires())
	out.append(_forward_not_fires())
	out.append(_side_one_error())
	out.append(_degenerate_few())
	out.append(_degenerate_zero_area())
	out.append(_auto_angle())
	out.append(_concave_multi())
	out.append(_alternation())
	out.append(_narrow_one_line())
	return out


static func _rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])


static func _plan(poly: PackedVector2Array, front := 0.75, side := 0.65, speed := 8.0, opts := {}) -> Dictionary:
	return SurveyPlanner.plan(poly, CameraParams.generic_1inch(), H, front, side, speed, opts)


static func _inside(poly: PackedVector2Array, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


static func _near_edge(poly: PackedVector2Array, p: Vector2, d: float) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < d:
			return true
	return false


static func _coverage(poly: PackedVector2Array, lines: Array) -> float:
	var fp := CameraParams.generic_1inch().footprint_m(H)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var total := 0
	var covered := 0
	for ix in int(hi.x - lo.x):
		for iy in int(hi.y - lo.y):
			var c := lo + Vector2(ix + 0.5, iy + 0.5)
			if not _inside(poly, c) or _near_edge(poly, c, 1.0):
				continue
			total += 1
			for l in lines:
				var d: Vector2 = (l.b - l.a).normalized()
				var rel: Vector2 = c - l.a
				var along := rel.dot(d)
				var perp := absf(rel.dot(Vector2(-d.y, d.x)))
				if perp <= fp.x * 0.5 and along >= -fp.y * 0.5 and along <= (l.b - l.a).length() + fp.y * 0.5:
					covered += 1
					break
	return float(covered) / maxf(1.0, float(total))


static func _cam_footprint() -> TestResult:
	var c := CameraParams.generic_1inch()
	var f := c.footprint_m(60.0)
	var g := c.gsd_cm(60.0)
	# gsd = 90 m / 5472 px = 1.645 cm
	var ok := is_equal_approx(f.x, 90.0) and is_equal_approx(f.y, 60.0) and absf(g - 1.6447) < 0.001 and c.tag == "estimated"
	return TestResult.new("sr4 survey camera: 60 m gives footprint 90 x 60 m (along = short side), GSD 1.645 cm, tag estimated",
		ok, "footprint %s gsd %.4f tag %s" % [f, g, c.tag])


static func _worked_count_spacing() -> TestResult:
	var p := _plan(_rect(400, 300))
	print("SR4 survey worked: lines %d spacing %.3f path %.2f time %.2f interval %.3f" % [p.line_count, p.spacing_m, p.path_length_m, p.expected_time_s, p.shot_interval_s])
	var ok: bool = p.line_count == 10 and absf(p.spacing_m - 31.5) < 1e-9 and absf(p.along_spacing_m - 15.0) < 1e-9 \
		and absf(p.shot_interval_s - 1.875) < 1e-9
	return TestResult.new("sr4 survey worked 400x300 field: exactly 10 lines, spacing 31.5 m, shot spacing 15 m, interval 1.875 s",
		ok, "lines %d spacing %.4f along %.4f interval %.4f" % [p.line_count, p.spacing_m, p.along_spacing_m, p.shot_interval_s])


static func _worked_path_time() -> TestResult:
	var p := _plan(_rect(400, 300))
	var hand_path := 4600.0 + 9.0 * PI * 15.75
	var hand_time := 4600.0 / 8.0 + 9.0 * PI * 15.75 / (8.0 * 0.6)
	var ok: bool = absf(p.path_length_m - hand_path) / hand_path < 0.01 and absf(p.expected_time_s - hand_time) / hand_time < 0.01
	return TestResult.new("sr4 survey worked: path length within 1 %% of hand 5045.3 m and time within 1 %% of 667.8 s",
		ok, "path %.2f (hand %.2f) time %.2f (hand %.2f)" % [p.path_length_m, hand_path, p.expected_time_s, hand_time])


static func _area() -> TestResult:
	var a := SurveyPlanner.polygon_area(_rect(400, 300))
	var l := SurveyPlanner.polygon_area(_l_shape())
	# L: 200x200 minus the 120x120 notch = 40000 - 14400 = 25600
	return TestResult.new("sr4 survey shoelace area: 400x300 = 120000 m2, L-shape = 25600 m2",
		absf(a - 120000.0) < 1e-6 and absf(l - 25600.0) < 1e-6, "rect %.3f L %.3f" % [a, l])


static func _l_shape() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 80), Vector2(80, 80), Vector2(80, 200), Vector2(0, 200)])


static func _u_shape() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(300, 200), Vector2(200, 200), Vector2(200, 60),
		Vector2(100, 60), Vector2(100, 200), Vector2(0, 200)])


static func _coverage_rect() -> TestResult:
	var poly := _rect(400, 300)
	var cov := _coverage(poly, _plan(poly).lines)
	return TestResult.new("sr4 survey coverage 400x300: swath union covers at least 99 %% of interior cells",
		cov >= 0.99, "coverage %.4f" % cov)


static func _coverage_l() -> TestResult:
	var poly := _l_shape()
	var cov := _coverage(poly, _plan(poly).lines)
	return TestResult.new("sr4 survey coverage concave L-shape: swath union covers at least 99 %% of interior cells",
		cov >= 0.99, "coverage %.4f" % cov)


## At 65 % side overlap one missing line is still covered by its neighbours (footprint 90 m vs gap 63 m), so
## this case uses side overlap 0.1 (spacing 81 m, 4 lines) where each line matters.
static func _coverage_after_skip() -> TestResult:
	var poly := _rect(400, 300)
	var p := _plan(poly, 0.75, 0.1)
	var full := _coverage(poly, p.lines)
	var lines: Array = p.lines.duplicate()
	lines.remove_at(1)
	var cov := _coverage(poly, lines)
	return TestResult.new("sr4 survey: with all 4 lines coverage >= 99 %%, with line 2 removed it falls below 98 %%",
		full >= 0.99 and cov < 0.98, "full %.4f skipped %.4f lines %d" % [full, cov, p.line_count])


static func _forward_fires() -> TestResult:
	var p := _plan(_rect(400, 300), 0.75, 0.65, 10.0)
	var warned := false
	for w in p.warnings:
		if w.contains("forward overlap impossible"):
			warned = true
	var hole_ok := false
	for h in p.holes:
		if h.kind == "forward" and absf(h.needed_speed_max - 7.5) < 1e-9:
			hole_ok = true
	return TestResult.new("sr4 survey: 10 m/s at 75 %% front overlap warns 'forward overlap impossible' and records a forward hole with max speed 7.5 m/s",
		warned and hole_ok, "warnings %s holes %s" % [p.warnings, p.holes])


static func _forward_not_fires() -> TestResult:
	var p := _plan(_rect(400, 300), 0.75, 0.65, 7.0)
	return TestResult.new("sr4 survey: 7 m/s (interval 2.14 s) raises no forward warning and no hole",
		p.warnings.is_empty() and p.holes.is_empty(), "warnings %s holes %s" % [p.warnings, p.holes])


static func _side_one_error() -> TestResult:
	var p := _plan(_rect(400, 300), 0.75, 1.0)
	return TestResult.new("sr4 survey: side overlap 1.0 gives an error plan with a warning and no lines",
		p.error and p.line_count == 0 and p.warnings.size() > 0, "error %s lines %d warnings %s" % [p.error, p.line_count, p.warnings])


static func _degenerate_few() -> TestResult:
	var p := _plan(PackedVector2Array([Vector2(0, 0), Vector2(10, 10)]), 0.75, 0.65, 7.0)
	return TestResult.new("sr4 survey: a 2-point polygon gives no lines and a warning",
		p.line_count == 0 and p.warnings.size() == 1 and String(p.warnings[0]).contains("degenerate"), "lines %d warnings %s" % [p.line_count, p.warnings])


static func _degenerate_zero_area() -> TestResult:
	var p := _plan(PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(100, 0)]), 0.75, 0.65, 7.0)
	return TestResult.new("sr4 survey: a collinear (zero-area) polygon gives no lines and a warning",
		p.line_count == 0 and p.warnings.size() == 1 and String(p.warnings[0]).contains("degenerate"), "lines %d warnings %s" % [p.line_count, p.warnings])


## 400 x 100 rectangle rotated 30 degrees: the long edge is at 30 deg, so lines must run at 30 deg.
static func _auto_angle() -> TestResult:
	var r := deg_to_rad(30.0)
	var u := Vector2(cos(r), sin(r)) * 400.0
	var v := Vector2(-sin(r), cos(r)) * 100.0
	var poly := PackedVector2Array([Vector2.ZERO, u, u + v, v])
	var p := _plan(poly)
	var worst := 0.0
	for l in p.lines:
		var d: Vector2 = (l.b - l.a).normalized()
		worst = maxf(worst, absf(d.cross(Vector2(cos(r), sin(r)))))
	return TestResult.new("sr4 survey: auto line angle follows the longest edge (30 deg), every line parallel to it",
		absf(p.line_angle_deg - 30.0) < 1e-6 and p.line_count > 0 and worst < 1e-6, "angle %.4f lines %d worst cross %.6f" % [p.line_angle_deg, p.line_count, worst])


## U-shape: scan lines above y = 60 cut the two arms, giving two segments on the same scan line.
static func _concave_multi() -> TestResult:
	var p := _plan(_u_shape())
	var by_c := {}
	for l in p.lines:
		var k := snappedf(l.a.y, 0.01)
		by_c[k] = by_c.get(k, 0) + 1
	var most := 0
	for k in by_c:
		most = maxi(most, by_c[k])
	return TestResult.new("sr4 survey concave U-shape: some scan line is split into 2 segments",
		most == 2, "max segments on one scan line %d, lines %d" % [most, p.line_count])


static func _alternation() -> TestResult:
	var p := _plan(_rect(400, 300))
	var alt: bool = p.line_count == 10
	var prev := 0.0
	var contiguous := true
	for i in p.lines.size():
		var l: Dictionary = p.lines[i]
		var s: float = signf(l.b.x - l.a.x)
		if i > 0 and s == prev:
			alt = false
		if i > 0 and absf(l.a.y - p.lines[i - 1].a.y - 31.5) > 1e-6:
			contiguous = false
		prev = s
	return TestResult.new("sr4 survey: consecutive lines alternate direction and step exactly one spacing across (continuous lawnmower)",
		alt and contiguous, "alternates %s contiguous %s" % [alt, contiguous])


static func _narrow_one_line() -> TestResult:
	var p := _plan(_rect(400, 40))
	return TestResult.new("sr4 survey: a 40 m wide field (narrower than the 90 m footprint) still gets exactly one line",
		p.line_count == 1 and not p.error, "lines %d warnings %s" % [p.line_count, p.warnings])
