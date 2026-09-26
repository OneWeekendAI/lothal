class_name ConfigDiagram
extends Control
## The drawing on the five Config item pages (lab dock design §2, §3) — VideoDiagram's sibling.
## Read-only; every figure comes from `ConfigFigures`, the calls the row, the page's two numbers and
## the sheet read, so the drawing cannot disagree with them.
##
##   - `motors`: the four motors in plan, nose up, Betaflight numbering, each with the spin the MIXER
##     flies (`MotorLayout.spin_map`) as an arrow; a diagonal pair that disagrees is drawn red.
##   - `ports`: the board's UARTs as slots, filled in the demand's order. Slots are not UART numbers.
##   - `failsafe`: link lost → stage 2's action, and what that action needs fitted.
##   - `rates`: stick deflection against rotation rate, straight, as the sim flies it; the sim's own
##     line too when this aircraft's differs. No expo curve: its shape depends on the radio.
##   - `sheet`: the sheet's four settings with whose each is, and its count of flags.

const MODE_MOTORS := "motors"
const MODE_PORTS := "ports"
const MODE_FAILSAFE := "failsafe"
const MODE_RATES := "rates"
const MODE_SHEET := "sheet"
const MODES := [MODE_MOTORS, MODE_PORTS, MODE_FAILSAFE, MODE_RATES, MODE_SHEET]

var mode := ""
## motors: `ConfigFigures.spin_check` — {spin, net, broken}.
var spin_check: Dictionary = {}
## ports: `ConfigFigures.uart_slots`.
var uart: Dictionary = {}
## failsafe: stage 2's label, whether the build can carry it out, what it needs, the ESC protocol.
var stage2_label := ""
var failsafe_ok := true
var failsafe_needs := ""
var bidir_on := false
var esc_protocol := ""
## rates: full-stick °/s, this aircraft's and the sim's.
var rate_set := 0.0
var rate_sim := 0.0
## sheet: `ConfigFigures.sheet_settings` and the flag count.
var settings: Array = []
var flags := 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func show_build(build: Build, p_mode: String) -> void:
	mode = p_mode
	spin_check = {}
	uart = {}
	settings = []
	if build == null:
		queue_redraw()
		return
	match mode:
		MODE_MOTORS:
			spin_check = ConfigFigures.spin_check(build)
		MODE_PORTS:
			uart = ConfigFigures.uart_slots(build)
		MODE_FAILSAFE:
			var stage2 := FailsafeSettings.stage2(build.config)
			stage2_label = FailsafeSettings.label_for(stage2)
			failsafe_ok = ConfigFigures.failsafe_can_run(build)
			failsafe_needs = "a GPS" if stage2 == FailsafeSettings.GPS_RESCUE else ""
			bidir_on = FailsafeSettings.bidir_dshot(build.config)
			esc_protocol = ConfigFigures.esc_protocol(build)
		MODE_RATES:
			rate_set = ConfigFigures.set_rate_deg_s(build)
			rate_sim = ConfigFigures.sim_rate_deg_s()
		MODE_SHEET:
			settings = ConfigFigures.sheet_settings(build)
			flags = ConfigFigures.sheet_flag_count(build)
	queue_redraw()


