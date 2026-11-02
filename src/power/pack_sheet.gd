class_name PackSheet
extends RefCounted
## The buy-and-build sheet for a designed pack: what cells to buy, how many, how to join them, what
## wire and plug to put on it, the balance lead, and the figures to expect. Plain text, to copy or to
## save, in the spirit of the Airframe build sheet (BuildSheet).
##
## A pure function of the design. Every number is read from PackDesign.derive() or the cell; the only
## words typed here are instructions. Figures are ideal / datasheet (a legacy pack's are "typed
## figures", and the sheet says so instead): nothing here is a measurement of a real pack.

const BALANCE_CONNECTOR := "JST-XH"


## The sheet as data. Keys: name, label, arrangement, cells {model, chemistry, count, mah_each, form,
## source, basis, typed}, wiring_order (strings), busbar_note, lead {awg, length_mm, conductors,
## mass_g}, connector {family, note}, balance_lead {pins, connector, text}, expected (derive()), safety.
static func compose(design: PackDesign) -> Dictionary:
	var f := design.derive()
	var legacy := design.is_legacy()
	var s := _series(design)
	var p := 1 if legacy else clampi(design.parallel, PackDesign.P_RANGE.x, PackDesign.P_RANGE.y)
	var chem := design.chemistry()
	var cell := design.cell
	var cs: Dictionary = cell.get("specs", {})
	var count := s * p
	var cylindrical := String(cell.get("form", "pouch")) == "cylindrical" and not legacy
	var lead_mass := float((f.get("mass_parts", {}) as Dictionary).get("lead", 0.0))
	return {
		"name": design.name,
		"label": String(f.get("basis", PackDesign.BASIS)),
		"arrangement": "%dS%dP" % [s, p],
		"cells": {
			"model": "typed figures (no cell datasheet)" if legacy else String(cell.get("name", "custom cell")),
			"chemistry": chem,
			"count": count,
			"mah_each": float(f.get("mah", 0.0)) / float(p) if legacy else float(cs.get("mah", 0.0)),
			"form": "pouch" if legacy else String(cell.get("form", "pouch")),
			"source": "figures typed by hand" if legacy else String(cell.get("source", "")),
			"basis": "typed" if legacy else String(cell.get("basis", "")),
			"typed": legacy or String(cell.get("basis", "")) == "custom",
		},
		"wiring_order": _wiring_order(s, p),
		"busbar_note": _busbar_note(cylindrical, float(f.get("cont_a", 0.0))),
		"lead": {
			"awg": design.lead_awg,
			"length_mm": design.lead_length_mm,
			"conductors": PackDesign.PIGTAIL_CONDUCTORS,
			"mass_g": lead_mass,
		},
		"connector": {
			"family": design.connector_family,
			"note": "Fit the pack half of the %s connector (the aircraft half is on the drone)." % design.connector_family,
		},
		"balance_lead": {
			"pins": s + 1,
			"connector": BALANCE_CONNECTOR,
			"text": "%d-pin %s balance lead: one wire on the pack's negative, one on each of the %d junctions between cells in order, and one on the positive." % [s + 1, BALANCE_CONNECTOR, maxi(s - 1, 0)],
		},
		"expected": f,
		"safety": _safety(chem, legacy, String(f.get("basis", PackDesign.BASIS))),
	}


