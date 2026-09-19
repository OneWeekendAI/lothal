class_name VibrationOverlay
extends Control
## What the pad lets through — the third of P10e's five analysis overlays.
##
## ## What it draws
##
## Transmissibility against frequency: the fraction of a disturbance at each frequency that
## reaches the gyro. One curve from `VibrationModel.mount_transmissibility`, the pad's own `f_n`
## marked, the region where the curve sits ABOVE one shaded as amplification and the region below
## one shaded as isolation, and this aircraft's three excitation frequencies — 1x, blade passing,
## motor electrical — dropped on as vertical lines at the RPM it is actually turning.
##
## The frequency axis is LOGARITHMIC, with decade gridlines. On this aircraft the motor's electrical
## excitation at hover is near a kilohertz and the pad sits near 141 Hz, so a linear ruler spends
## six sevenths of its width on a flat tail and squashes the hump — the reason §3.2 gives for this
## overlay existing — against the left edge. Transmissibility itself stays linear: it is a ratio
## read against T = 1, and a log Y would put that line wherever zero happens to fall.
##
## A transmissibility curve on its own is a property of a grommet, and a textbook has printed it.
## The same curve with THIS build's blade-passing line on it answers the question a builder has:
## is my prop exciting the band where this pad makes things worse? Nothing in Lothal has ever put
## those two facts on one picture, which is §0's bar.
##
## ## Why the curve comes from the model and not from here
##
## Every sample is `VibrationModel.mount_transmissibility(hz)` on the model
## `VibrationModel.for_build` settled — the same object the sim shakes the gyro with. The formula
## is not restated here in any form: not for the nominal curve, not for the damping band (which
## goes through `mount_transmissibility_at`, an extraction that sets the one field the formula
## reads zeta from), and not for the amplification test, which asks whether the SAMPLE is above
## one rather than comparing the frequency against a sqrt(2) written out again. A second copy of
## an isolator's response, free to drift, is the P10d defect in a new file.
##
## ## The two ways of having no pad, which are not the same way
##
## `SoftMount.f_n_hz` returns INF for a mount that is not fitted AND for a mount whose spec it
## declined to read — a Shore reading outside the sold band, a non-positive contact area, a zero
## grommet count, a tip mass it cannot carry. Both make transmissibility exactly 1.0, deliberately,
## so the vibration path reports what the frame does with nothing fitted rather than inventing a
## class-typical pad. **They must not render identically.** A flat line captioned "no soft mount"
## is honest for the first and is the overlay attributing a choice to a builder who made a
## different one in the second. So the caption comes from `SoftMount.compute`'s `tier` string,
## which exists for exactly this reader, and the declined case says a mount IS fitted, names the
## reason the model gave, and is drawn in the refusal colour rather than the bare-frame one.
##
## ## The hump's height is the least trustworthy thing on screen
##
## `SoftMount.DEFAULT_DAMPING_RATIO` decides how tall the peak is, and no vendor publishes it —
## soft_mount.gd's own comment calls it "the guess it always was". The peak is also the part of
## the picture a builder's eye goes to first, which is the worst possible pairing. So it is drawn
## as a BAND between the ends of the published range the default was picked from
## (`SoftMount.DAMPING_RATIO_LOW`/`HIGH`), and the caption says derived rather than measured —
## CampbellOverlay's posture with its arm mode, for the same reason.
##
## The band pinches to nothing where the curves cross, and that is not a drawing artefact: the
## crossover where amplification becomes isolation is independent of damping, so the one feature
## of this curve that does not depend on the guess is the one the band shows as certain.
##
## ## An overlay is not a room
##
## No state, no editing, no signals out — `ThrustOverlay`'s posture, for its reasons. The mapping
## and the captions are public and pure so both are provable headless.

## The margin around the plot, in pixels. Layout, not physics — and deliberately
## `ThrustOverlay.MARGIN_PX`'s value, as `CampbellOverlay` is: three charts that can be on screen
## together and rule their axes at different insets read as three charts about three aircraft.
const MARGIN_PX := 34.0

## How many samples the curve is drawn from. Resolution of a polyline, in the same category as
## MARGIN_PX — it changes how smooth the picture is and nothing about what it says.
const SAMPLE_COUNT := 160

