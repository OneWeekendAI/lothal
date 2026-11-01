class_name WarningPins
extends RefCounted
## Part-anchored warnings (PLAN Section 8, owner-approved addition): what the Design Space shows of
## a build's warnings, as pure data, so it is testable headless.
##
## Each pin carries IN ITS DATA everything the screen needs, and nothing is read back out of a
## sentence:
## - `tag`: 2-4 words and at most one number ("Current cap · 92% throttle"). The number is formatted
##   from the warning's own `values` (the numbers its sentence was written from), never parsed.
## - `anchor`: the pick address the pin sits on, from the warning's owning row (`BuildWarning.item`,
##   which `WarningRows` already resolves from values: a pack current limit sits on the battery);
##   `slot`: the selection category that row is.
## - `readout`: the readout key it affects ("" where no readout carries its number), and
##   `mark_value` / `mark_text`: the in-air figure shown beside that readout ("▲ 8.0 in air"),
##   from the warning's values or a named Build method (`mark_method`).
## - `severity`: "blocking" (cannot fly or cannot be built: an IMPOSSIBLE warning, a missing
##   required part, a refused drop) or "caution" (a LIMITING warning). `tint`: blocking pins also
##   tint their part. CHARACTERISTIC warnings are descriptions, not issues (BuildWarning's own
##   rule), and get no pin, exactly as the readouts panel never listed them.
## - `long`: the existing full sentence, shown in the inspector when the pin or mark is clicked.

const CAUTION := "caution"
const BLOCKING := "blocking"
const MARKER := "▲"
const SEP := " · "

## WarningRows row -> where its pin sits (a pick address of the 5"'s drawn model).
const ROW_ANCHOR := {
	WarningRows.BATTERY: "part/battery", WarningRows.ESC: "part/stack", WarningRows.FC: "part/stack",
	WarningRows.RECEIVER: "part/stack", WarningRows.PORTS: "part/stack", WarningRows.TUNE: "part/stack",
	WarningRows.FAILSAFE: "part/stack", WarningRows.RATES: "part/stack", WarningRows.SHEET: "part/stack",
	WarningRows.MOTORS: "part/motor/FR", WarningRows.MOTOR_DIRECTION: "part/motor/FR",
	WarningRows.PROPELLERS: "part/prop/FL", WarningRows.GUARDS: "part/prop/FL",
	WarningRows.HARNESS: "part/wires", WarningRows.CAMERA: "part/camera", WarningRows.VTX: "part/antennas",
	WarningRows.FRAME: "frame/plate/top", WarningRows.ARMS: "frame/arm/FR",
	WarningRows.HARDWARE: "frame/plate/top", WarningRows.LAYOUT: "frame/plate/top",
	WarningRows.STRAPS: "frame/plate/top", WarningRows.PRINTED: "frame/plate/top",
	WarningRows.COURSE: "frame/plate/top", WarningRows.CONDITIONS: "frame/plate/top",
}
## WarningRows row -> the selection slot it is about.
const ROW_SLOT := {
	WarningRows.BATTERY: "battery", WarningRows.ESC: "esc", WarningRows.FC: "flight_controller",
	WarningRows.RECEIVER: "receiver", WarningRows.PORTS: "flight_controller",
	WarningRows.TUNE: "flight_controller", WarningRows.FAILSAFE: "flight_controller",
	WarningRows.RATES: "flight_controller", WarningRows.SHEET: "flight_controller",
	WarningRows.MOTORS: "motor", WarningRows.MOTOR_DIRECTION: "motor",
	WarningRows.PROPELLERS: "propeller", WarningRows.GUARDS: "guard", WarningRows.HARNESS: "battery",
	WarningRows.CAMERA: "camera", WarningRows.VTX: "vtx", WarningRows.FRAME: "frame",
	WarningRows.ARMS: "frame", WarningRows.HARDWARE: "frame", WarningRows.LAYOUT: "frame",
	WarningRows.STRAPS: "frame", WarningRows.PRINTED: "frame", WarningRows.COURSE: "frame",
	WarningRows.CONDITIONS: "frame",
}
## Where a pin sits when its own anchor is not drawn (a part removed, a row with no part).
const FALLBACK_ANCHOR := "frame/plate/top"
## A missing required part's pin: the part is gone, so it sits on what it mounts to.
const MISSING_ANCHOR := {"battery": "frame/plate/top", "motor": "frame/arm/FR",
	"propeller": "part/motor/FR", "esc": "frame/plate/top", "flight_controller": "frame/plate/top",
	"frame": "frame/plate/top"}
