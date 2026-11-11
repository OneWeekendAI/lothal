class_name DsHud
extends Control
## The flight readouts of the Sim, in Design Space language: two quiet panels (the file bar's own
## box, ink text, the interface face) and nothing else. Bottom left the aircraft (speed, wind, pack,
## flight mode), top right the race (lap, best, gate, recording), top centre a banner, top left the
## build's warnings. Every number is read off the observables layer and the Build; none is computed
## here beyond unit conversion and the formatting of a clock.
##
## Words, not codes: the flight mode reads "Self-levelling" / "Full manual", the pack "62 %  ·  2:24
## left". The wind is stated (speed, and the bearing it comes FROM) and never graded.
##
## Built in code, like every Design Space surface.

const VOLTAGE_WARN_FRACTION := 0.82
const VOLTAGE_CRITICAL_FRACTION := 0.75
const COLOR_OK := DsUi.INK
const COLOR_WARN := LothalTheme.WARNING
const COLOR_CRITICAL := LothalTheme.DANGER
const COLOR_ACCENT := DesignSpace.SELECT_INK
const COLOR_DIM := DsUi.INK_MUTED
## Most warnings listed at once; the rest are counted.
const MAX_WARNING_LINES := 5
const SIZE_BODY := LothalTheme.FONT_SIZE_BODY

var _throttle_bar: ProgressBar
var _throttle_label: Label
var _speed_gauge: ReadoutGauge
var _speed_label: Label
var _wind_label: Label
var _voltage_label: Label
var _pack_label: Label
var _mode_label: Label
var _current_lap_label: Label
var _best_lap_label: Label
var _gate_label: Label
var _record_label: Label
var _banner_label: Label
var _banner_panel: PanelContainer
var _warnings_panel: PanelContainer
var _warnings_label: Label

var _banner_timeout := 0.0


