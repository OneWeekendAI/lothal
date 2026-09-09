class_name CameraView
extends RefCounted
## What the fitted camera has in front of it — plans/2026-08-26-propulsion-room-design.md §5 P10c,
## the half that was deferred when the row closed on 2026-08-28.
##
## ## THIS CLASS KNOWS NO FIELD OF VIEW, AND THAT IS THE DESIGN
##
## §5 asked for a "camera frustum check": is the guard inside the camera's cone. A frustum needs a
## field of view, and Lothal does not have one to give it. `cameras.json` bans lens FOV from
## `specs` BY NAME, and `FpvView`'s header argues why at length: nobody has sourced FOV figures for
## these entries, the catalog's rule is that a published number is a measured one, and a real FPV
## lens is a 150-170 deg fisheye that a rectilinear projection cannot honestly represent anyway.
## `FpvView.PLACEHOLDER_FOV_DEG` is 90 and says of itself that it is a framing choice rather than
## an optical spec.
##
## So a containment test run against that placeholder would emit a WARNING ABOUT A BUILD derived
## from a number this project refuses to claim — "never invent a spec to unlock a feature", and it
## is worse here than in the renderer, because `FpvView` captions its picture as a placeholder and
## a warning that says "your guard is in shot" is read as a fact about the aircraft.
##
## What is asked instead is the question that needs no lens: HOW FAR OFF THE CAMERA'S CENTRELINE
## does each obstruction sit. That is pure geometry from parts whose dimensions are published. A
## guard at 62 deg off-axis is in shot on any lens wider than 124 deg and out of shot on anything
## narrower, and the reader supplies the lens. The ranking across builds is exact even though no
## angle-of-view is claimed — which is CONTINUE-HERE §9's rule about a trustworthy ranking over an
## untrustworthy magnitude, applied where it was meant to be applied.
##
## ## Why the minimum, and not the maximum
##
## An obstruction enters the picture at its point CLOSEST to the centreline, so the minimum over a
## polygon is the number that decides whether it is seen at all. The maximum would describe how far
## the thing extends into the corner of an image whose corners are not defined.
##
## ## No transforms, no tree
##
## Every position here is in the airframe's own frame, and nothing calls `global_transform`. A
## `Node3D` outside the tree returns identity from it — silently, with an error only in the editor
## build — so a check written that way computes an aircraft centred on the origin, which is exactly
## the defect the 2026-08-28 review found in this slice's own deferred half. `AirframeModel` hands
## this class numbers, not nodes.

## The angle from the camera's centreline to `point`, in degrees, both in the airframe's own frame.
##
## Forward is -Z (physics.md §1) and there is no tilt anywhere in the model yet — see `FpvView`,
## which names tilt as its own slice belonging in `AssemblyTweaks`. When it lands, it rotates the
## boresight passed in here and every number below moves with it; nothing in this file assumes the
## axis.
##
## 180 for a point at the eye itself: a degenerate direction has no angle, and reporting 0 would
## claim the most intrusive possible obstruction from the least information.
static func off_axis_deg(eye_m: Vector3, boresight: Vector3, point_m: Vector3) -> float:
	var to_point := point_m - eye_m
	if to_point.length_squared() < 1e-18:
		return 180.0
	return rad_to_deg(boresight.normalized().angle_to(to_point.normalized()))


## The smallest off-axis angle over a CLOSED polygon — where an obstruction first enters the
## picture. INF for an empty polygon, which is the honest answer for a build that fits no such
## part: "never in shot", and it sorts last rather than first.
##
## MEASURED OVER THE EDGES, NOT THE CORNERS, and the difference is not academic. A plate's outline
## has few vertices and long straight runs between them, and the point of an edge nearest the
## centreline is almost never one of its ends — a frame whose front edge crosses the centreline has
## its closest approach in the middle of that edge, and a corner-only minimum would report the
## corner instead and quietly place the whole front of the aircraft further out of shot than it is.
## Under-reporting intrusion is the one direction this check must not fail in.
##
## Each edge is solved exactly rather than sampled. Maximising cos(angle) = u.d/|d| along
## d(t) = p + t*q gives t = (aQ - bP) / (bQ - aR) with a = u.p, b = u.q, P = p.p, Q = p.q, R = q.q;
## clamped to the segment, and compared against both ends, so a degenerate denominator falls back to
## the endpoints rather than to a NAN.
static func min_off_axis_deg(eye_m: Vector3, boresight: Vector3, points: PackedVector3Array) -> float:
	if points.is_empty():
		return INF
	if points.size() == 1:
		return off_axis_deg(eye_m, boresight, points[0])

	var u := boresight.normalized()
	var best := INF
	for index in points.size():
		var a_point := points[index]
		# Closed: the last vertex joins the first. Both inputs — a plate outline and a guard ring —
		# are closed loops, and leaving the last edge out would leave one run of the silhouette
		# unmeasured.
		var b_point := points[(index + 1) % points.size()]
		best = minf(best, _min_off_axis_on_segment_deg(eye_m, u, a_point, b_point))
	return best


static func _min_off_axis_on_segment_deg(
	eye_m: Vector3, u: Vector3, a_point: Vector3, b_point: Vector3
) -> float:
	var best := minf(off_axis_deg(eye_m, u, a_point), off_axis_deg(eye_m, u, b_point))

	var p := a_point - eye_m
	var q := b_point - a_point
	var a := u.dot(p)
	var b := u.dot(q)
	var big_p := p.dot(p)
	var big_q := p.dot(q)
	var big_r := q.dot(q)

	var denominator := b * big_q - a * big_r
	if absf(denominator) < 1e-18:
		return best
	var t := (a * big_q - b * big_p) / denominator
	if t <= 0.0 or t >= 1.0:
		return best
	return minf(best, off_axis_deg(eye_m, u, a_point + q * t))


## Each obstruction's closest approach to the centreline, `{name: degrees}`.
##
## `obstructions` is `{name: PackedVector3Array}` in the airframe's own frame — what
## `AirframeModel.camera_obstruction_points_m()` returns.
static func off_axis_report(eye_m: Vector3, boresight: Vector3, obstructions: Dictionary) -> Dictionary:
	var out := {}
	for name in obstructions:
		out[name] = min_off_axis_deg(eye_m, boresight, obstructions[name])
	return out
