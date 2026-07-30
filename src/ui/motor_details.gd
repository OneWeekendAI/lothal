class_name MotorDetails
extends PartDetails
## The motor panel. All the machinery is PartDetails' — read its header.
##
## The row worth explaining is "Thrust measured on". A motor's headline thrust figure is
## meaningless without the propeller and pack it was measured with, and Build fits the thrust
## coefficient from exactly that pairing (physics.md §4). Showing it puts the provenance of the
## number on screen next to the number, which is the difference between a spec sheet and a
## claim. It is also the row that makes an over-propped build legible: when the max thrust says
## 1450 g and the pairing says a 5x4.3 on 4S, a 7" prop fitted to it is visibly not the test
## condition.

const SPEC_ROWS := [
	{"key": "stator_class", "label": "Stator class"},
	{"key": "kv_class", "label": "KV class"},
	{"key": "intended_use", "label": "Intended for"},
	{"key": "mass_g", "label": "Motor mass"},
	{"key": "kv", "label": "KV"},
	{"key": "stator", "label": "Stator (Ø × height)"},
	{"key": "max_thrust_g", "label": "Max thrust (each)"},
	{"key": "max_amps", "label": "Max current"},
	{"key": "poles", "label": "Poles"},
	{"key": "mount_pattern", "label": "Mount"},
	{"key": "thrust_test", "label": "Thrust measured on"},
]

var _catalog: PartsCatalog

## The catalog is held so the thrust_test row can name the propeller rather than its part_id —
## "5x4.3x3 at 14.8 V" is provenance a builder can read; "prop_5x43x3" is a database key.
func _init(p_catalog: PartsCatalog) -> void:
	_catalog = p_catalog
	super(SPEC_ROWS)

func _read(motor: Dictionary, key: String) -> String:
	var specs: Dictionary = motor.get("specs", {})

	match key:
		"mass_g":
			return "%.0f g" % float(motor.get("mass_g", 0.0))
		"kv":
			return "%.0f KV" % float(specs.get("kv", 0.0))
		"stator":
			return "%.0f × %.0f mm" % [
				float(specs.get("stator_diameter_mm", 0.0)), float(specs.get("stator_height_mm", 0.0))]
		"max_thrust_g":
			return "%.0f g" % float(specs.get("max_thrust_g", 0.0))
		"max_amps":
			return "%.0f A" % float(specs.get("max_amps", 0.0))
		"poles":
			return "%.0f" % float(specs.get("poles", 0.0))
		"mount_pattern":
			return _or_dash(str(motor.get("mount_pattern", "")))
		"thrust_test":
			var test: Dictionary = motor.get("thrust_test", {})
			var prop: Dictionary = _catalog.get_part(str(test.get("prop_id", "")))
			if prop.is_empty():
				return "—"
			return "%s at %.1f V" % [prop.get("name", "?"), float(test.get("voltage_v", 0.0))]
	return super(motor, key)
