class_name PartPicker
extends PanelContainer
## One rail of the catalog: every part in a category, with filters over its `catalog` block.
##
## This started life as FramePicker and was generalised the moment motors and propellers needed
## the same rail. Generalised rather than copied for a specific reason: the two rules below are
## easy to state and easy to lose, and three copies of them would decay independently — the
## motor rail would grow a hardcoded KV list in a hurry one afternoon and nothing would notice.
##
## Built in code, like every other Control in this project (architecture.md: "Hand-placed UI
## does not survive version control"). It computes no physics and knows no specs — it filters
## dictionaries and emits the one that is highlighted.
##
## The two rules:
##
## Filter options are DERIVED from the JSON, never listed here. A contributor who adds the
## first titanium frame, or the first 31xx motor, gets an entry in the right filter without
## touching any GDScript — the same instinct that keeps the catalog in reviewable JSON.
##
## A filter combination that matches nothing SAYS so. An empty list with no explanation is
## indistinguishable from a broken catalog load, and Lothal's whole posture on incompatibility
## is to explain the consequence rather than present a void (parts.md: warn, never block).
##
## A filter entry may name the BLOCK it reads from — `{"key": ..., "label": ..., "block": "specs"}`
## — and defaults to `catalog`, which is where browsing metadata belongs and where every filter
## read from until the battery rail arrived. The pack's chemistry is the exception that needed
## this: it is physics-bearing (it selects BatteryModel's discharge curve, physics.md §5) so it
## lives in `specs`, and it is also the first question anyone asks about a pack, so it has to be
## filterable. The two alternatives were both worse — copying it into `catalog` would give one
## fact two homes that can disagree, and quietly falling back from one block to the other would
## make "which block is this read from" a thing you have to work out rather than read.
##
## An entry may also carry a `"format"` — a single-argument format string applied to the raw
## value, e.g. `"%.0fC"` for a pack's C-rating. That exists for the same reason `block` does: a
## physics-bearing number has to stay browsable without being stored twice. c_rating is capacity
## multiplied by it to get the pack's current limit, so it is a float in `specs`; a filter labelled
## "75" rather than "75C" is not the thing a builder narrows a shelf by.

signal part_selected(part: Dictionary)

const ALL := "All"
## The block a filter entry reads from when it does not say.
const DEFAULT_BLOCK := "catalog"

var catalog: PartsCatalog
## The category this rail lists, e.g. "motor".
var category: String
## What one entry is called, for the empty state's prose: "No motor matches these filters".
var noun: String
## Array of {"key": <catalog field>, "label": <UI label>}.
var filter_keys: Array

var _filters: Dictionary = {}        # filter key -> OptionButton
var _options: Dictionary = {}        # filter key -> Array[String], ALL first
var _entries: Dictionary = {}        # filter key -> the filter entry dictionary it came from
var _list: ItemList
var _empty_hint: Label
var _visible_parts: Array = []
## Kept so that changing a filter does not throw away a selection that is still valid —
## narrowing the list by material should not silently move you to a different part.
var _selected_id: String = ""

