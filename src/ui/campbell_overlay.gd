class_name CampbellOverlay
extends Control
## Which RPM this airframe rings at — the second of P10e's five analysis overlays.
##
## ## What it draws
##
## Frequency up, RPM across, from a stopped rotor to the motor's rated RPM. Three straight
## excitation lines rise through the origin — one per revolution (imbalance), one per blade per
## revolution (blade passing), one per POLE PAIR per revolution (the motor's electrical drive) —
## and the structure's own resonances lie across them. Where a line meets a resonance, that RPM
## is marked; the aircraft's own hover RPM is a vertical line through the whole diagram, so a
## builder can see at a glance whether a crossing is one they fly THROUGH or one they SIT ON.
##
## ## The number nobody can see is wrong
##
## The electrical line is `pole_pairs × rpm/60`. A 14-pole motor at 10,000 rpm excites at
## 1166.67 Hz — not 1400 (poles instead of pole pairs) and not 583.33 (a stray half the other
## way). All three are plausible-looking lines on a plausible-looking diagram, which is exactly
## why this file does not compute the number: `Build.excitation_orders()` hands it over, and it
## reads `Build.pole_pairs()`, which has carried the halving and the comment saying why since
## long before this overlay existed.
##
## ## The resonance is a BAND, and that is the whole design
##
## `VibrationModel.REFERENCE_RESONANCE_HZ` is 180 Hz and its own comment says "No source. There
## is no source." Every frame's mode in Lothal is a ratio to that guess. LTHL-18 went looking for
## it in blackbox logs and found the 1× line sweeps 155-235 Hz inside one analysis frame, so no
## peak survives to be measured; LTHL-49 built an impact test that was never run on hardware;
## LTHL-50 is a pre-registered third attempt. **A hairline drawn at a number this project has
## twice failed to measure would be the most dishonest thing in the room** — it would read as
## "your frame rings HERE" when the model can only say "somewhere around here". So it is a strip,
## labelled derived, and the caption says so in words rather than leaving it to a reader to infer
## from the fact that it is fuzzy.
##
## ## An overlay is not a room
##
## No state, no editing, no signals out — `ThrustOverlay`'s posture, for its reasons. The mapping
## functions are public and pure so the geometry is provable headless.

## The margin around the plot, in pixels. Layout, not physics — `ThrustOverlay.MARGIN_PX`'s
## category and, deliberately, its value: two overlays that can be on screen together and rule
## their axes at different insets would read as two charts about two aircraft.
const MARGIN_PX := 34.0

## HALF-WIDTH OF THE RESONANCE BAND, as a fraction of the resonance frequency. NOT a free
## constant: it is `ArmBeam`'s own error bar, quoted twice in `src/airframe/arm_beam.gd` — "first
## bending mode ... honestly +/-20%" in its honesty tiers, and again where its integration error
## is called "deep in the noise against the +/-20% the physics itself is quoted at". That is the
## tightest defensible number in the codebase for how well this project believes it knows an arm's
## first mode.
##
## IT IS A FLOOR AND NOT A BOUND, and this is the honest part. ArmBeam's ±20% is the uncertainty
## of a mode COMPUTED from a frame whose geometry is known. The number drawn here comes from
## `VibrationModel.resonance_hz_for`, which scales a GUESSED 180 Hz anchor — an unmeasured
## quantity has no error bar at all, and the true width is unknowable until LTHL-50 or a rewiring
## to ArmBeam lands. Drawing it at the computed model's width says "at least this wide"; the
## caption says derived rather than measured so the band is not read as a measurement's error bar.
## Widening it to a guess of a guess would have been inventing a second number to dress up the
## first.
const RESONANCE_BAND_FRAC := 0.20

## Per-rev multipliers, name → order, exactly as `Build.excitation_orders()` returned them.
var orders: Dictionary = {}

## The right-hand edge of the RPM axis: what the motor is rated at.
var rated_rpm := 0.0

## The highest RPM this build can actually turn. Everything above it is shaded, because a
## crossing there is one the aircraft cannot reach.
var reachable_rpm := 0.0

## Where the aircraft actually sits. `Build.operating_rpm()` — hover throttle × rated when it
## hovers, rated when it cannot — the SAME operating point the thrust overlay draws at and the
## spin-up linearises at. A third definition of "the RPM this drone sits at" would put this
## overlay's vertical line and that overlay's curve on different aircraft.
var hover_rpm := 0.0

## False when `hover_rpm` is the cannot-hover fallback rather than a hover, so the label can say
## which. A vertical line captioned "hover" on an aircraft that cannot hover is a lie of one word.
var hovers := false

## The arm's first bending mode, from `VibrationModel.for_build` — which is where the tip mass,
## the pad's own mass and the arm-length scaling already meet. Derived, not measured; see above.
var resonance_hz := 0.0

## The fitted soft-mount pad's natural frequency, or INF for no pad AND for a pad whose spec
## `SoftMount` declined to read. Those two are not the same thing and Overlay 3 must tell them
## apart; here they render identically as "no line", which is honest for both — this diagram
## draws resonances that exist, and neither case gives it one.
var mount_hz := INF

