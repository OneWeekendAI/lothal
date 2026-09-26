class_name PropulsionDiagram
extends Control
## The drawing on a Propulsion item page (lab dock design §2, §3) — FramePlanDiagram's sibling.
## Read-only; every figure comes from `PropulsionFigures`, the same calls the row and the page's two
## numbers read, so the picture cannot disagree with them.
##
##   - `thrust` (Motors): thrust per motor against throttle on THIS pack, sag included, to the
##     throttle ceiling; the peak (the row's number), the hover line, the ceiling and what binds it,
##     and the catalogue's test figure as a labelled reference line — so "1047 g" and "1450 g" are
##     visibly two different measurements, not a contradiction.
##   - `prop` (Propellers): the blade in plan, from the Prop sheet's own PropellerDocument chord
##     table, one per blade on the swept disc, diameter dimensioned.
##   - `guard` (Prop guards): one motor's disc and the guard ring at its spec radii, the tip gap
##     marked in mm; the bare disc when none is fitted.

const MODE_THRUST := "thrust"
const MODE_PROP := "prop"
const MODE_GUARD := "guard"

const CURVE_SAMPLES := 60
const MARGIN_PX := 44.0

var mode := ""

# Thrust
var curve: Array = []
var peak := Vector2.ZERO
var hover_g := 0.0
var ceiling: Dictionary = {}
var catalogue: Dictionary = {}

# Prop
var blade: PropellerDocument

# Guard
var tip_radius_mm := 0.0
var ring_inner_mm := 0.0
var ring_outer_mm := 0.0
var gap_mm := NAN
var guard_kind := ""


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func show_build(build: Build, p_mode: String) -> void:
	mode = p_mode
	curve = []
	blade = null
	ring_inner_mm = 0.0
	ring_outer_mm = 0.0
	gap_mm = NAN
	guard_kind = ""
	if build == null:
		queue_redraw()
		return
	match mode:
		MODE_THRUST:
			curve = PropulsionFigures.thrust_curve_each_g(build, CURVE_SAMPLES)
			peak = Vector2(float(build.peak_thrust()["throttle"]), PropulsionFigures.peak_each_g(build))
			hover_g = PropulsionFigures.hover_each_g(build)
			ceiling = PropulsionFigures.throttle_ceiling(build)
			catalogue = PropulsionFigures.catalogue_test(build)
		MODE_PROP:
			blade = PropellerDetails.document_for(build.propeller)
		MODE_GUARD:
			var doc := PropellerDetails.document_for(build.propeller)
			tip_radius_mm = doc.radius_mm() if doc != null else 0.0
			if not build.guard.is_empty():
				var specs: Dictionary = build.guard.get("specs", {})
				ring_outer_mm = float(specs.get("outer_radius_mm", 0.0))
				ring_inner_mm = ring_outer_mm - float(specs.get("wall_mm", 0.0))
				gap_mm = PropulsionFigures.guard_tip_gap_mm(build)
				guard_kind = str(specs.get("kind", ""))
	queue_redraw()


func blade_count() -> int:
	return blade.blades if blade != null else 0


## The reference line's caption: the catalogue figure named as the test it came from.
func catalogue_label() -> String:
	if catalogue.is_empty() or float(catalogue.get("grams", 0.0)) <= 0.0:
		return ""
	var where := ""
	if str(catalogue.get("prop", "")) != "":
		where = " · %s at %s V test" % [catalogue["prop"], _trim(float(catalogue["volts"]))]
	return "catalogue %d g%s" % [roundi(float(catalogue["grams"])), where]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match mode:
		MODE_THRUST:
			_draw_thrust()
		MODE_PROP:
			_draw_prop()
		MODE_GUARD:
			_draw_guard()


# ---------------------------------------------------------------------------
# Thrust against throttle
# ---------------------------------------------------------------------------

func _thrust_plot() -> Rect2:
	return Rect2(Vector2(MARGIN_PX + 14.0, 30.0),
		size - Vector2(MARGIN_PX + 14.0 + 24.0, 30.0 + MARGIN_PX))


func _thrust_top_g() -> float:
	return maxf(peak.y, float(catalogue.get("grams", 0.0))) * 1.12


func _thrust_y(grams: float) -> float:
	var plot := _thrust_plot()
	return plot.end.y - grams / _thrust_top_g() * plot.size.y


## The grams gridlines' y, px, bottom up — what `_draw_thrust` rules.
func gridline_ys() -> Array:
	var out: Array = []
	var top_g := _thrust_top_g()
	if top_g <= 0.0:
		return out
	var step := _round_step(top_g / 5.0)
	var g := 0.0
	while g <= top_g:
		out.append(_thrust_y(g))
		g += step
	return out


## The catalogue reference line's y, px.
func catalogue_line_y() -> float:
	return _thrust_y(float(catalogue.get("grams", 0.0)))


