class_name StrapsDetails
extends AirframePanel
## The Straps & pads sheet — airframe.md §6. The battery pad as a spring under the pack, and the strap
## slots the pack is held through, as numbers plus the checks that flag them.
##
## ## A frame panel that needs the pack, without reaching a Build
##
## AirframePanel's rule is that no Build is reachable from here, and this panel keeps it: the pad's
## resonance needs the pack's mass and the slot check needs the pack's footprint, so the caller hands
## in `StrapsPads.figures(build, document)` — a Dictionary of numbers — and the rows read that. The
## frame is still the subject; the pack is a load on it, passed as data, the way the Arms tab would
## take a tip mass if it ever showed one.
##
## Every pad row carries its tier (§8): the spring is CHARACTERISTIC, the damping a GUESS, the
## geometry EXACT. The checks warn and never block, as the Fasteners tab's do.

const SPEC_ROWS := [
	{"key": "pad", "label": "Battery pad"},
	{"key": "area", "label": "Loaded area"},
	{"key": "stiffness", "label": "Pad stiffness"},
	{"key": "resonance", "label": "Resonance with the pack"},
	{"key": "onset", "label": "Isolates above"},
	{"key": "frame_mode", "label": "At the frame's 1st mode"},
	{"key": "damping", "label": "Damping ratio"},
	{"key": "lift", "label": "Lifts the pack"},
	# ---- THE STRAP (§6.4) ----
	{"key": "strap", "label": "Strap"},
	{"key": "slots", "label": "Strap slots"},
	{"key": "checks", "label": "Strap & pad checks"},
]

var _figures: Dictionary = {}


func _init() -> void:
	super(SPEC_ROWS)


## Paints the sheet for one frame carrying one pack: `figures` is `StrapsPads.figures(build, document)`.
func render_straps(document: AirframeDocument, figures: Dictionary) -> void:
	_figures = figures
	render(document)


func row_text(key: String) -> String:
	if _figures.is_empty():
		return "—"
	var pad: Dictionary = _figures.get("pad", {})
	var pad_ok := bool(pad.get("ok", false))
	var dims: Dictionary = _figures.get("pad_dims", {})
	match key:
		"pad":
			if not bool(_figures["pad_fitted"]):
				return "— not fitted (tick Fitted on the Printed battery pad)"
			if not bool(dims.get("ok", false)):
				return "— %s" % str(dims.get("reason", "cannot be read"))
			return "TPU 95A, %.1f mm%s, %.0f × %.0f mm" % [float(dims["thickness_mm"]),
				" (guess)" if bool(dims["thickness_guessed"]) else "", float(dims["pad_length_mm"]),
				float(dims["pad_width_mm"])]
		"area":
			if not pad_ok:
				return "—"
			return with_tier("%.0f mm² under a %.0f g pack" % [float(pad["area_mm2"]),
				float(pad["load_kg"]) * 1000.0], PadMount.TIER_EXACT)
		"stiffness":
			if not pad_ok:
				return "—"
			return with_tier("~%.1f MN/m" % (float(pad["stiffness_n_m"]) / 1e6),
				PadMount.TIER_CHARACTERISTIC)
		"resonance":
			if not pad_ok:
				return "—"
			return with_tier("~%d Hz" % roundi(float(pad["f_n_hz"])), PadMount.TIER_CHARACTERISTIC)
		"onset":
			if not pad_ok:
				return "—"
			return with_tier("~%d Hz" % roundi(float(pad["onset_hz"])), PadMount.TIER_CHARACTERISTIC)
		"frame_mode":
			var t := float(_figures.get("frame_transmissibility", NAN))
			if not pad_ok or is_nan(t):
				return "—"
			var verdict := "isolates" if t < 1.0 else "passes it through"
			return with_tier("~%d Hz: %.2f× · %s" % [roundi(float(_figures["frame_mode_hz"])), t, verdict],
				PadMount.TIER_CHARACTERISTIC)
		"damping":
			return with_tier("%.2f" % PadMount.DAMPING_RATIO, PadMount.TIER_GUESS)
		"lift":
			if not pad_ok:
				return "—"
			# PR17's rise and PR11's mass, read rather than recomputed.
			return with_tier("%.1f mm, pad %.1f g" % [float(_figures["lift_mm"]),
				float(_figures["pad_mass_g"])], PadMount.TIER_EXACT)
		"strap":
			return "%.0f × %.0f mm%s" % [float(_figures["strap_width_mm"]),
				float(_figures["strap_thickness_mm"]), " (guess)" if bool(_figures["strap_guessed"]) else ""]
		"slots":
			if not bool(_figures["seat_plate"]):
				return "— (no plate for the pack to strap to)"
			var found: Array = _figures["slots"]
			if found.is_empty():
				return "none cut"
			var first: Dictionary = found[0]
			return "%d · %.1f × %.1f mm · %d under the pack" % [found.size(),
				float(first["length_mm"]), float(first["width_mm"]), StrapsPads.under_pack_count(_figures)]
		"checks":
			var typed: Array[BuildWarning] = []
			typed.assign(_figures.get("warnings", []))
			if typed.is_empty():
				return "all pass"
			return "%d flagged — %s" % [typed.size(), BuildWarning.by_severity(typed)[0].short]
	return super(key)
