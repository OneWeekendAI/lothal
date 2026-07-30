class_name Hud
extends Control
## Throttle, voltage, speed, lap timer and next gate — the fourth consumer of the
## observables layer, after vision, controls and the build panel.
##
## Architecture note worth keeping, with a correction. Adding this required no change to
## src/sim — but only because it reached into DroneCore's internal fields (motor_rpm,
## last_voltage_v) directly, which is cheap for the first consumer and a drift hazard for
## the second. It now reads DroneCore.observables, the same object audio reads, so the two
## cannot disagree about how fast a motor is turning.
##
## Built in code, like the build panel — hand-placed UI does not survive version control.

## Below this fraction of nominal pack voltage the reading turns amber: the pack is sagging
## hard enough that the drone is about to feel different, and a pilot should see it coming
## rather than discover it in a corner.
const VOLTAGE_WARN_FRACTION := 0.82
const VOLTAGE_CRITICAL_FRACTION := 0.75

const COLOR_OK := Color(0.86, 0.90, 0.94)
const COLOR_WARN := Color(1.0, 0.72, 0.25)
const COLOR_CRITICAL := Color(1.0, 0.36, 0.30)
const COLOR_ACCENT := Color(0.45, 0.86, 1.0)
const COLOR_DIM := Color(0.6, 0.63, 0.68)

var _throttle_bar: ProgressBar
var _throttle_label: Label
var _voltage_label: Label
var _speed_label: Label
var _current_lap_label: Label
var _best_lap_label: Label
var _gate_label: Label
var _mode_label: Label
var _banner_label: Label

var _banner_timeout := 0.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Bottom-left: the flight instruments ---
	var flight := VBoxContainer.new()
	flight.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flight.offset_left = 16
	flight.offset_top = -104
	flight.offset_bottom = -16
	flight.offset_right = 296
	flight.add_theme_constant_override("separation", 4)
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flight)

	var throttle_row := HBoxContainer.new()
	throttle_row.add_theme_constant_override("separation", 8)
	flight.add_child(throttle_row)

	var throttle_caption := Label.new()
	throttle_caption.text = "THR"
	throttle_caption.add_theme_color_override("font_color", COLOR_DIM)
	throttle_row.add_child(throttle_caption)

	_throttle_bar = ProgressBar.new()
	_throttle_bar.min_value = 0.0
	_throttle_bar.max_value = 100.0
	_throttle_bar.show_percentage = false
	_throttle_bar.custom_minimum_size = Vector2(180, 14)
	_throttle_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	throttle_row.add_child(_throttle_bar)

	_throttle_label = Label.new()
	_throttle_label.custom_minimum_size = Vector2(52, 0)
	_throttle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	throttle_row.add_child(_throttle_label)

	_speed_label = _add_readout(flight)
	_voltage_label = _add_readout(flight)

	_mode_label = Label.new()
	_mode_label.add_theme_color_override("font_color", COLOR_DIM)
	flight.add_child(_mode_label)

	# --- Top-right: the race ---
	var race := VBoxContainer.new()
	race.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	race.offset_left = -240
	race.offset_top = 16
	race.offset_right = -16
	race.alignment = BoxContainer.ALIGNMENT_BEGIN
	race.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(race)

	_current_lap_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	_current_lap_label.add_theme_font_size_override("font_size", 22)
	_best_lap_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	_gate_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	_gate_label.add_theme_color_override("font_color", COLOR_ACCENT)

	# --- Centre: transient banners (lap complete, new best) ---
	_banner_label = Label.new()
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.offset_top = 72
	_banner_label.offset_left = -220
	_banner_label.offset_right = 220
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 28)
	_banner_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.visible = false
	add_child(_banner_label)

func _add_readout(parent: Node, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", COLOR_OK)
	parent.add_child(label)
	return label

## Called every frame with the live simulation state. Nothing is cached and nothing is
## computed here beyond unit conversion — if a number on the HUD is wrong, it is wrong in
## the physics, which is the property that makes the HUD useful for debugging.
func render(core: DroneCore, build: Build, course: GateCourse, timer: LapTimer, rate_mode: bool) -> void:
	var obs := core.observables
	var throttle_fraction := _average_throttle_fraction(obs, build)
	_throttle_bar.value = throttle_fraction * 100.0
	_throttle_label.text = "%.0f %%" % (throttle_fraction * 100.0)

	_speed_label.text = "%.0f km/h" % (obs.airspeed_mps * 3.6)

	_voltage_label.text = "%.2f V   %.0f A" % [obs.voltage_live_v, obs.current_total_a]
	_voltage_label.add_theme_color_override("font_color", _voltage_color(obs, build))

	_mode_label.text = "ACRO" if rate_mode else "ANGLE"

	_current_lap_label.text = "LAP  %s" % LapTimer.format(timer.current_lap_s) if timer.running else "LAP  --:--.--"
	_best_lap_label.text = "BEST %s" % LapTimer.format(timer.best_lap_s)
	_gate_label.text = "GATE %d / %d" % [course.next_gate_index + 1, GateCourse.GATE_COUNT]

func tick_banner(delta: float) -> void:
	if _banner_timeout > 0.0:
		_banner_timeout -= delta
		if _banner_timeout <= 0.0:
			_banner_label.visible = false

func show_banner(text: String, seconds: float = 2.5) -> void:
	_banner_label.text = text
	_banner_label.visible = true
	_banner_timeout = seconds

## The bar shows what the motors are ACTUALLY doing — mean RPM against the ceiling this
## pack and prop can reach — not the stick position. In angle mode the controller is
## constantly moving individual motors away from the commanded throttle to hold attitude,
## and a bar showing the raw stick would sit still while the drone fought for its life.
func _average_throttle_fraction(obs: Observables, build: Build) -> float:
	var ceiling := build.rpm_at_throttle(build.max_throttle_fraction())
	if ceiling <= 0.0:
		return 0.0
	return clampf(obs.mean_rpm() / ceiling, 0.0, 1.0)

func _voltage_color(obs: Observables, build: Build) -> Color:
	var nominal: float = float(build.battery["specs"]["nominal_v"])
	if nominal <= 0.0:
		return COLOR_OK
	var fraction := obs.voltage_live_v / nominal
	if fraction < VOLTAGE_CRITICAL_FRACTION:
		return COLOR_CRITICAL
	if fraction < VOLTAGE_WARN_FRACTION:
		return COLOR_WARN
	return COLOR_OK
