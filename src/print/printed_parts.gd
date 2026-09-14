class_name PrintedParts
extends RefCounted
## What THIS build can send to a printer — the Printed room's parts list, printed-room slices PR0–PR1.
##
## Generated from the build, never a catalog category. There is no SKU for a TPU mount: it is a
## function of the parts it fits and of the drone's printing decisions (design §3 decision 2), which
## the build carries as `build.printing`.
##
## Each row is `{"id", "label", "note", "exportable", "fittable", "fitted"}`. A row that is listed and
## not exportable says why in `note`, because a greyed button with no reason is the stub again.
## `fittable` rows are the ones whose mass the builder switches on here; the prop guard is not one.
##
## THE PROP GUARD IS LISTED, NEVER PICKED. Propulsion owns it — it is physics-bearing, and a second
## rail choosing the same part is the "two lists that were never the same list" P10f found. So the
## row exists only when the build already fits one, and says where it is chosen.

const PROP_GUARD := "prop_guard"
const ARM_GUARD := ArmGuard.PART_ID
const CAMERA_MOUNT := CameraMount.PART_ID
const ANTENNA_MOUNT := AntennaMount.PART_ID


static func for_build(build: Build) -> Array:
	var rows: Array = []
	if build == null:
		return rows
	if not build.frame.is_empty():
		rows.append(_arm_guard_row(build))
	if build.components.has("camera"):
		rows.append(_camera_mount_row(build))
	if build.components.has("antenna"):
		rows.append(_antenna_mount_row(build))
	if not build.guard.is_empty():
		rows.append({
			"id": PROP_GUARD,
			"label": "Prop guard — %s" % String(build.guard.get("name", build.guard.get("part_id", ""))),
			"note": "Chosen under Propulsion. One ring, print four.",
			"exportable": true,
			"fittable": false,
			"fitted": true,
		})
	return rows


## The camera mount's row (PR2). Listed whenever a camera is fitted, refused or not, because the gap
## that decides whether it fits is edited on this row — a refused mount with no row would hide the
## one field that fixes it. Carries `plate_spacing_mm` so the panel can show the gap slider.
static func _camera_mount_row(build: Build) -> Dictionary:
	var camera: Dictionary = build.components.get("camera", {})
	var tilt := float(build.assembly_value("camera_tilt_deg"))
	var dims := CameraMount.dimensions(camera, build.printing, tilt)
	var gap_text := "Plate gap %.1f mm%s" % [float(dims["plate_spacing_mm"]),
		" (guess)" if bool(dims["plate_spacing_guessed"]) else ""]
	var note := ""
	if not bool(dims["ok"]):
		note = "%s. %s." % [String(dims["reason"]), gap_text]
	else:
		note = "Camera %.1f × %.1f × %.1f mm (published). %s → %.1f mm cheek each side. M2 screw at the box centre (guess). Printed at %.0f°, the Camera tilt shared by every drone. No weight of its own: the camera's mass is the camera as mounted. One cheek, print two." % [
			float(dims["camera_length_mm"]), float(dims["camera_width_mm"]), float(dims["camera_height_mm"]),
			gap_text, float(dims["cheek_thickness_mm"]), tilt]
	return {
		"id": CAMERA_MOUNT,
		"label": "Camera mount — TPU cheeks",
		"note": note,
		"exportable": bool(dims["ok"]),
		"fittable": false,
		"fitted": false,
		"plate_spacing_mm": float(dims["plate_spacing_mm"]),
	}


## The antenna mount's row (PR3). Listed whenever an antenna is fitted, refused or not, for the camera
## mount's reason: the two standoff guesses that decide it are edited here.
static func _antenna_mount_row(build: Build) -> Dictionary:
	var dims := AntennaMount.dimensions(build.components.get("antenna", {}), build.printing)
	var guesses := "Rear standoffs %.1f mm apart%s, %.1f mm across%s" % [
		float(dims["standoff_spacing_mm"]), " (guess)" if bool(dims["standoff_spacing_guessed"]) else "",
		float(dims["standoff_diameter_mm"]), " (guess)" if bool(dims["standoff_diameter_guessed"]) else ""]
	var note := ""
	if not bool(dims["ok"]):
		note = "%s. %s." % [String(dims["reason"]), guesses]
	else:
		note = "Antenna %.1f mm wide (published) → %.1f mm bore. %s. The tube leans %.0f° aft, the angle the antenna is drawn at. No weight of its own: the antenna's share holds it." % [
			float(dims["antenna_width_mm"]), 2.0 * float(dims["tube_bore_radius_mm"]), guesses,
			float(dims["lean_deg"])]
	return {
		"id": ANTENNA_MOUNT,
		"label": "Antenna mount — standoff clamp and tube",
		"note": note,
		"exportable": bool(dims["ok"]),
		"fittable": false,
		"fitted": false,
		"standoff_spacing_mm": float(dims["standoff_spacing_mm"]),
		"standoff_diameter_mm": float(dims["standoff_diameter_mm"]),
	}


## The arm guard's row. Its note is where the guesses are said: every number the sleeve is made from
## that the catalog did not publish is named as a guess, beside the button that prints it.
static func _arm_guard_row(build: Build) -> Dictionary:
	var dims := ArmGuard.dimensions(build.frame, build.printing)
	var fitted := ArmGuard.is_fitted(build.printing)
	var note := ""
	if not bool(dims["ok"]):
		note = String(dims["reason"])
	else:
		note = "Arm %.1f mm thick (published), %.1f mm wide%s. Wall %.1f mm, length %.0f mm (guesses). %.2f g each, print four%s." % [
			float(dims["arm_thickness_mm"]), float(dims["tip_width_mm"]),
			" (guess)" if bool(dims["tip_width_guessed"]) else "",
			float(dims["wall_mm"]), float(dims["length_mm"]), ArmGuard.mass_kg(dims) * 1000.0,
			"" if fitted else " — not counted in the weight until fitted"]
	return {
		"id": ARM_GUARD,
		"label": "Arm guards — TPU sleeve",
		"note": note,
		"exportable": bool(dims["ok"]),
		"fittable": bool(dims["ok"]),
		"fitted": fitted and bool(dims["ok"]),
	}
