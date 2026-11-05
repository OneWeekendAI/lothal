class_name PropSheet
## The prop's making sheet: what a mould shop or a printer needs, every figure read from the same place
## the page reads it. `to_text` is both Copy specs and Save as .txt.

## Radius fractions in the station table run from here to the tip in this step.
const STATION_STEP := 0.05
const FLAT_NOTE := "Flat section: a solid rectangle, as the mass law and the blade view use. Usable, not an airfoil. A mould maker adds the airfoil from the station table."
const PRINT_NOTE := "To make: print or mould in the named material, balance the set before flying, and spin it up behind a guard first."


static func stations(doc: PropellerDocument) -> Array:
	var out: Array = []
	var f := PropellerDocument.HUB_RADIUS_TO_RADIUS
	while f <= 1.0 + 1e-9:
		var c := doc.chord_at(f)
		out.append({"radius_mm": f * doc.radius_mm(), "chord_mm": c,
			"angle_deg": rad_to_deg(doc.beta_rad(f)), "thickness_mm": c * doc.thickness_ratio})
		f += STATION_STEP
	return out


## {name, material, density, mass_g, hub_g, cg_mm, heavy_mg, balance_n, rpm, safe_rpm, safe_note, bore_mm, shaft_mm, solid_g, make, label}
static func compose(shell: PropDesigner) -> Dictionary:
	var doc := shell.doc
	var f := shell.figures()
	var solid := PropExport.build(doc, shell.bore_mm())
	var over := PropStructure.overspeed_rpm(doc, shell.materials, shell.rpm)
	var rho := shell.materials.density(doc.material_id)
	return {
		"name": doc.name, "material": String(shell.materials.get_material(doc.material_id).get("name", doc.material_id)),
		"density": rho, "mass_g": float(f.mass_g), "hub_g": shell.hub_g, "cg_mm": float(f.cg_mm),
		"heavy_mg": shell.structure.heavy_mg,
		"balance_n": BladeGeometry.imbalance_force_n(shell.structure.heavy_mg, float(f.cg_mm), shell.rpm),
		"rpm": shell.rpm, "safe_rpm": over, "bore_mm": shell.bore_mm(), "shaft_mm": shell.shaft_mm(),
		"solid_g": float(solid.solid_mm3) * rho * 1e-6, "make": String(solid.reason), "label": "ideal / model",
	}


static func to_text(shell: PropDesigner) -> String:
	var d := compose(shell)
	var doc := shell.doc
	var lines: PackedStringArray = []
	lines.append("PROP MAKING SHEET: %s" % String(d.name))
	lines.append("Figures are %s, not measured." % String(d.label))
	lines.append("")
	lines.append("Size: %.1f in x %.1f in pitch, %d blades" % [doc.diameter_mm / PropellerDocument.INCH_TO_MM, doc.pitch_mm / PropellerDocument.INCH_TO_MM, doc.blades])
	lines.append("Material: %s, %.0f kg/m3" % [String(d.material), float(d.density)])
	lines.append("Mass: %.2f g with a %.1f g hub (solid section)" % [float(d.mass_g), float(d.hub_g)])
	if float(d.solid_g) > 0.0:
		lines.append("STL solid at this density: %.2f g, with the bore taken out" % float(d.solid_g))
	lines.append("Bore: %.2f mm, for a %.2f mm shaft%s" % [float(d.bore_mm), float(d.shaft_mm), " (assumed, check your motor)" if shell.shaft_is_assumed() else ""])
	lines.append("Balance tolerance: %d mg on one blade, %.1f N at %d rpm" % [roundi(float(d.heavy_mg)), float(d.balance_n), roundi(float(d.rpm))])
	if float(d.safe_rpm) > 0.0:
		lines.append("Safe rpm: under %d (est.). Root section not measured." % roundi(float(d.safe_rpm)))
	else:
		lines.append("Safe rpm: no figure for this prop.")
	lines.append("")
	lines.append("STATIONS")
	lines.append("  radius mm | chord mm | angle deg | thickness mm")
	for s: Dictionary in stations(doc):
		lines.append("  %.2f | %.2f | %.2f | %.3f" % [float(s.radius_mm), float(s.chord_mm), float(s.angle_deg), float(s.thickness_mm)])
	lines.append("")
	lines.append(FLAT_NOTE)
	lines.append(PRINT_NOTE)
	if String(d.make) != "":
		lines.append("STL refused: %s" % String(d.make))
	return "\n".join(lines) + "\n"
