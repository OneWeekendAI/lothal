class_name DsFlightControls
extends PanelContainer
## The Sim's flight controls as a quiet Design Space strip: one button per action with its key hint.
## Each button calls the SAME handler its key calls: `ACTIONS` is the one table both read, the key by
## keycode (`Main._physics_process`) and the button by `bind`. Nothing here holds state.
##
## id, label, key hint, keycode, handler method on the Sim scene. Flight mode keeps Space.
const ACTIONS := [
	["pause", "Pause", "P", KEY_P, "toggle_pause"],
	["reset", "Reset", "B", KEY_B, "_restart_course"],
	["respawn", "Respawn", "G", KEY_G, "_respawn_after_crash"],
	["view", "Chase / FPV", "C", KEY_C, "_toggle_fpv"],
	["mode", "Flight mode", "Space", KEY_SPACE, "_toggle_flight_mode"],
	["listener", "Listener", "L", KEY_L, "_toggle_listener"],
	["record", "Record", "R", KEY_R, "_toggle_recording"],
]

var buttons: Dictionary = {}


func _init() -> void:
	name = "DsFlightControls"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var box := DsUi.panel_style()
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.content_margin_left = 8
	box.content_margin_right = 8
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	add_child(row)
	for a in ACTIONS:
		var b := DsUi.button("%s  %s" % [a[1], a[2]], a[0] == "pause" or a[0] == "record")
		b.name = String(a[0])
		# Keys drive the flight; a focused button must not also eat Space.
		b.focus_mode = Control.FOCUS_NONE
		row.add_child(b)
		buttons[a[0]] = b


## Connects every button to the handler of the same name on `target`.
func bind(target: Object) -> void:
	for a in ACTIONS:
		var b: Button = buttons[a[0]]
		b.pressed.connect(Callable(target, a[4]))


## Lights the two toggles to the state they report.
func show_state(paused: bool, recording: bool) -> void:
	buttons["pause"].set_pressed_no_signal(paused)
	buttons["record"].set_pressed_no_signal(recording)
