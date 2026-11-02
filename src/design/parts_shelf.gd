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
## Swap mode (a part is selected on the drone): the pointer over a card, and off it again.
signal card_hovered(category: String, part_id: String)
signal card_unhovered
## The "None" card pressed (the other cards are clicked through the drag, see DesignSpace.end_drag).
signal card_clicked(category: String, part_id: String)

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const WIDTH := 240.0
const MAX_LIST_H := 470.0
## Cards: two to a row in WIDTH (less the scrollbar); headers and notes take a whole row.
const CARD_W := 106.0
const CARD_H := 116.0
const GAP := 4
const CHIP_H := 18.0
const TAG_W := 40.0
const ROW_W := 218.0
## The one amber of the shelf: a misfit's reason, as the rest of the app shows a warning.
const WARN := Color(0.95, 0.72, 0.28)

var open := false
var header: Button
var list: HFlowContainer
var scroll: ScrollContainer
## category -> true while that category is opened.
var expanded := {}
## Rows as shown, for tests: [{category, id, name, ok, reason, button}] (open categories only).
var rows: Array = []
## category -> {group key: option id}: the chips pressed (PartFilter).
var filters := {}
## category -> true while its misfits are shown (the default is to hide them).
var show_misfits := {}
## The cue under the list that it runs on below the fold.
var more_cue: Label
## The list's laid-out height (estimated from the cards), to tell whether it overflows.
var _content_h := 0.0
## The groups last handed in (PartSnap.shelf's shape).
var _groups: Array = []
## Callable(category) -> {part_id: {ok, reason}}; null shows every part as fitting.
var judge: Callable
## Swap mode: the categories of the selected part's slot (a click on a card swaps it in place; a
## card then only drags when the pointer leaves it), and the part fitted now in each ("" for none).
var swap_cats: Array = []
var fitted := {}
## Where the list scrolls to, once the fitted part's card is laid out (px from the list's top).
var scroll_target := -1.0
var _scroll_pending := false


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
	list = HFlowContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", GAP)
	list.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(list)
	more_cue = Label.new()
	more_cue.name = "MoreCue"
	more_cue.text = "⌄  more below"
	more_cue.visible = false
	more_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	more_cue.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	more_cue.add_theme_color_override("font_color", INK_MUTED)
	add_child(more_cue)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_cue())
	scroll.get_v_scroll_bar().changed.connect(_update_cue)
	scroll.get_v_scroll_bar().changed.connect(_apply_scroll)
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


## A part was selected on the drone: opens the shelf if it was shut, expands exactly `cats`
## (collapsing the rest), marks `fitted_ids` ({category: part id}) and scrolls to the first of them.
func focus_slot(cats: Array, fitted_ids: Dictionary, groups: Array) -> void:
	_groups = groups
	swap_cats = cats.duplicate()
	fitted = fitted_ids.duplicate()
	expanded = {}
	for c in cats:
		expanded[String(c)] = true
	if open:
		_rebuild()
	else:
		set_open(true)


