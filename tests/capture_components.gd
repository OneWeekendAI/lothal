extends SceneTree
## Dev tool, not a test: renders an AirframeModel on its own and writes a PNG of it, so the four
## component silhouettes can be looked at without going through Lab.
##
##   godot --script res://tests/capture_components.gd -- <out.png> [frame_id] [azimuth_deg] [elevation_deg] [distance_scale]
##   godot --script res://tests/capture_components.gd -- <out.png> [frame_id] eye
##
## Passing "eye" as the third argument shoots THROUGH the fitted camera's own lens, at FpvView's
## placeholder FOV — the same lens Sim's feed uses, without the field around it.
##
## Deliberately NOT booting main.tscn, unlike capture_lab.gd and capture_frame.gd. Those two are the
## right tools for looking at the SCREEN and boot the whole app to get there, which
## is correct for them and useless here — this one has one job, which is to look at generated
## geometry, and it builds the same AirframeModel Lab and Sim both build.
##
## It frames the CURRENT build rather than the largest in the catalog, which is exactly the framing
## decision Lab does not make (lab_screen.gd holds a fixed distance so a whoop looks tiny beside a
## 10", on purpose). That is why this is a dev tool and not a feature: it is the "inspect" view
## argued for separately, with none of the decisions that view would have to make.
##
## Must NOT be run with --headless: it captures Godot's own framebuffer, and the dummy rendering
## driver does not have one — it will sit there and never write a PNG.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://components.png"
	var frame_id: String = args[1] if args.size() > 1 else "frame_5in_freestyle"
	var azimuth: float = float(args[2]) if args.size() > 2 else 35.0
	var elevation: float = float(args[3]) if args.size() > 3 else 22.0
	var distance_scale: float = float(args[4]) if args.size() > 4 else 1.0

	var catalog := PartsCatalog.load_default()
	var build := Build.from_ids(catalog, frame_id, "motor_2207_1960kv", "prop_5x43x3",
		"battery_4s_1500")

	var world := Node3D.new()
	root.add_child(world)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.6
	environment.environment = env
	world.add_child(environment)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	world.add_child(key)
	key.rotation_degrees = Vector3(-45.0, 35.0, 0.0)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	world.add_child(fill)
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)

	var airframe := AirframeModel.new()
	world.add_child(airframe)
	airframe.rebuild(build)

	var through_the_lens: bool = args.size() > 2 and args[2] == "eye"

	var camera := Camera3D.new()
	camera.near = 0.001
	world.add_child(camera)

	if through_the_lens:
		camera.fov = FpvView.PLACEHOLDER_FOV_DEG
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.near = FpvView.NEAR_M
		camera.make_current()
		var eye := airframe.camera_eye()
		if eye == null:
			print("no camera fitted on %s — nothing to look through" % frame_id)
			quit(1)
			return
		for i in 8:
			await process_frame
		camera.global_transform = FpvView.world_transform_of(eye)
		for i in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var lens_image := root.get_texture().get_image()
		lens_image.save_png(out_path)
		print("wrote %s (%dx%d) — through the lens on %s" % [
			out_path, lens_image.get_width(), lens_image.get_height(), frame_id])
		quit()
		return
	# Framed off the build on screen — arm length is the aircraft's own scale, so the same numbers
	# frame a 65 mm whoop and a 10" long-range without a second table.
	var distance: float = build.arm_m * 4.2 * distance_scale
	var pitch := deg_to_rad(elevation)
	var yaw := deg_to_rad(azimuth)
	camera.position = Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw))
	camera.make_current()

	# Aimed AFTER the first frame, not here. A node added from a SceneTree script's _init is not
	# actually inside the tree yet, and look_at on a node outside the tree silently does nothing —
	# it leaves the identity basis, so the camera looks down its own -Z and produces a frame with
	# the aircraft in a corner that reads as a framing bug rather than as an un-aimed camera.
	for i in 8:
		await process_frame
	camera.look_at(Vector3.ZERO, Vector3.UP)
	for i in 2:
		await process_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d) — %s" % [out_path, image.get_width(), image.get_height(), frame_id])
	quit()
