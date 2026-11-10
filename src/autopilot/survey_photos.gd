class_name SurveyPhotos
extends RefCounted
## SR5.4: what the camera actually saw. The runner records the POSE at every camera trigger (time, position, body attitude,
## ground speed); this turns those poses into a coverage map through Footprint.project (real attitude on the real ground) and
## CoverageMap, and reports GSD as a RANGE and motion blur per photo. No swath formula (precision rule P1).
##
## photo = {t, pos: Vector3, q: Quaternion (body orientation, camera on a FIXED mount unless the runner folded a gimbal in), vg: ground speed m/s}.
## MOTION BLUR (estimated model): blur in pixels = ground speed x exposure / GSD of that photo. It ignores the aircraft's rotation
## during the exposure and image-motion compensation. A photo is FLAGGED when blur exceeds BLUR_LIMIT_PX; 0.5 px is a common
## photogrammetry rule of thumb, NOT a measured limit (tag estimated; override with the runner param blur_limit_px).
## GSD of a photo = sqrt(footprint area / pixels): the mean ground size of a pixel, correct on tilted or sloping ground.

const BLUR_LIMIT_PX := 0.5
const MAX_CELLS := 400000


static func report(photos: Array, cam: CameraParams, poly: PackedVector2Array, ground: Callable, required: int, blur_limit_px: float, interval_s: float = 2.0) -> Dictionary:
	var shots: Array = []
	var rejected := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	if poly.size() >= 3:
		for q in poly:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	for ph in photos:
		var f := Footprint.project(cam, ph["pos"], ph["q"], ground)
		if not bool(f["ok"]):
			rejected += 1
			continue
		shots.append({"corners": f["corners"], "area": float(f["area_m2"]), "vg": float(ph["vg"]), "t": float(ph["t"])})
		if poly.size() < 3:
			for c in (f["corners"] as PackedVector2Array):
				lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
				hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	var out := {"triggers": photos.size(), "images": shots.size(), "rejected_no_ground": rejected, "required_photos": required,
		"required_photos_tag": "estimated", "mapped_m2": 0.0, "mapped_acres": 0.0, "mapped_hectares": 0.0, "mapped_fraction": 0.0,
		"mean_photos_per_cell": 0.0, "unmapped_in_polygon_m2": 0.0, "cell_m": 0.0,
		"front_overlap": {"min": 0.0, "mean": 0.0, "max": 0.0, "pairs": 0, "tag": "estimated", "rule": "overlap area / footprint area of consecutive triggers closer than interval + 0.5 s (same line)"},
		"gsd_cm": {"min": 0.0, "mean": 0.0, "max": 0.0, "tag": cam.tag},
		"blur": {"limit_px": blur_limit_px, "limit_tag": "estimated", "exposure_s": cam.exposure_s, "max_px": 0.0, "mean_px": 0.0, "flagged": 0,
			"flagged_fraction": 0.0, "model": "ground speed x exposure / GSD (no rotation, no motion compensation)"},
		"source": "footprints projected from the pose at each trigger (Footprint.project), counted in CoverageMap"}
	if shots.is_empty():
		return out
	var span := hi - lo
	var cell := maxf(1.0, sqrt(span.x * span.y / float(MAX_CELLS)))
	var map := CoverageMap.covering(Rect2(lo, span), cell)
	var g_min := INF
	var g_max := -INF
	var g_sum := 0.0
	var b_max := 0.0
	var b_sum := 0.0
	var flagged := 0
	var px := float(cam.px_w * cam.px_h)
	for s in shots:
		map.add_footprint(s["corners"])
		var gsd_m := sqrt(float(s["area"]) / px)
		g_min = minf(g_min, gsd_m)
		g_max = maxf(g_max, gsd_m)
		g_sum += gsd_m
		var blur := float(s["vg"]) * cam.exposure_s / gsd_m
		b_max = maxf(b_max, blur)
		b_sum += blur
		if blur > blur_limit_px:
			flagged += 1
	var n := float(shots.size())
	var ov_min := INF
	var ov_max := -INF
	var ov_sum := 0.0
	var pairs := 0
	for i in range(1, shots.size()):
		if float(shots[i]["t"]) - float(shots[i - 1]["t"]) > interval_s + 0.5:
			continue
		var a: PackedVector2Array = shots[i - 1]["corners"]
		var b: PackedVector2Array = shots[i]["corners"]
		var inter := 0.0
		for piece in Geometry2D.intersect_polygons(a, b):
			inter += absf(_area(piece))
		var ov := inter / float(shots[i - 1]["area"])
		ov_min = minf(ov_min, ov)
		ov_max = maxf(ov_max, ov)
		ov_sum += ov
		pairs += 1
	if pairs > 0:
		out["front_overlap"] = {"min": ov_min, "mean": ov_sum / pairs, "max": ov_max, "pairs": pairs, "tag": "estimated", "rule": out["front_overlap"]["rule"]}
	var area := map.mapped_area(required, poly)
	out["mapped_m2"] = area["m2"]
	out["mapped_acres"] = area["acres"]
	out["mapped_hectares"] = area["hectares"]
	out["cell_m"] = cell
	out["mean_photos_per_cell"] = map.mean_count(poly)
	if poly.size() >= 3:
		var holes := map.hole_area(required, poly)
		out["unmapped_in_polygon_m2"] = holes["m2"]
		var tot := float(area["m2"]) + float(holes["m2"])
		out["mapped_fraction"] = float(area["m2"]) / tot if tot > 0.0 else 0.0
	out["gsd_cm"] = {"min": g_min * 100.0, "mean": g_sum / n * 100.0, "max": g_max * 100.0, "tag": cam.tag}
	out["blur"]["max_px"] = b_max
	out["blur"]["mean_px"] = b_sum / n
	out["blur"]["flagged"] = flagged
	out["blur"]["flagged_fraction"] = float(flagged) / n
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return 0.5 * a