## Why there is nothing to draw, when there is nothing to draw. Empty when there is.
var refusal := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 190)
	# A Control does not clip its own `_draw` (the airframe room's finding).
	clip_contents = true
	# An overlay that ate clicks would make the model underneath it unrotatable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the overlay from a build. The only entry point, so a diagram and its caption cannot
## describe different aircraft.
func adopt(build: Build) -> void:
	if build == null:
		orders = {}
		rated_rpm = 0.0
		reachable_rpm = 0.0
		hover_rpm = 0.0
		hovers = false
		resonance_hz = 0.0
		mount_hz = INF
		refusal = "No drone open"
		queue_redraw()
		return
	orders = build.excitation_orders()
	rated_rpm = build.rated_rpm()
	reachable_rpm = build.reachable_rpm()
	hover_rpm = build.operating_rpm()
	hovers = build.can_hover()
	var vibration := VibrationModel.for_build(build)
	resonance_hz = vibration.resonance_hz
	mount_hz = vibration.mount_hz()
	refusal = refusal_for(orders, rated_rpm)
	queue_redraw()


## What is missing, in words. Empty when there is a diagram to draw.
##
## A Campbell diagram needs an RPM range and at least one order; without either there is nothing
## to plot, and drawing empty axes with a hover line on them would be the overlay presenting a
## frame as an answer. Static and public so the rule is checked where it lives.
static func refusal_for(p_orders: Dictionary, p_rated_rpm: float) -> String:
	if p_rated_rpm <= 0.0:
		return "This build has no RPM range to sweep"
	return "" if p_orders.size() > 0 else "This build excites nothing the model can name"


# ---------------------------------------------------------------------------
# The pure part
# ---------------------------------------------------------------------------

## The frequency an order of `order` per revolution forces at, at `rpm`.
##
## THE ONE ARITHMETIC FACT IN THIS FILE: revolutions per minute over sixty is revolutions per
## second, and an order is a multiple of that. The orders themselves — 1, blade count, pole PAIRS
## — come from the build and are not derived here.
static func excitation_hz(order: float, rpm: float) -> float:
	return order * rpm / 60.0


## The RPM at which an order of `order` crosses `hz`. INF when there is no such RPM: an order of
## zero never reaches anything, and a resonance at INF (no pad fitted) is never reached either.
static func crossing_rpm(order: float, hz: float) -> float:
	if order <= 0.0 or not is_finite(hz) or hz <= 0.0:
		return INF
	return hz * 60.0 / order


## The crossing to MARK, or −1.0 for one that must not be marked because the aircraft cannot get
## there.
##
## The envelope is `reachable_rpm` — full throttle against whichever of the motor, pack and ESC
## limits binds first — not the rated RPM the axis ends at. Marking a crossing between the two
## would be the diagram telling a builder to avoid a throttle setting their build does not have.
static func markable_crossing_rpm(order: float, hz: float, p_reachable_rpm: float) -> float:
	var at := crossing_rpm(order, hz)
	if not is_finite(at) or p_reachable_rpm <= 0.0 or at > p_reachable_rpm:
		return -1.0
	return at


## The resonance band, as `[low Hz, high Hz]`, empty for a frequency there is no band around. See
## `RESONANCE_BAND_FRAC` for why this is a strip and not a line, which is the load-bearing
## decision of this overlay.
##
## A PackedFloat64Array rather than the Vector2 this was first written as, and the reason is worth
## a line: **Vector2's components are 32-bit**. The band's half-width is a FRACTION of the
## frequency, and a check asserting that the fraction is the same on two frames read it as
## differing in the eighth digit — a real defect in this file, found by the check, in the units
## the check was about rather than in the picture.
static func band_hz(res_hz: float) -> PackedFloat64Array:
	if res_hz <= 0.0 or not is_finite(res_hz):
		return PackedFloat64Array()
	return PackedFloat64Array([
		res_hz * (1.0 - RESONANCE_BAND_FRAC), res_hz * (1.0 + RESONANCE_BAND_FRAC)])


## The top of the frequency axis: the highest order at the highest RPM on the axis, so every line
## drawn fits and the steepest one lands exactly in the corner.
##
## Fitted to the diagram's own content rather than to a fixed hertz-per-pixel, for
## `ThrustOverlay`'s reason: a 14-pole motor and a 12-pole one are compared by where their
## crossings sit, not by how tall their lines are.
func peak_hz() -> float:
	var top := 0.0
	# `order_name` rather than `name`, which would shadow `Node.name` — a warning, and
	# `project.godot` makes warnings errors.
	for order_name in orders:
		top = maxf(top, excitation_hz(float(orders[order_name]), rated_rpm))
	# A resonance above every excitation line still has to be visible, or the diagram would show
	# an airframe that rings out of reach by not showing it at all.
	var band := band_hz(resonance_hz)
	if band.size() == 2:
		top = maxf(top, band[1])
	if is_finite(mount_hz):
		top = maxf(top, mount_hz)
	return top


