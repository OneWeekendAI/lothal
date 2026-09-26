class_name PartFinder
extends VBoxContainer
## The summoned parts finder (plans/2026-09-19-quiet-canvas-design.md §4): one category of the
## catalog as a centred overlay, listing from the moment it opens, with a preview on the build
## behind it as the highlight moves.
##
## It replaces the permanent rail (`src/ui/part_picker.gd`), and it INHERITS that file's two rules
## rather than restating them in its own words:
##
## Filter options are DERIVED from the JSON, never listed here. The header chips a later slice
## draws are built from `filter_options()`, which walks the catalog — so the contributor who adds
## the first 31xx motor gets a chip without touching GDScript. The typed query matches against the
## same derived values, which is why `22xx` and `freestyle` narrow the list at all: nothing in this
## file knows those strings exist.
##
## A filter that matches nothing SAYS so, in the wording PartPicker already uses. An empty list
## with no explanation is indistinguishable from a broken catalog load.
##
## ## The decision this object exists to hold (§2 of the design)
##
## THE LIST IS NEVER CONDITIONAL ON INPUT. The stated audience is someone who does not know what a
## 2207 is, and you cannot type a name you have never heard; a finder that shows nothing until a
## keystroke arrives has optimised its own screenshot against its user. `visible_parts()` with an
## empty query is the whole catalog category, and `tests/test_part_finder.gd` mutates exactly that
## line to prove the check covering it can fail.
##
## ## Why it is a VBoxContainer and not a plain Control
##
## It WAS a plain `Control` that added a `VBoxContainer` as its own child, and that is a defect
## rather than a style: a `Control` neither lays its children out nor counts them in
## `get_combined_minimum_size()`, so this object reported `(368, 0)`, the `PanelContainer` around
## it obliged, and the first screenshot of QC4 was a **384x16 sliver** with eighteen motor rows
## drawing below it through the bottom of the window. Every assertion in the suite was green.
## `GlassShell._size_the_finder()` compensated from the outside by measuring the child column and
## pushing the answer back onto this node — a second place that had to know how tall a finder is.
##
## The root IS the column now. Nothing outside this file sizes it, and the two checks in
## `tests/test_shell_layout.gd` that measure the glass are mutated by putting `extends Control`
## back.
##
## ## Why it builds its own children in _init
##
## `tools/run_one_suite.gd` and `tests/run_tests.gd` process no frames, and the shell's rules used
## to be unreachable by any check for precisely that reason (see `tests/test_overlay_tray.gd`'s
## header). Every behaviour below is decided in _init or in a public method, never in `_ready()`,
## never after a layout pass — so the suite drives this object with no window and no tree.

## Emitted as the highlight moves. Provisional: the part is fitted on the build to be LOOKED at,
## and the builder has agreed to nothing by arrowing past it.
signal part_previewed(part: Dictionary)
## Emitted on accept(). This is the one that means the builder chose.
signal part_committed(part: Dictionary)
## Emitted on cancel(), carrying the part that was fitted when the finder opened — which is what
## the build is being put back to, not merely the fact that the finder closed.
signal fit_restored(part: Dictionary)
## A click on one of the category segments in the header. The POSITION in the system's own rail
## list, not a catalog category name: the shell is the only object that knows a system owns more
## than one shelf, and it re-summons the finder on the other one. Carried as a signal rather than
## done here because a finder that could rebuild itself on a different category would need the
## catalog, the noun and the filter axes of a shelf it was not constructed against.
signal category_chosen(position: int)
## The two authoring actions the rail used to carry under its list — "New custom motor…" and
## "Delete". Signals for the same reason as above: this object finds parts, it does not know how a
## custom motor is written to disk, and §4 forbids it becoming a command palette. The shell routes
## each one back to the rail's own button, which is still the only implementation.
signal new_part_requested()
signal delete_part_requested()
## The × in the corner. A finder that can only be dismissed by a key nobody was told about is a
## modal with no way out for anyone using the mouse — which is the audience §2 names. Routed to the
## shell rather than closed here for cancel()'s reason: closing is the BUILD being put back, and
## only the shell can take the overlay and the dim down together.
signal close_requested()

const ALL := PartPicker.ALL

