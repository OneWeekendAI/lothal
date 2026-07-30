class_name BenchInstruments
extends PanelContainer
## The readout under the thrust stand: what the pairing is doing right now, and how far the
## model can be trusted about it.
##
## Five live numbers — thrust, current, RPM, live pack voltage, efficiency — and two static
## ones: the throttle at which this pairing hits its current limit, and the predicted-versus-
## measured error at a held-out point.
##
## EFFICIENCY GETS THE WEIGHT. labs-and-sim.md §2.1 calls grams per watt "the number most
## builders never look at and the one that decides flight time", so it is not a sixth row in
## a list of six. It is set apart and set large, because a panel that treats every number as
## equally important teaches nothing about which one to read.
##
## Everything displayed is read from the published Observables, never from the powertrain's
## internals — the bench is a consumer of the same layer the HUD and the audio synthesiser
## consume, and that is what makes "the bench and the field agree" structural rather than
## something to keep checking.

const LABEL_COLOUR := Color(0.62, 0.66, 0.72)
const VALUE_COLOUR := Color(0.92, 0.94, 0.97)
const EFFICIENCY_COLOUR := Color(0.55, 0.86, 0.68)
const SAG_COLOUR := Color(1.0, 0.45, 0.36)
const LIMIT_COLOUR := Color(1.0, 0.72, 0.25)
const MUTED_COLOUR := Color(0.58, 0.60, 0.64)

## Rows in display order. Efficiency is deliberately NOT here — it has its own block above.
const ROWS := [
	{"key": "thrust", "label": "Thrust"},
	{"key": "rpm", "label": "RPM"},
	{"key": "current", "label": "Current"},
	{"key": "voltage", "label": "Pack voltage"},
]

## Surfaced from Build.max_throttle_fraction(), not recomputed here.
var current_limit_throttle := 1.0

var _efficiency_value: Label
var _efficiency_caption: Label
var _values: Dictionary = {}   # row key -> Label
var _limit_label: Label
var _validation_label: Label
var _nominal_v := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	PartDetails._padded(self).add_child(root)

	# --- Efficiency, given the room the other five do not get ---
	var efficiency_box := VBoxContainer.new()
	efficiency_box.add_theme_constant_override("separation", 0)
	root.add_child(efficiency_box)

	var efficiency_name := Label.new()
	efficiency_name.text = "EFFICIENCY"
	efficiency_name.add_theme_color_override("font_color", LABEL_COLOUR)
	efficiency_box.add_child(efficiency_name)

	_efficiency_value = Label.new()
	_efficiency_value.text = "—"
	_efficiency_value.add_theme_font_size_override("font_size", 34)
	_efficiency_value.add_theme_color_override("font_color", EFFICIENCY_COLOUR)
	efficiency_box.add_child(_efficiency_value)

	_efficiency_caption = Label.new()
	_efficiency_caption.text = "grams of thrust per watt — what decides flight time"
	_efficiency_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_efficiency_caption.custom_minimum_size = Vector2(280, 0)
	_efficiency_caption.add_theme_color_override("font_color", MUTED_COLOUR)
	efficiency_box.add_child(_efficiency_caption)

	root.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	for row in ROWS:
		var name_label := Label.new()
		name_label.text = row["label"]
		name_label.add_theme_color_override("font_color", LABEL_COLOUR)
		grid.add_child(name_label)

		var value := Label.new()
		value.text = "—"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.add_theme_color_override("font_color", VALUE_COLOUR)
		grid.add_child(value)
		_values[row["key"]] = value

	root.add_child(HSeparator.new())

	_limit_label = Label.new()
	_limit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_limit_label.custom_minimum_size = Vector2(280, 0)
	_limit_label.add_theme_color_override("font_color", LIMIT_COLOUR)
	root.add_child(_limit_label)

	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.custom_minimum_size = Vector2(280, 0)
	_validation_label.add_theme_color_override("font_color", MUTED_COLOUR)
	root.add_child(_validation_label)