## (rpm, hz) to a pixel on this canvas.
func to_pixels(rpm: float, hz: float) -> Vector2:
	var inner := _inner_rect()
	var top := peak_hz()
	var x_frac := 0.0 if rated_rpm <= 0.0 else clampf(rpm / rated_rpm, 0.0, 1.0)
	var y_frac := 0.0 if top <= 0.0 else clampf(hz / top, 0.0, 1.0)
	return Vector2(
		inner.position.x + x_frac * inner.size.x,
		inner.position.y + (1.0 - y_frac) * inner.size.y)


## One excitation line, origin to the right-hand edge of the axis.
func line_points(order: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if rated_rpm <= 0.0 or order <= 0.0:
		return out
	out.append(to_pixels(0.0, 0.0))
	out.append(to_pixels(rated_rpm, excitation_hz(order, rated_rpm)))
	return out


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# The drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := LothalTheme.draw_font()
	draw_style_box(LothalTheme.card_plate(), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(MARGIN_PX * 0.4, MARGIN_PX * 0.75), "Where this airframe rings",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.94, 0.98))

	if refusal != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y * 0.5), refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.45))
		return

	var inner := _inner_rect()
	var axis := Color(0.45, 0.5, 0.58, 0.7)
	draw_line(inner.position + Vector2(0.0, inner.size.y), inner.position + inner.size, axis, 1.0)
	draw_line(inner.position, inner.position + Vector2(0.0, inner.size.y), axis, 1.0)

	# Above the throttle limit, hatched out first so every line drawn over it reads as reaching
	# INTO a region rather than through open air.
	if reachable_rpm > 0.0 and reachable_rpm < rated_rpm:
		var edge := to_pixels(reachable_rpm, 0.0).x
		draw_rect(Rect2(Vector2(edge, inner.position.y),
			Vector2(inner.position.x + inner.size.x - edge, inner.size.y)),
			Color(0.5, 0.52, 0.58, 0.14), true)
		draw_string(font, Vector2(edge + 3.0, inner.position.y + inner.size.y - 4.0),
			"can't reach", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.62, 0.68))

	# The band, under the lines: it is the thing they cross, and a strip drawn on top of them
	# would hide the crossings it exists to explain.
	var band := band_hz(resonance_hz)
	if band.size() == 2:
		var lo := to_pixels(0.0, band[0])
		var hi := to_pixels(0.0, band[1])
		draw_rect(Rect2(Vector2(inner.position.x, hi.y),
			Vector2(inner.size.x, maxf(lo.y - hi.y, 1.0))),
			Color(0.95, 0.45, 0.35, 0.20), true)
		draw_string(font, Vector2(inner.position.x + 4.0, hi.y - 3.0),
			"arm mode ~%.0f Hz ±%d%% (derived, not measured)"
				% [resonance_hz, int(RESONANCE_BAND_FRAC * 100.0)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.62, 0.55))

	if is_finite(mount_hz):
		var pad := to_pixels(0.0, mount_hz)
		draw_line(Vector2(inner.position.x, pad.y),
			Vector2(inner.position.x + inner.size.x, pad.y), Color(0.55, 0.85, 0.7, 0.8), 1.0)
		draw_string(font, Vector2(inner.position.x + 4.0, pad.y - 3.0),
			"soft mount %.0f Hz" % mount_hz, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.6, 0.9, 0.75))

	var hues := [Color(0.45, 0.75, 1.0), Color(1.0, 0.78, 0.35), Color(0.75, 0.6, 1.0)]
	var index := 0
	for order_name in orders:
		var order := float(orders[order_name])
		var points := line_points(order)
		if points.size() == 2:
			draw_polyline(points, hues[index % hues.size()], 1.6, true)
			draw_string(font, Vector2(minf(points[1].x - 74.0, size.x - 78.0), points[1].y + 11.0),
				str(order_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hues[index % hues.size()])
		var at := markable_crossing_rpm(order, resonance_hz, reachable_rpm)
		if at >= 0.0:
			var mark := to_pixels(at, resonance_hz)
			draw_circle(mark, 3.0, hues[index % hues.size()])
		index += 1

	if hover_rpm > 0.0:
		var at_hover := to_pixels(hover_rpm, 0.0).x
		draw_line(Vector2(at_hover, inner.position.y),
			Vector2(at_hover, inner.position.y + inner.size.y), Color(1.0, 1.0, 1.0, 0.55), 1.0)
		draw_string(font, Vector2(minf(at_hover + 3.0, size.x - 52.0), inner.position.y + 11.0),
			"hover" if hovers else "flat out", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.9, 0.92, 0.96))

	# The caption names the band's status, because the band is the part a builder is most likely
	# to read as a measurement. "Derived" is doing the same job "BEMT total" does on the thrust
	# overlay: naming whose number this is before anyone acts on it.
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 8.0),
		"0-%.0f rpm  ·  arm mode derived from a scaling law, never measured" % rated_rpm,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.72, 0.8))