## THE FINDER IS A PICKER, NOT A PAGE (the density pass).
##
## QC5's finder was laid out at the shell's body scale: an 18 px title, 13 px rows, 8 px between
## every child and a 368 px column. On screen that read as a document that happened to contain a
## list — it covered the aircraft it was there to help choose a part FOR, and on a short window it
## did not fit at all. Every number below is one step down the scales the theme already publishes;
## nothing here invents a size. `FONT_SIZE_SMALL` (11) is the floor the rest of the app uses for
## real text and this does not go under it.
const PANEL_WIDTH := 300.0
## The list's width inside the column. The gutter below is taken out of it, not added to it, so
## widening the scroll affordance can never widen the overlay.
const LIST_WIDTH := 284.0
## What the list asks for when the window has room, and the least it may be squeezed to before
## `fit_to_height` stops shrinking it. The floor is about five rows: a list shorter than that is a
## dropdown, and the whole argument of §2 is that a beginner browses.
const LIST_HEIGHT := 232.0
const LIST_HEIGHT_MIN := 96.0
## The scroll affordance's width, and the gutter reserved for it. See the comment on the
## `custom_minimum_size.x` line for why the bar has to be widened here at all.
const SCROLLBAR_WIDTH := 8.0
const ROW_GUTTER := SCROLLBAR_WIDTH + LothalTheme.SPACE_1


## The list, subclassed for ONE reason: where its tooltip is drawn.
##
## `ItemList` has no hook for tooltip placement, and the engine puts a tooltip a few pixels below
## and right of the cursor — which, over a list of 24 px rows, lands squarely on the row the cursor
## is on. The screenshot that prompted this showed `H743 30.5x30.5   12 g` hovering over the row
## reading `H743 30.5x30.5   12 g`, hiding it. `_make_custom_tooltip` is the only place a Control
## can move its own tooltip, so the row list owns one.
##
## It is a `MarginContainer` with a top inset rather than a repositioned popup because the engine
## owns the popup's position outright; padding the contents downward is the one lever that is ours.
class RowList extends ItemList:
	## The inset, in px. A row is the font's height plus the theme's `v_separation` and the
	## selected stylebox's margins, and this clears it with a little to spare.
	const TOOLTIP_DROP := 22

	func _make_custom_tooltip(for_text: String) -> Object:
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_top", TOOLTIP_DROP)
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"TooltipPanel"
		margin.add_child(panel)
		var label := Label.new()
		label.theme_type_variation = &"TooltipLabel"
		label.text = for_text
		panel.add_child(label)
		return margin


var catalog: PartsCatalog
## The category this finder lists, e.g. "motor".
var category: String
## What one entry is called, for the empty state's prose: "No motor matches these filters".
var noun: String
## Array of {"key": ..., "label": ..., optionally "block"/"format"} — the same entries the rail's
## dropdowns were built from, and the same shape PartPicker.value_of reads.
var filter_keys: Array

## The build seam. Anything with preview_part / commit_part / restore_part; null in QC1/QC2 tests
## that only care about the list, and the shell's own adapter from QC5 onward. Injected rather than
## reached for, so this file never holds a Build, a LabScreen or a node path — see set_fitter().
var _fitter: Object = null

var _header: Label
var _header_row: HBoxContainer
var _close_button: Button
var _category_row: HBoxContainer
var _facet_grid: GridContainer
var _facet_selectors: Dictionary = {}   # filter key -> OptionButton
var _query_edit: LineEdit
var _list: ItemList
var _empty_hint: Label
var _actions_row: HBoxContainer
var _new_button: Button
var _delete_button: Button

var _query: String = ""
var _filters: Dictionary = {}        # filter key -> selected value, ALL when unset
var _options: Dictionary = {}        # filter key -> Array[String], ALL first
var _entries: Dictionary = {}        # filter key -> the filter entry dictionary it came from
var _visible_parts: Array = []
var _highlight: int = -1
## The part that was fitted when open_on() was called. Kept as the RECORD and not as an index into
## the visible list: typing changes what is visible, and an index would point at a different part —
## or at nothing — by the time Escape arrives.
var _original_part: Dictionary = {}
var _opened := false


