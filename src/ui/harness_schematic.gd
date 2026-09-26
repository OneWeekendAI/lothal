class_name HarnessSchematic
extends Control
## The current path, drawn — plans/2026-09-10-power-room-design.md §2.1, slice PW5.
##
## Pack, connector, main lead, the ESC's input pads with the capacitor standing across them, and
## four motor leads fanning out to the arms. **Every wire is drawn at its real gauge as a stroke
## width and its real length as a length**, which is the whole argument for this view existing: an
## icon diagram would say "there is a main lead" and this says how much lead there is and how thin
## it is, which is the question a builder actually has.
##
## ---------------------------------------------------------------------------
## ONE SCALE, AND NO EXAGGERATION FACTOR ANYWHERE
## ---------------------------------------------------------------------------
##
## Lengths and stroke widths share a single px-per-mm scale, fitted to whatever rect this Control
## has. A tempting first draft gave the strokes a scale of their own so thin wire would still be
## visible; it was dropped, because a stroke scale independent of the length scale is a second
## opinion about the drawing and the two would have to be kept in step by hand. Fitted at true
## scale the ratios come out readable anyway — on a 6S build a 12 AWG trunk is a 5.0 mm jacket and
## 22 AWG motor leads are 2.4 mm ones, which is the "four hairlines leaving a trunk" §2.1 asks for,
## unforced.
##
## The one clamp is MIN_STROKE_PX, and it is a legibility floor rather than a fudge: a stroke
## rounded to nothing is a segment a builder cannot click.
##
## ---------------------------------------------------------------------------
## THE PICTURE IS A FUNCTION OF THE DOCUMENT — NOTHING HERE IS CACHED
## ---------------------------------------------------------------------------
##
## `geometry()` derives every point, every width and every colour from the `Build` it was handed,
## on every call, and `_draw` and `_gui_input` both go through it. There is no stored polyline and
## no stored scale. That is the Build-free rule stated as an implementation detail, and it exists
## because `PropellerMesh` held its own copy of the chord law (P10d): an edited planform moved the
## physics and left the picture alone. A harness you can edit and cannot see would be the same
## defect in a smaller room.
##
## The segment list comes from `HarnessChecks.segments`, which is the list the ampacity check reads
## — one list, read twice. A room that built its own would be that defect again by a slower route.
##
## ---------------------------------------------------------------------------
## FOUR LEADS, ONE SEGMENT
## ---------------------------------------------------------------------------
##
## Four motor leads are drawn and they are all `motor_lead`: the model carries ONE gauge and ONE
## length for the set, because no builder solders four different gauges to four identical motors.
## Clicking any of the four selects that one segment, and the inspector says "Each motor lead" in
## the model's own words. Drawing one lead and labelling it "x4" would have been the alternative
## and it loses the thing the drawing is for — the fan is what makes a thin phase wire look thin.
##
## The capacitor is NOT a segment (§2.1). It is a part, drawn to its catalog can size across the
## board's input pads where it physically stands, and selectable — but the inspector offers it no
## gauge and no length, because it has neither.
##
## ---------------------------------------------------------------------------
## A CONTROL DOES NOT CLIP ITS OWN `_draw`
## ---------------------------------------------------------------------------
##
## So the scale is fitted to BOTH axes of the available rect, with the bounding box expanded by
## half of the fattest stroke before the fit — a line's width spills either side of its centreline,
## and a fit that measured centrelines would put half a 12 AWG trunk over the neighbouring panel.
## `content_rect()` is what `tests/test_power_room.gd` asserts against, and it is derived from the
## same geometry the drawing uses rather than from a second measurement.

## Emitted when the selection changes, carrying the id selected or "" for nothing. The ROOM decides
## what a selection is worth — see `PowerWorkbench` for why the history is not in here.
signal selection_changed(id: String)

## The capacitor's id in the selection vocabulary. Not a segment id: `HarnessChecks.segments` will
## never return it, which is exactly the distinction §2.1 draws.
const CAPACITOR_ID := "capacitor"

