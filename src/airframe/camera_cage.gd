class_name CameraCage
extends RefCounted
## Camera side plates — airframe gaps G5. Two upright plates either side of the FPV camera, each with
## the camera's pivot screw hole and a curved slot the second screw rides in, so the camera can be
## tilted 0–50° and clamped.
##
## ## Upright plates, and what "upright" means in the document
##
## A side plate is an ordinary plate whose role is `side` (`AirframeDocument.is_upright`). Its outline
## is drawn in ITS OWN PLANE, `(s, h)`: `s` is fore/aft (world Z, aft +, exactly like plan `v`) and `h`
## is height above the plate's base (world Y). The plane stands at `x_mm` (world X) and its base at
## `z_mm`, and the stock thickness is centred on `x_mm`. So the same polygon that is weighed, extruded
## and exported is the shape the cutter makes; only where it stands differs from a flat plate.
##
## ## The cage's numbers, and which are guesses
##
## The SPACING is the camera's width — that is the one figure that has to be right, because the camera
## is screwed through the plates into its own side holes and a cage narrower than the body does not
## close round it. Widths come from `cameras.json` where a part of that class exists, so a cage and the
## camera it is meant for agree to the hundredth of a millimetre.
##
## The PROFILE is proportioned from that width and is a GUESS, named as one: the pivot at mid-height
## of the body, the plate as tall as the camera is wide, the slot on a radius of 0.35 × width behind the
## pivot. Real cages vary; these are numbers a builder drags, not a claim about any vendor's part.

## The three camera classes "+ Camera cage" offers. `width_mm` is the fallback; `part_id` is the
## catalog camera whose published width overrides it (cameras.json lists the full-size body at 26 mm).
const SIZES := [
	{"id": "nano", "label": "Nano", "part_id": "cam_nano_analog", "width_mm": 14.0},
	{"id": "micro", "label": "Micro", "part_id": "cam_micro_analog", "width_mm": 19.0},
	{"id": "full", "label": "Full", "part_id": "cam_fullsize_analog", "width_mm": 22.0},
]

## The tilt range the slot covers, degrees of camera uptilt.
const TILT_MIN_DEG := 0.0
const TILT_MAX_DEG := 50.0

## M2 screws hold every camera in the catalog; the clearance hole is the project's +0.2 mm.
const SCREW_D_MM := 2.0
const DEFAULT_THICKNESS_MM := 2.0

## Proportions of the profile, as fractions of the camera width (guesses — see class docs).
const PIVOT_HEIGHT_PER_WIDTH := 0.5
const PLATE_HEIGHT_PER_WIDTH := 1.0
const FRONT_PER_WIDTH := 0.3
const REAR_PER_WIDTH := 0.6
const SLOT_RADIUS_PER_WIDTH := 0.35
## Outer corner radius of the plate. Convex, so the bit swings round it; rounded only so a plate's
## corner is not a point that splits on the first crash.
const CORNER_RADIUS_MM := 2.0

## A camera within this of the cage spacing fits: the hundredth a published width is quoted to.
const FIT_TOLERANCE_MM := 0.01

const CAMERA_WIDER_THAN_CAGE := &"camera_wider_than_cage"

## Plate key: the camera width this cage was cut for. INFORMATIONAL only — the fit check measures the
## spacing off the plates' own `x_mm` and thickness, so a cage somebody moved is judged where it is.
const PLATE_CAGE_WIDTH := "camera_cage_width_mm"


## The camera width for one of `SIZES`, by id: the catalog's published width when that camera exists.
static func size_width_mm(size_id: String, catalog: PartsCatalog = null) -> float:
	for size in SIZES:
		if str(size["id"]) != size_id:
			continue
		if catalog != null:
			var part := catalog.get_part(str(size["part_id"]))
			if part != null and not part.is_empty():
				var published := float((part.get("specs", {}) as Dictionary).get("width_mm", 0.0))
				if published > 0.0:
					return published
		return float(size["width_mm"])
	return 0.0


## The plate's outline in its own (s, h) plane: a rounded rectangle from `front` to `rear` along s and
## 0 to `height` along h. Counter-clockwise, so its area is positive.
static func outline_sh(front_s: float, rear_s: float, height: float) -> PackedVector2Array:
	var r := minf(CORNER_RADIUS_MM, minf(rear_s - front_s, height) * 0.25)
	var out := PackedVector2Array()
	var corners := [
		[Vector2(rear_s - r, r), -PI * 0.5],
		[Vector2(rear_s - r, height - r), 0.0],
		[Vector2(front_s + r, height - r), PI * 0.5],
		[Vector2(front_s + r, r), PI],
	]
	for corner in corners:
		out.append_array(PolygonProps.tessellate_arc(corner[0], r, float(corner[1]), PI * 0.5,
			PolygonProps.DEFAULT_CHORD_TOLERANCE_MM))
	return _deduped(out)