func _init(p_catalog: PartsCatalog, p_system: String, p_category: String, p_noun: String,
		p_filter_keys: Array) -> void:
	catalog = p_catalog
	category = p_category
	noun = p_noun
	filter_keys = p_filter_keys

	# ~23em at the shell's body size, per §4. Mouse-stopping because the canvas behind is dimmed
	# and a click that fell through would rotate the drone the overlay is covering.
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# SPACE_1 and not SPACE_2: eight children at 8 px apart is 56 px of air in a column that has to
	# clear the dock on a 720 px window, and it was most of what pushed the authoring row off the
	# bottom edge.
	add_theme_constant_override("separation", LothalTheme.SPACE_1)

	# The rail's title used to carry system and category, and §4 says that information must survive
	# the rail — without it the overlay is a list of names with no statement of what is being
	# chosen, which is the one thing a beginner needs most.
	for entry in filter_keys:
		var key: String = entry["key"]
		_entries[key] = entry
		_filters[key] = ALL
		_options[key] = _derive_options(entry)

	# THE TITLE AND THE WAY OUT, ON ONE LINE. The row exists for the × — a title Label that filled
	# the column left nowhere for it that was not a second row of chrome.
	_header_row = HBoxContainer.new()
	add_child(_header_row)

	_header = Label.new()
	_header.text = "%s · %s" % [p_system, _title_case(p_category)]
	_header.theme_type_variation = &"TitleLabel"
	# One step down the published scale — SUBTITLE, not TITLE. A picker's title names what is being
	# chosen; it is not the page's heading, because this is not a page.
	_header.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_row.add_child(_header)

	# ×, in the corner every window in this app puts it. `CompactButton` and not a bare Button: the
	# icon buttons of the dock and the room toolbars are that variation, and a close that looked
	# like nothing else on screen would read as part of the list.
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.theme_type_variation = &"CompactButton"
	_close_button.tooltip_text = "Close (Esc)"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	_header_row.add_child(_close_button)

	# The segments that reach a system's OTHER shelves. Empty and hidden until set_categories() is
	# called, because a finder constructed for a test knows nothing about systems — and because the
	# row must not reserve height on a system that owns exactly one shelf.
	_category_row = HBoxContainer.new()
	_category_row.visible = false
	add_child(_category_row)

	# THE THREE DROPDOWNS, WHICH ARE THE RAIL'S AND NOT A NEW IDEA. §4 calls them "filter chips in
	# the header for people who want to browse a facet rather than type", and they are built the way
	# PartPicker builds them — one label, one OptionButton, options DERIVED from the JSON — because
	# the alternative to carrying them over was a typed query that only a builder who already knows
	# the vocabulary can use, which is §2 lost on the mouse.
	_facet_grid = GridContainer.new()
	_facet_grid.columns = 2
	add_child(_facet_grid)
	for entry in filter_keys:
		var key: String = entry["key"]
		var label := Label.new()
		label.text = entry["label"]
		label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		_facet_grid.add_child(label)
		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Clipped and width-capped for PartPicker's reason: one long derived value like
		# "injection-moulded nylon (PA12)" would otherwise set the whole overlay's width.
		selector.clip_text = true
		selector.theme_type_variation = &"CompactButton"
		selector.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		selector.custom_minimum_size = Vector2(150, 0)
		for value in _options[key]:
			selector.add_item(value)
		selector.select(0)
		selector.item_selected.connect(func(index: int) -> void: _on_facet_chosen(key, index))
		_facet_grid.add_child(selector)
		_facet_selectors[key] = selector

	_query_edit = LineEdit.new()
	# Placeholder, never a gate: the list below it is already full. The words say the query is an
	# accelerator so that nobody reads the empty field as a thing they must satisfy first.
	_query_edit.placeholder_text = "Type to narrow — or just browse"
	_query_edit.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	_query_edit.text_changed.connect(set_query)
	add_child(_query_edit)

	_list = RowList.new()
	# THE LIST'S HEIGHT IS A REQUEST NOW, NOT A CONSTANT. It used to be a hand-measured 272 that
	# held for exactly one window and one facet count: QC5's number was derived against Propulsion's
	# three dropdowns at 1280x720, and Power's shelf has FOUR, which put the authoring row and the
	# bottom of the list under the dock on a window a third taller. `fit_to_height` squeezes this
	# number down to whatever the window can actually spare — see that function.
	_list.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	# Row pitch. The theme's SPACE_1 between rows is right for a panel of readouts and loose for a
	# list of 18 near-identical names, where tighter rows mean more of the shelf visible at once.
	_list.add_theme_constant_override("v_separation", 2)
	_list.item_selected.connect(highlight_index)
	# A SCROLLBAR YOU CAN SEE, and this line is a workaround with a named cause.
	#
	# `LothalTheme` styles a `VScrollBar` as a translucent grabber over an EMPTY track — a
	# `StyleBoxEmpty` and a `StyleBoxFlat`, neither of which carries a content margin. A
	# `ScrollBar`'s minimum size is its styleboxes' minimum size, so every scrollbar in this app
	# reports a width of ZERO: it is live, it tracks, the wheel and the arrow keys move it, and it
	# paints nothing at all. The motor shelf has 18 entries against 13 rows of room, and the
	# screenshot that prompted this showed a list that simply stopped at row 13 with no indication
	# that it had.
	#
	# Fixed here and not in the theme because widening every scrollbar in the app changes the
	# minimum width of every ScrollContainer in it, which is a measurement this slice has not made.
	# The theme is where it belongs and that is recorded rather than done quietly.
	_list.get_v_scroll_bar().custom_minimum_size.x = SCROLLBAR_WIDTH
	# AND A GUTTER SO THE BAR IS NOT STANDING ON THE WORDS. Widening the bar (above) gave it
	# pixels; it did not move the rows out from under it, and the screenshot showed `GEPRC SPEEDX2
	# 2107.5 1960KV  30 g` running beneath the grabber. `ItemList` lays its rows out inside its
	# `panel` stylebox's content margins, and the theme's is a `StyleBoxEmpty` with none — so the
	# gutter is a stylebox on this list and not a property, because the property does not exist.
	var list_box := StyleBoxEmpty.new()
	list_box.content_margin_left = LothalTheme.SPACE_1
	list_box.content_margin_top = LothalTheme.SPACE_1
	list_box.content_margin_bottom = LothalTheme.SPACE_1
	list_box.content_margin_right = ROW_GUTTER
	_list.add_theme_stylebox_override("panel", list_box)
	add_child(_list)

	_empty_hint = Label.new()
	# Wraps against the list's width rather than its own text, or the overlay widens the moment a
	# query goes empty and the dimmed canvas behind it jumps.
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_empty_hint.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	_empty_hint.theme_type_variation = &"WarnLabel"
	# Exception: Warning label explicit amber color override
	_empty_hint.add_theme_color_override("font_color", LothalTheme.WARNING)
	_empty_hint.visible = false
	add_child(_empty_hint)

	# The authoring row. Empty and hidden until set_actions() names it, for _category_row's reason:
	# the shell is what knows this catalog can be written to, and a test that only browses must not
	# be handed a New button that leads nowhere.
	_actions_row = HBoxContainer.new()
	_actions_row.visible = false
	add_child(_actions_row)

	_refresh()


