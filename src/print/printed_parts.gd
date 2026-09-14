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
## A frame whose catalog entry says it can be printed (PR9). Listed only then.
const FRAME := "frame"
const GPS_MAST := GpsMast.PART_ID
## Bumped BY HAND whenever the frame's exported triangles change for the same frame (persistence §7.4).
const FRAME_GENERATOR_VERSION := 1
## Bumped BY HAND whenever the prop guard ring's triangles change for the same guard (persistence §7.4).
const PROP_GUARD_GENERATOR_VERSION := 1


## The one door from a row id to printable triangles (printed-room PR4). The per-part Export buttons
## and the whole-room export both come through here, so the two cannot write different solids for one
## part. Returns `{"ok", "reason", "part", "solid_name", "triangles", "generator", "quantity"}`:
## `generator` is "<part>@<hand-bumped version>", `quantity` is how many of the one STL to print.
##
## The prop guard's triangles are PropulsionExport's, the same function Propulsion's own button writes.
static func solid_for(build: Build, part_id: String, prop_tip_radius_m: float) -> Dictionary:
	# `inputs`: settings a print record keeps so a later divergence can name them from/to (PR5). Only the
	# ones that live OUTSIDE this drone's own printing block need it — today, the global camera tilt.
	var out := {"ok": false, "reason": "", "part": part_id, "solid_name": part_id, "triangles": [],
		"generator": "", "quantity": 1, "inputs": {}}
	var dims := {}
	match part_id:
		ARM_GUARD:
			dims = ArmGuard.dimensions(build.frame, build.printing)
			out["solid_name"] = "%s-%s" % [part_id, String(build.frame.get("part_id", "frame"))]
			out["generator"] = "%s@%d" % [part_id, ArmGuard.GENERATOR_VERSION]
			out["quantity"] = MotorLayout.MOTOR_NAMES.size()
			out["triangles"] = ArmGuard.triangles_mm(dims)
		CAMERA_MOUNT:
			var camera: Dictionary = build.components.get("camera", {})
			dims = CameraMount.dimensions(camera, build.printing, float(build.assembly_value("camera_tilt_deg")))
			out["solid_name"] = "%s-%s" % [part_id, String(camera.get("part_id", "camera"))]
			out["generator"] = "%s@%d" % [part_id, CameraMount.GENERATOR_VERSION]
			out["quantity"] = 2
			out["inputs"] = {"tilt_deg": float(build.assembly_value("camera_tilt_deg"))}
			out["triangles"] = CameraMount.triangles_mm(dims)
		ANTENNA_MOUNT:
			var antenna: Dictionary = build.components.get("antenna", {})
			dims = AntennaMount.dimensions(antenna, build.printing)
			out["solid_name"] = "%s-%s" % [part_id, String(antenna.get("part_id", "antenna"))]
			out["generator"] = "%s@%d" % [part_id, AntennaMount.GENERATOR_VERSION]
			out["quantity"] = 1
			out["triangles"] = AntennaMount.triangles_mm(dims)
		GPS_MAST:
			dims = GpsMast.dimensions(build, build.printing)
			var gps: Dictionary = build.components.get("gps", {})
			out["solid_name"] = "%s-%s" % [part_id, String(gps.get("part_id", "gps"))]
			out["generator"] = "%s@%d" % [part_id, GpsMast.GENERATOR_VERSION]
			out["quantity"] = 1
			# The mast height is the GPS tweak, one global setting — recorded like the camera tilt.
			out["inputs"] = {"mast_height_mm": float(dims.get("mast_height_mm", 0.0))}
			out["triangles"] = GpsMast.triangles_mm(dims)
		PROP_GUARD:
			if build.guard.is_empty():
				out["reason"] = "%s: no prop guard is fitted" % part_id
				return out
			if PartsCatalog.fabrication_of(build.guard) == "bought":
				out["reason"] = "%s: %s is a bought part in the catalog, not a printed one" % [
					part_id, String(build.guard.get("part_id", part_id))]
				return out
			out["solid_name"] = String(build.guard.get("part_id", part_id))
			out["generator"] = "%s@%d" % [part_id, PROP_GUARD_GENERATOR_VERSION]
			out["quantity"] = MotorLayout.MOTOR_NAMES.size()
			out["triangles"] = PropulsionExport.guard_triangles_mm(build.guard, prop_tip_radius_m)
			dims = {"ok": not (out["triangles"] as Array).is_empty(),
				"reason": "%s: %s has no ring to print" % [part_id, out["solid_name"]]}
		FRAME:
			var fabrication := PartsCatalog.fabrication_of(build.frame)
			var frame_id := String(build.frame.get("part_id", part_id))
			if fabrication != "printed" and fabrication != "either":
				out["reason"] = "%s: %s is not marked printable in the catalog" % [part_id, frame_id]
				return out
			out["solid_name"] = "%s-%s" % [part_id, frame_id]
			out["generator"] = "%s@%d" % [part_id, FRAME_GENERATOR_VERSION]
			out["quantity"] = 1
			out["triangles"] = frame_triangles_mm(build.frame)
			if (out["triangles"] as Array).is_empty():
				dims = {"ok": false, "reason": "%s: %s has no plate geometry to print" % [part_id, frame_id]}
			else:
				# Checked HERE, not left to the writer, so the row can say why before the button is pressed.
				# A catalog frame is several plates that touch along identical edges; StlWriter counts edges
				# across the whole file and cannot tell that from a bad winding, so every catalog frame is
				# refused today. That is a limit of the check, recorded (track §7F), never overridden here.
				var report := StlWriter.check_manifold(out["triangles"])
				dims = {"ok": bool(report["ok"]), "reason": "%s: %s cannot be written as one checked solid (%s)" % [
					part_id, frame_id, ", ".join(PackedStringArray(report["reasons"]))]}
		_:
			out["reason"] = "%s: not a printed part" % part_id
			return out
	out["ok"] = bool(dims.get("ok", false))
	out["reason"] = "" if bool(out["ok"]) else String(dims.get("reason", ""))
	return out