## How far past the pad's own frequency the axis runs — and, on the other end, how far below the
## lowest feature it starts (`bottom_hz`), because a log axis has no zero. A ZOOM LEVEL, not a
## physical claim: the interesting structure is the hump and the crossover just above it, and an
## axis that stopped at f_n would cut the isolation region — the half of the picture that makes
## the other half worth looking at — off the right-hand edge. The axis still stretches past this
## whenever an excitation line lands further out, because a line drawn off-canvas is a line the
## builder is not told about.
const AXIS_SPAN_MULTIPLE := 4.0

## How much room to leave above the tallest curve, as a multiple of it. Layout, in MARGIN_PX's
## category — but not decoration: without it a BARE frame, whose curve is flat at exactly 1.0,
## draws unity along the top edge of the plot and the amplification region has no height at all.
## The one line every reading of this chart is made against would be indistinguishable from the
## frame around it.
const AXIS_HEADROOM := 1.1

## The frequency of each sample, hertz. Shared by all three curves.
var freq_hz := PackedFloat64Array()

## Transmissibility at each of `freq_hz`, at the damping the model is actually running.
var transmissibility := PackedFloat64Array()

## The same curve at the soft end of the published damping range — the taller hump.
var t_low_damping := PackedFloat64Array()

## And at the stiff end — the shorter one. Between the two is the band; see the class comment for
## why the band exists and why it pinches where it pinches.
var t_high_damping := PackedFloat64Array()

## The pad's natural frequency, or INF for both of the no-pad cases. Never a fallback: an INF here
## is a fact about the build and `tier` says which fact.
var mount_f_n_hz := INF

## `SoftMount.compute`'s tier — "computed", "no_mount", or "insufficient_data:<reason>". THE FIELD
## THAT KEEPS THE TWO INF CASES APART, which is this overlay's load-bearing decision.
var tier := "no_mount"

## Excitation name → frequency in hertz at the operating RPM, from `Build.excitation_orders()`
## through `CampbellOverlay.excitation_hz`. Reused rather than recomputed: `order · rpm / 60` has
## one implementation in this codebase and two readers.
var excitations: Dictionary = {}

## Where the aircraft sits while this is drawn — `Build.operating_rpm()`, the same operating point
## the thrust overlay draws its curve at and the Campbell diagram rules its hover line at. A curve
## whose vertical lines were placed at rated RPM would be a picture of a throttle position nobody
## is at.
var operating_rpm := 0.0

## False when `operating_rpm` is the cannot-hover fallback. A line captioned "hover" on an aircraft
## that cannot hover is a lie of one word.
var hovers := false

## Why there is nothing to draw, when there is nothing to draw. Empty when there is.
var refusal := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 190)
	# A Control does not clip its own `_draw` (the airframe room's finding).
	clip_contents = true
	# An overlay that ate clicks would make the model underneath it unrotatable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the overlay from a build. The only entry point, so a curve and a caption cannot describe
## different aircraft — and, here, so a curve drawn from one mount cannot be captioned with
## another mount's tier, which is the specific way this overlay would lie.
func adopt(build: Build) -> void:
	if build == null:
		freq_hz = PackedFloat64Array()
		transmissibility = PackedFloat64Array()
		t_low_damping = PackedFloat64Array()
		t_high_damping = PackedFloat64Array()
		mount_f_n_hz = INF
		tier = "no_mount"
		excitations = {}
		operating_rpm = 0.0
		hovers = false
		refusal = "No drone open"
		queue_redraw()
		return

	var model := VibrationModel.for_build(build)
	mount_f_n_hz = model.mount_hz()
	tier = model.mount_tier()
	operating_rpm = build.operating_rpm()
	hovers = build.can_hover()

	# Hoisted: `excitation_orders()` ASSEMBLES a dictionary, it does not hold one, so reading it
	# once per key and again per value builds the same fan twice a loop.
	var orders := build.excitation_orders()
	excitations = {}
	for order_name in orders:
		excitations[order_name] = CampbellOverlay.excitation_hz(
			float(orders[order_name]), operating_rpm)

	refusal = refusal_for(operating_rpm)
	_sample(model)
	queue_redraw()


## What is missing, in words. Empty when there is a curve to draw.
##
## A stopped aircraft excites nothing, so its vertical lines would all stack on the origin and the
## curve would be a picture of a pad nothing is shaking. Static and public so the rule is checked
## where it lives rather than restated in the test.
static func refusal_for(p_operating_rpm: float) -> String:
	return "" if p_operating_rpm > 0.0 else "This build turns nothing to shake the pad with"


