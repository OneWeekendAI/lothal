class_name VideoDiagram
extends Control
## The drawing on the Camera and VTX & antenna item pages (lab dock design §2, §3) — ControlDiagram's
## sibling. Read-only; every figure comes from `VideoFigures`, the calls the row, the page's two
## numbers and the sheet read. Both modes are one SIDE VIEW of the aircraft, nose to the right, to
## scale: the plates edge-on, the prop discs edge-on, the centre of mass.
##
##   - `camera`: the camera box tipped by its uptilt, the lens axis and the tilt against level, and
##     the CLEAR CONE — the cone about the lens axis out to whatever comes nearest it (the frame's
##     edge, or a fitted part nearer still, `AirframeModel.camera_clearances`). The lens axis lies in
##     the side plane (tilt is about X), so the cone's side-view silhouette is exactly the two lines
##     drawn: the drawing is true, not schematic. No lens angle is drawn — none is published.
##   - `vtx`: the transmitter and the antenna where the mass model weighs them, with their grams,
##     and the antenna's lever behind the centre of mass. No range and no heat: neither is modelled.

const MODE_CAMERA := "camera"
const MODE_VTX := "vtx"

var mode := ""
## `VideoFigures.side_view`'s dictionary.
var view: Dictionary = {}
## `VideoFigures.nearest_in_view` — the clear cone's edge, `{name, deg}`; empty for none.
var nearest: Dictionary = {}
## The frame's own nearest angle when a fitted part is nearer (both cones are drawn), else INF.
var frame_deg := INF
var tilt_deg := 0.0
## `VideoFigures.antenna_aft_of_com_mm`, NAN with no antenna.
var antenna_aft_mm := NAN
## The VTX's catalogue power class ("400 mW"), or "" — a caption, never a figure the drawing uses.
var power_class := ""

## mm → px, and the mm point drawn at the canvas origin; set in `_draw`, read by tests via `to_px`.
var _scale := 1.0
var _origin := Vector2.ZERO


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


## `airframe` is the drawn aircraft (the plates, discs and lens); `clearances` its
## `camera_clearances()`, passed rather than recomputed so the page and the row read one call.
func show_build(build: Build, p_mode: String, airframe: AirframeModel = null,
		clearances: Dictionary = {}) -> void:
	mode = p_mode
	view = {}
	nearest = {}
	frame_deg = INF
	antenna_aft_mm = NAN
	power_class = ""
	if build == null:
		queue_redraw()
		return
	view = VideoFigures.side_view(airframe, build)
	tilt_deg = VideoFigures.tilt_deg(build)
	match mode:
		MODE_CAMERA:
			nearest = VideoFigures.nearest_in_view(clearances)
			if not nearest.is_empty() and str(nearest["name"]) != VideoFigures.FRAME_NAME:
				frame_deg = float(clearances.get("frame_deg", INF))
		MODE_VTX:
			antenna_aft_mm = VideoFigures.antenna_aft_of_com_mm(build)
			if build.components.has("vtx"):
				power_class = str(((build.components["vtx"] as Dictionary).get("catalog", {}) \
					as Dictionary).get("power_class", ""))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0 or view.is_empty():
		return
	_fit()
	_text(Vector2(16.0, 20.0), "Side view · nose right · mm to scale", LothalTheme.TEXT_MUTED)
	_draw_airframe()
	match mode:
		MODE_CAMERA:
			_draw_camera()
		MODE_VTX:
			_draw_vtx()


## One scale for both axes, fitted to the page's own parts: a fore/aft window around the video
## parts and the CoM (the camera page adds room ahead of the lens for its cone), with the plates and
## discs clipped to that window but their heights kept — the canvas clips what runs past its edge.
func _fit() -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var com: Vector2 = view.get("com", Vector2.ZERO)
	low = low.min(com)
	high = high.max(com)
	for category in view.get("parts", {}):
		if mode == MODE_CAMERA and category != "camera":
			continue
		var part: Dictionary = view["parts"][category]
		var half := Vector2(part["l"], part["h"]) * 0.5 + Vector2.ONE * 4.0
		low = low.min(Vector2(part["f"], part["y"]) - half)
		high = high.max(Vector2(part["f"], part["y"]) + half)
	if not is_finite(low.x):
		low = Vector2(-60.0, -30.0)
		high = Vector2(60.0, 30.0)
	var window := Vector2(low.x - 30.0, high.x + (70.0 if mode == MODE_CAMERA else 30.0))
	for plate in view.get("plates", []):
		low = low.min(Vector2(maxf(plate["f0"], window.x), plate["y"] - plate["t"]))
		high = high.max(Vector2(minf(plate["f1"], window.y), plate["y"] + plate["t"]))
	for disc in view.get("discs", []):
		low.y = minf(low.y, disc["y"])
		high.y = maxf(high.y, disc["y"])
	low.x = minf(low.x, window.x)
	high.x = maxf(high.x, window.y)
	# Room above for the cone and labels, below for the dimension and caption.
	var span := high - low
	var area := Rect2(Vector2(28.0, 80.0), Vector2(size.x - 56.0, size.y - 190.0))
	_scale = minf(area.size.x / maxf(span.x, 1.0), area.size.y / maxf(span.y, 1.0))
	_scale = minf(_scale, 8.0)
	var mid := (low + high) * 0.5
	_origin = area.get_center() - Vector2(mid.x, -mid.y) * _scale


