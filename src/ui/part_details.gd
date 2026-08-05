class_name PartDetails
extends PanelContainer
## Everything known about the highlighted part, plus what choosing it does to the build.
##
## Every value here is read out of the part dictionary at render time. Nothing about any
## specific part is written into this file or its subclasses — if a number on screen cannot be
## traced back to the JSON, that is a bug, and tests/test_lab.gd asserts exactly that
## traceability.
##
## Each panel deliberately mixes two kinds of row. The SPEC rows are the part's own published
## figures, and each subclass supplies its own set. The BUILD rows are the five derived stats
## (parts.md) recomputed for the whole current build — because "32 g" means little on its own,
## and "all-up weight 496 g, hover 29%" is the thing a builder is actually deciding between.
##
## The build rows are identical on all three panels on purpose. They are not the frame's stats
## or the motor's stats; they are the aircraft's, and whichever rail you are working on you are
## working on the same aircraft. Giving each panel its own copy of the numbers would invite
## three renderers and eventually three answers.

const STAT_ROWS := [
	{"key": "weight", "label": "All-up weight"},
	{"key": "twr", "label": "Thrust : weight"},
	{"key": "hover", "label": "Hover throttle"},
	{"key": "time", "label": "Flight time"},
	{"key": "speed", "label": "Top speed"},
]

var spec_rows: Array = []

var _title: Label
var _detail_values: Dictionary = {}   # spec key -> Label
var _stat_values: Dictionary = {}     # stat key -> Label
var _warnings: WarningList
var _build_note: Label

func _init(p_spec_rows: Array) -> void:
	spec_rows = p_spec_rows

	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_padded(scroll).add_child(root)

	_title = Label.new()
	_title.text = "—"
	_title.theme_type_variation = &"TitleLabel"
	root.add_child(_title)

	root.add_child(HSeparator.new())

	var specs := GridContainer.new()
	specs.columns = 2
	root.add_child(specs)

	for row in spec_rows:
		_detail_values[row["key"]] = _add_row(specs, row["label"])

	root.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	root.add_child(stats)

	for row in STAT_ROWS:
		_stat_values[row["key"]] = _add_row(stats, row["label"])

	_warnings = WarningList.new(280)
	root.add_child(_warnings)

	_build_note = Label.new()
	_build_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_note.custom_minimum_size = Vector2(280, 0)
	_build_note.theme_type_variation = &"MutedLabel"
	root.add_child(_build_note)


## Inset the panel's contents so right-aligned values do not sit flush against the window edge,
## which reads as clipped text even when nothing is actually cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	# Exception: Programmatic margin container insets using spacing scale
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	parent.add_child(margin)
	return margin


func _add_row(grid: GridContainer, label_text: String) -> Label:
	var name_label := Label.new()
	name_label.text = label_text
	grid.add_child(name_label)

	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)
	return value_label


## Renders one part against the whole current build, so the five derived stats move with every
## selection — the feedback loop parts.md calls the product.
func render(part: Dictionary, build: Build) -> void:
	_title.text = String(part.get("name", "—")).to_upper()

	for row in spec_rows:
		var key: String = row["key"]
		_detail_values[key].text = _read(part, key)

	_stat_values["weight"].text = "%.0f g" % build.all_up_weight_g()
	_stat_values["twr"].text = "%.1f : 1" % build.thrust_to_weight()
	if build.can_hover():
		_stat_values["hover"].text = "%.1f %%" % (build.hover_throttle() * 100.0)
		_stat_values["time"].text = "%.1f min" % build.flight_time_min()
	else:
		_stat_values["hover"].text = "won't hover"
		_stat_values["time"].text = "—"
	_stat_values["speed"].text = "%.0f km/h" % build.top_speed_kmh()

	# Warn, never block (parts.md). A 3" frame under a 7" prop is a legitimate thing to look at;
	# the consequence is the lesson, and the choice stays selectable.
	_warnings.show_warnings(build.warnings())

	_build_note.text = "Stats for %s / %s / %s / %s / %s." % [
		build.frame.get("name", "?"), build.motor.get("name", "?"),
		build.propeller.get("name", "?"), build.battery.get("name", "?"),
		build.esc.get("name", "?")]


## Resolves a row key against the part dictionary and formats it for display. The default
## reads the `catalog` block, which covers every browsing field; subclasses override to add
## their own unit formatting for `specs` fields.
##
## Units are applied here and only here — physics.md §1's coordinate contract keeps everything
## SI (or, as here, raw catalog units) right up to the UI boundary.
##
## Unknown or absent values render as an em dash rather than "0" or "": a part whose contributor
## has not filled in a material should read as missing, not as a value.
func _read(part: Dictionary, key: String) -> String:
	return _or_dash(str(part.get("catalog", {}).get(key, "")))


## Every rendered row as one string, label and value, for tests.
##
## A TEST SEAM and nothing else: a panel's job is to put numbers on screen, and the only way to
## check that it put the RIGHT numbers there is to read back what it rendered. Asserting against
## the source dictionary instead would test the catalog twice and the panel not at all.
func rendered_text() -> String:
	var lines: Array[String] = []
	for row in spec_rows:
		var key: String = row["key"]
		lines.append("%s: %s" % [row["label"], _detail_values[key].text])
	return "\n".join(lines)


static func _or_dash(value: String) -> String:
	return value if value != "" else "—"
