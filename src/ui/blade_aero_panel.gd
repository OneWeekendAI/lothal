class_name BladeAeroPanel
extends Control
## Whether the blade on the bench is worth printing — the Propulsion room's verdict, drawn.
##
## ## What it shows, and why these four numbers
##
## A headline row of four figures at the design RPM, then one curve.
##
##   - **g/W** — hover efficiency, the number that becomes flight time. The headline, because it is
##     the one that answers "is this better than the 5x4.3x3 I can buy".
##   - **thrust** — what it makes at that RPM, so the g/W is readable as a trade rather than a score.
##   - **FM** — figure of merit against momentum theory: how close the blade is to the physical
##     floor for its disc. Two blades at the same g/W can sit very differently against their own
##     limit, and the one further from it has room to improve.
##   - **capped to** — how far out along the blade the polar's lift cap reaches. NOT a stalled
##     percentage: every propeller in the catalog runs some of its root at the cap (see the FINDING
##     in `BladeAero`), so the fraction cannot separate two blades and the EXTENT can. A blade
##     capped to 0.5 R is ordinary; one capped to 0.98 R is over-pitched for the speed it is being
##     turned at, and that is a thing to change.
##
## The curve is angle of attack against radius, with the capped stretches shaded. That pairing is
## the point: α(r) is the quantity the builder's edits actually move — pitch sets it directly and
## chord sets it through the inflow — and the cap is where it has gone past what the polar will
## pay for. A thrust curve would be prettier and would not tell them what to change.
##
## ## Why not just show the P10e overlays here
##
## Those read `Build.operating_rpm()` and the prop the AIRCRAFT is carrying, and `GlassShell`
## retracts them while this room is open (`OverlayTray`, defect 1). The blade on the bench is not
## fitted to an aircraft; it has no hover throttle and no pack. So this panel takes an RPM from the
## room and asks about the document, and the overlays keep answering for the fitted drone. Two
## questions, two answers, neither pretending to be the other.
##
## ## No physics here, and the mapping is provable
##
## Every number comes from `BladeAero`, which gets them from `BemtModel`. This file scales and
## draws. The mapping functions are public and pure for `ThrustOverlay`'s reason: where the curve
## lands can then be asserted headless, and only the colours need eyes.

## The margin around the plot, in pixels. `ThrustOverlay.MARGIN_PX`'s value, for its reason — these
## charts can be on screen together and a different inset would read as a misalignment.
const MARGIN_PX := 34.0

## Height reserved for the headline row above the plot.
const HEADER_PX := 46.0

## The α axis, in degrees. Fixed rather than fitted to the data, and that is deliberate: a builder
## comparing two blades needs the curves to be comparable, and an axis that rescales makes a gentle
## blade and a stalling one look identical. Negative because a blade CAN sit at negative incidence
## at the tip, and hiding that would hide the thing worth seeing.
const ALPHA_MIN_DEG := -5.0
const ALPHA_MAX_DEG := 25.0

## How far out the lift cap must reach before the readout warns. 0.95 R rather than anything
## smaller because the catalog's own blades reach 0.98 R at a plausible RPM — see `BladeAero`'s
## FINDING — so a lower threshold would warn about most propellers people actually fly.
const WHOLE_BLADE_CAPPED := 0.95

var verdict: Dictionary = {}
var radius_m := 0.0
var caret_r_frac := 0.7

var _c_l_max := 1.0


func _init() -> void:
	custom_minimum_size = Vector2(240, 190)
	# Not IGNORE, unlike the section view: this panel carries no controls today, but it sits under
	# the room's own RPM slider and swallowing the pointer here would be a surprise if one is added.
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_c_l_max = BemtModel.global_polar()[3]


## The verdict to draw, straight from `BladeAero.analyse`, plus the radius its station radii are
## measured against. Both, because the tap is metric and the drawing is in r/R — deriving the
## radius here from the first station would make this file guess at the solve's grid.
func show_verdict(p_verdict: Dictionary, p_radius_m: float) -> void:
	verdict = p_verdict
	radius_m = p_radius_m
	queue_redraw()


func set_caret(r_frac: float) -> void:
	caret_r_frac = clampf(r_frac, 0.0, 1.0)
	queue_redraw()


# ---------------------------------------------------------------------------
# Mapping — pure, so the geometry is provable headless
# ---------------------------------------------------------------------------

## The rectangle the curve is drawn inside: the control minus the margins and the headline row.
func plot_rect() -> Rect2:
	var left := MARGIN_PX
	var top := HEADER_PX
	var w := maxf(size.x - MARGIN_PX * 2.0, 1.0)
	var h := maxf(size.y - HEADER_PX - MARGIN_PX, 1.0)
	return Rect2(left, top, w, h)


## (r/R, α in degrees) → pixels. r/R runs left to right over the full radius — from the axis, not
## from the first station — so two blades with different hub fractions still line up against each
## other and against the planform editor above.
func to_pixels(r_frac: float, alpha_degrees: float) -> Vector2:
	var rect := plot_rect()
	var x := rect.position.x + clampf(r_frac, 0.0, 1.0) * rect.size.x
	var t := (alpha_degrees - ALPHA_MIN_DEG) / (ALPHA_MAX_DEG - ALPHA_MIN_DEG)
	var y := rect.position.y + rect.size.y * (1.0 - clampf(t, 0.0, 1.0))
	return Vector2(x, y)


