class_name BatteryPad
extends RefCounted
## The battery pad — a TPU grip pad under the pack, with two strap slots through it. Printed-room slice
## PR11 (plans/2026-09-14-printed-room-plan.md).
##
## ## The shape
##
## The pack's published footprint plus a margin, `thickness_mm` thick, with two strap slots across its
## width. Built as closed shells that overlap where they join (StlWriter allows it; a slicer unions it):
## three **bands** across the full width (both ends and the middle) and two **rails** along the sides
## through the slot zones. The slots are the gaps between the bands and inside the rails, so no shell
## ever reaches into a slot.
##
## Printed flat: the length along Y, the width along X, Z up, centred on the origin.
##
## ## What is published and what is guessed
##
##   - **Footprint: read.** The fitted pack's `length_mm` × `width_mm`. A pack that does not publish both
##     refuses by name.
##   - **Thickness, margin, slot width and rail width: guesses**, per drone in `Project.printing.battery_pad`,
##     each labelled "(guess)" on the row.
##   - **Clearance widens the strap slots.** The strap is the bought part the pad meets.
##
## ## Mass: opt-in, under the pack
##
## Nothing budgets a pad, so when Fitted it is ADDED: one point mass directly beneath the pack's own seat,
## half a pad below the pack's underside. The reference build is unchanged until the builder ticks Fitted.

const BLOCK := "battery_pad"
const FITTED := "fitted"
const THICKNESS := "thickness_mm"
const MARGIN := "margin_mm"
const SLOT := "slot_width_mm"
const PART_ID := "battery_pad"

## Bumped BY HAND whenever `triangles_mm`'s output changes for the same inputs (persistence §7.4).
const GENERATOR_VERSION := 1

const DEFAULT_THICKNESS_MM := 2.0
const DEFAULT_MARGIN_MM := 2.0
## A 20 mm strap. A guess: 15, 20 and 25 mm straps are all sold.
const DEFAULT_SLOT_MM := 20.0
## The rails beside each slot. Not edited; a guess with no data behind it.
const RAIL_MM := 3.0
## How thick a strap is, so how far a slot opens along the pad. A guess.
const STRAP_THICKNESS_MM := 2.0

const RANGES := {
	THICKNESS: [1.0, 5.0],
	MARGIN: [0.0, 8.0],
	SLOT: [8.0, 30.0],
}


static func settings(printing: Dictionary) -> Dictionary:
	var raw: Variant = printing.get(BLOCK, {})
	return raw if raw is Dictionary else {}


static func is_fitted(printing: Dictionary) -> bool:
	return bool(settings(printing).get(FITTED, false))


static func set_value(printing: Dictionary, key: String, value: Variant) -> void:
	var block := settings(printing).duplicate(true)
	if key == FITTED:
		block[FITTED] = bool(value)
	elif RANGES.has(key):
		block[key] = clampf(float(value), float(RANGES[key][0]), float(RANGES[key][1]))
	else:
		push_warning("battery_pad has no setting '%s'" % key)
		return
	printing[BLOCK] = block


static func _value(block: Dictionary, key: String, default_mm: float) -> Array:
	var raw: Variant = block.get(key, null)
	if raw is float or raw is int:
		return [clampf(float(raw), float(RANGES[key][0]), float(RANGES[key][1])), false]
	return [default_mm, true]


