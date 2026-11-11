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
##
## EVERY STATE LOOKS DIFFERENT (B4): rest, hover (brighter than rest, primary included), pressed (momentary: darker
## than rest with an ink border, so a click is seen), disabled (nearly gone), focus (an ACCENT hairline ring for
## the keyboard) and, through `set_busy`, busy (a held, lit "working" look that is not the disabled one).
## For a toggle, "pressed" is the selected look, and `hover_pressed` is that look brightened.
static func button(text: String, toggle := false, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	# Reachable by keyboard. A mouse press hands the focus straight back (below), so the ring never sits on
	# a button that was only clicked.
	b.focus_mode = Control.FOCUS_ALL
	if not toggle:
		b.pressed.connect(b.release_focus)
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	b.add_theme_color_override("font_color", INK if primary else INK_MUTED)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	var rest_fill := 0.16 if primary else 0.05
	var rest_edge := INK_MUTED if primary else Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, rest_fill), rest_edge))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.26 if primary else 0.12), INK_MUTED if primary else Color(1, 1, 1, 0.22)))
	if toggle:
		# Selected: the lit look; brighter under the pointer.
		b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.16), INK_MUTED))
		b.add_theme_stylebox_override("hover_pressed", _box(Color(1, 1, 1, 0.24), INK))
	else:
		# A click: darker than rest, ink edge, and the label one pixel down (the "pushed in" cue).
		var down := _box(Color(1, 1, 1, 0.07 if primary else 0.02), INK)
		down.content_margin_top += 1
		down.content_margin_bottom -= 1
		b.add_theme_stylebox_override("pressed", down)
		b.add_theme_stylebox_override("hover_pressed", down)
	var off := _box(Color(1, 1, 1, 0.015), Color(1, 1, 1, 0.05))
	b.add_theme_stylebox_override("disabled", off)
	b.set_meta("ds_disabled_box", off)
	var ring := _box(Color(1, 1, 1, rest_fill), LothalTheme.ACCENT)
	b.add_theme_stylebox_override("focus", ring)
	return b


## Busy: the button holds a lit look, cannot be pressed again and says what it is doing ("Loading..."). `on` false
## restores the label and the plain disabled look. Not the same look as disabled, so "working" and "unavailable"
## read differently.
static func set_busy(b: Button, on: bool, busy_text := "Working...") -> void:
	if on:
		if not b.has_meta("ds_rest_text"):
			b.set_meta("ds_rest_text", b.text)
		b.text = busy_text
		b.disabled = true
		b.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.10), LothalTheme.ACCENT_DIM))
		b.add_theme_color_override("font_disabled_color", INK_MUTED)
	else:
		if b.has_meta("ds_rest_text"):
			b.text = String(b.get_meta("ds_rest_text"))
			b.remove_meta("ds_rest_text")
		b.disabled = false
		b.add_theme_stylebox_override("disabled", b.get_meta("ds_disabled_box"))
		b.add_theme_color_override("font_disabled_color", INK_FAINT)


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
