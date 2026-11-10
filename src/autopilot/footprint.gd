class_name Footprint
extends RefCounted
## SR5.2: the ground footprint of ONE photo, from the real camera position and attitude, on the real ground height.
## No swath formula anywhere: four rays through the image corners are marched onto the terrain and the quadrilateral they
## bound is the footprint (precision rule P1: area comes from the flown pose, never from field / swath).
##
## Frame (the repo's): Y up, forward is -Z, right is +X. The camera is mounted looking straight down the body's -Y axis;
## the long sensor side (sensor_w_mm, across the flight direction) lies along body X, the short side along body -Z.
## `orientation` is the body orientation (Quaternion, as DroneCore.rigid_body.orientation); a gimbal can be folded into it.
## `ground` is a Callable (x, z) -> height_m, e.g. World.ground_fn() or Footprint.ground_of(heightfield); an invalid Callable is flat ground at y = 0.
##
## Result: {ok, corners: PackedVector2Array (x, z; order +X-forward, +X-back, -X-back, -X-forward), area_m2, ground_y_min, ground_y_max,
## note}. ok is false when a corner ray never reaches the ground within MAX_RANGE_M (the camera sees the horizon or the sky).

const MAX_RANGE_M := 2000.0
const MARCH_M := 1.0
const BISECT := 40


static func ground_of(hf: Heightfield) -> Callable:
	return func(x: float, z: float) -> float: return hf.height_at(x, z)


static func project(cam: CameraParams, pos: Vector3, orientation: Quaternion, ground: Callable = Callable()) -> Dictionary:
	var tx := cam.sensor_w_mm / (2.0 * cam.focal_mm)
	var tz := cam.sensor_h_mm / (2.0 * cam.focal_mm)
	var corner_dirs := [Vector3(tx, -1.0, -tz), Vector3(tx, -1.0, tz), Vector3(-tx, -1.0, tz), Vector3(-tx, -1.0, -tz)]
	var pts := PackedVector2Array()
	var ymin := INF
	var ymax := -INF
	for d in corner_dirs:
		var dir: Vector3 = (orientation * (d as Vector3)).normalized()
		var hit: Array = _march(pos, dir, ground)
		if hit.is_empty():
			return {"ok": false, "corners": PackedVector2Array(), "area_m2": 0.0, "ground_y_min": 0.0, "ground_y_max": 0.0,
				"note": "a corner ray does not reach the ground (horizon or sky in frame)"}
		var g: Vector3 = hit[0]
		pts.append(Vector2(g.x, g.z))
		ymin = minf(ymin, g.y)
		ymax = maxf(ymax, g.y)
	return {"ok": true, "corners": pts, "area_m2": absf(_shoelace(pts)), "ground_y_min": ymin, "ground_y_max": ymax, "note": ""}


static func _h(ground: Callable, x: float, z: float) -> float:
	return float(ground.call(x, z)) if ground.is_valid() else 0.0


## First crossing of the terrain along the ray (marched, then bisected). [hit point] or [] on a miss.
static func _march(origin: Vector3, dir: Vector3, ground: Callable) -> Array:
	var prev_t := 0.0
	if origin.y - _h(ground, origin.x, origin.z) <= 0.0:
		return []
	var t := MARCH_M
	while t <= MAX_RANGE_M:
		var p := origin + dir * t
		if p.y - _h(ground, p.x, p.z) <= 0.0:
			var lo := prev_t
			var hi := t
			for _i in BISECT:
				var mid := 0.5 * (lo + hi)
				var q := origin + dir * mid
				if q.y - _h(ground, q.x, q.z) <= 0.0:
					hi = mid
				else:
					lo = mid
			var r := origin + dir * hi
			return [Vector3(r.x, _h(ground, r.x, r.z), r.z)]
		prev_t = t
		t += MARCH_M
	return []


static func _shoelace(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return 0.5 * a
