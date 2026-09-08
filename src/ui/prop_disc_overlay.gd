class_name PropDiscOverlay
extends Control
## What the props sweep, looking down — the fifth of P10e's five analysis overlays, and
## plans/2026-09-02-analysis-overlays-design.md §5.
##
## ## What it draws
##
## The four swept discs at their true radii and mount positions, the arms under them, any fitted
## guard's bore as a ring around each, and the gaps that matter: disc to disc, and tip to guard.
##
## ## Why a picture, when both numbers are already checked
##
## They are. `AirframeModel.footprint_prop_clearance_m` measures a footprint against the discs, and
## `PropGuard.clearance_check` classifies a ring by its own gap — P9's slice found a mislabelled
## bumper through it. §5.2's argument is that a check produces a SENTENCE and geometry is the one
## domain where the picture is genuinely better: a builder who fits a 7" prop on a frame laid out
## for 5" reads a number today and sees two overlapping circles here.
##
## That is also what sets the bar. The picture must be drawn from the same geometry the sentence
## is, or a builder gets a warning and an illustration that disagree — and the illustration wins.
## So the centres are `MotorLayout.motor_position`'s, the radius is the fitted propeller's own, and
## the guard's bore is read back through `PropGuard.tip_clearance_mm` rather than re-derived from
## `outer − wall`. That last one is P10c's correction, one file over: `GuardMesh` had the ring
## built from its own copy of that expression and a test that measured it with the same copy.
##
## ## THIS IS A PLAN VIEW AND IT CANNOT SEE HEIGHT
##
## §5.3, and §7 names it as the one thing whoever built this must not get wrong. Props on a
## stretched-X sit at different heights, so discs that overlap on this canvas may not overlap in
## space. This overlay compares no heights and has nothing to compare them with. It may say the
## discs overlap in plan; it may not say the propellers meet. `verdict_for` carries that
## distinction and is the only place either sentence is written.
##
## ## The axes are square, and that is a correctness property rather than a style one
##
## The other four overlays fit each axis to its own content, because each plots one quantity
## against a different one. This plots metres against metres. Independently fitted axes turn a
## disc into an ellipse — a picture of a propeller that does not exist, and the one way a geometry
## overlay lies without getting a single number wrong.

## The margin around the plot, in pixels. The other four overlays' value, so four charts that
## share a baseline share an inset.
const MARGIN_PX := 34.0

## How opaque the backing plate is. `ThrustOverlay.PLATE_ALPHA`'s value, for the same reason.
const PLATE_ALPHA := 0.86

## How many segments a drawn circle gets. `GuardMesh`'s own segment count, so a ring in plan and
## the ring on the aircraft are the same polygon at the same resolution.
const CIRCLE_SEGMENTS := 32

## No guard is fitted. The builder chose nothing.
const GUARD_NONE := "none"

## A guard is fitted and its geometry reads.
const GUARD_FITTED := "fitted"

## A guard IS fitted and `PropGuard.compute` declined its spec. Distinct from `GUARD_NONE` by
## §5.3: both have no ring to draw, and only this says the builder made a choice Lothal could not
## read. The same three-way split `VibrationOverlay` needed for the pad, one part over.
const GUARD_REFUSED := "refused"

## Motor name -> disc centre in the airframe's own XZ plane, metres. `Vector2(x, z)`, forward
## being −z, so the nose is up on screen. Empty when there is nothing to draw.
var disc_centres_m: Dictionary = {}

## The swept radius, metres — the fitted propeller's own.
var radius_m := 0.0

## Which of the three states the guard is in. One of the `GUARD_*` constants above.
var guard_state := GUARD_NONE

## The guard's inner bore radius, metres, measured from the motor's axis. NAN unless a guard is
## fitted AND readable — a bore drawn at a guessed radius would be the invented spec CONTINUE-HERE
## §9 forbids.
var guard_bore_radius_m := NAN