## The pack and the board as fixed boxes in millimetres. THESE ARE ICONS AND THEY SAY SO: a pack's
## real footprint is in `batteries.json` and the board's is 30x30 or 20x20, but neither is the
## subject of this drawing and drawing them to scale would make the wire — which IS the subject —
## share its span with two rectangles that carry no information.
const PACK_BOX_MM := Vector2(46.0, 30.0)
const ESC_BOX_MM := Vector2(30.0, 30.0)
## The plug's own length along the run, as an icon. The connector's mass and its contact resistance
## are real and modelled; its physical length is not published by anybody and is not used for
## anything, so this is a drawing width and nothing else.
const CONNECTOR_MM := 9.0

## Where the four motor leads point, in degrees from straight ahead. Four angles rather than two
## mirrored ones so that four leads are four visible lines: at +/-30 the pairs overlap exactly and
## the fan reads as two wires.
const FAN_DEG := [-52.0, -18.0, 18.0, 52.0]

## The legibility floor described in the header, and the clear space kept around the drawing.
const MIN_STROKE_PX := 1.5
const MARGIN_PX := 16.0

## How far from a segment's centreline a click still counts, when the stroke itself is thinner than
## that. A 28 AWG lead is under 2 px wide at any scale this panel reaches, and a target that thin
## is a target nobody hits.
const MIN_HIT_PX := 7.0

## The selection ring's width, in px and not in mm: it is chrome, not wire, and a highlight that
## scaled with the drawing would be a fat ring on a whoop and a hairline on a cinelifter.
const SELECTION_RING_PX := 3.0

