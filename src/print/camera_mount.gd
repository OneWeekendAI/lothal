class_name CameraMount
extends RefCounted
## The camera mount — a TPU cheek either side of the camera, filling the gap between the camera and
## the frame's side plate, with the camera's side screw through it. Printed-room slice PR2
## (plans/2026-09-14-printed-room-plan.md).
##
## ## The shape, and why it is this shape
##
## A cheek is the camera's own side silhouette — the published length × height — tipped to the
## current uptilt about the box centre, with a screw hole at that centre, extruded to fill what is
## left of the gap. So a cheek clamped between the frame plates holds the camera at exactly the angle
## the Camera slider shows, and swapping the camera changes the cheek. One STL, print two: the left
## and right cheeks are the same solid (it is symmetric through its own thickness).
##
## It is NOT a cradle with a bridge. Joining two cheeks needs either a boolean union or a second shell
## that overlaps the camera's space; neither is worth it for a part a builder screws in place.
##
## ## What is published and what is guessed
##
##   - **Camera box: read.** Length, width and height from the fitted camera. A camera that does not
##     publish all three refuses the part by name.
##   - **Plate gap: a labelled guess, per drone.** No frame in the catalog publishes the distance
##     between its camera side plates. It opens at 24 mm (a 19 mm camera with a cheek of about 2 mm
##     each side, the common 5" layout) and the row says "(guess)" until the builder sets it. It lives
##     in `Project.printing.camera_mount`, beside the clearance.
##   - **Screw: a guess.** M2 (2.0 mm) at the box centre. No catalog entry publishes where a camera's
##     side screws are.
##   - **Tilt: GLOBAL, deliberately not moved.** Read from the assembly (`camera_tilt_deg`), the one
##     Camera setting every drone shares. A per-drone gap beside a global tilt is untidy and recorded
##     (RESUME-printed, "Things that will bite" 4); paying off that debt is not this slice.
##
## ## Refusal
##
## The cheek is (gap − camera width − 2 × clearance) / 2. Below MIN_CHEEK_MM there is no part: a
## camera wider than the gap refuses, naming the camera and both widths, so the builder sees which of
## the two numbers to change.
##
## ## Mass: none of its own
##
## The camera's catalog mass is the camera AS MOUNTED (cameras.json: "the camera with its bracket"),
## so a mount weighed on top would count the bracket twice. Nothing here reaches `Build.mass_parts`.
##
## ## Drawn when Fitted (PR19)
##
## Ticking Fitted draws both cheeks in the Lab, from `triangles_mm`, either side of the drawn camera at
## the drawn tilt. It adds no weight (above). The Wave V camera checks do not move: they measure the
## plates, the guard rings and the component boxes, and a cheek lies wholly behind the lens plane —
## more than 90° off the boresight — beside a camera whose box the checks already read.

const BLOCK := "camera_mount"
const PLATE_SPACING := "plate_spacing_mm"
const FITTED := "fitted"
const PART_ID := "camera_mount"

## Bumped BY HAND whenever `triangles_mm`'s output changes for the same inputs (persistence §7.4).
const GENERATOR_VERSION := 1

const DEFAULT_PLATE_SPACING_MM := 24.0
const MIN_PLATE_SPACING_MM := 10.0
const MAX_PLATE_SPACING_MM := 45.0
## Thinner than this is not a cheek worth printing in TPU. A guess, and the refusal threshold.
const MIN_CHEEK_MM := 1.0
## M2, the usual side screw of the micro and full-size camera classes. A guess.
const SCREW_DIAMETER_MM := 2.0
## Material left between the screw hole and the cheek's edge before the cheek is not a cheek.
const MIN_LIGAMENT_MM := 1.0
const HOLE_SEGMENTS := 24

const PLATE_SPACING_HINT := "The gap between the frame's two camera side plates. No frame publishes it, so 24 mm is a guess — measure yours and set it here. Saved with this drone."


static func settings(printing: Dictionary) -> Dictionary:
	var raw: Variant = printing.get(BLOCK, {})
	return raw if raw is Dictionary else {}


static func is_fitted(printing: Dictionary) -> bool:
	return bool(settings(printing).get(FITTED, false))


