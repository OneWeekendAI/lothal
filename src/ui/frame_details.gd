class_name FrameDetails
extends PanelContainer
## Everything known about the highlighted frame, plus what choosing it does to the build.
##
## Every value here is read out of the part dictionary at render time. Nothing about any
## specific frame is written into this file — if a number on screen cannot be traced back to
## frames.json, that is a bug, and tests/test_lab.gd asserts exactly that traceability.
##
## The panel deliberately mixes two kinds of row. The SPEC rows are the frame's own
## published figures. The BUILD rows are the five derived stats (parts.md) recomputed with
## this frame fitted to the reference motor, prop and pack — because "148 g" means little on
## its own, and "all-up weight 534 g, hover 34%" is the thing a builder is actually
## deciding between. Holding the other three parts fixed is what makes two frames
## comparable at all.

## key -> label. The key is the path into the part dictionary, resolved in _read().
const SPEC_ROWS := [
	{"key": "frame_type", "label": "Type"},
	{"key": "size_class", "label": "Built around"},
	{"key": "material", "label": "Material"},
	{"key": "mass_g", "label": "Frame mass"},
	{"key": "arm_mm", "label": "Arm (centre→motor)"},
	{"key": "max_prop_inches", "label": "Max prop"},
	{"key": "motor_mount", "label": "Motor mount"},
]

const STAT_ROWS := [
	{"key": "weight", "label": "All-up weight"},
	{"key": "twr", "label": "Thrust : weight"},
	{"key": "hover", "label": "Hover throttle"},
	{"key": "time", "label": "Flight time"},
	{"key": "speed", "label": "Top speed"},
]

var _title: Label
var _detail_values: Dictionary = {}   # spec key -> Label
var _stat_values: Dictionary = {}     # stat key -> Label
var _warning_label: Label
var _fixture_note: Label

func _init() -> void:
	custom_minimum_size = Vector2(344, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_padded(self).add_child(root)

	_title = Label.new()
	_title.text = "—"
	root.add_child(_title)

	root.add_child(HSeparator.new())

	var specs := GridContainer.new()
	specs.columns = 2
	specs.add_theme_constant_override("h_separation", 10)
	specs.add_theme_constant_override("v_separation", 4)
	root.add_child(specs)

	for row in SPEC_ROWS:
		_detail_values[row["key"]] = _add_row(specs, row["label"])

	root.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 4)
	root.add_child(stats)

	for row in STAT_ROWS:
		_stat_values[row["key"]] = _add_row(stats, row["label"])

	_warning_label = Label.new()
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.custom_minimum_size = Vector2(300, 0)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	root.add_child(_warning_label)

	_fixture_note = Label.new()
	_fixture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fixture_note.custom_minimum_size = Vector2(300, 0)
	_fixture_note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	root.add_child(_fixture_note)

## Inset the panel's contents so right-aligned values do not sit flush against the window
## edge, which reads as clipped text even when nothing is actually cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
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


## Renders one frame. `build` is that frame fitted to the reference powertrain, so the five
## derived stats move with the selection — the feedback loop parts.md calls the product.
func render(frame: Dictionary, build: Build) -> void:
	_title.text = String(frame.get("name", "—")).to_upper()

	for row in SPEC_ROWS:
		var key: String = row["key"]
		_detail_values[key].text = _read(frame, key)

	_stat_values["weight"].text = "%.0f g" % build.all_up_weight_g()
	_stat_values["twr"].text = "%.1f : 1" % build.thrust_to_weight()
	if build.can_hover():
		_stat_values["hover"].text = "%.1f %%" % (build.hover_throttle() * 100.0)
		_stat_values["time"].text = "%.1f min" % build.flight_time_min()
	else:
		_stat_values["hover"].text = "won't hover"
		_stat_values["time"].text = "—"
	_stat_values["speed"].text = "%.0f km/h" % build.top_speed_kmh()

	# Warn, never block (parts.md). A 3" frame under a 5" prop is a legitimate thing to look
	# at; the consequence is the lesson, and the choice stays selectable.
	var warnings := build.warnings()
	_warning_label.text = "\n".join(warnings)
	_warning_label.visible = not warnings.is_empty()

	_fixture_note.text = "Stats assume %s / %s / %s." % [
		build.motor.get("name", "?"), build.propeller.get("name", "?"), build.battery.get("name", "?")]


## Resolves a row key against the part dictionary and formats it for display. Units are
## applied here and only here — physics.md §1's coordinate contract keeps everything SI (or
## in this case, raw catalog units) right up to the UI boundary.
##
## Unknown or absent values render as an em dash rather than "0" or "": a frame whose
## contributor has not filled in a material should read as missing, not as a value.
func _read(frame: Dictionary, key: String) -> String:
	var specs: Dictionary = frame.get("specs", {})
	var meta: Dictionary = frame.get("catalog", {})

	match key:
		"mass_g":
			return "%.0f g" % float(frame.get("mass_g", 0.0))
		"arm_mm":
			return "%.0f mm" % float(specs.get("arm_mm", 0.0))
		"max_prop_inches":
			return "%.1f\"" % float(specs.get("max_prop_inches", 0.0))
		"motor_mount":
			return _or_dash(str(specs.get("motor_mount", "")))
		_:
			return _or_dash(str(meta.get(key, "")))

static func _or_dash(value: String) -> String:
	return value if value != "" else "—"
