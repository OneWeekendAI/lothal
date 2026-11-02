class_name PlugButton
extends Button
## A small drawn mains plug: two prongs, a body and a cable. Muted at rest, accent on hover,
## pulsing while `charging`, faint when disabled. No text; the chip beside it says the rest.

const SIDE := 22.0

var charging := false


func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var c := LothalTheme.TEXT_MUTED
	if disabled:
		c = LothalTheme.TEXT_FAINT
		c.a = 0.55
	elif charging:
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)
		c = LothalTheme.ACCENT.lerp(Color.WHITE, 0.25 * k)
		c.a = 0.6 + 0.4 * k
		draw_circle(size * 0.5, SIDE * (0.5 + 0.1 * k), Color(LothalTheme.ACCENT, 0.10 + 0.10 * k))
	elif is_hovered():
		c = LothalTheme.ACCENT
	var o := (size - Vector2(SIDE, SIDE)) * 0.5
	var w := 1.6
	# Prongs, body (rounded outline), cable.
	draw_line(o + Vector2(8, 3), o + Vector2(8, 8), c, w, true)
	draw_line(o + Vector2(14, 3), o + Vector2(14, 8), c, w, true)
	var body := PackedVector2Array([o + Vector2(5, 8), o + Vector2(17, 8), o + Vector2(17, 12),
		o + Vector2(14.5, 15), o + Vector2(7.5, 15), o + Vector2(5, 12), o + Vector2(5, 8)])
	draw_polyline(body, c, w, true)
	draw_line(o + Vector2(11, 15), o + Vector2(11, 19), c, w, true)