static func set_value(printing: Dictionary, key: String, value: Variant) -> void:
	var block := settings(printing).duplicate(true)
	match key:
		FITTED:
			block[FITTED] = bool(value)
		PLATE_SPACING:
			block[PLATE_SPACING] = clampf(float(value), MIN_PLATE_SPACING_MM, MAX_PLATE_SPACING_MM)
		_:
			push_warning("camera_mount has no setting '%s'" % key)
			return
	printing[BLOCK] = block


## Everything the cheek is made from, or a refusal. `tilt_deg` is the assembly's camera tilt.
static func dimensions(camera: Dictionary, printing: Dictionary, tilt_deg: float) -> Dictionary:
	var block := settings(printing)
	var raw: Variant = block.get(PLATE_SPACING, null)
	var guessed := not (raw is float or raw is int)
	var spacing := DEFAULT_PLATE_SPACING_MM if guessed \
		else clampf(float(raw), MIN_PLATE_SPACING_MM, MAX_PLATE_SPACING_MM)
	var clearance := PrintSettings.clearance_mm(printing)
	var out := {"ok": false, "reason": "", "plate_spacing_mm": spacing, "plate_spacing_guessed": guessed,
		"tilt_deg": tilt_deg, "clearance_mm": clearance, "hole_segments": HOLE_SEGMENTS}

	if camera.is_empty():
		out["reason"] = "%s: no camera is fitted" % PART_ID
		return out
	var camera_id := String(camera.get("part_id", "camera"))
	var specs: Dictionary = camera.get("specs", {})
	for field in ["length_mm", "width_mm", "height_mm"]:
		if specs.get(field) == null or float(specs[field]) <= 0.0:
			out["reason"] = "%s: %s publishes no %s" % [PART_ID, camera_id, field]
			return out
	var length := float(specs["length_mm"])
	var width := float(specs["width_mm"])
	var height := float(specs["height_mm"])
	var cheek := (spacing - width - 2.0 * clearance) * 0.5
	var hole_r := SCREW_DIAMETER_MM * 0.5 + clearance
	out.merge({"camera_length_mm": length, "camera_width_mm": width, "camera_height_mm": height,
		"cheek_thickness_mm": cheek, "hole_radius_mm": hole_r}, true)

	if cheek < MIN_CHEEK_MM:
		out["reason"] = "%s: %s is %.1f mm wide and the plate gap is %.1f mm%s, which leaves a %.2f mm cheek (under %.1f mm)" % [
			PART_ID, camera_id, width, spacing, " (guess)" if guessed else "", cheek, MIN_CHEEK_MM]
		return out
	if hole_r + MIN_LIGAMENT_MM > minf(length, height) * 0.5:
		out["reason"] = "%s: %s is too small (%.1f × %.1f mm) for an M2 screw hole" % [
			PART_ID, camera_id, length, height]
		return out
	out["ok"] = true
	return out


## One cheek as printable triangles: millimetres, lying flat — the silhouette in (X forward, Y up),
## the thickness along Z — wound OUTWARD, centred on the screw hole. Empty for a refused `dims`.
static func triangles_mm(dims: Dictionary) -> Array:
	var out: Array = []
	if not bool(dims.get("ok", false)):
		return out
	var half_t := float(dims["cheek_thickness_mm"]) * 0.5
	var r := float(dims["hole_radius_mm"])
	var n := int(dims["hole_segments"])
	var boundary := _boundary(dims)

	# The ring between the outline and the hole, walked once: each outline step fans to the hole vertex
	# of its angular bucket, and a step that lands on the next uniform angle closes the quad.
	var ring: Array = []
	for j in boundary.size():
		var p: Dictionary = boundary[j]
		var q: Dictionary = boundary[(j + 1) % boundary.size()]
		var hk := _hole(int(p["bucket"]), n, r)
		ring.append([hk, p["point"], q["point"]])
		if int(q["uniform"]) >= 0:
			ring.append([hk, q["point"], _hole(int(q["uniform"]), n, r)])

	for tri in ring:
		# Front face (+Z) counter-clockwise seen from +Z; the back face is the same triangle reversed.
		out.append(PackedVector3Array([_at(tri[0], half_t), _at(tri[1], half_t), _at(tri[2], half_t)]))
		out.append(PackedVector3Array([_at(tri[0], -half_t), _at(tri[2], -half_t), _at(tri[1], -half_t)]))

	for j in boundary.size():
		var a: Vector2 = boundary[j]["point"]
		var b: Vector2 = boundary[(j + 1) % boundary.size()]["point"]
		out.append(PackedVector3Array([_at(a, -half_t), _at(b, -half_t), _at(b, half_t)]))
		out.append(PackedVector3Array([_at(a, -half_t), _at(b, half_t), _at(a, half_t)]))

	for k in n:
		var a := _hole(k, n, r)
		var b := _hole((k + 1) % n, n, r)
		# The bore faces back into the hole.
		out.append(PackedVector3Array([_at(a, -half_t), _at(b, half_t), _at(b, -half_t)]))
		out.append(PackedVector3Array([_at(a, -half_t), _at(a, half_t), _at(b, half_t)]))
	return out


