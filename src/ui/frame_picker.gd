class_name FramePicker
extends PartPicker
## Lab's frame rail. Everything about how a rail behaves lives in PartPicker — read its header
## for the two rules that matter. This file is only the three axes a builder actually browses a
## frame catalog along, and the frame-shaped names for the generic surface.

## Each reads from the part's `catalog` block — browsing metadata, deliberately kept out of
## `specs`, which is reserved for fields the physics reads (see frames.json's _schema).
const FILTER_KEYS := [
	{"key": "frame_type", "label": "Type"},
	{"key": "size_class", "label": "Size"},
	{"key": "material", "label": "Material"},
]

signal frame_selected(frame: Dictionary)
signal custom_frames_changed()

var _delete_button: Button

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "frame", "FRAMES", "frame", FILTER_KEYS)
	part_selected.connect(func(frame: Dictionary) -> void: frame_selected.emit(frame))

	# The authoring entry point, on the frame rail because a frame is what this slice lets a
	# builder enter. It is a BUTTON on the existing rail rather than a new screen, for the reason
	# PartPicker's header gives about parallel surfaces: a second place to browse frames from is a
	# second thing that can disagree about what a frame is.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom frame…"
	new_button.pressed.connect(_open_dialog)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_delete_selected)
	buttons.add_child(_delete_button)
	add_custom_buttons(buttons)
	part_selected.connect(func(_frame: Dictionary) -> void: _refresh_delete_button())
	_refresh_delete_button()

func visible_frames() -> Array:
	return visible_parts()

func selected_frame() -> Dictionary:
	return selected_part()


## Delete is only meaningful on a frame the builder owns. Disabled rather than hidden on a catalog
## frame, so the rail does not reflow every time the selection moves.
func _refresh_delete_button() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	_delete_button.disabled = not PartsCatalog.is_custom(part_id)


func _open_dialog() -> void:
	var dialog := CustomFrameDialog.new()
	dialog.frame_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_frames_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return
	var document := CustomFrames.load_from()
	if document.remove(part_id):
		document.save()
		custom_frames_changed.emit()
