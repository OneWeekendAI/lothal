class_name CustomReceivers
extends CustomComponents
## The radio receivers a builder entered themselves. Read CustomComponents for everything these
## four categories share, and CustomParts for the id space and the document.
##
## The lightest category in the catalog, and the one where a builder is most likely to ask why it
## is worth entering at all. Two grams is nothing on a 496 g freestyle build and it is a tenth of a
## real whoop — which is the whole argument of LTHL-11 restated at its smallest scale: a flat
## allowance is a rounding error at one size and the answer at another.
const RECEIVERS_KEY := "receivers"


func array_key() -> String:
	return RECEIVERS_KEY


func category() -> String:
	return "receiver"


func receivers() -> Array:
	return records()


func get_receiver(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomReceivers:
	var document := CustomReceivers.new()
	document.read_from(path)
	return document


static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, protocol: String, band: String, antenna_type: String,
		source: String) -> Dictionary:
	return component_record(id_for(name), name, "receiver", mass_g, length_mm, width_mm, height_mm,
		{"protocol": protocol, "band": band, "antenna_type": antenna_type}, source)


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "receiver")
