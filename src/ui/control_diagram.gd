class_name ControlDiagram
extends Control
## The drawing on the Flight controller, Receiver & link and Tune item pages (lab dock design §2,
## §3) — PowerDiagram's sibling. Read-only; every figure comes from `ControlFigures` or the
## `RateTune` in force, the same calls the row, the page's two numbers and the sheet read.
##
##   - `fc`: the stack in plan — the frame's hole square and each board's (FC, ESC), to scale, in
##     red where a board's pattern is not the frame's — and the board's serial ports as slots: the
##     parts that use one, the board's count (solid to the low end of a class range, dashed across
##     the range, `~`), and any part past the high end in red.
##   - `link`: where each link bay lands on the flight controller (UART or beeper pad), with its
##     name and mass, the GPS's mast and whether the buzzer has its own cell; an empty bay dashed.
##     No range is drawn: no receiver publishes the figures one needs.
##   - `tune`: per axis, the gains in force beside the derived ones; and each axis's D against the
##     gyro's noise ceiling (`RateTune.kd_ceiling`).

const MODE_FC := "fc"
const MODE_LINK := "link"
const MODE_TUNE := "tune"

## Slot states on the FC's port strip.
const SLOT_USED := "used"
const SLOT_EMPTY := "empty"
## Past the low end of a class range and within its high end: the board may or may not have it.
const SLOT_MAYBE := "maybe"
## A part past the board's high end: it does not fit on either figure.
const SLOT_OVER := "over"

var mode := ""

# FC
## Millimetres: `{frame, fc, esc}` → Vector2 (ZERO where the pattern is unreadable).
var stack: Dictionary = {}
var stack_text: Dictionary = {}
## `{label, state}` per slot, left to right.
var slots: Array = []
var ports_caption := ""

# Link
var wiring: Array = []

# Tune
## `{axis, in_force: Vector3, derived: Vector3, overridden}` per axis.
var gains: Array = []
var kd_ceiling := INF


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func show_build(build: Build, p_mode: String, tune: RateTune = null) -> void:
	mode = p_mode
	stack = {}
	stack_text = {}
	slots = []
	wiring = []
	gains = []
	kd_ceiling = INF
	ports_caption = ""
	if build == null:
		queue_redraw()
		return
	match mode:
		MODE_FC:
			stack_text = ControlFigures.stack_patterns(build)
			for key in stack_text:
				stack[key] = ControlFigures.pattern_mm(str(stack_text[key]))
			_fill_slots(build)
		MODE_LINK:
			wiring = ControlFigures.link_wiring(build)
		MODE_TUNE:
			if tune != null:
				kd_ceiling = tune.kd_ceiling
				for axis in 3:
					gains.append({"axis": str(RateTune.AXIS_NAMES[axis]).capitalize(),
						"in_force": tune.gains_for(axis), "derived": tune.derived_gains_for(axis),
						"overridden": tune.is_overridden(axis)})
	queue_redraw()


func _fill_slots(build: Build) -> void:
	var parts := ControlFigures.serial_parts(build)
	var supply := ControlFigures.port_supply(build)
	var published := String(supply["provenance"]) != PortBudget.UNPUBLISHED
	var low := int(supply["low"])
	var high := int(supply["high"])
	var count := maxi(parts.size(), high) if published else parts.size()
	for i in count:
		var label := kind_of(str((parts[i] as Dictionary)["category"])) if i < parts.size() else ""
		var state := SLOT_EMPTY
		if not published:
			state = SLOT_USED
		elif i >= high:
			state = SLOT_OVER
		elif i < parts.size():
			state = SLOT_USED
		elif i >= low:
			state = SLOT_MAYBE
		slots.append({"label": label, "state": state})
	var figure := ControlFigures.ports_figure(build)
	if not published:
		ports_caption = "%d want a UART · this board's count is not published" % parts.size()
	elif String(supply["provenance"]) == PortBudget.TYPED:
		ports_caption = "%d of %s UARTs · your count for this board" % [parts.size(), figure]
	else:
		ports_caption = "%d of %s UARTs · class-typical range, not this board's" % [parts.size(),
			figure]


