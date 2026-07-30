class_name BatteryPicker
extends PartPicker
## Lab's battery rail. All behaviour is PartPicker's — read its header. This file is only the
## four axes a builder browses packs along.
##
## Cell count leads, because it is the one property that changes everything downstream: pack
## voltage sets the RPM ceiling (max_RPM = KV * live voltage), so a 6S pack under a motor wound
## for 4S is a different aircraft rather than a longer-lasting one. Chemistry is next, and it is
## the axis this rail exists to make visible — a Li-ion is not a big LiPo, it is a pack that
## trades sag for capacity, and putting the two side by side under the same filter is how that
## reads as a choice. C-rating and connector come last: the first is the pack's own claim about
## how hard it can be pushed, the second is the only thing on this list that can stop you flying
## tonight.
##
## Chemistry reads from `specs` rather than `catalog`, because it is physics-bearing — it selects
## the open-circuit discharge curve (physics.md §5). See PartPicker's header for why that is
## declared here rather than solved by copying the field into both blocks.

const FILTER_KEYS := [
	{"key": "cell_class", "label": "Cells"},
	{"key": "chemistry", "label": "Chemistry", "block": "specs"},
	{"key": "c_rating", "label": "C-rating"},
	{"key": "connector", "label": "Connector"},
]

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "battery", "BATTERIES", "battery", FILTER_KEYS)
