class_name ReadoutGauge
extends Control
## One readout's gauge: a thin track whose fill shows where the value sits in a stated range. The
## fill fraction is a pure function (`fraction`), so it is tested without a window. Monochrome;
## amber only when `warn` is set (a warning moves this readout).

## key -> [low, high]: the value at the empty and the full end of the gauge. Chosen to bracket
## the classes from a 65 mm whoop to a 7" long-range build, so a 5" sits mid-gauge.
const RANGES := {
	"auw_g": [0.0, 1000.0],
	"thrust_to_weight": [0.0, 15.0],
	"hover_throttle": [0.0, 1.0],
	"flight_time_min": [0.0, 12.0],
	"top_speed_kmh": [0.0, 200.0],
}
const INK := Color(0.93, 0.93, 0.93)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const ICON_PX := 14.0
## The icons are drawn on a 20-unit grid and scaled down to ICON_PX.
const ART_UNITS := 20.0
const TRACK_H := 3.0

var key: String = ""
var fill: float = 0.0
var warn: bool = false


## Where `value` sits in `key`'s range, 0..1, clamped. A missing value (null) or an unknown key is 0.
static func fraction(key_: String, value: Variant) -> float:
	if value == null or not RANGES.has(key_):
		return 0.0
	var lo := float(RANGES[key_][0])
	var hi := float(RANGES[key_][1])
	var v := float(value)
	if is_nan(v):
		return 0.0
	return clampf((v - lo) / (hi - lo), 0.0, 1.0)


func _init(key_: String = "") -> void:
	key = key_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, TRACK_H)


func set_value(value: Variant) -> void:
	fill = fraction(key, value)
	queue_redraw()


func set_warn(on: bool) -> void:
	warn = on
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, size.x, TRACK_H), INK_FAINT)
	var ink := LothalTheme.WARNING if warn else INK
	draw_rect(Rect2(0, 0, size.x * fill, TRACK_H), ink)


## The icon Control for a readout: drawn in code, ICON_PX, one stroke weight.
class Icon extends Control:
	var key: String = ""

	func _init(key_: String = "") -> void:
		key = key_
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var c := Color(0.72, 0.72, 0.72)
		var w := 1.5
		match key:
			"auw_g":  # a kettlebell: ring handle over a trapezoid
				draw_arc(Vector2(10, 6), 3.5, PI, TAU, 12, c, w, true)
				draw_polyline(PackedVector2Array([Vector2(4, 18), Vector2(6, 9), Vector2(14, 9),
					Vector2(16, 18), Vector2(4, 18)]), c, w, true)
			"thrust_to_weight":  # up arrow over a base line
				draw_line(Vector2(10, 15), Vector2(10, 3), c, w, true)
				draw_polyline(PackedVector2Array([Vector2(5, 8), Vector2(10, 3), Vector2(15, 8)]), c, w, true)
				draw_line(Vector2(4, 18), Vector2(16, 18), c, w, true)
			"hover_throttle":  # a slider stick with its knob
				draw_line(Vector2(10, 3), Vector2(10, 17), c, w, true)
				draw_rect(Rect2(5, 8, 10, 4), c, false, w)
			"flight_time_min":  # a clock
				draw_arc(Vector2(10, 10), 7.5, 0.0, TAU, 28, c, w, true)
				draw_polyline(PackedVector2Array([Vector2(10, 5), Vector2(10, 10), Vector2(14, 12)]), c, w, true)
			"top_speed_kmh":  # a speedometer arc and needle
				draw_arc(Vector2(10, 14), 8.0, PI, TAU, 20, c, w, true)
				draw_line(Vector2(10, 14), Vector2(15, 8), c, w, true)
				draw_line(Vector2(2, 15), Vector2(18, 15), c, w, true)  # the base, so the dial reads whole
