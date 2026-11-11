class_name PartSheet
extends Control
## The Part sheet: one part's sheet over the Design Space, with a tab strip. The Parts drawer is the
## one place a build is edited; what used to be a room of its own (the Airframe plan editor, the
## blade designer, ...) is a tab here, built by `PartSheetTabs.build` the first time it is shown.
##
## A dimmed backdrop, one window, a bar (Back, the part's name, the tabs) and the tab's control
## filling the rest. Esc and Back close it. It edits through the DesignSpace it was opened over, so
## the undo history is the session's and survives the sheet closing.

signal closed

const MARGIN_X := 36
const MARGIN_Y := 24

var category := ""
var ds: DesignSpace
var window: PanelContainer
var tab_bar: HBoxContainer
var title_label: Label
var status_label: Label
var body: Control
var tab_buttons := {}
var current_tab := ""
var _built := {}


func _init(p_ds: DesignSpace, p_category: String) -> void:
	ds = p_ds
	category = p_category
	name = "PartSheet"
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
	title_label = DsUi.label(_title(), DsUi.INK, LothalTheme.FONT_SIZE_TITLE)
	title_label.name = "Title"
	bar.add_child(title_label)
	tab_bar = HBoxContainer.new()
	tab_bar.name = "Tabs"
	tab_bar.add_theme_constant_override("separation", 4)
	bar.add_child(tab_bar)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)
	status_label = DsUi.label("", DsUi.INK_MUTED)
	status_label.name = "Status"
	bar.add_child(status_label)
	body = Control.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	root.add_child(body)
	for t in PartSheetTabs.for_category(category):
		var b := DsUi.button(String(t["label"]), true)
		b.name = "Tab_" + String(t["id"])
		var id := String(t["id"])
		b.pressed.connect(func(): show_tab(id))
		tab_bar.add_child(b)
		tab_buttons[id] = b


func _title() -> String:
	var id := String(ds.session.selection.get(category, ""))
	var part: Dictionary = ds._catalog.get_part(id)
	var label := String(part.get("name", id))
	return label if label != "" else category.capitalize()


## The tab ids this sheet has, in order.
func tab_ids() -> Array:
	return tab_buttons.keys()


## Shows one tab (building it the first time). False for an id the sheet does not have.
func show_tab(tab_id: String) -> bool:
	if not tab_buttons.has(tab_id):
		return false
	if not _built.has(tab_id):
		var c := PartSheetTabs.build(category, tab_id, ds, self)
		if c == null:
			return false
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(c)
		_built[tab_id] = c
	for id in _built:
		(_built[id] as Control).visible = id == tab_id
	for id in tab_buttons:
		(tab_buttons[id] as Button).set_pressed_no_signal(id == tab_id)
	current_tab = tab_id
	return true


## The control of a tab already built (null if it has not been shown).
func tab(tab_id: String) -> Control:
	return _built.get(tab_id)


func set_status(text: String) -> void:
	status_label.text = text


func close() -> void:
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