func _init(p_catalog: PartsCatalog, p_category: String, p_title: String, p_noun: String,
		p_filter_keys: Array) -> void:
	catalog = p_catalog
	category = p_category
	noun = p_noun
	filter_keys = p_filter_keys

	custom_minimum_size = Vector2(272, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	PartDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = p_title
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	for entry in filter_keys:
		var key: String = entry["key"]
		_entries[key] = entry

		var label := Label.new()
		label.text = entry["label"]
		grid.add_child(label)

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Clipped and width-capped, or a long value like "injection-moulded nylon (PA12)" sets
		# the rail's width from its longest string and shoves the details panel off the
		# right-hand edge of the window.
		selector.clip_text = true
		selector.custom_minimum_size = Vector2(158, 0)
		_options[key] = _derive_options(entry)
		for value in _options[key]:
			selector.add_item(value)
		selector.select(0)
		selector.item_selected.connect(_on_filter_changed)
		grid.add_child(selector)
		_filters[key] = selector

	root.add_child(HSeparator.new())

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(252, 240)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	root.add_child(_list)

	_empty_hint = Label.new()
	# Wraps against the list's width rather than its own text, so the rail does not widen the
	# moment a filter combination goes empty. Its real text is written in _refresh().
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.custom_minimum_size = Vector2(252, 0)
	_empty_hint.theme_type_variation = &"WarnLabel"
	# Exception: Warning label explicit amber color override
	_empty_hint.add_theme_color_override("font_color", LothalTheme.WARNING)
	_empty_hint.visible = false
	root.add_child(_empty_hint)

	# Silent: whoever constructed this connects to part_selected afterwards, so emitting from
	# inside _init would fire into nothing. They call emit_current() once wired.
	_refresh(false)


## The distinct values of one catalog field, in first-appearance order rather than sorted. Each
## catalog file is authored smallest-part-first, so first-appearance gives the size filters an
## ascending order for free — where an alphabetical sort would put 10" before 3".
func _derive_options(entry: Dictionary) -> Array:
	var values: Array = [ALL]
	for part in catalog.list_category(category):
		var value := value_of(part, entry)
		if value != "" and not values.has(value):
			values.append(value)
	return values


## One filter entry's value for one part, read from the block that entry names. Public and
## static because it is the single expression of "where does a filter read from", and the tests
## assert against the same function rather than against a second copy of the lookup.
static func value_of(part: Dictionary, entry: Dictionary) -> String:
	var block: String = entry.get("block", DEFAULT_BLOCK)
	var raw: Variant = part.get(block, {}).get(entry["key"], null)
	# Compared against null rather than against "": a filter may now read a NUMBER out of `specs`
	# (a pack's C-rating), and `some_float == ""` is a type error in GDScript rather than false.
	if raw == null or (raw is String and raw == ""):
		return ""
	var format: String = entry.get("format", "")
	return (format % raw) if format != "" else str(raw)


func no_match_text() -> String:
	return "No %s matches these filters" % noun


# ---------------------------------------------------------------------------
# Public surface (also what the tests drive)
# ---------------------------------------------------------------------------

func filter_options(key: String) -> Array:
	return _options.get(key, [])

func filter_value(key: String) -> String:
	var selector: OptionButton = _filters[key]
	return _options[key][selector.selected]

func set_filter(key: String, value: String) -> void:
	var selector: OptionButton = _filters[key]
	var index: int = _options[key].find(value)
	if index < 0:
		push_error("no such %s filter value: %s" % [key, value])
		return
	selector.select(index)
	_refresh()

func visible_parts() -> Array:
	return _visible_parts

func empty_state_visible() -> bool:
	return _empty_hint.visible

## Selects the i-th VISIBLE part and announces it. The index is into the filtered list, which
## is what the ItemList shows and therefore what a click means.
func select_index(index: int) -> void:
	if index < 0 or index >= _visible_parts.size():
		return
	_list.select(index)
	_selected_id = _visible_parts[index]["part_id"]
	part_selected.emit(_visible_parts[index])

func selected_part() -> Dictionary:
	for part in _visible_parts:
		if part["part_id"] == _selected_id:
			return part
	return {}

## Selects a part by id if the current filters show it, and reports whether it could. Used to
## open Lab on the reference build rather than on whatever happens to be first in each file.
func select_id(part_id: String) -> bool:
	for i in _visible_parts.size():
		if _visible_parts[i]["part_id"] == part_id:
			select_index(i)
			return true
	return false

## Re-announces the current selection. Used once by LabScreen after it has connected, so the
## first paint of the geometry, the details and the stats needs no apply button either.
func emit_current() -> void:
	var part := selected_part()
	if not part.is_empty():
		part_selected.emit(part)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _on_filter_changed(_index: int) -> void:
	_refresh()

func _on_item_selected(index: int) -> void:
	select_index(index)

func _refresh(emit := true) -> void:
	_visible_parts = _matching_parts()

	_list.clear()
	if _visible_parts.is_empty():
		# Not an empty list: a row that explains itself, unselectable so it cannot be mistaken
		# for a part.
		_list.add_item(no_match_text())
		_list.set_item_selectable(0, false)
		_list.set_item_disabled(0, true)
		_empty_hint.text = "Nothing in the catalog is a %s. Set a filter back to \"%s\" to widen the search." % [
			_active_filter_description(), ALL]
		_empty_hint.visible = true
		return

	_empty_hint.visible = false
	for part in _visible_parts:
		_list.add_item("%s   %s g" % [part["name"], _format_mass(part)])

	# Keep the highlighted part if the new filters still include it; otherwise fall back to the
	# top of the list.
	var index := 0
	for i in _visible_parts.size():
		if _visible_parts[i]["part_id"] == _selected_id:
			index = i
			break
	_list.select(index)
	_selected_id = _visible_parts[index]["part_id"]
	if emit:
		part_selected.emit(_visible_parts[index])

func _matching_parts() -> Array:
	var out: Array = []
	for part in catalog.list_category(category):
		var keep := true
		for entry in filter_keys:
			var key: String = entry["key"]
			var wanted := filter_value(key)
			if wanted != ALL and value_of(part, entry) != wanted:
				keep = false
				break
		if keep:
			out.append(part)
	return out

## The active filters as a readable phrase, so the empty state names what was asked for rather
## than just reporting that it failed.
func _active_filter_description() -> String:
	var parts: Array = []
	for entry in filter_keys:
		var value := filter_value(entry["key"])
		if value != ALL:
			parts.append("%s %s" % [String(entry["label"]).to_lower(), value])
	if parts.is_empty():
		return "%s like that" % noun
	return " / ".join(parts) + " " + noun

## Masses in this catalog span a 0.5 g propeller to a 265 g frame, so a single format is wrong
## at one end or the other: "%.0f" turns every small prop into "0 g" or "1 g" and loses the
## distinction the rail exists to show.
static func _format_mass(part: Dictionary) -> String:
	var grams := float(part["mass_g"])
	if grams < 10.0:
		return "%.1f" % grams
	return "%.0f" % grams
