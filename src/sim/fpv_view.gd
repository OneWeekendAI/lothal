class_name FpvView
extends PanelContainer
## The feed from the fitted camera, in the field — a corner inset by default, and the whole screen
## on a keypress.
##
## THIS IS A FEED AND NOT A FIT CHECK, which is the difference between this class and the Lab inset
## it replaces. That inset rendered a parked aircraft, where the only question a lens can answer is
## a geometric one (do my props show, does the pack block the glass), and it answered it in a box
## the size of a postage stamp beside the aircraft itself. Here the aircraft is moving, the props
## are turning at the RPM the physics computed, and the question is the one the camera is actually
## for: can you fly off it. That question needs the full screen, so it gets it.
##
## THE FIELD OF VIEW IS A STATED PLACEHOLDER AND IS NOT A PROPERTY OF THE FITTED CAMERA, and moving
## this from the bench to the air raises the stakes rather than lowering them — a number you fly off
## is read harder than a number you glance at. `cameras.json`'s schema still bans resolution and
## lens FOV from `specs` by name, this class still reads no optical spec of any part, and every
## camera in the catalog still renders through the same PLACEHOLDER_FOV_DEG. The two reasons are
## unchanged, and the second is still the interesting one:
##
##   - nobody has sourced FOV figures for these entries, and the catalog's rule is that a published
##     number is a measured one. A plausible 150 deg per entry would be this project computing a
##     spec instead of reading one.
##   - A REAL FPV LENS IS A FISHEYE AND THIS IS A RECTILINEAR PROJECTION. Real cameras in this class
##     are sold at 150-170 deg diagonal, and a perspective Camera3D asked for that stretches the
##     corners into uselessness — the picture would be wrong in a way that looks like a bug rather
##     than like a wide lens. So even with sourced numbers, feeding them straight to `fov` would be
##     dishonest. Rendering a genuine FPV image needs a fisheye projection, which is a real slice.
##
## Because of that the caption is not decoration and is on screen in BOTH modes, saying which view
## is which and that the angle is a placeholder. The header's argument is worth nothing if the
## screen implies a spec it is not reading.
##
## THERE IS NO CAMERA TILT, AND IT IS A WORSE GAP HERE THAN IT WAS ON THE BENCH. Real builds run
## 15-40 deg of uptilt and it is the most-adjusted thing on a quad; MountLayout's camera bay is a
## seat and a normal with no angle in it at all. Level, you fly staring at the horizon and have to
## pitch hard to see what you are flying at — which is a real setup (a 0-degree cinematic build) but
## not the one most people fly, and on the bench it cost nothing while here it costs you the lap.
## Tilt is a property of the BUILD rather than of the part, so it belongs in AssemblyTweaks beside
## standoff height and pack offset, and it is its own slice.
##
## WHAT IS DELIBERATELY ABSENT is everything about the LINK: no static, no breakup at range, no
## RSSI, and no path from VTX power or antenna choice to picture quality. A 25 mW setup on a stock
## whoop antenna does not go grey at the far gate here, and it would in life. That is a slice of its
## own and it needs the same sourced-numbers discipline the FOV above is held to — inventing a
## range at which the picture breaks up would be exactly the fabricated spec this header refuses.

## Horizontal degrees, held for every camera in the catalog. See the header: this is a framing
## choice, not an optical spec, and it is deliberately narrower than the class really is.
const PLACEHOLDER_FOV_DEG := 90.0
## The near plane for the FPV lens. Tiny, because the eye is INSIDE the aircraft: at the chase
## camera's 2 cm the pack and the camera's own lens barrel would be clipped away and the feed would
## look clear when it is not.
const NEAR_M := 0.002
## Render size of the inset. Small on purpose — it is a corner inset, and the mode that is meant to
## be flown off is the full-screen one. 16:9 to match the main viewport rather than asserting a
## sensor aspect, which would be a claim about the fitted camera of the kind the header refuses.
const VIEW_SIZE := Vector2i(400, 225)
## How big the inset sits on screen.
const PANEL_SIZE := Vector2(240.0, 135.0)