## Why the guard was refused, in `PropGuard.compute`'s own words. Empty unless refused.
var guard_reason := ""

## What the guard leaves around the blade tip, millimetres — `PropGuard.tip_clearance_mm`'s answer
## carried through unchanged. NAN when no readable guard is fitted. Negative is a real answer, not
## an error: it is the ring intersecting its own disc.
var tip_clearance_mm := NAN

## Why there is nothing to draw, when there is nothing to draw. Empty when there is.
var refusal := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 190)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the overlay from a build. The only entry point, so the plan and the numbers under it
## cannot describe different aircraft.
func adopt(build: Build) -> void:
	disc_centres_m = {}
	guard_state = GUARD_NONE
	guard_bore_radius_m = NAN
	guard_reason = ""
	tip_clearance_mm = NAN
	if build == null:
		radius_m = 0.0
		refusal = "No drone open"
		queue_redraw()
		return

	radius_m = float(build.prop_geometry().diameter_m) * 0.5
	for motor_name in MotorLayout.MOTOR_NAMES:
		var hub := MotorLayout.motor_position(motor_name, build.arm_m)
		disc_centres_m[motor_name] = Vector2(hub.x, hub.z)
	_adopt_guard(build)
	refusal = "" if radius_m > 0.0 and not disc_centres_m.is_empty() \
		else "The model declines this rotor"
	queue_redraw()


func _adopt_guard(build: Build) -> void:
	if build.guard.is_empty():
		return
	var specs: Dictionary = build.guard.get("specs", {})
	var clearance := PropGuard.tip_clearance_mm(specs, radius_m * 1000.0)
	if is_nan(clearance):
		# Fitted, and unreadable. NOT the same as absent.
		guard_state = GUARD_REFUSED
		guard_reason = String(PropGuard.compute(specs).get("tier", "unknown"))
		return
	guard_state = GUARD_FITTED
	tip_clearance_mm = clearance
	# The bore is the tip plus what the model says it clears, and not `outer − wall` restated.
	guard_bore_radius_m = radius_m + clearance * 0.001


# ---------------------------------------------------------------------------
# The pure part
# ---------------------------------------------------------------------------

## The gap between two discs of radius `p_radius_m` centred at `a` and `b`, in metres. Negative
## means they overlap in plan.
static func gap_m(a: Vector2, b: Vector2, p_radius_m: float) -> float:
	return a.distance_to(b) - p_radius_m * 2.0


## The narrowest gap between any two discs, metres. INF when there is no pair to measure — a
## refusal rather than a comfortable zero, on `PropGuard`'s posture that 0.0 is a real clearance.
func narrowest_disc_gap_m() -> float:
	var names := disc_centres_m.keys()
	var narrowest := INF
	for i in names.size():
		for j in range(i + 1, names.size()):
			narrowest = minf(narrowest,
				gap_m(disc_centres_m[names[i]], disc_centres_m[names[j]], radius_m))
	return narrowest


## Every pair of discs that overlaps in plan, as `"M1-M2"` strings in the layout's own order.
func overlapping_pairs() -> Array:
	var names := disc_centres_m.keys()
	var out: Array = []
	for i in names.size():
		for j in range(i + 1, names.size()):
			if gap_m(disc_centres_m[names[i]], disc_centres_m[names[j]], radius_m) < 0.0:
				out.append("%s-%s" % [names[i], names[j]])
	return out


## What the guard leaves around the tip, millimetres. NAN unless a readable guard is fitted.
func tip_to_guard_mm() -> float:
	return tip_clearance_mm