## A missing required part, in its tag ("No battery").
const MISSING_TAG := {"battery": "No battery", "motor": "No motors", "propeller": "No props",
	"esc": "No ESC", "flight_controller": "No flight controller", "frame": "No frame"}

## id -> how its pin reads. tag: the words; num: printf for ONE number taken from values[of]
## (times `scale`); readout: the readout it affects; mark_of / mark_method: the in-air figure for
## the mark, from values or a Build method; mark: printf for it. An IMPOSSIBLE or LIMITING id not
## listed here falls back to its WarningRows short (also formatted from values) and no readout.
const TABLE := {
	&"current_limit": {"tag": "Current cap", "num": "%d%% throttle", "of": "throttle_cap", "scale": 100.0,
		"readout": "thrust_to_weight", "mark_method": "reachable_thrust_to_weight", "mark": "%.1f in air"},
	&"pack_sag": {"tag": "Sags", "num": "%.1f:1 in air", "of": "reachable_twr",
		"readout": "thrust_to_weight", "mark_of": "reachable_twr", "mark": "%.1f in air"},
	&"cannot_hover": {"tag": "Cannot hover", "num": "%.1f:1 in air", "of": "reachable_twr",
		"readout": "thrust_to_weight", "mark_of": "reachable_twr", "mark": "%.1f in air"},
	&"connector_rating": {"tag": "Plug overloaded", "num": "%.0f A", "of": "sustained_a", "readout": ""},
	&"connector_mismatch": {"tag": "Plug does not mate", "readout": ""},
	&"harness_ampacity": {"tag": "Wire overloaded", "num": "%.0f A", "of": "segment_current_a", "readout": ""},
	&"no_receiver": {"tag": "No receiver", "readout": ""},
	&"buzzer_not_self_powered": {"tag": "Buzzer dies with pack", "readout": ""},
	&"prop_clearance": {"tag": "Props too big", "num": "%.1f\" max", "of": "max_prop_inches", "readout": ""},
	&"motor_mount": {"tag": "Motor mount", "num": "%s", "of": "frame_pattern", "readout": ""},
	&"stack_mount": {"tag": "Stack mount", "num": "%s", "of": "frame_pattern", "readout": ""},
	&"fc_stack_mount": {"tag": "Stack mount", "num": "%s", "of": "frame_pattern", "readout": ""},
	# Kinds whose WarningRows short runs past four words; most are the designer's and the Lab's.
	&"drawn_frame_not_flown": {"tag": "Frame not flown", "readout": ""},
	&"frame_cg_off_axis": {"tag": "CG off axis", "num": "%.1f mm", "of": "offset_mm", "readout": ""},
	&"frame_is_directional": {"tag": "Directional frame", "num": "%.2f : 1", "of": "ratio", "readout": ""},
	&"arm_centreline_leaves_plate": {"tag": "Arm leaves plate", "readout": ""},
	&"frame_resonance": {"tag": "Arm resonance", "num": "%d Hz", "of": "resonance_hz", "readout": ""},
	&"hole_to_edge": {"tag": "Hole near edge", "readout": ""},
	&"cut_corner_tighter_than_bit": {"tag": "Corners too sharp", "readout": ""},
	&"arm_weaker_than_class": {"tag": "Weak arm", "readout": ""},
	&"cut_gap_narrower_than_bit": {"tag": "Gap below bit", "readout": ""},
	&"no_strap_slots": {"tag": "No strap slots", "readout": ""},
	&"strap_slot_narrow": {"tag": "Strap slot narrow", "num": "%.0f mm", "of": "slot_mm", "readout": ""},
	&"strap_slot_off_pack": {"tag": "Strap slot off pack", "readout": ""},
	&"pad_too_soft": {"tag": "Pad too soft", "num": "%d Hz", "of": "f_n_hz", "readout": ""},
	&"mount_attachment": {"tag": "Nothing to mount to", "readout": ""},
	&"component_in_prop_disc": {"tag": "Part in prop disc", "readout": ""},
	&"pack_in_prop_disc": {"tag": "Pack in prop disc", "readout": ""},
	&"component_larger_than_plate": {"tag": "Part over plate", "readout": ""},
	&"pack_wider_than_plate": {"tag": "Pack wider than plate", "readout": ""},
	&"tight_prop_clearance": {"tag": "Near a prop", "num": "%d mm", "of": "clearance_mm", "readout": ""},
	&"prop_unloading": {"tag": "Props unload", "num": "%d%% at top speed", "of": "thrust_fraction_at_top_speed",
		"scale": 100.0, "readout": ""},
	&"manoeuvre_headroom": {"tag": "Little headroom", "num": "%d%% hover", "of": "hover_throttle", "scale": 100.0,
		"readout": ""},
	&"climb_margin": {"tag": "Spare thrust", "num": "%.1f× weight", "of": "climb_g", "readout": ""},
	&"harness_voltage_drop": {"tag": "Lead drop", "num": "%.2f V", "of": "harness_drop_v", "readout": ""},
	&"camera_tilt_into_top_plate": {"tag": "Camera hits plate", "num": "%d°", "of": "tilt_deg", "readout": ""},
	&"camera_wider_than_cage": {"tag": "Camera too wide", "readout": ""},
	&"ports_over_budget": {"tag": "Too few UARTs", "num": "%d wanted", "of": "demand", "readout": ""},
	&"config_sheet_defaults": {"tag": "Defaults kept", "num": "%d settings", "of": "missing", "readout": ""},
	&"field_air": {"tag": "Thin air", "num": "%d%% below sea level", "of": "fraction_below_standard",
		"scale": 100.0, "readout": ""},
	&"course_ring_smaller_than_aircraft": {"tag": "Ring too small", "readout": ""},
	&"implausible_frame_mass": {"tag": "Frame mass implausible", "readout": ""},
	&"layout_not_controllable": {"tag": "Layout uncontrollable", "readout": ""},
	&"arm_has_no_centreline": {"tag": "Arm lacks centreline", "readout": ""},
	&"implausible_arm": {"tag": "Arm implausible", "readout": ""},
	&"hover_on_resonance": {"tag": "Hover on resonance", "num": "%d Hz", "of": "resonance_hz", "readout": ""},
	&"electronics_lump": {"tag": "Electronics as lump", "readout": ""},
	&"pad_passes_frame_mode": {"tag": "Pad passes ring", "readout": ""},
	&"mount_pattern": {"tag": "Mount pattern mismatch", "readout": ""},
	&"mount_overhang": {"tag": "Part overhangs mount", "readout": ""},
	&"prop_extrapolation": {"tag": "Thrust extrapolated", "readout": ""},
	&"implausible_kv_for_stator": {"tag": "KV implausible", "readout": ""},
	&"implausible_pack_mass_per_energy": {"tag": "Pack mass implausible", "readout": ""},
	&"fc_mass_budget": {"tag": "FC over budget", "num": "%.0f g", "of": "excess_g", "readout": ""},
	&"d_noise_ceiling": {"tag": "D noise-limited", "readout": ""},
	&"camera_obstruction": {"tag": "Lens obstructed", "num": "%d°", "of": "closest_deg", "readout": ""},
	&"printed_differs": {"tag": "Print out of date", "readout": ""},
	&"printed_missing_file": {"tag": "Print file missing", "readout": ""},
	&"printed_gone": {"tag": "Print not generated", "readout": ""},
	&"failsafe_gps_rescue_no_gps": {"tag": "Rescue without GPS", "readout": ""},
	&"course_gate_below_ground": {"tag": "Gate below ground", "readout": ""},
	&"course_route_through_gate": {"tag": "Route through gate", "readout": ""},
	&"course_tightest_turn": {"tag": "Tight turn", "readout": ""},
	&"course_gate_intersects_obstacle": {"tag": "Gate hits obstacle", "readout": ""},
}