# ---------------------------------------------------------------------------
# The build seam
# ---------------------------------------------------------------------------

## Injects the thing that actually fits parts. The contract is three calls —
## `preview_part(part)`, `commit_part(part)`, `restore_part(part)` — and this file requires nothing
## else of the object, which is what lets the suite pass a recorder and the shell pass an adapter
## over its own Build without either one becoming a dependency of the finder.
##
## Duck-typed against `has_method` rather than declared as a class, because the alternative is this
## Control holding a typed reference to a build object, and the rail's mistake was exactly that
## kind of reach: a list widget that knows how to assemble an aircraft cannot be tested without
## assembling one.
func set_fitter(fitter: Object) -> void:
	_fitter = fitter


## Opens the finder over a build that currently has `fitted_part_id` in this category. The id may
## be empty (nothing fitted yet), in which case cancel() restores nothing and says so by emitting
## no part.
##
## This is the call that takes the snapshot. It is separate from _init because the finder is
## summoned repeatedly against different builds, and a snapshot taken at construction would be the
## fit from whenever the overlay happened to be built rather than from when it was opened.
func open_on(fitted_part_id: String) -> void:
	_original_part = {}
	for part in catalog.list_category(category):
		if str(part.get("part_id", "")) == fitted_part_id:
			_original_part = part
	_opened = true
	set_query("")
	clear_filters()
	# Highlight the fitted part if it is in the list, so the finder opens ON the build rather than
	# at whatever is first in the file — but WITHOUT previewing, because previewing here would
	# re-fit the part that is already fitted and put a spurious entry in the seam's log.
	_highlight = 0
	for i in _visible_parts.size():
		if _visible_parts[i]["part_id"] == fitted_part_id:
			_highlight = i
	_select_row(_highlight)


func original_part() -> Dictionary:
	return _original_part


# ---------------------------------------------------------------------------
# Browsing
# ---------------------------------------------------------------------------

func query() -> String:
	return _query


func set_query(text: String) -> void:
	_query = text
	if _query_edit.text != text:
		_query_edit.text = text
	_refresh()


func filter_options(key: String) -> Array:
	return _options.get(key, [])


func filter_value(key: String) -> String:
	return str(_filters.get(key, ALL))


func set_filter(key: String, value: String) -> void:
	if not _options.has(key):
		push_error("no such filter: %s" % key)
		return
	if not (_options[key] as Array).has(value):
		push_error("no such %s filter value: %s" % [key, value])
		return
	_filters[key] = value
	# The chip follows, or the header says "All" over a narrowed list — the same disagreement
	# PartPicker.set_filter avoids by driving the OptionButton rather than a parallel dictionary.
	if _facet_selectors.has(key):
		(_facet_selectors[key] as OptionButton).select((_options[key] as Array).find(value))
	_refresh()


