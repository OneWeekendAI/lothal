class_name PropellerPicker
extends PartPicker
## Lab's propeller rail. All behaviour is PartPicker's — read its header.
##
## Diameter leads, because thrust goes as D^4 and diameter therefore dominates every other
## property on the list (physics.md §4). Blade count is the next question and material the
## last, which is also roughly the order of how much each one changes the flying.

const FILTER_KEYS := [
	{"key": "diameter_class", "label": "Diameter"},
	{"key": "blade_count", "label": "Blades"},
	{"key": "intended_use", "label": "For"},
	{"key": "material", "label": "Material"},
]

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "propeller", "PROPELLERS", "propeller", FILTER_KEYS)