## A side-view point (forward, up) in mm to canvas pixels: forward is right, up is up.
func to_px(point_mm: Vector2) -> Vector2:
	return _origin + Vector2(point_mm.x, -point_mm.y) * _scale


func _draw_airframe() -> void:
	var plate_fill := Color(LothalTheme.TEXT_MUTED, 0.35)
	for plate in view.get("plates", []):
		var top_left := to_px(Vector2(plate["f0"], plate["y"] + plate["t"] * 0.5))
		var bottom_right := to_px(Vector2(plate["f1"], plate["y"] - plate["t"] * 0.5))
		draw_rect(Rect2(top_left, bottom_right - top_left), plate_fill)
	var first := true
	for disc in view.get("discs", []):
		var a := to_px(Vector2(disc["f"] - disc["r"], disc["y"]))
		var b := to_px(Vector2(disc["f"] + disc["r"], disc["y"]))
		draw_line(a, b, LothalTheme.TEXT_FAINT, 2.0)
		if first:
			_text(a + Vector2(0.0, -6.0), "prop disc", LothalTheme.TEXT_FAINT)
			first = false
	var com := to_px(view.get("com", Vector2.ZERO))
	draw_arc(com, 6.0, 0.0, TAU, 20, LothalTheme.TEXT_MAIN, 1.5)
	draw_line(com - Vector2(8.0, 0.0), com + Vector2(8.0, 0.0), LothalTheme.TEXT_MAIN, 1.0)
	draw_line(com - Vector2(0.0, 8.0), com + Vector2(0.0, 8.0), LothalTheme.TEXT_MAIN, 1.0)
	_text(com + Vector2(10.0, 16.0), "CoM", LothalTheme.TEXT_MAIN)


## A part's weighed box, rotated about its centre by `deg` (positive tips the nose up).
func _part_box(part: Dictionary, colour: Color, fill: Color, deg := 0.0) -> void:
	var centre := Vector2(part["f"], part["y"])
	var half := Vector2(part["l"], part["h"]) * 0.5
	var turn := deg_to_rad(deg)
	var points := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
			Vector2(-half.x, half.y)]:
		points.append(to_px(centre + (corner as Vector2).rotated(turn)))
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, colour, 1.5)


# ---------------------------------------------------------------------------
# Camera: the tipped box, the lens axis, the clear cone
# ---------------------------------------------------------------------------

func _draw_camera() -> void:
	var parts: Dictionary = view.get("parts", {})
	if not parts.has("camera"):
		_text(Vector2(16.0, size.y - 14.0), "No camera fitted", LothalTheme.TEXT_FAINT)
		return
	_part_box(parts["camera"], LothalTheme.ACCENT, LothalTheme.ACCENT_FILL, tilt_deg)
	if not bool(view.get("has_eye", false)):
		return
	var eye := to_px(view["eye"])
	var bore: Vector2 = view["bore"]
	var reach := size.x
	# Level, faint; the axis, accent; the tilt between them.
	draw_dashed_line(eye, eye + Vector2(reach, 0.0), LothalTheme.TEXT_FAINT, 1.0, 5.0)
	var axis_px := Vector2(bore.x, -bore.y)
	draw_line(eye, eye + axis_px * reach, LothalTheme.ACCENT, 2.0)
	var up := -atan2(bore.y, bore.x)
	draw_arc(eye, 46.0, up, 0.0, 24, LothalTheme.ACCENT, 1.5)
	_text(eye + Vector2(52.0, -6.0), "%d° up" % roundi(tilt_deg), LothalTheme.ACCENT)
	# The clear cone, and the frame's own when a fitted part comes nearer.
	if is_finite(frame_deg):
		_cone(eye, axis_px, frame_deg, LothalTheme.TEXT_MUTED, "%s %d°" % [VideoFigures.FRAME_NAME,
			roundi(frame_deg)])
	if not nearest.is_empty() and float(nearest["deg"]) < 90.0:
		var deg := float(nearest["deg"])
		var colour := LothalTheme.WARNING if is_finite(frame_deg) else LothalTheme.TEXT_MAIN
		_cone(eye, axis_px, deg, colour, "%s ~%d°" % [str(nearest["name"]), roundi(deg)])
		_text(Vector2(16.0, size.y - 14.0),
			"Clear cone ~%d° each side · in view on any lens wider than %d°" % [roundi(deg),
				roundi(deg * 2.0)], LothalTheme.TEXT_MUTED)
	else:
		_text(Vector2(16.0, size.y - 14.0), "No plate outline to measure the view against",
			LothalTheme.TEXT_FAINT)