func clear_filters() -> void:
	for key in _filters:
		_filters[key] = ALL
		if _facet_selectors.has(key):
			(_facet_selectors[key] as OptionButton).select(0)
	_refresh()


## The facets ON SCREEN, by label, in the order they are drawn.
##
## READ OFF THE GRID AND NOT OFF `filter_keys`, and that is the difference between this and a
## helper that always agrees with itself. The by-name capability check compares this against the
## rail's own `filter_keys` labels — if it read the same array the chips are built from, deleting
## the chip-building loop entirely would leave it returning all three names over an empty header.
func facet_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _facet_grid.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func _on_facet_chosen(key: String, index: int) -> void:
	_filters[key] = str((_options[key] as Array)[index])
	_refresh()


# ---------------------------------------------------------------------------
# The header segments — a system's other shelves
# ---------------------------------------------------------------------------

## Draws one segment per shelf the focused system owns, with `current` pressed.
##
## THIS IS WHAT STOPS QC5 LOSING HALF THE CATALOG. Propulsion owns Motor and Prop, Power owns Pack
## and ESC, Control owns FC and Link; the rail column showed all of them as tabs, and a finder that
## only ever opens on `rails[0]` would have made propellers, ESCs and receivers unreachable the
## moment the rail came down — silently, because every existing check opens on the first one.
##
## `current` is pressed rather than hidden, so the row reads as "you are here, and there is another
## one" rather than as a button that appears and disappears.
func set_categories(titles: Array, current: int) -> void:
	for child in _category_row.get_children():
		_category_row.remove_child(child)
		child.queue_free()
	_category_row.visible = titles.size() > 1
	if titles.size() <= 1:
		return
	for i in titles.size():
		# `slot` and not `position`: `position` is a property of Control, and a local of that name
		# is SHADOWED_VARIABLE, which this project treats as an error.
		var slot := int((titles[i] as Dictionary)["position"])
		var button := Button.new()
		button.text = str((titles[i] as Dictionary)["title"])
		button.theme_type_variation = &"CompactButton"
		button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		button.toggle_mode = true
		button.button_pressed = slot == current
		button.pressed.connect(func() -> void: category_chosen.emit(slot))
		_category_row.add_child(button)


## The segments on screen, by name. For the by-name capability check, and for the same reason
## `facet_labels()` exists: "Prop is still reachable" is a claim about a word being on the screen.
func category_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _category_row.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out


# ---------------------------------------------------------------------------
# The authoring row — what used to sit under the rail's list
# ---------------------------------------------------------------------------

## Gives the finder the rail's two authoring buttons. `p_new_label` is the rail's own wording —
## "New custom motor…" — passed in rather than composed here, so the words a builder learned on the
## rail are the words they see in the finder and there is still one spelling of them.
##
## Delete is DISABLED rather than hidden on a catalog part, exactly as `MotorPicker` disables it,
## so the row does not reflow as the highlight moves. Whether it is enabled is decided from
## `PartsCatalog.is_custom` — the same single rule the rail reads — and not from the rail's button,
## because the rail's button only follows the highlight once something has been previewed.
func set_actions(p_new_label: String) -> void:
	if _new_button == null:
		_new_button = Button.new()
		_new_button.theme_type_variation = &"CompactButton"
		_new_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		_new_button.pressed.connect(func() -> void: new_part_requested.emit())
		_actions_row.add_child(_new_button)
		_delete_button = Button.new()
		_delete_button.theme_type_variation = &"CompactButton"
		_delete_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		_delete_button.text = "Delete"
		_delete_button.pressed.connect(func() -> void: delete_part_requested.emit())
		_actions_row.add_child(_delete_button)
	_new_button.text = p_new_label
	_actions_row.visible = true
	_refresh_delete_button()


## The authoring actions on screen, by name — "New custom motor…" and "Delete". The by-name check
## deletes one of the two and watches this go red, which is the whole point of the list existing:
## the create/delete path is the capability most likely to vanish in a layout change and be missed,
## because nothing else in the app mentions it.
func action_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _actions_row.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out


func delete_enabled() -> bool:
	return _delete_button != null and not _delete_button.disabled


func _refresh_delete_button() -> void:
	if _delete_button == null:
		return
	_delete_button.disabled = not PartsCatalog.is_custom(
		str(highlighted_part().get("part_id", "")))


func visible_parts() -> Array:
	return _visible_parts


func row_count() -> int:
	return _list.item_count


## The text of one row, which is what a test asserts the mass against. The mass column is NOT
## decoration: §4 names it as half of why a builder scans this list at all, and the rail showed it
## (`2207 1960KV   32 g`). A finder that drops it has made every row the same size as every other.
func row_text(index: int) -> String:
	if index < 0 or index >= _list.item_count:
		return ""
	return _list.get_item_text(index)


