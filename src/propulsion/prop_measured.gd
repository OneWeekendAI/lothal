class_name PropMeasured
extends RefCounted
## UIUC wind-tunnel tables as dots on the tunnel chart (PD8), the only *measured* thing on that page.
## Never blended into the model: a dot is a table row, converted to this chart's units and nothing else.

const TABLE := "res://data/validation/uiuc_props.json"
const NAMES := {"apcff_4.2x4": "APC FF 4.2x4", "da4002_5x3.75": "DA4002 5x3.75", "apce_9x4.5": "APC E 9x4.5"}
## Half a designer step and a little, so 3.75 in is reachable from a 0.1 in stepper.
const MATCH_TOLERANCE_IN := 0.06
const INCH_TO_MM := 25.4


## The table this blade's size matches, or {}. Size and blade count only: chord may differ, which is
## part of what the dots show. `{key, name, run_rpm, rows}`.
static func match_for(doc: PropellerDocument) -> Dictionary:
	var props: Dictionary = JsonStore.read_document(TABLE).get("props", {})
	for key: String in props:
		var p: Dictionary = props[key]
		if int(p["blades"]) == doc.blades \
				and absf(float(p["diameter_in"]) - doc.diameter_mm / INCH_TO_MM) <= MATCH_TOLERANCE_IN \
				and absf(float(p["pitch_in"]) - doc.pitch_mm / INCH_TO_MM) <= MATCH_TOLERANCE_IN:
			return {"key": key, "name": NAMES.get(key, key), "run_rpm": float(p["run_rpm"]),
				"rows": p["run_j_ct_cp_eta"]}
	return {}