## Nothing is selected: no swapping, no marks. What was expanded stays so.
func clear_focus(groups: Array) -> void:
	if swap_cats.is_empty() and fitted.is_empty():
		return
	_groups = groups
	swap_cats = []
	fitted = {}
	scroll_target = -1.0
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
	scroll_target = -1.0
	_scroll_pending = false
	if not open:
		scroll.custom_minimum_size.y = 0.0
		_content_h = 0.0
		_update_cue()
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
		head.custom_minimum_size.x = ROW_W
		h += head.get_combined_minimum_size().y + GAP
		if not is_open:
			continue
		var verdicts: Dictionary = judge.call(cat) if judge.is_valid() else {}
		var entries: Array = []
		for p in parts:
			var v: Dictionary = verdicts.get(String(p["id"]), {"ok": true, "reason": "", "rank": 0.0})
			entries.append({"part": p.get("part", {}), "p": p, "ok": v["ok"], "v": v})
		var chosen: Dictionary = filters.get(cat, {})
		h += _add_chips(cat, chosen)
		var shown := PartFilter.view(entries, cat, chosen, bool(show_misfits.get(cat, false)))
		var fits: Array = shown["fits"]
		var misfits: Array = shown["misfits"]
		# Among the parts that mount, the ones nearest this drone's own first (`rank`, the caller's).
		fits.sort_custom(func(a, b): return float(a["v"].get("rank", 0.0)) < float(b["v"].get("rank", 0.0)))
		var empty_view := fits.is_empty() and misfits.is_empty()
		# Swapping a part that may be left off: a first card for "not fitted".
		if swap_cats.has(cat) and ProjectSchema.OPTIONAL_CATEGORIES.has(cat):
			fits.push_front({"part": {}, "p": {"id": "", "name": "None", "part": {}, "caption": ""},
				"ok": true, "v": {"ok": true, "reason": "", "rank": 0.0}})
		var base := h
		for k in fits.size():
			_add_row(cat, fits[k]["p"], fits[k]["v"], base + floorf(k / 2.0) * (CARD_H + GAP))
		h += _card_rows(fits.size())
		if empty_view:
			h += _add_note("Nothing here fits" if int(shown["hidden"]) == 0 else "Nothing fits with these filters")
		if int(shown["hidden"]) > 0 or int(shown["total_misfits"]) > 0:
			h += _add_misfit_toggle(cat, int(shown["hidden"]), bool(show_misfits.get(cat, false)))
		if not misfits.is_empty():
			h += _add_note("Does not fit this drone")
			base = h
			for k in misfits.size():
				_add_row(cat, misfits[k]["p"], misfits[k]["v"], base + floorf(k / 2.0) * (CARD_H + GAP))
			h += _card_rows(misfits.size())
	_content_h = h
	scroll.custom_minimum_size.y = minf(h, MAX_LIST_H)
	scroll.scroll_vertical = mini(scroll.scroll_vertical, maxi(int(h - MAX_LIST_H), 0))
	for r in rows:
		if bool(r["fitted"]):
			# A card already in view leaves the list at the top (the category's head and chips stay
			# showing); a farther one comes up with a little of the way to it above.
			var y := float(r["y"])
			scroll_target = 0.0 if y + CARD_H <= MAX_LIST_H else y - 56.0
			_scroll_pending = true
			break
	_apply_scroll()
	_update_cue()


## Scrolls to the fitted card once the list has the range for it (called again as the bar's range
## changes, so a list that is laid out a frame later still arrives).
func _apply_scroll() -> void:
	if not _scroll_pending:
		return
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(scroll_target)
	if bar.page > 0.0:
		_scroll_pending = false


## Set one chip: pressing the option already chosen clears it. Rebuilds.
func set_filter(category: String, key: String, option_id: String) -> void:
	var f: Dictionary = filters.get(category, {}).duplicate()
	if option_id == "" or String(f.get(key, "")) == option_id:
		f.erase(key)
	else:
		f[key] = option_id
	filters[category] = f
	_rebuild()


func set_show_misfits(category: String, want: bool) -> void:
	show_misfits[category] = want
	_rebuild()


## Whether the list runs on below what shows (the "more below" cue is up). Once the scroll bar has
## its real range (a laid-out window) that decides; before, the estimate from the cards does.
func can_scroll_more() -> bool:
	if not open:
		return false
	var bar := scroll.get_v_scroll_bar()
	if bar.page > 0.0:
		return bar.value + bar.page < bar.max_value - 1.0
	return _content_h > scroll.custom_minimum_size.y + 1.0 \
		and float(scroll.scroll_vertical) + scroll.custom_minimum_size.y < _content_h - 1.0


func _update_cue() -> void:
	more_cue.visible = can_scroll_more()


## The category's chip groups: a faint label then small toggle chips. Returns the height used.
func _add_chips(cat: String, chosen: Dictionary) -> float:
	var h := 0.0
	for g in PartFilter.chips(cat):
		var flow := HFlowContainer.new()
		flow.name = "Chips_" + String(g["key"])
		flow.custom_minimum_size.x = ROW_W
		flow.add_theme_constant_override("h_separation", 2)
		flow.add_theme_constant_override("v_separation", 2)
		var tag := Label.new()
		tag.text = String(g["label"])
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL - 2)
		tag.add_theme_color_override("font_color", INK_FAINT)
		tag.custom_minimum_size = Vector2(TAG_W, CHIP_H)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		flow.add_child(tag)
		var x := TAG_W
		var n_rows := 1
		for o in g["options"]:
			var on := String(chosen.get(g["key"], "")) == String(o["id"])
			var c := _chip(String(o["label"]), on)
			c.name = "Chip_%s_%s" % [g["key"], o["id"]]
			var key := String(g["key"])
			var oid := String(o["id"])
			c.pressed.connect(func(): set_filter(cat, key, oid))
			flow.add_child(c)
			var w := c.custom_minimum_size.x + 2.0
			if x + w > ROW_W:
				n_rows += 1
				x = 0.0
			x += w
		list.add_child(flow)
		h += n_rows * (CHIP_H + 2.0) + GAP
	return h


