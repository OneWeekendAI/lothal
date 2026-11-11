class_name FlightsSheet
extends Control
## The Flights drawer (M13): Studio, the log reader, as a sheet over the Design Space beside Field and
## Mission. Same chrome as the Part sheet (dim backdrop, one window, Back), the StudioScreen filling it.
##
## Reading a flight never builds a `Build` (StudioScreen's own rule, guarded by a source check in
## test_flight_recorder); this sheet adds nothing that could: it hosts the screen and closes.

signal closed

const MARGIN_X := 36
const MARGIN_Y := 24

var studio: StudioScreen
var window: PanelContainer
var title_label: Label


## `library` is injectable (a test hands over a temp directory); null reads the builder's real flights.
func _init(library: FlightLogLibrary = null) -> void:
	name = "FlightsSheet"
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.color = Color(0.0, 0.0, 0.0, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	window = PanelContainer.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = MARGIN_X
	window.offset_right = -MARGIN_X
	window.offset_top = MARGIN_Y
	window.offset_bottom = -MARGIN_Y
	window.add_theme_stylebox_override("panel", DsUi.panel_style())
	add_child(window)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	window.add_child(root)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	root.add_child(bar)
	var back := DsUi.button("‹  Back")
	back.name = "Back"
	back.pressed.connect(close)
	bar.add_child(back)
	title_label = DsUi.label("Flights", DsUi.INK, LothalTheme.FONT_SIZE_TITLE)
	title_label.name = "Title"
	bar.add_child(title_label)
	var body := Control.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	root.add_child(body)
	studio = StudioScreen.new(library if library != null else FlightLogLibrary.load_from())
	studio.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(studio)


func close() -> void:
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