## The α(r) polyline in pixels, one point per LIFTING station.
##
## Zero-chord annuli are skipped rather than drawn at 0°: the tap carries them so both taps align,
## but a station with no blade at it has no angle of attack, and joining the curve down to zero
## across the hub would draw a feature of the array as if it were a feature of the propeller.
func alpha_curve_px() -> PackedVector2Array:
	var out := PackedVector2Array()
	if verdict.is_empty() or verdict.get("refused", true) or radius_m <= 0.0:
		return out
	var stations: PackedFloat64Array = verdict["stations"]
	var count := BladeAero.station_count(stations)
	for i in count:
		var at := i * BladeAero.STATION_STRIDE
		if stations[at + 2] <= 0.0 and stations[at + 1] <= 0.0:
			continue
		out.append(to_pixels(stations[at] / radius_m, rad_to_deg(stations[at + 1])))
	return out


## The stalled stretches as pixel rectangles spanning the full plot height.
func stall_rects_px() -> Array:
	var rects: Array = []
	if verdict.is_empty() or verdict.get("refused", true) or radius_m <= 0.0:
		return rects
	var bands := BladeAero.stall_bands(verdict["stations"], _c_l_max, radius_m)
	var rect := plot_rect()
	var i := 0
	while i + 1 < bands.size():
		var x0 := to_pixels(bands[i], 0.0).x
		var x1 := to_pixels(bands[i + 1], 0.0).x
		rects.append(Rect2(x0, rect.position.y, maxf(x1 - x0, 1.0), rect.size.y))
		i += 2
	return rects


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var rect := plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.PANEL_BG)

	if verdict.is_empty() or verdict.get("refused", true):
		# A refusal says so in words. Drawing an empty grid would read as a blade that makes
		# nothing, which is a claim about the blade rather than about the model's standing.
		draw_string(font, Vector2(MARGIN_PX, HEADER_PX), "No solution at this speed",
			HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_BODY, LothalTheme.TEXT_MUTED)
		draw_string(font, Vector2(MARGIN_PX, HEADER_PX + 18.0),
			"The model declines this rotor rather than guessing.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
		return

	_draw_headline(font)

	for stall_rect in stall_rects_px():
		# WARNING and not DANGER, for the headline cell's reason: this shading marks the normal
		# condition of every static rotor's root, and a red band would say otherwise.
		draw_rect(stall_rect, Color(LothalTheme.WARNING.r, LothalTheme.WARNING.g,
			LothalTheme.WARNING.b, 0.14))

	# The zero-incidence line: where the curve crosses it, the blade has stopped lifting and
	# started dragging, and a tip that dips below it is the classic over-pitched planform.
	var zero_y := to_pixels(0.0, 0.0).y
	draw_line(Vector2(rect.position.x, zero_y), Vector2(rect.end.x, zero_y),
		LothalTheme.BORDER, 1.0)

	var curve := alpha_curve_px()
	if curve.size() > 1:
		draw_polyline(curve, LothalTheme.ACCENT, 2.0)

	# The caret, tying this curve to the section the room is showing and the station on the blade.
	var caret_x := to_pixels(caret_r_frac, 0.0).x
	draw_line(Vector2(caret_x, rect.position.y), Vector2(caret_x, rect.end.y),
		Color(LothalTheme.TEXT_MUTED, 0.6), 1.0)

	draw_string(font, Vector2(rect.position.x, rect.end.y + 14.0), "r/R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
	draw_string(font, Vector2(2.0, rect.position.y + 10.0), "%d°" % int(ALPHA_MAX_DEG),
		HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
	draw_string(font, Vector2(2.0, rect.end.y), "%d°" % int(ALPHA_MIN_DEG),
		HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)


func _draw_headline(font: Font) -> void:
	var capped: float = verdict["capped_to_r_frac"]
	var cells := [
		["g/W", "%.1f" % verdict["grams_per_watt"], LothalTheme.ACCENT],
		["thrust", "%.0f g" % (verdict["thrust_n"] / BladeAero.NEWTON_PER_GRAM_F),
			LothalTheme.TEXT_MAIN],
		["FM", "%.2f" % verdict["figure_of_merit"], LothalTheme.TEXT_MAIN],
		# Muted until the cap reaches the tip, and that threshold is the finding: inboard capping is
		# every propeller's normal condition, so colouring it red by default would train a builder
		# to ignore the one case that is not normal.
		["capped to", "%.2f R" % capped,
			LothalTheme.DANGER if capped >= WHOLE_BLADE_CAPPED else LothalTheme.TEXT_MUTED],
	]
	var step := size.x / float(cells.size())
	for i in cells.size():
		var x := i * step + LothalTheme.SPACE_1
		draw_string(font, Vector2(x, 16.0), str(cells[i][0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
		draw_string(font, Vector2(x, 34.0), str(cells[i][1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, LothalTheme.FONT_SIZE_SUBTITLE, cells[i][2])
