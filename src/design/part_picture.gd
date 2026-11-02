class_name PartPicture
extends Control
## A clean monochrome line diagram of a part, drawn in code per category (the catalog has no
## per-part model, only whole-class models). Proportions follow the part's own numbers where a
## number is cheap to use (cell count, blade count, motor size, board pattern), so two parts of
## one category do not look identical. Lines in `ink`, the card's colour; and, inside the lines, the
## one property PartColour picks for the category, as a fill level or a hue (`code`, PartColour.encode).

const SIZE := Vector2(98, 58)

var category := ""
var part: Dictionary = {}
var ink := Color(0.93, 0.93, 0.93)
## Drawing scale: 1.0 is the original 98 px picture; the shelf draws it at SHELF_K.
var scale_k := 1.0
## PartColour.encode's answer for this part ({} draws lines only): {kind, t, colour, ...}.
var code: Dictionary = {}
## The shelf's picture: the drawing at 0.6, cropped to a canvas 46 px wide (the drawing's own margins
## are left out, so the part itself is what fills the 46 px).
const SHELF_K := 0.6
const SHELF_W := 46.0
## The canvas's width in px when it is narrower than the drawing (0 = the drawing's own width).
var canvas_w := 0.0


func _init(category_: String = "", part_: Dictionary = {}, ink_: Color = Color(0.93, 0.93, 0.93),
		scale_: float = 1.0, code_: Dictionary = {}, canvas_w_: float = 0.0) -> void:
	category = category_
	part = part_
	ink = ink_
	scale_k = scale_
	code = code_
	canvas_w = canvas_w_
	custom_minimum_size = Vector2(canvas_w_ if canvas_w_ > 0.0 else SIZE.x * scale_, SIZE.y * scale_)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var shift := (canvas_w - SIZE.x * scale_k) * 0.5 if canvas_w > 0.0 else 0.0
	draw_set_transform(Vector2(shift, 0.0), 0.0, Vector2(scale_k, scale_k))
	var s: Dictionary = part.get("specs", {})
	var c := SIZE * 0.5
	# A line that stays about a pixel and a half wide once drawn, however small the picture.
	var w := maxf(1.4, 0.9 / scale_k)
	var hl := w * 0.7
	var fc := _fill_colour()
	var ft := _fill_t()
	match category:
		"none":  # an empty slot: a ring with a slash
			draw_arc(c, 16.0, 0.0, TAU, 28, ink * Color(1, 1, 1, 0.6), w)
			draw_line(c + Vector2(-11, 11), c + Vector2(11, -11), ink * Color(1, 1, 1, 0.6), w)
		"battery":
			var cells := clampi(int(s.get("cells", 1)), 1, 8)
			var r := Rect2(14, 14, 70, 30)
			_fill_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), ft, fc, false)
			draw_rect(r, ink, false, w)
			draw_rect(Rect2(84, 24, 4, 10), ink, false, w)
			for i in range(1, cells):
				var x := r.position.x + r.size.x * float(i) / cells
				draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.end.y - 4), ink * Color(1, 1, 1, 0.5), hl)
		"motor":
			var h := clampf(float(s.get("stator_height_mm", 7)), 2.0, 14.0)
			var d := clampf(float(s.get("stator_diameter_mm", 22)), 6.0, 40.0)
			var rad := 8.0 + d * 0.4
			var bh := 8.0 + h * 1.5
			var top := c.y - bh * 0.5 - 4
			if not code.is_empty():
				draw_rect(Rect2(c.x - rad, top, rad * 2.0, bh), fc)
			draw_rect(Rect2(c.x - rad, top, rad * 2.0, bh), ink, false, w)
			draw_line(Vector2(c.x, top - 6), Vector2(c.x, top), ink, w)
			draw_line(Vector2(c.x - rad * 0.6, top + bh), Vector2(c.x - rad * 0.6, top + bh + 8), ink, w)
			draw_line(Vector2(c.x + rad * 0.6, top + bh), Vector2(c.x + rad * 0.6, top + bh + 8), ink, w)
		"propeller":
			var blades := clampi(int(s.get("blades", 2)), 2, 6)
			var blade_len := clampf(float(s.get("diameter_inches", 5)) * 5.0 + 8.0, 12.0, 28.0)
			for i in blades:
				var a := TAU * float(i) / blades - PI * 0.5
				var dir := Vector2.from_angle(a)
				var side := dir.orthogonal() * (blade_len * 0.2)
				var tip := c + dir * blade_len
				var kite := [c, c + dir * blade_len * 0.5 + side, tip, c + dir * blade_len * 0.5 - side]
				if not code.is_empty():
					draw_colored_polygon(PackedVector2Array(kite), fc)
				draw_colored_polygon_outline(kite, ink, w)
			draw_arc(c, 3.0, 0.0, TAU, 14, ink, w)
		"esc":
			_board(c, 36.0, true)
			draw_line(Vector2(c.x - 18, c.y + 22), Vector2(c.x - 18, c.y + 27), ink, w)
			draw_line(Vector2(c.x + 18, c.y + 22), Vector2(c.x + 18, c.y + 27), ink, w)
		"flight_controller":
			_board(c, 36.0, false)
		"guard":
			if not code.is_empty() and ft > 0.0:
				draw_arc(c, 19.5, -PI * 0.5, -PI * 0.5 + TAU * ft, 32, fc, 4.0)
			draw_arc(c, 22.0, 0.0, TAU, 32, ink, w)
			draw_arc(c, 17.0, 0.0, TAU, 32, ink * Color(1, 1, 1, 0.5), hl)
			draw_line(c + Vector2(22, 0), c + Vector2(40, 0), ink, w)
		"camera":
			_fill_rect(Rect2(c.x - 14, c.y - 14, 28, 28), ft, fc, true)
			draw_rect(Rect2(c.x - 15, c.y - 15, 30, 30), ink, false, w)
			draw_arc(c, 9.0, 0.0, TAU, 20, ink, w)
			draw_arc(c, 4.0, 0.0, TAU, 14, ink, w)
		"vtx":
			_fill_rect(Rect2(c.x - 21, c.y - 13, 42, 26), ft, fc, false)
			draw_rect(Rect2(c.x - 22, c.y - 14, 44, 28), ink, false, w)
			draw_line(Vector2(c.x + 22, c.y), Vector2(c.x + 34, c.y), ink, w)
			for i in 3:
				draw_arc(Vector2(c.x + 34, c.y), 4.0 + 4.0 * i, -0.9, 0.9, 8, ink * Color(1, 1, 1, 0.6), hl)
		"antenna":
			draw_line(Vector2(c.x - 6, c.y + 22), Vector2(c.x - 6, c.y - 18), ink, w)
			draw_line(Vector2(c.x - 6, c.y + 22), Vector2(c.x + 12, c.y + 22), ink, w)
			draw_circle(Vector2(c.x - 6, c.y - 20), 2.0, ink)
			_fill_rect(Rect2(c.x - 20, c.y + 26, 40, 4), ft, fc, false)
			draw_rect(Rect2(c.x - 20, c.y + 26, 40, 4), ink * Color(1, 1, 1, 0.6), false, hl)
		_:  # receiver, and anything uncatalogued
			_fill_rect(Rect2(c.x - 17, c.y - 7, 34, 14), ft, fc, false)
			draw_rect(Rect2(c.x - 18, c.y - 8, 36, 16), ink, false, w)
			draw_line(Vector2(c.x + 18, c.y - 4), Vector2(c.x + 32, c.y - 18), ink, w)