## A serial part's kind as a slot names it: a 110 px slot truncates a catalogue name, and the
## sheet and the Link page carry the names.
static func kind_of(category: String) -> String:
	match category:
		"receiver":
			return "Receiver"
		"gps":
			return "GPS"
		"vtx":
			return "VTX"
		"esc":
			return "ESC telemetry"
		"buzzer":
			return "Buzzer"
	return category.capitalize()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match mode:
		MODE_FC:
			_draw_fc()
		MODE_LINK:
			_draw_link()
		MODE_TUNE:
			_draw_tune()


# ---------------------------------------------------------------------------
# Flight controller: the stack in plan, and the ports
# ---------------------------------------------------------------------------

## The stack's square in the upper part, the port strip under it.
func _draw_fc() -> void:
	var strip_h := 96.0
	var plan := Rect2(Vector2(16.0, 34.0), Vector2(size.x - 32.0, size.y - 34.0 - strip_h - 40.0))
	_text(Vector2(16.0, 20.0), "The stack in plan · hole centres, mm", LothalTheme.TEXT_MUTED)
	_draw_stack(plan)
	_draw_ports(Rect2(Vector2(16.0, size.y - strip_h - 16.0), Vector2(size.x - 32.0, strip_h)))


func _draw_stack(plan: Rect2) -> void:
	var frame_mm: Vector2 = stack.get("frame", Vector2.ZERO)
	var widest := 0.0
	for key in stack:
		widest = maxf(widest, maxf((stack[key] as Vector2).x, (stack[key] as Vector2).y))
	if widest <= 0.0 or plan.size.y < 60.0:
		return
	var side := minf(plan.size.x, plan.size.y) * 0.5
	var px_per_mm := side / widest
	var centre := plan.get_center()
	# The frame's holes first, as rings; each board's pattern over it. Where a board's pattern IS
	# the frame's the holes coincide, and saying so is the whole content of the drawing.
	var boards := [{"key": "fc", "name": "FC", "colour": LothalTheme.ACCENT},
		{"key": "esc", "name": "ESC", "colour": LothalTheme.TEXT_MAIN}]
	if frame_mm != Vector2.ZERO:
		var half := frame_mm * px_per_mm * 0.5
		draw_rect(Rect2(centre - half, half * 2.0), Color(LothalTheme.BORDER_STRONG, 0.5), false, 1.0)
		for corner in _corners(centre, half):
			draw_arc(corner, 9.0, 0.0, TAU, 24, LothalTheme.TEXT_MUTED, 1.5)
		# The dimension, along the top edge.
		var y := centre.y + half.y + 20.0
		draw_line(Vector2(centre.x - half.x, y), Vector2(centre.x + half.x, y), LothalTheme.TEXT_MUTED, 1.0)
		for x in [centre.x - half.x, centre.x + half.x]:
			draw_line(Vector2(x, y - 4.0), Vector2(x, y + 4.0), LothalTheme.TEXT_MUTED, 1.0)
		_text(Vector2(centre.x - 20.0, y + 16.0), "%s mm" % _trim(frame_mm.x), LothalTheme.TEXT_MUTED)
	var legend_y := plan.position.y + 16.0
	var legend := [["frame %s" % str(stack_text.get("frame", "—")), LothalTheme.TEXT_MUTED]]
	for i in boards.size():
		var board: Dictionary = boards[i]
		var mm: Vector2 = stack.get(board["key"], Vector2.ZERO)
		if mm == Vector2.ZERO:
			continue
		var fits := frame_mm == Vector2.ZERO or mm == frame_mm
		var colour: Color = board["colour"] if fits else LothalTheme.DANGER
		var half: Vector2 = mm * px_per_mm * 0.5
		# A small offset per board so two coincident patterns both read, as a stack does in side view.
		for corner in _corners(centre, half):
			draw_circle(corner + Vector2(0.0, 0.0), 4.5 - 1.5 * i, colour)
		var word := "on the frame's holes" if fits else "does not bolt to this frame"
		legend.append(["%s %s · %s" % [board["name"], str(stack_text.get(board["key"], "")), word], colour])
	for entry in legend:
		_text(Vector2(plan.end.x - 4.0, legend_y), str(entry[0]), entry[1], true)
		legend_y += 16.0