## Where the catalogue caption is drawn, as the box its text occupies. Above its dashed line
## unless a gridline runs through that box (1450 g sits 14 px under the 1500 g line on the
## reference build), then below it.
func catalogue_label_rect() -> Rect2:
	var text := catalogue_label()
	if text == "" or _thrust_top_g() <= 0.0:
		return Rect2()
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var height := font.get_height(LothalTheme.FONT_SIZE_SMALL)
	var x := _thrust_plot().position.x + 8.0
	var line := catalogue_line_y()
	var above := Rect2(Vector2(x, line - 4.0 - height), Vector2(width, height))
	var below := Rect2(Vector2(x, line + 4.0), Vector2(width, height))
	for y in gridline_ys():
		if float(y) >= above.position.y - 1.0 and float(y) <= above.end.y + 1.0:
			return below
	return above


func _draw_thrust() -> void:
	if curve.is_empty():
		return
	var plot := _thrust_plot()
	var top_g := _thrust_top_g()
	if top_g <= 0.0:
		return
	var to_px := func(t: float, grams: float) -> Vector2:
		return Vector2(plot.position.x + t * plot.size.x, plot.end.y - grams / top_g * plot.size.y)

	# Grid and axes: throttle every 25%, grams on a round step.
	var grid := Color(LothalTheme.BORDER, 0.6)
	for i in 5:
		var x: float = to_px.call(i * 0.25, 0.0).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid, 1.0)
		_text(Vector2(x - 12.0, plot.end.y + 16.0), "%d%%" % (i * 25), LothalTheme.TEXT_MUTED)
	var step := _round_step(top_g / 5.0)
	var g := 0.0
	while g <= top_g:
		var y: float = to_px.call(0.0, g).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
		_text(Vector2(4.0, y + 4.0), "%d g" % roundi(g), LothalTheme.TEXT_MUTED)
		g += step
	_text(Vector2(plot.position.x, plot.end.y + 34.0),
		"Throttle · thrust per motor on this pack (sag included)", LothalTheme.TEXT_MUTED)

	# The catalogue's test figure: a reference, dashed, captioned as the test it was.
	var cat_g := float(catalogue.get("grams", 0.0))
	if cat_g > 0.0:
		var y: float = to_px.call(0.0, cat_g).y
		draw_dashed_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
			LothalTheme.TEXT_MUTED, 1.0, 6.0)
		var box := catalogue_label_rect()
		# A backing plate: the throttle gridlines run vertically through where it sits.
		draw_rect(box.grow(2.0), Color(LothalTheme.SURFACE_BASE, 0.85))
		_text(Vector2(box.position.x, box.position.y + LothalTheme.draw_font().get_ascent(
			LothalTheme.FONT_SIZE_SMALL)), catalogue_label(), LothalTheme.TEXT_MUTED)

	# Hover: what each motor must lift.
	var hy: float = to_px.call(0.0, hover_g).y
	draw_dashed_line(Vector2(plot.position.x, hy), Vector2(plot.end.x, hy), LothalTheme.SUCCESS,
		1.0, 4.0)
	_text(Vector2(plot.end.x - 110.0, hy - 6.0), "hover %d g" % roundi(hover_g), LothalTheme.SUCCESS)

	# The throttle ceiling and what binds it; beyond it is unreachable, shaded.
	var cap := float(ceiling.get("fraction", 1.0))
	if cap < 0.999:
		var cx: float = to_px.call(cap, 0.0).x
		draw_rect(Rect2(Vector2(cx, plot.position.y), Vector2(plot.end.x - cx, plot.size.y)),
			Color(LothalTheme.WARNING, 0.08))
		draw_line(Vector2(cx, plot.position.y), Vector2(cx, plot.end.y), LothalTheme.WARNING, 1.5)
		_text(Vector2(cx - 6.0, plot.position.y + 14.0),
			"ceiling %d%% · %s" % [roundi(cap * 100.0), str(ceiling.get("limiter", ""))],
			LothalTheme.WARNING, true)

	var points := PackedVector2Array()
	for point in curve:
		points.append(to_px.call((point as Vector2).x, (point as Vector2).y))
	draw_polyline(points, LothalTheme.ACCENT, 2.0, true)

	var at: Vector2 = to_px.call(peak.x, peak.y)
	draw_circle(at, 4.0, LothalTheme.ACCENT)
	_text(at + Vector2(-70.0, -10.0), "%d g max" % roundi(peak.y), LothalTheme.ACCENT)


static func _round_step(raw: float) -> float:
	var magnitude := pow(10.0, floor(log(raw) / log(10.0)))
	for mult in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= mult * magnitude:
			return mult * magnitude
	return 10.0 * magnitude


# ---------------------------------------------------------------------------
# The propeller in plan
# ---------------------------------------------------------------------------

