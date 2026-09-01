class_name ThrustOverlay
extends Control
## Where the fitted blade makes its thrust — the first of P10e's five analysis overlays.
##
## ## What it draws
##
## dT/dr against radius for the propeller this drone currently flies, at the RPM it currently
## flies at (`Build.operating_rpm()`). One curve, its peak marked in r/R, and the BEMT's own total
## under it. Nothing is fitted, smoothed or resampled: the plotted points are the annuli of the
## solve, at the radii the solve placed them.
##
## ## Why the numbers come from Rust and not from here
##
## `BemtModel.thrust_distribution` returns the per-annulus `[r_m, dT_N]` pairs from INSIDE
## `solve_impl`'s own loop. The alternative — walking the chord table in GDScript and integrating
## it here — is the defect P10d spent a slice deleting from `PropellerMesh`: a second copy of a
## definition, free to drift from the first, with nothing to say which copy is the propeller. So
## this file does exactly two arithmetic things to what it is handed, both of them reversible:
## it divides dT by the annulus width to get a density, and it maps that density to pixels.
##
## The annulus width comes from the returned grid (`r[1] − r[0]`) rather than from the diameter,
## for the same reason. `dr` is a property of how the solve chose to discretise the disc; a
## constant here would be this file having its own opinion about that.
##
## ## An overlay is not a room
##
## No state, no editing, no signals out. It reads a Build, draws, and is thrown away — which is
## what lets it sit over the Lab viewport without owning any of it. The mapping functions below
## are public and pure so the geometry is provable headless, the split
## `PropellerPlanformEditor`/`PlanformEdits` already makes one level down.

## The margin around the plot, in pixels. Room for the axis labels and the peak callout, and
## nothing more.
const MARGIN_PX := 34.0

## How opaque the backing plate is. Matched to `GlassShell.GLASS_ALPHA` in intent rather than
## imported from it: a curve read against a turning airframe needs the same treatment the panels
## carrying numbers get, and an overlay that borrowed the shell's constant would not be usable
## over anything else.
const PLATE_ALPHA := 0.86

## `[r_m, dT_N]` interleaved, exactly as `Build.thrust_distribution()` returned it. Empty means
## the solve DECLINED this rotor — a different answer from a blade that makes no thrust, and
## drawn differently below.
var distribution := PackedFloat64Array()

## The blade's tip radius in metres, for the r/R axis. Carried alongside rather than inferred
## from the last annulus, because the last annulus sits half a `dr` inside the tip and an axis
## that ended at 0.99 would be quietly wrong at exactly the end a builder is looking at.
var radius_m := 0.0

## What the rotor is doing while this is drawn, for the caption. Purely descriptive.
var operating_rpm := 0.0

## Why there is nothing to draw, when there is nothing to draw. Empty when there is.
var refusal := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 190)
	# A Control does not clip its own `_draw` (the airframe room's finding), and a curve drawn
	# from a stale distribution during a refit would paint over the viewport around it.
	clip_contents = true
	# An overlay that ate clicks would make the model underneath it unrotatable, which is the
	# one thing a full-bleed viewport exists for.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the overlay from a build. The only entry point, so there is no way to render a curve and
## a caption that describe different aircraft.
func adopt(build: Build) -> void:
	if build == null:
		distribution = PackedFloat64Array()
		radius_m = 0.0
		operating_rpm = 0.0
		refusal = "No drone open"
		queue_redraw()
		return
	distribution = build.thrust_distribution()
	radius_m = float(build.prop_geometry().diameter_m) * 0.5
	operating_rpm = build.operating_rpm()
	refusal = refusal_for(distribution)
	queue_redraw()


## The solve's own refusal, turned into words. Empty when there is a curve to draw.
##
## `BemtModel.thrust_distribution` returns an EMPTY array for a rotor it declines — no blades, no
## disc, stopped, or a chord table too short to be a planform — and rendering that as a flat line
## at zero would be the overlay inventing an answer the model refused to give. Two annuli is the
## floor for a curve, so four numbers is the floor for a distribution.
##
## Static and public so the rule is checked where it lives rather than restated in the test, which
## would be a check that passes whatever this function does.
static func refusal_for(pairs: PackedFloat64Array) -> String:
	return "" if pairs.size() >= 4 else "The model declines this rotor"


# ---------------------------------------------------------------------------
# The pure part
# ---------------------------------------------------------------------------

## The annulus width the solve used, off the returned grid. 0.0 for anything too short to have
## one, so callers divide by it only after checking.
static func annulus_width_m(pairs: PackedFloat64Array) -> float:
	if pairs.size() < 4:
		return 0.0
	return pairs[2] - pairs[0]


