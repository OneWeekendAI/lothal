class_name FrameDetails
extends PartDetails
## The frame panel. All the machinery is PartDetails' — read its header. This file is the
## frame's own published figures and the units they are quoted in.

## key -> label. The key is the path into the part dictionary, resolved in _read().
const SPEC_ROWS := [
	{"key": "frame_type", "label": "Type"},
	{"key": "size_class", "label": "Built around"},
	{"key": "material", "label": "Material"},
	{"key": "mass_g", "label": "Frame mass"},
	{"key": "arm_mm", "label": "Arm (centre→motor)"},
	{"key": "max_prop_inches", "label": "Max prop"},
	{"key": "motor_mount", "label": "Motor mount"},
]

func _init() -> void:
	super(SPEC_ROWS)

func _read(frame: Dictionary, key: String) -> String:
	var specs: Dictionary = frame.get("specs", {})

	match key:
		"mass_g":
			return "%.0f g" % float(frame.get("mass_g", 0.0))
		"arm_mm":
			return "%.0f mm" % float(specs.get("arm_mm", 0.0))
		"max_prop_inches":
			return "%.1f\"" % float(specs.get("max_prop_inches", 0.0))
		"motor_mount":
			return _or_dash(str(specs.get("motor_mount", "")))
	return super(frame, key)