## The tilt slot: a band of width `slot_w` on a circle of `radius` about the pivot, from the screw's
## place at `TILT_MIN_DEG` to its place at `TILT_MAX_DEG`, with round ends. Tilting the nose UP swings a
## screw behind the pivot DOWN, so the slot runs from straight aft (angle 0) to 50° below it. Wound
## clockwise, so it subtracts.
static func tilt_slot_sh(pivot: Vector2, radius: float, slot_w: float) -> PackedVector2Array:
	var half := slot_w * 0.5
	var a0 := -deg_to_rad(TILT_MIN_DEG)
	var a1 := -deg_to_rad(TILT_MAX_DEG)
	var sweep := a1 - a0
	var sigma := signf(sweep)
	var tol := PolygonProps.DEFAULT_CHORD_TOLERANCE_MM
	var c0 := pivot + Vector2(cos(a0), sin(a0)) * radius
	var c1 := pivot + Vector2(cos(a1), sin(a1)) * radius
	var out := PackedVector2Array()
	out.append_array(PolygonProps.tessellate_arc(pivot, radius + half, a0, sweep, tol))
	out.append_array(PolygonProps.tessellate_arc(c1, half, a1, sigma * PI, tol))
	out.append_array(PolygonProps.tessellate_arc(pivot, radius - half, a1, -sweep, tol))
	out.append_array(PolygonProps.tessellate_arc(c0, half, a0 + PI, sigma * PI, tol))
	out = _deduped(out)
	if PolygonProps.area(out) > 0.0:
		out = PolygonProps.reversed(out)
	return out


## One side plate of a cage for a camera `width_mm` wide, its pivot at `pivot_s` along the frame and
## its base at `base_z_mm`, standing at `x_mm`. `{outline, holes}` in the plate's own plane.
static func plate_profile(width_mm: float) -> Dictionary:
	var pivot := Vector2(0.0, width_mm * PIVOT_HEIGHT_PER_WIDTH)
	var hole_d := SCREW_D_MM + AirframeDocument.BOLT_CLEARANCE_MM
	var outline := outline_sh(-width_mm * FRONT_PER_WIDTH, width_mm * REAR_PER_WIDTH,
		width_mm * PLATE_HEIGHT_PER_WIDTH)
	var holes: Array = [
		PolygonProps.tessellate_circle(pivot, hole_d * 0.5, PolygonProps.DEFAULT_CHORD_TOLERANCE_MM,
			true),
		tilt_slot_sh(pivot, width_mm * SLOT_RADIUS_PER_WIDTH, hole_d),
	]
	return {"outline": outline, "holes": holes, "pivot": pivot}


## Where a cage goes on a document: the pivot at the FRONT edge of the lowest bottom plate (MountLayout's
## camera bay is that edge), standing on that plate's upper face. `{pivot_s, base_z_mm}`; a frame with
## no plates puts it at the origin.
static func seat(document: AirframeDocument) -> Dictionary:
	var best: Dictionary = {}
	for plate in document.plates:
		if AirframeDocument.is_upright(plate):
			continue
		var role := str(plate.get("role", ""))
		if best.is_empty() or (role == AirframeDocument.ROLE_BOTTOM
				and str(best.get("role", "")) != AirframeDocument.ROLE_BOTTOM) \
				or (role == str(best.get("role", "")) and AirframeDocument.plate_z_mm(plate)
					< AirframeDocument.plate_z_mm(best)):
			best = plate
	if best.is_empty():
		return {"pivot_s": 0.0, "base_z_mm": 0.0}
	var front := INF
	for point in AirframeDocument.plate_outline(best):
		front = minf(front, point.y)
	return {"pivot_s": front if is_finite(front) else 0.0,
		"base_z_mm": AirframeDocument.plate_z_mm(best) + AirframeDocument.plate_thickness_mm(best)}


## The clear width between the cage's two plates, mm: the nearest plate on the right's inner face
## minus the nearest on the left's. -1 when the document has no plate on each side of the centreline.
static func spacing_mm(document: AirframeDocument) -> float:
	if document == null:
		return -1.0
	var right := INF
	var left := -INF
	for plate in document.plates:
		if not AirframeDocument.is_upright(plate):
			continue
		var x := AirframeDocument.plate_x_mm(plate)
		var half_t := AirframeDocument.plate_thickness_mm(plate) * 0.5
		if x > 0.0:
			right = minf(right, x - half_t)
		elif x < 0.0:
			left = maxf(left, x + half_t)
	if not is_finite(right) or not is_finite(left):
		return -1.0
	return right - left


## LIMITING when the fitted camera is wider than the cage it has to sit in. Nothing when there is no
## cage, no camera, or the camera publishes no width — no number, no claim.
static func warnings(camera: Dictionary, document: AirframeDocument) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var spacing := spacing_mm(document)
	if spacing < 0.0 or camera == null or camera.is_empty():
		return out
	var width := float((camera.get("specs", {}) as Dictionary).get("width_mm", 0.0))
	if width <= 0.0 or width <= spacing + FIT_TOLERANCE_MM:
		return out
	out.append(BuildWarning.limiting(CAMERA_WIDER_THAN_CAGE,
		("The %s is %.1f mm wide and the camera side plates are %.1f mm apart, so it does not fit " +
		"between them. Cut a cage for a %.0f mm camera, or fit a narrower camera.") % [
			str(camera.get("name", "camera")), width, spacing, width],
		{"camera_width_mm": width, "spacing_mm": spacing}))
	return out


static func _deduped(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		if out.is_empty() or out[out.size() - 1].distance_to(point) > 1.0e-6:
			out.append(point)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 1.0e-6:
		out.remove_at(out.size() - 1)
	return out
