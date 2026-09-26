class_name PrintedFigures
extends RefCounted
## The numbers the Lab dock's Printed rows and pages show (lab dock design §3, §4): one row per
## generated printed part. The row's line 2 (material), its line 3 (print mass), the page's two
## numbers and the page's drawing all read THESE functions, and these read the part's own solid —
## `PrintedParts.solid_for`, the one door the Export buttons also go through — so the number beside
## the drawing is the triangles the printer would get, not a second derivation.
##
## What is modelled, and so what may be shown:
##   - VOLUME: the signed volume of the exported triangles (divergence theorem). Exact for the mesh.
##   - PRINT MASS: volume × the material's density × the one infill guess (`PrintSettings`) for the
##     generated TPU parts; volume × the catalogue ring's published density for a prop guard. `~`,
##     because density and infill are class-typical guesses. A printable frame publishes no printed
##     density, so it gets its volume and no mass.
##   - THE KEY FIT: the bought part a printed part closes on, against the hole the generator cut for
##     it — the clearance on each side. Only the four generated parts that meet a bought one have it.
## Print TIME is not modelled (no slicer), so it is never shown.

## The generated parts' material ids, as a row says them.
const MATERIAL_NAMES := {"tpu_95a": "TPU 95A"}


## Line 2: what the part is printed in. Generated parts: this drone's printing material. A prop
## guard or a printable frame: the catalogue's own material field, as published.
static func material_text(build: Build, part_id: String) -> String:
	match part_id:
		PrintedParts.PROP_GUARD:
			return str((build.guard.get("catalog", {}) as Dictionary).get("material", "—"))
		PrintedParts.FRAME:
			return str((build.frame.get("catalog", {}) as Dictionary).get("material", "—"))
	var id := PrintSettings.material(build.printing)
	return str(MATERIAL_NAMES.get(id, id))


## The signed volume of closed, outward-wound triangles (mm → mm³). StlWriter refuses an inside-out
## solid, so a part that exports has a positive volume.
static func volume_mm3(triangles: Array) -> float:
	var total := 0.0
	for t in triangles:
		total += (t[0] as Vector3).dot((t[1] as Vector3).cross(t[2] as Vector3)) / 6.0
	return total


## One piece's figures: `{"ok", "reason", "volume_mm3", "mass_g", "quantity"}`. `mass_g` is NAN when
## no density is known (a printable frame). Everything read off `PrintedParts.solid_for`.
static func piece(build: Build, part_id: String) -> Dictionary:
	var solid := PrintedParts.solid_for(build, part_id)
	var out := {"ok": bool(solid["ok"]), "reason": str(solid["reason"]), "volume_mm3": 0.0,
		"mass_g": NAN, "quantity": int(solid["quantity"])}
	if not bool(solid["ok"]):
		return out
	var volume := volume_mm3(solid["triangles"])
	out["volume_mm3"] = volume
	match part_id:
		PrintedParts.PROP_GUARD:
			var density := float((build.guard.get("specs", {}) as Dictionary).get("density_kg_m3", 0.0))
			if density > 0.0:
				out["mass_g"] = volume * 1.0e-9 * density * 1000.0
		PrintedParts.FRAME:
			pass
		_:
			out["mass_g"] = PrintSettings.printed_mass_kg(volume) * 1000.0
	return out


## Line 3 when nothing is wrong: "~1.5 g each · print 4", "~7.2 g", or a frame's "~12.3 cm³".
static func mass_text(figures: Dictionary) -> String:
	if not bool(figures.get("ok", false)):
		return ""
	var quantity := int(figures["quantity"])
	var mass := float(figures["mass_g"])
	var amount := "~%.1f cm³" % (float(figures["volume_mm3"]) / 1000.0) if is_nan(mass) \
		else "~%.1f g" % mass
	return "%s each · print %d" % [amount, quantity] if quantity > 1 else amount


## THE KEY FIT: `{"what", "part_mm", "hole_mm"}` — the bought part the print closes on, its size,
## and the size the generator cut for it (the clearance each side is half the difference). Empty
## for a part that closes on nothing bought, or that is refused.
static func fit(build: Build, part_id: String) -> Dictionary:
	match part_id:
		PrintedParts.ARM_GUARD:
			var d := ArmGuard.dimensions(build.frame, build.printing)
			if bool(d["ok"]):
				return {"what": "Arm", "part_mm": float(d["arm_thickness_mm"]),
					"hole_mm": float(d["bore_height_mm"])}
		PrintedParts.CAMERA_MOUNT:
			var d := CameraMount.dimensions(build.components.get("camera", {}), build.printing,
				float(build.assembly_value("camera_tilt_deg")))
			if bool(d["ok"]):
				# The cheeks sit inside the plates; the camera between them.
				return {"what": "Camera", "part_mm": float(d["camera_width_mm"]),
					"hole_mm": float(d["plate_spacing_mm"]) - 2.0 * float(d["cheek_thickness_mm"])}
		PrintedParts.ANTENNA_MOUNT:
			var d := AntennaMount.dimensions(build.components.get("antenna", {}), build.printing)
			if bool(d["ok"]):
				return {"what": "Standoff", "part_mm": float(d["standoff_diameter_mm"]),
					"hole_mm": 2.0 * float(d["standoff_bore_radius_mm"])}
		PrintedParts.BATTERY_PAD:
			var d := BatteryPad.dimensions(build.battery, build.printing)
			if bool(d["ok"]):
				return {"what": "Strap", "part_mm": float(d["strap_thickness_mm"]),
					"hole_mm": float(d["slot_open_mm"])}
	return {}


## The fit as a page number: "5.0 in 5.4 mm". The clearance behind it is a guess until set, and
## says so.
static func fit_text(build: Build, part_id: String) -> String:
	var f := fit(build, part_id)
	if f.is_empty():
		return ""
	return "%.1f in %.1f mm%s" % [float(f["part_mm"]), float(f["hole_mm"]),
		"" if PrintSettings.has_clearance_override(build.printing) else " (guess)"]


## The part's own warnings. Divergence (`PrintedDivergence.warnings`) is the shell's to add, since
## only it holds the drone's print records; this is what the build alone says — a part it cannot
## generate. A bought guard is not refused: there is simply nothing to print.
static func warnings(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	for row in PrintedParts.for_build(build):
		var id := str(row["id"])
		if bool(row["exportable"]) or (id == PrintedParts.PROP_GUARD
				and PartsCatalog.fabrication_of(build.guard) == "bought"):
			continue
		var solid := PrintedParts.solid_for(build, id)
		out.append(BuildWarning.impossible(&"printed_refused", str(solid["reason"]), {"part": id}))
	return out