func _chip(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL - 1)
	b.add_theme_color_override("font_color", INK_MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.14) if on else Color(1, 1, 1, 0.04)
	sb.border_color = INK_MUTED if on else Color(1, 1, 1, 0.10)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.18 if on else 0.09)
	for st in ["normal", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hv)
	b.custom_minimum_size = Vector2(maxf(26.0, 12.0 + 6.5 * text.length()), CHIP_H)
	return b


## The "show parts that don't fit (N)" toggle. Returns its height.
func _add_misfit_toggle(cat: String, n_hidden: int, showing: bool) -> float:
	var t := "hide parts that don't fit" if showing else "show parts that don't fit (%d)" % n_hidden
	var b := _flat_button(t, LothalTheme.FONT_SIZE_SMALL - 1, INK_MUTED)
	b.name = "MisfitToggle_" + cat
	b.custom_minimum_size = Vector2(ROW_W, 0)
	b.pressed.connect(func(): set_show_misfits(cat, not showing))
	list.add_child(b)
	return b.get_combined_minimum_size().y + GAP


func _add_note(text: String) -> float:
	var note := Label.new()
	note.text = text
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	note.add_theme_color_override("font_color", INK_MUTED)
	note.custom_minimum_size = Vector2(ROW_W, 20)
	note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	list.add_child(note)
	return note.get_combined_minimum_size().y + GAP


## Height of `n` cards laid two to a row.
func _card_rows(n: int) -> float:
	return ceilf(n / 2.0) * (CARD_H + GAP)


func _add_row(cat: String, part: Dictionary, v: Dictionary, y: float = 0.0) -> void:
	var ink: Color = INK if v["ok"] else INK_FAINT
	var id := String(part["id"])
	var is_fitted := swap_cats.has(cat) and fitted.has(cat) and String(fitted[cat]) == id
	var b := _flat_button("", LothalTheme.FONT_SIZE_SMALL, ink)
	b.name = "Part_" + id if id != "" else "Part_none_" + cat
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.mouse_default_cursor_shape = Control.CURSOR_DRAG if id != "" else Control.CURSOR_POINTING_HAND
	b.tooltip_text = String(part["name"]) if v["ok"] else String(v["reason"])
	if id != "":
		b.button_down.connect(func(): drag_started.emit(id))
	elif swap_cats.has(cat):
		b.pressed.connect(func(): card_clicked.emit(cat, id))
	if swap_cats.has(cat):
		b.mouse_entered.connect(func(): card_hovered.emit(cat, id))
		b.mouse_exited.connect(func(): card_unhovered.emit())
		if is_fitted:
			var mark := StyleBoxFlat.new()
			mark.bg_color = Color(1, 1, 1, 0.07)
			mark.border_color = INK_MUTED
			mark.set_border_width_all(1)
			mark.set_corner_radius_all(6)
			b.add_theme_stylebox_override("normal", mark)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var pic := PartPicture.new(cat if id != "" else "none", part.get("part", {}), ink)
	pic.name = "Picture"
	col.add_child(pic)
	var name_label := _caption(String(part["name"]), ink, LothalTheme.FONT_SIZE_SMALL, "Name")
	# The whole name, over two lines when it needs them: a card never ends a name in an ellipsis.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	col.add_child(name_label)
	col.add_child(_caption(String(part.get("caption", "")), INK_MUTED if v["ok"] else INK_FAINT,
		LothalTheme.FONT_SIZE_SMALL - 1, "Spec"))
	# A misfit, while a part is selected: its one-line reason on the card itself, no hover needed.
	var why: Label = null
	if swap_cats.has(cat) and not v["ok"]:
		why = _caption(String(v["reason"]), WARN, LothalTheme.FONT_SIZE_SMALL - 2, "Reason")
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		why.max_lines_visible = 3
		col.add_child(why)
	b.add_child(col)
	if is_fitted:
		var badge := Label.new()
		badge.name = "Fitted"
		badge.text = "FITTED"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", INK)
		badge.position = Vector2(5, 2)
		b.add_child(badge)
	list.add_child(b)
	rows.append({"category": cat, "id": id, "name": String(part["name"]), "ok": v["ok"],
		"reason": String(v["reason"]), "button": b, "caption": String(part.get("caption", "")),
		"fitted": is_fitted, "y": y, "reason_label": why})


func _caption(text: String, ink: Color, font_px: int, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", ink)
	l.custom_minimum_size.x = CARD_W - 8.0
	return l


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