# ---------------------------------------------------------------------------
# The pure part
# ---------------------------------------------------------------------------

## The caption for a mount, from `SoftMount.compute`'s tier. THE §3.3 RULE, in one function so it
## is checked where it lives.
##
## The three strings say three different things, and the second and third are the pair that matters:
## both draw a flat line at 1.0 because both have an INF `f_n`, and only these words tell a builder
## whether that flat line is the frame they chose or a pad the model would not read.
static func caption_for_tier(p_tier: String, f_n: float) -> String:
	if p_tier == "no_mount":
		return "No soft mount fitted — everything the props make reaches the gyro (T = 1.00)."
	if p_tier.begins_with("insufficient_data:"):
		return ("A mount IS fitted, and the model declined its spec (%s) — so it is drawn as no "
			+ "pad. This is NOT a bare frame; it is a mount Lothal could not read.") \
			% p_tier.trim_prefix("insufficient_data:")
	return "Soft mount, natural frequency %.0f Hz — derived from grommet specs, never measured." % f_n


## Whether a transmissibility value is amplification, isolation, or neither, from the VALUE rather
## than from the frequency.
##
## Written this way on purpose. The textbook statement of the rule is "below sqrt(2)·f_n a pad
## amplifies", and writing that here would put a second copy of the isolator's crossover in a file
## that has no business owning one — right up until someone changes the damping term and the
## shading and the curve disagree. Asking whether the sample the model returned is above unity
## cannot disagree with the model, because it IS the model's answer.
##
## THREE-WAY, and that is the fix rather than a nicety. T = 1 is not isolation: both no-pad cases
## are flat at exactly 1.0, so a two-way split labelled every excitation line on a bare frame
## "isolated" — a word a builder reads as a result, on a chart whose own caption two lines below
## says nothing is fitted. Unchanged is its own answer and it is the honest one.
static func region_at(t: float) -> String:
	if t > 1.0:
		return "amplified"
	if t < 1.0:
		return "isolated"
	return "passed through unchanged"


## The region an excitation frequency lands in, read off the SAMPLED curve the way `_draw` reads it
## — public so the words on the lines are provable headless, which is the only way this file is
## tested.
func region_at_hz(hz: float) -> String:
	var t := 1.0
	for i in freq_hz.size():
		if freq_hz[i] >= hz:
			t = transmissibility[i]
			break
	return region_at(t)


## The top of the frequency axis. Fitted to the picture's own content: far enough past the pad to
## show the isolation region, and always far enough to contain every excitation line, because a
## line off the edge is a warning the builder never gets.
func top_hz() -> float:
	var top := 0.0
	for order_name in excitations:
		top = maxf(top, float(excitations[order_name]))
	if is_finite(mount_f_n_hz) and mount_f_n_hz > 0.0:
		top = maxf(top, mount_f_n_hz * AXIS_SPAN_MULTIPLE)
	return top


## The bottom of the frequency axis, and the reason it exists at all: THE AXIS IS LOGARITHMIC, and
## a log axis has no zero to start at.
##
## It is logarithmic because of what this build actually looks like. The motor's electrical
## excitation at hover is near a kilohertz and the pad's own frequency is near 141 Hz, so on a
## linear ruler the amplification hump — the single feature §3.2 gives as the reason this overlay
## exists — is squashed into the left seventh of the plot and the crossover with it. A decade ruler
## gives the hump and the kilohertz line comparable room, which is what a builder is comparing.
##
## Symmetric with `top_hz`: the same zoom multiple, below the lowest feature instead of above the
## highest.
func bottom_hz() -> float:
	var low := INF
	for order_name in excitations:
		var hz := float(excitations[order_name])
		if hz > 0.0:
			low = minf(low, hz)
	if is_finite(mount_f_n_hz) and mount_f_n_hz > 0.0:
		low = minf(low, mount_f_n_hz)
	if not is_finite(low) or low <= 0.0:
		return 0.0
	return low / AXIS_SPAN_MULTIPLE