func _draw_ports(strip: Rect2) -> void:
	_text(strip.position + Vector2(0.0, 12.0), "Serial ports (UARTs)", LothalTheme.TEXT_MUTED)
	if slots.is_empty():
		_text(strip.position + Vector2(0.0, 40.0), "No fitted part needs a UART", LothalTheme.TEXT_MUTED)
		return
	var gap := 8.0
	var slot_w := minf(120.0, (strip.size.x - gap * float(slots.size() - 1)) / float(slots.size()))
	var slot_h := 34.0
	var top := strip.position.y + 22.0
	var font := LothalTheme.draw_font()
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var rect := Rect2(Vector2(strip.position.x + float(i) * (slot_w + gap), top), Vector2(slot_w, slot_h))
		var state := str(slot["state"])
		match state:
			SLOT_USED:
				draw_rect(rect, LothalTheme.ACCENT_FILL)
				draw_rect(rect, LothalTheme.ACCENT, false, 1.5)
			SLOT_OVER:
				draw_rect(rect, Color(LothalTheme.DANGER, 0.14))
				draw_rect(rect, LothalTheme.DANGER, false, 1.5)
			SLOT_EMPTY:
				draw_rect(rect, LothalTheme.TEXT_MUTED, false, 1.0)
			SLOT_MAYBE:
				_dashed_rect(rect, LothalTheme.TEXT_FAINT)
		var label := str(slot["label"])
		if label == "" and state == SLOT_MAYBE:
			label = "maybe"
		var colour := LothalTheme.TEXT_MAIN if state == SLOT_USED else (LothalTheme.DANGER \
			if state == SLOT_OVER else LothalTheme.TEXT_FAINT)
		draw_string(font, rect.position + Vector2(6.0, 21.0), label, HORIZONTAL_ALIGNMENT_LEFT,
			slot_w - 10.0, LothalTheme.FONT_SIZE_SMALL, colour, TextServer.JUSTIFICATION_NONE)
	_text(Vector2(strip.position.x, top + slot_h + 20.0), ports_caption, LothalTheme.TEXT_MUTED)


# ---------------------------------------------------------------------------
# Receiver & link: where each bay lands on the board
# ---------------------------------------------------------------------------

