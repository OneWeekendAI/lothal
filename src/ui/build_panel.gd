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
	{"category": "flight_controller", "label": "Flight controller"},
	{"category": "camera", "label": "Camera"},
	{"category": "vtx", "label": "Video TX"},
	{"category": "antenna", "label": "Antenna"},
	{"category": "receiver", "label": "Receiver"},
	{"category": "gps", "label": "GPS"},
	{"category": "buzzer", "label": "Buzzer"},
]
## ^ THIS LIST AND Build.OPTIONAL_COMPONENTS ARE TWO LISTS, and C2 collected on that: the moment
## GPS and buzzer joined the mass model, `component_ids()` below started asking `selected_id()` for
## a category this panel had never built a selector for. A hand-written table beside a derived one
## is the P10f finding, and the check that caught it — "Sim's BUILD panel has a dropdown for every
## component" — was already in the suite, written for exactly this. The two rows are added rather
## than the table being derived because six of the ten categories here are NOT optional components
## and the order and the labels are this panel's own; C4 is where the coverage rule gets teeth.

## The four categories whose lists carry a "Not fitted" row, and the only ones that may resolve to
## "". Derived from Build rather than listed, so this panel cannot know about a different set of
## optional components than the mass model does.
##
## Their dropdowns are the reason _ids below exists. A component list is the catalog plus one row
## the catalog does not have, so the old `list_category(category)[selector.selected]` is off by one
## for the whole of these four — and off by one over a shelf of similar 2 g boards fits the wrong
## part without ever looking wrong on screen.
const OPTIONAL := Build.OPTIONAL_COMPONENTS
const NOT_FITTED := "Not fitted"

const STAT_ROWS := [
	{"key": "weight", "label": "All-up weight"},
	{"key": "twr", "label": "Thrust : weight"},
	{"key": "hover", "label": "Hover throttle"},
	{"key": "time", "label": "Flight time"},
	{"key": "speed", "label": "Top speed"},
]

var catalog: PartsCatalog
var build: Build
## The designer's edit to the fitted frame, handed across the Lab→Sim door with the selection
## (`LabScreen.frame_edit`). Applied on every rebuild; `FittedFrame.apply` ignores it once the
## pilot fits a different frame here, so it can never land on a frame it was not drawn from.
var frame_edit: Dictionary = {}

## How much of the top of the screen is already spoken for by something drawn over Sim.
## Zero when main.tscn is run on its own; the tab bar's height when Sim is reached through
## AppShell, which draws that bar on a CanvasLayer ABOVE the flight scene — without this the
## bar sits across the panel's title and "BUILD" is simply not there.
var top_inset := 0.0
## And how much of the bottom is spoken for — the HUD's flight readouts sit in the same corner
## this panel grows down into. Set by whoever composes the two.
var bottom_reserve := 0.0

var _selectors: Dictionary = {}   # category -> OptionButton
## category -> Array[String] of part ids, parallel to that selector's items. The selector's index
## is an index into THIS and never into the catalog; see OPTIONAL above for why that matters.
var _ids: Dictionary = {}
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
	"flight_controller": ReferenceBuild.FC_ID,
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
		# Clipped, because "RHCP SMA long-range (5.8 GHz)" would otherwise set this floating
		# panel's width from its longest catalog string and cover a third of the flight view.
		selector.clip_text = true

		var ids: Array = []
		if OPTIONAL.has(category):
			selector.add_item(NOT_FITTED)
			ids.append("")
		for part in catalog.list_category(category):
			selector.add_item(str(part["name"]))
			ids.append(str(part["part_id"]))
		_ids[category] = ids

		# An id the catalog does not have falls back rather than leaving the dropdown on -1, which
		# is a selector with nothing chosen and a selected_id() that cannot answer. "" is a real
		# answer for the four optional categories and resolves to the "Not fitted" row above.
		var wanted := str(initial_ids.get(category, _fallback_id(category)))
		var index: int = ids.find(wanted)
		if index < 0:
			index = maxi(ids.find(_fallback_id(category)), 0)
		selector.select(index)
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
	return str(_ids[category][selector.selected])


## What a category opens on when the hand-over does not name it. The optional components fall back
## to Build's own defaults, so a caller that predates these four categories — scenes/main.gd loaded
## directly, or a test naming only the pack — still builds the aircraft it used to.
static func _fallback_id(category: String) -> String:
	if CATEGORY_FALLBACKS.has(category):
		return str(CATEGORY_FALLBACKS[category])
	return str(Build.DEFAULT_COMPONENT_IDS.get(category, ""))


## The payload, in the shape Build.from_ids takes. Every category present, "" for an empty bay —
## an ABSENT key would mean "fit the default" to Build, which is the one thing a bay the pilot
## emptied must not turn back into.
func component_ids() -> Dictionary:
	var out := {}
	for category in OPTIONAL:
		out[category] = selected_id(category)
	return out

func _rebuild() -> void:
	build = Build.from_ids(
		catalog,
		selected_id("frame"), selected_id("motor"),
		selected_id("propeller"), selected_id("battery"), selected_id("esc"),
		selected_id("flight_controller"), component_ids()
	)
	if not frame_edit.is_empty():
		build.set_frame_edit(frame_edit)
	_refresh_stats()
	build_changed.emit(build)

## Units are converted to grams, percent and km/h here and ONLY here — physics.md §1's
## coordinate contract keeps everything SI right up to the UI boundary.
func _refresh_stats() -> void:
	_stat_values["weight"].text = "%.0f g" % build.all_up_weight_g()
	_stat_values["twr"].text = "%.1f : 1" % build.thrust_to_weight()

	if build.can_hover():
		_stat_values["hover"].text = "%.1f %%" % (build.hover_throttle() * 100.0)
		# THE CONDITIONS THE FIGURE WAS COMPUTED UNDER, named beside it (F8, design §4.3/§3.3).
		# `flight_time_min()` picks up the flown Build's own wind, so since F8 the NUMBER here has
		# been right and only the LABEL was missing — which is exactly the defect F8 exists to
		# remove ("a figure quoted without the conditions it was computed under"), in one file
		# outside F8's own scope. `part_details.gd` is the sibling that already says it this way.
		#
		# No wind argument, for that file's reason: the function defaults to the Build's own
		# `field_wind_mps`, so the number and the label beside it cannot come apart.
		_stat_values["time"].text = "%.1f min (%s)" % [
			build.flight_time_min(), build.field_conditions_name]
	else:
		_stat_values["hover"].text = "won't hover"
		_stat_values["time"].text = "—"

	_stat_values["speed"].text = "%.0f km/h" % build.top_speed_kmh()

	_warnings.show_warnings(build.warnings())