## The static half: what this pairing is, before it is run. Called on a selection change
## rather than every frame, because none of it moves while the motor spins.
func render_build(build: Build, catalog: PartsCatalog) -> void:
	current_limit_throttle = build.max_throttle_fraction()
	_nominal_v = build.battery_model().nominal_v

	if current_limit_throttle < 0.995:
		_limit_label.text = "Hits its %.0f A limit at %.0f%% throttle — everything above that is prop the motor cannot turn." % [
			float(build.motor["specs"]["max_amps"]), current_limit_throttle * 100.0]
	else:
		_limit_label.text = "Reaches full throttle inside its %.0f A limit." % float(build.motor["specs"]["max_amps"])

	# The bench quoting its own error bar. A motor with no held-out measurement says so
	# plainly — an unvalidated bench and a validated one must never look the same.
	var summary := ThrustValidation.summary_for(catalog, build.motor)
	if summary == "not validated":
		_validation_label.text = "Held-out validation: not validated — no independently-measured point in the catalog for this motor."
	else:
		_validation_label.text = "Held-out validation (a prop the fit did NOT come from):\n%s" % summary


## The live half, once per frame off the published observables.
func render_live(observables: Observables) -> void:
	var readout := readings(observables)

	_values["thrust"].text = "%.0f g" % readout["thrust_g"]
	_values["rpm"].text = "%.0f" % readout["rpm"]
	_values["current"].text = "%.1f A" % readout["current_a"]
	_values["voltage"].text = "%.2f V" % readout["voltage_v"]

	# Sag stated as a colour as well as a number: the pack losing a volt under load is the
	# lesson the battery bench exists for, and it is easy to miss as a digit that ticks down.
	var sagging: bool = _nominal_v > 0.0 and readout["voltage_v"] < _nominal_v * 0.9
	_values["voltage"].add_theme_color_override("font_color", SAG_COLOUR if sagging else VALUE_COLOUR)

	if readout["efficiency_g_per_w"] > 0.0:
		_efficiency_value.text = "%.2f g/W" % readout["efficiency_g_per_w"]
	else:
		_efficiency_value.text = "—"


## What one motor on the stand is doing, derived from the published observables and nothing
## else. Exposed as data rather than only as text so the tests can assert on the numbers
## instead of parsing labels.
##
## The powertrain runs four identical motors because that is the one electrical model the
## project has; a thrust stand holds ONE. So thrust is read per motor and current is the pack
## total divided by four. Modelling a single motor separately would be a second copy of the
## electrical model, which is the thing the Powertrain split exists to prevent.
static func readings(observables: Observables) -> Dictionary:
	var thrust_g := observables.thrust_n[0] / 9.81 * 1000.0
	var current_a := observables.current_total_a / float(Observables.MOTOR_COUNT)
	var voltage_v := observables.voltage_live_v
	var watts := voltage_v * current_a

	return {
		"thrust_g": thrust_g,
		"rpm": float(observables.rpm[0]),
		"current_a": current_a,
		"voltage_v": voltage_v,
		"watts": watts,
		# Grams per WATT. Grams per amp would look almost identical on screen and be wrong by
		# whatever the pack voltage happens to be, which is exactly the kind of error a unit
		# nobody checks is made of.
		"efficiency_g_per_w": thrust_g / watts if watts > 0.0 else 0.0,
	}


## The keys the panel is displaying, for a test that wants to assert the bench shows what
## labs-and-sim.md §2.1 says it must without depending on label wording.
func readout_text() -> Dictionary:
	return {
		"thrust": _values["thrust"].text,
		"rpm": _values["rpm"].text,
		"current": _values["current"].text,
		"voltage": _values["voltage"].text,
		"efficiency": _efficiency_value.text,
		"limit": _limit_label.text,
		"validation": _validation_label.text,
	}
