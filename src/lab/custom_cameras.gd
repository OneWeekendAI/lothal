class_name CustomCameras
extends CustomComponents
## The FPV cameras a builder entered themselves. Read CustomComponents for everything these four
## categories share, and CustomParts for the id space and the document.
##
## What is specific to a camera is one line of browsing metadata: whether it is analog or digital,
## and what size class it is. Neither reaches the physics — nothing in Lothal renders through this
## camera — and both are in `catalog` for that reason.

const CAMERAS_KEY := "cameras"


func array_key() -> String:
	return CAMERAS_KEY


func category() -> String:
	return "camera"


func cameras() -> Array:
	return records()


func get_camera(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomCameras:
	var document := CustomCameras.new()
	document.read_from(path)
	return document


static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, signal_kind: String, size_class: String, sensor: String,
		source: String) -> Dictionary:
	return component_record(id_for(name), name, "camera", mass_g, length_mm, width_mm, height_mm,
		{"signal": signal_kind, "size_class": size_class, "sensor": sensor}, source)


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "camera")
