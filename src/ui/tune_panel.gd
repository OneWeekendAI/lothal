class_name TunePanel
extends PanelContainer
## The tuning screen: three axes, three gains each, over the RateTune the aircraft is flying.
##
## ---------------------------------------------------------------------------
## WHY THERE IS A DIAL AT ALL
## ---------------------------------------------------------------------------
##
## RateTune derives a tune from the plant, and it is a better tune than the fixed gains it replaced
## on every build in the catalog. That is not a reason to hide it. Tuning is what FPV builders DO —
## it is half of what a Betaflight configurator is for, and an auto-tune with no dial would have
## removed the one thing a builder came to this screen wanting to do. A workbench that does the
## interesting part for you and then locks the drawer has not helped.
##
## So the derived tune is a BASELINE, not an answer. What this panel is really for is making the
## comparison legible: every row shows what the law derived beside what is in force, so "what did I
## change and by how much" is answerable at a glance, and going back is one button.
##
## ---------------------------------------------------------------------------
## WHAT THIS PANEL DOES NOT OWN
## ---------------------------------------------------------------------------
##
## No gains, no limits, no ranges, and no opinion about what a good tune is. The baseline comes from
## RateTune.derive() for the build on screen; the D ceiling and every warning come from the tune
## itself. This is the same rule AssemblyPanel follows and for the same reason: a panel with its own
## numbers in it is a second opinion about the aircraft, and the whole point of deriving them is
## that there is only one.
##
## It also does not block. A builder who types P 400 gets P 400, and gets told what it is
## (labs-and-sim.md §2, warnings not blocks). The gains are stored unclamped for the same reason a
## shim is: silently rewriting the number somebody typed is the same mistake in a new place.

## The three gains of an axis, in the order a configurator shows them and a builder says them.
const GAIN_ROWS := [
	{"key": "p", "label": "P", "step": 0.01, "max": 400.0},
	{"key": "i", "label": "I", "step": 0.001, "max": 40.0},
	{"key": "d", "label": "D", "step": 0.001, "max": 4.0},
]

## The spin boxes' ceiling is deliberately absurd rather than sensible. It is not a limit on the
## tune — RateTune stores whatever it is given — it is the range of the WIDGET, and setting it near
## a plausible gain would turn "warn, never block" into a block by the back door on a 10" build
## whose derived P is legitimately five times the reference's.

signal tune_changed

var tune: RateTune = null
var build: Build = null

## axis index -> {gain key -> SpinBox}
var _fields: Dictionary = {}
## axis index -> Label showing what the law derived for that axis.
var _derived_labels: Dictionary = {}
var _plant_labels: Dictionary = {}
var _warnings: WarningList
var _summary: Label
## Set while the panel is writing its own controls from the model. Range.value_changed does not
## fire for code-set values on Godot 4.7.1, so this is belt and braces rather than load-bearing —
## but a guard that is only correct on one engine version is a guard worth keeping.
var _updating := false


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Scrolls, for AssemblyPanel's reason: three axes of three fields, plus a baseline row and a
	# plant row each, plus the warning block, is taller than a laptop window — and the warning is
	# the one thing on here nobody can afford to miss.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "TUNE"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = "Rate PID, per axis. The baseline is derived from what this aircraft can accelerate at — change it and the derived figure stays beside it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(280, 0)
	_summary.theme_type_variation = &"MutedLabel"
	root.add_child(_summary)

	for axis in 3:
		root.add_child(HSeparator.new())
		_add_axis(root, axis)

	root.add_child(HSeparator.new())

	_warnings = WarningList.new(280)
	root.add_child(_warnings)

	var reset_button := Button.new()
	reset_button.text = "Reset every axis to the derived tune"
	reset_button.pressed.connect(reset_all)
	root.add_child(reset_button)


static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	# Exception: Programmatic margin container insets using spacing scale
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	parent.add_child(margin)
	return margin


