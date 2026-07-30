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

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "frame", "FRAMES", "frame", FILTER_KEYS)
	part_selected.connect(func(frame: Dictionary) -> void: frame_selected.emit(frame))

func visible_frames() -> Array:
	return visible_parts()

func selected_frame() -> Dictionary:
	return selected_part()
