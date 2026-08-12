class_name CustomVtxs
extends CustomComponents
## The video transmitters a builder entered themselves. Read CustomComponents for everything these
## four categories share, and CustomParts for the id space and the document.
##
## Output power is asked for and is browsing metadata only. Lothal has no radio model and nothing
## computes a link budget, so a power figure in `specs` would be a claim that the sim reads it —
## the same line vtxs.json's `_schema` takes, and worth repeating on the form a builder fills in,
## because "does turning it up cost me anything" is a reasonable thing to expect of a design
## workbench and the honest answer today is that it costs mass and nothing else.
const VTXS_KEY := "vtxs"


func array_key() -> String:
	return VTXS_KEY


func category() -> String:
	return "vtx"


func noun() -> String:
	return "video transmitter"


func vtxs() -> Array:
	return records()


func get_vtx(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomVtxs:
	var document := CustomVtxs.new()
	document.read_from(path)
	return document


static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, signal_kind: String, power_class: String, band: String,
		source: String) -> Dictionary:
	return component_record(id_for(name), name, "vtx", mass_g, length_mm, width_mm, height_mm,
		{"signal": signal_kind, "power_class": power_class, "band": band}, source)


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "vtx")
