class_name PropTunnelPanel
extends VBoxContainer
## The Wind tunnel tab (PD8). Holds no physics: every number is `PropTunnel` or a `PropMeasured` row.
## A refusal leaves the chart empty and says why; the subtitle is on screen in every state.

const SUBTITLE := "Estimated with blade-element theory, not a flow simulation. Good for comparing designs; expect real power to be higher."
const METRICS := ["thrust", "power", "efficiency"]
const METRIC_LABELS := ["Thrust", "Power", "Efficiency"]
const METRIC_UNITS := {"thrust": "thrust, g", "power": "power, W", "efficiency": "efficiency"}
const SHADES := ["alpha", "thrust"]
const SHADE_LABELS := ["α", "Thrust"]
const ANGLE_STEP := 15.0
## Past 90 the air comes from below. The control goes there on purpose, to show the refusal.
const ANGLE_MAX := 120.0
const G_PER_N := 1000.0 / 9.80665
## The blade greys. Never black or white, so the blade's edge stays readable either way.
const SHADE_LOW := 0.22
const SHADE_HIGH := 0.95
const NOTE_OFF_AXIS := "Off axis: total thrust and power only, no blade asymmetry."
const NOTE_NO_EFFICIENCY := "Efficiency is only read straight on. Off axis, this model gives thrust and power."

var shell: PropDesigner
var metric := "thrust"
var shade_by := "alpha"
var angle_deg := 0.0
var look_j := 0.0
var result: Dictionary = {}
var shade_table := PackedFloat64Array()
var measured: Dictionary = {}

var subtitle: Label
var chart: PropTunnelChart
var warning_label: Label
var note_label: Label
var dots_label: Label
var station_label: Label
var metric_row: HFlowContainer
var shade_row: HFlowContainer
var rpm_value: Label
var angle_value: Label
var look_value: Label


func _init(p_shell: PropDesigner) -> void:
	shell = p_shell
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	subtitle = shell._faint(SUBTITLE)
	subtitle.name = "TunnelSubtitle"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle)
	metric_row = shell._chip_row("TunnelMetric", "Metric_")
	shell._set_chips(metric_row, METRICS, METRIC_LABELS, set_metric)
	add_child(metric_row)
	chart = PropTunnelChart.new()
	chart.name = "TunnelChart"
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(0, 170)
	add_child(chart)
	warning_label = _line("TunnelWarning")
	warning_label.add_theme_color_override("font_color", DesignSpace.WARN_INK)
	note_label = _line("TunnelNote")
	dots_label = _line("TunnelDots")
	rpm_value = shell._add_stepper(self, "TunnelRpm", "Rpm", "The rpm for this sweep and the figures.",
		func(): shell.step_rpm(-PropDesigner.STEP_RPM), func(): shell.step_rpm(PropDesigner.STEP_RPM), 90.0)
	angle_value = shell._add_stepper(self, "TunnelAngle", "Flow angle", "0 is straight into the disc, 90 is edgewise, past 90 is descent.",
		func(): set_angle(angle_deg - ANGLE_STEP), func(): set_angle(angle_deg + ANGLE_STEP), 90.0)
	look_value = shell._add_stepper(self, "TunnelLook", "Blade shows J", "Which point of the curve the blade is shaded for.",
		func(): set_look_j(look_j - PropTunnel.J_STEP), func(): set_look_j(look_j + PropTunnel.J_STEP), 90.0)
	shade_row = shell._chip_row("TunnelShade", "Shade_")
	shell._set_chips(shade_row, SHADES, SHADE_LABELS, set_shade)
	add_child(shade_row)
	station_label = _line("TunnelStations")


func _line(node_name: String) -> Label:
	var l := shell._faint("")
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func set_metric(m: Variant) -> void:
	metric = String(m)
	shell._rederive()


func set_shade(s: Variant) -> void:
	shade_by = String(s)
	shell._rederive()


func set_angle(deg: float) -> void:
	angle_deg = clampf(deg, 0.0, ANGLE_MAX)
	shell._rederive()


func set_look_j(j: float) -> void:
	look_j = maxf(j, 0.0)
	shell._rederive()


