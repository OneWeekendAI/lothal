class_name ChargeChip
extends HBoxContainer
## A calm one-line readout of the selected battery's charge, with a small plug button that charges
## it: "4S 1500mAh · 62%" and a plug. Pressing the plug counts the percentage up over CHARGE_S,
## the plug pulses and the text reads "Charging 74%"; at 100% the plug is dimmed and disabled.
##
## The chip owns no storage: it is told the pack and how much is used (`set_pack`), and says when a
## charge has finished (`charged`) so the owner writes PackCharge. Outside a tree there is no
## animation: the charge completes at once, which keeps the headless tests exact.

signal charged(part_id: String)

const CHARGE_S := 3.0

var part_id := ""
var pack_text := ""
var capacity_mah := 0.0
var used_mah := 0.0
var label: Label
var plug: PlugButton

var _charging := false
## How many plug redraws were requested (tests read this).
var redraw_requests := 0
var _t := 0.0
var _from_frac := 0.0


func _init() -> void:
	name = "ChargeChip"
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.name = "ChargeText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	add_child(label)
	plug = PlugButton.new()
	plug.name = "Plug"
	plug.pressed.connect(start_charge)
	add_child(plug)
	visible = false
	set_process(false)


## Shows `pack` (text such as "4S 1500mAh") with `used` of `capacity` mAh gone. An empty id hides.
func set_pack(p_id: String, p_text: String, capacity: float, used: float) -> void:
	if _charging and p_id == part_id:
		return
	_charging = false
	set_process(false)
	part_id = p_id
	pack_text = p_text
	capacity_mah = capacity
	used_mah = clampf(used, 0.0, maxf(capacity, 0.0))
	visible = p_id != "" and capacity > 0.0
	_refresh()


func clear_pack() -> void:
	set_pack("", "", 0.0, 0.0)


func is_charging() -> bool:
	return _charging


func fraction() -> float:
	if capacity_mah <= 0.0:
		return 1.0
	return 1.0 - used_mah / capacity_mah


## Whole percent as shown: never 100 until the pack is actually full.
func percent() -> int:
	var f := fraction()
	if used_mah <= 0.0:
		return 100
	return clampi(roundi(f * 100.0), 0, 99)


func start_charge() -> void:
	if part_id == "" or _charging or used_mah <= 0.0:
		return
	if not is_inside_tree():
		_finish()
		return
	_charging = true
	_t = 0.0
	_from_frac = fraction()
	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	step(delta)
	if _charging:
		redraw_requests += 1
		plug.queue_redraw()


func step(delta: float) -> void:
	if not _charging:
		return
	_t = minf(_t + delta, CHARGE_S)
	var e := 0.5 - 0.5 * cos(PI * _t / CHARGE_S)
	used_mah = capacity_mah * (1.0 - lerpf(_from_frac, 1.0, e))
	if _t >= CHARGE_S:
		_finish()
	else:
		_refresh()


func _finish() -> void:
	_charging = false
	used_mah = 0.0
	set_process(false)
	_refresh()
	charged.emit(part_id)


func _refresh() -> void:
	if _charging:
		label.text = "Charging %d%%" % percent()
	else:
		label.text = "%s · %d%%" % [pack_text, percent()]
	var full := used_mah <= 0.0
	label.add_theme_color_override("font_color",
		LothalTheme.ACCENT if _charging else (LothalTheme.TEXT_FAINT if full else LothalTheme.TEXT_MUTED))
	plug.disabled = full and not _charging
	plug.charging = _charging
	plug.tooltip_text = "Fully charged" if full and not _charging else ("Charging" if _charging else "Charge this pack")
	plug.queue_redraw()