## Where a motor sits in the plan drawing, unit square, nose up: front motors at y = -1, right at
## x = +1 (MotorLayout.IS_FRONT / IS_RIGHT, so the drawing and the mixer name the same corner).
static func plan_corner(motor_name: String) -> Vector2:
	return Vector2(1.0 if MotorLayout.IS_RIGHT[motor_name] else -1.0,
		-1.0 if MotorLayout.IS_FRONT[motor_name] else 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match mode:
		MODE_MOTORS:
			if not spin_check.is_empty():
				_draw_motors()
		MODE_PORTS:
			if not uart.is_empty():
				_draw_ports()
		MODE_FAILSAFE:
			_draw_failsafe()
		MODE_RATES:
			_draw_rates()
		MODE_SHEET:
			_draw_sheet()


func _draw_motors() -> void:
	_text(Vector2(16.0, 22.0), "Plan · nose up · as the mixer spins them", LothalTheme.TEXT_MUTED)
	var centre := size * 0.5 + Vector2(0.0, 10.0)
	var half := minf(size.x, size.y - 60.0) * 0.28
	var radius := half * 0.45
	var spin: Dictionary = spin_check["spin"]
	var broken: Array = spin_check["broken"]
	# The frame: two diagonals, a pair that disagrees in red.
	for pair in ConfigPlausibility.DIAGONALS:
		var bad := broken.has("%s/%s" % [pair[0], pair[1]])
		draw_line(centre + plan_corner(pair[0]) * half, centre + plan_corner(pair[1]) * half,
			LothalTheme.DANGER if bad else LothalTheme.BORDER, 3.0 if bad else 2.0)
	# The nose.
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -half * 0.55),
		centre + Vector2(-9, -half * 0.35), centre + Vector2(9, -half * 0.35)]), LothalTheme.ACCENT)
	_text(centre + Vector2(-14, -half * 0.62), "nose", LothalTheme.TEXT_MUTED)
	for motor_name in MotorLayout.MOTOR_NAMES:
		var at := centre + plan_corner(motor_name) * half
		var cw := float(spin[motor_name]) > 0.0
		var colour := LothalTheme.ACCENT if cw else LothalTheme.WARNING
		draw_arc(at, radius, 0.0, TAU, 48, LothalTheme.BORDER, 1.0, true)
		# The arrow: an arc of 270° ending in a head pointing along the turn (screen y is down, so a
		# clockwise-from-above turn is increasing angle on screen).
		var start := -PI * 0.5
		var sweep := PI * 1.5 * (1.0 if cw else -1.0)
		draw_arc(at, radius * 0.8, start, start + sweep, 40, colour, 3.0, true)
		var end_angle := start + sweep
		var tip := at + Vector2(cos(end_angle), sin(end_angle)) * radius * 0.8
		var tangent := Vector2(-sin(end_angle), cos(end_angle)) * (1.0 if cw else -1.0)
		var normal := Vector2(cos(end_angle), sin(end_angle))
		draw_colored_polygon(PackedVector2Array([tip + tangent * 10.0, tip - tangent * 2.0 + normal * 7.0,
			tip - tangent * 2.0 - normal * 7.0]), colour)
		_text(at + Vector2(-12, 5), motor_name, LothalTheme.TEXT_MAIN)
		var label := MotorLayout.direction_name(float(spin[motor_name]))
		var side := 1.0 if MotorLayout.IS_RIGHT[motor_name] else -1.0
		_text(at + Vector2(side * (radius + 8.0), 5.0), label, colour, side < 0.0)
	var net := roundi(float(spin_check["net"]))
	_text(Vector2(16.0, size.y - 16.0), "Net yaw torque at equal throttle: %s" % (
		"0 · cancels" if net == 0 else "%+d motors' worth" % net),
		LothalTheme.TEXT_MAIN if net == 0 else LothalTheme.DANGER)


func _draw_ports() -> void:
	var slots: Array = uart["slots"]
	var over: Array = uart["over"]
	_text(Vector2(16.0, 22.0), "Board UARTs · filled in order, not by UART number",
		LothalTheme.TEXT_MUTED)
	var top := 50.0
	var row_h := 34.0
	var width := minf(size.x - 32.0, 360.0)
	if not bool(uart["known"]):
		_text(Vector2(16.0, top + 20.0), "Board's UART count: unpublished", LothalTheme.WARNING)
		var listed_y := top + 50.0
		for part in uart["parts"]:
			_slot(Rect2(16.0, listed_y, width, row_h - 6.0), str(part), LothalTheme.BORDER, false)
			listed_y += row_h
		return
	var y := top
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var part := str(slot["part"])
		var text := part if part != "" else "free"
		if bool(slot["maybe"]):
			text += "  · if the board has it"
		_slot(Rect2(16.0, y, width, row_h - 6.0), text,
			LothalTheme.WARNING if bool(slot["maybe"]) and part != "" else
				(LothalTheme.ACCENT if part != "" else LothalTheme.BORDER), bool(slot["maybe"]))
		y += row_h
	for part in over:
		_slot(Rect2(16.0, y, width, row_h - 6.0), "%s  · no UART left" % part, LothalTheme.DANGER,
			false)
		y += row_h


func _slot(rect: Rect2, text: String, colour: Color, dashed: bool) -> void:
	if dashed:
		for side in [[rect.position, rect.position + Vector2(rect.size.x, 0)],
				[rect.position + Vector2(0, rect.size.y), rect.end],
				[rect.position, rect.position + Vector2(0, rect.size.y)],
				[rect.position + Vector2(rect.size.x, 0), rect.end]]:
			draw_dashed_line(side[0], side[1], colour, 1.5, 6.0)
	else:
		draw_rect(rect, colour, false, 2.0)
	_text(rect.position + Vector2(10.0, rect.size.y * 0.5 + 5.0), text, LothalTheme.TEXT_MAIN)


