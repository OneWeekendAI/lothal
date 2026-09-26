class_name PackView
extends Control
## The pack on the frame, in plan and elevation, with the centre of mass marked —
## plans/2026-09-10-power-room-design.md §2.2, slice PW6.
##
## ---------------------------------------------------------------------------
## THIS VIEW CHANGES NO PHYSICS, AND THAT IS THE WHOLE ARGUMENT FOR IT
## ---------------------------------------------------------------------------
##
## `build.gd` has seated the pack at a real strap mount, with a real box inertia and a fore/aft
## offset out of `AssemblyTweaks`, since the pack stopped being a lump at the origin; and
## `AirframeProperties.compute` has returned the resulting centre of mass ever since. What has never
## existed is anywhere a builder can SEE that. Slide `battery_offset_mm` today and the only evidence
## is a tune that comes out slightly different. This draws the causation and adds no term to it.
##
## ---------------------------------------------------------------------------
## EVERY NUMBER HERE IS READ, NOT DERIVED
## ---------------------------------------------------------------------------
##
## Three quantities are drawn and none of them is computed in this file:
##
##   - **How big the pack is** — `Build.battery_size_of` through `battery_size_m()`, which exists
##     precisely because the catalog publishes packs in the part's own frame (length, width,
##     height) and the aircraft wants body axes (width across X, height up Y, length along Z). The
##     reorder is easy to get right in the physics and wrong in the picture, so the picture does not
##     do it: it asks the one function that does.
##   - **Where the pack sits** — the `"Pack"` entry in `build.mass_parts()`, which is the position
##     `MountLayout.seated_centre_m` put it at and the position it is WEIGHED at. Resolving the
##     mount and re-running that sum here would be a second answer to "where is the pack", and the
##     project has already paid for one of those (main.tscn's hardcoded 0.0778 against MotorLayout).
##   - **Where the mass ends up** — `AirframeProperties.compute`. Not a first-moment sum of this
##     file's own. That is the Build-free rule stated for a marker rather than for a mesh, and
##     `tests/test_power_room.gd` proves it by changing the pack's MASS — a quantity nothing in this
##     drawing's geometry depends on — and requiring the marker to move.
##
## ---------------------------------------------------------------------------
## THE FRAME STAND-IN IS DROPPED FROM `extra_parts`, AND IT HAS TO BE
## ---------------------------------------------------------------------------
##
## `AirframeProperties.compute` weighs the frame from the DOCUMENT'S OWN PLATES — ρ·t·A over real
## outlines — and `mass_parts()` also carries a `"Frame"` box, the `frames.json` mass at a ratio-
## chosen size, which is the stand-in that file is honest about being. Passing the whole parts list
## through would weigh the frame twice, and because the stand-in sits exactly at the origin the
## symptom is not a wrong-looking picture: it is a centre of mass dragged toward the middle by a
## hundred grams of frame that is not there. So the stand-in is dropped by label, and
## `tests/test_power_room.gd` pins the marker's fore/aft figure against `MassProperties` over the
## SAME parts list — the aircraft's own flight centre of mass — so the two cannot part company.
##
## ---------------------------------------------------------------------------
## TWO PANES, ONE SCALE, AND THE FORE/AFT AXIS SHARED
## ---------------------------------------------------------------------------
##
## Plan above, elevation below, both drawn with FORE/AFT ACROSS — nose to the left, aft to the
## right. Sharing that axis between the panes is what makes the view answer its question: the offset
## the builder is sliding runs left-right in both, so the pack and the marker move together and in
## the same direction. Two panes on two different horizontal axes would be two drawings that happen
## to be adjacent.
##
## One px-per-mm for both, `HarnessSchematic`'s rule for its reason: a pane with a scale of its own
## is a second opinion about the drawing, and nothing would keep the two in step by anything but
## hand.
##
## ---------------------------------------------------------------------------
## A CONTROL DOES NOT CLIP ITS OWN `_draw`
## ---------------------------------------------------------------------------
##
## So the fit is over a bounds that already includes the marker's arms and the pack's outline, and
## `content_rect()` is derived from the same geometry the drawing uses rather than measured a second
## time. A marker drawn past the edge would land on the inspector.

## Clear space around the drawing, and the gap between the two panes. In pixels and millimetres
## respectively: the margin is chrome, the gap is part of the thing being fitted.
const MARGIN_PX := 14.0
const PANE_GAP_MM := 12.0

## The marker's arms, in pixels — chrome, like `HarnessSchematic`'s selection ring and for the same
## reason: an arm that scaled with the drawing would be a smudge on a whoop and a hairline on a
## cinelifter.
const MARKER_ARM_PX := 9.0
const MARKER_WIDTH_PX := 2.0