## What a gap of `p_gap_m` metres may be said to mean — and the sentence it may NOT be given.
##
## §5.3 and §7: **a plan view must not shade a 2D overlap as a 3D collision.** The arithmetic
## behind a negative gap is right; the discs really do overlap looking down. What this overlay has
## no way to know is whether they overlap in SPACE, because it compares no heights and a
## stretched-X puts its props at different ones. So the overlap verdict names the limitation in
## the same breath as the finding, and neither verdict claims the propellers meet.
##
## Static, so the rule is checked where it lives rather than restated in the test.
static func verdict_for(p_gap_m: float) -> String:
	if p_gap_m < 0.0:
		return "discs overlap in plan view — heights are not compared"
	return "clear in plan view"


## Half the width of the aircraft plus its props, metres — what the canvas has to contain.
func plan_extent_m() -> float:
	var extent := 0.0
	for motor_name in disc_centres_m:
		var at: Vector2 = disc_centres_m[motor_name]
		extent = maxf(extent, maxf(absf(at.x), absf(at.y)) + radius_m)
	return extent


## A point in the airframe's XZ plane to a pixel on this canvas.
##
## ONE scale for both axes — see this file's header. The plot is centred on the aircraft's origin,
## and +z (aft) maps to +y (down), so the nose points up.
func to_pixels(point_m: Vector2) -> Vector2:
	var inner := _inner_rect()
	var centre := inner.position + inner.size * 0.5
	return centre + point_m * _pixels_per_m()


func _pixels_per_m() -> float:
	var extent := plan_extent_m()
	if extent <= 0.0:
		return 0.0
	var inner := _inner_rect()
	return minf(inner.size.x, inner.size.y) / (extent * 2.0)


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# The drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, PLATE_ALPHA), true)
	draw_string(font, Vector2(MARGIN_PX * 0.4, MARGIN_PX * 0.75), "What the props sweep",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.94, 0.98))

	if refusal != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y * 0.5), refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.45))
		return

	var centre := to_pixels(Vector2.ZERO)
	var px_per_m := _pixels_per_m()
	var fouled := overlapping_pairs()

	# The arms first, under everything, so the discs read as sitting on the aircraft.
	for motor_name in disc_centres_m:
		draw_line(centre, to_pixels(disc_centres_m[motor_name]),
			Color(0.45, 0.5, 0.58, 0.7), 2.0)

	for motor_name in disc_centres_m:
		var at: Vector2 = to_pixels(disc_centres_m[motor_name])
		var r := radius_m * px_per_m
		# Shaded when this disc is in a fouling pair — SHADED, and captioned as a plan overlap.
		var fouls := false
		for pair in fouled:
			if String(pair).contains(motor_name):
				fouls = true
		var fill := Color(0.9, 0.45, 0.4, 0.22) if fouls else Color(0.35, 0.62, 0.95, 0.16)
		draw_circle(at, r, fill)
		draw_arc(at, r, 0.0, TAU, CIRCLE_SEGMENTS,
			Color(0.9, 0.5, 0.45) if fouls else Color(0.45, 0.75, 1.0), 1.5, true)
		if guard_state == GUARD_FITTED:
			draw_arc(at, guard_bore_radius_m * px_per_m, 0.0, TAU, CIRCLE_SEGMENTS,
				Color(0.7, 0.78, 0.9, 0.9), 1.0, true)

	var gap := narrowest_disc_gap_m()
	var caption := "disc to disc %.1f mm  ·  %s" % [gap * 1000.0, verdict_for(gap)]
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 22.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.9, 0.6, 0.5) if gap < 0.0 else Color(0.68, 0.72, 0.8))

	var guard_line := ""
	match guard_state:
		GUARD_FITTED:
			guard_line = "tip to guard %.1f mm" % tip_clearance_mm
		GUARD_REFUSED:
			# A guard IS fitted and the model declined it. Saying "no guard" here would attribute
			# to the builder a choice they did not make.
			guard_line = "a guard is fitted and Lothal cannot read it (%s)" % guard_reason
		_:
			guard_line = "no guard fitted"
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 8.0), guard_line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.85, 0.7, 0.45) if guard_state == GUARD_REFUSED else Color(0.68, 0.72, 0.8))
