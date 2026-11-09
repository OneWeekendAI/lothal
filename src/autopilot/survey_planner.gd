class_name SurveyPlanner
extends RefCounted
## Lawnmower survey planner. Pure static, no physics. Local metres: x east, y = world z (south).
##
## RULES (all stated, all tested):
##  * Line direction: opts.line_angle_deg if given, else the direction of the polygon's LONGEST edge
##    (angle of that edge, folded to [0,180)). Scan lines run along it; they stack across the other axis.
##  * footprint = camera.footprint_m(height) = (across, along). spacing = across * (1 - side_overlap).
##    shot spacing = along * (1 - front_overlap); shot_interval_s = shot spacing / speed.
##  * Line count n = ceil(W / spacing), or 1 when W <= across (one centred swath already spans it); W = polygon extent across the lines. The n lines are
##    centred on the extent: margin to each extreme edge = (W - (n-1)*spacing)/2 <= spacing/2
##    <= across/2, so the first/last swath always reaches the boundary, and spacing is exactly as stated.
##  * Each scan line is clipped to the polygon (even-odd, half-open rule), so a concave polygon gives
##    several segments per scan line. Segments are ordered greedily: start at the lowest-across,
##    lowest-along end; then always fly to the nearest unvisited segment end.
##  * Each segment is flown with overrun_m (default along/2) past both ends.
##  * Turn: between two segments whose near ends have equal along-coordinate (adjacent lines) the connector
##    is a SEMICIRCLE on the chord between the two overrun points (diameter = chord, bulging forward, 9
##    interior waypoints kind "turn"). Otherwise a straight "transit". Semicircle radius < turn_radius_m
##    gives a warning (plan still produced).
##  * Time: line part at speed, turn/transit part at 0.6 * speed (stated slowdown).
## waypoints: Array of {p:Vector2, kind:String} kind in "overrun","line","turn".
## lines: in flight order, a -> b in the flown direction, clipped to the polygon (no overrun).
## holes: coverage holes, e.g. {kind:"forward", needed_speed_max:float}.

const TURN_SPEED_FACTOR := 0.6
const ARC_POINTS := 9


static func polygon_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func auto_angle_deg(poly: PackedVector2Array) -> float:
	var best := -1.0
	var ang := 0.0
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best + 1e-9:
			best = e.length()
			ang = rad_to_deg(atan2(e.y, e.x))
	return fposmod(ang, 180.0)


static func _empty(warn: String) -> Dictionary:
	return {"lines": [], "waypoints": [], "line_count": 0, "spacing_m": 0.0, "along_spacing_m": 0.0,
		"shot_interval_s": 0.0, "path_length_m": 0.0, "turn_length_m": 0.0, "expected_time_s": 0.0,
		"polygon_area_m2": 0.0, "warnings": [warn], "holes": [], "error": true, "line_angle_deg": 0.0}


