class_name PickerPlace
extends RefCounted
## Where the swap picker goes (PLAN Section 3), as pure arithmetic on a CameraRig and a screen
## size, so placement is testable headless.
##
## The picker sits beside the drone, never over it, and never over the right-hand column (the
## readouts on top, the inspector growing up from the bottom: both live in the right 340 px). At
## the 5"'s home view at 1280x720 the drone's screen box spans x 102..876 and the column starts at
## 940, so neither side has room for a 360 px picker. Rather than shrink the picker below its rows,
## the camera makes room: it backs off and slides the drone left until the picker fits between the
## drone and the column (`room_goal`), and goes back when the picker closes.

const MARGIN := 24.0           ## from the screen edge
const GAP := 24.0              ## between the drone's box and the picker
const COLUMN_W := 356.0        ## the right column (readouts + inspector, 340 px) plus a little air
const TOP := 64.0              ## below the "Classes" back link


## The screen rect (px, y down) of the union of `boxes` (AABBs) seen through `view`.
static func screen_rect(view: CameraRig, boxes: Array, size: Vector2) -> Rect2:
	if boxes.is_empty():
		return Rect2()
	var u: AABB = boxes[0]
	for b in boxes:
		u = u.merge(b)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := to_px(view.project(u.get_endpoint(i)), size)
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


static func to_px(ndc: Vector2, size: Vector2) -> Vector2:
	return Vector2((ndc.x + 1.0) * 0.5 * size.x, (1.0 - ndc.y) * 0.5 * size.y)


## A copy of `rig` settled at its goal: where the camera is going, so the picker is placed once
## for the view the eased camera will arrive at instead of chasing it.
static func settled(rig: CameraRig) -> CameraRig:
	var v := CameraRig.new(rig.radius, rig.height)
	v.aspect = rig.aspect
	v.goal_target = rig.goal_target
	v.goal_yaw = rig.goal_yaw
	v.goal_pitch = rig.goal_pitch
	v.goal_distance = rig.goal_distance
	v.snap()
	return v


## The x of a picker `w` wide beside `drone`, clear of it and of the right column; the side nearer
## `part_x` wins when both fit. NAN when neither side has room.
static func side_x(drone: Rect2, w: float, size: Vector2, part_x: float) -> float:
	var right := drone.end.x + GAP
	var left := drone.position.x - GAP - w
	var right_ok := right + w <= size.x - COLUMN_W
	var left_ok := left >= MARGIN
	if right_ok and left_ok:
		return right if absf(right - part_x) <= absf(left + w - part_x) else left
	if right_ok:
		return right
	if left_ok:
		return left
	return NAN


## The y of a picker `h` tall, centred on the part and kept on screen.
static func near_y(part_y: float, h: float, size: Vector2) -> float:
	return clampf(part_y - h * 0.5, TOP, maxf(size.y - h - MARGIN, TOP))


## The goal {target, distance} that fits the drone into the space left of a `w`-wide picker (and
## the picker's gap) beside the right column, keeping yaw and pitch.
static func room_goal(rig: CameraRig, boxes: Array, size: Vector2, w: float) -> Dictionary:
	var region := Rect2(Vector2(MARGIN, TOP),
		Vector2(size.x - COLUMN_W - w - GAP - MARGIN * 2.0, size.y - TOP - MARGIN))
	var v := settled(rig)
	var t := tan(deg_to_rad(CameraRig.FOV_DEG) * 0.5)
	for i in 12:
		var r := screen_rect(v, boxes, size)
		if i >= 6 and region.encloses(r):
			break
		var s := maxf(r.size.x / region.size.x, r.size.y / region.size.y)
		# Perspective is not linear in distance; past six rounds, a few percent more each time.
		v.goal_distance *= maxf(s, 1.0) * (1.03 if i >= 6 else 1.0)
		v.snap()
		r = screen_rect(v, boxes, size)
		var d := region.get_center() - r.get_center()
		var world_per_px := 2.0 * v.goal_distance * t / size.y
		v.goal_target += (-v.right_of(v.goal_yaw) * d.x + v.up_of(v.goal_yaw, v.goal_pitch) * d.y) * world_per_px
		v.snap()
	return {"target": v.goal_target, "distance": v.goal_distance}


## The scroll offset that shows the span [top, bottom] in a window `view_h` tall now at `current`:
## unchanged when it already shows, else the least move that does.
static func reveal(top: float, bottom: float, view_h: float, current: float) -> float:
	if top < current:
		return maxf(top, 0.0)
	if bottom > current + view_h:
		return minf(bottom - view_h, top)
	return current