func _draw_failsafe() -> void:
	_text(Vector2(16.0, 22.0), "When the radio link drops", LothalTheme.TEXT_MUTED)
	var w := minf(size.x - 32.0, 360.0)
	var lost := Rect2(16.0, 50.0, w, 36.0)
	var action := Rect2(16.0, 120.0, w, 36.0)
	draw_rect(lost, LothalTheme.BORDER, false, 2.0)
	_text(lost.position + Vector2(10, 23), "Link lost", LothalTheme.TEXT_MAIN)
	draw_line(Vector2(40.0, lost.end.y), Vector2(40.0, action.position.y - 4.0), LothalTheme.BORDER, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(40, action.position.y), Vector2(34, action.position.y - 10),
		Vector2(46, action.position.y - 10)]), LothalTheme.BORDER)
	draw_rect(action, LothalTheme.ACCENT if failsafe_ok else LothalTheme.WARNING, false, 2.0)
	_text(action.position + Vector2(10, 23), "Stage 2: %s" % stage2_label, LothalTheme.TEXT_MAIN)
	var needs := "Needs nothing fitted" if failsafe_needs == "" else (
		"Needs %s · %s" % [failsafe_needs, "fitted" if failsafe_ok else "not fitted"])
	_text(Vector2(16.0, action.end.y + 26.0), needs,
		LothalTheme.TEXT_MUTED if failsafe_ok else LothalTheme.WARNING)
	_text(Vector2(16.0, action.end.y + 56.0), "Bidirectional DShot %s · ESC %s" % [
		"on" if bidir_on else "off", esc_protocol if esc_protocol != "" else "protocol unpublished"],
		LothalTheme.TEXT_MUTED)


func _draw_rates() -> void:
	_text(Vector2(16.0, 22.0), "Stick against rotation · every axis · straight, as the sim flies",
		LothalTheme.TEXT_MUTED)
	var plot := Rect2(64.0, 48.0, maxf(size.x - 96.0, 40.0), maxf(size.y - 110.0, 40.0))
	var top := maxf(maxf(rate_set, rate_sim), 1.0) * 1.15
	draw_line(plot.position + Vector2(0, plot.size.y), plot.end, LothalTheme.BORDER, 1.5)
	draw_line(plot.position, plot.position + Vector2(0, plot.size.y), LothalTheme.BORDER, 1.5)
	_text(Vector2(plot.position.x, plot.end.y + 22.0), "centre", LothalTheme.TEXT_MUTED)
	_text(Vector2(plot.end.x, plot.end.y + 22.0), "full stick", LothalTheme.TEXT_MUTED, true)
	_text(Vector2(8.0, plot.position.y + 10.0), "°/s", LothalTheme.TEXT_MUTED)
	var differs := absf(rate_set - rate_sim) >= RateSettings.SAME_RATE_EPSILON_DEG_S
	if differs:
		var sim_end := Vector2(plot.end.x, plot.end.y - plot.size.y * rate_sim / top)
		draw_dashed_line(Vector2(plot.position.x, plot.end.y), sim_end, LothalTheme.TEXT_FAINT, 2.0, 8.0)
		_text(sim_end + Vector2(-6.0, -8.0 if rate_sim > rate_set else 18.0),
			"sim %d°/s" % roundi(rate_sim), LothalTheme.TEXT_MUTED, true)
	var end := Vector2(plot.end.x, plot.end.y - plot.size.y * rate_set / top)
	draw_line(Vector2(plot.position.x, plot.end.y), end, LothalTheme.ACCENT, 3.0, true)
	draw_circle(end, 5.0, LothalTheme.ACCENT)
	_text(end + Vector2(-6.0, (-8.0 if not differs or rate_set >= rate_sim else 18.0)),
		"%d°/s" % roundi(rate_set), LothalTheme.TEXT_MAIN, true)


func _draw_sheet() -> void:
	_text(Vector2(16.0, 22.0), "What the sheet states · and whose each figure is", LothalTheme.TEXT_MUTED)
	var y := 60.0
	var w := minf(size.x - 32.0, 420.0)
	for setting in settings:
		var yours := str(setting["whose"]) == ConfigFigures.YOURS
		draw_line(Vector2(16.0, y + 10.0), Vector2(16.0 + w, y + 10.0), LothalTheme.BORDER, 1.0)
		_text(Vector2(16.0, y), str(setting["name"]), LothalTheme.TEXT_MAIN)
		_text(Vector2(16.0 + w * 0.5, y), str(setting["value"]), LothalTheme.TEXT_MAIN)
		_text(Vector2(16.0 + w, y), ("✓ " if yours else "") + str(setting["whose"]),
			LothalTheme.ACCENT if yours else LothalTheme.WARNING, true)
		y += 34.0
	_text(Vector2(16.0, y + 16.0), "%d %s on the sheet" % [flags, "flag" if flags == 1 else "flags"],
		LothalTheme.TEXT_MAIN if flags == 0 else LothalTheme.WARNING)


func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)