func _cone(eye: Vector2, axis_px: Vector2, deg: float, colour: Color, label: String) -> void:
	var reach := minf(size.x * 0.45, 320.0)
	for side in [-1.0, 1.0]:
		var edge := axis_px.rotated(deg_to_rad(deg) * side)
		draw_dashed_line(eye, eye + edge * reach, colour, 1.5, 6.0)
	# Labelled on the upper edge, where nothing of the airframe is drawn.
	var upper := axis_px.rotated(-deg_to_rad(deg))
	_text(eye + upper * reach + Vector2(4.0, -4.0), label, colour)


# ---------------------------------------------------------------------------
# VTX & antenna: where they are weighed, and the antenna's lever
# ---------------------------------------------------------------------------

func _draw_vtx() -> void:
	var parts: Dictionary = view.get("parts", {})
	if parts.has("camera"):
		_part_box(parts["camera"], LothalTheme.TEXT_FAINT, Color(LothalTheme.TEXT_FAINT, 0.12),
			tilt_deg)
	var labels := {"vtx": "VTX", "antenna": "Antenna"}
	var lowest := -INF
	for category in ["vtx", "antenna"]:
		if not parts.has(category):
			continue
		var part: Dictionary = parts[category]
		_part_box(part, LothalTheme.ACCENT, LothalTheme.ACCENT_FILL)
		# The antenna's label above it, the transmitter's to its left: the transmitter sits in the
		# stack under the antenna, and a label above it would land on the antenna.
		var label := "%s %.1f g" % [labels[category], float(part["mass_g"])]
		if category == "antenna":
			var top := to_px(Vector2(part["f"], float(part["y"]) + float(part["h"]) * 0.5))
			_text(top + Vector2(-30.0, -8.0), label, LothalTheme.TEXT_MAIN)
		else:
			var left := to_px(Vector2(float(part["f"]) - float(part["l"]) * 0.5, part["y"]))
			_text(left + Vector2(-8.0, 5.0), label, LothalTheme.TEXT_MAIN, true)
		lowest = maxf(lowest, to_px(Vector2(part["f"], float(part["y"]) - float(part["h"]) * 0.5)).y)
	if parts.is_empty() or (not parts.has("vtx") and not parts.has("antenna")):
		_text(Vector2(16.0, size.y - 14.0), "No transmitter or antenna fitted", LothalTheme.TEXT_FAINT)
		return
	# The antenna's lever: CoM to the antenna's weighed centre, fore/aft, below the aircraft.
	if parts.has("antenna") and not is_nan(antenna_aft_mm):
		var com := to_px(view.get("com", Vector2.ZERO))
		var antenna := to_px(Vector2(parts["antenna"]["f"], parts["antenna"]["y"]))
		var y := maxf(maxf(lowest, com.y), to_px(Vector2(0.0, _lowest_plate_mm())).y) + 34.0
		draw_line(Vector2(antenna.x, y), Vector2(com.x, y), LothalTheme.WARNING, 1.5)
		for x in [antenna.x, com.x]:
			draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), LothalTheme.WARNING, 1.5)
			draw_dashed_line(Vector2(x, y - 5.0), Vector2(x, minf(antenna.y, com.y)),
				Color(LothalTheme.WARNING, 0.5), 1.0, 4.0)
		_text(Vector2((antenna.x + com.x) * 0.5 - 40.0, y + 18.0),
			"~%d mm %s CoM" % [roundi(absf(antenna_aft_mm)), "behind" if antenna_aft_mm >= 0.0
				else "ahead of"], LothalTheme.WARNING)
	var caption := "No radio or heat model: no range, no temperature"
	if power_class != "":
		caption = "%s class · %s" % [power_class, caption.to_lower()]
	_text(Vector2(16.0, size.y - 14.0), caption, LothalTheme.TEXT_MUTED)


func _lowest_plate_mm() -> float:
	var low := INF
	for plate in view.get("plates", []):
		low = minf(low, float(plate["y"]) - float(plate["t"]) * 0.5)
	return low if is_finite(low) else 0.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A label kept inside the canvas on a backing plate (ControlDiagram's).
func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	var y := clampf(at.y, 14.0, size.y - 4.0)
	var height := font.get_height(LothalTheme.FONT_SIZE_SMALL)
	draw_rect(Rect2(Vector2(x - 2.0, y - font.get_ascent(LothalTheme.FONT_SIZE_SMALL) - 1.0),
		Vector2(width + 4.0, height + 2.0)), Color(LothalTheme.SURFACE_BASE, 0.85))
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)
