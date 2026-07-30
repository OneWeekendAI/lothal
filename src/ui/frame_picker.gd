class_name FramePicker
extends PanelContainer
## Lab's left rail: every frame in the catalog, with filters for type, size and material.
##
## Built in code, like every other Control in this project (architecture.md: "Hand-placed
## UI does not survive version control"). It computes no physics and knows no frame specs —
## it filters dictionaries and emits the one that is highlighted.
##
## Two rules this file exists to keep:
##
## The filter options are DERIVED from frames.json, never listed here. A contributor who
## adds the first titanium frame gets a titanium entry in the material filter without
## touching any GDScript, which is the same instinct that keeps the catalog in reviewable
## JSON in the first place.
##
## A filter combination that matches nothing SAYS so. An empty list with no explanation is
## indistinguishable from a broken catalog load, and Lothal's whole posture on
## incompatibility is to explain the consequence rather than present a void (parts.md:
## warn, never block).

signal frame_selected(frame: Dictionary)

## The three axes a builder actually browses a frame catalog along. Each reads from the
## part's `catalog` block — browsing metadata, deliberately kept out of `specs`, which is
## reserved for fields the physics reads (see frames.json's _schema).
const FILTER_KEYS := [
	{"key": "frame_type", "label": "Type"},
	{"key": "size_class", "label": "Size"},
	{"key": "material", "label": "Material"},
]

const ALL := "All"
const NO_MATCH_TEXT := "No frame matches these filters"

var catalog: PartsCatalog

var _filters: Dictionary = {}        # filter key -> OptionButton
var _options: Dictionary = {}        # filter key -> Array[String], ALL first
var _list: ItemList
var _empty_hint: Label
var _visible_frames: Array = []
## Kept so that changing a filter does not throw away a selection that is still valid —
## narrowing the list by material should not silently move you to a different frame.
var _selected_id: String = ""

func _init(p_catalog: PartsCatalog) -> void:
	catalog = p_catalog

	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	FrameDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = "FRAMES"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	for entry in FILTER_KEYS:
		var key: String = entry["key"]

		var label := Label.new()
		label.text = entry["label"]
		grid.add_child(label)

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Clipped and width-capped, or a long value like "injection-moulded nylon (PA12)"
		# sets the rail's width from its longest string and shoves the details panel off the
		# right-hand edge of the window.
		selector.clip_text = true
		selector.custom_minimum_size = Vector2(186, 0)
		_options[key] = _derive_options(key)
		for value in _options[key]:
			selector.add_item(value)
		selector.select(0)
		selector.item_selected.connect(_on_filter_changed)
		grid.add_child(selector)
		_filters[key] = selector

	root.add_child(HSeparator.new())

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(280, 260)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	root.add_child(_list)

	_empty_hint = Label.new()
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.custom_minimum_size = Vector2(280, 0)
	_empty_hint.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	root.add_child(_empty_hint)

	# Silent: LabScreen connects to frame_selected after constructing this, so emitting from
	# inside _init would fire into nothing. It calls emit_current() once it is wired.
	_refresh(false)


## The distinct values of one catalog field, in first-appearance order rather than sorted.
## frames.json is authored smallest-frame-first, so first-appearance gives the size filter
## an ascending order for free — where an alphabetical sort would put 10" before 3".
func _derive_options(key: String) -> Array:
	var values: Array = [ALL]
	for frame in catalog.list_category("frame"):
		var value := _value_of(frame, key)
		if value != "" and not values.has(value):
			values.append(value)
	return values


static func _value_of(frame: Dictionary, key: String) -> String:
	return str(frame.get("catalog", {}).get(key, ""))


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

func visible_frames() -> Array:
	return _visible_frames

func empty_state_visible() -> bool:
	return _empty_hint.visible

## Selects the i-th VISIBLE frame and announces it. The index is into the filtered list,
## which is what the ItemList shows and therefore what a click means.
func select_index(index: int) -> void:
	if index < 0 or index >= _visible_frames.size():
		return
	_list.select(index)
	_selected_id = _visible_frames[index]["part_id"]
	frame_selected.emit(_visible_frames[index])

func selected_frame() -> Dictionary:
	for frame in _visible_frames:
		if frame["part_id"] == _selected_id:
			return frame
	return {}

## Re-announces the current selection. Used once by LabScreen after it has connected, so
## the first paint of the geometry, the details and the stats needs no apply button either.
func emit_current() -> void:
	var frame := selected_frame()
	if not frame.is_empty():
		frame_selected.emit(frame)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _on_filter_changed(_index: int) -> void:
	_refresh()

func _on_item_selected(index: int) -> void:
	select_index(index)

func _refresh(emit := true) -> void:
	_visible_frames = _matching_frames()

	_list.clear()
	if _visible_frames.is_empty():
		# Not an empty list: a row that explains itself, unselectable so it cannot be
		# mistaken for a frame.
		_list.add_item(NO_MATCH_TEXT)
		_list.set_item_selectable(0, false)
		_list.set_item_disabled(0, true)
		_empty_hint.text = "Nothing in the catalog is a %s. Set a filter back to \"%s\" to widen the search." % [
			_active_filter_description(), ALL]
		_empty_hint.visible = true
		return

	_empty_hint.visible = false
	for frame in _visible_frames:
		_list.add_item("%s   %s g" % [frame["name"], _format_mass(frame)])

	# Keep the highlighted frame if the new filters still include it; otherwise fall back to
	# the top of the list.
	var index := 0
	for i in _visible_frames.size():
		if _visible_frames[i]["part_id"] == _selected_id:
			index = i
			break
	_list.select(index)
	_selected_id = _visible_frames[index]["part_id"]
	if emit:
		frame_selected.emit(_visible_frames[index])

func _matching_frames() -> Array:
	var out: Array = []
	for frame in catalog.list_category("frame"):
		var keep := true
		for entry in FILTER_KEYS:
			var key: String = entry["key"]
			var wanted := filter_value(key)
			if wanted != ALL and _value_of(frame, key) != wanted:
				keep = false
				break
		if keep:
			out.append(frame)
	return out

## The active filters as a readable phrase, so the empty state names what was asked for
## rather than just reporting that it failed.
func _active_filter_description() -> String:
	var parts: Array = []
	for entry in FILTER_KEYS:
		var value := filter_value(entry["key"])
		if value != ALL:
			parts.append("%s %s" % [String(entry["label"]).to_lower(), value])
	if parts.is_empty():
		return "frame like that"
	return " / ".join(parts) + " frame"

static func _format_mass(frame: Dictionary) -> String:
	return "%.0f" % float(frame["mass_g"])
