class_name CustomAntennas
extends CustomComponents
## The video antennas a builder entered themselves. Read CustomComponents for everything these four
## categories share, and CustomParts for the id space and the document.
##
## Of the four, this is the one where the DIMENSIONS matter most and are most often left off a
## product page. An antenna is the longest and least dense thing on the aircraft — a 95 mm whip is
## longer than the reference build's centre plate is wide — so the stand-in cube the missing-
## dimension refusal exists to prevent would be wrong here by more than it is anywhere else. The
## refusal is CustomComponents'; the reason it earns its keep is this category.
const ANTENNAS_KEY := "antennas"


func array_key() -> String:
	return ANTENNAS_KEY


func category() -> String:
	return "antenna"


func antennas() -> Array:
	return records()


func get_antenna(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomAntennas:
	var document := CustomAntennas.new()
	document.read_from(path)
	return document


static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, polarisation: String, connector: String, gain_class: String,
		source: String) -> Dictionary:
	return component_record(id_for(name), name, "antenna", mass_g, length_mm, width_mm, height_mm,
		{"polarisation": polarisation, "connector": connector, "gain_class": gain_class}, source)


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "antenna")
