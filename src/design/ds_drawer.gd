class_name DsDrawer
extends PanelContainer
## A Design Space side drawer: the file dialog's box, a small-caps title with a close mark, then a column of content that
## scrolls when it is taller than the room (`content`). It sits at the left under the top bar, as the Parts shelf does, and
## `avoid_rect` tells the callout layout where it is so no callout chip lands on it.

signal closed

const LEFT := 12.0
const TOP := 104.0
const WIDTH := 320.0
const BOTTOM_ROOM := 124.0

var content: VBoxContainer
## Fixed under the scrolling content: the actions that must stay in reach.
var footer: VBoxContainer
var scroll: ScrollContainer
var close_button: Button
var title_label: Label


func _init(title := "") -> void:
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = LEFT
	offset_top = TOP
	offset_right = LEFT + WIDTH
	offset_bottom = TOP
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", DsUi.panel_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	title_label = DsUi.section(title)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title_label)
	close_button = DsUi.button("×")
	close_button.tooltip_text = "Close"
	close_button.pressed.connect(func() -> void:
		hide()
		closed.emit())
	head.add_child(close_button)
	v.add_child(head)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	v.add_child(footer)
	content.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	visibility_changed.connect(_fit)


func _max_h() -> float:
	var vp := get_viewport_rect().size.y if is_inside_tree() else 720.0
	return maxf(120.0, vp - TOP - BOTTOM_ROOM - 60.0 - footer.get_combined_minimum_size().y)


func _fit() -> void:
	scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 40.0, _max_h())


## The screen rect the drawer holds (px), from offsets and minimum sizes so it holds headless too.
func avoid_rect() -> Rect2:
	return Rect2(offset_left, offset_top, WIDTH, maxf(size.y, get_combined_minimum_size().y))