## Everything the pad is made from, or a refusal.
static func dimensions(battery: Dictionary, printing: Dictionary) -> Dictionary:
	var block := settings(printing)
	var thickness := _value(block, THICKNESS, DEFAULT_THICKNESS_MM)
	var margin := _value(block, MARGIN, DEFAULT_MARGIN_MM)
	var slot := _value(block, SLOT, DEFAULT_SLOT_MM)
	var clearance := PrintSettings.clearance_mm(printing)
	var out := {"ok": false, "reason": "", "thickness_mm": thickness[0], "thickness_guessed": thickness[1],
		"margin_mm": margin[0], "margin_guessed": margin[1], "slot_width_mm": slot[0], "slot_guessed": slot[1],
		"clearance_mm": clearance, "rail_mm": RAIL_MM, "strap_thickness_mm": STRAP_THICKNESS_MM}

	if battery.is_empty():
		out["reason"] = "%s: no battery is fitted" % PART_ID
		return out
	var battery_id := String(battery.get("part_id", "battery"))
	var specs: Dictionary = battery.get("specs", {})
	for field in ["length_mm", "width_mm"]:
		if specs.get(field) == null or float(specs[field]) <= 0.0:
			out["reason"] = "%s: %s publishes no %s, and the pad is not guessed" % [PART_ID, battery_id, field]
			return out
	var pad_length := float(specs["length_mm"]) + 2.0 * float(margin[0])
	var pad_width := float(specs["width_mm"]) + 2.0 * float(margin[0])
	# A slot runs ACROSS the pad. The strap passes through it, so the slot opens by the strap's thickness
	# along the pad and spans the strap's width across it — clearance on every side of both.
	var slot_open := STRAP_THICKNESS_MM + 2.0 * clearance
	var slot_needed := float(slot[0]) + 2.0 * clearance
	var slot_across := pad_width - 2.0 * RAIL_MM
	out.merge({"battery_length_mm": float(specs["length_mm"]), "battery_width_mm": float(specs["width_mm"]),
		"pad_length_mm": pad_length, "pad_width_mm": pad_width, "slot_open_mm": slot_open,
		"slot_across_mm": slot_across}, true)

	out["slot_needed_mm"] = slot_needed
	if slot_across < slot_needed:
		out["reason"] = "%s: a %.1f mm strap%s does not fit across %s's %.1f mm pad between %.1f mm rails" % [
			PART_ID, float(slot[0]), " (guess)" if bool(slot[1]) else "", battery_id, pad_width, RAIL_MM]
		return out
	# Three bands and two slots along the length; each band must keep some material.
	var band := (pad_length - 2.0 * slot_open) / 3.0
	if band < 2.0:
		out["reason"] = "%s: %s's %.1f mm pad is too short for two strap slots" % [PART_ID, battery_id, pad_length]
		return out
	out["band_mm"] = band
	out["ok"] = true
	return out


## The pad as closed shells, millimetres: three bands across the full width and four rail segments beside
## the two slots. Empty for a refusal.
static func triangles_mm(dims: Dictionary) -> Array:
	var out: Array = []
	if not bool(dims.get("ok", false)):
		return out
	var half_w := float(dims["pad_width_mm"]) * 0.5
	var half_l := float(dims["pad_length_mm"]) * 0.5
	var t := float(dims["thickness_mm"])
	var band := float(dims["band_mm"])
	var slot_open := float(dims["slot_open_mm"])
	var rail := float(dims["rail_mm"])
	# Along Y, from -half_l: band, slot, band, slot, band.
	var y := -half_l
	for i in 3:
		out.append_array(AntennaMount._box(Vector3(-half_w, y, 0.0), Vector3(half_w, y + band, t)))
		y += band
		if i < 2:
			# The rails beside this slot, reaching a little into the bands on each side so the shells join.
			out.append_array(AntennaMount._box(Vector3(-half_w, y - 0.5, 0.0), Vector3(-half_w + rail, y + slot_open + 0.5, t)))
			out.append_array(AntennaMount._box(Vector3(half_w - rail, y - 0.5, 0.0), Vector3(half_w, y + slot_open + 0.5, t)))
			y += slot_open
	return out


## The shells' closed forms summed as they overlap, mm³: three bands, four rails of slot + 1 mm.
static func volume_mm3(dims: Dictionary) -> float:
	if not bool(dims.get("ok", false)):
		return 0.0
	var t := float(dims["thickness_mm"])
	return 3.0 * float(dims["band_mm"]) * float(dims["pad_width_mm"]) * t \
		+ 4.0 * (float(dims["slot_open_mm"]) + 1.0) * float(dims["rail_mm"]) * t


static func mass_kg(dims: Dictionary) -> float:
	return PrintSettings.printed_mass_kg(volume_mm3(dims))


## One point mass beneath the pack's own seat when fitted; nothing otherwise.
static func part_masses(build: Build, printing: Dictionary) -> Array:
	var out: Array = []
	if not is_fitted(printing):
		return out
	var dims := dimensions(build.battery, printing)
	if not bool(dims["ok"]):
		return out
	# The pack's seat, from the ONE place Build seats the pack (`Build.battery_seat`), never recomputed here.
	var seat := build.battery_seat()
	var mount: MountPoint = seat["mount"]
	# MountPoint.normal is an int (+1 up, -1 down); widened so both branches are floats.
	var normal := float(mount.normal) if mount != null else 1.0
	var below := build.battery_size_m().y * 0.5 + float(dims["thickness_mm"]) * 0.0005
	out.append(PartMass.new(mass_kg(dims), (seat["position"] as Vector3) - Vector3(0.0, normal * below, 0.0),
		Vector3.ZERO, "Battery pad"))
	return out
