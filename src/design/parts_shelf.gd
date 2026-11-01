class_name PartsShelf
extends VBoxContainer
## The parts shelf (PLAN Section 5): a "Parts" header that opens a column of categories, each of
## which opens to its parts. A part is dragged out of a row onto the drone (DesignSpace does the
## drag; the row only says which part was picked up).
##
## The catalog lists every class's parts in one category (1S whoop packs beside 6S packs), so a
## category opens with the parts that would fit THIS drone first, in ink, and the rest after a
## "does not fit this drone" line, faint. They stay draggable: dropping one shows the refusal and
## its reason, which is the answer to "why not this one". The verdicts come from the caller
## (`judge`, one build per part), and only for a category the user opens.
##
## Monochrome: ink, muted and faint greys; nothing here uses the accent.

signal drag_started(part_id: String)
signal toggled(open: bool)

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const WIDTH := 240.0
const MAX_LIST_H := 470.0

var open := false
var header: Button
var list: VBoxContainer
var scroll: ScrollContainer
## category -> true while that category is opened.
var expanded := {}
## Rows as shown, for tests: [{category, id, name, ok, reason, button}] (open categories only).
var rows: Array = []
## The groups last handed in (PartSnap.shelf's shape).
var _groups: Array = []
## Callable(category) -> {part_id: {ok, reason}}; null shows every part as fitting.
var judge: Callable


func _init() -> void:
	name = "Shelf"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(WIDTH, 0)
	header = _flat_button("Parts", LothalTheme.FONT_SIZE_BODY, INK_MUTED)
	header.name = "ShelfHeader"
	header.pressed.connect(func(): set_open(not open))
	add_child(header)
	scroll = ScrollContainer.new()
	scroll.name = "ShelfScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, 0)
	scroll.visible = false
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	_update_header()


func set_open(want: bool) -> void:
	if open == want:
		return
	open = want
	scroll.visible = open
	_update_header()
	_rebuild()
	toggled.emit(open)


## Shows `groups` ([{category, name, parts: [{id, name, numbers}]}]); keeps which are expanded.
func fill(groups: Array) -> void:
	_groups = groups
	_rebuild()


func toggle_category(category: String) -> void:
	expanded[category] = not bool(expanded.get(category, false))
	_rebuild()


## The row for `part_id` ({} when it is not showing).
func row_of(part_id: String) -> Dictionary:
	for r in rows:
		if String(r["id"]) == part_id:
			return r
	return {}


func _update_header() -> void:
	header.text = ("⌄  Parts" if open else "›  Parts")


func _rebuild() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	if not open:
		scroll.custom_minimum_size.y = 0.0
		return
	var h := 0.0
	for g in _groups:
		var cat := String(g["category"])
		var parts: Array = g["parts"]
		var is_open := bool(expanded.get(cat, false))
		var head := _flat_button("%s %s   %d" % ["⌄" if is_open else "›",
			String(g["name"]).to_upper(), parts.size()], LothalTheme.FONT_SIZE_SMALL, INK_MUTED)
		head.name = "Cat_" + cat
		head.pressed.connect(func(): toggle_category(cat))
		list.add_child(head)
		h += head.get_combined_minimum_size().y + 1.0
		if not is_open:
			continue
		var verdicts: Dictionary = judge.call(cat) if judge.is_valid() else {}
		var fits: Array = []
		var misfits: Array = []
		for p in parts:
			var v: Dictionary = verdicts.get(String(p["id"]), {"ok": true, "reason": "", "rank": 0.0})
			(fits if v["ok"] else misfits).append([p, v])
		# Among the parts that mount, the ones nearest this drone's own first (`rank`, the caller's).
		fits.sort_custom(func(a, b): return float(a[1].get("rank", 0.0)) < float(b[1].get("rank", 0.0)))
		for pair in fits:
			h += _add_row(cat, pair[0], pair[1])
		if not misfits.is_empty():
			var note := Label.new()
			note.text = "Does not fit this drone"
			note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			note.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
			note.add_theme_color_override("font_color", INK_MUTED)
			note.custom_minimum_size = Vector2(0, 20)
			note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			list.add_child(note)
			h += note.get_combined_minimum_size().y + 1.0
			for pair in misfits:
				h += _add_row(cat, pair[0], pair[1])
	scroll.custom_minimum_size.y = minf(h, MAX_LIST_H)


func _add_row(cat: String, part: Dictionary, v: Dictionary) -> float:
	var numbers := " · ".join(PackedStringArray(part.get("numbers", [])))
	var b := _flat_button(String(part["name"]) + ("\n" + numbers if numbers != "" else ""),
		LothalTheme.FONT_SIZE_SMALL, INK if v["ok"] else INK_FAINT)
	b.name = "Part_" + String(part["id"])
	b.clip_text = true
	b.mouse_default_cursor_shape = Control.CURSOR_DRAG
	b.tooltip_text = "" if v["ok"] else String(v["reason"])
	var id := String(part["id"])
	b.button_down.connect(func(): drag_started.emit(id))
	list.add_child(b)
	rows.append({"category": cat, "id": id, "name": String(part["name"]), "ok": v["ok"],
		"reason": String(v["reason"]), "button": b})
	return b.get_combined_minimum_size().y + 1.0


func _flat_button(text: String, font_size: int, ink: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.06)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(5)
	var plain := StyleBoxEmpty.new()
	plain.set_content_margin_all(5)
	b.add_theme_stylebox_override("normal", plain)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	return b
