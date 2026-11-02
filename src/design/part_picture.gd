class_name PartPicture
extends Control
## A clean monochrome line diagram of a part, drawn in code per category (the catalog has no
## per-part model, only whole-class models). Proportions follow the part's own numbers where a
## number is cheap to use (cell count, blade count, motor size, board pattern), so two parts of
## one category do not look identical. Lines only; `ink` is the card's colour.

const SIZE := Vector2(98, 58)

var category := ""
var part: Dictionary = {}
var ink := Color(0.93, 0.93, 0.93)
## Drawing scale: 1.0 is the shelf's 98 px picture; the swap strip draws the same lines smaller.
var scale_k := 1.0


func _init(category_: String = "", part_: Dictionary = {}, ink_: Color = Color(0.93, 0.93, 0.93),
		scale_: float = 1.0) -> void:
	category = category_
	part = part_
	ink = ink_
	scale_k = scale_
	custom_minimum_size = SIZE * scale_
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_k, scale_k))
	var s: Dictionary = part.get("specs", {})
	var c := SIZE * 0.5
	var w := 1.4
	match category:
		"none":  # an empty slot: a ring with a slash
			draw_arc(c, 16.0, 0.0, TAU, 28, ink * Color(1, 1, 1, 0.6), w)
			draw_line(c + Vector2(-11, 11), c + Vector2(11, -11), ink * Color(1, 1, 1, 0.6), w)
		"battery":
			var cells := clampi(int(s.get("cells", 1)), 1, 8)
			var r := Rect2(14, 14, 70, 30)
			draw_rect(r, ink, false, w)
			draw_rect(Rect2(84, 24, 4, 10), ink, false, w)
			for i in range(1, cells):
				var x := r.position.x + r.size.x * float(i) / cells
				draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.end.y - 4), ink * Color(1, 1, 1, 0.5), 1.0)
		"motor":
			var h := clampf(float(s.get("stator_height_mm", 7)), 2.0, 14.0)
			var d := clampf(float(s.get("stator_diameter_mm", 22)), 6.0, 40.0)
			var rad := 8.0 + d * 0.4
			var bh := 8.0 + h * 1.5
			var top := c.y - bh * 0.5 - 4
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
				draw_colored_polygon_outline([c, c + dir * blade_len * 0.5 + side, tip, c + dir * blade_len * 0.5 - side], ink, w)
			draw_arc(c, 3.0, 0.0, TAU, 14, ink, w)
		"esc":
			_board(c, 36.0, true)
			draw_line(Vector2(c.x - 18, c.y + 22), Vector2(c.x - 18, c.y + 27), ink, w)
			draw_line(Vector2(c.x + 18, c.y + 22), Vector2(c.x + 18, c.y + 27), ink, w)
		"flight_controller":
			_board(c, 36.0, false)
		"guard":
			draw_arc(c, 22.0, 0.0, TAU, 32, ink, w)
			draw_arc(c, 17.0, 0.0, TAU, 32, ink * Color(1, 1, 1, 0.5), 1.0)
			draw_line(c + Vector2(22, 0), c + Vector2(40, 0), ink, w)
		"camera":
			draw_rect(Rect2(c.x - 15, c.y - 15, 30, 30), ink, false, w)
			draw_arc(c, 9.0, 0.0, TAU, 20, ink, w)
			draw_arc(c, 4.0, 0.0, TAU, 14, ink, w)
		"vtx":
			draw_rect(Rect2(c.x - 22, c.y - 14, 44, 28), ink, false, w)
			draw_line(Vector2(c.x + 22, c.y), Vector2(c.x + 34, c.y), ink, w)
			for i in 3:
				draw_arc(Vector2(c.x + 34, c.y), 4.0 + 4.0 * i, -0.9, 0.9, 8, ink * Color(1, 1, 1, 0.6), 1.0)
		"antenna":
			draw_line(Vector2(c.x - 6, c.y + 22), Vector2(c.x - 6, c.y - 18), ink, w)
			draw_line(Vector2(c.x - 6, c.y + 22), Vector2(c.x + 12, c.y + 22), ink, w)
			draw_circle(Vector2(c.x - 6, c.y - 20), 2.0, ink)
		_:  # receiver, and anything uncatalogued
			draw_rect(Rect2(c.x - 18, c.y - 8, 36, 16), ink, false, w)
			draw_line(Vector2(c.x + 18, c.y - 4), Vector2(c.x + 32, c.y - 18), ink, w)


## A square board with four mounting holes (the stack pattern); `stripes` adds the ESC's power bars.
func _board(c: Vector2, side: float, stripes: bool) -> void:
	var r := Rect2(c.x - side * 0.5, c.y - side * 0.5, side, side)
	draw_rect(r, ink, false, 1.4)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_arc(c + Vector2(sx, sy) * (side * 0.5 - 5.0), 2.0, 0.0, TAU, 8, ink, 1.2)
	if stripes:
		for i in 3:
			var y := c.y - 6.0 + 6.0 * i
			draw_line(Vector2(c.x - 8, y), Vector2(c.x + 8, y), ink * Color(1, 1, 1, 0.6), 1.0)
	else:
		draw_rect(Rect2(c.x - 6, c.y - 6, 12, 12), ink * Color(1, 1, 1, 0.6), false, 1.0)


func draw_colored_polygon_outline(pts: Array, col: Color, width: float) -> void:
	var p := PackedVector2Array(pts)
	p.append(p[0])
	draw_polyline(p, col, width)
