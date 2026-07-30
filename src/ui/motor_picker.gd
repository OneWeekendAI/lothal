class_name MotorPicker
extends PartPicker
## Lab's motor rail. All behaviour is PartPicker's — read its header. This file is only the
## three axes a builder browses motors along.
##
## Stator size, KV and intended use are the three questions in that order, because that is the
## order a real decision is made in: the stator class is set by the airframe you are building,
## KV is then set by the pack you intend to fly, and intended use is the sanity check on both.

const FILTER_KEYS := [
	{"key": "stator_class", "label": "Stator"},
	{"key": "kv_class", "label": "KV"},
	{"key": "intended_use", "label": "For"},
]

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "motor", "MOTORS", "motor", FILTER_KEYS)