func _init() -> void:
	name = "DsHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Bottom left: the aircraft ---
	var flight_panel := _panel()
	flight_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flight_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	flight_panel.offset_left = LothalTheme.SPACE_4
	flight_panel.offset_bottom = -LothalTheme.SPACE_4
	flight_panel.custom_minimum_size = Vector2(264, 0)
	add_child(flight_panel)
	var flight := VBoxContainer.new()
	flight.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_panel.add_child(flight)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(top)
	_speed_gauge = ReadoutGauge.new("top_speed_kmh")
	top.add_child(_speed_gauge)
	var speed_col := VBoxContainer.new()
	speed_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_col.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(speed_col)
	_speed_label = _line(speed_col, LothalTheme.FONT_SIZE_HERO - 8, DsUi.INK)
	_mode_label = _line(speed_col, LothalTheme.FONT_SIZE_SMALL, DsUi.INK_MUTED)

	var throttle_row := HBoxContainer.new()
	throttle_row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	throttle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(throttle_row)
	throttle_row.add_child(DsUi.label("Throttle"))
	_throttle_bar = ProgressBar.new()
	_throttle_bar.min_value = 0.0
	_throttle_bar.max_value = 100.0
	_throttle_bar.show_percentage = false
	_throttle_bar.custom_minimum_size = Vector2(120, 6)
	_throttle_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_throttle_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_throttle_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = DsUi.INK_FAINT
	var fill := StyleBoxFlat.new()
	fill.bg_color = DsUi.INK_MUTED
	_throttle_bar.add_theme_stylebox_override("background", track)
	_throttle_bar.add_theme_stylebox_override("fill", fill)
	throttle_row.add_child(_throttle_bar)
	_throttle_label = DsUi.label("", DsUi.INK)
	_throttle_label.custom_minimum_size = Vector2(40, 0)
	_throttle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	throttle_row.add_child(_throttle_label)

	flight.add_child(DsUi.rule())
	_wind_label = _line(flight, SIZE_BODY, COLOR_OK)
	_voltage_label = _line(flight, SIZE_BODY, COLOR_OK)
	_pack_label = _line(flight, SIZE_BODY, COLOR_OK)

	# --- Top right: the race ---
	var race_panel := _panel()
	race_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	race_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	race_panel.offset_right = -LothalTheme.SPACE_4
	race_panel.offset_top = 64   # under the file bar, which at wide sizes reaches this corner
	race_panel.custom_minimum_size = Vector2(176, 0)
	add_child(race_panel)
	var race := VBoxContainer.new()
	race.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	race.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_panel.add_child(race)
	_current_lap_label = _line(race, LothalTheme.FONT_SIZE_TITLE, DsUi.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_best_lap_label = _line(race, SIZE_BODY, COLOR_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_gate_label = _line(race, SIZE_BODY, COLOR_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	# Recording is armed by hand and can be forgotten either way, so it is a persistent line, not a
	# banner: it stays until the recorder stops (logs.md §4.1).
	_record_label = _line(race, SIZE_BODY, COLOR_CRITICAL, HORIZONTAL_ALIGNMENT_RIGHT)
	_record_label.visible = false

	# --- Top centre: transient banner, under the file bar ---
	_banner_panel = _panel()
	_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_panel.offset_top = 72
	_banner_panel.visible = false
	add_child(_banner_panel)
	_banner_label = DsUi.label("", COLOR_ACCENT, LothalTheme.FONT_SIZE_SUBTITLE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_panel.add_child(_banner_label)

	# --- Top left: what is wrong with the build being flown ---
	_warnings_panel = _panel()
	_warnings_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_warnings_panel.offset_left = LothalTheme.SPACE_4
	_warnings_panel.offset_top = LothalTheme.SPACE_4
	_warnings_panel.custom_minimum_size = Vector2(250, 0)
	_warnings_panel.visible = false
	add_child(_warnings_panel)
	_warnings_label = DsUi.label("", COLOR_WARN, LothalTheme.FONT_SIZE_SMALL)
	_warnings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings_panel.add_child(_warnings_label)


static func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := DsUi.panel_style()
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", box)
	return p


static func _line(parent: Node, font_px: int, ink: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := DsUi.label("", ink, font_px)
	l.horizontal_alignment = alignment
	parent.add_child(l)
	return l


## Lists the build's warnings (Build.warnings()), or hides the panel when there
## are none. Called once when the sim takes its Build: the warnings depend on the parts, not the
## frame. Amber when anything is impossible or limiting; muted when all are only characteristic.
func show_warnings(build: Build) -> void:
	var entries := build.warnings()
	entries.sort_custom(func(a: BuildWarning, b: BuildWarning) -> bool: return a.severity < b.severity)
	var lines: PackedStringArray = []
	var serious := false
	for i in entries.size():
		if entries[i].severity != BuildWarning.Severity.CHARACTERISTIC:
			serious = true
		if i < MAX_WARNING_LINES:
			lines.append(entries[i].short if entries[i].short != "" else entries[i].message.left(WarningRows.SHORT_MAX))
	if entries.size() > MAX_WARNING_LINES:
		lines.append("+ %d more" % (entries.size() - MAX_WARNING_LINES))
	_warnings_label.text = "\n".join(lines)
	_warnings_label.add_theme_color_override("font_color", COLOR_WARN if serious else COLOR_DIM)
	_warnings_panel.visible = not lines.is_empty()


## Called every frame with the live simulation state.
func render(core: DroneCore, build: Build, course: GateCourse, timer: LapTimer, rate_mode: bool) -> void:
	var obs := core.observables
	var throttle_fraction := _average_throttle_fraction(obs, build)
	_throttle_bar.value = throttle_fraction * 100.0
	_throttle_label.text = "%.0f %%" % (throttle_fraction * 100.0)

	var kmh := obs.airspeed_mps * 3.6
	_speed_label.text = "%.0f km/h" % kmh
	_speed_gauge.set_value(kmh)

	# States the wind and stops there: a pilot judges it themselves ("too windy" is Lothal deciding
	# what the pilot can handle, which is the warning vocabulary's job). `core.wind` is null on a
	# core nobody handed a Wind: that reads as no wind.
	if core.wind != null:
		_wind_label.text = "Wind  %.1f m/s from %.0f°" % [core.wind.speed_mps, core.wind.from_deg]
	else:
		_wind_label.text = "Wind  none"

	_voltage_label.text = "%.2f V  ·  %.0f A" % [obs.voltage_live_v, obs.current_total_a]
	_voltage_label.add_theme_color_override("font_color", _voltage_color(obs, build))

	var remaining := 1.0 - obs.capacity_used_fraction
	var minutes := build.remaining_flight_time_min(core.powertrain.battery)
	_pack_label.text = "%.0f %%  ·  %s" % [remaining * 100.0, _format_minutes(minutes)]
	_pack_label.add_theme_color_override("font_color",
		COLOR_CRITICAL if minutes <= 0.0 else (COLOR_WARN if remaining < 0.2 else COLOR_OK))
	_speed_gauge.set_warn(minutes <= 0.0 or remaining < 0.2)

	_mode_label.text = "Full manual (acro)" if rate_mode else "Self-levelling"

	_current_lap_label.text = "Lap  %s" % (LapTimer.format(timer.current_lap_s) if timer.running else "--:--.--")
	_best_lap_label.text = "Best  %s" % LapTimer.format(timer.best_lap_s)
	_gate_label.text = "Gate %d of %d" % [course.next_gate_index + 1, course.gate_count()]


## "2:24 left", because "2.4 min" is a number to convert mid-flight. Zero reads as spent.
static func _format_minutes(minutes: float) -> String:
	if minutes <= 0.0:
		return "on reserve"
	return "%s left" % Duration.clock(round(minutes * 60.0))


## Shows or hides the recording line. `rows` and `seconds` come from the recorder itself.
func set_recording(active: bool, seconds: float = 0.0, rows: int = 0) -> void:
	_record_label.visible = active
	if active:
		_record_label.text = "Recording  %s  ·  %s rows" % [Duration.clock(round(seconds)), rows]


func tick_banner(delta: float) -> void:
	if _banner_timeout > 0.0:
		_banner_timeout -= delta
		if _banner_timeout <= 0.0:
			_banner_panel.visible = false


func show_banner(text: String, seconds: float = 2.5) -> void:
	_banner_label.text = text
	_banner_panel.visible = true
	_banner_timeout = seconds


## Mean RPM against the ceiling this pack and prop can reach, not the stick: in angle mode the
## controller moves the motors away from the commanded throttle constantly.
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
