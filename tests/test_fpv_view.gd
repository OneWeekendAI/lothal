class_name TestFpvView
extends RefCounted
## The feed from the fitted camera in the field: a corner inset by default, the whole screen on C.
##
## THE CLAIMS UNDER TEST ARE THE ONES THAT WOULD BE SILENTLY WRONG. A feed pointed at very nearly
## the right place looks perfectly convincing — you cannot tell a lens seated 8 mm too far forward
## from a correct one by looking at it, and you certainly cannot tell one that has dropped the
## airframe's roll from one that carries it, because the horizon still moves. So the eye is asserted
## to BE the transform of the node on the drawn camera, roll included, rather than to be near it.
##
## The swap is tested for the failure it can actually have: a viewport left with no camera. That is
## why FpvView moves placements between two permanent nodes instead of moving one node between
## viewports, and a test that only checked "the picture changed" would pass against the design that
## has a black frame in it.
##
## What is deliberately NOT asserted here is anything optical. The field of view is a stated
## placeholder shared by every camera in the catalog (FpvView's header says why), so a test
## comparing it against a part would be asserting a spec this project does not publish. What IS
## asserted about it is that the screen says it is a placeholder.

const EPS := 1e-6

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_the_feed_is_taken_from_the_node_on_the_drawn_camera(catalog))
	results.append(_the_feed_carries_the_airframes_roll(catalog))
	results.append(_the_swap_never_leaves_a_viewport_without_a_camera(catalog))
	results.append(_the_swap_restores_the_chase_lens(catalog))
	results.append(_a_rebuild_re_points_the_feed(catalog))
	results.append(_no_camera_fitted_means_no_fpv_rather_than_a_black_screen(catalog))
	results.append(_the_caption_says_the_angle_is_a_placeholder(catalog))

	return results


static func _reference(catalog: PartsCatalog) -> AirframeModel:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	return airframe


## A helper standing in for main.tscn's Camera3D, carrying the lens main.tscn authors.
static func _scene_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.02
	camera.far = 600.0
	return camera