## Called by the designer's `_rederive`, so any change reruns the sweep.
func refresh(doc: PropellerDocument, rpm: float) -> void:
	var g := PropTunnel.geometry_of(doc)
	result = PropTunnel.sweep(g, rpm, angle_deg)
	measured = PropMeasured.match_for(doc) if angle_deg == 0.0 else {}
	warning_label.text = ""
	note_label.text = ""
	dots_label.text = ""
	shell._mark_chips(metric_row, METRICS, metric)
	shell._mark_chips(shade_row, SHADES, shade_by)
	rpm_value.text = "%d rpm" % roundi(rpm)
	angle_value.text = "%d°" % roundi(angle_deg)
	if not result.ok:
		look_value.text = "–"
		warning_label.text = String(result.reason)
		chart.set_data([], PackedVector2Array(), METRIC_UNITS[metric], -1.0)
		_clear_stations()
		_hide_empty_lines()
		return
	var pts: Array = result.points
	look_j = minf(look_j, float(pts[pts.size() - 1].j))
	look_value.text = "%.2f" % look_j
	var off_axis := angle_deg != 0.0
	var flag := _first_flag(pts)
	var series := _series(pts)
	if metric == "efficiency" and off_axis:
		warning_label.text = NOTE_NO_EFFICIENCY
	else:
		warning_label.text = flag
	var notes := PackedStringArray([String(result.end_reason)])
	if off_axis:
		notes.append(NOTE_OFF_AXIS)
	note_label.text = " ".join(notes)
	var dots := _dots(doc, rpm) if not series.is_empty() else PackedVector2Array()
	if not dots.is_empty():
		var scaled := "" if absf(rpm / float(measured.run_rpm) - 1.0) < 0.01 else ", scaled to this rpm"
		dots_label.text = "Dots: measured, UIUC %s, tested at %d rpm%s." % [measured.name, int(measured.run_rpm), scaled]
	chart.set_data(series, dots, METRIC_UNITS[metric], look_j)
	_shade_stations(g, rpm)
	_hide_empty_lines()


static func _first_flag(pts: Array) -> String:
	for p: Dictionary in pts:
		if String(p.flag) != "":
			return String(p.flag)
	return ""


## The chart's points, one per sweep point. Efficiency stops where power stops being positive, since
## the ratio means nothing past it, and off axis there is none at all.
func _series(pts: Array) -> Array:
	var out: Array = []
	if metric == "efficiency" and angle_deg != 0.0:
		return out
	for p: Dictionary in pts:
		var y := 0.0
		match metric:
			"thrust": y = float(p.thrust_n) * G_PER_N
			"power": y = float(p.power_w)
			"efficiency":
				if float(p.power_w) <= 0.0:
					break
				y = float(p.eta)
		out.append({"x": float(p.j), "y": y, "flagged": String(p.flag) != ""})
	return out


func _dots(doc: PropellerDocument, rpm: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if measured.is_empty():
		return out
	var n := rpm / 60.0
	var d := doc.diameter_mm * 0.001
	var rho := PropTunnel.RHO_SEA_LEVEL
	for row: Array in measured.rows:
		var y := 0.0
		match metric:
			"thrust": y = float(row[1]) * rho * n * n * pow(d, 4.0) * G_PER_N
			"power": y = float(row[2]) * rho * pow(n, 3.0) * pow(d, 5.0)
			"efficiency": y = float(row[3])
		out.append(Vector2(float(row[0]), y))
	return out


func _clear_stations() -> void:
	shade_table = PackedFloat64Array()
	station_label.text = ""


## Stations at the looked-at J, the blade shaded across their own range. Grey, because the range is
## relative: this shows where on the blade, not how much against another blade.
func _hide_empty_lines() -> void:
	for l: Label in [warning_label, note_label, dots_label, station_label]:
		l.visible = l.text != ""


func _shade_stations(g: Dictionary, rpm: float) -> void:
	var v := PropTunnel.speeds_at(g, rpm, look_j, angle_deg)
	var tap := PropTunnel.stations(g, rpm, float(v.v_axial), float(v.v_edge))
	if not tap.ok or (tap.stations as Array).is_empty():
		_clear_stations()
		return
	var lo := INF
	var hi := -INF
	var key := "alpha_rad" if shade_by == "alpha" else "thrust_n"
	for s: Dictionary in tap.stations:
		lo = minf(lo, float(s[key]))
		hi = maxf(hi, float(s[key]))
	var table := PackedFloat64Array()
	for s: Dictionary in tap.stations:
		table.append(float(s.r_frac))
		var t := (float(s[key]) - lo) / (hi - lo) if hi > lo else 0.5
		table.append(lerpf(SHADE_LOW, SHADE_HIGH, t))
	shade_table = table
	if shade_by == "alpha":
		station_label.text = "Blade at J %.2f: α %.1f° (dark) to %.1f° (light)." % [look_j, rad_to_deg(lo), rad_to_deg(hi)]
	else:
		station_label.text = "Blade at J %.2f: light stations make the most thrust." % look_j
