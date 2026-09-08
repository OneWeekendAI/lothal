class_name SpinUpOverlay
extends Control
## How fast the motor arrives — the fourth of P10e's five analysis overlays, and
## plans/2026-09-02-analysis-overlays-design.md §4 is candid that it is the weakest of them.
##
## ## What it draws
##
## `omega(t) = omega_final · (1 − e^(−t/tau))` over five time constants, with the 63% point marked
## at `t = tau`. `tau` is `Build.spin_up()`'s, computed per motor since P7; `omega_final` is
## `Build.operating_rpm()`, the same point the linearisation was taken at and the same point
## `ThrustOverlay` draws its blade loading at.
##
## ## Why it is one curve and not four
##
## §4.1 asks for four curves overlaid "so an asymmetric build shows as four curves instead of one".
## A `Build` holds ONE motor record and ONE propeller, so `spin_up()` returns one dictionary with
## no motor name in it — the four curves would be one curve drawn four times, a picture claiming
## the model can express an asymmetric quad when it cannot. CONTINUE-HERE §9: never invent a spec
## to unlock a feature; if the honest outcome is that a slot cannot be filled, the app says so. So
## the caption says all four motors are the same motor, and
## `tests/test_spin_up_overlay.gd` pins `spin_up()`'s shape so this reasoning goes red the day
## per-motor tau lands — which is the day the fourth curve becomes real rather than decorative.
##
## ## Why a fallback is drawn differently
##
## `MotorSpinUp.FALLBACK_TAU_S` is 0.03 s and it is not a measurement: it is the shared constant
## P7 deleted from `motor.rs`, kept only so a caller that CANNOT compute tau reproduces the old
## numbers instead of a silent zero. A curve drawn from it looks exactly like a curve drawn from a
## recovered winding resistance, which would be this overlay presenting a constant as a result —
## §4.3's one obligation. `compute()` carries a `tier` string for precisely this reader, so the
## curve is dashed and the note names the tier whenever the tier is a fallback.
##
## ## An overlay is not a room
##
## No state, no editing, no signals out — the posture the first three take, and the reason the
## mapping functions below are public and pure.

## The margin around the plot, in pixels. The first three overlays' value, deliberately: four
## charts that can be on screen together and rule their axes at different insets read as four
## charts about four aircraft.
const MARGIN_PX := 34.0

## How opaque the backing plate is. `ThrustOverlay.PLATE_ALPHA`'s value for the same reason.
const PLATE_ALPHA := 0.86

## How many time constants the axis runs for. A ZOOM LEVEL, not a physical claim, in the same
## category as `VibrationOverlay.AXIS_SPAN_MULTIPLE`: a first-order response is 99.3% arrived at
## five tau, so an axis that stopped earlier would cut off the arrival and one that ran longer
## would spend its width on a flat line. §4.1's "roughly 5 tau", made exact because an axis label
## has to say something.
const AXIS_SPAN_TAUS := 5.0

## The dash length used to draw a fallback curve, in pixels. Layout, like `MARGIN_PX` — what it
## has to be is VISIBLY not a solid line, and this is the size of a hand rather than a claim.
const FALLBACK_DASH_PX := 6.0

## The mechanical time constant this curve is drawn from, seconds. Straight from
## `Build.spin_up()`, with no arithmetic applied — the overlay has no second opinion about tau.
var tau_s := 0.0

## `MotorSpinUp.compute`'s own tier: `"recovered"`, `"fallback_r"`, or `"fallback_all:<reason>"`.
## The one field that decides whether the curve is a result or a constant.
var tier := ""

## The RPM the curve converges on — `Build.operating_rpm()`. Carried rather than recomputed for
## the reason that function was made public: two definitions of "the RPM this drone sits at" would
## let the overlay draw an approach to a point the tau does not describe, invisibly.
var final_rpm := 0.0

## Why there is nothing to draw, when there is nothing to draw. Empty when there is.
var refusal := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 190)
	# A Control does not clip its own `_draw` (the airframe room's finding).
	clip_contents = true
	# An overlay that ate clicks would make the model underneath it unrotatable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the overlay from a build. The only entry point, so the curve and the caption cannot
## describe different aircraft.
func adopt(build: Build) -> void:
	if build == null:
		tau_s = 0.0
		tier = ""
		final_rpm = 0.0
		refusal = "No drone open"
		queue_redraw()
		return
	var spin: Dictionary = build.spin_up()
	tau_s = float(spin.get("tau_s", 0.0))
	tier = String(spin.get("tier", ""))
	final_rpm = build.operating_rpm()
	refusal = "" if tau_s > 0.0 and final_rpm > 0.0 else "The model declines this motor"
	queue_redraw()


# ---------------------------------------------------------------------------
# The pure part
# ---------------------------------------------------------------------------

## Whether `p_tier` says the tau is a fallback rather than a recovered figure.
##
## A PREFIX test and not an equality one, because `MotorSpinUp._fallback_all` returns
## `"fallback_all:" + reason` — the tier where tau is ENTIRELY the constant is the one an equality
## test against `"fallback_all"` misses, which is the wrong way round.
static func is_fallback(p_tier: String) -> bool:
	return p_tier.begins_with("fallback")