static func plan(polygon: PackedVector2Array, camera: CameraParams, height_m: float, front_overlap: float,
		side_overlap: float, speed_mps: float, opts: Dictionary = {}) -> Dictionary:
	var area := polygon_area(polygon)
	if polygon.size() < 3 or area < 1e-6:
		var d := _empty("degenerate polygon (fewer than 3 points or zero area): no lines")
		d["polygon_area_m2"] = area
		return d
	var fp := camera.footprint_m(height_m)
	var spacing := fp.x * (1.0 - side_overlap)
	var along_sp := fp.y * (1.0 - front_overlap)
	if side_overlap >= 1.0 or side_overlap < 0.0 or front_overlap >= 1.0 or front_overlap < 0.0 \
			or spacing <= 0.0 or height_m <= 0.0 or speed_mps <= 0.0:
		var e := _empty("error: overlap must be in [0,1) and height and speed positive (side %.2f, front %.2f)" % [side_overlap, front_overlap])
		e["polygon_area_m2"] = area
		return e
	var overrun: float = opts.get("overrun_m", fp.y * 0.5)
	var turn_r: float = opts.get("turn_radius_m", 3.0)
	var angle: float = opts["line_angle_deg"] if opts.has("line_angle_deg") else auto_angle_deg(polygon)
	var u := Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))
	var v := Vector2(-u.y, u.x)
	# polygon in (u,v) coordinates
	var q := PackedVector2Array()
	var vmin := INF
	var vmax := -INF
	for p in polygon:
		var c := Vector2(p.dot(u), p.dot(v))
		q.append(c)
		vmin = minf(vmin, c.y)
		vmax = maxf(vmax, c.y)
	var width := vmax - vmin
	var n := 1 if width <= fp.x else maxi(1, int(ceil(width / spacing - 1e-6)))
	var segs: Array = []  # {c, u0, u1}
	for k in n:
		var c := vmin + width * 0.5 + (k - (n - 1) * 0.5) * spacing
		var xs: Array = []
		for i in q.size():
			var a := q[i]
			var b := q[(i + 1) % q.size()]
			if (a.y <= c) != (b.y <= c):
				xs.append(a.x + (c - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			if xs[j + 1] - xs[j] > 0.01:
				segs.append({"c": c, "u0": xs[j], "u1": xs[j + 1]})
			j += 2
	var warnings: Array[String] = []
	var holes: Array = []
	var interval := along_sp / speed_mps
	if interval < camera.min_shot_interval_s:
		var vmax_ok := along_sp / camera.min_shot_interval_s
		warnings.append("forward overlap impossible: shot every %.2f s needed at %.1f m/s but camera minimum is %.2f s; max speed %.2f m/s" % [interval, speed_mps, camera.min_shot_interval_s, vmax_ok])
		holes.append({"kind": "forward", "needed_speed_max": vmax_ok})
	if segs.is_empty():
		warnings.append("no scan line met the polygon: no lines")
	# greedy order
	var remaining := segs.duplicate()
	var lines: Array = []
	var wps: Array = []
	var line_len := 0.0
	var turn_len := 0.0
	var cur_pos := Vector2.ZERO
	var cur_dir := Vector2.ZERO
	var first := true
	var tight := false
	while not remaining.is_empty():
		var bi := 0
		var b_rev := false
		var bd := INF
		for i in remaining.size():
			var s: Dictionary = remaining[i]
			var pa: Vector2 = u * s.u0 + v * s.c
			var pb: Vector2 = u * s.u1 + v * s.c
			for rev in [false, true]:
				var pt: Vector2 = pb if rev else pa
				var dd: float
				if first:
					dd = (s.c - vmin) * 1e6 + (s.u1 if rev else s.u0)
				else:
					dd = cur_pos.distance_to(pt - (u if not rev else -u) * overrun)
				if dd < bd - 1e-9:
					bd = dd
					bi = i
					b_rev = rev
		var s2: Dictionary = remaining[bi]
		remaining.remove_at(bi)
		var a: Vector2 = u * s2.u0 + v * s2.c
		var b: Vector2 = u * s2.u1 + v * s2.c
		if b_rev:
			var t := a
			a = b
			b = t
		var dir := (b - a).normalized()
		var ea := a - dir * overrun
		var eb := b + dir * overrun
		if not first:
			var chord := ea - cur_pos
			if absf(chord.dot(cur_dir)) < 0.5 and chord.length() > 1e-6 and cur_dir.dot(dir) < 0.0:
				var r := chord.length() * 0.5
				var mid := cur_pos + chord * 0.5
				var am := cur_pos - mid
				for m in range(1, ARC_POINTS + 1):
					var th := PI * m / (ARC_POINTS + 1)
					wps.append({"p": mid + am * cos(th) + cur_dir * (r * sin(th)), "kind": "turn"})
				turn_len += PI * r
				if r < turn_r:
					tight = true
			else:
				turn_len += chord.length()
		if overrun > 1e-6:
			wps.append({"p": ea, "kind": "overrun"})
		wps.append({"p": a, "kind": "line"})
		wps.append({"p": b, "kind": "line"})
		if overrun > 1e-6:
			wps.append({"p": eb, "kind": "overrun"})
		lines.append({"a": a, "b": b})
		line_len += (eb - ea).length()
		cur_pos = eb
		cur_dir = dir
		first = false
	if tight:
		warnings.append("turn radius below turn_radius_m on some turns (line spacing too tight for the aircraft)")
	if width < fp.x and not lines.is_empty():
		warnings.append("field narrower than one footprint: single line")
	return {"lines": lines, "waypoints": wps, "line_count": lines.size(), "spacing_m": spacing,
		"along_spacing_m": along_sp, "shot_interval_s": interval, "path_length_m": line_len + turn_len,
		"turn_length_m": turn_len, "expected_time_s": line_len / speed_mps + turn_len / (speed_mps * TURN_SPEED_FACTOR),
		"polygon_area_m2": area, "warnings": warnings, "holes": holes, "error": false,
		"line_angle_deg": angle, "overrun_m": overrun}
