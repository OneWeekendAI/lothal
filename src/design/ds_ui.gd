class_name DsUi
extends RefCounted
## The Design Space's small widgets in one place: the same ink greys, hairline buttons, "tag" chip and dialog box the file
## bar and the frame tool row already draw, so a panel built from these reads as part of the same room. Nothing new is
## styled here; every value is the one those two files use (monochrome, amber only for a warning).

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const WARN := LothalTheme.WARNING


static func label(text: String, ink := INK_MUTED, size := LothalTheme.FONT_SIZE_SMALL) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	return l


## A small caps section title, as the open dialog's "OPEN  ·  RECENT".
static func section(text: String) -> Label:
	return label(text.to_upper(), INK_FAINT)


static func rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = INK_FAINT
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _box(bg: Color, border: Color, radius := LothalTheme.RADIUS_CONTROL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = LothalTheme.SPACE_3
	s.content_margin_right = LothalTheme.SPACE_3
	s.content_margin_top = LothalTheme.SPACE_2
	s.content_margin_bottom = LothalTheme.SPACE_2
	return s


## The hairline button of the file bar. `toggle`: selected = lighter fill and an ink border (the tool row's look).
## `primary`: rests in that selected look, the one lit action of a group.
static func button(text: String, toggle := false, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	b.add_theme_color_override("font_color", INK if primary else INK_MUTED)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	var flat := _box(Color(1, 1, 1, 0.16) if primary else Color(1, 1, 1, 0.05), INK_MUTED if primary else Color(1, 1, 1, 0.12))
	b.add_theme_stylebox_override("normal", flat)
	var hover := _box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.12))
	b.add_theme_stylebox_override("hover", hover)
	var on := _box(Color(1, 1, 1, 0.16), INK_MUTED)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b


## The "not modelled" tag of the tool row: returns [chip, label] so the caller can change the words.
static func tag(text: String) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = INK_FAINT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, INK_MUTED)
	p.add_child(l)
	return [p, l]


## The dialog box of the file bar.
static func panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.075, 0.085, 0.97)
	box.border_color = Color(1, 1, 1, 0.14)
	box.set_border_width_all(1)
	box.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


## The name field of the Save as dialog.
static func style_field(e: LineEdit) -> void:
	e.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("caret_color", INK)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.05)
	field.border_color = Color(1, 1, 1, 0.22)
	field.set_border_width_all(1)
	field.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	field.content_margin_left = 8
	field.content_margin_right = 8
	field.content_margin_top = 5
	field.content_margin_bottom = 5
	e.add_theme_stylebox_override("normal", field)
	var f2 := field.duplicate() as StyleBoxFlat
	f2.border_color = Color(1, 1, 1, 0.55)
	e.add_theme_stylebox_override("focus", f2)


## The slider of the tool row: a thin rule, the filled part in ink.
static func style_slider(s: HSlider) -> void:
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 18)
	var track := StyleBoxFlat.new()
	track.bg_color = INK_FAINT
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = INK_MUTED
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