func _draw_link() -> void:
	if wiring.is_empty():
		return
	_text(Vector2(16.0, 20.0), "Where the link lands on the flight controller", LothalTheme.TEXT_MUTED)
	var fc := Rect2(Vector2(size.x - 150.0, 50.0), Vector2(120.0, maxf(size.y - 110.0, 120.0)))
	draw_rect(fc, LothalTheme.PANEL_SUNKEN)
	draw_rect(fc, LothalTheme.BORDER_STRONG, false, 1.5)
	_text(fc.position + Vector2(10.0, 20.0), "Flight controller", LothalTheme.TEXT_MAIN)
	var row_h := minf((fc.size.y - 30.0) / float(wiring.size()), 110.0)
	var box_w := minf(230.0, fc.position.x - 110.0)
	for i in wiring.size():
		var bay: Dictionary = wiring[i]
		var cy := fc.position.y + 40.0 + row_h * (float(i) + 0.5)
		var box := Rect2(Vector2(16.0, cy - 26.0), Vector2(box_w, 52.0))
		var fitted := bool(bay["fitted"])
		var title := kind_of(str(bay["category"]))
		if fitted:
			draw_rect(box, LothalTheme.ACCENT_FILL)
			draw_rect(box, LothalTheme.ACCENT, false, 1.5)
			_text(box.position + Vector2(8.0, 18.0), "%s · %.1f g" % [title, float(bay["mass_g"])],
				LothalTheme.TEXT_MAIN)
			_text(box.position + Vector2(8.0, 38.0), str(bay["name"]), LothalTheme.TEXT_MUTED)
			var wire := LothalTheme.ACCENT
			draw_line(Vector2(box.end.x, cy), Vector2(fc.position.x, cy), wire, 2.0)
			draw_circle(Vector2(fc.position.x, cy), 4.0, wire)
			_text(Vector2(fc.position.x - 8.0, cy - 8.0), str(bay["lands"]), wire, true)
			var note := str(bay["note"])
			if note != "":
				var warn := note.contains("dies")
				_text(Vector2(fc.position.x - 8.0, cy + 18.0), note,
					LothalTheme.WARNING if warn else LothalTheme.TEXT_MUTED, true)
		else:
			_dashed_rect(box, LothalTheme.TEXT_FAINT)
			_text(box.position + Vector2(8.0, 30.0), "%s · not fitted" % title, LothalTheme.TEXT_FAINT)
	_text(Vector2(16.0, size.y - 14.0), "No range: no receiver here publishes power or sensitivity",
		LothalTheme.TEXT_FAINT)


# ---------------------------------------------------------------------------
# Tune: the gains, and D against the gyro's noise ceiling
# ---------------------------------------------------------------------------

