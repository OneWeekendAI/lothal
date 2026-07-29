class_name BuildPanel
extends PanelContainer
## The part picker and the live stat readout — Day 5's deliverable, and the feedback loop
## that parts.md calls the product: change a part, watch all five numbers move, then fly it.
##
## Built entirely in code (architecture.md: "Hand-placed UI does not survive version
## control"). Nothing here computes physics; it reads Build and renders it. Adding this
## consumer required no change to src/sim — which is the architecture's own stated test.

signal build_changed(build: Build)

const CATEGORY_ORDER := [
	{"category": "frame", "label": "Frame"},
	{"category": "motor", "label": "Motor"},
	{"category": "propeller", "label": "Propeller"},
	{"category": "battery", "label": "Battery"},
]

const STAT_ROWS := [
	{"key": "weight", "label": "All-up weight"},
	{"key": "twr", "label": "Thrust : weight"},
	{"key": "hover", "label": "Hover throttle"},
	{"key": "time", "label": "Flight time"},
	{"key": "speed", "label": "Top speed"},
]

var catalog: PartsCatalog
var build: Build

var _selectors: Dictionary = {}   # category -> OptionButton
var _stat_values: Dictionary = {} # key -> Label
var _warning_label: Label

func _init(p_catalog: PartsCatalog, initial_ids: Dictionary) -> void:
	catalog = p_catalog

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16
	offset_top = 16
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "BUILD"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	for entry in CATEGORY_ORDER:
		var category: String = entry["category"]
		var name_label := Label.new()
		name_label.text = entry["label"]
		grid.add_child(name_label)

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var parts := catalog.list_category(category)
		for i in parts.size():
			selector.add_item(parts[i]["name"], i)
			if parts[i]["part_id"] == initial_ids.get(category, ""):
				selector.select(i)
		selector.item_selected.connect(_on_selection_changed.bind(category))
		grid.add_child(selector)
		_selectors[category] = selector

	root.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 4)
	root.add_child(stats)

	for row in STAT_ROWS:
		var name_label := Label.new()
		name_label.text = row["label"]
		stats.add_child(name_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(value_label)
		_stat_values[row["key"]] = value_label

	_warning_label = Label.new()
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.custom_minimum_size = Vector2(300, 0)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	root.add_child(_warning_label)

	var hint := Label.new()
	hint.text = "Tab: hide panel   Space/A: angle <-> acro"
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	root.add_child(hint)

func _ready() -> void:
	_rebuild()

func _on_selection_changed(_index: int, _category: String) -> void:
	_rebuild()

func selected_id(category: String) -> String:
	var selector: OptionButton = _selectors[category]
	return catalog.list_category(category)[selector.selected]["part_id"]

func _rebuild() -> void:
	build = Build.from_ids(
		catalog,
		selected_id("frame"), selected_id("motor"),
		selected_id("propeller"), selected_id("battery")
	)
	_refresh_stats()
	build_changed.emit(build)

## Units are converted to grams, percent and km/h here and ONLY here — physics.md §1's
## coordinate contract keeps everything SI right up to the UI boundary.
func _refresh_stats() -> void:
	_stat_values["weight"].text = "%.0f g" % build.all_up_weight_g()
	_stat_values["twr"].text = "%.1f : 1" % build.thrust_to_weight()

	if build.can_hover():
		_stat_values["hover"].text = "%.1f %%" % (build.hover_throttle() * 100.0)
		_stat_values["time"].text = "%.1f min" % build.flight_time_min()
	else:
		_stat_values["hover"].text = "won't hover"
		_stat_values["time"].text = "—"

	_stat_values["speed"].text = "%.0f km/h" % build.top_speed_kmh()

	var warnings := build.warnings()
	_warning_label.text = "\n".join(warnings) if not warnings.is_empty() else ""
	_warning_label.visible = not warnings.is_empty()
