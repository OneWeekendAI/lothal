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
	{"category": "esc", "label": "ESC"},
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

## How much of the top of the screen is already spoken for by something drawn over Sim.
## Zero when main.tscn is run on its own; the tab bar's height when Sim is reached through
## AppShell, which draws that bar on a CanvasLayer ABOVE the flight scene — without this the
## bar sits across the panel's title and "BUILD" is simply not there.
var top_inset := 0.0
## And how much of the bottom is spoken for — the HUD's flight readouts sit in the same corner
## this panel grows down into. Set by whoever composes the two.
var bottom_reserve := 0.0

var _selectors: Dictionary = {}   # category -> OptionButton
var _stat_values: Dictionary = {} # key -> Label
var _warnings: WarningList
var _scroll: ScrollContainer
## The padded box inside the scroll — its minimum size is the panel's natural height.
var _content: MarginContainer

## `initial_ids` may name only some categories. Anything it leaves out falls back to the
## reference build's part rather than to whatever happens to sit first in the catalog file — which
## for ESCs would be a 3 g whoop board, silently making every caller's aircraft 9 g lighter and
## its ESC the binding constraint. A partial hand-over is a normal thing (scenes/main.gd fills its
## own defaults, Lab hands over what its rails hold, and a test names what it cares about), so the
## fallback belongs here where every one of them passes through.
const CATEGORY_FALLBACKS := {
	"frame": ReferenceBuild.FRAME_ID,
	"motor": ReferenceBuild.MOTOR_ID,
	"propeller": ReferenceBuild.PROPELLER_ID,
	"battery": ReferenceBuild.BATTERY_ID,
	"esc": ReferenceBuild.ESC_ID,
}


func _init(p_catalog: PartsCatalog, initial_ids: Dictionary) -> void:
	catalog = p_catalog

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = LothalTheme.SPACE_4
	offset_top = LothalTheme.SPACE_4
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content = PartDetails._padded(_scroll)
	_content.add_child(root)

	var title := Label.new()
	title.text = "BUILD"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
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
			if parts[i]["part_id"] == initial_ids.get(category, CATEGORY_FALLBACKS.get(category, "")):
				selector.select(i)
		selector.item_selected.connect(_on_selection_changed.bind(category))
		grid.add_child(selector)
		_selectors[category] = selector

	root.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	root.add_child(stats)

	for row in STAT_ROWS:
		var name_label := Label.new()
		name_label.text = row["label"]
		stats.add_child(name_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.theme_type_variation = &"ReadoutLabel"
		stats.add_child(value_label)
		_stat_values[row["key"]] = value_label

	_warnings = WarningList.new(300)
	root.add_child(_warnings)

	var hint := Label.new()
	hint.text = "Tab: hide panel   Space/A: angle <-> acro"
	hint.theme_type_variation = &"MutedLabel"
	root.add_child(hint)

func _ready() -> void:
	_rebuild()
	offset_top = LothalTheme.SPACE_4 + top_inset
	get_viewport().size_changed.connect(_fit_to_viewport)
	_content.minimum_size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


## This panel floats at the top-left of the Sim rather than sitting in a container, so it takes
## its own minimum size — and a ScrollContainer's minimum HEIGHT is zero, which collapsed the
## whole panel to an invisible strip the moment scrolling was added. The height is therefore
## stated here: the content's own height while it fits on screen, the window's while it does
## not, which is also the only state in which the scrollbar has anything to do.
func _fit_to_viewport() -> void:
	var available := get_viewport_rect().size.y - offset_top - bottom_reserve \
		- LothalTheme.SPACE_4 - 2.0 * LothalTheme.SPACE_2
	_scroll.custom_minimum_size.y = minf(
		_content.get_combined_minimum_size().y, maxf(available, 0.0))

func _on_selection_changed(_index: int, _category: String) -> void:
	_rebuild()

func selected_id(category: String) -> String:
	var selector: OptionButton = _selectors[category]
	return catalog.list_category(category)[selector.selected]["part_id"]

func _rebuild() -> void:
	build = Build.from_ids(
		catalog,
		selected_id("frame"), selected_id("motor"),
		selected_id("propeller"), selected_id("battery"), selected_id("esc")
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

	_warnings.show_warnings(build.warnings())