## THE ANTI-DIVERGENCE TEST. The eye is a marker seated by the same MountLayout call the mass model
## uses, so the feed's placement must BE that marker's transform and not a second derivation of it.
##
## Fails the day anybody recomputes an eye position here from the bay and the camera's dimensions —
## which would look right for a long time, and is exactly the drift airframe_model.gd exists to stop.
## Compared against the airframe's own answer rather than against a coordinate written in this file,
## so it also fails if the two ever stop agreeing without either one being "the" wrong number.
static func _the_feed_is_taken_from_the_node_on_the_drawn_camera(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var view := FpvView.new()
	var camera := _scene_camera()
	view.attach(airframe.camera_eye())
	view.toggle_main()
	view.place_lenses(camera, Transform3D.IDENTITY)

	var expected := FpvView.world_transform_of(airframe.camera_eye())
	var offset := camera.transform.origin.distance_to(expected.origin)

	airframe.free()
	view.free()
	camera.free()

	return TestResult.new(
		"the feed is taken from the eye on the drawn camera",
		offset < EPS,
		"lens is %.4f mm from the eye marker" % (offset * 1000.0))


## Rolling with the airframe is the whole difference between this and the chase camera, and it is
## the half a "does it point roughly forward" test would miss: a feed that dropped roll would still
## show the gate ahead, still move with the aircraft, and be wrong in the one way that matters.
##
## The airframe is banked 30 deg and the lens's own axes are checked against the airframe's, rather
## than against world up — the assertion is "it carries the roll", not "it has some roll".
##
## SINCE V2 THE LENS IS TIPPED UP, so its up-vector is no longer the airframe's (it is the camera
## tilt off it, 25 deg on this untweaked build) and the old "lens up == airframe up" would be wrong.
## Roll is about the forward axis and tilt about the right axis, so the two separate cleanly: the
## lens's RIGHT axis must be the banked airframe's right axis, and its FORWARD axis must be the
## airframe's own boresight carried through the bank. A feed that dropped the roll fails the first;
## one that dropped the tilt fails the second.
static func _the_feed_carries_the_airframes_roll(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var drone := Node3D.new()
	drone.add_child(airframe)
	drone.basis = Basis(Vector3(0, 0, -1), deg_to_rad(30.0))

	var view := FpvView.new()
	var camera := _scene_camera()
	view.attach(airframe.camera_eye())
	view.toggle_main()
	view.place_lenses(camera, Transform3D.IDENTITY)

	var lens_right: Vector3 = camera.transform.basis.x
	var lens_forward: Vector3 = -camera.transform.basis.z
	var banked := lens_right.angle_to(Vector3.RIGHT)
	var roll_agreement := lens_right.angle_to(drone.basis.x)
	var forward_agreement := lens_forward.angle_to(drone.basis * airframe.camera_boresight())

	drone.free()
	view.free()
	camera.free()

	return TestResult.new(
		"the feed rolls with the airframe rather than staying level",
		roll_agreement < 1e-4 and forward_agreement < 1e-4 and banked > deg_to_rad(29.0),
		"lens right is %.2f deg off the airframe's and %.2f deg off world right; forward %.4f deg off the banked boresight" % [
			rad_to_deg(roll_agreement), rad_to_deg(banked), rad_to_deg(forward_agreement)])


## The one failure the swap can actually have. Reparenting a camera between viewports, or toggling
## `current` across several, has a state in which a viewport is rendering with no camera at all —
## one black frame, or a whole mode that draws nothing when the ordering is disturbed.
##
## Asserted across a full cycle (inset -> main -> inset), because a swap that is only correct in one
## direction is the ordinary way this breaks.
static func _the_swap_never_leaves_a_viewport_without_a_camera(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var view := FpvView.new()
	var camera := _scene_camera()
	view.attach(airframe.camera_eye())

	var states: Array[bool] = []
	var modes: Array[bool] = []
	for i in 3:
		view.place_lenses(camera, Transform3D.IDENTITY)
		# Both nodes exist and each is the only camera in its own viewport. The design claim is that
		# neither is ever moved or unset, so both must survive every swap.
		states.append(is_instance_valid(camera) and is_instance_valid(view.inset_camera())
			and view.inset_camera().get_parent() is SubViewport)
		modes.append(view.is_fpv_main())
		view.toggle_main()

	var never_empty := not states.has(false)
	# ...and the swap must actually swap, or "never empty" passes on a view that does nothing.
	var alternates := not modes[0] and modes[1] and not modes[2]

	airframe.free()
	view.free()
	camera.free()

	return TestResult.new(
		"every swap leaves both viewports with a camera",
		never_empty and alternates,
		"cameras intact %s across modes %s" % [never_empty, modes])


## After a swap the chase view is rendering through the node that was just wearing the 90 deg
## placeholder. An unrestored FOV would leave the chase camera flying a lens that is not its own —
## a bug that only appears on the SECOND keypress, which is why the cycle is driven twice here.
static func _the_swap_restores_the_chase_lens(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var view := FpvView.new()
	var camera := _scene_camera()
	var authored := camera.fov
	view.attach(airframe.camera_eye())

	view.place_lenses(camera, Transform3D.IDENTITY)   # chase on the scene camera, FPV in the inset
	view.toggle_main()
	view.place_lenses(camera, Transform3D.IDENTITY)   # FPV on the scene camera
	var fpv_fov := camera.fov
	view.toggle_main()
	view.place_lenses(camera, Transform3D.IDENTITY)   # chase back on the scene camera
	var restored := camera.fov

	airframe.free()
	view.free()
	camera.free()

	return TestResult.new(
		"the chase lens comes back after a swap rather than keeping the FPV angle",
		is_equal_approx(fpv_fov, FpvView.PLACEHOLDER_FOV_DEG) and is_equal_approx(restored, authored),
		"authored %.1f deg -> FPV %.1f deg -> restored %.1f deg" % [authored, fpv_fov, restored])


## A rebuild frees the old ComponentMesh, so an eye held across one is a freed node — and reading a
## freed node's transform is a crash in the middle of a flight, not a wrong picture.
##
## Swapping to a frame whose camera bay sits somewhere else is what makes this test able to fail for
## the right reason: a stale-but-valid eye would give the old position, and the position is checked.
static func _a_rebuild_re_points_the_feed(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var view := FpvView.new()
	view.attach(airframe.camera_eye())
	var before := view.eye_position_m()

	airframe.rebuild(Build.from_ids(catalog, "frame_10in_long_range", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	view.attach(airframe.camera_eye())
	var after := view.eye_position_m()

	var moved := before.distance_to(after)
	var live := view.is_fitted()

	airframe.free()
	view.free()

	return TestResult.new(
		"a rebuild re-points the feed at the new camera rather than a freed one",
		live and moved > 1e-4,
		"eye moved %.2f mm across the rebuild, still live: %s" % [moved * 1000.0, live])


## An AIO whoop carries no separate camera, and that is a real build rather than an error state.
## FPV must be unavailable rather than main-and-black: a full screen rendering from a lens that does
## not exist reads as a crash, and it is the state a naive toggle would happily enter.
static func _no_camera_fitted_means_no_fpv_rather_than_a_black_screen(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_25x25x4", "battery_1s_550", Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID,
		Build.no_components()))
	var view := FpvView.new()
	view.attach(airframe.camera_eye())

	var refused := not view.toggle_main() and not view.is_fpv_main() and not view.is_fitted()
	var caption := view.caption_text()

	airframe.free()
	view.free()

	return TestResult.new(
		"a build with no camera refuses FPV and says why",
		refused and caption.contains("no camera fitted"),
		"toggle refused: %s; caption: %s" % [refused, caption])


## The angle is a framing choice this project made, not a spec it read off the part, and moving the
## feed from the bench into the air is what makes saying so non-negotiable — a number you fly off is
## read harder than one you glance at. Asserted in BOTH modes, because the mode that gets flown is
## the one whose caption would be quietly dropped as clutter.
static func _the_caption_says_the_angle_is_a_placeholder(catalog: PartsCatalog) -> TestResult:
	var airframe := _reference(catalog)
	var view := FpvView.new()
	view.attach(airframe.camera_eye())

	var inset := view.caption_text()
	view.toggle_main()
	var full := view.caption_text()

	airframe.free()
	view.free()

	return TestResult.new(
		"both modes say the angle is a placeholder and there is no tilt",
		inset.contains("placeholder") and inset.contains("no tilt")
			and full.contains("placeholder") and full.contains("no tilt"),
		"inset: %s | full: %s" % [inset, full])
