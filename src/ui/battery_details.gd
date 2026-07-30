class_name BatteryDetails
extends PartDetails
## The battery panel. All the machinery is PartDetails' — read its header.
##
## Two rows here are not on the pack's label and are the ones worth explaining.
##
## "Energy" is capacity times voltage. Milliamp-hours alone is the number every pack is sold on
## and it is not comparable across cell counts: a 6S 1100 holds more energy than a 4S 1500, which
## is invisible if you only read the capacity. Watt-hours is what actually decides how long you
## fly, and putting it next to the mAh is the cheapest way to make that legible.
##
## "Sag at 30 A" is internal resistance stated as the thing it does. 15 mΩ is an abstraction;
## "0.45 V gone the moment you punch it" is a consequence, and the difference between a good LiPo
## and the Li-ion is a tenth of a volt against three volts. 30 A is a real punch current for a 5"
## quad rather than a derived figure — it is a fixed yardstick chosen so two packs can be compared
## at the same load, which is exactly what the battery bench then does properly against the motors
## actually fitted. It is a label, not a model: nothing reads it.

const SPEC_ROWS := [
	{"key": "cell_class", "label": "Cells"},
	{"key": "chemistry", "label": "Chemistry"},
	{"key": "c_rating", "label": "C-rating"},
	{"key": "connector", "label": "Connector"},
	{"key": "mass_g", "label": "Pack mass"},
	{"key": "nominal_v", "label": "Nominal voltage"},
	{"key": "mah", "label": "Capacity"},
	{"key": "energy_wh", "label": "Energy"},
	{"key": "internal_r_ohm", "label": "Internal resistance"},
	{"key": "sag_at_30a", "label": "Sag at 30 A"},
]

## The reference punch current the sag row is quoted at. See the header: a yardstick, not a model.
const SAG_REFERENCE_A := 30.0

func _init() -> void:
	super(SPEC_ROWS)

func _read(battery: Dictionary, key: String) -> String:
	var specs: Dictionary = battery.get("specs", {})

	match key:
		"chemistry":
			return _or_dash(str(specs.get("chemistry", "")))
		"mass_g":
			return "%.0f g" % float(battery.get("mass_g", 0.0))
		"nominal_v":
			return "%.1f V" % float(specs.get("nominal_v", 0.0))
		"mah":
			return "%.0f mAh" % float(specs.get("mah", 0.0))
		"energy_wh":
			return "%.1f Wh" % (float(specs.get("nominal_v", 0.0)) * float(specs.get("mah", 0.0)) / 1000.0)
		"internal_r_ohm":
			return "%.0f mΩ" % (float(specs.get("internal_r_ohm", 0.0)) * 1000.0)
		"sag_at_30a":
			return "−%.2f V" % (float(specs.get("internal_r_ohm", 0.0)) * SAG_REFERENCE_A)
	return super(battery, key)