## A square board with four mounting holes (the stack pattern); `stripes` adds the ESC's power bars.
func _board(c: Vector2, side: float, stripes: bool) -> void:
	var r := Rect2(c.x - side * 0.5, c.y - side * 0.5, side, side)
	var w := maxf(1.4, 0.9 / scale_k)
	_fill_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), _fill_t(), _fill_colour(), true)
	draw_rect(r, ink, false, w)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_arc(c + Vector2(sx, sy) * (side * 0.5 - 5.0), 2.0, 0.0, TAU, 8, ink, w * 0.85)
	if stripes:
		for i in 3:
			var y := c.y - 6.0 + 6.0 * i
			draw_line(Vector2(c.x - 8, y), Vector2(c.x + 8, y), ink * Color(1, 1, 1, 0.6), w * 0.7)
	else:
		draw_rect(Rect2(c.x - 6, c.y - 6, 12, 12), ink * Color(1, 1, 1, 0.6), false, w * 0.7)


## The fill level the picture shows (0 without a code, so a bare picture is lines only).
func _fill_t() -> float:
	return float(code.get("t", 0.0))


func _fill_colour() -> Color:
	return code.get("colour", ink)


## `t` of `r` filled in `col`: from the left, or from the bottom when `up`. Nothing without a code.
func _fill_rect(r: Rect2, t: float, col: Color, up: bool) -> void:
	if code.is_empty() or t <= 0.0:
		return
	if up:
		var h := r.size.y * t
		draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
	else:
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x * t, r.size.y), col)


func draw_colored_polygon_outline(pts: Array, col: Color, width: float) -> void:
	var p := PackedVector2Array(pts)
	p.append(p[0])
	draw_polyline(p, col, width)
