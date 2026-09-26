class_name PropellerShelf
extends ScrollContainer
## The propulsion room's left column: the blades you can start from, and the blades you have drawn.
##
## ## Why the chips are DIAGRAMS
##
## The airframe shelf's argument, one system over and slightly stronger. "5x4.3x3" and "5x5.5x3"
## are the same five characters to a builder who has not flown both, and the difference between
## them — how much blade there is, and where — is the whole of what this room edits. So a chip is
## the blade's own planform silhouette, drawn from `PropellerDocument.chord_at()`, with the name
## underneath as confirmation.
##
## Drawn from the document rather than from a stored thumbnail, which is the same rule the rest of
## P10d holds to: a chip cannot show a planform the room does not open.
##
## ## What a chip does not carry
##
## No mass, no vendor, no price, and no thrust. A blade's thrust is a property of the motor turning
## it and the air it is turning in, and putting a number here would be this shelf answering a
## question that belongs to the bench.

## Emitted when a catalog preset is chosen, with its `part_id`.
signal preset_chosen(part_id: String)
## Emitted when one of the builder's saved blades is chosen, with its path.
signal blade_chosen(path: String)

const COLUMN_WIDTH := 168.0
const CHIP_HEIGHT := 78.0

var _content: VBoxContainer
var _saved_box: VBoxContainer
var _catalog: PartsCatalog


func _init(p_catalog: PartsCatalog = null) -> void:
	_catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)

	_content.add_child(_heading("Start from"))
	# `list_category` returns the RECORDS, not their ids — so the chip is built from the entry the
	# catalog already parsed rather than from a second lookup that could miss.
	for prop in _catalog.list_category("propeller"):
		_content.add_child(_chip(prop as Dictionary))

	_content.add_child(_heading("Your blades"))
	_saved_box = VBoxContainer.new()
	_saved_box.add_theme_constant_override("separation", 2)
	_content.add_child(_saved_box)
	refresh_saved()


## Rebuilds the saved list off DISK on every open, on `FrameLayoutShelf.refresh_saved`'s reason: a
## blade can appear in the directory because somebody copied a file in, and a list built once at
## startup would not know.
func refresh_saved() -> void:
	for child in _saved_box.get_children():
		_saved_box.remove_child(child)
		child.queue_free()
	var entries := BladeLibrary.entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Nothing drawn yet."
		empty.theme_type_variation = &"SmallLabel"
		empty.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
		_saved_box.add_child(empty)
		return
	for entry in entries:
		var button := Button.new()
		button.text = str(entry["name"])
		button.tooltip_text = "%.0f mm, %d blades" % [
			float(entry["diameter_mm"]), int(entry["blades"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		var path := str(entry["path"])
		button.pressed.connect(func() -> void: blade_chosen.emit(path))
		_saved_box.add_child(button)


## How many preset chips the shelf is carrying. Public so a test can assert the shelf shows the
## catalog rather than a hardcoded list — an empty shelf that looked tidy would otherwise pass.
func preset_count() -> int:
	var count := 0
	for child in _content.get_children():
		if child is PropellerShelfChip:
			count += 1
	return count


func _chip(prop: Dictionary) -> Control:
	var part_id := str(prop.get("part_id", ""))
	var chip := PropellerShelfChip.new(PropellerDocument.from_catalog_prop(prop),
		str(prop.get("name", part_id)))
	chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	chip.pressed.connect(func() -> void: preset_chosen.emit(part_id))
	return chip


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	return label