func empty_state_visible() -> bool:
	return _empty_hint.visible


## The refusal wording, CALLED THROUGH to PartPicker rather than spelled again here. It was a
## character-identical copy for as long as the rail's version was an instance method on a Control
## this file must not construct; it is static now, so the copy is gone and the two rails cannot
## word their refusal differently.
func no_match_text() -> String:
	return PartPicker.no_match_text(noun)


## The width the list's scroll affordance actually draws at. Zero means the bar is live and
## invisible, which is what the theme's margin-free styleboxes produce and what made a shelf of 18
## motors look like a shelf of 13. A number rather than a bool because "it is there" and "it is a
## pixel wide" are different answers and only one of them is a scrollbar.
func scrollbar_width() -> float:
	return _list.get_v_scroll_bar().get_combined_minimum_size().x


## The clear space reserved to the RIGHT of a row, inside the list, in px. The scroll affordance
## stands in it. Zero means the bar is drawn on top of the words, which is what the screenshot of
## the motor shelf showed and is a different defect from the bar being invisible — the check above
## stayed green through it.
func row_gutter() -> float:
	return _list.get_theme_stylebox("panel").content_margin_right


## The right-hand edge a row's text may reach, in px from the list's left edge. Derived from the
## same three numbers the truncation test uses, so "is this row cut off" and "where does a row end"
## cannot disagree.
func row_text_width() -> float:
	var box := _list.get_theme_stylebox("panel")
	var selected := _list.get_theme_stylebox("selected")
	return LIST_WIDTH - box.content_margin_left - box.content_margin_right \
		- selected.get_minimum_size().x


## The tooltip a row would show, or "" when it shows none.
##
## A STRING AND NOT A BOOL, because the two failure modes are different: a row with the tooltip
## still enabled returns its own text (the defect), and a truncated row must return something. A
## bool would collapse them.
func row_tooltip(index: int) -> String:
	if index < 0 or index >= _list.item_count:
		return ""
	if not _list.is_item_tooltip_enabled(index):
		return ""
	var own := _list.get_item_tooltip(index)
	# ItemList falls back to the item's own text when no tooltip string was set, and that fallback
	# IS the defect — so report what the builder would actually see, not the empty field.
	return own if own != "" else _list.get_item_text(index)


## Whether a row's text runs past the column, measured against the font the list actually draws in.
##
## Measured and not guessed: the answer changes with the font size (the density pass moved it), with
## the gutter (the scrollbar reserves one) and with the selected stylebox's own padding, and a
## hand-picked character count would have been wrong the moment any of the three moved.
func _row_is_truncated(text: String) -> bool:
	var font := _list.get_theme_font("font")
	if font == null:
		return false
	var font_size := _list.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > row_text_width()


## The × in the corner, by name, for the by-name capability check.
func close_label() -> String:
	return _close_button.text if _close_button != null else ""


## Presses the close control. The BUTTON'S OWN signal, emitted through it rather than re-emitting
## `close_requested` here: a check that called the signal directly would pass against a finder whose
## button was never wired to anything, which is exactly the defect "there is no way to dismiss it"
## describes.
func press_close() -> void:
	if _close_button != null:
		_close_button.pressed.emit()


## The height of everything in the column EXCEPT the list, separations included.
##
## Walked over the visible children rather than summed from constants, because two of them —
## the category row and the authoring row — are hidden on some shelves and present on others, and
## a constant would have been right for Propulsion and wrong for Power. That difference is the
## defect this function exists for.
func _chrome_height() -> float:
	var total := 0.0
	var shown := 0
	for child in get_children():
		if child is Control and (child as Control).visible:
			shown += 1
			if child != _list:
				total += (child as Control).get_combined_minimum_size().y
	return total + float(get_theme_constant("separation")) * float(maxi(shown - 1, 0))


## Squeezes the list so the whole column fits in `available` px, and returns the height the list
## ended up asking for.
##
## THE OVERLAY MUST SHRINK RATHER THAN OVERFLOW, and it did neither before this: the column's
## height was the sum of a set of constants, a `PanelContainer` obliges its child's minimum, and a
## `Control` does not clip — so on Power's four-facet shelf the list's last rows, the scrollbar's
## bottom end and both authoring buttons drew straight through the bottom of the window and under
## the dock. Nothing was clipped in the sense of being trimmed; it was simply painted off the end.
##
## Clamped at `LIST_HEIGHT_MIN` deliberately: below about five rows the finder has stopped being a
## list, and a window too short for that is a window the overlay cannot honestly fit — better to
## keep a usable list and let the check say so than to squeeze to nothing and call it fitted.
func fit_to_height(available: float) -> float:
	var height := clampf(available - _chrome_height(), LIST_HEIGHT_MIN, LIST_HEIGHT)
	_list.custom_minimum_size.y = height
	return height