## The pins of a fitted build: one per IMPOSSIBLE or LIMITING warning, most severe first.
static func of_build(b: Build) -> Array:
	var out: Array = []
	if b == null:
		return out
	for w in BuildWarning.by_severity(b.warnings()):
		if w.severity != BuildWarning.Severity.CHARACTERISTIC:
			out.append(of_warning(w, b))
	return out


## One warning's pin. `b` answers a `mark_method`; null leaves such a mark empty.
static func of_warning(w: BuildWarning, b: Build) -> Dictionary:
	var row: Dictionary = TABLE.get(w.id, {})
	var item := w.item
	var tag := String(row.get("tag", w.short))
	if row.has("num") and w.values.has(String(row["of"])):
		var v: Variant = w.values[String(row["of"])]
		var num := String(row["num"])
		var scale := float(row.get("scale", 1.0))
		var text: String
		if num.begins_with("%s"):
			text = num % str(v)
		elif num.begins_with("%d"):
			text = num % roundi(float(v) * scale)
		else:
			text = num % (float(v) * scale)
		tag = tag + SEP + text
	var readout := String(row.get("readout", ""))
	var mark_value := NAN
	if readout != "":
		if row.has("mark_of") and w.values.has(String(row["mark_of"])):
			mark_value = float(w.values[String(row["mark_of"])])
		elif row.has("mark_method") and b != null and b.has_method(String(row["mark_method"])):
			mark_value = float(b.call(String(row["mark_method"])))
	var blocking := w.severity == BuildWarning.Severity.IMPOSSIBLE
	return {"id": "w:%s:%s" % [w.id, item], "warning": w.id, "tag": tag,
		"anchor": String(ROW_ANCHOR.get(item, FALLBACK_ANCHOR)), "slot": String(ROW_SLOT.get(item, "")),
		"readout": readout, "mark_value": mark_value,
		"mark_text": "" if is_nan(mark_value) else "%s %s" % [MARKER, String(row["mark"]) % mark_value],
		"severity": BLOCKING if blocking else CAUTION, "tint": blocking, "long": w.long()}


