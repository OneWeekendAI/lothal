class_name DsSetup
extends Control
## THE SETUP PAGES: the lab's sheets (frame, propulsion, power, control, video, printed, config) on
## a Design Space stage. The sheets are the same panels the lab always had (`lab.panels`, already
## in Design Space tokens); what is new is the frame around them: a hairline top row with
## "Back to the drone", the seven groups as buttons, and the group's pages as a second row. There
## is no system dropdown, no dock, no rail. Parts are chosen in the Design Space, not here.
##
## The Power group also holds the harness designer (`PowerWorkbench`), which fills the page area.

signal closed

## [group, [panel titles in LabScreen's tab bar]].
const GROUPS := [
	["Frame", ["Frame", "Structure", "Arms", "Fasteners", "Layout", "Straps", "Fit"]],
	["Propulsion", ["Motor", "Prop"]],
	["Power", ["Pack", "ESC", "Harness"]],
	["Control", ["FC", "Link", "Tune"]],
	["Video", ["Camera", "Electronics"]],
	["Printed", ["Print"]],
	["Config", ["Motors", "Ports", "Failsafe", "Rates", "Sheet"]],
]

var lab: LabScreen
var panels: TabContainer
var power_room: PowerWorkbench
var group := ""
var page := ""
var group_buttons := {}
var page_buttons: Array[Button] = []
var back_button: Button
var title_label: Label
var _pages_row: HBoxContainer
var _content: MarginContainer


func _init() -> void:
	name = "Setup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = DesignSpace.STAGE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_right = -24
	column.offset_top = 14
	column.offset_bottom = -16
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var top := HBoxContainer.new()
	top.name = "TopRow"
	top.add_theme_constant_override("separation", 6)
	column.add_child(top)
	back_button = DsUi.button("‹ Back to the drone")
	back_button.name = "Back"
	back_button.pressed.connect(func() -> void: closed.emit())
	top.add_child(back_button)
	title_label = DsUi.label("Setup", DsUi.INK, LothalTheme.FONT_SIZE_TITLE)
	title_label.custom_minimum_size = Vector2(110, 0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title_label)
	for entry in GROUPS:
		var name_: String = entry[0]
		var b := DsUi.button(name_, true)
		b.name = "Group_" + name_
		b.pressed.connect(show_page.bind(name_))
		group_buttons[name_] = b
		top.add_child(b)
	_pages_row = HBoxContainer.new()
	_pages_row.name = "PagesRow"
	_pages_row.add_theme_constant_override("separation", 6)
	column.add_child(_pages_row)
	column.add_child(DsUi.rule())
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_content)


## Takes the lab's sheets in. Called once, after the lab exists.
func adopt_panels(p_lab: LabScreen) -> void:
	lab = p_lab
	panels = lab.panels
	panels.get_parent().remove_child(panels)
	_content.add_child(panels)
	panels.tabs_visible = false
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels.visible = false
	for i in panels.get_tab_count():
		panels.set_tab_hidden(i, false)
	power_room = PowerWorkbench.new()
	power_room.visible = false
	power_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(power_room)
	power_room.document_changed.connect(func(_harness: Harness) -> void: lab.refresh_build())
	power_room.pack_offset_edited.connect(func(millimetres: float) -> void:
		lab.assembly_panel.set_tweak_mm(AssemblyTweaks.BATTERY_OFFSET, millimetres))


static func group_pages(group_name: String) -> Array:
	for entry in GROUPS:
		if entry[0] == group_name:
			return entry[1]
	return []


## Shows a group (its first page) or, given a panel title, that page of its group. "" = the last one.
func show_page(what := "") -> void:
	if what == "":
		what = page if page != "" else group if group != "" else String(GROUPS[0][0])
	var want_group := ""
	var want_page := ""
	for entry in GROUPS:
		if entry[0] == what:
			want_group = what
			want_page = String(entry[1][0])
		elif what in entry[1]:
			want_group = String(entry[0])
			want_page = what
	if want_group == "":
		push_warning("no such setup page: %s" % what)
		return
	group = want_group
	page = want_page
	power_room.visible = false
	panels.visible = true
	for i in panels.get_tab_count():
		if panels.get_tab_title(i) == page:
			panels.current_tab = i
	title_label.text = group
	for g in group_buttons:
		(group_buttons[g] as Button).set_pressed_no_signal(g == group)
	for b in page_buttons:
		_pages_row.remove_child(b)
		b.queue_free()
	page_buttons.clear()
	var titles := group_pages(group)
	if titles.size() > 1:
		for t in titles:
			var b := DsUi.button(String(t), true)
			b.name = "Page_" + String(t)
			b.set_pressed_no_signal(t == page)
			b.pressed.connect(show_page.bind(String(t)))
			_pages_row.add_child(b)
			page_buttons.append(b)


## The harness designer in the page area (the Harness sheet's door).
func show_harness_room() -> void:
	if lab == null:
		return
	show_page("Harness")
	power_room.set_build(lab.build_with_open_harness(), lab.tweaks, lab.frame_document)
	panels.visible = false
	power_room.visible = true


func harness_room_open() -> bool:
	return power_room != null and power_room.visible


## Leaving Setup: whatever is open goes away.
func leave() -> void:
	if panels != null:
		panels.visible = false
	if power_room != null:
		power_room.visible = false