## The first-order step response, in RPM, at `t_s` seconds after a step to `p_final_rpm`.
##
## This is the same law `MotorModel::step` integrates — `alpha = 1 − exp(−dt/tau)` applied from a
## standstill IS `final · (1 − exp(−t/tau))` — and `tests/test_spin_up_overlay.gd` asserts that by
## running the Rust one and comparing, rather than by restating the algebra in a comment. Drawing
## a curve the sim does not fly is the only way this overlay can lie about a number that is
## otherwise already on the panel.
static func rpm_at(t_s: float, p_tau_s: float, p_final_rpm: float) -> float:
	if p_tau_s <= 0.0:
		return 0.0
	return p_final_rpm * (1.0 - exp(-t_s / p_tau_s))


## How long the time axis runs, in seconds.
func span_s() -> float:
	return tau_s * AXIS_SPAN_TAUS


## (t, rpm) to a pixel on this canvas. Public and pure for the same reason
## `ThrustOverlay.to_pixels` is: where the curve lands is provable headless, and how it is coloured
## is not.
func to_pixels(t_s: float, rpm: float) -> Vector2:
	var inner := _inner_rect()
	var span := span_s()
	var x_frac := 0.0 if span <= 0.0 else clampf(t_s / span, 0.0, 1.0)
	var y_frac := 0.0 if final_rpm <= 0.0 else clampf(rpm / final_rpm, 0.0, 1.0)
	return Vector2(
		inner.position.x + x_frac * inner.size.x,
		inner.position.y + (1.0 - y_frac) * inner.size.y)


## The curve, as pixels, ready for `draw_polyline`. Empty when there is nothing to draw.
##
## Sampled once per pixel column of the plot, so the corner near t = 0 — the part of the shape a
## builder is actually comparing between two motors — is resolved by the canvas rather than by a
## sample count this file would have had to pick.
func curve_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if refusal != "" or tau_s <= 0.0 or final_rpm <= 0.0:
		return out
	var inner := _inner_rect()
	var columns := int(maxf(inner.size.x, 2.0))
	for i in columns + 1:
		var t := span_s() * float(i) / float(columns)
		out.append(to_pixels(t, rpm_at(t, tau_s, final_rpm)))
	return out


## What the tier means, in words. Empty for a recovered tau — there is nothing to warn about, and
## a note on every chart is a note nobody reads.
func tier_note() -> String:
	if not is_fallback(tier):
		return ""
	if tier.begins_with("fallback_all"):
		var reason := tier.substr(tier.find(":") + 1) if tier.contains(":") else ""
		return "tau is the 0.03 s fallback constant, not a computed one (%s)" % reason
	return "winding resistance is class-typical, not recovered from the thrust test"


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# The drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, PLATE_ALPHA), true)
	draw_string(font, Vector2(MARGIN_PX * 0.4, MARGIN_PX * 0.75), "How fast the motor arrives",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.94, 0.98))

	if refusal != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y * 0.5), refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.45))
		return

	var inner := _inner_rect()
	var axis := Color(0.45, 0.5, 0.58, 0.7)
	draw_line(inner.position + Vector2(0.0, inner.size.y), inner.position + inner.size, axis, 1.0)
	draw_line(inner.position, inner.position + Vector2(0.0, inner.size.y), axis, 1.0)

	var fallback := is_fallback(tier)
	var curve_colour := Color(0.85, 0.7, 0.45) if fallback else Color(0.45, 0.75, 1.0)
	var points := curve_points()
	if points.size() >= 2:
		if fallback:
			# Dashed, so a constant never looks like a result even at a glance. §4.3.
			var i := 0
			while i + 1 < points.size():
				var step := int(maxf(FALLBACK_DASH_PX, 1.0))
				var j: int = mini(i + step, points.size() - 1)
				draw_line(points[i], points[j], curve_colour, 2.0, true)
				i = j + step
		else:
			draw_polyline(points, curve_colour, 2.0, true)

	# The 63% mark — the one feature §4.1 asks for, and the point that IS tau by definition.
	var knee := to_pixels(tau_s, rpm_at(tau_s, tau_s, final_rpm))
	draw_line(Vector2(knee.x, inner.position.y), Vector2(knee.x, inner.position.y + inner.size.y),
		Color(1.0, 0.78, 0.35, 0.8), 1.0)
	draw_string(font, Vector2(minf(knee.x + 4.0, size.x - 96.0), inner.position.y + 12.0),
		"63%% at %.1f ms" % (tau_s * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(1.0, 0.82, 0.45))

	# The caption says whose curve this is and what it is not. "As modelled" because a first-order
	# lag is what `MotorModel` flies, not what a real motor does — §4.3's second paragraph. And the
	# four motors are named as one because the model carries one tau; see this file's header.
	var caption := "all four motors, as modelled  ·  arrives at %.0f rpm  ·  axis %.0f ms" % [
		final_rpm, span_s() * 1000.0]
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 8.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.72, 0.8))
	var note := tier_note()
	if note != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 22.0), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.7, 0.45))