## The height the list is currently asking for. For the check that the squeeze happened at all.
func list_height() -> float:
	return _list.custom_minimum_size.y


## Whether the highlighted row is inside the part of the list a builder can SEE.
##
## Arrowing past the bottom of the visible rows selects a part and previews it on the model while
## leaving the viewport where it was, so the builder watches the drone change with no row lit
## anywhere. `ItemList.select()` does not scroll; `ensure_current_is_visible()` does, and this is
## the question that tells the two apart.
func highlighted_row_is_in_view() -> bool:
	if _highlight < 0 or _highlight >= _list.item_count:
		return false
	var row := _list.get_item_rect(_highlight)
	var top := _list.get_v_scroll_bar().value
	return row.position.y >= top and row.end.y <= top + _list.size.y


func highlighted_index() -> int:
	return _highlight


func highlighted_part() -> Dictionary:
	if _highlight < 0 or _highlight >= _visible_parts.size():
		return {}
	return _visible_parts[_highlight]


## Moves the highlight and PREVIEWS what it lands on. The preview is the feature (§2, second
## defence): browsing is how a beginner learns the catalog exists, and it teaches nothing unless
## the consequence is visible on the model while they browse.
func highlight_index(index: int) -> void:
	if index < 0 or index >= _visible_parts.size():
		return
	_highlight = index
	_select_row(index)
	var part: Dictionary = _visible_parts[index]
	part_previewed.emit(part)
	if _fitter != null and _fitter.has_method("preview_part"):
		_fitter.call("preview_part", part)


## Up/down. Clamped rather than wrapped: wrapping from the last row to the first previews a part
## eleven rows away from the one being looked at, which reads as the model glitching.
func move_highlight(delta: int) -> void:
	if _visible_parts.is_empty():
		return
	highlight_index(clampi(_highlight + delta, 0, _visible_parts.size() - 1))


# ---------------------------------------------------------------------------
# Accept and cancel
# ---------------------------------------------------------------------------

## Enter. Commits whatever is highlighted and returns it; the returned dictionary is empty when
## there was nothing to commit (an empty result set), which is also why accept() cannot be a void
## that the caller assumes succeeded.
func accept() -> Dictionary:
	var part := highlighted_part()
	if part.is_empty():
		return {}
	_opened = false
	part_committed.emit(part)
	if _fitter != null and _fitter.has_method("commit_part"):
		_fitter.call("commit_part", part)
	return part


## Escape. Restores THE PART THAT WAS FITTED WHEN THE FINDER OPENED, after any number of previews.
##
## The defect this line prevents is the obvious implementation: restoring the last previewed part,
## which is the value nearest to hand and is exactly what the builder just declined. It would also
## be invisible in the one-preview case — preview A then cancel looks identical either way — so the
## check that covers this arrows through several parts first.
func cancel() -> Dictionary:
	_opened = false
	if _original_part.is_empty():
		return {}
	var part := _original_part
	fit_restored.emit(part)
	if _fitter != null and _fitter.has_method("restore_part"):
		_fitter.call("restore_part", part)
	return part


func is_open() -> bool:
	return _opened


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Selects a row AND SCROLLS IT INTO VIEW.
##
## `ensure_current_is_visible()` is not a nicety here, it is the arrow keys working. An `ItemList`
## scrolls on a click because the click was on a row already on screen; `select()` from code moves
## the selection and leaves the viewport where it was. The motor shelf has eighteen entries and
## about sixteen fit, so arrowing down past the sixteenth previewed motors the builder could not
## see — a highlight off the bottom of a list with the model changing behind it.
func _select_row(index: int) -> void:
	if index >= 0 and index < _list.item_count and _list.is_item_selectable(index):
		_list.select(index)
		_list.ensure_current_is_visible()
	_refresh_delete_button()