## The marker on the drawn camera the feed is taken from, or null when no camera is fitted. Held
## rather than re-fetched so the "not fitted" state is one check in one place.
var _eye: Node3D
var _viewport: SubViewport
var _inset_camera: Camera3D
var _caption: Label
var _empty: Label
## Which viewport the FPV lens is currently rendering into: false = the inset, true = the main
## viewport (the whole screen), with the chase view demoted to the inset.
var _fpv_is_main := false
## The chase camera's authored lens, captured from the scene's own Camera3D before the first swap.
## See _apply_chase_lens for why these are read rather than written.
var _chase_fov := 75.0
var _chase_near := 0.02
var _chase_lens_captured := false


## The inset borrows the main viewport's World3D by inheritance rather than by assignment —
## `own_world_3d` is left false and `world_3d` is never touched, so this SubViewport draws whatever
## world its ancestor viewport draws, which in the field is the one and only flying aircraft.
##
## THIS IS THE HALF LAB GOT WRONG. The Lab inset sat under a SubViewport that carried its OWN world,
## so it could not inherit and had to be handed one — and a viewport has no World3D until it enters
## the tree, so the world captured in Lab's constructor was null every time and the box rendered
## nothing. Sim's flight scene IS the root viewport's world, so there is nothing to capture, nothing
## to time, and no lifecycle to get wrong: a plain nested SubViewport is already looking at it.
func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	add_child(column)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.add_theme_font_size_override("font_size", 11)
	column.add_child(_caption)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = PANEL_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.own_world_3d = false
	# Held down to the small render target above rather than the window size, because this is the
	# world drawn a SECOND time every frame. UPDATE_WHEN_VISIBLE so that hiding the inset costs
	# nothing at all rather than costing a hidden render.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)

	_inset_camera = Camera3D.new()
	_inset_camera.name = "InsetLens"
	_inset_camera.keep_aspect = Camera3D.KEEP_WIDTH
	container.add_child(_empty_label())
	_viewport.add_child(_inset_camera)

	_refresh()


func _empty_label() -> Label:
	_empty = Label.new()
	_empty.name = "NotFitted"
	_empty.text = "no camera fitted"
	_empty.add_theme_font_size_override("font_size", 12)
	_empty.set_anchors_preset(Control.PRESET_CENTER)
	return _empty


## Points the feed at the lens of the airframe just rebuilt, or at nothing when this build has no
## camera. Called on every build change, and it MUST be: a rebuild frees the old ComponentMesh, so
## an eye held across one is a freed node.
##
## The not-fitted case is not an edge case (an AIO whoop carries no separate camera, and that is a
## real build). The inset stays where it is and says so, rather than vanishing and reflowing the
## screen around a panel that comes and goes — and FPV drops out of main, because there is no lens
## to fly off and leaving the screen black would read as a crash.
func attach(eye: Node3D) -> void:
	_eye = eye
	if not is_fitted():
		_fpv_is_main = false
	_refresh()


## Swaps which viewport the FPV lens renders into, and returns whether it is now the main one.
## Refuses when no camera is fitted — there is nothing to swap to.
func toggle_main() -> bool:
	if not is_fitted():
		return false
	_fpv_is_main = not _fpv_is_main
	_refresh()
	return _fpv_is_main


func is_fpv_main() -> bool:
	return _fpv_is_main


func is_fitted() -> bool:
	return _eye != null and is_instance_valid(_eye)


## The camera living in the inset viewport. Never reparented and never swapped out — see
## place_lenses() for why the swap moves the PLACEMENT rather than the node.
func inset_camera() -> Camera3D:
	return _inset_camera