static func to_text(design: PackDesign) -> String:
	var d := compose(design)
	var c: Dictionary = d["cells"]
	var f: Dictionary = d["expected"]
	var dims: Vector3 = f.get("dims_mm", Vector3.ZERO)
	var lines: PackedStringArray = []
	lines.append("PACK BUILD SHEET: %s" % String(d["name"]))
	lines.append("Figures are %s, not measured." % String(d["label"]))
	lines.append("")
	lines.append("CELLS TO BUY")
	lines.append("  %d x %s (%s, %s, %.0f mAh each)" % [int(c["count"]), String(c["model"]),
		String(c["chemistry"]), String(c["form"]), float(c["mah_each"])])
	lines.append("  Layout: %s" % String(d["arrangement"]))
	if String(c["source"]) != "":
		lines.append("  Source: %s" % String(c["source"]))
	lines.append("")
	lines.append("ARRANGEMENT AND WIRING ORDER")
	for step in d["wiring_order"]:
		lines.append("  %s" % String(step))
	lines.append("  %s" % String(d["busbar_note"]))
	lines.append("")
	lines.append("LEAD AND CONNECTOR")
	var lead: Dictionary = d["lead"]
	lines.append("  Lead: %d AWG silicone wire, %.0f mm, %d conductors (red positive, black negative), about %.1f g." % [
		int(lead["awg"]), float(lead["length_mm"]), int(lead["conductors"]), float(lead["mass_g"])])
	lines.append("  Connector: %s. %s" % [String((d["connector"] as Dictionary)["family"]), String((d["connector"] as Dictionary)["note"])])
	lines.append("")
	lines.append("BALANCE LEAD")
	lines.append("  %s" % String((d["balance_lead"] as Dictionary)["text"]))
	lines.append("")
	lines.append("EXPECTED FIGURES (%s)" % String(d["label"]))
	lines.append("  Voltage: %.1f V nominal, %.1f V full, %.1f V empty" % [
		float(f["nominal_v"]), float(f["full_v"]), float(f["empty_v"])])
	lines.append("  Capacity: %.0f mAh, %.1f Wh" % [float(f["mah"]), float(f["wh"])])
	lines.append("  Mass: about %.0f g (the wrap and solder allowance is an estimate)" % float(f["mass_g"]))
	lines.append("  Size: %.0f x %.0f x %.0f mm" % [dims.x, dims.y, dims.z])
	lines.append("  Current: %.0f A steady, %.0f A burst%s" % [float(f["cont_a"]), float(f["burst_a"]),
		" (est.)" if bool(f.get("burst_estimated", false)) else ""])
	lines.append("  Internal resistance: %.0f mOhm" % (float(f["internal_r_ohm"]) * 1000.0))
	lines.append("")
	lines.append("SAFETY")
	for line in d["safety"]:
		lines.append("  - %s" % String(line))
	return "\n".join(lines) + "\n"


static func _series(design: PackDesign) -> int:
	if design.is_legacy():
		return maxi(int(design.legacy_specs.get("cells", design.series)), 1)
	return clampi(design.series, PackDesign.S_RANGE.x, PackDesign.S_RANGE.y)


static func _wiring_order(s: int, p: int) -> Array:
	var out: Array = []
	if p == 1:
		out.append("%dS1P: %d cells in series" % [s, s])
		out.append("1. Check every cell reads the same voltage (within 0.05 V) before joining anything.")
		out.append("2. Join the cells one after another, positive of one to negative of the next, %d joints in all." % maxi(s - 1, 0))
	else:
		out.append("%dS%dP: %d cells in series, %d in parallel at each step (%d cells)" % [s, p, s, p, s * p])
		out.append("1. Check every cell reads the same voltage (within 0.05 V) before joining anything.")
		out.append("2. Join the %d cells of each step in parallel first (all positives together, all negatives together)." % p)
		out.append("3. Join the %d steps in series, positive of one step to negative of the next." % s)
	out.append("%d. Solder the balance lead, then the main lead, then wrap the pack." % (out.size()))
	return out


static func _busbar_note(cylindrical: bool, cont_a: float) -> String:
	if cylindrical:
		return "Busbar: join round cells with pure nickel strip, spot-welded; size and stack the strip for the pack's %.0f A steady current, and use more layers if unsure." % cont_a
	return "Busbar: pouch cells are joined tab to tab with short, thick solder joints or copper strip, kept brief so the tabs do not overheat; most builders buy ready-made pouch packs instead."


static func _safety(chem: String, typed: bool, basis: String = PackDesign.BASIS) -> Array:
	return [
		"Lithium cells can start a fire. Build and charge on a fireproof surface, away from anything that burns, and never leave a charging pack alone.",
		"Check polarity at every joint before connecting; a short circuit can ignite a cell.",
		"Charge only with a charger set for %s, at no more than %.1fC, and stop at %.2f V per cell." % [
			chem, BatteryModel.max_charge_c(chem), BatteryModel.max_cell_v(chem)],
		"Never discharge below %.2f V per cell, and stop using a puffed, dented or hot cell." % BatteryModel.min_cell_v(chem),
		"These figures were typed by hand, not taken from a cell datasheet; check them against the real pack." if typed
			else "These figures are %s values for the cells named; a real pack built by hand will differ." % basis,
	]