## Line weights, pixels.
const PLATE_WIDTH_PX := 1.5
const PACK_WIDTH_PX := 2.0
const MOUNT_WIDTH_PX := 3.0

## A floor under the elevation's plate rectangles. A 2 mm plate at a whoop's scale rounds to nothing
## and the elevation loses the surface the pack is strapped to — the one thing that pane is for.
const MIN_PLATE_PX := 1.0

## The label the frame stand-in carries in `mass_parts()`. Matched by name because that is the only
## handle a `PartMass` offers, and a mislabelled entry here is a visibly wrong marker rather than a
## silent one — see the header for what dropping it is about.
const FRAME_PART_LABEL := "Frame"

## The shipped material table. Loaded once and shared, `AirframePanel`'s arrangement: it is a
## catalog, not build state, and re-reading it per repaint would be file I/O inside a view.
static var _materials_shared: FrameMaterials = null

var _build: Build = null
var _frame: AirframeDocument = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(360, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Puts an aircraft and the frame it is built on in front of the drawing.
##
## ONE FUNCTION TAKING BOTH, `HarnessSchematic.show_harness`'s discipline and W0.7's: a `set_build`
## with a `set_frame` beside it is an argument a caller can forget, and the forgotten one would draw
## this pack on the previous frame's plates.
##
## The document is passed in rather than derived from `build.frame` here, and that is not
## fastidiousness: Lab regenerates it only when the FRAME changes, precisely so an edit made in the
## Airframe room survives a pack change. A document re-derived in this file would quietly discard
## those edits and draw a catalog frame nobody is flying.
func show_pack(build: Build, frame: AirframeDocument) -> void:
	_build = build
	_frame = frame
	queue_redraw()


static func materials() -> FrameMaterials:
	if _materials_shared == null:
		_materials_shared = FrameMaterials.load_default()
	return _materials_shared


# ---------------------------------------------------------------------------
# The drawing, derived
# ---------------------------------------------------------------------------

## Everything drawn, in THIS control's pixel coordinates, recomputed from the build on every call.
##
## Keys: `scale` (px per mm), `plates_plan` / `plates_elevation`, `pack_plan` / `pack_elevation`,
## `mount_plan` / `mount_elevation`, `com_plan` / `com_elevation`, and the metre-space figures the
## drawing was made from — `com_m`, `pack_centre_m`, `pack_size_m`, `frame_centre_m`, `offset_mm`.
##
## Empty for no build and for no frame, both of which are real states: the room is constructed
## before an aircraft reaches it.
func geometry() -> Dictionary:
	var empty := {"scale": 0.0, "plates_plan": [], "plates_elevation": [],
		"pack_plan": Rect2(), "pack_elevation": Rect2(), "mount_plan": Rect2(),
		"mount_elevation": Rect2(), "com_plan": Vector2.ZERO, "com_elevation": Vector2.ZERO,
		"frame_centre_plan": Vector2.ZERO,
		"com_m": Vector3.ZERO, "pack_centre_m": Vector3.ZERO, "pack_size_m": Vector3.ZERO,
		"frame_centre_m": Vector3.ZERO, "offset_mm": 0.0}
	if _build == null or _frame == null:
		return empty

	var parts := _build.mass_parts()
	var pack_centre := _pack_centre_m(parts)
	var pack_size := _build.battery_size_m()
	var com := centre_of_mass_m()
	var offset_mm := float(_build.assembly_value("battery_offset_m")) * 1000.0

	# --- millimetre space. Plan: fore/aft across, lateral down. Elevation: fore/aft across, up up.
	var plates_plan: Array = []
	var plates_elevation: Array = []
	var plan_bounds := Rect2()
	var elevation_bounds := Rect2()
	var started := false
	for plate in _frame.plates:
		var outline := AirframeDocument.plate_outline(plate)
		if outline.size() < 3:
			continue
		# Plate `u` is world X and `v` is world Z (AirframeDocument's stated mapping), so the plan
		# point is the v/u pair swapped — the axes are the document's, only the page is turned.
		var polygon := PackedVector2Array()
		var span := Rect2()
		for i in outline.size():
			var point := Vector2(outline[i].y, outline[i].x)
			polygon.append(point)
			span = Rect2(point, Vector2.ZERO) if i == 0 else span.expand(point)
		plates_plan.append(polygon)

		# In elevation a plate is what it is: a flat sheet seen edge-on. Its fore/aft extent is the
		# outline's own, and its height is the stock thickness at the height it is stacked at.
		var thickness := AirframeDocument.plate_thickness_mm(plate)
		var z_mm := AirframeDocument.plate_z_mm(plate)
		var edge := Rect2(span.position.x, -z_mm - thickness * 0.5, span.size.x, thickness)
		plates_elevation.append(edge)

		plan_bounds = span if not started else plan_bounds.merge(span)
		elevation_bounds = edge if not started else elevation_bounds.merge(edge)
		started = true
	if not started:
		return empty
	# The FRAME's own centre, before the pack or the marker are merged into the bounds. What row
	# three of the plan's table compares the marker against, and it has to be the plates and only
	# the plates or the comparison is the marker against itself.
	var frame_centre_mm := plan_bounds.get_center()

	var pack_plan := Rect2(
		Vector2(pack_centre.z - pack_size.z * 0.5, pack_centre.x - pack_size.x * 0.5) * 1000.0,
		Vector2(pack_size.z, pack_size.x) * 1000.0)
	var pack_elevation := Rect2(
		Vector2(pack_centre.z - pack_size.z * 0.5, -pack_centre.y - pack_size.y * 0.5) * 1000.0,
		Vector2(pack_size.z, pack_size.y) * 1000.0)

	var mount := _mount()
	var mount_plan := Rect2()
	var mount_elevation := Rect2()
	if mount != null:
		mount_plan = Rect2(
			Vector2(mount.position.z - mount.span_m.y * 0.5,
				mount.position.x - mount.span_m.x * 0.5) * 1000.0,
			Vector2(mount.span_m.y, mount.span_m.x) * 1000.0)
		mount_elevation = Rect2(
			Vector2((mount.position.z - mount.span_m.y * 0.5) * 1000.0,
				-mount.position.y * 1000.0),
			Vector2(mount.span_m.y * 1000.0, 0.0))
		plan_bounds = plan_bounds.merge(mount_plan)
		elevation_bounds = elevation_bounds.merge(mount_elevation)

	var com_plan := Vector2(com.z, com.x) * 1000.0
	var com_elevation := Vector2(com.z, -com.y) * 1000.0

	plan_bounds = plan_bounds.merge(pack_plan).merge(Rect2(com_plan, Vector2.ZERO))
	elevation_bounds = elevation_bounds.merge(pack_elevation).merge(Rect2(com_elevation, Vector2.ZERO))

	# The elevation pane is slid down until it clears the plan pane, and both are then fitted as one
	# drawing — see the header for why they are not fitted separately.
	var drop := plan_bounds.end.y + PANE_GAP_MM - elevation_bounds.position.y
	var slid := Vector2(0.0, drop)
	elevation_bounds.position += slid
	pack_elevation.position += slid
	mount_elevation.position += slid
	com_elevation += slid
	for i in plates_elevation.size():
		plates_elevation[i] = Rect2(plates_elevation[i].position + slid, plates_elevation[i].size)

	var bounds := plan_bounds.merge(elevation_bounds)
	# The marker's arms are pixels, so they are grown out of the bounds in millimetres AFTER a
	# provisional scale would be known — which is circular. Reserving the arms as a margin instead
	# costs a few pixels of fit and cannot be circular. A Control does not clip its own `_draw`.
	var usable := size - Vector2.ONE * (MARGIN_PX + MARKER_ARM_PX + MARKER_WIDTH_PX) * 2.0
	if usable.x <= 0.0 or usable.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return empty
	var px_per_mm := minf(usable.x / bounds.size.x, usable.y / bounds.size.y)
	var inset := MARGIN_PX + MARKER_ARM_PX + MARKER_WIDTH_PX
	var origin := Vector2(inset, inset) + (usable - bounds.size * px_per_mm) * 0.5 \
		- bounds.position * px_per_mm

	var plan_px: Array = []
	for polygon in plates_plan:
		var out := PackedVector2Array()
		for point in polygon:
			out.append(point * px_per_mm + origin)
		plan_px.append(out)
	var elevation_px: Array = []
	for edge in plates_elevation:
		var rect := _to_px(edge, px_per_mm, origin)
		elevation_px.append(Rect2(rect.position, Vector2(rect.size.x, maxf(rect.size.y, MIN_PLATE_PX))))

	return {
		"scale": px_per_mm,
		"plates_plan": plan_px,
		"plates_elevation": elevation_px,
		"pack_plan": _to_px(pack_plan, px_per_mm, origin),
		"pack_elevation": _to_px(pack_elevation, px_per_mm, origin),
		"mount_plan": _to_px(mount_plan, px_per_mm, origin) if mount != null else Rect2(),
		"mount_elevation": _to_px(mount_elevation, px_per_mm, origin) if mount != null else Rect2(),
		"com_plan": com_plan * px_per_mm + origin,
		# The frame's own centre, in the same pixels as the marker. Carried rather than left to a
		# caller to reconstruct: recovering it needs the scale AND the origin, and a check that
		# rebuilt those would be checking its own arithmetic instead of the drawing's.
		"frame_centre_plan": frame_centre_mm * px_per_mm + origin,
		"com_elevation": com_elevation * px_per_mm + origin,
		"com_m": com,
		"pack_centre_m": pack_centre,
		"pack_size_m": pack_size,
		"frame_centre_m": Vector3(frame_centre_mm.y, 0.0, frame_centre_mm.x) * 0.001,
		"offset_mm": offset_mm,
	}


## The aircraft's centre of mass, from `AirframeProperties` and from nowhere else.
##
## Public because the room quotes the figure beside the drawing and a second call is a second
## chance to disagree — the readout and the marker are one function called twice, which is the same
## arrangement `HarnessChecks.segments` is under.
func centre_of_mass_m() -> Vector3:
	if _build == null or _frame == null:
		return Vector3.ZERO
	return AirframeProperties.compute(_frame, materials(), _extra_parts()).cg_m


## `mass_parts()` less the frame stand-in — see the header. Everything else goes through: the
## motors at the arm tips, the boards on their standoffs, the harness at its real positions, and
## the pack wherever it was just slid to.
func _extra_parts() -> Array:
	var out: Array = []
	for part in _build.mass_parts():
		if part.label != FRAME_PART_LABEL:
			out.append(part)
	return out


## Where the pack is, taken from the entry that is weighed there rather than re-seated here.
static func _pack_centre_m(parts: Array) -> Vector3:
	for part in parts:
		if part.label == "Pack":
			return part.position_m
	return Vector3.ZERO


## The strap the pack is on, resolved the way `Build.mass_parts()` resolves it, fallback included:
## a frame that does not offer the saved mount falls back to the top plate rather than dropping the
## pack at the origin. Drawn only — where the pack ENDS UP comes from the parts list above, so a
## disagreement between this and the physics shows as a pack floating off its strap and not as a
## silently wrong position.
func _mount() -> MountPoint:
	var mounts := _build.mount_points()
	var mount := MountLayout.by_id(mounts, String(_build.assembly_value("battery_mount")))
	return mount if mount != null else MountLayout.by_id(mounts, "strap_top")


static func _to_px(rect_mm: Rect2, px_per_mm: float, origin: Vector2) -> Rect2:
	return Rect2(rect_mm.position * px_per_mm + origin, rect_mm.size * px_per_mm)


## Everything the drawing occupies, from the same geometry the drawing uses.
func content_rect() -> Rect2:
	var g := geometry()
	if float(g["scale"]) <= 0.0:
		return Rect2()
	var out := Rect2(g["pack_plan"] as Rect2)
	out = out.merge(g["pack_elevation"])
	for polygon in g["plates_plan"]:
		for point in polygon:
			out = out.expand(point)
	for rect in g["plates_elevation"]:
		out = out.merge(rect)
	var arm := Vector2.ONE * (MARKER_ARM_PX + MARKER_WIDTH_PX * 0.5)
	out = out.merge(Rect2(g["com_plan"] as Vector2 - arm, arm * 2.0))
	out = out.merge(Rect2(g["com_elevation"] as Vector2 - arm, arm * 2.0))
	return out


func _draw() -> void:
	var g := geometry()
	if float(g["scale"]) <= 0.0:
		return

	for polygon in g["plates_plan"]:
		var closed := PackedVector2Array(polygon)
		closed.append(polygon[0])
		draw_polyline(closed, LothalTheme.TEXT_MUTED, PLATE_WIDTH_PX)
	for rect in g["plates_elevation"]:
		draw_rect(rect, LothalTheme.TEXT_MUTED, false, PLATE_WIDTH_PX)

	for key in ["mount_plan", "mount_elevation"]:
		var mount_rect: Rect2 = g[key]
		if mount_rect.size.x > 0.0:
			draw_line(Vector2(mount_rect.position.x, mount_rect.get_center().y),
				Vector2(mount_rect.end.x, mount_rect.get_center().y),
				LothalTheme.ACCENT, MOUNT_WIDTH_PX)

	draw_rect(g["pack_plan"], LothalTheme.TEXT_MAIN, false, PACK_WIDTH_PX)
	draw_rect(g["pack_elevation"], LothalTheme.TEXT_MAIN, false, PACK_WIDTH_PX)

	for key in ["com_plan", "com_elevation"]:
		var at: Vector2 = g[key]
		draw_line(at - Vector2(MARKER_ARM_PX, 0.0), at + Vector2(MARKER_ARM_PX, 0.0),
			LothalTheme.ACCENT, MARKER_WIDTH_PX)
		draw_line(at - Vector2(0.0, MARKER_ARM_PX), at + Vector2(0.0, MARKER_ARM_PX),
			LothalTheme.ACCENT, MARKER_WIDTH_PX)