## The powers of ten inside the axis — the gridlines a log ruler is read against. Without them a
## reader has no way to tell a log axis from a linear one, and a mis-read decade is a factor of ten
## in the wrong direction.
func decade_gridlines() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var bottom := bottom_hz()
	var top := top_hz()
	if bottom <= 0.0 or top <= bottom:
		return out
	var exponent := int(ceil(log(bottom) / log(10.0)))
	while true:
		var hz: float = pow(10.0, float(exponent))
		if hz > top:
			break
		out.append(hz)
		exponent += 1
	return out


## The top of the transmissibility axis: the tallest point of the widest curve, and never below 1,
## so the unity line a whole half of this chart is defined against is always on the canvas.
func peak_t() -> float:
	var peak := 1.0
	for value in t_low_damping:
		peak = maxf(peak, value)
	for value in transmissibility:
		peak = maxf(peak, value)
	return peak * AXIS_HEADROOM


## (hz, T) to a pixel on this canvas. X is LOGARITHMIC (see `bottom_hz`); Y is not — transmissibility
## is a ratio around unity and the whole chart is read against the T = 1 line, which a log Y would
## put at the arbitrary place zero goes.
func to_pixels(hz: float, t: float) -> Vector2:
	var inner := _inner_rect()
	var top := top_hz()
	var bottom := bottom_hz()
	var x_frac := 0.0
	if top > bottom and bottom > 0.0 and hz > 0.0:
		x_frac = clampf(log(hz / bottom) / log(top / bottom), 0.0, 1.0)
	var y_frac := clampf(t / peak_t(), 0.0, 1.0)
	return Vector2(
		inner.position.x + x_frac * inner.size.x,
		inner.position.y + (1.0 - y_frac) * inner.size.y)


