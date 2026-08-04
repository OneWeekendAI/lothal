class_name Hud
extends Control
## Throttle, voltage, current, pack charge, remaining flight time, speed, lap timer and next gate
## — the fourth consumer of the observables layer, after vision, controls and the build panel.
##
## THE PACK LINE IS TWO QUESTIONS, and a pilot in the air asks the second one. Voltage and current
## say what the pack is doing right now; remaining charge and remaining flight time say how much
## longer you have. The discharge curve is exactly why both are needed — a LiPo sits on its
## plateau for most of a flight and the voltmeter barely moves, so a timer is the better fuel
## gauge and the voltmeter is the better warning of the knee (physics.md §5).
##
## Neither of the two new figures is computed here. Charge comes off the observables layer where
## the powertrain publishes it, and the minutes come from Build.remaining_flight_time_min(), which
## uses the same reserve and the same average-to-hover ratio as the flight time on the garage
## stats panel. A HUD that did its own arithmetic would be a second opinion about the aircraft.
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

## Named against LothalTheme rather than restated as literals: a copied colour that agrees with
## the theme today is a colour that disagrees with it after the next palette change, silently.
const COLOR_OK := LothalTheme.TEXT_MAIN
const COLOR_WARN := LothalTheme.WARNING
const COLOR_CRITICAL := LothalTheme.DANGER
const COLOR_ACCENT := LothalTheme.ACCENT
const COLOR_DIM := LothalTheme.TEXT_MUTED

## How much of the bottom-left corner the flight readouts claim. Stated rather than measured
## because the panel that has to keep clear of them is sized before this block has ever been
## laid out — and a HUD that another panel draws over is not a HUD.
const FLIGHT_BLOCK_HEIGHT := 136.0

var _throttle_bar: ProgressBar
var _throttle_label: Label
var _voltage_label: Label
var _pack_label: Label
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
	flight.offset_left = LothalTheme.SPACE_4
	flight.offset_bottom = -LothalTheme.SPACE_4
	flight.custom_minimum_size = Vector2(280, 0)
	flight.grow_vertical = Control.GROW_DIRECTION_BEGIN
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flight)

	var throttle_row := HBoxContainer.new()
	flight.add_child(throttle_row)

	var throttle_caption := Label.new()
	throttle_caption.text = "THR"
	throttle_caption.theme_type_variation = &"MutedLabel"
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
	_throttle_label.theme_type_variation = &"ReadoutLabel"
	throttle_row.add_child(_throttle_label)

	_speed_label = _add_readout(flight)
	_voltage_label = _add_readout(flight)
	_pack_label = _add_readout(flight)

	_mode_label = Label.new()
	_mode_label.theme_type_variation = &"MutedLabel"
	flight.add_child(_mode_label)

	# --- Top-right: the race ---
	var race := VBoxContainer.new()
	race.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	race.offset_right = -LothalTheme.SPACE_4
	race.offset_top = LothalTheme.SPACE_4
	race.custom_minimum_size = Vector2(220, 0)
	race.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	race.alignment = BoxContainer.ALIGNMENT_BEGIN
	race.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(race)

	_current_lap_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	_current_lap_label.theme_type_variation = &"TitleLabel"
	_best_lap_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	_gate_label = _add_readout(race, HORIZONTAL_ALIGNMENT_RIGHT)
	# Exception: Accent highlight for gate label
	_gate_label.add_theme_color_override("font_color", COLOR_ACCENT)

	# --- Centre: transient banners (lap complete, new best) ---
	_banner_label = Label.new()
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.offset_top = 72
	_banner_label.custom_minimum_size = Vector2(440, 0)
	_banner_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.theme_type_variation = &"TitleLabel"
	# Exception: Accent highlight for transient banner
	_banner_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.visible = false
	add_child(_banner_label)

func _add_readout(parent: Node, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.theme_type_variation = &"ReadoutLabel"
	# Exception: Default base color for HUD readouts
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
	# Exception: Dynamic runtime voltage sag color shift
	_voltage_label.add_theme_color_override("font_color", _voltage_color(obs, build))

	# Remaining charge and remaining flying, updating live off the same pack the physics drains.
	# Amber below a fifth, the same threshold the garage's charger and the bench's knee use, so
	# "nearly flat" reads the same everywhere.
	var remaining := 1.0 - obs.capacity_used_fraction
	var minutes := build.remaining_flight_time_min(core.powertrain.battery)
	_pack_label.text = "%.0f %%   %s left" % [remaining * 100.0, _format_minutes(minutes)]
	# Exception: Dynamic runtime flight time / pack warning color shift
	_pack_label.add_theme_color_override("font_color",
		COLOR_CRITICAL if minutes <= 0.0 else (COLOR_WARN if remaining < 0.2 else COLOR_OK))

	_mode_label.text = "ACRO" if rate_mode else "ANGLE"

	_current_lap_label.text = "LAP  %s" % LapTimer.format(timer.current_lap_s) if timer.running else "LAP  --:--.--"
	_best_lap_label.text = "BEST %s" % LapTimer.format(timer.best_lap_s)
	# Off the course being flown, not off GateCourse.GATE_COUNT — which was 8 whatever the pilot
	# had laid out, and would have read "GATE 3 / 8" all the way round a five-gate course.
	_gate_label.text = "GATE %d / %d" % [course.next_gate_index + 1, course.gate_count()]

## Minutes and seconds, because "2.4 min" is a number a pilot has to convert mid-flight and
## "2:24" is one they can act on. Zero reads as spent rather than as 0:00, which would look like a
## clock that had stopped rather than a pack past its reserve.
static func _format_minutes(minutes: float) -> String:
	if minutes <= 0.0:
		return "RESERVE"
	# Rounded to the nearest second HERE, then handed to a formatter that truncates — so the
	# countdown ticks on the half-second the way a clock does, and the mm:ss arithmetic itself
	# lives in exactly one place (Duration, which this was the fourth copy of).
	return Duration.clock(round(minutes * 60.0))


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