## The tipped silhouette's outline, counter-clockwise from angle 0: a point on the outline at every
## uniform hole angle, plus the four corners between them. Each entry is
## `{"angle", "point": Vector2, "uniform": k or -1, "bucket": the uniform index at or before it}`.
static func _boundary(dims: Dictionary) -> Array:
	var half_l := float(dims["camera_length_mm"]) * 0.5
	var half_h := float(dims["camera_height_mm"]) * 0.5
	var n := int(dims["hole_segments"])
	# The corners in the camera's own frame (Y up, −Z forward), tipped by THE tilt rotation — Build's,
	# the one ComponentMesh draws the camera with — then read as (forward, up) for printing.
	var tilt := Build.camera_tilt_transform(float(dims["tilt_deg"]))
	var corners: Array = []
	for yz in [Vector2(-half_h, half_l), Vector2(-half_h, -half_l), Vector2(half_h, -half_l), Vector2(half_h, half_l)]:
		var local: Vector3 = tilt * Vector3(0.0, yz.x, yz.y)
		corners.append(Vector2(-local.z, local.y))

	var step := TAU / n
	var entries: Array = []
	for k in n:
		entries.append({"angle": step * k, "point": _ray_to_outline(Vector2.from_angle(step * k), corners),
			"uniform": k})
	for c in corners:
		var angle := fposmod((c as Vector2).angle(), TAU)
		var nearest := roundi(angle / step)
		if absf(angle - step * nearest) < 1e-4:
			# A corner on a uniform ray: that ray's outline point IS the corner. Snap, never duplicate.
			entries[nearest % n]["point"] = c
			continue
		entries.append({"angle": angle, "point": c, "uniform": -1})
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["angle"]) < float(y["angle"]))

	var bucket := 0
	for e in entries:
		if int(e["uniform"]) >= 0:
			bucket = int(e["uniform"])
		e["bucket"] = bucket
	return entries


## Where a ray from the hole centre leaves the convex outline.
static func _ray_to_outline(direction: Vector2, corners: Array) -> Vector2:
	var best := INF
	for i in corners.size():
		var a: Vector2 = corners[i]
		var edge: Vector2 = corners[(i + 1) % corners.size()] - a
		var denom := direction.cross(edge)
		if absf(denom) < 1e-12:
			continue
		var s := a.cross(edge) / denom
		var u := a.cross(direction) / denom
		if s > 0.0 and u >= -1e-9 and u <= 1.0 + 1e-9:
			best = minf(best, s)
	return direction * best


static func _hole(k: int, n: int, r: float) -> Vector2:
	return Vector2.from_angle(TAU / n * k) * r


static func _at(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


## The cheek's volume by its closed form, mm³: the box side less a regular N-gon, times thickness.
static func volume_mm3(dims: Dictionary) -> float:
	if not bool(dims.get("ok", false)):
		return 0.0
	var n := int(dims["hole_segments"])
	var r := float(dims["hole_radius_mm"])
	return (float(dims["camera_length_mm"]) * float(dims["camera_height_mm"])
		- n * 0.5 * r * r * sin(TAU / n)) * float(dims["cheek_thickness_mm"])