## One of the three curves, as pixels, ready for `draw_polyline`.
func curve_points(values: PackedFloat64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if values.size() != freq_hz.size():
		return out
	for i in values.size():
		out.append(to_pixels(freq_hz[i], values[i]))
	return out


## Samples the three curves off the settled model. The only place a number enters this file, and
## every one of them is `mount_transmissibility` answering about a frequency.
func _sample(model: VibrationModel) -> void:
	freq_hz = PackedFloat64Array()
	transmissibility = PackedFloat64Array()
	t_low_damping = PackedFloat64Array()
	t_high_damping = PackedFloat64Array()
	var top := top_hz()
	var bottom := bottom_hz()
	if top <= 0.0 or bottom <= 0.0 or top <= bottom:
		return
	# Sampled evenly in LOG space, to match the axis. Even spacing in linear hertz would put most
	# of the samples in the top decade, where the curve is a straight line, and leave the hump —
	# the narrowest and only interesting feature — resolved by a handful of them.
	var ratio := top / bottom
	for i in SAMPLE_COUNT + 1:
		var hz: float = bottom * pow(ratio, float(i) / float(SAMPLE_COUNT))
		freq_hz.append(hz)
		transmissibility.append(model.mount_transmissibility(hz))
		t_low_damping.append(
			model.mount_transmissibility_at(hz, SoftMount.DAMPING_RATIO_LOW))
		t_high_damping.append(
			model.mount_transmissibility_at(hz, SoftMount.DAMPING_RATIO_HIGH))


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# The drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := LothalTheme.draw_font()
	draw_style_box(LothalTheme.card_plate(), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(MARGIN_PX * 0.4, MARGIN_PX * 0.75), "What the pad lets through",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.94, 0.98))

	if refusal != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y * 0.5), refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.45))
		return

	var inner := _inner_rect()
	var axis := Color(0.45, 0.5, 0.58, 0.7)
	draw_line(inner.position + Vector2(0.0, inner.size.y), inner.position + inner.size, axis, 1.0)
	draw_line(inner.position, inner.position + Vector2(0.0, inner.size.y), axis, 1.0)

	# The decades. A log ruler that is not marked as one is a linear ruler to whoever reads it.
	for hz in decade_gridlines():
		var gx := to_pixels(hz, 0.0).x
		draw_line(Vector2(gx, inner.position.y), Vector2(gx, inner.position.y + inner.size.y),
			Color(0.45, 0.5, 0.58, 0.22), 1.0)
		draw_string(font, Vector2(gx + 2.0, inner.position.y + inner.size.y + 11.0),
			"%.0f" % hz, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.55, 0.62))

	# Unity first, under everything: it is the line the two regions are defined against, and the
	# whole point of the picture is which side of it a builder's harmonics land on.
	var unity_y := to_pixels(0.0, 1.0).y
	draw_line(Vector2(inner.position.x, unity_y),
		Vector2(inner.position.x + inner.size.x, unity_y), Color(0.8, 0.82, 0.88, 0.5), 1.0)
	draw_rect(Rect2(Vector2(inner.position.x, inner.position.y),
		Vector2(inner.size.x, maxf(unity_y - inner.position.y, 1.0))),
		Color(0.95, 0.45, 0.35, 0.10), true)
	draw_rect(Rect2(Vector2(inner.position.x, unity_y),
		Vector2(inner.size.x, maxf(inner.position.y + inner.size.y - unity_y, 1.0))),
		Color(0.45, 0.85, 0.65, 0.08), true)
	draw_string(font, Vector2(inner.position.x + 4.0, unity_y - 3.0), "T = 1  ·  above: worse "
		+ "than no pad", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.82, 0.88))

	# The damping band, under the curve for CampbellOverlay's reason: it is the thing the curve
	# sits inside, and a band painted over the curve would hide what it exists to qualify.
	var low := curve_points(t_low_damping)
	var high := curve_points(t_high_damping)
	if low.size() == high.size() and low.size() >= 2:
		var band := PackedVector2Array(low)
		for i in range(high.size() - 1, -1, -1):
			band.append(high[i])
		draw_colored_polygon(band, Color(0.55, 0.7, 1.0, 0.22))

	# The mount's own frequency, where the hump lives — drawn only when there is one. Both no-pad
	# cases have an INF f_n and get no line, and the caption below is what tells them apart.
	if is_finite(mount_f_n_hz) and mount_f_n_hz > 0.0:
		var at_fn := to_pixels(mount_f_n_hz, 0.0).x
		draw_line(Vector2(at_fn, inner.position.y),
			Vector2(at_fn, inner.position.y + inner.size.y), Color(0.55, 0.85, 0.7, 0.7), 1.0)
		draw_string(font, Vector2(minf(at_fn + 3.0, size.x - 62.0),
			inner.position.y + inner.size.y - 4.0), "f_n %.0f Hz" % mount_f_n_hz,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.9, 0.75))

	var curve := curve_points(transmissibility)
	if curve.size() >= 2:
		var flat := tier != "computed"
		draw_polyline(curve,
			Color(0.85, 0.7, 0.45) if tier.begins_with("insufficient_data:")
				else (Color(0.6, 0.64, 0.72) if flat else Color(0.45, 0.75, 1.0)), 2.0, true)

	# The excitation lines, at the RPM this aircraft is actually turning. Each is labelled with the
	# side of unity it lands on, because "your blade passing is in the amplification region" is the
	# sentence a builder came for and reading it off a colour is not the same as being told.
	var hues := [Color(0.45, 0.75, 1.0), Color(1.0, 0.78, 0.35), Color(0.75, 0.6, 1.0)]
	var index := 0
	for order_name in excitations:
		var hz := float(excitations[order_name])
		if hz >= bottom_hz() and hz <= top_hz():
			var at := to_pixels(hz, 0.0)
			draw_line(Vector2(at.x, inner.position.y),
				Vector2(at.x, inner.position.y + inner.size.y),
				hues[index % hues.size()], 1.0)
			draw_string(font, Vector2(minf(at.x + 3.0, size.x - 116.0),
				inner.position.y + 12.0 + 11.0 * index),
				"%s: %s" % [str(order_name), region_at_hz(hz)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hues[index % hues.size()])
		index += 1

	# The caption names WHICH kind of nothing a flat line is, and says the hump's height is
	# derived. Both are the §3.3 rules, in words rather than left to a reader's inference.
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 20.0), caption_for_tier(tier, mount_f_n_hz),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.7, 0.45)
			if tier.begins_with("insufficient_data:") else Color(0.68, 0.72, 0.8))
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 6.0),
		"%.0f-%.0f Hz, log scale, at %.0f rpm (%s)  ·  band = damping zeta %.2f-%.2f, a guess, not a spec"
			% [bottom_hz(), top_hz(), operating_rpm, "hover" if hovers else "flat out",
				SoftMount.DAMPING_RATIO_LOW, SoftMount.DAMPING_RATIO_HIGH],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.72, 0.8))
