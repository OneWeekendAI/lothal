class_name PlanTransform
extends RefCounted
## The mapping between a frame's millimetres and the pixels it is drawn on — airframe.md §7.1.
##
## ## Why this is its own object
##
## Everything the plan editor does is one of two things: turn a point in the document into a place on
## screen, or turn a click on screen back into a point in the document. Both directions have to be
## exact inverses or a builder drags a vertex and it lands somewhere else, and the error compounds
## over a drag. Keeping the pair in one small class means the round trip can be ASSERTED rather than
## eyeballed, which is what `test_plan_transform.gd` does.
##
## ## The axes, stated once
##
## `AirframeDocument` fixes plan `u` → world X (right) and plan `v` → world Z (aft), and
## `world_m()` is the one place that mapping is written as code. This class is the second place the
## same convention has to hold, on screen:
##
##   - `+u` is to the RIGHT, which matches both the document and the screen.
##   - `+v` is DOWN, and that is not an accident of Godot's screen coordinates — it is the aircraft
##     drawn nose-up, which is how every frame is photographed, sold and bolted together. Flipping it
##     would put the nose at the bottom of a top view, and every builder reading the picture would
##     have to invert it in their head against every product photo they have ever seen.
##
## So the mapping is a pure scale and offset with no reflection, and a frame whose CG is aft of the
## origin draws below it.

## Pixels per millimetre. A 5" frame is about 300 mm across, so the interesting range is roughly
## 1 to 8 px/mm on a normal window; the bounds below are generous either side of that.
const MIN_SCALE := 0.05
const MAX_SCALE := 60.0

## Where document (0, 0) sits on screen, in pixels.
var origin_px := Vector2.ZERO
var scale_px_per_mm := 2.0


static func make(p_origin_px: Vector2, p_scale: float) -> PlanTransform:
	var transform := PlanTransform.new()
	transform.origin_px = p_origin_px
	transform.scale_px_per_mm = clampf(p_scale, MIN_SCALE, MAX_SCALE)
	return transform


func to_pixels(point_mm: Vector2) -> Vector2:
	return origin_px + point_mm * scale_px_per_mm


func to_mm(point_px: Vector2) -> Vector2:
	return (point_px - origin_px) / scale_px_per_mm


## Millimetres per pixel, for hit tests written in screen terms — "within eight pixels of the
## vertex" is the sentence a builder's hand obeys, and it has to be converted at one place.
func mm_per_pixel() -> float:
	return 1.0 / scale_px_per_mm


## Zooms about a fixed point on screen, so the geometry under the cursor stays under the cursor.
##
## The alternative — zooming about the view's centre — is the single most disorienting thing a
## canvas can do: the part you were looking at slides away exactly when you are trying to look
## closer at it.
func zoom_at(anchor_px: Vector2, factor: float) -> void:
	var anchor_mm := to_mm(anchor_px)
	scale_px_per_mm = clampf(scale_px_per_mm * factor, MIN_SCALE, MAX_SCALE)
	origin_px = anchor_px - anchor_mm * scale_px_per_mm


func pan(delta_px: Vector2) -> void:
	origin_px += delta_px


## Frames a bounding box in a viewport, leaving `margin_px` of air on every side.
##
## A degenerate or empty box — an empty frame, or one with a single point in it — leaves the scale
## alone and simply centres the origin. Fitting to nothing would otherwise send the scale to its
## maximum and drop the builder into a view 60 px/mm deep, which reads as a blank screen.
func fit(min_mm: Vector2, max_mm: Vector2, size_px: Vector2, margin_px: float = 40.0) -> void:
	var span := max_mm - min_mm
	var usable := size_px - Vector2.ONE * margin_px * 2.0
	if usable.x <= 0.0 or usable.y <= 0.0:
		return
	if span.x > 0.0 and span.y > 0.0:
		scale_px_per_mm = clampf(
			minf(usable.x / span.x, usable.y / span.y), MIN_SCALE, MAX_SCALE)
	var centre_mm := (min_mm + max_mm) * 0.5
	origin_px = size_px * 0.5 - centre_mm * scale_px_per_mm


## The grid step to draw, in mm, chosen so lines stay legible at any zoom.
##
## A fixed 10 mm grid turns into a grey wash when you zoom out to see a 10" frame and disappears
## when you zoom in on a bolt hole. This walks the 1-2-5-10 sequence — the same one every ruler,
## oscilloscope and chart axis uses — until a step is at least `min_pixels` apart on screen.
func grid_step_mm(min_pixels: float = 12.0) -> float:
	var step := 1.0
	var guard := 0
	while step * scale_px_per_mm < min_pixels and guard < 24:
		# 1 -> 2 -> 5 -> 10, by the leading digit of the current step.
		var leading := step / pow(10.0, floor(log(step) / log(10.0)))
		if leading < 1.5:
			step *= 2.0
		elif leading < 3.5:
			step *= 2.5
		else:
			step *= 2.0
		guard += 1
	return step