## The frame as triangles, read back off FrameExport's own STL text rather than tessellated a second
## time here: FrameExport is the one frame solid, and this is its second reader, not a second writer.
static func frame_triangles_mm(frame: Dictionary) -> Array:
	var text := FrameExport.to_stl(AirframeDocument.from_catalog_frame(frame))
	var out: Array = []
	var corners := PackedVector3Array()
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("vertex "):
			continue
		var parts := stripped.substr(7).split(" ", false)
		if parts.size() != 3:
			continue
		corners.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		if corners.size() == 3:
			out.append(corners)
			corners = PackedVector3Array()
	return out


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
	if build.components.has("gps"):
		rows.append(_gps_mast_row(build))
	if not build.guard.is_empty():
		var guard_fabrication := PartsCatalog.fabrication_of(build.guard)
		var guard_note := "Chosen under Propulsion. One ring, print four. The catalog does not say whether this guard is bought or printed."
		if guard_fabrication == "bought":
			guard_note = "Chosen under Propulsion. A bought part in the catalog, so there is nothing to print."
		elif guard_fabrication == "printed":
			guard_note = "Chosen under Propulsion. A printed part in the catalog. One ring, print four."
		elif guard_fabrication == "either":
			guard_note = "Chosen under Propulsion. Bought or printed, per the catalog. One ring, print four."
		rows.append({
			"id": PROP_GUARD,
			"label": "Prop guard — %s" % String(build.guard.get("name", build.guard.get("part_id", ""))),
			"note": guard_note,
			"exportable": guard_fabrication != "bought",
			"fittable": false,
			"fitted": true,
		})
	var frame_fabrication := PartsCatalog.fabrication_of(build.frame)
	if frame_fabrication == "printed" or frame_fabrication == "either":
		var frame_solid := solid_for(build, FRAME, 0.0)
		rows.append({
			"id": FRAME,
			"label": "Frame — %s" % String(build.frame.get("name", build.frame.get("part_id", ""))),
			"note": ("A %s frame in the catalog: the plates as one solid, from the frame export." % frame_fabrication) \
				if bool(frame_solid["ok"]) else String(frame_solid["reason"]),
			"exportable": bool(frame_solid["ok"]),
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
		var source := "%.1f mm mount diameter (published)" % float(dims["antenna_width_mm"])
		if bool(dims["bore_from_width"]):
			source = "%.1f mm, from published width — this antenna publishes no mount_diameter_mm, so the bore may be wider than the barrel it holds" % float(dims["antenna_width_mm"])
		note = "Antenna bore %.1f mm: %s. %s. The tube leans %.0f° aft, the angle the antenna is drawn at. No weight of its own: the antenna's share holds it." % [
			2.0 * float(dims["tube_bore_radius_mm"]), source, guesses, float(dims["lean_deg"])]
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


## The GPS mast's row (PR10). Listed whenever a GPS is fitted, refused or not. Fittable, like the arm
## guard: nothing budgets a printed stalk, so its weight counts only once ticked.
static func _gps_mast_row(build: Build) -> Dictionary:
	var dims := GpsMast.dimensions(build, build.printing)
	var fitted := GpsMast.is_fitted(build.printing)
	var note := ""
	if not bool(dims["ok"]):
		note = String(dims["reason"])
	else:
		note = "GPS %.1f × %.1f mm (published) on a %.1f mm mast (the GPS mast setting, shared by every drone). Lead bore %.1f mm%s, wall %.1f mm%s, pad %.1f mm%s, flange %.1f mm%s. %.2f g%s." % [
			float(dims["gps_length_mm"]), float(dims["gps_width_mm"]), float(dims["mast_height_mm"]),
			float(dims["bore_mm"]), " (guess)" if bool(dims["bore_guessed"]) else "",
			float(dims["post_wall_mm"]), " (guess)" if bool(dims["wall_guessed"]) else "",
			float(dims["pad_thickness_mm"]), " (guess)" if bool(dims["pad_guessed"]) else "",
			float(dims["flange_mm"]), " (guess)" if bool(dims["flange_guessed"]) else "",
			GpsMast.mass_kg(dims) * 1000.0, "" if fitted else " — not counted in the weight until fitted"]
	return {
		"id": GPS_MAST,
		"label": "GPS mast — printed stalk",
		"note": note,
		"exportable": bool(dims["ok"]),
		"fittable": bool(dims["ok"]),
		"fitted": fitted and bool(dims["ok"]),
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
