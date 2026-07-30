class_name PropellerDetails
extends PartDetails
## The propeller panel. All the machinery is PartDetails' — read its header.
##
## Diameter is listed first because thrust goes as D^4 and diameter therefore dominates every
## other number here (physics.md §4). Pitch is shown both in inches, as the catalog and the
## real world quote it, and as the blade angle it implies at the tip — which is the same figure
## PropellerMesh draws, so the twist on screen and the number in the panel are one thing.

const SPEC_ROWS := [
	{"key": "diameter_class", "label": "Diameter class"},
	{"key": "blade_count", "label": "Blades"},
	{"key": "intended_use", "label": "Intended for"},
	{"key": "material", "label": "Material"},
	{"key": "mass_g", "label": "Prop mass (each)"},
	{"key": "diameter_inches", "label": "Diameter"},
	{"key": "pitch_inches", "label": "Pitch"},
	{"key": "tip_angle", "label": "Blade angle at tip"},
]

func _init() -> void:
	super(SPEC_ROWS)

func _read(prop: Dictionary, key: String) -> String:
	var specs: Dictionary = prop.get("specs", {})

	match key:
		"mass_g":
			return "%.1f g" % float(prop.get("mass_g", 0.0))
		"diameter_inches":
			return "%.1f\"" % float(specs.get("diameter_inches", 0.0))
		"pitch_inches":
			return "%.1f\"" % float(specs.get("pitch_inches", 0.0))
		"tip_angle":
			var radius_m: float = float(specs.get("diameter_inches", 0.0)) * PropellerMesh.INCH_M * 0.5
			if radius_m <= 0.0:
				return "—"
			var pitch_m: float = float(specs.get("pitch_inches", 0.0)) * PropellerMesh.INCH_M
			return "%.1f°" % rad_to_deg(PropellerMesh.twist_angle_rad(pitch_m, radius_m))
	return super(prop, key)
