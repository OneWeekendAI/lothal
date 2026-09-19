class_name FrameLayoutShelf
extends ScrollContainer
## The Airframe room's left column: the layouts you can start from, and the frames you have saved.
##
## ## Why a shelf of DIAGRAMS and not a list of names
##
## "Hex V" and "Hex I" are the same three words to anybody who has not built one, and the
## difference between them — whether an arm points forward or a gap does — is the single decision
## that determines how the aircraft flies and what it can carry. Every flight-controller manual in
## existence therefore shows the picture and treats the name as a caption, and this shelf does the
## same: a chip is a drawing of the arms with each motor's rotation on it, at a size you can read
## across a room, and the name sits underneath as confirmation rather than as the content.
##
## The diagrams are drawn from `FrameLayouts.TEMPLATES` — the same angles the generator builds from
## — so a chip cannot show a topology the button does not produce. That is the room's standing rule
## applied to its own furniture: no second description of the same thing.
##
## ## What a chip does NOT carry
##
## No size, no mass, no vendor, no propeller. A layout is a topology, and every one of these chips
## makes a 3" or a 10" aircraft depending on what the controls column then says. That is why this
## shelf replaced the frame picker in this room: the picker's job is choosing a product to fly, and
## in here nobody has an aircraft yet.

## Emitted when a layout chip is clicked, with the `FrameLayouts` id.
signal layout_chosen(layout_id: String)
## Emitted when one of the builder's saved frames is clicked, with its path.
signal frame_chosen(path: String)

const COLUMN_WIDTH := 168.0
const CHIP_HEIGHT := 92.0


var _content: VBoxContainer
var _saved_box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)

	_content.add_child(_heading("Start from"))
	for entry in FrameLayouts.TEMPLATES:
		_content.add_child(_chip(entry))

	_content.add_child(_heading("Your frames"))
	_saved_box = VBoxContainer.new()
	_saved_box.add_theme_constant_override("separation", 2)
	_content.add_child(_saved_box)
	refresh_saved()


## Rebuilds the saved list off disk.
##
## Off DISK rather than from a cache, and rebuilt on every open, for `FrameLibrary`'s own reason: it
## is a directory of readable JSON, so a frame can appear in it because somebody copied a file in
## — and a list built once at startup would not know.
func refresh_saved() -> void:
	for child in _saved_box.get_children():
		child.queue_free()
	var entries := FrameLibrary.entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Nothing saved yet."
		empty.theme_type_variation = &"SmallLabel"
		empty.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
		_saved_box.add_child(empty)
		return
	for entry in entries:
		var button := Button.new()
		button.text = str(entry["name"])
		button.tooltip_text = "%d plates" % int(entry["plates"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		var path := str(entry["path"])
		button.pressed.connect(func() -> void: frame_chosen.emit(path))
		_saved_box.add_child(button)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	return label


func _chip(entry: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	button.tooltip_text = "%d arms, %d motors" % [
		(entry["arms"] as Array).size(),
		(entry["arms"] as Array).size() * int(entry.get("motors_per_arm", 1))]
	var layout_id := str(entry["id"])
	button.pressed.connect(func() -> void: layout_chosen.emit(layout_id))

	var diagram := LayoutDiagram.new(entry)
	diagram.set_anchors_preset(Control.PRESET_FULL_RECT)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(diagram)
	return button


## The picture on a chip: the arms at their real angles, with a ring per motor showing which way it
## turns and a caption underneath.
##
## Its own class rather than a `_draw` on the shelf because a Control does not clip its own drawing
## and does not know where its siblings are — nine diagrams painted by one node would be nine
## coordinate systems maintained by hand, and the first one to go wrong would draw a hexacopter
## across the quad above it.
class LayoutDiagram extends Control:
	const ARM_COLOUR := Color(0.72, 0.74, 0.78, 0.9)

	var entry: Dictionary

	func _init(p_entry: Dictionary) -> void:
		entry = p_entry

	func _draw() -> void:
		var arms: Array = entry.get("arms", [])
		if arms.is_empty():
			return
		var caption_height := 16.0
		var centre := Vector2(size.x * 0.5, (size.y - caption_height) * 0.5)
		var radius := minf(size.x, size.y - caption_height) * 0.36
		var coaxial := int(entry.get("motors_per_arm", 1)) > 1

		# The body: a disc, not a drawn plate. A chip is a topology and a centre plate is a shape
		# the builder has not chosen yet — drawing a square here would be this file inventing
		# geometry, which is the one thing the room forbids.
		draw_circle(centre, radius * 0.28, Color(ARM_COLOUR, 0.35))

		for slot in arms.size():
			var angle := deg_to_rad(float(arms[slot]))
			var tip := centre + Vector2(cos(angle), sin(angle)) * radius
			draw_line(centre, tip, ARM_COLOUR, 2.0)
			# Spin, as the same filled/hollow ring the plan canvas uses, so the two pictures of the
			# same property are one picture. Clockwise is filled.
			var clockwise := slot % 2 == 0
			var colour := LothalTheme.SUCCESS if clockwise else LothalTheme.WARNING
			draw_arc(tip, 6.0, 0.0, TAU, 20, colour, 2.0)
			if clockwise:
				draw_circle(tip, 2.5, colour)
			if coaxial:
				# A coaxial pair is two motors on one mast, so it is drawn as a second ring behind
				# the first rather than as a second arm — which is what it is.
				draw_arc(tip, 9.5, 0.0, TAU, 20,
					LothalTheme.WARNING if clockwise else LothalTheme.SUCCESS, 1.0)

		draw_string(LothalTheme.draw_font(), Vector2(0.0, size.y - 3.0),
			str(entry.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, size.x,
			LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MAIN)