## The aircraft being drawn, and what the checks said about it. Held as references rather than as
## anything derived from them — see the header.
var _build: Build = null
var _warnings: Array[BuildWarning] = []
var _selected := ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(420, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Puts an aircraft in front of the drawing, WITH what the checks said about it.
##
## ONE FUNCTION TAKING BOTH, and that is W0.7's discipline rather than a convenience: three code
## paths retracted the shell's chrome and one of them omitted a term, and the fix was to remove the
## argument a caller could omit. A `set_build` with a separate `set_warnings` beside it is exactly
## that shape — a caller can update the aircraft and forget the colours, and the drawing would then
## be warning about the harness it used to have. There is one door and it takes both.
func show_harness(build: Build, warnings: Array[BuildWarning]) -> void:
	_build = build
	_warnings = warnings
	queue_redraw()


func selected() -> String:
	return _selected


## Selects an id, or "" for nothing. Silent when it changes nothing, so a room re-selecting what is
## already selected does not push an undo step for a click that moved no wire.
func select(id: String) -> void:
	if id == _selected:
		return
	_selected = id
	queue_redraw()
	selection_changed.emit(id)


# ---------------------------------------------------------------------------
# The drawing, derived
# ---------------------------------------------------------------------------

## Every point, width and colour in the picture, in THIS control's pixel coordinates.
##
## Keys: `scale` (px per mm), `wires` (an array of `{id, from, to, stroke_px, color, awg,
## length_mm}`), `boxes` (`{id, rect, color, fill}`), and `bounds_mm`. Recomputed from the build on
## every call — see the header for why there is nothing to invalidate.
##
## Empty for no build, which is a real state: the room is constructed before an aircraft reaches it.
func geometry() -> Dictionary:
	var empty := {"scale": 0.0, "wires": [], "boxes": [], "bounds_mm": Rect2()}
	if _build == null:
		return empty
	var by_id := {}
	for segment in HarnessChecks.segments(_build):
		by_id[String(segment["id"])] = segment
	if not by_id.has("main_lead") or not by_id.has("motor_lead"):
		return empty

	var main: Dictionary = by_id["main_lead"]
	var motor: Dictionary = by_id["motor_lead"]
	var main_od := _jacket_mm(int(main["awg"]))
	var motor_od := _jacket_mm(int(motor["awg"]))
	var main_len := maxf(float(main["length_mm"]), 0.0)
	var motor_len := maxf(float(motor["length_mm"]), 0.0)

	# --- millimetre space, y down, the run going left to right ---
	var pack_rect := Rect2(0.0, -PACK_BOX_MM.y * 0.5, PACK_BOX_MM.x, PACK_BOX_MM.y)
	var main_from := Vector2(pack_rect.end.x + CONNECTOR_MM, 0.0)
	var main_to := main_from + Vector2(main_len, 0.0)
	var esc_rect := Rect2(main_to.x, -ESC_BOX_MM.y * 0.5, ESC_BOX_MM.x, ESC_BOX_MM.y)
	var fan_from := Vector2(esc_rect.end.x, 0.0)

	# The can, at its catalog diameter and height, standing on the board it is soldered to. To
	# scale because it CAN be — `capacitors.json` publishes both — and because a 1000 uF can next to
	# a 220 uF one is the one part of §3.4's rule a picture can actually make.
	var cap_size := _build.harness.capacitor_size_m(_build) * 1000.0
	var cap_fitted := not _build.harness.capacitor_row(_build).is_empty()
	var cap_rect := Rect2(
		esc_rect.position.x + ESC_BOX_MM.x * 0.5 - cap_size.x * 0.5,
		esc_rect.position.y - cap_size.y,
		cap_size.x, cap_size.y)

	var wires_mm: Array = [{
		"id": "main_lead", "from": main_from, "to": main_to,
		"od_mm": main_od, "awg": int(main["awg"]), "length_mm": main_len,
	}]
	for degrees in FAN_DEG:
		var direction := Vector2(cos(deg_to_rad(degrees)), sin(deg_to_rad(degrees)))
		wires_mm.append({
			"id": "motor_lead", "from": fan_from, "to": fan_from + direction * motor_len,
			"od_mm": motor_od, "awg": int(motor["awg"]), "length_mm": motor_len,
		})

	# --- the bounds, INCLUDING the half-stroke each line spills either side of its centreline ---
	var bounds := pack_rect.merge(esc_rect)
	if cap_fitted:
		bounds = bounds.merge(cap_rect)
	for wire in wires_mm:
		var half: float = float(wire["od_mm"]) * 0.5
		var span := Rect2(wire["from"], Vector2.ZERO).expand(wire["to"]).grow(half)
		bounds = bounds.merge(span)

	var usable := size - Vector2.ONE * MARGIN_PX * 2.0
	if usable.x <= 0.0 or usable.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return empty
	var px_per_mm := minf(usable.x / bounds.size.x, usable.y / bounds.size.y)
	# Centred in whatever the fit did not use, so a short whoop harness does not sit in the corner.
	var origin := Vector2(MARGIN_PX, MARGIN_PX) \
		+ (usable - bounds.size * px_per_mm) * 0.5 - bounds.position * px_per_mm

	var wires: Array = []
	for wire in wires_mm:
		var severity := severity_for(String(wire["id"]))
		wires.append({
			"id": wire["id"],
			"from": Vector2(wire["from"]) * px_per_mm + origin,
			"to": Vector2(wire["to"]) * px_per_mm + origin,
			"stroke_px": maxf(float(wire["od_mm"]) * px_per_mm, MIN_STROKE_PX),
			"color": WarningList.COLORS[severity],
			"severity": severity,
			"awg": wire["awg"],
			"length_mm": wire["length_mm"],
		})

	var boxes: Array = [
		{"id": "pack", "rect": _to_px(pack_rect, px_per_mm, origin), "color": LothalTheme.TEXT_MUTED,
			"label": "PACK"},
		{"id": "connector", "rect": _to_px(
			Rect2(pack_rect.end.x, -PACK_BOX_MM.y * 0.25, CONNECTOR_MM, PACK_BOX_MM.y * 0.5),
			px_per_mm, origin), "color": LothalTheme.TEXT_MAIN, "label": ""},
		{"id": "esc", "rect": _to_px(esc_rect, px_per_mm, origin), "color": LothalTheme.TEXT_MUTED,
			"label": "ESC"},
	]
	if cap_fitted:
		boxes.append({"id": CAPACITOR_ID, "rect": _to_px(cap_rect, px_per_mm, origin),
			"color": WarningList.COLORS[severity_for(CAPACITOR_ID)], "label": ""})

	return {"scale": px_per_mm, "wires": wires, "boxes": boxes, "bounds_mm": bounds}


## Everything the drawing occupies, in this control's coordinates — the union of every wire's
## stroked span and every box. What the clipping check measures, derived from the geometry the
## drawing uses rather than from a second pass over the same numbers.
func content_rect() -> Rect2:
	var geometry_now := geometry()
	var out := Rect2()
	var started := false
	for wire in geometry_now["wires"]:
		var half: float = float(wire["stroke_px"]) * 0.5
		var span := Rect2(wire["from"], Vector2.ZERO).expand(wire["to"]).grow(half)
		out = span if not started else out.merge(span)
		started = true
	for box in geometry_now["boxes"]:
		out = box["rect"] if not started else out.merge(box["rect"])
		started = true
	return out


## How hard a segment is working, in `BuildWarning`'s vocabulary.
##
## **READ OFF THE WARNINGS THEMSELVES, not recomputed.** §2.1 asks for the segment to be coloured
## by its share of its own ampacity on the same ramp the warning list uses, "so the room and the
## warning list cannot disagree about which segment is the problem" — and the only way two things
## cannot disagree is for there to be one of them. `HarnessChecks._ampacity` already puts the
## segment id in `values["segment"]`, so this reads the severity the check assigned and paints it.
## A second threshold here would be a colour that goes amber at a load the list is silent about.
##
## The consequence, said plainly: today the ramp has two steps in practice, not three, because the
## only per-segment warning in the section is `LIMITING` (ampacity, never `IMPOSSIBLE` — thin wire
## sags, it does not refuse). The third step is not decoration waiting for a use: a future check
## that named a segment at any severity would colour it here for free, with nothing to add.
func severity_for(id: String) -> BuildWarning.Severity:
	var worst := BuildWarning.Severity.CHARACTERISTIC
	for warning in _warnings:
		if String(warning.values.get("segment", "")) != id:
			continue
		if warning.severity < worst:
			worst = warning.severity
	return worst


# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

func _draw() -> void:
	var geometry_now := geometry()
	if geometry_now["wires"].is_empty():
		return

	for box in geometry_now["boxes"]:
		var rect: Rect2 = box["rect"]
		draw_rect(rect, LothalTheme.PANEL_BG, true)
		draw_rect(rect, box["color"], false, 2.0)
		if String(box["id"]) == _selected:
			draw_rect(rect.grow(SELECTION_RING_PX), LothalTheme.BORDER_FOCUS, false,
				SELECTION_RING_PX)

	for wire in geometry_now["wires"]:
		if String(wire["id"]) == _selected:
			draw_line(wire["from"], wire["to"], LothalTheme.BORDER_FOCUS,
				float(wire["stroke_px"]) + SELECTION_RING_PX * 2.0)
		draw_line(wire["from"], wire["to"], wire["color"], float(wire["stroke_px"]))

	var font := get_theme_default_font()
	if font == null:
		return
	for box in geometry_now["boxes"]:
		var label := String(box["label"])
		if label == "":
			continue
		var rect: Rect2 = box["rect"]
		draw_string(font, rect.position + Vector2(4.0, rect.size.y * 0.5 + 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 11, LothalTheme.TEXT_MUTED)


# ---------------------------------------------------------------------------
# Clicking
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	select(id_at(click.position))
	accept_event()


## What is under a point, or "" for empty panel. Public because a click is a layout fact and a test
## has no window: driving this is how `tests/test_power_room.gd` selects a segment, which is the
## same path `_gui_input` takes rather than a parallel one.
##
## Wires win over boxes: the capacitor's can overlaps the board it stands on, and the thing a
## builder is pointing at when they click a wire is the wire.
func id_at(point: Vector2) -> String:
	var geometry_now := geometry()
	for wire in geometry_now["wires"]:
		var reach := maxf(float(wire["stroke_px"]) * 0.5, MIN_HIT_PX)
		var nearest := Geometry2D.get_closest_point_to_segment(
			point, wire["from"], wire["to"])
		if nearest.distance_to(point) <= reach:
			return String(wire["id"])
	for box in geometry_now["boxes"]:
		if String(box["id"]) == CAPACITOR_ID and (box["rect"] as Rect2).has_point(point):
			return CAPACITOR_ID
	return ""


static func _to_px(rect_mm: Rect2, px_per_mm: float, origin: Vector2) -> Rect2:
	return Rect2(rect_mm.position * px_per_mm + origin, rect_mm.size * px_per_mm)


## The jacket diameter for a gauge — the wire's real width, which is what a stroke width means here.
##
## Zero for a gauge the table does not carry, which `MIN_STROKE_PX` then floors to a hairline. That
## is the honest picture of an authored 19 AWG lead: `WireGauge` refuses to invent a row for it, so
## the drawing has nothing to be to scale ABOUT, and a hairline that looks wrong beside a warning
## that says the gauge is unknown is better than a plausible-looking guess.
static func _jacket_mm(awg: int) -> float:
	var row: Array = WireGauge.GAUGES.get(awg, [])
	return 0.0 if row.is_empty() else float(row[2])