## dT/dr in newtons per metre, one value per annulus, in the solve's own order.
##
## This is the ONLY transformation applied to what Rust returned, and it is a division by a
## constant — so the curve's shape is the solve's shape, and a reader comparing two blades is
## comparing the model rather than this file's opinion of it.
static func density_n_per_m(pairs: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var width := annulus_width_m(pairs)
	if width <= 0.0:
		return out
	var i := 1
	while i < pairs.size():
		out.append(pairs[i] / width)
		i += 2
	return out


## The total thrust the plotted annuli carry — the sum of the pairs, in the order they were
## returned.
##
## BIT-IDENTICAL to `BemtModel.solve(...)[0]` for the same arguments, and that is a checked
## property rather than a hope (tests/test_thrust_overlay.gd asserts it with `==`, not with a
## tolerance). It holds because the pairs ARE the addends of that sum: same values, same order,
## same IEEE additions. If this ever stops being exact, the overlay has stopped drawing the solve
## and the right response is to find out why, not to loosen the assertion.
static func total_n(pairs: PackedFloat64Array) -> float:
	var total := 0.0
	var i := 1
	while i < pairs.size():
		total += pairs[i]
		i += 2
	return total


## Index into the DENSITY array of the annulus carrying the most thrust per metre. −1 for empty.
##
## The number a builder came for: "where does this blade actually work". A tapered tip-unloaded
## blade and a flat-planform preset of the same diameter put it in visibly different places, and
## before this overlay there was nowhere in Lothal that difference appeared.
static func peak_index(pairs: PackedFloat64Array) -> int:
	var densities := density_n_per_m(pairs)
	var best := -1
	var best_value := -INF
	for i in densities.size():
		if densities[i] > best_value:
			best_value = densities[i]
			best = i
	return best


## The radius, as a fraction of the tip radius, of annulus `index`. −1.0 when there is no such
## annulus or no tip to measure against.
static func r_frac_at(pairs: PackedFloat64Array, index: int, p_radius_m: float) -> float:
	if p_radius_m <= 0.0 or index < 0 or index * 2 >= pairs.size():
		return -1.0
	return pairs[index * 2] / p_radius_m


## (r/R, dT/dr) to a pixel on this canvas. Public and pure for the planform editor's reason: where
## the curve LANDS is provable without a window, and how it is coloured is not.
##
## The vertical scale is fitted to this blade's own peak, not to a fixed newtons-per-metre. Two
## props are compared by SHAPE here — a shared scale would flatten a 3" blade to nothing beside a
## 10" one, and the question the overlay answers is where the load sits, not how big it is.
func to_pixels(r_frac: float, density: float) -> Vector2:
	var inner := _inner_rect()
	var peak := _peak_density()
	var y_frac := 0.0 if peak <= 0.0 else clampf(density / peak, 0.0, 1.0)
	return Vector2(
		inner.position.x + clampf(r_frac, 0.0, 1.0) * inner.size.x,
		inner.position.y + (1.0 - y_frac) * inner.size.y)


## The curve, as pixels, ready for `draw_polyline`. Empty when there is nothing to draw.
func curve_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius_m <= 0.0:
		return out
	var densities := density_n_per_m(distribution)
	for i in densities.size():
		out.append(to_pixels(distribution[i * 2] / radius_m, densities[i]))
	return out


func _peak_density() -> float:
	var densities := density_n_per_m(distribution)
	var peak := 0.0
	for value in densities:
		peak = maxf(peak, value)
	return peak


func _inner_rect() -> Rect2:
	return Rect2(Vector2(MARGIN_PX, MARGIN_PX),
		Vector2(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0)))


# ---------------------------------------------------------------------------
# The drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var plate := Color(0.06, 0.07, 0.09, PLATE_ALPHA)
	draw_rect(Rect2(Vector2.ZERO, size), plate, true)

	var title := "Thrust along the blade"
	draw_string(font, Vector2(MARGIN_PX * 0.4, MARGIN_PX * 0.75), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.94, 0.98))

	if refusal != "":
		draw_string(font, Vector2(MARGIN_PX * 0.4, size.y * 0.5), refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.45))
		return

	var inner := _inner_rect()
	var axis := Color(0.45, 0.5, 0.58, 0.7)
	draw_line(inner.position + Vector2(0.0, inner.size.y),
		inner.position + inner.size, axis, 1.0)
	draw_line(inner.position, inner.position + Vector2(0.0, inner.size.y), axis, 1.0)

	var points := curve_points()
	if points.size() >= 2:
		# Filled under the curve, because the AREA is the thrust — the overlay's whole subject is
		# a quadrature, and an outline alone reads as a signal rather than as an integral.
		var filled := PackedVector2Array(points)
		filled.append(Vector2(points[points.size() - 1].x, inner.position.y + inner.size.y))
		filled.append(Vector2(points[0].x, inner.position.y + inner.size.y))
		draw_colored_polygon(filled, Color(0.35, 0.62, 0.95, 0.28))
		draw_polyline(points, Color(0.45, 0.75, 1.0), 2.0, true)

	var peak := peak_index(distribution)
	var peak_frac := r_frac_at(distribution, peak, radius_m)
	if peak_frac >= 0.0:
		var at := to_pixels(peak_frac, _peak_density())
		draw_line(Vector2(at.x, inner.position.y), Vector2(at.x, inner.position.y + inner.size.y),
			Color(1.0, 0.78, 0.35, 0.8), 1.0)
		draw_string(font, Vector2(minf(at.x + 4.0, size.x - 60.0), inner.position.y + 12.0),
			"peak %.2f R" % peak_frac, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.82, 0.45))

	# The caption says WHOSE total this is. The BEMT's, at this RPM — not the panel's thrust
	# figure, which carries the catalog's fitted k_t and the guard's static factor on top. Two
	# numbers a builder could read as the same number is exactly how an overlay lies.
	var caption := "BEMT total %.2f N per blade set  ·  %.0f rpm  ·  area = thrust" % [
		total_n(distribution), operating_rpm]
	draw_string(font, Vector2(MARGIN_PX * 0.4, size.y - 8.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.72, 0.8))
	draw_string(font, Vector2(inner.position.x, size.y - 22.0), "0",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.6, 0.68))
	draw_string(font, Vector2(inner.position.x + inner.size.x - 16.0, size.y - 22.0), "R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.6, 0.68))
