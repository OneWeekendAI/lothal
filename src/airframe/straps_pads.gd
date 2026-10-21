class_name StrapsPads
extends RefCounted
## The Straps & pads row and page — airframe.md §6 — as ONE computation over a Build and the frame
## document, so the Lab list's row, the page's two numbers, the sheet and the drawing all read the same
## figures (FrameHardware's reason for existing, applied to the next row down).
##
## This is the one place a build becomes the four numbers `PadMount` takes and the footprint
## `StrapSlots` checks against. Nothing here is a new measurement of the pad: its dimensions are
## BatteryPad's (PR11), its mass is BatteryPad's, and the height it lifts the pack is
## `Build.battery_rise_m` (PR17). What is new is the spring and the slots.

static var _materials: FrameMaterials


static func materials() -> FrameMaterials:
	if _materials == null:
		_materials = FrameMaterials.load_default()
	return _materials


## The pack's footprint in plan, mm (u across = world X, v fore-aft = world Z), where Build seats it.
static func pack_rect_mm(build: Build) -> Rect2:
	if build == null or build.battery.is_empty():
		return Rect2()
	var seat: Vector3 = build.battery_seat()["position"]
	var size := build.battery_size_m()
	var centre := Vector2(seat.x, seat.z) * 1000.0
	var extent := Vector2(size.x, size.z) * 1000.0
	return Rect2(centre - extent * 0.5, extent)


## The strap mount the pack is on, by id — Build's own resolution, fallback included.
static func mount_id(build: Build) -> String:
	var mount: MountPoint = build.battery_seat()["mount"]
	return mount.id if mount != null else "strap_top"


## The pad's loaded contact area, mm²: the pack's footprint, less the two strap slots BatteryPad cuts
## under it (each `slot_open` long and as wide as the pack across the rails). EXACT on the pad's
## geometry; whether a solid printed slab really compresses over all of it is the characteristic part,
## and it is carried by the modulus, not by this number.
static func contact_area_mm2(dims: Dictionary) -> float:
	if not bool(dims.get("ok", false)):
		return 0.0
	var length := float(dims["battery_length_mm"])
	var width := float(dims["battery_width_mm"])
	var slot_across := minf(float(dims["slot_across_mm"]), width)
	return maxf(length * width - 2.0 * float(dims["slot_open_mm"]) * slot_across, 0.0)


## Every figure the row, the page and the drawing show. Keys:
##
##   strap_width_mm, strap_guessed, strap_thickness_mm, mount_id, pack_rect_mm (Rect2),
##   slots (StrapSlots.measure dicts), seat_plate (bool),
##   pad_fitted, pad_dims (BatteryPad.dimensions), pad (PadMount.compute, `{}` when unfitted),
##   pad_mass_g, lift_mm, frame_mode_hz, frame_transmissibility, warnings (Array[BuildWarning]).
static func figures(build: Build, document: AirframeDocument) -> Dictionary:
	var out := {"strap_width_mm": BatteryPad.DEFAULT_SLOT_MM, "strap_guessed": true,
		"strap_thickness_mm": BatteryPad.STRAP_THICKNESS_MM, "mount_id": "strap_top",
		"pack_rect_mm": Rect2(), "slots": [], "seat_plate": false, "pad_fitted": false,
		"pad_dims": {}, "pad": {}, "pad_mass_g": 0.0, "lift_mm": 0.0, "frame_mode_hz": 0.0,
		"frame_transmissibility": NAN, "warnings": [] as Array[BuildWarning]}
	if build == null:
		return out
	var dims := BatteryPad.dimensions(build.battery, build.printing)
	out["pad_dims"] = dims
	out["strap_width_mm"] = float(dims["slot_width_mm"])
	out["strap_guessed"] = bool(dims["slot_guessed"])
	out["strap_thickness_mm"] = float(dims["strap_thickness_mm"])
	out["mount_id"] = mount_id(build)
	out["pack_rect_mm"] = pack_rect_mm(build)
	var plate := StrapSlots.seat_plate(document, str(out["mount_id"]))
	out["seat_plate"] = not plate.is_empty()
	out["slots"] = StrapSlots.slots(plate) if not plate.is_empty() else []
	out["frame_mode_hz"] = VibrationModel.for_build(build).resonance_hz

	var found: Array[BuildWarning] = []
	out["pad_fitted"] = BatteryPad.is_fitted(build.printing)
	if bool(out["pad_fitted"]) and bool(dims["ok"]):
		var load_kg := float(build.battery.get("mass_g", 0.0)) / 1000.0
		var pad := PadMount.compute(materials(), contact_area_mm2(dims), float(dims["thickness_mm"]),
			load_kg)
		out["pad"] = pad
		out["pad_mass_g"] = BatteryPad.mass_kg(dims) * 1000.0
		out["lift_mm"] = build.battery_rise_m() * 1000.0
		if bool(pad["ok"]):
			out["frame_transmissibility"] = PadMount.transmissibility(float(out["frame_mode_hz"]),
				float(pad["f_n_hz"]), float(pad["zeta"]))
		found.append_array(PadMount.warnings(pad, float(out["frame_mode_hz"])))
	found.append_array(StrapSlots.warnings(document, str(out["mount_id"]), out["pack_rect_mm"],
		float(out["strap_width_mm"]), float(out["strap_thickness_mm"])))
	out["warnings"] = found
	return out