## Drives both lenses for this frame: `main_camera` is the scene's own Camera3D, `chase` is the
## placement the chase cam has computed for itself, and the eye supplies the FPV placement.
##
## THE SWAP MOVES THE PLACEMENT, NOT THE NODE, and that is the whole design. Reparenting a camera
## between viewports, or toggling `current` on four of them, has a state in which a viewport has no
## camera at all — one frame of black, or a whole mode that renders nothing if the ordering is ever
## disturbed. Here both nodes exist for the lifetime of the scene, each is permanently current in
## its own viewport, and all a swap changes is which of the two receives the eye's transform and
## which receives the chase's. There is no camera-less state to reach.
##
## THE FPV PLACEMENT IS A TRANSFORM COPY, INCLUDING ROLL. The eye is a marker on the drawn camera,
## seated by the same MountLayout.seated_centre_m() call the mass model uses, so its transform is
## the one answer to where the lens is and which way it looks. Recomputing an eye position here from
## the bay and the part's dimensions would be a second copy of that sum — the divergence
## airframe_model.gd's header is about — and it would look right for a long time. Rolling with the
## airframe is the deliberate opposite of the chase camera's yaw-only rule (see main.gd): rolling is
## what makes a chase cam unwatchable and it is exactly what an FPV feed does.
func place_lenses(main_camera: Camera3D, chase: Transform3D) -> void:
	if not _chase_lens_captured:
		# First frame, before any swap: whatever the scene camera is wearing IS the chase lens.
		_chase_fov = main_camera.fov
		_chase_near = main_camera.near
		_inset_camera.far = main_camera.far
		_chase_lens_captured = true

	var fpv_lens := main_camera if _fpv_is_main else _inset_camera
	var chase_lens := _inset_camera if _fpv_is_main else main_camera

	chase_lens.global_transform = chase
	_apply_chase_lens(chase_lens)

	if not is_fitted():
		return
	fpv_lens.global_transform = world_transform_of(_eye)
	_apply_fpv_lens(fpv_lens)


## The placeholder lens, applied wherever the FPV view currently lives.
func _apply_fpv_lens(lens: Camera3D) -> void:
	lens.fov = PLACEHOLDER_FOV_DEG
	lens.near = NEAR_M
	lens.keep_aspect = Camera3D.KEEP_WIDTH


## The chase camera's own lens, restored wherever the chase view currently lives.
##
## Restoring is not optional: after one swap the chase view renders through the node that was just
## wearing the 90 deg placeholder, and an unrestored FOV would leave the chase camera silently
## flying a lens that is not its own — a bug that only appears after the second keypress.
##
## The numbers are READ OFF THE SCENE'S CAMERA rather than written here, on the first frame, before
## anything has been swapped. main.tscn is where the chase lens is authored, and a copy of its FOV
## in this file would be a second place to change it — the kind that stays correct right up until
## somebody tunes the chase view and cannot work out why it only takes effect until they press C.
func _apply_chase_lens(lens: Camera3D) -> void:
	lens.fov = _chase_fov
	lens.near = _chase_near
	lens.keep_aspect = Camera3D.KEEP_HEIGHT


## Caption and empty state for the mode currently in force. The caption names BOTH views every time,
## because after a swap the inset is the chase view and an unlabelled small picture of a drone from
## behind is indistinguishable from the feed it replaced.
func _refresh() -> void:
	_empty.visible = not is_fitted()
	if not is_fitted():
		_caption.text = "CHASE — no camera fitted, no FPV"
	elif _fpv_is_main:
		_caption.text = "CHASE (inset) — flying FPV, %d° placeholder, no tilt" % int(PLACEHOLDER_FOV_DEG)
	else:
		_caption.text = "FPV (inset) — %d° placeholder, no tilt" % int(PLACEHOLDER_FOV_DEG)


## What the caption currently reads. A named accessor so tests do not reach into the node tree.
func caption_text() -> String:
	return _caption.text


## A node's placement in the world, chained up through its Node3D ancestors rather than read from
## `global_transform`.
##
## THE SAME ARITHMETIC GODOT DOES, and it is written out for one specific reason: Node3D's
## `global_transform` REQUIRES the node to be inside the tree — outside it, it pushes an error and
## returns the identity, silently. So the built-in version makes this class untestable, because an
## airframe built in a test is never adopted by the tree (nodes cannot enter it from a SceneTree
## script's _init), and an untestable placement is exactly the kind that drifts. Walking the chain
## gives the identical answer in the tree and a correct one outside it.
static func world_transform_of(node: Node3D) -> Transform3D:
	var placement := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		placement = (parent as Node3D).transform * placement
		parent = parent.get_parent()
	return placement


## Where the feed is being taken from, in the airframe's own space — the number a test can compare
## against the drawn camera. Vector3.ZERO when nothing is fitted.
func eye_position_m() -> Vector3:
	if not is_fitted():
		return Vector3.ZERO
	return world_transform_of(_eye).origin