func _draw_tune() -> void:
	if gains.is_empty():
		return
	var font := LothalTheme.draw_font()
	# The gains table: axis, P, I, D in force, and the derived triple beside it where they differ.
	_text(Vector2(16.0, 20.0), "Gains in force · derived from this airframe's plant", LothalTheme.TEXT_MUTED)
	var cols := [16.0, 96.0, 176.0, 256.0]
	var y := 46.0
	for i in 3:
		_text(Vector2(cols[i + 1], y), ["P", "I", "D"][i], LothalTheme.TEXT_MUTED)
	for row in gains:
		y += 22.0
		var in_force: Vector3 = row["in_force"]
		var derived: Vector3 = row["derived"]
		var colour := LothalTheme.WARNING if bool(row["overridden"]) else LothalTheme.TEXT_MAIN
		draw_string(font, Vector2(cols[0], y), str(row["axis"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			LothalTheme.FONT_SIZE_BODY, LothalTheme.TEXT_MAIN)
		for i in 3:
			draw_string(font, Vector2(cols[i + 1], y), _gain(in_force[i], i), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, LothalTheme.FONT_SIZE_BODY, colour)
		var tail := "by hand · derived %s / %s / %s" % [_gain(derived.x, 0), _gain(derived.y, 1),
			_gain(derived.z, 2)] if bool(row["overridden"]) else "derived"
		_text(Vector2(cols[3] + 70.0, y), tail, colour if bool(row["overridden"]) else LothalTheme.TEXT_FAINT)

	# D against the ceiling, one bar per axis.
	var top := y + 44.0
	var plot := Rect2(Vector2(70.0, top + 22.0), Vector2(size.x - 70.0 - 40.0,
		minf(size.y - top - 22.0 - 52.0, 3.0 * 56.0)))
	if plot.size.y < 60.0 or plot.size.x < 120.0:
		return
	_text(Vector2(16.0, top), "D against the gyro's noise ceiling", LothalTheme.TEXT_MUTED)
	var most := 0.0
	for row in gains:
		most = maxf(most, maxf((row["in_force"] as Vector3).z, (row["derived"] as Vector3).z))
	if is_finite(kd_ceiling):
		most = maxf(most, kd_ceiling)
	if most <= 0.0:
		return
	most *= 1.15
	var to_x := func(kd: float) -> float: return plot.position.x + kd / most * plot.size.x
	var grid := Color(LothalTheme.BORDER, 0.6)
	var step := PropulsionDiagram._round_step(most / 5.0)
	var v := 0.0
	while v <= most:
		var gx: float = to_x.call(v)
		draw_line(Vector2(gx, plot.position.y), Vector2(gx, plot.end.y), grid, 1.0)
		_text(Vector2(gx - 12.0, plot.end.y + 16.0), _trim_gain(v), LothalTheme.TEXT_MUTED)
		v += step
	var row_h := minf(plot.size.y / 3.0, 56.0)
	var bar_h := minf(row_h * 0.45, 22.0)
	for i in gains.size():
		var row: Dictionary = gains[i]
		var cy := plot.position.y + row_h * (float(i) + 0.5)
		var kd := (row["in_force"] as Vector3).z
		_text(Vector2(16.0, cy + 4.0), str(row["axis"]), LothalTheme.TEXT_MAIN)
		if kd <= 0.0:
			_text(Vector2(plot.position.x + 6.0, cy + 4.0), "no D on this axis", LothalTheme.TEXT_FAINT)
			continue
		var over := is_finite(kd_ceiling) and kd > kd_ceiling
		var colour := LothalTheme.DANGER if over else LothalTheme.ACCENT
		var x_end: float = to_x.call(kd)
		draw_rect(Rect2(Vector2(plot.position.x, cy - bar_h * 0.5), Vector2(x_end - plot.position.x, bar_h)),
			colour)
		_text(Vector2(x_end + 6.0, cy + 4.0), _gain(kd, 2), colour)
		var derived_kd := (row["derived"] as Vector3).z
		if bool(row["overridden"]) and derived_kd > 0.0:
			var dx: float = to_x.call(derived_kd)
			draw_line(Vector2(dx, cy - bar_h * 0.8), Vector2(dx, cy + bar_h * 0.8), LothalTheme.TEXT_MAIN, 2.0)
	if is_finite(kd_ceiling):
		var cx: float = to_x.call(kd_ceiling)
		draw_line(Vector2(cx, plot.position.y - 6.0), Vector2(cx, plot.end.y), LothalTheme.WARNING, 1.5)
		_text(Vector2(cx - 4.0, plot.position.y - 8.0), "ceiling %s · %d%% of full stick on noise" % [
			_gain(kd_ceiling, 2), roundi(RateTune.D_NOISE_BUDGET * 100.0)], LothalTheme.WARNING, true)


static func _gain(value: float, index: int) -> String:
	return ["%.2f", "%.3f", "%.3f"][index] % value


static func _trim_gain(value: float) -> String:
	return ("%.3f" % value).rstrip("0").rstrip(".") if value > 0.0 else "0"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _corners(centre: Vector2, half: Vector2) -> Array:
	return [centre + Vector2(-half.x, -half.y), centre + Vector2(half.x, -half.y),
		centre + Vector2(half.x, half.y), centre + Vector2(-half.x, half.y)]


func _dashed_rect(rect: Rect2, colour: Color) -> void:
	var c := _corners(rect.get_center(), rect.size * 0.5)
	for i in 4:
		draw_dashed_line(c[i], c[(i + 1) % 4], colour, 1.0, 5.0)


## A label kept inside the canvas; `right` sets it to end at `at.x` instead of starting there.
func _text(at: Vector2, text: String, colour: Color, right := false) -> void:
	var font := LothalTheme.draw_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL).x
	var x := clampf(at.x - width if right else at.x, 4.0, maxf(4.0, size.x - width - 6.0))
	var height := font.get_height(LothalTheme.FONT_SIZE_SMALL)
	draw_rect(Rect2(Vector2(x - 2.0, at.y - font.get_ascent(LothalTheme.FONT_SIZE_SMALL) - 1.0),
		Vector2(width + 4.0, height + 2.0)), Color(LothalTheme.SURFACE_BASE, 0.85))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LothalTheme.FONT_SIZE_SMALL, colour)


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
