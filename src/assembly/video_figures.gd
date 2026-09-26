class_name VideoFigures
extends RefCounted
## The numbers the Video rows, their page numbers and their drawings all read (lab dock design §3):
## one computation per figure, so the list, the page and the drawing cannot disagree. The
## `PowerFigures` / `ControlFigures` pattern, for Video.
##
## Nothing here is a second model. The tilt is the assembly tweak (`Build.assembly_value`), the
## standing height is `Build.camera_standing_height_m` (VideoPlausibility's own figure), the
## off-axis angles are `AirframeModel.camera_clearances` (the obstruction warning's own split), and
## every position is the seat `Build.component_centre_m` gives the mass model.
##
## WHAT IS DELIBERATELY NOT HERE:
##   - a field of view, and so any "in shot" verdict. No camera publishes a lens angle (CameraView's
##     header); an angle off the lens axis needs none, and the reader supplies the lens.
##   - a video range, and a VTX temperature. Output power is catalogue metadata, not a spec: Lothal
##     has no radio model and no thermal model, so either figure would be invented.
##   - the plate gap against the camera's height. The gap is not published (VideoPlausibility's
##     header), so only the camera's own standing height is stated, level and tipped.

## What a row calls the plates' nearest approach — the arms are the plates' outline.
const FRAME_NAME := "frame edge"


static func tilt_deg(build: Build) -> float:
	return float(build.assembly_value(AssemblyTweaks.CAMERA_TILT))


## The Camera row's line 2: the camera's name and the uptilt it is mounted at.
static func camera_choice(build: Build) -> String:
	if not build.components.has("camera"):
		return "none"
	return "%s · %d° up" % [str((build.components["camera"] as Dictionary).get("name", "")),
		roundi(tilt_deg(build))]


## How tall the published camera box stands, mm: `{level, tipped}` — tipped at the tilt in force.
## Empty with no camera fitted.
static func standing_mm(build: Build) -> Dictionary:
	if not build.components.has("camera"):
		return {}
	var camera: Dictionary = build.components["camera"]
	return {"level": Build.camera_standing_height_m(camera, 0.0) * 1000.0,
		"tipped": Build.camera_standing_height_m(camera, tilt_deg(build)) * 1000.0}


## What comes nearest the lens axis ahead of the lens: `{name, deg}` — the frame's edge or a fitted
## part, whichever is nearer — from `AirframeModel.camera_clearances()`'s result. Empty when there is
## nothing to measure (no camera, or a moulded frame with no outline and nothing fitted), and
## `deg >= 90` means nothing is ahead of the lens plane.
static func nearest_in_view(clearances: Dictionary) -> Dictionary:
	if clearances.is_empty():
		return {}
	var best := {}
	var frame_deg := float(clearances.get("frame_deg", INF))
	if is_finite(frame_deg):
		best = {"name": FRAME_NAME, "deg": frame_deg}
	var fitted: Array = clearances.get("fitted", [])
	if not fitted.is_empty() and (best.is_empty() or float(fitted[0]["deg"]) < float(best["deg"])):
		best = {"name": str(fitted[0]["name"]), "deg": float(fitted[0]["deg"])}
	return best


## "frame edge ~54° off lens axis" — the Camera row's line 3. `~`: the lens sits where MountLayout
## seats the camera, a drawing simplification (the box straddles the plate edge). Empty when
## `nearest_in_view` is.
static func nearest_text(clearances: Dictionary) -> String:
	var nearest := nearest_in_view(clearances)
	if nearest.is_empty():
		return ""
	if float(nearest["deg"]) >= 90.0:
		return "nothing ahead of the lens"
	return "%s ~%d° off lens axis" % [str(nearest["name"]), roundi(float(nearest["deg"]))]


## The transmitter and the antenna together, grams — the two parts the VTX row stands for.
static func vtx_antenna_mass_g(build: Build) -> float:
	var grams := 0.0
	for category in ["vtx", "antenna"]:
		grams += float((build.components.get(category, {}) as Dictionary).get("mass_g", 0.0))
	return grams


## How far behind the centre of mass the antenna is weighed, mm (forward is -Z, so aft is +Z). NAN
## with no antenna. The antenna is the farthest-out of the video parts (antennas.json), and this is
## the lever its grams sit on. Both ends are the mass model's: `Build.component_centre_m` and the
## composite centre of mass.
static func antenna_aft_of_com_mm(build: Build) -> float:
	if not build.components.has("antenna"):
		return NAN
	return (build.component_centre_m("antenna").z - build.mass_properties.com_m.z) * 1000.0


## Everything the Video side views draw, in mm, in side projection: `f` is forward (-Z), `y` is up.
##   plates: [{f0, f1, y, t}]  each plate's fore/aft extent, centre height and thickness
##   discs:  [{f, y, r}]       one per fore/aft prop position (side view overlaps a pair)
##   parts:  {category: {f, y, l, h, mass_g, name}}  each fitted video part's weighed box
##   eye, bore: Vector2        the lens and its axis; `bore` is a unit vector (forward, up)
##   com: Vector2              the aircraft's centre of mass
## Positions of the parts are the mass model's; the plates, discs and lens are the drawn airframe's.
static func side_view(airframe: AirframeModel, build: Build) -> Dictionary:
	var out := {"plates": [], "discs": [], "parts": {}, "eye": Vector2.ZERO, "bore": Vector2.RIGHT,
		"com": Vector2.ZERO, "has_eye": false}
	if build == null:
		return out
	var com := build.mass_properties.com_m * 1000.0
	out["com"] = Vector2(-com.z, com.y)
	for category in ["camera", "vtx", "antenna"]:
		if not build.components.has(category):
			continue
		var part: Dictionary = build.components[category]
		var centre := build.component_centre_m(category) * 1000.0
		var size := Build.component_size_of(part) * 1000.0
		out["parts"][category] = {"f": -centre.z, "y": centre.y, "l": size.z, "h": size.y,
			"mass_g": float(part.get("mass_g", 0.0)), "name": str(part.get("name", category))}
	if airframe == null:
		return out
	for record in airframe.frame_model.plate_polygons_m():
		var low := INF
		var high := -INF
		for plan_mm in record["outline_mm"]:
			var f := -AirframeDocument.world_m(plan_mm, 0.0).z * 1000.0
			low = minf(low, f)
			high = maxf(high, f)
		if is_finite(low):
			(out["plates"] as Array).append({"f0": low, "f1": high,
				"y": float(record["y_m"]) * 1000.0, "t": float(record.get("thickness_mm", 0.0))})
	var seen := {}
	for motor_name in MotorLayout.MOTOR_NAMES:
		if not airframe.propeller_meshes.has(motor_name):
			continue
		var pad: Node3D = airframe.frame_model.arm_tips[motor_name]
		var motor: Node3D = airframe.motor_meshes[motor_name]
		var prop: PropellerMesh = airframe.propeller_meshes[motor_name]
		var f := -pad.position.z * 1000.0
		var key := roundi(f)
		if seen.has(key):
			continue
		seen[key] = true
		(out["discs"] as Array).append({"f": f,
			"y": (pad.position.y + motor.position.y + prop.position.y) * 1000.0,
			"r": prop.radius_m * 1000.0})
	var eye = airframe.camera_eye_m()
	if eye != null:
		var bore := airframe.camera_boresight()
		out["eye"] = Vector2(-(eye as Vector3).z, (eye as Vector3).y) * 1000.0
		out["bore"] = Vector2(-bore.z, bore.y).normalized()
		out["has_eye"] = true
	return out