func _draw_prop() -> void:
	if blade == null or blade.radius_mm() <= 0.0:
		return
	var radius := blade.radius_mm()
	# Room under the disc for the diameter dimension and the caption.
	var centre := Vector2(size.x * 0.5, (size.y - 40.0) * 0.5)
	var px_per_mm := (minf(size.x, size.y - 40.0) * 0.5 - MARGIN_PX * 0.5) / radius
	if px_per_mm <= 0.0:
		return
	draw_circle(centre, radius * px_per_mm, Color(LothalTheme.TEXT_MUTED, 0.06))
	draw_arc(centre, radius * px_per_mm, 0.0, TAU, 96, Color(LothalTheme.TEXT_MUTED, 0.6), 1.0)
	var hub := radius * PropellerDocument.HUB_RADIUS_TO_RADIUS
	for k in blade.blades:
		var angle := -PI * 0.5 + TAU * float(k) / float(blade.blades)
		var along := Vector2(cos(angle), sin(angle))
		var across := Vector2(-along.y, along.x)
		var lead := PackedVector2Array()
		var trail := PackedVector2Array()
		for i in 25:
			var f := lerpf(hub / radius, 1.0, float(i) / 24.0)
			var half := blade.chord_at(f) * 0.5
			lead.append(centre + (along * f * radius + across * half) * px_per_mm)
			trail.append(centre + (along * f * radius - across * half) * px_per_mm)
		trail.reverse()
		var outline := lead + trail
		draw_colored_polygon(outline, Color(LothalTheme.ACCENT, 0.30))
		outline.append(outline[0])
		draw_polyline(outline, LothalTheme.ACCENT, 1.5, true)
	draw_circle(centre, hub * px_per_mm, LothalTheme.TEXT_MUTED)
	# Diameter, dimensioned across the disc below the hub.
	var y := centre.y + radius * px_per_mm + 12.0
	var a := Vector2(centre.x - radius * px_per_mm, y)
	var b := Vector2(centre.x + radius * px_per_mm, y)
	draw_line(a, b, LothalTheme.WARNING, 1.0)
	draw_line(a + Vector2(0, -5), a + Vector2(0, 5), LothalTheme.WARNING, 1.0)
	draw_line(b + Vector2(0, -5), b + Vector2(0, 5), LothalTheme.WARNING, 1.0)
	_text(Vector2(b.x + 8.0, y + 4.0), "Ø %d mm" % roundi(radius * 2.0), LothalTheme.WARNING)
	var origin := "chord ~generated (no vendor publishes one)" if blade.chord_is_assumed \
		else "chord as drawn"
	_text(Vector2(12.0, size.y - 12.0), "Top view · %d blades · %s" % [blade.blades, origin],
		LothalTheme.TEXT_MUTED)


# ---------------------------------------------------------------------------
# One motor's disc and its guard
# ---------------------------------------------------------------------------

func _draw_guard() -> void:
	if tip_radius_mm <= 0.0:
		return
	var reach := maxf(tip_radius_mm, ring_outer_mm)
	var centre := size * 0.5
	var px_per_mm := (minf(size.x, size.y) * 0.5 - MARGIN_PX) / reach
	if px_per_mm <= 0.0:
		return
	draw_circle(centre, tip_radius_mm * px_per_mm, Color(LothalTheme.ACCENT, 0.10))
	draw_arc(centre, tip_radius_mm * px_per_mm, 0.0, TAU, 96, LothalTheme.ACCENT, 1.5)
	draw_circle(centre, 4.0, LothalTheme.TEXT_MUTED)
	if ring_outer_mm <= 0.0:
		_text(Vector2(12.0, size.y - 12.0),
			"Top view · one motor · prop disc Ø %d mm · no guard fitted" % roundi(tip_radius_mm * 2.0),
			LothalTheme.TEXT_MUTED)
		return
	var mid := (ring_inner_mm + ring_outer_mm) * 0.5 * px_per_mm
	var wall := maxf((ring_outer_mm - ring_inner_mm) * px_per_mm, 2.0)
	var colour := LothalTheme.DANGER if gap_mm < 0.0 else LothalTheme.TEXT_MAIN
	draw_arc(centre, mid, 0.0, TAU, 128, Color(colour, 0.85), wall)
	# The tip gap, marked on the right where tip and inner wall face each other.
	var from := centre + Vector2(tip_radius_mm * px_per_mm, 0.0)
	var to := centre + Vector2(ring_inner_mm * px_per_mm, 0.0)
	var gap_colour := LothalTheme.DANGER if gap_mm < 0.0 else LothalTheme.WARNING
	draw_line(from, to, gap_colour, 2.0)
	draw_circle(from, 3.0, gap_colour)
	draw_circle(to, 3.0, gap_colour)
	# Inside the disc, right-aligned to the tip, where the ring does not cross it.
	_text(from + Vector2(-8.0, -8.0), "%s mm tip gap" % _trim(gap_mm), gap_colour, true)
	_text(Vector2(12.0, size.y - 12.0),
		"Top view · one motor · %s ring, Ø %d mm outside" % [guard_kind, roundi(ring_outer_mm * 2.0)],
		LothalTheme.TEXT_MUTED)


## A label kept inside the canvas; `right` sets it to end at `at.x` instead of starting there.
func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
