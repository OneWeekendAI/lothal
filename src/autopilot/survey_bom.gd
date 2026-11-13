extends RefCounted
## Per-part bill of materials for a survey-kit build (cross-check phase C). Preloaded (no class_name):
## const SurveyBom = preload("res://src/autopilot/survey_bom.gd").
## Rows come from the Build's OWN mass_parts() (the list the sim sums into total_mass_kg), so they reconcile with the flown mass by
## construction: the four "Motor + prop" lumps become one motor row and one prop row of qty 4; harness leads stay one row each;
## the single "Payload" lump is split into the add-on parts SurveyKitBuilds.make reports in payload_items.
## Power: the camera and RTK rows carry SurveyKitBuilds' payload load (sensor published, RTK estimated); FC / receiver / VTX carry
## the build's avionics_breakdown (estimated). A part whose power the model does not book has power_w empty.

const COLUMNS := ["variant", "role", "part_id", "part_name", "qty", "unit_mass_g", "total_mass_g", "power_w", "source_tag", "source_note"]
const VARIANTS := {
	"base": {"sensor": "rededge_p", "pack": "15"},
	"base_remote_id": {"sensor": "rededge_p", "pack": "15", "remote_id": true},
	"base_rgb": {"sensor": "rededge_p", "pack": "15", "rgb_addon": true},
	"base_rtk_off": {"sensor": "rededge_p", "pack": "15", "rtk": false},
	"sentera": {"sensor": "sentera_6x", "pack": "15"},
	"sentera_remote_id": {"sensor": "sentera_6x", "pack": "15", "remote_id": true},
	"pack10": {"sensor": "rededge_p", "pack": "10"},
	"pack20": {"sensor": "rededge_p", "pack": "20"},
	"pack25": {"sensor": "rededge_p", "pack": "25"},
	"pack6s10": {"sensor": "rededge_p", "pack": "6s10"},
	"pack6s15": {"sensor": "rededge_p", "pack": "6s15"},
}
const COMPONENT_ROLE := {"camera": "camera kit", "gps": "RTK GNSS", "vtx": "FPV video (VTX)", "antenna": "FPV antenna", "receiver": "RC receiver"}
const HARNESS_LABELS := ["Connector", "Main lead", "Capacitor", "Harness remainder"]


static func _tag(part: Dictionary) -> Array:
	var src := String(part.get("source", ""))
	var tag := "PUBLISHED" if src.contains("PUBLISHED") else ("ESTIMATED" if src.contains("ESTIMATED") else "unverified")
	var url := ""
	var at := src.find("https://")
	if at >= 0:
		url = src.substr(at).split(" ")[0].rstrip(",;)")
	if src.contains("PUBLISHED") and src.contains("ESTIMATED"):
		tag = "PUBLISHED+ESTIMATED"
	return [tag, url if url != "" else src.left(140)]


static func _row(variant: String, role: String, part: Dictionary, qty: int, unit_g: float, power: Variant, tag: String = "", note: String = "") -> Dictionary:
	var t := _tag(part) if not part.is_empty() else [tag, note]
	return {"variant": variant, "role": role, "part_id": String(part.get("part_id", "")), "part_name": String(part.get("name", note if part.is_empty() else "")),
		"qty": qty, "unit_mass_g": snappedf(unit_g, 0.01), "total_mass_g": snappedf(unit_g * qty, 0.01), "power_w": power,
		"source_tag": tag if tag != "" else t[0], "source_note": t[1] if note == "" or not part.is_empty() else note}


## One row per part for `made` (a SurveyKitBuilds.make result). Unknown mass_parts labels become role "other", never dropped.
static func rows(variant: String, made: Dictionary, cat: PartsCatalog) -> Array:
	var out: Array = []
	if String(made.get("error", "x")) != "":
		return out
	var b: Build = made["build"]
	var items: Array = made.get("payload_items", [])
	var av: Dictionary = b.avionics_breakdown()
	var pay_w := {}
	for it in items:
		if float(it["mass_g"]) == 0.0:
			pay_w[String(it["part_id"])] = float(pay_w.get(String(it["part_id"]), 0.0)) + float(it["w"])
	var comp_by_name := {}
	for k in b.components:
		comp_by_name[String(b.components[k].get("name", ""))] = k
	var motor_done := false
	for pm in b.mass_parts():
		var label := String(pm.label)
		var g := float(pm.mass_kg) * 1000.0
		if label.begins_with("Motor + prop"):
			if motor_done:
				continue
			motor_done = true
			var n := b.mass_parts().filter(func(x): return String(x.label).begins_with("Motor + prop")).size()
			out.append(_row(variant, "motor", b.motor, n, float(b.motor["mass_g"]), ""))
			out.append(_row(variant, "prop", b.propeller, n, float(b.propeller["mass_g"]), ""))
			var lump := float(b.motor["mass_g"]) + float(b.propeller["mass_g"])
			if absf(lump - g) > 0.005:
				out.append(_row(variant, "other", {}, n, g - lump, "", "computed", "motor+prop lump minus catalog motor and prop masses"))
		elif label == "Frame":
			out.append(_row(variant, "frame", b.frame, 1, g, ""))
		elif label == "Pack":
			out.append(_row(variant, "pack", b.battery, 1, g, ""))
		elif label == "Flight controller":
			out.append(_row(variant, "FC", b.fc, 1, g, av.get("fc", {}).get("w", "")))
		elif label == "ESC":
			out.append(_row(variant, "ESC", b.esc, 1, g, ""))
		elif label == "Payload":
			for it in items:
				if float(it["mass_g"]) > 0.0:
					out.append(_row(variant, String(it["role"]), cat.get_part(String(it["part_id"])), 1, float(it["mass_g"]), float(it["w"])))
		elif comp_by_name.has(label):
			var k := String(comp_by_name[label])
			var part: Dictionary = b.components[k]
			var w: Variant = pay_w.get(String(part.get("part_id", "")), "")
			if str(w) == "" and av.has(k) and k != "camera" and k != "gps":
				w = av[k].get("w", "")
			out.append(_row(variant, String(COMPONENT_ROLE.get(k, "other")), part, 1, g, w))
		elif label in HARNESS_LABELS or label.begins_with("Motor lead"):
			out.append(_row(variant, "wiring/harness", {}, 1, g, "", "computed", "%s (harness model: lengths x wire gauge, Build.harness)" % label))
		else:
			out.append(_row(variant, "other", {}, 1, g, "", "unverified", label))
	return out


static func csv_lines(rows_in: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for r in rows_in:
		var cells := PackedStringArray()
		for c in COLUMNS:
			cells.append(SurveyMatrix.csv_cell(r.get(c, "")))
		lines.append(",".join(cells))
	return lines