## The warnings alone — what the shell adds to the list under Airframe, beside the joint checks.
static func warnings(build: Build, document: AirframeDocument) -> Array[BuildWarning]:
	var list: Array[BuildWarning] = []
	list.assign(figures(build, document)["warnings"])
	return list


## Line 2: what was chosen. "TPU pad 2 mm · 20 mm strap (guess)", or "no pad · …".
static func choice_text(f: Dictionary) -> String:
	var strap := "%s mm strap%s" % [_trim(float(f["strap_width_mm"])),
		" (guess)" if bool(f["strap_guessed"]) else ""]
	if not bool(f["pad_fitted"]):
		return "no pad · %s" % strap
	return "TPU pad %s mm · %s" % [_trim(float((f["pad_dims"] as Dictionary).get("thickness_mm", 0.0))),
		strap]


## Line 3: where the pad starts isolating (`~`, characteristic), else how many slots are under the pack.
static func number_text(f: Dictionary) -> String:
	var pad: Dictionary = f["pad"]
	if bool(pad.get("ok", false)):
		return "~%d Hz pad isolation corner" % roundi(float(pad["onset_hz"]))
	if not bool(f["seat_plate"]):
		return ""
	var count := under_pack_count(f)
	return "%d strap slot%s under the pack" % [count, "" if count == 1 else "s"]


## How many of the seat plate's slots have their centre inside the pack's footprint.
static func under_pack_count(f: Dictionary) -> int:
	var rect: Rect2 = f["pack_rect_mm"]
	var count := 0
	for shape in f["slots"]:
		if rect.has_point(shape["centre"]):
			count += 1
	return count


## The page's two numbers: the pad's isolation corner against the frame's mode, and the slots.
static func page_numbers(f: Dictionary) -> Array:
	var pad: Dictionary = f["pad"]
	var corner := "no pad fitted"
	if bool(pad.get("ok", false)):
		corner = "~%d Hz · frame ~%d Hz" % [roundi(float(pad["onset_hz"])), roundi(float(f["frame_mode_hz"]))]
	elif bool(f["pad_fitted"]):
		corner = "pad cannot be read"
	var slots := "no plate to cut"
	if bool(f["seat_plate"]):
		var found: Array = f["slots"]
		slots = "%d of %d under the pack" % [under_pack_count(f), found.size()] if not found.is_empty() \
			else "none cut"
	return [["Pad isolates above", corner], ["Strap slots", slots]]


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
