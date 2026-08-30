class_name PropellerMountProfile
extends Control
## The motor and its mount stack in side elevation — propulsion.md §7.1's third authoring view,
## slice P10d.
##
## ## What a builder is looking at, and why it is a view rather than four numbers
##
## Between the arm and the propeller there is a stack: a soft-mount pad, the motor's own mounting
## boss, the bell, the prop adapter, any shim washers, the prop, and the nut on top. Every one of
## those is a number somewhere in the app, and the questions they raise are all about the
## RELATIONSHIP between them — is the pad eating the screw thread, is the nut still on the shaft,
## does a 3 mm pad move the mount frequency somewhere the frame's first mode already is. Those are
## proportions, and proportions are a picture.
##
## ## It draws the model's own geometry, and this is the whole design
##
## The profile does not compute a single height. It takes a `MotorMesh` — the node Lab already
## builds and already puts on the aircraft — and draws a side elevation of the cylinders that node
## actually generated, reading each one's radius, height and centre off the mesh itself. So there
## is no second copy of the seat height, the shim reserve or the bell proportions to drift from
## `MotorMesh.rebuild`'s, and the drawn total height is the model's `total_height_m` by
## construction rather than by agreement.
##
## That is the same rule the rest of P10d holds to, in the one view where it was easiest to break:
## a side elevation is trivially re-derivable from `MotorMesh.dimensions()`, and a file that
## re-derived it would look correct on the day it was written and be wrong the first time the stack
## gained a part.
##
## ## What it will not draw
##
## An arm. The stack sits ON something, and what that something is belongs to Airframe — a profile
## that drew an arm would be this room making a claim about a frame it does not own, and the plate
## thickness under a motor is a number the airframe designer is already responsible for.

const MARGIN_PX := 16.0

## The motor stack this view draws, as a live `MotorMesh`. Held rather than copied, so a rebuild
## on the node is a rebuild in the picture.
var motor_mesh: MotorMesh

## The pad thickness in metres, carried only so the caption can name it. The pad's RECTANGLE comes
## off the mesh like everything else.
var soft_mount_m := 0.0
## The mount frequency the pad produces, or INF for no mount / a pad the model cannot read. Passed
## in rather than computed here: `SoftMount` owns it, and this view owning a second call to it
## would be a second answer.
var mount_f_n_hz := INF


func _init(p_motor_mesh: MotorMesh = null) -> void:
	motor_mesh = p_motor_mesh
	custom_minimum_size = Vector2(200, 150)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_stack(p_motor_mesh: MotorMesh, p_soft_mount_m: float, p_f_n_hz: float) -> void:
	motor_mesh = p_motor_mesh
	soft_mount_m = p_soft_mount_m
	mount_f_n_hz = p_f_n_hz
	queue_redraw()


## Every part of the stack as `{name, id, radius_m, bottom_m, top_m}`, read off the generated mesh in
## bottom-up order. The one function this view has, and the reason it cannot disagree with the
## model: a part that is not in the mesh is not in this list.
func parts() -> Array:
	var out: Array = []
	if motor_mesh == null:
		return out
	for child in motor_mesh.get_children():
		var node := child as MeshInstance3D
		if node == null:
			continue
		var cylinder := node.mesh as CylinderMesh
		if cylinder == null:
			continue
		var centre: float = node.position.y
		out.append({
			"name": String(node.name),
			# The node's own instance id. A rebuild frees these and makes new ones, so this is what
			# distinguishes "the stack did not change" from "the stack was rebuilt to the same
			# numbers" — a distinction every dimension in this dictionary is blind to.
			"id": node.get_instance_id(),
			"radius_m": maxf(cylinder.top_radius, cylinder.bottom_radius),
			"bottom_m": centre - cylinder.height * 0.5,
			"top_m": centre + cylinder.height * 0.5,
		})
	out.sort_custom(func(a, b): return float(a["bottom_m"]) < float(b["bottom_m"]))
	return out


## The full extent of what is drawn, in metres. Asserted against `MotorMesh.total_height_m` — one
## number, two places, and the check exists because those two places COULD drift and the picture
## is where a drift would be least visible.
func drawn_height_m() -> float:
	var top := 0.0
	for part in parts():
		top = maxf(top, float(part["top_m"]))
	return top


## Metres per pixel, fitted to the taller of height and width so the stack sits inside the view
## whatever its proportions. A 3" motor and a 16" motor then draw at different scales, which is
## right: the view is about proportion within one stack, never about comparing two.
func scale_px_per_m() -> float:
	var height := drawn_height_m()
	var widest := 0.0
	for part in parts():
		widest = maxf(widest, float(part["radius_m"]) * 2.0)
	if height <= 0.0 or widest <= 0.0:
		return 1.0
	return minf(maxf(size.y - MARGIN_PX * 2.0, 1.0) / height,
		maxf(size.x - MARGIN_PX * 2.0, 1.0) / widest)


## One part's rectangle in pixels. Public for the same reason the section view's corners are: the
## assertions are about where things land, and landing does not require a window.
func part_rect(part: Dictionary) -> Rect2:
	var px_per_m := scale_px_per_m()
	var centre_x := size.x * 0.5
	var floor_y := size.y - MARGIN_PX
	var half_width: float = float(part["radius_m"]) * px_per_m
	var top_y: float = floor_y - float(part["top_m"]) * px_per_m
	var bottom_y: float = floor_y - float(part["bottom_m"]) * px_per_m
	return Rect2(Vector2(centre_x - half_width, top_y),
		Vector2(half_width * 2.0, maxf(bottom_y - top_y, 1.0)))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)

	var floor_y := size.y - MARGIN_PX
	draw_line(Vector2(MARGIN_PX * 0.5, floor_y), Vector2(size.x - MARGIN_PX * 0.5, floor_y),
		LothalTheme.BORDER, 1.0)

	for part in parts():
		var part_name := String(part["name"])
		# The pad is the part this view exists to make arguable, so it is the one that is coloured
		# rather than outlined. Everything else is the context it sits in.
		var colour := LothalTheme.WARNING if part_name == "SoftMount" else LothalTheme.TEXT_MUTED
		var rect := part_rect(part)
		draw_rect(rect, Color(colour, 0.22))
		draw_rect(rect, colour, false, 1.0)

	if motor_mesh == null:
		return

	# The SEAT: where the propeller sits. A line rather than a part, because it is a height and not
	# a thing, and it is the number a spacer moves.
	var seat_y := floor_y - motor_mesh.prop_mount_height_m * scale_px_per_m()
	draw_line(Vector2(MARGIN_PX * 0.5, seat_y), Vector2(size.x - MARGIN_PX * 0.5, seat_y),
		LothalTheme.ACCENT, 1.0)

	var frequency := "no mount" if not is_finite(mount_f_n_hz) \
		else "%.0f Hz" % mount_f_n_hz
	var caption := "pad %.1f mm   seat %.1f mm   stack %.1f mm   f_n %s" % [
		soft_mount_m * 1000.0, motor_mesh.prop_mount_height_m * 1000.0,
		drawn_height_m() * 1000.0, frequency]
	draw_string(ThemeDB.fallback_font, Vector2(MARGIN_PX * 0.5, size.y - 3.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