func _refresh() -> void:
	# Read BEFORE the list is replaced. The id is what survives a keystroke; the index does not,
	# because the row that was at 3 is a different motor once the list has narrowed. An earlier
	# draft of this function read the id off `_visible_parts` after reassigning it, which is a
	# helper that always agrees with itself and therefore preserved nothing.
	var previous_id := _highlighted_id()

	_visible_parts = _matching_parts()

	_list.clear()
	if _visible_parts.is_empty():
		# Not an empty list: a row that explains itself, unselectable so it cannot be mistaken for
		# a part with a strange name.
		_list.add_item(no_match_text())
		_list.set_item_selectable(0, false)
		_list.set_item_disabled(0, true)
		_empty_hint.text = "Nothing in the catalog is a %s. Clear the search to widen it." % _asked_for_description()
		_empty_hint.visible = true
		_highlight = -1
		return

	_empty_hint.visible = false
	for part in _visible_parts:
		# display_name and _format_mass come from PartPicker unchanged: the mark on a custom part
		# and the two mass formats (a 0.5 g propeller and a 265 g frame cannot share one) are rules
		# that must read identically on every surface, and a second copy would decay on its own.
		var text := "%s   %s g" % [PartPicker.display_name(part), PartPicker._format_mass(part)]
		var index_added := _list.add_item(text)
		# A TOOLTIP THAT REPEATS THE ROW IS NOISE, AND IT COVERS THE ROW IT REPEATS.
		#
		# `ItemList` falls back to an item's own text when no tooltip is set, so every row in this
		# list carried a floating copy of itself — `2.5" Micro Whoop   28 g` hovering over the row
		# reading `2.5" Micro Whoop   28 g`, hiding the thing the cursor was pointing at. A tooltip
		# earns its place only when it says something the row does not, which here means exactly
		# one case: the label is too long for the column and the end of it is cut off.
		_list.set_item_tooltip_enabled(index_added, _row_is_truncated(text))

	# Keep the highlight on the same PART across a keystroke where possible. Narrowing the list by
	# typing should not silently move the preview to a different motor.
	var index := 0
	for i in _visible_parts.size():
		if str(_visible_parts[i].get("part_id", "")) == previous_id:
			index = i
			break
	_highlight = index
	_select_row(index)


## The highlighted part's id, or "" when nothing is highlighted. Separate from `_highlight` because
## the index means nothing once the visible list has changed underneath it.
func _highlighted_id() -> String:
	if _highlight >= 0 and _highlight < _visible_parts.size():
		return str(_visible_parts[_highlight].get("part_id", ""))
	return ""


## The distinct values of one catalog field, in first-appearance order rather than sorted, exactly
## as PartPicker derives them: each catalog file is authored smallest-part-first, so first
## appearance gives the size facets an ascending order for free where an alphabetical sort would
## put 10" before 3". Nothing in this file lists a value; the JSON does.
func _derive_options(entry: Dictionary) -> Array:
	var values: Array = [ALL]
	for part in catalog.list_category(category):
		var value := PartPicker.value_of(part, entry)
		if value != "" and not values.has(value):
			values.append(value)
	return values


func _matching_parts() -> Array:
	var out: Array = []
	for part in catalog.list_category(category):
		if not _passes_filters(part):
			continue
		if not _matches_query(part):
			continue
		out.append(part)
	return out


func _passes_filters(part: Dictionary) -> bool:
	for entry in filter_keys:
		var wanted := filter_value(entry["key"])
		if wanted != ALL and PartPicker.value_of(part, entry) != wanted:
			return false
	return true


## The typed query, matched against the name and against every DERIVED spec value — which is what
## makes `2207`, `1960`, `freestyle` and `22xx` all narrow the list without any of those strings
## appearing in this file. Split on whitespace and ANDed, so "2207 freestyle" means both.
##
## An empty query matches everything. That is not a convenience: it is §2, and it is the line the
## suite mutates to prove its browse-mode check can fail.
func _matches_query(part: Dictionary) -> bool:
	for token in _query.strip_edges().to_lower().split(" ", false):
		if not _haystack(part).contains(token):
			return false
	return true


func _haystack(part: Dictionary) -> String:
	var fields: Array = [PartPicker.display_name(part)]
	for entry in filter_keys:
		fields.append(PartPicker.value_of(part, entry))
	return " ".join(fields).to_lower()


## What was asked for, as a readable phrase, so the refusal names the request rather than only
## reporting that it failed. Includes the typed query for the same reason the rail included its
## dropdowns: the builder who typed "2207 tinywhoop" needs to see both halves to know which one to
## drop.
func _asked_for_description() -> String:
	var said: Array = []
	for entry in filter_keys:
		var value := filter_value(entry["key"])
		if value != ALL:
			said.append("%s %s" % [String(entry["label"]).to_lower(), value])
	if _query.strip_edges() != "":
		said.append("\"%s\"" % _query.strip_edges())
	if said.is_empty():
		return "%s like that" % noun
	return " / ".join(said) + " " + noun


static func _title_case(text: String) -> String:
	return text.replace("_", " ").capitalize()