func _add_axis(parent: VBoxContainer, axis: int) -> void:
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = String(RateTune.AXIS_NAMES[axis]).capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	# Per axis rather than only globally, because P/I/D on one axis is one decision and a builder
	# who has been experimenting with yaw should not have to throw away a roll tune to undo it.
	var revert := Button.new()
	revert.text = "Revert"
	revert.pressed.connect(func() -> void: reset_axis(axis))
	header.add_child(revert)
	parent.add_child(header)

	# What the aircraft IS on this axis, in the units the law is written in. Here rather than only
	# in a docstring because it is the reason the numbers below differ from the reference build's,
	# and a tuning screen that showed the gains without the plant would be showing half of it.
	var plant := Label.new()
	plant.theme_type_variation = &"MutedLabel"
	plant.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plant.custom_minimum_size = Vector2(280, 0)
	parent.add_child(plant)
	_plant_labels[axis] = plant

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	var fields: Dictionary = {}
	for row in GAIN_ROWS:
		var name_label := Label.new()
		name_label.text = row["label"]
		grid.add_child(name_label)

		var field := SpinBox.new()
		field.step = row["step"]
		field.min_value = 0.0
		field.max_value = row["max"]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The signal calls a NAMED method rather than doing the work in a lambda, because
		# Range.value_changed does not fire for code-set values on 4.7.1 — so a test driving this
		# panel has to be able to set the fields and then call the same path the mouse does.
		field.value_changed.connect(func(_v: float) -> void: apply_axis(axis))
		grid.add_child(field)
		fields[row["key"]] = field

		var spacer := Label.new()
		spacer.text = ""
		grid.add_child(spacer)

	_fields[axis] = fields

	var derived_label := Label.new()
	derived_label.theme_type_variation = &"MutedLabel"
	derived_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	derived_label.custom_minimum_size = Vector2(280, 0)
	parent.add_child(derived_label)
	_derived_labels[axis] = derived_label


## Shows the tune in force for `p_build`. Called on every selection change as well as after an
## edit, because a part change moves the PLANT — so choosing a longer frame has to move the derived
## baseline while you watch, exactly as choosing a smaller motor narrows the shim slider.
func render(p_build: Build, p_tune: RateTune) -> void:
	build = p_build
	tune = p_tune

	_updating = true
	for axis in 3:
		var fields: Dictionary = _fields[axis]
		var gains := p_tune.gains_for(axis)
		(fields["p"] as SpinBox).value = gains.x
		(fields["i"] as SpinBox).value = gains.y
		(fields["d"] as SpinBox).value = gains.z

		var derived := p_tune.derived_gains_for(axis)
		var suffix := "  (in force)" if not p_tune.is_overridden(axis) else ""
		(_derived_labels[axis] as Label).text = "Derived  P %.3f   I %.4f   D %.4f%s" % [
			derived.x, derived.y, derived.z, suffix]

		# alpha is the plant gain the law divides by; tau is what it holds constant. Showing both
		# is what makes the derived number legible as physics rather than as a magic constant.
		(_plant_labels[axis] as Label).text = "%.0f rad/s%s at full command  ·  %.2fx the reference build  ·  loop %.0f ms" % [
			p_tune.plant_alpha[axis], "²", p_tune.scale[axis],
			p_tune.time_constant_s()[axis] * 1000.0]
	_updating = false

	_summary.text = "Roll, pitch and yaw are scaled separately — this airframe accelerates %.1fx harder in roll than in yaw." % [
		p_tune.plant_alpha.x / p_tune.plant_alpha.z if p_tune.plant_alpha.z > 0.0 else 0.0]
	_warnings.show_warnings(p_tune.warnings())


## Sets one field without going through the mouse. Exists because Range.value_changed does not
## fire for code-set values on 4.7.1, so a test that wrote to the SpinBox directly and waited would
## be asserting on a signal that never arrives — and would pass against a panel wired to nothing.
## This writes the widget; apply_axis() is still what reads it into the model, so the path under
## test is the path the mouse takes.
func set_field(axis: int, gain_key: String, value: float) -> void:
	((_fields[axis] as Dictionary)[gain_key] as SpinBox).value = value


## Reads the three fields of one axis into the model. Public, and a named method rather than the
## body of a lambda, so a test can set the fields and drive exactly the path a mouse drives.
func apply_axis(axis: int) -> void:
	if _updating or tune == null:
		return
	var fields: Dictionary = _fields[axis]
	tune.set_gains(axis, Vector3(
		(fields["p"] as SpinBox).value,
		(fields["i"] as SpinBox).value,
		(fields["d"] as SpinBox).value))
	render(build, tune)
	tune_changed.emit()


func reset_axis(axis: int) -> void:
	if tune == null:
		return
	tune.clear_override(axis)
	render(build, tune)
	tune_changed.emit()


func reset_all() -> void:
	if tune == null:
		return
	tune.clear_all()
	render(build, tune)
	tune_changed.emit()


## The whole panel as text, for tests and for the same reason PartDetails has one: asserting on a
## sentence is how a screen's claims get checked without a screenshot.
func rendered_text() -> String:
	var lines: Array[String] = [_summary.text]
	for axis in 3:
		var fields: Dictionary = _fields[axis]
		lines.append("%s: P %.3f I %.4f D %.4f" % [RateTune.AXIS_NAMES[axis],
			(fields["p"] as SpinBox).value, (fields["i"] as SpinBox).value,
			(fields["d"] as SpinBox).value])
		lines.append((_derived_labels[axis] as Label).text)
		lines.append((_plant_labels[axis] as Label).text)
	for warning in tune.warnings() if tune != null else []:
		lines.append(warning.message)
	return "\n".join(lines)
