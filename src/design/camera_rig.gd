class_name CameraRig
extends RefCounted
## The Design Space's free camera as pure arithmetic: an orbit about a target point, with eased
## motion. No Node, so the limits and the home view are testable headless.
##
## The camera sits `distance` from `target` at (`yaw`, `pitch`). Input moves the GOAL; `step`
## eases the shown values toward it. Orbit and pan are clamped, zoom is clamped, and zoom goes
## toward the point under the cursor (that point stays put on screen).

const FOV_DEG := 30.0
const MIN_PITCH := deg_to_rad(2.0)
const MAX_PITCH := deg_to_rad(88.0)
## The isometric home view: 45 deg about, atan(1/sqrt 2) down.
const HOME_YAW := deg_to_rad(45.0)
const HOME_PITCH := 0.6154797086703874
const MIN_DISTANCE := 0.02
## Ease rate (1/s): about 95% of the way after a quarter of a second.
## Closer than this fraction of the home distance counts as zoomed in (the readouts step aside).
const ZOOMED_FRACTION := 0.6
const EASE_RATE := 12.0

var radius := 0.15            ## the drone's footprint radius, m
var height := 0.06            ## the drone's height, m
var aspect := 16.0 / 9.0

var target := Vector3.ZERO
var yaw := HOME_YAW
var pitch := HOME_PITCH
var distance := 0.5
var goal_target := Vector3.ZERO
var goal_yaw := HOME_YAW
var goal_pitch := HOME_PITCH
var goal_distance := 0.5
var framing := false          ## true after frame(); cleared by home and zoom


func _init(p_radius: float = 0.15, p_height: float = 0.06) -> void:
	radius = p_radius
	height = p_height
	snap_home()


func max_distance() -> float:
	return radius * 8.0


func home_distance() -> float:
	return radius / sin(deg_to_rad(FOV_DEG) * 0.5) * 0.92


## True while the view is close in or framing a part.
func is_zoomed_in() -> bool:
	return framing or goal_distance < home_distance() * ZOOMED_FRACTION


func home_target() -> Vector3:
	# Aimed a little right of the drone so it sits left of the readout panel.
	return Vector3(0.0, height * 0.5, 0.0) + right_of(HOME_YAW) * radius * 0.4


## Eases back to the isometric view.
func go_home() -> void:
	framing = false
	goal_target = home_target()
	goal_yaw = HOME_YAW
	goal_pitch = HOME_PITCH
	goal_distance = home_distance()


func snap_home() -> void:
	go_home()
	snap()


func snap() -> void:
	target = goal_target
	yaw = goal_yaw
	pitch = goal_pitch
	distance = goal_distance


## Orbit by a drag in pixels-scaled units (radians).
func orbit(d_yaw: float, d_pitch: float) -> void:
	goal_yaw -= d_yaw
	goal_pitch = clampf(goal_pitch + d_pitch, MIN_PITCH, MAX_PITCH)


## Pan by a fraction of the view (1.0 = the full visible height at the target).
func pan(dx: float, dy: float) -> void:
	var h := 2.0 * goal_distance * tan(deg_to_rad(FOV_DEG) * 0.5)
	goal_target += (-right_of(goal_yaw) * dx + up_of(goal_yaw, goal_pitch) * dy) * h
	_clamp_target()


## Zooms by `factor` (<1 comes closer) toward the cursor at `ndc` (x right, y up, each -1..1): the
## point under the cursor on the target plane keeps its place on screen.
func zoom_toward(factor: float, ndc: Vector2) -> void:
	framing = false
	var t := tan(deg_to_rad(FOV_DEG) * 0.5)
	var new_d := clampf(goal_distance * factor, MIN_DISTANCE, max_distance())
	var r := right_of(goal_yaw)
	var u := up_of(goal_yaw, goal_pitch)
	var old_off := (r * ndc.x * aspect + u * ndc.y) * (goal_distance * t)
	var new_off := (r * ndc.x * aspect + u * ndc.y) * (new_d * t)
	goal_target += old_off - new_off
	goal_distance = new_d
	_clamp_target()


## Frames a box: centres it and closes in until it fills the view.
func frame(box: AABB) -> void:
	framing = true
	goal_target = box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.001)
	goal_distance = clampf(r / sin(deg_to_rad(FOV_DEG) * 0.5) * 1.15, MIN_DISTANCE, max_distance())
	_clamp_target()


func step(delta: float) -> void:
	var k := 1.0 - exp(-EASE_RATE * maxf(delta, 0.0))
	target = target.lerp(goal_target, k)
	yaw = lerpf(yaw, goal_yaw, k)
	pitch = lerpf(pitch, goal_pitch, k)
	distance = lerpf(distance, goal_distance, k)


func position() -> Vector3:
	return target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance


func basis() -> Basis:
	return Transform3D.IDENTITY.looking_at(-Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)), Vector3.UP).basis


func near() -> float:
	return maxf(distance * 0.05, 0.001)


func far() -> float:
	return distance + radius * 12.0


## World ray through the screen point `ndc`: {origin, dir}.
func ray(ndc: Vector2) -> Dictionary:
	var t := tan(deg_to_rad(FOV_DEG) * 0.5)
	var r := right_of(yaw)
	var u := up_of(yaw, pitch)
	var f := -Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return {"origin": position(), "dir": (f + r * ndc.x * aspect * t + u * ndc.y * t).normalized()}


## Where a world point lands on screen, as ndc (x right, y up).
func project(p: Vector3) -> Vector2:
	var b := basis()
	var local := b.inverse() * (p - position())
	var t := tan(deg_to_rad(FOV_DEG) * 0.5)
	return Vector2(local.x / (-local.z * t * aspect), local.y / (-local.z * t))


func right_of(y: float) -> Vector3:
	return Vector3(cos(y), 0.0, -sin(y))


func up_of(y: float, p: float) -> Vector3:
	return Vector3(-sin(y) * sin(p), cos(p), -cos(y) * sin(p))


func _clamp_target() -> void:
	var lim := radius * 1.5
	goal_target = Vector3(clampf(goal_target.x, -lim, lim), clampf(goal_target.y, 0.0, maxf(height * 2.0, 0.05)),
		clampf(goal_target.z, -lim, lim))