## A required part that is not fitted: the drone cannot fly. Blocking, on what the part mounts to.
static func of_missing(category: String) -> Dictionary:
	return {"id": "w:missing:%s" % category, "warning": &"missing_required",
		"tag": String(MISSING_TAG.get(category, "No " + category)) + SEP + "cannot fly",
		"anchor": String(MISSING_ANCHOR.get(category, FALLBACK_ANCHOR)), "slot": category,
		"readout": "", "mark_value": NAN, "mark_text": "", "severity": BLOCKING, "tint": true,
		"long": "A drone cannot fly without its %s." % String(PartSwap.CATEGORY_NAMES.get(category,
			PartSnap.MISSING_NAMES.get(category, category))).to_lower()}


## A refused drop (PartSnap.resolve's "refused" verdict), on the mount it was refused at. Its tag
## and sentence are the refusing warning's, when one refused it; else the verdict's own reason.
static func of_refusal(verdict: Dictionary, anchor: String) -> Dictionary:
	var by: Variant = verdict.get("refused_by")
	var out := {"id": "w:refused", "warning": &"refused_drop", "tag": "Cannot mount here",
		"anchor": anchor if anchor != "" else FALLBACK_ANCHOR, "slot": String(verdict.get("category", "")),
		"readout": "", "mark_value": NAN, "mark_text": "", "severity": BLOCKING, "tint": true,
		"long": String(verdict.get("reason", ""))}
	if by is BuildWarning:
		var w := by as BuildWarning
		var p := of_warning(w, null)
		out["tag"] = p["tag"]
		out["long"] = w.long()
		out["warning"] = w.id
	return out


## The readout marks: readout key -> {text, ids}. Pins that mark the same readout with the same
## figure share one mark (the seed's current cap and sag both say 8.0 in the air).
static func marks(pins: Array) -> Dictionary:
	var out := {}
	for p in pins:
		var key := String(p["readout"])
		if key == "" or String(p["mark_text"]) == "":
			continue
		if not out.has(key):
			out[key] = {"text": String(p["mark_text"]), "ids": []}
		elif String(out[key]["text"]).find(String(p["mark_text"])) < 0:
			out[key]["text"] = String(out[key]["text"]) + "  " + String(p["mark_text"])
		(out[key]["ids"] as Array).append(String(p["id"]))
	return out


## The readouts panel's count: "" for none, "1 issue", "2 issues".
static func count_text(n: int) -> String:
	if n <= 0:
		return ""
	return "%d issue%s" % [n, "" if n == 1 else "s"]
